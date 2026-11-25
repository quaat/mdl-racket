#lang racket/base
;; M4 Phase 2 scenario "killed by the troll" (epic #163, death and recovery;
;; combat; tests/scenarios/troll-death.json). The faithful run.mud path,
;; <FLOAD "77loadall.mud"> then SAVE-IT through the host top-level loop, on
;; the fixed session clock (fixed_epoch 250776000, zone UTC; ADR-0052), with
;; the unmodified pinned sources and no RANDOM override: the troll-combat path
;; without the sword (take the lamp, move the rug, open the trap door, the
;; lamp on, `down`, `east` into the troll room), then `wait` eight times. The
;; troll fights the unarmed hero through the demon FIGHTING (78melee.mud:282)
;; -> BLOW (78melee.mud:377): the sixth `wait` staggers the hero (ASTAGGERED),
;; the seventh wounds him (ASTRENGTH -1, the CURIN clock enabled), the eighth
;; kills him ("The troll's axe removes your head.") and JIGS-UP
;; (77rooms.mud:870) asks the question, answered `y`: the carried lit lamp
;; goes to the living room, the hero is resurrected in the forest with his
;; light wound, the trap door is untouched again (OTOUCH? false). Then `look`,
;; `inventory`, `diagnose`, `score`.
;;
;; READSTRING entry 19 is YES/NO's: its prompt is the question, not `>`
;; (#:entry-prompts, ADR-0062 amendment). Prefix 19 (input ends at the
;; question) resurrects too: YES/NO's end-of-input read returns 0 and the
;; stale `w` of `wait` in INBUF is not a refusal; it then ends by end of input
;; (D3), as every prefix does here.
;;
;; Compared with the pinned Confusion captures in
;; docs/evidence/M4/troll-death-reference.json (TROLL-DEATH-REFERENCE.md)
;; through the shared runner tests/m4_scenario_runner.rkt, byte for byte
;; after D1 only. Scenario evidence for M4, not a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_troll_death_test.rkt   (exit status is authoritative)
(require rackunit racket/list racket/string "m4_scenario_runner.rkt" "m4_death_checkpoint.rkt")

(current-check-handler (lambda (e) (raise e)))

(define commands (append '("north" "east" "open window" "west" "west" "take lamp" "move rug"
                           "open trap door" "turn on lamp" "down" "east")
                         (make-list 8 "wait")
                         '("y" "look" "inventory" "diagnose" "score")))
(define question "Do you want me to try to patch you?")

;; --- reference-side checks (no game run) ------------------------------------------------
(define reference (m4-reference "troll-death"))
(define ref-checks (hash-ref reference 'checks))
(define diagnostic (hash-ref reference 'diagnostic))
(define cps (hash-ref diagnostic 'checkpoints))
(define (cp k key) (strip-trailers (hash-ref (list-ref cps k) key)))
(check-equal? (hash-ref reference 'entry_prompts) (hasheq '|19| question))
(check-equal? (hash-ref diagnostic 'yes_no_entries) '(19))
(check-equal? (hash-ref diagnostic 'yes_no_results) '("T"))
(check-equal? (hash-ref ref-checks 'prefix_runs_with_non_standard_end) '(19))
(check-equal? (remove-duplicates (hash-ref reference 'endings)) '("eof"))
;; The fight, by READSTRING entry: in the troll room from entry 11; the hero
;; staggered (entry 17, the troll now fighting), then wounded (entry 18:
;; ASTRENGTH -1, CURIN enabled), then dead (entry 19: DEATHS 1, score 35 ->
;; 25); entry 20 in the forest, empty handed, the lit lamp in the living
;; room, the trap door untouched again, the wound and the cure clock kept.
(check-equal? (for/list ([k (in-range 11 21)])
                (list (cp k 'here) (cp k 'winner_staggered) (cp k 'winner_astrength)
                      (cp k 'curin_cflag) (cp k 'troll_fighting) (cp k 'deaths) (cp k 'raw_score)))
              (append (make-list 6 '("MTROL" "#FALSE ()" "0" "#FALSE ()" "#FALSE ()" "0" "35"))
                      '(("MTROL" "T" "0" "#FALSE ()" "T" "0" "35")
                        ("MTROL" "#FALSE ()" "-1" "T" "T" "0" "35")
                        ("MTROL" "#FALSE ()" "-1" "T" "T" "1" "25")
                        ("FORE1" "#FALSE ()" "-1" "T" "T" "1" "25"))))
(check-equal? (list (cp 19 'aobjs) (cp 19 'lamp_olight) (cp 19 'door_otouch))
              '("(LAMP)" "1" "T"))
(check-equal? (list (cp 20 'aobjs) (cp 20 'lamp_oroom) (cp 20 'lamp_olight) (cp 20 'door_otouch))
              '("()" "LROOM" "1" "#FALSE ()"))
;; RANDOM draws by READSTRING entry: one per `wait` before the fight, then
;; three, two and two in the stagger, wound and death turns.
(check-equal? (for/list ([d (hash-ref diagnostic 'random_draws)]) (hash-ref d 'before_checkpoint))
              '(0 11 12 13 14 15 16 17 17 17 18 18 19 19))
;; No run writes MDL/ZORK.LOG natively (no QUIT); every run rewrites
;; MADADV.SAVE through SAVE-IT (ADR-0048).
(check-equal? (remove-duplicates (hash-ref ref-checks 'prefix_files_changed)) '(("MDL/MADADV.SAVE")))

;; --- the scenario ------------------------------------------------------------------------
(run-m4-scenario "troll-death" commands
                 #:checkpoint death-checkpoint
                 #:entry-prompts (hasheqv 19 question)
                 #:check-turn
                 (lambda (k transcript)
                   (when (>= k 19)
                     (check-true (string-contains?
                                  transcript
                                  (string-append "The troll's axe removes your head.\n"
                                                 "It appears that that last blow was too much for you.  I'm afraid you\r\nare dead.\n"
                                                 question))))))
