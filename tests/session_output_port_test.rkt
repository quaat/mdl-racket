#lang racket/base
;; S13 part B (ADR-0050 "Explicit output port", amended 2026-11-23): a session
;; or context made without #:output-port never writes to, or flushes, the
;; host's current-output-port. Every terminal output operation and every
;; flush path is a strict error naming ADR-0050, and a parameterized sentinel
;; port stays empty. The explicit opt-in (#:follow-current-output-port? on
;; mdl-ensure-terminal-channels!) is used only by the process-wide default
;; context and #lang mdl modules; make-mdl-session/make-mdl-context refuse it.
(require rackunit racket/file racket/port
         "../mdl/loader.rkt" "../mdl/runtime/core.rkt"
         "../mdl/parser.rkt" "../mdl/compiler.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))

(define root (make-temporary-file "mdl-output-port~a" 'directory))
(call-with-output-file (build-path root "prog.mud")
  (lambda (port)
    (write-string #<<MDL
<SETG NULL <INSERT <ATOM ""> <ROOT>>>
<SETG INBUF <ISTRING 20>>
<SETG RS <STRING <ASCII 27> <ASCII 13> <ASCII 10>>>
<DEFINE ENTRY () ,NULL>
<DEFINE LOUD-ENTRY () <PRINC "entry"> ,NULL>
<DEFINE READER () <READSTRING ,INBUF ,INCHAN ,RS>>
MDL
                  port)
    (void)))
(call-with-output-file (build-path root "loud.mud")
  (lambda (port) (write-string "<PRINTSTRING \"loaded\"> <TERPRI>\n" port) (void)))

(define no-port-rx
  #rx"PRINT CHANNEL has no host-supplied output port; the runtime never falls back to the host's current-output-port \\(ADR-0050\\)")

;; Run THUNK with current-output-port parameterized to a fresh sentinel port.
;; Returns (values raised-or-#f sentinel-text).
(define (with-sentinel thunk)
  (define sentinel (open-output-string))
  (define raised
    (parameterize ([current-output-port sentinel])
      (with-handlers ([(lambda (v) #t) values]) (thunk) #f)))
  (values raised (get-output-string sentinel)))

(define (check-strict-no-write label thunk #:rx [rx no-port-rx])
  (define-values (raised text) (with-sentinel thunk))
  (check-pred exn:fail? raised label)
  (when (exn? raised) (check-regexp-match rx (exn-message raised) label))
  (check-equal? text "" (format "~a: sentinel must stay empty" label)))

;; --- a session made without #:output-port ------------------------------------
(define portless (make-mdl-session root #:input-port (open-input-string "abc\n")))
(check-equal? (hash-ref (mdl-session-load! portless "prog.mud") 'status) "PASS")
(define outchan (mdl-session-global portless "OUTCHAN"))
;; Each output operation, with the default channel (LVAL of OUTCHAN) and with
;; the CHANNEL given explicitly.
(for ([op (in-list (list (list "PRINC" "x") (list "PRIN1" 42) (list "PRINTSTRING" "abc")
                         (list "TERPRI") (list "CRLF")))])
  (check-strict-no-write (format "~a default channel" (car op))
                         (lambda () (apply mdl-session-call portless op))
                         #:rx (regexp (string-append "^[^:]*: this session's "
                                                     (object-name no-port-rx))))
  (check-strict-no-write (format "~a explicit channel" (car op))
                         (lambda () (apply mdl-session-call portless
                                           (append op (list outchan))))))
(check-strict-no-write "PRINC who" (lambda () (mdl-session-call portless "PRINC" "x"))
                       #:rx #rx"^PRINC: this session's PRINT CHANNEL")
(check-strict-no-write "PRIN1 who" (lambda () (mdl-session-call portless "PRIN1" 42))
                       #:rx #rx"^PRIN1: this session's PRINT CHANNEL")
;; Argument errors keep Confusion's order: they are reported before the host
;; port is resolved (a missing port never hides them).
(check-strict-no-write "PRINTSTRING buffer before port"
                       (lambda () (mdl-session-call portless "PRINTSTRING" 5 outchan))
                       #:rx #rx"STRING buffer")
(check-strict-no-write "PRINC TYPE before port"
                       (lambda () (mdl-session-call portless "PRINC" (mdl-session-atom portless "FOO")))
                       #:rx #rx"^PRINC: unsupported TYPE")
(check-strict-no-write "PRINC channel check before port"
                       (lambda () (mdl-session-call portless "PRINC" "x"
                                                    (mdl-session-global portless "INCHAN")))
                       #:rx #rx"output channel")
;; READSTRING's pre-read flush is strict too, and it fails before any input is
;; consumed.
(let ([in (open-input-string "abc\n")])
  (define s (make-mdl-session root #:input-port in))
  (check-equal? (hash-ref (mdl-session-load! s "prog.mud") 'status) "PASS")
  (check-strict-no-write "READSTRING pre-read flush"
                         (lambda () (mdl-session-call s "READER"))
                         #:rx #rx"^READSTRING: this session's PRINT CHANNEL")
  (check-equal? (port->string in) "abc\n"))
;; Output during a load (VFLOAD's PRINTSTRING/TERPRI) fails the load strictly.
(let ([s (make-mdl-session root)] [raised-report #f])
  (define-values (raised text)
    (with-sentinel (lambda () (set! raised-report (mdl-session-load! s "loud.mud")))))
  (check-false raised)
  (check-equal? text "")
  (check-equal? (hash-ref raised-report 'status) "FAIL")
  (check-regexp-match no-port-rx (hash-ref (hash-ref raised-report 'failure) 'exception)))
;; The host loop still refuses a session without both explicit ports.
(check-strict-no-write "run-interactive without output port"
                       (lambda () (mdl-session-run-interactive portless "ENTRY"))
                       #:rx #rx"requires a session made with explicit #:input-port and #:output-port \\(ADR-0050\\)")

;; --- a context made without #:output-port (core level) -----------------------
(define (in-portless-context thunk #:input [input "abc\n"])
  (parameterize ([current-namespace ns])
    (call-with-mdl-context
     (make-mdl-context #:input-port (open-input-string input))
     thunk)))
(define (run-mdl source)
  (for/fold ([r #f]) ([expr (in-list (compile-program (parse-mdl source)))])
    (eval expr)))
(for ([source (in-list '("<PRINC \"x\">" "<PRIN1 42>" "<PRINTSTRING \"abc\">"
                         "<TERPRI>" "<CRLF>"
                         "<READSTRING <ISTRING 3> ,INCHAN>"))])
  (check-strict-no-write (format "context ~a" source)
                         (lambda () (in-portless-context (lambda () (run-mdl source))))))

;; --- the host loop's final flush (F2): secondary, never masking a primary -----
;; The entry value print is the first output: it raises (primary); the final
;; flush's strict error is recorded as its secondary failure.
(let ()
  (define-values (raised text)
    (with-sentinel
     (lambda ()
       (in-portless-context
        (lambda () (mdl-run-host-loop (lambda () 7) #:max-passes 1))))))
  (check-regexp-match #rx"^PRIN1: this session's PRINT CHANNEL" (exn-message raised))
  (define secondary (mdl-host-loop-secondary-failures raised))
  (check-equal? (length secondary) 1)
  (check-regexp-match #rx"^host-loop: this session's PRINT CHANNEL" (exn-message (car secondary)))
  (check-equal? text ""))
;; A primary raised by the entry itself is re-raised unchanged (same object).
(let ()
  (define boom (exn:fail "boom" (current-continuation-marks)))
  (define-values (raised text)
    (with-sentinel
     (lambda ()
       (in-portless-context
        (lambda () (mdl-run-host-loop (lambda () (raise boom))))))))
  (check-eq? raised boom)
  (check-equal? (length (mdl-host-loop-secondary-failures boom)) 1)
  (check-regexp-match no-port-rx (exn-message (car (mdl-host-loop-secondary-failures boom))))
  (check-equal? text ""))
;; Nothing raised (a host escape out of ON-EVENT): the flush failure itself is
;; raised. A flush that fell back to current-output-port would return quietly.
(let ()
  (define-values (raised text)
    (with-sentinel
     (lambda ()
       (in-portless-context
        (lambda ()
          (let/ec escape
            (mdl-run-host-loop (lambda () 7)
                               #:on-event (lambda (e) (escape 'escaped)))))))))
  (check-pred exn:fail? raised)
  (check-regexp-match #rx"^host-loop: this session's PRINT CHANNEL" (exn-message raised))
  (check-equal? text ""))

;; --- normal output reaches the supplied port, never the sentinel --------------
(let* ([out (open-output-string)]
       [in (open-input-string "go\n")]
       [s (make-mdl-session root #:input-port in #:output-port out)])
  (check-equal? (hash-ref (mdl-session-load! s "prog.mud") 'status) "PASS")
  (define-values (raised text)
    (with-sentinel
     (lambda ()
       (mdl-session-call s "PRINC" "a")
       (mdl-session-call s "PRIN1" 42)
       (mdl-session-call s "PRINTSTRING" "bcd" (mdl-session-global s "OUTCHAN") 2)
       (mdl-session-call s "TERPRI")
       (mdl-session-call s "CRLF")
       (check-equal? (mdl-session-call s "READER") 2))))
  (check-false raised)
  (check-equal? text "")
  (check-equal? (get-output-string out) "a42bc\n\n"))
;; The host loop with both ports: entry print and final flush go to OUT.
(let* ([out (open-output-string)]
       [s (make-mdl-session root #:input-port (open-input-string "") #:output-port out)])
  (check-equal? (hash-ref (mdl-session-load! s "prog.mud") 'status) "PASS")
  (define-values (raised text)
    (with-sentinel (lambda () (mdl-session-run-interactive s "LOUD-ENTRY" #:max-passes 1))))
  ;; REP is the default (inert) REP: the loop's first pass fails strictly.
  (check-regexp-match #rx"REP" (exn-message raised))
  (check-equal? text "")
  (check-equal? (get-output-string out) "entry\n"))
(let ([out (open-output-string)])
  (define-values (raised text)
    (with-sentinel
     (lambda ()
       (parameterize ([current-namespace ns])
         (call-with-mdl-context (make-mdl-context #:output-port out)
                                (lambda () (run-mdl "<PRINC \"ok\"> <CRLF>")))))))
  (check-false raised)
  (check-equal? text "")
  (check-equal? (get-output-string out) "ok\n"))

;; --- the explicit opt-in -------------------------------------------------------
;; The process-wide default context (no session) follows current-output-port.
(let-values ([(raised text)
              (with-sentinel (lambda ()
                               (parameterize ([current-namespace ns])
                                 (run-mdl "<PRINC \"ambient\"> <CRLF>"))))])
  (check-false raised)
  (check-equal? text "ambient\n"))
;; make-mdl-session and make-mdl-context do not accept the opt-in.
(check-exn exn:fail:contract?
           (lambda () (keyword-apply make-mdl-session '(#:follow-current-output-port?) '(#t)
                                     (list root))))
(check-exn exn:fail:contract?
           (lambda () (keyword-apply make-mdl-context '(#:follow-current-output-port?) '(#t) '())))
;; The opt-in and an explicit port are mutually exclusive.
(check-exn #rx"mdl-ensure-terminal-channels!: .*either"
           (lambda ()
             (parameterize ([current-mdl-globals (make-hasheq)]
                            [current-mdl-locals (list (make-hasheq))]
                            [current-mdl-atom-space (make-mdl-atom-space)])
               (mdl-ensure-terminal-channels! #:output-port (open-output-string)
                                              #:follow-current-output-port? #t))))
;; A fresh space given the opt-in follows current-output-port; one without it
;; is strict.
(for ([follow? (in-list '(#t #f))])
  (define-values (raised text)
    (with-sentinel
     (lambda ()
       (parameterize ([current-namespace ns]
                      [current-mdl-globals (make-hasheq)]
                      [current-mdl-locals (list (make-hasheq))]
                      [current-mdl-atom-space (make-mdl-atom-space)])
         (mdl-ensure-terminal-channels! #:follow-current-output-port? follow?)
         (run-mdl "<PRINC \"opt\">")))))
  (cond [follow? (check-false raised) (check-equal? text "opt")]
        [else (check-regexp-match no-port-rx (exn-message raised))
              (check-equal? text "")]))

;; S13 independent review: (1) a host-made terminal CHANNEL must carry a real
;; port, so no stray port-less PRINT channel can break READSTRING's pre-read
;; flush or the final flush of a session whose OUTCHAN has a port; (4) the
;; opt-in keyword takes a boolean only.
(check-exn #rx"requires a Racket port"
           (lambda () (mdl-make-terminal-channel "PRINT" #f)))
(check-exn #rx"requires a Racket port"
           (lambda () (mdl-make-terminal-channel "READ" #f)))
(check-exn #rx"boolean\\?"
           (lambda ()
             (parameterize ([current-mdl-globals (make-hasheq)]
                            [current-mdl-locals (list (make-hasheq))]
                            [current-mdl-atom-space (make-mdl-atom-space)])
               (mdl-ensure-terminal-channels! #:follow-current-output-port? 'no))))
;; A host-made PRINT channel with a real port leaves READSTRING working.
(let* ([out (open-output-string)]
       [ctx (make-mdl-context #:output-port out #:input-port (open-input-string "ab\n"))])
  (call-with-mdl-context
   ctx
   (lambda ()
     (mdl-make-terminal-channel "PRINT" (open-output-string))
     (parameterize ([current-namespace ns])
       (check-equal? (run-mdl "<READSTRING <ISTRING 5> .INCHAN <STRING <ASCII 10>>>") 2)))))

(delete-directory/files root)
