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
(check-equal? (mdl-node-kind (car (parse-mdl "#NEXIT \"Blocked\""))) 'typed)
(check-equal? (mdl-atom-pname (run "<NEWTYPE NEXIT STRING> <TYPE #NEXIT \"Blocked\">")) "NEXIT")
(check-equal? (run "<NEWTYPE NEXIT STRING> <CHTYPE #NEXIT \"Blocked\" STRING>") "Blocked")
(check-exn #rx"unknown MDL TYPE" (lambda () (run "#NEXIT \"Blocked\"")))
(check-exn #rx"primitive type mismatch" (lambda () (run "<NEWTYPE NEXIT WORD> #NEXIT \"Blocked\"")))
