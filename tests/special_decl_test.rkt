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

(check-equal? (run "<DEFINE F (X) #DECL ((X) <SPECIAL FIX>) .X> <F 7>") 7)
(check-equal? (run "<DEFINE F (X) #DECL ((X) <UNSPECIAL STRING>) .X> <F \"ok\">") "ok")
;; not enforced at the call since M4 #196 (attached declarations)
(check-equal? (run "<DEFINE F (X) #DECL ((X) <SPECIAL FIX>) .X> <F \"bad\">") "bad")
(check-exn #rx"SPECIAL.*one|SPECIAL.*Pattern|unsupported"
           (lambda () (run "<DEFINE F (X) #DECL ((X) <SPECIAL>) .X>")))
(check-exn #rx"SPECIAL.*one|SPECIAL.*Pattern|unsupported"
           (lambda () (run "<DEFINE F (X) #DECL ((X) <SPECIAL FIX STRING>) .X>")))
(check-exn #rx"unsupported"
           (lambda () (run "<DEFINE F (X) #DECL ((X) <OR <SPECIAL FIX> STRING>) .X>")))
(check-exn #rx"unsupported"
           (lambda () (run "<DECL? 3 '<SPECIAL FIX>>")))
