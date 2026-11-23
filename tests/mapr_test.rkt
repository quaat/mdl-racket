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
(check-equal? (run "<SETG V [1 2 3]> <MAPR <> <FUNCTION (X) <PUT .X 1 <+ <1 .X> 1>>> ,V> <2 ,V>") 3)
(check-equal? (run "<SETG L '(1 2 3)> <MAPR <> <FUNCTION (X) <PUT .X 1 <+ <1 .X> 1>>> ,L> <3 ,L>") 4)
(check-equal? (mdl-list->list (run "<MAPR ,LIST <FUNCTION (X) <1 .X>> '(3 4 5)>")) '(3 4 5))
(check-equal? (mdl-list->list (run "<MAPR ,LIST <FUNCTION (X Y) <+ <1 .X> <1 .Y>>> '(1 2 3) '(4 5)>")) '(5 7))
