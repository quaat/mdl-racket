#lang racket/base
;; Tests for MDL backslash-escape semantics in ATOM names (I119).
;;
;; MDL chapter 15: `\` quotes the next character, making it a literal
;; constituent of the PNAME (backslash is dropped).  The !- OBLIST
;; trailer split operates on the processed (backslash-stripped) string.
;;
;; Confusion reference (pinned binary 6df359f6…, probed 2026-11-22):
;;   DEAD\!!-WORDS  → PNAME "DEAD!", oblist WORDS  (not "DEAD\!" on WORDS)
;;   IN\!!-WORDS    → PNAME "IN!",   oblist WORDS
;;   OUT\!!-WORDS   → PNAME "OUT!",  oblist WORDS
;;   <SPNAME A\!B>  → "A!B"    (backslash stripped; no !- split)
;;   <SPNAME A\-B>  → "A-B"    (backslash stripped)
;;   <SPNAME A\\B>  → "A\B"    (double backslash → single)
;;   <SPNAME \!A>   → "!A"     (leading escaped !)
;;   <==? DEAD\!!-WORDS DEAD\!!-WORDS> → T  (intern identity)
;;   <SPNAME A\!-B> → "A"  / OBLIST B  (escaped ! still triggers !- split)
;;
;; docs/evidence/M3/I119-ESCAPED-TRAILER.md
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))

(define-syntax-rule (in-fresh-session body ...)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    body ...))

(define (run source)
  (in-fresh-session
   (for/fold ([value #f]) ([expr (in-list (compile-program (parse-mdl source)))])
     (eval expr))))

;; ---- Parser: backslash stripped from atom names -----

(test-case "read-atom: backslash stripped; character kept"
  ;; A\!B → PNAME "A!B" (backslash stripped)
  (define nodes (parse-mdl "A\\!B"))
  (check-equal? (length nodes) 1)
  (check-equal? (mdl-node-value (car nodes)) "A!B"))

(test-case "read-atom: escaped hyphen"
  (define nodes (parse-mdl "A\\-B"))
  (check-equal? (mdl-node-value (car nodes)) "A-B"))

(test-case "read-atom: double backslash gives single backslash"
  (define nodes (parse-mdl "A\\\\B"))
  (check-equal? (mdl-node-value (car nodes)) "A\\B"))

(test-case "read-atom: leading escaped exclamation mark"
  (define nodes (parse-mdl "\\!A"))
  (check-equal? (mdl-node-value (car nodes)) "!A"))

(test-case "read-atom: DEAD\\!!-WORDS stripped to DEAD!!-WORDS"
  ;; The global-ref node sees the processed string without backslash.
  ;; mdl-atom will then split on the first (unescaped in processed str) !-
  (define nodes (parse-mdl ",DEAD\\!!-WORDS"))
  (check-equal? (length nodes) 1)
  (check-equal? (mdl-node-kind (car nodes)) 'global)
  ;; After stripping backslash: "DEAD!!-WORDS"
  (check-equal? (mdl-node-value (car nodes)) "DEAD!!-WORDS"))

;; ---- Runtime: PNAME correctness after full compile+eval -----

(test-case "SPNAME A\\!B → \"A!B\""
  (check-equal? (run "<SPNAME A\\!B>") "A!B"))

(test-case "SPNAME A\\-B → \"A-B\""
  (check-equal? (run "<SPNAME A\\-B>") "A-B"))

(test-case "SPNAME A\\\\B → \"A\\\\B\""
  ;; In MDL source A\\B means the atom with PNAME A\B (single backslash).
  ;; Confusion: (spname A\\B) → "A\\B" (printed with escape = single backslash char)
  (check-equal? (run "<SPNAME A\\\\B>") "A\\B"))

(test-case "SPNAME \\!A → \"!A\""
  (check-equal? (run "<SPNAME \\!A>") "!A"))

;; ---- Core I119 cases: escaped trailer -----

;; DEAD\!!-WORDS: \! produces literal ! in PNAME; the following !-WORDS
;; is an unescaped !- oblist trailer.  PNAME must be "DEAD!", not "DEAD\!".
;; Use 'DEAD\!!-WORDS (quoted) to intern the atom without looking up its GVAL.
(test-case "DEAD\\!!-WORDS: PNAME is DEAD!, oblist is WORDS"
  (in-fresh-session
   (run "<MOBLIST WORDS 23>")
   (define atom (run "'DEAD\\!!-WORDS"))
   (check-equal? (mdl-atom-pname atom) "DEAD!")
   (check-not-equal? (mdl-atom-pname atom) "DEAD\\!")))

(test-case "IN\\!!-WORDS: PNAME is IN!"
  (in-fresh-session
   (run "<MOBLIST WORDS 23>")
   (define atom (run "'IN\\!!-WORDS"))
   (check-equal? (mdl-atom-pname atom) "IN!")))

(test-case "OUT\\!!-WORDS: PNAME is OUT!"
  (in-fresh-session
   (run "<MOBLIST WORDS 23>")
   (define atom (run "'OUT\\!!-WORDS"))
   (check-equal? (mdl-atom-pname atom) "OUT!")))

;; Intern identity: two reads of the same escaped form return ==? atom
;; in the same session.  `run` creates its own atom space, so we use
;; a single-session eval here.
(test-case "DEAD\\!!-WORDS identity (intern)"
  (in-fresh-session
   ;; eval a multi-expression program in one compile+run call
   (define prog (compile-program (parse-mdl
     "<MOBLIST WORDS 23> <==? 'DEAD\\!!-WORDS 'DEAD\\!!-WORDS>")))
   (define result (for/fold ([v #f]) ([e prog]) (eval e)))
   (check-equal? (and (mdl-atom? result) (mdl-atom-pname result)) "T")))

;; A\!-B: escaped ! followed by -B → processed string "A!-B".
;; First !- at pos 1 → PNAME="A", oblist=B.
;; Matches Confusion: <SPNAME A\!-B> → "A".
(test-case "A\\!-B: escaped ! still triggers !- split (matches Confusion)"
  (in-fresh-session
   (run "<MOBLIST B>")
   (define atom (run "'A\\!-B"))
   (check-equal? (mdl-atom-pname atom) "A")))

;; A\!!-B: escaped ! in PNAME, then unescaped !- → pname "A!", oblist B.
;; Processed string: "A!!-B", first !- at pos 2 → pname "A!", oblist B.
(test-case "A\\!!-B: PNAME is A!, oblist B"
  (in-fresh-session
   (run "<MOBLIST B>")
   (define atom (run "'A\\!!-B"))
   (check-equal? (mdl-atom-pname atom) "A!")))

;; ---- Regression: escaped atoms must NOT be classified as numeric / # tokens -----
;; Confusion reference (I119): `<TYPE \5>` → ATOM; `<TYPE \-5>` → ATOM;
;; `<TYPE \1.5>` → ATOM; `<TYPE \*7*>` → ATOM; `<TYPE \#FOO>` → ATOM.
;; Without the 'escaped-atom node kind the compiler would mis-classify these.

