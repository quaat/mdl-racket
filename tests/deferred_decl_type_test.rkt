#lang racket/base
;; M3 issue #98: defer unresolved TYPE atom in attached #DECL, never ignore it.
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

(check-true (procedure? (run "<DEFINE F (X) #DECL ((X) PRSOBJ) .X>")))
(check-exn #rx"unknown declaration type PRSOBJ" (lambda ()
  (run "<DEFINE F (X) #DECL ((X) PRSOBJ) .X> <F 1>")))
(check-equal? (mdl-atom-pname
               (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <NEWTYPE FUTURE VECTOR> <TYPE <F <CHTYPE [] FUTURE>>>"))
              "FUTURE")
(check-equal? (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <PUT FUTURE DECL 'FIX> <F 3>") 3)
(check-equal? (run "<DEFINE F (X) #DECL ((X) <OR FIX FUTURE>) .X> <F 1>") 1)
(check-exn #rx"unknown declaration type FUTURE" (lambda ()
  (run "<DEFINE F (X) #DECL ((X) <OR FUTURE FIX>) .X> <F 1>")))
(check-true (procedure? (run "<DEFINE F (X) #DECL ((X) <VECTOR FUTURE>) .X>")))
(check-exn #rx"unknown declaration type FUTURE" (lambda ()
  (run "<DEFINE F (X) #DECL ((X) <VECTOR FUTURE>) .X> <F [1]>")))
(check-exn #rx"DECL\\?: unknown declaration type PRSOBJ" (lambda ()
  (run "<DECL? 1 'PRSOBJ>")))
(check-exn #rx"unknown declaration type PRSOBJ" (lambda ()
  (run "<DEFINE F (X) #DECL (\"VALUE\" PRSOBJ FIX) .X>")))
