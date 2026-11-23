#lang racket/base
;; Historical regression (S11; ADR-0054 QUIT and the session outcome,
;; ADR-0055 OPEN denial). The faithful run.mud path, <FLOAD "77loadall.mud">
;; then SAVE-IT through the host top-level loop, on the fixed session clock
;; (fixed_epoch 250776000, zone UTC; ADR-0052), played to a complete local
;; session that ends in the game's own QUIT (FINISH -> RECORD -> QUIT).
;;
;; The transcripts are compared with the pinned Confusion pipe-mode captures
;; in docs/evidence/M3/session-quit-probe.json (SESSION-QUIT-REFERENCE.md):
;; our raw output must equal the reference stdout byte for byte after the
;; only approved presentation difference for a pipe capture, D1 (the
;; Confusion/LISTEN banner up to "LISTENING-AT-LEVEL 1 PROCESS 1" and the
;; "DONE" line are not printed by the host loop). No other normalisation.
;;
;; Every game run is guarded: a security guard records any file write or
;; delete attempt during load and play (there must be none), the game
;; directory is hashed before and after, and the run happens in an empty
;; temporary current directory that must stay empty. Each run has a
;; wall-clock watchdog; a timeout is a failure, not a hang.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: make test-m3-session   (or: raco test tests/historical_session_quit_test.rkt)
(require rackunit racket/runtime-path racket/port racket/string racket/list
         racket/file racket/path file/sha1 json
         "../mdl/loader.rkt")

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(define-runtime-path scenario-file "scenarios/house-quit.json")
(define-runtime-path reference-file "../docs/evidence/M3/session-quit-probe.json")
(unless (directory-exists? source-root)
  (error 'historical-session-quit "pinned source missing: ~a" source-root))

(define scenario (call-with-input-file scenario-file read-json))
(define reference (call-with-input-file reference-file read-json))
(define commands (hash-ref scenario 'commands))
(check-equal? commands '("north" "west" "open mailbox" "take leaflet" "inventory" "score"
                         "quit" "n" "inventory" "quit" "y" "look"))
(check-equal? (hash-ref scenario 'fixed_epoch) 250776000)
(check-equal? (hash-ref scenario 'tz) "UTC")

;; --- the pinned reference ------------------------------------------------------
(check-equal? (hash-ref reference 'interpreter_sha256_before)
              "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789")
(check-equal? (hash-ref reference 'upstream_mdlzork_checked_out)
              "bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3")
(define (ref-case name)
  (or (findf (lambda (c) (equal? (hash-ref c 'name) name)) (hash-ref reference 'cases))
      (error 'ref-case "no reference case ~a" name)))
(define (entry-input lines)
  (string-append "<FLOAD \"77loadall.mud\">\n<SAVE-IT>\n" (string-join lines "\n") "\n"))
;; A reference stdout, integrity-checked against its recorded sha256 (the JSON
;; holds it as latin-1 text, CR kept), with only D1 applied.
(define (reference-transcript name lines)
  (define c (ref-case name))
  (check-equal? (hash-ref c 'mode) "pipe" name)
  (check-equal? (hash-ref c 'clock) (hasheq 'epoch 250776000 'tz "UTC") name)
  (check-equal? (hash-ref c 'input) (entry-input lines) name)
  (define raw (hash-ref c 'stdout_raw))
  (check-equal? (bytes->hex-string
                 (sha256-bytes (apply bytes (map char->integer (string->list raw)))))
                (hash-ref c 'stdout_sha256) name)
  (define banner "LISTENING-AT-LEVEL 1 PROCESS 1\n")
  (define after-banner
    (cadr (or (regexp-match (regexp (string-append "^.*?" (regexp-quote banner) "(.*)$")) raw)
              (error 'reference-transcript "no LISTEN banner in ~a" name))))
  (unless (= 1 (length (regexp-match* (regexp-quote "\"DONE\"\n") after-banner)))
    (error 'reference-transcript "expected one \"DONE\" line in ~a" name))
  (string-replace after-banner "\"DONE\"\n" "" #:all? #f))

;; --- guarded, watchdogged game runs ----------------------------------------------
(define original-guard (current-security-guard))
;; Relative path, size and sha256 of every file under DIR, read under the
;; original guard (the test's own reads are not the run's).
(define (tree-manifest dir0)
  (define dir (simplify-path dir0))
  (parameterize ([current-security-guard original-guard])
    (sort
     (for/list ([p (in-list (find-files file-exists? dir))])
       (list (path->string (find-relative-path dir (simplify-path p)))
             (file-size p)
             (call-with-input-file p (lambda (in) (bytes->hex-string (sha256-bytes in))))))
     string<? #:key car)))

(struct run-result (session load-report result raw events input writes cwd-after
                            manifest-before manifest-after))
(define run-limit-seconds 300)
(define (run-game lines)
  (define input (open-input-string (string-append (string-join lines "\n") "\n")))
  (define output (open-output-string))
  (define cwd (make-temporary-file "s11-quit-cwd-~a" 'directory))
  (define manifest-before (tree-manifest source-root))
  (define writes '())
  (define guard
    (make-security-guard
     original-guard
     (lambda (who path modes)
       (when (and path (or (memq 'write modes) (memq 'delete modes)))
         (set! writes (cons (list who path modes) writes))))
     (lambda (who host port mode) (void))))
  (define events '())
  (define session
    (make-mdl-session source-root #:input-port input #:output-port output
                      #:clock (make-fixed-mdl-clock 250776000) #:time-zone 'utc))
  (define done (make-channel))
  (define worker
    (parameterize ([current-security-guard guard] [current-directory cwd])
      (thread
       (lambda ()
         (channel-put
          done
          (with-handlers ([(lambda (v) #t) (lambda (v) (list #f v))])
            (define report (mdl-session-load! session "77loadall.mud"))
            (list report
                  (with-handlers ([(lambda (v) #t) values])
                    (mdl-session-run-interactive
                     session "SAVE-IT"
                     #:on-event (lambda (e) (set! events (cons e events))))))))))))
  (define outcome
    (or (sync/timeout run-limit-seconds done)
        (begin (kill-thread worker) (list #f 'timed-out))))
  (define cwd-after (parameterize ([current-security-guard original-guard])
                      (directory-list cwd)))
  (delete-directory/files cwd)
  (run-result session (first outcome) (second outcome) (get-output-string output)
              (reverse events) input writes cwd-after
              manifest-before (tree-manifest source-root)))

;; Checks common to every run: the full source loaded, nothing was written
;; anywhere, the game directory and the run's directory are unchanged.
(define (check-clean-run r label)
  (check-not-false (run-result-load-report r) label)
  (when (run-result-load-report r)
    (check-equal? (hash-ref (run-result-load-report r) 'status) "PASS" label)
    (check-equal? (hash-ref (run-result-load-report r) 'completed_expressions) 1229 label))
  (check-equal? (run-result-writes r) '() label)
  (check-equal? (run-result-cwd-after r) '() label)
  (check-equal? (run-result-manifest-after r) (run-result-manifest-before r) label)
  (check-false (file-exists? (build-path source-root "MDL" "ZORK.LOG")) label))
(define (open-records r)
  (for/list ([o (in-list (mdl-session-open-records (run-result-session r)))])
    (list (mdl-open-record-mode o) (mdl-open-record-file-spec o) (mdl-open-record-status o))))
(define (global r name) (mdl-session-global (run-result-session r) name))
(define prompt "Do you wish to leave the game? (Y is affirmative): \n")

;; === C1: the complete session ====================================================
(define c1 (run-game commands))
(define c1-result (run-result-result c1))
(check-clean-run c1 "C1")
;; Normal user quit: the loop returned the outcome (it did not raise).
(check-pred mdl-session-outcome? c1-result
            (if (exn? c1-result) (exn-message c1-result) (format "~a" c1-result)))
(when (mdl-session-outcome? c1-result)
  (check-equal? (mdl-session-outcome-kind c1-result) 'quit)
  (check-equal? (mdl-session-outcome-mdl-errors c1-result) '()))
;; Exact transcript: the pinned Confusion capture of the same input.
(define c1-reference (reference-transcript "C1-session-quit-pipe" commands))
(check-equal? (run-result-raw c1) c1-reference)
;; The reference's post-"y" activity writes MDL/ZORK.LOG (and rewrites
;; MADADV.SAVE through SAVE-IT); our no-file policy writes nothing. That is
;; the documented deviation, and it has no console output.
(check-equal? (sort (map symbol->string
                         (hash-keys (hash-ref (ref-case "C1-session-quit-pipe") 'files_changed)))
                    string<?)
              '("MDL/MADADV.SAVE" "MDL/ZORK.LOG"))
(check-equal? (hash-ref (ref-case "C1-session-quit-pipe") 'stderr_raw) "")
;; Quit prompt and move counting: quit counts, the y/n answer does not.
(define c1-raw (run-result-raw c1))
(check-equal? (length (regexp-match* (regexp-quote prompt) c1-raw)) 2)
(check-true (string-contains? c1-raw (string-append "in 7 moves.\nThis score gives you the rank of Beginner.\n" prompt)))
(check-true (string-contains? c1-raw (string-append "in 9 moves.\nThis score gives you the rank of Beginner.\n" prompt)))
(check-true (string-suffix? c1-raw prompt))       ; nothing after the final prompt
(check-false (regexp-match? #rx"I'm sorry|Error" c1-raw))
;; RECORD ran exactly once: one denied READB, one denied PRINT, no loop,
;; no CLOSE; FINISH's UNWIND cleanup QUIT did not run a second RECORD.
(check-equal? (open-records c1) '(("READB" "MDL/ZORK.LOG" 2) ("PRINT" "MDL/ZORK.LOG" 13)))
;; The extra line after "y" was never read.
(check-equal? (port->string (run-result-input c1)) (hash-ref scenario 'unread_after_quit))
;; One loop pass: SAVE-IT returned ,NULL, then RDCOM ran until QUIT.
(check-equal? (map car (run-result-events c1)) '(entry-returned pass))
(check-equal? (second (run-result-events c1)) '(pass 1))
;; Game-state checkpoints after the run.
(check-equal? (global c1 "MOVES") 9)
(check-equal? (global c1 "DEATHS") 0)
(check-equal? (global c1 "RAW-SCORE") 0)
(check-eq? (global c1 "REP") (global c1 "RDCOM"))
(check-equal? (length (mdl-session-save-records (run-result-session c1))) 1)

;; === C2: end of input while the confirmation is pending ============================
;; YES/NO's READSTRING meets EOF (count 0, the mirrored read), the stale "q" in
;; INBUF answers no, RDCOM prints ">" and its next READSTRING is the strict
;; D3 input-exhausted failure. Not a quit.
(define c2-lines (take commands 7))                  ; ... score, quit
(define c2 (run-game c2-lines))
(check-clean-run c2 "C2")
(check-pred exn:fail:mdl-input-exhausted? (run-result-result c2))
(check-equal? (run-result-raw c2) (reference-transcript "C2-eof-at-yesno" c2-lines))
(check-equal? (hash-ref (ref-case "C2-eof-at-yesno") 'stderr_raw) "Error: Unexpected EOF\n")
(check-equal? (open-records c2) '())
(check-equal? (global c2 "MOVES") 7)

;; === C3: unknown words and parser replies, then quit/y =============================
;; The whole reference C3 session. Its "put leaflet in" reaches SPARSE's TOP
;; (77np.mud:126); before M4 S4 (docs/evidence/M4/S4-TOP.md) that line, and
;; everything after it but the quit, was left out here.
(define c3-lines '("xyzzy" "frobozzle" "blorfintz" "qqq" "take" "open the" "put leaflet in" ""
                   "north west" "score" "quit" "y"))
(define c3 (run-game c3-lines))
(check-clean-run c3 "C3")
(check-equal? (and (mdl-session-outcome? (run-result-result c3))
                   (mdl-session-outcome-kind (run-result-result c3)))
              'quit)
(define c3-expected (reference-transcript "C3-unknown-and-malformed" c3-lines))
(check-true (string-contains? c3-expected ">Opening the mailbox reveals a leaflet.\n>I can't make sense out of that.\n>"))
(check-true (string-contains? c3-expected "in 10 moves."))
(check-equal? (run-result-raw c3) c3-expected)
(check-true (string-contains? (run-result-raw c3) ">I don't know the word XYZZY\n>"))
(check-true (string-contains? (run-result-raw c3) ">I don't know the word BLORF\n>"))
(check-equal? (global c3 "MOVES") 10)
(check-equal? (open-records c3) '(("READB" "MDL/ZORK.LOG" 2) ("PRINT" "MDL/ZORK.LOG" 13)))

;; === an unsupported host operation stays a strict failure ============================
;; "info" reaches FILE-TO-TTY's <OPEN "READ" ...> (77rooms.mud:961), which is
;; outside the supported OPEN forms. It is a host strict error: it is not an
;; MDL ERROR, so HANDLE never runs and no FINISH/RECORD/QUIT follows.
(define s4 (run-game '("north" "info" "quit" "y")))
(check-clean-run s4 "strict")
(define s4-result (run-result-result s4))
(check-pred exn:fail? s4-result)
(check-false (exn:fail:mdl-input-exhausted? s4-result))
(check-false (mdl-session-outcome? s4-result))
(check-regexp-match #rx"^OPEN: mode \"READ\" is not supported" (exn-message s4-result))
(check-false (regexp-match? #rx"I'm sorry|Do you wish to leave" (run-result-raw s4)))
(check-equal? (port->string (run-result-input s4)) "quit\ny\n")
(check-equal? (open-records s4) '())