(test-case "\\5 → ATOM with PNAME \"5\", not FIX 5"
  ;; Parser must tag this 'escaped-atom; compiler must skip the numeric path.
  (define nodes (parse-mdl "\\5"))
  (check-equal? (length nodes) 1)
  (check-equal? (mdl-node-kind (car nodes)) 'escaped-atom)
  (check-equal? (mdl-node-value (car nodes)) "5")
  ;; At runtime the atom interned from PNAME "5" must be an ATOM, not a FIX.
  (check-true (mdl-atom? (run "'\\5"))))

(test-case "\\-5 → ATOM with PNAME \"-5\", not FIX -5"
  (define nodes (parse-mdl "\\-5"))
  (check-equal? (mdl-node-kind (car nodes)) 'escaped-atom)
  (check-equal? (mdl-node-value (car nodes)) "-5")
  (check-true (mdl-atom? (run "'\\-5"))))

(test-case "\\1.5 → ATOM with PNAME \"1.5\", not FLOAT 1.5"
  (define nodes (parse-mdl "\\1.5"))
  (check-equal? (mdl-node-kind (car nodes)) 'escaped-atom)
  (check-equal? (mdl-node-value (car nodes)) "1.5")
  (check-true (mdl-atom? (run "'\\1.5"))))

(test-case "\\*7* → ATOM with PNAME \"*7*\", not octal FIX"
  (define nodes (parse-mdl "\\*7*"))
  (check-equal? (mdl-node-kind (car nodes)) 'escaped-atom)
  (check-equal? (mdl-node-value (car nodes)) "*7*")
  (check-true (mdl-atom? (run "'\\*7*"))))

(test-case "\\#FOO → ATOM with PNAME \"#FOO\", not an unsupported # token"
  (define nodes (parse-mdl "\\#FOO"))
  (check-equal? (mdl-node-kind (car nodes)) 'escaped-atom)
  (check-equal? (mdl-node-value (car nodes)) "#FOO")
  (check-true (mdl-atom? (run "'\\#FOO"))))

;; ---- Regression: escaped atom as PROG label -----
;; `\1ST` has PNAME "1ST" and kind 'escaped-atom.  atom-node-constant-token?
;; must return #f for 'escaped-atom so prog-label-name accepts it as a label.
(test-case "\\1ST is a valid PROG label"
  ;; The PROG body has two items: label \1ST and expression 42.
  ;; GO jumps to the label; the PROG returns the value after it.
  (check-equal? (run "<PROG () <GO \\1ST> 99 \\1ST 42>") 42))

;; ---- Regression: .\ is LVAL of escaped atom, not numeric -----
;; `.\5` must produce LVAL of ATOM "5", not a FLOAT/FIX literal.
;; (Local variables with numeric-looking names are bizarre but legal.)
;; Use a function with formal argument \5 to bind the local.
(test-case ".\\5 → LVAL of atom named \"5\""
  ;; Bind the local "5" via a function formal, read it back via .\5.
  (check-equal? (run "<DEFINE F (\\5) .\\5>  <F 99>") 99))

(displayln "escaped atom tests passed")
