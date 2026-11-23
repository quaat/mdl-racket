#lang racket/base
;; S12 (WP4): the local launcher zork/main.rkt.
;;
;; run-zork is a thin host wrapper over the faithful run.mud path (load
;; 77loadall.mud, host loop applying SAVE-IT), so its transcript must be the
;; S11 transcript: the house-quit session on the fixed clock (250776000, UTC)
;; is compared byte for byte with the pinned Confusion capture
;; C1-session-quit-pipe (docs/evidence/M3/session-quit-probe.json) after D1
;; only, exactly as tests/historical_session_quit_test.rkt does.
;;
;; Also covered: EOF -> 'input-exhausted; the launcher notice (present by
;; default, absent with #:notice? #f, never mixed into the game text); two
;; runs in one process share no state; a missing source root fails clearly
;; before printing anything; the command line's (zork/cli.rkt) exit codes
;; (0 quit, 4 EOF, 1 strict failure, 2 usage) as a subprocess; and a break during the blocking
;; read propagates as exn:break out of run-zork without ending this process
;; (the DrRacket Stop behaviour). Every game run has a wall-clock watchdog.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: make test-m3-launcher   (or: raco test tests/launcher_test.rkt)
(require rackunit racket/runtime-path racket/port racket/string racket/list
         racket/file file/sha1 json compiler/find-exe
         "../zork/main.rkt" "../mdl/loader.rkt")

