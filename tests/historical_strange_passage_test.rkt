#lang racket/base
;; M4 S9 scenario "the Strange Passage and C-INT" (tests/scenarios/
;; strange-passage.json; issue #170 TIME). The faithful run.mud path, <FLOAD
;; "77loadall.mud"> then SAVE-IT through the host top-level loop, on the fixed
;; session clock (fixed_epoch 250776000, zone UTC; ADR-0052): the troll-combat
;; path and the maze into the Cyclops Room (the cyclops-room route without the
;; kitchen), `odysseus` (SINBAD 77act1.mud:1190: the cyclops flees north),
;; `north` into BLROO whose room action is the ATOM TIME (77dung.mud:1385;
;; ROOM-INFO 77rooms.mud:553-555 applies <GVAL TIME> on entry, RDCOM :634 after
;; each successful command there), `c-int` (verb function TIME,
;; 77dung.mud:2904: "Nothing happens."), `look`, `east` into the living room,
;; `c-int` again, `score`.
;;
;; Compared with the pinned Confusion pipe captures in
;; docs/evidence/M4/strange-passage-reference.json
;; (STRANGE-PASSAGE-REFERENCE.md) by the shared driver
;; tests/m4_p0prims_scenario.rkt: every prefix's transcript byte for byte (D1
;; only) and its end checkpoint. TIME's value is not printed by the game (it is
;; only tested for truth), so the deterministic TIME deviation (decision #170)
;; is invisible here, as natively. Scenario evidence for M4, not a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_strange_passage_test.rkt   (exit status is authoritative)
(require rackunit racket/string racket/list "m4_p0prims_scenario.rkt")

(current-check-handler (lambda (e) (raise e)))

(define commands
  '("north" "east" "open window" "west" "west" "take sword" "inventory" "take lamp"
    "move rug" "open trap door" "turn on lamp" "down" "east" "kill troll with sword"
    "kill troll with sword" "kill troll with sword" "south" "south" "east" "up" "sw"
    "east" "south" "ne" "odysseus" "north" "c-int" "look" "east" "c-int" "score"))

(run-p0prims-scenario
 "strange-passage" commands
 (lambda (reference)
   (define split (hash-ref (hash-ref (hash-ref reference 'transcript) 'split) 'commands))
   (define (response i) (hash-ref (list-ref split i) 'output))
   (check-true (string-prefix? (response 24) "The cyclops, hearing the name of his deadly nemesis, flees"))
   (check-true (string-prefix? (response 25) "You are in a long passage."))
   (check-equal? (response 26) "Nothing happens.\n")
   (check-equal? (response 29) "Nothing happens.\n")
   (define cps (hash-ref reference 'end_checkpoints))
   (check-equal? (hash-ref (list-ref cps 26) 'here) "BLROO!-ROOMS")
   (check-equal? (hash-ref (list-ref cps 26) 'magic_flag) "T")
   (check-equal? (hash-ref (list-ref cps 29) 'here) "LROOM!-ROOMS")))
