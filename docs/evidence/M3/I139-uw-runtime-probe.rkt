#lang racket/base
;; UNWIND-frontier probe of this repository's runtime (issue #139).
;; Run from the repository root:
;;   PLTCOLLECTS=":$PWD" racket docs/evidence/M3/I139-uw-runtime-probe.rkt OUT.json
;; The "before" observations (I139-uw-runtime-before.json) were recorded with
;; the same cases against the pre-#139 runtime (s6-rep, aea622a6).
;; Observation: each case runs in fresh globals/atom space; after the case
;; (normal value or exception) a follow-up query reads ,CL / ,ORDER in the
;; same session state, so cleanup side effects are visible either way.
(require racket/list racket/string json racket/port
         (file "../../../mdl/parser.rkt")
         (file "../../../mdl/compiler.rkt")
         (file "../../../mdl/runtime/core.rkt"))

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))

(define (show v)
  (cond [(mdl-atom? v) (mdl-atom-pname v)]
        [(void? v) "#<void>"]
        [else (format "~a" v)]))

(define (run-case name source [query "<LIST ,CL ,ORDER>"])
  (define globals (make-hasheq))
  (define space (make-mdl-atom-space))
  (define (ev src)
    (parameterize ([current-namespace ns]
                   [current-mdl-globals globals]
                   [current-mdl-locals (list (make-hasheq))]
                   [current-mdl-atom-space space])
      (for/fold ([r #f]) ([e (in-list (compile-program (parse-mdl src)))])
        (eval e))))
  (ev "<SETG CL 0> <SETG ORDER 0>")
  (define-values (outcome detail)
    (with-handlers ([exn:fail? (lambda (e) (values "exception" (exn-message e)))]
                    [(lambda (_) #t) (lambda (v) (values "raised-non-exn" (format "~s" v)))])
      (values "value" (show (ev source)))))
  (define after
    (with-handlers ([exn:fail? (lambda (e) (string-append "QUERY-FAILED: " (exn-message e)))])
      (let ([v (ev query)])
        (string-join (map show (mdl-list->list v)) " "))))
  (printf "--- ~a\n  ~a: ~a\n  [CL ORDER] after: ~a\n" name outcome detail after)
  (hasheq 'name name 'source source 'outcome outcome 'detail detail
          'cl_order_after after))

(define mdl-cases
  (list
   (list "normal-no-cleanup" "<UNWIND 5 <SETG CL 1>>")
   (list "return-crosses" "<PROG () <UNWIND <RETURN 1> <SETG CL 1>>>")
   (list "again-crosses" "<SETG N 0> <PROG () <SETG N <+ ,N 1>> <COND (<G? ,N 2> <RETURN ,N>)> <UNWIND <AGAIN> <SETG CL <+ ,CL 1>>>>")
   (list "nested-return-order" "<PROG () <UNWIND <UNWIND <RETURN 1> <SETG ORDER <+ <* ,ORDER 10> 1>>> <SETG ORDER <+ <* ,ORDER 10> 2>>>>")
   (list "mdl-error-in-body" "<UNWIND <ERROR FOO> <SETG CL 1>>")
   (list "unbound-fn-in-body" "<UNWIND <OPEN-NOT-DEFINED \"X\"> <SETG CL 1>>")
   (list "open-in-body" "<UNWIND <OPEN \"READ\" \"ZORK\" \"LOG\"> <SETG CL 1>>")
   (list "quit-in-body" "<UNWIND <QUIT> <SETG CL 1>>")
   (list "strict-unsupported-in-body" "<UNWIND <UNPARSE 1.5> <SETG CL 1>>")
   (list "finish-shaped-cleanup-errors" "<UNWIND <PROG () <OPEN-NOT-DEFINED \"X\"> 1> <PROG () <SETG CL 1> <QUIT>>>")
   (list "error-inside-cleanup-of-return" "<PROG () <UNWIND <RETURN 1> <PROG () <SETG CL 1> <ERROR BAR>>>>")
   (list "error-inside-cleanup-of-error" "<UNWIND <ERROR FOO> <PROG () <SETG CL 1> <ERROR BAR>>>")
   (list "cleanup-returns-past-strict-error" "<PROG P () <UNWIND <OPEN-NOT-DEFINED \"X\"> <PROG () <SETG CL 1> <RETURN 7 .P>>>>")
   (list "cleanup-returns-past-mdl-error" "<PROG P () <UNWIND <ERROR FOO> <PROG () <SETG CL 1> <RETURN 7 .P>>>>")
   (list "handler-erret-above-unwind" "<HANDLER <EVENT \"ERROR\" 8> <FUNCTION (FR \"TUPLE\" TT) <ERRET 42 .FR>>> <UNWIND <ERROR FOO> <SETG CL 1>>")
   (list "handler-falls-through" "<HANDLER <EVENT \"ERROR\" 8> <FUNCTION (FR \"TUPLE\" TT) <SETG ORDER 9>>> <UNWIND <ERROR FOO> <SETG CL 1>>")))

(define results (for/list ([c mdl-cases]) (apply run-case c)))

;; Host-level QUIT models (QUIT is not implemented in s6-rep): what each
;; candidate Racket mechanism does to an mdl-unwind cleanup.
(define (model name thunk)
  (define log '())
  (define outcome
    (with-handlers ([(lambda (_) #t) (lambda (v) (format "caught ~a" (if (exn? v) (exn-message v) v)))])
      (thunk (lambda (tag) (set! log (cons tag log))))))
  (printf "--- model ~a: ~a; cleanups ran: ~s\n" name outcome (reverse log))
  (hasheq 'name name 'outcome (format "~a" outcome) 'cleanups_ran (map symbol->string (reverse log))))

(define models
  (list
   (model "quit-as-raise-non-exn"
          (lambda (note) (mdl-unwind (lambda () (raise 'mdl-quit)) (lambda () (note 'cleanup)))))
   (model "quit-as-escape-continuation"
          (lambda (note) (let/ec k (mdl-unwind (lambda () (k 'quit-escaped)) (lambda () (note 'cleanup))))))
   (model "strict-error-cleanup-raises"
          (lambda (note) (mdl-unwind (lambda () (error 'strict "OPEN unsupported"))
                                     (lambda () (note 'cleanup) (error 'cleanup "QUIT unbound")))))))

;; (exit) inside mdl-unwind: run in a subprocess-free way by checking with
;; exit-handler parameterized to an escape (the default handler exits the
;; process without running dynamic-wind posts).
(define exit-model
  (let ([log '()])
    (define r
      (let/ec k
        (parameterize ([exit-handler (lambda (c) (k (format "exit ~a" c)))])
          (mdl-unwind (lambda () (exit 0)) (lambda () (set! log (cons 'cleanup log)))))))
    (printf "--- model quit-as-exit (exit-handler escapes, as a stand-in): ~a; cleanups ran: ~s\n" r log)
    (hasheq 'name "quit-as-exit-via-escaping-exit-handler" 'outcome r
            'cleanups_ran (map symbol->string log)
            'note "with an exit-handler that escapes, posts run; the DEFAULT exit-handler terminates the process immediately and runs no dynamic-wind posts (verified with a standalone (exit 3) probe during the investigation)")))

(call-with-output-file (vector-ref (current-command-line-arguments) 0) #:exists 'replace
  (lambda (o)
    (write-json (hasheq 'name "unwind-frontier-runtime"
                        'worktree "this repository (see git HEAD)"
                        'cases results 'quit_models (append models (list exit-model)))
                o)))
