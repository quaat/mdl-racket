#lang racket/base
;; M2 D2 regression tests: historical MDL SEGMENT (`!` splice) evaluation.
;;
;; The reference observations are the pinned Confusion runs recorded in
;; docs/evidence/M2/segment-reference.json and segment-error-reference.json
;; (see docs/evidence/M2/SEGMENTS.md). `run` cases mirror recorded successes
;; and deliberate errors; interpreted twins run through the shared-session
;; loader exactly like tests/loader_test.rkt. Atoms are compared through the
;; pinned reference's printed notation.
(require rackunit racket/file racket/path racket/list racket/string
         "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt" "../mdl/loader.rkt")

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

(define (data-elements value)
  (cond [(mdl-array? value)
         (for/list ([i (in-range (mdl-array-length value))]) (mdl-nth value (add1 i)))]
        [(or (null? value) (mpair? value)) (mdl-list->list value)]
        [(mdl-form? value) (form-elements value)]
        [else (error 'segment-test "unsupported expected-value view ~s" value)]))
(define (name-atom? value name)
  (and (mdl-atom? value) (string=? (mdl-atom-pname value) name)))

;; Render a value in the pinned Confusion notation, with SEGMENT objects
;; printed in their original source notation, following mdl_output.cpp:780
;; (`!.ATOM`, `!,ATOM`, `!'...`, otherwise `!<...!>`).
;; Atom identity is per-session, so type checks go through PNAMEs.
(define (typed-name? value name)
  (string=? (mdl-atom-pname (mdl-type value)) name))
(define (render value)
  (cond
    ;; SEGMENT identity is per session (ADR-0056 amendment); RUN returns values
    ;; out of a fresh atom space, so check the TYPE by PNAME here.
    [(typed-name? value "SEGMENT")
     (segment-notation value)]
    [(mdl-atom? value) (mdl-atom-pname value)]
    [(string? value) (format "~s" value)]
    [(or (null? value) (mpair? value))
     (format "(~a)" (string-join (map render (mdl-list->list value)) " "))]
    [(typed-name? value "FORM")
     (format "<~a>" (string-join (map render (form-elements value)) " "))]
    [(mdl-array? value)
     (if (eq? (mdl-array-kind value) 'UVECTOR)
         (format "![~a!]" (string-join (map render (data-elements value)) " "))
         (format "[~a]" (string-join (map render (data-elements value)) " ")))]
    [(typed-name? value "CHARACTER")
     (format "!\\~a" (integer->char (mdl-base value)))]
    [(number? value) (format "~a" value)]
    [else (format "~s" value)]))
(define (segment-notation segment)
  (define elements (form-elements (mdl-segment-payload segment)))
  (cond
    [(and (= (length elements) 2)
          (name-atom? (car elements) "LVAL") (mdl-atom? (second elements)))
     (format "!.~a" (mdl-atom-pname (second elements)))]
    [(and (= (length elements) 2)
          (name-atom? (car elements) "GVAL") (mdl-atom? (second elements)))
     (format "!,~a" (mdl-atom-pname (second elements)))]
    [(and (pair? elements) (name-atom? (car elements) "QUOTE"))
     (format "'~a" (render (second elements)))]
    [else (format "!<~a!>" (string-join (map render elements) " "))]))

;; --- reader: splice nodes with source positions ----------------------------
(let ([nodes (parse-mdl "(1 !.ZOP)")])
  (define sp (second (mdl-node-value (car nodes))))
  (check-eq? (mdl-node-kind sp) 'splice)
  (check-equal? (list (mdl-node-line sp) (mdl-node-column sp)) '(1 4))
  (check-eq? (mdl-node-kind (mdl-node-value sp)) 'local))
(check-eq? (mdl-node-kind (second (mdl-node-value (car (parse-mdl "(1 !,ZOO)")))))
           'splice)
;; explicit `!>` terminates the segment payload of a form
(let ([sp (car (mdl-node-value (car (parse-mdl "(!<REST .ARF!>)"))))])
  (check-eq? (mdl-node-kind sp) 'splice)
  (check-eq? (mdl-node-kind (mdl-node-value sp)) 'form)
  (check-equal? (list (mdl-node-line sp) (mdl-node-column sp)) '(1 2)))
;; `![`/`!]` remain UVECTOR syntax, never SEGMENT notation
(check-eq? (mdl-node-kind (car (parse-mdl "![1 2]"))) 'uvector)
(check-eq? (mdl-node-kind (second (mdl-node-value (car (parse-mdl "[1 ![2 3]]")))))
           'uvector)
;; a dangling bang after the segment payload is a reader error
(check-exn exn:fail:mdl-reader? (lambda () (parse-mdl "(!)")))
(check-exn exn:fail:mdl-reader?
           (lambda () (parse-mdl "<SET ARF '(B 3 4)> (!<REST .ARF>!)")))

;; --- compiled evaluation: LIST construction --------------------------------
;; list-splice-lval and manual-unquoted-arf (segment-reference.json)
(check-equal?
 (render (run "<SET ARF '(B 3 4)> <SET ZOP '![2 3 4]> (.ARF !.ZOP)"))
 "((B 3 4) 2 3 4)")
(check-equal?
 (render (run "<SET ARF (B 3 4)> <SET ZOP '![2 3 4]> (.ARF !.ZOP)"))
 "((B 3 4) 2 3 4)")
;; gval-splice
(check-equal? (render (run "<SETG GSEG '![7 8 9]> (!,GSEG)")) "(7 8 9)")
;; form-segment-explicit-bang / form-segment-implicit-bang
(check-equal? (render (run "<SET ARF '(B 3 4)> (!<REST .ARF!>)")) "(3 4)")
(check-equal? (render (run "<SET ARF '(B 3 4)> (!<REST .ARF>)")) "(3 4)")
;; subr-arg-splice: spliced elements are not re-evaluated
(check-equal? (run "<SET A '![1 2 3 4]> <+ !.A 5>") 15)
;; empty-segment-quoted / empty-segment-lval
(check-equal? (render (run "(1 !'() 2)")) "(1 2)")
(check-equal? (render (run "<SET E '()> (1 !.E 2)")) "(1 2)")
;; nested-segments-list
(check-equal?
 (render (run "<SET ZOP '![2 3 4]> <SET ARF '(B 3 4)> (!.ZOP !<REST .ARF>)"))
 "(2 3 4 3 4)")
;; evaluation interleaves element evaluation with segment payloads
(check-equal?
 (render (run (string-append
               "<SETG LOG 0> <DEFINE F2 (N) [.N]>"
               " <SETG R ( !<F2 ,LOG> <SETG LOG <+ ,LOG 100>> )> (,R ,LOG)")))
 "((0 100) 100)")
;; splice-order-side-effects: ordered segment payloads interleave with calls
(check-equal?
 (render (run (string-append
               "<SETG LOG 0>"
               " <DEFINE F (I \"AUX\" (N <+ ,LOG 1>)) <SETG LOG .N> ![.N]>"
               " <SETG ORDERED (1 !<F 10> 20 !<F 30>)>"
               " ,ORDERED")))
 "(1 1 20 2)")

;; --- LIST tail sharing and copying (PUT mutation visibility) ---------------
(check-equal?
 (render (run (string-append
               "<SET ARF '(B 3 4)> <SET DOG (1 2 !.ARF)>"
               "<PUT .ARF 1 \"BOWOW\"> (.ARF .DOG)")))
 "((\"BOWOW\" 3 4) (1 2 \"BOWOW\" 3 4))")
(check-equal?
 (render (run (string-append
               "<SET ARF '(B 3 4)> <SET CAT (1 !.ARF 2)>"
               "<PUT .ARF 1 \"BOWOW\"> (.CAT)")))
 "((1 B 3 4 2))")

;; --- VECTOR and UVECTOR construction ---------------------------------------
(check-equal? (render (run "<SET ZOP '![2 3 4]> [1 !.ZOP]")) "[1 2 3 4]")
(check-equal?
 (render (run "<SET ZOP '![2 3 4]> <SET ARF '(B 3 4)> [1 !.ZOP !<REST .ARF>]"))
 "[1 2 3 4 3 4]")
(let ([uv (run "<SET ZOP '![2 3 4]> <SET ARF '(B 3 4)> ![!.ZOP !<REST .ARF>!]")])
  (check-true (and (mdl-array? uv) (eq? (mdl-array-kind uv) 'UVECTOR)))
  (check-equal? (render uv) "![2 3 4 3 4!]"))
;; uvector-non-uniform
(check-exn #rx"TYPES-DIFFER-IN-UNIFORM-VECTOR"
           (lambda () (run "<SET X '![2 3]> ![1 !.X \"s\"!]")))

;; --- string splice: STRING characters, as CHARACTER values -----------------
(define (character-code value)
  (and (typed-name? value "CHARACTER")
       (mdl-base value)))
(let ([spliced (run "<SET S \"STRUNG.\"> (!.S)")])
  (check-equal? (mdl-length spliced) 7)
  (check-equal?
   (map character-code (mdl-list->list spliced))
   (map char->integer (string->list "STRUNG."))))

;; --- quoted structures keep segments as unevaluated data -------------------
(let ([quoted (run "<SET X '![9 9]> <SET A '![5 5]> '(1 !.X !.A)")])
  (check-equal? (render quoted) "(1 !.X !.A)")
  (check-true (typed-name? (second (mdl-list->list quoted)) "SEGMENT"))
  (check-true (typed-name? (third (mdl-list->list quoted)) "SEGMENT")))
(check-equal? (render (run "<SET X '![9 9]> '<PROG () !.X>")) "<PROG () !.X>")
;; A plain element that evaluates to a segment object is stored, not spliced
;; (pinned Confusion: `(1 ,Y 2)` with Y = `!.A` gives `(1 !.A 2)`).
(check-equal? (render (run "<SETG A '![9 8]> <SETG Y '!.A> (1 ,Y 2)"))
              "(1 !.A 2)")
(check-equal? (render (run "'(1 !.X 2)")) "(1 !.X 2)")

;; --- errors on the compiled path -------------------------------------------
;; A standalone SEGMENT is not a compiled value; the compiler rejects it
;; before evaluation. The interpreted path reproduces the reference's
;; ILLEGAL-SEGMENT diagnostic (see the loader section).
(check-exn #rx"SEGMENT outside a structured construction"
           (lambda () (run "<SET ZOP '![2 3 4]> !.ZOP")))
(check-exn #rx"SEGMENT outside a structured construction"
           (lambda () (run "<SET ZOP '![2 3 4]> !<SET B 2>")))
(check-exn #rx"SEGMENT outside a structured construction"
           (lambda () (run "<SET X !.X>")))
;; segment-non-structured-value / segment-atom-value
(check-exn #rx"ILLEGAL-SEGMENT: Segment evaluated to nonstructured type"
           (lambda () (run "<SET X 5> (1 !.X 2)")))
(check-exn #rx"ILLEGAL-SEGMENT: Segment evaluated to nonstructured type"
           (lambda () (run "<SET A 'FOO> (1 !.A 2)")))

;; --- review regressions (PR #49 independent review) ------------------------
;; FALSE, TUPLE, and typed LIST-primtype payloads splice their elements
;; like the pinned reference; the pre-review walkers returned raw mpair
;; chains (crashing consumers) or rejected typed values (review P1-1).
(check-equal? (render (run "<SETG FZ #FALSE (1 2)> (1 !,FZ 2)")) "(1 1 2 2)")
(check-equal? (render (run "<DEFINE TT (\"TUPLE\" T) .T> <SETG TP <TT 1 2>> (1 !,TP 2)"))
              "(1 1 2 2)")
(check-equal? (render (run "<NEWTYPE NTL LIST> <SETG NT <CHTYPE (1 2) NTL>> (1 !,NT 2)"))
              "(1 1 2 2)")
(check-equal? (render (run "<SETG EF #FALSE ()> (1 !,EF 2)")) "(1 2)")
;; A bare segment nested in a sibling position must not inherit the
;; structured context (review P2-2); it is an explicit compile error, like
;; the reference's runtime ILLEGAL-SEGMENT.
(check-exn #rx"SEGMENT outside a structured construction"
           (lambda () (run "<SET X '(1)> <SET Y '(2)> (!.X <PROG () !.Y>)")))
(check-exn #rx"SEGMENT outside a structured construction"
           (lambda ()
             (run "<SET X '(1)> <DEFINE ID (X) .X> <SETG Q <ID <PROG () !.X>>>")))

;; --- interpreted twins through the shared-session loader -------------------
(define scratch-root
  (let ([p (make-temporary-file "mdl-segment-test~a" #f (find-system-path 'temp-dir))])
    (delete-file p)
    (make-directory* p)
    p))
(dynamic-wind
 void
 (lambda ()
   (define (put relative contents)
     (call-with-output-file (build-path scratch-root relative)
       #:exists 'truncate/replace (lambda (out) (display contents out))))
   (define (status report) (hash-ref report 'status))
   (define (failure report) (hash-ref report 'failure))
   (put "segments.mud" (string-append
                        "<SETG LOG 0>\n"
                        "<SET ARF '(B 3 4)>\n"
                        "<SET ZOP '![2 3 4]>\n"
                        "<SETG GSEG '![7 8 9]>\n"
                        "<SETG DOG (1 2 !.ARF)>\n"
                        "<DEFINE NEST () ( .ARF !.ZOP)>\n"
                        "<DEFINE GSP () ( !,GSEG )>\n"
                        "<DEFINE EXPLICIT () ( !<REST .ARF!> )>\n"
                        "<DEFINE IMPLICIT () ( !<REST .ARF> )>\n"
                        "<DEFINE EMPTY () (1 !'() 2)>\n"
                        "<DEFINE VEC () [1 !.ZOP !.ZOP]>\n"
                        "<DEFINE UVEC () ![!.ZOP !.ZOP!]>\n"
                        "<DEFINE SHARED () (1 2 !.ARF)>\n"
                        "<DEFINE COUNTED (I \"AUX\" (N <+ ,LOG 1>)) <SETG LOG .N> ![.N]>\n"
                        "<SETG ORDERED (1 !<COUNTED 10> 20 !<COUNTED 30>)>\n"
                        "<DEFINE TWIN () (1 !<COUNTED 100> 200 !<COUNTED 300>)>\n"))
   (define session (make-mdl-session scratch-root))
   (check-equal? (status (mdl-session-load! session "segments.mud")) "PASS")
   (check-equal? (render (mdl-session-call session "NEST")) "((B 3 4) 2 3 4)")
   (check-equal? (render (mdl-session-call session "GSP")) "(7 8 9)")
   (check-equal? (render (mdl-session-call session "EXPLICIT")) "(3 4)")
   (check-equal? (render (mdl-session-call session "IMPLICIT")) "(3 4)")
   (check-equal? (render (mdl-session-call session "EMPTY")) "(1 2)")
   (check-equal? (render (mdl-session-call session "VEC")) "[1 2 3 4 2 3 4]")
   (check-equal? (render (mdl-session-call session "UVEC")) "![2 3 4 2 3 4!]")
   (check-equal? (render (mdl-session-global session "DOG")) "(1 2 B 3 4)")
   ;; interpreted evaluation order matches the compiled order
   (check-equal? (render (mdl-session-global session "ORDERED")) "(1 1 20 2)")
   (check-equal? (render (mdl-session-call session "TWIN")) "(1 3 200 4)")
   ;; interpreted tail sharing: mutation goes through the shared cells
   (check-equal? (mdl-list->list (mdl-session-call session "SHARED"))
                 (mdl-list->list (mdl-session-global session "DOG")))
   ;; string splice, as CHARACTER values
   (put "string.mud" "<SET S \"STRUNG.\">\n<DEFINE STRS () (1 !.S 2)>\n")
   (check-equal? (status (mdl-session-load! session "string.mud")) "PASS")
   (let ([result (mdl-session-call session "STRS")])
     (check-equal? (mdl-length result) 9)
     (check-equal?
      (map character-code (mdl-list->list result))
      (cons #f (append (map char->integer (string->list "STRUNG.")) (list #f)))))
   ;; interpreted standalone evaluation is the reference's ILLEGAL-SEGMENT
   (put "bare.mud" "<DEFINE BARE ('D) !.ZOP>\n")
   (check-equal? (status (mdl-session-load! session "bare.mud")) "PASS")
   (check-exn #rx"ILLEGAL-SEGMENT: Attempt to evaluate segment outside structured type"
              (lambda () (mdl-session-call session "BARE" 0)))
   ;; segments that evaluate to non-structured values are errors
   (put "nonstructured.mud" "<SET FIVE 5>\n<DEFINE NONSTR () (1 !.FIVE 2)>\n")
   (check-equal? (status (mdl-session-load! session "nonstructured.mud")) "PASS")
   (check-exn #rx"ILLEGAL-SEGMENT: Segment evaluated to nonstructured type"
              (lambda () (mdl-session-call session "NONSTR")))
   ;; a segment of one ATOM is non-structured for element insertion
   (put "globals.mud" "<SETG SYMBOL 'FOO>\n<DEFINE ATOMV () (1 !,SYMBOL 2)>\n")
   (check-equal? (status (mdl-session-load! session "globals.mud")) "PASS")
   (check-exn #rx"ILLEGAL-SEGMENT: Segment evaluated to nonstructured type"
              (lambda () (mdl-session-call session "ATOMV")))
   ;; non-uniform UVECTOR with segments is an error
   (put "uniform.mud" "<SETG GZ '![2 3]>\n<SETG GS \"s\">\n<DEFINE UBAD () ![1 !,GZ !,GS!]>\n")
   (check-equal? (status (mdl-session-load! session "uniform.mud")) "PASS")
   (check-exn #rx"TYPES-DIFFER-IN-UNIFORM-VECTOR"
              (lambda () (mdl-session-call session "UBAD")))
   ;; standalone segments fail the compile stage through the loader
   (put "standalone.mud" "<SET ZOP '![2 3 4]>\n!<SET B 2>\n")
   (let ([report (mdl-session-load! session "standalone.mud")])
     (check-equal? (status report) "FAIL")
     (check-equal? (hash-ref (failure report) 'stage) "compile")
     (check-equal? (hash-ref (failure report) 'construct) "splice")
     (check-equal? (hash-ref report 'completed_expressions) 1))

   ;; Since D3 (structured declaration patterns, issue #48) the PSETG
   ;; definition from the pinned 81prim.mud installs its <LIST [REST ATOM]>
   ;; declaration, so the definition installs and invoking it fails on its
   ;; body: this trimmed two-line body evaluates the segment !.PL while its
   ;; PL auxiliary is still unassigned. The pinned definition initializes PL
   ;; through its PURE-LIST COND first; see tests/declaration_pattern_test.rkt.
   ;; This trimmed body deliberately omits that initialization.
   (put "psetg.mud" (string-append
                     "<DEFINE PSETG (FOO BAR \"AUX\" PL)\n"
                     "        #DECL ((FOO) ATOM (PL) <LIST [REST ATOM]>)\n"
                     "        <SETG .FOO .BAR>\n"
                     "        <SETG PURE-LIST <SET PL (.FOO !.PL)>>\n"
                     "        .BAR>\n"))
   (define psetg-session (make-mdl-session scratch-root))
   (check-equal? (status (mdl-session-load! psetg-session "psetg.mud")) "PASS")
   (check-exn #rx"unassigned MDL local PL"
              (lambda ()
                (define psetg-atom (mdl-session-call psetg-session "ATOM" "P2"))
                (mdl-session-call psetg-session "PSETG" psetg-atom 1)))

   ;; Review P2-3: genuine interpreted twins — quoted formals force the
   ;; interpreted FUNCTION path, exercising mdl-eval's splice assembly,
   ;; interpreted tail sharing (PUT-observable, not structural equality),
   ;; non-final copying, and macro raw-argument semantics.
   (put "twins.mud" (string-append
                     "<SETG ARF2 '(B 3 4)>\n"
                     "<SETG ZOP2 '![2 3 4]>\n"
                     "<DEFINE INEST ('X) ( !,ARF2 !,ZOP2)>\n"
                     "<DEFINE ISHARED ('X) (1 2 !,ARF2)>\n"
                     "<DEFINE ICAT ('X) (1 !,ARF2 2)>\n"))
   (check-equal? (status (mdl-session-load! session "twins.mud")) "PASS")
   ;; two adjacent GVAL segments: ARF2's and ZOP2's elements both splice
   (check-equal? (render (mdl-session-call session "INEST" 0)) "(B 3 4 2 3 4)")
   (define shared-tail (mdl-session-call session "ISHARED" 0))
   (check-equal? (render shared-tail) "(1 2 B 3 4)")
   (define arf2 (mdl-session-global session "ARF2"))
   (mdl-session-call session "PUT" arf2 1 "BOWOW")
   ;; interpreted sharing: the PUT through ARF2 is visible in the built list
   (check-equal? (render shared-tail) "(1 2 \"BOWOW\" 3 4)")
   ;; interpreted non-final segment copies: later mutation is NOT visible
   (define copied (mdl-session-call session "ICAT" 0))
   (check-equal? (render copied) "(1 \"BOWOW\" 3 4 2)")
   (mdl-session-call session "PUT" arf2 1 "WOOF")
   (check-equal? (render copied) "(1 \"BOWOW\" 3 4 2)")
   ;; Review P3-4: macro call arguments stay raw; a segment in a macro call
   ;; binds as the SEGMENT object, not as its spliced elements (the pinned
   ;; reference passes macro arguments unexpanded).
   (put "macros.mud" "<DEFMAC QX ('X) <FORM QUOTE .X>>\n")
   (check-equal? (status (mdl-session-load! session "macros.mud")) "PASS")
   (put "macrocall.mud" "<SETG AVAL '(9)>\n<SETG MACQ <QX !,AVAL>>\n")
   (check-equal? (status (mdl-session-load! session "macrocall.mud")) "PASS")
   ;; Checked inside the session: SEGMENT identity is per session (S2 review).
   (check-equal? (mdl-atom-pname (mdl-session-call session "TYPE"
                                                   (mdl-session-global session "MACQ")))
                 "SEGMENT")

   (displayln "loader segment tests passed"))
 (lambda () (delete-directory/files scratch-root)))

(displayln "segment tests passed")
