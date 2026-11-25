#lang racket/base
;; M4 S10 scenario "help and info" (tests/scenarios/help-info.json; issue
;; #171, ADR-0055 amendment "Read-only allowlist"). The faithful run.mud path,
;; <FLOAD "77loadall.mud"> then SAVE-IT through the host top-level loop, on
;; the fixed session clock (fixed_epoch 250776000, zone UTC; ADR-0052):
;; `north`, `help` (HELP -> FILE-TO-TTY, 77rooms.mud:956-985: OPEN "READ" of
;; MDL/MADADV.HELP, FILE-LENGTH 4274, 42 READSTRINGs of 100 by count and one
;; with ,BREAKS that meets end of file after 74, PRINTSTRING with each count,
;; CRLF, CLOSE), `east`, `info` (MADADV.INFO, 1527 = 15 x 100 + 27), `open
;; window`, `?` (LEX maps it to HELP: opened, read and closed again), `west`,
;; `score`.
;;
;; Compared with the pinned Confusion pipe captures in
;; docs/evidence/M4/help-info-reference.json (HELP-INFO-REFERENCE.md) through
;; the shared runner tests/m4_scenario_runner.rkt: every turn's transcript
;; byte for byte (D1 only) and checkpoint, and the end-of-input tail. The help
;; text holds two `>` inside a line, so prompts are split at line-initial `>`
;; (#:prompt-split 'line-initial, ADR-0062 amendment; strict count). The
;; checkpoint includes the 100 character codes of ,INBUF, which the file
;; READSTRINGs share with RDCOM: after `help` it holds the last 74 help
;; characters and 26 of the previous chunk. Only terminal READSTRINGs are
;; turns (a file READSTRING never calls the input observer); the runner's
;; guard also fails on a file CHANNEL left open. Scenario evidence for M4, not
;; a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_help_info_test.rkt   (exit status is authoritative)
(require rackunit racket/string racket/list racket/file
         "m4_scenario_runner.rkt"
         (only-in "../mdl/loader.rkt" mdl-session-call mdl-session-global)
         (only-in "../mdl/runtime/core.rkt" mdl-string-snapshot))

(current-check-handler (lambda (e) (raise e)))

(define commands '("north" "help" "east" "info" "open window" "?" "west" "score"))

;; --- read-only checkpoint (the reference's DIAG-STATE fields) ---------------------------
(define (inbuf-codes s)
  (define str (mdl-string-snapshot 'help-info (mdl-session-global s "INBUF") "INBUF must be a STRING"))
  (string-append "(" (string-join (for/list ([ch (in-string str)])
                                    (number->string (char->integer ch)))
                                  " ")
                 ")"))
(define (our-checkpoint s)
  (define winner (mdl-session-global s "WINNER"))
  (hasheq 'here (render s (field s (mdl-session-global s "HERE") "RID"))
          'aobjs (oids s (field s winner "AOBJS"))
          'moves (render s (mdl-session-global s "MOVES"))
          'raw_score (render s (mdl-session-global s "RAW-SCORE"))
          'deaths (render s (mdl-session-global s "DEATHS"))
          'tell_flag (render s (mdl-session-global s "TELL-FLAG"))
          'inbuf (inbuf-codes s)))

;; --- reference-side checks (no game run) ------------------------------------------------
(define reference (m4-reference "help-info"))
(define split (hash-ref (hash-ref (hash-ref reference 'transcript) 'split) 'commands))
(define (response i) (hash-ref (list-ref split i) 'output))
(define help-text (bytes->string/latin-1 (file->bytes (build-path m4-source-root "MDL" "MADADV.HELP"))))
(define info-text (bytes->string/latin-1 (file->bytes (build-path m4-source-root "MDL" "MADADV.INFO"))))
(check-equal? (hash-ref reference 'prompt_split) "line-initial")
(check-equal? (response 1) (string-append "\n" help-text "\n"))
(check-equal? (response 3) (string-append "\n" info-text "\n"))
(check-equal? (response 5) (string-append "\n" help-text "\n"))
(check-true (string-prefix? (response 7) "\nYour score would be 10 [total of 500 points], in 8 moves."))
(check-equal? (hash-ref (hash-ref reference 'checks) 'prefix_runs_with_non_standard_eof_tail) '())
(define file-events (hash-ref (hash-ref reference 'checks) 'x1_file_events))
(check-equal? (filter (lambda (e) (hash-has-key? e 'FILE-LENGTH-RESULT)) file-events)
              (list (hasheq 'FILE-LENGTH-RESULT "4274") (hasheq 'FILE-LENGTH-RESULT "1527")
                    (hasheq 'FILE-LENGTH-RESULT "4274")))

;; --- the scenario ------------------------------------------------------------------------
(run-m4-scenario "help-info" commands
                 #:checkpoint our-checkpoint
                 #:prompt-split 'line-initial
                 #:check-turn
                 (lambda (k transcript)
                   ;; from k = 2 on (after `help`) the compared output holds the
                   ;; whole file between CRLFs, followed by a prompt (single run:
                   ;; the output at entry k; per-prefix: the whole prefix run)
                   (when (>= k 2)
                     (check-true (string-contains? transcript (string-append "\n" help-text "\n>"))))))
