#lang racket/base
;; Issue #86: the side-effect-free %<> reader macro value.
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

(check-equal? (mdl-atom-pname (run "<TYPE %<>>")) "FALSE")
(check-equal? (mdl-atom-pname (run "<NOT %<>>")) "T")
(check-equal? (mdl-atom-pname (run "<==? %<> %<>>")) "T")
(check-equal? (mdl-atom-pname
               (run "<DEFINE M3P () %<>> <TYPE <M3P>>")) "FALSE")
(check-equal? (mdl-atom-pname
               (run "<DEFINE M3P () %<>> <==? <M3P> <M3P>>")) "T")
(check-equal? (mdl-atom-pname
               (run "<DEFINE M3P () <LIST %<>>> <TYPE <1 <M3P>>>")) "FALSE")

;; The general reader macro remains a separate slice and must fail.
(check-exn #rx"unsupported percent reader macro"
           (lambda () (run "%<+ 1 2>")))
(check-exn #rx"unsupported percent reader macro"
           (lambda () (run "%,X")))

(displayln "percent empty-FORM reader macro tests passed")
