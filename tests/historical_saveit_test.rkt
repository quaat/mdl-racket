#lang racket/base
;; Historical regression: SAVE-IT frontier after the 1,229-form load.
;;
;; Tracks source progress toward INITIALIZED on the faithful run.mud entry
;; path (<FLOAD "77loadall.mud"> then <SAVE-IT>).
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: make test-m3-saveit   (or: racket tests/historical_saveit_test.rkt)
(require rackunit racket/runtime-path "../mdl/loader.rkt")

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

;; Known XFAIL frontier: SAVE-IT calls UNSPEAKABLE-CODE (77rooms.mud:146-157)
;; which uses SUBSTRUC on a STRING (77rooms.mud:155), called from SAVE-IT
;; (77rooms.mud:12).  MEMQ on STRING is now implemented (S1-MEMQ-STRING);
;; SUBSTRUC is the next dependency.
;; Call chain: SAVE-IT → UNSPEAKABLE-CODE → SUBSTRUC (77rooms.mud:155)
;; This test asserts the XFAIL message so progress is tracked without claiming
;; INITIALIZED.
(define output (open-output-string))
(define failure
  (with-handlers ([exn:fail? values])
    (parameterize ([current-output-port output])
      (mdl-session-call session "SAVE-IT"))))
(check-true (exn:fail? failure))
(check-true (regexp-match? #rx"unassigned or non-applicable MDL operator SUBSTRUC"
                           (exn-message failure)))
