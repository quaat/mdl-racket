#lang racket/base
;; M4 S2 scenario "drop the leaflet" (frontier F1: CHTYPE to SEGMENT in the
;; INSERT-OBJECT macro, 77defs.mud:332-336). The faithful run.mud path,
;; <FLOAD "77loadall.mud"> then SAVE-IT through the host top-level loop, on
;; the fixed session clock (fixed_epoch 250776000, zone UTC; ADR-0052), with
;; the commands of tests/scenarios/mailbox-drop.json.
;;
;; Compared with the pinned Confusion pipe captures in
;; docs/evidence/M4/mailbox-drop-reference.json (MAILBOX-DROP-REFERENCE.md) by
;; the shared runner tests/m4_scenario_runner.rkt (docs/TESTING.md, "M4
;; scenario runner"), byte for byte after D1 only (the LISTEN banner and the
;; "DONE" line), exactly like tests/historical_house_cellar_test.rkt:
;;   * single-run mode (default): one boot fed all 8 commands; at READSTRING
;;     entry k (k = 0..8) the output equals the native prefix-k stdout up to
;;     its prompt and the read-only checkpoints equal the reference diagnostic
;;     checkpoint k (taken at READSTRING entry k in run X1, whose game text
;;     was verified byte-identical to T1); at end of input the whole output
;;     equals T1 and the state equals checkpoint 8;
;;   * per-prefix mode (M4_SCENARIO_MODE=per-prefix): for every prefix of k
;;     commands (k = 0..8; k = 8 is reference case T1, otherwise Pkk) the
;;     whole output equals the reference stdout and, after end of input, the
;;     checkpoints equal diagnostic checkpoint k;
;;   * the diagnostic-only field robjs_tail_shared (identity with the
;;     previous checkpoint's list) is not compared (it is not comparable
;;     across fresh prefix sessions); the tail sharing is checked directly in
;;     the macro section below;
;;   * macros: after a fresh FLOAD (no SAVE-IT, like reference case
;;     game-insert-take-object of docs/evidence/M4/segment-chtype-probe.json)
;;     the game's own INSERT-OBJECT and TAKE-OBJECT prepend the object and
;;     share the previous ROBJS/AOBJS list as the tail (==?), and set OROOM.
;;
;; Every run is guarded (no file write or delete, empty temporary cwd, game
;; directory hashes unchanged) and watchdogged (a timeout is a failure).
;; This is scenario evidence for M4, not a PLAYABLE or M4-gate claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_mailbox_drop_test.rkt   (exit status is authoritative)
(require rackunit racket/runtime-path racket/string racket/list json "m4_scenario_runner.rkt"
         (only-in "../mdl/loader.rkt" mdl-session-call mdl-session-global mdl-session-atom)
         (only-in "../mdl/runtime/core.rkt" mdl-truthy?))

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler (lambda (e) (raise e)))

(define-runtime-path probe-file "../docs/evidence/M4/segment-chtype-probe.json")
(define commands '("open mailbox" "take leaflet" "drop leaflet" "inventory" "look"
                   "take leaflet" "drop leaflet" "look"))

