#lang racket/base
;; M2-D5: atom-property PUT/GET associations (issue #53).
;;
;; The reference observations are the pinned Confusion runs recorded in
;; docs/evidence/M2/atom-props-reference.json and atom-props-error-reference.json
;; (see docs/evidence/M2/ATOM-PROPS.md, interpreter SHA a29c756df5c9...7317e629).
;; `run` cases mirror recorded successes and deliberate errors, keyed by ==?
;; identity of item and indicator; the loader cases replay the pinned
;; 77loadall.mud -> 77defs.mud bytes in an isolated scratch root (never from
;; .cache/upstream) and pin the original RAPPLIC association in a bounded
;; prefix. Every value
;; is rendered in the pinned Confusion notation *inside* its session context,
;; since rendering an identity (a FORM's TYPE atom) after the session's atom
;; space is gone would fail spuriously.
(require rackunit racket/file racket/path racket/list racket/string
         racket/port racket/system
         "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt" "../mdl/loader.rkt")

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
;; Runs the source and renders its last result in the same session context.
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (render-final
     (for/fold ([result #f])
               ([expr (in-list (compile-program (parse-mdl source)))])
       (eval expr)))))
;; Render a value in the pinned Confusion notation, as in segment_test.rkt:
;; atom identity is per-session, so comparisons go through PNAMEs.
(define (render-final value)
  (cond
    [(mdl-atom? value) (mdl-atom-pname value)]
    [(mdl-false? value)
     (format "#FALSE (~a)"
             (string-join (map render-final (mdl-false-payload value)) " "))]
    [(string? value) (format "~s" value)]
    [(char? value) (format "!\\~a" value)]
    [(and (mdl-atom? (mdl-type value))
          (string=? (mdl-atom-pname (mdl-type value)) "CHARACTER"))
     (format "!\\~a" (integer->char (mdl-base value)))]
    [(or (null? value) (mpair? value))
     (format "(~a)" (string-join (map render-final (mdl-list->list value)) " "))]
    [(mdl-form? value)
     (format "<~a>" (string-join (map render-final (form-elements value)) " "))]
    [(number? value) (format "~a" value)]
    [else (format "~s" value)]))

;; --- success cases (atom-props-reference.json, 18/18 clean exits) ----------

;; 77defs.mud expression 3, the load blocker itself: PUT on an atom is an
;; association, returns the item, storage succeeds.
(check-equal? (run "<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>") "RAPPLIC")
;; get-decl-after-put: GET retrieves the stored FORM; its TYPE is FORM.
(check-equal? (run "<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>> <GET RAPPLIC DECL>")
              "<OR ATOM FALSE NOFFSET>")
(check-equal? (run "<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>> <TYPE <GET RAPPLIC DECL>>")
              "FORM")
;; Values are evaluated before storing (putprop-subr-computed-value shape).
(check-equal? (run "<PUT RAPPLIC P <+ 1 2>> <GET RAPPLIC P>") "3")
(check-equal? (run "<PUT RAPPLIC P <+ 1 2>> <TYPE <GET RAPPLIC P>>") "FIX")
;; Second-property independence: per-indicator storage on one item.
(check-equal? (run "<PUT RAPPLIC OTHER 5> <PUT RAPPLIC DECL 'FIX> <GET RAPPLIC OTHER>")
              "5")
(check-equal? (run "<PUT RAPPLIC OTHER 5> <PUT RAPPLIC DECL 'FIX> <GET RAPPLIC DECL>")
              "FIX")
;; Overwrite-latest-wins.
(check-equal? (run "<PUT W W 1> <PUT W W 2> <GET W W>") "2")
;; Complex values round-trip (list-value-preserved).
(check-equal? (run "<PUT RAPPLIC L '(1 2 3)> <GET RAPPLIC L>") "(1 2 3)")
(check-equal? (run "<PUT RAPPLIC L '(1 2 3)> <TYPE <GET RAPPLIC L>>") "LIST")
;; The printer shows no properties (atom-echo-no-property-markup).
(check-equal? (run "<PUT RAPPLIC DECL 'FIX> RAPPLIC") "RAPPLIC")
(check-equal? (run "<PUT RAPPLIC DECL 'FIX> 'RAPPLIC") "RAPPLIC")
;; TYPE/PRIMTYPE of a property-carrying atom stay ATOM.
(check-equal? (run "<PUT RAPPLIC DECL 'FIX> <TYPE RAPPLIC>") "ATOM")
(check-equal? (run "<PUT RAPPLIC DECL 'FIX> <PRIMTYPE RAPPLIC>") "ATOM")
;; RAPPLIC stays GASSIGNED?-false after the DECL property PUT.
(check-equal? (run "<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>> <GASSIGNED? RAPPLIC>")
              "#FALSE ()")
;; A ,RAPPLIC GVAL read still breaks UNBOUND-VARIABLE with the property set:
;; properties and assignment are fully separate in the reference.
(check-exn #rx"unassigned MDL global RAPPLIC"
           (lambda () (run "<PUT RAPPLIC DECL 'FIX> ,RAPPLIC")))
;; GET on a missing property with no exp is #FALSE () (get-missing-property-false).
(check-equal? (run "<GET FOO MISSING-PROP>") "#FALSE ()")
;; GET's association-path exp fallback (get-exp-fallback): present indicator
;; -> stored value; missing indicator -> the exp value.
(check-equal? (run "<PUT RAPPLIC P 'V> <GET RAPPLIC P 'FALLBACK>") "V")
(check-equal? (run "<PUT RAPPLIC P 'V> <GET RAPPLIC Q 'FALLBACK>") "FALLBACK")
;; PUT on a non-atom item is a legal association (fix-item-association).
(check-equal? (run "<PUT 5 DECL 'FIX>") "5")
(check-equal? (run "<PUT 5 DECL 'FIX> <GET 5 DECL>") "FIX")
(check-equal? (run "<PUT 5 DECL 'FIX> <TYPE <GET 5 DECL>>") "ATOM")
;; Final-head local review (#67): a SUBR is an unstructured association item.
;; Its FIX indicator must not force host-procedure PRIMTYPE dispatch.
(check-equal? (run "<PUT ,+ 7 9> <GET ,+ 7>") "9")
(check-equal? (run "<PUT ,+ 7 9> <PUT ,+ 7> <GET ,+ 7>") "#FALSE ()")
;; Chapter 13 keys are selected by MDL ==?, including equal WORD values,
;; large FIXes, and independently constructed views of the same array tail.
;; All five observations were reproduced in pinned Confusion on 2026-11-20.
(check-equal? (run "<PUT <CHTYPE 1 WORD> P 'X> <GET <CHTYPE 1 WORD> P>") "X")
(check-equal? (run "<PUT X <CHTYPE 1 WORD> 'Y> <GET X <CHTYPE 1 WORD>>") "Y")
(check-equal? (run "<PUT 4294967295 P 'X> <GET 4294967295 P>") "X")
(check-equal? (run "<SET V '[1 2 3]> <PUT <REST .V 1> P 'X> <GET <REST .V 1> P>") "X")
(check-equal? (run "<SET V '![1 2 3]> <PUT <REST .V 1> P 'X> <GET <REST .V 1> P>") "X")
;; Removal via two-argument PUT; the item is echoed (association-remove-
;; two-arg-put), and the property is gone afterwards.
(check-equal? (run "<PUT RAPPLIC P 'V> <PUT RAPPLIC P>") "RAPPLIC")
(check-equal? (run "<PUT RAPPLIC P 'V> <PUT RAPPLIC P> <GET RAPPLIC P>")
              "#FALSE ()")
(check-exn #rx"TOO-FEW-ARGUMENTS-SUPPLIED"
           (lambda () (run "<PUT '(1 2) 1>")))
;; Identity-keyed retrieval: a fresh (1 2 3) LIST misses .L's association.
(check-equal? (run "<SET L (1 2 3)> <PUT .L FOO 'VAL> <GET .L FOO>") "VAL")
(check-equal? (run "<SET L (1 2 3)> <PUT .L FOO 'VAL> <GET (1 2 3) FOO>")
              "#FALSE ()")
;; Identity-keyed misses on STRINGs (string-item-identity-miss): a string
;; built at load time is a distinct ==? object from a same-spelling literal.
(check-equal? (run "<PUT <STRING \"abc\"> P 'X> <GET \"abc\" P>") "#FALSE ()")
;; Recorded deviation: in this bootstrap compiler Racket's eval interns equal
;; string literals, so two same-spelling string literals are one ==? object
;; and the reference's fresh-READ miss cannot be reproduced with literals.
;; The table itself matches whatever ==? decides (the STRING-append miss
;; above); literal-string identity is a reader/compiler issue, not an
;; association one.
(check-equal? (run "<PUT \"abc\" P 'X> <GET \"abc\" P>") "X")
;; DECL? consults the atom's DECL property (declq-consults-atom-decl): the
;; NOFFSET-typed value matches the RAPPLIC pattern via <OR ATOM FALSE NOFFSET>.
(check-equal?
 (run "<NEWTYPE NOFFSET WORD> <PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>> \
<DECL? <CHTYPE 1 NOFFSET> RAPPLIC>")
 "T")
;; The miss carries the resolved pattern's leaf, not the atom: #FALSE (3 NOFFSET).
(check-equal?
 (run "<NEWTYPE NOFFSET WORD> <PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>> \
<DECL? 3 RAPPLIC>")
 "#FALSE (3 NOFFSET)")
;; Alias chains are traversed to a registered TYPE, while a registered TYPE
;; keeps its intrinsic meaning even if an association is attached to it.
(check-equal? (run "<PUT A DECL 'B> <PUT B DECL 'FIX> <DECL? 3 A>") "T")
(check-equal? (run "<PUT A DECL 'B> <PUT B DECL 'FIX> <DECL? \"x\" A>")
              "#FALSE (\"x\" FIX)")
(check-equal? (run "<PUT FIX DECL 'STRING> <DECL? 3 FIX>") "T")
(check-exn #rx"cyclic.*DECL"
           (lambda () (run "<PUT A DECL 'B> <PUT B DECL 'A> <DECL? 3 A>")))
;; The same alias normalization is used by attached declarations.
(check-equal? (run "<PUT A DECL 'FIX> <DEFINE F (X) #DECL ((X) A) .X> <F 3>") "3")
(check-exn #rx"DECL.*X"
           (lambda () (run "<PUT A DECL 'FIX> <DEFINE F (X) #DECL ((X) A) .X> <F \"x\">")))
;; SETG ignores the atom's DECL property (setg-ignores-atom-decl).
(check-equal? (run "<PUT SOMETHING DECL 'FIX> <SETG SOMETHING \"str\"> ,SOMETHING")
              "\"str\"")
(check-equal? (run "<PUT SOMETHING DECL 'FIX> <SETG SOMETHING \"str\"> <GASSIGNED? SOMETHING>")
              "T")

;; --- deliberate-error cases (atom-props-error-reference.json) --------------

;; PUT with one argument: TOO-FEW-ARGUMENTS-SUPPLIED.
(check-exn #rx"TOO-FEW-ARGUMENTS-SUPPLIED"
           (lambda () (run "<PUT RAPPLIC>")))
;; GET on a structured item rejects the optional exp.
(check-exn #rx"No EXP allowed for GET on structure"
           (lambda () (run "<GET '(1 2 3) 1 'X>")))
;; PUT index too large on a structure: the element path keeps the existing
;; out-of-range failure, now with the reference's stderr text (the older
;; "index out of range" wording was this runtime's D1-era deviation).
(check-exn #rx"PUT index too large"
           (lambda () (run "<PUT '(1 2 3) 9 'X>")))
;; PUT into a STRING requires CHARACTER elements.
(check-exn #rx"Strings may only contain CHARACTER type"
           (lambda () (run "<PUT \"ab\" 1 3>")))
;; GET on a STRING or one-argument structured object follows NTH; the
;; CHARACTER result can be stored into a mutable STRING built by STRING.
(check-equal? (run "<GET \"ab\" 1>") "!\\a")
(check-equal? (run "<TYPE <GET \"ab\" 1>>") "CHARACTER")
(check-equal? (run "<PRIMTYPE <GET \"ab\" 1>>") "WORD")
(check-equal? (run "<GET '(1 2)>") "1")
(check-equal? (run "<GET \"ab\">") "!\\a")
(check-equal? (run "<SET S <STRING \"ab\">> <PUT .S 1 <GET \"xy\" 1>> .S")
              "\"xb\"")
;; Final-head review: STRING segment extraction and indexed GET must yield
;; the same CHARACTER identity; PUT must accept either source path.
(check-equal?
 (run "<SET S <STRING \"ab\">> <SET C \"xy\"> <PUT .S 1 <NTH (!.C) 1>> .S")
 "\"xb\"")
(check-equal?
 (run "<SET C \"xy\"> <==? <GET .C 1> <NTH (!.C) 1>>")
 "T")
;; GETPROP/PUTPROP stay out of scope: explicit unassigned-operator failure
;; (the task's strict-failure rule; the reference implements them, but the
;; pinned sources never call them).
(check-exn #rx"unassigned or non-applicable MDL operator GETPROP"
           (lambda () (run "<PUT RAPPLIC P 'V> <GETPROP RAPPLIC P>")))
(check-exn #rx"unassigned or non-applicable MDL operator GETPROP"
           (lambda () (run "<PUT RAPPLIC P 'V> <GETPROP RAPPLIC Q 'FALLBACK 77>")))
(check-exn #rx"unassigned or non-applicable MDL operator PUTPROP"
           (lambda () (run "<PUTPROP RAPPLIC P 'V>")))

;; --- properties do not leak across sessions --------------------------------
;; A fresh `run` is a fresh atom-space: after one session stores RAPPLIC's
;; DECL property, another session's RAPPLIC has zero associations, and its
;; name remains a plain unregistered atom (explicit normalization error, as
;; before this slice).
(check-equal? (run "<PUT RAPPLIC DECL 'FIX> <GET RAPPLIC DECL>") "FIX")
(check-equal? (run "<GET RAPPLIC DECL>") "#FALSE ()")
(check-equal? (run "<PUT RAPPLIC DECL 'VECTOR> <DECL? 3 RAPPLIC>")
              "#FALSE (3 VECTOR)")
(check-exn #rx"unknown declaration type RAPPLIC"
           (lambda () (run "<DECL? 3 RAPPLIC>")))

;; --- historical bounded prefix: the pinned original bytes ------------------
;; Copy the exact pinned bytes of 77loadall.mud, 81prim.mud, and 77defs.mud
;; into an isolated scratch root (never executing from .cache/upstream), then
;; assert the association exists after the first 14 77defs forms. The full
;; loader's next barrier belongs to M3. Skipped where sources have not been fetched
;; (run `make sources` first).
(define pinned-root
  (build-path ".cache" "upstream" "mdlzork" "mdlzork_771212"
              "patched_confusion"))
(when (file-exists? (build-path pinned-root "77defs.mud"))
  (define scratch-root
    (make-temporary-file "mdl-atom-props-test~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     ;; 77defs.mud SHA-256 must match the pinned evidence value (computed the
     ;; same way historical_decl_test.rkt does, via the system sha256sum tool).
     (define sha-out
       (with-output-to-string
         (lambda ()
           (unless (zero? (system/exit-code
                           (string-append "sha256sum "
                                          (path->string
                                           (build-path pinned-root "77defs.mud")))))
             (error 'atom-props-test "sha256sum failed")))))
     (check-equal? (car (string-split (string-trim sha-out)))
                   "566ebcc32be9b9226dd7cefd77a517583eebab80a03f452df39e13b85eed734e")
     (for ([name '("77loadall.mud" "81prim.mud" "77defs.mud")])
       (call-with-output-file (build-path scratch-root name)
         #:exists 'truncate/replace
         (lambda (out) (write-bytes (file->bytes (build-path pinned-root name)) out))))
     (define chain-session (make-mdl-session scratch-root))
     (define entry-report
       (mdl-session-load! chain-session "77loadall.mud" #:max-expressions 1))
     (define prim-report (mdl-session-load! chain-session "81prim.mud"))
     (define defs-report
       (mdl-session-load! chain-session "77defs.mud" #:max-expressions 14))
     (check-equal? (hash-ref entry-report 'status) "PARTIAL")
     (check-equal? (hash-ref entry-report 'completed_expressions) 1)
     (check-equal? (hash-ref prim-report 'status) "PASS")
     (check-equal? (hash-ref prim-report 'completed_expressions) 8)
     (check-equal? (hash-ref defs-report 'status) "PARTIAL")
     (check-equal? (hash-ref defs-report 'completed_expressions) 14)
     (check-false (hash-ref defs-report 'failure))
     (check-equal?
      (mdl-atom-pname
       (mdl-session-call chain-session "TYPE"
                         (mdl-session-call chain-session "GET"
                                           (mdl-session-atom chain-session "RAPPLIC")
                                           (mdl-session-atom chain-session "DECL"))))
      "FORM"))
   (lambda () (with-handlers ([exn:fail? void])
                (delete-directory/files scratch-root)))))

(displayln "atom properties tests passed")
