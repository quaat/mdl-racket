#lang racket/base
;; M4 S2 regression tests: CHTYPE to SEGMENT and runtime-built SEGMENT
;; objects (frontier F1; docs/SEMANTICS.md "M4 S2", ADR-0056).
;;
;; Every expectation is a pinned Confusion observation recorded in
;; docs/evidence/M4/segment-chtype-probe.json (SEGMENT-CHTYPE-REFERENCE.md);
;; the case name of the probe is given above each group. Values are compared
;; through the reference's printed notation (`render`, a test-only printer:
;; the runtime's own PRIN1/UNPARSE of SEGMENT stays strict). Each group runs
;; compiled (`run`) and, where the game path depends on it, interpreted
;; through the shared-session loader, like tests/segment_test.rkt.
;;
;; The runtime has no EVAL SUBR (outside the game path). The reference cases
;; that use EVAL have recorded "-via-macro" twins that replace <EVAL x> by
;; <EV x> with <DEFMAC EV (X) .X> (evaluate the argument, then evaluate that
;; value as the expansion); their output equals the EVAL cases. `run`
;; defines EV first, and the tests below use it.
(require rackunit racket/file racket/list racket/string
         "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt" "../mdl/loader.rkt")

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler (lambda (e) (raise e)))

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (render
     (for/fold ([result #f])
               ([expr (in-list (compile-program (parse-mdl (string-append "<DEFMAC EV (X) .X> "
                                                                         source))))])
       (eval expr)))))

