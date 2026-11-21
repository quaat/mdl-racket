#lang racket/base
;; Native observations: docs/evidence/M3/root-{reference,error-reference}.json.
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
(check-equal? (mdl-atom-pname (run "<TYPE <ROOT>>")) "OBLIST")
(check-equal? (mdl-atom-pname (run "<==? <ROOT> <MOBLIST 'ROOT>>")) "T")
(check-equal? (mdl-atom-pname (run "<==? <ROOT> <GET ROOT OBLIST>>")) "T")
(check-equal? (mdl-atom-pname (run "<==? <LOOKUP \"ROOT\" <ROOT>> 'ROOT>")) "T")
(check-true (mdl-false? (run "<LOOKUP \"COMPILE\" <ROOT>>")))
(check-exn #rx"Too many|TOO-MANY" (lambda () (run "<ROOT 1>")))
