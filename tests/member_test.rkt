#lang racket/base
;; MEMBER (MDL manual §8.2.2), S9. Every expected value below is a pinned
;; Confusion observation from docs/evidence/M3/MEMBER-REFERENCE.md
;; (member-probe.json; case names in comments) unless marked "manual" or
;; "runtime refusal". Specification: docs/SEMANTICS.md "M3 primitive: MEMBER".
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

;; Cycle cases must never hang the suite.
(define (bounded-run source)
  (define custodian (make-custodian))
  (define output (make-channel))
  (parameterize ([current-custodian custodian])
    (thread (lambda ()
              (channel-put output
                           (with-handlers ([exn:fail? values])
                             (run source))))))
  (define result (sync/timeout 5 output))
  (custodian-shutdown-all custodian)
  (cond [(not result) (error 'bounded-run "MEMBER did not terminate")]
        [(exn:fail? result) (raise result)]
        [else result]))

;; A printer-independent view of an MDL value (UNPARSE has no VECTOR/FLOAT).
;; LIST -> (L ...), VECTOR -> (V ...), UVECTOR -> (U ...), STRING -> "..",
;; FALSE -> (FALSE ...), ATOM -> symbol; other values are returned as is.
(define (view v)
  (cond
    [(mdl-false? v) (cons 'FALSE (map view (mdl-false-payload v)))]
    [(or (null? v) (mpair? v)) (cons 'L (map view (mdl-list->list v)))]
    [(mdl-array? v)
     (cons (if (eq? (mdl-array-kind v) 'VECTOR) 'V 'U)
           (for/list ([i (in-range (mdl-array-length v))])
             (view (mdl-nth v (add1 i)))))]
    [(mdl-atom? v) (string->symbol (mdl-atom-pname v))]
    [(with-handlers ([exn:fail? (lambda (e) #f)])
       (mdl-string-snapshot 'view v "not a STRING"))
     => values]
    [else v]))
(define (v src) (view (run src)))
(define (type-of src [prefix ""])
  (mdl-atom-pname (run (string-append prefix "<TYPE " src ">"))))
(define (t? value) (and (mdl-atom? value) (string=? (mdl-atom-pname value) "T")))
(define (miss? src) (mdl-false? (run src)))
(define (miss-payload-empty? src)
  (define r (run src))
  (and (mdl-false? r) (null? (mdl-false-payload r))))

(test-case "structural search on LIST (=?)"
  (check-equal? (v "<MEMBER 2 '(1 2 3)>") '(L 2 3))                     ; list-hit
  (check-true (miss-payload-empty? "<MEMBER 4 '(1 2 3)>"))              ; list-miss
  (check-equal? (v "<MEMBER 2 '(1 2 3 2 5)>") '(L 2 3 2 5))             ; list-first-of-duplicates
  (check-equal? (run "<LENGTH <MEMBER 2 '(1 2 3 2 5)>>") 4)
  (check-true (miss-payload-empty? "<MEMBER 1 ()>"))                    ; list-empty
  (check-equal? (v "<MEMBER '(1 2) '(0 (1 2) 3)>") '(L (L 1 2) 3))      ; list-nested-equal
  (check-true (miss? "<MEMBER '[1 2] '(0 (1 2) 3)>"))                   ; list-nested-kind-differs
  (check-equal? (v "<MEMBER '(1 [2 \"x\"]) '(0 (1 [2 \"x\"]) 3)>")       ; list-deep-nested
                '(L (L 1 (V 2 "x")) 3))
  ;; fix-vs-float
  (check-true (miss? "<MEMBER 2 '(1 2.0 3)>"))
  (check-equal? (v "<MEMBER 2.0 '(1 2 2.0)>") '(L 2.0))
  (check-equal? (v "<MEMBER 2.0 '(1 2.0)>") '(L 2.0))
  ;; atom-element
  (check-equal? (v "<MEMBER FOO '(BAR FOO BAZ)>") '(L FOO BAZ))
  (check-true (miss? "<MEMBER FOO '(BAR BAZ)>"))
  ;; character-element
  (check-equal? (run "<LENGTH <MEMBER !\\b '(!\\a !\\b)>>") 1)
  (check-equal? (run "<ASCII <1 <MEMBER !\\b '(!\\a !\\b)>>>") 98)
  (check-true (miss? "<MEMBER !\\B '(!\\a !\\b)>"))
  ;; false-element
  (check-equal? (v "<MEMBER <> '(1 #FALSE () 2)>") '(L (FALSE) 2))
  (check-equal? (v "<MEMBER #FALSE (1) '(#FALSE () #FALSE (1) 2)>") '(L (FALSE 1) 2))
  ;; string-element-list, string-element-distinct-object
  (check-equal? (v "<MEMBER \"abc\" '(\"x\" \"abc\" \"y\")>") '(L "abc" "y"))
  (check-equal? (v "<MEMBER <STRING \"ab\" \"c\"> '(\"x\" \"abc\")>") '(L "abc")))

(test-case "MEMBER is not MEMQ"
  ;; memq-contrast-distinct-string: MEMQ misses where MEMBER hits.
  (check-true (miss? "<MEMQ <STRING \"ab\" \"c\"> '(\"x\" \"abc\")>"))
  (check-equal? (v "<MEMBER <STRING \"ab\" \"c\"> '(\"x\" \"abc\")>") '(L "abc"))
  (check-equal? (v "<MEMBER '(1) '((0) (1) 2)>") '(L (L 1) 2))
  ;; The result is a structure, never a host Boolean or T.
  (check-true (mpair? (run "<MEMBER 1 '(1)>"))))

(test-case "STRING needle against LIST/VECTOR is element search, not substring"
  ;; string-needle-vector-no-substring
  (check-true (miss? "<MEMBER \"a\" [\"abc\" \"xa\"]>"))
  (check-equal? (v "<MEMBER \"abc\" [\"xabcx\" \"abc\"]>") '(V "abc"))
  ;; string-needle-char-list
  (check-true (miss? "<MEMBER \"a\" '(!\\a)>")))

(test-case "VECTOR and UVECTOR"
  ;; vector-hit
  (check-equal? (v "<MEMBER \"B\" [\"A\" \"B\" \"C\"]>") '(V "B" "C"))
  (check-equal? (type-of "<MEMBER \"B\" [\"A\" \"B\" \"C\"]>") "VECTOR")
  ;; uvector-hit
  (check-equal? (v "<MEMBER 2 ![1 2 3!]>") '(U 2 3))
  (check-equal? (type-of "<MEMBER 2 ![1 2 3!]>") "UVECTOR")
  (check-true (miss? "<MEMBER 4 ![1 2 3!]>")))

(define winners "<SETG WINNERS '[\"BKD\" \"TAA\" \"MARC\" \"PDL\" \"MDL\"]> ")
(test-case "WINNERS (77rooms.mud:254) and LEXV (77rooms.mud:1555) shapes"
  ;; winners-vector
  (check-equal? (v (string-append winners "<MEMBER \"MARC\" ,WINNERS>"))
                '(V "MARC" "PDL" "MDL"))
  (check-true (miss? (string-append winners "<MEMBER \"MTRZORK\" ,WINNERS>")))
  (check-true (miss? (string-append winners "<MEMBER \"MAR\" ,WINNERS>")))
  (check-true (miss? (string-append winners "<MEMBER \"marc\" ,WINNERS>")))
  (check-equal? (v (string-append winners "<MEMBER <STRING \"MD\" \"L\"> ,WINNERS>"))
                '(V "MDL"))
  ;; lexv-empty-string-search
  (define lexv "<SETG LEXV <IVECTOR 10 '<REST <ISTRING 5> 5>>> ")
  (check-equal? (run (string-append lexv "<LENGTH <MEMBER \"\" ,LEXV>>")) 10)
  (check-true (t? (run (string-append lexv "<==? <MEMBER \"\" ,LEXV> ,LEXV>"))))
  (define filled
    (string-append lexv "<PUT ,LEXV 1 \"ROBOT\"> <PUT ,LEXV 2 \"GO\"> "))
  (check-equal? (run (string-append filled "<LENGTH <MEMBER \"\" ,LEXV>>")) 8)
  (check-true (t? (run (string-append filled "<==? <MEMBER \"\" ,LEXV> <REST ,LEXV 2>>"))))
  (check-equal? (run (string-append filled "<LENGTH <REST <MEMBER \"\" ,LEXV>>>")) 7)
  (check-true (miss? "<MEMBER \"\" [\"A\" \"B\"]>")))

(test-case "result shares the haystack (aliasing, ==? to REST)"
  ;; list-alias
  (define l "<SET L (1 2 3)> ")
  (check-equal? (v (string-append l "<PUT <MEMBER 2 .L> 1 99>")) '(L 99 3))
  (check-equal? (v (string-append l "<PUT <MEMBER 2 .L> 1 99> .L")) '(L 1 99 3))
  (check-true (t? (run (string-append l "<PUT <MEMBER 2 .L> 1 99> <==? <MEMBER 99 .L> <REST .L 1>>"))))
  (check-true (t? (run (string-append l "<==? <MEMBER 1 .L> .L>"))))
  ;; vector-alias
  (define vec "<SET L [1 2 3]> ")
  (check-equal? (v (string-append vec "<PUT <MEMBER 2 .L> 1 99>")) '(V 99 3))
  (check-equal? (v (string-append vec "<PUT <MEMBER 2 .L> 1 99> .L")) '(V 1 99 3))
  (check-true (t? (run (string-append vec "<PUT <MEMBER 2 .L> 1 99> <==? <MEMBER 99 .L> <REST .L 1>>"))))
  (check-true (t? (run (string-append vec "<==? <MEMBER 1 .L> .L>"))))
  ;; uvector-alias
  (define uv "<SET L ![1 2 3!]> ")
  (check-equal? (v (string-append uv "<PUT <MEMBER 2 .L> 1 99>")) '(U 99 3))
  (check-equal? (v (string-append uv "<PUT <MEMBER 2 .L> 1 99> .L")) '(U 1 99 3))
  (check-true (t? (run (string-append uv "<PUT <MEMBER 2 .L> 1 99> <==? <MEMBER 99 .L> <REST .L 1>>")))))

(test-case "REST'd haystack offsets"
  ;; rest-view-haystack
  (check-equal? (v "<MEMBER 1 <REST '(1 2 1 3) 1>>") '(L 1 3))
  (check-equal? (v "<MEMBER 1 <REST [1 2 1 3] 1>>") '(V 1 3))
  (check-true (miss? "<MEMBER 1 <REST [1 2 3] 1>>"))
  (check-true (t? (run "<SET X [1 2 1 3]> <==? <MEMBER 1 <REST .X 1>> <REST .X 2>>"))))

(test-case "typed haystacks return the PRIMTYPE type"
  ;; typed-structure. The probe built the FORM with <CHTYPE (1 2 3) FORM>;
  ;; this runtime refuses CHTYPE to FORM, so the same FORM comes from the
  ;; FORM SUBR.
  (check-equal? (type-of "<FORM 1 2 3>") "FORM")
  (check-equal? (v "<MEMBER 2 <FORM 1 2 3>>") '(L 2 3))
  (check-equal? (type-of "<MEMBER 2 <FORM 1 2 3>>") "LIST")
  (define myv "<NEWTYPE MYV VECTOR> ")
  (check-equal? (v (string-append myv "<MEMBER 2 <CHTYPE [1 2 3] MYV>>")) '(V 2 3))
  (check-equal? (type-of "<MEMBER 2 <CHTYPE [1 2 3] MYV>>" myv) "VECTOR")
  ;; manual (REST result is PRIMTYPE): offset-0 hit on a typed VECTOR.
  (check-equal? (type-of "<MEMBER 1 <CHTYPE [1 2 3] MYV>>" myv) "VECTOR")
  ;; false-haystack
  (check-true (miss-payload-empty? "<MEMBER 1 <>>"))
  (check-equal? (v "<MEMBER 1 #FALSE (1 2)>") '(L 1 2))
  (check-equal? (type-of "<MEMBER 1 #FALSE (1 2)>") "LIST"))

(test-case "substring search: STRING needle in STRING haystack"
  (check-equal? (v "<MEMBER \"PART\" \"SUM OF PARTS\">") "PARTS")          ; str-manual-example
  (check-true (miss-payload-empty? "<MEMBER \"XYZ\" \"SUM OF PARTS\">"))  ; str-miss
  (check-equal? (v "<MEMBER \"SUM\" \"SUM OF PARTS\">") "SUM OF PARTS")   ; str-match-at-start
  (check-equal? (v "<MEMBER \"S\" \"SUM OF PARTS\">") "SUM OF PARTS")
  (check-equal? (v "<MEMBER \"TS\" \"SUM OF PARTS\">") "TS")              ; str-match-at-end
  (check-equal? (v "<MEMBER \"PARTS\" \"SUM OF PARTS\">") "PARTS")
  (check-equal? (v "<MEMBER \"abc\" \"abc\">") "abc")                     ; str-equal
  (check-true (miss? "<MEMBER \"abcd\" \"abc\">"))                        ; str-needle-longer
  (check-true (miss? "<MEMBER \"xabc\" \"abc\">"))
  (check-true (miss? "<MEMBER \"part\" \"SUM OF PARTS\">"))               ; str-case-sensitive
  (check-equal? (v "<MEMBER \"AB\" \"xABAB\">") "ABAB")                   ; str-first-of-multiple
  (check-equal? (run "<LENGTH <MEMBER \"AB\" \"xABAB\">>") 4)
  (check-equal? (v "<MEMBER \"aab\" \"aaab\">") "aab")                    ; str-backtrack
  ;; str-rest-haystack
  (check-equal? (v "<MEMBER \"b\" <REST \"abcb\" 2>>") "b")
  (check-equal? (v "<MEMBER \"ab\" <REST \"abab\" 1>>") "ab")
  (check-true (miss? "<MEMBER \"a\" <REST \"abc\" 1>>"))
  (check-equal? (v "<MEMBER <REST \"xLEDG\" 1> \"CLEDG\">") "LEDG")      ; str-rest-needle
  (check-equal? (type-of "<MEMBER \"b\" \"abc\">") "STRING")             ; str-result-type
  ;; str-empty-haystack
  (check-true (miss? "<MEMBER \"a\" \"\">"))
  (check-true (miss? "<MEMBER \"a\" <REST \"abc\" 3>>"))
  ;; str-nul-needle (a one-character NUL needle is an ordinary needle)
  (check-true (miss? "<MEMBER <STRING <ASCII 0>> \"abc\">"))
  (check-equal? (v "<MEMBER <STRING <ASCII 0>> <STRING \"ab\" <ASCII 0>>>")
                (string (integer->char 0))))

(test-case "substring result shares the haystack"
  ;; str-alias
  (define s "<SET S <STRING \"RIVR3\">> <SET M <MEMBER \"VR\" .S>> ")
  (check-equal? (v (string-append s ".M")) "VR3")
  (check-equal? (run (string-append s "<LENGTH .M>")) 3)
  (check-equal? (v (string-append s "<PUT .M 1 !\\Z>")) "ZR3")
  (check-equal? (v (string-append s "<PUT .M 1 !\\Z> .S")) "RIZR3")
  (check-true (t? (run (string-append s "<==? .M <REST .S 2>>"))))
  (check-true (t? (run (string-append s "<=? .M <REST .S 2>>"))))
  ;; BACK recovers the removed prefix: the result is a view, not a copy.
  (check-equal? (v (string-append s "<BACK .M 2>")) "RIVR3")
  ;; str-identity-offset0 (ECHO-ROOM, 77act1.mud:1096)
  (check-true (t? (run "<SET B \"ECHO\"> <==? <MEMBER \"ECHO\" .B> .B>")))
  (check-true (miss? "<SET B \"ECHO\"> <==? <MEMBER \"CHO\" .B> .B>"))
  (check-true (miss? "<SET B2 \"XECHO\"> <==? <MEMBER \"ECHO\" .B2> .B2>"))
  (check-true
   (t? (run (string-append
             "<SET B3 <ISTRING 10 !\\x>> <PUT .B3 1 !\\E> <PUT .B3 2 !\\C> "
             "<PUT .B3 3 !\\H> <PUT .B3 4 !\\O> <==? <MEMBER \"ECHO\" .B3> .B3>")))))

(test-case "SPNAME haystacks (RBOAT, BALLOON, CAKE call sites)"
  ;; str-spname-haystack
  (check-equal? (v "<MEMBER \"RIVR\" <SPNAME RIVR4>>") "RIVR4")
  (check-equal? (v "<MEMBER \"LEDG\" <SPNAME LEDG2>>") "LEDG2")
  (check-equal? (v "<MEMBER \"VAIR\" <SPNAME VAIR1>>") "VAIR1")
  (check-equal? (v "<MEMBER \"ALI\" <SPNAME ALICE>>") "ALICE")
  (check-equal? (v "<MEMBER \"ALI\" <SPNAME ALITR>>") "ALITR")
  (check-true (miss? "<MEMBER \"RIVR\" <SPNAME RAVINE>>"))
  ;; GUEST check (DO-SCRIPT, DO-SAVE)
  (check-true (miss? "<NOT <MEMBER \"GUEST\" \"GUEST\">>")))

(test-case "typed STRING needle and haystack"
  (define mys "<NEWTYPE MYS STRING> ")
  ;; str-typed
  (check-equal? (v (string-append mys "<MEMBER \"b\" <CHTYPE \"abc\" MYS>>")) "bc")
  (check-equal? (type-of "<MEMBER \"b\" <CHTYPE \"abc\" MYS>>" mys) "STRING")
  (check-equal? (v (string-append mys "<MEMBER <CHTYPE \"b\" MYS> \"abc\">")) "bc")
  (check-equal? (v (string-append mys "<MEMBER <CHTYPE \"b\" MYS> <CHTYPE \"abc\" MYS>>")) "bc")
  (check-true (miss? (string-append mys "<MEMBER <CHTYPE \"b\" MYS> '(\"b\")>"))))

(test-case "non-STRING needle in a STRING haystack: element search"
  ;; str-character-needle
  (check-equal? (v "<MEMBER !\\b \"abc\">") "bc")
  (check-true (miss? "<MEMBER !\\z \"abc\">"))
  (check-true (miss? "<MEMBER !\\B \"abc\">"))
  (check-equal? (v "<MEMQ !\\b \"abc\">") "bc")
  (check-true (t? (run "<SET S \"abc\"> <==? <MEMBER !\\b .S> <REST .S 1>>")))
  (check-true (miss? "<MEMBER 98 \"abc\">"))     ; str-fix-needle
  (check-true (miss? "<MEMBER abc \"abc\">"))    ; str-atom-needle
  (check-true (miss? "<MEMBER '(1) \"abc\">")))  ; str-list-needle

(test-case "cycles terminate (=? cycle boundary)"
  ;; A self-containing element is found by identity.
  (check-true
   (t? (bounded-run "<SET V [1 2]> <PUT .V 2 .V> <SET H [0 .V]> <==? <MEMBER .V .H> <REST .H 1>>")))
  (check-true
   (t? (bounded-run "<SET A (1)> <PUTREST .A .A> <SET H (0 .A)> <==? <MEMBER .A .H> <REST .H 1>>")))
  ;; A cyclic needle against a differently shaped element is a finite miss.
  (check-true (mdl-false? (bounded-run "<SET A (1)> <PUTREST .A .A> <MEMBER .A '((1 1) 2)>")))
  ;; Distinct equal-content cycles: the existing explicit =? refusal.
  (check-exn #rx"unsupported cyclic structural equality"
             (lambda ()
               (bounded-run "<SET A (1)> <PUTREST .A .A> <SET B (1)> <PUTREST .B .B> <MEMBER .A (0 .B)>")))
  ;; A cyclic LIST haystack: a hit before the cycle closes is returned; a
  ;; miss is an explicit error rather than a hang (runtime refusal).
  (check-true
   (t? (bounded-run "<SET C (1 2 3)> <PUTREST <REST .C 2> .C> <==? <MEMBER 3 .C> <REST .C 2>>")))
  (check-exn #rx"MEMBER.*cyclic LIST"
             (lambda () (bounded-run "<SET C (1 2 3)> <PUTREST <REST .C 2> .C> <MEMBER 9 .C>"))))

(test-case "strict refusals"
  ;; err-arity-0 / err-arity-1 / err-arity-3
  (check-exn #rx"TOO-FEW-ARGUMENTS-SUPPLIED" (lambda () (run "<MEMBER>")))
  (check-exn #rx"TOO-FEW-ARGUMENTS-SUPPLIED" (lambda () (run "<MEMBER 1>")))
  (check-exn #rx"TOO-MANY-ARGUMENTS-SUPPLIED" (lambda () (run "<MEMBER 1 '(1) 2>")))
  ;; err-nonstructured-* (Confusion: "Second arg to MEMBER must be structured")
  (for ([src (in-list '("<MEMBER 1 2>" "<MEMBER 1 FOO>" "<MEMBER \"a\" 5>"
                        "<MEMBER \"a\" !\\a>"))])
    (check-exn #rx"Second arg to MEMBER must be structured" (lambda () (run src)) src))
  ;; Empty STRING needle on a STRING haystack: runtime refusal. Confusion's
  ;; observed results (str-empty-needle*) are out-of-bounds reads.
  (for ([src (in-list '("<MEMBER \"\" \"abc\">"
                        "<MEMBER <REST \"xyz\" 3> \"abc\">"
                        "<MEMBER <ISTRING 0> \"abc\">"
                        "<MEMBER \"\" <REST \"abc\" 3>>"
                        "<MEMBER \"\" \"\">"
                        "<MEMBER \"\" <ISTRING 3>>"
                        "<MEMBER \"\" <STRING \"ab\" <ASCII 0> \"cd\">>"
                        "<MEMBER <REST <STRING \"x\" \"y\"> 2> \"abc\">"
                        "<NEWTYPE MYS STRING> <MEMBER <CHTYPE \"\" MYS> \"abc\">"))])
    (check-exn #rx"MEMBER.*empty STRING needle" (lambda () (run src)) src))
  ;; TUPLE haystack: modelled by the runtime but not probed for MEMBER.
  (check-exn #rx"MEMBER.*TUPLE"
             (lambda () (run "<DEFINE F (\"TUPLE\" T) <MEMBER 2 .T>> <F 1 2 3>"))))

(displayln "MEMBER tests passed")
