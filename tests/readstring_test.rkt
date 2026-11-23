#lang racket/base
;; S7 (ADR-0050): <READSTRING buffer channel [stop]> on the terminal INCHAN,
;; as RDCOM (77rooms.mud:616, READER-STRING = ESC CR LF) and YES/NO
;; (77defs.mud:434) use it, plus end of input (maintainer decision D3,
;; "Mirror, then strict") and RESET's end-of-input flag.
;; Reference: evidence/M3/S7-frontier/primitives-reference.json
;; (readstring-*, reset-buffer-discard), extra2-reference.json
;; (eof-sequence-then-reset), boot-reference.json (boot-six, boot-eof-midline,
;; boot-edge-lines, boot-six-crlf).
(require rackunit racket/port racket/file
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))

(define prelude "<SETG RS <STRING <ASCII 27> <ASCII 13> <ASCII 10>>> <SETG B <ISTRING 10>> ")
;; Run PRELUDE + SOURCE in a fresh context reading INPUT (a string or port).
;; Returns (values last-value written-text input-port).
(define (run* source #:input [input ""] #:out [out (open-output-string)])
  (define in (if (string? input) (open-input-string input) input))
  (define value
    (parameterize ([current-namespace ns])
      (call-with-mdl-context
       (make-mdl-context #:input-port in #:output-port out)
       (lambda ()
         (for/fold ([result #f])
                   ([expr (in-list (compile-program (parse-mdl (string-append prelude source))))])
           (eval expr))))))
  (values value (if (string-port? out) (get-output-string out) #f) in))
(define (value-of source #:input [input ""])
  (let-values ([(v _o _i) (run* source #:input input)]) v))
(define (pname value) (and (mdl-atom? value) (mdl-atom-pname value)))
(define (true? value) (equal? (pname value) "T"))
(define (nul n) (make-string n #\nul))
(define rd "<READSTRING ,B ,INCHAN ,RS>")
;; Collect several results in one run as an MDL LIST of FIX/STRING values.
(define (results source #:input input #:setup [setup ""])
  (mdl-list->list (value-of (string-append setup " (" source ")") #:input input)))

;; --- basic read: count, buffer, stop character consumed ----------------------
(let-values ([(v out in) (run* (string-append "(" rd " ,B)") #:input "Hello\nrest\n")])
  (check-equal? (mdl-list->list v) (list 5 (string-append "Hello" (nul 5))))
  (check-equal? out "")                       ; no echo, nothing written
  (check-equal? (port->string in) "rest\n"))  ; LF consumed, next line unread
(check-equal? (pname (value-of (string-append "<TYPE " rd ">") #:input "x\n")) "FIX")
;; Case is preserved (LEX upper-cases later).
(check-equal? (results (string-append rd " ,B") #:input "NoRtH\n")
              (list 5 (string-append "NoRtH" (nul 5))))
;; Stale characters stay after a shorter read (YES/NO relies on <1 .INBUF>).
(check-equal? (results (string-append rd " " rd " ,B") #:input "north\nwest\n")
              (list 5 4 (string-append "westh" (nul 5))))
;; An empty line reads 0 and leaves the buffer as it was.
(check-equal? (results (string-append rd " ,B") #:input "\nnorth\n")
              (list 0 (nul 10)))
;; ESC ends a command; CR is a stop character, so CRLF gives an extra empty
;; read (Confusion boot-edge-lines, boot-six-crlf).
(check-equal? (results (string-append rd " " rd) #:input "we\ast\n")
              (list 5 0))
(check-equal? (results (string-append rd " " rd) #:input "west\x1binventory\n")
              (list 4 9))
(check-equal? (results (string-append rd " " rd " " rd) #:input "ab\r\ncd\n")
              (list 2 0 2))
;; A full buffer leaves the rest of the line for the next read
;; (readstring-overflow).
(let-values ([(v _o in)
              (run* "<SETG B <ISTRING 4>> (<READSTRING ,B ,INCHAN ,RS> <STRING ,B>
                      <READSTRING ,B ,INCHAN ,RS> <STRING ,B> <READSTRING ,B ,INCHAN ,RS>)"
                    #:input "abcdefgh\nxy\n")])
  (check-equal? (mdl-list->list v) (list 4 "abcd" 4 "efgh" 0))
  (check-equal? (port->string in) "xy\n"))
;; RDCOM's INBUF is 100 characters; LEX reads <REST .INBUF .INPLEN>.
(check-equal? (results "<READSTRING ,B ,INCHAN ,RS> <LENGTH <REST ,B 12>>"
                       #:setup "<SETG B <ISTRING 100>>" #:input "open mailbox\n")
              (list 12 88))
;; A REST view is written from its own position 1 (readstring-rest-view).
(check-equal? (results "<READSTRING <REST ,B 2> ,INCHAN ,RS> ,B" #:input "xy\n")
              (list 2 (string-append (nul 2) "xy" (nul 6))))
;; Without a stop STRING only a full buffer (or end of input) ends the read.
(let-values ([(v _o in)
              (run* "<SETG B <ISTRING 5>> (<READSTRING ,B ,INCHAN> ,B)" #:input "ab\ncdefg")])
  (check-equal? (mdl-list->list v) (list 5 "ab\ncd"))
  (check-equal? (port->string in) "efg"))
;; A zero-length buffer reads nothing.
(let-values ([(v _o in) (run* "<READSTRING <ISTRING 0> ,INCHAN ,RS>" #:input "abc\n")])
  (check-equal? v 0)
  (check-equal? (port->string in) "abc\n"))
;; YES/NO's local INCHAN and the game's LVAL use.
(check-equal? (value-of "<PROG ((INCHAN ,INCHAN)) <READSTRING ,B .INCHAN ,RS>>" #:input "y\n") 1)

;; --- end of input: mirror once, then strict (D3) ----------------------------
(define exhausted-message
  (string-append "READSTRING: input exhausted: the session input ended and the "
                 "mirrored end-of-input read was already returned "
                 "(maintainer decision D3; ADR-0050)"))
(define (exhausted? e)
  (and (exn:fail:mdl-input-exhausted? e) (equal? (exn-message e) exhausted-message)))
;; First read at end of input returns 0 (RDCOM: "Beg pardon?"), the next raises.
(check-equal? (results rd #:input "") (list 0))
(check-exn exhausted? (lambda () (value-of (string-append rd " " rd) #:input "")))
;; After the last command line: one 0-count read, then the strict error.
(check-equal? (results (string-append rd " " rd) #:input "score\n") (list 5 0))
(check-exn exhausted? (lambda () (value-of (string-append rd " " rd " " rd) #:input "score\n")))
;; End of input in mid-line returns the partial count and sets the flag
;; (boot-eof-midline: "west" is executed, then the error follows).
(check-equal? (results (string-append rd " ,B") #:input "west")
              (list 4 (string-append "west" (nul 6))))
(check-exn exhausted? (lambda () (value-of (string-append rd " " rd) #:input "west")))
;; The flag stays set after the error: every later read fails too.
(check-exn exhausted?
           (lambda ()
             (value-of (string-append rd " <PROG () " rd ">") #:input "")))
;; RESET clears the flag: one more 0-count read, then the error
;; (Confusion eof-sequence-then-reset).
(check-equal? (results (string-append rd " <PROG () <RESET ,INCHAN> " rd ">") #:input "")
              (list 0 0))
(check-exn exhausted?
           (lambda ()
             (value-of (string-append rd " <RESET ,INCHAN> " rd " " rd) #:input "")))
;; RESET does not discard queued input (reset-buffer-discard has no lookahead
;; here: READSTRING never peeks).
(check-equal? (results (string-append "<PROG () <RESET ,INCHAN> " rd "> ,B") #:input "abc\n")
              (list 3 (string-append "abc" (nul 7))))
;; The error is host-level, not an MDL ERROR: a live ERROR handler never runs.
(let-values ([(failure handled)
              (parameterize ([current-namespace ns])
                (call-with-mdl-context
                 (make-mdl-context #:input-port (open-input-string "")
                                   #:output-port (open-output-string))
                 (lambda ()
                   (define (eval-all source)
                     (for/fold ([r #f]) ([expr (in-list (compile-program (parse-mdl source)))])
                       (eval expr)))
                   (eval-all (string-append prelude "
                      <SETG EH <HANDLER <EVENT \"ERROR\" 8>
                                        <FUNCTION (FRM \"TUPLE\" Z) <SETG HANDLED T>>>>"))
                   ;; The handler is live: an MDL ERROR reaches it.
                   (with-handlers ([exn:fail? void]) (eval-all "<ERROR PROBE>"))
                   (check-true (true? (eval-all "<GASSIGNED? HANDLED>")))
                   (eval-all "<GUNASSIGN HANDLED>")
                   (define failure
                     (with-handlers ([exn:fail? values]) (eval-all (string-append rd " " rd))))
                   (values failure (eval-all "<GASSIGNED? HANDLED>")))))])
  (check-pred exhausted? failure)
  (check-true (mdl-false? handled)))

;; --- output is flushed before a blocking read --------------------------------
(let* ([path (make-temporary-file "mdl-readstring-flush~a")]
       [file-out (open-output-file path #:exists 'truncate)]
       [seen #f]
       [base (open-input-string "go\n")]
       [in (make-input-port 'probe
                            (lambda (bytes)
                              (unless seen (set! seen (file->string path)))
                              (read-bytes-avail!* bytes base))
                            #f void)])
  (dynamic-wind
   void
   (lambda ()
     (define-values (v _o _i) (run* (string-append "<PRINC \">\"> " rd) #:input in #:out file-out))
     (check-equal? v 2)
     (check-equal? seen ">"))
   (lambda () (close-output-port file-out) (delete-file path))))

;; --- strict errors -------------------------------------------------------------
(define (refused rx source #:input [input "abc\n"])
  (check-exn rx (lambda () (value-of source #:input input)) source))
(refused #rx"^READSTRING: READSTRING takes a buffer, a CHANNEL and an optional stop STRING"
         "<READSTRING>")
(refused #rx"^READSTRING: READSTRING takes a buffer, a CHANNEL and an optional stop STRING"
         "<READSTRING ,B>")
(refused #rx"^READSTRING: an EOF routine argument is not supported"
         "<READSTRING ,B ,INCHAN ,RS <>>")
(refused #rx"^READSTRING: READSTRING takes a buffer, a CHANNEL and an optional stop STRING"
         "<READSTRING ,B ,INCHAN ,RS <> 5>")
(refused #rx"^READSTRING: buffer must be a mutable STRING" "<READSTRING 1 ,INCHAN ,RS>")
(refused #rx"^READSTRING: buffer must be a mutable STRING" "<READSTRING \"abc\" ,INCHAN ,RS>")
(refused #rx"^READSTRING: buffer must be a mutable STRING"
         "<NEWTYPE PS STRING> <READSTRING <CHTYPE <ISTRING 3> PS> ,INCHAN ,RS>")
(refused #rx"^READSTRING: READSTRING requires an input channel" "<READSTRING ,B ,OUTCHAN ,RS>")
(refused #rx"^READSTRING: argument must be of type CHANNEL" "<READSTRING ,B 1 ,RS>")
(refused #rx"^READSTRING: READSTRING requires an input channel" "<READSTRING ,B <BACK ,INCHAN> ,RS>")
(refused #rx"^READSTRING: CHANNEL is not open in this MDL session"
         "<READSTRING ,B <CHTYPE [0 \"READ\"] CHANNEL> ,RS>")
(refused #rx"^READSTRING: a FIX stop is not supported" "<READSTRING ,B ,INCHAN 3>")
(refused #rx"^READSTRING: stop must be a STRING" "<READSTRING ,B ,INCHAN FOO>")
;; Non-ASCII is refused. (The `!` escape is no longer refused: S13 part A
;; follows pinned Confusion; see tests/readstring_bang_test.rkt.)
(refused #rx"^READSTRING: non-ASCII character \\(code 233\\)" rd #:input "café\n")
;; Arguments are validated before the end-of-input check.
(refused #rx"^READSTRING: buffer must be a mutable STRING"
         (string-append rd " <READSTRING 1 ,INCHAN ,RS>") #:input "")

;; --- review follow-ups: host-port isolation and cross-session CHANNELs ------
;; A context without a host input port never reads the process's own stdin:
;; READSTRING is a strict error and the (parameterized) stdin stays unread.
(let ([fake-stdin (open-input-string "SECRET\n")])
  (check-exn #rx"^READSTRING: this session's READ CHANNEL has no host-supplied port"
             (lambda ()
               (parameterize ([current-input-port fake-stdin]
                              [current-namespace ns])
                 (call-with-mdl-context
                  (make-mdl-context #:output-port (open-output-string))
                  (lambda ()
                    (for ([expr (in-list (compile-program
                                          (parse-mdl (string-append prelude "<READSTRING ,B ,INCHAN ,RS>"))))])
                      (eval expr)))))))
  (check-equal? (port->string fake-stdin) "SECRET\n"))
;; A CHANNEL from another session is refused by READSTRING (not only RESET).
(let ()
  (define foreign-inchan
    (let-values ([(v _o _i) (run* ",INCHAN")]) v))
  (check-exn #rx"^READSTRING: CHANNEL is not open in this MDL session"
             (lambda ()
               (parameterize ([current-namespace ns])
                 (call-with-mdl-context
                  (make-mdl-context #:input-port (open-input-string "abc\n")
                                    #:output-port (open-output-string))
                  (lambda ()
                    (define buffer
                      (for/fold ([r #f]) ([expr (in-list (compile-program (parse-mdl (string-append prelude ",B"))))])
                        (eval expr)))
                    (mdl-apply "READSTRING" buffer foreign-inchan)))))))
