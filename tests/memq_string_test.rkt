#lang racket/base
;; STRING MEMQ: Confusion-backed reference tests for CHARACTER-in-STRING MEMQ.
;; Probe evidence: docs/evidence/M3/memq-string-reference.json
;; MDL manual ch. 13: MEMQ on STRING searches for ==? element (CHARACTER),
;; returns STRING REST'd to that element (view sharing storage), or #FALSE ().
;; Non-CHARACTER needle: Confusion returns #FALSE () silently (never ==? to CHARACTER).
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

;; ---- hit cases (Confusion reference) ----
;; <MEMQ !\a "abc"> → "abc" (hit at start; STRING view over full remaining string)
(check-equal? (run "<STRING <MEMQ !\\a \"abc\">>") "abc")
;; <MEMQ !\b "abc"> → "bc" (hit at middle)
(check-equal? (run "<STRING <MEMQ !\\b \"abc\">>") "bc")
;; <MEMQ !\c "abc"> → "c" (hit at end)
(check-equal? (run "<STRING <MEMQ !\\c \"abc\">>") "c")

;; ---- miss / empty ----
;; <MEMQ !\z "abc"> → #FALSE ()
(check-true (mdl-false? (run "<MEMQ !\\z \"abc\">")))
;; <MEMQ !\a ""> → #FALSE ()
(check-true (mdl-false? (run "<MEMQ !\\a \"\">")))

;; ---- type, length, element (Confusion confirmed) ----
(check-equal? (mdl-atom-pname (run "<TYPE <MEMQ !\\b \"abc\">>")) "STRING")
(check-equal? (run "<LENGTH <MEMQ !\\b \"abc\">>") 2)
;; NTH 1 of result is the same CHARACTER (!\b = ASCII 98)
(check-equal? (run "<ASCII <1 <MEMQ !\\b \"abc\">>>") 98)

;; ---- storage aliasing (Confusion: "zaa") ----
;; MEMQ result shares storage with the original ISTRING.
;; PUT into MEMQ result position 1 mutates the original string.
(check-equal? (run "<SET S <ISTRING 3 !\\a>> <PUT <MEMQ !\\a .S> 1 !\\z> <STRING .S>")
              "zaa")

;; ---- view haystack: Confusion <MEMQ !\b <REST "xbc" 1>> → "bc" ----
(check-equal? (run "<STRING <MEMQ !\\b <REST \"xbc\" 1>>>") "bc")

;; ---- BACK compatibility: UNSPEAKABLE-CODE pattern 77rooms.mud:148-150 ----
;; <SET STR <MEMQ !\/ "11/1/77 Dungeon">> → view at offset 2, length 13
;; <BACK .STR 2> → extended back to start, length 15 → full original string
(check-equal? (run "<LENGTH <MEMQ !\\/ \"11/1/77 Dungeon\">>") 13)
(check-equal? (run "<LENGTH <BACK <MEMQ !\\/ \"11/1/77 Dungeon\"> 2>>") 15)
;; The first character two slots before the '/' is '1' (digit 1)
(check-equal? (run "<ASCII <1 <BACK <MEMQ !\\/ \"11/1/77 Dungeon\"> 2>>>") 49)

;; ---- second MEMQ in UNSPEAKABLE-CODE: 77rooms.mud:153 pattern ----
;; <REST <MEMQ !\/ <REST <MEMQ !\/ .STR>>> 3>
;; Uses nested MEMQ + REST on a STRING view haystack.
;; Confusion confirmed: "11/1/77 Dungeon" → " Dungeon" (space included before Dungeon)
(check-equal?
 (run "<STRING <REST <MEMQ !\\/ <REST <MEMQ !\\/ \"11/1/77 Dungeon\">>> 3>>")
 " Dungeon")

;; ---- non-CHARACTER needle: Confusion silently returns #FALSE ----
;; (deviation from strict ==? semantics: a FIX is not a CHARACTER, can never match)
(check-true (mdl-false? (run "<MEMQ 97 \"abc\">")))   ; FIX needle
(check-true (mdl-false? (run "<MEMQ \"a\" \"abc\">"))) ; STRING needle

(displayln "STRING MEMQ tests passed")

;; ---- review additions ----
;; Case-sensitive CHARACTER identity (==?): the game's YES/NO reader depends on
;; it (77defs.mud:436-438, <MEMQ <1 .INBUF> "NnfF">). Confusion: both #FALSE ().
(check-equal? (run "<TYPE <MEMQ !\\A \"abc\">>") (run "<TYPE <>>"))
(check-equal? (run "<TYPE <MEMQ !\\a \"ABC\">>") (run "<TYPE <>>"))
(check-equal? (run "<STRING <MEMQ !\\N \"NnfF\">>") "NnfF")
(check-equal? (run "<STRING <MEMQ !\\n \"NnfF\">>") "nfF")
;; BACK past the start of the underlying storage stays a strict error.
(check-exn #rx"BACK" (lambda () (run "<BACK <MEMQ !\\b \"abc\"> 2>")))
