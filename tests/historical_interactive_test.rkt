#lang racket/base
;; Historical regression (S7, ADR-0050): the faithful run.mud path played
;; interactively. <FLOAD "77loadall.mud"> (mdl-session-load!), then the host
;; top-level loop applies SAVE-IT, prints its value (D1), and applies the GVAL
;; of REP (the game's RDCOM) to the six approved house-boot commands.
;;
;; Asserts (a) INITIALIZED: startup reaches the first READSTRING without
;; error; (b) INTERACTIVE: all six commands are read and dispatched; (c) end of
;; input gives the mirrored empty read ("Beg pardon?", ">") and then the strict
;; host-level input-exhausted error (D3). The game text is compared with the
;; approved CANDIDATE golden (tests/fixtures/house-boot-golden.json) as
;; canonical_text(ONLCR(raw)) (D2), after removing the golden's LISTEN banner
;; and "DONE" lines (D1) and normalising the "This version created" date line
;; in both texts: DSKDATE reads the host clock until issue #135 provides a
;; fixed clock. RANDOM is seeded from that clock too, so the "west" response
;; (ROOM-INFO's <PROB 80>) is accepted in either of its two source-defined
;; forms. This is NOT a SMOKE_PARITY claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: make test-m3-interactive   (or: raco test tests/historical_interactive_test.rkt)
(require rackunit racket/runtime-path racket/port racket/string racket/list json
         "../mdl/loader.rkt" "../mdl/runtime/core.rkt")

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(define-runtime-path scenario-file "scenarios/house-boot.json")
(define-runtime-path golden-file "fixtures/house-boot-golden.json")
(unless (directory-exists? source-root)
  (error 'historical-interactive "pinned source missing: ~a" source-root))

(define scenario (call-with-input-file scenario-file read-json))
(define golden (call-with-input-file golden-file read-json))
(define commands (hash-ref scenario 'commands))
(check-equal? commands '("north" "west" "open mailbox" "take leaflet" "inventory" "score"))
(check-equal? (map (lambda (c) (hash-ref c 'input)) (hash-ref golden 'commands)) commands)

;; The host feeds LF-terminated lines and never echoes (D7).
(define input (open-input-string (string-append (string-join commands "\n") "\n")))
(define output (open-output-string))
(define session (make-mdl-session source-root #:input-port input #:output-port output))
(define (listing dir) (sort (map path->string (directory-list dir)) string<?))
(define source-before (listing source-root))

(define load-report (mdl-session-load! session "77loadall.mud"))
(check-equal? (hash-ref load-report 'status) "PASS")
(check-equal? (hash-ref load-report 'completed_expressions) 1229)
(check-equal? (hash-ref load-report 'skipped_expressions) 0)

(define events '())
;; Hang guard (review follow-up): RDCOM never returns, so a runtime bug that
;; stops consuming input would loop forever. The run gets a wall-clock limit
;; and a timeout is reported as a failure, not a hang.
(define run-limit-seconds 300)
(define failure
  (let* ([result (make-channel)]
         [worker (thread
                  (lambda ()
                    (channel-put
                     result
                     (with-handlers ([exn:fail? values])
                       (mdl-session-run-interactive
                        session "SAVE-IT"
                        #:on-event (lambda (e) (set! events (cons e events))))
                       'returned))))])
    (or (sync/timeout run-limit-seconds result)
        (begin (kill-thread worker) 'timed-out))))
(set! events (reverse events))
(define raw (get-output-string output))

;; --- (c) end of input: mirrored empty read, then the strict error (D3) -------
(check-pred exn:fail:mdl-input-exhausted? failure
            (if (exn? failure) (exn-message failure) (format "~a" failure)))
(check-equal? (exn-message failure)
              (string-append "READSTRING: input exhausted: the session input ended and the "
                             "mirrored end-of-input read was already returned "
                             "(maintainer decision D3; ADR-0050)"))
;; Confusion boot-six ends "...rank of Beginner.\n>Beg pardon?\n>".
(check-true (string-suffix? raw "This score gives you the rank of Beginner.\n>Beg pardon?\n>")
            raw)
;; The MDL ERROR handler HANDLE never ran (its TELL/FINISH text is absent).
(check-false (regexp-match? #rx"I'm sorry|Do you wish to leave" raw))

;; --- (a) INITIALIZED: SAVE-IT returned ,NULL and RDCOM reached READSTRING ----
(check-equal? (map car events) '(entry-returned pass))
(check-eq? (cadr (first events)) (mdl-session-global session "NULL"))
(check-equal? (second events) '(pass 1))   ; RDCOM never returns: one pass
(check-eq? (mdl-session-global session "REP") (mdl-session-global session "RDCOM"))

;; --- transcript normalisation (D1, D2) -----------------------------------------
(define (onlcr text) (string-replace text "\n" "\r\n"))
(define (canonical-text text)        ; scripts/boot_reference.py canonical_text
  (string-replace (string-replace text "\r\n" "\n") "\r" "\n"))
(define (normalise-date text)
  (regexp-replace* #rx"This version created [A-Z][a-z]+ [0-9]+\\." text
                   "This version created [DATE]."))
(define (remove-line-once text line)
  (define n (length (regexp-match* (regexp-quote line) text)))
  (unless (= n 1) (error 'remove-line-once "expected one ~s, found ~a" line n))
  (string-replace text line "" #:all? #f))
(define ours (normalise-date (canonical-text (onlcr raw))))
(define golden-boot
  (normalise-date
   (remove-line-once (remove-line-once (hash-ref golden 'boot_output)
                                       "LISTENING-AT-LEVEL 1 PROCESS 1\n")
                     "\"DONE\"\n")))
;; Prompts are bare ">" with no newline; no game text in this scenario has ">".
(define segments (string-split ours ">" #:trim? #f))
(check-equal? (length segments) 9 ours)   ; boot, 6 commands, Beg pardon?, ""

;; Our raw date line really differs only by the clock (documented limit).
(check-regexp-match #rx"This version created [A-Z][a-z]+ [0-9]+\\.\n" raw)

;; (a) boot text up to the first prompt equals the approved golden, including
;; the blank line from the D1 print of ,NULL.
(check-equal? (first segments) golden-boot)
(check-true (string-contains? (first segments) "This version created [DATE].\n\nYou are in an open field"))

;; --- (b) INTERACTIVE: all six commands read, dispatched, answered as golden ---
;; "west" re-enters West of House. ROOM-INFO (77rooms.mud:521-525) prints the
;; brief RDESC2 for a seen room only if <PROB 80> holds, so with RANDOM seeded
;; from the unfixed host clock this output is RNG-dependent: about one run in
;; five prints the full description instead (observed locally; see
;; S7-INTERACTIVE.md). Until issue #135 fixes the clock, "west" must equal
;; either the golden's brief text or the full West of House description, taken
;; from the golden boot text (the same ROOM-INFO output). Every other command
;; is compared exactly.
(define full-west-of-house
  (cadr (regexp-match #rx"This version created \\[DATE\\]\\.\n\n(.*)$" golden-boot)))
(check-equal? full-west-of-house
              "You are in an open field west of a big white house, with a boarded\n\nfront door.\nThere is a small mailbox here.\n")
(for ([command (in-list (hash-ref golden 'commands))]
      [segment (in-list (take (rest segments) 6))])
  (if (equal? (hash-ref command 'input) "west")
      (check-not-false (member segment (list (hash-ref command 'output) full-west-of-house))
                       segment)
      (check-equal? segment (hash-ref command 'output) (hash-ref command 'input))))
(check-equal? (list-ref segments 7) "Beg pardon?\n")
(check-equal? (list-ref segments 8) "")
;; MOVES counts the six non-empty reads; the empty EOF read is not counted.
(check-equal? (mdl-session-global session "MOVES") 6)
(check-equal? (port->string input) "")       ; every command line was consumed
;; No file was written next to the source (SAVE is a session record).
(check-equal? (listing source-root) source-before)
(check-equal? (length (mdl-session-save-records session)) 1)
