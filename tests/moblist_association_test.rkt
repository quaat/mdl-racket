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
  (define oblist (run "<MOBLIST FLAG>"))
  (check-eq? (run "<GET FLAG OBLIST>") oblist)
  (check-eq? (run "<MOBLIST FLAG>") oblist)
  (check-eq? (run "<GET <MOBLIST FLAG> OBLIST>") (mdl-atom "FLAG")))
