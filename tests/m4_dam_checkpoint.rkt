#lang racket/base
;; The read-only state checkpoint of the M4 Phase 3b Flood Control Dam #3
;; scenarios (match-clock; dam-sluice and maint-leak are native references
;; only, see docs/evidence/M4/DAM-CLOCKS.md). It renders exactly the fields of the
;; reference diagnostic's "dam" profile in
;; scripts/probe_death_scenario_reference.py (DAM_DIAG_FORMS): every field of
;; the timers checkpoint (tests/m4_timers_checkpoint.rkt), then
;;
;;   gate_flag        GATE-FLAG!-FLAG (the yellow / brown buttons, MAINT-ROOM)
;;   low_tide         LOW-TIDE!-FLAG (the sluice gates, BOLT-FUNCTION)
;;   maint_rvars      the Maintenance Room's RVARS (MAINT-ROOM's water level)
;;   maint_munged     the Maintenance Room's RMUNGBIT (MUNG-ROOM when full)
;;   mntin_cflag/ctick the leak clock MNTIN's CFLAG and CTICK
;;   wrenc_oroom      the wrench's OROOM
;;   tube_oopen       the tube's OOPEN?
;;   putty_oroom/ocan the putty's OROOM and OCAN (OID)
;;   trunk_oroom      the trunk's OROOM
;;   trunk_visible    the trunk's OVISON bit (BOLT-FUNCTION sets it)
;;   match_orand      the matchbook's ORAND (matches left, 77dung.mud:2392)
;;   match_olight     the matchbook's OLIGHT?
;;   match_flaming    the matchbook's FLAMEBIT
;;   matin_cflag/ctick the match clock MATIN's CFLAG and CTICK
;;
;; rendered like the reference's PRIN1 (the reference's "!-OBLIST" trailers
;; are stripped on its side). Pure reads only (docs/TESTING.md, "M4 scenario
;; runner"): GVALs, NTH on NEWSTRUC offsets, ANDB/CHTYPE on flag words,
;; FIND-OBJ and FIND-ROOM on IDs that exist (FIND-ROOM only looks the room up
;; when its atom is on ROOM-OBL with a GVAL, 77defs.mud:470). No allocation
;; charged to the game, no RANDOM, no new ATOM; the runner's snapshot guard
;; checks the RANDOM state, the storage ledger, the output and the MDL error
;; record around every read.
(require "m4_scenario_runner.rkt" "m4_timers_checkpoint.rkt"
         (only-in "../mdl/loader.rkt" mdl-session-call mdl-session-global))
(provide dam-checkpoint)

(define (dam-checkpoint s)
  (define (obj id) (mdl-session-call s "FIND-OBJ" id))
  (define (rid r) (render s (field s r "RID")))
  (define (oid o) (render s (field s o "OID")))
  (define (room-of o) (or-false (field s o "OROOM") rid))
  (define maint (mdl-session-call s "FIND-ROOM" "MAINT"))
  (define mntin (mdl-session-global s "MNTIN"))
  (define putty (obj "PUTTY"))
  (define trunk (obj "TRUNK"))
  (define match (obj "MATCH"))
  (define matin (mdl-session-global s "MATIN"))
  (hash-set* (timers-checkpoint s)
             'gate_flag (render s (mdl-session-global s "GATE-FLAG!-FLAG"))
             'low_tide (render s (mdl-session-global s "LOW-TIDE!-FLAG"))
             'maint_rvars (render s (field s maint "RVARS"))
             'maint_munged (bit-set? s (field s maint "RBITS") "RMUNGBIT")
             'mntin_cflag (render s (field s mntin "CFLAG"))
             'mntin_ctick (render s (field s mntin "CTICK"))
             'wrenc_oroom (room-of (obj "WRENC"))
             'tube_oopen (render s (field s (obj "TUBE") "OOPEN?"))
             'putty_oroom (room-of putty)
             'putty_ocan (or-false (field s putty "OCAN") oid)
             'trunk_oroom (room-of trunk)
             'trunk_visible (bit-set? s (field s trunk "OFLAGS") "OVISON")
             'match_orand (render s (field s match "ORAND"))
             'match_olight (render s (field s match "OLIGHT?"))
             'match_flaming (bit-set? s (field s match "OFLAGS") "FLAMEBIT")
             'matin_cflag (render s (field s matin "CFLAG"))
             'matin_ctick (render s (field s matin "CTICK"))))
