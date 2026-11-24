#lang racket/base
;; Child process of tests/persistence_replay_test.rkt (WP4.5 "restore in a
;; fresh process"): restore the Zork replay checkpoint in CHECKPOINT-FILE,
;; continue with the commands in COMMANDS-FILE (a JSON list of strings) on the
;; fixed wall clock 1900000000, and print one JSON object on stdout: the state
;; read at the restore point (RNG words, draw count, selected game state),
;; the visible post-restore output, the result kind and the end state.
;;   racket tests/persistence_restore_child.rkt CHECKPOINT-FILE COMMANDS-FILE
;; Exit status 0 on a verified restore; a restore failure exits 1 with the
;; error on stderr.
(require racket/port json
         "../mdl/loader.rkt" "../mdl/replay.rkt" "../zork/persistence.rkt")

(module+ main
  (define args (current-command-line-arguments))
  (unless (= (vector-length args) 2)
    (eprintf "usage: persistence_restore_child.rkt CHECKPOINT-FILE COMMANDS-FILE\n")
    (exit 2))
  ;; A bounded read: never more than the checkpoint size limit plus one byte.
  (define checkpoint
    (call-with-input-file (vector-ref args 0)
      (lambda (in) (read-bytes (add1 (hash-ref replay-limits 'bytes)) in))))
  (define commands (call-with-input-file (vector-ref args 1) read-json))
  (define input (open-input-string
                 (apply string-append (map (lambda (c) (string-append c "\n")) commands))))
  (define output (open-output-string))
  (define at-restore #f)
  (with-handlers ([exn:fail:replay-restore?
                   (lambda (e) (eprintf "~a\n" (exn-message e)) (exit 1))])
    (define result
      (zork-restore checkpoint #:input input #:output output
                    #:wall-clock (make-fixed-mdl-clock 1900000000)
                    #:on-restored
                    (lambda (s)
                      (define snap (mdl-session-random-snapshot s))
                      (set! at-restore
                            (hasheq 'rng (random36-state-words snap)
                                    'draws (random36-state-draws snap)
                                    'state (zork-replay-state s))))))
    (write-json (hasheq 'at_restore at-restore
                        'output (get-output-string output)
                        'kind (symbol->string (replay-result-kind result))
                        'end_state (zork-replay-state (replay-result-session result))))
    (newline)
    (flush-output))
  (exit 0))
