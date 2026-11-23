#lang racket/base
;; Pinned Confusion: docs/evidence/M2/indirect-apply-reference.json.
(require rackunit racket/mpair racket/string
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))
(define (render value)
  (cond [(mdl-atom? value) (mdl-atom-pname value)]
        [(or (null? value) (mpair? value))
         (format "(~a)" (string-join (map render (mdl-list->list value)) " "))]
        [else (format "~a" value)]))

;; Red before APPLY and computed-head dispatch are implemented.
(check-equal? (run "<APPLY ,+ 1 2 3>") 6)
(check-equal? (run "<APPLY <FUNCTION (X) <+ .X 1>> 4>") 5)
(check-equal? (run "<DEFINE TUP-F (\"TUPLE\" T) <LENGTH .T>> <APPLY ,TUP-F 1 2>") 2)
(check-equal? (render (run "<APPLY <FUNCTION (X) .X> '(A B)>")) "(A B)")
(check-equal? (render (run "<APPLY 1 '(A B)>")) "A")
(check-equal? (render (run "<APPLY ,MAPF ,LIST ,+ '(1 2)>")) "(1 2)")
(check-equal? (run "<SETG O 0> <APPLY <FUNCTION (X Y) ,O> <SETG O <+ <* 10 ,O> 1>> <SETG O <+ <* 10 ,O> 2>>>") 12)
(check-equal? (run "<SET F ,+> <.F 1 2>") 3)
(check-equal? (run "<SETG F ,+> <,F 2 3>") 5)
(check-equal? (run "<SETG O 0> <<PROG () <SETG O 1> ,+> <SETG O <+ <* 10 ,O> 2>> <SETG O <+ <* 10 ,O> 3>>>") 135)
(check-equal? (render (run "<1 '(A B)>")) "A")
(check-equal? (render (run "<1 '(A B) '(C D)>")) "((C D) B)")
(check-equal? (run "<SET F <FUNCTION (X) <* .X 2>>> <.F 4>") 8)
(let ([quoted (run "<SETG F <FUNCTION ('X) .X>> <,F <+ 1 2>>")])
  (check-equal? (mdl-atom-pname (mdl-type quoted)) "FORM")
  (check-equal? (mdl-atom-pname (car (form-elements quoted))) "+"))
(check-equal? (run "<DEFINE F (A) <RETURN 7 .A>> <PROG X () <APPLY ,F .X> 9>") 7)
(check-exn #rx"TOO-FEW|Too few" (lambda () (run "<APPLY>")))
(check-exn #rx"non-applicable|NON-APPLICABLE" (lambda () (run "<APPLY 'FOO 1>")))
(check-exn #rx"quoted" (lambda () (run "<APPLY <FUNCTION ('X) .X> 1>")))
(check-exn #rx"ARGS" (lambda () (run "<APPLY <FUNCTION (\"ARGS\" X) .X> 1>")))
(check-exn #rx"ARGS" (lambda () (run "<DEFINE ARGS-F (\"ARGS\" X) .X> <APPLY ,ARGS-F 1>")))
(check-exn #rx"MACRO" (lambda () (run "<DEFMAC M (X) .X> <APPLY ,M 1>")))
(check-exn #rx"non-applicable|NON-APPLICABLE" (lambda () (run "<SET F 'FOO> <.F 1>")))
(check-exn #rx"TOO-MANY|Too many" (lambda () (run "<1 '(A B) '(C D) 3>")))
(check-exn #rx"First argument to PUT must be structured"
           (lambda () (run "<SETG + 9> <+ 1 2>")))

;; The host session API also receives values, including interpreted FUNCTION
;; arguments whose structured contents must stay unevaluated.
(parameterize ([current-mdl-globals (make-hasheq)]
               [current-mdl-locals (list (make-hasheq))]
               [current-mdl-atom-space (make-mdl-atom-space)])
  (define x (mdl-atom "API-X"))
  (define f (mdl-atom "API-F"))
  (define body (mdl-make-form (mdl-list (mdl-atom "LVAL") x)))
  (mdl-define-interpreted! f (mdl-list x) (list body))
  (define embedded (mdl-make-form (mdl-list (mdl-atom "+") 1 2)))
  (define structured (mdl-list embedded))
  (check-eq? (car (mdl-list->list (mdl-apply f structured))) embedded))
