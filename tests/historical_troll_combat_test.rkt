#lang racket/base
;; M4 S6 scenario "fight the troll" (tests/scenarios/troll-combat.json). The
;; faithful run.mud path, <FLOAD "77loadall.mud"> then SAVE-IT through the host
;; top-level loop, on the fixed session clock (fixed_epoch 250776000, zone UTC;
;; ADR-0052): the sword-glow path into the troll room, `kill troll with sword`
;; three times (KILLER 77act1.mud:1699 -> BLOW 78melee.mud:377 for the hero;
;; the demon FIGHTING 78melee.mud:282 -> BLOW for the troll's counterattack;
;; TROLL 77act1.mud:360 for FIGHT!/DEAD!; PRES 78melee.mud:351 picks remarks
;; with RANDOM; MAX in the wound arithmetic 78melee.mud:447), which under the
;; fixed clock and seed pinks the troll, knocks his axe to the floor (he
;; recovers it), then kills him; then `diagnose`, `score`, `inventory`, `look`,
;; `take axe` (gone with the troll) and `east`.
;;
;; Compared with the pinned Confusion pipe captures in
;; docs/evidence/M4/troll-combat-reference.json (TROLL-COMBAT-REFERENCE.md) by
;; the shared runner tests/m4_scenario_runner.rkt (docs/TESTING.md, "M4
;; scenario runner"), byte for byte after D1 only (the LISTEN banner and the
;; "DONE" line), exactly like tests/historical_sword_glow_test.rkt:
;;   * single-run mode (default): one boot fed all 22 commands; at READSTRING
;;     entry k (k = 0..22) the output equals the native prefix-k stdout up to
;;     its prompt and the read-only checkpoints equal the reference diagnostic
;;     checkpoint k (READSTRING entry k in run X1); at end of input the whole
;;     output equals T1 and the state equals end checkpoint 22. Prefix 0 is
;;     re-run per prefix (its end checkpoint differs, see below);
;;   * per-prefix mode (M4_SCENARIO_MODE=per-prefix): for every prefix of k
;;     commands (k = 0..22; k = 22 is reference case T1, otherwise Pkk) the
;;     whole output equals the reference stdout and the state equals the
;;     reference END checkpoint k: the last checkpoint of the reference
;;     diagnostic run Dkk (X1 for k = 22), taken at the READSTRING that meets
;;     end of input, i.e. after the empty command ("Beg pardon?") that end of
;;     input produces in both engines, which still runs the demons (Dkk game
;;     text verified equal to Pkk, X1 to T1);
;;   * checkpoint fields: HERE, the winner's AOBJS/ASTRENGTH/ASTAGGERED, the
;;     troll's OROOM/OCAPAC/OCONTENTS/FIGHTBIT/STAGGERED, the axe's
;;     OROOM/OCAN, TROLL-FLAG!-FLAG, <1 ,OPPV>, <1 ,VILLAIN-PROBS>, CURIN's
;;     CFLAG/CTICK, the sword's OTVAL, SWORD-DEMON's HACTION, scores and MOVES.
;;
;; Every run is guarded (no file write or delete, empty temporary cwd, game
;; directory hashes unchanged) and watchdogged (a timeout is a failure).
;; This is scenario evidence for M4, not a PLAYABLE or M4-gate claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_troll_combat_test.rkt   (exit status is authoritative)
(require rackunit racket/list "m4_scenario_runner.rkt"
         (only-in "../mdl/loader.rkt" mdl-session-call mdl-session-global mdl-session-atom)
         (only-in "../mdl/runtime/core.rkt" mdl-truthy?))

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler (lambda (e) (raise e)))

(define commands '("north" "east" "open window" "west" "west" "take sword" "inventory"
                   "take lamp" "move rug" "open trap door" "turn on lamp" "down" "east"
                   "kill troll with sword" "kill troll with sword" "kill troll with sword"
                   "diagnose" "score" "inventory" "look" "take axe" "east"))

