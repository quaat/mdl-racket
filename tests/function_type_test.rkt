#lang racket/base
;; M4 S5b regression tests: the TYPE of applicable values (frontier F4, SWORD
;; 77act1.mud:1903 `<TYPE? ,SWORD-GLOW NOFFSET>`; docs/SEMANTICS.md "M4 S5b:
;; TYPE of applicable values", ADR-0060).
;;
;; Part 1 replays the supported forms of the pinned Confusion probe
;; docs/evidence/M4/function-type-probe.json (FUNCTION-TYPE-REFERENCE.md): the
;; forms of a case run in order in one fresh MDL context; for every form marked
;; 'same the value, printed with a test-only printer in the reference's
;; notation, must equal the line the reference printed for that form. Forms
;; the runtime cannot represent are marked with the strict error they raise
;; (recorded deviations), so a silent change is noticed. Part 2 checks the
;; TYPE of every host built-in against the reference (builtin-subr-types) and
;; FLOAD in a loader session. Part 3 checks the properties the game relies on
;; directly: identity, application paths, and that TYPE never depends on a
;; name.
(require rackunit racket/runtime-path racket/list racket/string racket/file json
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt"
         "../mdl/loader.rkt")

;; Plain `racket` must exit non-zero on any failed check (the check's
;; details are printed first).
(current-check-handler
 (lambda (e)
   (when (exn:test:check? e)
     (for ([i (in-list (exn:test:check-stack e))])
       (eprintf "~a: ~s\n" (check-info-name i) (check-info-value i))))
   (raise e)))

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define-runtime-path probe-file "../docs/evidence/M4/function-type-probe.json")
(define probe (call-with-input-file probe-file read-json))
(check-equal? (hash-ref probe 'interpreter_sha256_before)
              "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789")
(check-equal? (hash-ref probe 'interpreter_sha256_after)
              (hash-ref probe 'interpreter_sha256_before))

;; --- a fresh context per case; one value (or exn) per form ---------------------
(define (eval-forms forms)
  (parameterize ([current-namespace ns])
    (call-with-mdl-context
     (make-mdl-context #:input-port (open-input-string "") #:output-port (open-output-string))
     (lambda ()
       (for/list ([form (in-list forms)])
         (with-handlers ([exn:fail? (lambda (e) e)])
           (render
            (for/fold ([v #f]) ([expr (in-list (compile-program (parse-mdl form)))])
              (eval expr)))))))))
(define (run . forms) (last (eval-forms forms)))
(define (raise-if-exn v) (if (exn? v) (raise v) v))

;; The reference's printed notation for the values that occur. Anything else
;; (a FUNCTION, a SUBR, a FALSE with a payload) is returned as a tagged list
;; so a check can assert its TYPE without printing it.
(define (render v)
  (cond [(exact-integer? v) (number->string v)]
        [(mdl-atom? v) (mdl-atom-pname v)]
        [(and (mdl-false? v) (null? (mdl-false-payload v))) "#FALSE ()"]
        [(mdl-false? v) (list 'false-with-payload)]
        [(or (null? v) (mpair? v))
         (define items (map render (mdl-list->list v)))
         (if (andmap string? items)
             (string-append "(" (string-join items " ") ")")
             (list 'list items))]
        [else (list 'value (mdl-atom-pname (mdl-type v)))]))

(define (ref-case name)
  (or (findf (lambda (c) (equal? (hash-ref c 'name) name)) (hash-ref probe 'cases))
      (error 'ref-case "no probe case ~a" name)))
;; One printed line per form (the cases replayed here print nothing else).
(define (ref-lines name)
  (define c (ref-case name))
  (check-equal? (hash-ref c 'exit_status) 0 name)
  (define out (hash-ref c 'stdout_raw))
  (define body (cadr (regexp-match #rx"LISTENING-AT-LEVEL 1 PROCESS 1\n(.*)$" out)))
  (define lines (string-split body "\n" #:trim? #f))
  (take lines (length (hash-ref c 'forms))))

;; spec: 'same (equal to the reference line), (list 'type T) (an unprintable
;; value of TYPE T; the reference printed it), (list 'refuse rx) (a strict
;; error; recorded deviation), (list 'false) (FALSE with a payload whose
;; elements the test printer cannot show), (list 'deviation v) (a recorded
;; deviation: our value is v, the reference line differs).
(define (replay name specs)
  (define c (ref-case name))
  (define forms (hash-ref c 'forms))
  (check-equal? (length specs) (length forms) name)
  (define ref (ref-lines name))
  (define ours (eval-forms forms))
  (for ([form forms] [spec specs] [line ref] [value ours])
    (define label (format "~a: ~a (reference ~s)" name form line))
    (when (and (exn? value) (not (and (pair? spec) (eq? (car spec) 'refuse))))
      (error 'replay "~a raised ~a" label (exn-message value)))
    (cond
      [(eq? spec 'same)
       (check-equal? value line label)]
      [(eq? (car spec) 'type)
       (check-equal? value (list 'value (cadr spec)) label)]
      [(eq? (car spec) 'false)
       (check-equal? value (list 'false-with-payload) label)]
      [(eq? (car spec) 'deviation)
       (check-not-equal? (cadr spec) line label)
       (check-equal? value (cadr spec) label)]
      [(eq? (car spec) 'refuse)
       (check-pred exn? value label)
       (when (exn? value)
         (check-regexp-match (cadr spec) (exn-message value) label))]
      [else (error 'replay "bad spec ~a" spec)])))

;; A compiled <DEFINE ...> form evaluates to the stored FUNCTION here; the
;; reference returns the name ATOM (recorded pre-existing deviation, not
;; changed by this slice; an interpreted DEFINE returns the name in both).
(define S 'same)
(define D (list 'deviation (list 'value "FUNCTION")))
(define (refuse rx) (list 'refuse rx))
(define (typed t) (list 'type t))

;; === Part 1: the reference cases ====================================================
;; APPLICABLE? is not a SUBR of this runtime (recorded deviation).
(define no-applicableq (refuse #rx"unassigned or non-applicable MDL operator APPLICABLE\\?"))
(replay "define-function"
        (list D S S S S S S S S S S
              no-applicableq                    ; <APPLICABLE? ,F>
              S                                 ; <DECL? ,F FUNCTION>
              (list 'false)                     ; #FALSE (#FUNCTION ((X) ...) ATOM)
              S S S))
(replay "define-shapes" (list D S D S D S S D S D S S D S S S (typed "FORM")))
(replay "function-identity"
        (list D S (typed "FUNCTION") S S S S D S
              (list 'deviation "#FALSE ()")     ; <=? ,F ,G>: identity only here
              (typed "FUNCTION") S))
(replay "function-literal" (list S S (typed "FUNCTION") S S))
(replay "macro" (list S S S S S no-applicableq S))
(replay "builtin-subr"
        (list S
              (refuse #rx"unknown MDL TYPE SUBR")       ; PRIMTYPE ,+ (reference WORD)
              S S
              no-applicableq
              (refuse #rx"unknown declaration type SUBR") ; DECL? ,+ SUBR (ADR-0049)
              S (typed "SUBR") S S S
              (refuse #rx"unknown MDL TYPE SUBR")       ; TYPEPRIM SUBR
              (refuse #rx"unknown MDL TYPE FSUBR")      ; TYPEPRIM FSUBR
              S S))
(replay "function-uvector" (list D D (typed "UVECTOR") S S))
(replay "fsubr"
        (list (refuse #rx"unassigned MDL global COND")
              (refuse #rx"unassigned MDL global COND")
              (refuse #rx"unassigned MDL global COND")
              no-applicableq                            ; APPLICABLE? (operator first)
              (list 'deviation "#FALSE ()")))           ; GASSIGNED? COND
(replay "applicable-other" (make-list 4 no-applicableq))
(replay "special-form-types"
        (for/list ([n (hash-ref probe 'special_names)])
          (refuse (regexp (string-append "unassigned MDL global " (regexp-quote n))))))

;; The FUNCTION-as-LIST forms the reference supports are strict errors here:
;; a compiled DEFINE has no MDL formal/body LIST (recorded deviation).
(let ([forms (hash-ref (ref-case "function-structure") 'forms)])
  (define ours (eval-forms forms))
  (check-equal? (car ours) (list 'value "FUNCTION"))
  (for ([form (in-list (cdr forms))] [v (in-list (cdr ours))])
    (check-pred exn? v form)))
(for ([who '("<CHTYPE ,F LIST>" "<LENGTH ,F>" "<1 ,F>" "<EMPTY? ,F>" "<REST ,F>"
             "<MAPF ,LIST ,TYPE ,F>" "<PUTREST ,F ()>")])
  (check-exn exn:fail? (lambda () (raise-if-exn (run "<DEFINE F (X) <+ .X 1>>" who))) who))
(check-exn #rx"unsupported primitive storage conversion"
           (lambda () (raise-if-exn (run "<DEFINE F (X) <+ .X 1>>" "<CHTYPE ,F LIST>"))))
(check-exn #rx"unsupported built-in TYPE conversion"
           (lambda () (raise-if-exn (run "<CHTYPE '((Y) <* .Y 2>) FUNCTION>"))))
;; Printing a FUNCTION or a SUBR stays strict (reference: #FUNCTION ((X) ...),
;; #SUBR *...*).
(for ([form '("<UNPARSE ,F>" "<PRIN1 ,F>" "<PRINC ,F>" "<UNPARSE ,+>" "<PRIN1 ,+>")])
  (check-exn #rx"unsupported (MDL type|TYPE) (FUNCTION|SUBR)"
             (lambda () (raise-if-exn (run "<DEFINE F (X) <+ .X 1>>" form))) form))
;; CHTYPE of a SUBR is refused (the reference: PRIMTYPES do not match).
(check-exn exn:fail? (lambda () (raise-if-exn (run "<CHTYPE ,+ LIST>"))))
(printf "function-type: reference cases replayed\n")

;; === Part 2: TYPE of every host built-in =================================================
(let* ([names (hash-ref probe 'builtin_names)]
       [ref (ref-lines "builtin-subr-types")])
  (check-equal? (length names) (length ref))
  (check-true (andmap (lambda (l) (equal? l "SUBR")) ref))
  (for ([n names] [line ref] #:unless (equal? n "FLOAD"))
    (define v (run (format "<TYPE ,~a>" n)))
    (check-equal? v line n)))
;; FLOAD is bound by the loader: TYPE SUBR, not FUNCTION.
(let* ([root (make-temporary-file "ftype-root-~a" 'directory)]
       [s (make-mdl-session root #:input-port (open-input-string "")
                            #:output-port (open-output-string))])
  (define fload (mdl-session-global s "FLOAD"))
  (check-equal? (mdl-atom-pname (mdl-session-call s "TYPE" fload)) "SUBR")
  (check-true (mdl-false? (mdl-session-call s "TYPE?" fload (mdl-session-atom s "FUNCTION"))))
  (delete-directory/files root))
(printf "function-type: every host built-in is SUBR (and FLOAD)\n")

;; === Part 3: properties the game relies on ==============================================
;; SWORD's shape (77act1.mud:1903): the COND stores the ATOM, never the FUNCTION.
(check-equal? (run "<NEWTYPE NOFFSET WORD>" "<DEFINE SG (DEM) T>"
                   "<COND (<TYPE? ,SG NOFFSET> ,SG) (SG)>")
              "SG")
(check-equal? (run "<DEFINE SG (DEM) T>" "<TYPE ,SG>") "FUNCTION")
;; TYPE is the ROOT ATOM FUNCTION, whatever the function is called; a function
;; named like a TYPE or a SUBR is still a FUNCTION.
(check-equal? (run "<DEFINE F () 1> <==? <TYPE ,F> FUNCTION!-ROOT>") "T")
(check-equal? (run "<DEFINE SUBR-LIKE () 1> <TYPE ,SUBR-LIKE>") "FUNCTION")
(check-equal? (run "<SETG MYPLUS ,+> <TYPE ,MYPLUS>") "SUBR")
(check-equal? (run "<DEFINE F () 1> <SETG REP ,F> <TYPE ,REP>") "FUNCTION")
;; Identity and every application path are unchanged.
(check-equal? (run "<DEFINE F (X) <* .X 2>> <SETG G ,F> <==? ,F ,G>") "T")
(check-equal? (run "<DEFINE F (X) <* .X 2>> <SETG G ,F> <G 4>") "8")
(check-equal? (run "<DEFINE F (X) <* .X 2>> <APPLY ,F 5>") "10")
(check-equal? (run "<DEFINE F (X) <* .X 2>> <MAPF ,LIST ,F (1 2)>") "(2 4)")
(check-equal? (run "<DEFINE F (X) <* .X 2>> <SET H ,F> <.H 3>") "6")
(check-equal? (run "<DEFINE F (X) <* .X 2>> <DECL? ,F APPLICABLE>") "T")
(check-equal? (run "<DEFINE F (\"TUPLE\" A) <LENGTH .A>> <APPLY ,F 1 2 3>") "3")
;; A DECL naming FUNCTION matches a compiled DEFINE; one naming ATOM does not.
(check-equal? (run "<DEFINE F () 1> <GDECL (G) FUNCTION> <SETG G ,F> <TYPE ,G>") "FUNCTION")
(check-exn #rx"GDECL" (lambda () (raise-if-exn
                                  (run "<DEFINE F () 1> <GDECL (G) ATOM> <SETG G ,F>"))))
;; A UVECTOR of FUNCTIONs is uniform; a FUNCTION and a SUBR are not.
(check-equal? (run "<DEFINE F () 1> <DEFINE G () 2> <UTYPE <UVECTOR ,F ,G>>") "FUNCTION")
(check-exn exn:fail? (lambda () (raise-if-exn (run "<DEFINE F () 1> <UVECTOR ,F ,+>"))))
;; A host procedure that is neither a compiled DEFINE nor a built-in has no TYPE.
(check-exn #rx"mdl-type: unsupported MDL type"
           (lambda ()
             (parameterize ([current-namespace ns])
               (call-with-mdl-context
                (make-mdl-context #:input-port (open-input-string "")
                                  #:output-port (open-output-string))
                (lambda () (mdl-type (lambda () 1)))))))
(printf "function-type: identity, application and TYPE-by-representation checks pass\n")
