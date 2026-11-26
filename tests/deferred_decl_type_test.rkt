#lang racket/base
;; M3 issue #98: defer unresolved TYPE atom in attached #DECL, never ignore it
;; at definition time.
;; M4 issue #193 (INV-11; amendment to the #98 ADR, maintainer decision
;; 2026-11-25): an attached declaration's TYPE name that is STILL undefined
;; when checked (no registered TYPE, no DECL association) is not enforced at
;; that position, matching pinned Confusion. A name defined later is checked
;; strictly; DECL?, positional declarations, GDECL and every known type stay
;; strict (docs/SEMANTICS.md, DECISIONS.md).
;; M4 issue #196 (INV-12; the next amendment, maintainer decision 2026-11-26):
;; attached declarations are not enforced at all in production. The #193
;; rules now define what the test-only recorder evaluates. So the cases
;; below run in production (the call proceeds with its value) and with a
;; recorder (`recorded`: the bindings reported as would-be violations,
;; exactly the cases that raised "does not satisfy declaration" before #196).
;; The old assertions are listed in docs/evidence/M4/S16-ATTACHED-DECL.md.
(require (rename-in rackunit [check-equal? rk:check-equal?] [check-true rk:check-true])
         "../mdl/parser.rkt" "../mdl/compiler.rkt"
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
(define (pname v) (mdl-atom-pname v))
;; The bindings the test-only recorder reports for SOURCE (oldest first).
(define (recorded source)
  (define infos '())
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space
                  (make-mdl-atom-space
                   #:decl-violation-recorder (lambda (i) (set! infos (cons i infos))))])
    (for ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr)))
  (map (lambda (i) (hash-ref i 'binding)) (reverse infos)))
;; An unexpected exception while evaluating a checked value becomes that
;; check's failing actual value (so one run reports every failing check).
(define-syntax-rule (guard e)
  (with-handlers ([exn:fail? (lambda (x) (list 'raised (exn-message x)))]) e))
(define-syntax-rule (check-equal? actual expected) (rk:check-equal? (guard actual) expected))
(define-syntax-rule (check-true actual) (rk:check-true (guard actual)))
;; A former strict failure (#193 rules): production proceeds with ACTUAL's
;; value; the recorder reports BINDINGS.
(define-syntax-rule (check-violation source actual expected bindings)
  (begin (check-equal? actual expected)
         (check-equal? (recorded source) bindings)))
;; A case the #193 rules accept: the recorder reports nothing.
(define-syntax-rule (check-accepted source)
  (check-equal? (recorded source) '()))

;; --- definition (issue #98, unchanged) ---------------------------------------
(check-true (procedure? (run "<DEFINE F (X) #DECL ((X) PRSOBJ) .X>")))
(check-true (procedure? (run "<DEFINE F (X) #DECL ((X) <VECTOR FUTURE>) .X>")))

;; --- still undefined at the check: any value (#193) --------------------------
(define f-prsobj "<DEFINE F (X) #DECL ((X) PRSOBJ) .X> ")
(check-equal? (run (string-append f-prsobj "<F 1>")) 1)
(check-accepted (string-append f-prsobj "<F 1>"))
(check-true (mdl-false? (run (string-append f-prsobj "<F <>>"))))
(check-accepted (string-append f-prsobj "<F <>>"))
(check-equal? (pname (run (string-append f-prsobj "<F 'NORTH>"))) "NORTH")
(check-equal? (run (string-append f-prsobj "<F \"s\">")) "s")
;; an OBJECT-like structure (OBJECT is a NEWTYPE of VECTOR here; PRSOBJ is not)
(check-equal? (pname (run (string-append "<NEWTYPE OBJECT VECTOR> " f-prsobj
                                         "<TYPE <F <CHTYPE [1 2] OBJECT>>>")))
              "OBJECT")
;; MAINT-ROOM's shape (77act1.mud:737-741): an AUX bound to a FALSE or an
;; OBJECT, beside known-type declarations that stay checked.
(define maint
  (string-append
   "<NEWTYPE OBJECT VECTOR> "
   "<DEFINE M (PV \"AUX\" (PRSO <2 .PV>) (HACK 1)) "
   "#DECL ((PV) VECTOR (PRSO) PRSOBJ (HACK) FIX) <SET HACK <+ .HACK 1>> .PRSO> "))
(check-true (mdl-false? (run (string-append maint "<M [1 <>]>"))))
(check-equal? (pname (run (string-append maint "<TYPE <M [1 <CHTYPE [] OBJECT>]>>"))) "OBJECT")
(check-violation (string-append maint "<M (1 2)>")
                 (run (string-append maint "<M (1 2)>")) 2 '("PV"))
;; SET of a declared local and the VALUE result
(check-equal? (run "<DEFINE F (X) #DECL ((X) PRSOBJ) <SET X \"t\"> .X> <F 1>") "t")
(check-accepted "<DEFINE F (X) #DECL ((X) PRSOBJ) <SET X \"t\"> .X> <F 1>")
(check-equal? (run "<DEFINE F (X) #DECL ((VALUE) PRSOBJ (X) FIX) .X> <F 1>") 1)
(check-violation "<DEFINE F (X) #DECL ((VALUE) PRSOBJ (X) FIX) .X> <F <>>"
                 (mdl-false? (run "<DEFINE F (X) #DECL ((VALUE) PRSOBJ (X) FIX) .X> <F <>>")) #t '("X"))

;; --- nested undefined names: that position only -------------------------------
(check-equal? (run "<DEFINE F (X) #DECL ((X) <OR FUTURE FIX>) .X> <F 1>") 1)
(check-equal? (run "<DEFINE F (X) #DECL ((X) <OR FIX FUTURE>) .X> <F \"s\">") "s")
(check-accepted "<DEFINE F (X) #DECL ((X) <OR FIX FUTURE>) .X> <F \"s\">")
(check-equal? (run "<DEFINE F (X) #DECL ((X) <VECTOR FUTURE>) .X> <1 <F [\"s\"]>>") "s")
(check-equal? (run "<DEFINE F (X) #DECL ((X) <LIST FUTURE FIX>) <2 .X>> <F (<> 2)>") 2)
(check-accepted "<DEFINE F (X) #DECL ((X) <LIST FUTURE FIX>) <2 .X>> <F (<> 2)>")
(check-violation "<DEFINE F (X) #DECL ((X) <LIST FUTURE FIX>) .X> <LENGTH <F (<> \"s\")>>"   ; FIX element: a violation (recorder)
                 (run "<DEFINE F (X) #DECL ((X) <LIST FUTURE FIX>) .X> <LENGTH <F (<> \"s\")>>") 2 '("X"))
(check-violation "<DEFINE F (X) #DECL ((X) <LIST FUTURE FIX>) .X> <LENGTH <F [1 2]>>"   ; structure TYPE: a violation (recorder)
                 (run "<DEFINE F (X) #DECL ((X) <LIST FUTURE FIX>) .X> <LENGTH <F [1 2]>>") 2 '("X"))
(check-violation "<DEFINE F (X) #DECL ((X) <LIST FUTURE FIX>) .X> <LENGTH <F (1)>>"   ; required length: a violation (recorder)
                 (run "<DEFINE F (X) #DECL ((X) <LIST FUTURE FIX>) .X> <LENGTH <F (1)>>") 1 '("X"))
(check-equal? (run "<DEFINE F (X) #DECL ((X) <LIST [REST FUTURE]>) <LENGTH .X>> <F (1 \"s\" <>)>") 3)
(check-equal? (run "<DEFINE F (X) #DECL ((X) <LIST [REST FIX FUTURE]>) <LENGTH .X>> <F (1 \"s\" 2 A)>") 4)
(check-accepted "<DEFINE F (X) #DECL ((X) <LIST [REST FIX FUTURE]>) <LENGTH .X>> <F (1 \"s\" 2 A)>")
(check-violation "<DEFINE F (X) #DECL ((X) <LIST [REST FIX FUTURE]>) .X> <LENGTH <F (1 \"s\" B A)>>"   ; REST's FIX: a violation (recorder)
                 (run "<DEFINE F (X) #DECL ((X) <LIST [REST FIX FUTURE]>) .X> <LENGTH <F (1 \"s\" B A)>>") 4 '("X"))
(check-equal? (run "<DEFINE F (X) #DECL ((X) <VECTOR [2 FUTURE]>) <LENGTH .X>> <F [A \"b\"]>") 2)

;; --- defined later by NEWTYPE: checked as that TYPE (recorder) -----------------
(check-equal? (pname
               (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <NEWTYPE FUTURE VECTOR> <TYPE <F <CHTYPE [] FUTURE>>>"))
              "FUTURE")
(check-violation "<DEFINE F (X) #DECL ((X) FUTURE) .X> <NEWTYPE FUTURE VECTOR> <F 1>"
                 (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <NEWTYPE FUTURE VECTOR> <F 1>") 1 '("X"))
(check-violation "<DEFINE F (X) #DECL ((X) FUTURE) .X> <NEWTYPE FUTURE VECTOR> <F <>>"
                 (mdl-false? (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <NEWTYPE FUTURE VECTOR> <F <>>")) #t '("X"))
;; the same function, called before and after the NEWTYPE
(check-violation "<DEFINE F (X) #DECL ((X) FUTURE) .X> <F 1> <NEWTYPE FUTURE VECTOR> <F 2>"
                 (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <F 1> <NEWTYPE FUTURE VECTOR> <F 2>") 2 '("X"))
(check-equal? (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <F 1> <NEWTYPE FUTURE VECTOR> <F <CHTYPE [] FUTURE>> 9") 9)
(check-accepted "<DEFINE F (X) #DECL ((X) FUTURE) .X> <F 1> <NEWTYPE FUTURE VECTOR> <F <CHTYPE [] FUTURE>> 9")
;; nested, defined later
(check-violation "<DEFINE F (X) #DECL ((X) <OR FUTURE FIX>) .X> <NEWTYPE FUTURE VECTOR> <F \"s\">"
                 (run "<DEFINE F (X) #DECL ((X) <OR FUTURE FIX>) .X> <NEWTYPE FUTURE VECTOR> <F \"s\">") "s" '("X"))
(check-equal? (run "<DEFINE F (X) #DECL ((X) <OR FUTURE FIX>) .X> <NEWTYPE FUTURE VECTOR> <F 1>") 1)
(check-violation "<DEFINE F (X) #DECL ((X) <VECTOR FUTURE>) .X> <NEWTYPE FUTURE VECTOR> <LENGTH <F [1]>>"
                 (run "<DEFINE F (X) #DECL ((X) <VECTOR FUTURE>) .X> <NEWTYPE FUTURE VECTOR> <LENGTH <F [1]>>") 1 '("X"))
(check-violation "<DEFINE F (X) #DECL ((X) <LIST [REST FUTURE]>) .X> <NEWTYPE FUTURE VECTOR> <LENGTH <F (1)>>"
                 (run "<DEFINE F (X) #DECL ((X) <LIST [REST FUTURE]>) .X> <NEWTYPE FUTURE VECTOR> <LENGTH <F (1)>>") 1 '("X"))

;; --- defined later by a DECL association: checked as that Pattern (recorder) ---
(check-equal? (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <PUT FUTURE DECL 'FIX> <F 3>") 3)
(check-violation "<DEFINE F (X) #DECL ((X) FUTURE) .X> <PUT FUTURE DECL 'FIX> <F \"s\">"
                 (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <PUT FUTURE DECL 'FIX> <F \"s\">") "s" '("X"))
(check-true (mdl-false?
             (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <PUT FUTURE DECL '<OR FIX FALSE>> <F <>>")))
(check-violation "<DEFINE F (X) #DECL ((X) FUTURE) .X> <PUT FUTURE DECL '<OR FIX FALSE>> <F A>"
                 (pname (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <PUT FUTURE DECL '<OR FIX FALSE>> <F A>")) "A" '("X"))
(check-violation "<DEFINE F (X) #DECL ((X) <LIST FUTURE>) .X> <PUT FUTURE DECL 'FIX> <LENGTH <F (A)>>"
                 (run "<DEFINE F (X) #DECL ((X) <LIST FUTURE>) .X> <PUT FUTURE DECL 'FIX> <LENGTH <F (A)>>") 1 '("X"))
;; The order of definition matters for an association's own target
;; (independent review): an association that already exists when the
;; function is defined is followed with the attached deferral, so an unknown
;; name inside it is retained and, while still undefined, matches any value;
;; once defined it is strict.
(check-equal? (run "<PUT ALIAS DECL '<OR BAR FIX>> <DEFINE F (X) #DECL ((X) ALIAS) .X> <F 1.5>") 1.5)
(check-accepted "<PUT ALIAS DECL '<OR BAR FIX>> <DEFINE F (X) #DECL ((X) ALIAS) .X> <F 1.5>")
(check-equal? (run "<PUT ALIAS DECL '<OR BAR FIX>> <DEFINE F (X) #DECL ((X) ALIAS) .X> <F 7>") 7)
(check-violation "<PUT ALIAS DECL '<OR BAR FIX>> <DEFINE F (X) #DECL ((X) ALIAS) .X> <NEWTYPE BAR LIST> <F 1.5>"
                 (run "<PUT ALIAS DECL '<OR BAR FIX>> <DEFINE F (X) #DECL ((X) ALIAS) .X> <NEWTYPE BAR LIST> <F 1.5>") 1.5 '("X"))
;; ...whereas an association added after the definition is normalized
;; strictly at the check: an unknown target there is a strict error where the
;; check is evaluated (the recorder); production evaluates no check (#196).
(check-equal? (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <PUT FUTURE DECL 'NOWHERE> <F 1>") 1)
(check-exn #rx"unknown declaration type NOWHERE"
           (lambda () (recorded "<DEFINE F (X) #DECL ((X) FUTURE) .X> <PUT FUTURE DECL 'NOWHERE> <F 1>")))

;; --- strict paths unchanged ----------------------------------------------------
;; explicit DECL? (pinned Confusion: BAD-TYPE-SPECIFICATION1,
;; docs/evidence/M3/DEFERRED-DECL-TYPE.md)
(check-exn #rx"DECL\\?: unknown declaration type PRSOBJ" (lambda ()
  (run "<DECL? 1 'PRSOBJ>")))
(check-exn #rx"DECL\\?: unknown declaration type PRSOBJ" (lambda ()
  (run "<DECL? 1 '<OR FIX PRSOBJ>>")))
;; positional (RSUBR-style) declarations fail at definition
(check-exn #rx"unknown declaration type PRSOBJ" (lambda ()
  (run "<DEFINE F (X) #DECL (\"VALUE\" PRSOBJ FIX) .X>")))
(check-exn #rx"unknown declaration type PRSOBJ" (lambda ()
  (run "<DEFINE F (X) #DECL (\"VALUE\" FIX PRSOBJ) .X>")))
;; GDECL: at SETG and against an existing value
(check-exn #rx"unknown declaration type PRSOBJ" (lambda ()
  (run "<GDECL (G) PRSOBJ> <SETG G 1>")))
(check-exn #rx"unknown declaration type PRSOBJ" (lambda ()
  (run "<SETG G 1> <GDECL (G) PRSOBJ>")))
;; known types in attached declarations: checked by the recorder (#193),
;; not enforced in production (#196)
(check-violation "<DEFINE F (X) #DECL ((X) FIX) .X> <F \"s\">"
                 (run "<DEFINE F (X) #DECL ((X) FIX) .X> <F \"s\">") "s" '("X"))
(check-violation "<DEFINE F (X) #DECL ((X) <OR FALSE FIX>) .X> <F A>"
                 (pname (run "<DEFINE F (X) #DECL ((X) <OR FALSE FIX>) .X> <F A>")) "A" '("X"))
(check-violation "<NEWTYPE OBJECT VECTOR> <DEFINE F (X) #DECL ((X) <OR FALSE OBJECT>) .X> <LENGTH <F [1]>>"
                 (run "<NEWTYPE OBJECT VECTOR> <DEFINE F (X) #DECL ((X) <OR FALSE OBJECT>) .X> <LENGTH <F [1]>>") 1 '("X"))
(check-violation "<DEFINE F (X) #DECL ((VALUE) FIX (X) PRSOBJ) .X> <F A>"
                 (pname (run "<DEFINE F (X) #DECL ((VALUE) FIX (X) PRSOBJ) .X> <F A>")) "A" '("VALUE"))
