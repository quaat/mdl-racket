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

(check-equal? (mdl-atom-pname (run "<TYPE #LOSE 27>")) "LOSE")
(check-equal? (mdl-atom-pname (run "<PRIMTYPE #LOSE *37*>")) "WORD")
(check-equal? (run "<CHTYPE #LOSE 27 FIX>") 27)
(check-exn #rx"word|range|overflow"
           (lambda () (run "#LOSE 68719476736")))
(check-exn #rx"primitive type mismatch"
           (lambda () (run "#LOSE \"bad\"")))
