#lang racket/base
;; The December 1977 Zork profile for deterministic replay persistence
;; (ADR-0061; SEMANTICS "M4 WP4"). Host-only: it reads game state through the
;; session introspection API and never changes it, never writes a file, and
;; adds nothing to run-zork (zork/main.rkt), whose no-file policy is unchanged.
;;
;;   zork-replay-profile       the replay-profile for run.mud's path
;;                             (<FLOAD "77loadall.mud">, then SAVE-IT)
;;   zork-record / zork-restore  replay-record / replay-restore with it
;;   zork-replay-state         the selected game state of a session
;;   zork-dskdate              DSKDATE (81tell-repl.mud:57) of a clock read
(require racket/runtime-path racket/list racket/string racket/date json
         "../mdl/loader.rkt" "../mdl/replay.rkt" "../mdl/runtime/clock.rkt"
         (only-in "../mdl/runtime/core.rkt" mdl-atom? mdl-atom-pname mdl-truthy?
                  mdl-false? mdl-string-snapshot))

(provide zork-replay-profile zork-record zork-restore zork-replay-state zork-dskdate
         zork-upstream zork-default-source-root)

(define-runtime-path zork-default-source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(define-runtime-path sources-lock "../sources.lock.json")

;; Upstream SHAs from the repository's pinned sources.lock.json (a trusted,
;; checked-in file).
(define (zork-upstream)
  (define lock (call-with-input-file sources-lock read-json))
  (for/hasheq ([(name src) (in-hash (hash-ref lock 'sources))])
    (values name (hash-ref src 'commit))))

;; --- the save boundary: RDCOM's command prompt, nothing pending ----------------------
(define rdcom-locals '("AV" "INBUF" "INPLEN" "IVEC" "OUTCHAN" "RANDOM-ACTION" "RM" "RVEC" "STR"
                       "VC" "WINNER"))
(define reader-stops (list (integer->char 27) #\return #\newline)) ; READER-STRING, 77rooms.mud:598
(define (frame-names frame) (sort (map mdl-atom-pname (hash-keys frame)) string<?))
(define (frame-ref frame name)
  (for/first ([(k v) (in-hash frame)] #:when (equal? (mdl-atom-pname k) name)) v))

(define (zork-prompt-refusal s info)
  (define frames (hash-ref info 'local-frames))
  (define not-rdcom "not at the RDCOM command prompt (77rooms.mud:616)")
  (cond
    [(not (and (= (length frames) 3)
               (equal? (frame-names (first frames)) '("CV" "VVAL"))
               (equal? (frame-names (second frames)) rdcom-locals)
               (equal? (hash-ref info 'activation-kinds) '(prog))))
     (string-append not-rdcom ": the READSTRING is not RDCOM's own (a parser follow-up, YES/NO or another reader)")]
    [(mdl-truthy? (frame-ref (second frames) "IVEC"))
     (string-append not-rdcom ": RDCOM is running a given command vector")]
    [(not (and (eq? (hash-ref info 'buffer) (mdl-session-global s "INBUF"))
               (eq? (hash-ref info 'channel) (mdl-session-global s "INCHAN"))
               (equal? (hash-ref info 'stops) reader-stops)))
     (string-append not-rdcom ": the READSTRING does not read INBUF from INCHAN up to READER-STRING")]
    [(not (eq? (mdl-session-global s "REP") (mdl-session-global s "RDCOM")))
     (string-append not-rdcom ": ,REP is not ,RDCOM")]
    [(mdl-truthy? (mdl-session-call s "NTH" (mdl-session-global s "ORPHANS") 1))
     "an orphan question is pending (<1 ,ORPHANS> is set)"]
    [else #f]))

;; --- the selected game state ---------------------------------------------------------
;; Rendered like the troll scenario's checkpoints (FIX decimal, ATOM PNAME,
;; empty FALSE "#FALSE ()"), extended for WORD ("#WORD n"), STRING, non-empty
;; FALSE and other TYPEs (TYPE name only).
(define (type-name s v) (mdl-atom-pname (mdl-session-call s "TYPE" v)))
(define (render s v)
  (cond [(exact-integer? v) (number->string v)]
        [(mdl-atom? v) (mdl-atom-pname v)]
        [else
         (define type (type-name s v))
         (cond [(equal? type "FALSE")
                (if (eqv? 0 (mdl-session-call s "LENGTH" v)) "#FALSE ()" "#FALSE (...)")]
               [(equal? type "WORD")
                (format "#WORD ~a" (mdl-session-call s "CHTYPE" v (mdl-session-atom s "FIX")))]
               [(equal? type "STRING") (format "~s" (mdl-string-snapshot 'zork-state v "STRING"))]
               [else (string-append "#" type)])]))
;; A global the game may not have assigned yet (PARSE-WON before the first
;; command): "#UNASSIGNED" instead of a strict error.
(define (render-global s name)
  (if (mdl-truthy? (mdl-session-call s "GASSIGNED?" (mdl-session-atom s name)))
      (render s (mdl-session-global s name))
      "#UNASSIGNED"))
(define (field s obj name) (mdl-session-call s "NTH" obj (mdl-session-global s name)))
(define (oids s lst)
  (string-append
   "(" (string-join (for/list ([i (in-range 1 (add1 (mdl-session-call s "LENGTH" lst)))])
                      (render s (field s (mdl-session-call s "NTH" lst i) "OID")))
                    " ")
   ")"))
(define (bit-set? s flags bit-name)
  (define w (mdl-session-call s "ANDB" flags (mdl-session-global s bit-name)))
  (if (eqv? 0 (mdl-session-call s "CHTYPE" w (mdl-session-atom s "FIX"))) "#FALSE ()" "T"))

(define (zork-replay-state s)
  (define here (mdl-session-global s "HERE"))
  (define winner (mdl-session-global s "WINNER"))
  (define sword (mdl-session-call s "FIND-OBJ" "SWORD"))
  (define troll (mdl-session-call s "FIND-OBJ" "TROLL"))
  (define axe (mdl-session-call s "FIND-OBJ" "AXE"))
  (define lamp (mdl-session-call s "FIND-OBJ" "LAMP"))
  (define demon (mdl-session-global s "SWORD-DEMON"))
  (define curin (mdl-session-global s "CURIN"))
  (define oppv-1 (mdl-session-call s "NTH" (mdl-session-global s "OPPV") 1))
  (define (or-false v f) (if (mdl-truthy? v) (f v) "#FALSE ()"))
  (define (rid r) (render s (field s r "RID")))
  (define (oid o) (render s (field s o "OID")))
  (define events (mdl-session-call s "NTH" (mdl-session-global s "CLOCKER")
                                   (mdl-session-global s "HOBJS")))
  (define ledger (mdl-session-storage-stats s))
  (hasheq
   ;; the troll scenario's checkpoint fields (tests/historical_troll_combat_test.rkt)
   'here (rid here)
   'aobjs (oids s (field s winner "AOBJS"))
   'winner_astrength (render s (field s winner "ASTRENGTH"))
   'winner_staggered (bit-set? s (field s winner "AFLAGS") "ASTAGGERED")
   'troll_oroom (or-false (field s troll "OROOM") rid)
   'troll_ocapac (render s (field s troll "OCAPAC"))
   'troll_ocontents (oids s (field s troll "OCONTENTS"))
   'troll_fighting (bit-set? s (field s troll "OFLAGS") "FIGHTBIT")
   'troll_staggered (bit-set? s (field s troll "OFLAGS") "STAGGERED")
   'axe_oroom (or-false (field s axe "OROOM") rid)
   'axe_ocan (or-false (field s axe "OCAN") oid)
   'troll_flag (render s (mdl-session-global s "TROLL-FLAG!-FLAG"))
   'oppv_1 (or-false oppv-1 oid)
   'villain_probs_1 (render s (mdl-session-call s "NTH" (mdl-session-global s "VILLAIN-PROBS") 1))
   'curin_cflag (render s (field s curin "CFLAG"))
   'curin_ctick (render s (field s curin "CTICK"))
   'sword_otval (render s (field s sword "OTVAL"))
   'sword_demon_haction (render s (field s demon "HACTION"))
   'raw_score (render s (mdl-session-global s "RAW-SCORE"))
   'ascore (render s (field s winner "ASCORE"))
   'moves (render s (mdl-session-global s "MOVES"))
   ;; more of the game and runtime state
   'winner_aroom (rid (field s winner "AROOM"))
   'deaths (render s (mdl-session-global s "DEATHS"))
   'intime (render s (mdl-session-global s "INTIME"))
   'played_time (render s (mdl-session-global s "PLAYED-TIME"))
   'parse_won (render-global s "PARSE-WON")
   'orphans_oflag (render s (mdl-session-call s "NTH" (mdl-session-global s "ORPHANS") 1))
   ;; every clock event (CLOCK-INT, 77rooms.mud:1657): CID CTICK CFLAG
   'clock_events
   (string-join (for/list ([i (in-range 1 (add1 (mdl-session-call s "LENGTH" events)))])
                  (define ev (mdl-session-call s "NTH" events i))
                  (format "~a ~a ~a" (render s (field s ev "CID")) (render s (field s ev "CTICK"))
                          (render s (field s ev "CFLAG"))))
                "; ")
   'lamp_light_count (render s (mdl-session-call s "NTH" (field s lamp "ORAND") 1))
   'lamp_olight (render s (field s lamp "OLIGHT?"))
   ;; the logical GC ledger and the game's DIVERT counters (77rooms.mud:66-90)
   'divert_cnt (render s (mdl-session-global s "DIVERT-CNT"))
   'divert_amt (render s (mdl-session-global s "DIVERT-AMT"))
   'ledger_used (number->string (hash-ref ledger 'used))
   'ledger_capacity (number->string (hash-ref ledger 'capacity))))

(define (zork-moves s) (mdl-session-global s "MOVES"))

;; DSKDATE (81tell-repl.mud:57-63) of one clock read, computed host-side:
;; half-seconds of the day in bits 0-17, day of month at 18, month at 23,
;; year of century at 27.
(define (zork-dskdate seconds micros time-zone)
  (define d (seconds->date seconds (eq? time-zone 'local)))
  (+ (+ (quotient micros 500000) (* 2 (date-second d)) (* 120 (date-minute d))
        (* 7200 (date-hour d)))
     (arithmetic-shift (date-day d) 18)
     (arithmetic-shift (date-month d) 23)
     (arithmetic-shift (modulo (date-year d) 100) 27)))

;; START's <RANDOM <CHTYPE <DSKDATE> FIX>> (77rooms.mud:291) is the session's
;; third clock read: after REMARKABLY-DISGUSTING-CODE (VERS, SAVE-IT) and
;; START's INTIME (77rooms.mud:277).
(define seed-observation-index 2)
(define (zork-seed observations time-zone)
  (cond
    [(> (length observations) seed-observation-index)
     (define o (list-ref observations seed-observation-index))
     (hasheq 'source "START <RANDOM <CHTYPE <DSKDATE> FIX>> (77rooms.mud:291)"
             'observation_index seed-observation-index
             'dskdate (zork-dskdate (clock-observation-seconds o) (clock-observation-micros o)
                                    time-zone))]
    [else (hasheq 'source "none: START has not seeded RANDOM")]))

(define zork-replay-profile
  (replay-profile "zork-1977-run.mud/v1" "77loadall.mud" "SAVE-IT" zork-upstream
                  zork-prompt-refusal zork-replay-state zork-moves zork-seed))

(define (with-default-root kws vals)
  (if (memq '#:source-root kws)
      (values kws vals)
      (let ([pairs (sort (cons (cons '#:source-root zork-default-source-root) (map cons kws vals))
                         keyword<? #:key car)])
        (values (map car pairs) (map cdr pairs)))))
;; replay-record / replay-restore with the Zork profile; the source root
;; defaults to the pinned game directory. Same keywords otherwise.
(define zork-record
  (make-keyword-procedure
   (lambda (kws vals)
     (define-values (k v) (with-default-root kws vals))
     (keyword-apply replay-record k v (list zork-replay-profile)))))
(define zork-restore
  (make-keyword-procedure
   (lambda (kws vals checkpoint)
     (define-values (k v) (with-default-root kws vals))
     (keyword-apply replay-restore k v (list zork-replay-profile checkpoint)))))
