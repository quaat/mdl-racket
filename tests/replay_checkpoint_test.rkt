#lang racket/base
;; ADR-0061 / SEMANTICS "M4 WP4": the canonical checkpoint encoding and its
;; strict parser, checkpoint validation and tampering, and record/restore of a
;; small MDL program that reads the clock, draws RANDOM and reseeds it
;; explicitly (WP4.6 "explicit RANDOM reseed"; reordered clock observations).
;; Smoke suite: needs no upstream source.
(require rackunit racket/file racket/list racket/string file/sha1
         "../mdl/loader.rkt" "../mdl/replay.rkt" "../mdl/runtime/clock.rkt"
         (only-in "../mdl/runtime/random36.rkt" random36-next! random36-state-draws))

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler
 (lambda (e)
   (when (exn:test:check? e)
     (for ([i (in-list (exn:test:check-stack e))])
       (eprintf "  ~a: ~e\n" (check-info-name i) (check-info-value i))))
   (raise e)))

;; --- canonical JSON ------------------------------------------------------------------
(define sample (hasheq 'b (list 1 -2 0 "x\"y\\z\n\u001b\u007f") 'a (hasheq) 'c #t 'd 'null 'e #f))
(define sample-bytes (canonical-json-bytes sample))
(check-equal? sample-bytes
              #"{\"a\":{},\"b\":[1,-2,0,\"x\\\"y\\\\z\\u000a\\u001b\\u007f\"],\"c\":true,\"d\":null,\"e\":false}")
(check-equal? (canonical-json-parse sample-bytes) sample)
(check-exn #rx"non-ASCII" (lambda () (canonical-json-bytes "caf\u00e9")))
(check-exn #rx"unsupported value" (lambda () (canonical-json-bytes 1.5)))
(for ([bad (list #"{\"a\": 1}" #"{\"b\":1,\"a\":2}" #"{\"a\":1,\"a\":2}" #"[1.0]" #"[1e3]"
                 #"[01]" #"[-0]" #"[12345678901234567890]" #"\"\\n\"" #"\"\\u0041\""
                 #"\"\\u00e9\"" #"\"\t\"" #"[1] " #"[1,]" #"{}x" #"tru" #"\"\xc3\xa9\""
                 #"[[[[[[[[[1]]]]]]]]]")])
  (check-exn #rx"canonical-json" (lambda () (canonical-json-parse bad)) (format "~s" bad)))
(check-equal? (canonical-json-parse #"[[[[[[[[1]]]]]]]]") '(((((((( 1)))))))))

;; --- a small MDL program on the replay engine ----------------------------------------
;; BOOT seeds RANDOM from two clock reads; each REP pass (STEP) reads one line:
;; r -> PRIN1 <RANDOM>; s -> explicit reseed <RANDOM 12345 67890>; t -> two
;; clock reads; q -> QUIT; anything else -> "?". N counts lines. The first
;; end of input RESETs the channel (like YES/NO), the second QUITs.
(define root (make-temporary-file "mdl-replay-ck~a" 'directory))
(define program #<<MDL
<SETG BUF <ISTRING 40>>
<SETG N 0>
<SETG E <>>
<DEFINE BOOT ("AUX" (A <GETTIMEDATE>) (B <GETTIMEDATE>))
  <RANDOM <+ <* <1 .A> 1000000> <7 .B>>>
  <PRINC "booted">
  <CRLF>
  T>
<DEFINE STEP ("AUX" L)
  <PRINC "> ">
  <SET L <READSTRING ,BUF ,INCHAN <STRING <ASCII 10>>>>
  <SETG N <+ ,N 1>>
  <COND (<0? .L> <PRINC "empty"> <COND (,E <QUIT>)> <SETG E T> <RESET ,INCHAN>)
        (<==? <1 ,BUF> !\r> <PRIN1 <RANDOM>>)
        (<==? <1 ,BUF> !\s> <PRIN1 <RANDOM 12345 67890>>)
        (<==? <1 ,BUF> !\t> <PRIN1 <7 <GETTIMEDATE>>> <PRINC " "> <PRIN1 <7 <GETTIMEDATE>>>)
        (<==? <1 ,BUF> !\q> <QUIT>)
        (T <PRINC "?">)>
  <CRLF>>
<SETG REP ,STEP>
MDL
  )
(call-with-output-file (build-path root "prog.mud") (lambda (o) (void (write-string program o))))

(define profile
  (replay-profile "test-readstring/v1" "prog.mud" "BOOT" '("prog.mud") (lambda () (hasheq 'test "none"))
                  (lambda (s info)
                    (and (not (eq? (hash-ref info 'buffer) (mdl-session-global s "BUF")))
                         "not the STEP reader"))
                  (lambda (s) (hasheq 'n (number->string (mdl-session-global s "N"))))
                  (lambda (s) (mdl-session-global s "N"))
                  (lambda (obs tz) (hasheq 'source "BOOT <RANDOM> from two clock reads"))))

;; A deterministic source advancing 0.37 s per read.
(define (stepping-clock start step-micros)
  (define n 0)
  (make-mdl-clock (lambda ()
                    (define total (+ (* start 1000000) (* n step-micros)))
                    (set! n (add1 n))
                    (values (quotient total 1000000) (remainder total 1000000)))))
(define (lines l) (apply string-append (map (lambda (c) (string-append c "\n")) l)))
;; The clock is read only before the save point here: after a restore the
;; resumed clock (not the recording source) serves reads, which the
;; wall-clock checks below cover separately.
(define commands '("r" "t" "r" "s" "r" "x" "r" "r" "s" "r" "r" "x"))
(define save-turn 5) ; after "r t r s r": the reseed is in the past, another follows

;; Uninterrupted run, recording; checkpoints at every turn.
(define checkpoints (make-hash))
(define rng-at (make-hash))
(define full-out (open-output-string))
(define full
  (replay-record profile #:source-root root #:input (open-input-string (lines commands))
                 #:output full-out #:clock (stepping-clock 1000000000 370000) #:time-zone 'utc
                 #:boot-clock "stepping"
                 #:on-prompt (lambda (p)
                               (hash-set! rng-at (replay-prompt-turn p)
                                          (mdl-session-random-snapshot (replay-prompt-session p)))
                               (unless (replay-prompt-refusal p)
                                 (hash-set! checkpoints (replay-prompt-turn p)
                                            (replay-prompt-checkpoint p))))))
(check-equal? (replay-result-kind full) 'quit)
(check-equal? (replay-result-host-errors full) '())
(check-equal? (sort (hash-keys checkpoints) <) (range 13)) ; turn 13 follows the consumed end of input
(define full-text (get-output-string full-out))
(check-equal? (length (regexp-match* #rx"> " full-text)) 14)
(define cp (hash-ref checkpoints save-turn))
(define doc (canonical-json-parse cp))
(check-equal? (hash-ref doc 'format) "mdl-zork-replay/v1")
(check-equal? (hash-ref (hash-ref doc 'rng) 'version) "rng/v1")
(check-equal? (hash-ref (hash-ref doc 'rng) 'draws) 5)        ; BOOT + r + r + s + r
(check-equal? (length (hash-ref doc 'observations)) 4)         ; BOOT 2 + t 2
(check-equal? (map caddr (hash-ref doc 'observations)) '(0 0 2 2))
(check-equal? (hash-ref doc 'input) '(("r\n" "stop") ("t\n" "stop") ("r\n" "stop") ("s\n" "stop")
                                      ("r\n" "stop")))
;; The saved transcript is exactly the output up to the save prompt.
(define pre (hash-ref (hash-ref doc 'verification) 'transcript_bytes))
(define (sha256-hex bs) (bytes->hex-string (sha256-bytes (open-input-bytes bs))))
(check-equal? (sha256-hex (subbytes (string->bytes/latin-1 full-text) 0 pre))
              (hash-ref (hash-ref doc 'verification) 'transcript_sha256))

;; Restore and continue with the same remaining inputs: identical output and
;; RANDOM state, including the explicit reseed after the restore.
(define (restore bs #:wall [wall (make-fixed-mdl-clock 2000000000)] #:rest [rest (drop commands save-turn)]
                 #:on-restored [on-restored void])
  (define out (open-output-string))
  (define result (replay-restore profile bs #:source-root root #:input (open-input-string (lines rest))
                                 #:output out #:wall-clock wall #:on-restored on-restored))
  (check-equal? (replay-result-host-errors result) '())
  (values result (get-output-string out)))
(define restored-rng #f)
(define-values (r1 out1)
  (restore cp #:on-restored (lambda (s) (set! restored-rng (mdl-session-random-snapshot s)))))
(check-equal? (replay-result-kind r1) 'quit)
;; no duplicate output: the live port sees only what follows the save prompt
(check-equal? (string-append (substring full-text 0 pre) out1) full-text)
(check-equal? (random36-state-words restored-rng) (random36-state-words (hash-ref rng-at save-turn)))
(check-equal? (random36-state-draws restored-rng) 5)
;; continuity: the next draws (on detached copies) are equal
(define (next-draws snap k) (for/list ([_ k]) (random36-next! snap)))
(check-equal? (next-draws restored-rng 8) (next-draws (hash-ref rng-at save-turn) 8))
(check-equal? (random36-state-words (mdl-session-random-snapshot (replay-result-session r1)))
              (random36-state-words (mdl-session-random-snapshot (replay-result-session full))))
;; restoring the same checkpoint twice gives identical results
(define-values (r2 out2) (restore cp))
(check-equal? out2 out1)
(check-false (eq? (replay-result-session r1) (replay-result-session r2)))

;; Resumed clock: the post-restore `t` reads continue from the last
;; observation plus elapsed wall time, whatever the absolute wall clock.
(define-values (rw1 outw1) (restore cp #:wall (stepping-clock 1700000000 1000000) #:rest '("t")))
(define-values (rw2 outw2) (restore cp #:wall (stepping-clock 2100000000 1000000) #:rest '("t")))
(check-equal? outw1 outw2)
;; (the save prompt "> " belongs to the saved transcript)
(check-regexp-match #rx"^110000 110000\n" outw1) ; base 1000000001.110000; +1 s per wall read

;; A restored session can be saved again and that checkpoint restores too.
(define resaved #f)
(define-values (rr outr)
  (let ([out (open-output-string)])
    (values (replay-restore profile cp #:source-root root
                            #:input (open-input-string (lines '("x" "t" "r" "r" "s" "r")))
                            #:output out #:wall-clock (make-fixed-mdl-clock 2000000000)
                            #:on-prompt (lambda (p) (when (= (replay-prompt-turn p) 9)
                                                      (set! resaved (replay-prompt-checkpoint p)))))
            (get-output-string out))))
(check-true (bytes? resaved))
(define-values (rr2 outr2) (restore resaved #:rest '("s" "r")))
;; the resaved game ran on the resumed clock after turn 5 (its `t` output
;; differs from the uninterrupted run), so compare with that restored run
(define rr-transcript (string-append (substring full-text 0 pre) outr))
(define resaved-pre (hash-ref (hash-ref (canonical-json-parse resaved) 'verification) 'transcript_bytes))
(check-equal? (string-append (substring rr-transcript 0 resaved-pre) outr2) rr-transcript)
(check-equal? (length (hash-ref (canonical-json-parse resaved) 'observations)) 6)

;; --- rejection before any session is created ------------------------------------------
(define (stage-of thunk)
  (with-handlers ([exn:fail:replay-restore? exn:fail:replay-restore-stage]) (thunk) 'accepted))
(define (reject bs) (stage-of (lambda () (restore bs))))
(define (tamper f) (checkpoint-reseal (f doc)))
(define (hset* h path v)
  (if (null? (cdr path)) (hash-set h (car path) v)
      (hash-set h (car path) (hset* (hash-ref h (car path)) (cdr path) v))))
(define before (replay-sessions-created))
(check-equal? (reject (bytes-append cp #" ")) 'format)
(check-equal? (reject (make-bytes (add1 (hash-ref replay-limits 'bytes)) 32)) 'format)
(check-equal? (reject (tamper (lambda (d) (hash-set d 'format "mdl-zork-replay/v2")))) 'format)
(check-equal? (reject (tamper (lambda (d) (hset* d '(rng version) "rng/v2")))) 'format)
(check-equal? (reject (tamper (lambda (d) (hset* d '(rng algorithm) "other/v1")))) 'format)
;; one modified byte inside a string keeps the encoding canonical: checksum
(define flipped (bytes-copy cp))
(bytes-set! flipped (car (car (regexp-match-positions #rx"two clock" cp))) (char->integer #\X))
(check-equal? (reject flipped) 'checksum)
(check-equal? (reject (canonical-json-bytes (hash-set doc 'checksum (make-string 64 #\0)))) 'checksum)
(check-equal? (reject (tamper (lambda (d) (hash-set d 'extra "x")))) 'schema)
(check-equal? (reject (tamper (lambda (d) (hset* d '(observations) '((1 2000000 0)))))) 'schema)
(check-equal? (reject (tamper (lambda (d) (hash-set d 'profile "other/v1")))) 'profile)
(check-equal? (reject (tamper (lambda (d) (hset* d '(source upstream) (hasheq 'test "other"))))) 'provenance)
(check-equal? (reject (tamper (lambda (d) (hset* d '(source manifest_sha256) (make-string 64 #\a)))))
              'provenance)
;; a different game source on disk
(define root2 (make-temporary-file "mdl-replay-ck2~a" 'directory))
(call-with-output-file (build-path root2 "prog.mud")
  (lambda (o) (void (write-string (string-append program "\n;\"changed\"\n") o))))
(check-equal? (stage-of (lambda () (replay-restore profile cp #:source-root root2
                                                   #:input (open-input-string "") #:output (open-output-string))))
              'provenance)
(delete-directory/files root2)
(check-equal? (replay-sessions-created) before "a rejected checkpoint created a session")

;; --- failures during replay or at verification ----------------------------------------
(define obs (hash-ref doc 'observations))
;; reordered observations at turn 0: BOOT's seed differs, but the explicit
;; reseed at turn 3 makes the RNG words equal again by the save point, so the
;; transcript digest (the earlier RANDOM values) is what fails -> verification
(check-equal? (reject (tamper (lambda (d) (hash-set d 'observations
                                                    (list* (cadr obs) (car obs) (cddr obs))))))
              'verification)
;; an observation moved to another turn: strict clock order divergence
(check-equal? (reject (tamper (lambda (d) (hash-set d 'observations
                                                    (list* (car obs) (list-set (cadr obs) 2 1) (cddr obs))))))
              'replay)
;; a missing observation: an extra clock read during replay
(check-equal? (reject (tamper (lambda (d) (hset* (hash-set d 'observations (drop-right obs 1))
                                                 '(verification observations) 3))))
              'replay)
;; an extra observation: left unread at the end of replay
(check-equal? (reject (tamper (lambda (d) (hset* (hash-set d 'observations (append obs (list (last obs))))
                                                 '(verification observations) 5))))
              'replay)
;; modified RNG words or draw count -> verification
(check-equal? (reject (tamper (lambda (d) (hset* d '(rng state)
                                                 (list (car (hash-ref (hash-ref d 'rng) 'state)) 1)))))
              'verification)
(check-equal? (reject (tamper (lambda (d) (hset* d '(rng draws) 6)))) 'verification)
(check-equal? (reject (tamper (lambda (d) (hset* d '(verification moves) 6)))) 'verification)
(check-equal? (reject (tamper (lambda (d) (hset* d '(verification transcript_bytes) 1)))) 'verification)
;; a modified input unit: the replayed session diverges or the state differs
(check-equal? (reject (tamper (lambda (d) (hash-set d 'input (list-set (hash-ref d 'input) 2 '("x\n" "stop"))))))
              'verification)
;; a last input unit without its stop character: the replayed READSTRING
;; reads past the recorded input (never from the live port) -> replay
(define overrun
  (tamper (lambda (d) (hash-set d 'input (list-set (hash-ref d 'input) 4 '("r" "stop"))))))
(define overrun-live (open-input-string "live\n"))
(check-exn (lambda (e) (and (exn:fail:replay-restore? e)
                            (eq? (exn:fail:replay-restore-stage e) 'replay)
                            (regexp-match? #rx"read past the 9 recorded input bytes" (exn-message e))))
           (lambda () (replay-restore profile overrun #:source-root root #:input overrun-live
                                      #:output (open-output-string))))
(check-equal? (read-line overrun-live) "live" "the live input was not touched by the failed replay")
;; review L1: each verification field alone is checked
(check-equal? (reject (tamper (lambda (d) (hset* d '(verification transcript_sha256) (make-string 64 #\0)))))
              'verification)
(check-equal? (reject (tamper (lambda (d) (hset* d '(verification state) (hasheq 'n "99")))))
              'verification)
(check-equal? (reject (tamper (lambda (d) (hset* d '(verification state_sha256) (make-string 64 #\0)))))
              'verification)
;; review M3: wrong-typed fields are schema rejections (never a contract error)
(define sessions-before-m3 (replay-sessions-created))
(for ([path+value (list (list '(verification input_units) "x") (list '(verification observations) "x")
                        (list '(verification moves) "x") (list '(verification transcript_bytes) "x")
                        (list '(verification state) "x") (list '(verification state_sha256) 5)
                        (list '(verification) "x") (list '(rng draws) "x") (list '(rng state) '("a" 1))
                        (list '(rng seed) "x") (list '(source files) "x") (list '(source files) '(("prog.mud")))
                        (list '(source upstream) '()) (list '(input) "x") (list '(input) '(("r\n")))
                        (list '(observations) "x") (list '(observations) '((1 2))) (list '(clock) "x")
                        (list '(runtime) "x") (list '(profile) 7))])
  (check-equal? (reject (tamper (lambda (d) (hset* d (car path+value) (cadr path+value))))) 'schema
                (format "~s" path+value)))
(check-equal? (replay-sessions-created) sessions-before-m3)
;; review M2: source.files is bounded, duplicate-free and must be exactly the
;; profile's game files; nothing is read from disk before that is settled
(define (with-files files)
  (tamper (lambda (d) (hset* (hset* d '(source files) files) '(source manifest_sha256)
                             (sha256-hex (canonical-json-bytes files))))))
(define prog-entry (car (hash-ref (hash-ref doc 'source) 'files)))
(check-equal? (reject (with-files (list prog-entry prog-entry))) 'schema)
(check-equal? (reject (with-files (make-list 40000 prog-entry))) 'schema)
(check-equal? (reject (with-files (for/list ([i 65]) (list (format "f~a.mud" i) (cadr prog-entry))))) 'schema)
(let ([e (with-handlers ([exn:fail:replay-restore? values])
           (replay-validate-checkpoint profile (with-files (list (list "missing.mud" (cadr prog-entry))))
                                       #:source-root root))])
  (check-equal? (exn:fail:replay-restore-stage e) 'provenance)
  (check-regexp-match #rx"not the profile's game files" (exn-message e)))
(check-equal? (replay-sessions-created) sessions-before-m3)
;; the runtime block is diagnostic only
(check-equal? (reject (tamper (lambda (d) (hset* d '(runtime commit) "0000000")))) 'accepted)
(check-equal? (reject (tamper (lambda (d) (hset* d '(runtime racket) "Racket 99 (cs)")))) 'accepted)

;; --- save refusals ----------------------------------------------------------------------
;; a full buffer leaves pending input; after end of input was consumed (and
;; the channel RESET) there is no prompt to resume at
(define refusals '())
(define refusals-run (replay-record profile #:source-root root
                     #:input (open-input-string (string-append "r\n" (make-string 45 #\x) "\nr\n"))
                     #:output (open-output-string) #:clock (make-fixed-mdl-clock 5) #:time-zone 'utc
                     #:on-prompt (lambda (p)
                                   (set! refusals (cons (list (replay-prompt-turn p) (replay-prompt-refusal p))
                                                        refusals))
                                   (when (replay-prompt-refusal p)
                                     (check-exn exn:fail:replay-save-refused?
                                                (lambda () (replay-prompt-checkpoint p)))))))
(check-equal? (replay-result-host-errors refusals-run) '())
(check-equal? (map car (reverse refusals)) '(0 1 2 3 4 5))
(check-false (cadr (assv 1 refusals)))
(check-regexp-match #rx"filled its buffer" (cadr (assv 2 refusals)))
(check-false (cadr (assv 3 refusals)))
(check-false (cadr (assv 4 refusals)))
(check-regexp-match #rx"end of input" (cadr (assv 5 refusals)))
;; review L2: a host callback that fails (here: a refused save) does not end
;; the live game; the failure is reported in the result. A non-raising
;; variant returns the refusal.
(define tried '())
(define survived
  (replay-record profile #:source-root root
                 #:input (open-input-string (string-append "r\n" (make-string 45 #\x) "\nr\nr\n"))
                 #:output (open-output-string) #:clock (make-fixed-mdl-clock 5) #:time-zone 'utc
                 #:on-prompt (lambda (p)
                               (set! tried (cons (replay-prompt-try-checkpoint p) tried))
                               (when (= (replay-prompt-turn p) 2) (replay-prompt-checkpoint p)))))
(check-equal? (replay-result-kind survived) 'quit)
(check-equal? (length (replay-result-host-errors survived)) 1)
(check-true (exn:fail:replay-save-refused? (car (replay-result-host-errors survived))))
(check-equal? (mdl-session-global (replay-result-session survived) "N") 7)
(check-equal? (map (lambda (v) (if (bytes? v) 'checkpoint v)) (take (reverse tried) 4))
              (list 'checkpoint 'checkpoint
                    "the previous READSTRING filled its buffer; the rest of that line is pending input"
                    'checkpoint))
;; review M1: validating a crafted checkpoint near the size limit is linear
;; (100 000 input units, 300 000 observations): well under the watchdog
(define big
  (tamper (lambda (d)
            (define input (make-list 100000 '("" "stop")))
            (define observations (make-list 300000 '(0 0 0)))
            (hset* (hset* (hash-set (hash-set d 'input input) 'observations observations)
                          '(verification input_units) 100000)
                   '(verification observations) 300000))))
(check-true (< (* 3/4 (hash-ref replay-limits 'bytes)) (bytes-length big) (hash-ref replay-limits 'bytes)))
(define big-done (make-channel))
(define big-thread (thread (lambda () (channel-put big-done
                                                   (replay-validate-checkpoint profile big #:source-root root)))))
(define big-doc (sync/timeout 30 big-done))
(kill-thread big-thread)
(check-true (hash? big-doc) "validating a 100k-unit/300k-observation checkpoint took over 30 s")
;; a prompt object is valid only during its callback
(define kept #f)
(void (replay-record profile #:source-root root #:input (open-input-string "r\n")
                     #:output (open-output-string) #:clock (make-fixed-mdl-clock 5) #:time-zone 'utc
                     #:on-prompt (lambda (p) (set! kept p))))
(check-regexp-match #rx"no longer current" (replay-prompt-refusal kept))

(delete-directory/files root)
(printf "replay checkpoint format, validation and reseed replay: ok\n")
