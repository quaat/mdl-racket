#lang racket/base
(require rackunit "../mdl/runtime/core.rkt")
(define (session thunk)
  (parameterize ([current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (thunk)))
(session
 (lambda ()
   (check-eq? (mdl-apply (mdl-atom "0?") 0) (mdl-atom "T"))
   (check-eq? (mdl-apply (mdl-atom "0?") 0.0) (mdl-atom "T"))
   (check-true (mdl-false? (mdl-apply (mdl-atom "0?") 1)))
   (check-eq? (mdl-apply (mdl-atom "1?") 1) (mdl-atom "T"))
   (check-eq? (mdl-apply (mdl-atom "1?") 1.0) (mdl-atom "T"))
   (check-true (mdl-false? (mdl-apply (mdl-atom "1?") 0)))
   (check-exn #rx"number|FIX|FLOAT" (lambda () (mdl-apply (mdl-atom "1?") "1")))
   (check-exn #rx"arity|argument" (lambda () (mdl-apply (mdl-atom "1?"))))))
