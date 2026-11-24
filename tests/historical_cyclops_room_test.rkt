#lang racket/base
;; M4 S8 scenario "the cyclops and ABS" (tests/scenarios/cyclops-room.json;
;; issue #167). The faithful run.mud path, <FLOAD "77loadall.mud"> then SAVE-IT
;; through the host top-level loop, on the fixed session clock (fixed_epoch
;; 250776000, zone UTC; ADR-0052): take the lunch (FOOD) and the bottle of
;; water in the kitchen, the troll-combat path (the troll dies on the third
;; blow), the maze route into the Cyclops Room, where the demon FIGHTING
;; (78melee.mud:308-309) applies CYCLOPS (77act1.mud:934) with the FIRST? verb
;; and so evaluates <ABS .COUNT> (77act1.mud:951; the #167 failure). Then
;; feed the cyclops (RVARS -1), look (CYCLOPS-ROOM 77act1.mud:1031
;; <NTH ,CYCLOMAD <ABS .VARS>> with -1), take him (AOS-SOS 77act1.mud:1050 with
;; -2), give him the water (asleep, CYCLOPS-FLAG), take him asleep, look, wake
;; him (77act1.mud:949 stores <ABS -2> = 2 and sets FIGHTBIT; he attacks),
;; look ("standing in the corner": RVARS is now positive), flee west, diagnose,
;; inventory, score.
;;
;; Compared with the pinned Confusion pipe captures in
;; docs/evidence/M4/cyclops-room-reference.json (CYCLOPS-ROOM-REFERENCE.md) by
;; the shared runner tests/m4_scenario_runner.rkt (docs/TESTING.md, "M4
;; scenario runner"), byte for byte after D1 only (the LISTEN banner and the
;; "DONE" line), exactly like tests/historical_troll_combat_test.rkt:
;;   * single-run mode (default): one boot fed all 40 commands; at READSTRING
;;     entry k (k = 0..40) the output equals the native prefix-k stdout up to
;;     its prompt and the read-only checkpoints equal the reference diagnostic
;;     checkpoint k (READSTRING entry k in run X1); at end of input the whole
;;     output equals T1 and the state equals end checkpoint 40. Every
;;     prefix's end-of-input tail is standard, so no prefix is re-run;
;;   * per-prefix mode (M4_SCENARIO_MODE=per-prefix): for every prefix of k
;;     commands (k = 0..40; k = 40 is reference case T1, otherwise Pkk) the
;;     whole output equals the reference stdout and the state equals the
;;     reference END checkpoint k (the last checkpoint of the diagnostic run
;;     Dkk, X1 for k = 40, taken at the READSTRING that meets end of input);
;;   * checkpoint fields: HERE, the winner's AOBJS/ASTRENGTH/ASTAGGERED, the
;;     cyclops's OROOM/OCAPAC/SLEEPBIT/FIGHTBIT/STAGGERED, the Cyclops Room's
;;     RVARS, CYCLOPS-FLAG/MAGIC-FLAG/TROLL-FLAG, FOOD's and WATER's
;;     OROOM/OCAN, the bottle's OCONTENTS, <3 ,OPPV>, <3 ,VILLAIN-PROBS>,
;;     CURIN's CFLAG/CTICK, the sword's OTVAL, scores and MOVES;
;;   * RNG: the reference RANDOM draws are pinned below.
;;
;; Every run is guarded (no file write or delete, empty temporary cwd, game
;; directory hashes unchanged) and watchdogged (a timeout is a failure).
;; This is scenario evidence for M4, not a PLAYABLE or M4-gate claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_cyclops_room_test.rkt   (exit status is authoritative)
(require rackunit racket/list "m4_scenario_runner.rkt"
         (only-in "../mdl/loader.rkt" mdl-session-call mdl-session-global mdl-session-atom)
         (only-in "../mdl/runtime/core.rkt" mdl-truthy?))

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler (lambda (e) (raise e)))

(define commands '("north" "east" "open window" "west" "open sack" "take lunch" "take bottle"
                   "inventory" "west" "take sword" "take lamp" "move rug" "open trap door"
                   "turn on lamp" "down" "east" "kill troll with sword"
                   "kill troll with sword" "kill troll with sword" "south" "south" "east"
                   "up" "sw" "east" "south" "ne" "give lunch to cyclops" "look"
                   "take cyclops" "open bottle" "give water to cyclops" "take cyclops"
                   "look" "wake cyclops" "look" "west" "diagnose" "inventory" "score"))

