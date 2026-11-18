#lang racket/base
;; M2 function formals: OPTIONAL/AUX/TUPLE/ARGS sections in DEFINE.
;; Reference observations: docs/evidence/M2/formals-reference.json and
;; formals-error-reference.json (pinned Confusion, 2026-11-18).
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

(define (mdl-list->racket value)
  (map (lambda (item) (if (mdl-atom? item) (mdl-atom-pname item) item))
       (mdl-list->list value)))

;; Required formals still work through the unified binder.
(check-equal? (mdl-list->racket (run "<DEFINE M2-F (A B) <LIST .A .B>> <M2-F 1 2>"))
              (list 1 2))
(check-equal? (run "<DEFINE M2-F () 7> <M2-F>") 7)

;; OPTIONAL without a default is unassigned when not supplied, but assignable.
(check-equal? (mdl-list->racket
               (run "<DEFINE M2-F (A \"OPTIONAL\" B) <SET B 3> <LIST .A .B>> <M2-F 1>"))
              (list 1 3))
(check-equal? (mdl-list->racket
               (run "<DEFINE M2-F (A \"OPTIONAL\" B) <LIST .A .B>> <M2-F 1 2>"))
              (list 1 2))
(check-exn #rx"unassigned MDL local"
           (lambda () (run "<DEFINE M2-F (A \"OPTIONAL\" B) <LIST .A .B>> <M2-F 1>")))

;; OPTIONAL defaults evaluate in the growing frame, left to right.
(check-equal? (run "<DEFINE M2-F (A \"OPTIONAL\" (B <+ .A 1>)) .B> <M2-F 5>") 6)
(check-equal? (run "<DEFINE M2-F (A \"OPTIONAL\" (B <+ .A 1>)) .B> <M2-F 5 9>") 9)
(check-equal? (mdl-list->racket
               (run "<DEFINE M2-F (\"OPTIONAL\" (A 1) (B <+ .A 1>)) <LIST .A .B>> <M2-F>"))
              (list 1 2))
(check-equal? (run "<DEFINE M2-F (A \"OPT\" (B <+ .A 1>)) .B> <M2-F 5>") 6)

;; AUX locals bind after formals; initializers see earlier bindings.
(check-equal? (run "<DEFINE M2-F (A \"AUX\" (B <+ .A 1>)) .B> <M2-F 5>") 6)
(check-equal? (run "<DEFINE M2-F (\"AUX\" B) <SET B 3> .B> <M2-F>") 3)
(check-equal? (run "<DEFINE M2-F (\"AUX\" (A 2) (B <* .A 5>)) .B> <M2-F>") 10)
(check-equal? (run "<DEFINE M2-F (\"EXTRA\" B) <SET B 3> .B> <M2-F>") 3)
(check-equal? (mdl-list->racket
               (run "<SET M2-X 1> <DEFINE M2-F (\"AUX\" (M2-X 2)) .M2-X> <LIST <M2-F> .M2-X>"))
              (list 2 1))
(check-exn #rx"unassigned MDL local"
           (lambda () (run "<DEFINE M2-F (\"AUX\" B) .B> <M2-F>")))

;; An ATOM named AUX is an ordinary required formal; only STRINGs are markers.
(check-equal? (mdl-list->racket
               (run "<DEFINE M2-F (A AUX B) <LIST .A .B>> <M2-F 1 2 3>"))
              (list 1 3))

;; TUPLE binds remaining arguments as a TUPLE-typed value.
(check-equal? (mdl-atom-pname
               (run "<DEFINE M2-F (\"TUPLE\" T) <TYPE .T>> <M2-F 1 2 3>"))
              "TUPLE")
(check-equal? (mdl-atom-pname
               (run "<DEFINE M2-F (\"TUPLE\" T) <PRIMTYPE .T>> <M2-F 1 2 3>"))
              "TUPLE")
(check-equal? (mdl-atom-pname (run "<TYPEPRIM TUPLE>")) "TUPLE")
(check-equal? (run "<DEFINE M2-F (\"TUPLE\" T) <LENGTH .T>> <M2-F 1 2 3>") 3)
(check-equal? (run "<DEFINE M2-F (\"TUPLE\" T) <LENGTH .T>> <M2-F>") 0)
(check-equal? (run "<DEFINE M2-F (\"TUPLE\" T) <NTH .T 2>> <M2-F 1 2 3>") 2)
(check-equal? (mdl-atom-pname
               (run "<DEFINE M2-F (\"TUPLE\" T) <TYPE <REST .T>>> <M2-F 1 2 3>"))
              "TUPLE")
