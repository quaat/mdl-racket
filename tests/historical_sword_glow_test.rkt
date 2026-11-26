#lang racket/base
;; M4 S5b scenario "take the sword" (frontier F4: TYPE of a DEFINEd FUNCTION in
;; SWORD 77act1.mud:1903, `<TYPE? ,SWORD-GLOW NOFFSET>`; ADR-0060). The faithful
;; run.mud path, <FLOAD "77loadall.mud"> then SAVE-IT through the host
;; top-level loop, on the fixed session clock (fixed_epoch 250776000, zone UTC;
;; ADR-0052), with the commands of tests/scenarios/sword-glow.json: the S1 path
;; into the living room, `take sword` (TAKE -> APPLY-OBJECT -> SWORD, whose
;; TYPE? sees a FUNCTION, so SWORD-DEMON's HACTION becomes the ATOM
;; SWORD-GLOW), `inventory`, the cellar path, `down` (the sword demon prints
;; the faint blue glow) and `east` into the troll room (the bright glow).
;;
;; Compared with the pinned Confusion pipe captures in
;; docs/evidence/M4/sword-glow-reference.json (SWORD-GLOW-REFERENCE.md) by the
;; shared runner tests/m4_scenario_runner.rkt (docs/TESTING.md, "M4 scenario
;; runner"), byte for byte after D1 only (the LISTEN banner and the "DONE"
;; line):
;;   * single-run mode (default): one boot fed all 13 commands; at READSTRING
;;     entry k (k = 0..13) the output equals the native prefix-k stdout up to
;;     its prompt and the read-only checkpoints equal the reference diagnostic
;;     checkpoint k (READSTRING entry k in run X1, whose game text was
;;     verified byte-identical to T1); at end of input the whole output
;;     equals T1 and the state equals end checkpoint 13. Prefix 0 is re-run
;;     per prefix: its end checkpoint differs from its READSTRING-entry
;;     checkpoint (see below);
;;   * per-prefix mode (M4_SCENARIO_MODE=per-prefix): for every prefix of k
;;     commands (k = 0..13; k = 13 is reference case T1, otherwise Pkk) the
;;     whole output equals the reference stdout and the state equals the
;;     reference END checkpoint k: the last checkpoint of the reference
;;     diagnostic run Dkk (X1 for k = 13), taken at the READSTRING that meets
;;     end of input, i.e. after the empty command ("Beg pardon?") that end of
;;     input produces in both engines, which still runs the demons (Dkk game
;;     text verified equal to Pkk, X1 to T1);
;;   * checkpoint fields: HERE, the winner's AOBJS, the sword's
;;     OROOM/OTOUCH?/OTVAL (glow level), SWORD-DEMON's HACTION and HROOM, LAMP
;;     OLIGHT?, TRAP-DOOR!-FLAG, scores and MOVES;
;;   * the reference X1 log of every TYPE? ... NOFFSET call (one, in
;;     `take sword`, on a FUNCTION, FALSE) is asserted, and the game's
;;     applicables are typed after a fresh FLOAD like probe case
;;     game-sword-glow of docs/evidence/M4/function-type-probe.json.
;;
;; Every run is guarded (no file write or delete, empty temporary cwd, game
;; directory hashes unchanged) and watchdogged (a timeout is a failure).
;; This is scenario evidence for M4, not a PLAYABLE or M4-gate claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_sword_glow_test.rkt   (exit status is authoritative)
(require rackunit racket/runtime-path racket/string racket/list json "m4_scenario_runner.rkt"
         (only-in "../mdl/loader.rkt" mdl-session-call mdl-session-global)
         (only-in "../mdl/runtime/core.rkt" mdl-atom-pname mdl-truthy?))

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler (lambda (e) (raise e)))

(define-runtime-path probe-file "../docs/evidence/M4/function-type-probe.json")
(define commands '("north" "east" "open window" "west" "west" "take sword" "inventory"
                   "take lamp" "move rug" "open trap door" "turn on lamp" "down" "east"))

