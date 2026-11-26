#lang racket/base
;; M4 issue #196 ("sweep first", maintainer decision 2026-11-26): the
;; host-only, test-only attached-declaration violation recorder
;; (docs/SEMANTICS.md "Diagnostic-only: attached-declaration violation
;; recorder"; docs/TESTING.md). It is NOT a semantic choice:
;;
;;   * without it (the default, and always in run-zork, the command line and
;;     the replay host) every attached-declaration check is strict, with the
;;     same message as before;
;;   * with it, an attached check that would fail calls the recorder once
;;     with a description of the violation and then proceeds as if the check
;;     had passed;
;;   * every other declaration path (DECL?, GDECL/SETG, positional
;;     declarations, CHTYPE to a NEWTYPE with a DECL association, malformed or
;;     unknown declarations, the traversal limit) stays strict with it on;
;;   * MDL code can neither reach nor enable it.
;; Smoke suite: needs no upstream source.
(require rackunit racket/file racket/list racket/string racket/port racket/runtime-path
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt"
         "../mdl/loader.rkt" "../mdl/replay.rkt" "../zork/main.rkt")

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler
 (lambda (e)
   (when (exn:test:check? e)
     (for ([i (in-list (exn:test:check-stack e))])
       (eprintf "  ~a: ~e\n" (check-info-name i) (check-info-value i))))
   (raise e)))

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
;; Run SOURCE in a fresh atom space, with RECORDER (#f: the default).
(define (run source #:recorder [recorder #f])
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space
                  (if recorder
                      (make-mdl-atom-space #:decl-violation-recorder recorder)
                      (make-mdl-atom-space))])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))
