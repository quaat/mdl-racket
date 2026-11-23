#lang racket/base
;; S6-REP (ADR-0049, maintainer decision 2026-11-23 "Inert REP + host loop").
;; Every session's GVAL of ROOT REP is a predefined SUBR value: GASSIGNED,
;; TYPE SUBR, APPLICABLE, storable with <SETG SAVEREP ,REP> (77rooms.mud:301)
;; and visible to BLO's <TYPE? ,REP SUBR FSUBR> (77act1.mud:3). Applying the
;; default REP by any path is a strict error: the runtime never provides a raw
;; MDL read-eval-print loop. Reference: evidence/M3/S6-rep-reference.json.
;; Each `run` builds a fresh atom space; never compare atoms across runs.
(require rackunit racket/list racket/port racket/runtime-path
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt"
         "../mdl/loader.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (session thunk)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (thunk)))
(define (eval-source source)
  (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
    (eval expr)))
(define (run source) (session (lambda () (eval-source source))))
(define (pname value) (and (mdl-atom? value) (mdl-atom-pname value)))
(define (true? value) (equal? (pname value) "T"))

(define rep-error
  (regexp-quote
   (string-append
    "REP: the default REP SUBR is inert; this runtime never provides a raw MDL "
    "read-eval-print loop (maintainer decision 2026-11-23; ADR-0049)")))
(define (check-rep-refused source)
  (check-exn (lambda (e) (and (exn:fail? e) (regexp-match? rep-error (exn-message e))))
             (lambda () (run source))
             source))

;; --- the predefined value ------------------------------------------------
(check-true (true? (run "<GASSIGNED? REP>")))
(check-equal? (pname (run "<TYPE ,REP>")) "SUBR")
;; TYPE is the ROOT atom SUBR, and REP itself is on ROOT.
(check-true (true? (run "<==? <TYPE ,REP> SUBR!-ROOT>")))
(check-true (true? (run "<==? <OBLIST? REP> <ROOT>>")))
;; BLO's test (77act1.mud:3).
(check-equal? (pname (run "<TYPE? ,REP SUBR FSUBR>")) "SUBR")
(check-true (mdl-false? (run "<TYPE? ,REP FSUBR FUNCTION>")))
(check-true (true? (run "<DECL? ,REP APPLICABLE>")))
;; Not a FUNCTION, MACRO or FIX applicable.
(check-true (mdl-false? (run "<TYPE? ,REP FUNCTION MACRO FIX>")))

;; --- CONTIN 77rooms.mud:301-302 --------------------------------------------
(check-true (mdl-false? (run "<GASSIGNED? SAVEREP>")))
(check-equal? (pname (run "<SETG SAVEREP ,REP> <TYPE ,SAVEREP>")) "SUBR")
(check-true (true? (run "<SETG SAVEREP ,REP> <==? ,REP ,SAVEREP>")))
(check-true (true? (run "<SETG SAVEREP ,REP> <=? ,REP ,SAVEREP>")))
(check-true (true? (run "<==? ,REP ,REP>")))
(check-true (true? (run "<==? ,REP <GVAL REP>>")))
;; SETG REP to a FUNCTION (as CONTIN sets it to RDCOM) replaces the GVAL;
;; SAVEREP keeps the SUBR, and restoring it gives back the same object.
(check-equal? (pname (run "<SETG SAVEREP ,REP> <SETG REP <FUNCTION () 1>> <TYPE ,REP>"))
              "FUNCTION")
(check-equal? (pname (run "<SETG SAVEREP ,REP> <SETG REP <FUNCTION () 1>> <TYPE ,SAVEREP>"))
              "SUBR")
(check-true (true? (run "<SETG SAVEREP ,REP> <SETG REP <FUNCTION () 1>>
                         <SETG REP ,SAVEREP> <==? ,REP ,SAVEREP>")))
(check-equal? (run "<SETG REP <FUNCTION () 42>> <REP>") 42)
(check-true (mdl-false? (run "<GUNASSIGN REP> <GASSIGNED? REP>")))

;; --- applying the default REP is a strict error ---------------------------
(check-rep-refused "<REP>")
(check-rep-refused "<REP 1 2>")
(check-rep-refused "<APPLY ,REP>")
(check-rep-refused "<APPLY ,REP \"<+ 1 2>\">")
(check-rep-refused "<SETG SAVEREP ,REP> <APPLY ,SAVEREP>")
(check-rep-refused "<SETG SAVEREP ,REP> <SETG REP <FUNCTION () 1>>
                    <SETG REP ,SAVEREP> <REP>")
(check-rep-refused "<SET R ,REP> <APPLY .R>")
(check-rep-refused "<MAPF <> ,REP '(1)>")
;; Arguments are evaluated first (ordinary SUBR), then the call is refused.
(session
 (lambda ()
   (check-exn (regexp rep-error) (lambda () (eval-source "<REP <SETG M3-ARG 7>>")))
   (check-equal? (eval-source ",M3-ARG") 7)))
;; It never reads input, prints, or behaves as a REPL.
(session
 (lambda ()
   (define in (open-input-string "<+ 1 2>\n"))
   (define out (open-output-string))
   (check-exn (regexp rep-error)
              (lambda ()
                (parameterize ([current-input-port in] [current-output-port out])
                  (eval-source "<REP>"))))
   (check-equal? (port->string in) "<+ 1 2>\n")
   (check-equal? (get-output-string out) "")))
;; Host application paths refuse too.
(session
 (lambda ()
   (check-exn (regexp rep-error) (lambda () (mdl-apply "REP")))
   (check-exn (regexp rep-error) (lambda () (mdl-apply "APPLY" (mdl-gval (mdl-root-atom "REP")))))))
;; As an interrupt action: registration works (it is an APPLICABLE SUBR),
;; delivery applies it and is refused.
(session
 (lambda ()
   (check-equal? (pname (mdl-type (eval-source "<ON \"M3-USER\" ,REP 3>"))) "HANDLER")
   (check-exn (regexp rep-error) (lambda () (mdl-emit-event! "M3-USER" '())))))

;; --- unsupported uses stay strict errors (no silent success) --------------
;; Confusion: PRIMTYPE/TYPEPRIM WORD. SUBR is not in the TYPE table (ADR-0049
;; scope), so these fail explicitly instead of inventing a WORD view.
(for ([case '(("<PRIMTYPE ,REP>" . #rx"unknown MDL TYPE SUBR")
              ("<TYPEPRIM SUBR>" . #rx"unknown MDL TYPE SUBR")
              ("<CHTYPE ,REP FIX>" . #rx"unknown MDL TYPE SUBR")
              ("<DECL? ,REP SUBR>" . #rx"unknown declaration type SUBR")
              ("<UNPARSE ,REP>" . #rx"UNPARSE: unsupported MDL type SUBR"))])
  (check-exn (cdr case) (lambda () (run (car case))) (car case)))

;; --- review follow-ups: MAPR, host call, object name, association isolation --
(check-rep-refused "<MAPR <> ,REP '(1)>")
;; Calling the REP value directly from host code is refused too.
(session
 (lambda ()
   (define rep (eval-source ",REP"))
   (check-equal? (object-name rep) 'REP)
   (check-exn (regexp rep-error) (lambda () (rep)))))
;; The REP object is shared by all sessions, but associations on it are
;; per-session: a PUT in one session is not visible in another.
(session
 (lambda ()
   (check-equal? (eval-source "<PUT ,REP FOO 42> <GET ,REP FOO>") 42)))
(session
 (lambda ()
   (check-true (mdl-false? (eval-source "<GET ,REP FOO>")))))

;; --- every session has its own REP binding ----------------------------------
(define-values (rep-a rep-b)
  (values (run "<SETG REP <FUNCTION () 1>> <GVAL REP>") (run ",REP")))
(check-equal? (pname (session (lambda () (mdl-type rep-b)))) "SUBR")
(check-true (mdl-function? rep-a))
(session
 (lambda ()
   (eval-source "<GUNASSIGN REP>")
   (check-true (mdl-false? (eval-source "<GASSIGNED? REP>")))
   (session (lambda () (check-true (true? (eval-source "<GASSIGNED? REP>")))))))
;; Two loader sessions: SETG in one does not reach the other, and the
;; session API refuses to apply the default REP.
(define-runtime-path fixtures "fixtures")
(define s1 (make-mdl-session fixtures))
(define s2 (make-mdl-session fixtures))
(check-equal? (mdl-atom-pname (mdl-session-call s1 "TYPE" (mdl-session-global s1 "REP")))
              "SUBR")
(check-exn (regexp rep-error) (lambda () (mdl-session-call s1 "REP")))
(void (mdl-session-call s1 "SETG" (mdl-session-atom s1 "REP") 5))
(check-equal? (mdl-session-global s1 "REP") 5)
(check-equal? (mdl-atom-pname (mdl-session-call s2 "TYPE" (mdl-session-global s2 "REP")))
              "SUBR")
(check-eq? (mdl-session-call s1 "TYPE" (mdl-session-global s2 "REP"))
           (mdl-session-atom s1 "SUBR"))

;; --- runtime modules never build atoms by name outside test modules -------
;; Runtime code must use the session ROOT interner (mdl-root-atom), never an
;; (mdl-atom "...") literal, so REP/SUBR always resolve in the current session.
(define-runtime-path runtime-dir "../mdl")
(define (mdl-atom-literals path)
  (define form
    (parameterize ([read-accept-reader #t] [read-accept-lang #t])
      (call-with-input-file path read)))
  (let walk ([x form])
    (cond [(and (pair? x) (eq? (car x) 'module+)) '()]
          [(and (pair? x) (eq? (car x) 'mdl-atom) (pair? (cdr x)) (string? (cadr x)))
           (list (cadr x))]
          [(pair? x) (append (walk (car x)) (walk (cdr x)))]
          [else '()])))
(for ([file '("runtime/core.rkt" "loader.rkt" "compiler.rkt")])
  (check-equal? (mdl-atom-literals (build-path runtime-dir file)) '() file))
