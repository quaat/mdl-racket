#lang racket/base
;; M4 S7 scenario "parser rejection and ambiguity"
;; (tests/scenarios/parser-ambiguity.json). The faithful run.mud path,
;; <FLOAD "77loadall.mud"> then SAVE-IT through the host top-level loop, on the
;; fixed session clock (fixed_epoch 250776000, zone UTC; ADR-0052). RDCOM
;; (77rooms.mud:600) -> LEX (77rooms.mud:1559) -> EPARSE (77np.mud:347) ->
;; SPARSE (77np.mud:19) -> SYN-MATCH (77np.mud:144): unknown words, the
;; 5-letter truncation, an empty line (no move) and a blank line (a move), a
;; buzz word alone, a bare noun and its orphan continuation (ORFEO), `take it`
;; (IT is a buzz word), a dangling adjective, an adjective that does not fit,
;; too many objects, a double preposition, a quoted word, eleven words, a
;; truncated direction, the dark attic, and in the living room after `move
;; rug` the ambiguous `door` (GET-OBJECT 77np.mud:363 returns NEFALS):
;; `Which door?` answered by the adjective `trap`, then again, with an
;; unknown word in between, answered by `wooden`; mixed case, `take all`,
;; `score`.
;;
;; Compared with the pinned Confusion pipe captures in
;; docs/evidence/M4/parser-ambiguity-reference.json
;; (PARSER-AMBIGUITY-REFERENCE.md) by the shared runner
;; tests/m4_scenario_runner.rkt (docs/TESTING.md, "M4 scenario runner"), byte
;; for byte after D1 only (the LISTEN banner and the "DONE" line), exactly
;; like tests/historical_troll_combat_test.rkt:
;;   * single-run mode (default): one boot fed all 34 commands; at READSTRING
;;     entry k (k = 0..34) the output equals the native prefix-k stdout up to
;;     its prompt and the read-only checkpoints equal the reference diagnostic
;;     checkpoint k (READSTRING entry k in run X1), so the LEXV and PARSE-WON
;;     left by command k are compared too; at end of input the whole output
;;     equals T1 and the state equals end checkpoint 34. The end-of-input
;;     empty command's effect on LEXV and PARSE-WON (after-empty-command
;;     below, verified against every reference end checkpoint) is declared to
;;     the runner, so no prefix is re-run;
;;   * per-prefix mode (M4_SCENARIO_MODE=per-prefix): for every prefix of k
;;     commands (k = 0..34; k = 34 is reference case T1, otherwise Pkk) the
;;     whole output equals the reference stdout and the state equals the
;;     reference END checkpoint k: the last checkpoint of the reference
;;     diagnostic run Dkk (X1 for k = 34), taken at the READSTRING that meets
;;     end of input, i.e. after the empty command ("Beg pardon?") that end of
;;     input produces in both engines (Dkk game text verified equal to Pkk, X1
;;     to T1);
;;   * checkpoint fields: HERE, LIT?, the winner's AOBJS, the 10 LEXV
;;     strings, PRSVEC, PARSE-WON, the five ORPHANS slots, TRAP-DOOR!-FLAG,
;;     the trap door's OVISON bit, scores and MOVES.
;;
;; Every run is guarded (no file write or delete, empty temporary cwd, game
;; directory hashes unchanged) and watchdogged (a timeout is a failure).
;; This is scenario evidence for M4, not a PLAYABLE or M4-gate claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_parser_ambiguity_test.rkt   (exit status is authoritative)
(require rackunit racket/string racket/list
         (except-in "m4_scenario_runner.rkt" render oids)
         (only-in "../mdl/loader.rkt" mdl-session-call mdl-session-global mdl-session-atom)
         (only-in "../mdl/runtime/core.rkt" mdl-atom? mdl-atom-pname mdl-truthy?
                  mdl-string-snapshot))

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler (lambda (e) (raise e)))

(define commands
  '("xyzzy" "frobozz" "" "   " "inven" "inventoryxyz" "INVENTORY" "the" "mailbox"
    "take" "take it" "open brass" "take wooden mailbox" "open mailbox door mailbox"
    "open with with mailbox" "take \"leaflet\""
    "take the the the the the the the the the leaflet" "northeast" "east"
    "open window" "west" "up" "take knife" "down" "west" "move rug" "open door"
    "trap" "open door" "xyzzy" "wooden" "Take BRASS Lantern" "take all" "score"))

