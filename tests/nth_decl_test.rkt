#lang racket/base
;; M3 issue #96: manual §14.1 and docs/evidence/M3/nth-decl-reference.json.
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
(define (true? value) (and (mdl-atom? value) (string=? (mdl-atom-pname value) "T")))
(define (false? value) (mdl-false? value))

(check-true (true? (run "<DECL? [1 2 3] '<VECTOR [3 FIX]>>")))
(check-true (false? (run "<DECL? [1 2] '<VECTOR [3 FIX]>>")))
(check-true (true? (run "<DECL? [1 2 3 4] '<VECTOR [3 FIX]>>")))
(check-true (false? (run "<DECL? [1 A 3] '<VECTOR [3 FIX]>>")))
(check-true (true? (run "<DECL? [1 A 2 B] '<VECTOR [2 FIX ATOM]>>")))
(check-true (false? (run "<DECL? [1 A 2] '<VECTOR [2 FIX ATOM]>>")))
(check-true (true? (run "<DECL? [1 A 2 B 3] '<VECTOR [2 FIX ATOM]>>")))
(check-true (true? (run "<DECL? [A 1 2 3] '<VECTOR ATOM [3 FIX]>>")))
(check-true (true? (run "<DECL? [1 2 3 A] '<VECTOR [3 FIX] ATOM>>")))
(check-true (true? (run "<DECL? (1 2 3 4) '<LIST [3 FIX]>>")))
(check-true (true? (run "<DECL? (1 2 3 A B) '<LIST [3 FIX] [REST ATOM]>>")))
(check-true (false? (run "<DECL? [] '<VECTOR [34359738367 FIX]>>")))

;; Attached declaration from unchanged 77act1.mud:78.
(check-true (true? (run "<DEFINE F (PV) #DECL ((PV) <VECTOR [3 ANY]>) T> <F [1 A 3]>")))
(check-exn #rx"declaration|DECL|satisf" (lambda ()
  (run "<DEFINE F (PV) #DECL ((PV) <VECTOR [3 ANY]>) T> <F [1 2]>")))

(check-exn #rx"positive|count|NTH" (lambda ()
  (run "<DECL? [1] '<VECTOR [0 FIX]>>")))
(check-exn #rx"positive|count|NTH" (lambda ()
  (run "<DECL? [1] '<VECTOR [-1 FIX]>>")))
(check-exn #rx"at least one|NTH" (lambda ()
  (run "<DECL? [1] '<VECTOR [3]>>")))

;; NEWTYPE stores the same declaration Pattern and validates its shape early.
(check-true (true? (run
  "<NEWTYPE M3N VECTOR '<<PRIMTYPE VECTOR> [2 FIX]>> <DECL? <CHTYPE '[1 2] M3N> <GET M3N DECL>>")))
(check-exn #rx"declaration|DECL|satisf" (lambda ()
  (run "<NEWTYPE M3N VECTOR '<<PRIMTYPE VECTOR> [2 FIX]>> <CHTYPE '[1] M3N>")))
