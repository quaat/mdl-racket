#lang racket/base
;; Review R1 x R3/R4 (f): the unchanged original START prints through the
;; session's injected OUTCHAN port, nothing reaches the process port.
;; Needs the pinned source (.cache/upstream); run by `make test-historical`,
;; not by the smoke suite. Run from the repository root.
(require rackunit racket/runtime-path racket/string "../mdl/loader.rkt")

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")

(define session-out (open-output-string))
(define stray (open-output-string))
(define session (make-mdl-session source-root #:output-port session-out))
(define load-result
  (parameterize ([current-output-port stray])
    (mdl-session-load! session "77loadall.mud")))
(check-equal? (hash-ref load-result 'status) "PASS")
(check-equal? (hash-ref load-result 'completed_expressions) 1229)
;; START currently stops at a later, separately tracked frontier (RANDOM at
;; this base); the assertion here is only about where its output goes.
(define start-outcome
  (parameterize ([current-output-port stray])
    (with-handlers ([exn:fail? exn-message])
      (mdl-session-call session "START" "WHOUS" "")
      'returned)))
(define output (get-output-string session-out))
(check-true (string-prefix? output "81prim.mud loaded\n"))
(check-true (string-contains? output "77dung.mud loaded\n"))
(check-true (string-contains? output "Welcome to Dungeon."))
(check-equal? (get-output-string stray) "")
(printf "historical START channel routing passed: ~a output chars; START outcome: ~a\n"
        (string-length output) start-outcome)
