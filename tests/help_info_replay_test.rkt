#lang racket/base
;; M4 S10 (issue #171; ADR-0055 amendment, ADR-0061): deterministic replay
;; across `help`, `info` and `?`. A file READSTRING is not input: it never
;; calls the host-only READSTRING observer, so the replay host neither logs the
;; file text as input nor sees a prompt for it; replay re-reads the two
;; pinned, hash-checked files. On the help-info scenario
;; (tests/scenarios/help-info.json), recorded on a recording clock over the
;; fixed source 250776000 UTC:
;;   1. the recorded run equals the native T1 transcript (D1 only) and the save
;;      boundary is offered at exactly the n + 1 RDCOM prompts (k = 0..n), never
;;      inside FILE-TO-TTY's 102 file reads;
;;   2. a checkpoint after `help` (turn 2) and one after `?` (turn 6) hold as
;;      input exactly the commands typed so far, nothing of the files;
;;   3. each restores in a fresh session, verifies (state, RNG, transcript
;;      digests), and pre-save + post-restore output equals native T1; the
;;      restored session re-read and closed the files;
;;   4. a game directory whose MADADV.HELP differs (same size) makes the
;;      restore of the turn-2 checkpoint fail strictly (the sha256 check),
;;      never a silent fallback.
;; Every run is guarded (no file write or delete, empty temporary cwd) and
;; watchdogged.
;;
;; Requires the pinned upstream source. Run with:
;;   racket tests/help_info_replay_test.rkt   (exit status is authoritative)
(require rackunit racket/runtime-path racket/string racket/list racket/file json
         "../mdl/loader.rkt" "../mdl/replay.rkt" "../mdl/runtime/clock.rkt"
         "../zork/persistence.rkt")

(current-check-handler (lambda (e) (raise e)))

(define-runtime-path tests-dir ".")
(define epoch 250776000)
(define (lines l) (apply string-append (map (lambda (c) (string-append c "\n")) l)))
(define commands
  (hash-ref (call-with-input-file (build-path tests-dir "scenarios" "help-info.json") read-json)
            'commands))
(check-equal? commands '("north" "help" "east" "info" "open window" "?" "west" "score"))
(define native-t1
  (let* ([reference (call-with-input-file
                     (build-path tests-dir 'up "docs" "evidence" "M4" "help-info-reference.json")
                     read-json)]
         [c (findf (lambda (c) (equal? (hash-ref c 'name) "T1-help-info-pipe"))
                   (hash-ref reference 'cases))]
         [raw (hash-ref c 'stdout_raw)]
         [banner "LISTENING-AT-LEVEL 1 PROCESS 1\n"]
         [after (cadr (regexp-match (regexp (string-append "^.*?" (regexp-quote banner) "(.*)$")) raw))])
    (string-replace after "\"DONE\"\n" "" #:all? #f)))

;; --- guarded runs --------------------------------------------------------------------
(define original-guard (current-security-guard))
(define (guarded thunk #:limit [limit 300])
  (define cwd (make-temporary-file "m4-s10-replay-cwd-~a" 'directory))
  (define writes '())
  (define guard
    (make-security-guard
     original-guard
     (lambda (who path modes)
       (when (and path (or (memq 'write modes) (memq 'delete modes)))
         (set! writes (cons (list who path modes) writes))))
     (lambda (who host port mode) (void))))
  (define done (make-channel))
  (define worker
    (parameterize ([current-security-guard guard] [current-directory cwd])
      (thread (lambda ()
                (channel-put done (with-handlers ([(lambda (v) #t) (lambda (v) (list 'raised v))])
                                    (list 'ok (thunk))))))))
  (define outcome (or (sync/timeout limit done) (begin (kill-thread worker) (list 'raised 'timed-out))))
  (check-equal? (parameterize ([current-security-guard original-guard]) (directory-list cwd)) '())
  (delete-directory/files cwd)
  (check-equal? writes '())
  (when (and (eq? (car outcome) 'ok) (replay-result? (cadr outcome)))
    (check-equal? (replay-result-host-errors (cadr outcome)) '() "host callback errors"))
  (if (eq? (car outcome) 'ok) (cadr outcome) (raise (cadr outcome))))

(define fixed-source (make-fixed-mdl-clock epoch))
(define wall (make-fixed-mdl-clock 1900000000))
(define (doc cp) (canonical-json-parse cp))
(define (transcript-bytes cp) (hash-ref (hash-ref (doc cp) 'verification) 'transcript_bytes))

;; === 1. record: native T1, prompts only at RDCOM =====================================
(define prompts '())
(define cps (make-hash))
(define out (open-output-string))
(define rec
  (guarded (lambda ()
             (zork-record #:input (open-input-string (lines commands)) #:output out
                          #:clock fixed-source #:time-zone 'utc #:boot-clock "fixed:250776000"
                          #:on-prompt
                          (lambda (p)
                            (define k (replay-prompt-turn p))
                            (set! prompts (cons k prompts))
                            (when (memv k '(2 6))
                              (hash-set! cps k (replay-prompt-checkpoint p))))))))
(check-equal? (replay-result-kind rec) 'input-exhausted)
(check-equal? (get-output-string out) native-t1 "recorded run = native T1")
(check-equal? (reverse prompts) '(0 1 2 3 4 5 6 7 8))
(check-equal? (mdl-session-file-channels (replay-result-session rec))
              '(("MDL/MADADV.HELP" closed) ("MDL/MADADV.INFO" closed) ("MDL/MADADV.HELP" closed)))
(printf "1. recorded help-info = native T1; save boundary at the 9 RDCOM prompts only\n")

;; === 2. the checkpoints' input is the commands only ==================================
(define cp2 (hash-ref cps 2))
(define cp6 (hash-ref cps 6))
(check-equal? (map car (hash-ref (doc cp2) 'input)) '("north\n" "help\n"))
(check-equal? (hash-ref (hash-ref (doc cp2) 'verification) 'input_units) 2)
(check-equal? (map car (hash-ref (doc cp6) 'input)) (map (lambda (c) (string-append c "\n")) (take commands 6)))
(check-equal? (hash-ref (hash-ref (doc cp6) 'verification) 'input_units) 6)
(check-false (for/or ([u (in-list (hash-ref (doc cp6) 'input))]) (string-contains? (car u) "Useful")))
(printf "2. checkpoints after help (2) and ? (6) log only the typed commands\n")

;; === 3. restore exactly ==============================================================
(define (restore cp rest)
  (define o (open-output-string))
  (define restored-state (box #f))
  (define restored-files (box #f))
  (define result
    (guarded (lambda ()
               (zork-restore cp #:input (open-input-string (lines rest)) #:output o
                             #:wall-clock wall
                             #:on-restored (lambda (s)
                                             (set-box! restored-state (zork-replay-state s))
                                             (set-box! restored-files (mdl-session-file-channels s)))))))
  (check-equal? (replay-result-kind result) 'input-exhausted)
  (values (unbox restored-state) (unbox restored-files) (get-output-string o)))
(for ([k '(2 6)])
  (define cp (hash-ref cps k))
  (define-values (state files post) (restore cp (drop commands k)))
  (check-equal? state (hash-ref (hash-ref (doc cp) 'verification) 'state) (format "state at ~a" k))
  (check-equal? files (if (= k 2)
                          '(("MDL/MADADV.HELP" closed))
                          '(("MDL/MADADV.HELP" closed) ("MDL/MADADV.INFO" closed) ("MDL/MADADV.HELP" closed))))
  (check-equal? (string-append (substring (get-output-string out) 0 (transcript-bytes cp)) post)
                native-t1 (format "pre-save + post-restore = native T1 (turn ~a)" k))
  (printf "3. checkpoint at turn ~a restores exactly; pre + post = native T1\n" k))

;; === 4. a changed HELP file fails the restore strictly ===============================
(define copy (make-temporary-file "m4-s10-game-copy-~a" 'directory))
(define game (build-path copy "game"))
(copy-directory/files zork-default-source-root game)
(define help-path (build-path game "MDL" "MADADV.HELP"))
(define help-bytes (file->bytes help-path))
(call-with-output-file help-path #:exists 'truncate
  (lambda (o) (void (write-bytes (bytes-append (subbytes help-bytes 0 10) #"X"
                                               (subbytes help-bytes 11)) o))))
(define tampered
  (with-handlers ([exn:fail? values])
    (guarded (lambda () (zork-restore cp2 #:source-root game #:input (open-input-string "")
                                      #:output (open-output-string) #:wall-clock wall)))
    #f))
(check-pred exn:fail? tampered)
(check-regexp-match #rx"sha256" (exn-message tampered))
(delete-directory/files copy)
(printf "4. restore over a changed MADADV.HELP fails strictly: ~a\n" (exn-message tampered))