(define-runtime-path launcher-lib "../zork/main.rkt")
(define-runtime-path launcher-file "../zork/cli.rkt")
(define-runtime-path scenario-file "scenarios/house-quit.json")
(define-runtime-path reference-file "../docs/evidence/M3/session-quit-probe.json")
(unless (directory-exists? default-source-root)
  (error 'launcher-test "pinned source missing: ~a (run `make sources`)" default-source-root))

(define scenario (call-with-input-file scenario-file read-json))
(define reference (call-with-input-file reference-file read-json))
(define commands (hash-ref scenario 'commands))
(define epoch (hash-ref scenario 'fixed_epoch))
(check-equal? epoch 250776000)
(check-equal? (hash-ref scenario 'tz) "UTC")

;; --- the pinned reference (same derivation as historical_session_quit_test) ---
(define (ref-case name)
  (or (findf (lambda (c) (equal? (hash-ref c 'name) name)) (hash-ref reference 'cases))
      (error 'ref-case "no reference case ~a" name)))
(define (reference-transcript name lines)
  (define c (ref-case name))
  (check-equal? (hash-ref c 'clock) (hasheq 'epoch epoch 'tz "UTC") name)
  (check-equal? (hash-ref c 'input)
                (string-append "<FLOAD \"77loadall.mud\">\n<SAVE-IT>\n"
                               (string-join lines "\n") "\n")
                name)
  (define raw (hash-ref c 'stdout_raw))
  (check-equal? (bytes->hex-string
                 (sha256-bytes (apply bytes (map char->integer (string->list raw)))))
                (hash-ref c 'stdout_sha256) name)
  (define banner "LISTENING-AT-LEVEL 1 PROCESS 1\n")
  (define after-banner
    (cadr (or (regexp-match (regexp (string-append "^.*?" (regexp-quote banner) "(.*)$")) raw)
              (error 'reference-transcript "no LISTEN banner in ~a" name))))
  (string-replace after-banner "\"DONE\"\n" "" #:all? #f))
(define c1-reference (reference-transcript "C1-session-quit-pipe" commands))
(define c2-lines (take commands 7))
(define c2-reference (reference-transcript "C2-eof-at-yesno" c2-lines))

;; --- watchdogged runs --------------------------------------------------------------
(define run-limit-seconds 300)
(define (lines->string lines) (string-append (string-join lines "\n") "\n"))
;; Runs THUNK in a fresh thread; returns its value or whatever it raised.
;; A timeout kills the worker and is reported as a failure, never a hang.
(define (watchdog label thunk)
  (define done (make-channel))
  (define worker
    (thread (lambda ()
              (channel-put done (with-handlers ([(lambda (v) #t) (lambda (v) (list 'raised v))])
                                  (list 'value (thunk)))))))
  (define r (sync/timeout run-limit-seconds done))
  (unless r
    (kill-thread worker)
    (fail (format "~a: timed out after ~a s" label run-limit-seconds)))
  r)
(define (play lines #:notice? [notice? #f])
  (define in (open-input-string (lines->string lines)))
  (define out (open-output-string))
  (define r (watchdog (format "~s" lines)
                      (lambda ()
                        (run-zork #:input in #:output out #:notice? notice?
                                  #:clock (make-fixed-mdl-clock epoch) #:time-zone 'utc))))
  (values r (get-output-string out) in))
(define (value-of r label)
  (unless (eq? (car r) 'value)
    (fail (format "~a raised: ~a" label
                  (if (exn? (cadr r)) (exn-message (cadr r)) (cadr r)))))
  (cadr r))

;; === 1. the complete house-quit session equals the S11 transcript ===================
(define-values (q1 q1-out q1-in) (play commands))
(check-equal? (value-of q1 "quit") (zork-result 'quit '() #f))
(check-equal? q1-out c1-reference)
(check-false (string-contains? q1-out "[launcher]"))        ; #:notice? #f
(check-equal? (port->string q1-in) (hash-ref scenario 'unread_after_quit))
(check-equal? (exit-code-for 'quit) 0)

;; === 2. EOF -> 'input-exhausted (the C2 reference transcript) =======================
(define-values (e1 e1-out e1-in) (play c2-lines))
(define e1-result (value-of e1 "eof"))
(check-equal? (zork-result-kind e1-result) 'input-exhausted)
(check-equal? (zork-result-mdl-errors e1-result) '())
(check-regexp-match #rx"^READSTRING: input exhausted" (zork-result-message e1-result))
(check-equal? e1-out c2-reference)
(check-equal? (exit-code-for 'input-exhausted) 4)
(check-equal? (exit-code-for 'quit-after-mdl-error) 3)

;; === 3. the notice: present by default, before (and separate from) the game ======
;; Also a second fresh session in this process: if anything leaked from run 1
;; (leaflet taken, 9 moves), the inventory and the move count would differ.
(define-values (n1 n1-out n1-in) (play '("inventory" "quit" "y") #:notice? #t))
(check-equal? (value-of n1 "notice") (zork-result 'quit '() #f))
(check-true (string-prefix? n1-out launcher-notice))
(for ([line (in-list (string-split launcher-notice "\n"))])
  (check-true (string-prefix? line "[launcher] ") line))
(check-regexp-match #rx"in-session record" launcher-notice)
(check-regexp-match #rx"RESTORE is unsupported" launcher-notice)
(check-regexp-match #rx"never writes" launcher-notice)
(define n1-game (substring n1-out (string-length launcher-notice)))
(check-false (string-contains? n1-game "[launcher]"))
;; Same boot text as run 1, up to the first prompt.
(define (boot-text s) (car (string-split s ">" #:trim? #f)))
(check-equal? (boot-text n1-game) (boot-text c1-reference))
(check-true (string-contains? n1-game ">You are empty handed.\n>"))
(check-false (string-contains? n1-game "leaflet"))
(check-true (string-contains? n1-game "in 2 moves."))
(check-true (string-suffix? n1-game "Do you wish to leave the game? (Y is affirmative): \n"))

;; === 4. a missing source root fails clearly, before any output ======================
(let ([out (open-output-string)]
      [missing (build-path (find-system-path 'temp-dir) "zork-launcher-no-such-dir-s12")])
  (check-false (directory-exists? missing))
  (check-exn (lambda (e) (and (exn:fail:zork-launcher:missing-source? e)
                              (regexp-match? #rx"pinned game directory is missing" (exn-message e))
                              (regexp-match? #rx"make sources" (exn-message e))))
             (lambda () (run-zork #:input (open-input-string "") #:output out
                                  #:source-root missing)))
  (check-equal? (get-output-string out) ""))

;; === 5. the command line: exit codes as a subprocess ================================
;; The library has no `main` submodule (running zork/main.rkt in DrRacket only
;; defines run-zork); the command line is zork/cli.rkt's `main`.
(check-false (module-declared? `(submod ,launcher-lib main) #t))
(check-true (module-declared? `(submod ,launcher-file main) #t))
(define racket-exe (find-exe))
(define (run-cli stdin-text . args)
  (define r
    (watchdog
     (format "cli ~s" args)
     (lambda ()
       (define-values (proc out in err)
         (apply subprocess #f #f #f racket-exe (path->string launcher-file) args))
       (define out-text #f)
       (define err-text #f)
       (define readers
         (list (thread (lambda () (set! out-text (port->string out))))
               (thread (lambda () (set! err-text (port->string err))))))
       (write-string stdin-text in)
       (close-output-port in)
       (subprocess-wait proc)
       (for-each thread-wait readers)
       (close-input-port out)
       (close-input-port err)
       (list (subprocess-status proc) out-text err-text))))
  (value-of r (format "cli ~s" args)))
(define-values (cli-quit-status cli-quit-out cli-quit-err)
  (apply values (run-cli (lines->string commands) "--fixed-clock" (number->string epoch))))
(check-equal? cli-quit-status 0 cli-quit-err)
(check-equal? cli-quit-out (string-append launcher-notice c1-reference))
(check-equal? cli-quit-err "")
(define-values (cli-eof-status cli-eof-out cli-eof-err)
  (apply values (run-cli (lines->string c2-lines) "--fixed-clock" (number->string epoch)
                         "--no-notice")))
(check-equal? cli-eof-status 4 cli-eof-err)
(check-equal? cli-eof-out c2-reference)
(check-regexp-match #rx"input ended \\(EOF\\)" cli-eof-err)
;; A strict failure (S11's unsupported "info" -> OPEN "READ") exits 1 with the
;; error on stderr; it is not reported as a quit.
(define-values (cli-strict-status cli-strict-out cli-strict-err)
  (apply values (run-cli (lines->string '("north" "info" "quit" "y"))
                         "--fixed-clock" (number->string epoch) "--no-notice")))
(check-equal? cli-strict-status 1)
(check-regexp-match #rx"strict failure: OPEN: mode \"READ\" is not supported" cli-strict-err)
(check-false (regexp-match? #rx"Do you wish to leave" cli-strict-out))
;; A usage error exits 2 before the game starts.
(define-values (cli-usage-status cli-usage-out cli-usage-err)
  (apply values (run-cli "" "--fixed-clock" "soon")))
(check-equal? cli-usage-status 2)
(check-equal? cli-usage-out "")

;; === 6. a break during the blocking read propagates as exn:break ==================
;; DrRacket's Stop breaks the evaluation thread. The input is a pipe that never
;; ends, so the game blocks in READSTRING after the first prompt; breaking the
;; thread must end run-zork with exn:break, and this process carries on.
(let* ([out (open-output-string)]
       [done (make-channel)])
  (define-values (pipe-in pipe-out) (make-pipe))
  (define worker
    (thread (lambda ()
              (channel-put done
                           (with-handlers ([(lambda (v) #t) values])
                             (run-zork #:input pipe-in #:output out #:notice? #f
                                       #:clock (make-fixed-mdl-clock epoch) #:time-zone 'utc))))))
  ;; Wait (watchdogged) until the game has printed its first prompt and blocks.
  (define deadline (+ (current-inexact-milliseconds) (* 1000 run-limit-seconds)))
  (let wait ()
    (cond [(string-contains? (get-output-string out) "mailbox here.\n>") (void)]
          [(> (current-inexact-milliseconds) deadline)
           (kill-thread worker) (fail "break test: no prompt before the watchdog")]
          [(thread-dead? worker) (fail "break test: run-zork ended before the prompt")]
          [else (sleep 0.05) (wait)]))
  (sleep 0.2)                                   ; let it enter the blocking read
  (check-false (thread-dead? worker))
  (break-thread worker)
  (define ended (sync/timeout 30 done))
  (unless ended (kill-thread worker))
  (check-pred exn:break? ended (format "~a" ended))
  (check-false (exn:fail? ended))
  (check-true (thread-dead? worker))
  (close-output-port pipe-out))
;; Still here: the break ended only the game thread.
(check-true #t "process continues after the break")
