#lang racket/base
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")

(define-namespace-anchor anchor)
(define test-namespace (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace test-namespace]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

(check-equal? (run "<PROG () 1 2>") 2)
(check-equal? (run "<PROG ((M2-X 2) (M2-Y <+ .M2-X 3>)) .M2-Y>") 5)
(check-equal? (run "<SET M2-X 10> <PROG ((M2-X <+ .M2-X 1>)) .M2-X>") 11)
(check-equal? (run "<PROG (M2-X) <SET M2-X 4> .M2-X>") 4)
(check-equal? (run "<SET M2-X 5> <PROG ((M2-X 7)) .M2-X> .M2-X") 5)
(check-equal? (run "<PROG () <RETURN 42> 99>") 42)
(check-equal? (run "<PROG ((M2-X <RETURN 6>)) 99>") 6)
(check-equal? (mdl-atom-pname (run "<PROG () <RETURN> 99>")) "T")
(check-equal? (run "<PROG ((M2-X 1)) <PROG ((M2-X 2)) <RETURN .M2-X>> .M2-X>") 1)
(check-equal? (run "<SETG M2-G 0> <PROG () <SETG M2-G 1> <RETURN ,M2-G> <SETG M2-G 2>> ,M2-G") 1)
(check-exn #rx"unassigned MDL local" (lambda () (run "<PROG (M2-X) .M2-X>")))
(check-exn #rx"no active PROG" (lambda () (run "<RETURN 3>")))
(check-exn #rx"no active PROG"
           (lambda () (run "<DEFINE M2-H () <RETURN 7>> <PROG () <M2-H> 9>")))
(check-exn #rx"named PROG activation"
           (lambda () (compile-program (parse-mdl "<PROG ACT () 1>"))))
(check-exn #rx"explicit activation"
           (lambda () (compile-program (parse-mdl "<RETURN 1 ACT>"))))
(check-exn #rx"PROG requires an auxiliary LIST"
           (lambda () (compile-program (parse-mdl "<PROG 1 2>"))))
(check-exn #rx"PROG requires a body"
           (lambda () (compile-program (parse-mdl "<PROG ()>"))))
(check-exn #rx"duplicate PROG auxiliary binding"
           (lambda () (compile-program (parse-mdl "<PROG (M2-X M2-X) 1>"))))
(check-exn #rx"PROG auxiliary must be an ATOM or two-element LIST"
           (lambda () (compile-program (parse-mdl "<PROG ((M2-X 1 2)) 1>"))))
(displayln "scoped PROG and RETURN tests passed")
