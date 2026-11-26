#lang racket/base
;; M4 scenario 1, "enter the house and open the cellar" (S1). The faithful
;; run.mud path, <FLOAD "77loadall.mud"> then SAVE-IT through the host
;; top-level loop, on the fixed session clock (fixed_epoch 250776000, zone
;; UTC; ADR-0052), with the commands of tests/scenarios/house-cellar.json.
;;
;; Compared with the pinned Confusion pipe captures in
;; docs/evidence/M4/house-cellar-reference.json (HOUSE-CELLAR-REFERENCE.md) by
;; the shared runner tests/m4_scenario_runner.rkt (docs/TESTING.md, "M4
;; scenario runner"), byte for byte after D1 only (the Confusion/LISTEN banner
;; up to "LISTENING-AT-LEVEL 1 PROCESS 1" and the "DONE" line; stricter than
;; D2):
;;   * single-run mode (default): one boot fed all 11 commands; at READSTRING
;;     entry k (k = 0..11) the output equals the native prefix-k stdout up to
;;     its prompt and the read-only checkpoints equal the reference diagnostic
;;     checkpoint k (taken at READSTRING entry k in run X1, whose game text
;;     was verified byte-identical to T1); at end of input the whole output
;;     equals T1 and the state equals checkpoint 11. Every prefix's native
;;     end-of-input tail is the standard "Beg pardon?" and a prompt, so no
;;     prefix is re-run;
;;   * per-prefix mode (M4_SCENARIO_MODE=per-prefix): for every prefix of k
;;     commands (k = 0..11; k = 11 is reference case T1, otherwise Pkk) the
;;     whole output equals the reference stdout and, after end of input, the
;;     checkpoints equal diagnostic checkpoint k. The reference shows the
;;     end-of-input read changes no checkpoint field (checkpoints 11 and 12
;;     are equal), so the state at our input exhaustion is comparable with
;;     checkpoint k;
;;   * end of input: the reference prints "Beg pardon?", a prompt, and dies
;;     with "Error: Unexpected EOF"; we end by D3 input exhaustion.
;;
;; Every run is guarded (no file write or delete, empty temporary cwd, game
;; directory hashes unchanged) and watchdogged (a timeout is a failure).
;; This is scenario evidence for M4, not a PLAYABLE or M4-gate claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_house_cellar_test.rkt   (exit status is authoritative)
(require rackunit racket/list json "m4_scenario_runner.rkt"
         (only-in "../mdl/loader.rkt" mdl-session-call mdl-session-global)
         (only-in "../mdl/runtime/core.rkt" mdl-truthy?))

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler (lambda (e) (raise e)))

(define commands '("north" "east" "open window" "west" "west" "take lamp" "move rug"
                   "open trap door" "turn on lamp" "down" "score"))

;; --- scenario-specific reference checks -------------------------------------------
(define reference (m4-reference "house-cellar"))
(define ref-checkpoints (hash-ref (hash-ref reference 'diagnostic) 'checkpoints))
;; The end-of-input read changes no checkpoint field (only the counter n).
(check-equal? (hash-remove (list-ref ref-checkpoints 11) 'n)
              (hash-remove (list-ref ref-checkpoints 12) 'n))
;; The only RANDOM call on the whole path is START's seeding call.
(check-equal? (for/list ([d (hash-ref (hash-ref reference 'diagnostic) 'random_draws)])
                (list (hash-ref d 'args) (hash-ref d 'result)))
              '(("(10438660480)" 16566282405)))

;; --- read-only checkpoints in our session ---------------------------------------
;; LIT? (77rooms.mud:1026) reaches LFCN in a dark room, which evaluates a
;; FUNCTION form and so charges the game-visible logical storage ledger: the
;; field `lit` is read only after end of input (LIT? #f), never at a
;; READSTRING entry in the middle of a run (docs/TESTING.md, "M4 scenario
;; runner").
(define (our-checkpoint s #:lit? [lit? #t])
  (define here (mdl-session-global s "HERE"))
  (define winner (mdl-session-global s "WINNER"))
  (define rug (mdl-session-call s "FIND-OBJ" "RUG"))
  (define door (mdl-session-call s "FIND-OBJ" "DOOR"))
  (define lamp (mdl-session-call s "FIND-OBJ" "LAMP"))
  (define lroom (mdl-session-call s "FIND-ROOM" "LROOM"))
  (define oflags
    (mdl-session-call s "CHTYPE" (field s door "OFLAGS") (existing-atom s "FIX")))
  (define ovison (mdl-session-global s "OVISON"))
  (define fields
   (hasheq 'here (render s (field s here "RID"))
           'rseen (render s (field s here "RSEEN?"))
           'aobjs (oids s (field s winner "AOBJS"))
           'kitchen_window (render s (mdl-session-global s "KITCHEN-WINDOW!-FLAG"))
           'rug_orand (render s (field s rug "ORAND"))
           'door_ovison (if (zero? (bitwise-and oflags ovison)) "#FALSE ()" "T")
           'door_oflags (render s oflags)
           'door_otouch (render s (field s door "OTOUCH?"))
           'trap_door (render s (mdl-session-global s "TRAP-DOOR!-FLAG"))
           'lamp_olight (render s (field s lamp "OLIGHT?"))
           'lamp_in_lroom (if (mdl-truthy? (mdl-session-call s "MEMQ" lamp (field s lroom "ROBJS")))
                              "T" "#FALSE ()")
           'raw_score (render s (mdl-session-global s "RAW-SCORE"))
           'ascore (render s (field s winner "ASCORE"))
           'moves (render s (mdl-session-global s "MOVES"))))
  (if lit? (hash-set fields 'lit (render s (mdl-session-call s "LIT?" here))) fields))

;; === every turn / every prefix, k = 0 .. 11 ========================================
(run-m4-scenario "house-cellar" commands #:checkpoint our-checkpoint
                 #:turn-checkpoint (lambda (s) (our-checkpoint s #:lit? #f))
                 #:end-only-keys '(lit))
