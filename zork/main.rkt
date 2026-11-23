#lang racket/base
;; Local launcher for the unchanged December 1977 Zork (S12, WP4).
;;
;; A thin host wrapper over the session API of mdl/loader.rkt: it creates a
;; FRESH session per call with explicit ports, performs the faithful run.mud
;; path (<FLOAD "77loadall.mud"> then the host top-level loop applying
;; SAVE-IT; ADR-0049/ADR-0050), and returns a structured result. It adds no
;; game behaviour of its own and exposes no MDL evaluator, REPL, network
;; service or persistence: the only thing that reaches MDL is the text the
;; game itself reads with READSTRING.
;;
;; This module is the library only (it has no `main` submodule), so opening
;; and running it in DrRacket just defines run-zork; nothing starts and
;; nothing exits. The command line lives in zork/cli.rkt.
;;   (require zork)              ; with the repository as a collection root
;;   (run-zork)                  ; returns a zork-result when the game QUITs
;;                               ; or input ends; never calls `exit`
;;
;; Results (never an exit, never a printed verdict inside run-zork):
;;   (zork-result 'quit '() #f)                    the game's own QUIT (ADR-0054)
;;   (zork-result 'quit-after-mdl-error msgs #f)   QUIT after an MDL ERROR
;;   (zork-result 'input-exhausted '() message)    input ended (D3, ADR-0050)
;; Everything else propagates unchanged: strict runtime failures (exn:fail,
;; e.g. an unsupported construct), exn:fail:zork-launcher for setup problems
;; (pinned source missing, load not PASS), and exn:break (DrRacket's Stop or
;; Ctrl-C), so a break ends the game without ending the host process.
(require racket/runtime-path racket/string
         "../mdl/loader.rkt")

(provide run-zork
         (struct-out zork-result)
         (struct-out exn:fail:zork-launcher)
         (struct-out exn:fail:zork-launcher:missing-source)
         default-source-root
         launcher-notice
         exit-code-for)

;; The pinned game directory (scripts/fetch_sources.py, sources.lock.json),
;; resolved relative to this file so the launcher works from any cwd.
(define-runtime-path default-source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")

(define entry-file "77loadall.mud")
(define entry-function "SAVE-IT")

(struct zork-result (kind mdl-errors message) #:transparent)
(struct exn:fail:zork-launcher exn:fail () #:transparent)
;; The pinned game directory (or its entry file) is absent: a setup problem.
(struct exn:fail:zork-launcher:missing-source exn:fail:zork-launcher () #:transparent)

(define (launcher-error fmt . args)
  (raise (exn:fail:zork-launcher (apply format (string-append "zork launcher: " fmt) args)
                                 (current-continuation-marks))))
(define (missing-source-error fmt . args)
  (raise (exn:fail:zork-launcher:missing-source
          (apply format (string-append "zork launcher: " fmt) args)
          (current-continuation-marks))))

;; The preview notice. Launcher text, not game output: every line carries the
;; "[launcher]" mark and it is printed before the session is created.
(define launcher-notice
  (string-append
   "[launcher] Preview: this is the unchanged December 1977 Zork source running on\n"
   "[launcher] an MDL-on-Racket runtime (not the original PDP-10 MDL). SAVE only makes\n"
   "[launcher] an in-session record and RESTORE is unsupported; the game never writes\n"
   "[launcher] files. A construct the runtime does not support stops the game with an\n"
   "[launcher] error instead of being guessed at. Type `quit` to leave.\n"
   "[launcher] ----------------------------------------------------------------------\n"))

;; A guard that refuses any file write/delete or network use for the run
;; (the no-file policy of ADR-0055, enforced host-side as defense in depth).
;; Reads (loading the source) are allowed. A refusal raises exn:fail and
;; propagates like any strict failure.
(define (no-write-guard parent)
  (make-security-guard
   parent
   (lambda (who path modes)
     (when (and path (or (memq 'write modes) (memq 'delete modes)))
       (raise (exn:fail:zork-launcher
               (format "zork launcher: refused ~a of ~a during the game (no-file policy)"
                       modes path)
               (current-continuation-marks)))))
   (lambda (who host port mode)
     (raise (exn:fail:zork-launcher
             "zork launcher: refused network access during the game"
             (current-continuation-marks))))))

(define (run-zork #:input [in (current-input-port)]
                  #:output [out (current-output-port)]
                  #:source-root [root default-source-root]
                  #:clock [clock real-mdl-clock]
                  #:time-zone [time-zone 'local]
                  #:notice? [notice? #t])
  (unless (input-port? in) (raise-argument-error 'run-zork "input-port?" in))
  (unless (output-port? out) (raise-argument-error 'run-zork "output-port?" out))
  (unless (path-string? root) (raise-argument-error 'run-zork "path-string?" root))
  (unless (directory-exists? root)
    (missing-source-error
     "the pinned game directory is missing: ~a\nRun `make sources` in the repository root first."
     root))
  (unless (file-exists? (build-path root entry-file))
    (missing-source-error "~a not found in ~a\nRun `make sources` in the repository root first."
                    entry-file root))
  (when notice?
    (write-string launcher-notice out)
    (flush-output out))
  (parameterize ([current-security-guard (no-write-guard (current-security-guard))])
    ;; A fresh session per call: no state is shared between two runs.
    (define session
      (make-mdl-session root #:input-port in #:output-port out
                        #:clock clock #:time-zone time-zone))
    (define report (mdl-session-load! session entry-file))
    (unless (equal? (hash-ref report 'status) "PASS")
      (define failure (hash-ref report 'failure #f))
      (launcher-error "loading ~a did not PASS (status ~a)~a"
                      entry-file (hash-ref report 'status)
                      (if (hash? failure)
                          (format ": ~a at ~a:~a (~a)"
                                  (hash-ref failure 'message (hash-ref failure 'classification #f))
                                  (hash-ref failure 'file #f) (hash-ref failure 'line #f)
                                  (hash-ref failure 'construct #f))
                          "")))
    (with-handlers ([exn:fail:mdl-input-exhausted?
                     (lambda (e) (zork-result 'input-exhausted '() (exn-message e)))])
      (define outcome (mdl-session-run-interactive session entry-function))
      (zork-result (mdl-session-outcome-kind outcome)
                   (mdl-session-outcome-mdl-errors outcome)
                   #f))))

;; Process exit codes of the command line (zork/cli.rkt; only it exits):
;;   0    the game QUIT normally ('quit)
;;   3    the game QUIT after an MDL ERROR ('quit-after-mdl-error)
;;   4    input ended before the game quit (EOF; 'input-exhausted)
;;   1    strict failure (unsupported construct, load failure, ...)
;;   2    usage error or pinned game sources missing
;;   130  interrupted (break / Ctrl-C)
(define (exit-code-for kind)
  (case kind
    [(quit) 0]
    [(quit-after-mdl-error) 3]
    [(input-exhausted) 4]
    [else (raise-argument-error 'exit-code-for "zork-result kind" kind)]))
