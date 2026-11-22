#lang racket/base
;; Tests for UNPARSE (MDL manual ch. 7, section 7.6.6.4; appendix 2).
;;
;; Reference: pinned Confusion mdli SHA256 b5fcb91b…
;; Cases and expected values are confirmed against Confusion probe output;
;; see docs/evidence/M3/S1-UNPARSE.md for the full probe JSON.
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
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

;; ── FIX ─────────────────────────────────────────────────────────────────────
;; Confusion probe: <UNPARSE 0> → "0", <UNPARSE 22> → "22", <UNPARSE -1> → "-1"
;; <UNPARSE 1073741823> → "1073741823", <UNPARSE -1073741824> → "-1073741824"
(check-equal? (run "<UNPARSE 0>") "0")
(check-equal? (run "<UNPARSE 1>") "1")
(check-equal? (run "<UNPARSE 22>") "22")
(check-equal? (run "<UNPARSE -1>") "-1")
(check-equal? (run "<UNPARSE 1073741823>") "1073741823")
(check-equal? (run "<UNPARSE -1073741824>") "-1073741824")

;; Radix argument is accepted but ignored per Confusion (22 at radix 8 → "22",
;; not "26"; 255 at radix 16 → "255", not "FF").
(check-equal? (run "<UNPARSE 22 8>") "22")
(check-equal? (run "<UNPARSE 255 16>") "255")

;; ── Result type and mutability ──────────────────────────────────────────────
;; Confusion: <TYPE <UNPARSE 42>> → STRING
;; <PUT <UNPARSE 42> 1 !\\X> succeeds, confirming result is a fresh mutable STRING.
(check-equal? (mdl-atom-pname (run "<TYPE <UNPARSE 42>>")) "STRING")
;; Mutability: PUT into the first element of the returned string must succeed.
(check-equal? (run "<PUT <UNPARSE 42> 1 !\\X> <UNPARSE 42>") "42")
;; Freshness: each call returns a distinct mutable string (not the same object).
(check-false (eq? (run "<UNPARSE 42>") (run "<UNPARSE 42>")))

;; ── Game use ─────────────────────────────────────────────────────────────────
;; The only UNPARSE call in 77rooms.mud: <UNPARSE <CHTYPE <GETBITS .N <BITS 5 18>> FIX>>
;; where the result is day-of-month (1–31).  CHTYPE of a FIX-range value to FIX
;; is equivalent to the FIX itself; test the FIX path directly.
(check-equal? (run "<UNPARSE <CHTYPE 22 FIX>>") "22")
(check-equal? (run "<STRING \"Day \" <UNPARSE 22> \".\">") "Day 22.")

;; ── ATOM ────────────────────────────────────────────────────────────────────
;; Confusion: <UNPARSE FOO> → "FOO"
(check-equal? (run "<UNPARSE FOO>") "FOO")

;; ── STRING ───────────────────────────────────────────────────────────────────
;; Confusion: <UNPARSE "hello"> → "\"hello\"" (the string itself contains "hello"
;; with surrounding double-quote characters).
(check-equal? (run "<UNPARSE \"hello\">") "\"hello\"")
;; Backslash in string content must be escaped.
(check-equal? (run "<UNPARSE \"a\\\\b\">") "\"a\\\\b\"")

;; ── FALSE ────────────────────────────────────────────────────────────────────
;; Confusion: <UNPARSE <>> → "#FALSE ()"
(check-equal? (run "<UNPARSE <>>") "#FALSE ()")

;; ── CHARACTER ────────────────────────────────────────────────────────────────
;; Confusion: <UNPARSE !\\A> → result_output "\"!\\\\A\"" i.e., the MDL string
;; contains 3 chars: !, \, A.
(check-equal? (run "<UNPARSE !\\A>") "!\\A")

;; ── LIST ─────────────────────────────────────────────────────────────────────
;; Confusion: <UNPARSE (1 2 3)> → "(1 2 3)"
(check-equal? (run "<UNPARSE (1 2 3)>") "(1 2 3)")

;; ── APPLY path ───────────────────────────────────────────────────────────────
;; Confirm UNPARSE is reachable via APPLY (tests the dispatch path).
(check-equal? (run "<APPLY ,UNPARSE 42>") "42")

;; ── Strict error on unsupported types ────────────────────────────────────────
;; FLOAT is not implemented exactly (Confusion format: 7 decimal places, not
;; confirmed for all values). Expect an explicit unsupported error, not Racket's
;; printer output.
(check-exn #rx"UNPARSE|unsupported|type" (lambda () (run "<UNPARSE 1.5>")))
;; VECTOR: not implemented.
(check-exn #rx"UNPARSE|unsupported|type" (lambda () (run "<UNPARSE [1 2]>")))
;; UVECTOR: not implemented.
(check-exn #rx"UNPARSE|unsupported|type" (lambda () (run "<UNPARSE ![1 2!]>")))
;; Bad radix arg.
(check-exn #rx"UNPARSE|radix" (lambda () (run "<UNPARSE 1 1>")))
(check-exn #rx"UNPARSE|radix" (lambda () (run "<UNPARSE 1 37>")))
