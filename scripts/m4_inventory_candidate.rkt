#lang racket/base
;; M4 Phase 1 gameplay failure inventory: run the command sequences of
;; tests/scenarios/failure-inventory-cases.json in THIS runtime and record what
;; happens, next to the pinned native captures in
;; docs/evidence/M4/failure-inventory-reference.json
;; (scripts/probe_failure_inventory_reference.py).
;;
;; Discovery evidence only: no runtime code is changed and nothing here is a
;; parity test. Each case boots exactly like the M4 scenario tests: a fresh
;; session over the pinned source, <FLOAD "77loadall.mud">, then SAVE-IT
;; through the host top-level loop, fixed session clock 250776000 UTC
;; (ADR-0052), input = the case's commands, guarded (any file write or delete
;; attempt is recorded), empty temporary cwd, watchdog. For each case it
;; records the raw output, how the run ended (input exhausted / QUIT outcome /
;; strict failure with its exception message), the MDL ERRORs signalled, the
;; denied OPEN calls, the game-directory manifest check, and the first
;; character at which our game text (from "Welcome to Dungeon.") differs from
;; the native game text.
;;
;; Run ONE heavy process at a time:
;;   PLTCOLLECTS=":$PWD" racket scripts/m4_inventory_candidate.rkt OUT.json [CASE-ID ...]
(require racket/runtime-path racket/port racket/string racket/list racket/file
         racket/path file/sha1 json
         "../mdl/loader.rkt")

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(define-runtime-path cases-file "../tests/scenarios/failure-inventory-cases.json")
(define-runtime-path reference-file "../docs/evidence/M4/failure-inventory-reference.json")
(define-runtime-path repo-root "..")