;; Run SOURCE with a collecting recorder: (values result infos), infos oldest
;; first.
(define (run/recorded source)
  (define infos '())
  (define result (run source #:recorder (lambda (info) (set! infos (cons info infos)))))
  (values result (reverse infos)))
;; The host-visible fields of an info, without the raw value.
(define (fields info)
  (for/list ([k '(binding kind pattern value-type value-summary line column)])
    (hash-ref info k)))

;; --- with the recorder: the violating call proceeds, recorded exactly once -------------
(define-values (r1 i1) (run/recorded "<DEFINE F (X) #DECL ((X) FIX) .X> <F \"s\">"))
(check-equal? r1 "s")
(check-equal? (map fields i1) '(("X" argument "FIX" "STRING" "\"s\"" 1 15)))
(check-equal? (hash-ref (car i1) 'value) "s")
;; the same call without the recorder: the same strict error as before
(check-exn #rx"^mdl-decl: DECL 1:15: X does not satisfy declaration$"
           (lambda () (run "<DEFINE F (X) #DECL ((X) FIX) .X> <F \"s\">")))
;; a passing call records nothing
(define-values (r1b i1b) (run/recorded "<DEFINE F (X) #DECL ((X) FIX) .X> <F 3>"))
(check-equal? (list r1b i1b) '(3 ()))

;; every attached-check kind, each recorded once, in evaluation order. Each
;; source has one #DECL on line 1; its 1-based column is the reported one.
(define (decl-column source) (add1 (caar (regexp-match-positions #rx"#DECL" source))))
(define-syntax-rule (check-kind source expected-result expected-fields)
  (let-values ([(r infos) (run/recorded source)])
    (check-equal? r expected-result source)
    (check-equal? (map fields infos)
                  (for/list ([f (in-list expected-fields)])
                    (append f (list 1 (decl-column source))))
                  source)))
(check-kind "<DEFINE F (\"OPTIONAL\" (X \"o\")) #DECL ((X) FIX) .X> <F>"
            "o" '(("X" optional "FIX" "STRING" "\"o\"")))
(check-kind "<DEFINE F (\"OPTIONAL\" X) #DECL ((X) FIX) .X> <F <>>"
            (mdl-false '()) '(("X" optional "FIX" "FALSE" "#FALSE ()")))
(check-kind "<DEFINE F (\"AUX\" (X \"a\")) #DECL ((X) FIX) .X> <F>"
            "a" '(("X" aux "FIX" "STRING" "\"a\"")))
(check-kind "<DEFINE F (\"TUPLE\" X) #DECL ((X) <LIST [REST FIX]>) 1> <F 1 2>"
            1 '(("X" rest "<LIST [REST FIX]>" "TUPLE" "#TUPLE")))
(check-kind "<DEFINE F (X) #DECL ((X) FIX) <SET X \"t\"> .X> <F 1>"
            "t" '(("X" set "FIX" "STRING" "\"t\"")))
(check-kind "<DEFINE F () #DECL ((VALUE) FIX) \"v\"> <F>"
            "v" '(("VALUE" value "FIX" "STRING" "\"v\"")))
(check-kind "<DEFINE F A () #DECL ((VALUE) FIX) <RETURN \"r\" .A>> <F>"
            "r" '(("VALUE" value "FIX" "STRING" "\"r\"")))
(check-kind "<PROG ((X \"p\")) #DECL ((X) FIX) .X>"
            "p" '(("X" prog-aux "FIX" "STRING" "\"p\"")))
(check-kind "<PROG ((X 1)) #DECL ((X) FIX (VALUE) FIX) <SET X 'A> \"q\">"
            "q" '(("X" set "FIX" "ATOM" "A") ("VALUE" value "FIX" "STRING" "\"q\"")))
;; the interpreted (quoted-formal) path
(check-kind "<DEFINE F ('X) #DECL ((X) FORM) .X> <F 1>"
            1 '(("X" argument "FORM" "FIX" "1")))
;; a compiled function with an activation
(check-kind "<DEFINE F A (X) #DECL ((X) FIX) 7> <F 'B>"
            7 '(("X" argument "FIX" "ATOM" "B")))
;; patterns are rendered from the normalized form; a name declared twice
;; (BALLOON's M, 77act2.mud:424-427) is one check, recorded once
(check-kind "<DEFINE F (X) #DECL ((X) <OR FIX <VECTOR [2 ATOM] [REST FIX]>>) 1> <F \"s\">"
            1 '(("X" argument "<OR FIX <VECTOR [2 ATOM] [REST FIX]>>" "STRING" "\"s\"")))
(check-kind "<DEFINE F (X) #DECL ((X) <OR FALSE <PRIMTYPE VECTOR>> (X) <OR FALSE <<PRIMTYPE VECTOR> ANY FIX>>) 1> <F [1 A]>"
            1 '(("X" argument "<OR FALSE <PRIMTYPE VECTOR>> & <OR FALSE <<PRIMTYPE VECTOR> ANY FIX>>"
                 "VECTOR" "#VECTOR")))
;; an unassigned binding is not checked (unchanged): nothing recorded
(check-kind "<DEFINE F (\"AUX\" X) #DECL ((X) FIX) 1> <F>" 1 '())
;; #193: a still-undefined attached TYPE name matches any value: not a
;; violation, nothing recorded
(check-kind "<DEFINE F (X) #DECL ((X) PRSOBJ) .X> <F 1>" 1 '())

;; --- the recorder affects only attached checks that would fail --------------------------
(define (record-nothing info) (error 'test "recorder called: ~s" info))
;; DECL? is a predicate: it returns FALSE, and the recorder is not consulted
(check-true (mdl-false? (run "<DECL? \"s\" FIX>" #:recorder record-nothing)))
;; DECL? of an unknown name, positional declarations, GDECL/SETG, CHTYPE to a
;; NEWTYPE with a DECL association: strict with the recorder on
(check-exn #rx"unknown declaration type"
           (lambda () (run "<DECL? 1 NOSUCHTYPE>" #:recorder record-nothing)))
(check-exn #rx"unknown declaration type"
           (lambda () (run "<DEFINE F (X) #DECL (\"VALUE\" NOSUCHTYPE FIX) .X>" #:recorder record-nothing)))
(check-exn #rx"declaration|DECL|TYPE-MISMATCH"
           (lambda () (run "<GDECL (G) FIX> <SETG G \"s\">" #:recorder record-nothing)))
(check-exn #rx"declaration|DECL|TYPE-MISMATCH"
           (lambda () (run "<SETG G \"s\"> <GDECL (G) FIX>" #:recorder record-nothing)))
(check-exn #rx"declaration|TYPE-MISMATCH|does not satisfy"
           (lambda () (run "<NEWTYPE M3N VECTOR '<VECTOR FIX>> <CHTYPE [A] M3N>" #:recorder record-nothing)))
;; a malformed attached declaration is a definition-time error, not a violation
(check-exn #rx"unsupported declaration pattern"
           (lambda () (run "<DEFINE F (X) #DECL ((X) <FOO FIX>) .X>" #:recorder record-nothing)))
;; a DECL association added after the definition whose target is unknown: a
;; strict error at the check (#193), never recorded as a violation
(check-exn #rx"unknown declaration type BAR"
           (lambda () (run "<DEFINE F (X) #DECL ((X) FOO) .X> <PUT FOO DECL BAR> <F 1>"
                           #:recorder record-nothing)))

;; --- argument validation --------------------------------------------------------------
(check-exn exn:fail:contract? (lambda () (make-mdl-atom-space #:decl-violation-recorder 5)))
(check-exn exn:fail:contract?
           (lambda () (make-mdl-atom-space #:decl-violation-recorder (lambda (a b) a))))
(check-exn exn:fail:contract? (lambda () (make-mdl-context #:decl-violation-recorder "x")))

;; --- sessions: the keyword reaches the session; the default stays strict ----------------
(define root (make-temporary-file "mdl-decl-recorder~a" 'directory))
(define toy-program #<<MDL
<DEFINE CHECKED (X) #DECL ((X) FIX) .X>
<DEFINE SAVE-IT ("AUX" (B <ISTRING 10>))
  <PRINC "booted">
  <CRLF>
  <READSTRING .B ,INCHAN <STRING <ASCII 10>>>
  <PRINC <CHECKED "s">>
  <CRLF>
  <QUIT>>
<DEFINE BOOT () <SAVE-IT>>
MDL
  )
(with-output-to-file (build-path root "77loadall.mud") (lambda () (void (write-string toy-program))))
(define (toy-session #:recorder [recorder #f] #:input [input "go\n"])
  (define out (open-output-string))
  (define s (if recorder
                (make-mdl-session root #:input-port (open-input-string input) #:output-port out
                                  #:decl-violation-recorder recorder)
                (make-mdl-session root #:input-port (open-input-string input) #:output-port out)))
  (check-equal? (hash-ref (mdl-session-load! s "77loadall.mud") 'status) "PASS")
  (values s out))
(let ()
  (define infos '())
  (define-values (s out) (toy-session #:recorder (lambda (i) (set! infos (cons i infos)))))
  (check-equal? (mdl-session-call s "CHECKED" "s") "s")
  (check-equal? (map fields infos) '(("X" argument "FIX" "STRING" "\"s\"" 1 21))))
(let ()
  (define-values (s out) (toy-session))
  (check-exn #rx"DECL 1:21: X does not satisfy declaration"
             (lambda () (mdl-session-call s "CHECKED" "s"))))
(check-exn exn:fail:contract?
           (lambda () (make-mdl-session root #:decl-violation-recorder (lambda () 1))))

;; MDL code cannot enable it: a default session whose program first evaluates
;; every MDL-visible handle on declarations still fails strictly.
(let ()
  (define-values (s out) (toy-session))
  (check-exn #rx"DECL 1:21: X does not satisfy declaration"
             (lambda ()
               (mdl-session-call s "PUT" (mdl-session-atom s "FIX") (mdl-session-atom s "DECL")
                                 (mdl-session-atom s "ANY"))
               (mdl-session-call s "CHECKED" "s"))))

;; run-zork (and so the command line, which only calls run-zork) never enables
;; it: the toy game's violation is a strict failure there.
(check-exn #rx"DECL 1:21: X does not satisfy declaration"
           (lambda ()
             (run-zork #:input (open-input-string "go\n") #:output (open-output-string)
                       #:source-root root #:notice? #f)))
;; the replay host never enables it either.
(define toy-profile
  (replay-profile "test-decl-recorder/v1" "77loadall.mud" "BOOT" '("77loadall.mud")
                  (lambda () (hasheq 'test "none"))
                  (lambda (s info) #f) (lambda (s) (hasheq)) (lambda (s) 0)
                  (lambda (obs tz) (hasheq)) '()))
(check-exn #rx"DECL 1:21: X does not satisfy declaration"
           (lambda ()
             (replay-record toy-profile #:source-root root #:input (open-input-string "go\n")
                            #:output (open-output-string))))
(delete-directory/files root)

;; --- static isolation (grep): one read site, immutable, no production host passes it ----
(define-runtime-path repo "..")
(define (source path) (file->string (build-path repo path)))
(define core (source "mdl/runtime/core.rkt"))
(check-equal? (length (regexp-match* #rx"\\(atom-space-decl-violation-recorder " core)) 1
              "exactly one read site of the recorder (check-declared!)")
(check-false (regexp-match? #rx"set-atom-space-decl-violation-recorder!" core))
(check-false (regexp-match? #rx"decl-violation-recorder[ \t\n]+#:mutable|\\[decl-violation-recorder #:mutable" core))
;; the accessor is not exported. Checked on the module itself (independent
;; review: a regex over the provide form stopped at its first `)`, so an
;; export added next to atom-space-outchan would not have been caught).
(check-false (dynamic-require (build-path repo "mdl/runtime/core.rkt")
                              'atom-space-decl-violation-recorder (lambda () #f))
             "atom-space-decl-violation-recorder must not be exported")
(for ([path '("zork/main.rkt" "zork/cli.rkt" "zork/persistence.rkt" "zork/game-files.rkt"
              "mdl/replay.rkt" "mdl/compiler.rkt" "mdl/parser.rkt"
              "mdl/lang/main.rkt" "mdl/lang/reader.rkt")])
  (check-false (regexp-match? #rx"decl-violation-recorder" (source path)) path))
;; the loader only threads its own keyword through to the context: one
;; keyword parameter, one pass-through
(check-equal? (length (regexp-match* #rx"#:decl-violation-recorder" (source "mdl/loader.rkt"))) 2)
;; no MDL-visible name for it: not a ROOT name, not a builtin
(check-false (for/or ([name (in-list (call-with-input-file (build-path repo "mdl/runtime/root-names.rktd") read))])
               (regexp-match? #rx"(?i:RECORDER|VIOLATION)" name)))
(printf "decl_violation_recorder_test: OK\n")
