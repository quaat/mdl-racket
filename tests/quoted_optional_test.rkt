#lang racket/base
;; Issue #82: quoted OPTIONAL defaults, compared with pinned Confusion.
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

;; The omitted default is evaluated in the callee frame; an explicit
;; argument is bound raw, without evaluating the argument or the default.
(check-equal? (mdl-atom-pname
               (run "<DEFINE M3Q (\"OPTIONAL\" ('X 'A)) .X> <M3Q>"))
              "A")
(check-equal? (mdl-atom-pname
               (run "<DEFINE M3Q (\"OPTIONAL\" ('X 'A)) <TYPE .X>> <M3Q <ERROR NO-EVAL>>"))
              "FORM")
(check-equal? (run "<DEFINE M3Q (\"OPTIONAL\" ('X <SETG M3FLAG 1>)) .X> <M3Q> ,M3FLAG") 1)
(check-equal? (run "<SETG M3FLAG 0> <DEFINE M3Q (\"OPTIONAL\" ('X <SETG M3FLAG 1>)) .X> <M3Q 9> ,M3FLAG") 0)
(check-equal? (run "<DEFINE M3Q (A \"OPTIONAL\" ('X .A)) .X> <M3Q 7>") 7)
(check-equal? (mdl-atom-pname
               (run "<SETG WINNER 4> <DEFINE M3Q (\"OPTIONAL\" ('X ',WINNER)) <TYPE .X>> <M3Q>"))
              "FORM")

;; The same syntax is needed for source macros and must preserve the
;; raw argument and the default expression's evaluation timing.
(check-equal? (mdl-atom-pname
               (run "<DEFMAC M3M (\"OPTIONAL\" ('X 'A)) <FORM QUOTE .X>> <M3M>"))
              "A")
(check-equal? (run "<SETG M3FLAG 0> <DEFMAC M3M (\"OPTIONAL\" ('X <SETG M3FLAG 1>)) 7> <M3M 9> ,M3FLAG") 0)

;; Strict formal validation is retained.
(check-exn #rx"quoted formal must name an ATOM"
           (lambda () (compile-program
                       (parse-mdl "<DEFINE M3Q (\"OPTIONAL\" ('(X) 1)) 0>"))))
(check-exn #rx"duplicate formal argument"
           (lambda () (compile-program
                       (parse-mdl "<DEFINE M3Q (X \"OPTIONAL\" ('X 1)) 0>"))))
(check-exn #rx"2-list defaults"
           (lambda () (compile-program
                       (parse-mdl "<DEFINE M3Q (('X 1)) 0>"))))

(displayln "quoted OPTIONAL default tests passed")
