#lang racket/base
;; M4 scenario 1, "enter the house and open the cellar" (S1). The faithful
;; run.mud path, <FLOAD "77loadall.mud"> then SAVE-IT through the host
;; top-level loop, on the fixed session clock (fixed_epoch 250776000, zone
;; UTC; ADR-0052), with the commands of tests/scenarios/house-cellar.json.
;;
;; Compared with the pinned Confusion pipe captures in
;; docs/evidence/M4/house-cellar-reference.json (HOUSE-CELLAR-REFERENCE.md):
;;   * transcript: for every prefix of k commands (k = 0..11; k = 11 is the
;;     whole scenario, reference case T1, otherwise case Pkk) our raw output
;;     must equal the reference stdout byte for byte after D1 only (the
;;     Confusion/LISTEN banner up to "LISTENING-AT-LEVEL 1 PROCESS 1" and the
;;     "DONE" line). That is stricter than D2 (canonical_text(ONLCR(raw)));
;;   * end of input: the reference prints "Beg pardon?", a prompt, and dies
;;     with "Error: Unexpected EOF"; we end by D3 input exhaustion;
;;   * state: after each prefix run, read-only checkpoints in our session
;;     equal the reference diagnostic checkpoint k (taken at READSTRING entry
;;     in run X1, whose game text was verified byte-identical to T1).
;;     The reference shows the end-of-input read changes no checkpoint field
;;     (checkpoints 11 and 12 are equal), so the state at our input
;;     exhaustion is comparable with checkpoint k.
;;
;; Every run is guarded (no file write or delete, empty temporary cwd, game
;; directory hashes unchanged) and watchdogged (a timeout is a failure).
;; This is scenario evidence for M4, not a PLAYABLE or M4-gate claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_house_cellar_test.rkt   (exit status is authoritative)
(require rackunit racket/runtime-path racket/port racket/string racket/list
         racket/file racket/path file/sha1 json
         "../mdl/loader.rkt"
         (only-in "../mdl/runtime/core.rkt" mdl-atom? mdl-atom-pname mdl-truthy?))

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler (lambda (e) (raise e)))

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(define-runtime-path scenario-file "scenarios/house-cellar.json")
(define-runtime-path reference-file "../docs/evidence/M4/house-cellar-reference.json")
(unless (directory-exists? source-root)
  (error 'historical-house-cellar "pinned source missing: ~a" source-root))

(define scenario (call-with-input-file scenario-file read-json))
(define reference (call-with-input-file reference-file read-json))
(define commands (hash-ref scenario 'commands))
(check-equal? commands '("north" "east" "open window" "west" "west" "take lamp" "move rug"
                         "open trap door" "turn on lamp" "down" "score"))
(check-equal? (hash-ref scenario 'fixed_epoch) 250776000)
(check-equal? (hash-ref scenario 'tz) "UTC")

;; --- the pinned reference ------------------------------------------------------
(check-equal? (hash-ref reference 'interpreter_sha256_before)
              "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789")
(check-equal? (hash-ref reference 'interpreter_sha256_after)
              (hash-ref reference 'interpreter_sha256_before))
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
      "T1-house-cellar-pipe"
      (string-append "P" (if (< k 10) "0" "") (number->string k) "-house-cellar-prefix")))
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
(define ref-checkpoints (hash-ref (hash-ref reference 'diagnostic) 'checkpoints))
(check-equal? (length ref-checkpoints) (+ 2 (length commands)))
;; The end-of-input read changes no checkpoint field (only the counter n).
(check-equal? (hash-remove (list-ref ref-checkpoints 11) 'n)
              (hash-remove (list-ref ref-checkpoints 12) 'n))
;; The only RANDOM call on the whole path is START's seeding call.
(check-equal? (for/list ([d (hash-ref (hash-ref reference 'diagnostic) 'random_draws)])
                (list (hash-ref d 'args) (hash-ref d 'result)))
              '(("(10438660480)" 16566282405)))

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
  (define cwd (make-temporary-file "m4-cellar-cwd-~a" 'directory))
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
;; FIX, ATOM (pname; the reference trailer "!-OBLIST" is stripped from its
;; side) and an empty FALSE. Anything else is a strict test error.
(define (render s v)
  (cond [(exact-integer? v) (number->string v)]
        [(mdl-atom? v) (mdl-atom-pname v)]
        [else
         (define type (mdl-atom-pname (mdl-session-call s "TYPE" v)))
         (cond [(and (equal? type "FALSE") (eqv? 0 (mdl-session-call s "LENGTH" v))) "#FALSE ()"]
               [else (error 'render "unexpected checkpoint value of type ~a" type)])]))
(define (strip-trailers str) (regexp-replace* #rx"!-[A-Z]+" str ""))
(define (field s obj name) (mdl-session-call s "NTH" obj (mdl-session-global s name)))
(define (our-checkpoint s)
  (define here (mdl-session-global s "HERE"))
  (define winner (mdl-session-global s "WINNER"))
  (define rug (mdl-session-call s "FIND-OBJ" "RUG"))
  (define door (mdl-session-call s "FIND-OBJ" "DOOR"))
  (define lamp (mdl-session-call s "FIND-OBJ" "LAMP"))
  (define lroom (mdl-session-call s "FIND-ROOM" "LROOM"))
  (define oflags
    (mdl-session-call s "CHTYPE" (field s door "OFLAGS") (mdl-session-atom s "FIX")))
  (define ovison (mdl-session-global s "OVISON"))
  (define aobjs (field s winner "AOBJS"))
  (hasheq 'here (render s (field s here "RID"))
          'rseen (render s (field s here "RSEEN?"))
          'aobjs (string-append
                  "("
                  (string-join (for/list ([i (in-range 1 (add1 (mdl-session-call s "LENGTH" aobjs)))])
                                 (render s (field s (mdl-session-call s "NTH" aobjs i) "OID")))
                               " ")
                  ")")
          'kitchen_window (render s (mdl-session-global s "KITCHEN-WINDOW!-FLAG"))
          'rug_orand (render s (field s rug "ORAND"))
          'door_ovison (if (zero? (bitwise-and oflags ovison)) "#FALSE ()" "T")
          'door_oflags (render s oflags)
          'door_otouch (render s (field s door "OTOUCH?"))
          'trap_door (render s (mdl-session-global s "TRAP-DOOR!-FLAG"))
          'lamp_olight (render s (field s lamp "OLIGHT?"))
          'lamp_in_lroom (if (mdl-truthy? (mdl-session-call s "MEMQ" lamp (field s lroom "ROBJS")))
                             "T" "#FALSE ()")
          'lit (render s (mdl-session-call s "LIT?" here))
          'raw_score (render s (mdl-session-global s "RAW-SCORE"))
          'ascore (render s (field s winner "ASCORE"))
          'moves (render s (mdl-session-global s "MOVES"))))
(define (reference-checkpoint k)
  (for/hasheq ([(key v) (in-hash (list-ref ref-checkpoints k))] #:unless (eq? key 'n))
    (values key (strip-trailers v))))

;; === every prefix, k = 0 .. 11 =====================================================
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

(printf "house-cellar: all ~a prefix runs match the reference (D1 only)\n"
        (add1 (length commands)))
