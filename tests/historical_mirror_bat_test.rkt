#lang racket/base
;; M4 S9 scenario "the mirror and the bat" (tests/scenarios/mirror-bat.json;
;; issues #168 IMAGE, #169 SLEEP). The faithful run.mud path, <FLOAD
;; "77loadall.mud"> then SAVE-IT through the host top-level loop, on the fixed
;; session clock (fixed_epoch 250776000, zone UTC; ADR-0052): the troll-combat
;; path, the round room (RANDOM lands the listed detours in the Grail Room),
;; `rub mirror`, the coal mine entrance, the Squeaky Room, then `west` into the
;; Bat Room without garlic: BATS-ROOM (77act2.mud:25) -> FLY-ME (:38) ->
;; <FWEEP 4 1> (:43) evaluates <IMAGE 7> (:57) and <SLEEP 1> (:58) three times;
;; the bat drops the player in a RANDOM mine room; `look`.
;;
;; Compared with the pinned Confusion pipe captures in
;; docs/evidence/M4/mirror-bat-reference.json (MIRROR-BAT-REFERENCE.md) by the
;; shared driver tests/m4_p0prims_scenario.rkt: every prefix's transcript byte
;; for byte (D1 only; the three BEL bytes included), its end checkpoint, and
;; that SLEEP never calls the host sleeper under the fixed (non-live) clock.
;; Natively the full run takes about 3.25 s (three real one-second SLEEPs);
;; here it does not wait. Scenario evidence for M4, not a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_mirror_bat_test.rkt   (exit status is authoritative)
(require rackunit racket/string racket/list "m4_p0prims_scenario.rkt")

(current-check-handler (lambda (e) (raise e)))

(define commands
  '("north" "east" "open window" "west" "west" "take sword" "inventory" "take lamp"
    "move rug" "open trap door" "turn on lamp" "down" "east" "kill troll with sword"
    "kill troll with sword" "kill troll with sword" "north" "east" "se" "south" "se"
    "east" "se" "south" "se" "south" "look" "se" "east" "sw" "rub mirror" "west" "west"
    "north" "nw" "west" "look"))
(define bat-entry 36) ; prefixes with at least 36 commands have entered the Bat Room
(define bat-text "\a\a\aA deranged giant vampire bat (a reject from WUMPUS) swoops down\r\nfrom his belfry and lifts you away....\n")

(define (bel-count s) (for/sum ([c (in-string s)]) (if (char=? c #\u7) 1 0)))

(run-p0prims-scenario
 "mirror-bat" commands
 (lambda (reference)
   (define checks (hash-ref reference 'checks))
   ;; Natively: three BEL bytes, three real one-second waits.
   (check-equal? (hash-ref checks 't1_bel_bytes) 3)
   (check-true (>= (hash-ref checks 't1_elapsed_seconds) 3.0))
   (check-true (>= (hash-ref checks 't1b_elapsed_seconds) 3.0))
   (define game (hash-ref (hash-ref reference 'transcript) 'game_output_raw))
   (check-true (string-contains? game (string-append "There is an exquisite jade figurine here.\n" bat-text
                                                     "You are in a non-descript part of a coal mine.\n>")))
   ;; The bat's drop room (BAT-DROPS via PICK-ONE: one RANDOM draw before end
   ;; checkpoint 36) and the room the player ends in.
   (define cps (hash-ref reference 'end_checkpoints))
   (check-equal? (hash-ref (list-ref cps 35) 'here) "SQUEE!-ROOMS")
   (check-equal? (hash-ref (list-ref cps 36) 'here) "MINE2!-ROOMS")
   (check-equal? (length (hash-ref (hash-ref reference 'diagnostic) 'random_draws)) 28))
 #:check-prefix
 (lambda (k raw session)
   (check-equal? (bel-count raw) (if (>= k bat-entry) 3 0) (format "BELs at prefix ~a" k))
   (when (>= k bat-entry)
     (check-true (string-contains? raw bat-text) (format "bat text at prefix ~a" k)))))
