#lang racket/base
;; M4 Phase 2 scenario "death by grue, resurrection" (epic #163, death and
;; recovery; tests/scenarios/grue-resurrection.json). Promotes the discovery
;; run F12 of docs/evidence/M4/GAMEPLAY-FAILURE-INVENTORY.md ("grue death,
;; patched": the game's own word, JIGS-UP asks "Do you want me to try to patch
;; you?"), extended so that the hero carries possessions to scatter. The
;; faithful run.mud path, <FLOAD "77loadall.mud"> then SAVE-IT through the
;; host top-level loop, on the fixed session clock (fixed_epoch 250776000,
;; zone UTC; ADR-0052), with the unmodified pinned sources:
;;   kitchen; take the sack and the bottle; the sword from the living room
;;   (the lamp stays there); `up` into the dark attic; `north`: WALK's
;;   <PROB 75> for an unlit room (77rooms.mud:1063) succeeds and the attic has
;;   no north exit, so JIGS-UP (77rooms.mud:870): SCORE-UPD -10, DEATHS 1, the
;;   question, answered `y` through YES/NO (77defs.mud:431): the lamp is put
;;   first in the possessions, GOTO FORE1, ROB-ADV (no valuable), the four
;;   possessions go one each to the first RANDOM-LIST rooms (77dung.mud:1476):
;;   lamp -> living room, sword -> kitchen, bottle -> clearing, sack -> forest
;;   (FORE3); then `look`, `inventory`, a walk past the sack, the sword and
;;   the lamp, `score`.
;;
;; Compared with the pinned Confusion captures in
;; docs/evidence/M4/grue-resurrection-reference.json
;; (GRUE-RESURRECTION-REFERENCE.md) through the shared runner
;; tests/m4_scenario_runner.rkt, byte for byte after D1 only. READSTRING entry
;; 11 is YES/NO's: its prompt is the question, not `>` (#:entry-prompts,
;; ADR-0062 amendment). Prefix 11 (input ends at the question) ends by the
;; game's QUIT natively and here: YES/NO's end-of-input read returns 0, the
;; stale `n` of `north` in INBUF refuses, FINISH -> RECORD (both OPENs denied,
;; ADR-0055; natively it appends to MDL/ZORK.LOG) -> QUIT (#:quit-prefixes).
;; Every other prefix ends by end of input (D3). Scenario evidence for M4, not
;; a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_grue_resurrection_test.rkt   (exit status is authoritative)
(require rackunit racket/list racket/string "m4_scenario_runner.rkt" "m4_death_checkpoint.rkt")

(current-check-handler (lambda (e) (raise e)))

(define commands '("north" "east" "open window" "west" "take sack" "take bottle" "west"
                   "take sword" "east" "up" "north" "y" "look" "inventory" "east" "west"
                   "east" "west" "west" "score"))
(define question "Do you want me to try to patch you?")

;; --- reference-side checks (no game run) ------------------------------------------------
(define reference (m4-reference "grue-resurrection"))
(define ref-checks (hash-ref reference 'checks))
(define diagnostic (hash-ref reference 'diagnostic))
(define cps (hash-ref diagnostic 'checkpoints))
(define (cp k key) (strip-trailers (hash-ref (list-ref cps k) key)))
(check-equal? (hash-ref reference 'entry_prompts) (hasheq '|11| question))
(check-equal? (hash-ref diagnostic 'yes_no_entries) '(11))
(check-equal? (hash-ref diagnostic 'yes_no_results) '("T"))
(check-equal? (hash-ref ref-checks 'prefix_runs_with_non_standard_end) '(11))
;; The death: entry 10 in the attic with three possessions; entry 11 (the
;; question) after SCORE-UPD -10 and DEATHS 1; entry 12 in the forest, empty
;; handed, the possessions scattered; the lamp, untouched, is back in the
;; living room.
(check-equal? (list (cp 10 'here) (cp 10 'aobjs) (cp 10 'raw_score) (cp 10 'deaths))
              '("ATTIC" "(SWORD BOTTL SBAG)" "10" "0"))
(check-equal? (list (cp 11 'here) (cp 11 'raw_score) (cp 11 'ascore) (cp 11 'deaths))
              '("ATTIC" "0" "0" "1"))
(check-equal? (list (cp 12 'here) (cp 12 'aobjs) (cp 12 'lamp_oroom) (cp 12 'sword_oroom)
                    (cp 12 'bottl_oroom) (cp 12 'sbag_oroom) (cp 12 'deaths))
              '("FORE1" "()" "LROOM" "KITCH" "CLEAR" "FORE3" "1"))
;; The only RANDOM draw of the death turn is WALK's PROB 75 (before entry 11).
(check-equal? (for/list ([d (hash-ref diagnostic 'random_draws)]
                         #:when (= 11 (hash-ref d 'before_checkpoint)))
                (hash-ref d 'args))
              '("()"))
;; Native file effects: SAVE-IT rewrites MDL/MADADV.SAVE in every run;
;; only the quitting prefix 11 also writes MDL/ZORK.LOG (RECORD), which this
;; runtime denies (ADR-0055; ADR-0048 for SAVE-IT). Ours writes nothing (the
;; runner's guard).
(check-equal? (for/list ([fs (hash-ref ref-checks 'prefix_files_changed)] [k (in-naturals)]
                         #:when (member "MDL/ZORK.LOG" fs))
                k)
              '(11))
(check-equal? (hash-ref (hash-ref reference 'native_zork_log) '|P11-grue-resurrection-prefix|)
              "\n        (MTRZORK)       December 12 at 12:00 PM\nPlayed for 0 seconds.\n0/500 points, 11 moves, 1 death.  In Attic. Died.\n/KI\n")

;; --- the scenario ------------------------------------------------------------------------
(run-m4-scenario "grue-resurrection" commands
                 #:checkpoint death-checkpoint
                 #:entry-prompts (hasheqv 11 question)
                 #:quit-prefixes '(11)
                 #:quit-open-records '(("READB" "MDL/ZORK.LOG" 2) ("PRINT" "MDL/ZORK.LOG" 13))
                 #:check-turn
                 (lambda (k transcript)
                   ;; from the answer on, the resurrection text follows the
                   ;; question directly (no CRLF, no echo)
                   (when (>= k 12)
                     (check-true (string-contains?
                                  transcript
                                  (string-append question "Now, let me see...\r\n"))))))
