#lang racket/base
;; Review findings R3/R4 for PR #107: one authoritative OBLIST lookup path
;; and session ROOT identity for runtime-internal names.
;; Native observations: docs/evidence/M3/review/R3R4-oblist-reference.json
;; and R3R4-oblist-error-reference.json (pinned Confusion b5fcb91b...).
(require rackunit racket/file racket/port
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/loader.rkt"
         "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))

(define (run source)
  (parameterize ([current-namespace ns])
    (for/fold ([value #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

(define-syntax-rule (in-fresh-session body ...)
  (parameterize ([current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    body ...))

(define (initial) (run "<GET INITIAL OBLIST>"))
(define (root) (run "<ROOT>"))
(define (oblist-of atom) (mdl-apply "OBLIST?" atom))
(define (lookup name oblist) (mdl-apply "LOOKUP" name oblist))
(define (t? value) (and (mdl-atom? value) (equal? (mdl-atom-pname value) "T")))

;; ---------------------------------------------------------------- R4
;; Runtime-internal names are the session's ROOT atoms (manual 15.5: ROOT
;; holds T, OBLIST and every SUBR/FSUBR name; Confusion
;; root-placement-internal-names). New user atoms still go to INITIAL.
(test-case "R4 internal names live in ROOT; user atoms in INITIAL"
  (in-fresh-session
   (define r (root))
   (for ([name (in-list '("T" "FIX" "+" "OBLIST" "REDEFINE" "LOSE" "DECL"
                          "CHANNEL" "QUOTE" "LVAL" "GVAL" "PRIMTYPE" "REST"
                          "FORM" "LIST" "ATOM" "GC" "FALSE"))])
     (check-eq? (oblist-of (run name)) r name))
   (check-eq? (oblist-of (run "'FOO")) (initial))
   ;; The internal T value is the reader's T at top level.
   (check-eq? (run "<DECL? 1 FIX>") (run "T"))))

(test-case "R4 internal lookups never intern into a user OBLIST"
  (in-fresh-session
   (run "<BLOCK (<MOBLIST RB> <ROOT>)>")
   (run "<SETG ZZ 1>")
   (run "<ENDBLOCK>")
   (define rb (run "<GET RB OBLIST>"))
   (check-true (mdl-false? (lookup "REDEFINE" rb)))
   (check-true (mdl-false? (lookup "T" rb)))))

(test-case "R4 GVAL queries on an uninterned ATOM do not intern it"
  (in-fresh-session
   (run "<GASSIGNED? <ATOM \"ZQX\">>")
   (check-true (mdl-false? (lookup "ZQX" (initial))))))

(test-case "R4 a BLOCK omitting ROOT shadows user-read names, not internal T"
  (in-fresh-session
   (define root-t (run "T"))
   (define decl? (run "DECL?"))
   (define fix (run "FIX"))
   (run "<BLOCK (<MOBLIST NR>)>")
   ;; User-read T is a new atom in NR (Confusion: #FALSE!- for the
   ;; ROOT test), while DECL?'s internal T stays ROOT's T.
   (check-false (eq? (mdl-atom "T") root-t))
   (check-eq? (mdl-apply decl? 1 fix) root-t)
   ;; A SUBR name read under NR is a fresh, unbound atom.
   (check-exn #rx"unassigned|non-applicable|UNBOUND"
              (lambda () (run "<+ 1 2>")))
   ))

;; ---------------------------------------------------------------- R3
(test-case "R3 a PROG/formal binding of OBLIST drives atom resolution"
  (in-fresh-session
   (define x1 (run "<MOBLIST X1>"))
   (define path (mdl-list x1 (root)))
   (mdl-with-bindings
    (list (cons "OBLIST" path))
    (lambda ()
      (check-eq? (mdl-lval "OBLIST") path)
      (check-eq? (oblist-of (mdl-atom "PFOO")) x1)))
   (check-eq? (oblist-of (mdl-atom "PFOO2")) (initial))))

(test-case "R3 SET inside a PROG binding does not leak after normal exit"
  (in-fresh-session
   (define before (mdl-lval "OBLIST"))
   (run "<PROG ((OBLIST .OBLIST)) <SET OBLIST (<MOBLIST X1> <ROOT>)> 1>")
   (check-eq? (mdl-lval "OBLIST") before)
   (check-eq? (oblist-of (run "'POUT")) (initial))))

(test-case "R3 non-local RETURN and ERROR unwinding restore the path"
  (in-fresh-session
   (define before (mdl-lval "OBLIST"))
   (run "<PROG OUTER () <PROG ((OBLIST .OBLIST)) <SET OBLIST (<MOBLIST X1> <ROOT>)> <RETURN 1 .OUTER>>>")
   (check-eq? (mdl-lval "OBLIST") before)
   (check-exn exn:fail?
              (lambda ()
                (run "<PROG ((OBLIST .OBLIST)) <SET OBLIST (<MOBLIST X2> <ROOT>)> <ERROR FOO>>")))
   (check-eq? (mdl-lval "OBLIST") before)
   (check-eq? (oblist-of (run "'AFTER")) (initial))
   ;; A Racket exception raised inside the host binder.
   (check-exn #rx"host failure"
              (lambda ()
                (mdl-with-bindings
                 (list (cons "OBLIST" (mdl-list (run "<MOBLIST X3>"))))
                 (lambda () (error 'test "host failure")))))
   (check-eq? (mdl-lval "OBLIST") before)
   (check-eq? (oblist-of (mdl-atom "AFTER2")) (initial))))

(test-case "R3 a bound but unassigned OBLIST is unassigned, not the default"
  (in-fresh-session
   (check-exn #rx"unassigned" (lambda () (run "<PROG (OBLIST) .OBLIST>")))
   (check-exn #rx"OBLIST"
              (lambda ()
                (mdl-with-bindings (list (cons "OBLIST" 1))
                                   (lambda () (mdl-atom "BAD")))))))

(test-case "R3 BLOCK in a function without an OBLIST binding sets top level"
  (in-fresh-session
   (define x1 (run "<SETG X1 <MOBLIST X1>>"))
   (run "<DEFINE F () <BLOCK (,X1 <GET INITIAL OBLIST> <ROOT>)> 1>")
   (run "<F>")
   (check-eq? (car (mdl-list->list (mdl-lval "OBLIST"))) x1)
   (check-eq? (oblist-of (run "'BF1")) x1)
   (run "<ENDBLOCK>")
   (check-eq? (oblist-of (run "'BF2")) (initial))))

(test-case "R3 BLOCK inside a function binding OBLIST is frame-independent"
  (in-fresh-session
   (define outer (mdl-lval "OBLIST"))
   (define x1 (run "<SETG X1 <MOBLIST X1>>"))
   (run "<DEFINE G (\"AUX\" (OBLIST .OBLIST)) <BLOCK (,X1 <ROOT>)> .OBLIST>")
   (define inner (run "<G>"))
   (check-eq? (car (mdl-list->list inner)) x1)
   ;; G's binding is gone; the top-level path never changed.
   (check-eq? (mdl-lval "OBLIST") outer)
   (check-eq? (oblist-of (run "'GA")) (initial))
   ;; ENDBLOCK pops the value BLOCK pushed (G's initial binding) and sets
   ;; the now-current (top-level) LVAL; a second ENDBLOCK fails.
   (check-eq? (run "<ENDBLOCK>") outer)
   (check-eq? (mdl-lval "OBLIST") outer)
   (check-exn #rx"ENDBLOCK" (lambda () (run "<ENDBLOCK>")))))

(test-case "R3 top-level SET OBLIST"
  (in-fresh-session
   (define s1 (run "<MOBLIST S1>"))
   (run "<SET OBLIST (<GET S1 OBLIST> <GET INITIAL OBLIST> <ROOT>)>")
   (check-eq? (oblist-of (run "'NEWS")) s1)
   (run "<SET OBLIST (<GET INITIAL OBLIST> <ROOT>)>")
   (check-eq? (oblist-of (run "'NEWS2")) (initial))))

;; Atoms are identified when a form is read, not each time compiled code
;; runs (Confusion lexical-identity-function-body).
(test-case "R3 lexical identity of already-read atoms"
  (in-fresh-session
   (run "<DEFINE LX () 'LXATOM>")
   (run "<BLOCK (<MOBLIST LB> <GET INITIAL OBLIST> <ROOT>)>")
   (check-eq? (oblist-of (run "<LX>")) (initial))
   (run "<ENDBLOCK>")
   (run "<DEFINE LY () <PROG ((OBLIST (<MOBLIST LC> <ROOT>))) 'LYATOM>>")
   (check-eq? (oblist-of (run "<LY>")) (initial))
   (check-true (mdl-false? (lookup "LYATOM" (run "<GET LC OBLIST>"))))))

(test-case "R3 two sessions keep separate lookup paths and ROOT atoms"
  (define a (make-mdl-atom-space))
  (define b (make-mdl-atom-space))
  (define a-locals (list (make-hasheq)))
  (define b-locals (list (make-hasheq)))
  (define (in space locals thunk)
    (parameterize ([current-mdl-globals (make-hasheq)]
                   [current-mdl-locals locals]
                   [current-mdl-atom-space space])
      (thunk)))
  (define a-block (in a a-locals (lambda () (run "<BLOCK (<MOBLIST AB> <ROOT>)>"))))
  (in b b-locals
      (lambda ()
        (check-false (eq? (mdl-lval "OBLIST") a-block))
        (check-eq? (oblist-of (run "'BONLY")) (initial))))
  (define a-t (in a a-locals (lambda () (run "T"))))
  (define b-t (in b b-locals (lambda () (run "T"))))
  (check-false (eq? a-t b-t)))

;; Source loading: an FLOAD inside a PROG that binds OBLIST reads the file
;; with that binding (manual 15.3: READ uses the LVAL of OBLIST).
(test-case "R3 FLOAD under a PROG-bound OBLIST reads into that OBLIST"
  (define dir (make-temporary-file "oblist-identity-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (call-with-output-file (build-path dir "inner.mud")
       (lambda (out) (write-string "<SETG CAPTURED 'INNERATOM>\n" out)))
     (call-with-output-file (build-path dir "main.mud")
       (lambda (out)
         (write-string "<SETG CAPTURED 0>\n<SETG X1 <MOBLIST X1>>\n<PROG ((OBLIST (,X1 <GET INITIAL OBLIST> <ROOT>))) <FLOAD \"inner.mud\">>\n'AFTER-LOAD\n" out)))
     (define session (make-mdl-session dir))
     (define result (mdl-session-load! session "main.mud"))
     (check-equal? (hash-ref result 'status) "PASS" (format "~a" (hash-ref result 'failure)))
     (define captured (mdl-session-global session "CAPTURED"))
     (define x1 (mdl-session-global session "X1"))
     (check-eq? (mdl-session-call session "OBLIST?" captured) x1)
     (check-eq? (mdl-session-call session "OBLIST?" (mdl-session-atom session "AFTER-LOAD"))
                (mdl-session-call session "GET" (mdl-session-atom session "INITIAL")
                                  (mdl-session-atom session "OBLIST"))))
   (lambda () (delete-directory/files dir))))

;; An empty trailer names ROOT without consulting .OBLIST (Confusion
;; empty-trailer-root); 81tell-repl.mud reads TOPLEVEL!- at definition time.
(test-case "empty OBLIST trailer selects the session ROOT"
  (in-fresh-session
   (define r (root))
   (check-eq? (run "T!-") (run "T"))
   (check-eq? (oblist-of (run "'NEWROOTX!-")) r)
   (check-true (mdl-false? (lookup "NEWROOTX" (initial))))
   (check-eq? (oblist-of (run "'FOO!-INITIAL!-")) (initial))
   (define toplevel (mdl-atom "TOPLEVEL!-"))
   (check-eq? (oblist-of toplevel) r)
   (run "<BLOCK (<MOBLIST NR>)>")
   (check-eq? (mdl-atom "TOPLEVEL!-") toplevel)
   (check-exn #rx"trailer" (lambda () (mdl-atom "!-")))))
