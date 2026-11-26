#lang racket/base
;; The read-only state checkpoint of the M4 combat.thief scenario
;; (thief-fight). It renders exactly the fields of the reference diagnostic's
;; "thief" profile in scripts/probe_death_scenario_reference.py
;; (THIEF_DIAG_FORMS): every field of the timers checkpoint
;; (tests/m4_timers_checkpoint.rkt), then
;;
;;   thief_ocapac     the thief's OCAPAC (his fighting strength; BLOW lowers it)
;;   thief_fighting   the thief's FIGHTBIT (in melee)
;;   thief_staggered  the thief's STAGGERED bit
;;   still_oroom/ocan the stiletto's OROOM and OCAN (OID; the thief holds it)
;;   chali_oroom      the chalice's OROOM (the Treasure Room)
;;   chali_takebit    the chalice's TAKEBIT (TREASURE-ROOM clears it)
;;   robber_haction   the ROBBER demon's HACTION (ROBBER-FUNCTION's DEAD!,
;;                    OUT! and IN! change it)
;;
;; rendered like the reference's PRIN1 (the reference's "!-OBLIST" trailers
;; are stripped on its side). Pure reads only (docs/TESTING.md, "M4 scenario
;; runner"): GVALs, NTH on NEWSTRUC offsets, ANDB/CHTYPE on flag words and
;; FIND-OBJ on IDs that exist. No allocation charged to the game, no RANDOM,
;; no new ATOM; the runner's snapshot guard checks the RANDOM state, the
;; storage ledger, the output and the MDL error record around every read.
(require "m4_scenario_runner.rkt" "m4_timers_checkpoint.rkt"
         (only-in "../mdl/loader.rkt" mdl-session-call mdl-session-global))
(provide thief-checkpoint)

(define (thief-checkpoint s)
  (define (obj id) (mdl-session-call s "FIND-OBJ" id))
  (define (rid r) (render s (field s r "RID")))
  (define (oid o) (render s (field s o "OID")))
  (define (room-of o) (or-false (field s o "OROOM") rid))
  (define thief (obj "THIEF"))
  (define still (obj "STILL"))
  (define chali (obj "CHALI"))
  (hash-set* (timers-checkpoint s)
             'thief_ocapac (render s (field s thief "OCAPAC"))
             'thief_fighting (bit-set? s (field s thief "OFLAGS") "FIGHTBIT")
             'thief_staggered (bit-set? s (field s thief "OFLAGS") "STAGGERED")
             'still_oroom (room-of still)
             'still_ocan (or-false (field s still "OCAN") oid)
             'chali_oroom (room-of chali)
             'chali_takebit (bit-set? s (field s chali "OFLAGS") "TAKEBIT")
             'robber_haction (render s (field s (mdl-session-global s "ROBBER-DEMON") "HACTION"))))
