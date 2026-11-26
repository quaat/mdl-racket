#lang racket/base
;; M4 issue #196 (INV-12; maintainer decision 2026-11-26, the attached-
;; declaration ADR amendment in DECISIONS.md; docs/SEMANTICS.md "Amendment:
;; attached declarations are not enforced"): attached #DECLs are not enforced
;; at all in production, matching pinned Confusion. DECL?, GDECL/SETG,
;; positional declarations and CHTYPE stay strict with unchanged messages;
;; an attached #DECL is still validated when it is defined. The test-only
;; recorder still evaluates every attached check
;; (tests/decl_violation_recorder_test.rkt).
;; Smoke suite: needs no upstream source.
(require rackunit racket/list racket/string
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler
 (lambda (e)
   (when (exn:test:check? e)
     (for ([i (in-list (exn:test:check-stack e))])
       (eprintf "  ~a: ~e\n" (check-info-name i) (check-info-value i))))
   (raise e)))

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
;; Run SOURCE in a fresh production atom space (no recorder), or with
;; RECORDER.
(define (run source #:recorder [recorder #f])
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space
                  (if recorder
                      (make-mdl-atom-space #:decl-violation-recorder recorder)
                      (make-mdl-atom-space))])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))
;; The bindings the recorder reports for SOURCE, oldest first.
(define (recorded source)
  (define infos '())
  (run source #:recorder (lambda (info) (set! infos (cons info infos))))
  (map (lambda (i) (hash-ref i 'binding)) (reverse infos)))
(define (pname v) (mdl-atom-pname v))

;; --- production: every attached binding kind proceeds with its value ----------------
;; Each case: the source, the expected production result, and the bindings
;; the test-only recorder still reports for it (it is evaluated there).
(define-syntax-rule (proceeds source expected bindings)
  (begin
    (check-equal? (run source) expected source)
    (check-equal? (recorded source) bindings source)))

;; argument (compiled path), the value passed through unchanged
(proceeds "<DEFINE F (X) #DECL ((X) FIX) .X> <F \"s\">" "s" '("X"))
;; argument (interpreted path: a quoted formal)
(check-equal? (pname (run "<DEFINE F ('X) #DECL ((X) FIX) <TYPE .X>> <F <+ 1 2>>")) "FORM")
(check-equal? (recorded "<DEFINE F ('X) #DECL ((X) FIX) <TYPE .X>> <F <+ 1 2>>") '("X"))
;; OPTIONAL: default and supplied
(proceeds "<DEFINE F (\"OPTIONAL\" (X \"d\")) #DECL ((X) FIX) .X> <F>" "d" '("X"))
(proceeds "<DEFINE F (\"OPTIONAL\" X) #DECL ((X) FIX) .X> <F 2.5>" 2.5 '("X"))
;; REST ("TUPLE"/"ARGS")
(proceeds "<DEFINE F (\"TUPLE\" X) #DECL ((X) <LIST [REST FIX]>) <LENGTH .X>> <F A B>" 2 '("X"))
(proceeds "<DEFINE F (\"ARGS\" X) #DECL ((X) <VECTOR [REST FIX]>) <LENGTH .X>> <F A B C>" 3 '("X"))
;; AUX: initialized, then SET
(proceeds "<DEFINE F (\"AUX\" (X \"a\")) #DECL ((X) FIX) .X> <F>" "a" '("X"))
(proceeds "<DEFINE F (\"AUX\" X) #DECL ((X) FIX) <SET X \"t\"> .X> <F>" "t" '("X"))
;; SET of a declared argument
(proceeds "<DEFINE F (X) #DECL ((X) FIX) <SET X \"t\"> .X> <F 1>" "t" '("X"))
;; VALUE: the body's value, RETURN from the function's activation
(proceeds "<DEFINE F () #DECL ((VALUE) FIX) \"v\"> <F>" "v" '("VALUE"))
(proceeds "<DEFINE F A () #DECL ((VALUE) FIX) <RETURN \"r\" .A>> <F>" "r" '("VALUE"))
;; an inner PROG's result returned by a function whose VALUE says FIX
(proceeds "<DEFINE F () #DECL ((VALUE) FIX) <PROG () #DECL ((VALUE) STRING) <RETURN \"x\">>> <F>"
          "x" '("VALUE"))
;; PROG/REPEAT auxiliaries, SET and VALUE
(proceeds "<PROG ((X \"p\")) #DECL ((X) FIX) .X>" "p" '("X"))
(proceeds "<PROG ((X 1)) #DECL ((X) FIX (VALUE) FIX) <SET X 'A> \"q\">" "q" '("X" "VALUE"))
(proceeds "<REPEAT ((X 1)) #DECL ((X) FIX) <SET X \"r\"> <RETURN .X>>" "r" '("X"))
;; NAME (activation formal) declared as a FIX
(check-equal? (run "<DEFINE F (\"NAME\" A) #DECL ((A) FIX) 7> <F>") 7)
(check-equal? (recorded "<DEFINE F (\"NAME\" A) #DECL ((A) FIX) 7> <F>") '("A"))
;; DEFMAC's formals and a FUNCTION applied by MAPF
(proceeds "<DEFMAC M ('X) #DECL ((X) FIX) <FORM QUOTE .X>> <M \"s\">" "s" '("X"))
;; MAPF applies the FUNCTION twice: 1 satisfies FIX, only A is recorded
(proceeds "<LENGTH <MAPF ,LIST <FUNCTION (X) #DECL ((X) FIX) .X> '(1 A)>>" 2 '("X"))

;; --- nested and compound Patterns: none enforced ------------------------------------
(proceeds "<DEFINE F (X) #DECL ((X) <OR FALSE FIX>) .X> <F \"s\">" "s" '("X"))
(proceeds "<DEFINE F (X) #DECL ((X) <PRIMTYPE WORD>) .X> <F \"s\">" "s" '("X"))
(proceeds "<DEFINE F (X) #DECL ((X) <LIST [REST ATOM]>) <LENGTH .X>> <F (A 1)>" 2 '("X"))
(proceeds "<DEFINE F (X) #DECL ((X) <LIST FIX ATOM>) <LENGTH .X>> <F [1 A]>" 2 '("X"))
;; the required length (an NTH count, 77act1.mud:78's [3 ANY])
(proceeds "<DEFINE F (PV) #DECL ((PV) <VECTOR [3 ANY]>) <LENGTH .PV>> <F [1 2]>" 2 '("PV"))
;; a name declared twice (#100 conjunction; BALLOON's M)
(proceeds "<DEFINE F (X) #DECL ((X) FIX (X) ANY) .X> <F \"s\">" "s" '("X"))
;; SPECIAL wrapper; APPLICABLE; a DECL association
(proceeds "<DEFINE F (X) #DECL ((X) <SPECIAL FIX>) .X> <F \"s\">" "s" '("X"))
(proceeds "<DEFINE F (X) #DECL ((X) <OR APPLICABLE FIX>) <LENGTH .X>> <F (1 2)>" 2 '("X"))
(proceeds "<PUT A DECL 'FIX> <DEFINE F (X) #DECL ((X) A) .X> <F \"s\">" "s" '("X"))
;; a NEWTYPE'd structure (OBJECT) declared, a FALSE given: BALLOON's PRSO shape
(check-true (mdl-false? (run "<NEWTYPE OBJECT VECTOR> <DEFINE F (PV \"AUX\" (PRSO <2 .PV>)) #DECL ((PV) VECTOR (PRSO) <OR OBJECT FIX>) .PRSO> <F [1 <>]>")))
(check-equal? (recorded "<NEWTYPE OBJECT VECTOR> <DEFINE F (PV \"AUX\" (PRSO <2 .PV>)) #DECL ((PV) VECTOR (PRSO) <OR OBJECT FIX>) .PRSO> <F [1 <>]>")
              '("PRSO"))
;; a still-undefined name (#193) is not a violation for the recorder either
(proceeds "<DEFINE F (X) #DECL ((X) PRSOBJ) .X> <F 1>" 1 '())

;; --- production performs no conformance check at all ------------------------------
;; A check that would raise while being evaluated raises only in a recorder
;; host; production does not evaluate it.
;; (a) a DECL association added after the definition whose target is unknown
(define late-unknown "<DEFINE F (X) #DECL ((X) FUTURE) .X> <PUT FUTURE DECL 'NOWHERE> <F 1>")
(check-equal? (run late-unknown) 1)
(check-exn #rx"unknown declaration type NOWHERE"
           (lambda () (run late-unknown #:recorder (lambda (i) (error 'test "recorded ~s" i)))))
;; (b) ... or cyclic
(define late-cyclic "<DEFINE F (X) #DECL ((X) FUTURE) .X> <PUT FUTURE DECL 'BACK> <PUT BACK DECL 'FUTURE> <F 2>")
(check-equal? (run late-cyclic) 2)
(check-exn #rx"cyclic DECL association"
           (lambda () (run late-cyclic #:recorder void)))
;; (c) the traversal limit (an OR nested past decl-match-max-depth)
(define deep-or
  (let build ([n (+ decl-match-max-depth 50)] [acc "FIX"])
    (if (zero? n) acc (build (sub1 n) (string-append "<OR " acc ">")))))
(define deep-source (format "<DEFINE F (X) #DECL ((X) ~a) .X> <F 3>" deep-or))
(check-equal? (run deep-source) 3)
(check-exn #rx"traversal limit" (lambda () (run deep-source #:recorder void)))
;; (d) a cyclic LIST value under a [REST ...] Pattern
(define cyclic-value "<DEFINE F (X) #DECL ((X) <LIST [REST FIX]>) 1> <SET L '(1 2)> <PUTREST <REST .L> .L> <F .L>")
(check-equal? (run cyclic-value) 1)
(check-exn #rx"cyclic" (lambda () (run cyclic-value #:recorder void)))

;; --- definition time: the attached #DECL is still validated, unchanged --------------
(check-exn #rx"^mdl-decl: DECL 1:15: unsupported declaration pattern FOO$"
           (lambda () (run "<DEFINE F (X) #DECL ((X) <FOO FIX>) .X>")))
(check-exn #rx"^mdl-decl: DECL 1:15: empty OR pattern$"
           (lambda () (run "<DEFINE F (X) #DECL ((X) <OR>) .X>")))
(check-exn #rx"^mdl-decl: DECL 1:14: duplicate VALUE declaration$"
           (lambda () (run "<DEFINE F () #DECL ((VALUE) FIX (VALUE) ANY) 1>")))
(check-exn #rx"^mdl-decl: DECL 1:15: expected atom-list/pattern pairs$"
           (lambda () (run "<DEFINE F (X) #DECL ((X) FIX (Y)) .X>")))
(check-exn #rx"^mdl-decl: DECL 1:15: declaration name must be an ATOM$"
           (lambda () (run "<DEFINE F (X) #DECL ((X 1) FIX) .X>")))
(check-exn #rx"^mdl-decl: DECL 1:15: NTH repetition requires a positive count$"
           (lambda () (run "<DEFINE F (X) #DECL ((X) <VECTOR [0 FIX]>) .X>")))
(check-exn #rx"^mdl-decl: DECL 1:15: unsupported declaration pattern OPT$"
           (lambda () (run "<DEFINE F (X) #DECL ((X) <VECTOR [OPT FIX]>) .X>")))
(check-exn #rx"^mdl-decl: DECL 1:15: unsupported declaration pattern SPECIAL in this position$"
           (lambda () (run "<DEFINE F (X) #DECL ((X) <OR <SPECIAL FIX> STRING>) .X>")))
(check-exn #rx"^mdl-decl: DECL 1:[0-9]+: cyclic DECL association at A$"
           (lambda () (run "<PUT A DECL 'B> <PUT B DECL 'A> <DEFINE F (X) #DECL ((X) A) .X>")))
;; a PROG's #DECL likewise
(check-exn #rx"unsupported declaration pattern FOO"
           (lambda () (run "<PROG ((X 1)) #DECL ((X) <FOO>) .X>")))
;; an unknown TYPE ATOM is still retained (#98), not an error
(check-true (procedure? (run "<DEFINE F (X) #DECL ((X) PRSOBJ) .X>")))

;; --- strict paths unchanged, with the same messages --------------------------------
;; DECL?
(check-true (mdl-false? (run "<DECL? \"s\" FIX>")))
(check-equal? (let ([p (mdl-false-payload (run "<DECL? \"s\" FIX>"))]) (list (first p) (pname (second p))))
              '("s" "FIX"))
(check-equal? (mdl-false-payload (run "<DECL? [1 2] '<VECTOR [3 FIX]>>")) '())
(check-exn #rx"^mdl-decl: DECL\\?: unknown declaration type PRSOBJ$"
           (lambda () (run "<DECL? 1 'PRSOBJ>")))
;; GDECL against an existing value, and SETG of a GDECLed global
(check-exn #rx"^mdl-gdecl: existing value does not satisfy GDECL for G$"
           (lambda () (run "<SETG G \"s\"> <GDECL (G) FIX>")))
(check-exn #rx"^mdl-setg: value does not satisfy GDECL declaration for G$"
           (lambda () (run "<GDECL (G) FIX> <SETG G \"s\">")))
(check-exn #rx"unknown declaration type PRSOBJ"
           (lambda () (run "<GDECL (G) PRSOBJ> <SETG G 1>")))
;; positional (RSUBR-style) declarations: validated at definition
(check-exn #rx"^mdl-decl: DECL 1:15: unknown declaration type PRSOBJ$"
           (lambda () (run "<DEFINE F (X) #DECL (\"VALUE\" PRSOBJ FIX) .X>")))
(check-exn #rx"^mdl-decl: DECL 1:15: positional declaration must start with VALUE and a Pattern$"
           (lambda () (run "<DEFINE F (X) #DECL (\"WRONG\" FIX) .X>")))
;; CHTYPE to a NEWTYPE with a DECL association
(check-exn #rx"^mdl-chtype: TYPE-MISMATCH: value does not satisfy NEWTYPE declaration$"
           (lambda () (run "<NEWTYPE M3N VECTOR '<<PRIMTYPE VECTOR> FIX>> <CHTYPE '[A] M3N>")))
;; the same strict paths with the recorder on: never recorded
(define (record-nothing info) (error 'test "recorder called: ~s" info))
(check-exn #rx"value does not satisfy GDECL declaration for G"
           (lambda () (run "<GDECL (G) FIX> <SETG G \"s\">" #:recorder record-nothing)))
(check-exn #rx"TYPE-MISMATCH: value does not satisfy NEWTYPE declaration"
           (lambda () (run "<NEWTYPE M3N VECTOR '<<PRIMTYPE VECTOR> FIX>> <CHTYPE '[A] M3N>"
                           #:recorder record-nothing)))

;; --- the old strict error is gone from the runtime ----------------------------------
(check-false (for/or ([src (list "<DEFINE F (X) #DECL ((X) FIX) .X> <F \"s\">"
                                 "<DEFINE F () #DECL ((VALUE) FIX) \"v\"> <F>")])
               (with-handlers ([exn:fail? (lambda (e) (exn-message e))]) (run src) #f)))

(printf "attached_decl_unenforced_test: OK\n")
