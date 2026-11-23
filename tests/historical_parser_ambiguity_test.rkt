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
;; (PARSER-AMBIGUITY-REFERENCE.md), exactly like
;; tests/historical_troll_combat_test.rkt:
;;   * transcript: for every prefix of k commands (k = 0..34; k = 34 is the
;;     whole scenario, reference case T1, otherwise case Pkk) our raw output
;;     equals the reference stdout byte for byte after D1 only (the LISTEN
;;     banner and the "DONE" line);
;;   * state: after each prefix run, read-only checkpoints in our session
;;     equal the reference END checkpoint k: the last checkpoint of the
;;     reference diagnostic run Dkk (X1 for k = 34), taken at the READSTRING
;;     that meets end of input, i.e. after the empty command ("Beg pardon?")
;;     that end of input produces in both engines (Dkk game text verified
;;     equal to Pkk, X1 to T1): HERE, LIT?, the winner's AOBJS, the 10 LEXV
;;     strings, PRSVEC, PARSE-WON, the five ORPHANS slots, TRAP-DOOR!-FLAG,
;;     the trap door's OVISON bit, scores and MOVES.
;;
;; Every run is guarded (no file write or delete, empty temporary cwd, game
;; directory hashes unchanged) and watchdogged (a timeout is a failure).
;; This is scenario evidence for M4, not a PLAYABLE or M4-gate claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_parser_ambiguity_test.rkt   (exit status is authoritative)
(require rackunit racket/runtime-path racket/port racket/string racket/list
         racket/file racket/path file/sha1 json
         "../mdl/loader.rkt"
         (only-in "../mdl/runtime/core.rkt" mdl-atom? mdl-atom-pname mdl-truthy?
                  mdl-string-snapshot))

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler (lambda (e) (raise e)))

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(define-runtime-path scenario-file "scenarios/parser-ambiguity.json")
(define-runtime-path reference-file "../docs/evidence/M4/parser-ambiguity-reference.json")
(unless (directory-exists? source-root)
  (error 'historical-parser-ambiguity "pinned source missing: ~a" source-root))

(define scenario (call-with-input-file scenario-file read-json))
(define reference (call-with-input-file reference-file read-json))
(define commands (hash-ref scenario 'commands))
(check-equal? commands
              '("xyzzy" "frobozz" "" "   " "inven" "inventoryxyz" "INVENTORY" "the" "mailbox"
                "take" "take it" "open brass" "take wooden mailbox" "open mailbox door mailbox"
                "open with with mailbox" "take \"leaflet\""
                "take the the the the the the the the the leaflet" "northeast" "east"
                "open window" "west" "up" "take knife" "down" "west" "move rug" "open door"
                "trap" "open door" "xyzzy" "wooden" "Take BRASS Lantern" "take all" "score"))
(check-equal? (hash-ref scenario 'fixed_epoch) 250776000)
(check-equal? (hash-ref scenario 'tz) "UTC")

;; --- the pinned reference ------------------------------------------------------
(define pinned-mdli "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789")
(check-equal? (hash-ref reference 'interpreter_sha256_before) pinned-mdli)
(check-equal? (hash-ref reference 'interpreter_sha256_after) pinned-mdli)
(check-equal? (hash-ref reference 'upstream_mdlzork_checked_out)
              "bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3")
(check-equal? (hash-ref reference 'commands) commands)
(define ref-checks (hash-ref reference 'checks))
(check-true (hash-ref ref-checks 't1_equals_t1b_bytes))
(check-true (hash-ref ref-checks 'diag_game_part_equals_t1_game_part_bytes))
(check-true (hash-ref ref-checks 'prefix_runs_consistent_with_t1))
(check-true (hash-ref ref-checks 'diag_prefix_game_parts_equal_prefix_game_parts))
(define (ref-case name)
  (or (findf (lambda (c) (equal? (hash-ref c 'name) name)) (hash-ref reference 'cases))
      (error 'ref-case "no reference case ~a" name)))
(define (lines->input lines) (apply string-append (map (lambda (l) (string-append l "\n")) lines)))
(define (prefix-case-name k)
  (if (= k (length commands))
      "T1-parser-ambiguity-pipe"
      (string-append "P" (if (< k 10) "0" "") (number->string k) "-parser-ambiguity-prefix")))
;; A reference stdout, integrity-checked against its recorded sha256 (latin-1
;; text in the JSON, CR kept), with only D1 applied.
(define (reference-transcript name lines)
  (define c (ref-case name))
  (check-equal? (hash-ref c 'mode) "pipe" name)
  (check-equal? (hash-ref c 'kind) "transcript" name)
  (check-equal? (hash-ref c 'clock) (hasheq 'epoch 250776000 'tz "UTC") name)
  (check-equal? (hash-ref c 'input)
                (string-append "<FLOAD \"77loadall.mud\">\n<SAVE-IT>\n" (lines->input lines)) name)
  (check-equal? (hash-ref c 'exit_status) 0 name)
  (check-equal? (hash-ref c 'stderr_raw) "Error: Unexpected EOF\n" name)
  (define raw (hash-ref c 'stdout_raw))
  (check-equal? (bytes->hex-string
                 (sha256-bytes (apply bytes (map char->integer (string->list raw)))))
                (hash-ref c 'stdout_sha256) name)
  (define banner "LISTENING-AT-LEVEL 1 PROCESS 1\n")
  (define after-banner
    (cadr (or (regexp-match (regexp (string-append "^.*?" (regexp-quote banner) "(.*)$")) raw)
              (error 'reference-transcript "no LISTEN banner in ~a" name))))
  (unless (= 1 (length (regexp-match* (regexp-quote "\"DONE\"\n") after-banner)))
    (error 'reference-transcript "expected one \"DONE\" line in ~a" name))
  (string-replace after-banner "\"DONE\"\n" "" #:all? #f))
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
(for ([k (in-range 0 (add1 (length commands)))])
  (check-equal? (without-n (list-ref ref-end-checkpoints k))
                (hash-set* (without-n (list-ref ref-checkpoints k))
                           'lexv empty-lexv 'parse_won "#FALSE ()")
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

;; --- guarded, watchdogged game runs ----------------------------------------------
(define original-guard (current-security-guard))
(define (tree-manifest dir0)
  (define dir (simplify-path dir0))
  (parameterize ([current-security-guard original-guard])
    (sort
     (for/list ([p (in-list (find-files file-exists? dir))])
       (list (path->string (find-relative-path dir (simplify-path p)))
             (file-size p)
             (call-with-input-file p (lambda (in) (bytes->hex-string (sha256-bytes in))))))
     string<? #:key car)))

(struct run-result (session load-report result raw events input writes cwd-after
                            manifest-before manifest-after))
(define run-limit-seconds 300)
(define (run-game lines)
  (define input (open-input-string (lines->input lines)))
  (define output (open-output-string))
  (define cwd (make-temporary-file "m4-parser-cwd-~a" 'directory))
  (define manifest-before (tree-manifest source-root))
  (define writes '())
  (define guard
    (make-security-guard
     original-guard
     (lambda (who path modes)
       (when (and path (or (memq 'write modes) (memq 'delete modes)))
         (set! writes (cons (list who path modes) writes))))
     (lambda (who host port mode) (void))))
  (define events '())
  (define session
    (make-mdl-session source-root #:input-port input #:output-port output
                      #:clock (make-fixed-mdl-clock 250776000) #:time-zone 'utc))
  (define done (make-channel))
  (define worker
    (parameterize ([current-security-guard guard] [current-directory cwd])
      (thread
       (lambda ()
         (channel-put
          done
          (with-handlers ([(lambda (v) #t) (lambda (v) (list #f v))])
            (define report (mdl-session-load! session "77loadall.mud"))
            (list report
                  (with-handlers ([(lambda (v) #t) values])
                    (mdl-session-run-interactive
                     session "SAVE-IT"
                     #:on-event (lambda (e) (set! events (cons e events))))))))))))
  (define outcome
    (or (sync/timeout run-limit-seconds done)
        (begin (kill-thread worker) (list #f 'timed-out))))
  (define cwd-after (parameterize ([current-security-guard original-guard])
                      (directory-list cwd)))
  (delete-directory/files cwd)
  (run-result session (first outcome) (second outcome) (get-output-string output)
              (reverse events) input writes cwd-after
              manifest-before (tree-manifest source-root)))

(define (check-clean-run r label)
  (check-not-false (run-result-load-report r) label)
  (when (run-result-load-report r)
    (check-equal? (hash-ref (run-result-load-report r) 'status) "PASS" label)
    (check-equal? (hash-ref (run-result-load-report r) 'completed_expressions) 1229 label))
  (check-equal? (run-result-writes r) '() label)
  (check-equal? (run-result-cwd-after r) '() label)
  (check-equal? (run-result-manifest-after r) (run-result-manifest-before r) label)
  (check-equal? (mdl-session-open-records (run-result-session r)) '() label))

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
(define (strip-trailers str) (regexp-replace* #rx"!-[A-Z]+" str ""))
(define (field s obj name) (mdl-session-call s "NTH" obj (mdl-session-global s name)))
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
;; TRNN (77defs.mud:18-19): <N==? <CHTYPE <ANDB flags bit> FIX> 0>, rendered
;; like the reference's T / #FALSE ().
(define (bit-set? s flags bit-name)
  (define w (mdl-session-call s "ANDB" flags (mdl-session-global s bit-name)))
  (if (eqv? 0 (mdl-session-call s "CHTYPE" w (mdl-session-atom s "FIX"))) "#FALSE ()" "T"))
(define (our-checkpoint s)
  (define here (mdl-session-global s "HERE"))
  (define winner (mdl-session-global s "WINNER"))
  (define orphans (mdl-session-global s "ORPHANS"))
  (define tdoor (mdl-session-call s "FIND-OBJ" "DOOR"))
  (define (or-false v f) (if (mdl-truthy? v) (f v) "#FALSE ()"))
  (hasheq 'here (render s (field s here "RID"))
          'lit (if (mdl-truthy? (mdl-session-call s "LIT?" here)) "T" "#FALSE ()")
          'aobjs (oids s (field s winner "AOBJS"))
          'lexv (paren (each s (mdl-session-global s "LEXV") (lambda (v) (render s v))))
          'prsvec (paren (each s (mdl-session-global s "PRSVEC") (lambda (v) (diag-any s v))))
          'parse_won (if (mdl-truthy? (mdl-session-call s "GASSIGNED?"
                                                        (mdl-session-atom s "PARSE-WON")))
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
(define (reference-checkpoint k)
  (for/hasheq ([(key v) (in-hash (list-ref ref-end-checkpoints k))]
               #:unless (eq? key 'n))
    (values key (strip-trailers v))))

;; === every prefix, k = 0 .. 34 =====================================================
(for ([k (in-range 0 (add1 (length commands)))])
  (define lines (take commands k))
  (define label (format "prefix ~a" k))
  (define r (run-game lines))
  (check-clean-run r label)
  (define result (run-result-result r))
  ;; Input ends after the commands: D3 input exhaustion, never a quit or a
  ;; strict failure.
  (unless (exn:fail:mdl-input-exhausted? result)
    (error 'parser-ambiguity "~a: ~a; output tail ~s" label
           (if (exn? result) (exn-message result) result)
           (let ([raw (run-result-raw r)]) (substring raw (max 0 (- (string-length raw) 300))))))
  (check-equal? (map car (run-result-events r)) '(entry-returned pass) label)
  (check-equal? (port->string (run-result-input r)) "" label)
  ;; Exact transcript (D1 only).
  (check-equal? (run-result-raw r) (reference-transcript (prefix-case-name k) lines) label)
  ;; End checkpoint k.
  (let ([ours (our-checkpoint (run-result-session r))] [ref (reference-checkpoint k)])
    (unless (equal? ours ref)
      (error 'parser-ambiguity "~a: checkpoint differs:\n ours ~s\n ref  ~s" label ours ref)))
  (printf "~a: transcript and checkpoint ~a equal the reference\n" label k))

(printf "parser-ambiguity: all ~a prefix runs match the reference (D1 only)\n"
        (add1 (length commands)))
