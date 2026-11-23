#lang racket/base
;; Issue #139 / ADR-0051: UNWIND cleanups run only for MDL transfers of
;; control (RETURN, AGAIN, GO, MAPLEAVE/MAPRET/MAPSTOP, also from a
;; handler). A raised error (unresolved MDL ERROR, host strict error, or any
;; other Racket raise such as a future QUIT signal) propagates unchanged and
;; runs no cleanup. Manual chapter 16 (sections 16.2, 16.4, 16.6) and 23.3.
;; Pinned Confusion observations: docs/evidence/M3/I139-uw-confusion*.json.
(require rackunit racket/string
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))

;; Each scenario gets a fresh session; `run` evaluates in it, `g` reads a
;; global after an exception has left the session.
(define-syntax-rule (scenario label body ...)
  (test-case label
    (parameterize ([current-namespace ns]
                   [current-mdl-globals (make-hasheq)]
                   [current-mdl-locals (list (make-hasheq))]
                   [current-mdl-atom-space (make-mdl-atom-space)])
      (run "<SETG CL 0> <SETG OUT 0> <SETG ORDER 0>")
      body ...)))
(define (run source)
  (for/fold ([value #f]) ([expr (in-list (compile-program (parse-mdl source)))])
    (eval expr)))
(define (g name) (mdl-gval (mdl-atom name)))
;; The raised exception, so its message can be checked for what it must not
;; contain (a cleanup error must never replace the body's error).
(define (raised-message thunk)
  (with-handlers ([exn:fail? exn-message]) (thunk) 'no-exception))

;; --- Raised errors propagate unchanged and run no cleanup -----------------

(scenario "strict error: a cleanup RETURN past it cannot swallow it"
  ;; Old behaviour returned 7 and lost the strict error.
  (define msg (raised-message
               (lambda ()
                 (run "<PROG P () <UNWIND <OPEN-NOT-DEFINED \"X\">
                                          <PROG () <SETG CL 1> <RETURN 7 .P>>>>"))))
  (check-regexp-match #rx"OPEN-NOT-DEFINED" msg)
  (check-equal? (g "CL") 0))

(scenario "strict error with the issue's exact cleanup shape"
  (check-exn #rx"OPEN-NOT-DEFINED"
             (lambda () (run "<PROG P () <UNWIND <OPEN-NOT-DEFINED \"X\"> <RETURN 7 .P>>>"))))

(scenario "MDL ERROR: a cleanup RETURN past it cannot swallow it"
  (check-exn #rx"FOO"
             (lambda ()
               (run "<PROG P () <UNWIND <ERROR FOO> <PROG () <SETG CL 1> <RETURN 7 .P>>>>")))
  (check-equal? (g "CL") 0))

(scenario "<UNWIND <ERROR FOO> <ERROR BAR>> surfaces FOO, cleanup not run"
  (define msg (raised-message
               (lambda () (run "<UNWIND <ERROR FOO> <PROG () <SETG CL 1> <ERROR BAR>>>"))))
  (check-regexp-match #rx"FOO" msg)
  (check-false (string-contains? msg "BAR"))
  (check-equal? (g "CL") 0)
  (check-exn #rx"FOO" (lambda () (run "<UNWIND <ERROR FOO> <ERROR BAR>>"))))

(scenario "FINISH-shaped: cleanup would QUIT, body's strict error surfaces"
  (define msg (raised-message
               (lambda ()
                 (run "<UNWIND <PROG () <OPEN-NOT-DEFINED \"X\"> 1>
                               <PROG () <SETG CL 1> <QUIT>>>"))))
  (check-regexp-match #rx"OPEN-NOT-DEFINED" msg)
  (check-false (regexp-match? #rx"operator QUIT" msg))
  (check-equal? (g "CL") 0))

(scenario "host strict error in the body: original error, no cleanup"
  ;; mdl-go raises (it is not an escape) when the label is missing.
  (check-exn #rx"GO label not found"
             (lambda () (run "<PROG () <UNWIND <GO NOLABEL> <SETG CL 1>> 1>")))
  (check-equal? (g "CL") 0))

(scenario "QUIT in the body (S11 quit signal, ADR-0054) runs no cleanup"
  (check-pred mdl-quit-signal?
              (with-handlers ([(lambda (v) #t) values])
                (run "<UNWIND <QUIT> <SETG CL 1>>")
                'no-raise))
  (check-equal? (g "CL") 0))

(scenario "ERROR handler that returns normally falls through: no cleanup"
  (run "<HANDLER <EVENT \"ERROR\" 8> <FUNCTION (FR \"TUPLE\" TT) <SETG ORDER 9>>>")
  (check-exn #rx"FOO" (lambda () (run "<UNWIND <ERROR FOO> <SETG CL 1>>")))
  (check-equal? (g "ORDER") 9)
  (check-equal? (g "CL") 0))

(scenario "a raise under two UNWINDs runs neither cleanup"
  (check-exn #rx"OPEN-NOT-DEFINED"
             (lambda ()
               (run "<PROG () <UNWIND <UNWIND <OPEN-NOT-DEFINED \"X\"> <SETG CL 1>>
                                      <SETG OUT 1>>>")))
  (check-equal? (g "CL") 0)
  (check-equal? (g "OUT") 0))

(scenario "a raised non-exn value (future QUIT signal model) skips cleanups"
  (define cleaned 0)
  (check-equal?
   (with-handlers ([symbol? values])
     (mdl-unwind (lambda ()
                   (mdl-unwind (lambda () (raise 'mdl-quit))
                               (lambda () (set! cleaned (add1 cleaned)))))
                 (lambda () (set! cleaned (add1 cleaned)))))
   'mdl-quit)
  (check-equal? cleaned 0))

;; --- MDL transfers still run the cleanup exactly once ----------------------

(scenario "normal completion runs no cleanup"
  (check-equal? (run "<UNWIND 5 <SETG CL <+ ,CL 1>>>") 5)
  (check-equal? (g "CL") 0))

(scenario "bare RETURN through UNWIND runs the cleanup once"
  (check-equal? (run "<PROG () <UNWIND <RETURN 1> <SETG CL <+ ,CL 1>>> 99>") 1)
  (check-equal? (g "CL") 1))

(scenario "explicit RETURN to an outer PROG runs the cleanup once"
  (check-equal?
   (run "<PROG P () <PROG () <UNWIND <RETURN 4 .P> <SETG CL <+ ,CL 1>>>> 99>")
   4)
  (check-equal? (g "CL") 1))

(scenario "RETURN to a function activation runs the cleanup once"
  (check-equal?
   (run "<DEFINE UF S () <UNWIND <RETURN 3 .S> <SETG CL <+ ,CL 1>>> 99> <UF>")
   3)
  (check-equal? (g "CL") 1))

(scenario "AGAIN through UNWIND runs the cleanup once per crossing"
  (check-equal?
   (run "<SETG N 0> <PROG () <SETG N <+ ,N 1>> <COND (<G? ,N 2> <RETURN ,N>)>
                     <UNWIND <AGAIN> <SETG CL <+ ,CL 1>>>>")
   3)
  (check-equal? (g "CL") 2))

(scenario "GO through UNWIND runs the cleanup once"
  (check-equal? (run "<PROG () <UNWIND <GO L> <SETG CL <+ ,CL 1>>> L 5>") 5)
  (check-equal? (g "CL") 1))

(scenario "MAPLEAVE, MAPRET and MAPSTOP through UNWIND run the cleanup"
  (check-equal?
   (run "<MAPF ,LIST <FUNCTION (X) <UNWIND <MAPLEAVE 7> <SETG CL <+ ,CL 1>>>> '(1 2)>")
   7)
  (check-equal? (g "CL") 1)
  (run "<SETG CL 0>")
  (check-equal?
   (mdl-list->list
    (run "<MAPF ,LIST <FUNCTION (X) <UNWIND <MAPRET .X> <SETG CL <+ ,CL 1>>>> '(1 2)>"))
   '(1 2))
  (check-equal? (g "CL") 2)
  (run "<SETG CL 0>")
  (check-equal?
   (mdl-list->list
    (run "<MAPF ,LIST <FUNCTION (X) <UNWIND <MAPSTOP 9> <SETG CL <+ ,CL 1>>>> '(1 2)>"))
   '(9))
  (check-equal? (g "CL") 1))

(scenario "nested UNWINDs: a RETURN runs inner then outer, each once"
  (check-equal?
   (run "<PROG () <UNWIND <UNWIND <RETURN 1> <SETG ORDER <+ <* ,ORDER 10> 1>>>
                          <SETG ORDER <+ <* ,ORDER 10> 2>>>>")
   1)
  (check-equal? (g "ORDER") 12))

(scenario "a transfer to a frame inside the UNWIND body runs no cleanup"
  (check-equal? (run "<UNWIND <PROG () <RETURN 5>> <SETG CL 1>>") 5)
  (check-equal? (g "CL") 0))

(scenario "a handler's RETURN past the UNWIND is an MDL transfer: cleanup runs"
  (run "<HANDLER <EVENT \"ERROR\" 8> <FUNCTION (FR \"TUPLE\" TT) <RETURN 7 ,PACT>>>")
  (check-equal?
   (run "<PROG P () <SETG PACT .P> <UNWIND <ERROR FOO> <SETG CL <+ ,CL 1>>> 99>")
   7)
  (check-equal? (g "CL") 1))

(scenario "handler ERRET to the ERROR frame crosses no UNWIND"
  (run "<HANDLER <EVENT \"ERROR\" 8> <FUNCTION (FR \"TUPLE\" TT) <ERRET 42 .FR>>>")
  (check-equal? (run "<UNWIND <ERROR FOO> <SETG CL 1>>") 42)
  (check-equal? (g "CL") 0))

;; The next two scenarios pin per-UNWIND-call independence of the raise
;; mark: a raise handled inside (or before) one UNWIND must not leave a mark
;; that makes a later transfer skip its cleanup. A mutant sharing one mark
;; across all UNWIND calls is caught only here (review, 2026-11-23).
(scenario "a handler-resolved ERROR does not disable a later transfer's cleanup"
  (run "<HANDLER <EVENT \"ERROR\" 8> <FUNCTION (FR \"TUPLE\" TT) <ERRET 1 .FR>>>")
  (check-equal?
   (run "<PROG P () <UNWIND <PROG () <ERROR FOO> <RETURN 2 .P>> <SETG CL <+ ,CL 1>>> 99>")
   2)
  (check-equal? (g "CL") 1))

(scenario "a host error caught inside the body does not disable the cleanup"
  (define cleaned 0)
  (check-equal?
   (let/ec ret
     (mdl-unwind (lambda ()
                   (with-handlers ([exn:fail? void]) (error 'inner "caught"))
                   (ret 2))
                 (lambda () (set! cleaned (add1 cleaned)))))
   2)
  (check-equal? cleaned 1))

;; --- Errors inside a cleanup during an MDL transfer ------------------------

(scenario "an error in a cleanup during RETURN surfaces unchanged (terminal)"
  (check-exn #rx"BAR"
             (lambda ()
               (run "<PROG () <UNWIND <RETURN 1> <PROG () <SETG CL 1> <ERROR BAR>>> 99>")))
  (check-equal? (g "CL") 1))

(scenario "an error in an inner cleanup abandons the transfer: outer cleanup skipped"
  (check-exn #rx"BAR"
             (lambda ()
               (run "<PROG () <UNWIND <UNWIND <RETURN 1>
                                              <PROG () <SETG CL 1> <ERROR BAR>>>
                                      <SETG OUT 1>>>")))
  (check-equal? (g "CL") 1)
  (check-equal? (g "OUT") 0))

(scenario "a handler ERRET inside a cleanup lets the original RETURN complete"
  ;; Confusion probe error-inside-cleanup-erret-value prints 1.
  (run "<HANDLER <EVENT \"ERROR\" 8> <FUNCTION (FR \"TUPLE\" TT) <ERRET 3 .FR>>>")
  (check-equal? (run "<PROG () <UNWIND <RETURN 1> <SETG CL <ERROR BAR>>> 99>") 1)
  (check-equal? (g "CL") 3))

(displayln "UNWIND raise/transfer tests finished")
