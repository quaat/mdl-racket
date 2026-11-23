#lang racket/base
;; Historical regression: SAVE-IT frontier after the 1,229-form load.
;;
;; Tracks source progress toward INITIALIZED on the faithful run.mud entry
;; path (<FLOAD "77loadall.mud"> then <SAVE-IT>).
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: make test-m3-saveit   (or: racket tests/historical_saveit_test.rkt)
(require rackunit racket/runtime-path "../mdl/loader.rkt" "../mdl/runtime/core.rkt")

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(unless (directory-exists? source-root)
  (error 'historical-saveit "pinned source missing: ~a" source-root))

(define session (make-mdl-session source-root))
(define load-report
  (parameterize ([current-output-port (open-output-string)])
    (mdl-session-load! session "77loadall.mud")))
(check-equal? (hash-ref load-report 'status) "PASS")
(check-equal? (hash-ref load-report 'completed_expressions) 1229)
(check-equal? (hash-ref load-report 'skipped_expressions) 0)

;; Known XFAIL frontier (S5-SAVE-RECORD, ADR-0048). SAVE is a session
;; record: <SAVE .FN> returns a fresh "SAVED", writes no file, and is recorded
;; with INT-LEVEL 100000. The patched SAVE-IT has a single COND clause, so it
;; continues in the same session: <INT-LEVEL 0> (77rooms.mud:26), STARTER,
;; GETSYS (56), ON "BLOCKED" (59; registers, never fires), START (60).
;; INITIALIZED remains FAIL: the run stops in CONTIN at the first reference
;; to the GVAL of REP, the LISTEN loop's applicable (Confusion: a SUBR).
;;
;; Call chain: SAVE-IT (77rooms.mud:60) -> START (77rooms.mud:293)
;;   -> CONTIN (77rooms.mud:301) <SETG SAVEREP ,REP>  <- XFAIL here
;; This test asserts the XFAIL message so progress is tracked without claiming
;; INITIALIZED.
(define (listing dir) (sort (map path->string (directory-list dir)) string<?))
(define source-before (listing source-root))
(check-equal? (mdl-session-global session "ALT-FLAG") (mdl-session-atom session "T"))
(check-equal? (mdl-session-save-records session) '())
(define output (open-output-string))
(define failure
  (with-handlers ([exn:fail? values])
    (parameterize ([current-output-port output])
      (mdl-session-call session "SAVE-IT"))))
(check-true (exn:fail? failure))
(check-equal? (exn-message failure) "mdl-gval: unassigned MDL global REP")
;; SAVE (77rooms.mud:26) ran once, returned "SAVED" (the COND clause was
;; taken) and was recorded with the file-spec and INT-LEVEL 100000.
(define records (mdl-session-save-records session))
(check-equal? (length records) 1)
(check-equal? (mdl-save-record-sequence (car records)) 1)
(check-equal? (mdl-save-record-file-spec (car records)) "<MDL>MADADV.SAVE")
(check-equal? (mdl-save-record-int-level (car records)) 100000)
;; <INT-LEVEL 0> after SAVE (77rooms.mud:26) and in START (292) executed.
(check-equal? (mdl-session-call session "INT-LEVEL") 0)
;; No GC/DIVERT-AGC occurrence was pending at either INT-LEVEL 0: the
;; DIVERT handler (enabled at 77rooms.mud:17) never ran.
(check-equal? (mdl-session-global session "DIVERT-CNT") 0)
(check-equal? (mdl-session-global session "DIVERT-AMT") 0)
;; STARTER/GETSYS (56): TENEX? is FALSE.
(check-true (mdl-false? (mdl-session-global session "TENEX?")))
;; START ran through TELL (289-290) and its INT-LEVEL 0 (292).
(check-true
 (regexp-match? #rx"^Welcome to Dungeon\\.\r?\nThis version created [A-Z][a-z]+ [0-9]+\\.\n$"
                (get-output-string output))
 (get-output-string output))
(check-equal? (mdl-session-global session "DEATHS") 0)
(check-equal? (mdl-session-global session "MOVES") 0)
;; XUNAME/GET-NAME as in the Confusion trace (S5-SAVE-FRONTIER.md Q3 step 6).
(check-equal? (mdl-session-global session "XUNM") "MTRZORK")
(check-equal? (mdl-session-global session "USER-NAME") "")
;; CONTIN's first form (77rooms.mud:296) ran; 301 did not complete.
(check-true (mdl-false? (mdl-session-global session "ALT-FLAG")))
(check-exn #rx"unassigned MDL global SAVEREP"
           (lambda () (mdl-session-global session "SAVEREP")))
;; State established by 77rooms.mud:13-21 before SAVE was reached.
(check-equal? (mdl-session-global session "DEV") "DSK")
(check-equal? (mdl-session-global session "SNM") "MDL")
(check-equal? (mdl-session-global session "RAW-SCORE") 0)
(check-equal? (string-length (mdl-session-global session "SCRATCH-STR")) 32)
;; No image was written next to the source.
(check-equal? (listing source-root) source-before)
