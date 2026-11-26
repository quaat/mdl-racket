#lang racket/base
;; M4 #173 B2: OBLIST trailers in PRIN1, PRINT and UNPARSE (manual 15.4,
;; 15.2.1, 15.5, 15.7.4). Contract: docs/SEMANTICS.md "M4 #173 B2".
;; Reference: docs/evidence/M4/i173-trailer-reference-raw.json (exact stdout
;; bytes of pinned Confusion 6df359f6..., cases in i173-trailer-cases.json).
(require rackunit racket/runtime-path racket/string json
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define-runtime-path cases-path "../docs/evidence/M4/i173-trailer-cases.json")
(define-runtime-path raw-path "../docs/evidence/M4/i173-trailer-reference-raw.json")

;; LISTEN's echo of each top-level value (PRIN1, then a newline). An OBLIST
;; value is echoed as the placeholder line "<OBLIST>": printing OBLISTs is
;; not part of this slice (PRIN1 of an OBLIST stays strict), so the native
;; echo `#OBLIST ![...!]` is replaced by the same placeholder below. Nothing
;; else is normalised.
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
             (if (mdl-oblist? v)
                 (write-string "<OBLIST>" out) ; width 0: no column to keep
                 (mdl-apply (mdl-root-atom "PRIN1") v))
             (mdl-apply (mdl-root-atom "TERPRI")))
           v)))))
  (values value (get-output-string out)))
(define (written source) (let-values ([(_ text) (run* source)]) text))
(define (value-of source) (let-values ([(v _) (run* source)]) v))
(define (oblist-placeholder text)
  (regexp-replace* #rx"#OBLIST !\\[[^!]*!\\]" text "<OBLIST>"))

;; --- differential: every native case, byte for byte -------------------------
(define cases
  (for/list ([c (in-list (hash-ref (call-with-input-file cases-path read-json) 'cases))])
    (cons (hash-ref c 'name) (hash-ref c 'expression))))
(define native
  (for/hash ([c (in-list (hash-ref (call-with-input-file raw-path read-json) 'cases))])
    (values (hash-ref c 'name) c)))
(check-equal? (length cases) 19)
(for ([c (in-list cases)])
  (define name (car c))
  (define row (hash-ref native name))
  (check-equal? (hash-ref row 'stderr_bytes) "" name)
  (check-equal? (hash-ref row 'exit_code) 0 name)
  (define-values (_ text) (run* (cdr c) #:listen? #t))
  (check-equal? text (oblist-placeholder (hash-ref row 'result_bytes)) name))

;; --- the rule, directly ---------------------------------------------------------
;; Reachable: no trailer.
(check-equal? (written "<PRIN1 FOO>") "FOO")
;; A named OBLIST off the path; the name printed recursively.
(check-equal? (written "<PRIN1 FOO!-ERRORS>") "FOO!-ERRORS")
(check-equal? (written "<SETG OB1 <MOBLIST OB1 7>> <PRIN1 <INSERT \"BAR\" ,OB1>>") "BAR!-OB1")
;; ROOT: the bare separator.
(check-equal? (written "<SET R FOO!-> <SETG OB2 <MOBLIST OB2 7>> <PROG ((OBLIST (,OB2))) <PRIN1 .R>>")
              "FOO!-")
;; No OBLIST: !-#FALSE ().
(check-equal? (written "<PRIN1 <ATOM \"QQ\">>") "QQ!-#FALSE ()")
;; Shadowed by an earlier ATOM of the same PNAME on the path.
(check-equal? (written "<SETG OB3 <MOBLIST OB3 7>> <PRIN1 <INSERT \"T\" ,OB3>>") "T!-OB3")
;; UNPARSE gives the same text, one STRING; PRINT adds its newline and space.
(check-equal? (written "<PRINC <UNPARSE <ATOM \"QQ\">>>") "QQ!-#FALSE ()")
(check-equal? (written "<PRINC <UNPARSE FOO!-ERRORS>>") "FOO!-ERRORS")
(check-equal? (written "<PRINT (A FOO!-ERRORS)>") "\n(A FOO!-ERRORS) ")
;; The OBLIST's name follows the association; with none, Confusion's form.
(check-equal? (written "<SETG OB4 <MOBLIST OB4 7>> <SET X <INSERT \"RX\" ,OB4>>
                        <PUT ,OB4 OBLIST NEWNAME> <PRIN1 .X>")
              "RX!-NEWNAME")
(check-equal? (written "<SETG OB5 <MOBLIST OB5 7>> <SET X <INSERT \"QX\" ,OB5>>
                        <PUT ,OB5 OBLIST> <PRIN1 .X>")
              "QX!-!-#FALSE ()")
;; The object is not changed and the OBLIST path is not touched.
(check-equal? (mdl-atom-pname (value-of "<SET X <ATOM \"QQ\">> <PRIN1 .X> <PRIN1 .X> <SET Y .X>"))
              "QQ")

;; --- strict refusals; nothing is written ----------------------------------------
(define (refused rx source)
  (define out (open-output-string))
  (check-exn rx
             (lambda ()
               (parameterize ([current-namespace ns])
                 (call-with-mdl-context
                  (make-mdl-context #:output-port out)
                  (lambda ()
                    (for ([expr (in-list (compile-program (parse-mdl source)))])
                      (eval expr))))))
             source)
  (check-false (regexp-match? #rx"PRIN1-MARK" (get-output-string out)) source))
;; An OBLIST named by an unreachable ATOM on that same OBLIST: the trailer
;; would not terminate (manual 15.4), refused.
(refused #rx"trailer does not terminate"
         "<SET N <ATOM \"CYC\">> <SET O <MOBLIST .N 7>> <INSERT .N .O>
          <SET A <INSERT \"LOOP\" .O>> <PRIN1 (PRIN1-MARK .A)>")
;; A name that is not an ATOM.
(refused #rx"OBLIST name is not an ATOM"
         "<SETG OB6 <MOBLIST OB6 7>> <SET X <INSERT \"NX\" ,OB6>> <PUT ,OB6 OBLIST 5>
          <PRIN1 (PRIN1-MARK .X)>")
;; Unreachable empty PNAME and escaped PNAMEs stay strict.
(refused #rx"empty-PNAME ATOM not reachable" "<PRIN1 (PRIN1-MARK <ATOM \"\">)>")
(refused #rx"not in safe-char whitelist" "<PRIN1 (PRIN1-MARK <ATOM \"A B\">)>")
;; A trailer component with an unsafe PNAME is refused too.
(refused #rx"not in safe-char whitelist"
         "<SET O <MOBLIST <ATOM \"B C\"> 7>> <PRIN1 (PRIN1-MARK <INSERT \"OK\" .O>)>")
;; PRINC still refuses ATOMs (ADR-0050).
(refused #rx"^PRINC: unsupported TYPE ATOM" "<PRINC FOO!-ERRORS>")