(check-equal? (mdl-list->racket
               (run "<DEFINE M2-F (A \"TUPLE\" T \"AUX\" (B <LENGTH .T>)) <LIST .A .B>> <M2-F 9 1 2 3>"))
              (list 9 3))

;; Two separately made TUPLEs are structurally equal, never identical,
;; and a TUPLE never equals a LIST of the same content.
(check-equal? (mdl-atom-pname
               (run "<DEFINE M2-F (\"TUPLE\" T) .T> <=? <M2-F 1 2> <M2-F 1 2>>"))
              "T")
(check-true (mdl-false?
             (run "<DEFINE M2-F (\"TUPLE\" T) .T> <==? <M2-F 1 2> <M2-F 1 2>>")))
(check-true (mdl-false?
             (run "<DEFINE M2-F (\"TUPLE\" T) .T> <=? <M2-F 1 2> <LIST 1 2>>")))

;; ARGS binds the remaining arguments as a LIST.
(check-equal? (mdl-list->racket
               (run "<DEFINE M2-F (A \"ARGS\" L) <LIST .A <LENGTH .L>>> <M2-F 1 2 3>"))
              (list 1 2))
(check-equal? (mdl-list->racket
               (run "<DEFINE M2-F (A \"ARGS\" L \"AUX\" (B <LENGTH .L>)) <LIST .A .B>> <M2-F 9 1 2 3>"))
              (list 9 3))
(check-equal? (mdl-atom-pname
               (run "<DEFINE M2-F (A \"ARGS\" L) <TYPE .L>> <M2-F 1 2>"))
              "LIST")

;; Arity errors carry the historical MDL error names.
(check-exn #rx"TOO-FEW-ARGUMENTS-SUPPLIED"
           (lambda () (run "<DEFINE M2-F (A) .A> <M2-F>")))
(check-exn #rx"TOO-MANY-ARGUMENTS-SUPPLIED"
           (lambda () (run "<DEFINE M2-F (A) .A> <M2-F 1 2>")))
(check-exn #rx"TOO-MANY-ARGUMENTS-SUPPLIED"
           (lambda () (run "<DEFINE M2-F (A \"OPTIONAL\" B) <LIST .A .B>> <M2-F 1 2 3>")))
(check-exn #rx"TOO-FEW-ARGUMENTS-SUPPLIED"
           (lambda () (run "<DEFINE M2-F (A B) <LIST .A .B>> <M2-F 1>")))

;; Malformed formal lists fail at compile time (Confusion defers to call time).
(check-exn #rx"duplicate formal argument"
           (lambda () (compile-program (parse-mdl "<DEFINE M2-F (A \"OPTIONAL\" A) 1>"))))
(check-exn #rx"TUPLE"
           (lambda () (compile-program (parse-mdl "<DEFINE M2-F (\"AUX\" B \"TUPLE\" T) 1>"))))
(check-exn #rx"OPTIONAL"
           (lambda () (compile-program (parse-mdl "<DEFINE M2-F (\"AUX\" B \"OPTIONAL\" C) 1>"))))
(check-exn #rx"TUPLE"
           (lambda () (compile-program (parse-mdl "<DEFINE M2-F (\"TUPLE\" T \"TUPLE\" U) 1>"))))
(check-exn #rx"TUPLE"
           (lambda () (compile-program (parse-mdl "<DEFINE M2-F (\"TUPLE\" \"AUX\" T) 1>"))))
(check-exn #rx"2-list"
           (lambda () (compile-program (parse-mdl "<DEFINE M2-F ((A 1)) .A>"))))

;; Unsupported formal markers fail explicitly.
(check-exn #rx"activation formal"
           (lambda () (compile-program (parse-mdl "<DEFINE M2-F (\"NAME\" X) .X>"))))
(check-exn #rx"activation formal"
           (lambda () (compile-program (parse-mdl "<DEFINE M2-F (\"ACT\" X) .X>"))))
(check-exn #rx"BIND"
           (lambda () (compile-program (parse-mdl "<DEFINE M2-F (\"BIND\" X) .X>"))))
(check-exn #rx"CALL"
           (lambda () (compile-program (parse-mdl "<DEFINE M2-F (\"CALL\" X) .X>"))))
(check-exn #rx"quoted formal"
           (lambda () (compile-program (parse-mdl "<DEFINE M2-F (<QUOTE X>) .X>"))))
(check-exn #rx"unknown formal"
           (lambda () (compile-program (parse-mdl "<DEFINE M2-F (\"NOPE\" X) .X>"))))

(displayln "function formals tests passed")
