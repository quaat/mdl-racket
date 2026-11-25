#lang racket/base
;; M4 Phase 3 scenario "the cure clock heals the wound" (epic #163, timers;
;; tests/scenarios/cure-recovery.json). The faithful run.mud path,
;; <FLOAD "77loadall.mud"> then SAVE-IT through the host top-level loop, on
;; the fixed session clock (fixed_epoch 250776000, zone UTC; ADR-0052), with
;; the unmodified pinned sources and no RANDOM override: troll-death's first
;; eighteen commands (the troll room unarmed, seven `wait`s: the sixth
;; staggers the hero, the seventh wounds him, ASTRENGTH -1, and BLOW enables
;; CURIN with CTICK CURE-WAIT = 30, 78melee.mud:466), then `west` back to the
;; cellar, out of the troll's reach, `diagnose` ("You have a light wound,
;; which will be cured after 28 moves."), and `wait`/`diagnose` seven times.
;; WAIT (77rooms.mud:1619) runs CLOCK-DEMON up to three more times after
;; "Time passes..." and stops when an event fires, so the countdown falls by
;; 4 per `wait` and 1 per `diagnose` (28, 23, 18, 13, 8, 3). In the sixth
;; `wait` CURIN reaches 0 and CURE-CLOCK (78melee.mud:504) raises ASTRENGTH
;; to 0 and disables CURIN: "You are in perfect health.". Then `score`.
;;
;; robber_hroom is not compared here (#:ignore-keys, timers-checkpoint/no-hroom):
;; the ROBBER demon moves the thief (HROOM) on every turn, the end-of-input
;; turn included, so with it 34 of the 35 shorter prefixes would be re-run per
;; prefix in single-run mode (35 boots, about four minutes; that full
;; comparison passed once, TIMERS-SCORING.md). The thief's walk is compared in
;; full in thief-robbery; here thief_oroom, robber_hflag and robber_hobjs are
;; (the thief never meets the hero and takes nothing).
;;
;; Compared with the pinned Confusion captures in
;; docs/evidence/M4/cure-recovery-reference.json (CURE-RECOVERY-REFERENCE.md)
;; through the shared runner tests/m4_scenario_runner.rkt, byte for byte
;; after D1 only. Scenario evidence for M4, not a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_cure_recovery_test.rkt   (exit status is authoritative)
(require rackunit racket/list racket/string "m4_scenario_runner.rkt" "m4_timers_checkpoint.rkt")

(current-check-handler (lambda (e) (raise e)))

(define commands (append '("north" "east" "open window" "west" "west" "take lamp" "move rug"
                           "open trap door" "turn on lamp" "down" "east")
                         (make-list 7 "wait")
                         '("west" "diagnose")
                         (append* (make-list 7 '("wait" "diagnose")))
                         '("score")))
(define healed "You are in perfect health.\nYou can be killed by a serious wound.\n")

;; --- reference-side checks (no game run) ------------------------------------------------
(define reference (m4-reference "cure-recovery"))
(define ref-checks (hash-ref reference 'checks))
(define diagnostic (hash-ref reference 'diagnostic))
(define cps (hash-ref diagnostic 'checkpoints))
(define (cp k key) (strip-trailers (hash-ref (list-ref cps k) key)))
(check-equal? (remove-duplicates (hash-ref reference 'endings)) '("eof"))
;; The wound and the cure clock by READSTRING entry: staggered at 17, wounded
;; at 18 (CURIN enabled, 29 after its first tick), in the cellar from 19,
;; counting down to 2 at entry 30; healed at 31 (ASTRENGTH 0, CURIN disabled
;; at tick 0) and so to the end.
(define (row k) (list (cp k 'here) (cp k 'winner_astrength) (cp k 'winner_staggered)
                      (cp k 'curin_cflag) (cp k 'curin_ctick)))
(check-equal? (row 16) '("MTROL" "0" "#FALSE ()" "#FALSE ()" "0"))
(check-equal? (row 17) '("MTROL" "0" "T" "#FALSE ()" "0"))
(check-equal? (row 18) '("MTROL" "-1" "#FALSE ()" "T" "29"))
(check-equal? (for/list ([k (in-range 19 31)]) (cp k 'curin_ctick))
              '("28" "27" "23" "22" "18" "17" "13" "12" "8" "7" "3" "2"))
(check-equal? (remove-duplicates (for/list ([k (in-range 19 31)]) (take (cdr (row k)) 3)))
              (list (list "-1" "#FALSE ()" "T")))
(check-equal? (remove-duplicates (for/list ([k (in-range 31 37)]) (row k)))
              '(("CELLA" "0" "#FALSE ()" "#FALSE ()" "0")))
;; CURIN is queued by the wound (CLOCK-INT, 78melee.mud:330) beside LNTIN.
(check-equal? (cp 16 'clock_events) "((LNTIN T 327))")
(check-equal? (cp 18 'clock_events) "((CURIN T 29) (LNTIN T 319))")
(check-equal? (cp 31 'clock_events) "((CURIN #FALSE () 0) (LNTIN T 289))")
;; The troll fights only while the hero is in his room; the thief never
;; meets the hero and takes nothing.
(check-equal? (list (cp 18 'troll_fighting) (cp 19 'troll_fighting)) '("T" "#FALSE ()"))
(check-equal? (remove-duplicates (for/list ([k (in-range 0 37)])
                                   (list (cp k 'thief_oroom) (cp k 'robber_hflag) (cp k 'robber_hobjs))))
              '(("#FALSE ()" "#FALSE ()" "()")))
(define t1 (hash-ref (hash-ref reference 'transcript) 'game_output_raw))
(check-true (string-contains? t1 (string-append
                                  ">You have a light wound, which will be cured after 3 moves.\n"
                                  "You can be killed by one more light wound.\n>Time passes...\n>"
                                  healed)))
(check-equal? (length (regexp-match* (regexp-quote healed) t1)) 2)
(check-equal? (remove-duplicates (hash-ref ref-checks 'prefix_files_changed)) '(("MDL/MADADV.SAVE")))

;; --- the scenario ------------------------------------------------------------------------
(run-m4-scenario "cure-recovery" commands
                 #:checkpoint timers-checkpoint/no-hroom
                 #:ignore-keys '(robber_hroom)
                 #:check-turn
                 (lambda (k transcript)
                   (when (>= k 32)
                     (check-true (string-contains? transcript healed)))))
