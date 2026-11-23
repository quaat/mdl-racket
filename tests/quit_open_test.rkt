#lang racket/base
;; S11 (ADR-0054, ADR-0055): QUIT as a session-termination signal, the
;; host-loop session outcome, and OPEN's virtual no-file denial.
;; SEMANTICS: "M3 session end: QUIT and the host-loop outcome" and
;; "M3 file system: OPEN denial". The faithful game path is
;; tests/historical_session_quit_test.rkt.
(require rackunit racket/file racket/port racket/list
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/loader.rkt"
         "../mdl/runtime/core.rkt")

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))

(define-syntax-rule (scenario label body ...)
  (test-case label
    (parameterize ([current-namespace ns]
                   [current-mdl-globals (make-hasheq)]
                   [current-mdl-locals (list (make-hasheq))]
                   [current-mdl-atom-space (make-mdl-atom-space)])
      (run "<SETG CL 0> <SETG HANDLED 0>")
      body ...)))
(define (run source)
  (for/fold ([value #f]) ([expr (in-list (compile-program (parse-mdl source)))])
    (eval expr)))
(define (g name) (mdl-gval (mdl-atom name)))
;; The raw value a thunk raises (any value), or 'no-raise.
(define (raised thunk)
  (with-handlers ([(lambda (v) #t) values]) (thunk) 'no-raise))

;; --- QUIT -------------------------------------------------------------------

(scenario "<QUIT> raises the session quit signal, which is not an exn"
  (define v (raised (lambda () (run "<QUIT>"))))
  (check-pred mdl-quit-signal? v)
  (check-false (exn? v))
  (check-false (exn:fail? v))
  (check-false (exn:break? v))
  ;; an exn:fail? handler never intercepts it
  (check-pred mdl-quit-signal?
              (raised (lambda () (with-handlers ([exn:fail? (lambda (e) 'caught)])
                                   (run "<QUIT>")))))
  ;; also through APPLY and the GVAL
  (check-pred mdl-quit-signal? (raised (lambda () (run "<APPLY ,QUIT>")))))

(scenario "QUIT arity is strict: arguments are evaluated, then refused"
  (check-exn #rx"^QUIT: an exit-status argument is not supported \\(ADR-0054\\)$"
             (lambda () (run "<QUIT 0>")))
  (check-exn #rx"^QUIT: TOO-MANY-ARGUMENTS-SUPPLIED$"
             (lambda () (run "<QUIT 0 1>")))
  (check-exn exn:fail? (lambda () (run "<QUIT <SETG CL 5>>")))
  (check-equal? (g "CL") 5))

(scenario "QUIT skips UNWIND cleanups (ADR-0051), nested and FINISH-shaped"
  (check-pred mdl-quit-signal?
              (raised (lambda () (run "<UNWIND <QUIT> <SETG CL 1>>"))))
  (check-equal? (g "CL") 0)
  ;; FINISH's shape: the cleanup itself would QUIT again
  (check-pred mdl-quit-signal?
              (raised (lambda ()
                        (run "<PROG P () <UNWIND <PROG () <SETG HANDLED 1> <QUIT>>
                                                 <PROG () <SETG CL 1> <QUIT>>>>"))))
  (check-equal? (g "HANDLED") 1)
  (check-equal? (g "CL") 0)
  ;; a cleanup that would RETURN past the UNWIND cannot swallow the QUIT
  (check-pred mdl-quit-signal?
              (raised (lambda ()
                        (run "<PROG P () <UNWIND <UNWIND <QUIT> <SETG CL 1>>
                                                 <RETURN 7 .P>>>"))))
  (check-equal? (g "CL") 0))

(scenario "QUIT never runs an MDL ERROR handler"
  (run "<HANDLER <EVENT \"ERROR\" 8> <FUNCTION (FR \"TUPLE\" TT) <SETG HANDLED 1> <ERRET T .FR>>>")
  (check-pred mdl-quit-signal? (raised (lambda () (run "<QUIT>"))))
  (check-equal? (g "HANDLED") 0)
  ;; the handler is live: a real ERROR reaches it
  (check-equal? (run "<ERROR FOO>") (mdl-atom "T"))
  (check-equal? (g "HANDLED") 1))

(scenario "QUIT restores host bookkeeping while propagating"
  (run "<SET X 1> <DEFINE F (X) <QUIT>>")
  (check-pred mdl-quit-signal? (raised (lambda () (run "<F 2>"))))
  (check-equal? (run ".X") 1)
  ;; QUIT from an ERROR handler (HANDLE -> FINISH -> QUIT): the handler's
  ;; interrupt level and the ERROR frame are unwound with it.
  (run "<HANDLER <EVENT \"ERROR\" 8> <FUNCTION (FR \"TUPLE\" TT) <SETG FRM .FR> <QUIT>>>")
  (check-pred mdl-quit-signal? (raised (lambda () (run "<ERROR FOO>"))))
  (check-equal? (run "<INT-LEVEL>") 0)
  (check-exn #rx"live ERROR FRAME" (lambda () (run "<ERRET 1 ,FRM>")))
  ;; a PROG left by QUIT is no longer a RETURN target
  (run "<SETG ACT <>>")
  (check-pred mdl-quit-signal? (raised (lambda () (run "<PROG P () <SETG ACT .P> <QUIT>>"))))
  (check-exn exn:fail? (lambda () (run "<RETURN 1 ,ACT>"))))

;; --- OPEN denial --------------------------------------------------------------

;; The test's own listing runs under the original guard, so it is not
;; counted as an access by the code under test.
(define original-guard (current-security-guard))
(define (snapshot dir)
  (parameterize ([current-security-guard original-guard])
    (sort (map path->string (directory-list dir)) string<?)))
(define scratch (make-temporary-file "quit-open-test-~a" 'directory))
(define attempted-writes '())
(define attempted-files '())
;; Records every file-system access the code under test attempts: writes and
;; deletes separately, and any access at all (OPEN must not even read).
(define recorder
  (make-security-guard
   (current-security-guard)
   (lambda (who path modes)
     (when path
       (set! attempted-files (cons (list who path modes) attempted-files))
       (when (or (memq 'write modes) (memq 'delete modes))
         (set! attempted-writes (cons (list who path modes) attempted-writes)))))
   (lambda (who host port mode) (void))))
(define-syntax-rule (guarded body ...)
  (parameterize ([current-directory scratch] [current-security-guard recorder])
    body ...))

(scenario "RECORD's OPEN forms return the three-element virtual denial"
  (guarded
   (define before (snapshot scratch))
   (run "<SETG R <OPEN \"READB\" \"ZORK\" \"LOG\" \"DSK\" \"MDL\">>")
   (check-equal? (run "<TYPE ,R>") (mdl-atom "FALSE"))
   (check-equal? (run "<LENGTH ,R>") 3)
   (check-equal? (run "<1 ,R>") "No such file or directory")
   (check-equal? (run "<2 ,R>") "MDL/ZORK.LOG")
   (check-equal? (run "<3 ,R>") 2)
   (check-equal? (mdl-list->list (run "<MAPF ,LIST ,TYPE ,R>"))
                 (map mdl-atom '("STRING" "STRING" "FIX")))
   (for ([mode '("PRINT" "PRINTO")])
     (run (format "<SETG R <OPEN ~s \"ZORK\" \"LOG\" \"DSK\" \"MDL\">>" mode))
     (check-equal? (run "<1 ,R>") "Permission denied" mode)
     (check-equal? (run "<2 ,R>") "MDL/ZORK.LOG" mode)
     (check-equal? (run "<3 ,R>") 13 mode))
   ;; RECORD's busy tests: never *600130*; the other ITS/TENEX codes neither
   (for ([mode '("READB" "PRINT" "PRINTO")])
     (run (format "<SETG R <OPEN ~s \"ZORK\" \"LOG\" \"DSK\" \"MDL\">>" mode))
     (check-false (mdl-truthy? (run "<==? <3 ,R> *600130*>")) mode)
     (check-false (mdl-truthy? (run "<==? <3 ,R> *600117*>")) mode)
     (check-false (mdl-truthy? (run "<==? <3 ,R> *600123*>")) mode))
   ;; fresh, mutable STRINGs each call
   (run "<SETG R2 <OPEN \"READB\" \"ZORK\" \"LOG\" \"DSK\" \"MDL\">>")
   (check-false (mdl-truthy? (run "<==? <1 ,R> <1 ,R2>>")))
   (run "<PUT <2 ,R2> 1 !\\X>")
   (check-equal? (run "<2 <OPEN \"READB\" \"ZORK\" \"LOG\" \"DSK\" \"MDL\">>") "MDL/ZORK.LOG")
   ;; REST views of STRINGs are STRINGs; the file spec uses their characters
   (check-equal? (run "<2 <OPEN <REST \"XREADB\"> <REST \"XFOO\"> \"BAR\" \"DSK\" <REST \"XDIR\">>>")
                 "DIR/FOO.BAR")
   (check-equal? (snapshot scratch) before)
   (check-equal? attempted-files '())
   (check-equal? attempted-writes '())
   ;; host-side record, in call order
   (define recs (mdl-open-records))
   (check-equal? (map mdl-open-record-mode recs)
                 '("READB" "PRINT" "PRINTO" "READB" "PRINT" "PRINTO" "READB" "READB" "READB"))
   (check-equal? (map mdl-open-record-status (take recs 3)) '(2 13 13))
   (check-equal? (mdl-open-record-file-spec (car recs)) "MDL/ZORK.LOG")))

(scenario "unsupported OPEN forms are strict errors and touch nothing"
  (guarded
   (define cases
     '(;; the one-file-spec forms (MAKE-SCRIPT, DO-SAVE, DO-RESTORE)
       ("<OPEN \"PRINT\" \"MARC;%ZFOO >\">" . #rx"^OPEN: only the five-STRING form")
       ("<OPEN \"READB\" \"DSK:<MDL>ZORK.SAVE\">" . #rx"^OPEN: only the five-STRING form")
       ("<OPEN \"PRINTB\" \"DSK:<MDL>ZORK.SAVE\">" . #rx"^OPEN: only the five-STRING form")
       ;; READ (FILE-TO-TTY, DO-SCRIPT), PRINTB: not in RECORD's set
       ("<OPEN \"READ\" \"MADADV\" \"HELP\" \"DSK\" \"MDL\">" . #rx"^OPEN: mode \"READ\" is not supported")
       ("<OPEN \"PRINTB\" \"ZORK\" \"LOG\" \"DSK\" \"MDL\">" . #rx"^OPEN: mode \"PRINTB\" is not supported")
       ("<OPEN \"readb\" \"ZORK\" \"LOG\" \"DSK\" \"MDL\">" . #rx"^OPEN: mode \"readb\" is not supported")
       ;; arity
       ("<OPEN>" . #rx"^OPEN: only the five-STRING form")
       ("<OPEN \"READB\" \"ZORK\" \"LOG\" \"DSK\">" . #rx"^OPEN: only the five-STRING form")
       ("<OPEN \"READB\" \"ZORK\" \"LOG\" \"DSK\" \"MDL\" \"X\">" . #rx"^OPEN: only the five-STRING form")
       ;; argument types
       ("<OPEN READB \"ZORK\" \"LOG\" \"DSK\" \"MDL\">" . #rx"^OPEN: every argument must be a STRING")
       ("<OPEN \"READB\" \"ZORK\" \"LOG\" \"DSK\" 7>" . #rx"^OPEN: every argument must be a STRING")
       ("<OPEN \"READB\" \"ZORK\" !\\L \"DSK\" \"MDL\">" . #rx"^OPEN: every argument must be a STRING")))
   (for ([c (in-list cases)])
     (check-exn (cdr c) (lambda () (run (car c))) (car c)))
   (check-equal? (mdl-open-records) '())
   (check-equal? (snapshot scratch) '())
   (check-equal? attempted-files '())
   (check-equal? attempted-writes '())))

(scenario "CLOSE and the wider file API stay unsupported"
  (check-exn #rx"CLOSE" (lambda () (run "<CLOSE <OPEN \"PRINT\" \"ZORK\" \"LOG\" \"DSK\" \"MDL\">>")))
  (check-exn #rx"FILE-LENGTH" (lambda () (run "<FILE-LENGTH <OPEN \"READB\" \"ZORK\" \"LOG\" \"DSK\" \"MDL\">>"))))

(scenario "RECORD's OPEN cascade under the denial returns T without CLOSE or looping"
  ;; The OPEN part of RECORD (77rooms.mud:722-752, 795), with MUDDLE 101 and
  ;; the SLEEP/CLOSE/FILE-LENGTH branches replaced by markers: reaching one
  ;; of them is a failure of the policy.
  (guarded
   (run "<SETG MUDDLE-T 101> <SETG LOOPS 0>")
   (check-equal?
    (run "<DEFINE REC REC (\"AUX\" (CH <>) (MUDDLE ,MUDDLE-T))
            <UNWIND
             <PROG ()
              <PROG ()
                <COND (<SET CH <OPEN \"READB\" \"ZORK\" \"LOG\" \"DSK\" \"MDL\">>
                       <SETG CL 99> <RETURN BAD .REC>)
                      (<OR <AND <L? .MUDDLE 100> <N==? <3 .CH> *4000000*>>
                           <AND <G? .MUDDLE 100> <==? <3 .CH> *600130*>>>
                       <SETG LOOPS <+ ,LOOPS 1>>
                       <COND (<G? ,LOOPS 3> <RETURN LOOPED .REC>)>
                       <AGAIN>)
                      (<SET CH <OPEN \"PRINT\" \"ZORK\" \"LOG\" \"DSK\" \"MDL\">>)
                      (<AND <G? .MUDDLE 100> <==? <3 .CH> *600117*>>
                       <RETURN NOWRITE .REC>)
                      (<RETURN T .REC>)>>
              WROTE>
             <AND .CH <NOT <0? <1 .CH>>> <SETG CL 1>>>>
          <REC>")
    (mdl-atom "T"))
   (check-equal? (g "LOOPS") 0)
   (check-equal? (g "CL") 0)
   (check-equal? (map mdl-open-record-mode (mdl-open-records)) '("READB" "PRINT"))
   (check-equal? attempted-writes '())))

;; --- the host-loop outcome --------------------------------------------------

(define root (make-temporary-file "mdl-quit-loop~a" 'directory))
(call-with-output-file (build-path root "prog.mud")
  (lambda (port)
    (write-string #<<MDL
<SETG NULL <INSERT <ATOM ""> <ROOT>>>
<SETG INBUF <ISTRING 20>>
<SETG RS <STRING <ASCII 27> <ASCII 13> <ASCII 10>>>
<SETG MOVES 0>
<DEFINE CMD ("AUX" N)
  <REPEAT ()
    <PRINC ">">
    <SET N <READSTRING ,INBUF ,INCHAN ,RS>>
    <COND (<0? .N> <PRINC "Beg pardon?"> <CRLF>)
          (T <SETG MOVES <+ ,MOVES 1>>
             <COND (<=? <SUBSTRUC ,INBUF 0 .N> "quit"> <FIN>)
                   (<=? <SUBSTRUC ,INBUF 0 .N> "err"> <ERROR GAME-ERR>)
                   (<=? <SUBSTRUC ,INBUF 0 .N> "bad"> <NO-SUCH-PRIMITIVE>)
                   (T <PRINTSTRING ,INBUF ,OUTCHAN .N> <CRLF>)>)>>>
<DEFINE FIN ()
  <UNWIND <PROG () <PRINC "Bye?"> <CRLF>
                   <READSTRING ,INBUF ,INCHAN ,RS>
                   <COND (<MEMQ <1 ,INBUF> "Yy"> <SETG RECORDED <+ ,RECORDED 1>> <QUIT>)>>
          <PROG () <SETG CLEANED T> <QUIT>>>>
<SETG RECORDED 0>
<SETG CLEANED <>>
<DEFINE ENTRY () <SETG REP ,CMD> <RESET ,INCHAN> ,NULL>
<DEFINE QUITTER () <QUIT>>
<DEFINE HANDLE (FR "TUPLE" Z) <PRINC "sorry"> <CRLF> <FIN>>
<DEFINE ERRETTER (FR "TUPLE" Z) <ERRET T .FR>>
<DEFINE ENTRY-H () <HANDLER <EVENT "ERROR" 8> ,HANDLE> <ENTRY>>
<DEFINE ENTRY-E () <HANDLER <EVENT "ERROR" 8> ,ERRETTER> <ENTRY>>
MDL
                  port)
    (void)))

(define (session-with input #:output [out (open-output-string)])
  (define in (open-input-string input))
  (define s (make-mdl-session root #:input-port in #:output-port out))
  (check-equal? (hash-ref (mdl-session-load! s "prog.mud") 'status) "PASS")
  (values s in out))
(define (run-loop entry input #:max-passes [max-passes 10])
  (define-values (s in out) (session-with input))
  (define result
    (with-handlers ([(lambda (v) #t) values])
      (mdl-session-run-interactive s entry #:max-passes max-passes)))
  (values result (get-output-string out) s in))

;; A normal user quit: the loop RETURNS a 'quit outcome; input after the
;; confirmation is never read; the FIN cleanup never ran.
(let-values ([(result output s in) (run-loop "ENTRY" "north\nquit\nn\nwest\nquit\ny\nlook\n")])
  (check-pred mdl-session-outcome? result)
  (check-equal? (mdl-session-outcome-kind result) 'quit)
  (check-equal? (mdl-session-outcome-mdl-errors result) '())
  (check-equal? output "\n>north\n>Bye?\n>west\n>Bye?\n")
  (check-equal? (port->string in) "look\n")
  (check-equal? (mdl-session-global s "MOVES") 4)       ; the y/n answers do not count
  (check-equal? (mdl-session-global s "RECORDED") 1)
  (check-false (mdl-truthy? (mdl-session-global s "CLEANED"))))
;; QUIT straight from the entry FUNCTION: nothing printed, outcome returned.
(let-values ([(result output s in) (run-loop "QUITTER" "north\n")])
  (check-equal? (mdl-session-outcome-kind result) 'quit)
  (check-equal? output "")
  (check-equal? (port->string in) "north\n"))
;; EOF while the confirmation is pending: no quit (stale "quit" answers no),
;; then D3 input exhaustion, a failure.
(let-values ([(result output s in) (run-loop "ENTRY" "quit\n")])
  (check-pred exn:fail:mdl-input-exhausted? result)
  (check-equal? output "\n>Bye?\n>"))
;; An MDL ERROR whose handler (HANDLE-shaped) ends in FIN/QUIT: the outcome
;; says an MDL ERROR was signalled, so the run cannot look clean.
(let-values ([(result output s in) (run-loop "ENTRY-H" "err\ny\n")])
  (check-pred mdl-session-outcome? result)
  (check-equal? (mdl-session-outcome-kind result) 'quit-after-mdl-error)
  (check-equal? (mdl-session-outcome-mdl-errors result) '("GAME-ERR"))
  (check-equal? output "\n>sorry\nBye?\n"))
;; An MDL ERROR resolved by ERRET, then a normal quit later: still tainted.
(let-values ([(result output s in) (run-loop "ENTRY-E" "err\nquit\ny\n")])
  (check-equal? (mdl-session-outcome-kind result) 'quit-after-mdl-error)
  (check-equal? (length (mdl-session-outcome-mdl-errors result)) 1))
;; An unresolved MDL ERROR, or a strict host error, is still raised.
(let-values ([(result output s in) (run-loop "ENTRY" "err\nquit\ny\n")])
  (check-pred exn:fail? result)
  (check-regexp-match #rx"GAME-ERR" (exn-message result))
  (check-equal? (port->string in) "quit\ny\n"))
(let-values ([(result output s in) (run-loop "ENTRY-H" "bad\nquit\ny\n")])
  ;; a host strict error never reaches HANDLE and never becomes a quit
  (check-pred exn:fail? result)
  (check-false (exn:fail:mdl-input-exhausted? result))
  (check-regexp-match #rx"NO-SUCH-PRIMITIVE" (exn-message result))
  (check-false (regexp-match? #rx"sorry" output))
  (check-equal? (port->string in) "quit\ny\n"))
;; Host cancellation (break) stays a break, never a quit outcome.
(let-values ([(s in out) (session-with "north\n")])
  (define result
    (with-handlers ([(lambda (v) #t) values])
      (mdl-session-run-interactive
       s "ENTRY"
       #:on-event (lambda (e)
                    (when (eq? (car e) 'pass)
                      (raise (exn:break "host cancel" (current-continuation-marks)
                                        (let/ec k k))))))))
  (check-pred exn:break? result))

;; F2 review regression: a quit whose final flush fails raises the flush
;; failure (there is no primary failure to keep); further flush failures are
;; its secondaries. Requests: empty PRIN1, the READSTRING flush, then the
;; loop's final flush.
(define (flaky-output fail-from)
  (define collected (open-output-string))
  (define flushes (box 0))
  (define out
    (make-output-port
     'flaky-flush always-evt
     (lambda (bs start end non-block? breakable?)
       (cond [(= start end)
              (set-box! flushes (add1 (unbox flushes)))
              (when (>= (unbox flushes) fail-from)
                (raise (exn:fail "flaky-flush: simulated flush failure"
                                 (current-continuation-marks))))
              0]
             [else (write-bytes bs collected start end) (- end start)]))
     void))
  (values out collected flushes))
(let*-values ([(out collected flushes) (flaky-output 1)]
              [(s in _) (session-with "" #:output out)])
  (define result
    (with-handlers ([(lambda (v) #t) values])
      (mdl-session-run-interactive s "QUITTER")))
  (check-equal? (unbox flushes) 1)       ; only the loop's own final flush
  (check-pred exn:fail? result)
  (check-regexp-match #rx"simulated flush failure" (exn-message result))
  (check-false (mdl-session-outcome? result))
  (check-equal? (mdl-host-loop-secondary-failures result) '()))
(let*-values ([(out collected flushes) (flaky-output 1000)]
              [(s in _) (session-with "" #:output out)])
  ;; the same quit with a working port returns the outcome
  (check-equal? (mdl-session-outcome-kind (mdl-session-run-interactive s "QUITTER")) 'quit))

;; QUIT outside the host loop propagates the signal to the host caller.
(let-values ([(s in out) (session-with "")])
  (check-pred mdl-quit-signal?
              (with-handlers ([(lambda (v) #t) values]) (mdl-session-call s "QUITTER") 'no)))

;; --- S11 independent review -------------------------------------------------
;; (1) A QUIT during a load: the report says QUIT (never PASS) and its last
;; event locates the QUIT; later forms do not run.
(let ([dir (make-temporary-file "mdl-quit-load~a" 'directory)])
  (call-with-output-file (build-path dir "loadquit.mud")
    (lambda (port) (write-string "<SETG A 1>\n<QUIT>\n<SETG B 2>\n" port) (void)))
  (define s (make-mdl-session dir))
  (define report (mdl-session-load! s "loadquit.mud"))
  (check-equal? (hash-ref report 'status) "QUIT")
  (check-equal? (hash-ref report 'completed_expressions) 1)
  (define last-event (last (hash-ref report 'events)))
  (check-equal? (hash-ref last-event 'status) "QUIT")
  (check-equal? (hash-ref last-event 'expression_index) 2)
  (check-equal? (hash-ref last-event 'line) 2)
  (check-equal? (mdl-session-global s "A") 1)
  (check-exn #rx"unassigned MDL global B" (lambda () (mdl-session-global s "B")))
  (delete-directory/files dir))
;; (2) The unresolved ERROR's host message is formatted after handler
;; delivery (pre-S11 behaviour); the outcome record is the signal-time text.
(scenario "unresolved ERROR message reflects a mutating handler"
  (run "<SETG S <STRING \"abc\">>")
  (run "<HANDLER <EVENT \"ERROR\" 9> <FUNCTION (FR \"TUPLE\" T) <PUT ,S 1 !\\Z>>>")
  (define e (raised (lambda () (run "<ERROR FOO ,S>"))))
  (check-pred exn:fail? e)
  (check-regexp-match #rx"FOO \"Zbc\"" (exn-message e)))

(delete-directory/files root)
(delete-directory/files scratch)
