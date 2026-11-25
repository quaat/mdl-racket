#lang racket/base
;; The read-only state checkpoint of the M4 Phase 3c puzzle scenarios
;; (balloon-ledge, coal-machine, gas-room). It renders exactly the fields of
;; the reference diagnostic's "puzzles" profile in
;; scripts/probe_death_scenario_reference.py (PUZZLES_DIAG_FORMS): every field
;; of the boat checkpoint (tests/m4_boat_checkpoint.rkt), then
;;
;;   ballo_oroom      the balloon's OROOM (BALLO)
;;   bloc             BLOC, the balloon's location (RID)
;;   binf             BINF!-FLAG, the object burning in the receptacle (OID)
;;   btie             BTIE!-FLAG (the wire tied to a hook, WIRE-FUNCTION)
;;   recep_oopen      the receptacle's OOPEN?
;;   recep_contents   the receptacle's OCONTENTS (OIDs)
;;   bint_cflag/ctick the balloon clock BINT's CFLAG and CTICK
;;   brnin_cflag/ctick the burn-out clock BRNIN's CFLAG and CTICK
;;   guide_oroom/ocan/olight the guidebook's OROOM, OCAN (OID) and OLIGHT?
;;   rope_oroom       the rope's OROOM
;;   dome_flag        DOME-FLAG!-FLAG (the rope tied to the railing)
;;   torch_oroom/olight the torch's OROOM and OLIGHT?
;;   glacier_flag     GLACIER-FLAG!-FLAG (the glacier melted)
;;   cage_top         CAGE-TOP!-FLAG (the basket at the top of the shaft)
;;   tbask_oroom      the basket's OROOM (TBASK)
;;   tbask_contents   the basket's OCONTENTS (OIDs)
;;   fbask_oroom      the other end's OROOM (FBASK)
;;   coal_oroom/ocan  the coal's OROOM and OCAN (OID)
;;   machi_oopen      the machine's OOPEN? (its lid)
;;   machi_contents   the machine's OCONTENTS (OIDs)
;;   diamo_oroom/ocan the diamond's OROOM and OCAN (OID)
;;   screw_oroom      the screwdriver's OROOM
;;   light_shaft      LIGHT-SHAFT (10 until the lit Lower Shaft is scored)
;;   empty_handed     EMPTY-HANDED!-FLAG (NO-OBJS)
;;   candl_oroom/ocan/olight the candles' OROOM, OCAN (OID) and OLIGHT?
;;   cndin_cflag/ctick the candle clock CNDIN's CFLAG and CTICK
;;   brace_oroom      the sapphire bracelet's OROOM (the gas room)
;;
;; rendered like the reference's PRIN1 (the reference's "!-OBLIST" trailers
;; are stripped on its side). Pure reads only (docs/TESTING.md, "M4 scenario
;; runner"): GVALs, NTH on NEWSTRUC offsets, LENGTH/NTH over existing lists
;; and FIND-OBJ on IDs that exist. No allocation charged to the game, no
;; RANDOM, no new ATOM; the runner's snapshot guard checks the RANDOM state,
;; the storage ledger, the output and the MDL error record around every read.
(require "m4_scenario_runner.rkt" "m4_boat_checkpoint.rkt"
         (only-in "../mdl/loader.rkt" mdl-session-call mdl-session-global))
(provide puzzles-checkpoint)

(define (puzzles-checkpoint s)
  (define (obj id) (mdl-session-call s "FIND-OBJ" id))
  (define (gval name) (mdl-session-global s name))
  (define (rid r) (render s (field s r "RID")))
  (define (oid o) (render s (field s o "OID")))
  (define (room-of o) (or-false (field s o "OROOM") rid))
  (define (can-of o) (or-false (field s o "OCAN") oid))
  (define (fld o name) (render s (field s o name)))
  (define recep (obj "RECEP"))
  (define guide (obj "GUIDE"))
  (define torch (obj "TORCH"))
  (define tbask (obj "TBASK"))
  (define coal (obj "COAL"))
  (define machi (obj "MACHI"))
  (define diamo (obj "DIAMO"))
  (define candl (obj "CANDL"))
  (define bint (gval "BINT"))
  (define brnin (gval "BRNIN"))
  (define cndin (gval "CNDIN"))
  (hash-set* (boat-checkpoint s)
             'ballo_oroom (room-of (obj "BALLO"))
             'bloc (rid (gval "BLOC"))
             'binf (or-false (gval "BINF!-FLAG") oid)
             'btie (render s (gval "BTIE!-FLAG"))
             'recep_oopen (fld recep "OOPEN?")
             'recep_contents (oids s (field s recep "OCONTENTS"))
             'bint_cflag (fld bint "CFLAG")
             'bint_ctick (fld bint "CTICK")
             'brnin_cflag (fld brnin "CFLAG")
             'brnin_ctick (fld brnin "CTICK")
             'guide_oroom (room-of guide)
             'guide_ocan (can-of guide)
             'guide_olight (fld guide "OLIGHT?")
             'rope_oroom (room-of (obj "ROPE"))
             'dome_flag (render s (gval "DOME-FLAG!-FLAG"))
             'torch_oroom (room-of torch)
             'torch_olight (fld torch "OLIGHT?")
             'glacier_flag (render s (gval "GLACIER-FLAG!-FLAG"))
             'cage_top (render s (gval "CAGE-TOP!-FLAG"))
             'tbask_oroom (room-of tbask)
             'tbask_contents (oids s (field s tbask "OCONTENTS"))
             'fbask_oroom (room-of (obj "FBASK"))
             'coal_oroom (room-of coal)
             'coal_ocan (can-of coal)
             'machi_oopen (fld machi "OOPEN?")
             'machi_contents (oids s (field s machi "OCONTENTS"))
             'diamo_oroom (room-of diamo)
             'diamo_ocan (can-of diamo)
             'screw_oroom (room-of (obj "SCREW"))
             'light_shaft (render s (gval "LIGHT-SHAFT"))
             'empty_handed (render s (gval "EMPTY-HANDED!-FLAG"))
             'candl_oroom (room-of candl)
             'candl_ocan (can-of candl)
             'candl_olight (fld candl "OLIGHT?")
             'cndin_cflag (fld cndin "CFLAG")
             'cndin_ctick (fld cndin "CTICK")
             'brace_oroom (room-of (obj "BRACE"))))
