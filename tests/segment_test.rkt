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
    [(mdl-segment? value) (segment-notation value)]
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
  (check-true (mdl-segment? (second (mdl-list->list quoted))))
  (check-true (mdl-segment? (third (mdl-list->list quoted)))))
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

   ;; The PSETG definition from the pinned 81prim.mud gets past the splice
   ;; compile barrier: loading the exact definition now reaches the execute
   ;; stage and fails on its compound DECL pattern, a later slice.
   (put "psetg.mud" (string-append
                     "<DEFINE PSETG (FOO BAR \"AUX\" PL)\n"
                     "        #DECL ((FOO) ATOM (PL) <LIST [REST ATOM]>)\n"
                     "        <SETG .FOO .BAR>\n"
                     "        <SETG PURE-LIST <SET PL (.FOO !.PL)>>\n"
                     "        .BAR>\n"))
   (define psetg-session (make-mdl-session scratch-root))
   (let ([report (mdl-session-load! psetg-session "psetg.mud")])
     (check-equal? (status report) "FAIL")
     (check-equal? (hash-ref (failure report) 'stage) "execute")
     (check-equal? (hash-ref (failure report) 'construct) "DEFINE")
     (check-equal? (hash-ref (failure report) 'line) 1)
     (check-true (string-contains? (hash-ref (failure report) 'exception)
                                   "unsupported declaration pattern LIST"))
     (check-exn exn:fail? (lambda () (mdl-session-call psetg-session "PSETG" "A" 1))))

   (displayln "loader segment tests passed"))
 (lambda () (delete-directory/files scratch-root)))

(displayln "segment tests passed")
