#lang racket/base
;; M4 S8 (issue #167): the ABS SUBR. Contract: docs/SEMANTICS.md "M4: ABS
;; (#167)"; reference observations docs/evidence/M4/ABS-REFERENCE.md
;; (abs-probe.json).
(require rackunit racket/runtime-path
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")
;; Host-level access to the SUBR, for arguments no MDL literal can produce
;; (the reader turns an out-of-range integer into a FLOAT).
(define-runtime-path core-path "../mdl/runtime/core.rkt")
(define (host-abs . values) (apply (dynamic-require core-path 'mdl-abs) values))
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
;; check-equal? uses equal?, so a FIX 5 never matches a FLOAT 5.0 (the
;; result TYPE is observable).
(define-syntax-rule (check* form) (test-case (format "~s" 'form) form))

;; --- FIX (probe fix) ------------------------------------------------------------
(check* (check-equal? (run "<ABS 5>") 5))
(check* (check-equal? (name "<TYPE <ABS 5>>") "FIX"))
(check* (check-equal? (run "<ABS -5>") 5))
(check* (check-equal? (name "<TYPE <ABS -5>>") "FIX"))
(check* (check-equal? (run "<ABS 0>") 0))
(check* (check-equal? (name "<TYPE <ABS 0>>") "FIX"))
(check* (check-equal? (run "<ABS -1>") 1))
(check* (check-equal? (run "<ABS 1>") 1))

;; --- FLOAT (probe float, float-large) -----------------------------------------
(check* (check-equal? (run "<ABS 2.5>") 2.5))
(check* (check-equal? (name "<TYPE <ABS 2.5>>") "FLOAT"))
(check* (check-equal? (run "<ABS -2.5>") 2.5))
(check* (check-equal? (name "<TYPE <ABS -2.5>>") "FLOAT"))
(check* (check-equal? (run "<ABS 0.0>") 0.0))
(check* (check-equal? (name "<TYPE <ABS 0.0>>") "FLOAT"))
(check* (check-equal? (run "<ABS -0.5>") 0.5))
(check* (check-equal? (name "<==? <ABS -2.5> 2.5>") "T"))
;; This reader has no exponent FLOAT syntax (1.0E20 is a strict reader
;; failure), so the probe's -1.0E20 is formed by multiplication (probe
;; float-large, computed form) or passed from the host.
(check* (check-equal? (run "<ABS <* -100000000000.0 1000000000.0>>") 1e20))
(check* (check-equal? (name "<==? <ABS <* -100000000000.0 1000000000.0>>
                                  <* 100000000000.0 1000000000.0>>") "T"))
(check* (check-equal? (name "<TYPE <ABS <* -100000000000.0 1000000000.0>>>") "FLOAT"))
(check* (check-equal? (host-abs -1e20) 1e20))
(check* (check-equal? (name "<==? <ABS <- <MIN>>> <MIN>>") "T"))
(check* (check-equal? (name "<==? <ABS <MIN>> <MIN>>") "T"))
(check* (check-equal? (name "<TYPE <ABS <- <MIN>>>>") "FLOAT"))
;; <MAX> is the least PDP-10 FLOAT here (ADR-0059), so its ABS is <MIN>; the
;; reference's <MAX> is DBL_MIN (positive), so there <ABS <MAX>> is <MAX>.
(check* (check-equal? (name "<==? <ABS <MAX>> <MIN>>") "T"))
(check* (check-equal? (name "<G? <ABS <MAX>> 0>") "T"))

;; --- 36-bit FIX boundaries (probe fix-36bit-boundaries, fix-most-negative) -----
(check* (check-equal? (run "<ABS 34359738367>") 34359738367))
(check* (check-equal? (run "<ABS -34359738367>") 34359738367))
(check* (check-equal? (name "<TYPE <ABS -34359738367>>") "FIX"))
;; -2^35 has no positive 36-bit counterpart: a strict overflow, never a wrap
;; to -2^35 and never a FLOAT (documented deviation: the reference's 64-bit
;; FIX gives 34359738368).
(check* (check-equal? (run "-34359738368") -34359738368))
(check* (check-exn #rx"mdl-abs: FIX overflow" (lambda () (run "<ABS -34359738368>"))))
(check* (check-exn #rx"FIX overflow" (lambda () (host-abs (- (expt 2 35))))))
;; A host integer outside the 36-bit range is refused, never wrapped.
(check* (check-exn #rx"FIX overflow" (lambda () (host-abs (expt 2 35)))))
(check* (check-exn #rx"FIX overflow" (lambda () (host-abs (- -1 (expt 2 35))))))
;; Beyond -2^35 the reader gives a FLOAT (M1 issue #8), so ABS is FLOAT here.
(check* (check-equal? (run "<ABS -34359738369>") 34359738369.0))
(check* (check-equal? (name "<TYPE <ABS -34359738369>>") "FLOAT"))

;; --- Arity (probe err-no-args, err-two-args) ----------------------------------
(check* (check-exn #rx"mdl-abs: TOO-FEW-ARGUMENTS-SUPPLIED" (lambda () (run "<ABS>"))))
(check* (check-exn #rx"mdl-abs: TOO-MANY-ARGUMENTS-SUPPLIED" (lambda () (run "<ABS 1 2>"))))
(check* (check-exn #rx"mdl-abs: TOO-MANY-ARGUMENTS-SUPPLIED" (lambda () (run "<ABS -1 -2>"))))

;; --- Non-numeric arguments are refused (probe err-*) ----------------------------
(define abs-refusal #rx"mdl-abs: expected MDL FIX or FLOAT")
(check* (check-exn abs-refusal (lambda () (run "<ABS \"A\">"))))
(check* (check-exn abs-refusal (lambda () (run "<ABS A>"))))
(check* (check-exn abs-refusal (lambda () (run "<ABS 'A>"))))
(check* (check-exn abs-refusal (lambda () (run "<ABS '(1 2)>"))))
(check* (check-exn abs-refusal (lambda () (run "<ABS <>>"))))
(check* (check-exn abs-refusal (lambda () (run "<ABS !\\A>"))))
(check* (check-exn abs-refusal (lambda () (run "<ABS [-1]>"))))

;; --- ABS as an applicable SUBR value (probe applicable) -------------------------
(check* (check-equal? (name "<TYPE ,ABS>") "SUBR"))
(check* (check-equal? (run "<APPLY ,ABS -7>") 7))
(check* (check-equal? (run "<MAPF ,LIST ,ABS '(-1 2 -3)>") (run "'(1 2 3)")))

;; --- The game's own expressions (probe game-*) ----------------------------------
;; 77act1.mud:951 (CYCLOPS; COUNT is DECLed FIX): <G? <ABS .COUNT> 5>.
(for ([row (in-list '((0 #f) (-6 #t) (6 #t) (-5 #f) (5 #f)))])
  (test-case (format "77act1.mud:951 COUNT ~a" (car row))
    (define v (run (format "<SET COUNT ~a> <G? <ABS .COUNT> 5>" (car row))))
    (check-equal? (not (mdl-false? v)) (cadr row))))
;; 77act1.mud:1031/1050 (CYCLOPS-ROOM, AOS-SOS): <NTH ,CYCLOMAD <ABS .VARS>>.
(define cyclomad "<SETG CM '[\"a\" \"b\" \"c\" \"d\" \"e\" \"f\"]> ")
(define (nth-is source expected)
  (name (string-append cyclomad "<=? " source " \"" expected "\">")))
(check* (check-equal? (nth-is "<NTH ,CM <ABS -1>>" "a") "T"))
(check* (check-equal? (nth-is "<NTH ,CM <ABS 2>>" "b") "T"))
(check* (check-equal? (nth-is "<NTH ,CM <ABS -6>>" "f") "T"))
(check* (check-equal? (name (string-append cyclomad "<SET FOO -2> <SET FOO <- .FOO 1>> "
                                           "<=? <NTH ,CM <ABS .FOO>> \"c\">"))
                      "T"))
;; 77act1.mud:949 (CYCLOPS): <PUT .RM ,RVARS <ABS <RVARS .RM>>>.
(check* (check-equal? (run "<SETG V [-3]> <PUT ,V 1 <ABS <1 ,V>>> <1 ,V>") 3))
(check* (check-equal? (name "<SETG V [-3]> <PUT ,V 1 <ABS <1 ,V>>> <TYPE <1 ,V>>") "FIX"))
