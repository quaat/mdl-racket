#lang racket/base
;; M4 scenario "the thief fights and is fought" (epic #163, combat.thief;
;; tests/scenarios/thief-fight.json). The faithful run.mud path, <FLOAD
;; "77loadall.mud"> then SAVE-IT through the host top-level loop, on the fixed
;; session clock (fixed_epoch 250776000, zone UTC; ADR-0052), with the
;; unmodified pinned sources and no RANDOM override.
;;
;; Commands 1-25 are strange-passage's (the troll killed with the sword, the
;; maze route into the Cyclops Room, `odysseus`: the cyclops flees,
;; CYCLOPS-FLAG). Command 26 `up` into the Treasure Room: its room action
;; TREASURE-ROOM (77act1.mud:623) brings the thief there on the walk-in
;; whatever the seed ("You hear a scream of anguish as you violate the
;; robber's hideaway.  Using passages unknown to you, he rushes to its
;; defense."), sets his FIGHTBIT and clears the chalice's TAKEBIT; the
;; FIGHTING demon (78melee.mud:282) has him attack at once ("You dodge as the
;; thief comes in low."). Commands 27 and 28 `kill thief with sword`: the
;; hero's blows wound the thief twice (OCAPAC 4 -> 3 -> 2); the thief's first
;; answer wounds the hero (ASTRENGTH -1, CURIN enabled), his second knocks the
;; hero out and, OUT set, kills him ("The thief knocks you out.", "The thief,
;; who is essentially a pragmatist, dispatches you ...", JIGS-UP: DEATHS 1,
;; RAW-SCORE 60 -> 50). READSTRING entry 28 is YES/NO's: its prompt is the
;; death question, not `>` (#:entry-prompts, ADR-0062 amendment); `y`
;; (patched in the forest); `look`, `inventory`, `diagnose`, `score`. The
;; thief stays in the Treasure Room until the turn after (the ROBBER demon's
;; "leave if victim left"); he is not killed, his treasures are not
;; recovered. Prefix 28 (input ends at the question) is patched too: YES/NO's
;; end-of-input read returns 0 and the stale first character of INBUF, "k"
;; of "kill", answers: not one of "NnfF", so yes (77defs.mud:431-438).
;;
;; Prefixes 28 (the question) and 29 (the thief leaves at the end-of-input
;; turn) are re-run; robber_hroom is compared at every READSTRING entry, at
;; the end and in per-prefix mode, but not used to classify end-of-input
;; tails (#:eof-classification-ignore-keys, ADR-0062 amendment).
;;
;; Compared with the pinned Confusion captures in
;; docs/evidence/M4/thief-fight-reference.json (THIEF-FIGHT.md, captured twice,
;; byte-identical transcripts) through the shared runner
;; tests/m4_scenario_runner.rkt, byte for byte after D1 only. Scenario
;; evidence for M4, not a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_thief_fight_test.rkt   (exit status is authoritative)
(require rackunit racket/list racket/string "m4_scenario_runner.rkt" "m4_thief_checkpoint.rkt")

(current-check-handler (lambda (e) (raise e)))

(define question "Do you want me to try to patch you?")
(define commands
  (append (take (hash-ref (m4-reference "strange-passage") 'commands) 25)
          '("up" "kill thief with sword" "kill thief with sword" "y" "look" "inventory"
            "diagnose" "score")))

;; --- reference-side checks (no game run) ------------------------------------------------
(define reference (m4-reference "thief-fight"))
(define ref-checks (hash-ref reference 'checks))
(define cps (hash-ref (hash-ref reference 'diagnostic) 'checkpoints))
(define (cp k key) (strip-trailers (hash-ref (list-ref cps k) key)))
(define t1 (hash-ref (hash-ref reference 'transcript) 'game_output_raw))
(check-equal? (hash-ref reference 'commands) commands)
(check-equal? (length commands) 33)
(check-equal? (list-ref commands 24) "odysseus")
(check-equal? (hash-ref reference 'entry_prompts) (hasheq '|28| question))
(check-equal? (hash-ref ref-checks 'diag_yes_no_entries) '(28))
(check-equal? (hash-ref ref-checks 'diag_yes_no_results) '("T"))
(check-equal? (remove-duplicates (hash-ref reference 'endings)) '("eof"))
;; (HERE AOBJS THIEF-OROOM THIEF-OCAPAC THIEF-FIGHTING WINNER-ASTRENGTH
;;  DEATHS RAW-SCORE CHALI-TAKEBIT) by READSTRING entry
(define (fight k) (map (lambda (key) (cp k key))
                       '(here aobjs thief_oroom thief_ocapac thief_fighting winner_astrength
                              deaths raw_score chali_takebit)))
(check-equal?
 (for/list ([k (in-range 25 34)]) (cons k (fight k)))
 '((25 "CYCLO" "(LAMP SWORD)" "#FALSE ()" "4" "#FALSE ()" "0" "0" "35" "T")
   (26 "TREAS" "(LAMP SWORD)" "TREAS" "4" "T" "0" "0" "60" "#FALSE ()")     ; up: he rushes in, attacks, misses
   (27 "TREAS" "(LAMP SWORD)" "TREAS" "3" "T" "-1" "0" "60" "#FALSE ()")    ; both wounded
   (28 "TREAS" "(LAMP SWORD)" "TREAS" "2" "T" "-2" "1" "50" "#FALSE ()")    ; thief wounded; hero killed: the question
   (29 "FORE1" "()" "TREAS" "2" "T" "-2" "1" "50" "#FALSE ()")              ; patched
   (30 "FORE1" "()" "#FALSE ()" "2" "#FALSE ()" "-2" "1" "50" "#FALSE ()")  ; the thief has left
   (31 "FORE1" "()" "#FALSE ()" "2" "#FALSE ()" "-2" "1" "50" "#FALSE ()")
   (32 "FORE1" "()" "#FALSE ()" "2" "#FALSE ()" "-2" "1" "50" "#FALSE ()")
   (33 "FORE1" "()" "#FALSE ()" "2" "#FALSE ()" "-2" "1" "50" "#FALSE ()")))
;; before the Treasure Room the thief is never in a room (with the hero or not)
(check-equal? (remove-duplicates (for/list ([k (in-range 0 26)]) (cp k 'thief_oroom))) '("#FALSE ()"))
;; the stiletto stays in the thief's hand; the thief is not killed (HACTION kept)
(check-equal? (remove-duplicates (for/list ([k (in-range 0 34)]) (list (cp k 'still_ocan) (cp k 'robber_haction))))
              '(("THIEF" "ROBBER")))
;; shorter prefixes: non-standard through the question (28: the patch at the
;; end-of-input answer) and the thief leaving the Treasure Room (29)
(define ends (hash-ref reference 'end_checkpoints))
(check-equal? (for/list ([k (in-range 0 33)]
                         #:when (for/or ([(key v) (in-hash (list-ref cps k))])
                                  (and (not (memq key '(n robber_hroom)))
                                       (not (equal? v (hash-ref (list-ref ends k) key))))))
                k)
              '(28 29))
(check-equal? (cp 28 'here) "TREAS")
(check-equal? (strip-trailers (hash-ref (list-ref ends 28) 'here)) "FORE1")
(define fight-text
  (string-append
   "You hear a scream of anguish as you violate the robber's hideaway. \r\n"
   "Using passages unknown to you, he rushes to its defense.\n"
   "You dodge as the thief comes in low.\n"
   "Your sword has begun to glow very brightly.\n"
   ">Your sword pinks the thief on the wrist, but it's not serious.\n"
   "A quick thrust pinks your left arm, and blood starts to\r\ntrickle down.\n"
   ">The thief is struck on the arm, blood begins to trickle down.\n"
   "The thief knocks you out.\n"
   "The thief, who is essentially a pragmatist, dispatches you as a\r\n"
   "threat to his livelihood.\n"
   "It appears that that last blow was too much for you.  I'm afraid you\r\nare dead.\n"
   question "Now, let me see..."))
(check-true (string-contains? t1 fight-text))
(check-true (string-contains? t1 "Your score would be 50 [total of 500 points], in 32 moves."))

;; --- the scenario ------------------------------------------------------------------------
(run-m4-scenario "thief-fight" commands
                 #:checkpoint thief-checkpoint
                 #:entry-prompts (hasheqv 28 question)
                 #:eof-classification-ignore-keys '(robber_hroom)
                 #:check-turn
                 (lambda (k transcript)
                   (when (>= k 29)
                     (check-true (string-contains? transcript fight-text)))))