;; --- scenario-specific reference checks -------------------------------------------
(define reference (m4-reference "sword-glow"))
(define ref-checks (hash-ref reference 'checks))
(define diagnostic (hash-ref reference 'diagnostic))
(define ref-checkpoints (hash-ref diagnostic 'checkpoints))
(check-equal? (length ref-checkpoints) (+ 2 (length commands)))
;; The end checkpoints (state after the end-of-input empty command) equal the
;; READSTRING-entry checkpoints, except after prefix 0: there the empty
;; command is the first turn, whose sword demon run disarms SWORD-DEMON (the
;; sword is not carried), exactly as `north` does in checkpoint 1.
(check-true (hash-ref ref-checks 'diag_prefix_game_parts_equal_prefix_game_parts))
(define ref-end-checkpoints (hash-ref reference 'end_checkpoints))
(check-equal? (length ref-end-checkpoints) (add1 (length commands)))
(for ([k (in-range 1 (add1 (length commands)))])
  (check-equal? (hash-remove (list-ref ref-end-checkpoints k) 'n)
                (hash-remove (list-ref ref-checkpoints k) 'n) (format "end ~a" k)))
(check-equal? (hash-ref (list-ref ref-end-checkpoints 0) 'sword_demon_haction) "#FALSE ()")
(check-equal? (hash-remove (hash-remove (list-ref ref-end-checkpoints 0) 'n) 'sword_demon_haction)
              (hash-remove (hash-remove (list-ref ref-checkpoints 0) 'n) 'sword_demon_haction))
;; The sword demon: armed at boot, disarmed by its first run (the sword is not
;; carried), re-armed with the ATOM by SWORD in `take sword` (checkpoint 6);
;; the glow level OTVAL becomes 1 in the cellar and 2 in the troll room.
(check-equal? (for/list ([cp ref-checkpoints])
                (list (hash-ref cp 'sword_demon_haction) (hash-ref cp 'sword_otval)))
              (append '(("SWORD-GLOW" "0"))
                      (make-list 5 '("#FALSE ()" "0"))
                      (make-list 6 '("SWORD-GLOW" "0"))
                      '(("SWORD-GLOW" "1") ("SWORD-GLOW" "2") ("SWORD-GLOW" "2"))))
;; Every TYPE? ... NOFFSET in the scenario: SWORD's test in `take sword`
;; (before checkpoint 6), on a FUNCTION, FALSE.
(check-equal? (for/list ([c (hash-ref diagnostic 'typeq_noffset)])
                (list (hash-ref c 'arg_type) (hash-ref c 'result) (hash-ref c 'before_checkpoint)))
              '(("FUNCTION" "#FALSE ()" 6)))
;; RANDOM: START's seeding call, then one draw entering the troll room.
(check-equal? (for/list ([d (hash-ref diagnostic 'random_draws)])
                (list (hash-ref d 'args) (hash-ref d 'result) (hash-ref d 'before_checkpoint)))
              '(("(10438660480)" 16566282405 0) ("()" -21802663835 13)))

;; --- read-only checkpoints in our session ---------------------------------------
;; Rendered like the reference diagnostic's PRIN1 for the values that occur:
;; FIX, ATOM (pname; the reference trailer "!-OBLIST" is stripped from its
;; side), an empty FALSE and LISTs of OIDs. Anything else is a strict error.
(define (our-checkpoint s)
  (define here (mdl-session-global s "HERE"))
  (define winner (mdl-session-global s "WINNER"))
  (define sword (mdl-session-call s "FIND-OBJ" "SWORD"))
  (define lamp (mdl-session-call s "FIND-OBJ" "LAMP"))
  (define demon (mdl-session-global s "SWORD-DEMON"))
  (define (rid r) (render s (field s r "RID")))
  (hasheq 'here (rid here)
          'aobjs (oids s (field s winner "AOBJS"))
          'sword_oroom (or-false (field s sword "OROOM") rid)
          'sword_otouch (render s (field s sword "OTOUCH?"))
          'sword_otval (render s (field s sword "OTVAL"))
          'sword_demon_haction (render s (field s demon "HACTION"))
          'sword_demon_hroom (or-false (field s demon "HROOM") rid)
          'lamp_olight (render s (field s lamp "OLIGHT?"))
          'trap_door (render s (mdl-session-global s "TRAP-DOOR!-FLAG"))
          'raw_score (render s (mdl-session-global s "RAW-SCORE"))
          'ascore (render s (field s winner "ASCORE"))
          'moves (render s (mdl-session-global s "MOVES"))))

;; === every turn / every prefix, k = 0 .. 13 ========================================
(run-m4-scenario "sword-glow" commands #:checkpoint our-checkpoint)

;; === the game's applicables after FLOAD (no SAVE-IT) =================================
;; Reference: case game-sword-glow (function-type-probe.json).
(let* ([probe (call-with-input-file probe-file read-json)]
       [pcase (findf (lambda (c) (equal? (hash-ref c 'name) "game-sword-glow"))
                     (hash-ref probe 'cases))]
       [out (hash-ref pcase 'stdout_raw)])
  (check-equal? (hash-ref probe 'interpreter_sha256_before) m4-pinned-mdli)
  (check-true (string-suffix?
               out
               (string-append "\"DONE\"\nFUNCTION\nLIST\n#FALSE ()\nWORD\nFUNCTION\nFUNCTION\n"
                              "#FALSE ()\nFUNCTION\nHACK\nSWORD-GLOW\nATOM\n0\nSWORD-GLOW\nT\nSUBR\n")))
  (define s (m4-run-load-only "game-sword-glow"))
  (define (type-of v) (mdl-atom-pname (mdl-session-call s "TYPE" v)))
  (define (g name) (mdl-session-global s name))
  (define noffset (existing-atom s "NOFFSET"))
  (check-equal? (type-of (g "SWORD-GLOW")) "FUNCTION")
  (check-equal? (mdl-atom-pname (mdl-session-call s "PRIMTYPE" (g "SWORD-GLOW"))) "LIST")
  (check-false (mdl-truthy? (mdl-session-call s "TYPE?" (g "SWORD-GLOW") noffset)))
  (check-equal? (mdl-atom-pname (mdl-session-call s "TYPEPRIM" noffset)) "WORD")
  (check-equal? (type-of (g "SWORD")) "FUNCTION")
  (check-equal? (type-of (g "ROBBER")) "FUNCTION")
  (check-false (mdl-truthy? (mdl-session-call s "TYPE?" (g "ROBBER") noffset)))
  (check-equal? (type-of (g "RDCOM")) "FUNCTION")
  (check-equal? (type-of (g "SWORD-DEMON")) "HACK")
  (check-equal? (render s (field s (g "SWORD-DEMON") "HACTION")) "SWORD-GLOW")
  (check-equal? (type-of (field s (g "SWORD-DEMON") "HACTION")) "ATOM")
  (check-equal? (render s (field s (mdl-session-call s "FIND-OBJ" "SWORD") "OTVAL")) "0")
  (check-equal? (type-of (g "FLOAD")) "SUBR")
  (printf "game-sword-glow: the game's applicables are typed as in the reference\n"))
