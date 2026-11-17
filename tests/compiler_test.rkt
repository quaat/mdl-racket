#lang racket/base
(require rackunit racket/runtime-path "../mdl/runtime/core.rkt"
         "../mdl/parser.rkt" "../mdl/compiler.rkt")
(define-runtime-path fixture "fixtures/basic.mdl")
(parameterize ([current-mdl-globals (make-hash)])
  (dynamic-require fixture #f)
  (check-equal? (mdl-gval "ANSWER") 42)
  (check-equal? (mdl-gval "CONDITIONAL") 42)
  (check-true (mdl-false? (mdl-gval "NIL-EXAMPLE")))
  (check-equal? (mdl-gval "FALSE-SAME") 'T))
(check-exn exn:fail?
           (lambda () (compile-program (parse-mdl "<DEFINE F (\"AUX\" X) .X>"))))
(check-exn exn:fail?
           (lambda () (compile-program (parse-mdl "#ROOM {\"WHOUS\"}"))))
(check-exn #rx"computed GVAL is not supported"
           (lambda () (compile-program (parse-mdl ",<CXFLAG .LEAVINGS>"))))
(displayln "minimal #lang mdl compilation tests passed")
