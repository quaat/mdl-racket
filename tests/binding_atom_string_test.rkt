#lang racket/base
;; Issue #199: the binding primitives take an ATOM. A STRING (or FIX, or
;; FORM) first argument is an error and never names, interns or changes the
;; ATOM the STRING spells. Native observations:
;; docs/evidence/M4/I199-STRING-ATOM.md (i199-string-atom-*-reference.json).
;; Pinned Confusion reports the error in one of two ways (a "Type Mismatch"
;; abort to level 1, or an *ERROR* level); this runtime raises the strict
;; `mdl-<p>: expected an MDL ATOM` it already raised for FIX and FORM (the
;; existing error-reporting difference, SEMANTICS "#199").
;; MANIFEST: Confusion accepts any argument and does nothing; this runtime's
;; enforced MANIFEST (M2 D1) rejects every non-ATOM, a STRING included.
;; The host API (mdl/loader.rkt) names ATOMs by Racket strings and converts
;; them at its own boundary, without interning.
(require rackunit racket/file racket/list racket/string
         "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt" "../mdl/loader.rkt")

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))

;; Each SOURCE runs in one fresh context, in order; a failing source yields
;; (error MESSAGE) and the next source still runs in the same context, so a
;; later source observes the state the failed call left.
(define (run-steps . sources)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/list ([source (in-list sources)])
      (with-handlers ([exn:fail? (lambda (e) (list 'error (exn-message e)))])
        (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
          (eval expr))))))

;; A compiled DEFINE yields the FUNCTION here and the ATOM in Confusion (a
;; known, documented difference outside #199): shown as DEFINED.
(define (show v)
  (cond [(and (pair? v) (eq? (car v) 'error)) v]
        [(procedure? v) 'DEFINED]
        [(mdl-atom? v) (mdl-atom-pname v)]
        [(mdl-false? v) 'FALSE]
        [else v]))
(define (steps . sources) (map show (apply run-steps sources)))
(define (rejected who) (list 'error (format "~a: expected an MDL ATOM" who)))

;; --- every primitive, every non-ATOM type, top level and inside a FUNCTION ---
;; (primitive who extra-args)
(define primitives
  '(("SETG" "mdl-setg" " 3")
    ("GVAL" "mdl-gval" "")
    ("GASSIGNED?" "mdl-gassigned?" "")
    ("SET" "mdl-set" " 3")
    ("LVAL" "mdl-lval" "")
    ("VALUE" "mdl-value" "")
    ("GUNASSIGN" "mdl-gunassign" "")
    ("MANIFEST" "mdl-manifest" "")))
(define non-atoms '("\"M199-FOO\"" "5" "'<M199-FOO>"))

(for* ([p (in-list primitives)] [arg (in-list non-atoms)])
  (define-values (name who extra) (apply values p))
  (define call (format "<~a ~a~a>" name arg extra))
  (check-equal? (steps call) (list (rejected who)) call)
  (check-equal? (steps (format "<DEFINE M199-F () ~a>" call) "<M199-F>")
                (list 'DEFINED (rejected who))
                (format "in a FUNCTION: ~a" call)))

;; ASSIGNED? already agreed with Confusion (it never used binding-atom).
(for ([arg (in-list non-atoms)])
  (define call (format "<ASSIGNED? ~a>" arg))
  (define refused '(error "mdl-assigned?: First arg to ASSIGNED? must be ATOM"))
  (check-equal? (steps call) (list refused) call)
  (check-equal? (steps (format "<DEFINE M199-F () ~a>" call) "<M199-F>")
                (list 'DEFINED refused)))

;; --- the ATOM a STRING spells is unchanged after the rejected call -----------
;; No ATOM is interned: the STRING's PNAME is on no OBLIST of the search path
;; afterwards (the probe names it only as a STRING, so reading the probe does
;; not intern it either).
(define interned-probe
  "<OR <LOOKUP \"M199-NEW\" <1 .OBLIST>> <LOOKUP \"M199-NEW\" <ROOT>>>")
(for ([p (in-list primitives)])
  (define-values (name who extra) (apply values p))
  (define call (format "<~a \"M199-NEW\"~a>" name extra))
  (check-equal? (steps call interned-probe) (list (rejected who) 'FALSE)
                (format "no ATOM interned: ~a" call))
  (check-equal? (steps (format "<DEFINE M199-F () ~a>" call) "<M199-F>" interned-probe)
                (list 'DEFINED (rejected who) 'FALSE)
                (format "no ATOM interned, in a FUNCTION: ~a" call)))

;; Fresh ATOMs stay unassigned (global and local).
(check-equal? (steps "<SETG \"FOO\" 3>" "<GASSIGNED? FOO>" "<ASSIGNED? FOO>")
              (list (rejected "mdl-setg") 'FALSE 'FALSE))
(check-equal? (steps "<SET \"FOO\" 3>" "<ASSIGNED? FOO>" "<GASSIGNED? FOO>")
              (list (rejected "mdl-set") 'FALSE 'FALSE))
(check-equal? (steps "<MANIFEST \"FOO\">" "<GASSIGNED? FOO>" "<SETG FOO 2>" "<SETG FOO 3>")
              (list (rejected "mdl-manifest") 'FALSE 2 3))
(check-equal? (steps "<DEFINE F () <SETG \"X\" 1>>" "<F>" "<GASSIGNED? X>")
              (list 'DEFINED (rejected "mdl-setg") 'FALSE))
(check-equal? (steps "<DEFINE F () <SET \"X\" 1>>" "<F>" "<ASSIGNED? X>")
              (list 'DEFINED (rejected "mdl-set") 'FALSE))

;; Preset ATOMs keep their values; GUNASSIGN does not unassign; MANIFEST does
;; not make FOO manifest (a later SETG to another value succeeds).
(check-equal? (steps "<SETG FOO 1>" "<SETG \"FOO\" 3>" ",FOO")
              (list 1 (rejected "mdl-setg") 1))
(check-equal? (steps "<SETG FOO 1>" "<GVAL \"FOO\">" "<GASSIGNED? \"FOO\">" "<VALUE \"FOO\">" ",FOO")
              (list 1 (rejected "mdl-gval") (rejected "mdl-gassigned?") (rejected "mdl-value") 1))
(check-equal? (steps "<SETG FOO 1>" "<GUNASSIGN \"FOO\">" ",FOO" "<GASSIGNED? FOO>")
              (list 1 (rejected "mdl-gunassign") 1 "T"))
(check-equal? (steps "<SETG FOO 1>" "<MANIFEST \"FOO\">" "<SETG FOO 2>" ",FOO")
              (list 1 (rejected "mdl-manifest") 2 2))
(check-equal? (steps "<SET FOO 1>" "<SET \"FOO\" 3>" ".FOO")
              (list 1 (rejected "mdl-set") 1))
(check-equal? (steps "<SET FOO 1>" "<LVAL \"FOO\">" "<VALUE \"FOO\">" ".FOO")
              (list 1 (rejected "mdl-lval") (rejected "mdl-value") 1))
;; Inside FUNCTIONs: a free SET does not reach the top-level X, an AUX-bound
;; X is not set through its PNAME, and GUNASSIGN does not unassign X.
(check-equal? (steps "<SET X 0>" "<DEFINE F () <SET \"X\" 1>>" "<F>" ".X")
              (list 0 'DEFINED (rejected "mdl-set") 0))
(check-equal? (steps "<DEFINE F (\"AUX\" (X 0)) <SET \"X\" 1> .X>" "<F>")
              (list 'DEFINED (rejected "mdl-set")))
(check-equal? (steps "<DEFINE F (\"AUX\" (X 1)) <LVAL \"X\">>" "<F>")
              (list 'DEFINED (rejected "mdl-lval")))
(check-equal? (steps "<DEFINE F (\"AUX\" (X 1)) <VALUE \"X\">>" "<F>")
              (list 'DEFINED (rejected "mdl-value")))
(check-equal? (steps "<SETG X 1>" "<DEFINE F () <GVAL \"X\">>" "<F>")
              (list 1 'DEFINED (rejected "mdl-gval")))
(check-equal? (steps "<SETG X 1>" "<DEFINE F () <GASSIGNED? \"X\">>" "<F>")
              (list 1 'DEFINED (rejected "mdl-gassigned?")))
(check-equal? (steps "<SETG X 1>" "<DEFINE F () <GUNASSIGN \"X\">>" "<F>" "<GASSIGNED? X>" ",X")
              (list 1 'DEFINED (rejected "mdl-gunassign") "T" 1))
(check-equal? (steps "<SETG X 1>" "<DEFINE F () <MANIFEST \"X\">>" "<F>" "<SETG X 2>" ",X")
              (list 1 'DEFINED (rejected "mdl-manifest") 2 2))

;; MANIFEST checks every argument before marking any: a rejected later
;; argument leaves an earlier ATOM argument not manifest.
(check-equal? (steps "<SETG FOO 1>" "<MANIFEST FOO \"BAR\">" "<SETG FOO 2>")
              (list 1 (rejected "mdl-manifest") 2))
(check-equal? (steps "<SETG FOO 1>" "<MANIFEST FOO 5>" "<SETG FOO 2>")
              (list 1 (rejected "mdl-manifest") 2))

;; ATOM controls are unchanged.
(check-equal? (steps "<SETG FOO 3>" ",FOO" "<GVAL FOO>" "<GASSIGNED? FOO>" "<VALUE FOO>")
              (list 3 3 3 "T" 3))
(check-equal? (steps "<SET FOO 3>" ".FOO" "<LVAL FOO>" "<VALUE FOO>" "<ASSIGNED? FOO>")
              (list 3 3 3 3 "T"))
(check-equal? (steps "<SETG FOO 3>" "<GUNASSIGN FOO>" "<GASSIGNED? FOO>")
              (list 3 "FOO" 'FALSE))
(check-equal? (steps "<SETG FOO 1>" "<MANIFEST FOO>" "<SETG FOO 2>" ",FOO")
              (list 1 "T" '(error "mdl-setg: ATTEMPT-TO-CHANGE-MANIFEST-VARIABLE FOO") 1))

;; --- #121 (superseded by #199): APPLY and a FORM head with a STRING; REST views ---
;; Pinned Confusion: NON-APPLICABLE-TYPE for <APPLY "F" 1>, <APPLY "+" 1 2> and
;; <"F" 1>; SETG and GVAL reject <REST "XFOO" 1>
;; (docs/evidence/M4/i121-apply-string-reference.json). The STRING never names
;; the function, and nothing is interned.
(let ([r (steps "<DEFINE M121-F (X) <+ .X 1>>"
                "<APPLY \"M121-F\" 1>"
                "<\"M121-F\" 1>"
                "<APPLY \"+\" 1 2>"
                "<APPLY ,M121-F 1>"
                "<LOOKUP \"M121-G\" <1 .OBLIST>>"
                "<APPLY \"M121-G\" 1>"
                "<LOOKUP \"M121-G\" <1 .OBLIST>>")])
  (check-equal? (list-ref r 0) 'DEFINED)
  (for ([i '(1 2 3 6)])
    (check-match (list-ref r i) (list 'error (regexp #rx"NON-APPLICABLE-TYPE"))))
  (check-equal? (list-ref r 4) 2)
  (check-equal? (list-ref r 5) 'FALSE)
  (check-equal? (list-ref r 7) 'FALSE))
(check-equal? (steps "<SETG M121-V 7>" "<SETG <REST \"XM121-V\" 1> 3>"
                     "<GVAL <REST \"XM121-V\" 1>>" ",M121-V")
              (list 7 (rejected "mdl-setg") (rejected "mdl-gval") 7))

;; --- the runtime value API takes ATOMs only ----------------------------------
(parameterize ([current-namespace ns]
               [current-mdl-globals (make-hasheq)]
               [current-mdl-locals (list (make-hasheq))]
               [current-mdl-atom-space (make-mdl-atom-space)])
  ;; The exported value API (the other primitives are covered above).
  (for ([who '(mdl-setg mdl-gval mdl-set mdl-lval mdl-apply)]
        [call (list (lambda () (mdl-setg! "M199-HOST" 1))
                    (lambda () (mdl-gval "M199-HOST"))
                    (lambda () (mdl-set! "M199-HOST" 1))
                    (lambda () (mdl-lval "M199-HOST"))
                    (lambda () (mdl-apply "TYPE" 1)))])
    (check-exn (regexp (string-append "^" (regexp-quote (format "~a: expected an MDL ATOM" who)) "$"))
               call (symbol->string who)))
  (check-false (mdl-find-atom "M199-HOST"))
  ;; mdl-find-atom never interns; it finds what the reader interned.
  (check-false (mdl-find-atom "M199-LATER"))
  (check-false (mdl-find-atom "M199-LATER"))
  (define later (mdl-atom "M199-LATER"))
  (check-eq? (mdl-find-atom "M199-LATER") later)
  (check-eq? (mdl-find-atom "TYPE") (mdl-atom "TYPE"))
  (check-exn #rx"expected a STRING PNAME" (lambda () (mdl-find-atom later))))

;; --- the host API converts its string names at the boundary, never interning ---
(define root (make-temporary-file "mdl-i199-test~a" 'directory))
(call-with-output-file (build-path root "i199.mud") #:exists 'truncate/replace
  (lambda (out)
    (display (string-append
              "<SETG M199-G 7>\n"
              "<DEFINE M199-ADD (A B) <+ .A .B>>\n"
              "<DEFINE M199-INTERNED? (S) <OR <LOOKUP .S <1 .OBLIST>> <LOOKUP .S <ROOT>>>>\n"
              "<SETG M199-FLAGGED!-M199-OBL 9>\n"
              "<DEFINE M199-OBL-OF (A) <GET .A OBLIST>>\n")
             out)))
(define s (make-mdl-session root))
(check-equal? (hash-ref (mdl-session-load! s "i199.mud") 'status) "PASS")
(define (interned? name) (not (mdl-false? (mdl-session-call s "M199-INTERNED?" name))))

(check-equal? (mdl-session-global s "M199-G") 7)
(check-equal? (mdl-session-call s "M199-ADD" 2 3) 5)
(check-equal? (mdl-atom-pname (mdl-session-call s "TYPE" 1)) "FIX")
;; An ATOM name is still accepted as is.
(check-equal? (mdl-session-global s (mdl-session-atom s "M199-G")) 7)
(check-equal? (mdl-session-call s (mdl-session-atom s "M199-ADD") 1 1) 2)
;; An OBLIST trailer name resolves like the reader, without creating anything.
(check-equal? (mdl-session-global s "M199-FLAGGED!-M199-OBL") 9)
(check-exn #rx"unassigned MDL global M199-NOPE!-M199-OBL"
           (lambda () (mdl-session-global s "M199-NOPE!-M199-OBL")))
(check-exn #rx"unassigned MDL global M199-X!-M199-NO-OBLIST"
           (lambda () (mdl-session-global s "M199-X!-M199-NO-OBLIST")))
(check-false (interned? "M199-NO-OBLIST"))
;; The trailer's owner ATOM exists but has no OBLIST: the host read neither
;; finds the name nor creates the OBLIST (MOBLIST would).
(check-false (mdl-false? (mdl-session-call s "M199-OBL-OF"
                                           (mdl-session-find-atom s "M199-OBL"))))
(check-true (mdl-false? (mdl-session-call s "M199-OBL-OF"
                                          (mdl-session-find-atom s "M199-G"))))
(check-exn #rx"unassigned MDL global M199-X!-M199-G"
           (lambda () (mdl-session-global s "M199-X!-M199-G")))
(check-false (mdl-session-find-atom s "M199-X!-M199-G"))
(check-true (mdl-false? (mdl-session-call s "M199-OBL-OF"
                                          (mdl-session-find-atom s "M199-G"))))
;; A name the session never read is not interned by a host read or call.
(check-false (interned? "M199-NEVER"))
(check-exn #rx"unassigned MDL global M199-NEVER"
           (lambda () (mdl-session-global s "M199-NEVER")))
(check-exn #rx"unassigned MDL global M199-NEVER"
           (lambda () (mdl-session-call s "M199-NEVER" 1)))
(check-false (interned? "M199-NEVER"))
(check-false (mdl-session-find-atom s "M199-NEVER"))
(check-eq? (mdl-session-find-atom s "M199-G") (mdl-session-atom s "M199-G"))
;; mdl-session-atom keeps its documented meaning (the ATOM the reader would
;; produce, interning like the reader).
(check-false (interned? "M199-MADE"))
(define made (mdl-session-atom s "M199-MADE"))
(check-true (interned? "M199-MADE"))
(check-eq? (mdl-session-find-atom s "M199-MADE") made)
;; A host string passed as an MDL argument is an MDL STRING, so it is
;; rejected by the binding primitives like any other STRING.
(check-exn #rx"^mdl-gval: expected an MDL ATOM$"
           (lambda () (mdl-session-call s "GVAL" "M199-G")))
(check-exn #rx"^mdl-gassigned\\?: expected an MDL ATOM$"
           (lambda () (mdl-session-call s "GASSIGNED?" "M199-G")))
(check-exn #rx"^mdl-setg: expected an MDL ATOM$"
           (lambda () (mdl-session-call s "SETG" "M199-G" 1)))
(check-equal? (mdl-session-global s "M199-G") 7)
(check-equal? (mdl-session-call s "GVAL" (mdl-session-find-atom s "M199-G")) 7)
;; Bad host names are argument errors at the boundary.
(check-exn exn:fail:contract? (lambda () (mdl-session-global s 5)))
(check-exn exn:fail:contract? (lambda () (mdl-session-call s 'TYPE 1)))
(check-exn exn:fail:contract? (lambda () (mdl-session-find-atom s 5)))

(delete-directory/files root)
(displayln "binding-atom string tests passed")
