#lang racket/base
;; S7 (ADR-0049 part 3, ADR-0050): the host top-level loop
;; mdl-session-run-interactive on small synthetic programs. The faithful game
;; path is tests/historical_interactive_test.rkt.
(require rackunit racket/file racket/port
         "../mdl/loader.rkt" "../mdl/runtime/core.rkt")

(define root (make-temporary-file "mdl-host-loop~a" 'directory))
(call-with-output-file (build-path root "prog.mud")
  (lambda (port)
    (write-string #<<MDL
<SETG NULL <INSERT <ATOM ""> <ROOT>>>
<SETG INBUF <ISTRING 20>>
<SETG RS <STRING <ASCII 27> <ASCII 13> <ASCII 10>>>
<DEFINE ECHOER ("AUX" N)
  <REPEAT ()
    <PRINC ">">
    <SET N <READSTRING ,INBUF ,INCHAN ,RS>>
    <COND (<0? .N> <PRINC "Beg pardon?"> <CRLF>)
          (T <PRINTSTRING ,INBUF ,OUTCHAN .N> <CRLF>)>>>
<DEFINE ENTRY () <SETG ENTERED T> <SETG REP ,ECHOER> <RESET ,INCHAN> ,NULL>
<DEFINE NOREP () <GUNASSIGN REP> ,NULL>
<DEFINE KEEPREP () ,NULL>
<DEFINE BADREP () <SETG REP 7> ,NULL>
<DEFINE FAILING () <ERROR ENTRY-FAILED>>
<DEFINE R1 () <PRINC "1"> <SETG REP ,R2>>
<DEFINE R2 () <PRINC "2">>
<DEFINE SWITCHER () <SETG REP ,R1> 5>
<DEFINE STRVAL () <SETG REP ,R2> "s">
MDL
                  port)
    (void)))

;; A session with explicit ports, loaded with prog.mud.
(define (session-with input)
  (define in (open-input-string input))
  (define out (open-output-string))
  (define s (make-mdl-session root #:input-port in #:output-port out))
  (check-equal? (hash-ref (mdl-session-load! s "prog.mud") 'status) "PASS")
  (values s in out))
;; A pass bound keeps a broken loop from hanging the suite.
(define (run entry input #:max-passes [max-passes 10])
  (define-values (s in out) (session-with input))
  (define events '())
  (define failure
    (with-handlers ([exn:fail? values])
      (mdl-session-run-interactive s entry #:max-passes max-passes
                                   #:on-event (lambda (e) (set! events (cons e events))))
      'returned))
  (values failure (get-output-string out) (reverse events) s in))

;; --- the normal path: entry value printed, REP applied, D3 end of input -----
(let-values ([(failure output events s in) (run "ENTRY" "north\nwest\n")])
  (check-pred exn:fail:mdl-input-exhausted? failure)
  (check-regexp-match #rx"^READSTRING: input exhausted" (exn-message failure))
  ;; D1: PRIN1 of ,NULL prints nothing, then TERPRI; no banner, no "DONE".
  (check-equal? output "\n>north\n>west\n>Beg pardon?\n>")
  (check-equal? (map car events) '(entry-returned pass))
  (check-eq? (cadr (car events)) (mdl-session-global s "NULL"))
  (check-equal? (cadr events) '(pass 1))   ; ECHOER never returns: one pass
  (check-equal? (port->string in) ""))
;; A partial last line is read, then input is exhausted.
(let-values ([(failure output events s in) (run "ENTRY" "north\nwe")])
  (check-pred exn:fail:mdl-input-exhausted? failure)
  (check-equal? output "\n>north\n>we\n>"))
;; No input at all: one mirrored empty read, then the strict error.
(let-values ([(failure output events s in) (run "ENTRY" "")])
  (check-pred exn:fail:mdl-input-exhausted? failure)
  (check-equal? output "\n>Beg pardon?\n>"))

;; --- every pass re-reads the GVAL of REP --------------------------------------
(let-values ([(failure output events s in) (run "SWITCHER" "" #:max-passes 3)])
  (check-regexp-match #rx"^host-loop: the host loop exceeded its bound of 3 passes" (exn-message failure))
  ;; Entry value 5 printed by PRIN1; pass 1 applies R1, which SETGs REP to R2.
  (check-equal? output "5\n122")
  (check-equal? events '((entry-returned 5) (pass 1) (pass 2) (pass 3))))

;; --- strict failures ------------------------------------------------------------
;; The entry raises: the loop never starts and prints nothing.
(let-values ([(failure output events s in) (run "FAILING" "north\n")])
  (check-regexp-match #rx"ENTRY-FAILED" (exn-message failure))
  (check-false (exn:fail:mdl-input-exhausted? failure))
  (check-equal? output "")
  (check-equal? events '())
  (check-equal? (port->string in) "north\n"))
;; The default REP is never a REPL (ADR-0049).
(let-values ([(failure output events s in) (run "KEEPREP" "<+ 1 2>\n")])
  (check-regexp-match #rx"REP: the default REP SUBR is inert; .*ADR-0049" (exn-message failure))
  (check-equal? output "\n")
  (check-equal? (port->string in) "<+ 1 2>\n"))
(let-values ([(failure output events s in) (run "NOREP" "")])
  (check-regexp-match #rx"^host-loop: the GVAL of REP is unassigned" (exn-message failure)))
(let-values ([(failure output events s in) (run "BADREP" "")])
  (check-regexp-match #rx"^host-loop: the GVAL of REP is not an applicable" (exn-message failure)))
;; An entry value PRIN1 cannot print is a strict error before any pass.
(let-values ([(failure output events s in) (run "STRVAL" "")])
  (check-regexp-match #rx"^PRIN1: unsupported TYPE STRING" (exn-message failure))
  (check-equal? (map car events) '(entry-returned)))
(let-values ([(failure output events s in) (run "NO-SUCH-ENTRY" "")])
  (check-regexp-match #rx"NO-SUCH-ENTRY" (exn-message failure))
  (check-equal? events '()))
;; The session must own explicit ports: never the process's own stdin.
(let ([s (make-mdl-session root)])
  (mdl-session-load! s "prog.mud")
  (check-exn #rx"explicit #:input-port and #:output-port"
             (lambda () (mdl-session-run-interactive s "ENTRY")))
  (check-exn #rx"unassigned MDL global ENTERED"
             (lambda () (mdl-session-global s "ENTERED"))))
(let ([s (make-mdl-session root #:output-port (open-output-string))])
  (check-exn #rx"explicit #:input-port and #:output-port"
             (lambda () (mdl-session-run-interactive s "ENTRY"))))
(let-values ([(s in out) (session-with "")])
  (check-exn #rx"exact-positive-integer"
             (lambda () (mdl-session-run-interactive s "ENTRY" #:max-passes 0)))
  (check-exn #rx"string"
             (lambda () (mdl-session-run-interactive s 'ENTRY))))

;; --- output is flushed when the loop ends -----------------------------------
(let* ([path (build-path root "out.txt")]
       [file-out (open-output-file path #:exists 'truncate)]
       [s (make-mdl-session root #:input-port (open-input-string "")
                            #:output-port file-out)])
  (mdl-session-load! s "prog.mud")
  (check-exn exn:fail:mdl-input-exhausted?
             (lambda () (mdl-session-run-interactive s "ENTRY")))
  (check-equal? (file->string path) "\n>Beg pardon?\n>")
  (close-output-port file-out))
;; Output written with no later read (the entry value and two passes, then the
;; pass bound) is flushed by the loop's exit, before the port is closed.
(let* ([path (build-path root "out2.txt")]
       [file-out (open-output-file path #:exists 'truncate)]
       [s (make-mdl-session root #:input-port (open-input-string "")
                            #:output-port file-out)])
  (mdl-session-load! s "prog.mud")
  (check-exn #rx"exceeded its bound of 2 passes"
             (lambda () (mdl-session-run-interactive s "SWITCHER" #:max-passes 2)))
  (check-equal? (file->string path) "5\n12")   ; before close-output-port
  (close-output-port file-out))

(delete-directory/files root)
