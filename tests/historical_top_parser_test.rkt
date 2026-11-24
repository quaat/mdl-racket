#lang racket/base
;; M4 S4 scenario "top-parser" (issue #157; frontier item 3: TOP at
;; 77np.mud:126). The faithful run.mud path, <FLOAD "77loadall.mud"> then
;; SAVE-IT through the host top-level loop, on the fixed session clock
;; (fixed_epoch 250776000, zone UTC; ADR-0052), with the commands of
;; tests/scenarios/top-parser.json: `drop leaflet in` and `put leaflet in`
;; reach SPARSE's <TOP <PUT <BACK .PVR> 1 ...>> (dangling preposition);
;; `put all in mailbox`, `take all`, `drop all`, `take all` reach
;; EVERYTHING's (TUV <TOP .SUV>) on OBJ-UV (77rooms.mud:1283) and its
;; <==? .SUV .TUV> test.
;;
;; Compared with the pinned Confusion pipe captures in
;; docs/evidence/M4/top-parser-reference.json (TOP-PARSER-REFERENCE.md) by the
;; shared runner tests/m4_scenario_runner.rkt (docs/TESTING.md, "M4 scenario
;; runner"), byte for byte after D1 only (the LISTEN banner and the "DONE"
;; line), exactly like tests/historical_orphan_prompt_test.rkt:
;;   * single-run mode (default): one boot fed all 10 commands; at READSTRING
;;     entry k (k = 0..10) the output equals the native prefix-k stdout up to
;;     its prompt and the read-only checkpoints equal the reference diagnostic
;;     checkpoint k (taken at READSTRING entry k in run X1, whose game text
;;     was verified byte-identical to T1), including the PRSVEC slots (which
;;     SPARSE's TOP returns), the PREPVEC PHRASEs it rewrites, and the 20
;;     slots of OBJ-UV's storage, which EVERYTHING fills through BACK from
;;     <TOP ,OBJ-UV>; at end of input the whole output equals T1 and the state
;;     equals checkpoint 10;
;;   * per-prefix mode (M4_SCENARIO_MODE=per-prefix): for every prefix of k
;;     commands (k = 0..10; k = 10 is reference case T1, otherwise Pkk) the
;;     whole output equals the reference stdout and, after end of input, the
;;     checkpoints equal diagnostic checkpoint k;
;;   * the reference X1 log of every TOP call (operand and result TYPE and
;;     LENGTH, result ==? PRSVEC / the whole OBJ-UV, and the command that
;;     reached it) is asserted, and the game's own TOP operands are checked
;;     after a fresh FLOAD against probe case game-top-operands of
;;     docs/evidence/M4/top-probe.json.
;;
;; Every run is guarded (no file write or delete, empty temporary cwd, game
;; directory hashes unchanged) and watchdogged (a timeout is a failure).
;; This is scenario evidence for M4, not a PLAYABLE or M4-gate claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_top_parser_test.rkt   (exit status is authoritative)
(require rackunit racket/runtime-path racket/string racket/list json
         (except-in "m4_scenario_runner.rkt" render oids)
         (only-in "../mdl/loader.rkt" mdl-session-call mdl-session-global mdl-session-atom)
         (only-in "../mdl/runtime/core.rkt" mdl-atom? mdl-atom-pname mdl-truthy?))

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler (lambda (e) (raise e)))

(define-runtime-path probe-file "../docs/evidence/M4/top-probe.json")
(define commands '("open mailbox" "take leaflet" "drop leaflet in" "put all in mailbox"
                   "take all" "take leaflet" "drop all" "take all" "put leaflet in"
                   "inventory"))

