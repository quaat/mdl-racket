#lang racket/base
;; M3 issue #100: both attached Patterns for a repeated ATOM are retained.
;; Since M4 #196 attached declarations are not enforced at the call, so a
;; value violating either proceeds; the recorder still checks both
;; (tests/decl_violation_recorder_test.rkt).
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
(check-equal? (run "<DEFINE F (X) #DECL ((X) FIX (X) ANY) .X> <F \"BAD\">") "BAD")
(check-equal? (run "<DEFINE F (X) #DECL ((X) ANY (X) FIX) .X> <F 1>") 1)
(check-equal? (run "<DEFINE F (X) #DECL ((X) ANY (X) FIX) .X> <F \"BAD\">") "BAD")
(check-true (procedure?
  (run "<DEFINE F (M) #DECL ((M) <OR FALSE <PRIMTYPE VECTOR>> (M) <OR FALSE <<PRIMTYPE VECTOR> ANY ROOM>>) .M>")))
(check-exn #rx"duplicate VALUE declaration" (lambda ()
  (run "<DEFINE F () #DECL ((VALUE) FIX (VALUE) ANY) 1>")))
