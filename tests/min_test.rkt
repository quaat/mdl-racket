#lang racket/base
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([value #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))
(check-equal? (run "<CHTYPE <MIN> FIX>") 34359738367)
(check-equal? (run "<MIN 4 2 3>") 2)
(check-equal? (run "<MIN 4 2.0>") 2.0)
(check-equal? (run "<MIN -3 -2>") -3)
(check-exn #rx"number|FIX|FLOAT" (lambda () (run "<MIN A>")))
