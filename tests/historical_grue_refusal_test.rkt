#lang racket/base
;; M4 Phase 2 scenario "death by grue, refused" (epic #163, death and
;; recovery; tests/scenarios/grue-refusal.json). Promotes the discovery run
;; F13 of docs/evidence/M4/GAMEPLAY-FAILURE-INVENTORY.md unchanged. The
;; faithful run.mud path, <FLOAD "77loadall.mud"> then SAVE-IT through the
;; host top-level loop, on the fixed session clock (fixed_epoch 250776000,
;; zone UTC; ADR-0052), with the unmodified pinned sources: into the kitchen,
;; `up` into the dark attic, `north`: JIGS-UP (77rooms.mud:870), SCORE-UPD
;; -10, DEATHS 1, the question answered `n` through YES/NO (77defs.mud:431):
;; "What?  You don't trust me? ...", FINISH <> (77rooms.mud:700) prints the
;; score and rank, RECORD (77rooms.mud:722) and the game's QUIT. The last
;; command `look` is never read.
;;
;; The run ends by the game's QUIT, not by end of input: the scenario
;; declares it (#:quit-prefixes, ADR-0062 amendment) for prefixes 6 (input
;; ends at the question: YES/NO's end-of-input read returns 0 and the stale
;; `n` of `north` in INBUF refuses), 7 and 8; the runner then requires the
;; host loop's 'quit outcome with no MDL ERROR, exactly the unread input, and
;; exactly RECORD's two denied OPENs (ADR-0055: READB status 2, PRINT status
;; 13; S11). Natively RECORD appends a line to MDL/ZORK.LOG in the disposable
;; game copy; this runtime writes no file (ADR-0055; the runner's guard),
;; which has no console output, so the transcripts are identical. Prefixes
;; 0-5 end by end of input (D3). READSTRING entry 6 is YES/NO's: its prompt is
;; the question, not `>` (#:entry-prompts).
;;
;; Compared with the pinned Confusion captures in
;; docs/evidence/M4/grue-refusal-reference.json (GRUE-REFUSAL-REFERENCE.md)
;; through the shared runner tests/m4_scenario_runner.rkt, byte for byte
;; after D1 only. Scenario evidence for M4, not a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_grue_refusal_test.rkt   (exit status is authoritative)
(require rackunit racket/list racket/string "m4_scenario_runner.rkt" "m4_death_checkpoint.rkt")

(current-check-handler (lambda (e) (raise e)))

(define commands '("north" "east" "open window" "west" "up" "north" "n" "look"))
(define question "Do you want me to try to patch you?")
(define zork-log-line
  "\n        (MTRZORK)       December 12 at 12:00 PM\nPlayed for 0 seconds.\n0/500 points, 6 moves, 1 death.  In Attic. Died.\n/KI\n")

;; --- reference-side checks (no game run) ------------------------------------------------
(define reference (m4-reference "grue-refusal"))
(define ref-checks (hash-ref reference 'checks))
(define diagnostic (hash-ref reference 'diagnostic))
(define cps (hash-ref diagnostic 'checkpoints))
(define (cp k key) (strip-trailers (hash-ref (list-ref cps k) key)))
(check-equal? (hash-ref reference 'entry_prompts) (hasheq '|6| question))
(check-equal? (hash-ref reference 'endings) '("eof" "eof" "eof" "eof" "eof" "eof" "quit" "quit" "quit"))
(check-equal? (hash-ref diagnostic 'yes_no_entries) '(6))
(check-equal? (hash-ref diagnostic 'yes_no_results) '("#FALSE ()"))
(check-equal? (hash-ref diagnostic 'quit_nargs) '(0))
;; X1: entries 0..6 and the state at QUIT (the last checkpoint): the score
;; after SCORE-UPD -10, one death, still in the attic.
(check-equal? (length cps) 8)
(check-equal? (list (cp 6 'here) (cp 6 'raw_score) (cp 6 'deaths) (cp 6 'moves))
              '("ATTIC" "0" "1" "6"))
(check-equal? (hash-remove (list-ref cps 7) 'n) (hash-remove (list-ref cps 6) 'n))
;; The only RANDOM draw of the death turn is WALK's PROB 75 (before entry 6).
(check-equal? (for/list ([d (hash-ref diagnostic 'random_draws)]) (hash-ref d 'before_checkpoint))
              '(0 6))
;; FINISH's score text ends the transcript; `look` was never read.
(check-true (string-suffix? (hash-ref (hash-ref reference 'transcript) 'game_output_raw)
                            (string-append question "\nWhat?  You don't trust me?  Why, only last week I patched a running ITS\r\nand it survived for over 30 seconds.  Oh, well.\nYour score is 0 [total of 500 points], in 6 moves.\nThis score gives you the rank of Beginner.\n")))
;; The documented native difference (ADR-0055; ADR-0048 for SAVE-IT's
;; MADADV.SAVE): every quitting run appends this line to MDL/ZORK.LOG in its
;; disposable game copy; the end-of-input runs write only MADADV.SAVE.
(check-equal? (hash-ref ref-checks 'prefix_files_changed)
              (append (make-list 6 '("MDL/MADADV.SAVE"))
                      (make-list 3 '("MDL/MADADV.SAVE" "MDL/ZORK.LOG"))))
(check-equal? (hash-ref reference 'native_zork_log)
              (hasheq '|P06-grue-refusal-prefix| zork-log-line
                      '|P07-grue-refusal-prefix| zork-log-line
                      '|T1-grue-refusal-pipe| zork-log-line))

;; --- the scenario ------------------------------------------------------------------------
(run-m4-scenario "grue-refusal" commands
                 #:checkpoint death-checkpoint
                 #:entry-prompts (hasheqv 6 question)
                 #:quit-prefixes '(6 7 8)
                 #:quit-open-records '(("READB" "MDL/ZORK.LOG" 2) ("PRINT" "MDL/ZORK.LOG" 13)))
