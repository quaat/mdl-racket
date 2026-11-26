#lang racket/base
;; M4 Phase 3c scenario "the coal-mine machine and the basket" (epic #163,
;; objects beyond the house; tests/scenarios/coal-machine.json). The faithful
;; run.mud path, <FLOAD "77loadall.mud"> then SAVE-IT through the host
;; top-level loop, on the fixed session clock (fixed_epoch 250776000, zone
;; UTC; ADR-0052), with the unmodified pinned sources and no RANDOM override.
;;
;; Commands 1-24 are dam-sluice's (troll-combat's sixteen, the Maintenance
;; Room at 23, `take wrench`). Then `take screwdriver`, `push yellow button`
;; (GATE-FLAG), back to the Dam, `turn bolt with wrench` (29: LOW-TIDE);
;; across the drained reservoir to Reservoir North (32), the Atlantis Room,
;; the Cave, Mirror Room 1 (35); `rub mirror` (36: Mirror Room 2); the
;; crawlway, the Grail Room, the Temple, the Altar; `take candles` (41: the
;; burning candles, CANDLES queues CNDIN 50); back to Mirror Room 2, `rub
;; mirror` (46); the corridor, the Slide Room, the Mine Entrance, the Shaft
;; Room (50). The puzzle (DUMBWAITER, MACHINE-FUNCTION, MSWITCH-FUNCTION,
;; NO-OBJS; 77act2.mud:74-185):
;;
;;   51-58 through the mine and down the ladder to the Dead End; 59 `take
;;     coal`; 60-65 back up to the Shaft Room;
;;   66-68 coal, screwdriver, candles put in the basket; 69 `lower basket`:
;;     CAGE-TOP false, TBASK at the Lower Shaft, FBASK at the top;
;;   70-77 through the mine again to the Timber Room; 78 `drop all`
;;     (EMPTY-HANDED T); 79 `sw` to the Lower Shaft, lit by the candles in the
;;     basket: LIGHT-SHAFT scored (RAW-SCORE 40 -> 50);
;;   80-82 coal, screwdriver, candles taken; 83 `east` (the Machine Room);
;;   84 `open lid`; 85 `put coal in machine`; 86 `close lid`; 87 `turn switch
;;     with screwdriver`: the coal spliced out, the diamond in (OCAN MACHI);
;;   88 `open lid`; 89 `take diamond` (RAW-SCORE 60); 90 `nw`; 91 `put
;;     diamond in basket`; 92 `raise basket`: CAGE-TOP T, TBASK at the top.
;;
;; Native quirks kept as they are (and matched): an object put in the basket
;; keeps the OROOM it had when put in (the coal and candles TSHAF after the
;; basket went down; the diamond BSHAF after it went up), and the coal spliced
;; out of the machine keeps OROOM/OCAN MACHI.
;;
;; The thief (ROBBER demon) takes the trident and the trunk from rooms the
;; hero has left and never meets the hero. Prefixes 36 and 38 (the sword's
;; glow), 53 and 61 (his bag at the end-of-input turn) are re-run;
;; robber_hroom is compared at every READSTRING entry, at the end and in
;; per-prefix mode, but not used to classify end-of-input tails
;; (#:eof-classification-ignore-keys, ADR-0062 amendment).
;;
;; Compared with the pinned Confusion captures in
;; docs/evidence/M4/coal-machine-reference.json (COAL-MACHINE-REFERENCE.md,
;; captured twice, byte-identical transcripts) through the shared runner
;; tests/m4_scenario_runner.rkt, byte for byte after D1 only. Scenario
;; evidence for M4, not a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_coal_machine_test.rkt   (exit status is authoritative)
(require rackunit racket/list racket/string "m4_scenario_runner.rkt" "m4_puzzles_checkpoint.rkt")

(current-check-handler (lambda (e) (raise e)))

(define to-shaft-room
  '("north" "east" "open window" "west" "west" "take sword" "inventory" "take lamp" "move rug"
    "open trap door" "turn on lamp" "down" "east"
    "kill troll with sword" "kill troll with sword" "kill troll with sword"
    "north" "north" "down" "up" "east" "north" "north"
    "take wrench" "take screwdriver" "push yellow button" "south" "south" "turn bolt with wrench"
    "south" "nw" "north" "north" "up" "north" "rub mirror" "north" "north" "up" "east"
    "take candles" "west" "west" "east" "sw" "rub mirror" "west" "west" "north" "ne"))
(define commands
  (append to-shaft-room
          '("north" "ne" "north" "ne" "nw" "down" "down" "ne" "take coal"
            "south" "up" "up" "east" "east" "south"
            "put coal in basket" "put screwdriver in basket" "put candles in basket" "lower basket"
            "north" "ne" "north" "ne" "nw" "down" "down" "south" "drop all" "sw"
            "take coal" "take screwdriver" "take candles" "east"
            "open lid" "put coal in machine" "close lid" "turn switch with screwdriver" "open lid"
            "take diamond" "nw" "put diamond in basket" "raise basket" "inventory" "score")))

