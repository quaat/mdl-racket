#lang racket/base
;; ERROR interrupt boundary, issue #60. See docs/evidence/M2/ERROR.md.
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (for/fold ([result #f])
            ([expr (in-list (compile-program (parse-mdl source)))])
    (eval expr)))

(parameterize ([current-namespace ns]
               [current-mdl-globals (make-hasheq)]
               [current-mdl-locals (list (make-hasheq))]
               [current-mdl-atom-space (make-mdl-atom-space)])
  (check-exn #rx"^mdl-error: ERROR$" (lambda () (run "<ERROR>")))
  (check-exn #rx"MSETG.*G3-FOO.*ALREADY-GASSIGNED.*3"
             (lambda () (run "<ERROR MSETG G3-FOO ALREADY-GASSIGNED 3>")))
  (check-exn #rx"G3-FAIL.*1.*2"
             (lambda ()
               (run "<ERROR G3-FAIL <SETG G3-ERROR-SIDE 1> <SETG G3-ERROR-SIDE 2>>")))
  (check-equal? (mdl-gval (mdl-atom "G3-ERROR-SIDE")) 2))

(displayln "ERROR primitive tests passed")
