#lang racket/base
;; S13 part A (ADR-0050 §3 as amended 2026-11-23): the `!` escape in terminal
;; input read by <READSTRING buffer channel stop>, following pinned Confusion
;; by maintainer decision. One assertion group per direct reference case in
;; docs/evidence/M3/READSTRING-BANG-REFERENCE.md (readstring-bang-probe.json),
;; with the same buffer (<ISTRING n !\.>) and stop string (READER-STRING =
;; ESC CR LF) as the probes. The game-level check (RDCOM, `nor!th`) is in
;; tests/historical_bang_input_test.rkt.
(require rackunit racket/port
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))

(define prelude "<SETG RS <STRING <ASCII 27> <ASCII 13> <ASCII 10>>> ")
;; Run PRELUDE + <SETG B <ISTRING size !\.>> + SOURCE in a fresh context that
;; reads INPUT (a string, or bytes for raw byte input). Returns
;; (values last-value input-port).
(define (run* source #:input input #:size [size 10])
  (define in (if (bytes? input) (open-input-bytes input) (open-input-string input)))
  (define value
    (parameterize ([current-namespace ns])
      (call-with-mdl-context
       (make-mdl-context #:input-port in #:output-port (open-output-string))
       (lambda ()
         (for/fold ([result #f])
                   ([expr (in-list (compile-program
                                    (parse-mdl (string-append
                                                prelude
                                                (format "<SETG B <ISTRING ~a !\\.>> " size)
                                                source))))])
           (eval expr))))))
  (values value in))
;; One READSTRING into ,B followed by a copy of ,B.
(define rd "<READSTRING ,B ,INCHAN ,RS> <STRING ,B>")
;; Results of SOURCE (a sequence of forms) as a Racket list.
(define (results source #:input input #:size [size 10])
  (let-values ([(v _in) (run* (string-append "(" source ")") #:input input #:size size)])
    (mdl-list->list v)))
(define (reads n #:input input #:size [size 10])
  (results (apply string-append (for/list ([_ (in-range n)]) (string-append rd " ")))
           #:input input #:size size))
(define (dots n) (make-string n #\.))

(define exhausted-message
  (string-append "READSTRING: input exhausted: the session input ended and the "
                 "mirrored end-of-input read was already returned "
                 "(maintainer decision D3; ADR-0050)"))
(define (exhausted? e)
  (and (exn:fail:mdl-input-exhausted? e) (equal? (exn-message e) exhausted-message)))

;; bang-mid (41 62 21 63 44 0a): 4, "AbcD"; the `!` is removed, case is kept.
(check-equal? (reads 1 #:input "Ab!cD\n") (list 4 (string-append "AbcD" (dots 6))) "bang-mid")
;; bang-double (21 21 0a): `!!` gives one `!`.
(check-equal? (reads 1 #:input "!!\n") (list 1 (string-append "!" (dots 9))) "bang-double")
;; bang-double-between (61 21 21 62 0a): 3, "a!b".
(check-equal? (reads 1 #:input "a!!b\n") (list 3 (string-append "a!b" (dots 7)))
              "bang-double-between")
;; bang-multiple (21 61 21 62 21 63 0a): every `!` dropped and not counted.
(check-equal? (reads 1 #:input "!a!b!c\n") (list 3 (string-append "abc" (dots 7)))
              "bang-multiple")
;; bang-before-lf (61 62 21 0a 58 59 0a): an escaped LF still stops; it is
;; consumed and not stored; the next read gets "XY".
(check-equal? (reads 2 #:input "ab!\nXY\n")
              (list 2 (string-append "ab" (dots 8)) 2 (string-append "XY" (dots 8)))
              "bang-before-lf")
;; bang-before-cr (61 62 21 0d 58 59 0a).
(check-equal? (reads 2 #:input "ab!\rXY\n")
              (list 2 (string-append "ab" (dots 8)) 2 (string-append "XY" (dots 8)))
              "bang-before-cr")
;; bang-before-crlf (61 62 21 0d 0a 63 64 0a): 2, then 0 (the LF), then 2.
(check-equal? (reads 3 #:input "ab!\r\ncd\n")
              (list 2 (string-append "ab" (dots 8))
                    0 (string-append "ab" (dots 8))
                    2 (string-append "cd" (dots 8)))
              "bang-before-crlf")
;; bang-before-esc (61 62 21 1b 58 59 0a): an escaped ESC (altmode) stops.
(check-equal? (reads 2 #:input "ab!\x1bXY\n")
              (list 2 (string-append "ab" (dots 8)) 2 (string-append "XY" (dots 8)))
              "bang-before-esc")
;; bang-before-tab (61 21 09 62 0a): 3, codes 97 9 98.
(check-equal? (reads 1 #:input "a!\tb\n") (list 3 (string-append "a\tb" (dots 7)))
              "bang-before-tab")
;; bang-before-backslash (61 21 5c 62 0a): 3, codes 97 92 98.
(check-equal? (reads 1 #:input "a!\\b\n") (list 3 (string-append "a\\b" (dots 7)))
              "bang-before-backslash")
;; backslash-plain (61 5c 62 0a): `\` is not an escape in READSTRING.
(check-equal? (reads 1 #:input "a\\b\n") (list 3 (string-append "a\\b" (dots 7)))
              "backslash-plain")
;; bang-before-eof (61 62 21, EOF): the trailing `!` is stored literally and
;; counted; the read sets the end-of-input flag, so the next READSTRING meets
;; the D3 strict error at once (Confusion: Error: Unexpected EOF).
(check-equal? (reads 1 #:input "ab!") (list 3 (string-append "ab!" (dots 7)))
              "bang-before-eof")
(check-exn exhausted? (lambda () (reads 2 #:input "ab!")) "bang-before-eof, second read")
;; bang-only-eof (21, EOF): 1, "!", then the strict error.
(check-equal? (reads 1 #:input "!") (list 1 (string-append "!" (dots 9))) "bang-only-eof")
(check-exn exhausted? (lambda () (reads 2 #:input "!")) "bang-only-eof, second read")
;; bang-buffer-boundary-last-slot (buffer 3; 61 62 21 63 64 0a): the `!c`
;; pair takes the last slot; the read stops with the buffer full; the next
;; read gets "d" (buffer "dbc").
(check-equal? (reads 2 #:input "ab!cd\n" #:size 3) (list 3 "abc" 1 "dbc")
              "bang-buffer-boundary-last-slot")
;; bang-buffer-boundary-straddle (buffer 2; 61 62 21 63 64 0a): the next read
;; starts at `!` and escapes as usual.
(check-equal? (reads 2 #:input "ab!cd\n" #:size 2) (list 2 "ab" 2 "cd")
              "bang-buffer-boundary-straddle")
(let-values ([(v in) (run* (string-append "(" rd ")") #:input "ab!cd\n" #:size 2)])
  (check-equal? (port->string in) "!cd\n" "the unit after a full buffer stays unread"))
;; bang-buffer-boundary-2 (buffer 2; 61 21 62 63 0a): "ab", then "c" ("cb").
(check-equal? (reads 2 #:input "a!bc\n" #:size 2) (list 2 "ab" 1 "cb")
              "bang-buffer-boundary-2")
;; bang-fix-stop: a FIX stop stays a strict unsupported error in this runtime
;; (ADR-0050 §3), so this reference case cannot be exercised.
(check-exn #rx"^READSTRING: a FIX stop is not supported"
           (lambda () (results "<READSTRING ,B ,INCHAN 3>" #:input "!abcd\n"))
           "bang-fix-stop (not modelled)")

;; --- no loosening of non-ASCII validation ------------------------------------
;; bang-before-nonascii (61 21 e9 62 0a): Confusion stores the raw byte
;; (ASCII -23); here the escaped character passes the same > 127 check as
;; any other input and is refused (known deviation, unchanged).
(check-exn #rx"^READSTRING: non-ASCII character \\(code 233\\)"
           (lambda () (reads 1 #:input "a!éb\n")) "bang-before-nonascii (decoded)")
(check-exn #rx"^READSTRING: non-ASCII character \\(code 65533\\)"
           (lambda () (reads 1 #:input (bytes #x61 #x21 #xe9 #x62 #x0a)))
           "bang-before-nonascii (raw byte, decoded as U+FFFD)")
(check-exn #rx"^READSTRING: non-ASCII character \\(code 233\\)"
           (lambda () (reads 1 #:input "aéb\n")) "nonascii without !")
;; The escape does not make a non-ASCII character in the last slot valid.
(check-exn #rx"^READSTRING: non-ASCII character"
           (lambda () (reads 1 #:input "ab!é" #:size 3)))