;; --- reference-side checks (no game run) ------------------------------------------------
(define reference (m4-reference "coal-machine"))
(define ref-checks (hash-ref reference 'checks))
(define cps (hash-ref (hash-ref reference 'diagnostic) 'checkpoints))
(define (cp k key) (strip-trailers (hash-ref (list-ref cps k) key)))
(define t1 (hash-ref (hash-ref reference 'transcript) 'game_output_raw))
(check-equal? (hash-ref reference 'commands) commands)
(check-equal? (length commands) 94)
(check-equal? (take commands 24) (take (hash-ref (m4-reference "dam-sluice") 'commands) 24))
(check-equal? (remove-duplicates (hash-ref reference 'endings)) '("eof"))
;; the route's rooms
(check-equal? (for/list ([k '(23 29 32 35 36 40 46 50 58 65 77 79 83 90)]) (cp k 'here))
              '("MAINT" "DAM" "RESEN" "MIRR1" "MIRR2" "TEMP2" "MIRR1" "TSHAF" "DEAD7" "TSHAF"
                "TIMBE" "BSHAF" "MACHI" "BSHAF"))
(check-equal? (list (cp 28 'low_tide) (cp 29 'low_tide) (cp 26 'gate_flag)) '("#FALSE ()" "T" "T"))
;; the candles: burning from the altar on; CNDIN queued at `take candles`,
;; its first interval ends at entry 90 (the next one is 20)
(check-equal? (list (cp 40 'candl_oroom) (cp 40 'cndin_ctick) (cp 41 'aobjs) (cp 41 'cndin_ctick)
                    (cp 89 'cndin_ctick) (cp 90 'cndin_ctick))
              '("TEMP2" "0" "(CANDL SCREW WRENC LAMP SWORD)" "49" "1" "20"))
(check-equal? (remove-duplicates (for/list ([k (in-range 0 95)]) (cp k 'candl_olight))) '("1"))
;; the basket and the machine by READSTRING entry:
;; (HERE CAGE-TOP TBASK-OROOM TBASK-CONTENTS FBASK-OROOM COAL-OCAN MACHI-OOPEN
;;  MACHI-CONTENTS DIAMO-OCAN LIGHT-SHAFT EMPTY-HANDED RAW-SCORE)
(define (puz k) (map (lambda (key) (cp k key))
                     '(here cage_top tbask_oroom tbask_contents fbask_oroom coal_ocan machi_oopen
                       machi_contents diamo_ocan light_shaft empty_handed raw_score)))
(check-equal?
 (for/list ([k '(59 65 66 67 68 69 77 78 79 80 82 83 84 85 86 87 88 89 91 92 94)]) (cons k (puz k)))
 '((59 "DEAD7" "T" "TSHAF" "()" "BSHAF" "#FALSE ()" "#FALSE ()" "()" "#FALSE ()" "10" "#FALSE ()" "40")
   (65 "TSHAF" "T" "TSHAF" "()" "BSHAF" "#FALSE ()" "#FALSE ()" "()" "#FALSE ()" "10" "#FALSE ()" "40")
   (66 "TSHAF" "T" "TSHAF" "(COAL)" "BSHAF" "TBASK" "#FALSE ()" "()" "#FALSE ()" "10" "#FALSE ()" "40")
   (67 "TSHAF" "T" "TSHAF" "(SCREW COAL)" "BSHAF" "TBASK" "#FALSE ()" "()" "#FALSE ()" "10" "#FALSE ()" "40")
   (68 "TSHAF" "T" "TSHAF" "(CANDL SCREW COAL)" "BSHAF" "TBASK" "#FALSE ()" "()" "#FALSE ()" "10" "#FALSE ()" "40")
   (69 "TSHAF" "#FALSE ()" "BSHAF" "(CANDL SCREW COAL)" "TSHAF" "TBASK" "#FALSE ()" "()" "#FALSE ()" "10" "#FALSE ()" "40")
   (77 "TIMBE" "#FALSE ()" "BSHAF" "(CANDL SCREW COAL)" "TSHAF" "TBASK" "#FALSE ()" "()" "#FALSE ()" "10" "#FALSE ()" "40")
   (78 "TIMBE" "#FALSE ()" "BSHAF" "(CANDL SCREW COAL)" "TSHAF" "TBASK" "#FALSE ()" "()" "#FALSE ()" "10" "T" "40")
   (79 "BSHAF" "#FALSE ()" "BSHAF" "(CANDL SCREW COAL)" "TSHAF" "TBASK" "#FALSE ()" "()" "#FALSE ()" "0" "T" "50")
   (80 "BSHAF" "#FALSE ()" "BSHAF" "(CANDL SCREW)" "TSHAF" "#FALSE ()" "#FALSE ()" "()" "#FALSE ()" "0" "#FALSE ()" "50")
   (82 "BSHAF" "#FALSE ()" "BSHAF" "()" "TSHAF" "#FALSE ()" "#FALSE ()" "()" "#FALSE ()" "0" "#FALSE ()" "50")
   (83 "MACHI" "#FALSE ()" "BSHAF" "()" "TSHAF" "#FALSE ()" "#FALSE ()" "()" "#FALSE ()" "0" "#FALSE ()" "50")
   (84 "MACHI" "#FALSE ()" "BSHAF" "()" "TSHAF" "#FALSE ()" "T" "()" "#FALSE ()" "0" "#FALSE ()" "50")
   (85 "MACHI" "#FALSE ()" "BSHAF" "()" "TSHAF" "MACHI" "T" "(COAL)" "#FALSE ()" "0" "#FALSE ()" "50")
   (86 "MACHI" "#FALSE ()" "BSHAF" "()" "TSHAF" "MACHI" "#FALSE ()" "(COAL)" "#FALSE ()" "0" "#FALSE ()" "50")
   (87 "MACHI" "#FALSE ()" "BSHAF" "()" "TSHAF" "MACHI" "#FALSE ()" "(DIAMO)" "MACHI" "0" "#FALSE ()" "50")
   (88 "MACHI" "#FALSE ()" "BSHAF" "()" "TSHAF" "MACHI" "T" "(DIAMO)" "MACHI" "0" "#FALSE ()" "50")
   (89 "MACHI" "#FALSE ()" "BSHAF" "()" "TSHAF" "MACHI" "T" "()" "#FALSE ()" "0" "#FALSE ()" "60")
   (91 "BSHAF" "#FALSE ()" "BSHAF" "(DIAMO)" "TSHAF" "MACHI" "T" "()" "TBASK" "0" "#FALSE ()" "60")
   (92 "BSHAF" "T" "TSHAF" "(DIAMO)" "BSHAF" "MACHI" "T" "()" "TBASK" "0" "#FALSE ()" "60")
   (94 "BSHAF" "T" "TSHAF" "(DIAMO)" "BSHAF" "MACHI" "T" "()" "TBASK" "0" "#FALSE ()" "60")))
(check-equal? (list (cp 89 'aobjs) (cp 94 'aobjs) (cp 78 'lamp_oroom)) '("(DIAMO CANDL SCREW)" "(CANDL SCREW)" "TIMBE"))
;; the thief: takes the trident and the trunk, never in the hero's room
(check-equal? (remove-duplicates (for/list ([k (in-range 0 95)]) (cp k 'robber_hobjs)))
              '("()" "(TRIDE)" "(TRUNK TRIDE)"))
(check-equal? (remove-duplicates (for/list ([k (in-range 0 95)]) (cp k 'thief_oroom))) '("#FALSE ()"))
;; shorter prefixes: non-standard only through the thief (and HROOM)
(define ends (hash-ref reference 'end_checkpoints))
(check-equal? (remove-duplicates
               (for/list ([k (in-range 0 94)])
                 (sort (for/list ([(key v) (in-hash (list-ref cps k))]
                                  #:unless (eq? key 'n)
                                  #:unless (equal? v (hash-ref (list-ref ends k) key)))
                         key)
                       symbol<?)))
              '(() (robber_hroom) (robber_hobjs robber_hroom) (robber_hobjs robber_hroom trunk_oroom)))
(check-true (string-contains? t1 ">The basket is lowered to the bottom of the shaft.\n"))
(check-true (string-contains? t1 "At the end of the chain is a basket.\nThe basket contains:\n A pair of candles\n A screwdriver\n A small pile of coal\n>"))
(check-true (string-contains? t1 "The machine comes to life (figuratively) with a dazzling display of"))
(check-true (string-contains? t1 ">The basket is raised to the top of the shaft.\n"))
(check-true (string-contains? t1 "Your score would be 60 [total of 500 points], in 94 moves."))
(check-equal? (remove-duplicates (hash-ref ref-checks 'prefix_files_changed)) '(("MDL/MADADV.SAVE")))

;; --- the scenario ------------------------------------------------------------------------
(run-m4-scenario "coal-machine" commands
                 #:checkpoint puzzles-checkpoint
                 #:eof-classification-ignore-keys '(robber_hroom)
                 #:check-turn
                 (lambda (k transcript)
                   (when (>= k 88)
                     (check-true (string-contains? transcript "The machine comes to life (figuratively)")))))
