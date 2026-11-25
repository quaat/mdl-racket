#lang racket/base
;; The read-only state checkpoint of the M4 Phase 3b boat scenario
;; (boat-river). It renders exactly the fields of the reference diagnostic's
;; "boat" profile in scripts/probe_death_scenario_reference.py
;; (BOAT_DIAG_FORMS): every field of the dam checkpoint
;; (tests/m4_dam_checkpoint.rkt), then
;;
;;   winner_avehicle  the winner's AVEHICLE (OID; the magic boat when boarded)
;;   iboat_oroom      the folded boat's OROOM (IBOAT)
;;   rboat_oroom      the inflated boat's OROOM (RBOAT)
;;   pump_oroom       the pump's OROOM
;;
;; rendered like the reference's PRIN1 (the reference's "!-OBLIST" trailers
;; are stripped on its side). Pure reads only (docs/TESTING.md, "M4 scenario
;; runner"): GVALs, NTH on NEWSTRUC offsets and FIND-OBJ on IDs that exist.
;; No allocation charged to the game, no RANDOM, no new ATOM; the runner's
;; snapshot guard checks the RANDOM state, the storage ledger, the output and
;; the MDL error record around every read.
(require "m4_scenario_runner.rkt" "m4_dam_checkpoint.rkt"
         (only-in "../mdl/loader.rkt" mdl-session-call mdl-session-global))
(provide boat-checkpoint)

(define (boat-checkpoint s)
  (define (obj id) (mdl-session-call s "FIND-OBJ" id))
  (define (rid r) (render s (field s r "RID")))
  (define (oid o) (render s (field s o "OID")))
  (define (room-of o) (or-false (field s o "OROOM") rid))
  (hash-set* (dam-checkpoint s)
             'winner_avehicle (or-false (field s (mdl-session-global s "WINNER") "AVEHICLE") oid)
             'iboat_oroom (room-of (obj "IBOAT"))
             'rboat_oroom (room-of (obj "RBOAT"))
             'pump_oroom (room-of (obj "PUMP"))))
