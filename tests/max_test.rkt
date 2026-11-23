#lang racket/base
;; M4 S5a (issue #122): the MAX SUBR. Contract: docs/SEMANTICS.md "M4 S5a
;; MAX"; ADR-0059 (zero-argument identity); reference observations
;; docs/evidence/M4/MAX-REFERENCE.md (max-probe.json).
(require rackunit racket/flonum racket/runtime-path
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")
;; Host-level access to the SUBR, for arguments no MDL literal can produce
;; (the reader turns an out-of-range integer into a FLOAT).
(define-runtime-path core-path "../mdl/runtime/core.rkt")
(define (host-max . values) (apply (dynamic-require core-path 'mdl-max) values))
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([value #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))
(define (name source) (mdl-atom-pname (run source)))
;; Each check runs in its own test-case so one failure or exception does
;; not hide the remaining observations. check-equal? uses equal?, so a FIX
;; result 3 never matches an expected FLOAT 3.0 (contagion is observable).
(define-syntax-rule (check* form) (test-case (format "~s" 'form) form))

;; --- Two FIX arguments: both orders, equal operands (probe fix-two) -------
(check* (check-equal? (run "<MAX 1 2>") 2))
(check* (check-equal? (run "<MAX 2 1>") 2))
(check* (check-equal? (name "<TYPE <MAX 1 2>>") "FIX"))
(check* (check-equal? (run "<MAX 3 3>") 3))
(check* (check-equal? (name "<TYPE <MAX 3 3>>") "FIX"))
(check* (check-equal? (run "<MAX 0 0>") 0))

;; --- Negative FIX (probe fix-negative) -----------------------------------
(check* (check-equal? (run "<MAX -1 -2>") -1))
(check* (check-equal? (run "<MAX -2 -1>") -1))
(check* (check-equal? (run "<MAX -5 0>") 0))
(check* (check-equal? (run "<MAX 0 -5>") 0))
(check* (check-equal? (run "<MAX -7 -7>") -7))
(check* (check-equal? (run "<MAX -1 1>") 1))

;; --- Three or more FIX (probe fix-many) ----------------------------------
(check* (check-equal? (run "<MAX 1 5 3>") 5))
(check* (check-equal? (run "<MAX 5 1 3>") 5))
(check* (check-equal? (run "<MAX 1 3 5>") 5))
(check* (check-equal? (run "<MAX 4 4 4 4>") 4))
(check* (check-equal? (run "<MAX -3 -9 -1 -4>") -1))
(check* (check-equal? (run "<MAX 1 2 3 4 5 6 7 8 9 10>") 10))

;; --- A single argument (probe single) ------------------------------------
(check* (check-equal? (run "<MAX 7>") 7))
(check* (check-equal? (name "<TYPE <MAX 7>>") "FIX"))
(check* (check-equal? (run "<MAX -7>") -7))
(check* (check-equal? (run "<MAX 2.5>") 2.5))
(check* (check-equal? (name "<TYPE <MAX 2.5>>") "FLOAT"))
(check* (check-equal? (run "<MAX 0>") 0))

;; --- FIX/FLOAT contagion: one FLOAT makes the result FLOAT, whichever
;; operand is larger (probe mixed, mixed-many) ------------------------------
(check* (check-equal? (run "<MAX 1 2.0>") 2.0))
(check* (check-equal? (name "<TYPE <MAX 1 2.0>>") "FLOAT"))
(check* (check-equal? (run "<MAX 2.0 1>") 2.0))
(check* (check-equal? (run "<MAX 3 2.0>") 3.0))
(check* (check-equal? (name "<TYPE <MAX 3 2.0>>") "FLOAT"))
(check* (check-equal? (run "<MAX 2.0 3>") 3.0))
(check* (check-equal? (name "<TYPE <MAX 2.0 3>>") "FLOAT"))
(check* (check-equal? (run "<MAX 2 2.0>") 2.0))
(check* (check-equal? (name "<TYPE <MAX 2 2.0>>") "FLOAT"))
(check* (check-equal? (run "<MAX 2.0 2>") 2.0))
(check* (check-equal? (run "<MAX 1 2 3.0>") 3.0))
(check* (check-equal? (run "<MAX 5 1.0 3>") 5.0))
(check* (check-equal? (run "<MAX 1.0 5 3>") 5.0))
(check* (check-equal? (run "<MAX -1 -2.5>") -1.0))
(check* (check-equal? (name "<TYPE <MAX -1 -2.5>>") "FLOAT"))

;; --- FLOAT operands (probe float-float, float-negative) -------------------
(check* (check-equal? (run "<MAX 1.5 2.5>") 2.5))
(check* (check-equal? (run "<MAX 2.5 1.5>") 2.5))
(check* (check-equal? (run "<MAX 0.5 0.5>") 0.5))
(check* (check-equal? (run "<MAX 1.0 2.0 0.5>") 2.0))
(check* (check-equal? (run "<MAX -1.0 0.5>") 0.5))
(check* (check-equal? (run "<MAX 0.5 -1.0>") 0.5))
;; Documented reference deviation: pinned Confusion seeds a FLOAT first
;; argument with host DBL_MIN, so these return ~0.0 there. The manual's
;; MAX is the largest argument.
(check* (check-equal? (run "<MAX -1.5 -2.5>") -1.5))
(check* (check-equal? (run "<MAX -2.5 -1.5>") -1.5))
(check* (check-equal? (run "<MAX -1.5>") -1.5))
(check* (check-equal? (run "<MAX -1.5 -2>") -1.5))
(check* (check-equal? (run "<MAX -2 -1.5>") -1.5))

;; --- 36-bit FIX boundaries (probe fix-36bit-boundaries) -------------------
(check* (check-equal? (run "<MAX 34359738367 0>") 34359738367))
(check* (check-equal? (run "<MAX 0 34359738367>") 34359738367))
(check* (check-equal? (run "<MAX -34359738368 0>") 0))
(check* (check-equal? (run "<MAX -34359738368 -34359738367>") -34359738367))
(check* (check-equal? (run "<MAX 34359738367 -34359738368>") 34359738367))
(check* (check-equal? (run "<MAX 34359738367 34359738367>") 34359738367))
(check* (check-equal? (run "<MAX -34359738368 -34359738368>") -34359738368))
;; A host integer outside the 36-bit FIX range is refused, never wrapped.
(check* (check-exn #rx"FIX overflow" (lambda () (host-max (expt 2 35) 0))))
(check* (check-exn #rx"FIX overflow" (lambda () (host-max 0 (- -1 (expt 2 35))))))

;; --- Zero arguments (ADR-0059): the least PDP-10 FLOAT, the exact
;; negation of <MIN>, an ordinary FLOAT --------------------------------------
(define greatest-float (fl* 134217727.0 (flexpt 2.0 100.0)))
(define least-float (fl- 0.0 greatest-float))
(check* (check-true (flonum? (run "<MAX>"))))
(check* (check-equal? (run "<MAX>") least-float))
(check* (check-equal? (name "<TYPE <MAX>>") "FLOAT"))
(check* (check-equal? (name "<==? <MAX> <- <MIN>>>") "T"))
(check* (check-equal? (name "<L? <MAX> <MIN>>") "T"))
(check* (check-equal? (name "<L? <MAX> -1>") "T"))
(check* (check-true (mdl-false? (run "<G? <MAX> 0>"))))
(check* (check-equal? (run "<MAX <MAX> -1>") -1.0))
(check* (check-equal? (run "<MAX <MAX> 1>") 1.0))
(check* (check-equal? (run "<MAX <MAX> <MAX>>") least-float))
;; PDP-10 image: two's complement of 377777777777 (octal).
(check* (check-equal? (mdl-word-bits (run "<CHTYPE <MAX> WORD>")) #o400000000001))
(check* (check-equal? (run "<CHTYPE <MAX> FIX>") -34359738367))

;; --- Non-numeric arguments are refused (probe err-*) ----------------------
(define max-refusal #rx"mdl-max: expected MDL FIX or FLOAT")
(check* (check-exn max-refusal (lambda () (run "<MAX 1 \"A\">"))))
(check* (check-exn max-refusal (lambda () (run "<MAX \"A\" 1>"))))
(check* (check-exn max-refusal (lambda () (run "<MAX 1 A>"))))
(check* (check-exn max-refusal (lambda () (run "<MAX 1 '(1 2)>"))))
(check* (check-exn max-refusal (lambda () (run "<MAX 1 <>>"))))
(check* (check-exn max-refusal (lambda () (run "<MAX 1 !\\A>"))))
(check* (check-exn max-refusal (lambda () (run "<MAX A>"))))
(check* (check-exn max-refusal (lambda () (run "<MAX 1 2 \"A\">"))))
(check* (check-exn max-refusal (lambda () (run "<MAX 1.5 [2]>"))))

;; --- The game's own expressions -------------------------------------------
;; 78melee.mud:447-448 (BLOW; DEF is DECLed FIX at 78melee.mud:381):
;;   (<==? .RES ,LIGHT-WOUND> <SET DEF <MAX 0 <- .DEF 1>>>)
;;   (<==? .RES ,SERIOUS-WOUND> <SET DEF <MAX 0 <- .DEF 2>>>)
;; Expected values are the probe melee-def-* observations.
(define (wound def res)
  (run (format "<SETG LIGHT-WOUND 3> <SETG SERIOUS-WOUND 4> <SET DEF ~a> <SET RES ~a>
<COND (<==? .RES ,LIGHT-WOUND> <SET DEF <MAX 0 <- .DEF 1>>>)
      (<==? .RES ,SERIOUS-WOUND> <SET DEF <MAX 0 <- .DEF 2>>>)>
.DEF" def res)))
(for ([row (in-list '((-3 0 0) (0 0 0) (1 0 0) (2 1 0) (3 2 1) (5 4 3)))])
  (define def (car row))
  (test-case (format "78melee.mud:447 LIGHT-WOUND, DEF ~a" def)
    (check-equal? (wound def 3) (cadr row)))
  (test-case (format "78melee.mud:448 SERIOUS-WOUND, DEF ~a" def)
    (check-equal? (wound def 4) (caddr row))))
(check* (check-equal? (name "<SET DEF 2> <TYPE <MAX 0 <- .DEF 1>>>") "FIX"))
;; 77rooms.mud:741 argument shape <ACCESS .CH <MAX 0 <- .FL 1>>> (the
;; PRINTO branch itself is unreachable under ADR-0055).
(check* (check-equal? (run "<SET FL 0> <MAX 0 <- .FL 1>>") 0))
(check* (check-equal? (run "<SET FL 1> <MAX 0 <- .FL 1>>") 0))
(check* (check-equal? (run "<SET FL 100> <MAX 0 <- .FL 1>>") 99))
