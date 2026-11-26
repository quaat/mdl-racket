#lang racket/base
;; Review R1 x R3/R4 reconciliation (PR #117 after #118): session-owned
;; CHANNEL ports on the canonical seeded ROOT INCHAN/OUTCHAN identities.
;; Evidence: docs/evidence/M3/review/R1.md "Reconciliation with #118".
(require rackunit racket/file racket/runtime-path
         "../mdl/runtime/core.rkt" "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/loader.rkt")

(define-runtime-path print-fixture "fixtures/channel-print.mdl")
(define-runtime-path core-module "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define test-namespace (namespace-anchor->namespace anchor))

(define (run source)
  (parameterize ([current-namespace test-namespace])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

(define (pname value) (and (mdl-atom? value) (mdl-atom-pname value)))

;; (a) One canonical ROOT identity, seen by the channel machinery and by MDL
;;     source (reader, GDECL, SETG, ASSIGNED?, GASSIGNED?, LVAL/GVAL).
(test-case "(a) INCHAN/OUTCHAN are the seeded ROOT atoms everywhere"
  (define out (open-output-string))
  (call-with-mdl-context
   (make-mdl-context #:output-port out)
   (lambda ()
     (define space (current-mdl-atom-space))
     (check-eq? (atom-space-outchan space) (mdl-root-atom "OUTCHAN"))
     (check-eq? (atom-space-inchan space) (mdl-root-atom "INCHAN"))
     (check-eq? (run "OUTCHAN") (mdl-root-atom "OUTCHAN"))
     (check-eq? (run "INCHAN") (mdl-root-atom "INCHAN"))
     (check-eq? (run "<ROOT>") (mdl-apply (mdl-atom "OBLIST?") (mdl-root-atom "OUTCHAN")))
     (check-eq? (run ",OUTCHAN") (mdl-gval (mdl-root-atom "OUTCHAN")))
     (check-eq? (run ".OUTCHAN") (mdl-lval (mdl-root-atom "OUTCHAN")))
     (check-equal? (pname (run "<GASSIGNED? OUTCHAN>")) "T")
     (check-equal? (pname (run "<ASSIGNED? OUTCHAN>")) "T")
     ;; GDECL accepts the existing CHANNEL value of that same atom, and SETG
     ;; of the same atom is then checked against the declaration.
     (check-equal? (pname (run "<GDECL (OUTCHAN INCHAN) CHANNEL>")) "T")
     (check-exn #rx"GDECL" (lambda () (run "<SETG OUTCHAN 5>")))
     ;; The omitted PRINTSTRING channel is the LVAL of that same atom.
     (check-equal? (run "<PRINTSTRING \"a\">") 1)
     (check-equal? (get-output-string out) "a")
     (run "<SET OUTCHAN .INCHAN>")
     (check-exn #rx"PRINTSTRING requires an output channel"
                (lambda () (run "<PRINTSTRING \"b\">"))))))

;; (b) Standalone #lang mdl module output reaches its context's port.
(test-case "(b) standalone #lang mdl module prints through its context port"
  (define out (open-output-string))
  (define stray (open-output-string))
  (define ns (make-base-namespace))
  (namespace-attach-module test-namespace core-module ns)
  (parameterize ([current-namespace ns] [current-output-port stray])
    (call-with-mdl-context (make-mdl-context #:output-port out)
      (lambda () (dynamic-require print-fixture #f))))
  (check-equal? (get-output-string out) "from-b")
  ;; Module top-level result printing is Racket's, to current-output-port
  ;; (pre-existing; not channel-routed).
  (check-equal? (get-output-string stray) "6\n"))

(define (with-source-root text proc)
  (define root (make-temporary-file "mdl-root-identity~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (call-with-output-file (build-path root "main.mud")
       (lambda (o) (void (write-string text o))))
     (proc root))
   (lambda () (delete-directory/files root))))

;; (c) Two sessions with injected ports never cross; (e) a channel from one
;;     session is rejected by the other.
(test-case "(c)(e) session ports are isolated; foreign channels rejected"
  (with-source-root "<PRINTSTRING \"loaded\"> <CRLF>"
   (lambda (root)
     (define pa (open-output-string))
     (define pb (open-output-string))
     (define stray (open-output-string))
     (define sa (make-mdl-session root #:output-port pa))
     (define sb (make-mdl-session root #:output-port pb))
     (parameterize ([current-output-port stray])
       (check-equal? (hash-ref (mdl-session-load! sa "main.mud") 'status) "PASS")
       (check-equal? (mdl-session-call sb "PRINTSTRING" "B") 1))
     (check-equal? (get-output-string pa) "loaded\n")
     (check-equal? (get-output-string pb) "B")
     (check-equal? (get-output-string stray) "")
     (check-exn #rx"not open in this MDL session"
                (lambda ()
                  (mdl-session-call sb "PRINTSTRING" "x"
                                    (mdl-session-global sa "OUTCHAN"))))
     (check-equal? (get-output-string pb) "B"))))

;; (d) BLOCK/ENDBLOCK shadowing: a user OUTCHAN first on .OBLIST does not
;;     redirect the default channel, but MDL source inside the block reads
;;     the shadowing (unbound) user atom.
(test-case "(d) a shadowing user OUTCHAN does not capture the default channel"
  (with-source-root
   (string-append
    "<SETG OB1 <MOBLIST OB1>>\n<INSERT \"OUTCHAN\" ,OB1>\n"
    "<BLOCK (,OB1 <ROOT>)>\n<PRINTSTRING \"x\">\n"
    "<SETG R1-SHADOW-ATOM OUTCHAN>\n"
    "<SETG R1-SHADOW-ASSIGNED <ASSIGNED? OUTCHAN>>\n"
    "<SETG R1-SHADOW-GASSIGNED <GASSIGNED? OUTCHAN>>\n"
    "<ENDBLOCK>\n")
   (lambda (root)
     (define port (open-output-string))
     (define s (make-mdl-session root #:output-port port))
     (define result (mdl-session-load! s "main.mud"))
     (check-equal? (hash-ref result 'status) "PASS"
                   (format "~a" (hash-ref result 'failure #f)))
     (check-equal? (get-output-string port) "x")
     ;; Names read inside the block were interned on OB1, hence !-OB1.
     (define shadow (mdl-session-global s "R1-SHADOW-ATOM!-OB1"))
     (check-equal? (mdl-atom-pname shadow) "OUTCHAN")
     ;; After ENDBLOCK the reader resolves OUTCHAN to ROOT again.
     (check-false (eq? shadow (mdl-session-atom s "OUTCHAN")))
     (check-eq? (mdl-session-atom s "OUTCHAN") (mdl-session-atom s "OUTCHAN!-ROOT"))
     (check-true (mdl-false? (mdl-session-global s "R1-SHADOW-ASSIGNED!-OB1")))
     (check-true (mdl-false? (mdl-session-global s "R1-SHADOW-GASSIGNED!-OB1")))
     ;; .OUTCHAN inside such a block is the user atom's (missing) LVAL.
     (define port2 (open-output-string))
     (call-with-mdl-context
      (make-mdl-context #:output-port port2)
      (lambda ()
        (define root-outchan (mdl-root-atom "OUTCHAN"))
        (run "<SETG OB2 <MOBLIST OB2>> <INSERT \"OUTCHAN\" ,OB2>")
        (define ob2 (run ",OB2"))
        (run "<BLOCK (,OB2 <ROOT>)>")
        (define user (run "OUTCHAN"))
        (check-false (eq? user root-outchan))
        (check-eq? (mdl-apply (mdl-atom "OBLIST?") user) ob2)
        (check-exn #rx"unassigned MDL local OUTCHAN" (lambda () (run ".OUTCHAN")))
        (check-equal? (run "<PRINTSTRING \"y\">") 1)
        (run "<ENDBLOCK>")
        (check-eq? (run "OUTCHAN") root-outchan)))
     (check-equal? (get-output-string port2) "y"))))

;; (d2) The same shadowing on the compiled `run` path, as its own test-case
;;      so it is reported independently of the session-load case above:
;;      top-level and inside a function, the omitted channel stays the ROOT
;;      OUTCHAN's LVAL while a user OUTCHAN shadows ROOT on .OBLIST.
(test-case "(d2) compiled PRINTSTRING inside a shadowing BLOCK uses ROOT OUTCHAN"
  (define out (open-output-string))
  (call-with-mdl-context
   (make-mdl-context #:output-port out)
   (lambda ()
     (run "<SETG OB3 <MOBLIST OB3>> <INSERT \"OUTCHAN\" ,OB3>")
     (run "<BLOCK (,OB3 <ROOT>)>")
     (check-not-exn (lambda () (run "<PRINTSTRING \"top\">")))
     (check-not-exn
      (lambda () (run "<DEFINE R1-PS () <PRINTSTRING \"fn\">> <R1-PS>")))
     (run "<ENDBLOCK>")))
  (check-equal? (get-output-string out) "topfn"))