;; --- scenario-specific reference checks -------------------------------------------
(define reference (m4-reference "top-parser"))
(define diagnostic (hash-ref reference 'diagnostic))
(define ref-checkpoints (hash-ref diagnostic 'checkpoints))
(check-equal? (length ref-checkpoints) (+ 2 (length commands)))
;; The end-of-input read changes no compared checkpoint field.
(check-equal? (hash-remove (list-ref ref-checkpoints 10) 'n)
              (hash-remove (list-ref ref-checkpoints 11) 'n))
;; Every TOP call of the scenario (X1 TOP wrapper): SPARSE's TOP during
;; `drop leaflet in` (3) and `put leaflet in` (9) returns PRSVEC itself;
;; EVERYTHING's TOP of the empty OBJ-UV view during the four `all` commands
;; returns the whole 20-slot storage.
(define sparse-top "(VECTOR 2 VECTOR 3 T #FALSE ())")
(define everything-top "(UVECTOR 0 UVECTOR 20 #FALSE () T)")
(check-equal? (for/list ([c (hash-ref diagnostic 'top_calls)])
                (list (hash-ref c 'call) (hash-ref c 'before_checkpoint)))
              (list (list sparse-top 3) (list everything-top 4) (list everything-top 5)
                    (list everything-top 7) (list everything-top 8) (list sparse-top 9)))
;; RANDOM: START's seeding call, then one draw in `put all in mailbox` (the
;; door's reply).
(check-equal? (for/list ([d (hash-ref diagnostic 'random_draws)])
                (list (hash-ref d 'args) (hash-ref d 'result) (hash-ref d 'before_checkpoint)))
              '(("(10438660480)" 16566282405 0) ("()" -21802663835 4)))

;; --- read-only checkpoints in our session ---------------------------------------
;; Rendered like the reference diagnostic's PRIN1 for the values that occur:
;; FIX, ATOM (pname, `#` escaped as PRIN1 does; the reference trailers
;; "!-OBLIST" are stripped from its side), an empty FALSE and LISTs. Anything
;; else is a strict error.
(define (type-of s v) (mdl-atom-pname (mdl-session-call s "TYPE" v)))
(define (render s v)
  (cond [(exact-integer? v) (number->string v)]
        [(mdl-atom? v) (regexp-replace* #rx"#" (mdl-atom-pname v) "\\\\#")]
        [(and (equal? (type-of s v) "FALSE") (eqv? 0 (mdl-session-call s "LENGTH" v))) "#FALSE ()"]
        [else (error 'render "unexpected checkpoint value of type ~a" (type-of s v))]))
(define (nth s v i) (mdl-session-call s "NTH" v i))
(define (each s v f)
  (for/list ([i (in-range 1 (add1 (mdl-session-call s "LENGTH" v)))]) (f (nth s v i))))
(define (paren xs) (string-append "(" (string-join xs " ") ")"))
(define (oids s lst) (paren (each s lst (lambda (o) (render s (field s o "OID"))))))
;; DIAG-ANY of the probe: OID; (PREP-as-ATOM OID) for a PHRASE; (TYPE VNAME)
;; for a VERB or ACTION; FALSE; else the TYPE.
(define (diag-any s v)
  (cond [(not (mdl-truthy? v)) (render s v)]
        [else
         (define t (type-of s v))
         (cond [(equal? t "OBJECT") (render s (field s v "OID"))]
               [(equal? t "PHRASE")
                (paren (list (render s (mdl-session-call s "CHTYPE" (nth s v 1)
                                                         (mdl-session-atom s "ATOM")))
                             (render s (field s (nth s v 2) "OID"))))]
               [(member t '("VERB" "ACTION")) (paren (list t (render s (nth s v 1))))]
               [else t])]))
;; DIAG-UVOBJ: the OID of the slot's object if it is one of the known objects
;; (the leaflet and WHOUS's ROBJS at FLOAD), else 0.
(define (uv-slot s known v)
  (or (for/first ([o (in-list known)]
                  #:when (mdl-truthy? (mdl-session-call s "==?" v o)))
        (render s (field s o "OID")))
      "0"))
(define (our-checkpoint s)
  (define here (mdl-session-global s "HERE"))
  (define winner (mdl-session-global s "WINNER"))
  (define leaf (mdl-session-call s "FIND-OBJ" "ADVER"))
  (define mbox (mdl-session-call s "FIND-OBJ" "MAILB"))
  (define whous (mdl-session-call s "FIND-ROOM" "WHOUS"))
  (define known (list leaf (mdl-session-call s "FIND-OBJ" "FDOOR") mbox))
  (define objuv (mdl-session-global s "OBJ-UV"))
  (hasheq 'here (render s (field s here "RID"))
          'aobjs (oids s (field s winner "AOBJS"))
          'whous_robjs (oids s (field s whous "ROBJS"))
          'mailbox_ocontents (oids s (field s mbox "OCONTENTS"))
          'leaflet_oroom (or-false (field s leaf "OROOM") (lambda (r) (render s (field s r "RID"))))
          'leaflet_ocan (or-false (field s leaf "OCAN") (lambda (o) (render s (field s o "OID"))))
          'prsvec (paren (each s (mdl-session-global s "PRSVEC") (lambda (v) (diag-any s v))))
          'prepvec (paren (each s (mdl-session-global s "PREPVEC") (lambda (v) (diag-any s v))))
          'objuv_length (render s (mdl-session-call s "LENGTH" objuv))
          ;; read through BACK, not TOP, so the checkpoint does not depend on
          ;; the SUBR under test
          'objuv_slots (paren (each s (mdl-session-call s "BACK" objuv 20)
                                    (lambda (v) (uv-slot s known v))))
          'raw_score (render s (mdl-session-global s "RAW-SCORE"))
          'ascore (render s (field s winner "ASCORE"))
          'moves (render s (mdl-session-global s "MOVES"))))
;; The reference's known-object list is (leaflet !<ROBJS WHOUS>) at FLOAD;
;; WHOUS's ROBJS is (FDOOR MAILB) at checkpoint 0.
(check-equal? (hash-ref (list-ref ref-checkpoints 0) 'whous_robjs) "(FDOOR!-OBJECTS MAILB!-OBJECTS)")

;; === every turn / every prefix, k = 0 .. 10 ========================================
(run-m4-scenario "top-parser" commands #:checkpoint our-checkpoint)

;; === the game's own TOP operands, after FLOAD (no SAVE-IT) ========================
;; Reference: case game-top-operands (top-probe.json). <TOP ,INCHAN> is the
;; ADR-0058 deviation: the reference returns a 21-element CHANNEL, this
;; runtime refuses TOP of CHANNEL storage.
(let* ([probe (call-with-input-file probe-file read-json)]
       [pcase (findf (lambda (c) (equal? (hash-ref c 'name) "game-top-operands"))
                     (hash-ref probe 'cases))]
       [out (hash-ref pcase 'stdout_raw)])
  (check-equal? (hash-ref probe 'interpreter_sha256_before) m4-pinned-mdli)
  (check-true (string-suffix?
               out
               (string-append "\"DONE\"\n0\nOBJECT\n20\nOBJECT\nUVECTOR\nT\n0\n5\nSTRING\nT\n"
                              "VECTOR\n3\nT\nT\nCHANNEL\n21\n()\n")))
  (define s (m4-run-load-only "operands"))
  (define (call . args) (apply mdl-session-call s args))
  (define (pname v) (mdl-atom-pname v))
  (define objuv (mdl-session-global s "OBJ-UV"))
  (define scrstr (mdl-session-global s "SCRSTR"))
  (define prsvec (mdl-session-global s "PRSVEC"))
  (check-equal? (call "LENGTH" objuv) 0)
  (check-equal? (pname (call "UTYPE" objuv)) "OBJECT")
  (check-equal? (call "LENGTH" (call "TOP" objuv)) 20)
  (check-equal? (pname (call "UTYPE" (call "TOP" objuv))) "OBJECT")
  (check-equal? (pname (call "TYPE" (call "TOP" objuv))) "UVECTOR")
  (check-true (mdl-truthy? (call "==?" (call "TOP" objuv) (call "BACK" objuv 20))))
  (check-equal? (call "LENGTH" scrstr) 0)
  (check-equal? (call "LENGTH" (call "TOP" scrstr)) 5)
  (check-equal? (pname (call "TYPE" (call "TOP" scrstr))) "STRING")
  (check-true (mdl-truthy? (call "==?" (call "TOP" scrstr) (call "BACK" scrstr 5))))
  (check-equal? (pname (call "TYPE" prsvec)) "VECTOR")
  (check-equal? (call "LENGTH" prsvec) 3)
  (check-true (mdl-truthy? (call "==?" (call "TOP" (call "REST" prsvec 1)) prsvec)))
  (check-true (mdl-truthy? (call "==?" (call "TOP" (call "REST" prsvec 2)) prsvec)))
  (check-exn #rx"TOP of CHANNEL storage is not supported \\(ADR-0058\\)"
             (lambda () (call "TOP" (mdl-session-global s "INCHAN"))))
  (printf "operands: the game's TOP operands equal the reference (game-top-operands; INCHAN refused, ADR-0058)\n"))
