#lang racket/base
;; Shared driver of the M4 S9 scenarios (IMAGE, SLEEP, TIME; issues
;; #168-#170): tests/historical_mirror_bat_test.rkt and
;; tests/historical_strange_passage_test.rkt. Same protocol as
;; tests/historical_cyclops_room_test.rkt:
;;   * transcript: for every prefix of k commands (k = 0..n; k = n is the whole
;;     scenario, reference case T1, otherwise case Pkk) our raw output equals
;;     the pinned reference stdout byte for byte after D1 only (the LISTEN
;;     banner and the "DONE" line) — IMAGE's BEL bytes included;
;;   * state: after each prefix run, read-only checkpoints in our session equal
;;     the reference END checkpoint k (the last checkpoint of the diagnostic run
;;     Dkk, X1 for k = n): HERE, the winner's AOBJS/ASTRENGTH/ASTAGGERED, the
;;     cyclops's OROOM, TROLL/CYCLOPS/MAGIC/MIRROR-MUNG/CAROUSEL-FLIP/
;;     CAROUSEL-ZOOM flags, the sword's OTVAL, RAW-SCORE, ASCORE, MOVES, DEATHS;
;;   * SLEEP: every run is on the fixed session clock (non-live), with a
;;     recording fake host sleeper installed; it must never be called (SLEEP
;;     returns at once and reads no clock, decision #169).
;; Every run is guarded (no file write or delete, empty temporary cwd, game
;; directory hashes unchanged) and watchdogged (a timeout is a failure).
(require rackunit racket/runtime-path racket/port racket/string racket/list
         racket/file racket/path file/sha1 json
         "../mdl/loader.rkt"
         (only-in "../mdl/runtime/core.rkt" mdl-atom? mdl-atom-pname mdl-truthy?
                  current-mdl-sleeper))
(provide run-p0prims-scenario)

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(define-runtime-path tests-dir ".")
(define pinned-mdli "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789")
(define pinned-upstream "bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3")

(define (lines->input lines) (apply string-append (map (lambda (l) (string-append l "\n")) lines)))

;; --- guarded, watchdogged game runs ------------------------------------------------
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
                            manifest-before manifest-after sleeps))
