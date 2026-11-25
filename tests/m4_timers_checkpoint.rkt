#lang racket/base
;; The read-only state checkpoint of the M4 Phase 3 timer, object and scoring
;; scenarios (treasure-deposit, thief-robbery, cure-recovery, lamp-burnout).
;; It renders exactly the fields of the reference diagnostic's "timers"
;; profile in scripts/probe_death_scenario_reference.py (TIMERS_DIAG_FORMS):
;; every field of the death checkpoint (tests/m4_death_checkpoint.rkt), then
;;
;;   lamp_cnt         <1 <ORAND lamp>>, LIGHT-INT's count of fired lamp events
;;   lntin_cflag/ctick the lamp clock LNTIN's CFLAG and CTICK
;;   clock_events     the CLOCKER demon's HOBJS, each CEVENT as (CID CFLAG CTICK)
;;   paint_*          the painting's OROOM, OCAN, OFVAL and OTVAL
;;   tcase_*          the trophy case's OOPEN? and OCONTENTS (OIDs)
;;   thief_oroom      the thief's OROOM
;;   robber_*         the ROBBER demon's HROOM (RID), HFLAG and HOBJS (OIDs)
;;
;; rendered like the reference's PRIN1 (the reference's "!-OBLIST" trailers
;; are stripped on its side). Pure reads only (docs/TESTING.md, "M4 scenario
;; runner"): GVALs, NTH on NEWSTRUC offsets, FIND-OBJ on IDs that exist, and
;; LENGTH/NTH over existing lists. No allocation charged to the game, no
;; RANDOM, no new ATOM; the runner's snapshot guard checks the RANDOM state,
;; the storage ledger, the output and the MDL error record around every read.
(require racket/string "m4_scenario_runner.rkt" "m4_death_checkpoint.rkt"
         (only-in "../mdl/loader.rkt" mdl-session-call mdl-session-global))
(provide timers-checkpoint)

(define (list-items s lst)
  (for/list ([i (in-range 1 (add1 (mdl-session-call s "LENGTH" lst)))])
    (mdl-session-call s "NTH" lst i)))

(define (clock-events s)
  (define clocker (mdl-session-global s "CLOCKER"))
  (string-append
   "("
   (string-join (for/list ([ev (in-list (list-items s (field s clocker "HOBJS")))])
                  (string-append "(" (render s (field s ev "CID"))
                                 " " (render s (field s ev "CFLAG"))
                                 " " (render s (field s ev "CTICK")) ")"))
                " ")
   ")"))

;; The RID of the ROBBER demon's HROOM, rendered like the reference's PRIN1.
;; The thief's walk over ,ROOMS reaches rooms whose RID is not a plain name:
;; the room "!" (created by FIND-ROOM for NULEXIT, 77dung.mud:2053), which
;; PRIN1 prints escaped as \! (reference lamp-burnout, entry 105: "\!!-ROOMS",
;; its trailer stripped). The runtime's UNPARSE does not implement escaping
;; (core.rkt, mdl-unparse-value), so this renders only the PNAMEs observed:
;; [A-Za-z0-9-] as they are, "!" as \!, any other PNAME a strict error.
(define (hroom-rid s room)
  (define pname (render s (field s room "RID")))
  (cond [(regexp-match? #px"^[A-Za-z0-9-]+$" pname) pname]
        [(equal? pname "!") "\\!"]
        [else (error 'timers-checkpoint "HROOM RID ~s needs PRIN1 escaping not rendered here" pname)]))

(define (timers-checkpoint s)
  (define (obj id) (mdl-session-call s "FIND-OBJ" id))
  (define (rid r) (render s (field s r "RID")))
  (define (oid o) (render s (field s o "OID")))
  (define (room-of o) (or-false (field s o "OROOM") rid))
  (define lamp (obj "LAMP"))
  (define lntin (mdl-session-global s "LNTIN"))
  (define paint (obj "PAINT"))
  (define tcase (obj "TCASE"))
  (define robber (mdl-session-global s "ROBBER-DEMON"))
  (hash-set* (death-checkpoint s)
             'lamp_cnt (render s (mdl-session-call s "NTH" (field s lamp "ORAND") 1))
             'lntin_cflag (render s (field s lntin "CFLAG"))
             'lntin_ctick (render s (field s lntin "CTICK"))
             'clock_events (clock-events s)
             'paint_oroom (room-of paint)
             'paint_ocan (or-false (field s paint "OCAN") oid)
             'paint_ofval (render s (field s paint "OFVAL"))
             'paint_otval (render s (field s paint "OTVAL"))
             'tcase_oopen (render s (field s tcase "OOPEN?"))
             'tcase_contents (oids s (field s tcase "OCONTENTS"))
             'thief_oroom (room-of (obj "THIEF"))
             'robber_hroom (hroom-rid s (field s robber "HROOM"))
             'robber_hflag (render s (field s robber "HFLAG"))
             'robber_hobjs (oids s (field s robber "HOBJS"))))