;; --- scenario-specific reference checks -------------------------------------------
(define reference (m4-reference "cyclops-room"))
(define ref-checks (hash-ref reference 'checks))
(check-true (hash-ref ref-checks 'diag_prefix_game_parts_equal_prefix_game_parts))
(define diagnostic (hash-ref reference 'diagnostic))
(define ref-checkpoints (hash-ref diagnostic 'checkpoints))
(check-equal? (length ref-checkpoints) (+ 2 (length commands)))
(define ref-end-checkpoints (hash-ref reference 'end_checkpoints))
(check-equal? (length ref-end-checkpoints) (add1 (length commands)))
;; The end checkpoints (state after the end-of-input empty command) equal the
;; READSTRING-entry checkpoints for every k in this scenario, k = 0 included
;; (unlike troll-combat, SWORD-DEMON's HACTION is not a field here).
(for ([k (in-range 0 (add1 (length commands)))])
  (check-equal? (hash-remove (list-ref ref-end-checkpoints k) 'n)
                (hash-remove (list-ref ref-checkpoints k) 'n) (format "end ~a" k)))
;; The cyclops in the reference state, checkpoint by checkpoint (READSTRING
;; entry k = before command k+1): RVARS (the anger counter) 0 until `give
;; lunch to cyclops` (cp 28: <MIN -1 <- 0>> = -1), -2 after `take cyclops`
;; (AOS-SOS), unchanged while asleep (cp 32-34: SLEEPBIT, CYCLOPS-FLAG, the
;; water gone from the bottle), 2 after `wake cyclops` (cp 35: <ABS -2>,
;; FIGHTBIT, <3 ,OPPV> the cyclops), and still 2 after fleeing west (cp 37 on:
;; OPPV cleared, FIGHTBIT cleared). The cyclops never leaves its room and never
;; changes strength; MAGIC-FLAG stays FALSE.
(define (cyclops-row cp)
  (for/list ([key '(here cyclo_rvars cyclops_sleeping cyclops_fighting cyclops_flag
                    oppv_3 water_ocan bottle_ocontents food_ocan)])
    (hash-ref cp key)))
(define pre-cyclops '("#FALSE ()" "#FALSE ()" "#FALSE ()" "#FALSE ()"))
(check-equal? (map cyclops-row (drop ref-checkpoints 27))
              (list (append (list "CYCLO!-ROOMS" "0") pre-cyclops
                           '("BOTTL!-OBJECTS" "(WATER!-OBJECTS)" "#FALSE ()"))
                    (append (list "CYCLO!-ROOMS" "-1") pre-cyclops
                           '("BOTTL!-OBJECTS" "(WATER!-OBJECTS)" "#FALSE ()"))
                    (append (list "CYCLO!-ROOMS" "-1") pre-cyclops
                           '("BOTTL!-OBJECTS" "(WATER!-OBJECTS)" "#FALSE ()"))
                    (append (list "CYCLO!-ROOMS" "-2") pre-cyclops
                           '("BOTTL!-OBJECTS" "(WATER!-OBJECTS)" "#FALSE ()"))
                    (append (list "CYCLO!-ROOMS" "-2") pre-cyclops
                           '("BOTTL!-OBJECTS" "(WATER!-OBJECTS)" "#FALSE ()"))
                    '("CYCLO!-ROOMS" "-2" "T" "#FALSE ()" "T" "#FALSE ()" "#FALSE ()" "()" "#FALSE ()")
                    '("CYCLO!-ROOMS" "-2" "T" "#FALSE ()" "T" "#FALSE ()" "#FALSE ()" "()" "#FALSE ()")
                    '("CYCLO!-ROOMS" "-2" "T" "#FALSE ()" "T" "#FALSE ()" "#FALSE ()" "()" "#FALSE ()")
                    '("CYCLO!-ROOMS" "2" "#FALSE ()" "T" "#FALSE ()" "CYCLO!-OBJECTS" "#FALSE ()" "()" "#FALSE ()")
                    '("CYCLO!-ROOMS" "2" "#FALSE ()" "T" "#FALSE ()" "CYCLO!-OBJECTS" "#FALSE ()" "()" "#FALSE ()")
                    '("MAZ15!-ROOMS" "2" "#FALSE ()" "#FALSE ()" "#FALSE ()" "#FALSE ()" "#FALSE ()" "()" "#FALSE ()")
                    '("MAZ15!-ROOMS" "2" "#FALSE ()" "#FALSE ()" "#FALSE ()" "#FALSE ()" "#FALSE ()" "()" "#FALSE ()")
                    '("MAZ15!-ROOMS" "2" "#FALSE ()" "#FALSE ()" "#FALSE ()" "#FALSE ()" "#FALSE ()" "()" "#FALSE ()")
                    '("MAZ15!-ROOMS" "2" "#FALSE ()" "#FALSE ()" "#FALSE ()" "#FALSE ()" "#FALSE ()" "()" "#FALSE ()")
                    '("MAZ15!-ROOMS" "2" "#FALSE ()" "#FALSE ()" "#FALSE ()" "#FALSE ()" "#FALSE ()" "()" "#FALSE ()")))
(check-equal? (remove-duplicates
               (for/list ([cp ref-checkpoints])
                 (list (hash-ref cp 'cyclops_oroom) (hash-ref cp 'cyclops_ocapac)
                       (hash-ref cp 'cyclops_staggered) (hash-ref cp 'magic_flag)
                       (hash-ref cp 'villain_probs_3) (hash-ref cp 'winner_astrength)
                       (hash-ref cp 'curin_cflag))))
              '(("CYCLO!-ROOMS" "10000" "#FALSE ()" "#FALSE ()" "0" "0" "#FALSE ()")))
;; RANDOM: START's seeding call; the troll fight exactly as in the
;; troll-combat scenario (FIRST? entering the troll room, then 4 + 3 + 2
;; draws); one in the first `look` in the Cyclops Room; one in `take cyclops`
;; while he sleeps; one in the following `look`; three in `wake cyclops` and
;; four in the next `look` (the cyclops fights); one in `west`.
(check-equal? (for/list ([d (hash-ref diagnostic 'random_draws)])
                (list (hash-ref d 'args) (hash-ref d 'result) (hash-ref d 'before_checkpoint)))
              '(("(10438660480)" 16566282405 0) ("()" -21802663835 16)
                ("()" 12914488375 17) ("()" -6577089531 17) ("()" 34210328094 17)
                ("()" 3437552668 17) ("()" 13814526739 18) ("()" -20114144995 18)
                ("()" 11990399124 18) ("()" 31711279130 19) ("()" 25894896720 19)
                ("()" 24534915165 29) ("()" -5538612619 33) ("()" 19040958043 34)
                ("()" -20602270879 35) ("()" 4352946252 35) ("()" 19754489340 35)
                ("()" 17596141018 36) ("()" 27186759460 36) ("()" 18657501641 36)
                ("()" -2379718053 36) ("()" 23054062271 37)))

;; --- read-only checkpoints in our session ---------------------------------------
;; Rendered like the reference diagnostic's PRIN1 for the values that occur:
;; FIX, ATOM (pname; the reference trailers "!-OBLIST" are stripped from its
;; side), an empty FALSE and LISTs of OIDs. Anything else is a strict error.
(define (our-checkpoint s)
  (define here (mdl-session-global s "HERE"))
  (define winner (mdl-session-global s "WINNER"))
  (define sword (mdl-session-call s "FIND-OBJ" "SWORD"))
  (define cyc (mdl-session-call s "FIND-OBJ" "CYCLO"))
  (define food (mdl-session-call s "FIND-OBJ" "FOOD"))
  (define water (mdl-session-call s "FIND-OBJ" "WATER"))
  (define bottle (mdl-session-call s "FIND-OBJ" "BOTTL"))
  (define croom (mdl-session-call s "FIND-ROOM" "CYCLO"))
  (define curin (mdl-session-global s "CURIN"))
  (define oppv-3 (mdl-session-call s "NTH" (mdl-session-global s "OPPV") 3))
  (define (rid r) (render s (field s r "RID")))
  (define (oid o) (render s (field s o "OID")))
  (hasheq 'here (rid here)
          'aobjs (oids s (field s winner "AOBJS"))
          'winner_astrength (render s (field s winner "ASTRENGTH"))
          'winner_staggered (bit-set? s (field s winner "AFLAGS") "ASTAGGERED")
          'cyclops_oroom (or-false (field s cyc "OROOM") rid)
          'cyclops_ocapac (render s (field s cyc "OCAPAC"))
          'cyclops_sleeping (bit-set? s (field s cyc "OFLAGS") "SLEEPBIT")
          'cyclops_fighting (bit-set? s (field s cyc "OFLAGS") "FIGHTBIT")
          'cyclops_staggered (bit-set? s (field s cyc "OFLAGS") "STAGGERED")
          'cyclo_rvars (render s (field s croom "RVARS"))
          'cyclops_flag (render s (mdl-session-global s "CYCLOPS-FLAG!-FLAG"))
          'magic_flag (render s (mdl-session-global s "MAGIC-FLAG!-FLAG"))
          'troll_flag (render s (mdl-session-global s "TROLL-FLAG!-FLAG"))
          'food_oroom (or-false (field s food "OROOM") rid)
          'food_ocan (or-false (field s food "OCAN") oid)
          'water_oroom (or-false (field s water "OROOM") rid)
          'water_ocan (or-false (field s water "OCAN") oid)
          'bottle_ocontents (oids s (field s bottle "OCONTENTS"))
          'oppv_3 (or-false oppv-3 oid)
          'villain_probs_3 (render s (mdl-session-call s "NTH" (mdl-session-global s "VILLAIN-PROBS") 3))
          'curin_cflag (render s (field s curin "CFLAG"))
          'curin_ctick (render s (field s curin "CTICK"))
          'sword_otval (render s (field s sword "OTVAL"))
          'raw_score (render s (mdl-session-global s "RAW-SCORE"))
          'ascore (render s (field s winner "ASCORE"))
          'moves (render s (mdl-session-global s "MOVES"))))

;; === every turn / every prefix, k = 0 .. 40 ========================================
(run-m4-scenario "cyclops-room" commands #:checkpoint our-checkpoint)
