#lang racket/base
;; M4 WP4.5 proof of concept and WP4.6 regressions: host persistence of the
;; unchanged December 1977 Zork by deterministic replay (ADR-0061; SEMANTICS
;; "M4 WP4"). The S6 troll-combat scenario (tests/scenarios/troll-combat.json)
;; is played on a recording clock over the fixed source 250776000 UTC, so the
;; pinned native captures of docs/evidence/M4/troll-combat-reference.json stay
;; the oracle:
;;   a. save at the RDCOM prompt before the first `kill troll with sword`, end
;;      that session, restore in a fresh process and in-process: verification
;;      state and both RNG words exactly equal; pre-save output + post-restore
;;      output = the native full transcript (D1 only); end state = native;
;;   b. save after combat: ownership, score, flags after restore;
;;   c. the lamp countdown (LNTIN) is pending: equal after restore, downtime
;;      does not advance it;
;;   d. RNG continuity on detached snapshots;
;;   f. restore under different wall clocks: identical continuation (resumed
;;      clock, `time`);
;;   g. tampering and incompatible checkpoints;
;;   h. no duplicate output, no file writes;
;;   i. independent restored sessions, the same checkpoint twice, a failed
;;      restore beside a live session;
;;   j. replay cost (seconds per 100 commands).
;; (e, explicit RANDOM reseed, is in tests/replay_checkpoint_test.rkt: the game
;; never reseeds after START.)
;; Every game run is guarded (no file write or delete, empty temporary cwd,
;; game directory hashes unchanged) and watchdogged. Evidence, not a PLAYABLE
;; or M4-gate claim.
;;
;; Requires the pinned upstream source. Run with:
;;   racket tests/persistence_replay_test.rkt   (exit status is authoritative)
(require rackunit racket/runtime-path racket/port racket/string racket/list
         racket/file racket/path racket/system file/sha1 json compiler/find-exe
         "../mdl/loader.rkt" "../mdl/replay.rkt" "../mdl/runtime/clock.rkt"
         (only-in "../mdl/runtime/random36.rkt" random36-next! random36-state-copy)
         "../zork/persistence.rkt")

(current-check-handler
 (lambda (e)
   (when (exn:test:check? e)
     (for ([i (in-list (exn:test:check-stack e))])
       (eprintf "  ~a: ~e\n" (check-info-name i) (check-info-value i))))
   (raise e)))

