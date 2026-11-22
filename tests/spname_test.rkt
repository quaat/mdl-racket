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
(check-equal? (run "<SPNAME NORTH>") "NORTH")
(check-exn #rx"immutable|PNAME" (lambda () (run "<SETG S <SPNAME NORTH>> <PUT ,S 1 !\\X>")))
(check-equal? (run "<SETG S <PNAME NORTH>> <PUT ,S 1 !\\X> ,S") "XORTH")
(check-exn #rx"ATOM" (lambda () (run "<SPNAME 1>")))
