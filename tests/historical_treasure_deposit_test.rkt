#lang racket/base
;; M4 Phase 3 scenario "a treasure in the trophy case" (epic #163, scoring;
;; tests/scenarios/treasure-deposit.json). The faithful run.mud path,
;; <FLOAD "77loadall.mud"> then SAVE-IT through the host top-level loop, on
;; the fixed session clock (fixed_epoch 250776000, zone UTC; ADR-0052), with
;; the unmodified pinned sources and no RANDOM override: the house-cellar path
;; (lamp, rug, trap door, lamp on, `down`), `look`, `south` twice to the
;; Gallery, `take painting` (SCORE-OBJ: OFVAL 4, RAW-SCORE 35 -> 39), `south`
;; to the Studio, `up` the chimney (CHIMNEY-FUNCTION, 77act1.mud:289: the lamp
;; and one more object) to the kitchen, `west`, `open case`, `put painting in
;; case`: the living room's action (77act1.mud:204) sets ASCORE to RAW-SCORE
;; plus the case's OTVALs, 39 + 7 = 46; `look` lists "Your collection of
;; treasures consists of: A painting"; `score` says 46.
;;
;; The `look` in the cellar is part of the route: without it (thief-robbery)
;; the thief takes the painting in the Gallery under this clock and seed.
;;
;; The ROBBER demon moves the thief (HROOM) on every turn, the end-of-input
;; turn included. robber_hroom is compared at every READSTRING entry, at the
;; end and in per-prefix mode, but not used to classify end-of-input tails
;; (#:eof-classification-ignore-keys, ADR-0062 amendment): otherwise 18 of the
;; 21 shorter prefixes would be re-run per prefix in single-run mode (19
;; boots). Prefix 15 stays non-standard: at its end of input the thief
;; appears in the Studio (thief_oroom, robber_hflag and the tail differ).
;;
;; Compared with the pinned Confusion captures in
;; docs/evidence/M4/treasure-deposit-reference.json
;; (TREASURE-DEPOSIT-REFERENCE.md) through the shared runner
;; tests/m4_scenario_runner.rkt, byte for byte after D1 only. Scenario
;; evidence for M4, not a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_treasure_deposit_test.rkt   (exit status is authoritative)
(require rackunit racket/list racket/string "m4_scenario_runner.rkt" "m4_timers_checkpoint.rkt")

(current-check-handler (lambda (e) (raise e)))

(define commands '("north" "east" "open window" "west" "west" "take lamp" "move rug"
                   "open trap door" "turn on lamp" "down" "look" "south" "south" "take painting"
                   "south" "up" "west" "open case" "put painting in case" "look" "score"))

;; --- reference-side checks (no game run) ------------------------------------------------
(define reference (m4-reference "treasure-deposit"))
(define ref-checks (hash-ref reference 'checks))
(define diagnostic (hash-ref reference 'diagnostic))
(define cps (hash-ref diagnostic 'checkpoints))
(define (cp k key) (strip-trailers (hash-ref (list-ref cps k) key)))
(check-equal? (remove-duplicates (hash-ref reference 'endings)) '("eof"))
;; The painting, the case and the score by READSTRING entry: in the Gallery
;; until entry 13; carried from entry 14 (OFVAL scored: 0, RAW-SCORE 39); the
;; case opened at entry 18; in the case from entry 19, ASCORE 46.
(define (row k) (list (cp k 'here) (cp k 'aobjs) (cp k 'raw_score) (cp k 'ascore)
                      (cp k 'paint_oroom) (cp k 'paint_ocan) (cp k 'paint_ofval)
                      (cp k 'tcase_oopen) (cp k 'tcase_contents)))
(check-equal? (row 13) '("GALLE" "(LAMP)" "35" "35" "GALLE" "#FALSE ()" "4" "#FALSE ()" "()"))
(check-equal? (row 14) '("GALLE" "(PAINT LAMP)" "39" "39" "#FALSE ()" "#FALSE ()" "0" "#FALSE ()" "()"))
(check-equal? (row 18) '("LROOM" "(PAINT LAMP)" "39" "39" "#FALSE ()" "#FALSE ()" "0" "T" "()"))
(check-equal? (row 19) '("LROOM" "(LAMP)" "39" "46" "LROOM" "TCASE" "0" "T" "(PAINT)"))
(check-equal? (row 22) (row 19))
(check-equal? (remove-duplicates (for/list ([k (in-range 0 23)]) (cp k 'paint_otval))) '("7"))
;; The thief never takes anything (his bag stays empty) and is never seen
;; while the hero is there in T1; he appears in the Studio only at the end of
;; input of prefix 15 (a non-standard tail, re-run).
(check-equal? (remove-duplicates (for/list ([k (in-range 0 23)]) (cp k 'robber_hobjs))) '("()"))
(check-equal? (remove-duplicates (for/list ([k (in-range 0 23)]) (cp k 'thief_oroom))) '("#FALSE ()"))
(check-true (string-contains? (hash-ref (hash-ref reference 'transcript) 'game_output_raw)
                              "Your collection of treasures consists of:\n A painting\n"))
(check-true (string-contains? (hash-ref (hash-ref reference 'transcript) 'game_output_raw)
                              "Your score would be 46 [total of 500 points], in 21 moves."))
(check-equal? (remove-duplicates (hash-ref ref-checks 'prefix_files_changed)) '(("MDL/MADADV.SAVE")))

;; --- the scenario ------------------------------------------------------------------------
(run-m4-scenario "treasure-deposit" commands
                 #:checkpoint timers-checkpoint
                 #:eof-classification-ignore-keys '(robber_hroom)
                 #:check-turn
                 (lambda (k transcript)
                   (when (>= k 20)
                     (check-true (string-contains? transcript ">Done.\n>")))))
