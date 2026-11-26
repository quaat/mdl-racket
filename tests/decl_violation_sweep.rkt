#lang racket/base
;; M4 issue #196 ("sweep first", maintainer decision 2026-11-26): the
;; attached-declaration violation sweep. DIAGNOSTIC ONLY: not a test of
;; `make test`, not a scenario target, not part of `make m4-check`; it changes
;; no runtime semantics (production stays strict). Run with `make m4-decl-sweep`.
;;
;; Every gated M4 scenario (tests/scenarios/m4-manifest.json), the balloon-ledge
;; route (the INV-12 frontier) and the targeted probe routes
;; (tests/decl_sweep_probes.json) run in single-run mode with the host-only,
;; test-only decl-violation recorder on (make-mdl-session #:decl-violation-
;; recorder through the runner's current-m4-decl-violation-recorder; SEMANTICS
;; "Diagnostic-only: attached-declaration violation recorder"): an attached
;; #DECL check that would fail is recorded and the run proceeds. One more
;; probe, sphere-clock-direct, calls SPHERE-FUNCTION directly in a loaded game
;; with PRSVEC as CLOCK-DEMON leaves it for a clock action (no route).
;;
;; For each unit the sweep records every violation with the READSTRING entry
;; count k (the violation belongs to command k, 1-based; 0 = the boot) and
;; whether, allowed to proceed, the run still matches the native reference:
;;   gated scenarios: the scenario test module itself (every turn's output and
;;     checkpoint, the whole transcript, the end state; prefix re-runs);
;;   balloon-ledge: run-m4-scenario against its committed native reference
;;     (all 81 commands, the puzzles checkpoint);
;;   probe routes: the whole transcript (D1 only) against the native
;;     transcript-only capture docs/evidence/M4/decl-sweep-probes-reference.json.
;; Violations are deduplicated by site: the #DECL's file, line and column
;; (resolved by parsing the loaded game files with the project reader) and the
;; binding. The report is docs/evidence/M4/decl-violation-sweep.json (or OUT).
;;
;; Usage:
;;   racket tests/decl_violation_sweep.rkt [--out OUT.json] [--work DIR] [--units a,b] [--reuse]
;;   racket tests/decl_violation_sweep.rkt --one UNIT RESULT.json      (one unit; internal)
;; Each unit runs in its own racket process (memory), one at a time. The
;; exit status is 0 when every unit ran to a result (a scenario that diverges
;; with the recorder on is data, reported, not a sweep failure) and the
;; report was written; non-zero when a unit crashed without a result.
(require racket/list racket/string racket/file racket/port racket/system racket/runtime-path
         racket/cmdline json file/sha1 (only-in rackunit current-check-handler)
         "../mdl/parser.rkt" "../mdl/loader.rkt"
         (only-in "../mdl/runtime/core.rkt" mdl-atom? mdl-atom-pname)
         "m4_scenario_runner.rkt" "m4_puzzles_checkpoint.rkt")

(define-runtime-path repo "..")
(define-runtime-path this-file "decl_violation_sweep.rkt")
(define manifest-path (build-path repo "tests/scenarios/m4-manifest.json"))
(define probes-path (build-path repo "tests/decl_sweep_probes.json"))
(define probes-reference-path (build-path repo "docs/evidence/M4/decl-sweep-probes-reference.json"))
(define default-out (build-path repo "docs/evidence/M4/decl-violation-sweep.json"))
(define default-work (build-path repo "artifacts/decl-sweep"))
(define (read-json-file p) (call-with-input-file p read-json))

