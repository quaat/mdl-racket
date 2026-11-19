#lang racket/base
(require rackunit racket/list racket/runtime-path
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
(check-exn #rx"DECL" (lambda () (run "<DEFINE F (X) #DECL ((X) <LIST FIX>) .X>")))
(check-exn #rx"DECL" (lambda () (run "<DEFINE F (X) #DECL ((X) UNKNOWN-TYPE) .X>")))
(check-exn #rx"DECL" (lambda () (run "<DEFINE F (X) 1 #DECL ((X) FIX) .X>")))

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

;; The complete original file is attempted. Its first definition is retained
;; after the later, independently reported splice failure.
(define-runtime-path repo-root "..")
(define historical-root
  (build-path repo-root ".cache" "upstream" "mdlzork" "mdlzork_771212"
              "patched_confusion"))
(define historical-session (make-mdl-session historical-root))
(define historical-report (mdl-session-load! historical-session "81prim.mud"))
(check-equal? (hash-ref historical-report 'status) "FAIL")
(check-equal? (hash-ref historical-report 'completed_expressions) 2)
(check-equal? (hash-ref (hash-ref historical-report 'failure) 'construct) "splice")
(check-exn #rx"DECL.*FOO"
           (lambda () (mdl-session-call historical-session "MSETG" "bad" 3)))
(define historical-atom (mdl-session-call historical-session "ATOM" "M2-D1-TEMP"))
(check-equal? (mdl-atom-pname
               (mdl-session-call historical-session "MSETG" historical-atom 3))
              "T")
(check-equal? (mdl-session-global historical-session historical-atom) 3)

(displayln "declaration tests passed")