;; --- scenario-specific reference checks -------------------------------------------
(define reference (m4-reference "parser-ambiguity"))
(define diagnostic (hash-ref reference 'diagnostic))
(define ref-checkpoints (hash-ref diagnostic 'checkpoints))
(check-equal? (length ref-checkpoints) (+ 2 (length commands)))
(define ref-end-checkpoints (hash-ref reference 'end_checkpoints))
(check-equal? (length ref-end-checkpoints) (add1 (length commands)))
(define empty-lexv "(\"\" \"\" \"\" \"\" \"\" \"\" \"\" \"\" \"\" \"\")")
;; The end checkpoints (state after the end-of-input empty command) equal the
;; READSTRING-entry checkpoints, except that the empty command leaves LEXV
;; empty and PARSE-WON false (RDCOM's "Beg pardon?" branch, 77rooms.mud:641);
;; before the first command PARSE-WON is unassigned.
(define (without-n cp) (hash-remove cp 'n))
(define (after-empty-command cp) (hash-set* cp 'lexv empty-lexv 'parse_won "#FALSE ()"))
(for ([k (in-range 0 (add1 (length commands)))])
  (check-equal? (without-n (list-ref ref-end-checkpoints k))
                (after-empty-command (without-n (list-ref ref-checkpoints k)))
                (format "end ~a" k)))
(check-equal? (hash-ref (first ref-checkpoints) 'parse_won) "UNASSIGNED")
;; MOVES: every non-empty line is a move (unknown words, the blank line, the
;; rejected sentences); the empty line (k = 3) is not (RDCOM 77rooms.mud:620).
(check-equal? (for/list ([cp ref-checkpoints]) (hash-ref cp 'moves))
              (map number->string
                   (append '(0 1 2 2) (for/list ([m (in-range 3 34)]) m) '(33))))
;; LEX: 5-letter truncation, upper case, the quote skipping a slot, ten slots.
(define (lexv-at k) (hash-ref (list-ref ref-checkpoints k) 'lexv))
(for ([k '(5 6 7)])
  (check-equal? (lexv-at k) "(\"INVEN\" \"\" \"\" \"\" \"\" \"\" \"\" \"\" \"\" \"\")"))
(check-equal? (lexv-at 16) "(\"TAKE\" \"\" \"LEAFL\" \"\" \"\" \"\" \"\" \"\" \"\" \"\")")
(check-equal? (lexv-at 17)
              "(\"TAKE\" \"THE\" \"THE\" \"THE\" \"THE\" \"THE\" \"THE\" \"THE\" \"THE\" \"THE\")")
(check-equal? (lexv-at 18) "(\"NORTH\" \"\" \"\" \"\" \"\" \"\" \"\" \"\" \"\" \"\")")
;; ORPHANS: `mailbox` leaves OSLOT1 = the mailbox, which `take` consumes; the
;; `Which door?` orphan (OVERB OPEN, ONAME DOOR) survives the unknown word and
;; is consumed by the adjective answers.
(define (orphan-at k)
  (define cp (list-ref ref-checkpoints k))
  (map (lambda (f) (hash-ref cp f))
       '(orphan_flag orphan_verb orphan_slot1 orphan_prep orphan_name)))
(check-equal? (orphan-at 9) '("T" "#FALSE ()" "MAILB!-OBJECTS" "#FALSE ()" "#FALSE ()"))
(check-equal? (orphan-at 10) '("#FALSE ()" "#FALSE ()" "#FALSE ()" "#FALSE ()" "#FALSE ()"))
(for ([k '(27 29 30)])
  (check-equal? (orphan-at k) '("T" "OPEN!-ACTIONS" "#FALSE ()" "#FALSE ()" "DOOR!-OBJECTS")))
(for ([k '(28 31)])
  (check-equal? (orphan-at k) '("#FALSE ()" "#FALSE ()" "#FALSE ()" "#FALSE ()" "#FALSE ()")))
(check-equal? (for/list ([cp ref-checkpoints]) (hash-ref cp 'trap_door_flag))
              (append (make-list 28 "#FALSE ()") (make-list 8 "T")))
;; RANDOM: START's seeding call; `take` of the mailbox picks a YUKS remark
;; (PICK-ONE); `down` out of the dark attic draws WALK's <PROB 75>
;; (77rooms.mud:1063) and ROOM-INFO's <PROB 80> (77rooms.mud:523).
(check-equal? (for/list ([d (hash-ref diagnostic 'random_draws)])
                (list (hash-ref d 'args) (hash-ref d 'result) (hash-ref d 'before_checkpoint)))
              '(("(10438660480)" 16566282405 0) ("()" -21802663835 10)
                ("()" 12914488375 24) ("()" -6577089531 24)))

;; --- read-only checkpoints in our session ---------------------------------------
;; Rendered like the reference diagnostic's PRIN1 for the values that occur:
;; FIX, ATOM (pname, `#` escaped as PRIN1 does; the reference trailers
;; "!-OBLIST" are stripped from its side), an empty FALSE, STRINGs without
;; quotes or backslashes, and LISTs. Anything else is a strict error.
(define (type-of s v) (mdl-atom-pname (mdl-session-call s "TYPE" v)))
(define (render s v)
  (cond [(exact-integer? v) (number->string v)]
        [(mdl-atom? v) (regexp-replace* #rx"#" (mdl-atom-pname v) "\\\\#")]
        [(and (equal? (type-of s v) "FALSE") (eqv? 0 (mdl-session-call s "LENGTH" v))) "#FALSE ()"]
        [(and (equal? (type-of s v) "STRING")
              (not (regexp-match? #rx"[\"\\\\]" (mdl-string-snapshot 'render v "string"))))
         (string-append "\"" (mdl-string-snapshot 'render v "string") "\"")]
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
;; LIT? (77rooms.mud:1026) reaches LFCN in a dark room, which evaluates a
;; FUNCTION form and so charges the game-visible logical storage ledger: the
;; field `lit` is read only after end of input (LIT? #f), never at a
;; READSTRING entry in the middle of a run (docs/TESTING.md, "M4 scenario
;; runner").
(define (our-checkpoint s #:lit? [lit? #t])
  (define here (mdl-session-global s "HERE"))
  (define winner (mdl-session-global s "WINNER"))
  (define orphans (mdl-session-global s "ORPHANS"))
  (define tdoor (mdl-session-call s "FIND-OBJ" "DOOR"))
  (define fields
   (hasheq 'here (render s (field s here "RID"))
           'aobjs (oids s (field s winner "AOBJS"))
           'lexv (paren (each s (mdl-session-global s "LEXV") (lambda (v) (render s v))))
           'prsvec (paren (each s (mdl-session-global s "PRSVEC") (lambda (v) (diag-any s v))))
           'parse_won (if (mdl-truthy? (mdl-session-call s "GASSIGNED?"
                                                         (existing-atom s "PARSE-WON")))
                          (render s (mdl-session-global s "PARSE-WON"))
                          "UNASSIGNED")
           'orphan_flag (render s (field s orphans "OFLAG"))
           'orphan_verb (or-false (field s orphans "OVERB") (lambda (a) (render s (field s a "VNAME"))))
           'orphan_slot1 (diag-any s (field s orphans "OSLOT1"))
           'orphan_prep (or-false (field s orphans "OPREP")
                                  (lambda (p) (render s (mdl-session-call s "CHTYPE" p
                                                                          (mdl-session-atom s "ATOM")))))
           'orphan_name (render s (field s orphans "ONAME"))
           'trap_door_flag (render s (mdl-session-global s "TRAP-DOOR!-FLAG"))
           'trap_door_visible (bit-set? s (field s tdoor "OFLAGS") "OVISON")
           'raw_score (render s (mdl-session-global s "RAW-SCORE"))
           'ascore (render s (field s winner "ASCORE"))
           'moves (render s (mdl-session-global s "MOVES"))))
  (if lit?
      (hash-set fields 'lit (if (mdl-truthy? (mdl-session-call s "LIT?" here)) "T" "#FALSE ()"))
      fields))

;; === every turn / every prefix, k = 0 .. 34 ========================================
(run-m4-scenario "parser-ambiguity" commands #:checkpoint our-checkpoint
                 #:turn-checkpoint (lambda (s) (our-checkpoint s #:lit? #f))
                 #:end-only-keys '(lit)
                 #:eof-transform after-empty-command)
