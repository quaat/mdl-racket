#lang racket/base
;; M2 macro slice: DEFMAC, runtime macro expansion, EXPAND, FORM values,
;; and quoted formals. Reference observations:
;; docs/evidence/M2/macro-reference.json and macro-error-reference.json
;; (pinned Confusion, 2026-11-18).
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")

(define-namespace-anchor anchor)
(define test-namespace (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace test-namespace]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

;; DEFMAC stores the macro under its name and returns the name atom.
(check-equal? (mdl-atom-pname (run "<DEFMAC M2-M () <FORM + 1 2>>")) "M2-M")
(check-equal? (mdl-atom-pname (run "<DEFMAC M2-M () <FORM + 1 2>> <TYPE ,M2-M>"))
              "MACRO")
(check-equal? (mdl-atom-pname (run "<DEFMAC M2-M () <FORM + 1 2>> <PRIMTYPE ,M2-M>"))
              "LIST")
(check-equal? (mdl-atom-pname (run "<TYPEPRIM MACRO>")) "LIST")

;; A macro call expands and evaluates its result in place; a non-form
;; result evaluates to itself.
(check-equal? (run "<DEFMAC M2-M () <FORM + 1 2>> <M2-M>") 3)
(check-equal? (run "<DEFMAC M2-M () 7> <M2-M>") 7)
(check-equal? (run "<DEFMAC M2-M () <FORM DEFINE M2-F () 7>> <M2-M> <M2-F>") 7)

;; Quoted formals receive the call argument unevaluated; plain formals
;; evaluate their argument at expansion time.
(check-equal? (run "<SETG M2-C 0> <DEFMAC M2-M ('X) 0> <M2-M <SETG M2-C 1>> ,M2-C") 0)
(check-equal? (run "<SETG M2-C 0> <DEFMAC M2-M (X) 0> <M2-M <SETG M2-C 1>> ,M2-C") 1)
(check-equal? (run "<SET M2-X 3> <DEFMAC M2-M (M2-X M2-Y) .M2-Y> <M2-M 8 .M2-X>") 3)
(check-equal? (run "<SETG M2-C 0> <DEFINE M2-F ('X) 0> <M2-F <SETG M2-C 1>> ,M2-C") 0)
(check-equal? (mdl-atom-pname (run "<DEFINE M2-F ('X) <TYPE .X>> <M2-F 5>")) "FIX")

;; A leading activation is bound before quoted arguments without ending
;; their formal section. Direct and generated definitions use the same rule.
(check-equal? (run "<DEFINE M2-F M2-SELF ('X) <RETURN .X .M2-SELF>> <M2-F 7>") 7)
(check-equal? (run "<DEFMAC M2-M M2-SELF ('X) <RETURN <FORM + .X 1> .M2-SELF>> <M2-M 6>") 7)
(check-equal? (run "<DEFMAC M2-M ('D) .D> <M2-M <DEFINE M2-F M2-SELF ('X) <RETURN .X .M2-SELF>>> <M2-F 7>") 7)
(check-equal? (mdl-atom-pname
               (run "<DEFINE M2-F M2-SELF ('X \"OPTIONAL\" (Y <TYPE .M2-SELF>)) .Y> <M2-F 1>"))
              "ACTIVATION")
(check-equal? (run "<DEFINE M2-F ('X \"NAME\" M2-SELF) <RETURN .X .M2-SELF>> <M2-F 7>") 7)

;; Macros build forms from raw arguments; FORM is a first-class value.
(check-equal? (run "<SETG M2-V 3> <DEFMAC M2-M ('X) <FORM N==? <FORM GVAL .X> 4>> <COND (<M2-M M2-V> \"EQ\") (ELSE \"NE\")>")
              "EQ")
(check-equal? (run "<DEFMAC M2-M ('X) <FORM + .X 1>> <M2-M 5>") 6)
(check-equal? (run "<DEFMAC M2-M (X) <FORM + .X 1>> <M2-M 5>") 6)
(check-equal? (run "<SET M2-L 10> <DEFMAC M2-M ('X) <FORM + .X .M2-L>> <M2-M 5>") 15)
(check-equal? (mdl-atom-pname
               (run "<DEFINE M2-F ('X) <FORM + .X 1>> <TYPE <M2-F 5>>"))
              "FORM")
(check-equal? (mdl-atom-pname
               (run "<DEFINE M2-F ('X) <FORM + .X 1>> <NTH <M2-F 5> 1>"))
              "+")

;; TUPLE formals collect raw arguments; a nested macro call expands during
;; evaluation of the expansion; the "NAME" activation formal works in macros.
(check-equal? (run "<DEFMAC M2-M (\"TUPLE\" T) <FORM LENGTH .T>> <M2-M 1 2 3>") 3)
(check-equal? (run "<SETG M2-C 0> <DEFMAC M2-M (\"TUPLE\" T) 0> <M2-M <SETG M2-C 4>> ,M2-C") 4)
(check-equal? (run "<SETG M2-C 0> <DEFMAC M2-M (\"ARGS\" A) 0> <M2-M <SETG M2-C 4>> ,M2-C") 0)
(check-equal?
 (run "<DEFMAC M2-A ('X) <FORM + .X 1>> <DEFMAC M2-B ('Y) <FORM * <M2-A .Y> 2>> <M2-B 3>")
 8)
(check-equal? (run "<DEFMAC M2-M (\"NAME\" X) <RETURN 7 .X> 1> <M2-M>") 7)
(check-equal? (run "<DEFINE M2-F ('X) <PROG () 7>> <M2-F 1>") 7)
(check-equal? (run "<DEFINE M2-F ('X) <REPEAT () <RETURN 8>>> <M2-F 1>") 8)
(check-equal? (run "<DEFINE M2-F ('X) <PROG M2-SELF () <RETURN 9 .M2-SELF>>> <M2-F 1>") 9)
(check-equal? (run "<DEFINE M2-F ('X) <REPEAT M2-SELF () <RETURN 8 .M2-SELF>>> <M2-F 1>") 8)
(check-equal? (run "<DEFMAC M2-M () <FORM PROG () 7>> <M2-M>") 7)
(check-true (mdl-false? (run "<DEFMAC M2-M (\"OPTIONAL\" 'X) <FORM N==? .X 1>> <M2-M 1>")))

;; EXPAND performs one top-level macro expansion without evaluating; a
;; non-macro form is returned unchanged (pinned Confusion evaluates it
;; instead, a recorded deviation).
(check-equal? (mdl-atom-pname
               (run "<DEFMAC M2-M () <FORM + 1 2>> <NTH <EXPAND '<M2-M>> 1>"))
              "+")
(check-equal? (mdl-atom-pname
               (run "<DEFMAC M2-M () <FORM + 1 2>> <TYPE <EXPAND '<M2-M>>>"))
              "FORM")
(check-equal? (mdl-atom-pname (run "<DEFMAC M2-M () <FORM + 1 2>> <TYPE <EXPAND '<+ 1 2>>>"))
              "FORM")
(check-equal? (mdl-atom-pname (run "<TYPE <EXPAND '<M2-UNDEFINED 1>>>")) "FORM")

;; DEFMAC and quoted-formal DEFINE failures follow the reference errors.
(check-exn #rx"already bound in DEFMAC"
           (lambda () (run "<SETG M2-M 1> <DEFMAC M2-M () 1>")))
(check-exn #rx"already bound in DEFMAC"
           (lambda () (run "<DEFINE M2-M () 1> <DEFMAC M2-M () 1>")))
(check-exn #rx"First argument of DEFMAC must be an atom"
           (lambda () (run "<DEFMAC \"NOPE\" () 1>")))
(check-exn #rx"Too few args"
           (lambda () (run "<DEFMAC M2-M ('X 'Y) 1> <M2-M 1>")))
(check-exn #rx"unassigned MDL local"
           (lambda () (run "<DEFMAC M2-M (\"OPTIONAL\" 'X) <FORM N==? .X 1>> <M2-M>")))
;; APPLY itself is not implemented; calling it fails explicitly, which
;; subsumes the reference's quoted-argument APPLY restriction.
(check-exn #rx"unassigned or non-applicable"
           (lambda () (run "<DEFINE M2-F ('X) .X> <APPLY ,M2-F '(1)>")))
;; An interpreted function has its own owner; a bare RETURN cannot escape
;; the caller's PROG through a quoted-formal function call.
(check-exn #rx"no active PROG"
           (lambda () (run "<DEFINE M2-F ('X) <RETURN 7>> <PROG () <M2-F 1> 9>")))
(check-exn #rx"unsupported formal argument"
           (lambda () (run "<DEFMAC M2-M ('X 3) <FORM + .X 1>> <M2-M>")))
(check-exn #rx"quoted formal"
           (lambda () (compile-program
                        (parse-mdl "<DEFMAC M2-M (\"OPTIONAL\" ('X 3)) <FORM + .X 1>>"))))
(check-exn #rx"BAD-ARGUMENT-LIST"
           (lambda () (run "<DEFINE M2-F M2-SELF ('M2-SELF) .M2-SELF>")))

(displayln "macro expansion tests passed")
