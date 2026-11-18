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

(check-equal? (mdl-atom-pname (run "<PROG M2-ACT () <TYPE .M2-ACT>>")) "ACTIVATION")
(check-equal? (mdl-atom-pname (run "<PROG M2-ACT ((M2-X <TYPE .M2-ACT>)) .M2-X>")) "ACTIVATION")
(check-equal? (mdl-atom-pname (run "<PROG M2-ACT () <PRIMTYPE .M2-ACT>>")) "FRAME")
(check-equal? (mdl-atom-pname (run "<TYPEPRIM ACTIVATION>")) "FRAME")
(check-equal? (run "<PROG M2-ACT () <RETURN 7 .M2-ACT> 99>") 7)
(check-equal? (run "<PROG M2-OUT () <PROG M2-IN () <RETURN 8 .M2-OUT>> 99>") 8)
(check-equal? (run "<SETG M2-C 0> <PROG M2-ACT () <SETG M2-C <+ ,M2-C 1>> <COND (<==? ,M2-C 3> <RETURN ,M2-C .M2-ACT>) (ELSE <AGAIN .M2-ACT>)>>") 3)
(check-equal? (run "<REPEAT M2-ACT ((M2-N 0)) <SET M2-N <+ .M2-N 1>> <COND (<==? .M2-N 3> <RETURN .M2-N .M2-ACT>)>>") 3)
(check-equal? (run "<DEFINE M2-H (A) <RETURN 12 .A>> <PROG M2-ACT () <M2-H .M2-ACT> 99>") 12)
(check-equal? (run "<SETG M2-C 0> <DEFINE M2-H (A) <AGAIN .A>> <PROG M2-ACT () <SETG M2-C <+ ,M2-C 1>> <COND (<==? ,M2-C 3> <RETURN ,M2-C>) (ELSE <M2-H .M2-ACT>)>>") 3)
(check-equal? (run "<SETG M2-C 0> <PROG M2-OUT () <SETG M2-C <+ ,M2-C 1>> <PROG M2-IN () <COND (<==? ,M2-C 3> <RETURN ,M2-C .M2-OUT>) (ELSE <AGAIN .M2-OUT>)>>>") 3)
(check-equal? (run "<SET M2-ACT 4> <PROG M2-ACT () <TYPE .M2-ACT>> .M2-ACT") 4)
(check-exn #rx"expected ACTIVATION"
           (lambda () (run "<PROG M2-ACT () <RETURN 7 1>>")))
(check-exn #rx"expected ACTIVATION"
           (lambda () (run "<PROG M2-ACT () <AGAIN 1>>")))
(check-exn #rx"inactive ACTIVATION"
           (lambda () (run "<SETG M2-S #FALSE ()> <PROG M2-ACT () <SETG M2-S .M2-ACT> 1> <RETURN 2 ,M2-S>")))
(check-exn #rx"inactive ACTIVATION"
           (lambda () (run "<SETG M2-S #FALSE ()> <PROG M2-ACT () <SETG M2-S .M2-ACT> 1> <AGAIN ,M2-S>")))
(displayln "named activation and explicit target tests passed")
