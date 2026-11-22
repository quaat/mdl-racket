#lang racket/base
;; Review R1: session-owned CHANNEL host ports and default OUTCHAN resolution.
;; Evidence: docs/evidence/M3/review/R1.md, r1-channel-reference.json.
(require rackunit racket/file racket/runtime-path
         "../mdl/runtime/core.rkt" "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/loader.rkt")

(define-runtime-path standalone-fixture "fixtures/printstring.mdl")
(define-namespace-anchor anchor)
(define test-namespace (namespace-anchor->namespace anchor))

;; Fresh non-loader context: globals, locals, atom space; no session.
(define (in-fresh-context thunk)
  (parameterize ([current-namespace test-namespace]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (thunk)))

(define (run source)
  (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
    (eval expr)))

(define (capture thunk)
  (define port (open-output-string))
  (define result (parameterize ([current-output-port port]) (thunk)))
  (values result (get-output-string port)))

;; 1. Standalone #lang mdl module: no loader session binds OUTCHAN.
(test-case "Standalone #lang mdl module: no loader session binds OUTCHAN."
  (parameterize ([current-mdl-globals (make-hasheq)])
    (define-values (_ output)
      (capture (lambda () (dynamic-require standalone-fixture #f))))
    (check-equal? (mdl-gval "R1-PS-RESULT") 10)
    (check-regexp-match #rx"^standalone" output)))

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

;; 7. Default terminal channels follow the current Racket port per call.
(test-case "Default terminal channels follow the current Racket port per call."
  (in-fresh-context
   (lambda ()
     (define-values (_a first) (capture (lambda () (run "<PRINTSTRING \"one\">"))))
     (define-values (_b second) (capture (lambda () (run "<PRINTSTRING \"two\">"))))
     (check-equal? first "one")
     (check-equal? second "two"))))

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
