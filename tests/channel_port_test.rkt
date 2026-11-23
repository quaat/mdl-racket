#lang racket/base
;; Review R1: session-owned CHANNEL host ports and default OUTCHAN resolution.
;; Evidence: docs/evidence/M3/review/R1.md, r1-channel-reference.json.
(require rackunit racket/file racket/runtime-path
         "../mdl/runtime/core.rkt" "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/loader.rkt")

(define-runtime-path standalone-fixture "fixtures/printstring.mdl")
(define-runtime-path gdecl-fixture "fixtures/channel-gdecl.mdl")
(define-runtime-path mutate-fixture "fixtures/channel-mutate.mdl")
(define-runtime-path print-fixture "fixtures/channel-print.mdl")
(define-namespace-anchor anchor)
(define test-namespace (namespace-anchor->namespace anchor))
(define-runtime-path core-module "../mdl/runtime/core.rkt")

;; A fresh namespace (so a fixture module instantiates again) that shares
;; THIS runtime instance; a plain make-base-namespace would load a second
;; core.rkt with its own parameters and default context.
(define (fresh-mdl-namespace)
  (define ns (make-base-namespace))
  (namespace-attach-module test-namespace core-module ns)
  ns)

;; Fresh non-loader context from the shared context constructor. S13 part B
;; (ADR-0050): a context writes only to an explicit host port, so each fresh
;; context gets its own string port, read back by capture.
(define current-context-out (make-parameter #f))
(define (in-fresh-context thunk)
  (define out (open-output-string))
  (parameterize ([current-namespace test-namespace]
                 [current-context-out out])
    (call-with-mdl-context (make-mdl-context #:output-port out) thunk)))

(define (run source)
  (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
    (eval expr)))

;; Output written by THUNK. Inside in-fresh-context: what reached the
;; context's own port, and nothing may reach the (parameterized) host
;; current-output-port. Elsewhere (the process-wide default context and
;; #lang mdl modules, the explicit follow-current-output-port opt-in): what
;; reached current-output-port.
(define (capture thunk)
  (define port (open-output-string))
  (define context-out (current-context-out))
  (define before (and context-out (string-length (get-output-string context-out))))
  (define result (parameterize ([current-output-port port]) (thunk)))
  (cond [context-out
         (check-equal? (get-output-string port) "" "a context never writes to current-output-port")
         (values result (substring (get-output-string context-out) before))]
        [else (values result (get-output-string port))]))

;; 0. The default context is initialized by the runtime itself (end of
;;    core.rkt), before any #lang mdl module runs: nothing above has
;;    instantiated an MDL module yet.
(test-case "The process-wide default context has INCHAN/OUTCHAN at load."
  (check-equal? (mdl-atom-pname (mdl-type (mdl-gval "OUTCHAN"))) "CHANNEL")
  (check-equal? (mdl-atom-pname (mdl-type (mdl-lval "INCHAN"))) "CHANNEL")
  (define-values (n output)
    (capture (lambda () ((mdl-gval "PRINTSTRING") "boot"))))
  (check-equal? n 4)
  (check-equal? output "boot"))

;; 1. Standalone #lang mdl module in the process-wide default context.
(test-case "Standalone #lang mdl module: no loader session binds OUTCHAN."
  (define-values (_ output)
    (capture (lambda () (dynamic-require standalone-fixture #f))))
  (check-equal? (mdl-gval "R1-PS-RESULT") 10)
  (check-regexp-match #rx"^standalone" output)
  ;; The default context itself has the bindings, with no setup at all.
  (define-values (n direct)
    (capture (lambda () ((mdl-gval "PRINTSTRING") "dflt"))))
  (check-equal? n 4)
  (check-equal? direct "dflt"))

;; 2. Direct runtime call with the default channel.
(test-case "Direct runtime call with the default channel."
  (in-fresh-context
   (lambda ()
     (define-values (n output)
       (capture (lambda () ((mdl-gval "PRINTSTRING") "direct"))))
     (check-equal? n 6)
     (check-equal? output "direct"))))

;; 3. Interpreted evaluation path.
(test-case "Interpreted evaluation path."
  (in-fresh-context
   (lambda ()
     (define-values (n output)
       (capture (lambda ()
                  (mdl-eval (mdl-make-form
                             (mdl-list (mdl-atom "PRINTSTRING") "interp"))))))
     (check-equal? n 6)
     (check-equal? output "interp"))))

;; 4. Compiled evaluation path, including TERPRI and CRLF defaults.
(test-case "Compiled evaluation path, including TERPRI and CRLF defaults."
  (in-fresh-context
   (lambda ()
     (define-values (result output)
       (capture (lambda () (run "<PRINTSTRING \"ab\"> <TERPRI> <CRLF>"))))
     (check-equal? (mdl-atom-pname result) "T")
     (check-equal? output "ab\n\n"))))

;; 5. Initial LVAL and GVAL are the same ROOT terminal CHANNELs.
(test-case "Initial LVAL and GVAL are the same ROOT terminal CHANNELs."
  (in-fresh-context
   (lambda ()
     (check-equal? (mdl-atom-pname (run "<==? .OUTCHAN ,OUTCHAN>")) "T")
     (check-equal? (mdl-atom-pname (run "<==? .INCHAN ,INCHAN>")) "T")
     (check-equal? (mdl-atom-pname (run "<==? OUTCHAN OUTCHAN!-ROOT>")) "T")
     (check-equal? (mdl-atom-pname (run "<TYPE .OUTCHAN>")) "CHANNEL")
     (check-equal? (run "<NTH .OUTCHAN 2>") "PRINT")
     (check-equal? (run "<NTH .INCHAN 2>") "READ")
     (check-equal? (mdl-atom-pname (run "<ASSIGNED? OUTCHAN>")) "T"))))

;; 6. The omitted channel is the LVAL of OUTCHAN, not the GVAL (Confusion
;;    setg-outchan-default-uses-lval, prog-bound-*-default).
(test-case "The omitted channel is the LVAL of OUTCHAN, not the GVAL."
  (in-fresh-context
   (lambda ()
     (define-values (n output)
       (capture (lambda () (run "<SETG OUTCHAN .INCHAN> <PRINTSTRING \"lv\">"))))
     (check-equal? n 2)
     (check-equal? output "lv")))
  (in-fresh-context
   (lambda ()
     (check-exn #rx"output channel"
                (lambda () (run "<PROG ((OUTCHAN .INCHAN)) <PRINTSTRING \"x\">>")))
     (check-exn #rx"non-channel"
                (lambda () (run "<PROG ((OUTCHAN 5)) <PRINTSTRING \"x\">>")))
     (define-values (_ output)
       (capture (lambda ()
                  (run "<PROG ((OUTCHAN ,OUTCHAN)) <PRINTSTRING \"pg\">>"))))
     (check-equal? output "pg"))))

;; 7. S13 part B: only the process-wide default context (the explicit
;;    follow-current-output-port opt-in) follows the current Racket port per
;;    call; a fresh context writes every call to its own port.
(test-case "Only the default context follows the current Racket port per call."
  (parameterize ([current-namespace test-namespace])
    (define-values (_a first) (capture (lambda () (run "<PRINTSTRING \"one\">"))))
    (define-values (_b second) (capture (lambda () (run "<PRINTSTRING \"two\">"))))
    (check-equal? first "one")
    (check-equal? second "two"))
  (in-fresh-context
   (lambda ()
     (define-values (_a first) (capture (lambda () (run "<PRINTSTRING \"one\">"))))
     (define-values (_b second) (capture (lambda () (run "<PRINTSTRING \"two\">"))))
     (check-equal? first "one")
     (check-equal? second "two")
     (check-equal? (get-output-string (current-context-out)) "onetwo"))))

;; 8. Counts and invalid arguments.
(test-case "Counts and invalid arguments."
  (in-fresh-context
   (lambda ()
     (define-values (n output)
       (capture (lambda () (run "<PRINTSTRING \"abcdef\" .OUTCHAN 2>"))))
     (check-equal? n 2)
     (check-equal? output "ab")
     (define-values (m over)
       (capture (lambda () (run "<PRINTSTRING \"ab\" ,OUTCHAN 9>"))))
     (check-equal? m 2)
     (check-equal? over "ab")
     (check-exn #rx"non-channel" (lambda () (run "<PRINTSTRING \"x\" 5>")))
     (check-exn #rx"non-channel" (lambda () (run "<PRINTSTRING \"x\" [1 2]>")))
     (check-exn #rx"PRINTSTRING requires an output channel"
                (lambda () (run "<PRINTSTRING \"x\" .INCHAN>")))
     (check-exn #rx"TERPRI requires an output channel"
                (lambda () (run "<TERPRI .INCHAN>")))
     (check-exn #rx"CRLF requires an output channel"
                (lambda () (run "<CRLF .INCHAN>")))
     (check-exn #rx"count" (lambda () (run "<PRINTSTRING \"x\" .OUTCHAN -1>")))
     (check-exn #rx"STRING buffer" (lambda () (run "<PRINTSTRING 5 .OUTCHAN>")))
     (check-exn #rx"output port"
                (lambda () (mdl-make-terminal-channel "PRINT" (open-input-string ""))))
     (check-exn #rx"input port"
                (lambda () (mdl-make-terminal-channel "READ" (open-output-string))))
     ;; Like Confusion, the CHANNEL's mode slot must still say PRINT.
     (check-exn #rx"PRINTSTRING requires an output channel"
                (lambda () (run "<PUT .OUTCHAN 2 \"READ\"> <PRINTSTRING \"x\">"))))))

;; 9. Each atom space owns its default channels; a foreign one is rejected.
(test-case "Each atom space owns its default channels; a foreign one is rejected."
  (define foreign
    (in-fresh-context (lambda () (run ".OUTCHAN"))))
  (in-fresh-context
   (lambda ()
     (check-false (eq? foreign (run ".OUTCHAN")))
     (check-exn #rx"not open in this MDL session"
                (lambda () ((mdl-gval "PRINTSTRING") "x" foreign))))))

;; 10. Loader sessions write to their injected port, not process stdout,
;;     and two sessions never cross.
(test-case "Loader sessions write to their injected ports and never cross."
  (define root (make-temporary-file "mdl-channel-port~a" 'directory))
  (call-with-output-file (build-path root "hello.mud")
    (lambda (out) (void (write-string "<PRINTSTRING \"loaded\"> <CRLF>" out))))
  (define port-a (open-output-string))
  (define port-b (open-output-string))
  (define session-a (make-mdl-session root #:output-port port-a))
  (define session-b (make-mdl-session root #:output-port port-b))
  (define-values (_ stray)
    (capture
     (lambda ()
       (check-equal? (mdl-session-call session-a "PRINTSTRING" "A1") 2)
       (check-equal? (mdl-session-call session-b "PRINTSTRING" "B1"
                                       (mdl-session-global session-b "OUTCHAN")) 2)
       (mdl-session-call session-a "TERPRI")
       (mdl-session-call session-b "CRLF" (mdl-session-global session-b "OUTCHAN"))
       (mdl-session-load! session-a "hello.mud"))))
  (check-equal? stray "")
  (check-equal? (get-output-string port-a) "A1\nloaded\n")
  (check-equal? (get-output-string port-b) "B1\n")
  (check-exn #rx"not open in this MDL session"
             (lambda ()
               (mdl-session-call session-b "PRINTSTRING" "x"
                                 (mdl-session-global session-a "OUTCHAN"))))
  (check-equal? (get-output-string port-b) "B1\n")
  (check-exn #rx"output-port"
             (lambda () (make-mdl-session root #:output-port (open-input-string ""))))
  (check-exn #rx"input-port"
             (lambda () (make-mdl-session root #:input-port (open-output-string))))
  (delete-directory/files root))

;; 11. Review item 1: the initial bindings are real table entries, so GDECL,
;;     MANIFEST, SETG and ASSIGNED?/GASSIGNED? see them.
(test-case "Initial INCHAN/OUTCHAN bindings are visible to GDECL and MANIFEST."
  (in-fresh-context
   (lambda ()
     (check-equal? (mdl-atom-pname (run "<GASSIGNED? OUTCHAN>")) "T")
     (check-equal? (mdl-atom-pname (run "<ASSIGNED? INCHAN>")) "T")
     (check-equal? (mdl-atom-pname
                    (run "<GDECL (OUTCHAN) CHANNEL> <GASSIGNED? OUTCHAN>")) "T")
     (define-values (n output)
       (capture (lambda () (run "<PRINTSTRING \"g\" ,OUTCHAN>"))))
     (check-equal? n 1)
     (check-equal? output "g")))
  ;; This runtime's GDECL checks an existing value (pinned Confusion does not;
  ;; r1-followup-reference.json gdecl-fix-mismatch).
  (in-fresh-context
   (lambda ()
     (check-exn #rx"existing value does not satisfy GDECL"
                (lambda () (run "<GDECL (OUTCHAN INCHAN) FIX>")))))
  ;; This runtime refuses to change an assigned MANIFEST (Confusion allows it;
  ;; r1-followup-reference.json manifest-setg).
  (in-fresh-context
   (lambda ()
     (check-exn #rx"ATTEMPT-TO-CHANGE-MANIFEST-VARIABLE"
                (lambda () (run "<MANIFEST OUTCHAN> <SETG OUTCHAN 5>")))))
  ;; Same in the process-wide default context used by standalone modules.
  (define-values (_ output)
    (capture (lambda () (dynamic-require gdecl-fixture #f))))
  (check-equal? (mdl-atom-pname (mdl-gval "R1-GD-ASSIGNED")) "T")
  (check-equal? (mdl-gval "R1-GD-RESULT") 1)
  ;; Module-level results are also printed; PRINTSTRING's "g" precedes 1.
  (check-regexp-match #rx"\ng1\n$" output))

;; 12. Review item 2: channels belong to a context. Modules run in different
;;     contexts get different CHANNEL objects; modules run in the SAME context
;;     share its channels exactly as they share every other global.
(test-case "Each context owns its channels; one context is shared by its modules."
  ;; S13 part B: each context has its own explicit output port.
  (define out-a (open-output-string))
  (define out-b (open-output-string))
  (define ctx-a (make-mdl-context #:output-port out-a))
  (define ctx-b (make-mdl-context #:output-port out-b))
  (capture (lambda ()
             (call-with-mdl-context ctx-a
               (lambda () (dynamic-require mutate-fixture #f)))))
  (define-values (_ stray)
    (capture (lambda ()
               (call-with-mdl-context ctx-b
                 (lambda () (dynamic-require print-fixture #f))))))
  (check-regexp-match #rx"^from-b" (get-output-string out-b))
  (check-false (regexp-match? #rx"from-b" (get-output-string out-a)))
  (check-false (regexp-match? #rx"from-b" stray))
  (check-equal? (call-with-mdl-context ctx-b (lambda () (mdl-gval "R1-B-RESULT"))) 6)
  (check-false (eq? (call-with-mdl-context ctx-a (lambda () (mdl-gval "OUTCHAN")))
                    (call-with-mdl-context ctx-b (lambda () (mdl-gval "OUTCHAN")))))
  ;; Shared-context boundary, in a fresh namespace so both modules instantiate.
  (define ctx-shared (make-mdl-context #:output-port (open-output-string)))
  (parameterize ([current-namespace (fresh-mdl-namespace)])
    (call-with-mdl-context ctx-shared
      (lambda ()
        (capture (lambda () (dynamic-require mutate-fixture #f)))
        (check-exn #rx"PRINTSTRING requires an output channel"
                   (lambda () (dynamic-require print-fixture #f)))))))

;; 13. Review item 4: the host port is keyed by the CHANNEL's backing storage,
;;     so another view of the same storage typed CHANNEL reaches the same port.
;;     (REST of a CHANNEL is a VECTOR, also in Confusion: r1-followup-reference
;;     rest-type, rest0-printstring.)
(test-case "CHANNEL host lookup follows the backing storage, not the view."
  (in-fresh-context
   (lambda ()
     (check-equal? (mdl-atom-pname (run "<TYPE <REST .OUTCHAN 0>>")) "VECTOR")
     (check-exn #rx"non-channel"
                (lambda () (run "<PRINTSTRING \"x\" <REST .OUTCHAN 0>>")))
     (define-values (n output)
       (capture (lambda ()
                  (run "<PRINTSTRING \"rt\" <CHTYPE <CHTYPE .OUTCHAN VECTOR> CHANNEL>>"))))
     (check-equal? n 2)
     (check-equal? output "rt")
     (define-values (m view)
       (capture (lambda ()
                  (run "<PRINTSTRING \"rv\" <CHTYPE <REST .OUTCHAN 0> CHANNEL>>"))))
     (check-equal? m 2)
     (check-equal? view "rv")
     ;; A view shifted by REST 1 no longer has PRINT in its mode slot.
     (check-exn #rx"PRINTSTRING requires an output channel"
                (lambda () (run "<PRINTSTRING \"x\" <CHTYPE <REST .OUTCHAN 1> CHANNEL>>")))
     ;; A VECTOR that never was a host channel is not open in this session.
     (check-exn #rx"not open in this MDL session"
                (lambda ()
                  (run "<PRINTSTRING \"x\" <CHTYPE [0 \"PRINT\"] CHANNEL>>"))))))

;; 14. Review item 5: argument checks follow Confusion's order (channel type,
;;     channel mode, buffer, count); r1-followup-reference order-* cases.
(test-case "PRINTSTRING argument-check order matches Confusion."
  (in-fresh-context
   (lambda ()
     (check-exn #rx"PRINTSTRING requires an output channel"
                (lambda () (run "<PRINTSTRING 5 .INCHAN>")))
     (check-exn #rx"non-channel" (lambda () (run "<PRINTSTRING 5 6>")))
     (check-exn #rx"STRING buffer"
                (lambda () (run "<PRINTSTRING 5 .OUTCHAN -1>"))))))

;; 15. A #lang mdl module gives a context WITHOUT INCHAN/OUTCHAN its initial
;;     bindings (module-begin call site); output reaches that context's port.
(test-case "A #lang mdl module initializes a context that lacks channels."
  (define globals (make-hasheq))
  (define bare (list (make-hasheq)))
  (define space (make-mdl-atom-space))
  (parameterize ([current-namespace (fresh-mdl-namespace)]
                 [current-mdl-globals globals]
                 [current-mdl-locals bare]
                 [current-mdl-atom-space space])
    (check-true (mdl-false? ((mdl-gval "GASSIGNED?") "OUTCHAN")))
    (define-values (_ output)
      (capture (lambda () (dynamic-require print-fixture #f))))
    (check-regexp-match #rx"^from-b" output)
    (check-equal? (mdl-gval "R1-B-RESULT") 6)
    (check-equal? (mdl-atom-pname (mdl-type (mdl-gval "OUTCHAN"))) "CHANNEL")
    (check-eq? (mdl-lval "OUTCHAN") (mdl-gval "OUTCHAN"))))
