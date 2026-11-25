#lang racket/base
;; M4 Phase 3b scenario "the match clock" (epic #163, timers: a clock event
;; beyond the lamp and cure clocks; tests/scenarios/match-clock.json). The
;; faithful run.mud path, <FLOAD "77loadall.mud"> then SAVE-IT through the
;; host top-level loop, on the fixed session clock (fixed_epoch 250776000,
;; zone UTC; ADR-0052), with the unmodified pinned sources and no RANDOM
;; override. troll-combat's first sixteen commands (the sword kills the troll
;; at the third blow), then north, north, down (Reservoir South), up (Deep
;; Canyon), east (the Dam), north (the Dam Lobby), `take match` (the
;; matchbook, ORAND 5, 77dung.mud:2392). MATCH-FUNCTION (77act1.mud:1925):
;; `light match` counts a match off ORAND, sets FLAMEBIT and OLIGHT? 1 and
;; queues the clock event MATIN with CTICK 2 (<CLOCK-INT ,MATIN 2>); the same
;; turn's CLOCK-DEMON leaves it at 1 and the next tick fires it (C-INT: "The
;; match has gone out.", FLAMEBIT and OLIGHT? cleared). Lit four times:
;;
;;   command 24 `light match`, 25 `look`: gone out at the `look`'s tick;
;;   command 27 `light match`, 28 `wait`: WAIT stops at the tick that fires;
;;   command 29 `light match`, 30 `turn off match`: "The match is out.",
;;     <CLOCK-INT ,MATIN 0> (the event stays queued, CFLAG T, CTICK 0);
;;   command 31 `light match` (ORAND 1), 32 `light match`: ORAND 0, "I'm
;;     afraid that you have run out of matches.", then the burning one goes
;;     out at that turn's tick.
;;
;; The ROBBER demon moves the thief (HROOM) on every turn, the end-of-input
;; turn included. robber_hroom is compared at every READSTRING entry, at the
;; end and in per-prefix mode, but not used to classify end-of-input tails
;; (#:eof-classification-ignore-keys, ADR-0062 amendment): otherwise every
;; shorter prefix but the first would be re-run. The thief never meets the
;; hero and his bag stays empty.
;;
;; The dam puzzle and its leak clock MNTIN (the Maintenance Room) are not on
;; this route: this runtime stops on entering the Maintenance Room (MAINT-ROOM's
;; #DECL names the undefined type PRSOBJ; docs/evidence/M4/DAM-CLOCKS.md).
;;
;; Compared with the pinned Confusion captures in
;; docs/evidence/M4/match-clock-reference.json (MATCH-CLOCK-REFERENCE.md)
;; through the shared runner tests/m4_scenario_runner.rkt, byte for byte
;; after D1 only. Scenario evidence for M4, not a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_match_clock_test.rkt   (exit status is authoritative)
(require rackunit racket/list racket/string "m4_scenario_runner.rkt" "m4_dam_checkpoint.rkt")

(current-check-handler (lambda (e) (raise e)))

(define commands
  '("north" "east" "open window" "west" "west" "take sword" "inventory" "take lamp" "move rug"
    "open trap door" "turn on lamp" "down" "east"
    "kill troll with sword" "kill troll with sword" "kill troll with sword"
    "north" "north" "down" "up" "east" "north"
    "take match" "light match" "look" "look" "light match" "wait" "light match" "turn off match"
    "light match" "light match" "inventory" "score"))
(define burns "One of the matches starts to burn.\n")
(define gone "The match has gone out.\n")

;; --- reference-side checks (no game run) ------------------------------------------------
(define reference (m4-reference "match-clock"))
(define ref-checks (hash-ref reference 'checks))
(define cps (hash-ref (hash-ref reference 'diagnostic) 'checkpoints))
(define (cp k key) (strip-trailers (hash-ref (list-ref cps k) key)))
(check-equal? (hash-ref reference 'commands) commands)
(check-equal? (remove-duplicates (hash-ref reference 'endings)) '("eof"))
;; The match by READSTRING entry: (ORAND OLIGHT? FLAMEBIT MATIN-CFLAG MATIN-CTICK).
(define (m k) (list (cp k 'match_orand) (cp k 'match_olight) (cp k 'match_flaming)
                    (cp k 'matin_cflag) (cp k 'matin_ctick)))
(check-equal? (m 23) '("5" "0" "#FALSE ()" "T" "0"))
(check-equal? (cp 23 'here) "LOBBY")
(check-equal? (for/list ([k (in-range 23 36)]) (cons k (m k)))
              '((23 "5" "0" "#FALSE ()" "T" "0")
                (24 "4" "1" "T" "T" "1")                ; light match: CTICK 2, ticked once
                (25 "4" "0" "#FALSE ()" "T" "0")        ; look: MATIN fires
                (26 "4" "0" "#FALSE ()" "T" "0")
                (27 "3" "1" "T" "T" "1")
                (28 "3" "0" "#FALSE ()" "T" "0")        ; wait: fires, WAIT stops
                (29 "2" "1" "T" "T" "1")
                (30 "2" "0" "#FALSE ()" "T" "0")        ; turn off match: CLOCK-INT 0
                (31 "1" "1" "T" "T" "1")
                (32 "0" "0" "#FALSE ()" "T" "0")        ; out of matches; the lit one goes out
                (33 "0" "0" "#FALSE ()" "T" "0")
                (34 "0" "0" "#FALSE ()" "T" "0")
                (35 "0" "0" "#FALSE ()" "T" "0")))
;; MATIN is queued at the first `light match` (CLOCK-INT conses it in front)
;; and stays queued; the lamp clock ticks on beside it. WAIT at entry 28 ran
;; one extra CLOCK-DEMON pass (LNTIN 333 -> 331) and stopped when MATIN fired.
(check-equal? (cp 23 'clock_events) "((CURIN #FALSE () 0) (LNTIN T 337))")
(check-equal? (cp 24 'clock_events) "((MATIN T 1) (CURIN #FALSE () 0) (LNTIN T 336))")
(check-equal? (cp 28 'clock_events) "((MATIN T 0) (CURIN #FALSE () 0) (LNTIN T 331))")
(check-equal? (remove-duplicates (for/list ([k (in-range 24 36)])
                                   (regexp-replace #rx"\\(MATIN T [01]\\)"
                                                   (regexp-replace #rx"LNTIN T [0-9]+" (cp k 'clock_events) "LNTIN T N")
                                                   "(MATIN T C)")))
              '("((MATIN T C) (CURIN #FALSE () 0) (LNTIN T N))"))
(check-equal? (remove-duplicates (for/list ([k (in-range 0 24)]) (cp k 'matin_ctick))) '("0"))
;; The thief never meets the hero and takes nothing.
(check-equal? (remove-duplicates (for/list ([k (in-range 0 36)])
                                   (list (cp k 'thief_oroom) (cp k 'robber_hflag) (cp k 'robber_hobjs))))
              '(("#FALSE ()" "#FALSE ()" "()")))
;; Every shorter prefix is non-standard only through the thief's move on its
;; end-of-input turn.
(define ends (hash-ref reference 'end_checkpoints))
(check-equal? (remove-duplicates
               (for/list ([k (in-range 0 34)])
                 (for/list ([(key v) (in-hash (list-ref cps k))]
                            #:unless (eq? key 'n)
                            #:unless (equal? v (hash-ref (list-ref ends k) key)))
                   key)))
              '(() (robber_hroom)))
(define t1 (hash-ref (hash-ref reference 'transcript) 'game_output_raw))
(check-equal? (length (regexp-match* (regexp-quote burns) t1)) 4)
(check-equal? (length (regexp-match* (regexp-quote gone) t1)) 3)
(check-true (string-contains? t1 (string-append "desk.\n" gone ">")))
(check-true (string-contains? t1 (string-append ">Time passes...\n" gone ">")))
(check-true (string-contains? t1 (string-append ">" burns ">The match is out.\n>")))
(check-true (string-contains? t1 (string-append ">" burns ">I'm afraid that you have run out of matches.\n"
                                                gone ">")))
(check-equal? (remove-duplicates (hash-ref ref-checks 'prefix_files_changed)) '(("MDL/MADADV.SAVE")))

;; --- the scenario ------------------------------------------------------------------------
(run-m4-scenario "match-clock" commands
                 #:checkpoint dam-checkpoint
                 #:eof-classification-ignore-keys '(robber_hroom)
                 #:check-turn
                 (lambda (k transcript)
                   (when (>= k 26)
                     (check-true (string-contains? transcript (string-append "desk.\n" gone ">"))))))
