#lang racket/base
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")

(define-namespace-anchor anchor)
(define test-namespace (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace test-namespace]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

(check-true (mdl-false? (run "<=? 1 1.0>")))
(check-true (mdl-false? (run "<==? 1 1.0>")))
(check-equal? (mdl-atom-pname (run "<=? 10000000000 10000000000>")) "T")
(check-equal? (mdl-atom-pname (run "<==? 10000000000 10000000000>")) "T")
(check-equal? (mdl-atom-pname (run "<=? '(1 2) '(1 2)>")) "T")
(check-true (mdl-false? (run "<==? '(1 2) '(1 2)>")))
(check-equal? (mdl-atom-pname (run "<=? [1 2] [1 2]>")) "T")
(check-true (mdl-false? (run "<==? [1 2] [1 2]>")))
(check-equal? (run "<SETG M1-ORDER 0> <DEFINE M1-F (X Y) ,M1-ORDER> <M1-F <SETG M1-ORDER 1> <SETG M1-ORDER <+ ,M1-ORDER 1>>>") 2)
(displayln "integrated M1 equality and evaluation order tests passed")
