#lang racket/base
;; SUBSTRUC tests — Confusion-backed reference probes.
;; Evidence: docs/evidence/M3/S3-SUBSTRUC.md
;; Reference SHA: 6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789
;; mdlzork source: bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3
;;
;; Contract (MDL manual ch. 7, section 7.1.7 + Confusion probes):
;;   <SUBSTRUC from rest amount to>
;;   rest defaults to 0; amount defaults to remaining; to is optional.
;;   Result is a fresh independent structure of the PRIMTYPE of from.
;;   With to: copies into to starting at position 0, returns to.

(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([result #f])
              ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

;; ---- STRING basics (Confusion confirmed) ----
;; Full copy
(check-equal? (run "<SUBSTRUC \"hello\" 0 5>") "hello")
;; Slice rest=1 amount=3
(check-equal? (run "<SUBSTRUC \"hello\" 1 3>") "ell")
;; rest=0 amount defaults to all
(check-equal? (run "<SUBSTRUC \"hello\" 0>") "hello")
;; Only from — all defaults
(check-equal? (run "<SUBSTRUC \"hello\">") "hello")
;; rest=2 amount defaults to remaining
(check-equal? (run "<SUBSTRUC \"hello\" 2>") "llo")
;; amount=0 returns empty string
(check-equal? (run "<SUBSTRUC \"hello\" 0 0>") "")
;; rest == length yields empty string
(check-equal? (run "<SUBSTRUC \"hello\" 5>") "")
(check-equal? (run "<SUBSTRUC \"hello\" 5 0>") "")
;; Type is STRING
(check-equal? (mdl-atom-pname (run "<TYPE <SUBSTRUC \"hello\" 0 3>>")) "STRING")
;; Simple game pattern: 77rooms.mud:279
(check-equal? (run "<SUBSTRUC \"abc\" 0 3>") "abc")

;; ---- STRING independence (Confusion confirmed: "aaa" after mutating source) ----
;; Mutation of source does not affect result
(check-equal?
 (run "<SET A <ISTRING 3 !\\a>> <SET B <SUBSTRUC .A 0 3>> <PUT .A 1 !\\z> <STRING .B>")
 "aaa")
;; Mutation of result does not affect source
(check-equal?
 (run "<SET A <ISTRING 3 !\\a>> <SET B <SUBSTRUC .A 0 3>> <PUT .B 1 !\\z> <STRING .A>")
 "aaa")

;; ---- STRING view source (Confusion confirmed: "llo") ----
(check-equal? (run "<SUBSTRUC <REST \"hello\" 2> 0 3>") "llo")
;; Independence from view source (Confusion: "aaa" after mutation)
(check-equal?
 (run "<SET A <ISTRING 5 !\\a>> <SET B <SUBSTRUC <REST .A 1> 0 3>> <PUT .A 2 !\\z> <STRING .B>")
 "aaa")

;; ---- STRING with to (Confusion confirmed) ----
;; Returns to after modification
(check-equal?
 (run "<SET T <ISTRING 3 !\\z>> <SUBSTRUC \"abc\" 0 3 .T> <STRING .T>")
 "abc")
;; TYPE of return value with to is STRING
(check-equal?
 (mdl-atom-pname (run "<SET T <ISTRING 3 !\\z>> <TYPE <SUBSTRUC \"abc\" 0 3 .T>>"))
 "STRING")
;; Partial fill: only amount chars written, rest of to unchanged
(check-equal?
 (run "<SET T <ISTRING 5 !\\z>> <SUBSTRUC \"ab\" 0 2 .T> <STRING .T>")
 "abzzz")
;; to is a REST view — Confusion: "zhelz"
(check-equal?
 (run "<SET T <ISTRING 5 !\\z>> <SUBSTRUC \"hello\" 0 3 <REST .T 1>> <STRING .T>")
 "zhelz")
;; 77rooms.mud:139 pattern: copy CMA into TSTR
(check-equal?
 (run "<SET CMA \"hello \"> <SET TSTR <ISTRING 10 !\\ >> <SUBSTRUC .CMA 0 5 .TSTR> <STRING .TSTR>")
 "hello     ")
;; 77rooms.mud:142 pattern: copy two strings into adjacent views
(check-equal?
 (run "<SET T <ISTRING 6 !\\ >> <SUBSTRUC \"abc\" 0 3 .T> <SUBSTRUC \"xyz\" 0 3 <REST .T 3>> <STRING .T>")
 "abcxyz")
;; REST-view to (77rooms.mud:142)
(check-equal?
 (run "<SET T <ISTRING 6 !\\ >> <SUBSTRUC \"xyz\" 0 3 <REST .T 3>> <STRING .T>")
 "   xyz")

;; ---- NEWTYPE source (Confusion-confirmed: result PRIMTYPE, not NEWTYPE) ----
;; NEWTYPE FOO STRING source: result is a plain STRING.
(check-equal? (run "<NEWTYPE FOO STRING> <SET S <CHTYPE \"abc\" FOO>> <SUBSTRUC .S 0 3>") "abc")
(check-equal?
 (mdl-atom-pname (run "<NEWTYPE FOO STRING> <SET S <CHTYPE \"abc\" FOO>> <TYPE <SUBSTRUC .S 0 3>>"))
 "STRING")
;; NEWTYPE BAR VECTOR source: result TYPE is VECTOR.
(check-equal?
 (mdl-atom-pname (run "<NEWTYPE BAR VECTOR> <SET V <CHTYPE [1 2 3] BAR>> <TYPE <SUBSTRUC .V 0 2>>"))
 "VECTOR")
;; FORM has PRIMTYPE LIST: SUBSTRUC returns a LIST.
(check-equal?
 (mdl-atom-pname (run "<TYPE <SUBSTRUC '<+ 1 2> 0 2>>"))
 "LIST")
;; Result type for view source is STRING
(check-equal?
 (mdl-atom-pname (run "<TYPE <SUBSTRUC <REST \"hello\" 1> 0 3>>"))
 "STRING")

;; ---- UVECTOR basics (Confusion confirmed) ----
(check-equal?
 (mdl-atom-pname (run "<TYPE <SUBSTRUC ![1 2 3] 0 2>>"))
 "UVECTOR")
(check-equal? (run "<LENGTH <SUBSTRUC ![1 2 3] 0 2>>") 2)
(check-equal? (run "<1 <SUBSTRUC ![1 2 3] 0 2>>") 1)
(check-equal? (run "<2 <SUBSTRUC ![1 2 3] 0 2>>") 2)
;; UVECTOR with to (Confusion: returns to = ![1 2 3!])
(check-equal?
 (run "<SET T <IUVECTOR 3 0>> <SUBSTRUC ![1 2 3] 0 3 .T> <1 .T>")
 1)
(check-equal?
 (run "<SET T <IUVECTOR 3 0>> <SUBSTRUC ![1 2 3] 0 3 .T> <LENGTH .T>")
 3)

;; ---- VECTOR basics (Confusion confirmed) ----
(check-equal?
 (mdl-atom-pname (run "<TYPE <SUBSTRUC [1 2 3] 0 2>>"))
 "VECTOR")
(check-equal? (run "<LENGTH <SUBSTRUC [1 2 3] 0 2>>") 2)
(check-equal? (run "<1 <SUBSTRUC [1 2 3] 0 2>>") 1)

;; ---- LIST basics (Confusion confirmed) ----
(check-equal?
 (mdl-atom-pname (run "<TYPE <SUBSTRUC '(1 2 3) 0 2>>"))
 "LIST")
(check-equal? (run "<LENGTH <SUBSTRUC '(1 2 3) 0 2>>") 2)
(check-equal? (run "<1 <SUBSTRUC '(1 2 3) 0 2>>") 1)

;; ---- APPLY path ----
;; APPLY dispatches through mdl-apply; test that SUBSTRUC is accessible
(check-equal? (run "<APPLY ,SUBSTRUC \"abc\" 0 2>") "ab")

;; ---- Error cases (Confusion confirmed error messages) ----
;; Item 4: non-FIX rest → "Second argument to SUBSTRUC must be a FIX"
(check-exn #rx"Second argument to SUBSTRUC must be a FIX"
           (lambda () (run "<SUBSTRUC \"abc\" \"x\" 2>")))
;; Item 4: FALSE rest (<>) is not FIX → same error
(check-exn #rx"Second argument to SUBSTRUC must be a FIX"
           (lambda () (run "<SUBSTRUC \"abc\" <> 2>")))
;; Item 4: non-FIX amount → "Third argument to SUBSTRUC must be a FIX"
(check-exn #rx"Third argument to SUBSTRUC must be a FIX"
           (lambda () (run "<SUBSTRUC \"abc\" 0 \"y\">")))
;; negative rest
(check-exn #rx"SUBSTRUC rest cannot be negative"
           (lambda () (run "<SUBSTRUC \"abc\" -1 2>")))
;; negative amount
(check-exn #rx"SUBSTRUC amount cannot be negative"
           (lambda () (run "<SUBSTRUC \"abc\" 0 -1>")))
;; rest > length
(check-exn #rx"SUBSTRUC rest too large"
           (lambda () (run "<SUBSTRUC \"abc\" 4>")))
;; amount > available
(check-exn #rx"SUBSTRUC amount too big for source"
           (lambda () (run "<SUBSTRUC \"abc\" 0 4>")))
;; Non-structured argument
(check-exn #rx"SUBSTRUC requires a structured"
           (lambda () (run "<SUBSTRUC 42>")))
;; Item 4: wrong PRIMTYPE `to` → "Last arg to SUBSTRUC must be same type as primtype of first arg"
(check-exn #rx"Last arg to SUBSTRUC must be same type as primtype of first arg"
           (lambda () (run "<SUBSTRUC \"abc\" 0 2 ![1 2]>")))
(check-exn #rx"Last arg to SUBSTRUC must be same type as primtype of first arg"
           (lambda () (run "<SUBSTRUC ![1 2] 0 2 <ISTRING 2>>")))
;; Nit 2: CHTyped (NEWTYPE) `to` rejected — Confusion requires the primitive TYPE itself.
;; NEWTYPE FOO STRING `to` for STRING source → ARG-WRONG-TYPE (TYPE is FOO not STRING)
(check-exn #rx"Last arg to SUBSTRUC must be same type as primtype of first arg"
           (lambda () (run "<NEWTYPE FOO STRING> <SUBSTRUC \"abc\" 0 2 <CHTYPE <ISTRING 2> FOO>>")))
;; NEWTYPE BAR VECTOR `to` for VECTOR source → ARG-WRONG-TYPE (TYPE is BAR not VECTOR)
(check-exn #rx"Last arg to SUBSTRUC must be same type as primtype of first arg"
           (lambda () (run "<NEWTYPE BAR VECTOR> <SUBSTRUC [1 2 3] 0 2 <CHTYPE <IVECTOR 2> BAR>>")))
;; Item 2 regression: destination too short → error; to is UNCHANGED (no partial write)
(check-exn #rx"SUBSTRUC destination too short"
           (lambda () (run "<SUBSTRUC \"abcde\" 0 4 <ISTRING 2>>")))
(check-exn #rx"SUBSTRUC destination too short"
           (lambda () (run "<SUBSTRUC ![1 2 3] 0 3 <IUVECTOR 2 0>>")))
(check-exn #rx"SUBSTRUC destination too short"
           (lambda () (run "<SUBSTRUC [1 2 3] 0 3 <IVECTOR 2>>")))
;; Item 1 regression: UVECTOR to with mismatched element type must raise.
;; (a40e5e4 silently corrupted the target UVECTOR; now TYPES-DIFFER fires.)
(check-exn #rx"SUBSTRUC UVECTOR to and from must be same type"
           (lambda () (run "<SUBSTRUC <IUVECTOR 2 !\\a> 0 2 <IUVECTOR 2 0>>")))
;; Item 3 regression: overlapping from/to uses atomic (memmove) semantics.
;; (a40e5e4 gave "aaaaaf"; atomic copy snapshot gives "aabcdf" — Confusion-confirmed.)
(check-equal?
 (run (string-append
       "<SET S <ISTRING 6 !\\ >>"
       "<SUBSTRUC \"abcdef\" 0 6 .S>"
       "<SUBSTRUC .S 0 4 <REST .S 1>>"
       "<STRING .S>"))
 "aabcdf")
;; VECTOR overlap (a40e5e4 gave [1 1 1 1 5 6]; atomic gives [1 1 2 3 4 6])
(check-equal?
 (run (string-append
       "<SET V [1 2 3 4 5 6]>"
       "<SUBSTRUC .V 0 4 <REST .V 1>>"
       "<1 .V>"))
 1)
(check-equal?
 (run (string-append
       "<SET V [1 2 3 4 5 6]>"
       "<SUBSTRUC .V 0 4 <REST .V 1>>"
       "<3 .V>"))
 2)

;; ---- LIST to (Nit 1: strict error — not implemented) ----
;; Confusion supports LIST `to` but: (a) overlap writes non-atomically giving a
;; different result from STRING/VECTOR; (b) too-short is detected AFTER partial
;; writes.  Since the game never passes a LIST `to`, we refuse with strict error.
(check-exn #rx"SUBSTRUC: to argument for LIST is not implemented"
           (lambda () (run "<SUBSTRUC '(1 2 3) 0 2 '(0 0 0)>")))

;; ---- Interpreted / DEFINE path ----
;; Ensure SUBSTRUC is callable from an interpreted MDL function
(check-equal?
 (run "<DEFINE F (S) <SUBSTRUC .S 0 3>> <F \"hello\">")
 "hel")

(displayln "SUBSTRUC tests passed")

