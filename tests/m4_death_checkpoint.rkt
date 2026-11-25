#lang racket/base
;; The read-only state checkpoint shared by the M4 Phase 2 death scenarios
;; (grue-resurrection, grue-refusal, troll-death). It renders exactly the
;; fields of the reference diagnostic's DIAG-STATE in
;; scripts/probe_death_scenario_reference.py, like the reference's PRIN1: FIX,
;; ATOM pname (the reference's "!-OBLIST" trailers are stripped on its side),
;; an empty FALSE, LISTs of OIDs, and INBUF as its 100 character codes.
;;
;; Pure reads only (docs/TESTING.md, "M4 scenario runner"): GVALs, NTH on
;; NEWSTRUC offsets, ANDB/CHTYPE on flag words, FIND-OBJ on IDs that exist,
;; and a snapshot of INBUF's characters. No allocation charged to the game, no
;; RANDOM, no new ATOM; the runner's snapshot guard checks the RANDOM state,
;; the storage ledger, the output and the MDL error record around every read.
(require racket/string "m4_scenario_runner.rkt"
         (only-in "../mdl/loader.rkt" mdl-session-call mdl-session-global)
         (only-in "../mdl/runtime/core.rkt" mdl-string-snapshot))
(provide death-checkpoint)

(define (inbuf-codes s)
  (define str (mdl-string-snapshot 'death-checkpoint (mdl-session-global s "INBUF")
                                   "INBUF must be a STRING"))
  (string-append "(" (string-join (for/list ([ch (in-string str)])
                                    (number->string (char->integer ch)))
                                  " ")
                 ")"))

(define (death-checkpoint s)
  (define winner (mdl-session-global s "WINNER"))
  (define curin (mdl-session-global s "CURIN"))
  (define (obj id) (mdl-session-call s "FIND-OBJ" id))
  (define troll (obj "TROLL"))
  (define lamp (obj "LAMP"))
  (define (rid r) (render s (field s r "RID")))
  (define (oid o) (render s (field s o "OID")))
  (define (room-of o) (or-false (field s o "OROOM") rid))
  (hasheq 'here (rid (mdl-session-global s "HERE"))
          'aobjs (oids s (field s winner "AOBJS"))
          'moves (render s (mdl-session-global s "MOVES"))
          'raw_score (render s (mdl-session-global s "RAW-SCORE"))
          'ascore (render s (field s winner "ASCORE"))
          'deaths (render s (mdl-session-global s "DEATHS"))
          'egypt_flag (render s (mdl-session-global s "EGYPT-FLAG!-FLAG"))
          'door_otouch (render s (field s (obj "DOOR") "OTOUCH?"))
          'winner_astrength (render s (field s winner "ASTRENGTH"))
          'winner_staggered (bit-set? s (field s winner "AFLAGS") "ASTAGGERED")
          'curin_cflag (render s (field s curin "CFLAG"))
          'curin_ctick (render s (field s curin "CTICK"))
          'troll_oroom (room-of troll)
          'troll_ocapac (render s (field s troll "OCAPAC"))
          'troll_fighting (bit-set? s (field s troll "OFLAGS") "FIGHTBIT")
          'lamp_oroom (room-of lamp)
          'lamp_ocan (or-false (field s lamp "OCAN") oid)
          'lamp_olight (render s (field s lamp "OLIGHT?"))
          'sword_oroom (room-of (obj "SWORD"))
          'sbag_oroom (room-of (obj "SBAG"))
          'bottl_oroom (room-of (obj "BOTTL"))
          'inbuf (inbuf-codes s)))
