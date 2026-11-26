#lang racket/base
;; M4 #173 B2 (ADR-0064; INV-07): an MDL ERROR during play reaches the game's
;; own ERROR handler HANDLE (77rooms.mud:215-251, installed at load by
;; 77rooms.mud:258-270) and runs its general branch to the end: TELL, TELL
;; ,VERS, PRINT of every ERROR argument, FINISH -> SCORE -> RECORD -> QUIT.
;;
;; No ordinary command is known to signal an ERROR in the unchanged 1977
;; sources. The ERROR sites outside load-time code: DA (77defs.mud:458;
;; nothing calls it), FIND-PREP (77makstr.mud:129; only at load), and two
;; defensive branches, MELEE's unknown blow result (78melee.mud:462,
;; <ERROR MELEE "CHOMPS" .RES>, .RES a FIX) and DISPATCH of a non-applicable
;; object (81tell-repl.mud:133, <ERROR "Wrong dispatch type" <TYPE .NO> .NO>). The ERROR is therefore injected, test-only: at
;; the first READSTRING the session's input observer (ADR-0061, host-only)
;; replaces the GVAL of the verb JARGON (synonym "foo", 77dung.mud:2770-2771;
;; dispatched by APPLY-RANDOM through the GVAL, 77defs.mud:440-446) with a
;; host SUBR that calls ERROR with the arguments DA would pass
;; (77defs.mud:458): UNASSIGNED-VARIABLE!-ERRORS, an unassigned ATOM, DA. DA
;; itself is not used: it calls APPLICABLE?, which this runtime does not
;; implement (dead code in the pinned game; recorded in I173-HANDLE.md).
;; Nothing in the game sources is changed.
;;
;; Pinned Confusion stubs HANDLER/EVENT, so no native transcript of HANDLE
;; exists (case error-handler-native). The expected bytes are built from the
;; source and the manual, with two native anchors: the transcript up to the
;; second prompt is the pinned C1 capture's (session-quit-probe.json), and
;; the PRINT lines have the exact shape of the native case
;; print-tuple-like-handle (i173-trailer-reference-raw.json).
;;
;; Every run is guarded (no write or delete; the game tree is unchanged; an
;; empty temporary cwd) and watchdogged.
(require rackunit racket/runtime-path racket/port racket/string racket/list
         racket/file racket/path file/sha1 json
         "../mdl/loader.rkt" "../mdl/runtime/core.rkt")

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(define-runtime-path session-reference-file "../docs/evidence/M3/session-quit-probe.json")
(define-runtime-path trailer-reference-file "../docs/evidence/M4/i173-trailer-reference-raw.json")
(unless (directory-exists? source-root)
  (error 'historical-handle "pinned source missing: ~a" source-root))

;; --- native anchors -----------------------------------------------------------------
;; The pinned C1 transcript (house-quit; its first command is also `north`),
;; after the Confusion banner (presentation difference D1), up to and
;; including the prompt that follows `north`.
(define c1-after-banner
  (let* ([ref (call-with-input-file session-reference-file read-json)]
         [c (findf (lambda (c) (equal? (hash-ref c 'name) "C1-session-quit-pipe"))
                   (hash-ref ref 'cases))]
         [raw (hash-ref c 'stdout_raw)])
    (check-equal? (bytes->hex-string
                   (sha256-bytes (apply bytes (map char->integer (string->list raw)))))
                  (hash-ref c 'stdout_sha256))
    ;; D1 (the only approved presentation difference, as in
    ;; historical_session_quit_test): the banner and the one "DONE" line.
    (define after (cadr (regexp-match #rx"^.*?LISTENING-AT-LEVEL 1 PROCESS 1\n(.*)$" raw)))
    (check-equal? (length (regexp-match* (regexp-quote "\"DONE\"\n") after)) 1)
    (string-replace after "\"DONE\"\n" "" #:all? #f)))
(define (through-prompt text n) ; TEXT up to and including its Nth ">"
  (let loop ([i 0] [k 0])
    (cond [(= i (string-length text)) (error 'through-prompt "only ~a prompts" k)]
          [(char=? (string-ref text i) #\>)
           (if (= (add1 k) n) (substring text 0 (add1 i)) (loop (add1 i) (add1 k)))]
          [else (loop (add1 i) k)])))
(define native-north-prefix (through-prompt c1-after-banner 2))
(check-true (string-suffix? native-north-prefix "all the windows are barred.\n>"))
;; The native PRINT of a three-element ERROR tuple through HANDLE's MAPF.
(define native-handle-print
  (hash-ref (findf (lambda (c) (equal? (hash-ref c 'name) "print-tuple-like-handle"))
                   (hash-ref (call-with-input-file trailer-reference-file read-json) 'cases))
            'result_bytes))
(check-equal? native-handle-print "\nUNASSIGNED-VARIABLE!-ERRORS \nFOO \nDA DA\n")

;; --- expected bytes from the source -----------------------------------------------
;; HANDLE's TELL text, exactly as in 77rooms.mud:247-248 (a CR LF inside the
;; STRING, as the source file has it; TELL writes it raw with PRINTSTRING).
(define handle-tell
  (let* ([src (call-with-input-file (build-path source-root "77rooms.mud")
                (lambda (in) (port->string in #:close? #t)))]
         [m (regexp-match #rx"\\(<TELL \r?\n\"(I'm sorry[^\"]*)\">" src)])
    (cadr m)))
(check-equal? handle-tell
              "I'm sorry, you seem to have encountered an error in the program.\r\nSend mail to DUNGEON@MIT-DMS describing what it was you tried to do.")

;; --- guarded, watchdogged runs -------------------------------------------------------
(define original-guard (current-security-guard))
(define (tree-manifest dir0)
  (define dir (simplify-path dir0))
  (parameterize ([current-security-guard original-guard])
    (sort (for/list ([p (in-list (find-files file-exists? dir))])
            (list (path->string (find-relative-path dir (simplify-path p)))
                  (call-with-input-file p (lambda (in) (bytes->hex-string (sha256-bytes in))))))
          string<? #:key car)))

;; INJECT is a thunk run inside the session at the first READSTRING; it may
;; install the fault. Returns (values result raw-output unread-input session
;; writes cwd-after manifest-unchanged?).
(define (run-game lines inject)
  (define input (open-input-string (string-append (string-join lines "\n") "\n")))
  (define output (open-output-string))
  (define cwd (make-temporary-file "b2-handle-cwd-~a" 'directory))
  (define before (tree-manifest source-root))
  (define writes '())
  (define guard
    (make-security-guard
     original-guard
     ;; A write or delete attempt is recorded and refused at once (the
     ;; run then fails with the guard's exception), not merely recorded.
     (lambda (who path modes)
       (when (and path (or (memq 'write modes) (memq 'delete modes)))
         (set! writes (cons (list who path modes) writes))
         (raise (make-exn:fail
                 (format "historical-handle guard: ~a refused ~a on ~a" who modes path)
                 (current-continuation-marks)))))
     ;; No network access at all.
     (lambda (who host port mode)
       (set! writes (cons (list who host port mode) writes))
       (raise (make-exn:fail
               (format "historical-handle guard: ~a refused network ~a:~a" who host port)
               (current-continuation-marks))))))
  (define injected? #f)
  (define (observer stage data)
    (unless injected? (set! injected? #t) (inject)))
  (define session
    (make-mdl-session source-root #:input-port input #:output-port output
                      #:clock (make-fixed-mdl-clock 250776000) #:time-zone 'utc
                      #:input-observer observer))
  (define done (make-channel))
  (define worker
    (parameterize ([current-security-guard guard] [current-directory cwd])
      (thread
       (lambda ()
         (channel-put
          done
          (with-handlers ([(lambda (v) #t) values])
            (mdl-session-load! session "77loadall.mud")
            (mdl-session-run-interactive session "SAVE-IT")))))))
  (define result
    (or (sync/timeout 300 done) (begin (kill-thread worker) 'timed-out)))
  (define cwd-after (parameterize ([current-security-guard original-guard]) (directory-list cwd)))
  (delete-directory/files cwd)
  (values result (get-output-string output) (port->string input) session
          writes cwd-after (equal? before (tree-manifest source-root))))

(define (game-atom name) ; an existing ATOM, looked up without interning
  (or (mdl-find-atom name) (error 'game-atom "no ATOM ~a" name)))
;; The fault: JARGON's GVAL becomes a SUBR signalling ERROR with ARGS (thunk).
(define ((install-error-verb make-args #:before [before void]))
  (mdl-define-subr! (game-atom "JARGON")
                    (lambda ()
                      (before)
                      (apply mdl-apply (mdl-root-atom "ERROR") (make-args)))))
(define (da-args) ; the arguments DA passes (77defs.mud:458)
  (list (game-atom "UNASSIGNED-VARIABLE!-ERRORS")
        (mdl-atom "HANDLE-TEST-UNASSIGNED") ; unassigned, as DA's FN would be
        (game-atom "DA")))
(define (clean label writes cwd-after unchanged?)
  (check-equal? writes '() label)
  (check-equal? cwd-after '() label)
  (check-true unchanged? label))

;; === H1: the general branch of HANDLE, to the game's own QUIT ===========================
(define-values (h1 h1-raw h1-unread h1-session h1-writes h1-cwd h1-unchanged)
  (run-game '("north" "foo" "look") (install-error-verb da-args)))
(clean "H1" h1-writes h1-cwd h1-unchanged)
(check-pred mdl-session-outcome? h1 (if (exn? h1) (exn-message h1) (format "~a" h1)))
(when (mdl-session-outcome? h1)
  ;; QUIT after an MDL ERROR was signalled (ADR-0054): not an acceptance run.
  (check-equal? (mdl-session-outcome-kind h1) 'quit-after-mdl-error)
  (check-equal? (mdl-session-outcome-mdl-errors h1)
                '("UNASSIGNED-VARIABLE HANDLE-TEST-UNASSIGNED DA")))
(define vers (mdl-session-global h1-session "VERS"))
(check-equal? vers "This version created December 12.")
(define expected-h1
  (string-append
   native-north-prefix
   handle-tell "\n"                                     ; TELL (POST-CRLF)
   vers "\n"                       ; TELL ,VERS
   ;; MAPF PRINT over the ERROR tuple (native shape, FOO -> our ATOM)
   "\nUNASSIGNED-VARIABLE!-ERRORS \nHANDLE-TEST-UNASSIGNED \nDA "
   ;; FINISH #FALSE (". Error."): ASK? false, so SCORE prints its CRLF and
   ;; "Your score is" (77rooms.mud:671-674), no question; RECORD's OPENs are
   ;; denied (ADR-0055) and print nothing; QUIT.
   "\nYour score is 0 [total of 500 points], in 2 moves.\n"
   "This score gives you the rank of Beginner.\n"))
(check-equal? h1-raw expected-h1)
(check-true (string-contains? h1-raw (substring native-handle-print 0 30))) ; "\nUNASSIGNED-VARIABLE!-ERRORS \n"
(check-equal? h1-unread "look\n")          ; the game quit before reading it
(check-false (string-contains? h1-raw "Do you wish to leave"))
(check-false (string-contains? h1-raw ". Error."))
;; HANDLE's <PUT ,OUTCHAN 13 80> took effect.
(check-equal? (mdl-session-call h1-session "NTH" (mdl-session-global h1-session "OUTCHAN") 13) 80)
;; RECORD ran once: one denied READB and one denied PRINT OPEN.
(check-equal? (for/list ([o (in-list (mdl-session-open-records h1-session))])
                (list (mdl-open-record-mode o) (mdl-open-record-file-spec o)
                      (mdl-open-record-status o)))
              '(("READB" "MDL/ZORK.LOG" 2) ("PRINT" "MDL/ZORK.LOG" 13)))

;; === H2: an ERROR at interrupt level 8 is not delivered to HANDLE (manual 21.x;
;; ADR-0025): the ERROR is not handled, the session ends with a strict failure
;; and HANDLE prints nothing ==================================================
(define-values (h2 h2-raw h2-unread h2-session h2-writes h2-cwd h2-unchanged)
  (run-game '("north" "foo" "look")
            (install-error-verb da-args
                                #:before (lambda () (mdl-apply (mdl-root-atom "INT-LEVEL") 8)))))
(clean "H2" h2-writes h2-cwd h2-unchanged)
(check-pred exn:fail? h2 (format "~a" h2))
;; It is the undelivered ERROR itself, not some other host failure.
(when (exn? h2)
  (check-regexp-match #rx"UNASSIGNED-VARIABLE HANDLE-TEST-UNASSIGNED DA" (exn-message h2))
  (check-false (regexp-match? #rx"INT-LEVEL|PRINT" (exn-message h2))))
(check-false (mdl-session-outcome? h2))
(check-equal? h2-raw native-north-prefix)
(check-false (string-contains? h2-raw "I'm sorry"))

;; === H3: an ERROR argument PRINT cannot print here (a VECTOR; Confusion prints
;; [1 2]): HANDLE's TELLs run, then PRINT's strict refusal ends the session as a
;; host failure; nothing of the refused object is written ============================
(define-values (h3 h3-raw h3-unread h3-session h3-writes h3-cwd h3-unchanged)
  (run-game '("north" "foo" "look")
            (install-error-verb
             (lambda () (list (game-atom "UNASSIGNED-VARIABLE!-ERRORS")
                              (mdl-apply (mdl-root-atom "VECTOR") 1 2))))))
(clean "H3" h3-writes h3-cwd h3-unchanged)
(check-pred exn:fail? h3 (format "~a" h3))
(when (exn? h3)
  (check-regexp-match #rx"^PRINT: unsupported TYPE VECTOR" (exn-message h3)))
(check-equal? h3-raw
              (string-append native-north-prefix handle-tell "\n"
                             vers "\n"
                             "\nUNASSIGNED-VARIABLE!-ERRORS "))

;; === H4: the guard itself refuses a write at once (a host-side attempt from
;; inside the guarded run; MDL code has no file access, ADR-0055) =============
(define-values (h4 h4-raw h4-unread h4-session h4-writes h4-cwd h4-unchanged)
  (run-game '("north" "look")
            (lambda () (call-with-output-file "guard-probe.txt" void))))
(check-pred exn:fail? h4 (format "~a" h4))
(when (exn? h4)
  (check-regexp-match #rx"^historical-handle guard: .* refused" (exn-message h4)))
(check-equal? (length h4-writes) 1)
(check-equal? h4-cwd '())          ; nothing was created
(check-true h4-unchanged)
