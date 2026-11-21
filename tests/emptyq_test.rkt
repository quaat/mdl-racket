#lang racket/base
;; Native observations: docs/evidence/M3/emptyq-{reference,error-reference}.json.
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))
(define (truth-name value)
  (if (mdl-false? value) "FALSE" (mdl-atom-pname value)))

;; These cases fail at unassigned EMPTY? before issue #75's implementation.
(for ([source (in-list
               '("<EMPTY? '()>" "<EMPTY? '[]>" "<EMPTY? '![]>"
                 "<EMPTY? \"\">" "<EMPTY? <>>"
                 "<EMPTY? <REST '(A) 1>>"
                 "<DEFINE TUPQ (\"TUPLE\" X) <EMPTY? .X>> <TUPQ>"
                 "<NEWTYPE M3EMPTY LIST> <EMPTY? <CHTYPE '() M3EMPTY>>"))])
  (check-equal? (truth-name (run source)) "T"))
(for ([source (in-list
               '("<EMPTY? '(1)>" "<EMPTY? '[1]>" "<EMPTY? '![1]>"
                 "<EMPTY? \"a\">" "<EMPTY? #FALSE (1)>"
                 "<PROG ((L '(1))) <PUTREST .L .L> <EMPTY? .L>>"
                 "<DEFINE TUPQ (\"TUPLE\" X) <EMPTY? .X>> <TUPQ 1>"))])
  (check-equal? (truth-name (run source)) "FALSE"))
(check-exn #rx"Not enough|TOO-FEW" (lambda () (run "<EMPTY?>")))
(check-exn #rx"Too many|TOO-MANY" (lambda () (run "<EMPTY? '() '()>")))
(for ([source (in-list '("<EMPTY? 'A>" "<EMPTY? 1>" "<EMPTY? #WORD 1>"))])
  (check-exn #rx"structured|WRONG_TYPE" (lambda () (run source))))
