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
;; docs/evidence/M4/top-parser-reference.json (TOP-PARSER-REFERENCE.md),
;; exactly like tests/historical_orphan_prompt_test.rkt:
;;   * transcript: for every prefix of k commands (k = 0..10; k = 10 is the
;;     whole scenario, reference case T1, otherwise case Pkk) our raw output
;;     equals the reference stdout byte for byte after D1 only (the LISTEN
;;     banner and the "DONE" line);
;;   * state: after each prefix run, read-only checkpoints in our session
;;     equal the reference diagnostic checkpoint k (taken at READSTRING entry
;;     in run X1, whose game text was verified byte-identical to T1),
;;     including the PRSVEC slots (which SPARSE's TOP returns), the PREPVEC
;;     PHRASEs it rewrites, and the 20 slots of OBJ-UV's storage, which
;;     EVERYTHING fills through BACK from <TOP ,OBJ-UV>;
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
(require rackunit racket/runtime-path racket/port racket/string racket/list
         racket/file racket/path file/sha1 json
         "../mdl/loader.rkt"
         (only-in "../mdl/runtime/core.rkt" mdl-atom? mdl-atom-pname mdl-truthy?))

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler (lambda (e) (raise e)))

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(define-runtime-path scenario-file "scenarios/top-parser.json")
(define-runtime-path reference-file "../docs/evidence/M4/top-parser-reference.json")
(define-runtime-path probe-file "../docs/evidence/M4/top-probe.json")
(unless (directory-exists? source-root)
  (error 'historical-top-parser "pinned source missing: ~a" source-root))

(define scenario (call-with-input-file scenario-file read-json))
(define reference (call-with-input-file reference-file read-json))
(define commands (hash-ref scenario 'commands))
(check-equal? commands '("open mailbox" "take leaflet" "drop leaflet in" "put all in mailbox"
                         "take all" "take leaflet" "drop all" "take all" "put leaflet in"
                         "inventory"))
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
(define (ref-case name)
  (or (findf (lambda (c) (equal? (hash-ref c 'name) name)) (hash-ref reference 'cases))
      (error 'ref-case "no reference case ~a" name)))
(define (lines->input lines) (apply string-append (map (lambda (l) (string-append l "\n")) lines)))
(define (prefix-case-name k)
  (if (= k (length commands))
      "T1-top-parser-pipe"
      (string-append "P" (if (< k 10) "0" "") (number->string k) "-top-parser-prefix")))
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
;; lines = #f: load only (no SAVE-IT), for the operand section.
(define (run-game lines)
  (define input (open-input-string (if lines (lines->input lines) "")))
  (define output (open-output-string))
  (define cwd (make-temporary-file "m4-top-cwd-~a" 'directory))
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
                  (and lines
                       (with-handlers ([(lambda (v) #t) values])
                         (mdl-session-run-interactive
                          session "SAVE-IT"
                          #:on-event (lambda (e) (set! events (cons e events)))))))))))))
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
;; "!-OBLIST" are stripped from its side), an empty FALSE and LISTs. Anything
;; else is a strict error.
(define (type-of s v) (mdl-atom-pname (mdl-session-call s "TYPE" v)))
(define (render s v)
  (cond [(exact-integer? v) (number->string v)]
        [(mdl-atom? v) (regexp-replace* #rx"#" (mdl-atom-pname v) "\\\\#")]
        [(and (equal? (type-of s v) "FALSE") (eqv? 0 (mdl-session-call s "LENGTH" v))) "#FALSE ()"]
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
  (define (or-false v f) (if (mdl-truthy? v) (f v) "#FALSE ()"))
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
(define (reference-checkpoint k)
  (for/hasheq ([(key v) (in-hash (list-ref ref-checkpoints k))]
               #:unless (eq? key 'n))
    (values key (strip-trailers v))))
;; The reference's known-object list is (leaflet !<ROBJS WHOUS>) at FLOAD;
;; WHOUS's ROBJS is (FDOOR MAILB) at checkpoint 0.
(check-equal? (hash-ref (list-ref ref-checkpoints 0) 'whous_robjs) "(FDOOR!-OBJECTS MAILB!-OBJECTS)")

;; === every prefix, k = 0 .. 10 =====================================================
(for ([k (in-range 0 (add1 (length commands)))])
  (define lines (take commands k))
  (define label (format "prefix ~a" k))
  (define r (run-game lines))
  (check-clean-run r label)
  (define result (run-result-result r))
  ;; Input ends after the commands: D3 input exhaustion, never a quit or a
  ;; strict failure.
  (check-pred exn:fail:mdl-input-exhausted? result
              (format "~a: ~a" label (if (exn? result) (exn-message result) result)))
  (check-equal? (map car (run-result-events r)) '(entry-returned pass) label)
  (check-equal? (port->string (run-result-input r)) "" label)
  ;; Exact transcript (D1 only).
  (check-equal? (run-result-raw r) (reference-transcript (prefix-case-name k) lines) label)
  ;; State checkpoint k.
  (check-equal? (our-checkpoint (run-result-session r)) (reference-checkpoint k) label)
  (printf "~a: transcript and checkpoint ~a equal the reference\n" label k))

;; === the game's own TOP operands, after FLOAD (no SAVE-IT) ========================
;; Reference: case game-top-operands (top-probe.json). <TOP ,INCHAN> is the
;; ADR-0058 deviation: the reference returns a 21-element CHANNEL, this
;; runtime refuses TOP of CHANNEL storage.
(let* ([probe (call-with-input-file probe-file read-json)]
       [pcase (findf (lambda (c) (equal? (hash-ref c 'name) "game-top-operands"))
                     (hash-ref probe 'cases))]
       [out (hash-ref pcase 'stdout_raw)])
  (check-equal? (hash-ref probe 'interpreter_sha256_before) pinned-mdli)
  (check-true (string-suffix?
               out
               (string-append "\"DONE\"\n0\nOBJECT\n20\nOBJECT\nUVECTOR\nT\n0\n5\nSTRING\nT\n"
                              "VECTOR\n3\nT\nT\nCHANNEL\n21\n()\n")))
  (define r (run-game #f))
  (check-clean-run r "operands")
  (define s (run-result-session r))
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

(printf "top-parser: all ~a prefix runs match the reference (D1 only)\n"
        (add1 (length commands)))
