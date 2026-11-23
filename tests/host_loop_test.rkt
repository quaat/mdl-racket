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

;; --- the final flush never masks the failure that ends the loop (review F2) ----
;; A session whose output port's flush fails from the FAIL-FROM-th flush on
;; (writes always succeed). Returns the session, the output collector and a
;; box counting zero-length write requests: Racket sends a flush to a custom
;; port as one, and so is an empty write (PRIN1 of ,NULL writes ""), so the
;; counts below include the entry value's empty PRIN1.
(define (session-with-flaky-flush input fail-from)
  (define collected (open-output-string))
  (define flushes (box 0))
  (define out
    (make-output-port
     'flaky-flush always-evt
     (lambda (bs start end non-block? breakable?)
       (cond [(= start end)               ; a flush request
              (set-box! flushes (add1 (unbox flushes)))
              (when (>= (unbox flushes) fail-from)
                (raise (exn:fail "flaky-flush: simulated flush failure"
                                 (current-continuation-marks))))
              0]
             [else (write-bytes bs collected start end) (- end start)]))
     void))
  (define s (make-mdl-session root #:input-port (open-input-string input)
                              #:output-port out))
  (check-equal? (hash-ref (mdl-session-load! s "prog.mud") 'status) "PASS")
  (values s out collected flushes))

;; The reproduced defect: the host side closes the output port and raises a
;; preconstructed exception; the final flush then fails. The caller must get
;; the very same exception object, with the flush failure reported separately.
(let-values ([(s in out) (session-with "north\n")])
  (define original (exn:fail "ORIGINAL-STRICT-FAILURE" (current-continuation-marks)))
  (define events '())
  (define caught
    (with-handlers ([(lambda (e) #t) values])
      (mdl-session-run-interactive
       s "ENTRY"
       #:on-event (lambda (e)
                    (set! events (cons e events))
                    (when (eq? (car e) 'entry-returned)
                      (close-output-port out)
                      (raise original))))
      'returned))
  (check-eq? caught original)
  ;; ON-EVENT is never called once the loop body has been left.
  (check-equal? (map car (reverse events)) '(entry-returned))
  (define flush-failures (mdl-host-loop-secondary-failures original))
  (check-equal? (length flush-failures) 1)
  (for ([f (in-list flush-failures)])
    (check-regexp-match #rx"output port is closed" (exn-message f))))
;; A raised non-exception value is preserved too.
(let-values ([(s in out) (session-with "")])
  (define caught
    (with-handlers ([(lambda (e) #t) values])
      (mdl-session-run-interactive
       s "ENTRY"
       #:on-event (lambda (e) (when (eq? (car e) 'entry-returned)
                                (close-output-port out)
                                (raise 'host-signal))))
      'returned))
  (check-eq? caught 'host-signal))
;; Input exhaustion (D3) stays the outcome when only the final flush fails:
;; requests are the empty PRIN1, READSTRING's two flushes (prompt, then the
;; prompt after "Beg pardon?"), then the loop's own fourth.
(let-values ([(s out collected flushes) (session-with-flaky-flush "" 4)])
  (define events '())
  (define caught
    (with-handlers ([(lambda (e) #t) values])
      (mdl-session-run-interactive s "ENTRY"
                                   #:on-event (lambda (e) (set! events (cons e events))))
      'returned))
  (check-pred exn:fail:mdl-input-exhausted? caught)
  (check-equal? (unbox flushes) 4)
  (check-equal? (get-output-string collected) "\n>Beg pardon?\n>")
  (define flush-failures (mdl-host-loop-secondary-failures caught))
  (check-equal? (length flush-failures) 1)
  (for ([f (in-list flush-failures)])
    (check-regexp-match #rx"simulated flush failure" (exn-message f))))
;; A strict runtime error inside a pass keeps its message too (request 1 is
;; the empty PRIN1, request 2 the loop's final flush).
(let-values ([(s out collected flushes) (session-with-flaky-flush "<+ 1 2>\n" 2)])
  (define events '())
  (define caught
    (with-handlers ([(lambda (e) #t) values])
      (mdl-session-run-interactive s "KEEPREP"
                                   #:on-event (lambda (e) (set! events (cons e events))))
      'returned))
  (check-regexp-match #rx"REP: the default REP SUBR is inert" (exn-message caught))
  (check-equal? (unbox flushes) 2)
  (check-equal? (length (mdl-host-loop-secondary-failures caught)) 1))
;; Independent review of F2: a flush that raises a non-exception value (or a
;; non-exn:fail exn) is still only a secondary failure.
(define (session-with-raising-flush input raised)
  (define out
    (make-output-port
     'raising-flush always-evt
     (lambda (bs start end non-block? breakable?)
       (if (= start end) (raise raised) (- end start)))
     void))
  (define s (make-mdl-session root #:input-port (open-input-string input)
                              #:output-port out))
  (check-equal? (hash-ref (mdl-session-load! s "prog.mud") 'status) "PASS")
  s)
(let ([s (session-with-raising-flush "" 'port-raised-non-exn)])
  ;; KEEPREP: no READSTRING flush; PRIN1's empty write is the first request,
  ;; which raises inside the loop and is itself the primary failure.
  (define caught (with-handlers ([(lambda (e) #t) values])
                   (mdl-session-run-interactive s "KEEPREP") 'returned))
  (check-eq? caught 'port-raised-non-exn)
  ;; the loop's own flush raised the same value again: recorded, not raised
  (check-equal? (mdl-host-loop-secondary-failures caught) '(port-raised-non-exn)))
(let-values ([(s in out) (session-with "")])
  ;; A primary failure from the host, then a final flush that raises a
  ;; non-exception value: the primary still wins.
  (define original (exn:fail "PRIMARY" (current-continuation-marks)))
  (define flaky (session-with-raising-flush "" 'port-raised-non-exn))
  (define caught
    (with-handlers ([(lambda (e) #t) values])
      (mdl-session-run-interactive
       flaky "ENTRY"
       #:on-event (lambda (e) (when (eq? (car e) 'entry-returned) (raise original))))
      'returned))
  (check-eq? caught original)
  (check-equal? (mdl-host-loop-secondary-failures original) '(port-raised-non-exn)))
;; A host that escapes on EVERY event still cannot turn a failure into a
;; normal return: no event is delivered after the loop body is left.
(let-values ([(s in out) (session-with "north\n")])
  (define original (exn:fail "PRIMARY-2" (current-continuation-marks)))
  (define caught
    (with-handlers ([(lambda (e) #t) values])
      (let/ec escape
        (mdl-session-run-interactive
         s "ENTRY"
         #:on-event (lambda (e)
                      (if (eq? (car e) 'entry-returned)
                          (begin (close-output-port out) (raise original))
                          (escape 'clean-return)))))))
  (check-eq? caught original))

;; With no failure leaving the loop (a host escape out of ON-EVENT), a failed
;; final flush is itself the reported failure: never swallowed.
(let-values ([(s in out) (session-with "")])
  (define caught
    (with-handlers ([(lambda (e) #t) values])
      (let/ec escape
        (mdl-session-run-interactive
         s "ENTRY"
         #:on-event (lambda (e) (when (eq? (car e) 'pass)
                                  (close-output-port out)
                                  (escape 'escaped)))))))
  (check-pred exn:fail? caught)
  (check-regexp-match #rx"output port is closed" (exn-message caught)))
;; ... and a successful escape still flushes and returns normally.
(let-values ([(s out collected flushes) (session-with-flaky-flush "" 1000)])
  (check-equal?
   (let/ec escape
     (mdl-session-run-interactive
      s "ENTRY" #:on-event (lambda (e) (when (eq? (car e) 'pass) (escape 'escaped)))))
   'escaped)
  (check-equal? (unbox flushes) 2)      ; the empty PRIN1, the final flush
  (check-equal? (get-output-string collected) "\n"))

(delete-directory/files root)
