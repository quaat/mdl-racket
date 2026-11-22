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
;; 36-bit MDL FIX extremes: max = 2^35-1 = 34359738367, min = -2^35 = -34359738368.
(check-equal? (run "<UNPARSE 0>") "0")
(check-equal? (run "<UNPARSE 1>") "1")
(check-equal? (run "<UNPARSE 22>") "22")
(check-equal? (run "<UNPARSE -1>") "-1")
(check-equal? (run "<UNPARSE 34359738367>") "34359738367")
(check-equal? (run "<UNPARSE -34359738368>") "-34359738368")

;; Explicit radix=10 is the same as the default (decimal).
(check-equal? (run "<UNPARSE 22 10>") "22")
;; Non-decimal radix: strict unsupported error per AGENTS.md.
;; The MDL manual (§7.6.6.4) says radix is used for FIX conversion; Confusion
;; DEVIATES from this by ignoring the radix arg entirely (reference bug, not
;; a semantic contract — see docs/evidence/M3/S1-UNPARSE.md). The game never
;; passes a non-10 radix, so we raise a strict error rather than implement
;; unverified non-decimal output.
(check-exn #rx"UNPARSE: non-decimal radix" (lambda () (run "<UNPARSE 22 8>")))
(check-exn #rx"UNPARSE: non-decimal radix" (lambda () (run "<UNPARSE 255 16>")))
(check-exn #rx"UNPARSE: non-decimal radix" (lambda () (run "<UNPARSE 22 2>")))

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
;; Plain ATOM (no special chars): Confusion → "FOO".
(check-equal? (run "<UNPARSE FOO>") "FOO")
;; Hyphenated atoms are common in MDL and need no escaping.
(check-equal? (run "<UNPARSE FIND-OBJ>") "FIND-OBJ")
;; Exotic PNAME with space: strict error (space not in [A-Za-z0-9-] whitelist).
;; Use <ATOM "..."> to construct atoms with unusual pnames.
(check-exn #rx"UNPARSE ATOM: PNAME" (lambda () (run "<UNPARSE <ATOM \"FOO BAR\">>")))
;; Exotic PNAME with quote char: strict error.
(check-exn #rx"UNPARSE ATOM: PNAME" (lambda () (run "<UNPARSE <ATOM \"A\\\"B\">>")))
;; Exotic PNAME with open-paren: strict error.
(check-exn #rx"UNPARSE ATOM: PNAME" (lambda () (run "<UNPARSE <ATOM \"A(B\">>")))
;; Whitelist is ASCII-only: Racket char-alphabetic?/char-numeric? accept
;; Unicode letters/digits, which MDL does not print bare. Strict error.
(check-exn #rx"UNPARSE ATOM: PNAME" (lambda () (run "<UNPARSE <ATOM \"É\">>")))
(check-exn #rx"UNPARSE ATOM: PNAME" (lambda () (run "<UNPARSE <ATOM \"A٣\">>")))
;; Exotic PNAME with backslash: strict error.
(check-exn #rx"UNPARSE ATOM: PNAME" (lambda () (run "<UNPARSE <ATOM \"A\\\\B\">>" )))
;; B2: pname parseable as a number must fail even though digits are in the whitelist.
(check-exn #rx"UNPARSE ATOM: PNAME" (lambda () (run "<UNPARSE <ATOM \"42\">>")))
;; B2: pname with dot (not in whitelist).
(check-exn #rx"UNPARSE ATOM: PNAME" (lambda () (run "<UNPARSE <ATOM \"A.B\">>")))
;; B1: atom removed from OBLIST requires trailer notation — strict error.
(check-exn #rx"UNPARSE ATOM: trailer notation not implemented"
           (lambda () (run "<SET X <REMOVE FOO>> <UNPARSE .X>")))

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
;; B3: control character codes 0-31 and 127 require Confusion's !\^A notation — strict error.
(check-exn #rx"UNPARSE CHARACTER: control character"
           (lambda () (run "<UNPARSE <ASCII 0>>")))    ; NUL (code 0)
(check-exn #rx"UNPARSE CHARACTER: control character"
           (lambda () (run "<UNPARSE <ASCII 127>>")))

;; ── LIST ─────────────────────────────────────────────────────────────────────
;; Confusion: <UNPARSE (1 2 3)> → "(1 2 3)"
(check-equal? (run "<UNPARSE (1 2 3)>") "(1 2 3)")

;; ── APPLY path ───────────────────────────────────────────────────────────────
;; Confirm UNPARSE is reachable via APPLY (tests the dispatch path).
(check-equal? (run "<APPLY ,UNPARSE 42>") "42")

;; ── STRING with control chars ────────────────────────────────────────────────
;; B4: strings with control characters (codes 0-31, 127) require Confusion's
;; "^A…" embedded-control notation, which is not implemented; strict error.
;; Use <STRING <ASCII n>> to build a string with a control character via MDL.
(check-exn #rx"UNPARSE STRING: control character"
           (lambda () (run "<UNPARSE <STRING <ASCII 7>>>")))   ; bell (code 7)
(check-exn #rx"UNPARSE STRING: control character"
           (lambda () (run "<UNPARSE <STRING <ASCII 127>>>")))

;; ── Strict error on unsupported types ────────────────────────────────────────
;; FLOAT is not implemented exactly (Confusion format: 7 decimal places, not
;; confirmed for all values). Expect an explicit unsupported error, not Racket's
;; printer output.
(check-exn #rx"UNPARSE: unsupported MDL type" (lambda () (run "<UNPARSE 1.5>")))
;; VECTOR: not implemented.
(check-exn #rx"UNPARSE: unsupported MDL type" (lambda () (run "<UNPARSE [1 2]>")))
;; UVECTOR: not implemented.
(check-exn #rx"UNPARSE: unsupported MDL type" (lambda () (run "<UNPARSE ![1 2!]>")))
;; Out-of-range radix: error (range check is distinct from "not implemented").
(check-exn #rx"UNPARSE radix must be a FIX" (lambda () (run "<UNPARSE 1 1>")))
(check-exn #rx"UNPARSE radix must be a FIX" (lambda () (run "<UNPARSE 1 37>")))
;; Radix 10 explicit: works (decimal).
(check-equal? (run "<UNPARSE -5 10>") "-5")
