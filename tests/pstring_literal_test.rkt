#lang racket/base
;; Issue #88: custom WORD-primtype #type representation, from PSTRING.
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

(define parsed (parse-mdl "#PSTRING 0"))
(check-equal? (length parsed) 1)
(check-equal? (mdl-node-kind (car parsed)) 'typed)
(check-equal? (car (mdl-node-value (car parsed))) "#PSTRING")
(check-equal? (mdl-node-kind (cdr (mdl-node-value (car parsed)))) 'atom)
(check-equal? (length (mdl-node-value (car (parse-mdl "(OBJ #PSTRING 0)")))) 2)

(check-equal? (mdl-atom-pname
               (run "<NEWTYPE PSTRING WORD> <TYPE #PSTRING 0>")) "PSTRING")
(check-equal? (mdl-atom-pname
               (run "<NEWTYPE PSTRING WORD> <PRIMTYPE #PSTRING 0>")) "WORD")
(check-equal? (mdl-atom-pname
               (run "<NEWTYPE PSTRING WORD> <=? #PSTRING 0 <CHTYPE #WORD 0 PSTRING>>")) "T")
(check-equal? (mdl-atom-pname
               (run "<NEWTYPE PSTRING WORD> <=? #PSTRING *777* <CHTYPE #WORD *777* PSTRING>>")) "T")
(check-equal? (mdl-atom-pname
               (run "<NEWTYPE PSTRING WORD> <DEFINE M3PS (\"AUX\" (OBJ #PSTRING 0)) <TYPE .OBJ>> <M3PS>"))
              "PSTRING")

;; Unknown types, different primitive storage and non-integer WORD data
;; remain explicit errors rather than silent atom/default splitting.
(check-exn #rx"unknown MDL TYPE"
           (lambda () (run "#PSTRING 0")))
(check-exn #rx"primitive type mismatch"
           (lambda () (run "<NEWTYPE PSTRING LIST> #PSTRING 0")))
(check-exn #rx"numeric WORD"
           (lambda () (run "<NEWTYPE PSTRING WORD> #PSTRING 1.5")))
(check-exn #rx"36-bit word"
           (lambda () (run "<NEWTYPE PSTRING WORD> #PSTRING 68719476736")))

(displayln "custom WORD-primtype literal tests passed")
