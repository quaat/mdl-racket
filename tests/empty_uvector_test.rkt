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
(check-equal? (mdl-atom-pname (run "<UTYPE <UVECTOR>>")) "LOSE")
(check-equal? (mdl-atom-pname (run "<UTYPE '![]>")) "LOSE")
(check-equal? (mdl-atom-pname (run "<NEWTYPE ADJECTIVE ATOM> <SETG A <UVECTOR>> <CHUTYPE ,A ADJECTIVE> <UTYPE ,A>")) "ADJECTIVE")
