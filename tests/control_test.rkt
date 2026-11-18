#lang racket/base
;; M2 control slice: function activation formals, GO, and UNWIND.
;; Reference observations: docs/evidence/M2/control-reference.json and
;; control-error-reference.json (pinned Confusion, 2026-11-18). GO has no
;; Confusion implementation; its cases follow the MDL manual, chapter 10.
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
(define (run-with-globals source globals)
  (parameterize ([current-namespace test-namespace]
                 [current-mdl-globals globals]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

(define (mdl-list->racket value)
  (map (lambda (item) (if (mdl-atom? item) (mdl-atom-pname item) item))
       (mdl-list->list value)))

;; Function activation formals: the leading ATOM form used by the 1977
;; sources binds the function's own ACTIVATION before its formals.
(check-equal? (mdl-atom-pname (run "<DEFINE M2-F M2-SELF () <TYPE .M2-SELF>> <M2-F>"))
              "ACTIVATION")
(check-equal? (mdl-atom-pname (run "<DEFINE M2-F M2-SELF () <PRIMTYPE .M2-SELF>> <M2-F>"))
              "FRAME")
(check-equal? (run "<DEFINE M2-F M2-SELF () <RETURN 7 .M2-SELF> 99> <M2-F>") 7)
(check-equal? (run "<DEFINE M2-F M2-SELF () <PROG () <RETURN 8 .M2-SELF> 99> 77> <M2-F>") 8)
(check-equal? (mdl-atom-pname
               (run "<DEFINE M2-F M2-SELF (\"AUX\" (W <TYPE .M2-SELF>)) .W> <M2-F>"))
              "ACTIVATION")
(check-equal? (run "<DEFINE M2-F M2-SELF (\"AUX\" (X <RETURN 5 .M2-SELF>)) 9> <M2-F>") 5)
(check-equal?
 (run "<DEFINE M2-H (A) <RETURN 12 .A>> <DEFINE M2-F M2-SELF () <M2-H .M2-SELF> 99> <M2-F>")
 12)

;; AGAIN to the function activation re-runs the body; formals and AUX
;; bindings are not re-bound.
(check-equal?
 (run "<SETG M2-C 0> <DEFINE M2-F M2-SELF () <SETG M2-C <+ ,M2-C 1>> <COND (<==? ,M2-C 3> <RETURN ,M2-C .M2-SELF>) (ELSE <AGAIN .M2-SELF>)>> <M2-F>")
 3)
(check-equal?
 (run "<SETG M2-C 0> <DEFINE M2-F M2-SELF (\"AUX\" (N 0)) <SET N <+ .N 1>> <COND (<==? .N 3> <RETURN .N .M2-SELF>) (ELSE <AGAIN .M2-SELF>)>> <M2-F>")
 3)

;; Activation formals combine with the formal sections and TUPLE.
(check-equal?
 (mdl-list->racket
  (run "<DEFINE M2-F M2-SELF (A \"OPTIONAL\" (B 2)) <LIST .A .B <TYPE .M2-SELF>>> <M2-F 5>"))
 (list 5 2 "ACTIVATION"))
(check-equal?
 (mdl-list->racket
  (run "<DEFINE M2-F M2-SELF (\"TUPLE\" T) <LIST <LENGTH .T> <TYPE .M2-SELF>>> <M2-F 1 2 3>"))
 (list 3 "ACTIVATION"))

;; The "ACT"/"NAME" string markers bind the same activation in formal order.
(check-equal? (run "<DEFINE M2-F (A \"ACT\" X) <RETURN 7 .X> 99> <M2-F 1>") 7)
(check-equal? (run "<DEFINE M2-F (\"AUX\" (B 1) \"NAME\" X) <RETURN 9 .X> 8> <M2-F>") 9)

;; Bare transfers never target function activations; explicit targets may.
(check-exn #rx"no active PROG"
           (lambda () (run "<DEFINE M2-F M2-SELF () <RETURN 7>> <M2-F>")))
(check-exn #rx"inactive ACTIVATION"
           (lambda ()
             (run "<DEFINE M2-F M2-SELF () <SETG M2-S .M2-SELF> 1> <M2-F> <RETURN 2 ,M2-S>")))

;; GO: top-level ATOMs in a PROG/REPEAT body are labels and are skipped in
;; normal flow; GO resumes at the expression following the label in the
;; nearest surrounding PROG or REPEAT of the current function.
(check-equal? (run "<PROG () M2-L 5>") 5)
(check-equal? (run "<PROG () <SETG M2-C 0> <GO M2-L> <SETG M2-C 9> M2-L <SETG M2-C <+ ,M2-C 1>> ,M2-C>") 1)
(check-equal?
 (run "<PROG () <SETG M2-C 0> M2-TOP <SETG M2-C <+ ,M2-C 1>> <COND (<==? ,M2-C 3> <RETURN ,M2-C>)> <GO M2-TOP>>")
 3)
(check-equal?
 (run "<PROG () <PROG () <GO M2-X> M2-X <RETURN 8>> <GO M2-Y> M2-Y <RETURN 9>>")
 9)
(check-equal? (run "<SETG M2-C 0> <REPEAT () <SETG M2-C <+ ,M2-C 1>> <COND (<==? ,M2-C 2> <RETURN ,M2-C>)> <GO M2-SKIP> M2-SKIP>") 2)
(check-exn #rx"GO label not found"
           (lambda () (run "<PROG () <GO M2-Z> 1>")))
(check-exn #rx"no active PROG"
           (lambda () (run "<GO M2-Z>")))
(check-exn #rx"no active PROG"
           (lambda ()
             (run "<DEFINE M2-H () <GO M2-X>> <PROG () M2-X <M2-H> 1>")))
(check-exn #rx"GO expects exactly one"
           (lambda () (compile-program (parse-mdl "<GO>"))))
(check-exn #rx"GO expects exactly one"
           (lambda () (compile-program (parse-mdl "<GO M2-A M2-B>"))))
;; TAG has no reference implementation; requesting one fails explicitly.
(check-exn #rx"unassigned or non-applicable"
           (lambda () (run "<PROG () <GO <TAG M2-L>> M2-L 1>")))

;; Malformed activation formals fail at compile time.
(check-exn #rx"duplicate formal argument"
           (lambda () (compile-program (parse-mdl "<DEFINE M2-F (A \"NAME\" A) 1>"))))
(check-exn #rx"ATOM formal not allowed in this section"
           (lambda () (compile-program (parse-mdl "<DEFINE M2-F (\"NAME\" X A) 1>"))))
(check-exn #rx"in wrong place"
           (lambda () (compile-program (parse-mdl "<DEFINE M2-F (\"NAME\" X \"AUX\" B) 1>"))))
(check-exn #rx"activation formal BIND"
           (lambda () (compile-program (parse-mdl "<DEFINE M2-F (\"BIND\" X) .X>"))))
(check-exn #rx"activation formal CALL"
           (lambda () (compile-program (parse-mdl "<DEFINE M2-F (\"CALL\" X) .X>"))))

;; UNWIND: value of the first expression unless a nonlocal transfer crosses
;; below it; then the cleanup runs first in the UNWIND's environment.
(check-equal? (mdl-list->racket
               (run "<SETG M2-C 0> <LIST <UNWIND 5 <SETG M2-C 1>> ,M2-C>"))
              (list 5 0))
(check-equal? (mdl-list->racket
               (run "<SETG M2-C 0> <LIST <UNWIND <PROG () <RETURN 5>> <SETG M2-C 1>> ,M2-C>"))
              (list 5 0))
(check-equal?
 (mdl-list->racket
  (run "<SETG M2-C 0> <LIST <PROG M2-OUT () <UNWIND <PROG M2-IN () <RETURN 7 .M2-OUT>> <SETG M2-C 1>> 9> ,M2-C>"))
 (list 7 1))
(check-equal?
 (run "<SETG M2-C 0> <SETG M2-D 0> <PROG M2-OUT () <SETG M2-C <+ ,M2-C 1>> <COND (<==? ,M2-C 2> <RETURN ,M2-C>)> <UNWIND <PROG M2-IN () <AGAIN .M2-OUT> 1> <SETG M2-D <+ ,M2-D 1>>>> ,M2-D")
 1)
;; The manual (chapter 16, the FLOAD example) runs the cleanup when an
;; error unwinds below UNWIND; pinned Confusion skips it, a recorded
;; reference deviation. The Racket runtime follows the manual.
(define unwind-error-globals (make-hasheq))
(define unwind-error-space (make-mdl-atom-space))
(check-exn #rx"unassigned or non-applicable"
           (lambda ()
             (parameterize ([current-namespace test-namespace]
                            [current-mdl-globals unwind-error-globals]
                            [current-mdl-locals (list (make-hasheq))]
                            [current-mdl-atom-space unwind-error-space])
               (for/fold ([result #f])
                         ([expr (in-list
                                 (compile-program
                                  (parse-mdl "<SETG M2-C 0> <UNWIND <M2-BOOM> <SETG M2-C 1>>")))])
                 (eval expr)))))
(check-equal?
 (parameterize ([current-mdl-globals unwind-error-globals]
                [current-mdl-atom-space unwind-error-space])
   (mdl-gval (mdl-atom "M2-C")))
 1)
(check-exn #rx"UNWIND expects"
           (lambda () (compile-program (parse-mdl "<UNWIND 5>"))))
(check-exn #rx"UNWIND expects"
           (lambda () (compile-program (parse-mdl "<UNWIND 1 2 3>"))))

(displayln "control flow tests passed")
