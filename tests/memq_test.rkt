#lang racket/base
;; Reference-backed MEMQ identity and REST aliasing, issue #63.
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")

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
(define (atom-names values)
  (map mdl-atom-pname (mdl-list->list values)))

(check-equal? (atom-names (run "<MEMQ 'B '(A B C)>")) '("B" "C"))
(check-true (mdl-false? (run "<MEMQ 'X '(A B C)>")))
(check-true (mdl-false? (run "<MEMQ '(1) '((1) (2))>")))
(check-equal? (atom-names (run "<SET L '(A B C)> <PUT <MEMQ 'B .L> 1 'X> .L"))
              '("A" "X" "C"))
(define vector-tail (run "<MEMQ 2 '[1 2 3]>"))
(check-equal? (mdl-array-kind vector-tail) 'VECTOR)
(check-equal? (mdl-array-length vector-tail) 2)
(check-equal? (mdl-nth vector-tail 1) 2)
(define uvector-tail (run "<MEMQ 2 '![1 2 3!]>"))
(check-equal? (mdl-array-kind uvector-tail) 'UVECTOR)
(check-equal? (mdl-array-length uvector-tail) 2)
(check-equal? (mdl-nth uvector-tail 1) 2)
(check-exn #rx"TOO-FEW-ARGUMENTS-SUPPLIED" (lambda () (run "<MEMQ 1>")))
(check-exn #rx"TOO-MANY-ARGUMENTS-SUPPLIED" (lambda () (run "<MEMQ 1 '(1) 2>")))
(check-exn #rx"structured" (lambda () (run "<MEMQ 1 2>")))
(check-exn #rx"unsupported STRING MEMQ"
           (lambda () (run "<MEMQ <NTH \"ABC\" 2> \"ABC\">")))

(displayln "MEMQ primitive tests passed")
