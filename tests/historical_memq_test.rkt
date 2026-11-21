#lang racket/base
;; Invoke original PSETG twice after hash-verifying pinned 81prim.mud.
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
  (error 'historical-memq "pinned 81prim.mud missing; run make sources"))
(define sha-tool (find-executable-path "sha256sum"))
(unless sha-tool (error 'historical-memq "sha256sum is required"))
(define-values (proc stdout stdin stderr)
  (subprocess #f #f #f (path->string sha-tool) (path->string historical)))
(close-output-port stdin)
(define sha-output (port->string stdout))
(define sha-error (port->string stderr))
(subprocess-wait proc)
(check-equal? (subprocess-status proc) 0)
(check-equal? sha-error "")
(check-equal? (car (string-split sha-output)) expected-sha)

(define root (make-temporary-file "/tmp/mdl-memq-test~a" 'directory))
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
   (define atom (mdl-session-atom session "G3-P"))
   (check-equal? (mdl-session-call session "PSETG" atom 3) 3)
   (check-equal? (mdl-session-global session atom) 3)
   (check-equal? (mdl-list->list (mdl-session-global session "PURE-LIST"))
                 (list atom))
   (check-equal? (mdl-session-call session "PSETG" atom 4) 4)
   (check-equal? (mdl-session-global session atom) 4)
   (check-equal? (mdl-list->list (mdl-session-global session "PURE-LIST"))
                 (list atom)))
 (lambda () (delete-directory/files root)))
(displayln "historical PSETG MEMQ probe passed")
