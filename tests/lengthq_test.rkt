#lang racket/base
;; Native observations: docs/evidence/M3/lengthq-{reference,error-reference}.json.
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
(define (result value)
  (if (mdl-false? value) 'FALSE value))

;; Red at unassigned LENGTH? after the EMPTY? correction.
(for ([pair (in-list
             '(("<LENGTH? '() 0>" . 0)
               ("<LENGTH? '() -1>" . 0)
               ("<LENGTH? '(1) -1>" . FALSE)
               ("<LENGTH? '(1) 0>" . FALSE)
               ("<LENGTH? '(1) 1>" . 1)
               ("<LENGTH? '(1 2) 1>" . FALSE)
               ("<LENGTH? '(1 2) 2>" . 2)
               ("<LENGTH? '(1 2) 3>" . 2)
               ("<LENGTH? '[1 2] 2>" . 2)
               ("<LENGTH? '![1 2] 2>" . 2)
               ("<LENGTH? \"ab\" 2>" . 2)
               ("<LENGTH? #FALSE (1 2) 2>" . 2)
               ("<DEFINE TUPLQ (\"TUPLE\" X) <LENGTH? .X 2>> <TUPLQ 1 2>" . 2)
               ("<NEWTYPE M3LQ LIST> <LENGTH? <CHTYPE '(1 2) M3LQ> 2>" . 2)
               ("<LENGTH? <REST '(1 2) 1> 1>" . 1)
               ("<PROG ((L '(1))) <PUTREST .L .L> <LENGTH? .L 3>>" . FALSE)))])
  (check-equal? (result (run (car pair))) (cdr pair)))
(check-exn #rx"Not enough|TOO-FEW" (lambda () (run "<LENGTH?>")))
(check-exn #rx"Not enough|TOO-FEW" (lambda () (run "<LENGTH? '()>")))
(check-exn #rx"Too many|TOO-MANY" (lambda () (run "<LENGTH? '() 1 2>")))
(check-exn #rx"structured|WRONG_TYPE" (lambda () (run "<LENGTH? 'A 1>")))
(check-exn #rx"FIX|WRONG_TYPE" (lambda () (run "<LENGTH? '(1) 'A>")))