(define (type-name v) (mdl-atom-pname (mdl-type v)))
(define (render v)
  (cond
    [(mdl-segment? v) (segment-notation v)]
    [(mdl-atom? v) (mdl-atom-pname v)]
    [(exact-integer? v) (number->string v)]
    [(string? v) (format "~s" v)]
    [(mdl-false? v) (format "#FALSE (~a)" (string-join (map render (mdl-false-payload v)) " "))]
    [(or (null? v) (mpair? v)) (format "(~a)" (string-join (map render (mdl-list->list v)) " "))]
    [(equal? (type-name v) "FORM")
     (define elements (form-elements v))
     (define (head? name) (and (= 2 (length elements)) (mdl-atom? (car elements))
                               (string=? (mdl-atom-pname (car elements)) name)
                               (mdl-atom? (cadr elements))))
     (cond [(head? "LVAL") (format ".~a" (mdl-atom-pname (cadr elements)))]
           [(head? "GVAL") (format ",~a" (mdl-atom-pname (cadr elements)))]
           [else (format "<~a>" (string-join (map render elements) " "))])]
    [(equal? (type-name v) "CHARACTER") (format "!\\~a" (integer->char (mdl-base v)))]
    [(and (mdl-array? v) (eq? (mdl-array-kind v) 'VECTOR))
     (format "[~a]" (string-join (for/list ([i (in-range (mdl-array-length v))])
                                   (render (mdl-nth v (add1 i)))) " "))]
    [(not (eq? (mdl-base v) v))           ; a TYPE tag over a structure
     (format "#~a ~a" (type-name v) (render (mdl-base v)))]
    [else (error 'render "no test notation for ~s" v)]))
;; The reference's SEGMENT notation (mdl_output.cpp): !.X, !,X, else !<...!>.
(define (segment-notation s)
  (define elements (form-elements (mdl-segment-payload s)))
  (define (head? name) (and (= 2 (length elements)) (mdl-atom? (car elements))
                            (string=? (mdl-atom-pname (car elements)) name)
                            (mdl-atom? (cadr elements))))
  (cond [(head? "LVAL") (format "!.~a" (mdl-atom-pname (cadr elements)))]
        [(head? "GVAL") (format "!,~a" (mdl-atom-pname (cadr elements)))]
        [else (format "!<~a!>" (string-join (map render elements) " "))]))

;; --- type-of-chtype ---------------------------------------------------------
(check-equal? (run "<TYPE <CHTYPE <FORM A B> SEGMENT>>") "SEGMENT")
(check-equal? (run "<PRIMTYPE <CHTYPE <FORM A B> SEGMENT>>") "LIST")
(check-equal? (run "<TYPEPRIM SEGMENT>") "LIST")

;; --- reader-segment-is-same-type ---------------------------------------------
(check-equal? (run "<TYPE '!.X>") "SEGMENT")
(check-equal? (run "<PRIMTYPE '!.X>") "LIST")
(check-equal? (run "<1 '!.X>") "LVAL")
(check-equal? (run "<2 '!.X>") "X")
(check-equal? (run "<1 '!,X>") "GVAL")
(check-equal? (run "<TYPE '!<A B C>>") "SEGMENT")
(check-equal? (run "<LENGTH '!<A B C>>") "3")
(check-equal? (run "<=? '!<A B> <CHTYPE <FORM A B> SEGMENT>>") "T")

;; --- identity-sharing ---------------------------------------------------------
(define F+S "<SET F <FORM A B>> <SET S <CHTYPE .F SEGMENT>> ")
(check-equal? (run (string-append F+S ".S")) "!<A B!>")
(check-equal? (run (string-append F+S "<==? .S .F>")) "#FALSE ()")
(check-equal? (run (string-append F+S "<=? .S .F>")) "#FALSE ()")
;; Reference: <==? <CHTYPE .S FORM> .F> and <=? ...> are T. CHTYPE to FORM
;; stays an unsupported built-in conversion here (not on the game path;
;; tests/type_test.rkt); the LIST views below show the same cell identity.
(check-exn #rx"unsupported built-in TYPE conversion"
           (lambda () (run (string-append F+S "<CHTYPE .S FORM>"))))
(check-equal? (run (string-append F+S "<==? <CHTYPE .S LIST> <CHTYPE .F LIST>>")) "T")
(check-equal? (run (string-append F+S "<==? <CHTYPE .S SEGMENT> .S>")) "T")
(check-equal? (run (string-append F+S "<==? <CHTYPE .F SEGMENT> .S>")) "T")
(check-equal? (run (string-append F+S "<PUT .S 2 C>")) "!<A C!>")
(check-equal? (run (string-append F+S "<PUT .S 2 C> .F")) "<A C>")
(check-equal? (run (string-append F+S "<PUT .S 2 C> <PUT .F 1 D> .S")) "!<D C!>")
(check-equal? (run (string-append F+S "<LENGTH .S>")) "2")
(check-equal? (run (string-append F+S "<TYPE <REST .S>>")) "LIST")

;; --- list-primtype-sources ----------------------------------------------------
(check-equal? (run "<CHTYPE (A B) SEGMENT>") "!<A B!>")
(check-equal? (run "<TYPE <CHTYPE (A B) SEGMENT>>") "SEGMENT")
(check-equal? (run "<CHTYPE <> SEGMENT>") "!<!>")
(check-equal? (run "<TYPE <CHTYPE <> SEGMENT>>") "SEGMENT")
(check-equal? (run "<NEWTYPE FOO LIST> <CHTYPE <CHTYPE (A) FOO> SEGMENT>") "!<A!>")
(check-equal? (run "<NEWTYPE FOO LIST> <CHTYPE <CHTYPE (A B) SEGMENT> FOO>") "#FOO (A B)")
(check-exn #rx"unsupported built-in TYPE conversion"     ; reference: <A B>
           (lambda () (run "<CHTYPE <CHTYPE (A B) SEGMENT> FORM>")))
(check-equal? (run "<CHTYPE <CHTYPE (A B) SEGMENT> LIST>") "(A B)")
(check-equal? (run "<CHTYPE <CHTYPE <FORM A> SEGMENT> FALSE>") "#FALSE (A)")
(check-equal? (run "<CHTYPE () SEGMENT>") "!<!>")

;; --- err-vector / err-string / err-uvector / err-fix / err-atom /
;; --- err-segment-to-vector (reference: PRIMTYPES do not match in CHTYPE)
(for ([src (in-list '("<CHTYPE [1 2] SEGMENT>" "<CHTYPE \"AB\" SEGMENT>"
                      "<CHTYPE ![1 2!] SEGMENT>" "<CHTYPE 1 SEGMENT>"
                      "<CHTYPE FOO SEGMENT>"
                      "<CHTYPE <CHTYPE <FORM A> SEGMENT> VECTOR>"))])
  (check-exn #rx"primitive type mismatch" (lambda () (run src)) src))

;; --- eval-list-splice (and every eval-* group: the -via-macro twin) ---------------------------------------------------------
(define L+S "<SET L (6 7 8)> <SET S <CHTYPE <FORM LVAL L> SEGMENT>> ")
(check-equal? (run (string-append L+S ".S")) "!.L")
(check-equal? (run (string-append L+S "<EV <LIST 1 .S 2>>")) "(1 6 7 8 2)")
(check-equal? (run (string-append L+S "<EV <LIST 0 .S>>")) "(0 6 7 8)")
(check-equal? (run (string-append L+S "<==? <REST <EV <LIST 0 .S>>> .L>")) "T")
(check-equal? (run (string-append L+S "<EV <LIST .S>>")) "(6 7 8)")
(check-equal? (run (string-append L+S "<==? <EV <LIST .S>> .L>")) "T")
(check-equal? (run (string-append L+S "<EV <LIST .S 9>>")) "(6 7 8 9)")
(check-equal? (run (string-append L+S "<==? <REST <EV <LIST .S 9>> 3> .L>")) "#FALSE ()")
(check-equal? (run (string-append L+S "<EV <LIST .S .S>>")) "(6 7 8 6 7 8)")

;; --- eval-list-tail-mutation ----------------------------------------------------
(check-equal? (run (string-append "<SET L (6 7 8)> "
                                  "<SET R <EV <LIST 0 <CHTYPE <FORM LVAL L> SEGMENT>>>> "
                                  "<PUT .L 1 60> .R"))
              "(0 60 7 8)")
(check-equal? (run (string-append "<SET L (60 7 8)> "
                                  "<SET R4 <EV <LIST <CHTYPE <FORM LVAL L> SEGMENT> 0>>> "
                                  "<PUT .L 2 70> .R4"))
              "(60 7 8 0)")

;; --- eval-vector-uvector -----------------------------------------------------------
(check-equal? (run (string-append L+S "<EV <VECTOR 0 .S 9>>")) "[0 6 7 8 9]")
(check-equal? (run (string-append L+S "<EV <VECTOR .S>>")) "[6 7 8]")
;; The UVECTOR SUBR sees a FIX and a SEGMENT value before any EVAL.
(check-exn #rx"TYPES-DIFFER-IN-UNIFORM-VECTOR|one permitted TYPE"
           (lambda () (run (string-append L+S "<EV <UVECTOR 0 .S>>"))))

;; --- eval-form-args ---------------------------------------------------------------
(check-equal? (run (string-append L+S "<EV <FORM + 1 .S>>")) "22")
(check-equal? (run (string-append L+S "<EV <FORM LIST 1 .S>>")) "(1 6 7 8)")
(check-equal? (run (string-append L+S "<==? <REST <EV <FORM LIST 1 .S>>> .L>")) "#FALSE ()")
(check-equal? (run (string-append L+S "<EV <FORM LIST .S>>")) "(6 7 8)")
(check-equal? (run (string-append L+S "<==? <EV <FORM LIST .S>> .L>")) "#FALSE ()")
(check-exn #rx"TOO-MANY-ARGUMENTS"
           (lambda () (run (string-append L+S "<EV <FORM PUT <FORM LVAL L> 1 .S>>"))))

;; --- eval-function-args ----------------------------------------------------------
;; A "TUPLE" formal receives the spliced elements (reference: ?[1 6 7 8?]).
(check-equal? (run (string-append L+S "<DEFINE FT (\"TUPLE\" TT) .TT> <LENGTH <EV <FORM FT 1 .S>>>"))
              "4")
(check-equal? (run (string-append L+S "<DEFINE FT (\"TUPLE\" TT) .TT> <4 <EV <FORM FT 1 .S>>>"))
              "8")
;; Recorded deviation (SEMANTICS M2 D2 and M4 S2): the reference binds the
;; required formals of an interpreted FUNCTION from the raw SEGMENT and
;; raises ILLEGAL-SEGMENT; this runtime splices the elements.
(check-equal? (run (string-append L+S "<DEFINE F3 (A B C) (.A .B .C)> <EV <FORM F3 .S>>"))
              "(6 7 8)")

;; --- eval-chtype-list-source ---------------------------------------------------------
(check-equal? (run "<SET L (1 2)> <EV <LIST 0 <CHTYPE (LVAL L) SEGMENT>>>") "(0 1 2)")
(check-equal? (run "<EV <LIST 0 <CHTYPE <FORM LIST> SEGMENT> 3>>") "(0 3)")
(check-equal? (run "<EV <LIST 0 <CHTYPE <FORM VECTOR 4 5> SEGMENT>>>") "(0 4 5)")
(check-equal? (run "<EV <LIST 0 <CHTYPE <FORM STRING \"ab\"> SEGMENT>>>") "(0 !\\a !\\b)")

;; --- plain-element-value-stored -------------------------------------------------------
(check-equal? (run (string-append L+S "<LIST 1 .S>")) "(1 !.L)")
(check-equal? (run (string-append L+S "<TYPE <2 <LIST 1 .S>>>")) "SEGMENT")
(check-equal? (run (string-append L+S "<==? <2 <LIST 1 .S>> .S>")) "T")
(check-equal? (run (string-append L+S "(1 <CHTYPE <FORM LVAL L> SEGMENT>)")) "(1 !.L)")
(check-equal? (run (string-append L+S "<SET Q (1 <CHTYPE <FORM LVAL L> SEGMENT>)> <EV .Q>"))
              "(1 6 7 8)")

;; --- err-standalone-eval / err-nonstructured-payload ---------------------------------
(check-exn #rx"ILLEGAL-SEGMENT: Attempt to evaluate segment outside structured type"
           (lambda () (run "<SET L (6 7 8)> <EV <CHTYPE <FORM LVAL L> SEGMENT>>")))
(check-exn #rx"ILLEGAL-SEGMENT: Segment evaluated to nonstructured type"
           (lambda () (run "<EV <LIST 0 <CHTYPE <FORM + 1 2> SEGMENT>>>")))

;; --- defmac-insert-shape (compiled) ---------------------------------------------------
(define INS (string-append
         "<DEFMAC INS ('OBJ 'BOX) <FORM PUT .BOX 1 (.OBJ <CHTYPE <FORM 1 .BOX> SEGMENT>)>> "
             "<SET V [(A B)]> <SET OLD <1 .V>> "))
(check-equal? (run (string-append INS "<EXPAND '<INS Z .V>>")) "<PUT .V 1 (Z !<1 .V!>)>")
(check-equal? (run (string-append INS "<MAPF ,LIST ,TYPE <4 <EXPAND '<INS Z .V>>>>"))
              "(ATOM SEGMENT)")
(check-equal? (run (string-append INS "<INS Z .V> .V")) "[(Z A B)]")
(check-equal? (run (string-append INS "<INS Z .V> <==? <REST <1 .V>> .OLD>")) "T")
(check-equal? (run (string-append INS "<INS Z .V> <DEFINE USE (W) <INS Y .W>> <USE .V> .V"))
              "[(Y Z A B)]")
(check-equal? (run (string-append INS "<INS Z .V> <DEFINE USE (W) <INS Y .W>> <USE .V> "
                                  "<==? <REST <1 .V> 2> .OLD>"))
              "T")

;; --- interpreted twins through the shared-session loader --------------------------
(define scratch-root
  (let ([p (make-temporary-file "mdl-chtype-segment-test~a" #f (find-system-path 'temp-dir))])
    (delete-file p)
    (make-directory* p)
    p))
(dynamic-wind
 void
 (lambda ()
   (call-with-output-file (build-path scratch-root "seg.mud") #:exists 'truncate/replace
     (lambda (out)
       (display
        (string-append
         "<DEFMAC INS ('OBJ 'BOX) <FORM PUT .BOX 1 (.OBJ <CHTYPE <FORM 1 .BOX> SEGMENT>)>>\n"
         "<DEFMAC EV (X) .X>\n"
         "<SETG V [(A B)]>\n<SETG OLD <1 ,V>>\n"
         "<DEFINE USE (W) <INS Y .W>>\n"
         "<DEFINE MK (L) <CHTYPE <FORM LVAL L> SEGMENT>>\n"
         "<DEFINE SPL (L \"AUX\" (S <MK .L>)) <EV <LIST 0 .S>>>\n"
         "<DEFINE BACKL (S) <CHTYPE .S LIST>>\n")
        out)))
   (define session (make-mdl-session scratch-root))
   (check-equal? (hash-ref (mdl-session-load! session "seg.mud") 'status) "PASS")
   (define v (mdl-session-global session "V"))
   (define old (mdl-session-global session "OLD"))
   (mdl-session-call session "USE" v)
   (check-equal? (render (mdl-session-call session "NTH" v 1)) "(Y A B)")
   (check-eq? (mdl-session-call session "REST" (mdl-session-call session "NTH" v 1)) old)
   (define l (mdl-session-call session "LIST" 6 7 8))
   (define spliced (mdl-session-call session "SPL" l))
   (check-equal? (render spliced) "(0 6 7 8)")
   (check-eq? (mdl-session-call session "REST" spliced) l)
   (define seg (mdl-session-call session "MK" l))
   (check-equal? (mdl-atom-pname (mdl-session-call session "TYPE" seg)) "SEGMENT")
   (check-equal? (render (mdl-session-call session "BACKL" seg)) "(LVAL L)")
   (displayln "interpreted CHTYPE SEGMENT twins passed"))
 (lambda () (delete-directory/files scratch-root #:must-exist? #f)))

;; S2 independent review: a TYPE atom merely NAMED SEGMENT (not ROOT's) with
;; PRIMTYPE VECTOR is an ordinary user TYPE: CHTYPE tags the VECTOR and does
;; not take the built-in SEGMENT (LIST) branch; with PRIMTYPE LIST it does not
;; splice. The same holds for a user TYPE named LIST.
(check-equal? (run "<SET A <ATOM \"SEGMENT\">> <NEWTYPE .A VECTOR> <SPNAME <TYPE <CHTYPE [1 2] .A>>>")
              "\"SEGMENT\"")
(check-equal? (run "<SET A <ATOM \"SEGMENT\">> <NEWTYPE .A VECTOR> <==? <TYPE <CHTYPE [1 2] .A>> SEGMENT>")
              (run "<==? 1 2>"))
(check-equal? (run "<SET L <ATOM \"LIST\">> <NEWTYPE .L VECTOR> <LENGTH <CHTYPE [1 2 3] .L>>")
              "3")
(check-equal? (run "<SET A <ATOM \"SEGMENT\">> <NEWTYPE .A LIST> <SET Q (5 6)> <LENGTH (0 <CHTYPE (.Q) .A>)>")
              "2")

(displayln "chtype segment tests passed")
