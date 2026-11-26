#lang racket/base
;; S7 (ADR-0050): <PRIN1 object [channel]> for SCORE's FIX values
;; (77rooms.mud:675-680) and for the host loop's print of the entry value
;; (maintainer decision D1: SAVE-IT's ,NULL, an ATOM with an empty PNAME).
;; Reference: evidence/M3/S7-frontier/primitives-reference.json
;; (rep-value-printing-null-atom) and extra-reference.json (boot-null-marker).
(require rackunit
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))

(define (run* source)
  (define out (open-output-string))
  (define value
    (parameterize ([current-namespace ns])
      (call-with-mdl-context
       (make-mdl-context #:input-port (open-input-string "") #:output-port out)
       (lambda ()
         (for/fold ([result #f])
                   ([expr (in-list (compile-program (parse-mdl source)))])
           (eval expr))))))
  (values value (get-output-string out)))
(define (written source) (let-values ([(_ text) (run* source)]) text))
(define (value-of source) (let-values ([(v _) (run* source)]) v))
(define (pname value) (and (mdl-atom? value) (mdl-atom-pname value)))
(define (true? value) (equal? (pname value) "T"))

;; --- FIX ------------------------------------------------------------------
(check-equal? (written "<PRIN1 0>") "0")
(check-equal? (written "<PRIN1 500>") "500")
(check-equal? (written "<PRIN1 -12>") "-12")
(check-equal? (written "<PRIN1 6 ,OUTCHAN>") "6")
(check-equal? (written "<PROG ((OUTCHAN ,OUTCHAN)) <PRIN1 7>>") "7")
(check-equal? (value-of "<PRIN1 500>") 500)
;; SCORE's shape: PRINC and PRIN1 interleaved, no separators added.
(check-equal? (written "<PRINC \"Your score would be \"> <PRIN1 0> <PRINC \" [total of \"> <PRIN1 500>")
              "Your score would be 0 [total of 500")
;; Line breaking at the CHANNEL width (M4 #173, superseding the ADR-0050
;; "no line breaking" deviation): a token that does not fit after a positive
;; column starts a new line (Confusion width-prin1-positive-column).
(check-equal? (written "<PUT ,OUTCHAN 13 3> <PRIN1 12345> <PRIN1 67890>") "12345\n67890")
(check-equal? (written "<PUT ,OUTCHAN 13 10> <PRINC \"abcdefgh\"> <PRIN1 12> <PRIN1 3>")
              "abcdefgh12\n3")

;; --- ATOM -------------------------------------------------------------------
;; The game's NULL (81tell-repl.mud): an empty PNAME inserted on ROOT prints
;; nothing (Confusion rep-value-printing-null-atom).
(check-equal? (written "<SETG NULL <INSERT <ATOM \"\"> <ROOT>>> <PRIN1 ,NULL>") "")
(check-true (true? (value-of "<SETG NULL <INSERT <ATOM \"\"> <ROOT>>> <==? <PRIN1 ,NULL> ,NULL>")))
;; A reachable ATOM with a plain PNAME prints its PNAME (UNPARSE rules).
(check-equal? (written "<PRIN1 FOO>") "FOO")
(check-equal? (written "<PRIN1 T>") "T")
;; Not reachable on the OBLIST path: Confusion prints a trailer; refused.
(check-exn #rx"^PRIN1: .*trailer"
           (lambda () (written "<PRIN1 <ATOM \"\">>")))
(check-exn #rx"^PRIN1: .*trailer"
           (lambda () (written "<PRIN1 <ATOM \"BAR\">>")))
;; PNAMEs needing escapes are refused.
(check-exn #rx"^PRIN1: .*not in safe-char whitelist"
           (lambda () (written "<PRIN1 A\\ B>")))

;; --- strict errors -----------------------------------------------------------
(define (refused rx source)
  (check-exn rx (lambda () (written source)) source))
(refused #rx"^PRIN1: PRIN1 takes an object and an optional CHANNEL" "<PRIN1>")
(refused #rx"^PRIN1: PRIN1 takes an object and an optional CHANNEL" "<PRIN1 1 ,OUTCHAN 2>")
(refused #rx"^PRIN1: PRIN1 requires an output channel" "<PRIN1 1 ,INCHAN>")
(refused #rx"non-channel" "<PRIN1 1 2>")
(refused #rx"^PRIN1: unsupported TYPE VECTOR" "<PRIN1 [1]>")
(refused #rx"^PRIN1: unsupported TYPE FORM" "<PRIN1 '<FOO>>")
(refused #rx"^PRIN1: unsupported TYPE FLOAT" "<PRIN1 1.5>")
;; Nothing is written for a refused object.
(let ([out (open-output-string)])
  (check-exn #rx"unsupported TYPE"
             (lambda ()
               (parameterize ([current-namespace ns])
                 (call-with-mdl-context
                  (make-mdl-context #:output-port out)
                  (lambda ()
                    (for ([expr (in-list (compile-program (parse-mdl "<PRIN1 [1]>")))])
                      (eval expr)))))))
  (check-equal? (get-output-string out) ""))

;; --- STRING, CHARACTER, LIST, FALSE (M4 #173; Confusion i173-print-reference) ---
(check-equal? (written "<PRIN1 \"abc\">") "\"abc\"")
(check-equal? (written "<PRIN1 \"a\\\"b\\\\c\">") "\"a\\\"b\\\\c\"")
(check-equal? (written "<PRIN1 !\\a>") "!\\a")
(check-equal? (written "<PRIN1 (1)>") "(1)")
(check-equal? (written "<PRIN1 (1 (2 (3 ())) ())>") "(1 (2 (3 ())) ())")
(check-equal? (written "<PRIN1 <>>") "#FALSE ()")
(check-equal? (written "<PRIN1 #FALSE (1 \"x\")>") "#FALSE (1 \"x\")")
