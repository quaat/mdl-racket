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
(check-equal? (mdl-false-payload (run "#FALSE (1 NIL)")) '(1 NIL))
(check-false (mdl-truthy? (run "#FALSE (1)")))
(check-true (mdl-truthy? (run "NIL")))
(check-equal? (run "NIL") 'NIL)
(check-equal? (run "<TYPE <>>") 'FALSE)
(check-equal? (run "<TYPE NIL>") 'ATOM)
(check-equal? (run "<TYPE #FALSE (1)>") 'FALSE)
(check-equal? (run "<==? <> <>>") 'T)
(check-true (mdl-false? (run "<==? #FALSE (1) #FALSE (1)>")))
(check-equal? (run "<=? #FALSE (1) #FALSE (1)>") 'T)
(check-true (mdl-truthy? (run "0")))
(check-true (mdl-truthy? (run "()")))
(check-exn #rx"host Boolean escaped" (lambda () (mdl-truthy? #f)))
(check-equal? (run "<NOT #FALSE (1)>") 'T)
(check-true (mdl-false? (run "<NOT NIL>")))
(check-equal? (mdl-false-payload (run "<AND 3 #FALSE (1) 7>")) '(1))
(check-equal? (run "<AND>") 'T)
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
(check-exn #rx"quoting this MDL form is not implemented"
           (lambda () (compile-program (parse-mdl "#FALSE (<+ 1 2>)"))))
(check-exn #rx"#FALSE requires a LIST payload"
           (lambda () (compile-program (parse-mdl "#FALSE"))))
(check-exn #rx"TYPE currently supports"
           (lambda () (run "<TYPE 7>")))
(displayln "FALSE value and truth tests passed")
