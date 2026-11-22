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
(check-equal? (mdl-atom-pname (run "<NEWTYPE PREP ATOM> <TYPE <CHTYPE WITH PREP>>")) "PREP")
(check-equal? (mdl-atom-pname (run "<NEWTYPE PREP ATOM> <TYPE <CHTYPE <CHTYPE WITH PREP> ATOM>>")) "ATOM")
(check-exn #rx"primitive type mismatch" (lambda () (run "<NEWTYPE PREP ATOM> <CHTYPE 1 PREP>")))
