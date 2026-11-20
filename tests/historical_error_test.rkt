#lang racket/base
;; Invoke original MSETG's ERROR branch after hash-verifying pinned 81prim.mud.
(require rackunit racket/file racket/path racket/port racket/string
         "../mdl/loader.rkt" "../mdl/runtime/core.rkt")

;; Standalone `racket` runs must fail the process when an assertion fails.
(current-check-handler raise)

(define historical
  (build-path ".cache" "upstream" "mdlzork" "mdlzork_771212"
              "patched_confusion" "81prim.mud"))
(define expected-sha
  "8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571")
(unless (file-exists? historical)
  (error 'historical-neq "pinned 81prim.mud missing; run make sources"))
(define sha-tool (find-executable-path "sha256sum"))
(unless sha-tool (error 'historical-neq "sha256sum is required"))
(define-values (proc stdout stdin stderr)
  (subprocess #f #f #f (path->string sha-tool) (path->string historical)))
(close-output-port stdin)
(define sha-output (port->string stdout))
(define sha-error (port->string stderr))
(subprocess-wait proc)
(check-equal? (subprocess-status proc) 0)
(check-equal? sha-error "")
(check-equal? (car (string-split sha-output)) expected-sha)

(define root (make-temporary-file "/tmp/mdl-error-test~a" 'directory))
(dynamic-wind
 void
 (lambda ()
   (call-with-output-file (build-path root "81prim.mud") #:exists 'truncate/replace
     (lambda (out) (write-bytes (file->bytes historical) out)))
   (check-equal? (file->bytes (build-path root "81prim.mud"))
                 (file->bytes historical))
   (define session (make-mdl-session root))
   (define report (mdl-session-load! session "81prim.mud"))
   (check-equal? (hash-ref report 'status) "PASS")
   (check-equal? (hash-ref report 'completed_expressions) 8)
   (check-equal? (hash-ref report 'skipped_expressions) 0)
   (define atom (mdl-session-call session "ATOM" "G3-NEQ-TEMP"))
   (check-equal? (mdl-atom-pname (mdl-session-call session "MSETG" atom 3)) "T")
   (check-equal? (mdl-session-global session atom) 3)
   (check-equal? (mdl-atom-pname (mdl-session-call session "MSETG" atom 3)) "T")
   (check-equal? (mdl-session-global session atom) 3)
   (check-exn #rx"MSETG.*G3-NEQ-TEMP.*ALREADY-GASSIGNED.*3"
              (lambda () (mdl-session-call session "MSETG" atom 4)))
   (check-equal? (mdl-session-global session atom) 3))
 (lambda () (delete-directory/files root)))
(displayln "historical MSETG ERROR probe passed")
