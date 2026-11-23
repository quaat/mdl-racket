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

(check-equal? (mdl-atom-pname (run "<GDECL (X) <CHANNEL FIX>>")) "T")
(check-equal? (mdl-atom-pname
               (run "<NEWTYPE CUST VECTOR> <DECL? <CHTYPE [7] CUST> '<CUST FIX>>"))
              "T")
(check-true (mdl-false?
             (run "<NEWTYPE CUST VECTOR> <DECL? [7] '<CUST FIX>>")))
(check-exn #rx"unsupported|unknown|structured"
           (lambda () (run "<GDECL (X) <UNREGISTERED FIX>>")))
