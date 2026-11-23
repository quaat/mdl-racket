#lang racket/base
;; Historical regression (S13 part A, ADR-0050 §3 as amended 2026-11-23): the
;; `!` escape in terminal input, read by the game's own RDCOM
;; (<READSTRING .INBUF ,INCHAN .STR>, 77rooms.mud:616; INBUF <ISTRING 100>,
;; READER-STRING ESC CR LF). Each case loads 77loadall.mud into a fresh session
;; on the reference clock (fixed epoch 250776000, zone UTC; ADR-0052), runs
;; SAVE-IT and RDCOM through the host top-level loop on the case's typed
;; bytes, and compares the transcript with the pinned Confusion game case in
;; docs/evidence/M3/readstring-bang-probe.json: canonical_text(raw) against
;; the reference text after LISTENING-AT-LEVEL with its "DONE" line (FLOAD's
;; REP print) removed (D1). The reference cases are pipe captures, so no ONLCR
;; is applied on either side (unlike the PTY-rendered house-boot golden, D2). Every run must end with the D3
;; input-exhausted error (Confusion: Error: Unexpected EOF). In particular
;; `nor!th` must behave exactly like `north`.
;;
;; Not covered: game-nonascii (Confusion stores the raw byte; this runtime
;; refuses it, a recorded deviation) and the pty cases (same results as pipe).
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: make test-m3-bang   (or: raco test tests/historical_bang_input_test.rkt)
(require rackunit racket/runtime-path racket/port racket/string racket/list json
         "../mdl/loader.rkt")

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(define-runtime-path probe-file "../docs/evidence/M3/readstring-bang-probe.json")
(unless (directory-exists? source-root)
  (error 'historical-bang-input "pinned source missing: ~a" source-root))

(define probe (call-with-input-file probe-file read-json))
(check-equal? (hash-ref probe 'interpreter_sha256)
              "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789")
(check-equal? (hash-ref probe 'upstream_mdlzork_commit)
              "bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3")
(define (probe-case name)
  (or (for/first ([c (in-list (hash-ref probe 'cases))]
                  #:when (equal? (hash-ref c 'name) name))
        c)
      (error 'historical-bang-input "no reference case ~a" name)))

(define fixed-epoch 250776000)
(define (canonical-text text)        ; scripts/boot_reference.py canonical_text
  (string-replace (string-replace text "\r\n" "\n") "\r" "\n"))
(define (remove-line-once text line)
  (define n (length (regexp-match* (regexp-quote line) text)))
  (unless (= n 1) (error 'remove-line-once "expected one ~s, found ~a" line n))
  (string-replace text line "" #:all? #f))

;; Play TYPED (the bytes after <SAVE-IT>) in a fresh session. Returns
;; (values failure canonical-transcript).
(define (play typed)
  (define input (open-input-string typed))
  (define output (open-output-string))
  (define session (make-mdl-session source-root #:input-port input #:output-port output
                                    #:clock (make-fixed-mdl-clock fixed-epoch)
                                    #:time-zone 'utc))
  (define report (mdl-session-load! session "77loadall.mud"))
  (check-equal? (hash-ref report 'status) "PASS")
  (define failure
    (let* ([result (make-channel)]
           [worker (thread
                    (lambda ()
                      (channel-put result
                                   (with-handlers ([exn:fail? values])
                                     (mdl-session-run-interactive session "SAVE-IT")
                                     'returned))))])
      (or (sync/timeout 300 result)
          (begin (kill-thread worker) 'timed-out))))
  (values failure (canonical-text (get-output-string output))))

(define (reference-case name)
  (define c (probe-case name))
  (check-equal? (hash-ref c 'exit_status) 0 name)
  (check-true (hash-ref c 'fixed_clock) name)
  (check-equal? (hash-ref c 'mode) "pipe" name)
  (check-equal? (hash-ref c 'stderr_raw) "Error: Unexpected EOF\n" name)
  (define input (hash-ref c 'input))
  (define prefix "<FLOAD \"77loadall.mud\">\n<SAVE-IT>\n")
  (check-true (string-prefix? input prefix) name)
  (values (substring input (string-length prefix))
          (remove-line-once (hash-ref c 'result_after_listening) "\"DONE\"\n")))

(define (check-game-case name #:typed [expected-typed #f])
  (define-values (typed expected) (reference-case name))
  (when expected-typed (check-equal? typed expected-typed name))
  (define-values (failure transcript) (play typed))
  (check-pred exn:fail:mdl-input-exhausted? failure
              (format "~a: ~a" name (if (exn? failure) (exn-message failure) failure)))
  (check-equal? transcript expected name)
  transcript)

(define north (check-game-case "game-baseline-north" #:typed "north\n"))
(check-true (string-contains? north ">You are facing the north side of a white house."))
;; nor!th and !north behave exactly like north.
(check-equal? (check-game-case "game-bang-mid-word" #:typed "nor!th\n") north)
(check-equal? (check-game-case "game-bang-first" #:typed "!north\n") north)
(void (check-game-case "game-mixed-case-bang" #:typed "Ab!cD\n"))       ; I don't know the word ABCD
(void (check-game-case "game-bang-double" #:typed "!!\n"))              ; Huh?
(void (check-game-case "game-bang-before-lf" #:typed "north!\nwest\n")) ; escaped LF still ends it
(void (check-game-case "game-bang-before-esc" #:typed "north!\ewest\n"))
;; north! at EOF: north runs (INBUF "north!", 6), then no "Beg pardon?".
(define eof-transcript (check-game-case "game-bang-before-eof" #:typed "north!"))
(check-false (string-contains? eof-transcript "Beg pardon?"))
(void (check-game-case "game-buffer-boundary"))                       ; `!y` in slot 100