;; --- scenario-specific reference checks -------------------------------------------
(define reference (m4-reference "troll-combat"))
(define ref-checks (hash-ref reference 'checks))
(check-true (hash-ref ref-checks 'diag_prefix_game_parts_equal_prefix_game_parts))
(define diagnostic (hash-ref reference 'diagnostic))
(define ref-checkpoints (hash-ref diagnostic 'checkpoints))
(check-equal? (length ref-checkpoints) (+ 2 (length commands)))
(define ref-end-checkpoints (hash-ref reference 'end_checkpoints))
(check-equal? (length ref-end-checkpoints) (add1 (length commands)))
;; The end checkpoints (state after the end-of-input empty command) equal the
;; READSTRING-entry checkpoints, except after prefix 0: there the empty
;; command is the first turn, whose sword demon run disarms SWORD-DEMON (the
;; sword is not carried), exactly as `north` does in checkpoint 1.
(for ([k (in-range 1 (add1 (length commands)))])
  (check-equal? (hash-remove (list-ref ref-end-checkpoints k) 'n)
                (hash-remove (list-ref ref-checkpoints k) 'n) (format "end ~a" k)))
(check-equal? (hash-ref (list-ref ref-end-checkpoints 0) 'sword_demon_haction) "#FALSE ()")
;; The fight in the reference state: the troll's strength (OCAPAC) 2 until
;; the first attack, 1 after the light wound (MAX 0 <- 2 1>), 0 after the
;; third (dead: removed from the room, TROLL-FLAG set, FIGHTBIT cleared);
;; the axe stays in (or returns to) the troll's OCONTENTS throughout; the
;; hero is never wounded (ASTRENGTH 0, CURIN never enabled); the glow level
;; drops to 0 once the troll is gone.
(check-equal? (for/list ([cp ref-checkpoints])
                (list (hash-ref cp 'troll_ocapac) (hash-ref cp 'troll_fighting)
                      (hash-ref cp 'troll_oroom) (hash-ref cp 'troll_flag)
                      (hash-ref cp 'sword_otval)))
              (append (make-list 12 '("2" "#FALSE ()" "MTROL!-ROOMS" "#FALSE ()" "0"))
                      '(("2" "#FALSE ()" "MTROL!-ROOMS" "#FALSE ()" "1")
                        ("2" "#FALSE ()" "MTROL!-ROOMS" "#FALSE ()" "2")
                        ("1" "T" "MTROL!-ROOMS" "#FALSE ()" "2")
                        ("1" "T" "MTROL!-ROOMS" "#FALSE ()" "2"))
                      (make-list 8 '("0" "#FALSE ()" "#FALSE ()" "T" "0"))))
(check-equal? (remove-duplicates
               (for/list ([cp ref-checkpoints])
                 (list (hash-ref cp 'troll_ocontents) (hash-ref cp 'axe_ocan)
                       (hash-ref cp 'axe_oroom) (hash-ref cp 'winner_astrength)
                       (hash-ref cp 'winner_staggered) (hash-ref cp 'curin_cflag))))
              '(("(AXE!-OBJECTS)" "TROLL!-OBJECTS" "#FALSE ()" "0" "#FALSE ()" "#FALSE ()")))
;; RANDOM: START's seeding call; FIGHTING's FIRST? test entering the troll
;; room; four draws in the first attack (BLOW and PRES for each side), three
;; in the second, two in the third, one in `look`.
(check-equal? (for/list ([d (hash-ref diagnostic 'random_draws)])
                (list (hash-ref d 'args) (hash-ref d 'result) (hash-ref d 'before_checkpoint)))
              '(("(10438660480)" 16566282405 0) ("()" -21802663835 13)
                ("()" 12914488375 14) ("()" -6577089531 14) ("()" 34210328094 14)
                ("()" 3437552668 14) ("()" 13814526739 15) ("()" -20114144995 15)
                ("()" 11990399124 15) ("()" 31711279130 16) ("()" 25894896720 16)
                ("()" 24534915165 20)))

;; --- read-only checkpoints in our session ---------------------------------------
;; Rendered like the reference diagnostic's PRIN1 for the values that occur:
;; FIX, ATOM (pname; the reference trailers "!-OBLIST" are stripped from its
;; side), an empty FALSE and LISTs of OIDs. Anything else is a strict error.
(define (our-checkpoint s)
  (define here (mdl-session-global s "HERE"))
  (define winner (mdl-session-global s "WINNER"))
  (define sword (mdl-session-call s "FIND-OBJ" "SWORD"))
  (define troll (mdl-session-call s "FIND-OBJ" "TROLL"))
  (define axe (mdl-session-call s "FIND-OBJ" "AXE"))
  (define demon (mdl-session-global s "SWORD-DEMON"))
  (define curin (mdl-session-global s "CURIN"))
  (define oppv-1 (mdl-session-call s "NTH" (mdl-session-global s "OPPV") 1))
  (define (rid r) (render s (field s r "RID")))
  (define (oid o) (render s (field s o "OID")))
  (hasheq 'here (rid here)
          'aobjs (oids s (field s winner "AOBJS"))
          'winner_astrength (render s (field s winner "ASTRENGTH"))
          'winner_staggered (bit-set? s (field s winner "AFLAGS") "ASTAGGERED")
          'troll_oroom (or-false (field s troll "OROOM") rid)
          'troll_ocapac (render s (field s troll "OCAPAC"))
          'troll_ocontents (oids s (field s troll "OCONTENTS"))
          'troll_fighting (bit-set? s (field s troll "OFLAGS") "FIGHTBIT")
          'troll_staggered (bit-set? s (field s troll "OFLAGS") "STAGGERED")
          'axe_oroom (or-false (field s axe "OROOM") rid)
          'axe_ocan (or-false (field s axe "OCAN") oid)
          'troll_flag (render s (mdl-session-global s "TROLL-FLAG!-FLAG"))
          'oppv_1 (or-false oppv-1 oid)
          'villain_probs_1 (render s (mdl-session-call s "NTH" (mdl-session-global s "VILLAIN-PROBS") 1))
          'curin_cflag (render s (field s curin "CFLAG"))
          'curin_ctick (render s (field s curin "CTICK"))
          'sword_otval (render s (field s sword "OTVAL"))
          'sword_demon_haction (render s (field s demon "HACTION"))
          'raw_score (render s (mdl-session-global s "RAW-SCORE"))
          'ascore (render s (field s winner "ASCORE"))
          'moves (render s (mdl-session-global s "MOVES"))))

;; === every turn / every prefix, k = 0 .. 22 ========================================
(run-m4-scenario "troll-combat" commands #:checkpoint our-checkpoint)
