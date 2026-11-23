#lang racket/base
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns])
    (for/fold ([value #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))
(parameterize ([current-mdl-globals (make-hasheq)]
               [current-mdl-locals (list (make-hasheq))]
               [current-mdl-atom-space (make-mdl-atom-space)])
  (check-equal? (run "<LENGTH <IVECTOR 3>>") 3)
  (check-equal? (mdl-atom-pname (run "<TYPE <1 <IVECTOR 2>>>") ) "LOSE")
  (check-equal? (run "<SETG N 0> <IVECTOR 3 '<SETG N <+ ,N 1>>> ,N") 3)
  (check-equal? (run "<SETG V <IVECTOR 2 '<REST <ISTRING 5> 5>>> <LENGTH <2 ,V>>") 0)
  (check-exn #rx"length" (lambda () (run "<IVECTOR -1>"))))