;; --- units ---------------------------------------------------------------------------
;; (name class detail): class gated | frontier | probe | direct.
(define (units)
  (append
   (for/list ([s (in-list (hash-ref (read-json-file manifest-path) 'scenarios))])
     (list (hash-ref s 'name) "gated" (hash-ref s 'runner_test)))
   (list (list "balloon-ledge" "frontier" "tests/scenarios/balloon-ledge.json"))
   (for/list ([p (in-list (hash-ref (read-json-file probes-path) 'probes))])
     (list (hash-ref p 'name) "probe" "tests/decl_sweep_probes.json"))
   (list (list "sphere-clock-direct" "direct" "SPHERE-FUNCTION applied in a loaded game"))))

;; --- one unit (in its own process) ---------------------------------------------------
(define (render-value session info)
  (define type (hash-ref info 'value-type))
  (define v (hash-ref info 'value))
  (define (id field-name)
    (define x (mdl-session-call session "NTH" v (mdl-session-global session field-name)))
    (cond [(mdl-atom? x) (mdl-atom-pname x)]
          [(string? x) x]
          [else (error 'decl-sweep "unexpected ~a ~a" type field-name)]))
  (case type
    [("OBJECT") (format "#OBJECT ~a" (id "OID"))]
    [("ROOM") (format "#ROOM ~a" (id "RID"))]
    [else (hash-ref info 'value-summary)]))

(define (violation->json info k n session commands)
  (hasheq 'binding (hash-ref info 'binding)
          'kind (symbol->string (hash-ref info 'kind))
          'pattern (hash-ref info 'pattern)
          'value_type (hash-ref info 'value-type)
          'value (render-value session info)
          'line (hash-ref info 'line) 'column (hash-ref info 'column)
          'k k
          'command (cond [(not commands) "<host call after the boot>"]
                         [(and commands (<= 1 k) (<= k (length commands))) (list-ref commands (sub1 k))]
                         [(and commands (= k (add1 (length commands)))) "<end of input>"]
                         [(zero? k) "<boot>"]
                         [else 'null])
          'run (cond [(not commands) "host call"]
                     [(not n) "load-only"]
                     [(and commands (= n (length commands))) "single-run"]
                     [else (format "prefix-rerun ~a" n)])))

(define (run-one name out-path)
  (define unit (or (assoc name (units)) (error 'decl-sweep "unknown unit ~a" name)))
  (define class (second unit))
  (define recorded '())
  (define commands
    (case class
      [("gated" "frontier")
       (hash-ref (read-json-file (build-path repo "tests/scenarios" (string-append name ".json"))) 'commands)]
      [("probe")
       (hash-ref (findf (lambda (p) (equal? (hash-ref p 'name) name))
                        (hash-ref (read-json-file probes-path) 'probes))
                 'commands)]
      [else #f]))
  (define (recorder info k n session)
    (set! recorded (cons (violation->json info k n session commands) recorded)))
  (define started (current-inexact-milliseconds))
  (define-values (result native)
    (parameterize ([current-m4-decl-violation-recorder recorder])
      (case class
        [("gated")
         (define msg
           (with-handlers ([exn:fail? exn-message])
             (dynamic-require (build-path repo (third unit)) #f)
             #f))
         (values (or msg "PASS")
                 "the scenario test module: every READSTRING entry's output and checkpoint, the whole transcript and end state (single-run, prefix re-runs as declared)")]
        [("frontier")
         (define msg
           (with-handlers ([exn:fail? exn-message])
             (run-m4-scenario "balloon-ledge" commands
                              #:checkpoint puzzles-checkpoint
                              #:eof-classification-ignore-keys '(robber_hroom))
             #f))
         (values (or msg "PASS")
                 "run-m4-scenario against docs/evidence/M4/balloon-ledge-reference.json (81 commands, puzzles checkpoint), as historical_balloon_frontier_test.rkt")]
        [("probe") (parameterize ([current-check-handler raise]) (run-probe-route name commands))]
        [("direct") (run-sphere-direct)])))
  (define doc
    (hasheq 'unit name 'class class 'source (third unit)
            'result result 'native_comparison native
            'elapsed_seconds (string->number
                              (real->decimal-string (/ (- (current-inexact-milliseconds) started) 1000.0) 1))
            'violations (reverse recorded)))
  (call-with-output-file out-path #:exists 'truncate
    (lambda (out) (write-json doc out) (newline out)))
  (printf "~a: ~a violation(s); ~a\n" name (length recorded)
          (if (> (string-length result) 200) (substring result 0 200) result)))

;; A probe route: one boot (recorder on), its whole transcript compared with
;; the native T1 (D1 only) when the transcript-only capture holds the probe.
(define (run-probe-route name commands)
  (define r (m4-run-commands commands))
  (define ours (hash-ref r 'output))
  (define ref (and (file-exists? probes-reference-path) (read-json-file probes-reference-path)))
  (define probe (and ref (findf (lambda (p) (equal? (hash-ref p 'name) name)) (hash-ref ref 'probes))))
  (define guard (hash-ref r 'guard))
  (define ending (hash-ref r 'ending))
  (cond
    [guard (values (format "FAIL: run guard: ~a" guard) "none (guard failure)")]
    [(not probe)
     (values (format "ours only (no native capture): ending ~a, ~a READSTRING entries" ending (hash-ref r 'entries))
             "none: ours only")]
    [else
     (unless (equal? (hash-ref probe 'commands) commands)
       (error 'decl-sweep "~a: the native capture's commands differ from tests/decl_sweep_probes.json" name))
     (define cases (hash-ref probe 'cases))
     (unless (equal? (hash-ref (first cases) 'stdout_raw) (hash-ref (second cases) 'stdout_raw))
       (error 'decl-sweep "~a: native T1 and T1b differ" name))
     (define native (reference-transcript (first cases) commands))
     (define same? (equal? ours native))
     (define offset
       (and (not same?)
            (or (for/first ([i (in-range (min (string-length ours) (string-length native)))]
                            #:unless (char=? (string-ref ours i) (string-ref native i)))
                  i)
                (min (string-length ours) (string-length native)))))
     (values
      (cond [(and same? (equal? ending "input-exhausted"))
             (format "PASS: the whole transcript equals native T1 (D1 only), ~a commands, ended by input exhaustion"
                     (length commands))]
            [same? (format "FAIL: transcript equal but ending ~a" ending)]
            [else (format "FAIL: transcript differs from native T1 at character ~a (ending ~a): ours ~s native ~s"
                          offset ending
                          (substring ours (max 0 (- offset 60)) (min (string-length ours) (+ offset 60)))
                          (substring native (max 0 (- offset 60)) (min (string-length native) (+ offset 60))))])
      "the whole transcript (D1 only) against native T1 of docs/evidence/M4/decl-sweep-probes-reference.json (transcript only: no per-turn checkpoints)")]))

;; SPHERE-FUNCTION (77act3.mud:243) as the SPHIN clock action: CLOCK-DEMON
;; (77rooms.mud:1633-1648) puts <> in PRSVEC 2 and 3, then C-INT!-WORDS in
;; PRSVEC 1, then applies the action. Here the game boots by <SAVE-IT> with no
;; command (input ends at the first prompt; START has run), PRSVEC is set
;; exactly so, and SPHERE-FUNCTION is applied once by a host call: with the
;; recorder on, then in a strict run. Ours only: a direct call, not a route
;; and not compared with native (the route to the caged sphere, the Low Room
;; robot and the carousel, was not built).
(define (run-sphere-direct)
  (define (call-sphere)
    (define r (m4-run-commands '()))
    (when (hash-ref r 'guard) (error 'decl-sweep "sphere-clock-direct: run guard: ~a" (hash-ref r 'guard)))
    (unless (equal? (hash-ref r 'ending) "input-exhausted")
      (error 'decl-sweep "sphere-clock-direct: boot ended ~a" (hash-ref r 'ending)))
    (define s (hash-ref r 'session))
    (define before (string-length ((hash-ref r 'output-now))))
    (define prsvec (mdl-session-global s "PRSVEC"))
    (define c-int (mdl-session-call s "GVAL"
                                    (mdl-session-call s "LOOKUP" "C-INT" (mdl-session-global s "WORDS"))))
    (define false (mdl-session-call s "NTH" prsvec 3))
    (unless (equal? (mdl-atom-pname (mdl-session-call s "TYPE" false)) "FALSE")
      (error 'decl-sweep "PRSVEC 3 is not a FALSE"))
    (mdl-session-call s "PUT" prsvec 2 false)
    (mdl-session-call s "PUT" prsvec 3 false)
    (mdl-session-call s "PUT" prsvec 1 c-int)
    (define ending
      (with-handlers ([exn:fail? exn-message])
        (mdl-session-call s "SPHERE-FUNCTION")
        "returned"))
    (values ending (substring ((hash-ref r 'output-now)) before)))
  (define-values (ending output) (call-sphere))
  (define-values (strict-ending strict-output)
    (parameterize ([current-m4-decl-violation-recorder #f]) (call-sphere)))
  (values (format "ours only (direct call after the boot): with the recorder the call ended: ~a; its output ~s. Strict (no recorder): ~a; output ~s"
                  ending output strict-ending strict-output)
          "none: ours only (a direct host call of the clock action in a booted game; no route, no native comparison)"))

;; --- source index: every #DECL of the loaded game files ---------------------------------
;; (file line column) -> hasheq define construct names, by parsing each file
;; with the project reader (the same line/column the compiler gives the
;; #DECL; the reader needs no evaluation for these files).
(define (loaded-files)
  (define loadall (file->string (build-path m4-source-root "77loadall.mud")))
  (cons "77loadall.mud" (map cadr (regexp-match* #rx"<VFLOAD \"([^\"]+)\">" loadall #:match-select values))))

(define (decl-index)
  (define index (make-hash))
  (for ([file (in-list (loaded-files))])
    (define nodes (parse-mdl (file->string (build-path m4-source-root file)) #:source file))
    (define (head-name n)
      (and (eq? (mdl-node-kind n) 'form) (pair? (mdl-node-value n))
           (memq (mdl-node-kind (car (mdl-node-value n))) '(atom escaped-atom))
           (string-upcase (mdl-node-value (car (mdl-node-value n))))))
    (define (walk n top inner)
      (define h (head-name n))
      (define-values (top* inner*)
        (cond
          [(member h '("DEFINE" "DEFMAC"))
           (define items (mdl-node-value n))
           (define nm (and (pair? (cdr items)) (memq (mdl-node-kind (cadr items)) '(atom escaped-atom))
                           (string-upcase (mdl-node-value (cadr items)))))
           (values (or top nm) (format "~a ~a" h nm))]
          [(member h '("FUNCTION" "PROG" "REPEAT" "BIND")) (values top h)]
          [else (values top inner)]))
      (when (eq? (mdl-node-kind n) 'decl)
        (define items (mdl-node-value n))
        (define names
          (for*/list ([(item i) (in-parallel (in-list items) (in-naturals))] #:when (even? i)
                      #:when (eq? (mdl-node-kind item) 'list)
                      [a (in-list (mdl-node-value item))]
                      #:when (memq (mdl-node-kind a) '(atom escaped-atom)))
            (string-upcase (mdl-node-value a))))
        (hash-update! index (list (mdl-node-line n) (mdl-node-column n))
                      (lambda (l) (cons (hasheq 'file file 'function (or top* 'null)
                                                'construct (or inner* 'null) 'names names)
                                        l))
                      '()))
      (define v (mdl-node-value n))
      (cond [(mdl-node? v) (walk v top* inner*)]
            [(and (list? v) (andmap mdl-node? v)) (for ([c (in-list v)]) (walk c top* inner*))]
            [else (void)]))
    (for ([n (in-list nodes)]) (walk n #f #f)))
  index)

(define (resolve-site index v)
  (define cands
    (filter (lambda (c) (member (hash-ref v 'binding) (hash-ref c 'names)))
            (hash-ref index (list (hash-ref v 'line) (hash-ref v 'column)) '())))
  (unless (= 1 (length cands))
    (error 'decl-sweep "#DECL at ~a:~a declaring ~a: ~a candidate sites"
           (hash-ref v 'line) (hash-ref v 'column) (hash-ref v 'binding) (length cands)))
  (car cands))

;; --- aggregation ---------------------------------------------------------------------
(define (ranges ks)
  ;; (1 2 3 7) -> "1-3, 7"
  (define sorted (sort (remove-duplicates ks) <))
  (let loop ([xs sorted] [acc '()])
    (cond [(null? xs) (string-join (reverse acc) ", ")]
          [else
           (define start (car xs))
           (define-values (run rest)
             (let r ([prev start] [ys (cdr xs)])
               (if (and (pair? ys) (= (car ys) (add1 prev))) (r (car ys) (cdr ys)) (values prev ys))))
           (loop rest (cons (if (= start run) (number->string start) (format "~a-~a" start run)) acc))])))

(define class-rank (hash "gated" 0 "frontier" 1 "probe" 2 "direct" 3))
(define reachability
  (hash "gated" "on a gated scenario route"
        "frontier" "on the balloon-ledge route (INV-12 frontier)"
        "probe" "targeted probe route"
        "direct" "direct call only (no route run)"))

(define (aggregate results)
  (define index (decl-index))
  (define sites (make-hash))
  (for* ([r (in-list results)] [v (in-list (hash-ref r 'violations))])
    (define site (resolve-site index v))
    (define key (list (hash-ref site 'file) (hash-ref v 'line) (hash-ref v 'column) (hash-ref v 'binding)))
    (hash-update! sites key (lambda (l) (cons (cons r v) l)) '()))
  (define site-list
    (for/list ([(key occ) (in-hash sites)])
      (define site (resolve-site index (cdar occ)))
      (define by-unit (group-by (lambda (o) (hash-ref (car o) 'unit)) (reverse occ)))
      (define classes (remove-duplicates (map (lambda (o) (hash-ref (car o) 'class)) occ)))
      (define best (argmin (lambda (c) (hash-ref class-rank c)) classes))
      (hasheq 'file (first key) 'line (second key) 'column (third key)
              'decl (format "~a:~a" (first key) (second key))
              'function (hash-ref site 'function) 'construct (hash-ref site 'construct)
              'binding (fourth key)
              'kinds (sort (remove-duplicates (map (lambda (o) (hash-ref (cdr o) 'kind)) occ)) string<?)
              'patterns (remove-duplicates (map (lambda (o) (hash-ref (cdr o) 'pattern)) occ))
              'observed_value_types (sort (remove-duplicates (map (lambda (o) (hash-ref (cdr o) 'value_type)) occ)) string<?)
              'observed_values (take-up-to (sort (remove-duplicates (map (lambda (o) (hash-ref (cdr o) 'value)) occ)) string<?) 12)
              'occurrences (length occ)
              'reachability (hash-ref reachability best)
              'reachability_class best
              'units
              (for/list ([g (in-list by-unit)])
                (define r (car (car g)))
                (define vs (map cdr g))
                (define single (filter (lambda (v) (equal? (hash-ref v 'run) "single-run")) vs))
                (hasheq 'unit (hash-ref r 'unit) 'class (hash-ref r 'class)
                        'count (length vs)
                        'single_run_turns (ranges (map (lambda (v) (hash-ref v 'k)) single))
                        'first_command (let ([f (if (pair? single) (car single) (car vs))]) (hash-ref f 'command))
                        'other_runs (remove-duplicates (filter-map (lambda (v) (and (not (equal? (hash-ref v 'run) "single-run")) (hash-ref v 'run))) vs))
                        'unit_result_with_recorder (hash-ref r 'result))))))
  (sort site-list
        (lambda (a b)
          (define ra (hash-ref class-rank (hash-ref a 'reachability_class)))
          (define rb (hash-ref class-rank (hash-ref b 'reachability_class)))
          (if (= ra rb)
              (string<? (format "~a ~a" (hash-ref a 'decl) (hash-ref a 'binding))
                        (format "~a ~a" (hash-ref b 'decl) (hash-ref b 'binding)))
              (< ra rb)))))

(define (take-up-to l n) (if (> (length l) n) (take l n) l))

;; --- driver --------------------------------------------------------------------------
(define (sanitize s)
  (let* ([s (string-replace s (path->string (simplify-path (path->complete-path repo))) "<repo>/")]
         [s (string-replace s (path->string (find-system-path 'temp-dir)) "$TMPDIR/")])
    s))
(define (sanitize-json j)
  (cond [(string? j) (sanitize j)]
        [(list? j) (map sanitize-json j)]
        [(hash? j) (for/hasheq ([(k v) (in-hash j)]) (values k (sanitize-json v)))]
        [else j]))

(define (git-head)
  (string-trim (with-output-to-string (lambda () (system* (find-executable-path "git") "-C" (path->string repo) "rev-parse" "HEAD")))))

(define (run-all out work only reuse?)
  (make-directory* work)
  (make-directory* (build-path work "logs"))
  (define divergence (build-path work "scenario-divergence"))
  (make-directory* divergence)
  (define racket-exe
    (or (find-executable-path (find-system-path 'exec-file))
        (error 'decl-sweep "cannot locate the racket executable ~a" (find-system-path 'exec-file))))
  (define selected (filter (lambda (u) (or (not only) (member (first u) only))) (units)))
  (define failures '())
  (define results
    (for/list ([u (in-list selected)])
      (define name (first u))
      (define result-path (build-path work (format "~a.json" name)))
      (unless (and reuse? (file-exists? result-path))
        (when (file-exists? result-path) (delete-file result-path))
        (printf "== ~a (~a)\n" name (second u))
        (flush-output)
        (define env (environment-variables-copy (current-environment-variables)))
        (environment-variables-set! env #"M4_SCENARIO_DIVERGENCE_DIR" (string->bytes/utf-8 (path->string divergence)))
        (environment-variables-set! env #"M4_SCENARIO_MODE" #f)
        (define ok?
          (parameterize ([current-environment-variables env])
            (call-with-output-file (build-path work "logs" (format "~a.log" name)) #:exists 'truncate
              (lambda (log)
                (parameterize ([current-output-port log] [current-error-port log])
                  (system* racket-exe
                           (path->string this-file) "--one" name (path->string result-path)))))))
        (unless (and ok? (file-exists? result-path))
          (set! failures (cons name failures))))
      (and (file-exists? result-path)
           (let ([r (read-json-file result-path)])
             (printf "   ~a: ~a violation(s), ~as; ~a\n" name (length (hash-ref r 'violations))
                     (hash-ref r 'elapsed_seconds)
                     (let ([t (hash-ref r 'result)]) (if (> (string-length t) 160) (substring t 0 160) t)))
             r))))
  (define ok-results (filter values results))
  (define sites (aggregate ok-results))
  (define lock (read-json-file (build-path repo "sources.lock.json")))
  (define doc
    (sanitize-json
     (hasheq 'schema_version 1
             'kind "m4-decl-violation-sweep"
             'issue "#196"
             'note "Diagnostic only. Production behaviour is unchanged and strict: the recorder is a host-only, test-only hook (make-mdl-session #:decl-violation-recorder) that no production host passes. Here every attached #DECL check that would fail was recorded and the run proceeded."
             'repository_commit (git-head)
             'upstream (hasheq 'mdlzork (hash-ref (hash-ref (hash-ref lock 'sources) 'mdlzork) 'commit)
                               'mit_zork (hash-ref (hash-ref (hash-ref lock 'sources) 'mit_zork) 'commit))
             'reference_interpreter_sha256 m4-pinned-mdli
             'racket_version (version)
             'clock (hasheq 'fixed_epoch 250776000 'tz "UTC" 'microseconds 0 'rng_seed 10438660480
                            'note "every unit boots by <FLOAD \"77loadall.mud\"> (and <SAVE-IT> for routes) on this fixed session clock; RANDOM is never overridden")
             'turn_convention "k = READSTRING entries made when the violation happened: the violation belongs to command k (1-based); 0 = the boot; n+1 = the end-of-input entry"
             'units (for/list ([r (in-list ok-results)])
                      (hasheq 'unit (hash-ref r 'unit) 'class (hash-ref r 'class) 'source (hash-ref r 'source)
                              'violations (length (hash-ref r 'violations))
                              'result_with_recorder (hash-ref r 'result)
                              'native_comparison (hash-ref r 'native_comparison)
                              'elapsed_seconds (hash-ref r 'elapsed_seconds)))
             'units_crashed (reverse failures)
             'distinct_sites (length sites)
             'sites sites)))
  (call-with-output-file out #:exists 'truncate
    (lambda (o) (write-json doc o) (newline o)))
  (printf "\n~a distinct site(s); report ~a\n" (length sites) out)
  (for ([s (in-list sites)])
    (printf "  ~a ~a (~a) ~a ~a: ~a; ~a; values ~a; units ~a\n"
            (hash-ref s 'decl) (hash-ref s 'function) (hash-ref s 'construct) (hash-ref s 'binding)
            (hash-ref s 'kinds) (hash-ref s 'patterns) (hash-ref s 'reachability)
            (hash-ref s 'observed_values)
            (for/list ([u (in-list (hash-ref s 'units))])
              (format "~a[~a]" (hash-ref u 'unit) (hash-ref u 'single_run_turns)))))
  (when (pair? failures)
    (eprintf "units without a result: ~a (logs in ~a)\n" (reverse failures) (build-path work "logs")))
  (null? failures))

(module+ main
  (define args (current-command-line-arguments))
  (cond
    [(and (>= (vector-length args) 1) (equal? (vector-ref args 0) "--one"))
     (unless (= (vector-length args) 3) (error 'decl-sweep "usage: --one UNIT RESULT.json"))
     (run-one (vector-ref args 1) (vector-ref args 2))]
    [else
     (define out (make-parameter default-out))
     (define work (make-parameter default-work))
     (define only (make-parameter #f))
     (define reuse (make-parameter #f))
     (command-line
      #:once-each
      [("--out") p "report path" (out (string->path p))]
      [("--work") p "work directory" (work (string->path p))]
      [("--units") u "comma-separated unit names" (only (string-split u ","))]
      [("--reuse") "reuse existing unit results in the work directory" (reuse #t)])
     (unless (run-all (out) (work) (only) (reuse)) (exit 1))]))
