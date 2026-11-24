#lang racket/base
;; Shared checkpoint of the M4 S9 scenarios (IMAGE, SLEEP, TIME; issues
;; #168-#170): tests/historical_mirror_bat_test.rkt and
;; tests/historical_strange_passage_test.rkt. Both run through the shared
;; runner tests/m4_scenario_runner.rkt (docs/TESTING.md, "M4 scenario
;; runner"), exactly like tests/historical_cyclops_room_test.rkt:
;;   * transcript: byte for byte after D1 only (the LISTEN banner and the
;;     "DONE" line), IMAGE's BEL bytes included. Single-run mode (default):
;;     one boot; the output at READSTRING entry k equals the native prefix-k
;;     stdout up to its prompt, and at end of input the whole output equals
;;     T1; prefixes whose native end-of-input tail is not the standard
;;     "Beg pardon?" and prompt (mirror-bat prefix 33: the sword glows on the
;;     empty command) are re-run per prefix. Per-prefix mode
;;     (M4_SCENARIO_MODE=per-prefix): every prefix k = 0..n (k = n is T1,
;;     otherwise Pkk) in its own boot, whole output compared;
;;   * state: read-only checkpoints equal the reference diagnostic checkpoint
;;     k at READSTRING entry k (single run) or the reference END checkpoint k
;;     after end of input (per-prefix runs; the last checkpoint of the
;;     diagnostic run Dkk, X1 for k = n): HERE, the winner's
;;     AOBJS/ASTRENGTH/ASTAGGERED, the cyclops's OROOM,
;;     TROLL/CYCLOPS/MAGIC/MIRROR-MUNG/CAROUSEL-FLIP/CAROUSEL-ZOOM flags, the
;;     sword's OTVAL, RAW-SCORE, ASCORE, MOVES, DEATHS;
;;   * SLEEP: every run is on the fixed session clock (non-live), with a
;;     recording fake host sleeper installed by the runner; it must never be
;;     called (SLEEP returns at once and reads no clock, decision #169).
;; Every run is guarded (no file write or delete, empty temporary cwd, game
;; directory hashes unchanged) and watchdogged (a timeout is a failure).
(require "m4_scenario_runner.rkt"
         (only-in "../mdl/loader.rkt" mdl-session-call mdl-session-global))
(provide run-p0prims-scenario)

;; --- read-only checkpoints in our session ---------------------------------------------
(define (our-checkpoint s)
  (define here (mdl-session-global s "HERE"))
  (define winner (mdl-session-global s "WINNER"))
  (define sword (mdl-session-call s "FIND-OBJ" "SWORD"))
  (define cyc (mdl-session-call s "FIND-OBJ" "CYCLO"))
  (define (rid r) (render s (field s r "RID")))
  (define (flag name) (render s (mdl-session-global s name)))
  (hasheq 'here (rid here)
          'aobjs (oids s (field s winner "AOBJS"))
          'winner_astrength (render s (field s winner "ASTRENGTH"))
          'winner_staggered (bit-set? s (field s winner "AFLAGS") "ASTAGGERED")
          'cyclops_oroom (or-false (field s cyc "OROOM") rid)
          'troll_flag (flag "TROLL-FLAG!-FLAG")
          'cyclops_flag (flag "CYCLOPS-FLAG!-FLAG")
          'magic_flag (flag "MAGIC-FLAG!-FLAG")
          'mirror_mung (flag "MIRROR-MUNG!-FLAG")
          'carousel_flip (flag "CAROUSEL-FLIP!-FLAG")
          'carousel_zoom (flag "CAROUSEL-ZOOM!-FLAG")
          'sword_otval (render s (field s sword "OTVAL"))
          'raw_score (render s (mdl-session-global s "RAW-SCORE"))
          'ascore (render s (field s winner "ASCORE"))
          'moves (render s (mdl-session-global s "MOVES"))
          'deaths (render s (mdl-session-global s "DEATHS"))))

;; --- the scenario ------------------------------------------------------------------------
;; NAME: the scenario file stem (tests/scenarios/NAME.json, reference
;; docs/evidence/M4/NAME-reference.json). EXPECTED-COMMANDS pins the command
;; list. CHECK-REFERENCE runs scenario-specific checks on the parsed reference
;; before any game run. CHECK-TURN (k transcript) checks the transcript
;; compared at turn k (see run-m4-scenario).
(define (run-p0prims-scenario name expected-commands check-reference
                              #:check-turn [check-turn void])
  (check-reference (m4-reference name))
  (run-m4-scenario name expected-commands #:checkpoint our-checkpoint #:check-turn check-turn))
