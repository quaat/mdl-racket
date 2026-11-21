#lang racket/base
;; M3 issue #100: both attached Patterns for a repeated ATOM remain active.
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

(check-equal? (run "<DEFINE F (X) #DECL ((X) FIX (X) ANY) .X> <F 1>") 1)
(check-exn #rx"DECL.*X" (lambda ()
  (run "<DEFINE F (X) #DECL ((X) FIX (X) ANY) .X> <F \"BAD\">")))
(check-equal? (run "<DEFINE F (X) #DECL ((X) ANY (X) FIX) .X> <F 1>") 1)
(check-exn #rx"DECL.*X" (lambda ()
  (run "<DEFINE F (X) #DECL ((X) ANY (X) FIX) .X> <F \"BAD\">")))
(check-true (procedure?
  (run "<DEFINE F (M) #DECL ((M) <OR FALSE <PRIMTYPE VECTOR>> (M) <OR FALSE <<PRIMTYPE VECTOR> ANY ROOM>>) .M>")))
(check-exn #rx"duplicate VALUE declaration" (lambda ()
  (run "<DEFINE F () #DECL ((VALUE) FIX (VALUE) ANY) 1>")))
