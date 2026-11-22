#lang racket/base
(require rackunit "../mdl/runtime/core.rkt")
(define (session thunk)
  (parameterize ([current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (thunk)))
(session
 (lambda ()
   (check-eq? (mdl-apply "0?" 0) (mdl-atom "T"))
   (check-eq? (mdl-apply "0?" 0.0) (mdl-atom "T"))
   (check-true (mdl-false? (mdl-apply "0?" 1)))
   (check-eq? (mdl-apply "1?" 1) (mdl-atom "T"))
   (check-eq? (mdl-apply "1?" 1.0) (mdl-atom "T"))
   (check-true (mdl-false? (mdl-apply "1?" 0)))
   (check-exn #rx"number|FIX|FLOAT" (lambda () (mdl-apply "1?" "1")))
   (check-exn #rx"arity|argument" (lambda () (mdl-apply "1?")))))
