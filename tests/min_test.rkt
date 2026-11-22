#lang racket/base
(require rackunit racket/flonum "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")
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
;; not hide the remaining observations.
(define-syntax-rule (check* form) (test-case (format "~s" 'form) form))

;; Original source, 77dung.mud:57: <SETG BIGFIX </ <CHTYPE <MIN> FIX> 2>>.
;; On the 36-bit target the greatest FLOAT has the word image
;; 377777777777 (octal), i.e. the greatest FIX.
(check* (check-equal? (run "<CHTYPE <MIN> FIX>") 34359738367))
(check* (check-equal? (run "</ <CHTYPE <MIN> FIX> 2>") 17179869183))
(check* (check-equal? (mdl-word-bits (run "<CHTYPE <MIN> WORD>")) 34359738367))
(check* (check-equal? (run "<MIN 4 2 3>") 2))
(check* (check-equal? (run "<MIN 4 2.0>") 2.0))
(check* (check-equal? (run "<MIN -3 -2>") -3))
(check* (check-equal? (run "<MIN 1 2.0>") 1.0))
(check* (check-equal? (run "<MIN 2.0 1>") 1.0))
(check* (check-exn #rx"number|FIX|FLOAT" (lambda () (run "<MIN A>"))))

;; R6: the zero-argument identity is an ordinary FLOAT: the greatest
;; PDP-10 single-precision value (2^27-1)*2^100, exactly representable
;; as a host flonum.
(define greatest-float (fl* 134217727.0 (flexpt 2.0 100.0)))
(define greatest-expr
  "<* 134217727 1024.0 1024.0 1024.0 1024.0 1024.0 1024.0 1024.0 1024.0 1024.0 1024.0>")
(check* (check-true (flonum? (run "<MIN>"))))
(check* (check-equal? (run "<MIN>") greatest-float))
(check* (check-equal? (name "<TYPE <MIN>>") "FLOAT"))
(check* (check-equal? (name "<PRIMTYPE <MIN>>") "WORD"))
(check* (check-equal? (name (string-append "<==? <MIN> " greatest-expr ">")) "T"))
(check* (check-equal? (name (string-append "<=? <MIN> " greatest-expr ">")) "T"))
(check* (check-equal? (name "<==? <MIN> <MIN>>") "T"))
(check* (check-equal? (run "<MIN <MIN> 1>") 1.0))
(check* (check-equal? (run "<MIN <MIN> <MIN>>") greatest-float))
(check* (check-equal? (run "<- <MIN> <MIN>>") 0.0))
(check* (check-equal? (run "<+ <MIN> 0>") greatest-float))
(check* (check-equal? (name "<G? <MIN> 1>") "T"))
(check* (check-true (mdl-false? (run "<L? <MIN> 1>"))))
(check* (check-equal? (name "<L? 1 <MIN>>") "T"))
(check* (check-true (mdl-false? (run "<0? <MIN>>"))))
(check* (check-equal? (run "<FLOAT 3>") 3.0))
;; FLOAT takes a FIX (manual 3.4; Confusion: "Arg to FLOAT must be FIX").
(check* (check-exn #rx"FLOAT must be FIX" (lambda () (run "<FLOAT <MIN>>"))))
(check* (check-exn #rx"FLOAT must be FIX" (lambda () (run "<FLOAT 1.5>"))))
(check* (check-exn #rx"FLOAT must be FIX" (lambda () (run "<FLOAT A>"))))
(check* (check-exn #rx"FIX overflow" (lambda () (run "<FIX <MIN>>"))))

;; CHTYPE from FLOAT to a WORD-primtype TYPE exposes the PDP-10
;; single-precision word image for every FLOAT, not only for <MIN>.
(check* (check-equal? (run "<CHTYPE 0.0 FIX>") 0))
(check* (check-equal? (run "<CHTYPE 0.5 FIX>") #o200400000000))
(check* (check-equal? (run "<CHTYPE 1.0 FIX>") #o201400000000))
(check* (check-equal? (mdl-word-bits (run "<CHTYPE -1.0 WORD>")) #o576400000000))
(check* (check-equal? (run "<CHTYPE -0.5 FIX>") (- #o200400000000)))
(check* (check-equal? (run "<CHTYPE <MIN> FLOAT>") greatest-float))
;; Host flonums the 36-bit format cannot hold exactly fail strictly.
(check* (check-exn #rx"PDP-10 FLOAT" (lambda () (run "<CHTYPE 0.1 FIX>"))))
(check* (check-exn #rx"PDP-10 FLOAT" (lambda () (run "<CHTYPE <* <MIN> 2> FIX>"))))
;; Bit operations on FLOAT remain unsupported, for <MIN> as for 1.0.
(check* (check-exn exn:fail? (lambda () (run "<ANDB <MIN> 1>"))))
(check* (check-exn exn:fail? (lambda () (run "<ANDB 1.0 3>"))))

;; Smallest positive PDP-10 FLOAT, 0.5*2^-128: exponent field 0, word
;; 000400000000 (octal). Half of it has no 36-bit image.
(define smallest-expr
  (string-append "</ 0.5 1024.0 1024.0 1024.0 1024.0 1024.0 1024.0 16.0"
                 " 1024.0 1024.0 1024.0 1024.0 1024.0 1024.0 16.0>"))
(check* (check-equal? (run (string-append "<CHTYPE " smallest-expr " FIX>"))
                      #o000400000000))
(check* (check-exn #rx"PDP-10 FLOAT"
                   (lambda () (run (string-append "<CHTYPE </ " smallest-expr " 2.0> FIX>")))))

;; A user NEWTYPE of primtype WORD receives the same image.
(check* (check-equal? (run "<NEWTYPE FOO WORD> <CHTYPE <CHTYPE 1.0 FOO> FIX>")
                      #o201400000000))
(check* (check-equal? (name "<NEWTYPE FOO WORD> <TYPE <CHTYPE -0.5 FOO>>") "FOO"))

;; CHUTYPE converts each FLOAT element through the same CHTYPE path.
(check* (check-equal? (run "<SET U <UVECTOR 1.0 0.5>> <CHUTYPE .U FIX> <1 .U>")
                      #o201400000000))
(check* (check-equal? (run "<SET U <UVECTOR 1.0 0.5>> <CHUTYPE .U FIX> <2 .U>")
                      #o200400000000))
(check* (check-equal? (run "<NEWTYPE FOO WORD> <SET U <UVECTOR 1.0>> <CHUTYPE .U FOO>
                            <CHTYPE <1 .U> FIX>")
                      #o201400000000))
;; An element without an exact image fails the whole CHUTYPE: no element
;; and not the element type is changed.
(check* (check-exn #rx"PDP-10 FLOAT"
                   (lambda () (run "<SET U <UVECTOR 1.0 0.1>> <CHUTYPE .U FIX>"))))
(test-case "failed CHUTYPE leaves the UVECTOR unchanged"
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (define (eval-mdl source)
      (for/fold ([value #f]) ([expr (in-list (compile-program (parse-mdl source)))])
        (eval expr)))
    (eval-mdl "<SETG U <UVECTOR 1.0 0.1>>")
    (check-exn #rx"PDP-10 FLOAT" (lambda () (eval-mdl "<CHUTYPE ,U FIX>")))
    (check-equal? (mdl-atom-pname (eval-mdl "<UTYPE ,U>")) "FLOAT")
    (check-equal? (eval-mdl "<1 ,U>") 1.0)
    (check-equal? (eval-mdl "<2 ,U>") 0.1)))
