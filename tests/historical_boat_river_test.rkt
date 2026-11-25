#lang racket/base
;; M4 Phase 3b scenario "the boat and the river" (epic #163, objects beyond
;; the house; tests/scenarios/boat-river.json). The faithful run.mud path,
;; <FLOAD "77loadall.mud"> then SAVE-IT through the host top-level loop, on
;; the fixed session clock (fixed_epoch 250776000, zone UTC; ADR-0052), with
;; the unmodified pinned sources and no RANDOM override.
;;
;; Commands 1-31 are mirror-bat's (troll-combat's sixteen, the round room's
;; RANDOM exits to the Grail Room, the crawlway, Mirror Room 2, `rub mirror`:
;; the hero is left in Mirror Room 1). Then `east` (Cave), `down` (Atlantis
;; Room), `se` (Reservoir North: the reservoir is full, the only way in),
;; `take pump`, back `north` `up` `north`, `west` `west` (Slide Room), `down`
;; the slide to the cellar, `east` `north` `north` `down` (Reservoir South),
;; `up` `east` (the Dam), `down` (the Dam Base, where the folded boat lies).
;; The puzzle, IBOAT-FUNCTION / RBOAT-FUNCTION (77act2.mud:256-297):
;;
;;   command 49 `inflate boat with pump`: IBOAT replaced by RBOAT ("The boat
;;     inflates and appears seaworthy.");
;;   50 `board boat`: AVEHICLE RBOAT; 51 `launch`: onto the River Frigid
;;     (RIVR1), the boat with the hero; 52 `land`: back at the Dam Base;
;;   53 `disembark`: AVEHICLE cleared; 55 `deflate boat`: RBOAT replaced by
;;     IBOAT ("The boat deflates."); 56 `take boat`.
;;
;; The thief (ROBBER demon) takes the grail and the trident from rooms the
;; hero has left (HOBJS (GRAIL) at entry 35, (TRIDE GRAIL) at 54) and never
;; meets the hero. He appears in the Dam during prefix 47's end-of-input
;; turn (that prefix, prefix 34 whose end-of-input turn changes his bag, and
;; prefix 48 whose end-of-input tail ends the sword's glow, are re-run). robber_hroom is compared at every READSTRING entry, at the end
;; and in per-prefix mode, but not used to classify end-of-input tails
;; (#:eof-classification-ignore-keys, ADR-0062 amendment).
;;
;; The dam's own puzzle (the Maintenance Room's buttons, the bolt and the
;; sluice gates) is not on this route: this runtime stops on entering the
;; Maintenance Room (MAINT-ROOM's #DECL names the undefined type PRSOBJ;
;; docs/evidence/M4/DAM-CLOCKS.md).
;;
;; Compared with the pinned Confusion captures in
;; docs/evidence/M4/boat-river-reference.json (BOAT-RIVER-REFERENCE.md)
;; through the shared runner tests/m4_scenario_runner.rkt, byte for byte
;; after D1 only. Scenario evidence for M4, not a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_boat_river_test.rkt   (exit status is authoritative)
(require rackunit racket/list racket/string "m4_scenario_runner.rkt" "m4_boat_checkpoint.rkt")

(current-check-handler (lambda (e) (raise e)))

(define commands
  '("north" "east" "open window" "west" "west" "take sword" "inventory" "take lamp" "move rug"
    "open trap door" "turn on lamp" "down" "east"
    "kill troll with sword" "kill troll with sword" "kill troll with sword"
    "north" "east" "se" "south" "se" "east" "se" "south" "se" "south" "look" "se" "east" "sw"
    "rub mirror"
    "east" "down" "se" "take pump" "north" "up" "north" "west" "west" "down"
    "east" "north" "north" "down" "up" "east" "down"
    "inflate boat with pump" "board boat" "launch" "land" "disembark" "look" "deflate boat"
    "take boat" "inventory" "score"))

;; --- reference-side checks (no game run) ------------------------------------------------
(define reference (m4-reference "boat-river"))
(define ref-checks (hash-ref reference 'checks))
(define cps (hash-ref (hash-ref reference 'diagnostic) 'checkpoints))
(define (cp k key) (strip-trailers (hash-ref (list-ref cps k) key)))
(check-equal? (hash-ref reference 'commands) commands)
(check-equal? (take commands 31)
              (take (hash-ref (m4-reference "mirror-bat") 'commands) 31))
(check-equal? (remove-duplicates (hash-ref reference 'endings)) '("eof"))
;; The boat by READSTRING entry: (HERE AVEHICLE IBOAT-OROOM RBOAT-OROOM).
(define (boat k) (list (cp k 'here) (cp k 'winner_avehicle) (cp k 'iboat_oroom) (cp k 'rboat_oroom)))
(check-equal? (for/list ([k (in-range 48 59)]) (cons k (boat k)))
              '((48 "DOCK" "#FALSE ()" "DOCK" "#FALSE ()")
                (49 "DOCK" "#FALSE ()" "#FALSE ()" "DOCK")     ; inflate boat with pump
                (50 "DOCK" "RBOAT" "#FALSE ()" "DOCK")         ; board boat
                (51 "RIVR1" "RBOAT" "#FALSE ()" "RIVR1")       ; launch
                (52 "DOCK" "RBOAT" "#FALSE ()" "DOCK")         ; land
                (53 "DOCK" "#FALSE ()" "#FALSE ()" "DOCK")     ; disembark
                (54 "DOCK" "#FALSE ()" "#FALSE ()" "DOCK")
                (55 "DOCK" "#FALSE ()" "DOCK" "#FALSE ()")     ; deflate boat
                (56 "DOCK" "#FALSE ()" "#FALSE ()" "#FALSE ()")
                (57 "DOCK" "#FALSE ()" "#FALSE ()" "#FALSE ()")
                (58 "DOCK" "#FALSE ()" "#FALSE ()" "#FALSE ()")))
(check-equal? (list (cp 34 'here) (cp 34 'pump_oroom) (cp 35 'pump_oroom) (cp 35 'aobjs))
              '("RESEN" "RESEN" "#FALSE ()" "(PUMP LAMP SWORD)"))
(check-equal? (list (cp 31 'here) (cp 41 'here) (cp 47 'here)) '("MIRR1" "CELLA" "DAM"))
(check-equal? (cp 58 'aobjs) "(IBOAT PUMP LAMP SWORD)")
;; The dam's flags stay untouched on this route; the leak and match clocks are
;; never queued.
(check-equal? (remove-duplicates (for/list ([k (in-range 0 60)])
                                   (list (cp k 'gate_flag) (cp k 'low_tide) (cp k 'mntin_ctick) (cp k 'matin_ctick))))
              '(("#FALSE ()" "#FALSE ()" "0" "0")))
;; The thief: takes the grail and the trident from rooms the hero has left,
;; never in the hero's room at a READSTRING entry.
(check-equal? (remove-duplicates (for/list ([k (in-range 0 60)]) (cp k 'robber_hobjs)))
              '("()" "(GRAIL)" "(TRIDE GRAIL)"))
(check-equal? (list (cp 34 'robber_hobjs) (cp 35 'robber_hobjs) (cp 54 'robber_hobjs))
              '("()" "(GRAIL)" "(TRIDE GRAIL)"))
(check-equal? (remove-duplicates (for/list ([k (in-range 0 60)])
                                   (list (cp k 'thief_oroom) (cp k 'robber_hflag))))
              '(("#FALSE ()" "#FALSE ()")))
;; Shorter prefixes: non-standard only through the thief (HROOM on every
;; end-of-input turn; his bag at prefix 34; his appearance at prefix 47).
(define ends (hash-ref reference 'end_checkpoints))
(check-equal? (remove-duplicates
               (for/list ([k (in-range 0 58)])
                 (sort (for/list ([(key v) (in-hash (list-ref cps k))]
                                  #:unless (eq? key 'n)
                                  #:unless (equal? v (hash-ref (list-ref ends k) key)))
                         key)
                       symbol<?)))
              '(() (robber_hroom) (robber_hobjs robber_hroom) (robber_hflag robber_hroom thief_oroom)))
(define t1 (hash-ref (hash-ref reference 'transcript) 'game_output_raw))
(check-true (string-contains? t1 ">The boat inflates and appears seaworthy.\n"))
(check-true (string-contains? t1 ">You are in the magic boat.\n>You are on the River Frigid in the vicinity of the Dam."))
(check-true (string-contains? t1 ">You are on your own feet again.\n"))
(check-true (string-contains? t1 ">The boat deflates.\n>Taken.\n"))
(check-true (string-contains? t1 "Your score would be 40 [total of 500 points], in 58 moves."))
(check-equal? (remove-duplicates (hash-ref ref-checks 'prefix_files_changed)) '(("MDL/MADADV.SAVE")))

;; --- the scenario ------------------------------------------------------------------------
(run-m4-scenario "boat-river" commands
                 #:checkpoint boat-checkpoint
                 #:eof-classification-ignore-keys '(robber_hroom)
                 #:check-turn
                 (lambda (k transcript)
                   (when (>= k 50)
                     (check-true (string-contains? transcript ">The boat inflates and appears seaworthy.\n")))))
