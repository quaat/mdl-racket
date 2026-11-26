#lang racket/base
;; M4 #173: <PRINT object [channel]> (manual 11.1.2.1), PRIN1 of STRING,
;; CHARACTER, LIST and FALSE, and the CHANNEL line width / column (elements
;; 13 and 14, manual 11.1.2 and 11.2.8.1). Contract: docs/SEMANTICS.md
;; "M4 #173". Reference: docs/evidence/M4/i173-print-reference-raw.json (exact
;; stdout bytes of pinned Confusion 6df359f6..., cases in
;; i173-print-cases.json).
(require rackunit racket/runtime-path racket/list json
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define-runtime-path cases-path "../docs/evidence/M4/i173-print-cases.json")
(define-runtime-path raw-path "../docs/evidence/M4/i173-print-reference-raw.json")

;; Run SOURCE in a fresh context with its own output port. Every top-level
;; form is compiled and evaluated; when LISTEN? the value is then printed as
;; Confusion's LISTEN does (PRIN1, then a newline), through this runtime's own
;; PRIN1 and TERPRI on the same CHANNEL. Returns (values last-value text).
(define (run* source #:listen? [listen? #f])
  (define out (open-output-string))
  (define value
    (parameterize ([current-namespace ns])
      (call-with-mdl-context
       (make-mdl-context #:input-port (open-input-string "") #:output-port out)
       (lambda ()
         (for/fold ([result #f])
                   ([expr (in-list (compile-program (parse-mdl source)))])
           (define v (eval expr))
           (when listen?
             (mdl-apply (mdl-root-atom "PRIN1") v)
             (mdl-apply (mdl-root-atom "TERPRI")))
           v)))))
  (values value (get-output-string out)))
(define (written source) (let-values ([(_ text) (run* source)]) text))
(define (value-of source) (let-values ([(v _) (run* source)]) v))
(define (pname value) (and (mdl-atom? value) (mdl-atom-pname value)))
(define (true? value) (equal? (pname value) "T"))

;; A refused call raises RX and writes nothing at all (not even PRINT's
;; leading newline): the text of SETUP (run first, must succeed) is the
;; whole output.
(define (refused rx source #:setup [setup ""])
  (define out (open-output-string))
  (check-exn rx
             (lambda ()
               (parameterize ([current-namespace ns])
                 (call-with-mdl-context
                  (make-mdl-context #:output-port out)
                  (lambda ()
                    (for ([expr (in-list (compile-program (parse-mdl (string-append setup " " source))))])
                      (eval expr))))))
             source)
  (check-equal? (get-output-string out) (written setup) (string-append "nothing written: " source)))

;; --- differential: every case this runtime supports, byte for byte ----------
(define cases
  (for/hash ([c (in-list (hash-ref (call-with-input-file cases-path read-json) 'cases))])
    (values (hash-ref c 'name) (hash-ref c 'expression))))
(define native
  (for/hash ([c (in-list (hash-ref (call-with-input-file raw-path read-json) 'cases))])
    (values (hash-ref c 'name) c)))
(define supported
  '("print-fix" "print-negative-fix" "print-atom" "print-empty-pname-atom"
    "print-string-escapes" "print-character" "print-list" "print-nested-list"
    "print-false" "print-return-identity" "print-no-mutation" "print-eval-once"
    "print-explicit-channel" "print-binds-outchan-default-lval"
    "default-width-and-column"
    "width-print-list-breaks" "width-print-close-paren-break"
    "width-print-resets-column" "width-print-scalar-at-zero"
    "width-print-column-readback" "width-prin1-positive-column"
    "width-prin1-exact-fit" "width-princ-column-zero" "width-zero-no-tracking"
    "width-printstring-lf-counted" "width-princ-cr-resets"
    "width-terpri-crlf-reset" "width-list-of-strings" "width-nested-list"
    "width-false-breaks" "width-empty-list-token" "width-character-token"
    "width-empty-pname-atom" "width-handle-80" "print-type-subr"
    "width-image-no-advance"))
(for ([name (in-list supported)])
  (define row (hash-ref native name))
  ;; The native run itself was clean for every supported case.
  (check-equal? (hash-ref row 'stderr_bytes) "" name)
  (check-equal? (hash-ref row 'exit_code) 0 name)
  (define-values (_ text) (run* (hash-ref cases name) #:listen? #t))
  (check-equal? text (hash-ref row 'result_bytes) name))
;; Every case of the reference file is classified here.
(check-equal? (sort (append supported
                            '("print-form" "print-vector" "print-chtype-newtype-list"
                              "print-chtype-newtype-string" "print-arity-0"
                              "print-arity-3" "print-non-channel"
                              "print-input-channel" "error-handler-native"
                              ;; control characters: checked case by case below
                              "width-printstring-control-counts-2"
                              "printstring-control-chars"
                              "prin1-string-control-chars"))
                    string<?)
              (sort (hash-keys native) string<?))

;; --- PRINT: what is written ------------------------------------------------------
(check-equal? (written "<PRINT 42>") "\n42 ")
(check-equal? (written "<PRINT -17>") "\n-17 ")
(check-equal? (written "<PRINT FOO>") "\nFOO ")
(check-equal? (written "<PRINT \"a\\\"b\\\\c\">") "\n\"a\\\"b\\\\c\" ")
(check-equal? (written "<PRINT !\\A>") "\n!\\A ")
(check-equal? (written "<PRINT (1 FOO \"x\" !\\c ())>") "\n(1 FOO \"x\" !\\c ()) ")
(check-equal? (written "<PRINT <>>") "\n#FALSE () ")
(check-equal? (written "<PRINT #FALSE (1 \"x\")>") "\n#FALSE (1 \"x\") ")
(check-equal? (written "<SETG NULL <INSERT <ATOM \"\"> <ROOT>>> <PRINT ,NULL>") "\n ")
(check-equal? (written "<PRINT <REST \"abcd\" 2>>") "\n\"cd\" ")
;; The newline is the line feed TERPRI writes.
(check-equal? (written "<TERPRI> <PRINT 1>") (string-append (written "<TERPRI>") "\n1 "))

;; --- channel: default LVAL of OUTCHAN, explicit argument ---------------------------
(check-equal? (written "<PRINT 1 .OUTCHAN> <PRINT 2 ,OUTCHAN>") "\n1 \n2 ")
(check-equal? (written "<PROG ((OUTCHAN ,OUTCHAN)) <PRINT 7>>") "\n7 ")

;; --- value: the object itself, evaluated once ------------------------------------
(check-equal? (value-of "<PRINT 42>") 42)
(check-true (true? (value-of "<SET L (1 2)> <==? <PRINT .L> .L>")))
(check-true (true? (value-of "<SET S \"ab\"> <==? <PRINT .S> .S>")))
(check-true (true? (value-of "<SET F #FALSE (1)> <==? <PRINT .F> .F>")))
(check-equal? (pname (value-of "<TYPE <PRINT !\\a>>")) "CHARACTER")
(check-equal? (pname (value-of "<TYPE <PRINT <>>>")) "FALSE")
(let-values ([(v text) (run* "<SET X 1> <PRINT <SET X <+ .X 1>>> .X")])
  (check-equal? v 2)
  (check-equal? text "\n2 "))

;; --- every call path: compiled, interpreted FUNCTION body, APPLY, MAPF (HANDLE's shape) ----
;; A FUNCTION literal's body is interpreted (mdl-eval of its FORMs).
(check-equal? (written "<SET F <FUNCTION (X) <PRINT .X>>> <F 1>") "\n1 ")
(check-equal? (written "<APPLY ,PRINT 2>") "\n2 ")
(check-equal? (written "<MAPF <> <FUNCTION (X) <PRINT .X>> (FOO \"BAR\" 3)>")
              "\nFOO \n\"BAR\" \n3 ")
(check-equal? (pname (value-of "<TYPE ,PRINT>")) "SUBR")

;; --- the object is not mutated ------------------------------------------------------
(check-true
 (true? (value-of "<SET M (2)> <SET S \"s\"> <SET L (1 .M .S)>
                   <PRINT .L>
                   <AND <==? <2 .L> .M> <==? <3 .L> .S> <=? .L (1 (2) \"s\")>
                        <==? <LENGTH .L> 3> <=? .S \"s\">>")))

;; --- line width: PRINT starts at column 0 and leaves the column after its space ----
(check-equal? (value-of "<PUT .OUTCHAN 13 80> <PRINT FOO> <14 .OUTCHAN>") 4)
(check-equal? (written "<PUT .OUTCHAN 13 10> <PRINT (A B C D E F G H I J K)>")
              "\n(A B C D E\nF G H I J\nK) ")
(check-equal? (written "<PUT .OUTCHAN 13 10> <PRINT (A B C D E)>") "\n(A B C D E\n) ")
;; A scalar PRINT never breaks, whatever its length.
(check-equal? (written "<PUT .OUTCHAN 13 3> <PRINC \"ab\"> <PRINT FOOBARBAZ>") "ab\nFOOBARBAZ ")
;; Fresh PRINT CHANNEL: width 0 (unlimited) and column 0, as Confusion.
(check-equal? (value-of "<13 .OUTCHAN>") 0)
(check-equal? (value-of "<14 .OUTCHAN>") 0)
(check-equal? (written "<PRINC \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"> <PRIN1 \"bbbb\">")
              "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"bbbb\"")
;; A PUT of the column takes effect at the next output (manual 11.2.8).
(check-equal? (written "<PUT .OUTCHAN 13 10> <PUT .OUTCHAN 14 9> <PRINC \"ab\">") "\nab")
(check-equal? (value-of "<PUT .OUTCHAN 13 10> <PUT .OUTCHAN 14 9> <PRINC \"ab\"> <14 .OUTCHAN>") 2)
;; IMAGE does not move the column (Confusion writes it without advancing).
(check-equal? (value-of "<PUT .OUTCHAN 13 10> <IMAGE 65> <14 .OUTCHAN>") 0)

;; --- strict errors; nothing is written ---------------------------------------------
(refused #rx"^PRINT: PRINT takes an object and an optional CHANNEL" "<PRINT>")
(refused #rx"^PRINT: PRINT takes an object and an optional CHANNEL" "<PRINT 1 .OUTCHAN 3>")
(refused #rx"^PRINT: attempt to write to non-channel" "<PRINT 1 2>")
(refused #rx"^PRINT: PRINT requires an output channel" "<PRINT 1 .INCHAN>")
(refused #rx"^PRINT: PRINT requires an output channel" "<PROG ((OUTCHAN ,INCHAN)) <PRINT 1>>")
(refused #rx"^PRINT: CHANNEL is not open in this MDL session"
         "<PRINT 1 <CHTYPE [0 \"PRINT\"] CHANNEL>>")
;; TYPEs Confusion prints but this runtime does not (yet).
(refused #rx"^PRINT: unsupported TYPE FORM" "<PRINT '<FOO 1>>")
(refused #rx"^PRINT: unsupported TYPE VECTOR" "<PRINT [1 2]>")
(refused #rx"^PRINT: unsupported TYPE FLOAT" "<PRINT 1.5>")
(refused #rx"^PRINT: unsupported TYPE ZZ" "<PRINT <CHTYPE (1 2) ZZ>>"
         #:setup "<NEWTYPE ZZ LIST>")
(refused #rx"^PRINT: unsupported TYPE ZS" "<PRINT <CHTYPE \"ab\" ZS>>"
         #:setup "<NEWTYPE ZS STRING>")
;; A refused element anywhere refuses the whole object.
(refused #rx"^PRINT: unsupported TYPE VECTOR" "<PRINT (1 2 (3 [4]))>")
(refused #rx"^PRIN1: unsupported TYPE VECTOR" "<PRIN1 #FALSE (1 [4])>")
(refused #rx"^PRINT: UNPARSE STRING: control character \\(code 27\\)"
         "<PRINT <STRING \"a\" <ASCII 27>>>")
(refused #rx"^PRINT: UNPARSE CHARACTER: control character \\(code 9\\)" "<PRINT <ASCII 9>>")
(refused #rx"^PRINT: non-ASCII character \\(code 233\\)" "<PRINT \"a\u00e9\">")
(refused #rx"^PRINT: UNPARSE ATOM: trailer notation" "<PRINT <ATOM \"BAR\">>")
(refused #rx"^PRINT: .*empty-PNAME ATOM not reachable" "<PRINT (<ATOM \"\">)>")
;; Self-referencing structures (Confusion would not terminate).
(refused #rx"^PRINT: .*cyclic LIST" "<PRINT .L>"
         #:setup "<SET L (1 2)> <PUTREST <REST .L> .L>")
(refused #rx"^PRINT: .*self-referencing LIST" "<PRINT .L>"
         #:setup "<SET L (1 2)> <PUT .L 2 .L>")
(refused #rx"^PRINT: .*self-referencing LIST" "<PRINT .L>"
         #:setup "<SET L (1 (2))> <PUT <2 .L> 1 .L>")
;; Elements 13 and 14 must be nonnegative FIXes.
(refused #rx"^PRINT: CHANNEL element 13 \\(line width\\) must be a nonnegative FIX"
         "<PRINT 1>" #:setup "<PUT .OUTCHAN 13 \"x\">")
(refused #rx"^PRINT: CHANNEL element 14 \\(column\\) must be a nonnegative FIX"
         "<PRINT 1>" #:setup "<PUT .OUTCHAN 14 -1>")
(refused #rx"^mdl-printstring: CHANNEL element 13 \\(line width\\) must be a nonnegative FIX"
         "<PRINTSTRING \"ab\">" #:setup "<PUT .OUTCHAN 13 -5>")
(refused #rx"^mdl-terpri: CHANNEL element 14 \\(column\\) must be a nonnegative FIX"
         "<TERPRI>" #:setup "<PUT .OUTCHAN 14 <>>")

;; A refused call leaves the column (element 14) as it was: output is
;; all-or-nothing, so no partial write and no column update (review of #173).
(define (column-after-refusal setup source)
  (parameterize ([current-namespace ns])
    (call-with-mdl-context
     (make-mdl-context #:output-port (open-output-string))
     (lambda ()
       (define (run-all text)
         (for/last ([expr (in-list (compile-program (parse-mdl text)))]) (eval expr)))
       (run-all setup)
       (define before (run-all "<14 .OUTCHAN>"))
       (check-exn exn:fail? (lambda () (run-all source)) source)
       (list before (run-all "<14 .OUTCHAN>"))))))
(check-equal? (column-after-refusal "<PUT .OUTCHAN 13 10> <PRINC \"abc\">" "<PRINT (1 [2])>")
              '(3 3))
(check-equal? (column-after-refusal "<PUT .OUTCHAN 13 10> <PRINC \"abc\">"
                                    "<PRIN1 (A B C D E F G <ASCII 27>)>")
              '(3 3))
(check-equal? (column-after-refusal "<PUT .OUTCHAN 13 10> <PRINC \"ab\">" "<PRINT 1 2>")
              '(2 2))

;; --- control characters (native cases added after the review of #173) -------------
;; Confusion writes TAB, LF, VT, FF and CR raw and every other control
;; character as ^X (two columns), in PRIN1 and PRINTSTRING alike.
;; This runtime: PRINTSTRING writes the byte itself (pre-existing deviation,
;; recorded in SEMANTICS "M4 #173", #206) but counts it as two columns, so the
;; column matches Confusion; PRIN1 refuses the STRING (strict).
(let ([native-text (lambda (name) (hash-ref (hash-ref native name) 'result_bytes))]
      [ours (lambda (name) (let-values ([(_ text) (run* (hash-ref cases name) #:listen? #t)]) text))])
  (check-equal? (native-text "width-printstring-control-counts-2") "\nab^A\n4\n")
  (check-equal? (ours "width-printstring-control-counts-2") "\nab\u0001\n4\n")
  (check-equal? (native-text "printstring-control-chars")
                "\na\tb\nc\vd\fe\rf^Ag^[h\n0\n")
  (check-equal? (ours "printstring-control-chars")
                "\na\tb\nc\vd\fe\rf\u0001g\u001bh\n0\n")
  (check-equal? (native-text "prin1-string-control-chars")
                "\n\"a\tb\nc\vd\fe\rf^Ag^[h\"\n0\n")
  (check-exn #rx"^PRIN1: UNPARSE STRING: control character \\(code 9\\)"
             (lambda () (ours "prin1-string-control-chars"))))

;; A shared (not cyclic) sublist prints twice.
(check-equal? (written "<SET M (1)> <PRINT (.M .M)>") "\n((1) (1)) ")
