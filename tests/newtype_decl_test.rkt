#lang racket/base
;; Manual §14.6 and pinned Confusion deviation:
;; docs/evidence/M3/newtype-decl-{reference,error-reference}.json.
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
(define (name value) (mdl-atom-pname value))

;; Red at the original three-argument NEWTYPE arity failure.
(check-equal? (name (run "<NEWTYPE M3N VECTOR '<<PRIMTYPE VECTOR> FIX>> <TYPE <GET M3N DECL>>")) "FORM")
(check-equal? (name (run "<NEWTYPE M3N VECTOR '<<PRIMTYPE VECTOR> FIX>> <TYPE <CHTYPE '[1] M3N>>")) "M3N")
(check-equal? (name (run "<NEWTYPE M3N VECTOR '<<PRIMTYPE VECTOR> FIX>> <DECL? '[1] <GET M3N DECL>>")) "T")
(check-exn #rx"declaration|TYPE-MISMATCH|does not satisfy"
           (lambda () (run "<NEWTYPE M3N VECTOR '<<PRIMTYPE VECTOR> FIX>> <CHTYPE '[A] M3N>")))
(check-exn #rx"declaration|TYPE-MISMATCH|does not satisfy"
           (lambda () (run "<NEWTYPE M3N VECTOR '<<PRIMTYPE VECTOR> FIX>> <SETG V <CHTYPE '[1] M3N>> <PUT ,V 1 'A> <CHTYPE ,V M3N>")))
(check-equal? (name (run "<NEWTYPE M3N VECTOR '<<PRIMTYPE VECTOR> FIX>> <NEWTYPE M3N VECTOR '<<PRIMTYPE VECTOR> ATOM>> <TYPE <CHTYPE '[A] M3N>>")) "M3N")
(check-equal? (name (run "<NEWTYPE EXIT VECTOR '<<PRIMTYPE VECTOR> [REST ATOM <OR ROOM CEXIT NEXIT>]>> <TYPE <GET EXIT DECL>>")) "FORM")
(check-true (mdl-false? (run "<NEWTYPE M3N VECTOR> <GET M3N DECL>")))
(check-exn #rx"pattern|declaration|DECL" (lambda () (run "<NEWTYPE M3N VECTOR 3>")))
(check-exn #rx"declaration|TYPE-MISMATCH|does not satisfy"
           (lambda () (run "<NEWTYPE M3N VECTOR '<VECTOR FIX>> <CHTYPE '[1] M3N>")))
(check-exn #rx"declaration|pattern|unsupported"
           (lambda () (run "<NEWTYPE M3N VECTOR '<BAD FIX>>")))
(check-exn #rx"declaration|pattern|unsupported"
           (lambda () (run "<NEWTYPE M3N VECTOR '<<PRIMTYPE VECTOR> [OPT FIX]>>")))
(check-exn #rx"TYPE|type|primitive" (lambda () (run "<NEWTYPE M3N VECTOR> <NEWTYPE M3N FIX>")))
(check-exn #rx"type|TYPE" (lambda () (run "<NEWTYPE M3N M3UNKNOWN>")))
(check-exn #rx"ATOM|atom" (lambda () (run "<NEWTYPE 3 VECTOR>")))
(check-exn #rx"arity|ARGUMENTS" (lambda () (run "<NEWTYPE M3N VECTOR 3 4>")))
