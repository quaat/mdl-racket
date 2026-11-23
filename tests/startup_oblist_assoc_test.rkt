#lang racket/base
;; Pinned Confusion: docs/evidence/M2/get-initial-oblist-reference.json.
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
(check-true (mdl-oblist? (run "<GET INITIAL OBLIST>")))
(check-true (mdl-oblist? (run "<GET ROOT OBLIST>")))
(check-true (mdl-false? (run "<GET FOO OBLIST>")))
(check-true (mdl-false? (run "<LOOKUP \"GROUP-GLUE\" <GET INITIAL OBLIST>>")))
