#lang racket/base
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns])
    (for/fold ([value #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))
(parameterize ([current-mdl-globals (make-hasheq)]
               [current-mdl-locals (list (make-hasheq))]
               [current-mdl-atom-space (make-mdl-atom-space)])
  (check-equal? (mdl-atom-pname (run "<UTYPE <IUVECTOR 2>>")) "LOSE")
  (check-equal? (mdl-atom-pname (run "<UTYPE <IUVECTOR 2 1>>")) "FIX")
  (check-equal? (run "<LENGTH <IUVECTOR 3 1>>") 3)
  (check-equal? (run "<SETG N 0> <IUVECTOR 3 '<SETG N <+ ,N 1>>> ,N") 3)
  (check-equal? (mdl-atom-pname
                 (run "<NEWTYPE M3OBJ VECTOR> <SETG UV <IUVECTOR 20>> <SETG TAIL <REST ,UV 20>> <CHUTYPE ,TAIL M3OBJ> <UTYPE ,TAIL>"))
                "M3OBJ")
  (check-equal? (run "<SETG UV <IUVECTOR 2 1>> <CHUTYPE ,UV WORD> <TYPE <1 ,UV>>")
                (mdl-atom "WORD"))
  (check-equal? (mdl-atom-pname
                 (run "<SETG UV <IUVECTOR 2 1>> <SETG TAIL <REST ,UV 1>> <CHUTYPE ,TAIL WORD> <UTYPE ,UV>"))
                "WORD")
  (check-equal? (mdl-atom-pname
                 (run "<SETG UV <IUVECTOR 2 1>> <SETG TAIL <REST ,UV 1>> <CHUTYPE ,TAIL WORD> <TYPE <1 ,UV>>"))
                "WORD")
  (check-exn #rx"primitive|primtype" (lambda () (run "<CHUTYPE <IUVECTOR 2 1> LIST>")))
  (check-exn #rx"UVECTOR" (lambda () (run "<CHUTYPE [1] FIX>")))
  (check-exn #rx"length" (lambda () (run "<IUVECTOR -1>"))))
