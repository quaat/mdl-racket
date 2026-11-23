#lang racket/base
;; Pinned Confusion: docs/evidence/M2/typeq-reference.json.
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
(check-equal? (mdl-atom-pname (run "<TYPE? 'A ATOM>")) "ATOM")
(check-true (mdl-false? (run "<TYPE? 'A FIX>")))
(check-equal? (mdl-atom-pname (run "<TYPE? 3 ATOM FIX>")) "FIX")
(check-equal? (mdl-atom-pname (run "<TYPE? <> FALSE>")) "FALSE")
(check-true (mdl-false? (run "<TYPE? 3>")))
(check-true (mdl-false? (run "<TYPE? 3 4>")))
(check-true (mdl-false? (run "<TYPE? 3 XYZZY-TYPE>")))
(check-equal?
 (mdl-atom-pname (run "<NEWTYPE TQTEST VECTOR> <TYPE? <CHTYPE '[1] TQTEST> TQTEST>"))
 "TQTEST")
(check-exn #rx"Not enough|TOO-FEW" (lambda () (run "<TYPE?>")))
