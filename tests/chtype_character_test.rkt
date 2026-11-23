#lang racket/base
;; M4 S3 regression tests: CHTYPE between FIX (WORD) and CHARACTER
;; (frontier F2/F2b, FOOSTR 77np.mud:241; docs/SEMANTICS.md "M4 S3",
;; ADR-0057).
;;
;; Every expectation is a pinned Confusion observation recorded in
;; docs/evidence/M4/character-chtype-probe.json (CHARACTER-CHTYPE-REFERENCE.md);
;; the probe case name is given above each group. Values are compared through
;; the reference's printed notation (`render`, a test-only printer for the
;; values that occur). Out-of-range codes, which the reference accepts, are
;; strict refusals here (ADR-0057). The FOOSTR/PRSTR copy also runs
;; interpreted through the shared-session loader, the game's path.
(require rackunit racket/file racket/list racket/string
         "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt" "../mdl/loader.rkt")

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler (lambda (e) (raise e)))

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (eval-source source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (define v
      (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
        (eval expr)))
    (values v (render v))))
(define (run source)
  (define-values (v text) (eval-source source))
  text)
;; Output written by PRINC (terminal context as tests/princ_test.rkt), then
;; the rendered value.
(define (run/output source)
  (define out (open-output-string))
  (define value
    (parameterize ([current-namespace ns])
      (call-with-mdl-context
       (make-mdl-context #:input-port (open-input-string "") #:output-port out)
       (lambda ()
         (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
           (eval expr))))))
  (list (get-output-string out) (render value)))
(define (refuses source rx)
  (check-exn rx (lambda () (run source)) source))

(define (type-name v) (mdl-atom-pname (mdl-type v)))
(define (render v)
  (cond
    [(mdl-atom? v) (mdl-atom-pname v)]
    [(exact-integer? v) (number->string v)]
    [(string? v) (format "~s" v)]
    [(mdl-false? v) (format "#FALSE (~a)" (string-join (map render (mdl-false-payload v)) " "))]
    [(or (null? v) (mpair? v)) (format "(~a)" (string-join (map render (mdl-list->list v)) " "))]
    [(equal? (type-name v) "STRING") (format "~s" (mdl-string-snapshot 'render v "STRING"))]
    [(equal? (type-name v) "CHARACTER")
     (define code (mdl-base v))
     (unless (and (exact-integer? code) (<= 32 code 126))
       (error 'render "no test notation for CHARACTER code ~s" code))
     (format "!\\~a" (integer->char code))]
    [(mdl-word? (mdl-base v))
     (format "#~a *~a*" (type-name v)
             (let ([o (number->string (mdl-word-bits (mdl-base v)) 8)])
               (string-append (make-string (- 22 (string-length o)) #\0) o)))]
    [else (error 'render "no test notation for ~s" v)]))

;; --- fix-to-character ---------------------------------------------------------
(check-equal? (run "<CHTYPE 65 CHARACTER>") "!\\A")
(check-equal? (run "<TYPE <CHTYPE 65 CHARACTER>>") "CHARACTER")
(check-equal? (run "<PRIMTYPE <CHTYPE 65 CHARACTER>>") "WORD")
(check-equal? (run "<TYPEPRIM CHARACTER>") "WORD")
(check-equal? (run/output "<PRINC <CHTYPE 65 CHARACTER>>") '("A" "!\\A"))
(check-equal? (run "<UNPARSE <CHTYPE 65 CHARACTER>>") "\"!\\\\A\"")
(check-equal? (run "<TYPE? <CHTYPE 98 CHARACTER> CHARACTER>") "CHARACTER")
(check-equal? (run "<CHTYPE 119 CHARACTER>") "!\\w")
(check-equal? (run "<CHTYPE 32 CHARACTER>") "!\\ ")

;; --- character-identity -------------------------------------------------------
(check-equal? (run "<==? <CHTYPE 65 CHARACTER> !\\A>") "T")
(check-equal? (run "<=? <CHTYPE 65 CHARACTER> !\\A>") "T")
(check-equal? (run "<==? <CHTYPE 97 CHARACTER> <CHTYPE 97 CHARACTER>>") "T")
(check-equal? (run "<==? <CHTYPE 97 CHARACTER> !\\A>") "#FALSE ()")
(check-equal? (run "<==? <CHTYPE 97 CHARACTER> 97>") "#FALSE ()")
(check-equal? (run "<=? <CHTYPE 97 CHARACTER> 97>") "#FALSE ()")
(check-equal? (run "<==? <CHTYPE 119 CHARACTER> <ASCII 119>>") "T")
(check-equal? (run "<==? <CHTYPE !\\A CHARACTER> !\\A>") "T")

;; --- character-to-fix -----------------------------------------------------------
(check-equal? (run "<CHTYPE !\\A FIX>") "65")
(check-equal? (run "<TYPE <CHTYPE !\\A FIX>>") "FIX")
(check-equal? (run "<CHTYPE !\\a FIX>") "97")
(check-equal? (run "<CHTYPE <CHTYPE 119 CHARACTER> FIX>") "119")
(check-equal? (run "<==? <CHTYPE !\\w FIX> <ASCII !\\w>>") "T")
(check-equal? (run "<ASCII <CHTYPE 119 CHARACTER>>") "119")
(check-equal? (run "<CHTYPE !\\  FIX>") "32")

;; --- character-word ---------------------------------------------------------------
(check-equal? (run "<CHTYPE !\\A WORD>") "#WORD *0000000000000000000101*")
(check-equal? (run "<TYPE <CHTYPE !\\A WORD>>") "WORD")
(check-equal? (run "<CHTYPE <CHTYPE !\\A WORD> CHARACTER>") "!\\A")
(check-equal? (run "<==? <CHTYPE <CHTYPE !\\A WORD> CHARACTER> !\\A>") "T")
(check-equal? (run "<CHTYPE <CHTYPE 65 WORD> CHARACTER>") "!\\A")
(check-equal? (run "<CHTYPE <CHTYPE <CHTYPE 65 WORD> CHARACTER> FIX>") "65")
(check-equal? (run "<NEWTYPE CH WORD> <CHTYPE <CHTYPE 65 CH> CHARACTER>") "!\\A")
(check-equal? (run "<NEWTYPE CH WORD> <CHTYPE !\\A CH>") "#CH *0000000000000000000101*")
(check-equal? (run "<NEWTYPE CH WORD> <TYPE <CHTYPE !\\A CH>>") "CH")
(check-equal? (run "<NEWTYPE CH WORD> <CHTYPE <CHTYPE !\\A CH> CHARACTER>") "!\\A")

;; --- range-through-ascii (supported part: 0..127) ---------------------------------
(for ([code '(0 1 31 126 127)])
  (check-equal? (run (format "<ASCII <CHTYPE ~a CHARACTER>>" code)) (number->string code))
  (check-equal? (run (format "<CHTYPE <CHTYPE ~a CHARACTER> FIX>" code)) (number->string code))
  (check-equal? (run (format "<==? <CHTYPE ~a CHARACTER> <ASCII ~a>>" code code)) "T"))
(check-equal? (run "<TYPE <CHTYPE 0 CHARACTER>>") "CHARACTER")
;; ascii-fix-range: <TYPE <ASCII 0>> is CHARACTER; ASCII 128/-1 refused by both.
(check-equal? (run "<TYPE <ASCII 0>>") "CHARACTER")
(refuses "<ASCII 128>" #rx"Value for ASCII out of range")
(refuses "<ASCII -1>" #rx"Value for ASCII out of range")
;; Deviation (ADR-0057): the reference accepts these codes (ASCII gives them
;; back unchanged); this runtime refuses them strictly.
(for ([code '(128 255 256 300 -1 34359738367 -34359738368)])
  (refuses (format "<CHTYPE ~a CHARACTER>" code)
           #rx"CHARACTER code out of supported range 0..127"))
(refuses "<CHTYPE <CHTYPE 128 WORD> CHARACTER>" #rx"CHARACTER code out of supported range")
(refuses "<NEWTYPE CH WORD> <CHTYPE <CHTYPE -1 CH> CHARACTER>"
         #rx"CHARACTER code out of supported range")
;; float-word-bits: FLOAT <-> CHARACTER stays unsupported (deviation).
(refuses "<CHTYPE 0.0 CHARACTER>" #rx"mdl-chtype: unsupported")
(refuses "<CHTYPE 1.0 CHARACTER>" #rx"mdl-chtype: unsupported")
(refuses "<CHTYPE !\\A FLOAT>" #rx"mdl-chtype: unsupported built-in TYPE conversion")

;; --- character-in-strings -----------------------------------------------------------
(check-equal? (run "<PROG ((S <ISTRING 3 !\\X>)) <PUT .S 1 <CHTYPE 119 CHARACTER>> .S>") "\"wXX\"")
(check-equal? (run "<STRING <CHTYPE 104 CHARACTER> \"i\">") "\"hi\"")
(check-equal? (run "<MEMQ <CHTYPE 98 CHARACTER> \"abc\">") "\"bc\"")
(check-equal? (run "<MAPF ,STRING <FUNCTION (C) <CHTYPE <+ 32 <ASCII .C>> CHARACTER>> \"WITH\">")
              "\"with\"")
;; (the reference's last form stores code 200: refused here, as above)

;; --- foostr-prstr-shape: FOOSTR/PRSTR/SCRSTR of 77np.mud:230-243, 354 ---------------
(define FOOSTR-DEFS
  (string-append
   "<SETG XSCRSTR <REST <ISTRING 5> 5>>\n"
   "<DEFINE XFOOSTR (NAM STR \"OPTIONAL\" (1ST T)) #DECL ((STR NAM) STRING (1ST) <OR ATOM FALSE>) "
   "<MAPR <> <FUNCTION (X Y) #DECL ((X Y) STRING) <COND (<AND .1ST <==? .X .NAM>> <PUT .Y 1 <1 .X>>) "
   "(<PUT .Y 1 <CHTYPE <+ 32 <ASCII <1 .X>>> CHARACTER>>)>> .NAM .STR> .STR>\n"
   "<DEFINE XPRSTR (ATM \"AUX\" SP) #DECL ((ATM) ATOM (SP) STRING) "
   "<XFOOSTR <SET SP <SPNAME .ATM>> <BACK ,XSCRSTR <LENGTH .SP>> <>>>\n"))
(define (foostr source) (run (string-append FOOSTR-DEFS source)))
(check-equal? (foostr "<MAPF ,LIST ,ASCII <BACK ,XSCRSTR 5>>") "(0 0 0 0 0)")
(check-equal? (foostr "<XPRSTR WITH>") "\"with\"")
(check-equal? (foostr "<XPRSTR AT>") "\"at\"")
(check-equal? (foostr "<XPRSTR MAILB>") "\"mailb\"")
(check-equal? (foostr "<XPRSTR TROLL>") "\"troll\"")
(check-equal? (foostr "<XPRSTR <ATOM \"#####\">>") "\"CCCCC\"")
(check-equal? (foostr "<XPRSTR A-B>") "\"aMb\"")
(check-equal? (foostr (string-append "<XPRSTR WITH> <XPRSTR AT> <XPRSTR MAILB> <XPRSTR TROLL> "
                                     "<XPRSTR <ATOM \"#####\">> <XPRSTR A-B> "
                                     "<MAPF ,LIST ,ASCII <BACK ,XSCRSTR 5>>"))
              "(67 67 97 77 98)")
(check-equal? (foostr "<XFOOSTR \"WITH\" <ISTRING 4 !\\X>>") "\"With\"")
(check-equal? (foostr "<TYPE <1 <XPRSTR AT>>>") "CHARACTER")

;; --- refusals ---------------------------------------------------------------------------
(for ([source '("<CHTYPE \"A\" CHARACTER>" "<CHTYPE (65) CHARACTER>" "<CHTYPE FOO CHARACTER>"
                "<CHTYPE [65] CHARACTER>" "<CHTYPE !\\A ATOM>" "<CHTYPE !\\A LIST>"
                "<CHTYPE !\\A STRING>")])
  (refuses source #rx"mdl-chtype: primitive type mismatch"))
(refuses "<CHTYPE 65 CHARACTER FOO>" #rx"mdl-chtype: arity mismatch")
(refuses "<CHTYPE 65>" #rx"mdl-chtype: arity mismatch")

;; ADR-0056 dispatch: a TYPE atom merely NAMED CHARACTER is an ordinary WORD
;; NEWTYPE, not the built-in CHARACTER (no range check, not ==? to !\A).
(check-equal? (run "<SET A <ATOM \"CHARACTER\">> <NEWTYPE .A WORD> <SPNAME <TYPE <CHTYPE 65 .A>>>")
              "\"CHARACTER\"")
(check-equal? (run "<SET A <ATOM \"CHARACTER\">> <NEWTYPE .A WORD> <==? <TYPE <CHTYPE 65 .A>> CHARACTER>")
              "#FALSE ()")
(check-equal? (run "<SET A <ATOM \"CHARACTER\">> <NEWTYPE .A WORD> <==? <CHTYPE 65 .A> !\\A>")
              "#FALSE ()")
(check-equal? (run "<SET A <ATOM \"CHARACTER\">> <NEWTYPE .A WORD> <CHTYPE <CHTYPE 300 .A> FIX>")
              "300")

;; --- interpreted twin: the FOOSTR copy through the shared-session loader -------------
(define scratch-root
  (let ([p (make-temporary-file "mdl-chtype-character-test~a" #f (find-system-path 'temp-dir))])
    (delete-file p)
    (make-directory* p)
    p))
(dynamic-wind
 void
 (lambda ()
   (call-with-output-file (build-path scratch-root "chr.mud") #:exists 'truncate/replace
     (lambda (out)
       (display (string-append FOOSTR-DEFS
                               "<DEFINE LOW (N) <CHTYPE <+ 32 .N> CHARACTER>>\n"
                               "<DEFINE CODE (C) <CHTYPE .C FIX>>\n")
                out)))
   (define session (make-mdl-session scratch-root))
   (check-equal? (hash-ref (mdl-session-load! session "chr.mud") 'status) "PASS")
   (define (text v) (mdl-string-snapshot 'chtype-character-test v "STRING"))
   (check-equal? (text (mdl-session-call session "XPRSTR" (mdl-session-atom session "WITH"))) "with")
   (check-equal? (text (mdl-session-call session "XPRSTR" (mdl-session-atom session "AT"))) "at")
   (check-equal? (for/list ([c (in-string (text (mdl-session-call session "BACK"
                                                                  (mdl-session-global session "XSCRSTR")
                                                                  5)))])
                   (char->integer c))
                 '(0 119 105 97 116))
   (define w (mdl-session-call session "LOW" 87))
   (check-equal? (mdl-atom-pname (mdl-session-call session "TYPE" w)) "CHARACTER")
   (check-true (mdl-truthy? (mdl-session-call session "==?" w (mdl-session-call session "ASCII" 119))))
   (check-equal? (mdl-session-call session "CODE" w) 119)
   (check-exn #rx"CHARACTER code out of supported range"
              (lambda () (mdl-session-call session "LOW" 96)))
   (displayln "interpreted CHTYPE CHARACTER twins passed"))
 (lambda () (delete-directory/files scratch-root #:must-exist? #f)))

;; S3 independent review: the second game use, the balloon's VAIRn room
;; names (77act2.mud:526 rising, :578 falling), steps the digit with CHTYPE.
(check-equal? (run "<PROG ((S <ISTRING 5 !\\X>) (M \"VAIR3\")) <SUBSTRUC \"VAIR3\" 0 4 .S> <PUT .S 5 <CHTYPE <+ <CHTYPE <5 .M> FIX> 1> CHARACTER>> .S>")
              "\"VAIR4\"")
(check-equal? (run "<PROG ((S <ISTRING 5 !\\X>) (M \"VAIR3\")) <SUBSTRUC \"VAIR3\" 0 4 .S> <PUT .S 5 <CHTYPE <- <CHTYPE <5 .M> FIX> 1> CHARACTER>> .S>")
              "\"VAIR2\"")

(displayln "chtype character tests passed")
