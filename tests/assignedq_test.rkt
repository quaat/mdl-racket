#lang racket/base
;; Native observations: docs/evidence/M3/assignedq-{reference,error-reference}.json.
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
  (if (mdl-false? value) 'FALSE (mdl-atom-pname value)))

(for ([pair (in-list
             '(("<ASSIGNED? M3A>" . FALSE)
               ("<SET M3A 3> <ASSIGNED? M3A>" . "T")
               ("<SETG M3A 3> <ASSIGNED? M3A>" . FALSE)
               ("<PROG (M3A) <ASSIGNED? M3A>>" . FALSE)
               ("<PROG ((M3A 3)) <ASSIGNED? M3A>>" . "T")
               ("<PROG (M3A) <SET M3A 0> <ASSIGNED? M3A>>" . "T")
               ("<PROG ((M3A 3)) <PROG (M3A) <ASSIGNED? M3A>>>" . FALSE)
               ("<DEFINE M3F (X \"AUX\" Y) <ASSIGNED? Y>> <M3F 3>" . FALSE)
               ("<DEFINE M3F (X \"AUX\" Y) <SET Y 4> <ASSIGNED? Y>> <M3F 3>" . "T")))])
  (check-equal? (result (run (car pair))) (cdr pair)))
(check-exn #rx"Not enough|TOO-FEW" (lambda () (run "<ASSIGNED?>")))
(check-exn #rx"ATOM|atom" (lambda () (run "<ASSIGNED? 3>")))
(check-exn #rx"ATOM|atom" (lambda () (run "<ASSIGNED? \"M3A\">")))
(check-exn #rx"ENV|frame|unsupported" (lambda () (run "<ASSIGNED? M3A 1>")))
