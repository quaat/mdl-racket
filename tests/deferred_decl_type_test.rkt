#lang racket/base
;; M3 issue #98: defer unresolved TYPE atom in attached #DECL, never ignore it
;; at definition time.
;; M4 issue #193 (INV-11; amendment to the #98 ADR, maintainer decision
;; 2026-11-25): an attached declaration's TYPE name that is STILL undefined
;; when checked (no registered TYPE, no DECL association) is not enforced at
;; that position, matching pinned Confusion. A name defined later is checked
;; strictly; DECL?, positional declarations, GDECL and every known type stay
;; strict (docs/SEMANTICS.md, DECISIONS.md).
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
;; An unexpected exception while evaluating a checked value becomes that
;; check's failing actual value (so one run reports every failing check).
(define-syntax-rule (guard e)
  (with-handlers ([exn:fail? (lambda (x) (list 'raised (exn-message x)))]) e))
(define-syntax-rule (check-equal? actual expected) (rk:check-equal? (guard actual) expected))
(define-syntax-rule (check-true actual) (rk:check-true (guard actual)))

;; --- definition (issue #98, unchanged) ---------------------------------------
(check-true (procedure? (run "<DEFINE F (X) #DECL ((X) PRSOBJ) .X>")))
(check-true (procedure? (run "<DEFINE F (X) #DECL ((X) <VECTOR FUTURE>) .X>")))

;; --- still undefined at the check: any value (#193) --------------------------
(define f-prsobj "<DEFINE F (X) #DECL ((X) PRSOBJ) .X> ")
(check-equal? (run (string-append f-prsobj "<F 1>")) 1)
(check-true (mdl-false? (run (string-append f-prsobj "<F <>>"))))
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
(check-exn #rx"DECL.*PV does not satisfy declaration"
           (lambda () (run (string-append maint "<M (1 2)>"))))
;; SET of a declared local and the VALUE result
(check-equal? (run "<DEFINE F (X) #DECL ((X) PRSOBJ) <SET X \"t\"> .X> <F 1>") "t")
(check-equal? (run "<DEFINE F (X) #DECL ((VALUE) PRSOBJ (X) FIX) .X> <F 1>") 1)
(check-exn #rx"DECL.*X does not satisfy declaration"
           (lambda () (run "<DEFINE F (X) #DECL ((VALUE) PRSOBJ (X) FIX) .X> <F <>>")))

;; --- nested undefined names: that position only -------------------------------
(check-equal? (run "<DEFINE F (X) #DECL ((X) <OR FUTURE FIX>) .X> <F 1>") 1)
(check-equal? (run "<DEFINE F (X) #DECL ((X) <OR FIX FUTURE>) .X> <F \"s\">") "s")
(check-equal? (run "<DEFINE F (X) #DECL ((X) <VECTOR FUTURE>) .X> <1 <F [\"s\"]>>") "s")
(check-equal? (run "<DEFINE F (X) #DECL ((X) <LIST FUTURE FIX>) <2 .X>> <F (<> 2)>") 2)
(check-exn #rx"DECL.*X does not satisfy declaration"   ; FIX element still strict
           (lambda () (run "<DEFINE F (X) #DECL ((X) <LIST FUTURE FIX>) .X> <F (<> \"s\")>")))
(check-exn #rx"DECL.*X does not satisfy declaration"   ; structure TYPE still strict
           (lambda () (run "<DEFINE F (X) #DECL ((X) <LIST FUTURE FIX>) .X> <F [1 2]>")))
(check-exn #rx"DECL.*X does not satisfy declaration"   ; required length still strict
           (lambda () (run "<DEFINE F (X) #DECL ((X) <LIST FUTURE FIX>) .X> <F (1)>")))
(check-equal? (run "<DEFINE F (X) #DECL ((X) <LIST [REST FUTURE]>) <LENGTH .X>> <F (1 \"s\" <>)>") 3)
(check-equal? (run "<DEFINE F (X) #DECL ((X) <LIST [REST FIX FUTURE]>) <LENGTH .X>> <F (1 \"s\" 2 A)>") 4)
(check-exn #rx"DECL.*X does not satisfy declaration"   ; REST's FIX still strict
           (lambda () (run "<DEFINE F (X) #DECL ((X) <LIST [REST FIX FUTURE]>) .X> <F (1 \"s\" B A)>")))
(check-equal? (run "<DEFINE F (X) #DECL ((X) <VECTOR [2 FUTURE]>) <LENGTH .X>> <F [A \"b\"]>") 2)

;; --- defined later by NEWTYPE: strict as that TYPE ---------------------------
(check-equal? (pname
               (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <NEWTYPE FUTURE VECTOR> <TYPE <F <CHTYPE [] FUTURE>>>"))
              "FUTURE")
(check-exn #rx"DECL.*X does not satisfy declaration"
           (lambda () (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <NEWTYPE FUTURE VECTOR> <F 1>")))
(check-exn #rx"DECL.*X does not satisfy declaration"
           (lambda () (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <NEWTYPE FUTURE VECTOR> <F <>>")))
;; the same function, called before and after the NEWTYPE
(check-exn #rx"DECL.*X does not satisfy declaration"
           (lambda () (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <F 1> <NEWTYPE FUTURE VECTOR> <F 2>")))
(check-equal? (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <F 1> <NEWTYPE FUTURE VECTOR> <F <CHTYPE [] FUTURE>> 9") 9)
;; nested, defined later
(check-exn #rx"DECL.*X does not satisfy declaration"
           (lambda () (run "<DEFINE F (X) #DECL ((X) <OR FUTURE FIX>) .X> <NEWTYPE FUTURE VECTOR> <F \"s\">")))
(check-equal? (run "<DEFINE F (X) #DECL ((X) <OR FUTURE FIX>) .X> <NEWTYPE FUTURE VECTOR> <F 1>") 1)
(check-exn #rx"DECL.*X does not satisfy declaration"
           (lambda () (run "<DEFINE F (X) #DECL ((X) <VECTOR FUTURE>) .X> <NEWTYPE FUTURE VECTOR> <F [1]>")))
(check-exn #rx"DECL.*X does not satisfy declaration"
           (lambda () (run "<DEFINE F (X) #DECL ((X) <LIST [REST FUTURE]>) .X> <NEWTYPE FUTURE VECTOR> <F (1)>")))

;; --- defined later by a DECL association: strict as that Pattern -------------
(check-equal? (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <PUT FUTURE DECL 'FIX> <F 3>") 3)
(check-exn #rx"DECL.*X does not satisfy declaration"
           (lambda () (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <PUT FUTURE DECL 'FIX> <F \"s\">")))
(check-true (mdl-false?
             (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <PUT FUTURE DECL '<OR FIX FALSE>> <F <>>")))
(check-exn #rx"DECL.*X does not satisfy declaration"
           (lambda () (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <PUT FUTURE DECL '<OR FIX FALSE>> <F A>")))
(check-exn #rx"DECL.*X does not satisfy declaration"
           (lambda () (run "<DEFINE F (X) #DECL ((X) <LIST FUTURE>) .X> <PUT FUTURE DECL 'FIX> <F (A)>")))
;; The order of definition matters for an association's own target
;; (independent review): an association that already exists when the
;; function is defined is followed with the attached deferral, so an unknown
;; name inside it is retained and, while still undefined, matches any value;
;; once defined it is strict.
(check-equal? (run "<PUT ALIAS DECL '<OR BAR FIX>> <DEFINE F (X) #DECL ((X) ALIAS) .X> <F 1.5>") 1.5)
(check-equal? (run "<PUT ALIAS DECL '<OR BAR FIX>> <DEFINE F (X) #DECL ((X) ALIAS) .X> <F 7>") 7)
(check-exn #rx"X does not satisfy declaration"
           (lambda () (run "<PUT ALIAS DECL '<OR BAR FIX>> <DEFINE F (X) #DECL ((X) ALIAS) .X> <NEWTYPE BAR LIST> <F 1.5>")))
;; ...whereas an association added after the definition is normalized
;; strictly at the check: an unknown target there stays a strict error.
(check-exn #rx"unknown declaration type NOWHERE"
           (lambda () (run "<DEFINE F (X) #DECL ((X) FUTURE) .X> <PUT FUTURE DECL 'NOWHERE> <F 1>")))

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
;; known types in attached declarations: still strict
(check-exn #rx"DECL.*X does not satisfy declaration"
           (lambda () (run "<DEFINE F (X) #DECL ((X) FIX) .X> <F \"s\">")))
(check-exn #rx"DECL.*X does not satisfy declaration"
           (lambda () (run "<DEFINE F (X) #DECL ((X) <OR FALSE FIX>) .X> <F A>")))
(check-exn #rx"DECL.*X does not satisfy declaration"
           (lambda () (run "<NEWTYPE OBJECT VECTOR> <DEFINE F (X) #DECL ((X) <OR FALSE OBJECT>) .X> <F [1]>")))
(check-exn #rx"DECL.*VALUE does not satisfy declaration"
           (lambda () (run "<DEFINE F (X) #DECL ((VALUE) FIX (X) PRSOBJ) .X> <F A>")))
