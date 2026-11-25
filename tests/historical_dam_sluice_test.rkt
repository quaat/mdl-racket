#lang racket/base
;; M4 S14 scenario "the dam's sluice gates" (epic #163, objects beyond the
;; house; tests/scenarios/dam-sluice.json; issue #193, INV-11 fixed). The
;; faithful run.mud path, <FLOAD "77loadall.mud"> then SAVE-IT through the
;; host top-level loop, on the fixed session clock (fixed_epoch 250776000,
;; zone UTC; ADR-0052), with the unmodified pinned sources and no RANDOM
;; override. troll-combat's first sixteen commands (the sword kills the troll
;; at the third blow), then north, north, down, up, east (the Dam), north (the
;; Dam Lobby), north (the Maintenance Room, command 23). Entering the room
;; applies MAINT-ROOM (77act1.mud:737), whose attached #DECL declares PRSO as
;; the type PRSOBJ, defined in no 1977 source file: under the #98 ADR
;; amendment (#193) a still-undefined attached TYPE name is not enforced, as
;; in pinned Confusion, so play goes on. Then: `take wrench`; back to the Dam;
;; `turn bolt with wrench` refused (27: GATE-FLAG unset); back; `push yellow
;; button` (30: "Click.", GATE-FLAG T); back; `look` (33: "The green bubble
;; is glowing."); `turn bolt with wrench` (34: the sluice gates open,
;; LOW-TIDE T, the trunk visible); `look`; `south` `nw` (the drained
;; reservoir); `look`; `take trunk` (39: RAW-SCORE 40 -> 55); `north` (40:
;; across the reservoir bed to Reservoir North); `score`.
;;
;; The ROBBER demon moves the thief (HROOM) on every turn, the end-of-input
;; turn included; robber_hroom is compared at every entry, at the end and in
;; per-prefix mode, but not used to classify end-of-input tails
;; (#:eof-classification-ignore-keys, ADR-0062 amendment). The thief never
;; meets the hero.
;;
;; Compared with the pinned Confusion captures in
;; docs/evidence/M4/dam-sluice-reference.json (DAM-CLOCKS.md, captured twice,
;; byte-identical transcripts) through the shared runner
;; tests/m4_scenario_runner.rkt, byte for byte after D1 only. Scenario
;; evidence for M4, not a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_dam_sluice_test.rkt   (exit status is authoritative)
(require rackunit racket/list racket/string "m4_scenario_runner.rkt" "m4_dam_checkpoint.rkt")

(current-check-handler (lambda (e) (raise e)))

(define commands
  '("north" "east" "open window" "west" "west" "take sword" "inventory" "take lamp" "move rug"
    "open trap door" "turn on lamp" "down" "east"
    "kill troll with sword" "kill troll with sword" "kill troll with sword"
    "north" "north" "down" "up" "east" "north" "north"
    "take wrench" "south" "south" "turn bolt with wrench"
    "north" "north" "push yellow button" "south" "south" "look" "turn bolt with wrench" "look"
    "south" "nw" "look" "take trunk" "north" "score"))

;; --- reference-side checks (no game run; moved from the retired XFAIL test) --------------
(define reference (m4-reference "dam-sluice"))
(define cps (hash-ref (hash-ref reference 'diagnostic) 'checkpoints))
(define (cp k key) (strip-trailers (hash-ref (list-ref cps k) key)))
(define t1 (hash-ref (hash-ref reference 'transcript) 'game_output_raw))
(check-equal? (hash-ref reference 'commands) commands)
(check-equal? (remove-duplicates (hash-ref reference 'endings)) '("eof"))
(check-equal? (cp 23 'here) "MAINT")
;; the thief never meets the hero
(check-equal? (remove-duplicates (for/list ([k (in-range (length cps))])
                                   (list (cp k 'thief_oroom) (cp k 'robber_hobjs))))
              '(("#FALSE ()" "()")))
;; refused bolt (27), yellow button (30), gates open (34), the trunk taken from
;; the drained reservoir (39), across it to Reservoir North (40).
(check-equal? (for/list ([k '(26 27 30 33 34 39 40)])
                (list k (cp k 'here) (cp k 'gate_flag) (cp k 'low_tide) (cp k 'trunk_visible) (cp k 'raw_score)))
              '((26 "DAM" "#FALSE ()" "#FALSE ()" "#FALSE ()" "40")
                (27 "DAM" "#FALSE ()" "#FALSE ()" "#FALSE ()" "40")
                (30 "MAINT" "T" "#FALSE ()" "#FALSE ()" "40")
                (33 "DAM" "T" "#FALSE ()" "#FALSE ()" "40")
                (34 "DAM" "T" "T" "T" "40")
                (39 "RESES" "T" "T" "T" "55")
                (40 "RESEN" "T" "T" "T" "55")))
(check-true (string-contains? t1 ">The bolt won't turn with your best effort.\n>"))
(check-true (string-contains? t1 "The green bubble is glowing.\n>The sluice gates open and water pours through the dam.\n>"))

;; --- the scenario ------------------------------------------------------------------------
(run-m4-scenario "dam-sluice" commands
                 #:checkpoint dam-checkpoint
                 #:eof-classification-ignore-keys '(robber_hroom)
                 #:check-turn
                 (lambda (k transcript)
                   ;; past the Maintenance Room entry (MAINT-ROOM's PRSOBJ #DECL)
                   (when (>= k 24)
                     (check-true (string-contains? transcript "There is a screwdriver here.\n>")))
                   (when (>= k 35)
                     (check-true (string-contains? transcript "The sluice gates open and water pours through the dam.\n>")))))
