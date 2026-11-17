#lang racket/base
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")

(define-namespace-anchor anchor)
(define test-namespace (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace test-namespace]
                 [current-mdl-globals (make-hash)])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

(check-true (mdl-false? (run "<>")))
(check-equal? (mdl-false-payload (run "<>")) '())
(check-equal? (car (mdl-false-payload (run "#FALSE (1 NIL)"))) 1)
(check-eq? (cadr (mdl-false-payload (run "#FALSE (1 NIL)"))) (mdl-atom "NIL"))
(check-false (mdl-truthy? (run "#FALSE (1)")))
(check-true (mdl-truthy? (run "NIL")))
(check-eq? (run "NIL") (mdl-atom "NIL"))
(check-eq? (run "<TYPE <>>") (mdl-atom "FALSE"))
(check-eq? (run "<TYPE NIL>") (mdl-atom "ATOM"))
(check-eq? (run "<TYPE #FALSE (1)>") (mdl-atom "FALSE"))
(check-eq? (run "<==? <> <>>") (mdl-atom "T"))
(check-true (mdl-false? (run "<==? #FALSE (1) #FALSE (1)>")))
(check-eq? (run "<=? #FALSE (1) #FALSE (1)>") (mdl-atom "T"))
(check-eq? (run "<DEFINE F () #FALSE (1)> <==? <F> <F>>") (mdl-atom "T"))
(check-true (mdl-false?
             (run "<DEFINE G () <==? #FALSE (1) #FALSE (1)>> <G>")))
(check-eq? (run "<DEFINE H () <COND (T #FALSE (1))>> <==? <H> <H>>") (mdl-atom "T"))
(check-true (mdl-truthy? (run "0")))
(check-true (mdl-truthy? (run "()")))
(check-exn #rx"host Boolean escaped" (lambda () (mdl-truthy? #f)))
(check-eq? (run "<NOT #FALSE (1)>") (mdl-atom "T"))
(check-true (mdl-false? (run "<NOT NIL>")))
(check-equal? (mdl-false-payload (run "<AND 3 #FALSE (1) 7>")) '(1))
(check-eq? (run "<AND>") (mdl-atom "T"))
(check-equal? (mdl-false-payload (run "<OR #FALSE (1) #FALSE (2)>")) '(2))
(check-true (mdl-false? (run "<OR>")))
(check-equal? (mdl-false-payload
               (run "<COND (#FALSE (1) 7) (#FALSE (2) 8)>")) '(2))
(check-equal? (run "<COND (7) (T 8)>") 7)
(check-equal? (run "<SETG X 0> <AND #FALSE (1) <SETG X 1>> ,X") 0)
(check-equal? (run "<SETG X 0> <OR 7 <SETG X 1>> ,X") 0)
(check-equal? (run "<SETG X 0> <COND (7) (T <SETG X 1>)> ,X") 0)
(check-exn #rx"COND requires at least one clause"
           (lambda () (compile-program (parse-mdl "<COND>"))))
(check-exn #rx"this MDL data construct is not implemented"
           (lambda () (compile-program (parse-mdl "#FALSE (<+ 1 2>)"))))
(check-exn #rx"#FALSE requires a LIST payload"
           (lambda () (compile-program (parse-mdl "#FALSE"))))
(check-eq? (run "<TYPE 7>") (mdl-atom "FIX"))
(displayln "FALSE value and truth tests passed")
