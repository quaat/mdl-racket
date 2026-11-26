#lang racket/base
;; Shared driver of the M4 native-parity scenario tests (docs/TESTING.md,
;; "M4 scenario runner"; evidence docs/evidence/M4/SINGLE-RUN-RUNNER.md).
;;
;; Every scenario runs the faithful run.mud path, <FLOAD "77loadall.mud"> then
;; SAVE-IT through the host top-level loop, on the fixed session clock
;; (fixed_epoch 250776000, zone UTC; ADR-0052), and is compared with the pinned
;; Confusion captures in docs/evidence/M4/<name>-reference.json. Two modes,
;; chosen by the environment variable M4_SCENARIO_MODE:
;;
;;   single-run (default)
;;     ONE boot is fed all n commands. The host-only READSTRING observer
;;     (ADR-0061, #:input-observer of make-mdl-session) takes a snapshot at the
;;     entry of READSTRING call k (k = 0..n: k commands consumed): the output so
;;     far and the scenario's read-only state checkpoint. At entry k:
;;       * the output equals the native prefix-k stdout (D1 only) up to and
;;         including its (k+1)-th RDCOM prompt `>` (the reference's own
;;         prompt_head split; the remainder is that run's end-of-input tail);
;;       * the checkpoint equals the reference diagnostic checkpoint k (X1,
;;         taken at READSTRING entry k);
;;       * READSTRING call k consumed exactly command k+1 and its newline
;;         (k < n), or met end of input (k = n).
;;     After the run (end of input, D3): the whole output equals the native
;;     whole-scenario stdout (T1, D1 only) byte for byte, so the end-of-input
;;     tail of the full run is compared exactly, and the final state equals
;;     the end checkpoint n.
;;     End-of-input tails of shorter prefixes: from the reference alone, a
;;     prefix k < n is "standard" when its native tail is exactly
;;     "Beg pardon?\n>" and its end checkpoint equals EOF-TRANSFORM of its
;;     READSTRING-entry checkpoint (identity unless the scenario declares the
;;     effect of RDCOM's empty-command branch). Every non-standard prefix is
;;     re-run by the per-prefix protocol below (a reboot). Lost coverage, by
;;     construction: for standard prefixes k < n this runtime's own reply to
;;     the end-of-input empty command at state k is not executed (see
;;     docs/TESTING.md).
;;
;;   per-prefix (M4_SCENARIO_MODE=per-prefix; `make m4-scenarios-per-prefix`)
;;     The pre-runner protocol: one boot per prefix k = 0..n with only k
;;     commands; the whole output equals the native prefix-k stdout (D1 only)
;;     and the state after end of input equals the reference end checkpoint k
;;     (end_checkpoints when recorded, else diagnostic checkpoint k).
;;
;; Both modes report the earliest failing k and write a machine-readable
;; report artifacts/scenario-divergence/<name>-<mode>.json (directory
;; overridable with M4_SCENARIO_DIVERGENCE_DIR) before failing with a non-zero
;; exit; a passing run removes a stale report of the same name and mode.
;; Every run is guarded (no file write or delete, empty temporary cwd, game
;; directory hashes unchanged, no open RECORD, SLEEP's recording host sleeper
;; never called under the fixed clock) and watchdogged: a whole-scenario
;; wall-clock limit (M4_SCENARIO_TIMEOUT seconds) and a no-progress limit
;; between READSTRING entries (M4_SCENARIO_TURN_TIMEOUT seconds); either
;; fails with kind "timeout" and the last k reached.
;; Comparisons are byte-exact after ADR-0053 D1 only; nothing is normalised.
(require rackunit racket/runtime-path racket/port racket/string racket/list
         racket/file racket/path file/sha1 json
         "../mdl/loader.rkt" "../zork/game-files.rkt"
         (only-in "../mdl/runtime/core.rkt" mdl-atom? mdl-atom-pname mdl-truthy?
                  current-mdl-sleeper))
(provide run-m4-scenario m4-reference m4-run-load-only
         m4-source-root m4-pinned-mdli m4-pinned-upstream
         render strip-trailers field oids bit-set? or-false existing-atom
         current-m4-decl-violation-recorder m4-run-commands reference-transcript)

(define-runtime-path m4-source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(define-runtime-path tests-dir ".")
(define-runtime-path evidence-dir "../docs/evidence/M4")
(define-runtime-path default-divergence-dir "../artifacts/scenario-divergence")
(define m4-pinned-mdli "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789")
(define m4-pinned-upstream "bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3")
(define fixed-epoch 250776000)
(define standard-eof-tail "Beg pardon?\n>")

(define (lines->input lines) (apply string-append (map (lambda (l) (string-append l "\n")) lines)))

;; --- configuration (strict: an unknown value is an error) -------------------------
(define (scenario-mode)
  (define v (getenv "M4_SCENARIO_MODE"))
  (cond [(or (not v) (equal? v "") (equal? v "single-run")) 'single-run]
        [(equal? v "per-prefix") 'per-prefix]
        [else (error 'm4-scenario "M4_SCENARIO_MODE must be single-run or per-prefix, not ~s" v)]))
(define (env-seconds name default)
  (define v (getenv name))
  (cond [(or (not v) (equal? v "")) default]
        [else
         (define n (string->number v))
         (unless (and (real? n) (positive? n))
           (error 'm4-scenario "~a must be a positive number of seconds, not ~s" name v))
         n]))
(define (divergence-dir)
  (define v (getenv "M4_SCENARIO_DIVERGENCE_DIR"))
  (if (and v (not (equal? v ""))) (string->path v) default-divergence-dir))

;; --- read-only checkpoint helpers (shared by the scenario checkpoints) --------------
;; Rendered like the reference diagnostic's PRIN1 for the values that occur:
;; FIX, ATOM (pname; the reference trailers "!-OBLIST" are stripped from its
;; side), an empty FALSE. Anything else is a strict error.
(define (render s v)
  (cond [(exact-integer? v) (number->string v)]
        [(mdl-atom? v) (mdl-atom-pname v)]
        [else
         (define type (mdl-atom-pname (mdl-session-call s "TYPE" v)))
         (cond [(and (equal? type "FALSE") (eqv? 0 (mdl-session-call s "LENGTH" v))) "#FALSE ()"]
               [else (error 'render "unexpected checkpoint value of type ~a" type)])]))
(define (strip-trailers str) (regexp-replace* #rx"!-[A-Z]+" str ""))
(define (field s obj name) (mdl-session-call s "NTH" obj (mdl-session-global s name)))
(define (oids s lst #:render [rend render])
  (string-append
   "("
   (string-join (for/list ([i (in-range 1 (add1 (mdl-session-call s "LENGTH" lst)))])
                  (rend s (field s (mdl-session-call s "NTH" lst i) "OID")))
                " ")
   ")"))
;; TRNN (77defs.mud:18-19): <N==? <CHTYPE <ANDB flags bit> FIX> 0>, rendered
;; like the reference's T / #FALSE ().
(define (bit-set? s flags bit-name)
  (define w (mdl-session-call s "ANDB" flags (mdl-session-global s bit-name)))
  (if (eqv? 0 (mdl-session-call s "CHTYPE" w (existing-atom s "FIX"))) "#FALSE ()" "T"))
;; A checkpoint names an ATOM that already exists; it never interns (#199;
;; checkpoint reads are pure, docs/TESTING.md). A missing one is an error.
(define (existing-atom s name)
  (or (mdl-session-find-atom s name)
      (error 'm4-checkpoint "no ATOM ~a in the session (a checkpoint read never interns)" name)))
(define (or-false v f) (if (mdl-truthy? v) (f v) "#FALSE ()"))

;; --- diagnostic only: the attached-declaration violation sweep (M4 #196) ------------
;; #f (the default: production behaviour, no attached check evaluated, #196) or a
;; procedure (info k n session) for tests/decl_violation_sweep.rkt only. When
;; set, each game run below makes its session with make-mdl-session's host-only
;; #:decl-violation-recorder, so an attached #DECL check that would fail is
;; reported here and the run proceeds (docs/SEMANTICS.md "Diagnostic-only:
;; attached-declaration violation recorder"). INFO: the runtime's description;
;; K: READSTRING entries made so far (the violation belongs to command K,
;; 1-based; 0 = during the boot); N: the number of commands fed to this run
;; (#f for a load-only run); SESSION: the run's session (read-only use).
;; No scenario target, m4-check or production host sets it.
(define current-m4-decl-violation-recorder (make-parameter #f))

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

;; A watchdog stop: which limit ('scenario or 'turn), its seconds, and the
;; number of READSTRING entries reached.
(struct watchdog-timeout (which limit entries) #:transparent)

;; writes/sleeps: (k . detail), k = READSTRING entries reached at the time.
(struct run-result (session load-report result raw events input writes cwd-after
                            manifest-before manifest-after sleeps entries elapsed
                            output-port))

;; LINES: the commands, or #f to load only (no SAVE-IT). OBSERVER: #f or
;; (kind k info session output-port) called inside READSTRING; k is the
;; 0-based index of the READSTRING call. DEADLINE: absolute
;; current-inexact-milliseconds for the whole scenario. TURN-LIMIT: seconds
;; without a new READSTRING entry (boot to the first entry included).
(define (run-game lines #:observer [user-observer #f] #:deadline deadline #:turn-limit turn-limit
                  #:scenario-limit scenario-limit)
  (define input (open-input-string (if lines (lines->input lines) "")))
  (define output (open-output-string))
  (define cwd (make-temporary-file "m4-scenario-cwd-~a" 'directory))
  (define manifest-before (tree-manifest m4-source-root))
  (define writes '())
  (define sleeps '())
  (define entries 0)
  (define last-progress (current-inexact-milliseconds))
  (define session #f)
  (define (observer kind info)
    (case kind
      [(enter)
       (set! last-progress (current-inexact-milliseconds))
       (when user-observer (user-observer 'enter entries info session output))
       (set! entries (add1 entries))
       (set! last-progress (current-inexact-milliseconds))]
      [(complete)
       (when user-observer (user-observer 'complete (sub1 entries) info session output))]
      [else (error 'm4-scenario "unexpected READSTRING observer call ~s" kind)]))
  (define guard
    (make-security-guard
     original-guard
     (lambda (who path modes)
       (when (and path (or (memq 'write modes) (memq 'delete modes)))
         (set! writes (cons (cons entries (list who path modes)) writes))))
     (lambda (who host port mode) (void))))
  (define events '())
  (define decl-recorder (current-m4-decl-violation-recorder))
  (set! session
        (make-mdl-session m4-source-root #:input-port input #:output-port output
                          #:clock (make-fixed-mdl-clock fixed-epoch) #:time-zone 'utc
                          #:input-observer observer
                          ;; ADR-0055 amendment (#171): help/info's two files.
                          #:read-only-files zork-read-only-files
                          ;; #f unless the diagnostic sweep set it (M4 #196).
                          #:decl-violation-recorder
                          (and decl-recorder
                               (lambda (info)
                                 (decl-recorder info entries (and lines (length lines)) session)))))
  (define start (current-inexact-milliseconds))
  (define done (make-channel))
  (define worker
    (parameterize ([current-security-guard guard] [current-directory cwd]
                   ;; Any call is a failure: the fixed clock is non-live (#169).
                   [current-mdl-sleeper (lambda (s) (set! sleeps (cons (cons entries s) sleeps)))])
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
    (let loop ()
      (define now (current-inexact-milliseconds))
      (define turn-left (- (+ last-progress (* 1000.0 turn-limit)) now))
      (define total-left (- deadline now))
      (cond
        [(<= total-left 0)
         (kill-thread worker)
         (list #f (watchdog-timeout 'scenario scenario-limit entries))]
        [(<= turn-left 0)
         (kill-thread worker)
         (list #f (watchdog-timeout 'turn turn-limit entries))]
        [else (or (sync/timeout (/ (min turn-left total-left 1000.0) 1000.0) done) (loop))])))
  (define elapsed (/ (- (current-inexact-milliseconds) start) 1000.0))
  (define cwd-after (parameterize ([current-security-guard original-guard])
                      (directory-list cwd)))
  (delete-directory/files cwd)
  (run-result session (first outcome) (second outcome) (get-output-string output)
              (reverse events) input (reverse writes) cwd-after
              manifest-before (tree-manifest m4-source-root) (reverse sleeps) entries elapsed
              output))

;; A load-only session (no SAVE-IT), guarded and watchdogged, for the
;; scenario tests' post-FLOAD sections. Returns the session.
(define (m4-run-load-only label)
  (define limit (env-seconds "M4_SCENARIO_TIMEOUT" 900))
  (define r (run-game #f #:deadline (+ (current-inexact-milliseconds) (* 1000.0 limit))
                      #:turn-limit limit #:scenario-limit limit))
  (define f (or (guard-failure r 0 label) (load-failure r 0 label)))
  (when f (error 'm4-scenario "~a: ~a" label (failure-message f)))
  (run-result-session r))

;; Diagnostic only (M4 #196 targeted probes): one guarded, watchdogged boot fed
;; LINES, with no reference comparison. Returns a hash: output (the raw
;; transcript), ending (input-exhausted, quit, or the strict failure's
;; message), entries (READSTRING entries reached) and guard (#f, or the guard
;; failure's message: a file write, a sleeper call, a changed game directory),
;; session (the run's session, usable afterwards by host calls) and output-now
;; (a thunk: the session's whole output so far, including any after the run).
(define (m4-run-commands lines)
  (define limit (env-seconds "M4_SCENARIO_TIMEOUT" 900))
  (define r (run-game lines #:deadline (+ (current-inexact-milliseconds) (* 1000.0 limit))
                      #:turn-limit (env-seconds "M4_SCENARIO_TURN_TIMEOUT" 120)
                      #:scenario-limit limit))
  (define result (run-result-result r))
  (define f (or (guard-failure r (run-result-entries r) "probe") (load-failure r 0 "probe")))
  (hasheq 'output (run-result-raw r)
          'ending (cond [(exn:fail:mdl-input-exhausted? result) "input-exhausted"]
                        [(mdl-session-outcome? result)
                         (format "~a" (mdl-session-outcome-kind result))]
                        [else (result-text result)])
          'entries (run-result-entries r)
          'guard (and f (failure-message f))
          'session (run-result-session r)
          'output-now (lambda () (get-output-string (run-result-output-port r)))))

;; --- failures ------------------------------------------------------------------------
;; k: the earliest failing turn (commands consumed); kind: "transcript",
;; "checkpoint", "run-guard", "timeout", "scenario-check"; stage: where.
(struct failure (k kind stage message expected actual cp-diffs last-k) #:transparent)
(define (mk-failure k kind stage message
                    #:expected [expected #f] #:actual [actual #f]
                    #:cp-diffs [cp-diffs '()] #:last-k [last-k #f])
  (failure k kind stage message expected actual cp-diffs last-k))

(define (first-difference a b)
  (or (for/first ([i (in-range (min (string-length a) (string-length b)))]
                  #:unless (char=? (string-ref a i) (string-ref b i)))
        i)
      (and (not (= (string-length a) (string-length b))) (min (string-length a) (string-length b)))))
(define (context s i)
  (substring s (max 0 (- i 100)) (min (string-length s) (+ i 100))))
(define (cp-diffs expected actual)
  (for/list ([key (in-list (sort (remove-duplicates (append (hash-keys expected) (hash-keys actual)))
                                 symbol<?))]
             #:unless (equal? (hash-ref expected key #f) (hash-ref actual key #f)))
    (hasheq 'field (symbol->string key)
            'expected (hash-ref expected key 'null)
            'actual (hash-ref actual key 'null))))

;; The last READSTRING entry k reached, from the number of entries.
(define (last-k-reached entries) (if (zero? entries) 'null (sub1 entries)))
(define (output-tail raw) (substring raw (max 0 (- (string-length raw) 300))))
(define (result-text result)
  (cond [(exn? result) (exn-message result)]
        [else (format "~s" result)]))

;; Guard violations of a finished run. A write or sleeper call is attributed
;; to EVENT-K of the READSTRING entries reached when it happened (default: the
;; run's own k, as in a per-prefix run); the other guards, only known at the
;; end, to K-DEFAULT.
(define (open-record-list session)
  (for/list ([o (in-list (mdl-session-open-records session))])
    (list (mdl-open-record-mode o) (mdl-open-record-file-spec o) (mdl-open-record-status o))))
(define (guard-failure r k-default stage #:event-k [event-k (lambda (entries) k-default)]
                       #:open-records [open-records '()])
  (define writes (run-result-writes r))
  (define sleeps (run-result-sleeps r))
  (cond
    [(pair? writes)
     (mk-failure (event-k (car (first writes))) "run-guard" stage
                 (format "file write or delete attempted: ~s" (map cdr writes)))]
    [(pair? sleeps)
     (mk-failure (event-k (car (first sleeps))) "run-guard" stage
                 (format "the host sleeper was called under the fixed clock: ~s" (map cdr sleeps)))]
    [(pair? (run-result-cwd-after r))
     (mk-failure k-default "run-guard" stage
                 (format "the temporary cwd is not empty: ~s" (run-result-cwd-after r)))]
    [(not (equal? (run-result-manifest-after r) (run-result-manifest-before r)))
     (mk-failure k-default "run-guard" stage "the game directory changed")]
    ;; RECORD's denied OPENs (ADR-0055): none, except in a run declared to
    ;; end by the game's QUIT (FINISH -> RECORD -> QUIT), where they must be
    ;; exactly OPEN-RECORDS (mode file-spec status), in order.
    [(not (equal? (open-record-list (run-result-session r)) open-records))
     (mk-failure k-default "run-guard" stage
                 (format "RECORD OPENs ~s, expected ~s"
                         (open-record-list (run-result-session r)) open-records))]
    ;; M4 S10: every read-only file CHANNEL the game opened was CLOSEd.
    [(assq 'open (map reverse (mdl-session-file-channels (run-result-session r))))
     (mk-failure k-default "run-guard" stage
                 (format "file CHANNELs left open: ~s" (mdl-session-file-channels (run-result-session r))))]
    [else #f]))
(define (load-failure r k stage)
  (define report (run-result-load-report r))
  (define result (run-result-result r))
  (cond
    [(watchdog-timeout? result)
     ;; Stopped while processing command k+1 after READSTRING entry k: a
     ;; per-prefix run would hang at prefix k+1 = the number of entries.
     (define entries (watchdog-timeout-entries result))
     (mk-failure entries "timeout" stage
                 (format "~a limit of ~a s reached after ~a READSTRING entries"
                         (watchdog-timeout-which result) (watchdog-timeout-limit result) entries)
                 #:last-k (last-k-reached entries))]
    [(not report)
     (mk-failure k "run-guard" stage (format "FLOAD failed: ~a" (result-text result)))]
    [(not (and (equal? (hash-ref report 'status #f) "PASS")
               (eqv? (hash-ref report 'completed_expressions #f) 1229)))
     (mk-failure k "run-guard" stage (format "unexpected FLOAD report ~s" report))]
    [else #f]))
;; The end of a scenario run. ENDING 'eof (the default for every prefix): D3
;; input exhaustion (never a quit or a strict failure). ENDING 'quit (only a
;; prefix the scenario declares with #:quit-prefixes): the game's own QUIT,
;; i.e. the host loop's outcome of kind 'quit with no MDL ERROR signalled
;; (ADR-0054), never input exhaustion or a strict failure. Both: the host
;; loop's events, and the input left unread is exactly UNREAD ("" for 'eof).
(define (ending-failure r k stage [ending 'eof] [unread ""])
  (define result (run-result-result r))
  (cond
    [(and (eq? ending 'eof) (not (exn:fail:mdl-input-exhausted? result)))
     (mk-failure k "run-guard" stage
                 (format "the run did not end by input exhaustion: ~a; output tail ~s"
                         (result-text result) (output-tail (run-result-raw r))))]
    [(and (eq? ending 'quit)
          (not (and (mdl-session-outcome? result)
                    (eq? (mdl-session-outcome-kind result) 'quit)
                    (null? (mdl-session-outcome-mdl-errors result)))))
     (mk-failure k "run-guard" stage
                 (format "the run did not end by the game's QUIT (declared quit ending): ~a; output tail ~s"
                         (if (mdl-session-outcome? result)
                             (format "outcome ~a, MDL errors ~s" (mdl-session-outcome-kind result)
                                     (mdl-session-outcome-mdl-errors result))
                             (result-text result))
                         (output-tail (run-result-raw r))))]
    [(not (memq ending '(eof quit))) (error 'm4-scenario "unknown ending ~s" ending)]
    [(not (equal? (map car (run-result-events r)) '(entry-returned pass)))
     (mk-failure k "run-guard" stage (format "host loop events ~s" (map car (run-result-events r))))]
    [(not (equal? (port->string (run-result-input r)) unread))
     (mk-failure k "run-guard" stage
                 (if (equal? unread "")
                     "input was not fully consumed"
                     (format "the input left unread differs from ~s" unread)))]
    [else #f]))

;; --- the reference ---------------------------------------------------------------
;; A reference stdout, integrity-checked against its recorded sha256 (latin-1
;; text in the JSON, CR kept), with only D1 applied (the Confusion/LISTEN
;; banner up to "LISTENING-AT-LEVEL 1 PROCESS 1" and the "DONE" line).
;; ENDING: how the native run ended, from its stderr: 'eof (Confusion's
;; "Error: Unexpected EOF" at the READSTRING after the end of input) or 'quit
;; (the game's QUIT: empty stderr); exit status 0 either way.
(define (reference-transcript c lines [ending 'eof])
  (define name (hash-ref c 'name))
  (check-equal? (hash-ref c 'mode) "pipe" name)
  (check-equal? (hash-ref c 'kind) "transcript" name)
  (check-equal? (hash-ref c 'clock) (hasheq 'epoch fixed-epoch 'tz "UTC") name)
  (check-equal? (hash-ref c 'input)
                (string-append "<FLOAD \"77loadall.mud\">\n<SAVE-IT>\n" (lines->input lines)) name)
  (check-equal? (hash-ref c 'exit_status) 0 name)
  (check-equal? (hash-ref c 'stderr_raw)
                (case ending
                  [(eof) "Error: Unexpected EOF\n"]
                  [(quit) ""]
                  [else (error 'reference-transcript "unknown ending ~s" ending)])
                name)
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

(define reference-cache (make-hash))
;; The parsed reference JSON of scenario NAME (for scenario-specific checks).
(define (m4-reference name)
  (hash-ref! reference-cache name
             (lambda ()
               (call-with-input-file (build-path evidence-dir (string-append name "-reference.json"))
                 read-json))))

;; The prompt split (the probe's prompt_head): the text through the (k+1)-th
;; RDCOM prompt `>`. Strict: the stdout of prefix k must hold exactly k+2
;; prompts (one per READSTRING entry, the end-of-input one included), or the
;; split is ambiguous and this scenario cannot use the single-run mode.
;; SPLIT (ADR-0062 amendment, M4 S10): 'any counts every `>` (the default);
;; 'line-initial counts only a `>` at the start of the text or after a LF, for
;; a scenario whose game text itself holds `>` (help-info). The count check is
;; the same in both.
;; ENTRY-PROMPTS (M4 Phase 2 death scenarios, opt-in; default none): a hash
;; READSTRING entry index -> prompt text, for the entries that are not RDCOM
;; reads. JIGS-UP's "Do you want me to try to patch you?" is printed without a
;; CRLF and answered through YES/NO's READSTRING (77defs.mud:431), with no `>`.
;; The head of such an entry ends after the first occurrence of its text
;; after the previous entry's head, and no counted `>` may lie in between.
;; COUNT: the number of counted `>` the text must hold (default k + 2, one per
;; entry 0..k+1; see prompt-count), strict as before.
(define (prompt-head text k label [split 'any]
                     #:entry-prompts [entry-prompts (hasheqv)] #:count [count (+ k 2)])
  (define positions
    (for/list ([c (in-string text)] [i (in-naturals)]
               #:when (and (char=? c #\>)
                           (case split
                             [(any) #t]
                             [(line-initial) (or (zero? i) (char=? (string-ref text (sub1 i)) #\newline))]
                             [else (error 'm4-scenario "prompt split must be any or line-initial, not ~s" split)])))
      i))
  (unless (= (length positions) count)
    (error 'm4-scenario "~a: expected ~a prompts `>` in the reference stdout, found ~a; the prompt split is ambiguous (use M4_SCENARIO_MODE=per-prefix)"
           label count (length positions)))
  (define end
    (for/fold ([pos 0]) ([j (in-range 0 (add1 k))])
      (define literal (hash-ref entry-prompts j #f))
      (cond
        [literal
         (define m (regexp-match-positions (regexp-quote literal) text pos))
         (unless (and m (not (for/or ([p (in-list positions)]) (and (<= pos p) (< p (caar m))))))
           (error 'm4-scenario "~a: the prompt ~s of READSTRING entry ~a is not the next prompt in the reference stdout"
                  label literal j))
         (cdar m)]
        [else
         (define p (for/first ([p (in-list positions)] #:when (>= p pos)) p))
         (unless p
           (error 'm4-scenario "~a: no prompt `>` for READSTRING entry ~a in the reference stdout" label j))
         (add1 p)])))
  (substring text 0 end))

;; The number of counted `>` in the native stdout of a prefix whose last
;; observed READSTRING entry is LAST-ENTRY: one per entry 0..LAST-ENTRY that
;; is not in ENTRY-PROMPTS, plus, when the prefix ENDING is 'eof, the prompt
;; of the READSTRING that dies at end of input (it follows the empty command
;; of entry LAST-ENTRY, so it is RDCOM's `>`). Without ENTRY-PROMPTS and
;; with an 'eof ending: LAST-ENTRY + 2.
(define (prompt-count last-entry ending entry-prompts)
  (+ (for/sum ([j (in-range 0 (add1 last-entry))]) (if (hash-has-key? entry-prompts j) 0 1))
     (case ending [(eof) 1] [(quit) 0] [else (error 'm4-scenario "unknown ending ~s" ending)])))

;; The single-run split of the native prefix-k stdout P_k: its head, through
;; the prompt of READSTRING entry k (prompt-head, strict on the prompt count),
;; compared with this runtime's output at READSTRING entry k; the rest is the
;; end-of-input tail, classified by non-standard-eof-tails. That every head is
;; a prefix of T1 is implied by the run itself (outputs only grow, and the
;; whole output must equal T1), so a reference inconsistency there surfaces as
;; a failing turn, never as a silent pass.
(define (eof-split pk k label [split 'any]
                   #:entry-prompts [entry-prompts (hasheqv)] #:count [count (+ k 2)])
  (prompt-head pk k label split #:entry-prompts entry-prompts #:count count))

;; The prefixes k < n whose native end-of-input tail is not standard: the tail
;; text is not exactly "Beg pardon?\n>", or the end checkpoint differs from the
;; (transformed) READSTRING-entry checkpoint. TAIL, END-CP, ENTRY-CP: k ->
;; value. KS: the prefixes to classify (default 0..n-1). IGNORE-KEYS: fields
;; removed from both checkpoints (hasheqs) for this classification only
;; (#:eof-classification-ignore-keys of run-m4-scenario). Returns a list of
;; (k reason ...), ascending.
(define (non-standard-eof-tails n tail end-cp0 entry-cp0 #:ks [ks (range n)]
                                #:ignore-keys [ignore-keys '()])
  (define (strip h) (if (null? ignore-keys)
                        h
                        (for/hasheq ([(key v) (in-hash h)] #:unless (memq key ignore-keys))
                          (values key v))))
  (define (end-cp k) (strip (end-cp0 k)))
  (define (entry-cp k) (strip (entry-cp0 k)))
  (for*/list ([k (in-list ks)]
              #:when (< k n)
              [reasons (in-value
                        (append (if (equal? (tail k) standard-eof-tail)
                                    '()
                                    (list (format "tail ~s" (tail k))))
                                (if (equal? (end-cp k) (entry-cp k))
                                    '()
                                    (list (format "end checkpoint fields ~a"
                                                  (map (lambda (d) (hash-ref d 'field))
                                                       (cp-diffs (end-cp k) (entry-cp k))))))))]
              #:when (pair? reasons))
    (cons k reasons)))

;; --- the scenario ----------------------------------------------------------------
;; NAME: the scenario stem (tests/scenarios/NAME.json, reference
;; docs/evidence/M4/NAME-reference.json, cases T1-NAME-pipe, Pkk-NAME-prefix).
;; EXPECTED-COMMANDS pins the command list. CHECKPOINT: session -> hasheq of
;; rendered fields (read-only). IGNORE-KEYS: reference checkpoint keys not
;; compared (always n). EOF-TRANSFORM: the reference-verified effect of the
;; end-of-input empty command on a READSTRING-entry checkpoint (raw reference
;; values), used only to classify end-of-input tails as standard. CHECK-TURN:
;; (k transcript) -> any, a scenario-specific check of the transcript compared
;; at turn k (single-run: the output at READSTRING entry k; per-prefix and
;; reboots: the whole prefix-k output).
;; END-ONLY-KEYS / TURN-CHECKPOINT: fields whose read evaluates game code that
;; allocates (e.g. LIT? -> LFCN evaluates a FUNCTION form, which charges the
;; game-visible logical storage ledger, ADR-0044) must not be read in the
;; middle of a run. TURN-CHECKPOINT (session -> hasheq) is then the
;; checkpoint without exactly those keys; it is what is read at READSTRING
;; entries, while CHECKPOINT (all keys) is read only after end of input (the
;; single run's k = n, reboots, per-prefix runs). The reference is compared
;; without END-ONLY-KEYS at READSTRING entries, so a missing or extra key is
;; still a failure.
;; ENTRY-PROMPTS (opt-in, M4 Phase 2 death scenarios; ADR-0062 amendment): the
;; READSTRING entries whose prompt is not RDCOM's `>` (prompt-head); the
;; reference records the same map (`entry_prompts`).
;; QUIT-PREFIXES / QUIT-OPEN-RECORDS (opt-in, same amendment): the prefixes k
;; (0..n; n is the whole scenario) whose run ends by the game's own QUIT
;; (FINISH -> RECORD -> QUIT) instead of end of input (D3); the reference
;; records every prefix's native ending (`endings`, from its stderr) and they
;; must agree. Such a run must end with the host loop's 'quit outcome and no
;; MDL ERROR, leave exactly the input after the quitting answer unread, and
;; record exactly QUIT-OPEN-RECORDS (RECORD's denied OPENs, ADR-0055); every
;; other run must still end by D3 and record no OPEN. The default (no quit
;; prefix, no entry prompt) is the unchanged protocol of every other scenario.
(define (run-m4-scenario name expected-commands
                         #:checkpoint checkpoint
                         #:turn-checkpoint [turn-checkpoint checkpoint]
                         ;; #:eof-classification-ignore-keys: fields left out
                         ;; only when classifying which prefixes have a
                         ;; non-standard end-of-input tail (and are re-run);
                         ;; still compared at every READSTRING entry, at the
                         ;; end and in per-prefix mode (ADR-0062 amendment).
                         #:end-only-keys [end-only-keys '()]
                         #:ignore-keys [ignore-keys '()]
                         #:eof-classification-ignore-keys [eof-classification-ignore-keys '()]
                         #:eof-transform [eof-transform values]
                         #:check-turn [check-turn void]
                         #:prompt-split [prompt-split 'any]
                         #:entry-prompts [entry-prompts (hasheqv)]
                         #:quit-prefixes [quit-prefixes '()]
                         #:quit-open-records [quit-open-records '()])
  (unless (eq? (null? end-only-keys) (eq? turn-checkpoint checkpoint))
    (error 'm4-scenario "#:end-only-keys and #:turn-checkpoint must be given together"))
  (unless (and (list? eof-classification-ignore-keys) (andmap symbol? eof-classification-ignore-keys)
               (equal? eof-classification-ignore-keys (remove-duplicates eof-classification-ignore-keys)))
    (error 'm4-scenario "#:eof-classification-ignore-keys must be a list of distinct field symbols, not ~s"
           eof-classification-ignore-keys))
  ;; An end-only key is not compared at READSTRING entries, so it cannot also
  ;; be a classification key, which promises comparison at every entry
  ;; (independent review).
  (for ([key (in-list eof-classification-ignore-keys)])
    (when (memq key end-only-keys)
      (error 'm4-scenario "~a cannot be both an end-only key and an end-of-input classification key" key)))
  (unless (memq prompt-split '(any line-initial))
    (error 'm4-scenario "#:prompt-split must be 'any or 'line-initial, not ~s" prompt-split))
  (unless (and (hash? entry-prompts)
               (for/and ([(j p) (in-hash entry-prompts)])
                 (and (exact-nonnegative-integer? j) (string? p) (positive? (string-length p))
                      (not (regexp-match? #rx">" p)))))
    (error 'm4-scenario "#:entry-prompts must map entry indexes to non-empty prompt texts without `>`, not ~s"
           entry-prompts))
  (unless (and (list? quit-prefixes) (andmap exact-nonnegative-integer? quit-prefixes)
               (equal? quit-prefixes (remove-duplicates quit-prefixes)))
    (error 'm4-scenario "#:quit-prefixes must be a list of distinct prefix lengths, not ~s" quit-prefixes))
  (unless (eq? (null? quit-prefixes) (null? quit-open-records))
    (error 'm4-scenario "#:quit-prefixes and #:quit-open-records must be given together"))
  (unless (and (list? quit-open-records)
               (andmap (lambda (o) (and (list? o) (= 3 (length o)) (string? (first o))
                                        (string? (second o)) (exact-integer? (third o))))
                       quit-open-records))
    (error 'm4-scenario "#:quit-open-records must be a list of (mode file-spec status), not ~s"
           quit-open-records))
  (parameterize ([current-check-handler raise])
    (run-m4-scenario* name expected-commands checkpoint turn-checkpoint end-only-keys
                      (cons 'n ignore-keys) eof-classification-ignore-keys eof-transform
                      check-turn prompt-split entry-prompts quit-prefixes quit-open-records)))

(define (run-m4-scenario* name expected-commands checkpoint turn-checkpoint end-only-keys
                          ignore-keys eof-classification-ignore-keys eof-transform check-turn prompt-split
                          entry-prompts quit-prefixes quit-open-records)
  (unless (directory-exists? m4-source-root)
    (error 'm4-scenario "pinned source missing: ~a" m4-source-root))
  (define mode (scenario-mode))
  ;; A report left by an earlier local run never sits beside a new result,
  ;; including a failure raised before any turn is compared.
  (let ([stale (build-path (divergence-dir) (format "~a-~a.json" name mode))])
    (when (file-exists? stale) (delete-file stale)))
  (define scenario-limit (env-seconds "M4_SCENARIO_TIMEOUT" (if (eq? mode 'per-prefix) 3600 900)))
  (define turn-limit (env-seconds "M4_SCENARIO_TURN_TIMEOUT" 120))
  (define started (current-inexact-milliseconds))
  (define deadline (+ started (* 1000.0 scenario-limit)))

  ;; --- reference preparation (no game run) ---
  (define scenario (call-with-input-file (build-path tests-dir "scenarios" (string-append name ".json"))
                     read-json))
  (define reference (m4-reference name))
  (define commands (hash-ref scenario 'commands))
  (define n (length commands))
  (check-equal? commands expected-commands)
  (check-equal? (hash-ref scenario 'fixed_epoch) fixed-epoch)
  (check-equal? (hash-ref scenario 'tz) "UTC")
  ;; The test's declarations must equal the scenario file's (independent
  ;; review): not only indirectly through the reference generated from it.
  (check-equal? (for/hasheqv ([(key v) (in-hash (hash-ref scenario 'entry_prompts (hasheq)))])
                  (values (string->number (symbol->string key)) v))
                entry-prompts "scenario entry_prompts")
  (check-equal? (sort (hash-ref scenario 'quit_prefixes '()) <) (sort quit-prefixes <)
                "scenario quit_prefixes")
  (check-equal? (hash-ref reference 'interpreter_sha256_before) m4-pinned-mdli)
  (check-equal? (hash-ref reference 'interpreter_sha256_after) m4-pinned-mdli)
  (check-equal? (hash-ref reference 'upstream_mdlzork_checked_out) m4-pinned-upstream)
  (check-equal? (hash-ref reference 'commands) commands)
  ;; The reference records the split its capture used (help-info); the
  ;; scenario must declare the same one. A reference without it used 'any.
  (check-equal? (hash-ref reference 'prompt_split "any") (symbol->string prompt-split))
  (define ref-checks (hash-ref reference 'checks))
  (check-true (hash-ref ref-checks 't1_equals_t1b_bytes))
  (check-true (hash-ref ref-checks 'diag_game_part_equals_t1_game_part_bytes))
  (check-true (hash-ref ref-checks 'prefix_runs_consistent_with_t1))
  (define has-end-checkpoints? (hash-has-key? reference 'end_checkpoints))
  ;; A quit prefix's end state is the native state at QUIT, which only
  ;; end_checkpoints record; without them end-cp would fall back to the
  ;; READSTRING-entry checkpoint (independent review).
  (when (pair? quit-prefixes)
    (check-true has-end-checkpoints? "a scenario with quit prefixes needs end_checkpoints"))
  (when has-end-checkpoints?
    (check-true (hash-ref ref-checks 'diag_prefix_game_parts_equal_prefix_game_parts)))
  ;; Declared entry prompts and endings equal the reference's (a reference
  ;; without them has none: every entry is `>`, every prefix ends by D3).
  (for ([k (in-list quit-prefixes)])
    (unless (<= k n) (error 'm4-scenario "quit prefix ~a is beyond the ~a commands" k n)))
  (check-equal? (for/hasheqv ([(j p) (in-hash (hash-ref reference 'entry_prompts (hasheq)))])
                  (values (string->number (symbol->string j)) p))
                entry-prompts "entry_prompts")
  (define (ending-of k) (if (memv k quit-prefixes) 'quit 'eof))
  (check-equal? (hash-ref reference 'endings (for/list ([k (in-range 0 (add1 n))]) "eof"))
                (for/list ([k (in-range 0 (add1 n))]) (symbol->string (ending-of k)))
                "endings")
  (define cases (for/hash ([c (in-list (hash-ref reference 'cases))]) (values (hash-ref c 'name) c)))
  (define (prefix-case-name k)
    (if (= k n)
        (format "T1-~a-pipe" name)
        (format "P~a~a-~a-prefix" (if (< k 10) "0" "") k name)))
  ;; P_k: the native stdout of prefix k (D1 only); P_n is T1.
  (define transcripts
    (for/vector ([k (in-range 0 (add1 n))])
      (reference-transcript (hash-ref cases (prefix-case-name k)
                                      (lambda () (error 'm4-scenario "no reference case ~a"
                                                        (prefix-case-name k))))
                            (take commands k)
                            (ending-of k))))
  ;; X1's checkpoints: one per READSTRING entry 0..q of the whole run, then
  ;; its end state (the entry that dies at end of input, or the state at
  ;; QUIT). q = n unless the whole run ends by QUIT, at entry q <= n.
  (define diag-checkpoints (hash-ref (hash-ref reference 'diagnostic) 'checkpoints))
  (define q (- (length diag-checkpoints) 2))
  (if (eq? (ending-of n) 'eof)
      (check-equal? (length diag-checkpoints) (+ 2 n))
      (check-true (<= 0 q n) (format "X1 checkpoint count ~a" (length diag-checkpoints))))
  ;; The last READSTRING entry this runtime observes in the run of prefix k:
  ;; end of input, k (the READSTRING after it dies before its entry); QUIT,
  ;; the entry whose answer quit (q, or k when that answer met end of input).
  (define (last-entry k) (if (eq? (ending-of k) 'eof) k (min k q)))
  ;; The input a run of prefix k leaves unread: none at end of input; after
  ;; a QUIT at entry e, the commands after command e+1.
  (define (unread-input k)
    (if (eq? (ending-of k) 'eof)
        ""
        (lines->input (drop (take commands k) (min k (add1 (last-entry k)))))))
  (define (expected-open-records k) (if (eq? (ending-of k) 'quit) quit-open-records '()))
  (when has-end-checkpoints?
    (check-equal? (length (hash-ref reference 'end_checkpoints)) (add1 n)))
  (define (raw-cp h) (for/hasheq ([(key v) (in-hash h)] #:unless (memq key ignore-keys))
                       (values key v)))
  (define (expected-cp h) (for/hasheq ([(key v) (in-hash (raw-cp h))])
                            (values key (strip-trailers v))))
  ;; READSTRING-entry checkpoint k (X1) and the end checkpoint k used by the
  ;; per-prefix protocol (end_checkpoints when recorded, else checkpoint k).
  (define (entry-cp k) (list-ref diag-checkpoints k))
  ;; What is compared at READSTRING entry k: checkpoint k without END-ONLY-KEYS.
  (define (expected-turn-cp k)
    (for/hasheq ([(key v) (in-hash (expected-cp (entry-cp k)))] #:unless (memq key end-only-keys))
      (values key v)))
  (for ([key (in-list end-only-keys)])
    (unless (hash-has-key? (expected-cp (entry-cp 0)) key)
      (error 'm4-scenario "end-only key ~a is not a reference checkpoint field" key)))
  (when (pair? end-only-keys)
    (printf "~a: fields read only after end of input (allocating reads): ~a\n" name end-only-keys))
  (for ([key (in-list eof-classification-ignore-keys)])
    (unless (hash-has-key? (expected-cp (entry-cp 0)) key)
      (error 'm4-scenario "end-of-input classification key ~a is not a compared reference checkpoint field" key)))
  (when (pair? eof-classification-ignore-keys)
    (printf "~a: fields not used to classify end-of-input tails (still compared): ~a\n"
            name eof-classification-ignore-keys))
  (define (end-cp k) (if has-end-checkpoints?
                         (list-ref (hash-ref reference 'end_checkpoints) k)
                         (list-ref diag-checkpoints k)))
  ;; The end state of the whole run (k = n) is X1's last checkpoint.
  (check-equal? (raw-cp (end-cp n)) (raw-cp (last diag-checkpoints)) "end checkpoint n")

  ;; --- the per-prefix protocol for one prefix k (per-prefix mode, reboots) ---
  (define (check-prefix-run k stage)
    (define lines (take commands k))
    (define r (run-game lines #:deadline deadline #:turn-limit turn-limit
                        #:scenario-limit scenario-limit))
    (define expected (vector-ref transcripts k))
    (or (let ([f (load-failure r k stage)])
          ;; A watchdog stop in the run of prefix k fails prefix k; the last
          ;; READSTRING entry reached is that run's.
          (if (and f (equal? (failure-kind f) "timeout"))
              (struct-copy failure f [k k]
                           [message (format "prefix ~a run: ~a" k (failure-message f))])
              f))
        (guard-failure r k stage #:open-records (expected-open-records k))
        (ending-failure r k stage (ending-of k) (unread-input k))
        (and (not (equal? (run-result-raw r) expected))
             (mk-failure k "transcript" stage "the whole prefix output differs from the native prefix stdout (D1 only)"
                         #:expected expected #:actual (run-result-raw r)))
        (let ([ours (with-handlers ([exn:fail? values]) (checkpoint (run-result-session r)))]
              [ref (expected-cp (end-cp k))])
          (cond [(exn? ours)
                 (mk-failure k "checkpoint" stage (format "reading the checkpoint failed: ~a" (exn-message ours)))]
                [(not (equal? ours ref))
                 (mk-failure k "checkpoint" stage
                             (format "the state after ~a differs from the end checkpoint"
                                     (if (eq? (ending-of k) 'quit) "the game's QUIT" "end of input"))
                             #:cp-diffs (cp-diffs ref ours))]
                [else #f]))
        (turn-check-failure k (run-result-raw r) stage)
        (begin (printf "~a prefix ~a: transcript and end checkpoint ~a equal the reference (~a s)~a\n"
                       name k k (real->decimal-string (run-result-elapsed r) 1)
                       (if (eq? (ending-of k) 'quit) "; ended by the game's QUIT" ""))
               #f)))
  (define (turn-check-failure k transcript stage)
    (with-handlers ([exn? (lambda (e) (mk-failure k "scenario-check" stage (exn-message e)))])
      (check-turn k transcript)
      #f))

  ;; --- single-run mode ---
  (define (single-run)
    ;; Reference-side split and classification.
    ;; The single run reaches READSTRING entries 0..q (q = n unless it ends
    ;; by QUIT). Head k for k <= q: prefix k reaches entry k too (its input
    ;; is the same up to there), and its last entry is k.
    (define t1 (vector-ref transcripts n))
    (for ([k (in-range (add1 q) n)])
      (unless (eq? (ending-of k) 'quit)
        (error 'm4-scenario "prefix ~a is beyond the single run's last READSTRING entry ~a but not a quit prefix" k q)))
    (define heads (for/vector ([k (in-range 0 (add1 q))])
                    (eof-split (vector-ref transcripts k) k (prefix-case-name k) prompt-split
                               #:entry-prompts entry-prompts
                               #:count (prompt-count (last-entry k) (ending-of k) entry-prompts))))
    (define (tail k) (substring (vector-ref transcripts k) (string-length (vector-ref heads k))))
    ;; Re-run per prefix: every end-of-input prefix k < n whose tail is not
    ;; standard, and every declared quit prefix k < n (its run never meets
    ;; the end of input the single run's turn k stands for).
    (define reboots
      (sort (append
             (non-standard-eof-tails n tail
                                     (lambda (k) (raw-cp (end-cp k)))
                                     (lambda (k) (raw-cp (eof-transform (entry-cp k))))
                                     #:ks (filter (lambda (k) (eq? (ending-of k) 'eof)) (range n))
                                     #:ignore-keys eof-classification-ignore-keys)
             (for/list ([k (in-list (sort quit-prefixes <))] #:when (< k n))
               (list k "declared quit ending")))
            < #:key car))
    (for ([row (in-list reboots)])
      (if (eq? (ending-of (car row)) 'quit)
          (printf "~a: prefix ~a ends by the game's QUIT (declared); it is re-run per prefix\n"
                  name (car row))
          (printf "~a: prefix ~a's end-of-input tail is not standard (~a); it is re-run per prefix\n"
                  name (car row) (string-join (cdr row) "; "))))
    ;; The run.
    (define snapshots (make-vector (add1 q) #f))
    (define completes (make-vector (add1 q) #f))
    (define extra-entries '())
    (define (snapshot session output)
      (define out (get-output-string output))
      (define-values (rng0 ledger0 errors0)
        (values (mdl-session-random-snapshot session) (mdl-session-storage-stats session)
                (length (mdl-session-mdl-errors session))))
      (define cp (with-handlers ([exn:fail? values]) (turn-checkpoint session)))
      (define rng1 (mdl-session-random-snapshot session))
      (define ledger1 (mdl-session-storage-stats session))
      (define errors1 (length (mdl-session-mdl-errors session)))
      ;; #f, or what the read changed among what this guard observes: RANDOM's
      ;; state, the logical storage ledger (game-visible through DIVERT-AGC and
      ;; GC timing, ADR-0044), the session's output, or its record of signalled
      ;; MDL errors. Other mutation (e.g. interning a new ATOM, or game code
      ;; that sets state) is not observed here; checkpoint functions must stay
      ;; to pure reads of existing names (docs/TESTING.md).
      (define perturbed
        (cond [(not (and (equal? (random36-state-words rng0) (random36-state-words rng1))
                         (= (random36-state-draws rng0) (random36-state-draws rng1))))
               "the RANDOM state"]
              [(not (equal? ledger0 ledger1))
               (format "the storage ledger (~s -> ~s)" ledger0 ledger1)]
              [(not (= (string-length out) (string-length (get-output-string output))))
               "the session output"]
              [(not (= errors0 errors1))
               (format "the MDL error record (~a -> ~a errors)" errors0 errors1)]
              [else #f]))
      (vector out cp perturbed))
    (define (observer kind k info session output)
      (case kind
        [(enter) (if (<= k q)
                     (vector-set! snapshots k (snapshot session output))
                     (set! extra-entries (cons k extra-entries)))]
        [(complete) (when (<= 0 k q)
                      (vector-set! completes k (cons (hash-ref info 'raw) (hash-ref info 'reason))))]))
    (define r (run-game commands #:observer observer #:deadline deadline #:turn-limit turn-limit
                        #:scenario-limit scenario-limit))
    (define stage "single-run")
    (define writes (run-result-writes r))
    (define sleeps (run-result-sleeps r))
    (define (turn-failure k)
      (define snap (vector-ref snapshots k))
      (define complete (vector-ref completes k))
      (define expected-unit (if (< k n)
                                (cons (string-append (list-ref commands k) "\n") 'stop)
                                (cons "" 'eof)))
      (cond
        [(assv k writes)
         (mk-failure k "run-guard" stage (format "file write or delete attempted: ~s" (cdr (assv k writes))))]
        [(assv k sleeps)
         (mk-failure k "run-guard" stage (format "the host sleeper was called: ~s" (cdr (assv k sleeps))))]
        [(not snap)
         (or (load-failure r k stage)
             (mk-failure k "run-guard" stage
                         (format "the run ended before READSTRING entry ~a: ~a; output tail ~s"
                                 k (result-text (run-result-result r)) (output-tail (run-result-raw r)))
                         #:last-k (last-k-reached (run-result-entries r))))]
        [(not (equal? (vector-ref snap 0) (vector-ref heads k)))
         (mk-failure k "transcript" stage
                     (format "the output at READSTRING entry ~a differs from the native prefix-~a stdout up to its prompt ~a (D1 only)"
                             k k (add1 k))
                     #:expected (vector-ref heads k) #:actual (vector-ref snap 0))]
        [(exn? (vector-ref snap 1))
         (mk-failure k "checkpoint" stage (format "reading the checkpoint failed: ~a" (exn-message (vector-ref snap 1))))]
        [(vector-ref snap 2)
         (mk-failure k "run-guard" stage
                     (format "reading the checkpoint at READSTRING entry ~a changed ~a" k (vector-ref snap 2)))]
        [(not (equal? (vector-ref snap 1) (expected-turn-cp k)))
         (mk-failure k "checkpoint" stage
                     (format "the state at READSTRING entry ~a differs from the reference diagnostic checkpoint ~a" k k)
                     #:cp-diffs (cp-diffs (expected-turn-cp k) (vector-ref snap 1)))]
        [(and complete (not (equal? complete expected-unit)))
         (mk-failure k "run-guard" stage
                     (format "READSTRING call ~a consumed ~s (~a), expected ~s (~a)"
                             k (car complete) (cdr complete) (car expected-unit) (cdr expected-unit)))]
        [else (turn-check-failure k (vector-ref snap 0) stage)]))
    (define single-failure
      (or (for/or ([k (in-range 0 (add1 q))])
            (or (turn-failure k)
                ;; Entry k was reached but its READSTRING call never returned.
                (and (not (vector-ref completes k))
                     (or (load-failure r k stage)
                         (mk-failure k "run-guard" stage
                                     (format "READSTRING call ~a never returned: ~a"
                                             k (result-text (run-result-result r)))
                                     #:last-k (last-k-reached (run-result-entries r)))))
                (begin (printf "~a turn ~a: output and checkpoint at READSTRING entry ~a equal the reference\n"
                               name k k)
                       #f)))
          (and (pair? extra-entries)
               (mk-failure (min n (add1 q)) "run-guard" stage
                           (format "unexpected READSTRING entries ~a" (reverse extra-entries))))
          ;; End of the whole run: end of input (the T1 tail), or the game's
          ;; QUIT when declared; then end checkpoint n.
          (let ([stage (if (eq? (ending-of n) 'quit) "single-run end (QUIT)" "single-run end of input")])
            (or (load-failure r n stage)
                (guard-failure r n stage #:event-k (lambda (entries) (min n entries))
                               #:open-records (expected-open-records n))
                (ending-failure r n stage (ending-of n) (unread-input n))
                (and (not (equal? (run-result-raw r) t1))
                     (mk-failure n "transcript" stage "the whole output differs from the native T1 stdout (D1 only)"
                                 #:expected t1 #:actual (run-result-raw r)))
                (let ([ours (with-handlers ([exn:fail? values]) (checkpoint (run-result-session r)))]
                      [ref (expected-cp (end-cp n))])
                  (cond [(exn? ours)
                         (mk-failure n "checkpoint" stage (format "reading the checkpoint failed: ~a" (exn-message ours)))]
                        [(not (equal? ours ref))
                         (mk-failure n "checkpoint" stage
                                     (format "the state after ~a differs from the end checkpoint"
                                             (if (eq? (ending-of n) 'quit) "the game's QUIT" "end of input"))
                                     #:cp-diffs (cp-diffs ref ours))]
                        [else #f]))
                (turn-check-failure n (run-result-raw r) stage)))))
    (printf "~a: single run of ~a commands, ~a READSTRING entries, ~a s\n"
            name n (run-result-entries r) (real->decimal-string (run-result-elapsed r) 1))
    ;; Reboots for the non-standard prefixes below the single run's failure.
    ;; Not after a single-run watchdog stop: the reboots share the scenario's
    ;; deadline, so each would time out at once and be misreported as an
    ;; earlier failing k (independent review); the timeout is reported with
    ;; the last k reached instead.
    (define limit-k (if single-failure (failure-k single-failure) (add1 n)))
    (define reboot-ks
      (if (and single-failure (equal? (failure-kind single-failure) "timeout"))
          '()
          (filter (lambda (k) (< k limit-k)) (map car reboots))))
    (define reboot-failure
      (for/or ([k (in-list reboot-ks)])
        (check-prefix-run k (if (eq? (ending-of k) 'quit)
                                "reboot (declared quit ending)"
                                "reboot (non-standard end-of-input tail)"))))
    (values (or reboot-failure single-failure)
            (add1 (length reboot-ks))
            (- n (length reboots))))

  ;; --- per-prefix mode ---
  (define (per-prefix)
    (define f (for/or ([k (in-range 0 (add1 n))]) (check-prefix-run k "per-prefix")))
    (values f (if f (add1 (failure-k f)) (add1 n)) 0))

  (define-values (result boots standard)
    (if (eq? mode 'single-run) (single-run) (per-prefix)))
  (define elapsed (/ (- (current-inexact-milliseconds) started) 1000.0))
  (define report-path (simplify-path (build-path (divergence-dir) (format "~a-~a.json" name mode))))
  (cond
    [result
     (write-divergence-report report-path name mode commands result elapsed)
     (error 'm4-scenario "~a (~a): earliest failing k = ~a, kind ~a, stage ~a: ~a~a\n  report: ~a"
            name mode (failure-k result) (failure-kind result) (failure-stage result)
            (failure-message result)
            (if (pair? (failure-cp-diffs result))
                (format "\n  checkpoint diffs: ~s" (failure-cp-diffs result))
                "")
            report-path)]
    [else
     (when (file-exists? report-path) (delete-file report-path))
     (printf "~a (~a): all ~a turns match the reference (D1 only); ~a boot~a~a, ~a s\n"
             name mode (add1 n) boots (if (= boots 1) "" "s")
             (if (eq? mode 'single-run)
                 (format "; ~a of ~a shorter prefixes have a standard end-of-input tail (not re-run)" standard n)
                 "")
             (real->decimal-string elapsed 1))]))

(define (write-divergence-report path name mode commands f elapsed)
  (define k (failure-k f))
  (define expected (failure-expected f))
  (define actual (failure-actual f))
  (define offset (and expected actual (first-difference expected actual)))
  (make-directory* (let-values ([(dir _n _d) (split-path path)]) dir))
  (define doc
    (hasheq 'schema_version 1
            'kind "m4-scenario-divergence"
            'scenario name
            'mode (symbol->string mode)
            'status "FAIL"
            'earliest_failing_k k
            'commands_consumed k
            'command_at_k (if (and (<= 1 k) (<= k (length commands))) (list-ref commands (sub1 k)) 'null)
            'failure_kind (failure-kind f)
            'stage (failure-stage f)
            'message (failure-message f)
            'last_k_reached (or (failure-last-k f) 'null)
            'transcript (if offset
                            (hasheq 'byte_offset offset
                                    'offset_note "character index; transcripts are 7-bit/latin-1 text, so it equals the byte offset"
                                    'expected_length (string-length expected)
                                    'actual_length (string-length actual)
                                    'expected_context (context expected offset)
                                    'actual_context (context actual offset)
                                    'context_start (max 0 (- offset 100)))
                            'null)
            'checkpoint_diffs (failure-cp-diffs f)
            'elapsed_seconds (string->number (real->decimal-string elapsed 1))))
  (call-with-output-file path #:exists 'truncate
    (lambda (out) (write-json doc out) (newline out))))

;; --- unit tests of the reference-side logic (no game run; `make test`) -------------
(module+ test
  (require rackunit racket/file json)
  ;; The prompt split: through the (k+1)-th `>`; a wrong prompt count is a
  ;; strict error (never a guess).
  (define p0 "Welcome.\n>Beg pardon?\n>")
  (define p1 "Welcome.\n>You are here.\n>Beg pardon?\nYour sword glows.\n>")
  (check-equal? (prompt-head p0 0 "P00") "Welcome.\n>")
  (check-equal? (prompt-head p1 1 "P01") "Welcome.\n>You are here.\n>")
  (check-exn #rx"expected 3 prompts" (lambda () (prompt-head p0 1 "P01")))
  (check-exn #rx"expected 2 prompts" (lambda () (prompt-head "a > b\n>Beg pardon?\n>" 0 "P00")))
  (check-equal? (eof-split p0 0 "P00") "Welcome.\n>")
  (check-equal? (eof-split p1 1 "P01") "Welcome.\n>You are here.\n>")
  ;; #:prompt-split 'line-initial (ADR-0062 amendment): a `>` inside a line
  ;; (help-info's 'attack <villain> with <weapon>') is not a prompt; the count
  ;; stays strict.
  (define ph "Welcome.\n>\nkill <villain> with <weapon>\n>Beg pardon?\n>")
  (check-exn #rx"expected 3 prompts" (lambda () (prompt-head ph 1 "P01")))
  (check-equal? (prompt-head ph 1 "P01" 'line-initial) "Welcome.\n>\nkill <villain> with <weapon>\n>")
  (check-equal? (eof-split ph 1 "P01" 'line-initial) "Welcome.\n>\nkill <villain> with <weapon>\n>")
  (check-equal? (prompt-head ">x\n>" 0 "P00" 'line-initial) ">")
  (check-exn #rx"expected 2 prompts" (lambda () (prompt-head ph 0 "P00" 'line-initial)))
  (check-exn #rx"expected 3 prompts"
             (lambda () (prompt-head "Welcome.\n>a >b\n>" 1 "P01" 'line-initial)))
  (check-exn #rx"prompt split" (lambda () (prompt-head p0 0 "P00" 'mid-line)))
  ;; #:entry-prompts (ADR-0062 amendment, M4 Phase 2): YES/NO's question is
  ;; the prompt of its READSTRING entry; the `>` count is prompt-count's.
  (define q "Q?")
  (define ep (hasheqv 1 q))
  (check-equal? (prompt-count 0 'eof (hasheqv)) 2)
  (check-equal? (prompt-count 4 'eof (hasheqv)) 6)
  (check-equal? (prompt-count 1 'eof ep) 2)        ; entries 0 and the dying one
  (check-equal? (prompt-count 1 'quit ep) 1)       ; entry 0 only
  (check-equal? (prompt-count 2 'eof ep) 3)
  (check-exn #rx"unknown ending" (lambda () (prompt-count 1 'crash ep)))
  ;; quit at the question: entries 0 (`>`) and 1 (Q?), no prompt after
  (define pq "Welcome.\n>Dead.\nQ?\nWhat?\nScore.\n")
  (check-equal? (prompt-head pq 1 "P01" #:entry-prompts ep #:count (prompt-count 1 'quit ep))
                "Welcome.\n>Dead.\nQ?")
  (check-equal? (prompt-head pq 0 "P00" #:entry-prompts ep #:count 1) "Welcome.\n>")
  ;; resurrection, `look`, then end of input: Q?, two RDCOM prompts, the dying one
  (define py "Welcome.\n>Dead.\nQ?Now.\n>Forest.\n>Beg pardon?\n>")
  (check-equal? (prompt-count 3 'eof ep) 4)
  (check-equal? (prompt-head py 3 "P03" #:entry-prompts ep #:count (prompt-count 3 'eof ep))
                "Welcome.\n>Dead.\nQ?Now.\n>Forest.\n>")
  (check-equal? (prompt-head py 1 "P03" #:entry-prompts ep #:count 4) "Welcome.\n>Dead.\nQ?")
  (check-equal? (prompt-head py 2 "P03" #:entry-prompts ep #:count 4) "Welcome.\n>Dead.\nQ?Now.\n>")
  ;; strict: a wrong count, a missing question, a `>` before the question
  (check-exn #rx"expected 5 prompts"
             (lambda () (prompt-head py 3 "P03" #:entry-prompts ep #:count 5)))
  (check-exn #rx"is not the next prompt"
             (lambda () (prompt-head "Welcome.\n>Dead.\n>Q?" 1 "P01" #:entry-prompts ep #:count 2)))
  (check-exn #rx"is not the next prompt"
             (lambda () (prompt-head "Welcome.\n>Dead.\n>" 1 "P01" #:entry-prompts ep #:count 2)))
  (check-exn #rx"no prompt `>` for READSTRING entry 2"
             (lambda () (prompt-head "Welcome.\n>Q?x" 2 "P02" #:entry-prompts ep #:count 1)))
  ;; without entry prompts the head is unchanged (through the (k+1)-th `>`)
  (check-equal? (prompt-head p1 1 "P01" #:entry-prompts (hasheqv) #:count 3) (prompt-head p1 1 "P01"))
  ;; Classification: the tail text and the end checkpoint both decide.
  (define tails (vector "Beg pardon?\n>" "Beg pardon?\nYour sword glows.\n>" "Beg pardon?\n>"
                        "Beg pardon?\n>"))
  (define entry (vector (hasheq 'a "1") (hasheq 'a "1") (hasheq 'a "2") (hasheq 'a "3")))
  (define end (vector (hasheq 'a "1") (hasheq 'a "1") (hasheq 'a "9") (hasheq 'a "3")))
  (check-equal? (non-standard-eof-tails 3 (lambda (k) (vector-ref tails k))
                                        (lambda (k) (vector-ref end k))
                                        (lambda (k) (vector-ref entry k)))
                '((1 "tail \"Beg pardon?\\nYour sword glows.\\n>\"")
                  (2 "end checkpoint fields (a)")))
  (check-equal? (non-standard-eof-tails 1 (lambda (k) "Beg pardoN?\n>") (lambda (k) 1) (lambda (k) 1))
                '((0 "tail \"Beg pardoN?\\n>\"")))
  ;; #:ks restricts the classification (quit prefixes are not classified).
  (check-equal? (non-standard-eof-tails 3 (lambda (k) (vector-ref tails k))
                                        (lambda (k) (vector-ref end k))
                                        (lambda (k) (vector-ref entry k))
                                        #:ks '(0 2))
                '((2 "end checkpoint fields (a)")))
  ;; #:ignore-keys (#:eof-classification-ignore-keys): the listed fields are
  ;; removed from both sides for the classification only; a difference in
  ;; another field, or in the tail, still makes the prefix non-standard.
  (define entry2 (vector (hasheq 'a "1" 'h "R0") (hasheq 'a "1" 'h "R1") (hasheq 'a "2" 'h "R2")))
  (define end2 (vector (hasheq 'a "1" 'h "R1") (hasheq 'a "1" 'h "R2") (hasheq 'a "9" 'h "R3")))
  (check-equal? (non-standard-eof-tails 3 (lambda (k) "Beg pardon?\n>")
                                        (lambda (k) (vector-ref end2 k))
                                        (lambda (k) (vector-ref entry2 k)))
                '((0 "end checkpoint fields (h)") (1 "end checkpoint fields (h)")
                  (2 "end checkpoint fields (a h)")))
  (check-equal? (non-standard-eof-tails 3 (lambda (k) (if (= k 1) "Beg pardon?\nX\n>" "Beg pardon?\n>"))
                                        (lambda (k) (vector-ref end2 k))
                                        (lambda (k) (vector-ref entry2 k))
                                        #:ignore-keys '(h))
                '((1 "tail \"Beg pardon?\\nX\\n>\"") (2 "end checkpoint fields (a)")))
  ;; k = n is never re-run (the single run's own end of input covers it).
  (check-equal? (non-standard-eof-tails 0 (lambda (k) "x") (lambda (k) 1) (lambda (k) 2)) '())
  ;; Differences.
  (check-equal? (first-difference "abc" "abc") #f)
  (check-equal? (first-difference "abc" "abd") 2)
  (check-equal? (first-difference "abc" "abcd") 3)
  (check-equal? (first-difference "" "x") 0)
  (check-equal? (context (make-string 300 #\a) 150) (make-string 200 #\a))
  (check-equal? (cp-diffs (hasheq 'a "1" 'b "2") (hasheq 'a "1" 'b "3" 'c "4"))
                (list (hasheq 'field "b" 'expected "2" 'actual "3")
                      (hasheq 'field "c" 'expected 'null 'actual "4")))
  ;; Configuration is strict.
  (define (set-env! name value)
    (environment-variables-set! (current-environment-variables) (string->bytes/utf-8 name)
                                (and value (string->bytes/utf-8 value))))
  (define (with-env name value thunk)
    (define old (getenv name))
    (dynamic-wind (lambda () (set-env! name value)) thunk (lambda () (set-env! name old))))
  (with-env "M4_SCENARIO_MODE" #f (lambda () (check-equal? (scenario-mode) 'single-run)))
  (with-env "M4_SCENARIO_MODE" "per-prefix" (lambda () (check-equal? (scenario-mode) 'per-prefix)))
  (with-env "M4_SCENARIO_MODE" "fast" (lambda () (check-exn #rx"M4_SCENARIO_MODE" scenario-mode)))
  (with-env "M4_SCENARIO_TIMEOUT" "0" (lambda () (check-exn #rx"positive" (lambda () (env-seconds "M4_SCENARIO_TIMEOUT" 9)))))
  (with-env "M4_SCENARIO_TIMEOUT" "12.5" (lambda () (check-equal? (env-seconds "M4_SCENARIO_TIMEOUT" 9) 12.5)))
  (with-env "M4_SCENARIO_TIMEOUT" #f (lambda () (check-equal? (env-seconds "M4_SCENARIO_TIMEOUT" 9) 9)))
  ;; The divergence report.
  (define dir (make-temporary-file "m4-divergence-~a" 'directory))
  (define path (build-path dir "sub" "demo-single-run.json"))
  (write-divergence-report path "demo" 'single-run '("north" "east")
                           (mk-failure 1 "transcript" "single-run" "differs"
                                       #:expected "Welcome.\n>You are here.\n>"
                                       #:actual "Welcome.\n>You are there.\n>")
                           1.25)
  (define doc (call-with-input-file path read-json))
  (check-equal? (hash-ref doc 'scenario) "demo")
  (check-equal? (hash-ref doc 'mode) "single-run")
  (check-equal? (hash-ref doc 'earliest_failing_k) 1)
  (check-equal? (hash-ref doc 'command_at_k) "north")
  (check-equal? (hash-ref doc 'failure_kind) "transcript")
  (check-equal? (hash-ref (hash-ref doc 'transcript) 'byte_offset) 18)
  (check-equal? (hash-ref (hash-ref doc 'transcript) 'expected_context) "Welcome.\n>You are here.\n>")
  (check-equal? (hash-ref doc 'checkpoint_diffs) '())
  (write-divergence-report path "demo" 'per-prefix '("north")
                           (mk-failure 0 "timeout" "per-prefix" "turn limit" #:last-k 'null) 3.0)
  (define doc2 (call-with-input-file path read-json))
  (check-equal? (hash-ref doc2 'command_at_k) 'null)
  (check-equal? (hash-ref doc2 'transcript) 'null)
  (check-equal? (hash-ref doc2 'last_k_reached) 'null)
  (delete-directory/files dir))
