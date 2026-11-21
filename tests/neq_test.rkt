#lang racket/base
;; Reference-backed structural N=? cases, issue #57. See NEQ.md.
(require rackunit racket/file racket/path racket/port racket/string
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([result #f])
              ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))
(define (true? value)
  (and (mdl-atom? value) (string=? (mdl-atom-pname value) "T")))

(check-true (mdl-false? (run "<N=? 3 3>")))
(check-true (true? (run "<N=? 3 4>")))
(check-true (mdl-false? (run "<N=? 'SAME 'SAME>")))
(check-true (mdl-false? (run "<N=? (1 2) (1 2)>")))
(check-true (true? (run "<N=? (1 2) (1 3)>")))
(check-true (mdl-false? (run "<N=? <STRING \"ab\"> <STRING \"ab\">>")))
(check-true (mdl-false?
             (run "<NEWTYPE G3-NEQ-X WORD> <N=? <CHTYPE 7 G3-NEQ-X> <CHTYPE 7 G3-NEQ-X>>")))
(check-true (true?
             (run "<NEWTYPE G3-NEQ-X WORD> <NEWTYPE G3-NEQ-Y WORD> <N=? <CHTYPE 7 G3-NEQ-X> <CHTYPE 7 G3-NEQ-Y>>")))
(check-exn #rx"TOO-FEW-ARGUMENTS-SUPPLIED" (lambda () (run "<N=?>")))
(check-exn #rx"TOO-FEW-ARGUMENTS-SUPPLIED" (lambda () (run "<N=? 1>")))
(check-exn #rx"TOO-MANY-ARGUMENTS-SUPPLIED" (lambda () (run "<N=? 1 2 3>")))

;; The two bounded reference probes timed out. Preserve the established
;; finite/explicit-failure boundary of Racket's =? comparator.
(check-true (mdl-false? (run "<SET L (1)> <PUTREST .L .L> <N=? .L .L>")))
(check-exn #rx"unsupported cyclic structural equality"
           (lambda ()
             (run "<SET A (1)> <PUTREST .A .A> <SET B (1)> <PUTREST .B .B> <N=? .A .B>")))

(displayln "structural N=? tests passed")
