#lang racket/base
(require rackunit racket/file racket/list
         "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt" "../mdl/loader.rkt")

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

(define source "<DEFINE F (X) #DECL ((X) FIX) .X> <F 2>")
(define decl (fourth (mdl-node-value (first (parse-mdl source)))))
(check-eq? (mdl-node-kind decl) 'decl)
(check-equal? (list (mdl-node-line decl) (mdl-node-column decl)) '(1 15))
(check-equal? (run source) 2)
(check-exn #rx"DECL.*X" (lambda () (run "<DEFINE F (X) #DECL ((X) FIX) .X> <F \"bad\">")))
(check-exn #rx"DECL.*X" (lambda () (run "<DEFINE F (X) #DECL ((X) FIX) <SET X \"bad\">> <F 1>")))
(check-equal? (run "<DEFINE F (X) #DECL ((X) FIX) <SET X 4>> <F 1>") 4)
(check-exn #rx"DECL.*VALUE" (lambda () (run "<DEFINE F () #DECL ((VALUE) FIX) \"bad\"> <F>")))
(check-exn #rx"DECL.*VALUE" (lambda () (run "<DEFINE F A () #DECL ((VALUE) FIX) <RETURN \"bad\" .A>> <F>")))
(check-equal? (run "<DEFINE F () #DECL ((VALUE) FIX) 4> <F>") 4)

(check-equal? (run "<DEFINE F (\"OPTIONAL\" (X 3)) #DECL ((X) FIX) .X> <F>") 3)
(check-exn #rx"DECL.*X" (lambda () (run "<DEFINE F (\"OPTIONAL\" (X \"bad\")) #DECL ((X) FIX) .X> <F>")))
(check-exn #rx"DECL.*X" (lambda () (run "<DEFINE F (\"AUX\" X) #DECL ((X) FIX) <SET X \"bad\">> <F>")))
(check-equal? (run "<DEFINE F (\"AUX\" X) #DECL ((X) FIX) <SET X 2>> <F>") 2)
(check-exn #rx"DECL.*X" (lambda () (run "<DEFINE F ('X) #DECL ((X) FORM) .X> <F 1>")))

(check-equal? (run "<DEFINE F (X) #DECL ((X) <OR FIX STRING>) .X> <F \"ok\">") "ok")
(check-exn #rx"DECL.*X" (lambda () (run "<DEFINE F (X) #DECL ((X) <OR FIX STRING>) .X> <F []>")))
(check-equal? (run "<DEFINE F (X) #DECL ((X) <PRIMTYPE WORD>) .X> <F 2>") 2)
(check-exn #rx"DECL.*X" (lambda () (run "<DEFINE F (X) #DECL ((X) <PRIMTYPE WORD>) .X> <F \"bad\">")))
(check-equal? (mdl-atom-pname (run "<NEWTYPE M2-DECL-T LIST> <DEFINE F (X) #DECL ((X) M2-DECL-T) .X> <TYPE <F <CHTYPE (1) M2-DECL-T>>>") ) "M2-DECL-T")

(check-equal? (run "<PROG ((X 2)) #DECL ((X VALUE) FIX) .X>") 2)
(check-exn #rx"DECL.*X" (lambda () (run "<PROG ((X 2)) #DECL ((X) FIX) <SET X \"bad\">>")))
(check-exn #rx"DECL.*VALUE" (lambda () (run "<PROG () #DECL ((VALUE) FIX) \"bad\">")))

(check-exn #rx"#DECL" (lambda () (parse-mdl "#DECL")))
(check-exn #rx"#DECL" (lambda () (parse-mdl "#DECL FIX")))
(check-exn #rx"DECL" (lambda () (run "<DEFINE F (X) #DECL ((X) <OR>) .X>")))
;; D3 (issue #48): structured <LIST ...> patterns normalize and match; the
;; remaining explicit failures cover patterns still out of scope (SPECIAL
;; wrappers here, see tests/declaration_pattern_test.rkt for the others).
(check-equal? (mdl-list->list
               (run "<DEFINE F (X) #DECL ((X) <LIST FIX>) .X> <F (1)>"))
              '(1))
(check-exn #rx"unknown declaration type UNKNOWN-TYPE"
           (lambda () (run "<DEFINE F (X) #DECL ((X) UNKNOWN-TYPE) .X> <F 1>")))
(check-equal? (run "<DEFINE F (X) #DECL ((X) <SPECIAL FIX>) .X> <F 2>") 2)

;; #DECL is a DECL-typed value in any expression position, like the
;; reference's <TYPE #DECL ((X) FIX)> probe returning DECL.
(check-equal? (mdl-atom-pname (run "<TYPE #DECL ((X) FIX)>")) "DECL")
(check-equal? (run "#DECL ((X) FIX) 5") 5)
(check-equal? (mdl-atom-pname (run "<DECL? 3 FIX>")) "T")
(check-true (mdl-false? (run "<DECL? \"x\" FIX>")))
(check-equal? (list "x" (mdl-atom-pname (second (mdl-false-payload (run "<DECL? \"x\" FIX>")))))
              (list "x" "FIX"))
(check-equal? (mdl-atom-pname (run "<DECL? \"x\" '<OR FIX STRING>>")) "T")
(check-equal? (mdl-atom-pname (run "<DECL? 3 '<PRIMTYPE WORD>>")) "T")
(check-true (mdl-false? (run "<DECL? \"x\" '<PRIMTYPE WORD>>")))
(check-equal? (mdl-atom-pname (run "<DECL? 3 ANY>")) "T")
(check-exn #rx"DECL\\?: unknown declaration type"
           (lambda () (run "<DECL? 3 NO-SUCH-TYPE>")))
(check-exn #rx"DECL\\?: unsupported declaration pattern"
           (lambda () (run "<DECL? 3 \"bad\">")))
(check-exn #rx"DECL\\?" (lambda () (run "<DECL? 3 '<OR>>")))

;; The pinned original sources contain a doubled `#DECL #DECL ((...))`
;; (77act1.mud:110); Confusion's generic #type reader treats the extra
;; #DECL as a DECL re-typing no-op, so it collapses to one declaration.
(check-equal? (run "<DEFINE F (X) #DECL #DECL ((X) FIX) .X> <F 2>") 2)
(check-exn #rx"DECL.*X"
           (lambda () (run "<DEFINE F (X) #DECL #DECL ((X) FIX) .X> <F \"bad\">")))
(check-equal? (run "#DECL #DECL ((X) FIX) 5") 5)
(check-exn #rx"#DECL" (lambda () (parse-mdl "#DECL #DECL FIX")))

;; Review-derived regressions: manifest gating, frame isolation, and macro
;; declarations. A manifest global accepts only an ==?-identical reassignment
;; unless .REDEFINE is true; MANIFEST before assignment does not make the
;; global GASSIGNED?. A function's declaration never applies to another
;; frame's bindings, and a DEFMAC's own declaration checks its bound formals.
(check-equal? (run "<SETG M 1> <MANIFEST M> <SETG M 1>") 1)
(check-exn #rx"ATTEMPT-TO-CHANGE-MANIFEST-VARIABLE M"
           (lambda () (run "<SETG M 1> <MANIFEST M> <SETG M 2>")))
(check-equal? (run "<SETG REDEFINE T> <SETG M 1> <MANIFEST M> <SETG M 2>") 2)
(check-true (mdl-false? (run "<MANIFEST U> <GASSIGNED? U>")))
(check-equal? (run "<DEFINE G (X) .X> <DEFINE F (X) #DECL ((X) FIX) <G \"str\">> <F 1>")
              "str")
(check-equal? (run "<DEFMAC ADD1M ('X) #DECL ((X) FIX) <FORM + .X 1>> <ADD1M 3>")
              4)
(check-exn #rx"DECL.*X"
           (lambda ()
             (run "<DEFMAC ADD1M ('X) #DECL ((X) FIX) <FORM + .X 1>> <ADD1M \"s\">")))
;; An inner PROG's VALUE declaration is independent of the enclosing
;; function's: the PROG accepts its result, and the function's own
;; declaration then rejects it (error position is the function's #DECL).
(check-exn #rx"DECL.*VALUE"
           (lambda ()
             (run "<DEFINE F () #DECL ((VALUE) FIX) <PROG () #DECL ((VALUE) STRING) <RETURN \"x\"> 1>> <F>")))

;; The original MSETG definition, verbatim from the pinned 81prim.mud
;; (SHA-256 8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571,
;; verified against the pinned file by tests/historical_decl_test.rkt in
;; the make test-historical suite). Installing and executing this exact
;; source text through the shared-session loader is the D1 acceptance; the
;; pinned-file load progression is asserted there, not here, because the
;; smoke suite does not provision the upstream sources.
(define msetg-source
  (string-append
   "<DEFINE MSETG (FOO BAR)\n"
   "        #DECL ((FOO) ATOM (BAR) ANY)\n"
   "        <COND (<AND <GASSIGNED? .FOO> <N=? .BAR ,.FOO>>\n"
   "               <ERROR MSETG .FOO ALREADY-GASSIGNED ,.FOO>)\n"
   "              (ELSE\n"
   "               <SETG .FOO .BAR>\n"
   "               <MANIFEST .FOO>)>>\n"))
(define original-root (make-temporary-file "/tmp/mdl-decl-test~a" 'directory))
(define original-path (build-path original-root "msetg.mud"))
(call-with-output-file original-path #:exists 'truncate/replace
  (lambda (out) (display msetg-source out)))
(define original-session (make-mdl-session original-root))
(check-equal? (hash-ref (mdl-session-load! original-session "msetg.mud") 'status)
              "PASS")
(check-exn #rx"DECL.*FOO"
           (lambda () (mdl-session-call original-session "MSETG" "bad" 3)))
(define original-atom (mdl-session-call original-session "ATOM" "M2-D1-TEMP"))
(check-equal? (mdl-atom-pname
               (mdl-session-call original-session "MSETG" original-atom 3))
              "T")
(check-equal? (mdl-session-global original-session original-atom) 3)

(displayln "declaration tests passed")
