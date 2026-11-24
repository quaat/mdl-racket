#lang racket/base
;; M4 S9 (issues #169, #170; ADR-0061 note): deterministic replay across SLEEP
;; and TIME. SLEEP and TIME add no clock observation and no checkpoint field
;; (docs/SEMANTICS.md "M4: IMAGE, SLEEP, TIME"), so:
;;   1. mirror-bat (tests/scenarios/mirror-bat.json): recorded on a recording
;;      clock over the fixed source 250776000 UTC (non-live), the Bat Room's
;;      three <SLEEP 1> never call the host sleeper; the checkpoint taken at
;;      the prompt after the bat has as many clock observations as the one
;;      before it; restoring it replays FWEEP without waiting (replaying clock),
;;      verifies, and pre-save output + post-restore output equals the native
;;      T1 transcript (three BEL bytes included, D1 only);
;;   2. strange-passage (tests/scenarios/strange-passage.json): a checkpoint
;;      after `c-int` (TIME applied by name, and BLROO's room action TIME)
;;      restores exactly, and the session's TIME counter after restore equals
;;      the recorded session's at the same prompt (replay reproduces it).
;; Every run is guarded (no file write or delete, empty temporary cwd) and
;; watchdogged; a recording fake host sleeper detects any wait.
;;
;; Requires the pinned upstream source. Run with:
;;   racket tests/replay_sleep_time_test.rkt   (exit status is authoritative)
(require rackunit racket/runtime-path racket/string racket/list racket/file json
         "../mdl/loader.rkt" "../mdl/replay.rkt" "../mdl/runtime/clock.rkt"
         (only-in "../mdl/runtime/core.rkt" current-mdl-sleeper)
         "../zork/persistence.rkt")

(current-check-handler (lambda (e) (raise e)))

(define-runtime-path tests-dir ".")
(define epoch 250776000)
(define (lines l) (apply string-append (map (lambda (c) (string-append c "\n")) l)))
(define (scenario-commands name)
  (hash-ref (call-with-input-file (build-path tests-dir "scenarios" (string-append name ".json"))
              read-json)
            'commands))
;; The native T1 transcript of a scenario reference, D1 applied.
(define (native-t1 name)
  (define reference (call-with-input-file
                     (build-path tests-dir 'up "docs" "evidence" "M4" (string-append name "-reference.json"))
                     read-json))
  (define c (findf (lambda (c) (equal? (hash-ref c 'name) (format "T1-~a-pipe" name)))
                   (hash-ref reference 'cases)))
  (define raw (hash-ref c 'stdout_raw))
  (define banner "LISTENING-AT-LEVEL 1 PROCESS 1\n")
  (define after (cadr (regexp-match (regexp (string-append "^.*?" (regexp-quote banner) "(.*)$")) raw)))
  (string-replace after "\"DONE\"\n" "" #:all? #f))

;; --- guarded runs with a recording fake sleeper ----------------------------------------
(define original-guard (current-security-guard))
(define sleeps '())
(define (guarded thunk #:limit [limit 300])
  (define cwd (make-temporary-file "m4-s9-replay-cwd-~a" 'directory))
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
    (parameterize ([current-security-guard guard] [current-directory cwd]
                   [current-mdl-sleeper (lambda (s) (set! sleeps (cons s sleeps)))])
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
(define (record cmds on-prompt)
  (define out (open-output-string))
  (define result
    (guarded (lambda ()
               (zork-record #:input (open-input-string (lines cmds)) #:output out
                            #:clock fixed-source #:time-zone 'utc #:boot-clock "fixed:250776000"
                            #:on-prompt on-prompt))))
  (check-equal? (replay-result-kind result) 'input-exhausted)
  (values result (get-output-string out)))
(define (restore cp rest #:on-restored [on-restored void])
  (define out (open-output-string))
  (define result
    (guarded (lambda ()
               (zork-restore cp #:input (open-input-string (lines rest)) #:output out
                             #:wall-clock wall #:on-restored on-restored))))
  (check-equal? (replay-result-kind result) 'input-exhausted)
  (values result (get-output-string out)))
(define (observations cp) (hash-ref (canonical-json-parse cp) 'observations))
(define (transcript-bytes cp) (hash-ref (hash-ref (canonical-json-parse cp) 'verification) 'transcript_bytes))

;; === 1. mirror-bat: SLEEP never waits on record or replay ============================
(define bat-cmds (scenario-commands "mirror-bat"))
(check-equal? (list-ref bat-cmds 35) "west") ; the Bat Room
(define bat-cps (make-hash))
(set! sleeps '())
(define-values (bat-rec bat-out)
  (record bat-cmds (lambda (p) (when (memv (replay-prompt-turn p) '(35 36))
                                 (hash-set! bat-cps (replay-prompt-turn p)
                                            (replay-prompt-checkpoint p))))))
(check-equal? sleeps '() "recording over the fixed clock: SLEEP never waits")
(check-equal? bat-out (native-t1 "mirror-bat") "recorded run = native T1 (BELs included)")
(check-equal? (length (regexp-match* #rx"\a" bat-out)) 3)
(define cp35 (hash-ref bat-cps 35))
(define cp36 (hash-ref bat-cps 36))
;; The bat's three SLEEPs (and IMAGEs) between the two prompts add no clock
;; observation.
(check-equal? (observations cp36) (observations cp35))
(check-equal? (observations cp36) (list (list epoch 0 0) (list epoch 0 0) (list epoch 0 0)))
(set! sleeps '())
(define bat-restored-state (box #f))
(define t0 (current-inexact-milliseconds))
(define-values (bat-res bat-post)
  (restore cp36 (drop bat-cmds 36)
           #:on-restored (lambda (s) (set-box! bat-restored-state (zork-replay-state s)))))
(define bat-restore-seconds (/ (- (current-inexact-milliseconds) t0) 1000.0))
(check-equal? sleeps '() "replay (replaying clock) never waits")
(check-equal? (unbox bat-restored-state)
              (hash-ref (hash-ref (canonical-json-parse cp36) 'verification) 'state))
(check-equal? (string-append (substring bat-out 0 (transcript-bytes cp36)) bat-post)
              (native-t1 "mirror-bat") "pre-save + post-restore = native T1")
(printf "1. mirror-bat: no SLEEP wait recorded or replayed; checkpoint after the bat restores (~a s)\n"
        bat-restore-seconds)

;; === 2. strange-passage: TIME is reproduced by replay ===============================
(define sp-cmds (scenario-commands "strange-passage"))
(check-equal? (list-ref sp-cmds 26) "c-int")
(define sp-cp #f)
(define sp-time-at-27 #f)
(define-values (sp-rec sp-out)
  (record (take sp-cmds 27)
          (lambda (p)
            (when (= (replay-prompt-turn p) 27)
              (set! sp-cp (replay-prompt-checkpoint p))
              ;; Read the session's TIME counter (host call; after the checkpoint).
              (set! sp-time-at-27 (mdl-session-call (replay-prompt-session p) "TIME"))))))
(check-true (and (flonum? sp-time-at-27) (> sp-time-at-27 1.0)))
(check-equal? (observations sp-cp) (list (list epoch 0 0) (list epoch 0 0) (list epoch 0 0)))
(define sp-time-restored #f)
(define-values (sp-res sp-post)
  (restore sp-cp (drop sp-cmds 27)
           #:on-restored (lambda (s) (set! sp-time-restored (mdl-session-call s "TIME")))))
(check-equal? sp-time-restored sp-time-at-27 "TIME counter after restore = recorded")
(check-equal? (string-append (substring sp-out 0 (transcript-bytes sp-cp)) sp-post)
              (native-t1 "strange-passage") "pre-save + post-restore = native T1")
(check-equal? sleeps '())
(printf "2. strange-passage: checkpoint after c-int restores; TIME counter ~a reproduced\n"
        sp-time-at-27)