(define-runtime-path source-root "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(define-runtime-path scenario-file "scenarios/troll-combat.json")
(define-runtime-path reference-file "../docs/evidence/M4/troll-combat-reference.json")
(define-runtime-path child-file "persistence_restore_child.rkt")
(unless (directory-exists? source-root)
  (error 'persistence-replay "pinned source missing: ~a" source-root))

(define scenario (call-with-input-file scenario-file read-json))
(define reference (call-with-input-file reference-file read-json))
(define commands (hash-ref scenario 'commands))
(check-equal? (length commands) 22)
(check-equal? (list-ref commands 13) "kill troll with sword")
(check-equal? (take-right (take commands 16) 3) (make-list 3 "kill troll with sword"))
(check-equal? (hash-ref scenario 'fixed_epoch) 250776000)
(check-equal? (hash-ref reference 'upstream_mdlzork_checked_out) "bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3")
(check-equal? (hash-ref reference 'commands) commands)
(define epoch 250776000)
(define (lines l) (apply string-append (map (lambda (c) (string-append c "\n")) l)))

;; --- the native oracle (as tests/historical_troll_combat_test.rkt) ---------------
(define (ref-case name)
  (or (findf (lambda (c) (equal? (hash-ref c 'name) name)) (hash-ref reference 'cases))
      (error 'ref-case "no reference case ~a" name)))
(define native-t1
  (let* ([c (ref-case "T1-troll-combat-pipe")]
         [raw (hash-ref c 'stdout_raw)])
    (check-equal? (hash-ref c 'clock) (hasheq 'epoch epoch 'tz "UTC"))
    (check-equal? (hash-ref c 'input) (string-append "<FLOAD \"77loadall.mud\">\n<SAVE-IT>\n"
                                                     (lines commands)))
    (check-equal? (bytes->hex-string (sha256-bytes (apply bytes (map char->integer (string->list raw)))))
                  (hash-ref c 'stdout_sha256))
    (define banner "LISTENING-AT-LEVEL 1 PROCESS 1\n")
    (define after (cadr (regexp-match (regexp (string-append "^.*?" (regexp-quote banner) "(.*)$")) raw)))
    (check-equal? (length (regexp-match* (regexp-quote "\"DONE\"\n") after)) 1)
    (string-replace after "\"DONE\"\n" "" #:all? #f)))
(define (strip-trailers str) (regexp-replace* #rx"!-[A-Z]+" str ""))
(define (native-checkpoint k #:end? [end? #t])
  (define cps (if end? (hash-ref reference 'end_checkpoints)
                  (hash-ref (hash-ref reference 'diagnostic) 'checkpoints)))
  (for/hasheq ([(key v) (in-hash (list-ref cps k))] #:unless (eq? key 'n))
    (values key (strip-trailers v))))
(define troll-fields (hash-keys (native-checkpoint 22)))
(check-equal? (length troll-fields) 21)
(define (troll-part state) (for/hasheq ([k (in-list troll-fields)]) (values k (hash-ref state k))))
(define native-seed
  (string->number (cadr (regexp-match #rx"^\\(([0-9]+)\\)$"
                                      (hash-ref (car (hash-ref (hash-ref reference 'diagnostic)
                                                               'random_draws))
                                                'args)))))
(check-equal? native-seed 10438660480)

;; --- guarded, watchdogged runs -------------------------------------------------------
(define original-guard (current-security-guard))
(define (tree-manifest dir0)
  (define dir (simplify-path dir0))
  (parameterize ([current-security-guard original-guard])
    (sort (for/list ([p (in-list (find-files file-exists? dir))])
            (list (path->string (find-relative-path dir (simplify-path p)))
                  (file-size p)
                  (call-with-input-file p (lambda (in) (bytes->hex-string (sha256-bytes in))))))
          string<? #:key car)))
(define manifest-0 (tree-manifest source-root))
(define all-writes '())
(define (guarded thunk #:limit [limit 300])
  (define cwd (make-temporary-file "m4-replay-cwd-~a" 'directory))
  (define guard
    (make-security-guard
     original-guard
     (lambda (who path modes)
       (when (and path (or (memq 'write modes) (memq 'delete modes)))
         (set! all-writes (cons (list who path modes) all-writes))))
     (lambda (who host port mode) (void))))
  (define done (make-channel))
  (define worker
    (parameterize ([current-security-guard guard] [current-directory cwd])
      (thread (lambda ()
                (channel-put done (with-handlers ([(lambda (v) #t) (lambda (v) (list 'raised v))])
                                    (list 'ok (thunk))))))))
  (define outcome (or (sync/timeout limit done) (begin (kill-thread worker) (list 'raised 'timed-out))))
  (check-equal? (parameterize ([current-security-guard original-guard]) (directory-list cwd)) '()
                "the temporary cwd stayed empty")
  (delete-directory/files cwd)
  (if (eq? (car outcome) 'ok) (cadr outcome) (raise (cadr outcome))))
(define (stage-of thunk)
  (with-handlers ([exn:fail:replay-restore? (lambda (e) (list (exn:fail:replay-restore-stage e)
                                                              (exn-message e)))])
    (thunk)
    '(accepted "")))

(define fixed-source (make-fixed-mdl-clock epoch))
(define wall-1 (make-fixed-mdl-clock 1900000000))  ; restore ~30 years later

;; === 1. the uninterrupted recorded run (all 22 commands) ===============================
(define full-cps (make-hash))
(define full-rng (make-hash))
(define full-states (make-hash))
(define full-refusals (make-hash))
(define full-out (open-output-string))
(define full-result
  (guarded
   (lambda ()
     (zork-record #:input (open-input-string (lines commands)) #:output full-out
                  #:clock fixed-source #:time-zone 'utc #:boot-clock "fixed:250776000"
                  #:on-prompt
                  (lambda (p)
                    (define k (replay-prompt-turn p))
                    (define s (replay-prompt-session p))
                    (hash-set! full-refusals k (replay-prompt-refusal p))
                    (hash-set! full-rng k (mdl-session-random-snapshot s))
                    (when (memv k '(0 13 16 22))
                      (hash-set! full-states k (zork-replay-state s))
                      (hash-set! full-cps k (replay-prompt-checkpoint p))))))))
(check-equal? (replay-result-kind full-result) 'input-exhausted)
;; recording (and making checkpoints) does not change the game: native transcript
(check-equal? (get-output-string full-out) native-t1 "recorded run = native T1 (D1 only)")
(define full-end-state (zork-replay-state (replay-result-session full-result)))
(check-equal? (troll-part full-end-state) (native-checkpoint 22))
(check-equal? (sort (hash-keys full-refusals) <) (range 23))
(check-equal? (filter values (hash-values full-refusals)) '() "every RDCOM prompt of the run is a save point")
(set! full-result #f) ; drop the session
(define cp13 (hash-ref full-cps 13))
(define cp16 (hash-ref full-cps 16))
(define doc13 (canonical-json-parse cp13))
(define ver13 (hash-ref doc13 'verification))
(check-equal? (hash-ref ver13 'state) (hash-ref full-states 13))
(check-equal? (troll-part (hash-ref ver13 'state)) (native-checkpoint 13 #:end? #f))
(check-equal? (hash-ref (hash-ref doc13 'rng) 'seed)
              (hasheq 'source "START <RANDOM <CHTYPE <DSKDATE> FIX>> (77rooms.mud:291)"
                      'observation_index 2 'dskdate native-seed))
(check-equal? (hash-ref doc13 'observations) (list (list epoch 0 0) (list epoch 0 0) (list epoch 0 0)))
(check-equal? (hash-ref (hash-ref doc13 'rng) 'draws) 2) ; START's seed, FIGHTING entering the troll room
(check-equal? (hash-ref ver13 'moves) 13)
(check-regexp-match #rx"^LNTIN [0-9]+ T$" (hash-ref (hash-ref ver13 'state) 'clock_events))
(printf "1. recorded run = native T1; checkpoints at turns 0, 13, 16, 22 (~a, ~a bytes)\n"
        (bytes-length cp13) (bytes-length cp16))

;; === a. save before the first kill, end the session ===================================
(define trunc-cp #f)
(define trunc-out (open-output-string))
(define trunc-result
  (guarded
   (lambda ()
     (zork-record #:input (open-input-string (lines (take commands 13))) #:output trunc-out
                  #:clock fixed-source #:time-zone 'utc #:boot-clock "fixed:250776000"
                  #:on-prompt (lambda (p) (when (= (replay-prompt-turn p) 13)
                                            (set! trunc-cp (replay-prompt-checkpoint p))))))))
(check-equal? (replay-result-kind trunc-result) 'input-exhausted) ; the session ended
(set! trunc-result #f)
(check-equal? trunc-cp cp13 "the checkpoint of the ended session = the uninterrupted run's, byte for byte")
(define pre13 (hash-ref ver13 'transcript_bytes))
(define pre-save-output (substring (get-output-string trunc-out) 0 pre13))
(check-equal? pre-save-output (substring native-t1 0 pre13))
(define cp-dir (make-temporary-file "m4-replay-cp-~a" 'directory))
(define cp13-file (build-path cp-dir "troll-before-kill.mdl-zork-replay.json"))
(call-with-output-file cp13-file (lambda (o) (void (write-bytes cp13 o))))
(define (read-checkpoint file)
  (call-with-input-file file (lambda (in) (read-bytes (add1 (hash-ref replay-limits 'bytes)) in))))

;; In-process restore from the file; continue with the remaining 9 commands.
(define (restore cp rest #:wall [wall wall-1] #:on-restored [on-restored void])
  (define out (open-output-string))
  (define result
    (guarded (lambda ()
               (zork-restore cp #:input (open-input-string (lines rest)) #:output out
                             #:wall-clock wall #:on-restored on-restored))))
  (values result (get-output-string out)))
(define (capture-at-restore box)
  (lambda (s)
    (set-box! box (hasheq 'rng (mdl-session-random-snapshot s) 'state (zork-replay-state s)))))
(define at13 (box #f))
(define t-restore-0 (current-inexact-milliseconds))
(define t-restored #f)
(define-values (res13 post13)
  (restore (read-checkpoint cp13-file) (drop commands 13)
           #:on-restored (lambda (s) (set! t-restored (current-inexact-milliseconds))
                           ((capture-at-restore at13) s))))
(define restore13-seconds (/ (- t-restored t-restore-0) 1000.0))
(check-equal? (hash-ref (unbox at13) 'state) (hash-ref ver13 'state) "verification state after restore")
(check-equal? (random36-state-words (hash-ref (unbox at13) 'rng))
              (random36-state-words (hash-ref full-rng 13)) "both RNG words after restore")
(check-equal? (random36-state-draws (hash-ref (unbox at13) 'rng)) 2)
(check-equal? (replay-result-kind res13) 'input-exhausted)
;; h. no duplicate output: the live port got only the post-save text, and
;; pre-save + post-restore output is exactly the native transcript
(check-equal? (string-append pre-save-output post13) native-t1 "pre-save + post-restore = native T1")
(define end-state-13 (zork-replay-state (replay-result-session res13)))
(check-equal? (troll-part end-state-13) (native-checkpoint 22))
;; the restored game ends in exactly the uninterrupted run's state (all
;; selected fields: clock events, lamp, ledger, DIVERT counters included)
(check-equal? end-state-13 full-end-state)
(set! res13 #f)
(printf "a. in-process restore before the kill: verified in ~a s; output = native T1; end state = native\n"
        restore13-seconds)

;; d. RNG continuity: the next draws on detached snapshots are equal
(define (next-draws snap k)
  (define copy (random36-state-copy snap)) ; never step the stored snapshot
  (for/list ([_ k]) (random36-next! copy)))
(check-equal? (next-draws (hash-ref (unbox at13) 'rng) 12) (next-draws (hash-ref full-rng 13) 12))
(check-equal? (random36-state-words (hash-ref full-rng 13)) (hash-ref (hash-ref doc13 'rng) 'state))
(printf "d. next 12 RANDOM values after restore = uninterrupted run\n")

;; a. the same checkpoint restored in a FRESH PROCESS
(define rest-file (build-path cp-dir "rest-commands.json"))
(call-with-output-file rest-file (lambda (o) (write-json (drop commands 13) o)))
(define-values (child-status child-out child-err)
  (let ([out (open-output-string)] [err (open-output-string)])
    (define ok?
      (parameterize ([current-output-port out] [current-error-port err])
        (system* (find-exe) (path->string child-file) (path->string cp13-file) (path->string rest-file))))
    (values ok? (get-output-string out) (get-output-string err))))
(unless child-status (error 'persistence-replay "child restore failed: ~a" child-err))
(define child (with-input-from-string child-out read-json))
(define child-at (hash-ref child 'at_restore))
(check-equal? (hash-ref child-at 'rng) (random36-state-words (hash-ref (unbox at13) 'rng)))
(check-equal? (hash-ref child-at 'draws) 2)
(check-equal? (hash-ref child-at 'state) (hash-ref ver13 'state))
(check-equal? (hash-ref child 'output) post13 "fresh-process continuation = in-process continuation")
(check-equal? (hash-ref child 'kind) "input-exhausted")
(check-equal? (hash-ref child 'end_state) end-state-13)
(printf "a. fresh-process restore: RNG words, state, continuation and end state equal\n")

;; === b. save after combat ================================================================
(define doc16 (canonical-json-parse cp16))
(define ver16 (hash-ref doc16 'verification))
(define at16 (box #f))
(define-values (res16 post16) (restore cp16 (drop commands 16) #:on-restored (capture-at-restore at16)))
(define state16 (hash-ref (unbox at16) 'state))
(check-equal? state16 (hash-ref ver16 'state))
(check-equal? (troll-part state16) (native-checkpoint 16 #:end? #f))
;; ownership, score, flags after the troll's death
(check-equal? (map (lambda (k) (hash-ref state16 k))
                   '(aobjs troll_oroom troll_ocontents axe_ocan troll_flag troll_fighting raw_score ascore
                     sword_otval moves))
              '("(LAMP SWORD)" "#FALSE ()" "(AXE)" "TROLL" "T" "#FALSE ()" "35" "35" "0" "16"))
(check-equal? (random36-state-words (hash-ref (unbox at16) 'rng)) (random36-state-words (hash-ref full-rng 16)))
(check-equal? (string-append (substring native-t1 0 (hash-ref ver16 'transcript_bytes)) post16) native-t1)
(check-equal? (troll-part (zork-replay-state (replay-result-session res16))) (native-checkpoint 22))
(set! res16 #f)
(printf "b. restore after combat: ownership, score and flags equal; continuation = native\n")

;; === c./f. the pending lamp event and the resumed clock ===================================
;; c: LNTIN (the lamp, on since `turn on lamp`) is pending at turn 13. After a
;; restore ~30 years later (wall-1) its tick count is the saved one, and it then
;; advances per turn exactly as in the uninterrupted run (end-state-13 =
;; full-end-state above, clock_events included).
(define lamp-keys '(clock_events lamp_light_count lamp_olight))
(define (pick st keys) (map (lambda (k) (hash-ref st k)) keys))
(check-equal? (pick (hash-ref (unbox at13) 'state) lamp-keys) (pick (hash-ref full-states 13) lamp-keys))
(check-not-equal? (hash-ref (hash-ref full-states 13) 'clock_events) (hash-ref full-end-state 'clock_events))
(printf "c. lamp event at restore ~s = saved; downtime did not advance it\n"
        (hash-ref (hash-ref (unbox at13) 'state) 'clock_events))
;; f: two restores under different wall clocks (each advancing 1 s per read)
;; continue identically, and `time` counts only play since the save point.
(define (stepping-clock start step-micros)
  (define n 0)
  (make-mdl-clock (lambda ()
                    (define total (+ (* start 1000000) (* n step-micros)))
                    (set! n (add1 n))
                    (values (quotient total 1000000) (remainder total 1000000)))))
(define time-rest '("time" "kill troll with sword" "time"))
(define-values (rf1 postf1) (restore cp13 time-rest #:wall (stepping-clock 1000000000 1000000)))
(define-values (rf2 postf2) (restore cp13 time-rest #:wall (stepping-clock 2000000000 1000000)))
(set! rf1 #f) (set! rf2 #f)
(check-equal? postf1 postf2 "identical continuation under different wall clocks")
;; (the game text carries the source's CR LF after the PLAY-TIME sentence)
(check-regexp-match #rx"^You have been playing DUNGEON for 1 second\\.\r\n>" postf1)
(check-regexp-match #rx">You have been playing DUNGEON for 2 seconds\\.\r\n" postf1)
(printf "f. resumed clock: identical continuation under wall clocks 1e9 and 2e9; `time` = 1 s, then 2 s\n")

;; === g. tampering and incompatible checkpoints ============================================
(define (tamper f) (checkpoint-reseal (f doc13)))
(define (hset* h path v)
  (if (null? (cdr path)) (hash-set h (car path) v)
      (hash-set h (car path) (hset* (hash-ref h (car path)) (cdr path) v))))
(define (try-restore cp #:root [root source-root])
  (stage-of (lambda () (guarded (lambda ()
                                  (zork-restore cp #:source-root root #:input (open-input-string "")
                                                #:output (open-output-string) #:wall-clock wall-1))))))
(define sessions-before (replay-sessions-created))
(define flipped (bytes-copy cp13))
(let ([at (car (car (regexp-match-positions #rx"open window" cp13)))])
  (bytes-set! flipped at (char->integer #\O)))
(define no-boot-cases
  (list (list "one changed byte (in the input log)" flipped 'checksum)
        (list "changed checksum" (canonical-json-bytes (hash-set doc13 'checksum (make-string 64 #\f))) 'checksum)
        (list "truncated" (subbytes cp13 0 (sub1 (bytes-length cp13))) 'format)
        (list "format v2" (tamper (lambda (d) (hash-set d 'format "mdl-zork-replay/v2"))) 'format)
        (list "rng/v2" (tamper (lambda (d) (hset* d '(rng version) "rng/v2"))) 'format)
        (list "other RNG algorithm" (tamper (lambda (d) (hset* d '(rng algorithm) "mt19937/v1"))) 'format)
        (list "manifest hash" (tamper (lambda (d) (hset* d '(source manifest_sha256) (make-string 64 #\0))))
              'provenance)
        (list "upstream SHA" (tamper (lambda (d) (hset* d '(source upstream mdlzork) (make-string 40 #\0))))
              'provenance)
        (list "a listed file's hash" (tamper (lambda (d) (hset* (hset* d '(source files)
                                                                       (list-set (hash-ref (hash-ref d 'source) 'files) 1
                                                                                 (list "81prim.mud" (make-string 64 #\0))))
                                                                '(source manifest_sha256)
                                                                (bytes->hex-string
                                                                 (sha256-bytes
                                                                  (open-input-bytes
                                                                   (canonical-json-bytes
                                                                    (list-set (hash-ref (hash-ref d 'source) 'files) 1
                                                                              (list "81prim.mud" (make-string 64 #\0))))))))))
              'provenance)))
(for ([c (in-list no-boot-cases)])
  (check-equal? (car (try-restore (cadr c))) (caddr c) (car c)))
;; a different game source on disk: a copy of the pinned directory with one
;; comment appended to 77dung.mud
(define changed-root (build-path cp-dir "changed-source"))
(copy-directory/files source-root changed-root)
(call-with-output-file (build-path changed-root "77dung.mud") #:exists 'append
  (lambda (o) (void (write-string "\n\"changed\"\n" o))))
(define changed (try-restore cp13 #:root changed-root))
(check-equal? (car changed) 'provenance)
(check-regexp-match #rx"77dung.mud" (cadr changed))
(check-equal? (replay-sessions-created) sessions-before "rejected checkpoints created no session")
(define obs13 (hash-ref doc13 'observations))
(define (with-obs obs) (tamper (lambda (d) (hset* (hash-set d 'observations obs)
                                                  '(verification observations) (length obs)))))
(define first-word (car (hash-ref (hash-ref doc13 'rng) 'state)))
(define boot-cases
  (list (list "modified first RNG word"
              (tamper (lambda (d) (hset* d '(rng state)
                                         (list (modulo (add1 first-word) (expt 2 36))
                                               (cadr (hash-ref (hash-ref d 'rng) 'state))))))
              'verification #rx"RANDOM state words")
        (list "modified second RNG word"
              (tamper (lambda (d) (hset* d '(rng state) (list first-word 0))))
              'verification #rx"RANDOM state words")
        (list "missing clock observation" (with-obs (drop-right obs13 1)) 'replay #rx"extra clock read")
        (list "extra clock observation" (with-obs (append obs13 (list (last obs13)))) 'replay
              #rx"missing clock read")
        (list "reordered clock observation (moved to turn 5)"
              (with-obs (list (car obs13) (cadr obs13) (list epoch 0 5))) 'replay #rx"order diverged")))
(for ([c (in-list boot-cases)])
  (define r (try-restore (cadr c)))
  (check-equal? (car r) (caddr c) (car c))
  (check-regexp-match (cadddr c) (cadr r) (car c)))
(printf "g. ~a rejections before any session; ~a verification/replay failures\n"
        (add1 (length no-boot-cases)) (length boot-cases))

;; a different runtime commit and Racket version are diagnostic only
(define other-runtime (tamper (lambda (d) (hash-set d 'runtime (hasheq 'commit "0000000000000000000000000000000000000000"
                                                                       'racket "Racket 99.0 (chez-scheme)")))))
(define-values (r-rt post-rt) (restore other-runtime (drop commands 13)))
(set! r-rt #f)
(check-equal? post-rt post13 "a different runtime commit is accepted; continuation identical")
(printf "g. different runtime commit/Racket version: accepted, identical continuation\n")

;; === i. independence ========================================================================
;; A restored game waits at its prompt (live input on a pipe) while a failed
;; restore and another restore of the same checkpoint run to completion; it
;; then continues exactly as the uninterrupted game.
(define-values (pipe-in pipe-out) (make-pipe))
(define live-out (open-output-string))
(define live-ready (make-semaphore 0))
(define live-at (box #f))
(define live-done (make-channel))
(define live-thread
  (thread (lambda ()
            (channel-put live-done
                         (with-handlers ([(lambda (v) #t) (lambda (v) (list 'raised v))])
                           (list 'ok (guarded #:limit 600
                                              (lambda ()
                                                (zork-restore cp13 #:input pipe-in #:output live-out
                                                              #:wall-clock wall-1
                                                              #:on-restored
                                                              (lambda (s) ((capture-at-restore live-at) s)
                                                                (semaphore-post live-ready)))))))))))
(unless (sync/timeout 300 live-ready) (error 'persistence-replay "the live restore did not reach its prompt"))
(define failed (try-restore (cadr (car boot-cases))))
(check-equal? (car failed) 'verification)
(define-values (r-again post-again) (restore cp13 (drop commands 13)))
(set! r-again #f)
(check-equal? post-again post13 "the same checkpoint restored twice gives identical results")
(void (write-string (lines (drop commands 13)) pipe-out))
(close-output-port pipe-out)
(define live-result (sync/timeout 600 live-done))
(unless (and live-result (eq? (car live-result) 'ok))
  (error 'persistence-replay "live restored session failed: ~a" live-result))
(check-equal? (get-output-string live-out) post13 "the live session was unaffected by the other restores")
(check-equal? (zork-replay-state (replay-result-session (cadr live-result))) full-end-state)
(check-equal? (hash-ref (unbox live-at) 'state) (hash-ref ver13 'state))
(set! live-result #f)
(printf "i. a live restored game, a failed restore and a second restore are independent\n")

;; === j. replay cost ==========================================================================
;; 100 commands around the house, saved at the 101st prompt; the restore time
;; to the verified save point minus the restore time of the same run's first
;; prompt (boot only) is the replay cost of 100 commands.
(define walk (append* (make-list 10 '("look" "inventory" "north" "east" "south" "west" "score"
                                      "open mailbox" "read leaflet" "diagnose"))))
(check-equal? (length walk) 100)
(define walk-cps (make-hash))
(void (guarded (lambda ()
                 (zork-record #:input (open-input-string (lines walk)) #:output (open-output-string)
                              #:clock fixed-source #:time-zone 'utc #:boot-clock "fixed:250776000"
                              #:on-prompt (lambda (p) (when (memv (replay-prompt-turn p) '(0 100))
                                                        (hash-set! walk-cps (replay-prompt-turn p)
                                                                   (replay-prompt-checkpoint p))))))))
(define (time-to-verified cp)
  (define t0 (current-inexact-milliseconds))
  (define t1 #f)
  (define-values (r out) (restore cp '() #:on-restored (lambda (s) (set! t1 (current-inexact-milliseconds)))))
  (/ (- t1 t0) 1000.0))
(define boot-seconds (time-to-verified (hash-ref walk-cps 0)))
(define walk-seconds (time-to-verified (hash-ref walk-cps 100)))
(define per-100 (- walk-seconds boot-seconds))
(printf "j. restore to the verified prompt: boot only ~a s; 100 commands ~a s; replay cost ~a s per 100 commands; checkpoint ~a bytes\n"
        boot-seconds walk-seconds per-100 (bytes-length (hash-ref walk-cps 100)))
(check-true (< per-100 60.0) "replay cost per 100 commands stays under a minute")

;; === h. no file writes; the game directory is unchanged =====================================
(check-equal? all-writes '() "no file write or delete during any game run")
(check-equal? (tree-manifest source-root) manifest-0 "the pinned game directory is unchanged")
(delete-directory/files cp-dir)
(printf "persistence-replay: all checks passed (WP4.5 proof of concept and WP4.6 regressions)\n")
