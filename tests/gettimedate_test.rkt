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
(check-equal? (run "<LENGTH <GETTIMEDATE 0 T>>") 7)
(check-equal? (run "<5 <GETTIMEDATE 0 T>>") 1)
(check-equal? (run "<6 <GETTIMEDATE 0 T>>") 1970)
(check-equal? (run "<7 <GETTIMEDATE ![0 123456!] T>>") 123456)
(check-equal? (mdl-atom-pname (run "<UTYPE <GETTIMEDATE>>")) "FIX")
(check-exn #rx"time|GETTIMEDATE" (lambda () (run "<GETTIMEDATE \"bad\">")))
(check-exn #rx"too many|GETTIMEDATE" (lambda () (run "<GETTIMEDATE 0 T 1>")))
