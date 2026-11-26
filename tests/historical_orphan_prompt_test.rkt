#lang racket/base
;; M4 S3 scenario "orphan prompts" (frontier F2/F2b: CHTYPE FIX -> CHARACTER
;; in FOOSTR, 77np.mud:241, reached through ORTELL 77np.mud:226 and PRSTR). The
;; faithful run.mud path, <FLOAD "77loadall.mud"> then SAVE-IT through the host
;; top-level loop, on the fixed session clock (fixed_epoch 250776000, zone UTC;
;; ADR-0052), with the commands of tests/scenarios/orphan-prompt.json:
;; `throw leaflet` prints the orphan prompt `at what?`, the answer `mailbox`
;; completes the sentence; `kill mailbox` prints `with what?`, the answer
;; `leaflet` completes it.
;;
;; Compared with the pinned Confusion pipe captures in
;; docs/evidence/M4/orphan-prompt-reference.json (ORPHAN-PROMPT-REFERENCE.md)
;; by the shared runner tests/m4_scenario_runner.rkt (docs/TESTING.md, "M4
;; scenario runner"), byte for byte after D1 only (the LISTEN banner and the
;; "DONE" line), exactly like tests/historical_mailbox_drop_test.rkt:
;;   * single-run mode (default): one boot fed all 9 commands; at READSTRING
;;     entry k (k = 0..9) the output equals the native prefix-k stdout up to
;;     its prompt and the read-only checkpoints equal the reference diagnostic
;;     checkpoint k (taken at READSTRING entry k in run X1, whose game text
;;     was verified byte-identical to T1), including the parser's ORPHANS
;;     vector and the codes of the PRSTR scratch buffer <BACK ,SCRSTR 5>,
;;     which FOOSTR fills with the CHARACTERs made by CHTYPE; at end of input
;;     the whole output equals T1 and the state equals checkpoint 9;
;;   * per-prefix mode (M4_SCENARIO_MODE=per-prefix): for every prefix of k
;;     commands (k = 0..9; k = 9 is reference case T1, otherwise Pkk) the
;;     whole output equals the reference stdout and, after end of input, the
;;     checkpoints equal diagnostic checkpoint k;
;;   * the reference X1 log of every CHTYPE to CHARACTER (argument and the
;;     command that reached it) is asserted, and the game's own PRSTR/FOOSTR
;;     are called after a fresh FLOAD and compared with probe case game-prstr
;;     of docs/evidence/M4/character-chtype-probe.json.
;;
;; Every run is guarded (no file write or delete, empty temporary cwd, game
;; directory hashes unchanged) and watchdogged (a timeout is a failure).
;; This is scenario evidence for M4, not a PLAYABLE or M4-gate claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_orphan_prompt_test.rkt   (exit status is authoritative)
(require rackunit racket/runtime-path racket/string racket/list json "m4_scenario_runner.rkt"
         (only-in "../mdl/loader.rkt" mdl-session-call mdl-session-global)
         (only-in "../mdl/runtime/core.rkt" mdl-atom-pname mdl-truthy?
                  mdl-false mdl-string-snapshot))

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler (lambda (e) (raise e)))

(define-runtime-path probe-file "../docs/evidence/M4/character-chtype-probe.json")
(define commands '("open mailbox" "take leaflet" "throw leaflet" "mailbox" "look"
                   "take leaflet" "kill mailbox" "leaflet" "inventory"))

