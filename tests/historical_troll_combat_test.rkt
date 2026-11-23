#lang racket/base
;; M4 S6 scenario "fight the troll" (tests/scenarios/troll-combat.json). The
;; faithful run.mud path, <FLOAD "77loadall.mud"> then SAVE-IT through the host
;; top-level loop, on the fixed session clock (fixed_epoch 250776000, zone UTC;
;; ADR-0052): the sword-glow path into the troll room, `kill troll with sword`
;; three times (KILLER 77act1.mud:1699 -> BLOW 78melee.mud:377 for the hero;
;; the demon FIGHTING 78melee.mud:282 -> BLOW for the troll's counterattack;
;; TROLL 77act1.mud:360 for FIGHT!/DEAD!; PRES 78melee.mud:351 picks remarks
;; with RANDOM; MAX in the wound arithmetic 78melee.mud:447), which under the
;; fixed clock and seed pinks the troll, knocks his axe to the floor (he
;; recovers it), then kills him; then `diagnose`, `score`, `inventory`, `look`,
;; `take axe` (gone with the troll) and `east`.
;;
;; Compared with the pinned Confusion pipe captures in
;; docs/evidence/M4/troll-combat-reference.json (TROLL-COMBAT-REFERENCE.md),
;; exactly like tests/historical_sword_glow_test.rkt:
;;   * transcript: for every prefix of k commands (k = 0..22; k = 22 is the
;;     whole scenario, reference case T1, otherwise case Pkk) our raw output
;;     equals the reference stdout byte for byte after D1 only (the LISTEN
;;     banner and the "DONE" line);
;;   * state: after each prefix run, read-only checkpoints in our session
;;     equal the reference END checkpoint k: the last checkpoint of the
;;     reference diagnostic run Dkk (X1 for k = 22), taken at the READSTRING
;;     that meets end of input, i.e. after the empty command ("Beg pardon?")
;;     that end of input produces in both engines, which still runs the
;;     demons (Dkk game text verified equal to Pkk, X1 to T1): HERE, the
;;     winner's AOBJS/ASTRENGTH/ASTAGGERED, the troll's OROOM/OCAPAC/
;;     OCONTENTS/FIGHTBIT/STAGGERED, the axe's OROOM/OCAN, TROLL-FLAG!-FLAG,
;;     <1 ,OPPV>, <1 ,VILLAIN-PROBS>, CURIN's CFLAG/CTICK, the sword's OTVAL,
;;     SWORD-DEMON's HACTION, scores and MOVES.
;;
;; Every run is guarded (no file write or delete, empty temporary cwd, game
;; directory hashes unchanged) and watchdogged (a timeout is a failure).
;; This is scenario evidence for M4, not a PLAYABLE or M4-gate claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_troll_combat_test.rkt   (exit status is authoritative)
(require rackunit racket/runtime-path racket/port racket/string racket/list
         racket/file racket/path file/sha1 json
         "../mdl/loader.rkt"
         (only-in "../mdl/runtime/core.rkt" mdl-atom? mdl-atom-pname mdl-truthy?))

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler (lambda (e) (raise e)))

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(define-runtime-path scenario-file "scenarios/troll-combat.json")
(define-runtime-path reference-file "../docs/evidence/M4/troll-combat-reference.json")
(unless (directory-exists? source-root)
  (error 'historical-troll-combat "pinned source missing: ~a" source-root))

(define scenario (call-with-input-file scenario-file read-json))
(define reference (call-with-input-file reference-file read-json))
(define commands (hash-ref scenario 'commands))
(check-equal? commands '("north" "east" "open window" "west" "west" "take sword" "inventory"
                         "take lamp" "move rug" "open trap door" "turn on lamp" "down" "east"
                         "kill troll with sword" "kill troll with sword" "kill troll with sword"
                         "diagnose" "score" "inventory" "look" "take axe" "east"))
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
      "T1-troll-combat-pipe"
      (string-append "P" (if (< k 10) "0" "") (number->string k) "-troll-combat-prefix")))
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
;; The end checkpoints (state after the end-of-input empty command) equal the
;; READSTRING-entry checkpoints, except after prefix 0: there the empty
;; command is the first turn, whose sword demon run disarms SWORD-DEMON (the
;; sword is not carried), exactly as `north` does in checkpoint 1.
(for ([k (in-range 1 (add1 (length commands)))])
  (check-equal? (hash-remove (list-ref ref-end-checkpoints k) 'n)
                (hash-remove (list-ref ref-checkpoints k) 'n) (format "end ~a" k)))
(check-equal? (hash-ref (list-ref ref-end-checkpoints 0) 'sword_demon_haction) "#FALSE ()")
;; The fight in the reference state: the troll's strength (OCAPAC) 2 until
;; the first attack, 1 after the light wound (MAX 0 <- 2 1>), 0 after the
;; third (dead: removed from the room, TROLL-FLAG set, FIGHTBIT cleared);
;; the axe stays in (or returns to) the troll's OCONTENTS throughout; the
;; hero is never wounded (ASTRENGTH 0, CURIN never enabled); the glow level
;; drops to 0 once the troll is gone.
(check-equal? (for/list ([cp ref-checkpoints])
                (list (hash-ref cp 'troll_ocapac) (hash-ref cp 'troll_fighting)
                      (hash-ref cp 'troll_oroom) (hash-ref cp 'troll_flag)
                      (hash-ref cp 'sword_otval)))
              (append (make-list 12 '("2" "#FALSE ()" "MTROL!-ROOMS" "#FALSE ()" "0"))
                      '(("2" "#FALSE ()" "MTROL!-ROOMS" "#FALSE ()" "1")
                        ("2" "#FALSE ()" "MTROL!-ROOMS" "#FALSE ()" "2")
                        ("1" "T" "MTROL!-ROOMS" "#FALSE ()" "2")
                        ("1" "T" "MTROL!-ROOMS" "#FALSE ()" "2"))
                      (make-list 8 '("0" "#FALSE ()" "#FALSE ()" "T" "0"))))
(check-equal? (remove-duplicates
               (for/list ([cp ref-checkpoints])
                 (list (hash-ref cp 'troll_ocontents) (hash-ref cp 'axe_ocan)
                       (hash-ref cp 'axe_oroom) (hash-ref cp 'winner_astrength)
                       (hash-ref cp 'winner_staggered) (hash-ref cp 'curin_cflag))))
              '(("(AXE!-OBJECTS)" "TROLL!-OBJECTS" "#FALSE ()" "0" "#FALSE ()" "#FALSE ()")))
;; RANDOM: START's seeding call; FIGHTING's FIRST? test entering the troll
;; room; four draws in the first attack (BLOW and PRES for each side), three
;; in the second, two in the third, one in `look`.
(check-equal? (for/list ([d (hash-ref diagnostic 'random_draws)])
                (list (hash-ref d 'args) (hash-ref d 'result) (hash-ref d 'before_checkpoint)))
              '(("(10438660480)" 16566282405 0) ("()" -21802663835 13)
                ("()" 12914488375 14) ("()" -6577089531 14) ("()" 34210328094 14)
                ("()" 3437552668 14) ("()" 13814526739 15) ("()" -20114144995 15)
                ("()" 11990399124 15) ("()" 31711279130 16) ("()" 25894896720 16)
                ("()" 24534915165 20)))

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
  (define cwd (make-temporary-file "m4-troll-cwd-~a" 'directory))
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
;; FIX, ATOM (pname; the reference trailers "!-OBLIST" are stripped from its
;; side), an empty FALSE and LISTs of OIDs. Anything else is a strict error.
(define (render s v)
  (cond [(exact-integer? v) (number->string v)]
        [(mdl-atom? v) (mdl-atom-pname v)]
        [else
         (define type (mdl-atom-pname (mdl-session-call s "TYPE" v)))
         (cond [(and (equal? type "FALSE") (eqv? 0 (mdl-session-call s "LENGTH" v))) "#FALSE ()"]
               [else (error 'render "unexpected checkpoint value of type ~a" type)])]))
(define (strip-trailers str) (regexp-replace* #rx"!-[A-Z]+" str ""))
(define (field s obj name) (mdl-session-call s "NTH" obj (mdl-session-global s name)))
(define (oids s lst)
  (string-append
   "("
   (string-join (for/list ([i (in-range 1 (add1 (mdl-session-call s "LENGTH" lst)))])
                  (render s (field s (mdl-session-call s "NTH" lst i) "OID")))
                " ")
   ")"))
;; TRNN (77defs.mud:18-19): <N==? <CHTYPE <ANDB flags bit> FIX> 0>, rendered
;; like the reference's T / #FALSE ().
(define (bit-set? s flags bit-name)
  (define w (mdl-session-call s "ANDB" flags (mdl-session-global s bit-name)))
  (if (eqv? 0 (mdl-session-call s "CHTYPE" w (mdl-session-atom s "FIX"))) "#FALSE ()" "T"))
(define (our-checkpoint s)
  (define here (mdl-session-global s "HERE"))
  (define winner (mdl-session-global s "WINNER"))
  (define sword (mdl-session-call s "FIND-OBJ" "SWORD"))
  (define troll (mdl-session-call s "FIND-OBJ" "TROLL"))
  (define axe (mdl-session-call s "FIND-OBJ" "AXE"))
  (define demon (mdl-session-global s "SWORD-DEMON"))
  (define curin (mdl-session-global s "CURIN"))
  (define oppv-1 (mdl-session-call s "NTH" (mdl-session-global s "OPPV") 1))
  (define (or-false v f) (if (mdl-truthy? v) (f v) "#FALSE ()"))
  (define (rid r) (render s (field s r "RID")))
  (define (oid o) (render s (field s o "OID")))
  (hasheq 'here (rid here)
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
          'moves (render s (mdl-session-global s "MOVES"))))
(define (reference-checkpoint k)
  (for/hasheq ([(key v) (in-hash (list-ref ref-end-checkpoints k))]
               #:unless (eq? key 'n))
    (values key (strip-trailers v))))

;; === every prefix, k = 0 .. 22 =====================================================
(for ([k (in-range 0 (add1 (length commands)))])
  (define lines (take commands k))
  (define label (format "prefix ~a" k))
  (define r (run-game lines))
  (check-clean-run r label)
  (define result (run-result-result r))
  ;; Input ends after the commands: D3 input exhaustion, never a quit or a
  ;; strict failure.
  (unless (exn:fail:mdl-input-exhausted? result)
    (error 'troll-combat "~a: ~a; output tail ~s" label
           (if (exn? result) (exn-message result) result)
           (let ([raw (run-result-raw r)]) (substring raw (max 0 (- (string-length raw) 300))))))
  (check-equal? (map car (run-result-events r)) '(entry-returned pass) label)
  (check-equal? (port->string (run-result-input r)) "" label)
  ;; Exact transcript (D1 only).
  (check-equal? (run-result-raw r) (reference-transcript (prefix-case-name k) lines) label)
  ;; End checkpoint k.
  (let ([ours (our-checkpoint (run-result-session r))] [ref (reference-checkpoint k)])
    (unless (equal? ours ref)
      (error 'troll-combat "~a: checkpoint differs:\n ours ~s\n ref  ~s" label ours ref)))
  (printf "~a: transcript and checkpoint ~a equal the reference\n" label k))

(printf "troll-combat: all ~a prefix runs match the reference (D1 only)\n"
        (add1 (length commands)))