(define args (current-command-line-arguments))
(unless (>= (vector-length args) 1)
  (error 'm4-inventory "usage: racket scripts/m4_inventory_candidate.rkt OUT.json [CASE-ID ...]"))
(define out-file (vector-ref args 0))
(define only (cdr (vector->list args)))

(define spec (call-with-input-file cases-file read-json))
(unless (and (equal? (hash-ref spec 'fixed_epoch) 250776000) (equal? (hash-ref spec 'tz) "UTC"))
  (error 'm4-inventory "cases file must use the fixed clock 250776000 UTC"))
(define reference
  (and (file-exists? reference-file) (call-with-input-file reference-file read-json)))
(define (native-game-text id)
  (and reference
       (for/first ([c (hash-ref reference 'cases)] #:when (equal? (hash-ref c 'name) id))
         (hash-ref c 'game_output_canonical #f))))

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

(define run-limit-seconds 900)
(define (lines->input lines)
  (apply string-append (map (lambda (l) (string-append l "\n")) lines)))
(define (game-part s)
  (define m (regexp-match-positions #rx"Welcome to Dungeon\\." s))
  (if m (substring s (caar m)) ""))
(define (canon s) (regexp-replace* #rx"\r\n?" s "\n"))
(define (first-difference a b)
  (for/first ([i (in-range (add1 (min (string-length a) (string-length b))))]
              #:when (or (= i (string-length a)) (= i (string-length b))
                         (not (char=? (string-ref a i) (string-ref b i)))))
    (if (and (= i (string-length a)) (= i (string-length b))) #f i)))

(define (run-commands id lines native)
  (define input (open-input-string (lines->input lines)))
  (define output (open-output-string))
  (define cwd (make-temporary-file "m4-inventory-cwd-~a" 'directory))
  (define manifest-before (tree-manifest source-root))
  (define writes '())
  (define guard
    (make-security-guard
     original-guard
     (lambda (who path modes)
       (when (and path (or (memq 'write modes) (memq 'delete modes)))
         (set! writes (cons (format "~a ~a ~a" who path modes) writes))))
     (lambda (who host port mode) (void))))
  (define events '())
  (define session
    (make-mdl-session source-root #:input-port input #:output-port output
                      #:clock (make-fixed-mdl-clock 250776000) #:time-zone 'utc))
  (define done (make-channel))
  (define t0 (current-inexact-milliseconds))
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
  (define elapsed (/ (- (current-inexact-milliseconds) t0) 1000.0))
  (define cwd-after (parameterize ([current-security-guard original-guard])
                      (map path->string (directory-list cwd))))
  (delete-directory/files cwd)
  (define report (first outcome))
  (define result (second outcome))
  (define raw (get-output-string output))
  (define ending
    (cond [(eq? result 'timed-out) "timeout"]
          [(exn:fail:mdl-input-exhausted? result) "input-exhausted"]
          [(mdl-session-outcome? result)
           (format "outcome:~a" (mdl-session-outcome-kind result))]
          [(exn? result) "strict-failure"]
          [else (format "other:~s" result)]))
  (define ours (canon (game-part raw)))
  (define diff (and native (first-difference ours native)))
  (define unread (port->string input))
  (printf "~a: ~a load=~a elapsed=~as\n" id ending
          (and report (hash-ref report 'status #f)) (/ (round (* 10 elapsed)) 10))
  (when (exn? result) (printf "  exception: ~a\n" (exn-message result)))
  (hasheq 'id id
          'commands lines
          'load_status (and report (hash-ref report 'status #f))
          'load_completed_expressions (and report (hash-ref report 'completed_expressions #f))
          'ending ending
          'exception (and (exn? result) (exn-message result))
          'secondary_failures
          (if (exn? result)
              (for/list ([s (mdl-host-loop-secondary-failures result)])
                (if (exn? s) (exn-message s) (format "~s" s)))
              '())
          'mdl_errors (for/list ([m (mdl-session-mdl-errors session)]) (format "~a" m))
          'open_records
          (for/list ([r (mdl-session-open-records session)])
            (hasheq 'mode (mdl-open-record-mode r) 'file_spec (mdl-open-record-file-spec r)
                    'status (mdl-open-record-status r)))
          'save_record_count (length (mdl-session-save-records session))
          'events (map (lambda (e) (format "~a" (car e))) (reverse events))
          'unread_input unread
          'writes (reverse writes)
          'cwd_after cwd-after
          'game_dir_unchanged (equal? manifest-before (tree-manifest source-root))
          'elapsed_seconds (/ (round (* 10 elapsed)) 10)
          'raw_output raw
          'game_output_canonical ours
          'native_game_output_available (and native #t)
          'game_output_equals_native (and native (not diff))
          'first_difference_offset diff
          'ours_from_difference (and diff (substring ours diff (min (string-length ours) (+ diff 400))))
          'native_from_difference (and diff (substring native diff (min (string-length native) (+ diff 400))))))

;; A case with "fault_skip": true is a discovery battery: when a command ends
;; the run with a strict failure, the failure is recorded and the battery is
;; re-run from a fresh boot without that command, until a run ends without a
;; strict failure (bounded). The failing command is the last one read:
;; index = commands - unread lines - 1. Only the first run is compared with
;; the native capture of the full battery.
(define (unread-count s) (length (regexp-match* #rx"\n" s)))
(define (run-case c)
  (define id (hash-ref c 'id))
  (define lines (hash-ref c 'commands))
  (define native (native-game-text id))
  (cond
    [(not (hash-ref c 'fault_skip #f)) (run-commands id lines native)]
    [else
     (let loop ([remaining (for/list ([l lines] [i (in-naturals)]) (cons i l))]
                [skipped '()] [first-row #f] [n 0])
       (define row (run-commands id (map cdr remaining)
                                 (and (not first-row) native)))
       (define first (or first-row row))
       (cond
         [(and (equal? (hash-ref row 'ending) "strict-failure") (< n 25))
          (define k (- (length remaining) (unread-count (hash-ref row 'unread_input)) 1))
          (define bad (list-ref remaining k))
          (loop (append (take remaining k) (drop remaining (add1 k)))
                (cons (hasheq 'index (car bad) 'command (cdr bad)
                              'exception (hash-ref row 'exception))
                      skipped)
                first (add1 n))]
         [else
          (hash-set* first
                     'fault_skip_runs (add1 n)
                     'fault_skip_failures (reverse skipped)
                     'fault_skip_final_commands (map cdr remaining)
                     'fault_skip_final_ending (hash-ref row 'ending)
                     'fault_skip_final_exception (hash-ref row 'exception)
                     'fault_skip_final_game_output (hash-ref row 'game_output_canonical))]))]))

(define rows
  (for/list ([c (hash-ref spec 'cases)]
             #:when (or (null? only) (member (hash-ref c 'id) only)))
    (run-case c)))

(define result
  (hasheq 'schema_version 1
          'kind "m4-failure-inventory-candidate"
          'cases_file "tests/scenarios/failure-inventory-cases.json"
          'reference_file "docs/evidence/M4/failure-inventory-reference.json"
          'engine "mdl-racket (this runtime)"
          'racket_version (version)
          'fixed_epoch 250776000 'tz "UTC"
          'entry '("<FLOAD \"77loadall.mud\">" "SAVE-IT (host top-level loop)")
          'generator "scripts/m4_inventory_candidate.rkt"
          'cases rows))
(define text (jsexpr->string result))
(define (sanitize s)
  (define tmp (let ([t (getenv "TMPDIR")]) (and t (regexp-replace #rx"/$" t ""))))
  (define root (path->string (simplify-path (path->complete-path repo-root))))
  (let* ([s (string-replace s (regexp-replace #rx"/$" root "") "<repo>")]
         [s (if tmp (string-replace s tmp "$TMPDIR") s)])
    s))
(call-with-output-file out-file #:exists 'truncate
  (lambda (o) (write-string (sanitize text) o) (newline o)))
