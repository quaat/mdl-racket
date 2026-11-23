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

;; Known XFAIL frontier (S4-ON-SAVE): SAVE-IT now runs ON "IPC" (77rooms.mud:16;
;; registration only, maintainer decision 2026-11-22 on issue #112) and stops
;; at the intentional strict SAVE error at 77rooms.mud:26.  INITIALIZED is
;; BLOCKED at SAVE by maintainer decision (2): SAVE never returns "SAVED"
;; and writes no file.
;;
;; SAVE-IT steps that now execute successfully before the failure:
;;   77rooms.mud:12  PUT <FIND-OBJ "PAPER"> ODESC1 <UNSPEAKABLE-CODE>
;;   77rooms.mud:13  SETG VERS .ST (REMARKABLY-DISGUSTING-CODE date string)
;;   77rooms.mud:14  SETG SCRIPT-CHANNEL <>
;;   77rooms.mud:15  SETG RAW-SCORE 0
;;   77rooms.mud:16  SET IH <ON "IPC" ,ILO 1>       (registers; IPC never fires)
;;   77rooms.mud:17  HANDLER ,DIVERT-INT ,DIVERT-HAND
;;   77rooms.mud:19-21  SETG SCRATCH-STR <ISTRING 32>, DEV "DSK", SNM "MDL"
;;   77rooms.mud:25  INT-LEVEL 100000
;;   77rooms.mud:26  <SAVE .FN>  <- BLOCKED (strict unsupported)
;;
;; Call chain: SAVE-IT -> SAVE (77rooms.mud:26)
;; This test asserts the XFAIL message so progress is tracked without claiming
;; INITIALIZED.
(define (listing dir) (sort (map path->string (directory-list dir)) string<?))
(define source-before (listing source-root))
(define output (open-output-string))
(define failure
  (with-handlers ([exn:fail? values])
    (parameterize ([current-output-port output])
      (mdl-session-call session "SAVE-IT"))))
(check-true (exn:fail? failure))
(check-true
 (regexp-match?
  #rx"^SAVE: saving a restorable image is not supported \\(maintainer decision 2026-11-22; issue #112\\)$"
  (exn-message failure)))
(check-equal? (get-output-string output) "")
;; State established by 77rooms.mud:13-25 before SAVE was reached.
(check-equal? (mdl-session-call session "INT-LEVEL") 100000)
(check-equal? (mdl-session-global session "DEV") "DSK")
(check-equal? (mdl-session-global session "SNM") "MDL")
(check-equal? (mdl-session-global session "RAW-SCORE") 0)
(check-equal? (string-length (mdl-session-global session "SCRATCH-STR")) 32)
;; No image was written next to the source.
(check-equal? (listing source-root) source-before)
