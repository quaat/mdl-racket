#lang racket/base
;; M3 SMOKE_PARITY candidate run (S10; issues #131/#135; ADR-0053).
;;
;; Runs the faithful run.mud path of the pinned 1977 Zork in this runtime and
;; emits the RAW facts of the run as JSON; it compares nothing. Normalisation
;; and comparison live in one place, scripts/smoke_parity.py (ADR-0053).
;;
;;   <FLOAD "77loadall.mud">   = mdl-session-load!
;;   <SAVE-IT>                 = mdl-session-run-interactive "SAVE-IT"
;;
;; The session runs on the scenario's fixed clock (ADR-0052: fixed_epoch, zone
;; UTC) and reads the scenario commands as LF-terminated lines from a host
;; string port (no echo). RDCOM never returns, so the run ends by the
;; documented input-exhaustion protocol (ADR-0050 D3): one mirrored empty read
;; ("Beg pardon?", ">"), then exn:fail:mdl-input-exhausted. That outcome is
;; reported as "input-exhausted", never as a user QUIT or as success by itself.
;;
;; Local only: no network, no evaluator exposed; the game directory is the
;; pinned upstream checkout, opened read-only (SAVE is a session record,
;; ADR-0048), and its listing is checked unchanged.
;;
;; Usage: racket scripts/m3_house_boot_run.rkt SCENARIO.json [OUTPUT.json]
;;        (OUTPUT defaults to standard output)
(require racket/runtime-path racket/port racket/list racket/string json
         "../mdl/loader.rkt")

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(define run-limit-seconds 300)

(define (main scenario-path output-path)
  (unless (directory-exists? source-root)
    (error 'm3-house-boot-run "pinned source missing: ~a (run make sources)" source-root))
  (define scenario (call-with-input-file scenario-path read-json))
  (define commands (hash-ref scenario 'commands))
  (define epoch (hash-ref scenario 'fixed_epoch))
  (unless (and (list? commands) (pair? commands) (andmap string? commands))
    (error 'm3-house-boot-run "scenario commands must be a nonempty list of strings"))
  (unless (exact-integer? epoch)
    (error 'm3-house-boot-run "scenario fixed_epoch must be an integer"))
  (for ([c (in-list commands)])
    (when (regexp-match? #rx"[\r\n]" c)
      (error 'm3-house-boot-run "command contains a line break: ~s" c)))

  (define input (open-input-string (string-append (string-join commands "\n") "\n")))
  (define output (open-output-string))
  (define session (make-mdl-session source-root #:input-port input #:output-port output
                                    #:clock (make-fixed-mdl-clock epoch)
                                    #:time-zone 'utc))
  (define (listing) (sort (map path->string (directory-list source-root)) string<?))
  (define listing-before (listing))

  (define load-report (mdl-session-load! session "77loadall.mud"))
  (define events '())
  (define outcome
    (if (not (equal? (hash-ref load-report 'status #f) "PASS"))
        (list "load-failed" (format "~s" (hash-ref load-report 'status #f)))
        (let* ([result (make-channel)]
               [worker (thread
                        (lambda ()
                          (channel-put
                           result
                           (with-handlers ([exn:fail? values])
                             (mdl-session-run-interactive
                              session "SAVE-IT"
                              #:on-event (lambda (e) (set! events (cons e events))))
                             'returned))))])
          (define r (or (sync/timeout run-limit-seconds result)
                        (begin (kill-thread worker) 'timed-out)))
          (cond
            [(exn:fail:mdl-input-exhausted? r) (list "input-exhausted" (exn-message r))]
            [(exn? r) (list "error" (exn-message r))]
            [(eq? r 'timed-out) (list "timed-out" (format "no outcome within ~a s" run-limit-seconds))]
            [else (list "returned" "the host loop returned normally")]))))
  (define moves (with-handlers ([exn:fail? (lambda (_) #f)])
                  (mdl-session-global session "MOVES")))
  (define record
    (hasheq 'engine "mdl-racket-host-loop"
            'runner "scripts/m3_house_boot_run.rkt"
            'scenario (hash-ref scenario 'name)
            'fixed_epoch epoch
            'tz "UTC"
            'entry (list "<FLOAD \"77loadall.mud\">" "<SAVE-IT>")
            'command_inputs commands
            'load (hasheq 'status (hash-ref load-report 'status #f)
                          'completed_expressions (hash-ref load-report 'completed_expressions #f)
                          'skipped_expressions (hash-ref load-report 'skipped_expressions #f))
            'raw_output (get-output-string output)
            'outcome (hasheq 'kind (first outcome) 'message (second outcome))
            'events (for/list ([e (in-list (reverse events))]) (symbol->string (car e)))
            'moves (if (exact-integer? moves) moves 'null)
            'input_remaining (port->string input)
            'save_records (length (mdl-session-save-records session))
            'source_listing_unchanged (equal? listing-before (listing))
            'version (version)))
  (if output-path
      (call-with-output-file output-path #:exists 'truncate
        (lambda (out) (write-json record out) (newline out)))
      (begin (write-json record) (newline))))

(module+ main
  (define args (current-command-line-arguments))
  (unless (<= 1 (vector-length args) 2)
    (eprintf "usage: racket scripts/m3_house_boot_run.rkt SCENARIO.json [OUTPUT.json]\n")
    (exit 2))
  (main (vector-ref args 0) (and (= (vector-length args) 2) (vector-ref args 1))))
