#lang racket/base
(require rackunit racket/runtime-path "../mdl/loader.rkt")

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(unless (directory-exists? source-root)
  (error 'historical-start-back "pinned source missing: ~a" source-root))
;; S13 part B (ADR-0050): the session writes only to its explicit port.
(define session-out (open-output-string))
(define session (make-mdl-session source-root #:output-port session-out))
(define load-report (mdl-session-load! session "77loadall.mud"))
(check-equal? (hash-ref load-report 'status) "PASS")
(check-equal? (hash-ref load-report 'completed_expressions) 1229)
(check-equal? (hash-ref load-report 'skipped_expressions) 0)

;; Known XFAIL frontier: the unchanged START now passes RANDOM and BACK,
;; then needs the platform TENEX? global in original CONTIN at 77rooms.mud:298.
(define start-offset (string-length (get-output-string session-out)))
(define failure
  (with-handlers ([exn:fail? values])
    (mdl-session-call session "START" "WHOUS" "")))
(define output (substring (get-output-string session-out) start-offset))
(check-true (exn:fail? failure))
(check-true (regexp-match? #rx"unassigned MDL global TENEX\\?" (exn-message failure)))
(check-true (regexp-match? #rx"^Welcome to Dungeon" output))
