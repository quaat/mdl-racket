#lang racket/base
;; Command-line entry for the local Zork launcher (S12, WP4).
;;   racket zork/cli.rkt [--fixed-clock EPOCH] [--no-notice]
;;   racket -l zork/cli -- [options]      (with the repository as a collection root)
;; Plays one fresh session on the process's own stdin/stdout through run-zork
;; (zork/main.rkt) and maps the result to the process exit code; this is the
;; only place that calls `exit`.
;;   0    the game QUIT normally ('quit)
;;   3    the game QUIT after an MDL ERROR ('quit-after-mdl-error)
;;   4    input ended before the game quit (EOF; 'input-exhausted)
;;   1    strict failure (unsupported construct, load not PASS, ...) - message on stderr
;;   2    usage error, or the pinned game sources are missing (run `make sources`)
;;   130  interrupted (break / Ctrl-C)
;; --fixed-clock EPOCH runs on a fixed session clock at EPOCH seconds with zone
;; UTC (ADR-0052) for reproducible transcripts; the default is the real clock
;; and the host's local zone.
(require racket/cmdline racket/string "main.rkt" "../mdl/loader.rkt")

(module+ main
  (define fixed-epoch #f)
  (define notice? #t)
  (define (usage-exit msg)
    (eprintf "zork: ~a\n" msg)
    (exit 2))
  (with-handlers ([exn:fail? (lambda (e) (usage-exit (exn-message e)))])
    (command-line
     #:program "zork"
     #:once-each
     [("--fixed-clock") epoch
                        "Use a fixed session clock at EPOCH seconds (UTC) for reproducible runs"
                        (define n (string->number epoch))
                        (unless (exact-integer? n)
                          (usage-exit (format "--fixed-clock expects integer seconds, got ~s" epoch)))
                        (set! fixed-epoch n)]
     [("--no-notice") "Do not print the launcher preview notice"
                      (set! notice? #f)]))
  (define code
    (with-handlers ([exn:break? (lambda (e) (eprintf "\nzork: interrupted\n") 130)]
                    [exn:fail:zork-launcher?
                     (lambda (e)
                       (eprintf "~a\n" (exn-message e))
                       (if (exn:fail:zork-launcher:missing-source? e) 2 1))]
                    [exn:fail? (lambda (e) (eprintf "zork: strict failure: ~a\n" (exn-message e)) 1)])
      (define result
        (run-zork #:input (current-input-port) #:output (current-output-port)
                  #:clock (if fixed-epoch (make-fixed-mdl-clock fixed-epoch) real-mdl-clock)
                  #:time-zone (if fixed-epoch 'utc 'local)
                  #:notice? notice?))
      (flush-output (current-output-port))
      (case (zork-result-kind result)
        [(quit-after-mdl-error)
         (eprintf "zork: the game quit after MDL error(s): ~a\n"
                  (string-join (map (lambda (m) (format "~a" m)) (zork-result-mdl-errors result))
                               "; "))]
        [(input-exhausted)
         (eprintf "\nzork: input ended (EOF) before the game quit\n")])
      (exit-code-for (zork-result-kind result))))
  (flush-output (current-output-port))
  (exit code))