;; --- scenario-specific reference checks -------------------------------------------
(define reference (m4-reference "orphan-prompt"))
(define ref-checkpoints (hash-ref (hash-ref reference 'diagnostic) 'checkpoints))
(check-equal? (length ref-checkpoints) (+ 2 (length commands)))
;; The end-of-input read changes no compared checkpoint field.
(check-equal? (hash-remove (list-ref ref-checkpoints 9) 'n)
              (hash-remove (list-ref ref-checkpoints 10) 'n))
;; The orphan state: set by `throw leaflet` (checkpoint 3) and `kill mailbox`
;; (checkpoint 7), consumed by the answer that follows.
(check-equal? (for/list ([cp ref-checkpoints])
                (list (hash-ref cp 'orphan_flag) (hash-ref cp 'orphan_verb)
                      (hash-ref cp 'orphan_slot1) (hash-ref cp 'orphan_prep)))
              (let ([none '("#FALSE ()" "#FALSE ()" "#FALSE ()" "#FALSE ()")])
                (list none none none
                      '("T" "THROW!-ACTIONS" "ADVER!-OBJECTS" "AT!-WORDS")
                      none none none
                      '("T" "KILL!-ACTIONS" "MAILB!-OBJECTS" "WITH!-WORDS")
                      none none none)))
;; Every CHTYPE to CHARACTER in the scenario: FOOSTR lower-casing "AT" during
;; `throw leaflet` and "WITH" during `kill mailbox` (X1 CHTYPE wrapper).
(check-equal? (for/list ([c (hash-ref (hash-ref reference 'diagnostic) 'chtype_character)])
                (list (hash-ref c 'arg) (hash-ref c 'before_checkpoint)))
              '((97 3) (116 3) (119 7) (105 7) (116 7) (104 7)))
;; RANDOM: START's seeding call, then one draw in the `look`.
(check-equal? (for/list ([d (hash-ref (hash-ref reference 'diagnostic) 'random_draws)])
                (list (hash-ref d 'args) (hash-ref d 'result) (hash-ref d 'before_checkpoint)))
              '(("(10438660480)" 16566282405 0) ("()" -21802663835 5)))

;; --- read-only checkpoints in our session ---------------------------------------
;; Rendered like the reference diagnostic's PRIN1 for the values that occur:
;; FIX, ATOM (pname; the reference trailer "!-OBLIST" is stripped from its
;; side), an empty FALSE and LISTs of OIDs or FIXes. Anything else is a strict
;; error.
(define (codes s str)
  (string-append
   "("
   (string-join (for/list ([i (in-range 1 (add1 (mdl-session-call s "LENGTH" str)))])
                  (render s (mdl-session-call s "ASCII" (mdl-session-call s "NTH" str i))))
                " ")
   ")"))
;; An ORPHANS slot that holds an OBJECT is logged by its OID (DIAG-OBJ).
(define (orphan-object s v)
  (cond [(not (mdl-truthy? v)) (render s v)]
        [(equal? (mdl-atom-pname (mdl-session-call s "TYPE" v)) "OBJECT")
         (render s (field s v "OID"))]
        [else (mdl-atom-pname (mdl-session-call s "TYPE" v))]))
(define (our-checkpoint s)
  (define orphans (mdl-session-global s "ORPHANS"))
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
          'orphan_flag (render s (field s orphans "OFLAG"))
          'orphan_verb (or-false (field s orphans "OVERB") (lambda (a) (render s (field s a "VNAME"))))
          'orphan_slot1 (orphan-object s (field s orphans "OSLOT1"))
          'orphan_prep (or-false (field s orphans "OPREP")
                                 (lambda (p) (render s (mdl-session-call s "CHTYPE" p
                                                                         (existing-atom s "ATOM")))))
          'orphan_name (render s (field s orphans "ONAME"))
          'scrstr_codes (codes s (mdl-session-call s "BACK" (mdl-session-global s "SCRSTR") 5))
          'raw_score (render s (mdl-session-global s "RAW-SCORE"))
          'ascore (render s (field s winner "ASCORE"))
          'moves (render s (mdl-session-global s "MOVES"))))

;; === every turn / every prefix, k = 0 .. 9 =========================================
(run-m4-scenario "orphan-prompt" commands #:checkpoint our-checkpoint)

;; === the game's own PRSTR and FOOSTR, after FLOAD (no SAVE-IT) ===================
;; Reference: case game-prstr (character-chtype-probe.json). PRSTR writes the
;; lower-cased SPNAME into the tail of the shared 5-character SCRSTR buffer
;; (77np.mud:230-232, 354) and returns that tail; FOOSTR keeps the first
;; character unless its third argument is FALSE.
(let* ([probe (call-with-input-file probe-file read-json)]
       [pcase (findf (lambda (c) (equal? (hash-ref c 'name) "game-prstr"))
                     (hash-ref probe 'cases))]
       [out (hash-ref pcase 'stdout_raw)])
  (check-equal? (hash-ref probe 'interpreter_sha256_before) m4-pinned-mdli)
  (check-true (string-suffix?
               out
               (string-append "\"DONE\"\n(0 0 0 0 0)\n\"with\"\n\"at\"\n(0 119 105 97 116)\n"
                              "CHARACTER\n\"mailb\"\n(109 97 105 108 98)\n\"Troll\"\n\"troll\"\n")))
  (define s (m4-run-load-only "prstr"))
  (define (scr) (codes s (mdl-session-call s "BACK" (mdl-session-global s "SCRSTR") 5)))
  (define (prep-atom name)
    (mdl-session-call s "CHTYPE" (mdl-session-call s "FIND-PREP" name) (existing-atom s "ATOM")))
  (define (text v) (mdl-string-snapshot 'orphan-test v "expected a STRING"))
  (check-equal? (scr) "(0 0 0 0 0)")
  (check-equal? (text (mdl-session-call s "PRSTR" (prep-atom "WITH"))) "with")
  (check-equal? (text (mdl-session-call s "PRSTR" (prep-atom "AT"))) "at")
  (check-equal? (scr) "(0 119 105 97 116)")
  (define mailb (field s (mdl-session-call s "FIND-OBJ" "MAILB") "OID"))
  (check-equal? (mdl-atom-pname (mdl-session-call s "TYPE"
                                                  (mdl-session-call s "NTH"
                                                                    (mdl-session-call s "PRSTR" mailb)
                                                                    1)))
                "CHARACTER")
  (check-equal? (text (mdl-session-call s "PRSTR" mailb)) "mailb")
  (check-equal? (scr) "(109 97 105 108 98)")
  (define (x5) (mdl-session-call s "ISTRING" 5 (mdl-session-call s "ASCII" 88)))
  (check-equal? (text (mdl-session-call s "FOOSTR" "TROLL" (x5))) "Troll")
  (check-equal? (text (mdl-session-call s "FOOSTR" "TROLL" (x5) (mdl-false '()))) "troll")
  (printf "prstr: the game's PRSTR/FOOSTR and SCRSTR equal the reference (game-prstr)\n"))
