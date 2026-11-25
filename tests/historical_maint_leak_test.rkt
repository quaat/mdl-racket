#lang racket/base
;; M4 S14 scenario "the Maintenance Room leak" (epic #163, timers: the clock
;; event MNTIN; tests/scenarios/maint-leak.json; issue #193, INV-11 fixed).
;; The faithful run.mud path, <FLOAD "77loadall.mud"> then SAVE-IT through
;; the host top-level loop, on the fixed session clock (fixed_epoch
;; 250776000, zone UTC; ADR-0052), with the unmodified pinned sources and no
;; RANDOM override. troll-combat's first sixteen commands, then north, north,
;; down, up, east (the Dam), north (the Dam Lobby), north (the Maintenance
;; Room, command 23; MAINT-ROOM's attached #DECL declares PRSO as the
;; undefined type PRSOBJ, not enforced under the #98 ADR amendment, #193).
;;
;;   24 `push blue button`: the leak; MAINT-ROOM queues MNTIN with CTICK -1
;;     (<CLOCK-INT ,MNTIN -1>: fires on every CLOCK-DEMON pass), RVARS 2;
;;   25-28: one water level per turn (RVARS 3-6), printed in the room;
;;   29 `wait`: five passes (RVARS 6 -> 11);
;;   30 `plug leak with putty`: "By some miracle of elven technology, you
;;     have managed to stop the leak in the dam." (RVARS -1, MNTIN CTICK 0);
;;   31 `wait`: no level text; 33 `push blue button`: jammed.
;;
;; robber_hroom is compared at every entry, at the end and in per-prefix
;; mode, but not used to classify end-of-input tails
;; (#:eof-classification-ignore-keys, ADR-0062 amendment). The thief never
;; meets the hero.
;;
;; Compared with the pinned Confusion captures in
;; docs/evidence/M4/maint-leak-reference.json (DAM-CLOCKS.md, captured twice,
;; byte-identical transcripts) through the shared runner
;; tests/m4_scenario_runner.rkt, byte for byte after D1 only. Scenario
;; evidence for M4, not a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_maint_leak_test.rkt   (exit status is authoritative)
(require rackunit racket/list racket/string "m4_scenario_runner.rkt" "m4_dam_checkpoint.rkt")

(current-check-handler (lambda (e) (raise e)))

(define commands
  '("north" "east" "open window" "west" "west" "take sword" "inventory" "take lamp" "move rug"
    "open trap door" "turn on lamp" "down" "east"
    "kill troll with sword" "kill troll with sword" "kill troll with sword"
    "north" "north" "down" "up" "east" "north" "north"
    "push blue button" "look" "take tube" "open tube" "take putty" "wait"
    "plug leak with putty" "wait" "look" "push blue button" "south" "score"))
(define stopped "you have managed to stop the\r\nleak in the dam.\n")

;; --- reference-side checks (no game run; moved from the retired XFAIL test) --------------
(define reference (m4-reference "maint-leak"))
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
;; The leak (24) queues MNTIN with CTICK -1; RVARS rises once per pass (five
;; passes during `wait`); the putty (30) sets RVARS -1 and MNTIN's CTICK 0.
(check-equal? (for/list ([k (in-range 23 36)]) (list k (cp k 'maint_rvars) (cp k 'mntin_ctick)))
              '((23 "0" "0") (24 "2" "-1") (25 "3" "-1") (26 "4" "-1") (27 "5" "-1") (28 "6" "-1")
                (29 "11" "-1") (30 "-1" "0") (31 "-1" "0") (32 "-1" "0") (33 "-1" "0") (34 "-1" "0")
                (35 "-1" "0")))
(check-equal? (cp 24 'clock_events) "((MNTIN T -1) (CURIN #FALSE () 0) (LNTIN T 336))")
(check-equal? (remove-duplicates (for/list ([k (in-range 0 37)]) (cp k 'maint_munged))) '("#FALSE ()"))
(check-equal? (length (regexp-match* #rx"The water level here is now " t1)) 10)
(check-true (string-contains? t1 (string-append stopped ">Time passes...\n>")))

;; --- the scenario ------------------------------------------------------------------------
(run-m4-scenario "maint-leak" commands
                 #:checkpoint dam-checkpoint
                 #:eof-classification-ignore-keys '(robber_hroom)
                 #:check-turn
                 (lambda (k transcript)
                   (when (>= k 25)
                     (check-true (string-contains? transcript "The water level here is now up to your shin.\n")))
                   (when (>= k 31)
                     (check-true (string-contains? transcript stopped)))))