(define run-limit-seconds 300)
(define (run-game lines)
  (define input (open-input-string (lines->input lines)))
  (define output (open-output-string))
  (define cwd (make-temporary-file "m4-p0prims-cwd-~a" 'directory))
  (define manifest-before (tree-manifest source-root))
  (define writes '())
  (define sleeps '())
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
    (parameterize ([current-security-guard guard] [current-directory cwd]
                   ;; Any call is a failure: the fixed clock is non-live.
                   [current-mdl-sleeper (lambda (s) (set! sleeps (cons s sleeps)))])
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
              manifest-before (tree-manifest source-root) (reverse sleeps)))

(define (check-clean-run r label)
  (check-not-false (run-result-load-report r) label)
  (when (run-result-load-report r)
    (check-equal? (hash-ref (run-result-load-report r) 'status) "PASS" label)
    (check-equal? (hash-ref (run-result-load-report r) 'completed_expressions) 1229 label))
  (check-equal? (run-result-writes r) '() label)
  (check-equal? (run-result-cwd-after r) '() label)
  (check-equal? (run-result-manifest-after r) (run-result-manifest-before r) label)
  (check-equal? (mdl-session-open-records (run-result-session r)) '() label)
  (check-equal? (run-result-sleeps r) '() (format "~a: the host sleeper was called" label)))

;; --- read-only checkpoints in our session ---------------------------------------------
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
(define (bit-set? s flags bit-name)
  (define w (mdl-session-call s "ANDB" flags (mdl-session-global s bit-name)))
  (if (eqv? 0 (mdl-session-call s "CHTYPE" w (mdl-session-atom s "FIX"))) "#FALSE ()" "T"))
(define (our-checkpoint s)
  (define here (mdl-session-global s "HERE"))
  (define winner (mdl-session-global s "WINNER"))
  (define sword (mdl-session-call s "FIND-OBJ" "SWORD"))
  (define cyc (mdl-session-call s "FIND-OBJ" "CYCLO"))
  (define (or-false v f) (if (mdl-truthy? v) (f v) "#FALSE ()"))
  (define (rid r) (render s (field s r "RID")))
  (define (flag name) (render s (mdl-session-global s name)))
  (hasheq 'here (rid here)
          'aobjs (oids s (field s winner "AOBJS"))
          'winner_astrength (render s (field s winner "ASTRENGTH"))
          'winner_staggered (bit-set? s (field s winner "AFLAGS") "ASTAGGERED")
          'cyclops_oroom (or-false (field s cyc "OROOM") rid)
          'troll_flag (flag "TROLL-FLAG!-FLAG")
          'cyclops_flag (flag "CYCLOPS-FLAG!-FLAG")
          'magic_flag (flag "MAGIC-FLAG!-FLAG")
          'mirror_mung (flag "MIRROR-MUNG!-FLAG")
          'carousel_flip (flag "CAROUSEL-FLIP!-FLAG")
          'carousel_zoom (flag "CAROUSEL-ZOOM!-FLAG")
          'sword_otval (render s (field s sword "OTVAL"))
          'raw_score (render s (mdl-session-global s "RAW-SCORE"))
          'ascore (render s (field s winner "ASCORE"))
          'moves (render s (mdl-session-global s "MOVES"))
          'deaths (render s (mdl-session-global s "DEATHS"))))

;; --- the scenario ------------------------------------------------------------------------
;; NAME: the scenario file stem (tests/scenarios/NAME.json, reference
;; docs/evidence/M4/NAME-reference.json, case names T1-NAME-pipe and
;; Pkk-NAME-prefix). EXPECTED-COMMANDS pins the command list. CHECK-REFERENCE
;; runs scenario-specific checks on the parsed reference before any game run.
(define (run-p0prims-scenario name expected-commands check-reference
                              #:check-prefix [check-prefix void])
  (define scenario (call-with-input-file (build-path tests-dir "scenarios" (string-append name ".json"))
                     read-json))
  (define reference (call-with-input-file
                     (build-path tests-dir 'up "docs" "evidence" "M4" (string-append name "-reference.json"))
                     read-json))
  (define commands (hash-ref scenario 'commands))
  (check-equal? commands expected-commands)
  (check-equal? (hash-ref scenario 'fixed_epoch) 250776000)
  (check-equal? (hash-ref scenario 'tz) "UTC")
  (check-equal? (hash-ref reference 'interpreter_sha256_before) pinned-mdli)
  (check-equal? (hash-ref reference 'interpreter_sha256_after) pinned-mdli)
  (check-equal? (hash-ref reference 'upstream_mdlzork_checked_out) pinned-upstream)
  (check-equal? (hash-ref reference 'commands) commands)
  (define ref-checks (hash-ref reference 'checks))
  (check-true (hash-ref ref-checks 't1_equals_t1b_bytes))
  (check-true (hash-ref ref-checks 'diag_game_part_equals_t1_game_part_bytes))
  (check-true (hash-ref ref-checks 'prefix_runs_consistent_with_t1))
  (check-true (hash-ref ref-checks 'diag_prefix_game_parts_equal_prefix_game_parts))
  (define (ref-case case-name)
    (or (findf (lambda (c) (equal? (hash-ref c 'name) case-name)) (hash-ref reference 'cases))
        (error 'ref-case "no reference case ~a" case-name)))
  (define (prefix-case-name k)
    (if (= k (length commands))
        (format "T1-~a-pipe" name)
        (format "P~a~a-~a-prefix" (if (< k 10) "0" "") k name)))
  ;; A reference stdout, integrity-checked against its recorded sha256
  ;; (latin-1 text in the JSON, CR kept), with only D1 applied.
  (define (reference-transcript case-name lines)
    (define c (ref-case case-name))
    (check-equal? (hash-ref c 'mode) "pipe" case-name)
    (check-equal? (hash-ref c 'kind) "transcript" case-name)
    (check-equal? (hash-ref c 'clock) (hasheq 'epoch 250776000 'tz "UTC") case-name)
    (check-equal? (hash-ref c 'input)
                  (string-append "<FLOAD \"77loadall.mud\">\n<SAVE-IT>\n" (lines->input lines))
                  case-name)
    (check-equal? (hash-ref c 'exit_status) 0 case-name)
    (check-equal? (hash-ref c 'stderr_raw) "Error: Unexpected EOF\n" case-name)
    (define raw (hash-ref c 'stdout_raw))
    (check-equal? (bytes->hex-string
                   (sha256-bytes (apply bytes (map char->integer (string->list raw)))))
                  (hash-ref c 'stdout_sha256) case-name)
    (define banner "LISTENING-AT-LEVEL 1 PROCESS 1\n")
    (define after-banner
      (cadr (or (regexp-match (regexp (string-append "^.*?" (regexp-quote banner) "(.*)$")) raw)
                (error 'reference-transcript "no LISTEN banner in ~a" case-name))))
    (unless (= 1 (length (regexp-match* (regexp-quote "\"DONE\"\n") after-banner)))
      (error 'reference-transcript "expected one \"DONE\" line in ~a" case-name))
    (string-replace after-banner "\"DONE\"\n" "" #:all? #f))
  (define diagnostic (hash-ref reference 'diagnostic))
  (define ref-checkpoints (hash-ref diagnostic 'checkpoints))
  (check-equal? (length ref-checkpoints) (+ 2 (length commands)))
  (define ref-end-checkpoints (hash-ref reference 'end_checkpoints))
  (check-equal? (length ref-end-checkpoints) (add1 (length commands)))
  (check-reference reference)
  (define (reference-checkpoint k)
    (for/hasheq ([(key v) (in-hash (list-ref ref-end-checkpoints k))]
                 #:unless (eq? key 'n))
      (values key (strip-trailers v))))

  (for ([k (in-range 0 (add1 (length commands)))])
    (define lines (take commands k))
    (define label (format "~a prefix ~a" name k))
    (define r (run-game lines))
    (check-clean-run r label)
    (define result (run-result-result r))
    ;; Input ends after the commands: D3 input exhaustion, never a quit or a
    ;; strict failure.
    (unless (exn:fail:mdl-input-exhausted? result)
      (error 'p0prims-scenario "~a: ~a; output tail ~s" label
             (if (exn? result) (exn-message result) result)
             (let ([raw (run-result-raw r)]) (substring raw (max 0 (- (string-length raw) 300))))))
    (check-equal? (map car (run-result-events r)) '(entry-returned pass) label)
    (check-equal? (port->string (run-result-input r)) "" label)
    (define expected (reference-transcript (prefix-case-name k) lines))
    (check-equal? (run-result-raw r) expected label)
    (check-prefix k (run-result-raw r) (run-result-session r))
    (let ([ours (our-checkpoint (run-result-session r))] [ref (reference-checkpoint k)])
      (unless (equal? ours ref)
        (error 'p0prims-scenario "~a: checkpoint differs:\n ours ~s\n ref  ~s" label ours ref)))
    (printf "~a: transcript and checkpoint ~a equal the reference\n" label k))
  (printf "~a: all ~a prefix runs match the reference (D1 only)\n" name (add1 (length commands))))
