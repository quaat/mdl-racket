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

(check-equal? (run "<REPEAT ((M2-N 0)) <SET M2-N <+ .M2-N 1>> <COND (<==? .M2-N 3> <RETURN .M2-N>)>>") 3)
(check-equal? (run "<SETG M2-I 0> <REPEAT ((M2-N <SETG M2-I <+ ,M2-I 1>>)) <SET M2-N <+ .M2-N 1>> <COND (<==? .M2-N 3> <RETURN ,M2-I>)>>") 1)
(check-equal? (run "<PROG ((M2-N 0)) <SET M2-N <+ .M2-N 1>> <COND (<==? .M2-N 3> <RETURN .M2-N>) (ELSE <AGAIN>)>>") 3)
(check-equal? (run "<REPEAT ((M2-N 0)) <SET M2-N <+ .M2-N 1>> <COND (<==? .M2-N 3> <RETURN .M2-N>) (ELSE <AGAIN>)>>") 3)
(check-equal? (run "<REPEAT ((M2-N 0)) <SET M2-N <+ .M2-N 1>> <COND (<==? .M2-N 1000> <RETURN .M2-N>)>>") 1000)
(check-equal? (run "<REPEAT ((M2-N 0)) <SET M2-N <+ .M2-N 1>> <PROG () <COND (<==? .M2-N 2> <RETURN 0>)>> <COND (<==? .M2-N 3> <RETURN .M2-N>)>>") 3)
(check-exn #rx"no active PROG or REPEAT"
           (lambda () (run "<AGAIN>")))
(check-exn #rx"no active PROG or REPEAT"
           (lambda () (run "<DEFINE M2-H () <AGAIN>> <PROG () <M2-H> 9>")))
(check-exn #rx"AGAIN with explicit activation"
           (lambda () (compile-program (parse-mdl "<AGAIN ACT>"))))
(check-exn #rx"named REPEAT activation"
           (lambda () (compile-program (parse-mdl "<REPEAT ACT () 1>"))))
(check-exn #rx"REPEAT requires a body"
           (lambda () (compile-program (parse-mdl "<REPEAT ()>"))))
(displayln "unnamed REPEAT and bare AGAIN tests passed")
