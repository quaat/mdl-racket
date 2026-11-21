#lang racket/base
;; Native observations: docs/evidence/M3/andq-{reference,error-reference}.json.
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

;; Red at the unchanged original AND? expression.
(check-equal? (mdl-atom-pname (run "<AND?>")) "T")
(check-equal? (run "<AND? 1 2>") 2)
(check-equal? (run "<AND? 1 0>") 0)
(check-true (mdl-false? (run "<AND? 1 <> 3>")))
(define first-false (run "<AND? #FALSE (A) #FALSE (B) 9>"))
(check-true (mdl-false? first-false))
(check-equal? (map mdl-atom-pname (mdl-false-payload first-false)) '("A"))
(check-equal? (run "<SET X 0> <AND? <SET X 1> <> <SET X 2>> .X") 2)
(check-equal? (run "<AND? <SETG M3O1 1> <SETG M3O2 2>> ,M3O2") 2)
(check-exn #rx"ANDQ-LATE" (lambda () (run "<AND? <> <ERROR ANDQ-LATE>>")))
