#lang racket/base
;; M4 S4 regression tests: the TOP SUBR (issue #157; docs/SEMANTICS.md
;; "M4 S4: TOP of arrays", ADR-0058).
;;
;; Part 1 replays every supported language case of the pinned Confusion probe
;; docs/evidence/M4/top-probe.json (TOP-REFERENCE.md): the case's forms run in
;; order in one fresh MDL context and each value, printed with a test-only
;; printer in the reference's notation, must equal the line the reference
;; printed for that form. Part 2 checks the refusals. Part 3 checks the
;; properties the game relies on (shared storage, identity, the argument's
;; TYPE) directly on the runtime values, and the CHANNEL-storage refusal of
;; ADR-0058 (a deviation: the reference shows two hidden CHANNEL slots).
(require rackunit racket/runtime-path racket/list racket/string json
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler (lambda (e) (raise e)))

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define-runtime-path probe-file "../docs/evidence/M4/top-probe.json")

;; --- a fresh context per case; one value per form ------------------------------
;; Each value is passed to `k` as soon as its form has run (a later form may
;; mutate it, and the reference printed it at once).
(define (eval-forms* forms [k values])
  (parameterize ([current-namespace ns])
    (call-with-mdl-context
     (make-mdl-context #:input-port (open-input-string "") #:output-port (open-output-string))
     (lambda ()
       (for/list ([form (in-list forms)])
         (k (with-handlers ([exn:fail? (lambda (e) e)])
              (for/fold ([v #f]) ([expr (in-list (compile-program (parse-mdl form)))])
                (eval expr)))))))))
(define (run* . forms) (eval-forms* forms render))
(define (run . forms) (render (last (eval-forms* forms))))

;; --- the reference's printed notation, for the values that occur ---------------
(define (type-name v) (mdl-atom-pname (mdl-type v)))
(define (render-char c)
  (define n (char->integer c))
  (cond [(< n 32) (string #\^ (integer->char (+ n 64)))]
        [(memv c '(#\" #\\)) (string #\\ c)]
        [else (string c)]))
(define (elements v) (for/list ([i (in-range 1 (add1 (mdl-length v)))]) (mdl-nth v i)))
(define (render v)
  (cond
    [(exn? v) (raise v)]
    [(mdl-atom? v) (mdl-atom-pname v)]
    [(exact-integer? v) (number->string v)]
    [(mdl-false? v) (format "#FALSE (~a)" (string-join (map render (mdl-false-payload v)) " "))]
    [(or (null? v) (mpair? v)) (format "(~a)" (string-join (map render (mdl-list->list v)) " "))]
    [(equal? (type-name v) "STRING")
     (string-append "\"" (apply string-append
                                (map render-char (string->list (mdl-string-snapshot 'render v "STRING"))))
                    "\"")]
    [(equal? (type-name v) "CHARACTER") (format "!\\~a" (integer->char (mdl-base v)))]
    [(equal? (type-name v) "VECTOR") (format "[~a]" (string-join (map render (elements v)) " "))]
    [(equal? (type-name v) "UVECTOR") (format "![~a!]" (string-join (map render (elements v)) " "))]
    [(and (mdl-array? (mdl-base v)) (eq? (mdl-array-kind (mdl-base v)) 'VECTOR))
     (format "#~a [~a]" (type-name v) (string-join (map render (elements v)) " "))]
    [else (error 'render "no test notation for ~s" v)]))

;; === Part 1: every supported language case of the reference probe ==============
(define probe (call-with-input-file probe-file read-json))
(check-equal? (hash-ref probe 'interpreter_sha256_before)
              "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789")
(check-equal? (hash-ref probe 'interpreter_sha256_after)
              (hash-ref probe 'interpreter_sha256_before))
(define (probe-case name)
  (or (findf (lambda (c) (equal? (hash-ref c 'name) name)) (hash-ref probe 'cases))
      (error 'probe-case "no probe case ~a" name)))
;; One printed line per form after the LISTEN banner, then the QUIT.
(define (reference-lines name)
  (define c (probe-case name))
  (check-equal? (hash-ref c 'exit_status) 0 name)
  (check-equal? (hash-ref c 'stderr_raw) "" name)
  (define out (hash-ref c 'stdout_raw))
  (define banner "LISTENING-AT-LEVEL 1 PROCESS 1\n")
  (define body (substring out (+ (caar (regexp-match-positions (regexp-quote banner) out))
                                 (string-length banner))))
  (define lines (string-split body "\n" #:trim? #f))
  (check-equal? (last lines) "" name)
  (check-equal? (length lines) (add1 (length (hash-ref c 'forms))) name)
  (drop-right lines 1))
;; Known XFAIL, pre-existing and not about TOP: two equal STRING literals
;; read separately are one host string here (Racket interns literal strings),
;; so they are ==?; the reference answers FALSE (`<==? "abc" "abc">` is
;; FALSE there, T here). The form is tracked with this runtime's current
;; answer so that a fix is noticed; TOP's own identity is covered by the
;; other forms (ISTRING storage, views of one literal).
(define known-xfail
  (hash '("string-top" "<==? <TOP .R> \"abcdef\">") '("#FALSE ()" "T")))
(check-equal? (run "<==? \"abc\" \"abc\">") "T")
(define (check-probe-case name)
  (define forms (hash-ref (probe-case name) 'forms))
  (define ours (apply run* forms))
  (for ([form forms] [mine ours] [ref (reference-lines name)])
    (define xfail (hash-ref known-xfail (list name form) #f))
    (cond [xfail (check-equal? ref (first xfail) (format "~a: ~a (reference)" name form))
                 (check-equal? mine (second xfail) (format "~a: ~a (known XFAIL)" name form))]
          [else (check-equal? mine ref (format "~a: ~a" name form))]))
  (printf "~a: ~a forms equal the reference~a\n" name (length forms)
          (if (for/or ([f forms]) (hash-ref known-xfail (list name f) #f)) " (1 known XFAIL)" "")))

(for-each check-probe-case
          '("vector-top" "vector-identity" "vector-aliasing" "vector-back-view" "empty-arrays"
            "uvector-top" "uvector-objuv-shape" "string-top" "string-scrstr-shape"
            "string-aliasing" "newtype-vector" "newtype-string-uvector"))

;; === Part 2: refusals ============================================================
;; Reference: stderr `Bad type for TOP` (err-list .. err-rested-tuple) and the
;; ERROR frames TOO-FEW-/TOO-MANY-ARGUMENTS-SUPPLIED.
(define (refuses rx . forms)
  (define v (last (eval-forms* forms)))
  (check-pred exn:fail? v (format "~a" forms))
  (when (exn? v) (check-regexp-match rx (exn-message v) (format "~a" forms))))
(define bad-type #rx"^mdl-top: Bad type for TOP")
(for ([name '("err-list" "err-rested-list" "err-form" "err-false" "err-segment" "err-fix"
              "err-atom" "err-character" "err-tuple" "err-rested-tuple")])
  (define c (probe-case name))
  (check-equal? (hash-ref c 'stderr_raw) "Bad type for TOP\n" name)
  (apply refuses bad-type (hash-ref c 'forms)))
(for ([name '("err-too-few-args" "err-too-many-args")]
      [rx (list #rx"TOO-FEW-ARGUMENTS-SUPPLIED" #rx"TOO-MANY-ARGUMENTS-SUPPLIED")])
  (define c (probe-case name))
  (check-true (string-contains? (hash-ref c 'stdout_raw)
                                (if (equal? name "err-too-few-args")
                                    "TOO-FEW-ARGUMENTS-SUPPLIED" "TOO-MANY-ARGUMENTS-SUPPLIED"))
              name)
  (apply refuses rx (hash-ref c 'forms)))
;; A NEWTYPE of LIST and a FORM-typed REST are LIST-primtype too.
(refuses bad-type "<NEWTYPE LL LIST>" "<TOP <CHTYPE (1 2) LL>>")
(refuses bad-type "<TOP <REST '<A B C>>>")
(refuses bad-type "<TOP ()>")
;; GROW is not a SUBR in the reference (grow-unbound) nor here.
(check-true (string-contains? (hash-ref (probe-case "grow-unbound") 'stdout_raw) "UNBOUND-VARIABLE"))
(refuses #rx"GROW" "<GROW [1 2] 1 2>")

;; === Part 3: properties on the runtime values ===================================
;; TOP is a new view over the SAME storage, never a copy and never the argument.
(let* ([vs (eval-forms* '("<SET V [1 2 3 4]>" "<SET R <REST .V 2>>" "<TOP .R>"))]
       [v (first vs)] [r (second vs)] [t (third vs)])
  (check-true (mdl-identical? t v))
  (check-false (eq? t r))
  (check-equal? (mdl-length t) 4)
  (check-equal? (mdl-length r) 2)
  (mdl-put! t 3 'changed)
  (check-equal? (mdl-nth r 1) 'changed)
  (mdl-put! v 1 'first)
  (check-equal? (mdl-nth t 1) 'first))
;; A view that already starts at the first element: TOP covers the whole
;; storage (length grows back), not just the view.
(check-equal? (run "<SET V [1 2 3 4 5]>" "<SET B <BACK <REST .V 4> 2>>" "<LENGTH <TOP .B>>") "5")
(check-equal? (run "<SET V [1 2 3]>" "<TOP <REST <REST .V 1> 1>>") "[1 2 3]")
(check-equal? (run "<SET V [1 2 3]>" "<1 <TOP <REST .V 2>>>") "1")
;; STRING: same backing storage, through two RESTs.
(check-equal? (run "<SET S <ISTRING 6 !\\a>>" "<SET R <REST <REST .S 2> 3>>"
                   "<PUT <TOP .R> 1 !\\z>" "<PUT .R 1 !\\y>" ".S")
              "\"zaaaay\"")
(check-equal? (run "<SET S <ISTRING 3 !\\a>>" "<==? <TOP <REST .S 3>> .S>") "T")
;; UVECTOR: the UTYPE cell is shared with the original (CHUTYPE after TOP is
;; seen by both).
(check-equal? (run "<SET U <IUVECTOR 2>>" "<SET T <TOP <REST .U 2>>>"
                   "<CHUTYPE .U FIX>" "<UTYPE .T>")
              "FIX")
;; The argument's TYPE is kept, the payload is shared.
(check-equal? (run "<NEWTYPE FOO VECTOR>" "<SET V [1 2 3]>" "<SET F <CHTYPE <REST .V 1> FOO>>"
                   "<PUT <TOP .F> 1 X>" "<TYPE <TOP .F>>")
              "FOO")
(check-equal? (run "<NEWTYPE FOO VECTOR>" "<SET V [1 2 3]>" "<PUT <TOP <CHTYPE <REST .V 1> FOO>> 1 X>"
                   ".V")
              "[X 2 3]")
;; PHRASE-like NEWTYPE over a 2-slot VECTOR, as SPARSE's PREPVEC (77np.mud:12).
(check-equal? (run "<NEWTYPE PH VECTOR>" "<SET P <CHTYPE [A B] PH>>" "<==? <TOP .P> .P>") "T")

;; CHANNEL storage (ADR-0058): the reference's TOP exposes two hidden slots
;; (probe channel-top: CHANNEL, LENGTH 21, slot 1 `()`); this runtime models
;; one, so every TOP of a terminal CHANNEL's storage is refused, also through
;; a REST view (which has TYPE VECTOR), and in a fresh session's channels.
(let* ([c (probe-case "channel-top")]
       [out (hash-ref c 'stdout_raw)])
  (check-true (string-contains? out "CHANNEL\n21\n19\n#CHANNEL [() 0 1 \"READ\"")))
(define channel-refusal #rx"^mdl-top: TOP of CHANNEL storage is not supported \\(ADR-0058\\)")
(refuses channel-refusal "<TOP ,INCHAN>")
(refuses channel-refusal "<TOP ,OUTCHAN>")
(refuses channel-refusal "<TOP <REST ,INCHAN 3>>")
(refuses channel-refusal "<TOP <BACK ,INCHAN>>")
(refuses channel-refusal "<TOP <CHTYPE <REST ,OUTCHAN 0> CHANNEL>>")
;; BACK of a CHANNEL is unchanged (M3 #110): one slot.
(check-equal? (run "<LENGTH <BACK ,INCHAN>>") "20")
(check-equal? (run "<1 <BACK ,INCHAN>>") "0")

(printf "top: all reference cases, refusals and properties hold\n")
