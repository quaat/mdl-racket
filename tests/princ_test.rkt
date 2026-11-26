#lang racket/base
;; S7 (ADR-0050): <PRINC object [channel]> on a terminal CHANNEL. RDCOM's
;; prompt <PRINC ">"> (77rooms.mud:614), <PRINC !\.> (77rooms.mud:1398),
;; PRINC of a FIX (78melee.mud:524) and SCORE's strings (77rooms.mud:672-696).
;; Reference: evidence/M3/S7-frontier/primitives-reference.json (princ-values,
;; princ-errors, princ-linewidth).
(require rackunit
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))

;; Run SOURCE in a fresh context; return (values last-value written-text).
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

;; --- what is written --------------------------------------------------------
(check-equal? (written "<PRINC \">\">") ">")
(check-equal? (written "<PRINC \"abc\">") "abc")
(check-equal? (written "<PRINC \"\">") "")
(check-equal? (written "<PRINC <REST \"abcd\" 2>>") "cd")
(check-equal? (written "<PRINC !\\.>") ".")
(check-equal? (written "<PRINC <ASCII 65>>") "A")
(check-equal? (written "<PRINC 42>") "42")
(check-equal? (written "<PRINC -7>") "-7")
(check-equal? (written "<PRINC 0>") "0")
;; CR and LF are written raw (game strings contain the source's CR LF).
(check-equal? (written "<PRINC <STRING \"a\" <ASCII 13> <ASCII 10> \"b\">>") "a\r\nb")
(check-equal? (written "<PRINC \"x\" ,OUTCHAN> <PRINC \"y\" .OUTCHAN>") "xy")
;; The default channel is the LVAL of OUTCHAN (RDCOM binds it as an AUX).
(check-equal? (written "<PROG ((OUTCHAN ,OUTCHAN)) <PRINC \"p\">>") "p")
(check-exn #rx"^PRINC: PRINC requires an output channel"
           (lambda () (written "<PROG ((OUTCHAN ,INCHAN)) <PRINC \"p\">>")))

;; --- value: the object itself -------------------------------------------------
(check-true (true? (value-of "<SET S \"abc\"> <==? <PRINC .S> .S>")))
(check-equal? (pname (value-of "<TYPE <PRINC \"\">>")) "STRING")
(check-equal? (pname (value-of "<TYPE <PRINC !\\.>>")) "CHARACTER")
(check-equal? (value-of "<PRINC 42>") 42)

;; --- line breaking (M4 #173, superseding the ADR-0050 deviation) -----------
;; As Confusion: when the width (slot 13) is nonzero and the column (slot 14)
;; is positive, an object that does not fit starts a new line
;; (primitives-reference princ-linewidth; i173 width-* cases).
(check-equal? (written "<PUT ,OUTCHAN 13 10> <PRINC \"aaaaaaaa\"> <PRINC \"bbbbbbbb\"> <PRINC 12345678901>")
              "aaaaaaaa\nbbbbbbbb\n12345678901")
(check-equal? (written "<PUT ,OUTCHAN 13 10> <PRINC \"aaaa\"> <PRINC \"bbbbbbbb\"> <PRINC \"cc\"> <PRINTSTRING \"dddddddddd\"> <PRINC \"ee\">")
              "aaaa\nbbbbbbbbccdddddddddd\nee")
;; At column 0 nothing breaks, however long; width 0 never breaks.
(check-equal? (written "<PUT ,OUTCHAN 13 5> <PRINC \"abcdefghij\">") "abcdefghij")
(check-equal? (written "<PUT ,OUTCHAN 13 0> <PRINC \"aaaaaaaa\"> <PRINC \"bbbbbbbb\">")
              "aaaaaaaabbbbbbbb")
(check-equal? (written "<PUT ,OUTCHAN 13 1000> <PRINC \">\">") ">")

;; --- strict errors -------------------------------------------------------------
(define (refused rx source)
  (check-exn rx (lambda () (written source)) source))
(refused #rx"^PRINC: PRINC takes an object and an optional CHANNEL" "<PRINC>")
(refused #rx"^PRINC: PRINC takes an object and an optional CHANNEL"
         "<PRINC \"x\" ,OUTCHAN 3>")
(refused #rx"^PRINC: PRINC requires an output channel" "<PRINC \"x\" ,INCHAN>")
(refused #rx"non-channel" "<PRINC \"x\" 1>")
(refused #rx"^PRINC: .*not open in this MDL session"
         "<PRINC \"x\" <CHTYPE [0 \"PRINT\"] CHANNEL>>")
;; Control characters other than CR and LF (Confusion prints ^X notation).
(refused #rx"^PRINC: control character \\(code 27\\)" "<PRINC <STRING <ASCII 27> \"z\">>")
(refused #rx"^PRINC: control character \\(code 9\\)" "<PRINC <ASCII 9>>")
(refused #rx"^PRINC: control character \\(code 127\\)" "<PRINC <STRING <ASCII 127>>>")
;; Unmodelled TYPEs.
(refused #rx"^PRINC: unsupported TYPE ATOM" "<PRINC FOO>")
(refused #rx"^PRINC: unsupported TYPE LIST" "<PRINC (1 \"s\" !\\c)>")
(refused #rx"^PRINC: unsupported TYPE FLOAT" "<PRINC 1.5>")
(refused #rx"^PRINC: unsupported TYPE FALSE" "<PRINC <>>")
(refused #rx"^PRINC: unsupported TYPE VECTOR" "<PRINC [1]>")
(refused #rx"^PRINC: unsupported TYPE" "<NEWTYPE PS STRING> <PRINC <CHTYPE \"ab\" PS>>")
;; A refused object writes nothing, not even a prefix.
(let ([out (open-output-string)])
  (check-exn #rx"control character"
             (lambda ()
               (parameterize ([current-namespace ns])
                 (call-with-mdl-context
                  (make-mdl-context #:output-port out)
                  (lambda ()
                    (for ([expr (in-list (compile-program
                                          (parse-mdl "<PRINC <STRING \"ab\" <ASCII 27>>>")))])
                      (eval expr)))))))
  (check-equal? (get-output-string out) ""))