;; --- scenario-specific reference checks -------------------------------------------
(define reference (m4-reference "mailbox-drop"))
(define ref-checkpoints (hash-ref (hash-ref reference 'diagnostic) 'checkpoints))
(check-equal? (length ref-checkpoints) (+ 2 (length commands)))
;; The end-of-input read changes no compared checkpoint field.
(check-equal? (hash-remove (list-ref ref-checkpoints 8) 'n)
              (hash-remove (list-ref ref-checkpoints 9) 'n))
;; Both drops prepend to the room list and share the old list as its tail.
(check-equal? (for/list ([cp ref-checkpoints]) (hash-ref cp 'robjs_tail_shared))
              '("#FALSE ()" "#FALSE ()" "#FALSE ()" "T" "#FALSE ()" "#FALSE ()" "#FALSE ()"
                "T" "#FALSE ()" "#FALSE ()"))
;; RANDOM: START's seeding call, then one draw in each `look`.
(check-equal? (for/list ([d (hash-ref (hash-ref reference 'diagnostic) 'random_draws)])
                (list (hash-ref d 'args) (hash-ref d 'result) (hash-ref d 'before_checkpoint)))
              '(("(10438660480)" 16566282405 0) ("()" -21802663835 5) ("()" 12914488375 8)))

;; --- read-only checkpoints in our session ---------------------------------------
;; Rendered like the reference diagnostic's PRIN1 for the values that occur:
;; FIX, ATOM (pname; the reference trailer "!-OBLIST" is stripped from its
;; side), an empty FALSE and LISTs of OIDs. Anything else is a strict error.
(define (our-checkpoint s)
  (define here (mdl-session-global s "HERE"))
  (define winner (mdl-session-global s "WINNER"))
  (define leaf (mdl-session-call s "FIND-OBJ" "ADVER"))
  (define mbox (mdl-session-call s "FIND-OBJ" "MAILB"))
  (define whous (mdl-session-call s "FIND-ROOM" "WHOUS"))
  (hasheq 'here (render s (field s here "RID"))
          'aobjs (oids s (field s winner "AOBJS"))
          'whous_robjs (oids s (field s whous "ROBJS"))
          'mailbox_ocontents (oids s (field s mbox "OCONTENTS"))
          'mailbox_oopen (render s (field s mbox "OOPEN?"))
          'leaflet_oroom (or-false (field s leaf "OROOM") (lambda (r) (render s (field s r "RID"))))
          'leaflet_ocan (or-false (field s leaf "OCAN") (lambda (o) (render s (field s o "OID"))))
          'leaflet_otouch (render s (field s leaf "OTOUCH?"))
          'raw_score (render s (mdl-session-global s "RAW-SCORE"))
          'ascore (render s (field s winner "ASCORE"))
          'moves (render s (mdl-session-global s "MOVES"))))

;; === every turn / every prefix, k = 0 .. 8 =========================================
(run-m4-scenario "mailbox-drop" commands #:checkpoint our-checkpoint
                 #:ignore-keys '(robjs_tail_shared))

;; === the game's INSERT-OBJECT and TAKE-OBJECT, after FLOAD (no SAVE-IT) ============
;; Reference: case game-insert-take-object (segment-chtype-probe.json), which
;; binds R = LROOM, O = ADVER, W = ,PLAYER and calls the macros on .O/.R/.W.
;; Here the same objects are passed through the session's test boundary
;; (mdl-session-call expands the MACRO and evaluates the expansion).
(let* ([probe (call-with-input-file probe-file read-json)]
       [pcase (findf (lambda (c) (equal? (hash-ref c 'name) "game-insert-take-object"))
                     (hash-ref probe 'cases))]
       [out (hash-ref pcase 'stdout_raw)])
  (check-equal? (hash-ref probe 'interpreter_sha256_before) m4-pinned-mdli)
  (for ([expected (in-list
                   '("<PUT .R 7 (<PUT .O 19 .R> !<ROBJS .R!>)>"
                     "(FORM SEGMENT)"
                     "(WDOOR!-OBJECTS DOOR!-OBJECTS TCASE!-OBJECTS LAMP!-OBJECTS RUG!-OBJECTS PAPER!-OBJECTS SWORD!-OBJECTS)"
                     "(ADVER!-OBJECTS WDOOR!-OBJECTS DOOR!-OBJECTS TCASE!-OBJECTS LAMP!-OBJECTS RUG!-OBJECTS PAPER!-OBJECTS SWORD!-OBJECTS)"
                     "(LAMP!-OBJECTS ADVER!-OBJECTS)"))])
    (check-true (string-contains? out expected) expected))
  (define s (m4-run-load-only "macros"))
  (define lroom (mdl-session-call s "FIND-ROOM" "LROOM"))
  (define leaf (mdl-session-call s "FIND-OBJ" "ADVER"))
  (define lamp (mdl-session-call s "FIND-OBJ" "LAMP"))
  (define player (mdl-session-global s "PLAYER"))
  (define (same? a b) (mdl-truthy? (mdl-session-call s "==?" a b)))
  (define before (field s lroom "ROBJS"))
  (check-equal? (strip-trailers (oids s before))
                "(WDOOR DOOR TCASE LAMP RUG PAPER SWORD)")
  (mdl-session-call s "INSERT-OBJECT" leaf lroom)
  (check-equal? (oids s (field s lroom "ROBJS")) "(ADVER WDOOR DOOR TCASE LAMP RUG PAPER SWORD)")
  (check-true (same? (mdl-session-call s "REST" (field s lroom "ROBJS")) before))
  (check-true (same? (field s leaf "OROOM") lroom))
  (define a0 (field s player "AOBJS"))
  (mdl-session-call s "TAKE-OBJECT" leaf player)
  (check-equal? (oids s (field s player "AOBJS")) "(ADVER)")
  ;; a0 is (): this ==? check is trivially true (S2 review); the LAMP check
  ;; below, against a non-empty AOBJS, is the one that proves tail sharing.
  (check-true (same? (mdl-session-call s "REST" (field s player "AOBJS")) a0))
  (check-equal? (render s (field s leaf "OROOM")) "#FALSE ()")
  (define a1 (field s player "AOBJS"))
  (mdl-session-call s "TAKE-OBJECT" lamp player)
  (check-equal? (oids s (field s player "AOBJS")) "(LAMP ADVER)")
  (check-true (same? (mdl-session-call s "REST" (field s player "AOBJS")) a1))
  (printf "macros: INSERT-OBJECT and TAKE-OBJECT prepend and share the old list (reference)\n"))
