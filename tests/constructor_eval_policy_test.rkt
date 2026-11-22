#lang racket/base
;; ISTRING / IVECTOR / IUVECTOR evaluation policy (review finding R5).
;;
;; Manual 7.5.4: these are SUBRs. The optional second argument is evaluated
;; once as an ordinary SUBR argument; the resulting value is then EVALed
;; once per generated element. Every invocation path -- compiled call,
;; interpreted EVAL / FUNCTION body, APPLY, and MAPF -- must therefore agree.
;; Reference: docs/evidence/M3/review/r5-constructor-eval-reference.json.
(require rackunit racket/list "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))

(define (run-in-session source)
  (parameterize ([current-namespace ns])
    (for/fold ([value #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

(define (call-with-session thunk)
  (parameterize ([current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (thunk)))

(define (run source) (call-with-session (lambda () (run-in-session source))))

;; The interpreted evaluator: SOURCE yields a quoted FORM, which the runtime
;; evaluator (mdl-eval, the path used for FUNCTION bodies and loaded data)
;; then evaluates.
(define (run-interpreted setup quoted-form)
  (call-with-session
   (lambda ()
     (run-in-session setup)
     (mdl-eval (run-in-session quoted-form)))))

(define (t? value) (and (mdl-atom? value) (string=? (mdl-atom-pname value) "T")))

;; Run SETUP, then CHECK-EXPR (which must yield T), then return the counter.
(define (check-path label setup check-expr counter expected-counter
                    #:interpreted? [interpreted? #f])
  (test-case label
    (define both
      (if interpreted?
          (run-interpreted
           setup
           (string-append "'<PROG () <SETG RESULT " check-expr "> (,RESULT " counter ")>"))
          (run (string-append setup " <SETG RESULT " check-expr "> (,RESULT " counter ")"))))
    (check-true (t? (mdl-nth both 1)) (format "~a: structure mismatch" label))
    (check-equal? (mdl-nth both 2) expected-counter (format "~a: count" label))))

;; Each path evaluates CALL (the text of a constructor application) and
;; compares it with EXPECTED via =?.
(define (paths name call apply-call expected counter expected-counter
               #:setup [setup "<SETG A 0>"])
  (check-path (format "~a compiled" name) setup
              (format "<=? ~a ~a>" call expected) counter expected-counter)
  (check-path (format "~a interpreted mdl-eval" name) setup
              (format "<=? ~a ~a>" call expected) counter expected-counter
              #:interpreted? #t)
  (check-path (format "~a interpreted FUNCTION" name)
              (string-append setup (format " <DEFINE R5F () <=? ~a ~a>>" call expected))
              "<R5F>" counter expected-counter)
  (check-path (format "~a APPLY" name) setup
              (format "<=? ~a ~a>" apply-call expected) counter expected-counter))

;; --- IVECTOR -------------------------------------------------------------
(paths "IVECTOR quoted form"
       "<IVECTOR 3 '<SETG A <+ ,A 1>>>"
       "<APPLY ,IVECTOR 3 '<SETG A <+ ,A 1>>>"
       "[1 2 3]" ",A" 3)
(paths "IVECTOR unquoted form evaluates once"
       "<IVECTOR 3 <SETG A <+ ,A 1>>>"
       "<APPLY ,IVECTOR 3 <SETG A <+ ,A 1>>>"
       "[1 1 1]" ",A" 1)
(paths "IVECTOR plain value"
       "<IVECTOR 3 5>" "<APPLY ,IVECTOR 3 5>" "[5 5 5]" ",A" 0)
(paths "IVECTOR FORM held in a variable"
       "<IVECTOR 3 ,X>" "<APPLY ,IVECTOR 3 ,X>" "[1 2 3]" ",A" 3
       #:setup "<SETG X '<SETG A <+ ,A 1>>> <SETG A 0>")
(paths "IVECTOR segment arguments"
       "<IVECTOR !,L>" "<APPLY ,IVECTOR !,L>" "[1 2 3]" ",A" 3
       #:setup "<SETG A 0> <SETG L (3 '<SETG A <+ ,A 1>>)>")
(paths "IVECTOR empty FORM fill (77dung.mud:413)"
       "<IVECTOR 2 '<>>" "<APPLY ,IVECTOR 2 '<>>" "[#FALSE () #FALSE ()]" ",A" 0)

(test-case "IVECTOR MAPF passes element values that are then EVALed"
  (check-true
   (t? (run "<SETG A 0>
             <=? <MAPF ,VECTOR ,IVECTOR '(2 3) '(<SETG A <+ ,A 1>> <SETG A <+ ,A 10>>)>
                 [[1 2] [12 22 32]]>")))
  (check-equal?
   (run "<SETG A 0>
         <MAPF ,VECTOR ,IVECTOR '(2 3) '(<SETG A <+ ,A 1>> <SETG A <+ ,A 10>>)> ,A")
   32))

(test-case "IVECTOR VECTOR fill builds a fresh VECTOR per element"
  (check-false
   (t? (run "<SETG V <IVECTOR 2 [1 2]>> <==? <1 ,V> <2 ,V>>")))
  (check-true (t? (run "<SETG V <IVECTOR 2 [1 2]>> <=? <1 ,V> <2 ,V>>")))
  (check-false
   (t? (run "<SETG V <APPLY ,IVECTOR 2 [1 2]>> <==? <1 ,V> <2 ,V>>"))))

(test-case "IVECTOR quoted REST fill gives distinct views (77rooms.mud:1555)"
  (check-false
   (t? (run "<SETG V <APPLY ,IVECTOR 2 '<REST <ISTRING 5> 5>>> <==? <1 ,V> <2 ,V>>")))
  (check-equal? (run "<SETG V <APPLY ,IVECTOR 2 '<REST <ISTRING 5> 5>>> <LENGTH <2 ,V>>")
                0))

;; --- IUVECTOR ------------------------------------------------------------
;; The manual's own example is ![1 2 3 ...!]; pinned Confusion yields
;; ![2 3 4!] (one extra evaluation) -- a recorded reference deviation.
(paths "IUVECTOR quoted form"
       "<IUVECTOR 3 '<SETG A <+ ,A 1>>>"
       "<APPLY ,IUVECTOR 3 '<SETG A <+ ,A 1>>>"
       "![1 2 3!]" ",A" 3)
(paths "IUVECTOR unquoted form evaluates once"
       "<IUVECTOR 3 <SETG A <+ ,A 1>>>"
       "<APPLY ,IUVECTOR 3 <SETG A <+ ,A 1>>>"
       "![1 1 1!]" ",A" 1)
(paths "IUVECTOR plain value (77dung.mud:412)"
       "<IUVECTOR 2 0>" "<APPLY ,IUVECTOR 2 0>" "![0 0!]" ",A" 0)

(test-case "IUVECTOR MAPF"
  (check-true
   (t? (run "<SETG A 0>
             <=? <MAPF ,VECTOR ,IUVECTOR '(2) '(<SETG A <+ ,A 1>>)> [![1 2!]]>"))))

;; --- ISTRING -------------------------------------------------------------
(paths "ISTRING quoted CHARACTER form"
       "<ISTRING 3 '<ASCII <SETG A <+ ,A 1>>>>"
       "<APPLY ,ISTRING 3 '<ASCII <SETG A <+ ,A 1>>>>"
       "\"ABC\"" ",A" 67 #:setup "<SETG A 64>")
(paths "ISTRING unquoted form evaluates once"
       "<ISTRING 3 <ASCII <SETG A <+ ,A 1>>>>"
       "<APPLY ,ISTRING 3 <ASCII <SETG A <+ ,A 1>>>>"
       "\"AAA\"" ",A" 65 #:setup "<SETG A 64>")
(paths "ISTRING CHARACTER value"
       "<ISTRING 2 !\\Q>" "<APPLY ,ISTRING 2 !\\Q>" "\"QQ\"" ",A" 0)

(test-case "ISTRING MAPF"
  (check-true
   (t? (run "<=? <MAPF ,VECTOR ,ISTRING '(1 2) '(<ASCII 65> !\\Z)> [\"A\" \"ZZ\"]>"))))

(test-case "ISTRING rejects non-CHARACTER fill on every path"
  (for ([src (list "<ISTRING 2 5>" "<ISTRING 2 '<+ 1 2>>"
                   "<APPLY ,ISTRING 2 5>" "<APPLY ,ISTRING 2 '<+ 1 2>>"
                   "<MAPF ,LIST ,ISTRING '(2) '(<+ 1 2>)>")])
    (check-exn #rx"ISTRING|CHARACTER" (lambda () (run src)) src))
  (check-exn #rx"ISTRING|CHARACTER"
             (lambda () (run-interpreted "" "'<ISTRING 2 '<+ 1 2>>"))))

(test-case "constructors keep strict arity and length checks on every path"
  (for* ([name '("IVECTOR" "IUVECTOR" "ISTRING")]
         [template (list "<~a>" "<~a 1 2 3>" "<APPLY ,~a>" "<APPLY ,~a 1 2 3>")])
    (define src (format template name))
    (check-exn exn:fail? (lambda () (run src)) src))
  (for ([name '("IVECTOR" "IUVECTOR" "ISTRING")])
    (check-exn exn:fail? (lambda () (run-interpreted "" (format "'<~a>" name))))
    (check-exn #rx"length|FIX"
               (lambda () (run-interpreted "" (format "'<~a -1>" name)))))
  (for* ([name '("IVECTOR" "IUVECTOR" "ISTRING")]
         [template (list "<~a -1>" "<APPLY ,~a -1>" "<~a \"3\">")])
    (define src (format template name))
    (check-exn #rx"length|FIX" (lambda () (run src)) src)))
