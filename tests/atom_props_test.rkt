#lang racket/base
;; M2-D5: atom-property PUT/GET associations (issue #53).
;;
;; The reference observations are the pinned Confusion runs recorded in
;; docs/evidence/M2/atom-props-reference.json and atom-props-error-reference.json
;; (see docs/evidence/M2/ATOM-PROPS.md, interpreter SHA a29c756df5c9...7317e629).
;; `run` cases mirror recorded successes and deliberate errors, keyed by ==?
;; identity of item and indicator; the loader cases replay the pinned
;; 77loadall.mud -> 77defs.mud bytes in an isolated scratch root (never from
;; .cache/upstream) and pin the chain's new failure after 77defs.mud
;; expression 3's `<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>`. Every value
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
;; Removal via two-argument PUT; the item is echoed (association-remove-
;; two-arg-put), and the property is gone afterwards.
(check-equal? (run "<PUT RAPPLIC P 'V> <PUT RAPPLIC P>") "RAPPLIC")
(check-equal? (run "<PUT RAPPLIC P 'V> <PUT RAPPLIC P> <GET RAPPLIC P>")
              "#FALSE ()")
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

;; --- historical chain: the pinned 77loadall.mud path -----------------------
;; Copy the exact pinned bytes of 77loadall.mud, 81prim.mud, and 77defs.mud
;; into an isolated scratch root (never executing from .cache/upstream), then
;; assert the chain advances past 77defs.mud expression 3 and pin the new
;; barrier exactly. Skipped where the pinned sources have not been fetched
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
     (define chain-report (mdl-session-load! chain-session "77loadall.mud"))
     (check-equal? (hash-ref chain-report 'status) "FAIL")
     ;; D5: the atom-property PUT at 77defs.mud:5 succeeds, the NEWTYPE and
     ;; DEFMAC expressions 2-14 all load, and the chain reaches 24 completed
     ;; expressions (2 x 77loadall + 8 x 81prim + 14 x 77defs); the new
     ;; barrier is 77defs.mud expression 15, the ROOM NEWSTRUC at line 37,
     ;; whose slot handling needs the unassigned EMPTY? operator.
     (check-equal? (hash-ref chain-report 'completed_expressions) 24)
     (define failure (hash-ref chain-report 'failure))
     (check-equal? (hash-ref failure 'file) "77defs.mud")
     (check-equal? (hash-ref failure 'expression_index) 15)
     (check-equal? (hash-ref failure 'stage) "execute")
     (check-equal? (hash-ref failure 'construct) "NEWSTRUC")
     (check-equal? (hash-ref failure 'line) 37)
     (check-equal? (hash-ref failure 'column) 1)
     (check-true (string-contains? (hash-ref failure 'exception)
                                   "unassigned or non-applicable MDL operator EMPTY?")))
   (lambda () (with-handlers ([exn:fail? void])
                (delete-directory/files scratch-root)))))

(displayln "atom properties tests passed")
