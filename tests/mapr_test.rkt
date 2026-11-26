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
;; #113 R9: MAPSTOP, MAPLEAVE and MAPRET inside MAPR, the exact expressions of
;; docs/evidence/M3/review/r9-mapr-cases.json; pinned Confusion gives (1 99),
;; 42 and (1 1 2 2 3 3) (r9-mapr-reference.json).
(check-equal? (mdl-list->list (run "<MAPR ,LIST <FUNCTION (X) <COND (<==? <1 .X> 2> <MAPSTOP 99>) (T <1 .X>)>> '(1 2 3)>")) '(1 99))
(check-equal? (run "<MAPR ,LIST <FUNCTION (X) <COND (<==? <1 .X> 2> <MAPLEAVE 42>) (T <1 .X>)>> '(1 2 3)>") 42)
(check-equal? (mdl-list->list (run "<MAPR ,LIST <FUNCTION (X) <MAPRET <1 .X> <1 .X>>> '(1 2 3)>")) '(1 1 2 2 3 3))
