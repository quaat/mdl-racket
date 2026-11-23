#lang racket/base
;; S7 (ADR-0050): <RESET channel> of a terminal CHANNEL (77rooms.mud:303,
;; 77defs.mud:433). Returns the same CHANNEL, keeps every slot, the BACK
;; predecessor and queued input; strict errors otherwise. The end-of-input
;; flag it clears is tested with READSTRING in readstring_test.rkt.
;; Reference: evidence/M3/S7-frontier/primitives-reference.json
;; (reset-inchan-return, reset-outchan-return, reset-arg-errors,
;; contin-put-then-reset).
(require rackunit racket/port
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))

;; Fresh isolated context with explicit host ports; returns the last value.
(define (run source #:in [in (open-input-string "")]
             #:out [out (open-output-string)] #:after [after #f])
  (parameterize ([current-namespace ns])
    (call-with-mdl-context
     (make-mdl-context #:input-port in #:output-port out)
     (lambda ()
       (define value
         (for/fold ([result #f])
                   ([expr (in-list (compile-program (parse-mdl source)))])
           (eval expr)))
       (if after (after value) value)))))
(define (pname value) (and (mdl-atom? value) (mdl-atom-pname value)))
(define (true? value) (equal? (pname value) "T"))

;; --- value: the same CHANNEL object ---------------------------------------
(check-true (true? (run "<==? <RESET ,INCHAN> ,INCHAN>")))
(check-equal? (pname (run "<TYPE <RESET ,INCHAN>>")) "CHANNEL")
(check-equal? (run "<LENGTH <RESET ,INCHAN>>") 19)
(check-true (true? (run "<==? <RESET ,OUTCHAN> ,OUTCHAN>")))
;; CONTIN's form, value discarded, and YES/NO's local INCHAN.
(check-true (true? (run "<RESET ,INCHAN> T")))
(check-true (true? (run "<PROG ((INCHAN ,INCHAN)) <==? <RESET .INCHAN> ,INCHAN>>")))

;; --- slots, predecessor and associations untouched ------------------------
(define (slots channel)
  (for/list ([i (in-range 1 (add1 (mdl-length channel)))]) (mdl-nth channel i)))
(run "<PUT ,OUTCHAN 13 1000>"
     #:after
     (lambda (_)
       (define in (mdl-gval "INCHAN"))
       (define out (mdl-gval "OUTCHAN"))
       (define before (list (slots in) (slots out)))
       (define back-before (mdl-nth (mdl-apply "BACK" in) 1))
       (mdl-apply "RESET" in)
       (mdl-apply "RESET" out)
       (check-equal? (list (slots in) (slots out)) before)
       (check-equal? (mdl-nth out 13) 1000)
       (check-equal? (mdl-nth (mdl-apply "BACK" in) 1) back-before)
       (check-equal? (mdl-nth in 2) "READ")
       (check-equal? (mdl-nth in 9) "TTY")))
;; CONTIN 77rooms.mud:297-303: the association PUT on the predecessor slot
;; survives RESET (Confusion contin-put-then-reset).
(check-equal?
 (pname (run "<PUT <1 <BACK ,INCHAN>> 6 FOO> <RESET ,INCHAN> <GET <1 <BACK ,INCHAN>> 6>"))
 "FOO")

;; --- queued input is not discarded, nothing is written --------------------
(let ([in (open-input-string "north\nwest\n")] [out (open-output-string)])
  (check-true (true? (run "<==? <RESET ,INCHAN> ,INCHAN>" #:in in #:out out)))
  (check-equal? (port->string in) "north\nwest\n")
  (check-equal? (get-output-string out) ""))

;; --- strict errors ---------------------------------------------------------
(check-exn #rx"^RESET: .*one CHANNEL argument" (lambda () (run "<RESET>")))
(check-exn #rx"^RESET: .*one CHANNEL argument"
           (lambda () (run "<RESET ,INCHAN ,INCHAN>")))
(check-exn #rx"^RESET: argument must be of type CHANNEL" (lambda () (run "<RESET 1>")))
(check-exn #rx"^RESET: argument must be of type CHANNEL"
           (lambda () (run "<RESET <CHTYPE ,INCHAN VECTOR>>")))
;; A forged CHANNEL (CHTYPE of a fresh VECTOR) is not open in this session.
(check-exn #rx"^RESET: CHANNEL is not open in this MDL session"
           (lambda ()
             (run "<RESET <CHTYPE [0 \"READ\" \"\" \"\" \"\" \"\" \"\" \"\" \"TTY\" \"\" 0 0 80 0 24 0 0 10 0] CHANNEL>>")))
;; A shifted view of a real terminal CHANNEL is refused (mode slot check).
(check-exn #rx"^RESET: CHANNEL is not open in this MDL session"
           (lambda () (run "<RESET <BACK ,INCHAN>>")))
;; A CHANNEL of another session is refused.
(define foreign
  (parameterize ([current-namespace ns])
    (call-with-mdl-context (make-mdl-context) (lambda () (mdl-gval "INCHAN")))))
(check-exn #rx"^RESET: CHANNEL is not open in this MDL session"
           (lambda () (run "T" #:after (lambda (_) (mdl-apply "RESET" foreign)))))
