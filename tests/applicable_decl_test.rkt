#lang racket/base
;; Issue #84: APPLICABLE as a declaration Pattern, not yet a runtime SUBR.
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

;; Manual §14.1 and the native APPLICABLE? observations identify callables.
(check-equal? (mdl-atom-pname (run "<DECL? 1 'APPLICABLE>")) "T")
(check-equal? (mdl-atom-pname (run "<DECL? -1 'APPLICABLE>")) "T")
(check-equal? (mdl-atom-pname
               (run "<DECL? <FUNCTION () 1> 'APPLICABLE>")) "T")
(check-equal? (mdl-atom-pname
               (run "<DEFMAC M3-AM () 1> <DECL? ,M3-AM 'APPLICABLE>")) "T")
(check-equal? (mdl-atom-pname (run "<DECL? ,+ 'APPLICABLE>")) "T")
(check-true (mdl-false? (run "<DECL? 'X 'APPLICABLE>")))
(check-true (mdl-false? (run "<DECL? '(1 2) 'APPLICABLE>")))

;; The original DA declaration combines APPLICABLE with ATOM and FIX.
(check-equal? (mdl-atom-pname
               (run "<DECL? 1 '<OR APPLICABLE ATOM FIX>>")) "T")
(check-equal? (mdl-atom-pname
               (run "<DECL? 'X '<OR APPLICABLE ATOM FIX>>")) "T")
(check-true (mdl-false? (run "<DECL? '(1 2) '<OR APPLICABLE ATOM FIX>>")))
(check-equal? (mdl-atom-pname
               (run "<DECL? '(1) '<LIST [REST APPLICABLE]>>")) "T")
(check-true (mdl-false?
             (run "<DECL? '(X) '<LIST [REST APPLICABLE]>>")))
(check-equal?
 (run "<DEFINE M3-DA (FN) #DECL ((FN) <OR APPLICABLE ATOM FIX>) 7> <M3-DA <FUNCTION () 1>>")
 7)
(check-equal?
 (run "<DEFINE M3-DA (FN) #DECL ((FN) <OR APPLICABLE ATOM FIX>) 7> <M3-DA 'X>")
 7)
;; a non-matching argument proceeds: attached declarations are not enforced
;; (M4 #196); DECL? above still rejects it
(check-equal?
 (run "<DEFINE M3-DA (FN) #DECL ((FN) <OR APPLICABLE ATOM FIX>) 7> <M3-DA '(1 2)>")
 7)

;; Unknown compound names remain strict errors.
(check-exn #rx"unknown declaration type M3-UNKNOWN"
           (lambda () (run "<DECL? 1 'M3-UNKNOWN>")))

(displayln "APPLICABLE declaration Pattern tests passed")
