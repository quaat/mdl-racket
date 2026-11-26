#lang racket/base
;; Bootstrap MDL runtime: intentionally incomplete and NOT a gameplay engine.
(require racket/mpair racket/list racket/string racket/date racket/runtime-path
         "memory.rkt" "random36.rkt" "clock.rkt")
(provide current-mdl-globals current-mdl-locals
         current-mdl-read-values mdl-register-read-value! mdl-read-value
         mdl-interpreter-version
         mdl-setg! mdl-gval mdl-define! mdl-define-subr!
         mdl-set! mdl-lval mdl-with-bindings mdl-with-aux-bindings mdl-type
         mdl-bind-function-formals mdl-call-with-activation
         mdl-with-function-scope mdl-with-prog-activation
         mdl-return mdl-again mdl-go mdl-unwind
         mdl-eval mdl-make-form mdl-form? mdl-macro? mdl-function?
         mdl-apply-form mdl-apply-computed mdl-apply-interpreted mdl-function-literal
         mdl-expand mdl-defmac! mdl-define-interpreted!
         mdl-apply mdl-list mdl-list->list
         mdl-emit-event!
         mdl-save-records mdl-save-record? mdl-save-record-sequence
         mdl-save-record-file-spec mdl-save-record-int-level
         mdl-logical-storage-stats mdl-set-logical-storage-capacity!
         mdl-recompute-entry-words current-mdl-gc-min mdl-set-used-for-test!
         mdl-make-declaration mdl-gdecl
         mdl-vector mdl-uvector mdl-data-uvector mdl-rest mdl-nth mdl-put! mdl-get mdl-putrest!
         mdl-make-terminal-channel mdl-substruc
         exn:fail:mdl-input-exhausted exn:fail:mdl-input-exhausted?
         mdl-run-host-loop mdl-host-loop-secondary-failures
         mdl-quit-signal? mdl-session-outcome? mdl-session-outcome-kind
         mdl-session-outcome-mdl-errors
         mdl-open-records mdl-open-record? mdl-open-record-mode
         mdl-open-record-file-spec mdl-open-record-status
         (struct-out mdl-read-only-file) mdl-read-only-file-relative-path
         mdl-file-channels mdl-file-length mdl-close
         make-mdl-context mdl-context? mdl-context-globals mdl-context-locals
         mdl-context-atom-space call-with-mdl-context mdl-ensure-terminal-channels!
         mdl-random-state-snapshot mdl-error-messages
         mdl-max mdl-abs mdl-image mdl-sleep mdl-time current-mdl-sleeper
         atom-space-inchan atom-space-outchan
         mdl-array? mdl-array-kind mdl-array-length form-elements mdl-base
         mdl-length mdl-equal? mdl-identical?
         mdl-segment? mdl-segment-payload mdl-make-segment mdl-splice-result
         mdl-splice-result-value mdl-splice-list mdl-splice-vector
         mdl-splice-uvector
         mdl-word mdl-word? mdl-word-bits mdl-chtype mdl-character
         mdl-truthy? mdl-atom mdl-find-atom mdl-atom? mdl-atom-pname mdl-oblist?
         mdl-string-snapshot
         current-mdl-atom-space make-mdl-atom-space mdl-root-atom
         mdl-oblist-pnames
         mdl-false mdl-false? mdl-false-payload
         decl-match-max-depth)

(struct mdl-false-value (payload) #:transparent)
(define empty-mdl-false (mdl-false-value '()))
(define (mdl-false payload)
  (define list-payload (mdl-normalize-list payload))
  (if (null? list-payload) empty-mdl-false (mdl-false-value list-payload)))
(define mdl-false? mdl-false-value?)
(define (mdl-false-payload value)
  (unless (mdl-false? value) (error 'mdl-false-payload "expected FALSE"))
  (mdl-list->list (mdl-false-value-payload value)))

(define current-mdl-globals (make-parameter (make-hasheq)))
(define current-mdl-locals (make-parameter (list (make-hasheq))))
(define current-mdl-read-values (make-parameter #f))

(define (mdl-register-read-value! value)
  (define values (current-mdl-read-values))
  (unless (hash? values)
    (error 'mdl-register-read-value! "no executable MDL reader session"))
  (define key (hash-count values))
  (hash-set! values key value)
  key)

(define (mdl-read-value key)
  (define values (current-mdl-read-values))
  (unless (and (hash? values) (hash-has-key? values key))
    (error 'mdl-read-value "read-time value is not in this MDL session"))
  (hash-ref values key))
;; kind distinguishes PROG/REPEAT frames from function activations: a bare
;; RETURN/AGAIN/GO transfer only ever targets 'prog frames, matching the
;; reference's LASTPROG lookup, while explicit activation targets may select
;; any live frame. goto is the per-item GO escape; labels maps each top-level
;; body label ATOM to its item index.
(struct mdl-activation (owner escape kind
                        [restart #:mutable] [goto #:mutable]
                        [labels #:mutable] [live? #:mutable]
                        [decl #:mutable]))
(struct mdl-tuple-value (payload))
;; Interpreted definitions carry their formals and body as runtime MDL
;; data: a MACRO binds the raw call arguments, an interpreted FUNCTION
;; binds them per the historical quoted/unquoted rules. Compiled Racket
;; closures remain the fast path for quoted-formal-free definitions.
(struct mdl-macro (formals body leading-act decl))
(struct mdl-function (formals body leading-act decl))
;; Chapter 21 registration objects and session-owned interrupt scheduler.
;; Automatic event sources, including MDL GC, remain separate later slices.
(struct mdl-iheader (owner name priority [handlers #:mutable] [enabled? #:mutable]))
(struct mdl-handler (header applicable [active? #:mutable]))
(struct mdl-interrupt-state ([level #:mutable] [pending #:mutable]))
(struct mdl-interrupt-occurrence (header arguments))
(struct mdl-error-frame (owner resume [live? #:mutable]))
;; Every host procedure stored by a compiled DEFINE (mdl-define!, called only
;; by the compiler's DEFINE path), mapped to its formal kinds. Membership is
;; also what makes such a procedure an MDL FUNCTION (ADR-0060): see
;; compiled-function? and mdl-type-name.
(define compiled-function-formals (make-weak-hasheq))
(define (compiled-function? value)
  (and (procedure? value) (hash-has-key? compiled-function-formals value)))
(struct mdl-decl-value (bindings result line column positionals) #:transparent)
(define local-declarations (make-weak-hasheq))
(define current-mdl-function-owner (make-parameter (gensym 'mdl-top-level)))
(define current-mdl-activations (make-parameter '()))
(define unassigned (gensym 'mdl-unassigned))
(define restart-token (gensym 'mdl-restart))
(define goto-token (gensym 'mdl-goto))
(struct mdl-map-transfer (kind values))
(define current-mdl-map-step (make-parameter #f))
(define current-mdl-map-leave (make-parameter #f))

;; The first argument of SETG, GVAL, GASSIGNED?, SET, LVAL, VALUE, GUNASSIGN
;; and MANIFEST, and the name given to the host value API (mdl-apply) and the
;; binding frames, must be an ATOM (#199). Any other TYPE, a STRING included,
;; is an error raised before the call touches anything: a STRING never names
;; the ATOM it spells (pinned Confusion rejects it too; evidence
;; docs/evidence/M4/I199-STRING-ATOM.md). A host that names an ATOM by a
;; Racket string converts it at its own boundary (mdl/loader.rkt uses
;; mdl-find-atom, which never interns). Runtime-internal callers pass
;; (mdl-root-atom NAME) so a user OBLIST cannot shadow or break them.
(define (binding-atom who value)
  (unless (mdl-atom? value) (error who "expected an MDL ATOM"))
  value)

;; A declaration is parsed once when its containing definition is installed.
;; Patterns stay as MDL values until then, so NEWTYPE names use that session's
;; type registry. The hash is keyed by atom identity, like local frames.
;; `origin` names the checking context in errors; the explicit DECL?
;; predicate has no source position, so it passes #f for line/column.
(define (decl-error origin line column message . args)
  (if line
      (error 'mdl-decl "~a ~a:~a: ~a" origin line column
             (apply format message args))
      (error 'mdl-decl "~a: ~a" origin (apply format message args))))

;; Nesting budget for structured declaration pattern traversal (issue #48):
;; cyclic or over-deep structures raise an explicit error naming this limit
;; instead of recursing indefinitely.
(define decl-match-max-depth 200)

(define (registered-structured-type? atom)
  (and (mdl-atom? atom)
       (member (hash-ref (atom-space-types (current-mdl-atom-space)) atom #f)
               '("LIST" "VECTOR" "UVECTOR" "TUPLE"))
       #t))

(define (decl-bracket-items bracket)
  ;; The `[...]` repetition construction reads as a VECTOR literal inside the
  ;; pattern; its items are the NTH/OPT/REST specification.
  (for/list ([i (in-range (mdl-array-length bracket))])
    (mdl-nth bracket (add1 i))))

;; Normalizes `<struc elts>`: (structure TYPE-ATOM required-pats rest-spec).
;; required-pats is a list of normalized patterns or counted (nth n pats)
;; sequences; rest-spec is #f or the
;; list of normalized patterns of the trailing `[REST pat ... pat]`.
(define (normalize-decl-structure items line column origin)
  (define head (car items))
  (define primitive-head? (mdl-form? head))
  (define type-atom
    (if primitive-head?
        (let ()
          (define head-items (form-elements head))
          (unless (and (= (length head-items) 2)
                       (eq? (car head-items) (mdl-root-atom "PRIMTYPE")))
            (decl-error origin line column "malformed declaration pattern"))
          (define normalized (normalize-decl-pattern head line column origin))
          (unless (eq? (car normalized) 'primtype)
            (decl-error origin line column
                        "structured declaration head must be PRIMTYPE"))
          (cadr normalized))
        head))
  (unless (registered-structured-type? type-atom)
    (decl-error origin line column "unsupported structured declaration TYPE ~a"
                (if (mdl-atom? type-atom) (mdl-atom-pname type-atom) type-atom)))
  (define raw-elements (cdr items))
  (when (null? raw-elements)
    ;; Confusion reads the empty `<struc>` and matches any value of the TYPE,
    ;; but the manual BNF (`elts ::= pat | pat elts | ...`) requires at least
    ;; one element pattern: recorded deviation, rejected here.
    (decl-error origin line column
                "structured declaration pattern <~a> requires at least one element pattern"
                (mdl-atom-pname type-atom)))
  (let loop ([rest raw-elements] [required '()] [rest-spec #f])
    (cond
      [(null? rest) (list (if primitive-head? 'structure-primtype 'structure)
                          type-atom (reverse required) rest-spec)]
      [(mdl-array? (car rest))
       ;; The `[...]` repetition construction: an NTH count, [OPT ...], or
       ;; [REST ...]. Only a VECTOR-typed bracket is a repetition
       ;; construction (the reference treats MDL_TYPE_VECTOR only,
       ;; mdl_decl.cpp:169); a UVECTOR bracket (![...]) is an explicit
       ;; error, never a silently-accepted repetition (PR #50 review).
       (define bracket (car rest))
       (unless (eq? (mdl-array-kind bracket) 'VECTOR)
         (decl-error origin line column
                     "declaration repetition bracket must be a VECTOR"))
       (define bracket-items (decl-bracket-items bracket))
       (define first-item (and (pair? bracket-items) (car bracket-items)))
       (define kind
         (cond [(not first-item) 'empty]
               [(and (mdl-atom? first-item)
                     (string=? (mdl-atom-pname first-item) "REST")) 'rest]
               [(and (mdl-atom? first-item)
                     (or (string=? (mdl-atom-pname first-item) "OPT")
                         (string=? (mdl-atom-pname first-item) "OPTIONAL"))) 'opt]
               [(exact-integer? first-item) 'nth]
               [else 'stray]))
       (case kind
         [(empty)
          (decl-error origin line column
                      "a repetition bracket requires at least one element pattern")]
         [(stray)
          ;; A bracket whose first item names neither a repetition keyword
          ;; nor a FIX count: report its shape, not a false NTH (PR #50
          ;; review).
          (decl-error origin line column
                      "declaration repetition bracket must start with REST, OPT, or a FIX count")]
         [(rest)
          (unless (and (null? (cdr rest)) (not rest-spec))
            (decl-error origin line column
                        "only one [REST ...] repetition is allowed, and it must be last"))
          (when (null? (cdr bracket-items))
            (decl-error origin line column
                        "[REST ...] requires at least one element pattern"))
          (loop '() required
                (map (lambda (item)
                       (normalize-decl-pattern item line column origin))
                     (cdr bracket-items)))]
         [(opt)
          ;; `[OPT pat ...]` is a later slice (the reference computes its
          ;; results but pollutes stderr with its own leftover probes).
          (decl-error origin line column "unsupported declaration pattern OPT")]
         [(nth)
          (unless (positive? first-item)
            (decl-error origin line column "NTH repetition requires a positive count"))
          (when (null? (cdr bracket-items))
            (decl-error origin line column "NTH repetition requires at least one element pattern"))
          (loop (cdr rest)
                (cons (list 'nth first-item
                            (map (lambda (item)
                                   (normalize-decl-pattern item line column origin))
                                 (cdr bracket-items)))
                      required)
                rest-spec)])]
      [else
       (loop (cdr rest)
             (cons (normalize-decl-pattern (car rest) line column origin)
                   required)
             rest-spec)])))

(define current-decl-alias-path (make-parameter '()))
;; Only attached atom-list declarations retain forward TYPE names. DECL?
;; and positional metadata continue to reject unknown names immediately.
(define current-decl-defer-unknown? (make-parameter #f))

(define (normalize-decl-pattern pattern line column
                                 [origin "DECL"] [specialty-allowed? #f])
  (cond
    [(mdl-atom? pattern)
     (cond [(string=? (mdl-atom-pname pattern) "ANY") '(any)]
           [(string=? (mdl-atom-pname pattern) "APPLICABLE") (list 'applicable pattern)]
           [(hash-has-key? (atom-space-types (current-mdl-atom-space)) pattern)
            (list 'type pattern)]
           [else
            (define associated (association-lookup pattern (mdl-root-atom "DECL")))
            (cond
              [(not associated)
               (if (current-decl-defer-unknown?)
                   (list 'unresolved pattern line column)
                   (decl-error origin line column "unknown declaration type ~a"
                               (mdl-atom-pname pattern)))]
              [else
               (when (memq pattern (current-decl-alias-path))
                 (decl-error origin line column "cyclic DECL association at ~a"
                             (mdl-atom-pname pattern)))
               (parameterize ([current-decl-alias-path
                               (cons pattern (current-decl-alias-path))])
                 (normalize-decl-pattern (cdr associated) line column origin))])])]
    [(mdl-form? pattern)
     (define items (form-elements pattern))
     (unless (and (pair? items)
                  (or (mdl-atom? (car items)) (mdl-form? (car items))))
       (decl-error origin line column "malformed declaration pattern"))
     (if (mdl-form? (car items))
         (normalize-decl-structure items line column origin)
         (case (string->symbol (mdl-atom-pname (car items)))
       [(OR)
        (when (null? (cdr items)) (decl-error origin line column "empty OR pattern"))
        (cons 'or (map (lambda (item) (normalize-decl-pattern item line column origin))
                       (cdr items)))]
       [(PRIMTYPE)
        (unless (and (= (length items) 2) (mdl-atom? (cadr items))
                     (hash-has-key? (atom-space-types (current-mdl-atom-space))
                                    (cadr items)))
          (decl-error origin line column "PRIMTYPE requires one registered type"))
        (list 'primtype (cadr items))]
       [(SPECIAL UNSPECIAL)
        (unless specialty-allowed?
          (decl-error origin line column
                      "unsupported declaration pattern ~a in this position"
                      (mdl-atom-pname (car items))))
        (unless (= (length items) 2)
          (decl-error origin line column
                      "~a requires one Pattern" (mdl-atom-pname (car items))))
        (list 'specialty (car items)
              (normalize-decl-pattern (cadr items) line column origin))]
       [(LIST VECTOR UVECTOR TUPLE)
        (normalize-decl-structure items line column origin)]
       [else
        (if (registered-structured-type? (car items))
            (normalize-decl-structure items line column origin)
            (decl-error origin line column "unsupported declaration pattern ~a"
                        (mdl-atom-pname (car items))))]))]
    [else (decl-error origin line column "unsupported declaration pattern")]))

(define (mdl-make-positional-declaration items line column)
  ;; RSUBR-style metadata attached to an interpreted FUNCTION has no
  ;; ATOM binding checks. Validate and retain it instead of treating its
  ;; leading STRING as an ATOM-list (manual §14.9; pinned Confusion).
  (unless (and (pair? items) (string? (car items))
               (string=? (car items) "VALUE") (pair? (cdr items)))
    (decl-error "DECL" line column "positional declaration must start with VALUE and a Pattern"))
  (define value-pattern (normalize-decl-pattern (cadr items) line column))
  (define required '())
  (define optional '())
  (define in-optional? #f)
  (for ([item (in-list (cddr items))])
    (cond
      [(string? item)
       (unless (and (string=? item "OPTIONAL") (not in-optional?))
         (decl-error "DECL" line column
                     "unsupported positional declaration marker ~a" item))
       (set! in-optional? #t)]
      [else
       (define pattern (normalize-decl-pattern item line column))
       (if in-optional?
           (set! optional (cons pattern optional))
           (set! required (cons pattern required)))]))
  (when (and in-optional? (null? optional))
    (decl-error "DECL" line column "OPTIONAL requires a Pattern"))
  (mdl-decl-value (make-hasheq) #f line column
                  (list value-pattern (reverse required) (reverse optional))))

(define (mdl-make-declaration payload line column)
  (define items (mdl-list->list payload))
  (if (and (pair? items) (string? (car items)))
      (mdl-make-positional-declaration items line column)
      (let ()
        (unless (and (pair? items) (even? (length items)))
          (decl-error "DECL" line column "expected atom-list/pattern pairs"))
        (define bindings (make-hasheq))
        (define result #f)
        (for ([i (in-range 0 (length items) 2)])
          (define names (list-ref items i))
          (unless (and (mpair? names) (pair? (mdl-list->list names)))
            (decl-error "DECL" line column "expected a nonempty atom list"))
          (define pattern
            (parameterize ([current-decl-defer-unknown? #t])
              (normalize-decl-pattern (list-ref items (add1 i)) line column
                                      "DECL" #t)))
          (for ([name (in-list (mdl-list->list names))])
            (unless (mdl-atom? name)
              (decl-error "DECL" line column "declaration name must be an ATOM"))
            (if (string=? (mdl-atom-pname name) "VALUE")
                (begin
                  (when result (decl-error "DECL" line column "duplicate VALUE declaration"))
                  (set! result pattern))
                (begin
                  ;; Repeated ATOM pairs retain every constraint. This is
                  ;; necessary for original BALLOON's two M declarations.
                  (hash-set! bindings name
                             (if (hash-has-key? bindings name)
                                 (let ([old (hash-ref bindings name)])
                                   (if (eq? (car old) 'all)
                                       (append old (list pattern))
                                       (list 'all old pattern)))
                                 pattern))))))
        (mdl-decl-value bindings result line column #f))))

;; Structured pattern matching (issue #48). `decl-match` returns #t on a
;; match, #f on a simple failure (DECL? then keeps the D1 (value pattern)
;; payload), or one of the structured failure records:
;;   (list 'type)               overall TYPE mismatch -> bare #FALSE ()
;;   (list 'short)              value ran out below its required prefix
;;   (list 'element elem leaf)  an element mismatch: the offending ELEMENT
;;                              and the leaf pattern to report
;; A `leaf` is the MDL value the reference carries in a `#FALSE (value
;; pattern)` element payload: the element-pattern ATOM itself, or for an
;; `<OR ...>` the last alternative that failed (mdl_decl.cpp returns the
;; last comparison's FALSE unchanged).
(define (decl-failure-leaf pattern)
  ;; Only patterns whose failure is a plain #f (simple type atoms) carry a
  ;; leaf for the (element pattern) payload; PRIMTYPE and structure
  ;; failures are records (bare #FALSE ()), so they never reach here.
  (case (car pattern)
    [(specialty) (decl-failure-leaf (caddr pattern))]
    [(type) (cadr pattern)]
    [(applicable) (cadr pattern)]
    ;; A retained attached name (#98) that failed has been defined since
    ;; (#193): its leaf is the name ATOM. Attached checks report only the
    ;; declared ATOM, never this leaf; DECL? never retains a name.
    [(unresolved) (cadr pattern)]
    [(or) (decl-failure-leaf (last (cdr pattern)))]
    [else (error 'mdl-decl "unknown normalized declaration pattern")]))

;; The elements of a structured value, read without copying: arrays by
;; mdl-nth, LIST/FALSE/TUPLE payload chains via mdl-list->list on the fly
;; (which raises the explicit "cyclic LIST" error on a self-referential
;; chain rather than looping forever).
(define (decl-structured-elements value)
  (cond
    [(mdl-tuple-value? value) (mdl-list->list (mdl-tuple-value-payload value))]
    [(mdl-array? value)
     (for/list ([i (in-range (mdl-array-length value))])
       (mdl-nth value (add1 i)))]
    [(or (null? value) (mpair? value)) (mdl-list->list value)]
    [else (error 'mdl-decl "unsupported structured value ~a" value)]))

(define (decl-match value pattern [budget decl-match-max-depth])
  (when (<= budget 0)
    (error 'mdl-decl "declaration pattern nesting exceeds traversal limit ~a"
           decl-match-max-depth))
  (case (car pattern)
    [(specialty) (decl-match value (caddr pattern) budget)]
    [(unresolved)
     ;; Issue #193 (amendment to the #98 ADR): a retained attached TYPE name
     ;; that is still undefined at this check -- no registered TYPE and no
     ;; DECL association -- is not enforced at this position, as in pinned
     ;; Confusion. A name defined since is resolved strictly, as before.
     ;; Since #196 attached checks are evaluated only for the test-only
     ;; recorder (check-declared!); DECL? never retains a name.
     (if (and (not (hash-has-key? (atom-space-types (current-mdl-atom-space))
                                  (cadr pattern)))
              (not (association-lookup (cadr pattern) (mdl-root-atom "DECL"))))
         #t
         (decl-match value
                     (parameterize ([current-decl-defer-unknown? #f])
                       (normalize-decl-pattern (cadr pattern)
                                               (caddr pattern) (cadddr pattern)))
                     budget))]
    [(all)
     (let loop ([constraints (cdr pattern)])
       (cond [(null? constraints) #t]
             [else
              (define result (decl-match value (car constraints) budget))
              (if (eq? result #t)
                  (loop (cdr constraints))
                  result)]))]
    [(any) #t]
    [(applicable)
     (or (mdl-function? value) (mdl-macro? value)
         (procedure? value) (exact-integer? value))]
    [(type) (eq? (mdl-type value) (cadr pattern))]
    ;; The reference's PRIMTYPE check returns the plain FALSE, so a failing
    ;; <PRIMTYPE ...> surfaces as a bare #FALSE () — the (list 'type)
    ;; record — wherever it fails (PR #50 review).
    [(primtype)
     (if (eq? (mdl-primtype value) (mdl-typeprim (cadr pattern))) #t (list 'type))]
    [(or)
     ;; Any alternative may match; on failure the reference keeps the last
     ;; comparison's result (the last alternative's record for structured
     ;; children, a plain #f for simple ones). Alternatives consume
     ;; traversal budget like structure levels (PR #50 review).
     (let loop ([alts (cdr pattern)] [failed #f])
       (cond [(null? alts) failed]
             [else
              (define m (decl-match value (car alts) (sub1 budget)))
              (cond [(eq? m #t) #t]
                    [else (loop (cdr alts) m)])]))]
    [(structure structure-primtype)
     (decl-match-structure value pattern (sub1 budget))]
    [else (error 'mdl-decl "unknown normalized declaration pattern")]))

;; `<struc elts>` matching: the value's MDL TYPE must equal the pattern's
;; type ATOM (a STRING is LIST-primtype but is not a LIST here), then each
;; required element pattern applies positionally and the trailing
;; `[REST pat ...]` (if any) repeats cyclically over all remaining elements.
;; Undeclared elements beyond the declared patterns are allowed (manual
;; chapter 14), and an empty value fails only a nonempty required prefix.
;; The required prefix is walked in place: a prefix-only pattern matches
;; the prefix of a cyclic LIST like the reference, which walks by
;; NTH/REST incrementally. Only the REST tail materializes through
;; mdl-list->list, whose cycle check is the documented safety deviation
;; (the reference's REST loop would not terminate on a cyclic value).
;; Arrays cannot be cyclic; their element references are read by index.
(define (decl-match-structure value pattern budget)
  (define type-atom (cadr pattern))
  (define type-matches?
    (if (eq? (car pattern) 'structure-primtype)
        (eq? (mdl-primtype value) (mdl-typeprim type-atom))
        (eq? (mdl-type value) type-atom)))
  (if (not type-matches?)
      (list 'type)
      (let ([base (mdl-base value)]
            [required (caddr pattern)]
            [rest-spec (cadddr pattern)])
        (cond
          [(mdl-tuple-value? base)
           (decl-match-chain (mdl-tuple-value-payload base) required rest-spec budget)]
          [(or (null? base) (mpair? base))
           (decl-match-chain base required rest-spec budget)]
          [(mdl-array? base)
           (decl-match-sequence
            (for/list ([i (in-range (mdl-array-length base))])
              (mdl-nth base (add1 i)))
            required rest-spec budget)]
          [else (error 'mdl-decl "unsupported structured value")]))))

;; Unfold a counted sequence only as its corresponding value elements are
;; consumed. This bounds work for an enormous count and a short value.
(define (decl-next-required pats)
  (cond
    [(null? pats) (values #f '())]
    [(eq? (caar pats) 'nth)
     (define entry (car pats))
     (define count (cadr entry))
     (define sequence (caddr entry))
     (decl-next-required
      (append sequence
              (if (> count 1) (list (list 'nth (sub1 count) sequence)) '())
              (cdr pats)))]
    [else (values (car pats) (cdr pats))]))

;; Required-prefix walking over a LIST-primtype chain consumes one cell at a
;; time, so a cyclic chain is bounded when there is no REST tail.
(define (decl-match-chain chain required rest-spec budget)
  (let loop ([cursor chain] [pats required])
    (define-values (pat remaining) (decl-next-required pats))
    (cond
      [(not pat)
       (if rest-spec
           (decl-match-rest (mdl-list->list cursor) rest-spec budget)
           #t)]
      [(null? cursor) (list 'short)]
      [else
       (define m (decl-match (mcar cursor) pat budget))
       (cond
         [(eq? m #t) (loop (mcdr cursor) remaining)]
         [(eq? m #f) (list 'element (mcar cursor) (decl-failure-leaf pat))]
         [else m])])))

;; Required-prefix matching over an extracted array-element sequence
;; (arrays are finite; the reference walks them by NTH similarly).
(define (decl-match-sequence elements required rest-spec budget)
  (let loop ([els elements] [pats required])
    (define-values (pat remaining) (decl-next-required pats))
    (cond
      [(not pat)
       (if (or (not rest-spec) (null? els))
           #t
           (decl-match-rest els rest-spec budget))]
      [(null? els) (list 'short)]
      [else
       (define m (decl-match (car els) pat budget))
       (cond
         [(eq? m #t) (loop (cdr els) remaining)]
         [(eq? m #f) (list 'element (car els) (decl-failure-leaf pat))]
         [else m])])))

;; `[REST pat ... pat]` repetition: the sequence restarts after each period
;; (the recorded rest-multi-pattern and Confusion's REST loop), and the
;; value may end at any point.
(define (decl-match-rest els pats budget)
  (let loop ([rest els] [i 0])
    (cond
      [(null? rest) #t]
      [else
       (define pat (list-ref pats (remainder i (length pats))))
       (define m (decl-match (car rest) pat budget))
       (cond
         [(eq? m #t) (loop (cdr rest) (add1 i))]
         [(eq? m #f) (list 'element (car rest) (decl-failure-leaf pat))]
         [else m])])))

(define (matches-decl? value pattern [budget decl-match-max-depth])
  (eq? (decl-match value pattern budget) #t))

;; The explicit chapter 14 predicate checks one value against one pattern
;; with the same normalization as attached declarations. Pinned Confusion
;; (declaration-pattern-reference.json) returns T on a match, a bare #FALSE
;; () on an overall TYPE mismatch, and #FALSE carrying the offending ELEMENT
;; and its element pattern on a structured element mismatch; simple-pattern
;; failures keep the D1 #FALSE (value pattern) payload.
;;
;; D5 (issue #53): when the PATTERN argument is an ATOM carrying a DECL
;; association (the 77defs.mud:5 NEWTYPE-annotation mechanism), the property
;; value is the actual pattern (pinned mdl_decl.cpp:66), so <DECL? <CHTYPE 1
;; NOFFSET> RAPPLIC> matches RAPPLIC's <OR ATOM FALSE NOFFSET> property and
;; the miss payload carries the resolved pattern's leaf: #FALSE (3 NOFFSET)
;; (declq-consults-atom-decl). Attached #DECL checking consults DECL
;; associations too (#98, #193: normalize-decl-pattern and the (unresolved)
;; case of decl-match). SETG ignores them (the recorded
;; setg-ignores-atom-decl case, consistent with D1's non-enforcement).
(define (mdl-decl? value pattern)
  (define resolved?
    (and (mdl-atom? pattern)
         (not (hash-has-key? (atom-space-types (current-mdl-atom-space)) pattern))
         (association-lookup pattern (mdl-root-atom "DECL"))))
  (define normalized
    (normalize-decl-pattern pattern #f #f "DECL?"))
  (define result (decl-match value normalized decl-match-max-depth))
  (cond
    [(eq? result #t) (mdl-root-atom "T")]
    [(eq? result #f)
     (if resolved?
         (mdl-false (list value (decl-failure-leaf normalized)))
         (mdl-false (list value pattern)))]
    [(eq? (car result) 'element)
     (mdl-false (list (cadr result) (caddr result)))]
    [else (mdl-false '())]))

;; The attached-declaration check point (manual chapter 14; the #98 ADR, its
;; #193 amendment and its #196 amendment). KIND says which binding it is:
;; argument, optional, rest, aux (a FUNCTION's "AUX"), prog-aux (a PROG/REPEAT
;; auxiliary), name (an activation formal), set (SET of a declared local) or
;; value (the result).
;;
;; M4 #196 (maintainer decision 2026-11-26; DECISIONS.md, SEMANTICS "Amendment:
;; attached declarations are not enforced"): attached #DECLs are not enforced,
;; matching pinned Confusion. Without the host-only, test-only decl-violation
;; recorder (every production host) nothing is evaluated here: the value is
;; returned unchanged and no Pattern is matched, so nothing matching could raise
;; is raised either. With the recorder (SEMANTICS "Diagnostic-only:
;; attached-declaration violation recorder") the check is evaluated exactly as
;; before #196: a value that does not match is reported once and proceeds, and
;; an error raised while matching (a later DECL association whose target is
;; unknown or cyclic, the traversal limit) still raises in that host. The
;; recorder read below is its only read site. Definition-time validation of the
;; #DECL (mdl-make-declaration) and every other declaration path (DECL?,
;; GDECL/SETG, positional declarations, CHTYPE) are unchanged and strict.
(define (check-declared! decl name value [kind 'value])
  (define recorder (atom-space-decl-violation-recorder (current-mdl-atom-space)))
  (when (and recorder decl (not (eq? value unassigned)))
    (define pattern (if (eq? name 'VALUE)
                        (mdl-decl-value-result decl)
                        (hash-ref (mdl-decl-value-bindings decl) name #f)))
    (when (and pattern (not (matches-decl? value pattern)))
      (define binding (if (eq? name 'VALUE) "VALUE" (mdl-atom-pname name)))
      (recorder (decl-violation-info decl binding kind pattern value))))
  value)

(define (check-frame-binding! frame atom value kind)
  (check-declared! (hash-ref local-declarations frame #f) atom value kind))

(define (check-result! decl value)
  (check-declared! decl 'VALUE value 'value))

;; --- diagnostic only (M4 #196): the recorder's description of a violation ---
;; Built only when a recorder is present. Keys: binding (PNAME string, or
;; "VALUE"), kind (symbol, as check-declared!), pattern (the normalized
;; Pattern rendered as MDL text; a name declared twice renders its
;; constraints joined by " & "), value-type (TYPE PNAME), value-summary (a
;; bounded rendering: FIX, FLOAT, ATOM PNAME, a STRING up to 40 characters,
;; "#FALSE ()"; otherwise "#TYPE"), value (the value itself, for the host),
;; line and column (of the #DECL in its source file).
(define (decl-violation-info decl binding kind pattern value)
  (hasheq 'binding binding 'kind kind
          'pattern (render-normalized-decl pattern)
          'value-type (mdl-atom-pname (mdl-type value))
          'value-summary (decl-violation-value-summary value)
          'value value
          'line (mdl-decl-value-line decl) 'column (mdl-decl-value-column decl)))

(define (decl-violation-value-summary value)
  (cond
    [(exact-integer? value) (number->string value)]
    [(real? value) (number->string value)]
    [(mdl-atom? value) (mdl-atom-pname value)]
    [(string? value)
     (format "~s" (if (> (string-length value) 40)
                      (string-append (substring value 0 40) "...")
                      value))]
    [(and (mdl-false-value? value) (null? (mdl-false-value-payload value))) "#FALSE ()"]
    [else (string-append "#" (mdl-atom-pname (mdl-type value)))]))

(define (render-normalized-decl pattern)
  (define (pname a) (mdl-atom-pname a))
  (define (join items) (string-join (map render-normalized-decl items) " "))
  (define (render-structure head required rest-spec)
    (string-append
     "<" head
     (apply string-append
            (for/list ([p (in-list required)])
              (string-append
               " "
               (if (eq? (car p) 'nth)
                   (format "[~a ~a]" (cadr p) (join (caddr p)))
                   (render-normalized-decl p)))))
     (if rest-spec (format " [REST ~a]" (join rest-spec)) "")
     ">"))
  (case (car pattern)
    [(any) "ANY"]
    [(type applicable unresolved) (pname (cadr pattern))]
    [(primtype) (format "<PRIMTYPE ~a>" (pname (cadr pattern)))]
    [(or) (format "<OR ~a>" (join (cdr pattern)))]
    [(specialty) (format "<~a ~a>" (pname (cadr pattern))
                         (render-normalized-decl (caddr pattern)))]
    [(all) (string-join (map render-normalized-decl (cdr pattern)) " & ")]
    [(structure) (render-structure (pname (cadr pattern)) (caddr pattern) (cadddr pattern))]
    [(structure-primtype)
     (render-structure (format "<PRIMTYPE ~a>" (pname (cadr pattern)))
                       (caddr pattern) (cadddr pattern))]
    [else (error 'mdl-decl "unknown normalized declaration pattern")]))

;; The LVAL of an ATOM is its innermost binding in the dynamic frame chain,
;; ending in the session's top-level frame. ROOT OBLIST is the one ATOM with
;; a default top-level value: the session's startup search list, used only
;; when no frame (top level included) binds it. A binding that exists but
;; is unassigned stays unassigned; it never falls back to the default.
(define (local-option atom)
  (let loop ([frames (current-mdl-locals)])
    (cond [(null? frames)
           (define space (current-mdl-atom-space))
           (if (eq? atom (hash-ref (atom-space-internal space) "OBLIST"))
               (atom-space-lookup space)
               unassigned)]
          [(hash-has-key? (car frames) atom) (hash-ref (car frames) atom)]
          [else (loop (cdr frames))])))

;; The one authoritative atom search path (manual 15.3: READ uses the LVAL
;; of OBLIST). There is no cached copy: PROG/AUX/formal bindings, SET,
;; BLOCK and ENDBLOCK all act on the ordinary LVAL, so every exit from a
;; binding frame (normal, RETURN/AGAIN, ERROR, host exception) restores it
;; through the frame parameterization itself.
(define (current-lookup-path who)
  (define value (local-option (mdl-root-atom "OBLIST")))
  (when (eq? value unassigned)
    (error who "unassigned MDL local OBLIST: no atom search path"))
  (validate-oblist-lookup who value))

(define (mdl-lval name)
  (define atom (binding-atom 'mdl-lval name))
  (define result (local-option atom))
  (if (eq? result unassigned)
      (error 'mdl-lval "unassigned MDL local ~a" (mdl-atom-pname atom))
      result))

(define (mdl-set! name value)
  (define atom (binding-atom 'mdl-set name))
  ;; Strict slice: SET of OBLIST requires a valid search list now rather
  ;; than failing at the next read (Confusion accepts it and fails later).
  (when (eq? atom (mdl-root-atom "OBLIST"))
    (validate-oblist-lookup 'mdl-set value))
  (define frames (current-mdl-locals))
  (define target
    (or (for/or ([frame (in-list frames)])
          (and (hash-has-key? frame atom) frame))
        (last frames)))
  (check-frame-binding! target atom value 'set)
  (hash-set! target atom value)
  value)

(define (mdl-with-bindings pairs thunk)
  (define frame (make-hasheq))
  (for ([entry (in-list pairs)])
    (define atom (binding-atom 'mdl-with-bindings (car entry)))
    (when (hash-has-key? frame atom)
      (error 'mdl-with-bindings "duplicate local parameter"))
    (hash-set! frame atom (cdr entry)))
  (parameterize ([current-mdl-locals (cons frame (current-mdl-locals))])
    (thunk)))

;; Function application for the historical formal sections. Confusion's
;; mdl_bind_args processes the formal list at call time in order, so the
;; specs list is ordered: required and OPTIONAL entries consume arguments,
;; one ARGS/TUPLE rest entry collects the remainder, AUX entries bind
;; locals, and a NAME/ACT entry binds the function's own activation. Default
;; expressions evaluate in the growing frame; an unsupplied OPTIONAL or bare
;; AUX binding stays unassigned, like a PROG auxiliary. TUPLE wraps its
;; arguments in a TUPLE-typed value; ARGS yields a LIST. Error names follow
;; the observed reference behavior.
(define (mdl-bind-function-formals fn specs args activation-frame thunk [decl #f])
  (define frame (make-hasheq))
  (when decl (hash-set! local-declarations frame decl))
  (define (bind! atom value kind)
    (require-atom 'mdl-bind-function-formals atom)
    (when (hash-has-key? frame atom)
      (error 'mdl-bind-function-formals
             "BAD-ARGUMENT-LIST: duplicate formal argument"))
    (check-frame-binding! frame atom value kind)
    (hash-set! frame atom value))
  (define (spec-value spec)
    (define default (third spec))
    (if default (default) unassigned))
  (parameterize ([current-mdl-locals (cons frame (current-mdl-locals))])
    (define remaining args)
    (for ([spec (in-list specs)])
      (case (first spec)
        [(required)
         (when (null? remaining)
           (error 'mdl-bind-function-formals
                  "TOO-FEW-ARGUMENTS-SUPPLIED for ~a" (mdl-atom-pname fn)))
         (bind! (second spec) (car remaining) 'argument)
         (set! remaining (cdr remaining))]
        [(optional)
         (if (null? remaining)
             (bind! (second spec) (spec-value spec) 'optional)
             (begin
               (bind! (second spec) (car remaining) 'optional)
               (set! remaining (cdr remaining))))]
        [(rest)
         (define kind (second spec))
         (bind! (third spec)
                (if (null? remaining)
                    (if (eq? kind 'tuple) (mdl-tuple-value '()) '())
                    (if (eq? kind 'tuple)
                        (mdl-tuple-value (apply mdl-list remaining))
                        (apply mdl-list remaining)))
                'rest)
         (set! remaining '())]
        [(aux) (bind! (second spec) (spec-value spec) 'aux)]
        [(name)
         (unless activation-frame
           (error 'mdl-bind-function-formals
                  "NAME formal without a function activation"))
         (bind! (second spec) activation-frame 'name)]
        [else (error 'mdl-bind-function-formals
                     "unknown formal specification ~a" spec)]))
    (unless (null? remaining)
      (error 'mdl-bind-function-formals
             "TOO-MANY-ARGUMENTS-SUPPLIED for ~a" (mdl-atom-pname fn)))
    (check-result! decl (thunk))))

;; A DEFINE with an activation formal (a leading ATOM or a "NAME"/"ACT"
;; marker) creates a live activation for its own invocation. Explicit
;; RETURN/AGAIN may target it from any depth, including called functions;
;; AGAIN re-runs the body without re-binding formals. The frame exists
;; before auxiliary initialization, so RETURN during an AUX initializer
;; exits the whole call.
(define (mdl-call-with-activation fn specs args body-thunk [decl #f])
  (let/ec escape
    (define frame (mdl-activation (current-mdl-function-owner) escape 'function
                                 #f #f #f #t decl))
    (dynamic-wind
      void
      (lambda ()
        (parameterize ([current-mdl-activations
                        (cons frame (current-mdl-activations))])
          (mdl-bind-function-formals fn specs args frame
            (lambda ()
              (let body-loop ()
                (define result
                  (let/ec restart
                    (set-mdl-activation-restart! frame restart)
                    (body-thunk)))
                (if (eq? result restart-token)
                    (body-loop)
                    result)))
            decl)))
      (lambda () (set-mdl-activation-live?! frame #f)))))

(define (mdl-with-aux-bindings specs thunk [decl #f])
  (define frame (make-hasheq))
  (when decl (hash-set! local-declarations frame decl))
  (parameterize ([current-mdl-locals (cons frame (current-mdl-locals))])
    (for ([entry (in-list specs)])
      (define atom (binding-atom 'mdl-with-aux-bindings (car entry)))
      (when (hash-has-key? frame atom)
        (error 'mdl-with-aux-bindings "duplicate auxiliary binding"))
      ;; Evaluate before installing this binding. Earlier auxiliary bindings
      ;; are visible, while this initializer may still see an outer binding.
      (define initializer (cdr entry))
      (define value (if initializer (initializer) unassigned))
      (check-frame-binding! frame atom value 'prog-aux)
      (hash-set! frame atom value))
    (thunk)))

(define (mdl-with-function-scope thunk)
  (parameterize ([current-mdl-function-owner (gensym 'mdl-function)])
    (thunk)))

;; A PROG or REPEAT body runs as a vector of items: top-level label ATOMs
;; are skipped in normal flow and index the GO targets; expression items
;; are thunks. The last expression value is the frame's normal result.
;; AGAIN restarts the body without re-binding auxiliaries; GO transfers
;; to the item after a label in the nearest owned PROG/REPEAT.
(define (mdl-with-prog-activation items [specs '()] [repeat? #f] [name #f] [decl #f])
  (unless (vector? items)
    (error 'mdl-with-prog-activation "expected a vector of body items"))
  (define expr-count
    (for/sum ([item (in-vector items)])
      (if (eq? (car item) 'expr) 1 0)))
  (unless (positive? expr-count)
    (error 'mdl-with-prog-activation "PROG or REPEAT requires a body expression"))
  (let/ec escape
    (define frame (mdl-activation (current-mdl-function-owner) escape 'prog
                                 #f #f #f #t decl))
    (dynamic-wind
      void
      (lambda ()
        (parameterize ([current-mdl-activations
                        (cons frame (current-mdl-activations))])
          (define labels (make-hasheq))
          (for ([item (in-vector items)] [i (in-naturals)])
            (when (eq? (car item) 'label)
              (hash-set! labels (cdr item) i)))
          (set-mdl-activation-labels! frame labels)
          (define (run-items)
            (let loop ([i 0] [last #f])
              (cond
                [(>= i (vector-length items)) last]
                [(eq? (car (vector-ref items i)) 'label) (loop (add1 i) last)]
                [else
                 (define value
                   (let/ec goto-ec
                     (set-mdl-activation-goto! frame goto-ec)
                     ((cdr (vector-ref items i)))))
                 (if (and (pair? value) (eq? (car value) goto-token))
                     (loop (cdr value) last)
                     (loop (add1 i) value))])))
          (define (run)
            (mdl-with-aux-bindings
             specs
             (lambda ()
               (let outer ()
                 (define result
                   (let/ec restart
                     (set-mdl-activation-restart! frame restart)
                     (run-items)))
                 (if (or repeat? (eq? result restart-token))
                     (outer)
                     (check-result! decl result))))
             decl))
          (if name
              (mdl-with-bindings (list (cons name frame)) run)
              (run))))
      (lambda () (set-mdl-activation-live?! frame #f)))))

(define (current-mdl-activation)
  (for/first ([frame (in-list (current-mdl-activations))]
              #:when (and (eq? (mdl-activation-kind frame) 'prog)
                          (eq? (mdl-activation-owner frame)
                               (current-mdl-function-owner))))
    frame))

(define implicit-activation (gensym 'mdl-implicit-activation))

(define (resolve-activation who supplied)
  (if (eq? supplied implicit-activation)
      (let ([target (current-mdl-activation)])
        (unless (and target (mdl-activation-live? target))
          (error who "no active PROG or REPEAT in current function"))
        target)
      (begin
        (unless (mdl-activation? supplied)
          (error who "expected ACTIVATION target"))
        (unless (and (mdl-activation-live? supplied)
                     (memq supplied (current-mdl-activations)))
          (error who "inactive ACTIVATION target"))
        supplied)))

(define (mdl-return value [supplied implicit-activation])
  (define target (resolve-activation 'mdl-return supplied))
  (check-result! (mdl-activation-decl target) value)
  ((mdl-activation-escape target) value))

(define (mdl-again [supplied implicit-activation])
  (define target (resolve-activation 'mdl-again supplied))
  (unless (mdl-activation-restart target)
    (error 'mdl-again "ACTIVATION body restart is unavailable"))
  ((mdl-activation-restart target) restart-token))

;; GO resumes just before the expression following a top-level label ATOM
;; in the nearest surrounding PROG or REPEAT of the current function. The
;; pinned Confusion has no GO or TAG implementation; the semantics follow
;; the MDL manual, chapter 10.
(define (mdl-go label)
  (unless (mdl-atom? label)
    (error 'mdl-go "GO expects an ATOM label; TAG values are not supported"))
  (define target (current-mdl-activation))
  (unless (and target (mdl-activation-live? target))
    (error 'mdl-go "no active PROG or REPEAT in current function"))
  (define index
    (hash-ref (mdl-activation-labels target) label
              (lambda ()
                (error 'mdl-go "GO label not found: ~a" (mdl-atom-pname label)))))
  (unless (mdl-activation-goto target)
    (error 'mdl-go "GO target position is not active"))
  ((mdl-activation-goto target) (cons goto-token index)))

;; UNWIND evaluates its first expression and returns its value. If an MDL
;; transfer of control (RETURN, AGAIN, GO, MAPLEAVE/MAPRET/MAPSTOP, also
;; from a handler) leaves the first expression through this point, the
;; cleanup expression runs first in the environment of the UNWIND call, its
;; value is ignored, and the transfer completes. Normal completion never
;; runs the cleanup. A raised error (an unresolved MDL ERROR, a host strict
;; error, or any other Racket raise, including a future QUIT signal) is not
;; an MDL transfer: MDL enters an error level on the intact stack and only
;; ERRET/RETRY strip it (manual 16.2, 16.4, 16.6; QUIT 23.3). This runtime
;; has no error level, so the raise propagates unchanged and the cleanup
;; does not run (ADR-0051, issue #139). The exception handler only marks the
;; raise and returns, so the next enclosing handler receives the original
;; value. A raise caught inside the body never reaches this handler.
(define (mdl-unwind std-thunk erre-thunk)
  (define completed-normally? #f)
  (define raised-through? #f)
  (dynamic-wind
    void
    (lambda ()
      (define value
        (call-with-exception-handler
         (lambda (raised) (set! raised-through? #t) raised)
         std-thunk))
      (set! completed-normally? #t)
      value)
    (lambda ()
      (unless (or completed-normally? raised-through?)
        (erre-thunk)
        (void)))))

;; ---------------------------------------------------------------------------
;; SEGMENT values (MDL chapter 7, `!` splice notation).
;;
;; `!.ATOM`, `!,ATOM`, and `!<FORM...!>` denote a SEGMENT object whose
;; payload is the object's data; evaluating it inside a structure builds the
;; structure by inserting the payload value's ELEMENTS (pinned Confusion
;; macros.cpp:2704-2749). In data positions (quoted structures, raw
;; interpreted arguments, compiled data) the payload stays unevaluated, and
;; a compiled splice evaluates to a splice marker carrying its already
;; evaluated payload value. Segment objects that are merely the VALUE of a
;; plain element are stored, not re-spliced.
;;
;; SEGMENT is one built-in TYPE with PRIMTYPE LIST (ADR-0056; SEMANTICS
;; "M4 S2"): the reader's `!<...>`/`!.X`/`!,X` and `<CHTYPE x SEGMENT>` are
;; the same object, a TYPE tag over the LIST cells of its elements, exactly
;; like a FORM. Its payload is a FORM view over the same cells.
(struct mdl-splice-result (value line column) #:transparent)

;; Identity test against the CURRENT atom space's ROOT SEGMENT, exactly as
;; mdl-form? tests ROOT FORM (S2 independent review): a value from another
;; session is never treated as a splice here, and a user TYPE atom that is
;; merely named SEGMENT is never one.
(define (mdl-segment? value)
  (and (mdl-typed-value? value)
       (eq? (mdl-typed-value-type value) (mdl-root-atom "SEGMENT"))))

(define (mdl-segment-payload segment)
  (mdl-make-form (mdl-typed-value-value segment)))

;; The reader's constructor: PAYLOAD is the FORM read after `!`; the source
;; position is not kept (it is never shown in a message).
(define (mdl-make-segment payload line column)
  (unless (mdl-form? payload)
    (error 'mdl-make-segment "SEGMENT payload must be a FORM"))
  (mdl-typed-value (mdl-root-atom "SEGMENT") (mdl-typed-value-value payload)))

(define (mdl-segment-standalone-error)
  (error 'mdl-segment
         "ILLEGAL-SEGMENT: Attempt to evaluate segment outside structured type"))

;; The elements one SEGMENT contributes, mirroring the reference's structure
;; walker (macros.cpp:2447-2470): LIST, FALSE, FORM, and TUPLE payloads,
;; VECTORs and UVECTORs by element, and STRINGs as CHARACTER values. FALSE
;; and TUPLE payloads and every LIST-primtype chain are stored as mpairs,
;; so they convert to Racket lists here; NEWTYPE-wrapped (typed) structures
;; unwrap to their base before matching, like the reference's walker.
(define (segment-elements value)
  (cond
    [(mdl-typed-value? value) (segment-elements (mdl-base value))]
    [(mdl-false? value) (mdl-list->list (mdl-false-value-payload value))]
    [(mdl-form? value) (form-elements value)]
    [(mdl-tuple-value? value) (mdl-list->list (mdl-tuple-value-payload value))]
    [(or (null? value) (mpair? value)) (mdl-list->list value)]
    [(mdl-array? value)
     (for/list ([i (in-range (mdl-array-length value))])
       (mdl-nth value (add1 i)))]
    [(mdl-string? value)
     (for/list ([index (in-range (mdl-string-length value))])
       (mdl-character (mdl-string-ref value index)))]
    [else
     (error 'mdl-segment
            "ILLEGAL-SEGMENT: Segment evaluated to nonstructured type")]))

;; A trailing SEGMENT whose value has PRIMTYPE LIST shares its storage in
;; LIST construction instead of being copied (macros.cpp:2716-2724).
(define (segment-shares-tail? value)
  (eq? (mdl-primtype value) (mdl-root-atom "LIST")))
(define (segment-tail-chain value)
  (mdl-list-head value 'mdl-splice-list))

;; Assemble a LIST from ordered construction units. `shared`, when given, is
;; the trailing LIST-primtype payload whose cells are linked in place.
(define (finish-list items shared)
  (cond
    [(not shared) (apply mdl-list items)]
    [(null? items) (segment-tail-chain shared)]
    [else
     (define chain (apply mdl-list items))
     (set-mcdr! (mdl-list-tail chain (sub1 (length items)) 'mdl-splice-list)
                (segment-tail-chain shared))
     chain]))

;; Compiled construction: one thunk per element, evaluated in order; thunk
;; results are plain values or splice markers. Only the final marker may
;; share a LIST-primtype tail; other marker payloads contribute copied
;; elements.
(define (build-spliced-list units)
  (let loop ([rest units] [acc '()])
    (cond
      [(null? rest) (finish-list acc #f)]
      [else
       (define unit ((car rest)))
       (cond
         [(null? (cdr rest))
          (cond
            [(mdl-splice-result? unit)
             (define value (mdl-splice-result-value unit))
             (if (segment-shares-tail? value)
                 (finish-list acc value)
                 (finish-list (append acc (segment-elements value)) #f))]
            [else (finish-list (append acc (list unit)) #f)])]
         [(mdl-splice-result? unit)
          (loop (cdr rest)
                (append acc (segment-elements (mdl-splice-result-value unit))))]
         [else (loop (cdr rest) (append acc (list unit)))])])))

;; Interpreted construction over raw element data: a SEGMENT object in
;; element position is a splice (its payload evaluates here, in order); a
;; plain element evaluates and a segment-valued result is stored as itself.
(define (build-eval-list items)
  (let loop ([rest items] [acc '()])
    (cond
      [(null? rest) (finish-list acc #f)]
      [else
       (define item (car rest))
       (cond
         [(null? (cdr rest))
          (cond
            [(mdl-segment? item)
             (define value (mdl-eval (mdl-segment-payload item)))
             (if (segment-shares-tail? value)
                 (finish-list acc value)
                 (finish-list (append acc (segment-elements value)) #f))]
            [else (finish-list (append acc (list (mdl-eval item))) #f)])]
         [(mdl-segment? item)
          (loop (cdr rest)
                (append acc (segment-elements (mdl-eval (mdl-segment-payload item)))))]
         [else (loop (cdr rest) (append acc (list (mdl-eval item))))])])))

;; VECTOR and UVECTOR construction always copies splice elements.
(define (build-spliced-vector units)
  (define (unit-items rest acc)
    (if (null? rest)
        acc
        (let ([unit ((car rest))])
          (unit-items (cdr rest)
                      (if (mdl-splice-result? unit)
                          (append acc (segment-elements (mdl-splice-result-value unit)))
                          (append acc (list unit)))))))
  (apply mdl-vector (unit-items units '())))

(define (build-eval-vector items)
  (define (item-values rest acc)
    (if (null? rest)
        acc
        (let ([item (car rest)])
          (item-values (cdr rest)
                       (if (mdl-segment? item)
                           (append acc (segment-elements (mdl-eval (mdl-segment-payload item))))
                           (append acc (list (mdl-eval item))))))))
  (apply mdl-vector (item-values items '())))

;; A UVECTOR requires uniform element TYPEs. Confusion reports
;; TYPES-DIFFER-IN-UNIFORM-VECTOR when a later element differs from the
;; element TYPE fixed by the first (macros.cpp:2823-2835).
(define (uniform-uvector items)
  (if (null? items)
      (new-mdl-array 'UVECTOR (vector) 0 0 #f)
      (let ([element-type (mdl-type (car items))])
        (for ([value (in-list items)])
          (unless (eq? (mdl-type value) element-type)
            (error 'mdl-splice-uvector
                   "TYPES-DIFFER-IN-UNIFORM-VECTOR: UVECTOR elements must have one permitted TYPE")))
        (when (string=? (mdl-type-name (car items)) "STRING")
          (error 'mdl-splice-uvector
                 "UVECTOR elements must have one permitted TYPE"))
        (new-mdl-array 'UVECTOR (list->vector items) 0 (length items) element-type))))

(define (build-spliced-uvector units)
  (define (unit-items rest acc)
    (if (null? rest)
        acc
        (let ([unit ((car rest))])
          (unit-items (cdr rest)
                      (if (mdl-splice-result? unit)
                          (append acc (segment-elements (mdl-splice-result-value unit)))
                          (append acc (list unit)))))))
  (uniform-uvector (unit-items units '())))

(define (build-eval-uvector items)
  (define (item-values rest acc)
    (if (null? rest)
        acc
        (let ([item (car rest)])
          (item-values (cdr rest)
                       (if (mdl-segment? item)
                           (append acc (segment-elements (mdl-eval (mdl-segment-payload item))))
                           (append acc (list (mdl-eval item))))))))
  (uniform-uvector (item-values items '())))

;; Compiled constructors: variadic over unit thunks, evaluated left to right.
(define (mdl-splice-list . units) (build-spliced-list units))
(define (mdl-splice-vector . units) (build-spliced-vector units))
(define (mdl-splice-uvector . units) (build-spliced-uvector units))

;; Expand SEGMENT objects while a call's raw arguments are read, left to
;; right, like the reference's LIST assembly of a SUBR call: spliced
;; elements are values and are never re-evaluated. Plain data items stay
;; raw for formals that evaluate (or quote) them.
(define (expand-arg-items raw-args)
  (define items
    (if (or (null? raw-args) (mpair? raw-args))
        (mdl-list->list raw-args)
        raw-args))
  (let loop ([rest items] [acc '()])
    (cond
      [(null? rest) (reverse acc)]
      [(mdl-segment? (car rest))
       (define value (mdl-eval (mdl-segment-payload (car rest))))
       (loop (cdr rest)
             (foldl (lambda (element result)
                      (cons (cons 'value element) result))
                    acc
                    (reverse (segment-elements value))))]
      [else (loop (cdr rest) (cons (cons 'raw (car rest)) acc))])))

;; ---------------------------------------------------------------------------
;; Runtime evaluation, FORM values, and macro expansion.
;;
;; Confusion evaluates every object dynamically; this runtime needs the
;; same power for macro expansion results, interpreted definitions, and
;; loaded source. A FORM is MDL data with TYPE FORM and PRIMTYPE LIST;
;; `.X', `,X', and `'X' read as the forms <LVAL X>, <GVAL X>, and
;; <QUOTE X>. Bare atoms, strings, numbers, FALSE payloads, tuples, and
;; words evaluate to themselves (the reference's mdl_std_eval default
;; case); LIST, VECTOR, and UVECTOR evaluate their elements into fresh
;; structures. A nonempty FORM resolves its operator ATOM's global value
;; before its local value and applies it; an empty FORM is #FALSE ().
;; A MACRO-valued operator binds the raw call arguments per the
;; historical formal rules and evaluates the macro's result in place.
;; ---------------------------------------------------------------------------

(define (mdl-make-form lst)
  (mdl-typed-value (mdl-root-atom "FORM") lst))

(define (mdl-form? value)
  (and (mdl-typed-value? value)
       (eq? (mdl-typed-value-type value) (mdl-root-atom "FORM"))))

(define (form-elements form)
  (mdl-list->list (mdl-typed-value-value form)))

(define (quoted-formal-name item)
  ;; A quoted formal is the form <QUOTE atom> as stored data.
  (and (mdl-form? item)
       (let ([elements (form-elements item)])
         (and (= 2 (length elements))
              (eq? (car elements) (mdl-root-atom "QUOTE"))
              (mdl-atom? (cadr elements))
              (cadr elements)))))

(define (resolve-operator atom)
  (define global (global-option atom))
  (define result (if (eq? global unassigned) (local-option atom) global))
  (when (eq? result unassigned)
    (error 'mdl-eval "unassigned or non-applicable MDL operator ~a"
           (mdl-atom-pname atom)))
  result)

(define (mdl-apply-value fn raw-args)
  (cond
    [(mdl-macro? fn)
     (mdl-eval (mdl-apply-interpreted fn raw-args))]
    [(mdl-function? fn)
     (mdl-apply-interpreted fn raw-args)]
    [(procedure? fn)
     (apply fn (assemble-args raw-args (lambda (item) (mdl-eval item))))]
    [(exact-integer? fn)
     (mdl-apply-evaluated fn
                          (assemble-args raw-args (lambda (item) (mdl-eval item))))]
    [else (error 'mdl-apply-value "unassigned or non-applicable MDL operator ~a"
                 (if (mdl-atom? fn) (mdl-atom-pname fn) fn))]))

;; MAPF already has values from NTH. Send those values directly to an
;; interpreted FUNCTION; routing them through mdl-eval would rebuild LISTs
;; and VECTORs and could execute embedded FORMs a second time.
(define (mdl-apply-evaluated fn values)
  (cond [(mdl-function? fn) (mdl-apply-interpreted fn values #t)]
        [(procedure? fn) (apply fn values)]
        [(exact-integer? fn)
         (case (length values)
           [(1) (mdl-nth (car values) fn)]
           [(2)
            (unless (mdl-map-structured? (car values))
              (error 'mdl-apply-evaluated "First argument to PUT must be structured"))
            (mdl-put-element! (car values) fn (cadr values))]
           [(0) (error 'mdl-apply-evaluated "TOO-FEW-ARGUMENTS-SUPPLIED to FIX")]
           [else (error 'mdl-apply-evaluated "TOO-MANY-ARGUMENTS-SUPPLIED to FIX")])]
        [else (error 'mdl-apply-evaluated "NON-APPLICABLE-TYPE ~a" fn)]))

;; Call arguments assemble like the reference's LIST assembly for a SUBR:
;; items evaluate in order and SEGMENT objects contribute their elements,
;; already evaluated and never re-evaluated.
(define (assemble-args raw-args eval-item)
  (define items
    (if (or (null? raw-args) (mpair? raw-args))
        (mdl-list->list raw-args)
        raw-args))
  (let loop ([rest items] [acc '()])
    (cond
      [(null? rest) acc]
      [(mdl-segment? (car rest))
       (define value (mdl-eval (mdl-segment-payload (car rest))))
       (loop (cdr rest) (append acc (segment-elements value)))]
      [else (loop (cdr rest) (append acc (list (eval-item (car rest)))))])))

;; Historical formal sections over runtime data, mirroring the compiled
;; parser: required atoms, then OPTIONAL, then one ARGS/TUPLE rest
;; binding, then AUX; a quoted formal (<QUOTE atom>) binds its argument
;; raw and is legal only in the required and OPTIONAL sections.
(define (runtime-formal-specs formals)
  (define specs '())
  (define seen '())
  (define (add-name! atom)
    (when (member atom seen)
      (error 'mdl-bind-interpreted "BAD-ARGUMENT-LIST: duplicate formal argument"))
    (set! seen (cons atom seen)))
  (let loop ([items (if (mpair? formals) (mdl-list->list formals) formals)]
             [section 'required])
    (unless (null? items)
      (define item (car items))
      (cond
        [(string? item)
         (define marker (string-upcase item))
         (cond
           [(member marker '("OPT" "OPTIONAL"))
            (unless (eq? section 'required)
              (error 'mdl-bind-interpreted "OPTIONAL in wrong place in formal list"))
            (loop (cdr items) 'optional)]
           [(member marker '("ARGS" "TUPLE"))
            (unless (memq section '(required optional))
              (error 'mdl-bind-interpreted "~a in wrong place in formal list" marker))
            (when (or (null? (cdr items)) (not (mdl-atom? (cadr items))))
              (error 'mdl-bind-interpreted "ARGS or TUPLE requires an ATOM formal"))
            (add-name! (cadr items))
            (set! specs (cons (list (if (string=? marker "TUPLE") 'rest-tuple 'rest-args)
                                    (cadr items) #f)
                              specs))
            (loop (cddr items) 'after-rest)]
           [(member marker '("AUX" "EXTRA"))
            (unless (memq section '(required optional after-rest))
              (error 'mdl-bind-interpreted "AUX in wrong place in formal list"))
            (loop (cdr items) 'aux)]
           [(member marker '("NAME" "ACT"))
            (unless (memq section '(required optional after-rest aux))
              (error 'mdl-bind-interpreted "NAME in wrong place in formal list"))
            (when (or (null? (cdr items)) (not (mdl-atom? (cadr items))))
              (error 'mdl-bind-interpreted "NAME requires an ATOM formal"))
            (add-name! (cadr items))
            (set! specs (cons (list 'name (cadr items) #f) specs))
            (loop (cddr items) 'after-name)]
           [else (error 'mdl-bind-interpreted "unknown formal list marker")])]
        [(mdl-atom? item)
         (add-name! item)
         (define kind
           (case section
             [(required) 'required]
             [(optional) 'optional]
             [(aux) 'aux]
             [else (error 'mdl-bind-interpreted
                          "ATOM formal not allowed in this section")]))
         (set! specs (cons (list kind item #f) specs))
         (loop (cdr items) section)]
        [(quoted-formal-name item) =>
         (lambda (atom)
           (add-name! atom)
           (define kind
             (case section
               [(required) 'quoted]
               [(optional) 'quoted-optional]
               [else (error 'mdl-bind-interpreted
                            "quoted formal not allowed in this section")]))
           (set! specs (cons (list kind atom #f) specs))
           (loop (cdr items) section))]
        [(and (mpair? item) (= 2 (length (mdl-list->list item))))
         (define pair (mdl-list->list item))
         (unless (memq section '(optional aux))
           (error 'mdl-bind-interpreted
                  "2-list defaults are allowed only in OPTIONAL or AUX sections"))
         (define name (car pair))
         (define quoted-name (quoted-formal-name name))
         (when (and quoted-name (not (eq? section 'optional)))
           (error 'mdl-bind-interpreted "quoted formal not allowed in this section"))
         (unless (or quoted-name (mdl-atom? name))
           (error 'mdl-bind-interpreted "formal name must be an ATOM"))
         (define formal-name (or quoted-name name))
         (add-name! formal-name)
         (set! specs (cons (list (if quoted-name 'quoted-optional section)
                                 formal-name (cadr pair)) specs))
         (loop (cdr items) section)]
        [else (error 'mdl-bind-interpreted "unsupported formal argument")])))
  (reverse specs))

(define (interpreted-formal-specs formals leading-act)
  (define specs (runtime-formal-specs formals))
  (when (and leading-act (member leading-act (map second specs)))
    (error 'mdl-bind-interpreted "BAD-ARGUMENT-LIST: duplicate formal argument"))
  (if leading-act
      (cons (list 'name leading-act #f) specs)
      specs))

;; Apply an interpreted FUNCTION or MACRO to the raw call arguments. Plain
;; formals evaluate their argument (lazily, at expansion time in the
;; reference), quoted formals bind the raw argument, defaults and AUX
;; initializers evaluate in the growing frame, and the body evaluates
;; expression by expression. The invocation owns a function activation so
;; NAME formals and explicit RETURN/AGAIN targets work; AGAIN re-runs the
;; body without re-binding.
(define (mdl-apply-interpreted fn raw-args [already-evaluated? #f])
  (define formals (if (mdl-macro? fn) (mdl-macro-formals fn) (mdl-function-formals fn)))
  (define body (if (mdl-macro? fn) (mdl-macro-body fn) (mdl-function-body fn)))
  (define decl (if (mdl-macro? fn) (mdl-macro-decl fn) (mdl-function-decl fn)))
  (define leading-act (if (mdl-macro? fn) (mdl-macro-leading-act fn)
                          (mdl-function-leading-act fn)))
  (define specs (interpreted-formal-specs formals leading-act))
  ;; Raw arguments may carry SEGMENT objects; expand them (in order) at the
  ;; call level so spliced elements are values, never re-evaluated.
  ;; FUNCTION call arguments assemble spliced elements (see expand-arg-items);
  ;; MACRO call arguments stay entirely raw, like the reference's MACRO
  ;; branch, which never evaluates or expands the argument list — a SEGMENT
  ;; in a macro call binds as the SEGMENT object (PR #49 review).
  (define raw-list
    (if already-evaluated?
        (map (lambda (item) (cons 'value item)) raw-args)
        (if (mdl-macro? fn)
        (map (lambda (item) (cons 'raw item))
             (if (or (null? raw-args) (mpair? raw-args))
                 (mdl-list->list raw-args)
                 raw-args))
        (expand-arg-items raw-args))))
  (define (arg-value entry evaluate)
    ;; entry: (cons 'value v) for a spliced element, or (cons 'raw data) for
    ;; a plain argument (evaluated in the caller only when asked).
    (if (eq? (car entry) 'value)
        (cdr entry)
        (if evaluate
            (parameterize ([current-mdl-function-owner caller-owner]
                           [current-mdl-locals caller-locals])
              (mdl-eval (cdr entry)))
            (cdr entry))))
  (define caller-owner (current-mdl-function-owner))
  (define caller-locals (current-mdl-locals))
  (parameterize ([current-mdl-function-owner (gensym 'mdl-interpreted)])
  (let/ec escape
    (define frame (mdl-activation (current-mdl-function-owner) escape 'function
                                   #f #f #f #t decl))
    (dynamic-wind
      void
      (lambda ()
        (parameterize ([current-mdl-activations
                        (cons frame (current-mdl-activations))])
          (define locals (make-hasheq))
          (when decl (hash-set! local-declarations locals decl))
          (define (bind! atom value kind)
            (when (hash-has-key? locals atom)
              (error 'mdl-bind-interpreted
                     "BAD-ARGUMENT-LIST: duplicate formal argument"))
            (check-frame-binding! locals atom value kind)
            (hash-set! locals atom value))
          (define remaining raw-list)
          (parameterize ([current-mdl-locals (cons locals (current-mdl-locals))])
            (for ([spec (in-list specs)])
              (define kind (first spec))
              (define name (second spec))
              (define default (third spec))
              (define (too-few message)
                (error 'mdl-bind-interpreted
                       "~a for ~a" message (mdl-atom-pname name)))
              (case kind
                [(required quoted)
                 (when (null? remaining) (too-few "Too few args in function call"))
                 (bind! name (arg-value (car remaining) (not (eq? kind 'quoted))) 'argument)
                 (set! remaining (cdr remaining))]
                [(optional quoted-optional)
                 (if (null? remaining)
                     (bind! name (if default (mdl-eval default) unassigned) 'optional)
                     (begin
                       (bind! name (arg-value (car remaining)
                                              (not (eq? kind 'quoted-optional)))
                              'optional)
                       (set! remaining (cdr remaining))))]
                [(rest-tuple rest-args)
                 (bind! name (if (null? remaining)
                                 (if (eq? kind 'rest-tuple) (mdl-tuple-value '()) '())
                                 (if (eq? kind 'rest-tuple)
                                     (mdl-tuple-value
                                      (apply mdl-list
                                             (parameterize ([current-mdl-function-owner caller-owner]
                                                            [current-mdl-locals caller-locals])
                                               (map (lambda (entry)
                                                      (if (eq? (car entry) 'raw)
                                                          (mdl-eval (cdr entry))
                                                          (cdr entry)))
                                                    remaining))))
                                     (apply mdl-list (map cdr remaining))))
                        'rest)
                 (set! remaining '())]
                [(aux) (bind! name (if default (mdl-eval default) unassigned) 'aux)]
                [(name) (bind! name frame 'name)]
                [else (error 'mdl-bind-interpreted "unknown formal specification")]))
            (unless (null? remaining)
              (error 'mdl-bind-interpreted
                     "TOO-MANY-ARGUMENTS-SUPPLIED in interpreted application"))
            (let body-loop ()
              (define result
                (let/ec restart
                  (set-mdl-activation-restart! frame restart)
                  (let value-loop ([items body] [last #f])
                    (cond
                      [(null? items) last]
                      [else (value-loop (cdr items) (mdl-eval (car items)))]))))
              (if (eq? result restart-token)
                  (body-loop)
                  (check-result! decl result))))))
      (lambda () (set-mdl-activation-live?! frame #f))))))

;; The runtime evaluator over MDL data. A SEGMENT object evaluates only as
;; an element of a structure being built: standalone evaluation is the
;; reference's ILLEGAL-SEGMENT break, and a plain element whose value is a
;; SEGMENT object is stored without re-splicing.
(define (mdl-eval value)
  (cond
    [(mdl-segment? value) (mdl-segment-standalone-error)]
    [(mdl-form? value) (mdl-eval-form value)]
    [(or (null? value) (mpair? value))
     (build-eval-list (mdl-list->list value))]
    [(and (mdl-array? value) (eq? (mdl-array-kind value) 'VECTOR))
     (build-eval-vector
      (for/list ([i (in-range (mdl-array-length value))])
        (mdl-nth value (add1 i))))]
    [(and (mdl-array? value) (eq? (mdl-array-kind value) 'UVECTOR))
     (build-eval-uvector
      (for/list ([i (in-range (mdl-array-length value))])
        (mdl-nth value (add1 i))))]
    [else value]))

(define (mdl-eval-form form)
  (define elements (form-elements form))
  (cond
    [(null? elements) (mdl-false '())]
    [(mdl-atom? (car elements))
     (define op (car elements))
     (define args (cdr elements))
     (case (string->symbol (mdl-atom-pname op))
       [(QUOTE)
        (unless (= 1 (length args))
          (error 'mdl-eval "QUOTE expects one argument"))
        (car args)]
       [(COND) (runtime-cond args)]
       [(AND) (runtime-and args)]
       [(OR) (runtime-or args)]
       [(NOT)
        (unless (= 1 (length args)) (error 'mdl-eval "NOT expects one argument"))
        (if (mdl-truthy? (mdl-eval (car args)))
            (mdl-false '())
            (mdl-root-atom "T"))]
       [(PROG) (runtime-prog args #f)]
       [(REPEAT) (runtime-prog args #t)]
       [(RETURN) (apply mdl-return (map mdl-eval args))]
       [(AGAIN) (apply mdl-again (map mdl-eval args))]
       [(GO) (mdl-go (mdl-eval (car args)))]
       [(UNWIND)
        (unless (= 2 (length args))
          (error 'mdl-eval "UNWIND expects a value and cleanup expression"))
        (mdl-unwind (lambda () (mdl-eval (car args)))
                    (lambda () (mdl-eval (cadr args))))]
       [(FUNCTION) (runtime-function-literal args)]
       [(DEFINE) (runtime-define args #f)]
       [(DEFMAC) (runtime-define args #t)]
       [else (mdl-apply-value (resolve-operator op) args)])]
    [else (mdl-apply-value (mdl-eval (car elements)) (cdr elements))]))

(define (mdl-function-literal formals body [leading-act #f] [decl #f])
  (interpreted-formal-specs formals leading-act)
  (when (null? body) (error 'mdl-function "FUNCTION requires a body"))
  (mdl-function formals body leading-act decl))

(define (runtime-function-literal operands)
  (unless (and (pair? operands) (pair? (cdr operands)))
    (error 'mdl-function "FUNCTION requires formals and body"))
  (define leading-act (and (mdl-atom? (car operands)) (car operands)))
  (define formals (if leading-act (cadr operands) (car operands)))
  (define body (if leading-act (cddr operands) (cdr operands)))
  (unless (or (null? formals) (mpair? formals))
    (error 'mdl-function "FUNCTION requires a formal LIST"))
  (define decl (and (pair? body) (mdl-decl-value? (car body)) (car body)))
  (mdl-function-literal formals (if decl (cdr body) body) leading-act decl))

;; Runtime DEFINE and DEFMAC store interpreted definitions. The optional
;; leading activation atom between the name and the formal list binds the
;; invocation's own activation, like the compiled forms.
(define (runtime-define operands macro?)
  (define who (if macro? "DEFMAC" "DEFINE"))
  (unless (and (pair? operands) (pair? (cdr operands)))
    (error 'mdl-eval "~a expects a name, formal list, and body" who))
  (define name (car operands))
  (unless (mdl-atom? name)
    (error 'mdl-eval "First argument of ~a must be an atom" who))
  (define rest (cdr operands))
  (define leading-act (and (mdl-atom? (car rest)) (car rest)))
  (define formals-node (if leading-act
                           (and (pair? (cdr rest)) (cadr rest))
                           (car rest)))
  (define body (if leading-act
                   (and (pair? (cdr rest)) (cddr rest))
                   (cdr rest)))
  (unless (and (or (null? formals-node) (mpair? formals-node))
               (pair? body))
    (error 'mdl-eval "~a requires a parenthesized formal list" who))
  (interpreted-formal-specs formals-node leading-act) ; validation
  (define decl (and (pair? body) (mdl-decl-value? (car body)) (car body)))
  (define expressions (if decl (cdr body) body))
  (when (ormap mdl-decl-value? expressions)
    (error 'mdl-eval "#DECL must immediately follow the formal list"))
  (when (null? expressions)
    (error 'mdl-eval "declaration requires a body"))
  (if macro?
      (mdl-defmac! name formals-node expressions leading-act decl)
      (mdl-define-interpreted! name formals-node expressions leading-act decl)))

(define (runtime-cond clauses)
  (let loop ([remaining clauses] [last (mdl-false '())])
    (cond
      [(null? remaining) last]
      [else
       (define clause (mdl-list->list (car remaining)))
       (unless (pair? clause) (error 'mdl-eval "COND requires nonempty clauses"))
       (define test-value (mdl-eval (car clause)))
       (if (mdl-truthy? test-value)
           (let value-loop ([exprs (cdr clause)] [result test-value])
             (cond
               [(null? exprs) result]
               [else (value-loop (cdr exprs) (mdl-eval (car exprs)))]))
           (loop (cdr remaining) test-value))])))

(define (runtime-and args)
  (if (null? args)
      (mdl-root-atom "T")
      (let loop ([remaining args])
        (if (null? (cdr remaining))
            (mdl-eval (car remaining))
            (let ([value (mdl-eval (car remaining))])
              (if (mdl-truthy? value)
                  (loop (cdr remaining))
                  value))))))

(define (runtime-or args)
  (if (null? args)
      (mdl-false '())
      (let loop ([remaining args])
        (if (null? (cdr remaining))
            (mdl-eval (car remaining))
            (let ([value (mdl-eval (car remaining))])
              (if (mdl-truthy? value)
                  value
                  (loop (cdr remaining))))))))

(define (runtime-prog operands repeat?)
  (define named? (and (pair? operands) (mdl-atom? (car operands))
                      (pair? (cdr operands))
                      (or (null? (cadr operands)) (mpair? (cadr operands)))))
  (define name (and named? (car operands)))
  (define rest-operands (if named? (cdr operands) operands))
  (unless (and (pair? rest-operands)
               (or (null? (car rest-operands)) (mpair? (car rest-operands))))
    (error 'mdl-eval "PROG or REPEAT requires an auxiliary LIST and body"))
  (define aux-list (mdl-list->list (car rest-operands)))
  (define raw-body (cdr rest-operands))
  (define decl (and (pair? raw-body) (mdl-decl-value? (car raw-body))
                    (car raw-body)))
  (define body (if decl (cdr raw-body) raw-body))
  (when (ormap mdl-decl-value? body)
    (error 'mdl-eval "#DECL must immediately follow the auxiliary list"))
  (define names '())
  (define specs
    (for/list ([item (in-list aux-list)])
      (define two-list?
        (and (mpair? item) (= 2 (length (mdl-list->list item)))))
      (define name-atom (if two-list? (mcar item) item))
      (unless (mdl-atom? name-atom) (error 'mdl-eval "PROG auxiliary must be an ATOM"))
      (when (member name-atom names) (error 'mdl-eval "duplicate PROG auxiliary binding"))
      (set! names (cons name-atom names))
      (if two-list?
          (cons name-atom (lambda () (mdl-eval (mcar (mcdr item)))))
          (cons name-atom #f))))
  (define items
    (list->vector
     (for/list ([item (in-list body)])
       (if (mdl-atom? item)
           (cons 'label item)
           (cons 'expr (lambda () (mdl-eval item)))))))
  (if name
      (mdl-with-prog-activation items specs repeat? name decl)
      (mdl-with-prog-activation items specs repeat? #f decl)))

;; EXPAND performs one top-level macro expansion without evaluating. The
;; manual returns a non-macro form unchanged; pinned Confusion evaluates
;; it instead, a recorded deviation.
(define (mdl-expand value)
  (if (mdl-form? value)
      (let* ([elements (form-elements value)])
        (if (or (null? elements) (not (mdl-atom? (car elements))))
            value
            (let* ([operator (car elements)]
                   [global (global-option operator)]
                   [fn (if (eq? global unassigned)
                           (local-option operator)
                           global)])
              (if (mdl-macro? fn)
                  (mdl-apply-interpreted fn (cdr elements))
                  value))))
      value))

;; Compiled call sites pass the raw argument data and one thunk per
;; argument. Interpreted application evaluates a plain formal's raw data
;; through the runtime evaluator at bind time, so macros and quoted
;; formals see raw arguments and side effects in unevaluated arguments do
;; not run; procedure applications evaluate the compiled thunks in order.
;; Splice markers among the thunk results assemble into the argument list
;; in order before the operator is applied (chapter 7.5.2).
(define (mdl-dispatch-call fn raw-args-thunk arg-thunks)
  (cond
    [(or (mdl-macro? fn) (mdl-function? fn))
     (define result (mdl-apply-interpreted fn (raw-args-thunk)))
     (if (mdl-macro? fn) (mdl-eval result) result)]
    [(or (procedure? fn) (exact-integer? fn))
     (define results (map (lambda (thunk) (thunk)) arg-thunks))
     (mdl-apply-evaluated
      fn
      (append*
       (for/list ([value (in-list results)])
         (if (mdl-splice-result? value)
             (segment-elements (mdl-splice-result-value value))
             (list value)))))]
    [else (error 'mdl-dispatch-call "NON-APPLICABLE-TYPE ~a" fn)]))

(define (mdl-apply-form name raw-args-thunk arg-thunks)
  (define atom (binding-atom 'mdl-apply-form name))
  (mdl-dispatch-call (resolve-operator atom) raw-args-thunk arg-thunks))

(define (mdl-apply-computed fn raw-args-thunk arg-thunks)
  (mdl-dispatch-call fn raw-args-thunk arg-thunks))

(define (mdl-defmac! name formals body [leading-act #f] [decl #f])
  (require-atom 'mdl-defmac name)
  (interpreted-formal-specs formals leading-act)
  (unless (eq? (global-option name) unassigned)
    (error 'mdl-defmac "Atom is already bound in DEFMAC: ~a" (mdl-atom-pname name)))
  (hash-set! (current-mdl-globals) name (mdl-macro formals body leading-act decl))
  name)

(define (mdl-define-interpreted! name formals body [leading-act #f] [decl #f])
  (require-atom 'mdl-define-interpreted name)
  (interpreted-formal-specs formals leading-act)
  (hash-set! (current-mdl-globals) name (mdl-function formals body leading-act decl))
  name)

(define (global-option atom)
  (define globals (current-mdl-globals))
  ;; Built-in SUBRs are the GVALs of this session's ROOT atoms (manual
  ;; 15.5). The check never consults .OBLIST and never interns: a
  ;; same-named atom on another OBLIST, or an uninterned one, is unbound.
  (cond [(hash-has-key? globals atom) (hash-ref globals atom)]
        [(eq? atom (root-atom-or-false (mdl-atom-pname atom)))
         (hash-ref builtin-table (mdl-atom-pname atom) unassigned)]
        [else unassigned]))

;; Interpreter-supplied globals bound in every fresh MDL session, like the
;; historical interpreter's startup environment. The pinned reference binds
;; MUDDLE, the interpreter version, to the FIX 101 (issue #51 evidence
;; muddle-reference.json, interpreter SHA a29c756df5c9...7317e629): with that
;; value the 77defs.mud:1 guard <L? ,MUDDLE 100> is FALSE and its <AND ...>
;; short-circuits without evaluating USE (unbound in the reference). Changing
;; the value requires new reference evidence, not a source edit.
(define mdl-interpreter-version 101)

(define (mdl-setg! name value)
  (define atom (binding-atom 'mdl-setg name))
  (define globals (current-mdl-globals))
  (define declared
    (hash-ref (atom-space-global-declarations (current-mdl-atom-space)) atom #f))
  (when declared
    (define pattern (normalize-decl-pattern declared #f #f "SETG"))
    (unless (matches-decl? value pattern)
      (error 'mdl-setg "value does not satisfy GDECL declaration for ~a"
             (mdl-atom-pname atom))))
  (define old (hash-ref globals atom unassigned))
  (define redefine (hash-ref globals (mdl-root-atom "REDEFINE") unassigned))
  (when (and (hash-has-key? (atom-space-manifests (current-mdl-atom-space)) atom)
             (not (eq? old unassigned))
             (not (mdl-identical? old value))
             (or (eq? redefine unassigned) (mdl-false? redefine)))
    (error 'mdl-setg "ATTEMPT-TO-CHANGE-MANIFEST-VARIABLE ~a"
           (mdl-atom-pname atom)))
  (hash-set! globals atom value)
  value)

(define (mdl-gdecl raw-args)
  (define items (mdl-list->list raw-args))
  (unless (and (pair? items) (even? (length items)))
    (error 'mdl-gdecl "GDECL requires ATOM-list/declaration pairs"))
  (define staged (make-hasheq))
  (for ([i (in-range 0 (length items) 2)])
    (define names (list-ref items i))
    (define pattern (list-ref items (add1 i)))
    (unless (and (mpair? names) (pair? (mdl-list->list names)))
      (error 'mdl-gdecl "GDECL requires a nonempty ATOM list"))
    (check-decl-pattern-shape pattern 'mdl-gdecl)
    (for ([name (in-list (mdl-list->list names))])
      (unless (mdl-atom? name)
        (error 'mdl-gdecl "GDECL name must be an ATOM"))
      (when (hash-has-key? staged name)
        (error 'mdl-gdecl "duplicate GDECL name ~a" (mdl-atom-pname name)))
      (define current (hash-ref (current-mdl-globals) name unassigned))
      (unless (eq? current unassigned)
        (unless (matches-decl?
                 current (normalize-decl-pattern pattern #f #f "GDECL"))
          (error 'mdl-gdecl "existing value does not satisfy GDECL for ~a"
                 (mdl-atom-pname name))))
      (hash-set! staged name pattern)))
  (define declarations
    (atom-space-global-declarations (current-mdl-atom-space)))
  (for ([(name pattern) (in-hash staged)])
    (hash-set! declarations name pattern)
    (unless (hash-has-key? (current-mdl-globals) name)
      (hash-set! (current-mdl-globals) name unassigned)))
  (mdl-root-atom "T"))

(define (mdl-gassigned? name)
  (define atom (binding-atom 'mdl-gassigned? name))
  (mdl-boolean (not (eq? (global-option atom) unassigned))))

(define (mdl-assigned? . args)
  (when (null? args)
    (error 'mdl-assigned? "Not enough arguments to ASSIGNED?"))
  (when (pair? (cdr args))
    (error 'mdl-assigned? "ASSIGNED? ENV frame argument unsupported"))
  (define atom (car args))
  (unless (mdl-atom? atom)
    (error 'mdl-assigned? "First arg to ASSIGNED? must be ATOM"))
  (mdl-boolean (not (eq? (local-option atom) unassigned))))

;; Every argument is checked before any is marked (#199), so a rejected
;; argument leaves the call without effect.
(define (mdl-manifest . names)
  (for ([name (in-list names)])
    (binding-atom 'mdl-manifest name))
  (for ([atom (in-list names)])
    (hash-set! (atom-space-manifests (current-mdl-atom-space)) atom #t)
    (unless (hash-has-key? (current-mdl-globals) atom)
      (hash-set! (current-mdl-globals) atom unassigned)))
  (mdl-root-atom "T"))

(define (mdl-gval name)
  (define atom (binding-atom 'mdl-gval name))
  (define result (global-option atom))
  (if (eq? result unassigned)
      (error 'mdl-gval "unassigned MDL global ~a" (mdl-atom-pname atom))
      result))

(define (mdl-value name)
  (define atom (binding-atom 'mdl-value name))
  (define local (local-option atom))
  (if (eq? local unassigned) (mdl-gval atom) local))

(define (mdl-gunassign! name)
  (define atom (binding-atom 'mdl-gunassign name))
  (hash-set! (current-mdl-globals) atom unassigned)
  atom)

;; Compiler-only: the expansion of a compiled DEFINE calls this. Registering
;; fn makes it TYPE FUNCTION (ADR-0060); a host-provided SUBR must use
;; mdl-define-subr! instead.
(define (mdl-define! name fn [formal-kinds '()])
  (when (procedure? fn)
    (hash-set! compiled-function-formals fn formal-kinds))
  (mdl-setg! name fn))

;; A host-provided SUBR bound by a host (the loader's FLOAD): TYPE SUBR, like
;; REP (ADR-0049, ADR-0060), never registered as a compiled FUNCTION.
(define (mdl-define-subr! name proc)
  (require-atom 'mdl-define-subr! name)
  (mdl-setg! name (mdl-subr (string->symbol (mdl-atom-pname name)) proc)))

(struct atom-value (pname [oblist #:mutable]))
(struct oblist-value (name entries size))
;; inchan/outchan are the ROOT ATOMs INCHAN!-ROOT and OUTCHAN!-ROOT; channels
;; maps each CHANNEL's VECTOR storage to its host-channel (see
;; "Session-owned channels").
(struct atom-space (initial root named types builtins manifests associations
                            global-declarations events interrupt-state memory
                            random-state internal lookup [lookup-stack #:mutable]
                            inchan outchan channels
                            ;; ADR-0048: SAVE session records, newest first.
                            [save-records #:mutable]
                            ;; ADR-0052: session-owned host clock and zone
                            ;; for GETTIMEDATE's "now" and local decomposition.
                            clock time-zone
                            ;; ADR-0055: denied OPEN calls, newest first.
                            [open-records #:mutable]
                            ;; ADR-0054: messages of every MDL ERROR signalled
                            ;; in this session, newest first (host-only).
                            [mdl-errors #:mutable]
                            ;; ADR-0061: host-only READSTRING observer, or #f.
                            ;; Never reachable from MDL.
                            input-observer
                            ;; M4 S9 (#170): how many times TIME was called
                            ;; in this session (host-only; TIME's value).
                            [time-calls #:mutable]
                            ;; M4 S10 (#171, ADR-0055 amendment): the host's
                            ;; read-only allowlist (mdl-read-only-file list),
                            ;; the host reader (entry -> bytes) or #f, and the
                            ;; session's file CHANNEL records, newest first.
                            ;; Host-only; never reachable from MDL.
                            read-only-files read-only-reader
                            [file-channels #:mutable]
                            ;; M4 #196 (diagnostic only, SEMANTICS "Diagnostic-
                            ;; only: attached-declaration violation recorder"):
                            ;; a host-only, test-only procedure or #f (the
                            ;; default; production hosts never pass one). Set
                            ;; once at construction, read only by
                            ;; check-declared!; never reachable from MDL.
                            decl-violation-recorder))

(define mdl-atom? atom-value?)
(define mdl-atom-pname atom-value-pname)
(define mdl-oblist? oblist-value?)

(define (make-mdl-atom-space #:clock [clock real-mdl-clock]
                             #:time-zone [time-zone 'local]
                             #:input-observer [input-observer #f]
                             #:read-only-files [read-only-files '()]
                             #:read-only-reader [read-only-reader #f]
                             #:decl-violation-recorder [decl-violation-recorder #f])
  (unless (mdl-clock? clock)
    (raise-argument-error 'make-mdl-atom-space "mdl-clock?" clock))
  (unless (or (not decl-violation-recorder)
              (and (procedure? decl-violation-recorder)
                   (procedure-arity-includes? decl-violation-recorder 1)))
    (raise-argument-error 'make-mdl-atom-space "(or/c #f (procedure-arity-includes/c 1))"
                          decl-violation-recorder))
  (check-read-only-files! 'make-mdl-atom-space read-only-files read-only-reader)
  (unless (or (not input-observer)
              (and (procedure? input-observer)
                   (procedure-arity-includes? input-observer 2)))
    (raise-argument-error 'make-mdl-atom-space "(or/c #f (procedure-arity-includes/c 2))"
                          input-observer))
  (unless (mdl-time-zone? time-zone)
    (raise-argument-error 'make-mdl-atom-space "(or/c 'local 'utc)" time-zone))
  (define named (make-hasheq))
  (define types (make-hasheq))
  (define builtins (make-hasheq))
  (define root (oblist-value #f (make-hash) 151))
  (define root-name (atom-value "ROOT" root))
  (hash-set! (oblist-value-entries root) "ROOT" root-name)
  (hash-set! named root-name root)
  (define initial-name (atom-value "INITIAL" root))
  (hash-set! (oblist-value-entries root) "INITIAL" initial-name)
  (define initial (oblist-value initial-name (make-hash) 151))
  (hash-set! named initial-name initial)
  (define oblist-name (atom-value "OBLIST" root))
  (hash-set! (oblist-value-entries root) "OBLIST" oblist-name)
  ;; Manual 15.5 and Confusion: ROOT holds T, OBLIST, every SUBR/FSUBR
  ;; name and the built-in TYPE names; INITIAL starts empty. ROOT is seeded
  ;; with the complete pinned-Confusion startup inventory
  ;; (historical-root-names), implemented or not, so source read before a
  ;; primitive exists already holds the ROOT atom. `internal` caches every
  ;; seeded atom by name; later REMOVE/INSERT on ROOT cannot change which
  ;; atom the runtime means.
  (define internal (make-hash))
  (define entries (oblist-value-entries root))
  (for ([name (in-list historical-root-names)])
    (unless (hash-ref entries name #f)
      (hash-set! entries name (atom-value name root))))
  (for ([(name atom) (in-hash entries)])
    (hash-set! internal name atom))
  ;; Every name the runtime itself needs must be historical; a new one is
  ;; a deliberate inventory change backed by new reference evidence.
  (define (seed-root! name)
    (or (hash-ref entries name #f)
        (error 'make-mdl-atom-space
               "~a is not in the historical ROOT inventory (root-names.rktd)"
               name)))
  (for ([entry (in-list '(("ATOM" . "ATOM") ("OBLIST" . "UVECTOR")
                          ("LIST" . "LIST") ("FORM" . "LIST")
                          ("SEGMENT" . "LIST")
                          ("FALSE" . "LIST") ("DECL" . "LIST")
                          ("VECTOR" . "VECTOR")
                          ("CHANNEL" . "VECTOR")
                          ("UVECTOR" . "UVECTOR") ("STRING" . "STRING")
                          ("FIX" . "WORD") ("FLOAT" . "WORD")
                          ("WORD" . "WORD") ("BITS" . "WORD")
                          ("LOSE" . "WORD")
                          ("CHARACTER" . "WORD")
                          ("FRAME" . "FRAME")
                          ("TUPLE" . "TUPLE")
                          ("MACRO" . "LIST")
                          ("FUNCTION" . "LIST")
                          ("ACTIVATION" . "FRAME")
                          ("IHEADER" . "VECTOR")
                          ("HANDLER" . "VECTOR")))])
    (define type-atom (seed-root! (car entry)))
    (hash-set! types type-atom (cdr entry))
    (hash-set! builtins type-atom #t))
  (for ([name (in-hash-keys builtin-table)]) (seed-root! name))
  (for-each seed-root! root-internal-names)
  (atom-space initial root named types builtins (make-hasheq)
              ;; Session-owned association entries. Key comparison must use
              ;; mdl-identical?, which is broader than Racket eq? for WORDs
              ;; and independently constructed REST views.
              (box (list (list initial-name oblist-name initial)
                         (list root-name oblist-name root)
                         (list initial oblist-name initial-name)
                         (list root oblist-name root-name)))
              (make-hasheq) (make-hash) (mdl-interrupt-state 0 '())
              (make-mdl-memory) (make-random36-state) internal
              ;; Top-level default LVAL of ROOT OBLIST; see current-lookup-path.
              (mcons initial (mcons root '())) '()
              ;; R1 channels: the canonical seeded ROOT INCHAN/OUTCHAN
              ;; (seed-root! fails if either is missing from the inventory).
              (seed-root! "INCHAN") (seed-root! "OUTCHAN") (make-weak-hasheq)
              '() clock time-zone '() '() input-observer 0
              read-only-files read-only-reader '() decl-violation-recorder))

;; ROOT names that are not built-in TYPEs or builtin-table SUBRs, each in
;; pinned Confusion's startup ROOT (review/R3R4-oblist-reference.json
;; internal-name-placement): values the runtime produces or compares (T,
;; QUOTE, REDEFINE); interpreter-supplied globals and channels (MUDDLE,
;; INCHAN, OUTCHAN, FLOAD); the INTERRUPTS OBLIST name; and the FSUBRs the
;; compiler handles by name. GO, DIVERT-AGC and APPLICABLE are deliberately
;; absent: Confusion has them in neither ROOT nor INITIAL at startup.
(define root-internal-names
  '("T" "QUOTE" "REDEFINE" "MUDDLE" "INCHAN" "OUTCHAN" "FLOAD" "INTERRUPTS"
    "DEFINE" "DEFMAC" "FUNCTION" "PROG" "REPEAT" "RETURN" "AGAIN" "UNWIND"
    "GDECL" "COND" "AND" "OR" "NOT"))

;; The complete startup ROOT inventory of pinned Confusion, a checked-in
;; data file with provenance (docs/evidence/M3/review/
;; confusion-root-names.json). Malformed data fails module loading.
(define-runtime-path root-names-path "root-names.rktd")
(define historical-root-names
  (let ([names (call-with-input-file root-names-path read)])
    (unless (and (list? names) (pair? names)
                 (andmap (lambda (n) (and (string? n) (positive? (string-length n))))
                         names)
                 (= (length names) (length (remove-duplicates names))))
      (error 'root-names "root-names.rktd must be a nonempty list of distinct PNAME strings"))
    names))

;; Runtime-internal name -> the current session's ROOT atom. It never reads
;; .OBLIST and never interns: every internal name is seeded when the
;; session is created, so a missing name is an implementation error.
(define (mdl-root-atom name)
  (or (root-atom-or-false name)
      (error 'mdl-root-atom "internal name ~a is not a seeded ROOT atom" name)))

(define (root-atom-or-false name)
  (hash-ref (atom-space-internal (current-mdl-atom-space)) name #f))

;; A true event source must be supplied before predefined names are
;; registered. GC and DIVERT-AGC are internal MDL interrupts, not OS signals.
(define unsupported-predefined-interrupt-names
  '("CHAR" "READ" "WRITE" "UNBLOCKED"
    "CLOCK" "SYSDOWN" "INFERIOR" "RUNT" "REALT"
    "MPV" "PURE" "ILOPR" "PARITY" "IOC"))

;; Predefined names that may be registered (EVENT, HANDLER, ON, OFF all
;; work) although an isolated session has no source for them, so an
;; occurrence can never arise. Any attempt to emit or deliver one is a
;; strict error naming the decision. The emit check is the enforced
;; boundary; the delivery check in `mdl-deliver-occurrence!` is defensive
;; (no MDL-level path can queue such an occurrence today) and is kept so
;; that a future event source cannot bypass the decision.
;;   "IPC"     maintainer decision 2026-11-22 (issue #112, ADR-0047)
;;   "BLOCKED" maintainer decision 2026-11-23 (ADR-0048)
(define sourceless-predefined-interrupts
  '(("IPC" . "this session has no inter-process message source; IPC occurrences cannot be emitted (maintainer decision 2026-11-22; issue #112)")
    ("BLOCKED" . "this session has no blocked-input source; BLOCKED occurrences cannot be emitted (maintainer decision 2026-11-23; ADR-0048)")))
(define sourceless-predefined-interrupt-names
  (map car sourceless-predefined-interrupts))

(define (check-emittable-event who name)
  (define entry (assoc name sourceless-predefined-interrupts))
  (when entry
    (error who "~a: ~a" name (cdr entry))))

(define (current-interrupt-state)
  (atom-space-interrupt-state (current-mdl-atom-space)))

(define (active-iheader? header)
  (and (mdl-iheader-enabled? header)
       (eq? (hash-ref (atom-space-events (current-mdl-atom-space))
                      (mdl-iheader-name header) #f)
            header)))

(define (check-session-iheader who header)
  (unless (mdl-iheader? header)
    (error who "expected IHEADER"))
  (unless (eq? (mdl-iheader-owner header) (current-mdl-atom-space))
    (error who "IHEADER belongs to another MDL session")))

;; Event sources call this only at a safe delivery boundary, with values
;; already evaluated. Focused tests call it directly; it is not an MDL
;; primitive or client-facing evaluator, and no fake GC source uses it.
(define (mdl-emit-event! name arguments [strict? #f])
  (check-emittable-event 'mdl-emit-event! name)
  (define header (hash-ref (atom-space-events (current-mdl-atom-space)) name #f))
  (when (and strict? (not header))
    (error 'mdl-emit-event! "unknown or unregistered event ~a" name))
  (define enabled? (and header (active-iheader? header)))
  ;; Record this occurrence before draining at the source safe point. If an
  ;; older queued handler raises, the newer occurrence must not disappear.
  ;; The drain selects the earliest eligible occurrence; a higher-priority
  ;; nested event can still supersede a lower-priority queued one.
  (when enabled?
    (define state (current-interrupt-state))
    (set-mdl-interrupt-state-pending!
     state (append (mdl-interrupt-state-pending state)
                   (list (mdl-interrupt-occurrence header arguments)))))
  (mdl-drain-pending!)
  (and enabled? #t))

;; Host collection establishes lifetime; the ledger reports only charged
;; logical MDL words. No callback runs inside the host collector.
(define current-mdl-storage-pressure? (make-parameter #f))

(define (current-mdl-memory)
  (atom-space-memory (current-mdl-atom-space)))

(define (mdl-logical-storage-stats)
  (define memory (current-mdl-memory))
  (hash 'capacity (mdl-memory-capacity memory)
        'used (mdl-memory-used memory)
        'free (mdl-memory-free memory)))

(define (mdl-set-logical-storage-capacity! words)
  ;; Host-only test/configuration hook, never an MDL primitive.
  (unless (and (exact-integer? words) (>= words 0) (<= words fix-max))
    (error 'mdl-set-logical-storage-capacity! "expected nonnegative FIX"))
  (set-mdl-memory-capacity! (current-mdl-memory) words))

(define (mdl-recompute-entry-words)
  ;; Host-only test hook: independently recompute the total charged words
  ;; by summing ALL currently-registered entries, bypassing the cached 'used'
  ;; field. Use this in tests to verify 'used' is consistent with the entry list.
  (mdl-memory-entry-word-sum (current-mdl-memory)))

(define (mdl-set-used-for-test! words)
  ;; Host-only test hook: directly set the cached 'used' field WITHOUT
  ;; registering entries. Use ONLY to simulate near-fix-max ledger state for
  ;; overflow / cap-clamping tests. Leaves entries inconsistent.
  (unless (and (exact-integer? words) (>= words 0))
    (error 'mdl-set-used-for-test! "expected nonnegative integer"))
  (mdl-memory-set-used-for-test! (current-mdl-memory) words))

;; MDL manual ch.22 §22.5: GC min = minimum free words after a collection.
;; "A large min will result in fewer total garbage collections."
;; Initial value: 8192 words. Exposed as a session parameter so tests can
;; use a small value to reach the fix-max cap case that would otherwise
;; require fix-max live objects to trigger.
(define current-mdl-gc-min (make-parameter 8192))

(define (mdl-collect-logical! reason initiator)
  (define-values (reclaimed elapsed) (mdl-memory-collect! (current-mdl-memory)))
  (mdl-emit-event! "GC" (list elapsed reason (mdl-root-atom initiator)))
  (check-fix 'mdl-gc reclaimed))

(define (mdl-gc . args)
  (unless (null? args)
    (error 'mdl-gc "GC arguments are unsupported in this logical storage model"))
  (parameterize ([current-mdl-storage-pressure? #t])
    (mdl-collect-logical! 1 "GC")))

(define (mdl-bloat . args)
  (unless (<= (length args) 1)
    (error 'mdl-bloat "BLOAT storage classes beyond movable free space are unsupported"))
  (define requested (if (null? args) 0 (car args)))
  (unless (and (exact-integer? requested) (<= 0 requested fix-max))
    (error 'mdl-bloat "BLOAT requires a nonnegative FIX"))
  (check-fix 'mdl-bloat (mdl-memory-bloat! (current-mdl-memory) requested)))

(define (mdl-track-allocation! value words initiator)
  (define memory (current-mdl-memory))
  (when (and (not (current-mdl-storage-pressure?))
             (> (+ (mdl-memory-used memory) words) (mdl-memory-capacity memory)))
    (parameterize ([current-mdl-storage-pressure? #t])
      (mdl-emit-event! "DIVERT-AGC" (list words (mdl-root-atom initiator)))
      ;; Track whether a collection actually ran during this allocation.
      ;; The gc-min growth policy (MDL manual ch.22 §22.5) applies only after
      ;; a collection ran, NOT when a DIVERT-AGC handler's BLOAT already satisfied
      ;; the request. BLOAT is the handler's mechanism for postponing GC; if the
      ;; handler BLOATs to cover the pending words, logical capacity is already
      ;; correct and gc-min does not impose an additional floor.  Applying gc-min
      ;; after every BLOAT inflates capacity far beyond the handler's intent,
      ;; collapsing a game-designed diversion schedule (e.g. 77rooms.mud §78-90)
      ;; from ~85 diversions to ~2 per 300 k cells.
      (define collected? #f)
      (when (> (+ (mdl-memory-used memory) words) (mdl-memory-capacity memory))
        (mdl-collect-logical! 2 initiator)
        (set! collected? #t))
      ;; MDL manual ch.22 §22.5: gc-min = "the smallest number of words of
      ;; 'free' (unclaimed, available for use) movable garbage-collected storage"
      ;; that the collector must leave after a collection; initial value 8192.
      ;; "A large min will result in fewer total garbage collections."
      ;; Apply gc-min growth ONLY when collected? is #t (a collection ran).
      ;; Capacity grows geometrically (×3/2) to also avoid O(n²) cost.
      ;; Capped at fix-max (2^35-1); Racket error if needed > fix-max.
      ;;
      ;; Explicit <GC> (mdl-gc) bypasses this path entirely and does NOT apply
      ;; gc-min growth: it calls mdl-collect-logical! directly, leaving capacity
      ;; unchanged.  This matches the manual: min is an automatic-GC parameter.
      (when collected?
        (let* ([gc-min (current-mdl-gc-min)]  ; MDL manual ch.22, initial 8192
               [free-after (mdl-memory-free memory)])
          (when (< free-after (max words gc-min))
            (define needed (+ (mdl-memory-used memory) (max words gc-min)))
            (when (> needed fix-max)
              (error 'mdl-gc
                     "storage overflow: ~a logical words needed, exceeds FIX maximum ~a"
                     needed fix-max))
            (set-mdl-memory-capacity!
             memory
             (min fix-max
                  (max needed
                       (inexact->exact
                        (ceiling (* (mdl-memory-capacity memory) 3/2)))))))))))
  (mdl-memory-register! memory value words))

(define (mdl-deliver-occurrence! occurrence)
  (define header (mdl-interrupt-occurrence-header occurrence))
  (check-emittable-event 'mdl-deliver-occurrence! (mdl-iheader-name header))
  (when (active-iheader? header)
    (define state (current-interrupt-state))
    (define old-level (mdl-interrupt-state-level state))
    (dynamic-wind
      (lambda () (set-mdl-interrupt-state-level! state (mdl-iheader-priority header)))
      (lambda ()
        ;; Snapshot list order, but re-check active membership before each
        ;; call so OFF during dispatch suppresses a later action.
        (for ([handler (in-list (mdl-iheader-handlers header))])
          (when (and (active-iheader? header) (mdl-handler-active? handler))
            (mdl-apply-evaluated (mdl-handler-applicable handler)
                                 (mdl-interrupt-occurrence-arguments occurrence)))))
      (lambda () (set-mdl-interrupt-state-level! state old-level)))
    (mdl-drain-pending!)))

(define (mdl-drain-pending!)
  (define state (current-interrupt-state))
  (let loop ()
    (define pending (mdl-interrupt-state-pending state))
    (define eligible
      (for/first ([occurrence (in-list pending)]
                  #:when (or (not (active-iheader?
                                   (mdl-interrupt-occurrence-header occurrence)))
                             (> (mdl-iheader-priority
                                 (mdl-interrupt-occurrence-header occurrence))
                                (mdl-interrupt-state-level state))))
        occurrence))
    (when eligible
      (set-mdl-interrupt-state-pending!
       state (remove eligible pending eq?))
      (mdl-deliver-occurrence! eligible)
      (loop))))

(define (mdl-int-level . args)
  (define state (current-interrupt-state))
  (case (length args)
    [(0) (mdl-interrupt-state-level state)]
    [(1)
     (define new-level (car args))
     (unless (and (exact-integer? new-level)
                  (<= fix-min new-level fix-max))
       (error 'mdl-int-level "INT-LEVEL requires a FIX"))
     (define old-level (mdl-interrupt-state-level state))
     (set-mdl-interrupt-state-level! state new-level)
     ;; Also flush an eligible occurrence after an exceptional handler exit:
     ;; cleanup restored the level but deliberately preserved the original
     ;; exception instead of running another handler in its unwind path.
     (mdl-drain-pending!)
     old-level]
    [else (error 'mdl-int-level "INT-LEVEL expects zero or one FIX")]))

(define (mdl-enable header)
  (check-session-iheader 'mdl-enable header)
  (set-mdl-iheader-enabled?! header #t)
  header)

(define (mdl-disable header)
  (check-session-iheader 'mdl-disable header)
  (set-mdl-iheader-enabled?! header #f)
  header)

(define (mdl-event . args)
  (define events (atom-space-events (current-mdl-atom-space)))
  (case (length args)
    [(1)
     (define header (car args))
     (unless (mdl-iheader? header)
       (error 'mdl-event "EVENT requires IHEADER or name and priority"))
     (unless (eq? (mdl-iheader-owner header) (current-mdl-atom-space))
       (error 'mdl-event "IHEADER belongs to another MDL session"))
     (hash-set! events (mdl-iheader-name header) header)
     (set-mdl-iheader-enabled?! header #t)
     header]
    [(2)
     (define name (mdl-string-snapshot 'mdl-event (car args)
                                       "EVENT name must be STRING in this slice"))
     (define priority (cadr args))
     (unless (and (exact-integer? priority) (<= fix-min priority fix-max)
                  (positive? priority))
       (error 'mdl-event "EVENT priority must be a positive FIX"))
     (when (member name unsupported-predefined-interrupt-names)
       (error 'mdl-event "unsupported predefined EVENT ~a" name))
     (hash-ref events name
               (lambda ()
                 (define header (mdl-iheader (current-mdl-atom-space)
                                             name priority '() #t))
                 (hash-set! events name header)
                 header))]
    [else (error 'mdl-event "EVENT expects IHEADER or name and priority")]))

(define (mdl-install-handler . args)
  (unless (= (length args) 2)
    (error 'mdl-handler "HANDLER expects IHEADER and APPLICABLE"))
  (define header (car args))
  (define action (cadr args))
  (unless (mdl-iheader? header)
    (error 'mdl-handler "HANDLER first argument must be IHEADER"))
  (unless (eq? (mdl-iheader-owner header) (current-mdl-atom-space))
    (error 'mdl-handler "IHEADER belongs to another MDL session"))
  (define handler
    (cond
      [(mdl-handler? action)
       (unless (and (eq? (mdl-handler-header action) header)
                    (not (mdl-handler-active? action)))
         (error 'mdl-handler "HANDLER already in use or belongs to another IHEADER"))
       (set-mdl-handler-active?! action #t)
       action]
      [(or (procedure? action) (mdl-function? action))
       (mdl-handler header action #t)]
      [else (error 'mdl-handler "unsupported HANDLER action; expected FUNCTION or SUBR")]))
  (set-mdl-iheader-handlers! header
                             (cons handler (mdl-iheader-handlers header)))
  handler)

(define (mdl-off . args)
  (unless (= (length args) 1)
    (error 'mdl-off "OFF expects one IHEADER or HANDLER"))
  (define object (car args))
  (cond
    [(mdl-handler? object)
     (define header (mdl-handler-header object))
     (unless (eq? (mdl-iheader-owner header) (current-mdl-atom-space))
       (error 'mdl-off "HANDLER belongs to another MDL session"))
     (set-mdl-iheader-handlers! header
       (filter (lambda (entry) (not (eq? entry object)))
               (mdl-iheader-handlers header)))
     (set-mdl-handler-active?! object #f)
     object]
    [(mdl-iheader? object)
     (unless (eq? (mdl-iheader-owner object) (current-mdl-atom-space))
       (error 'mdl-off "IHEADER belongs to another MDL session"))
     (define events (atom-space-events (current-mdl-atom-space)))
     (unless (eq? (hash-ref events (mdl-iheader-name object) #f) object)
       (error 'mdl-off "IHEADER has no active event association"))
     (hash-remove! events (mdl-iheader-name object))
     (set-mdl-iheader-enabled?! object #f)
     object]
    [else (error 'mdl-off "OFF expects IHEADER or HANDLER")]))

;; Manual ch.21.6: <ON name applicable priority> = <HANDLER <EVENT name
;; priority> applicable>; it finds or creates the IHEADER, associates and
;; enables it, prepends a new HANDLER and returns that HANDLER. Every
;; argument is validated before anything is registered. The optional
;; process/which arguments are unsupported in this slice.
(define (mdl-on . args)
  (case (length args)
    [(3) (void)]
    [(4 5) (error 'mdl-on "ON process and which arguments are unsupported in this slice")]
    [else (error 'mdl-on "ON expects name, applicable and priority")])
  (define name-value (car args))
  (define name (mdl-string-snapshot 'mdl-on name-value
                                    "ON name must be STRING in this slice"))
  (define action (cadr args))
  (define priority (caddr args))
  (unless (or (procedure? action) (mdl-function? action))
    (error 'mdl-on "unsupported ON applicable; expected FUNCTION or SUBR"))
  (unless (and (exact-integer? priority) (<= fix-min priority fix-max)
               (positive? priority))
    (error 'mdl-on "ON priority must be a positive FIX"))
  (when (member name unsupported-predefined-interrupt-names)
    (error 'mdl-on "unsupported predefined EVENT ~a" name))
  (define header (mdl-enable (mdl-event name-value priority)))
  (mdl-install-handler header action))

;; ADR-0048 host-only view of the session's SAVE records (never an MDL
;; primitive): immutable records, oldest first.
(struct mdl-save-record (sequence file-spec int-level) #:transparent)
(define (mdl-save-records)
  (reverse (atom-space-save-records (current-mdl-atom-space))))

;; ADR-0048 (maintainer decision 2026-11-23, superseding ADR-0047 part 2):
;; <SAVE file-spec:STRING [gc?:FALSE]> (manual 11.6.1) records a session
;; save and returns a fresh "SAVED". It writes no file, performs no GC and
;; has no interrupt side effect (INT-LEVEL is only read). Arguments arrive
;; already evaluated (ordinary SUBR) and are validated before recording.
(define (mdl-save . args)
  (unless (<= 1 (length args) 2)
    (error 'SAVE "SAVE expects a file-spec STRING and an optional FALSE gc? (ADR-0048)"))
  (define file-spec
    (mdl-string-snapshot 'SAVE (car args)
                         "SAVE file-spec must be STRING (ADR-0048)"))
  (unless (or (null? (cdr args)) (mdl-false? (cadr args)))
    (error 'SAVE "SAVE gc? must be FALSE; this session never collects on SAVE (ADR-0048)"))
  (define space (current-mdl-atom-space))
  (define records (atom-space-save-records space))
  (set-atom-space-save-records!
   space
   (cons (mdl-save-record (add1 (length records)) file-spec
                          (mdl-interrupt-state-level (current-interrupt-state)))
         records))
  (string-copy "SAVED"))

;; ---------------------------------------------------------------------------
;; S11 / ADR-0054: QUIT ends the MDL session (manual 23.3). It never calls
;; Racket `exit`: it raises the dedicated host value mdl-quit-signal, which is
;; not an exn (so no exn:fail? handler intercepts it) and not an MDL ERROR (so
;; no MDL ERROR handler, e.g. the game's HANDLE, runs). Being a raise, it is
;; not an MDL transfer: every UNWIND it crosses skips its cleanup (ADR-0051),
;; while dynamic-wind host bookkeeping is restored. The host loop catches it
;; at the session boundary and returns an mdl-session-outcome.
(struct mdl-quit-signal ())
(define (mdl-quit . args)
  (case (length args)
    [(0) (raise (mdl-quit-signal))]
    [(1) (error 'QUIT "an exit-status argument is not supported (ADR-0054)")]
    [else (error 'QUIT "TOO-MANY-ARGUMENTS-SUPPLIED")]))

;; S11 / ADR-0055: OPEN under the maintainer's virtual no-file policy ("OPEN
;; returns FALSE, no file"). Only RECORD's five-STRING form
;; <OPEN mode name1 name2 device directory> (77rooms.mud:731, 736, 748) with
;; mode READB, PRINT or PRINTO is supported. It never touches the host file
;; system and returns #FALSE (reason file-spec status): the session's virtual
;; directory is empty and read-only, so READB is "No such file or directory"
;; (2) and PRINT/PRINTO are "Permission denied" (13), the values pinned
;; Confusion returns for an absent log in a read-only directory (Probe D2/D7).
;; The status is never *600130* (196696), RECORD's busy-retry code. The file
;; spec is built as Confusion builds it: directory "/" name1 "." name2.
(struct mdl-open-record (mode file-spec status) #:transparent)
(define (mdl-open-records)
  (reverse (atom-space-open-records (current-mdl-atom-space))))
(define open-denials
  '(("READB" "No such file or directory" 2)
    ("PRINT" "Permission denied" 13)
    ("PRINTO" "Permission denied" 13)))
(define (mdl-open . args)
  (unless (= (length args) 5)
    (error 'OPEN
           "only the five-STRING form <OPEN mode name1 name2 device directory> is supported (ADR-0055)"))
  (unless (andmap mdl-string? args)
    (error 'OPEN "every argument must be a STRING (ADR-0055)"))
  (define-values (mode name1 name2 device directory)
    (apply values (map mdl-string-content args)))
  (define file-spec (string-append directory "/" name1 "." name2))
  (cond
    [(equal? mode "READ") (open-read-only name1 name2 device directory file-spec)]
    [else
     (define denial (assoc mode open-denials))
     (unless denial
       (error 'OPEN "mode ~s is not supported; only READB, PRINT and PRINTO are (ADR-0055)" mode))
     (define status (caddr denial))
     (define space (current-mdl-atom-space))
     (set-atom-space-open-records!
      space (cons (mdl-open-record mode (string->immutable-string file-spec) status)
                  (atom-space-open-records space)))
     (mdl-false (list (string-copy (cadr denial)) (string-copy file-spec) status))]))

;; M4 S10 (issue #171; ADR-0055 amendment, maintainer decision 2026-11-24
;; "Read-only allowlist"). A host grants read access to individual files by
;; giving the session a list of mdl-read-only-file entries: the four names of
;; the five-STRING OPEN form, the pinned sha256 (lowercase hex) and size. A
;; name is 1-32 characters of [A-Za-z0-9], so no separator, dot, ".." or empty
;; component can occur; the file is directory/name1.name2 inside the session's
;; game directory (Confusion's file spec; the device is not part of it). The
;; host reader (mdl/loader.rkt) resolves and reads the file; this runtime
;; checks size and sha256 again before serving it.
(define read-only-name-rx #px"^[A-Za-z0-9]{1,32}$")
(define read-only-max-size 1048576)
(struct mdl-read-only-file (name1 name2 device directory sha256 size)
  #:transparent
  #:guard
  (lambda (name1 name2 device directory sha256 size _)
    (for ([n (in-list (list name1 name2 device directory))])
      (unless (and (string? n) (regexp-match? read-only-name-rx n))
        (raise-argument-error 'mdl-read-only-file "a name of 1-32 characters [A-Za-z0-9]" n)))
    (unless (and (string? sha256) (regexp-match? #px"^[0-9a-f]{64}$" sha256))
      (raise-argument-error 'mdl-read-only-file "a lowercase hexadecimal sha256" sha256))
    ;; At least 1 byte: the size pre-check before reading is what keeps a FIFO
    ;; or device file (never opened, never read) from being served or blocking
    ;; the read (independent review of S10).
    (unless (and (exact-integer? size) (<= 1 size read-only-max-size))
      (raise-argument-error 'mdl-read-only-file
                            (format "an exact size in 1..~a" read-only-max-size) size))
    (values (string->immutable-string name1) (string->immutable-string name2)
            (string->immutable-string device) (string->immutable-string directory)
            (string->immutable-string sha256) size)))
(define (read-only-file-key f)
  (list (mdl-read-only-file-name1 f) (mdl-read-only-file-name2 f)
        (mdl-read-only-file-device f) (mdl-read-only-file-directory f)))
(define (mdl-read-only-file-relative-path f)
  (string-append (mdl-read-only-file-directory f) "/" (mdl-read-only-file-name1 f)
                 "." (mdl-read-only-file-name2 f)))
(define (check-read-only-files! who files reader)
  (unless (and (list? files) (andmap mdl-read-only-file? files))
    (raise-argument-error who "(listof mdl-read-only-file?)" files))
  (unless (= (length (remove-duplicates (map read-only-file-key files))) (length files))
    (error who "duplicate read-only allowlist entry (ADR-0055 amendment)"))
  (when (and (pair? files) (not (and (procedure? reader) (procedure-arity-includes? reader 1))))
    (raise-argument-error who "a host reader procedure for a non-empty read-only allowlist" reader)))

;; OPEN "READ": exact, case-sensitive match of the four names against the
;; allowlist BEFORE any file-system access; no match is the strict error.
;; A match reads the whole content through the host reader (which checks the
;; path, links, file identity and size), checks size and sha256 here, and
;; serves a fresh read-only CHANNEL from the immutable bytes.
(define (open-read-only name1 name2 device directory file-spec)
  (define space (current-mdl-atom-space))
  (define entry
    (for/first ([f (in-list (atom-space-read-only-files space))]
                #:when (equal? (read-only-file-key f) (list name1 name2 device directory)))
      f))
  (unless entry
    (error 'OPEN
           "mode \"READ\" is not supported for ~a: it is not on this session's read-only allowlist (ADR-0055 amendment)"
           file-spec))
  (define content ((atom-space-read-only-reader space) entry))
  (unless (and (bytes? content) (= (bytes-length content) (mdl-read-only-file-size entry)))
    (error 'OPEN "~a: content size differs from the pinned size ~a (ADR-0055 amendment)"
           file-spec (mdl-read-only-file-size entry)))
  (unless (equal? (bytes->hex-string* (sha256-bytes content)) (mdl-read-only-file-sha256 entry))
    (error 'OPEN "~a: content sha256 differs from the pinned sha256 ~a (ADR-0055 amendment)"
           file-spec (mdl-read-only-file-sha256 entry)))
  (define in-use
    (for/list ([fc (in-list (atom-space-file-channels space))]
               #:unless (file-channel-closed? fc))
      (file-channel-number fc)))
  (define number (for/first ([n (in-naturals 3)] #:unless (memv n in-use)) n))
  ;; Confusion's file CHANNEL (HELP-INFO-REFERENCE.md): one predecessor slot,
  ;; then [number "READ" name1 name2 device directory name1 name2 device
  ;; directory status 0 #LOSE 0 0 0 0 10 0]. Element 10 is natively the
  ;; absolute host directory; here the requested directory (deviation: never
  ;; a host path, ADR-0055 amendment decision (c)).
  (define storage (mdl-vector 0 number (string-copy "READ")
                              (string-copy name1) (string-copy name2)
                              (string-copy device) (string-copy directory)
                              (string-copy name1) (string-copy name2)
                              (string-copy device) (string-copy directory)
                              0 0 (mdl-chtype 0 (mdl-root-atom "LOSE")) 0 0 0 0 10 0))
  (define view (mdl-rest storage 1))
  (define fc (file-channel (string->immutable-string file-spec) view (bytes-length content)
                           number (open-input-bytes content) #f))
  (hash-set! (atom-space-channels space) (mdl-array-storage storage)
             (host-channel 'READ #f #f fc))
  ;; ADR-0058: TOP refuses it as it refuses terminal CHANNELs.
  (hash-set! channel-storages (mdl-array-storage storage) #t)
  (set-atom-space-file-channels! space (cons fc (atom-space-file-channels space)))
  (mdl-typed-value (mdl-root-atom "CHANNEL") view))
(define (bytes->hex-string* bs)
  (apply string-append
         (for/list ([b (in-bytes bs)])
           (string-append (if (< b 16) "0" "") (number->string b 16)))))

;; Host introspection: the session's file CHANNELs, oldest first, as
;; (file-spec open|closed).
(define (mdl-file-channels)
  (for/list ([fc (in-list (reverse (atom-space-file-channels (current-mdl-atom-space))))])
    (list (file-channel-spec fc) (if (file-channel-closed? fc) 'closed 'open))))

;; The file record of an open file CHANNEL argument, after the CHANNEL checks
;; shared with READSTRING (TYPE, registered in this session, mode slot).
(define (file-channel-argument who channel)
  (define host (registered-channel-host who channel "argument must be of type CHANNEL"))
  (unless (channel-mode-intact? channel host)
    (error who "CHANNEL is not open in this MDL session"))
  host)

;; M4 S10: <FILE-LENGTH channel>, the content length in characters (= bytes;
;; native 4274 / 1527). Strict refusals carry the reference's ERROR names.
(define (mdl-file-length . args)
  (cond [(null? args) (error 'FILE-LENGTH "TOO-FEW-ARGUMENTS-SUPPLIED")]
        [(pair? (cdr args)) (error 'FILE-LENGTH "TOO-MANY-ARGUMENTS-SUPPLIED")])
  (define host (file-channel-argument 'FILE-LENGTH (car args)))
  (define fc (host-channel-file host))
  (unless fc
    (error 'FILE-LENGTH "FILE-LENGTH-UNAVAILABLE: not a file CHANNEL (ADR-0055 amendment)"))
  (when (file-channel-closed? fc)
    (error 'FILE-LENGTH "CHANNEL-CLOSED"))
  (file-channel-length fc))

;; M4 S10: <CLOSE channel> for a file CHANNEL: releases the content, marks the
;; record closed and clears elements 1 and 7-10 as Confusion does; returns the
;; CHANNEL. A closed file CHANNEL is returned again (native; decision (b)).
;; CLOSE of a terminal CHANNEL is not supported.
(define (mdl-close . args)
  (cond [(null? args) (error 'CLOSE "TOO-FEW-ARGUMENTS-SUPPLIED")]
        [(pair? (cdr args)) (error 'CLOSE "TOO-MANY-ARGUMENTS-SUPPLIED")])
  (define channel (car args))
  (define host (file-channel-argument 'CLOSE channel))
  (define fc (host-channel-file host))
  (unless fc
    (error 'CLOSE "CLOSE of a terminal CHANNEL is not supported (ADR-0055)"))
  (unless (file-channel-closed? fc)
    (set-file-channel-port! fc #f)
    (set-file-channel-closed?! fc #t)
    (define view (file-channel-view fc))
    (mdl-put! view 1 0)
    (for ([i (in-range 7 11)]) (mdl-put! view i (string-copy ""))))
  channel)

;; RESTORE stays intentionally unsupported (ADR-0048): it never reads or
;; writes a file and fails after ordinary SUBR argument evaluation.
(define (mdl-restore . args)
  (error 'RESTORE
         "restoring a saved image is not supported (maintainer decision 2026-11-23; ADR-0048)"))

;; ADR-0049 (maintainer decision 2026-11-23, "Inert REP + host loop"): a
;; predefined host value whose TYPE is SUBR (pinned Confusion: <TYPE ,REP> is
;; SUBR). Only REP uses this representation; other built-ins stay plain host
;; procedures. It is a Racket procedure, so every application path (FORM
;; call, APPLY, MAPF, HANDLER delivery, host mdl-apply) reaches `proc` after
;; ordinary SUBR argument evaluation, and APPLICABLE declarations match it.
(struct mdl-subr (name proc)
  #:property prop:procedure (struct-field-index proc)
  ;; Racket diagnostics name the SUBR (e.g. #<procedure:REP>), not a source line.
  #:property prop:object-name (struct-field-index name))

;; The default GVAL of ROOT REP. CONTIN stores it (<SETG SAVEREP ,REP>,
;; 77rooms.mud:301) and BLO tests its TYPE (77act1.mud:3), but applying it is
;; a strict error: this runtime never provides a raw MDL read-eval-print
;; loop. It reads no channel, evaluates nothing and prints nothing.
(define mdl-default-rep
  (mdl-subr
   'REP
   (lambda args
     (error 'REP
            "the default REP SUBR is inert; this runtime never provides a raw MDL read-eval-print loop (maintainer decision 2026-11-23; ADR-0049)"))))

(define (require-oblist who value)
  (unless (mdl-oblist? value)
    (error who "expected an MDL OBLIST, got ~a" value)))

(define (require-atom who value)
  (unless (mdl-atom? value)
    (error who "expected an MDL ATOM, got ~a" value)))

(define (mdl-moblist name [size 13])
  (require-atom 'mdl-moblist name)
  (unless (and (exact-integer? size) (positive? size))
    (error 'mdl-moblist "expected a positive bucket count"))
  (define named (atom-space-named (current-mdl-atom-space)))
  (hash-ref named name
            (lambda ()
              (define oblist (oblist-value name (make-hash) size))
              (hash-set! named name oblist)
              (mdl-put-association! name (mdl-root-atom "OBLIST") oblist)
              (mdl-put-association! oblist (mdl-root-atom "OBLIST") name)
              oblist)))

(define (mdl-root . args)
  (unless (null? args)
    (error 'mdl-root "Too many arguments to ROOT"))
  (atom-space-root (current-mdl-atom-space)))

(define (mdl-lookup name-value oblist)
  (define name (mdl-string-snapshot 'mdl-lookup name-value "expected a STRING PNAME"))
  (unless (mdl-oblist? oblist)
    (error 'mdl-lookup "expected an MDL OBLIST for PNAME ~a, got ~a"
           name oblist))
  (hash-ref (oblist-value-entries oblist) name (lambda () (mdl-false '()))))

(define (mdl-insert value oblist)
  (require-oblist 'mdl-insert oblist)
  (define atom
    (cond [(mdl-string? value)
           (atom-value (mdl-string-snapshot 'mdl-insert value "expected a STRING PNAME")
                       #f)]
          [(mdl-atom? value)
           (when (atom-value-oblist value)
             (error 'mdl-insert "ATOM is already on an OBLIST"))
           value]
          [else (error 'mdl-insert "expected a STRING or uninterned ATOM")]))
  (define name (atom-value-pname atom))
  (when (hash-has-key? (oblist-value-entries oblist) name)
    (error 'mdl-insert "ATOM with PNAME ~a is already on this OBLIST" name))
  (hash-set! (oblist-value-entries oblist) name atom)
  (set-atom-value-oblist! atom oblist)
  atom)

(define (mdl-remove . args)
  (define atom
    (case (length args)
      [(1) (define value (car args))
           (require-atom 'mdl-remove value)
           value]
      [(2) (define oblist (cadr args))
           (require-oblist 'mdl-remove oblist)
           (define value (mdl-lookup (car args) oblist))
           (if (mdl-false? value) #f value)]
      [else (error 'mdl-remove "expected ATOM or STRING and OBLIST")]))
  (if (and atom (atom-value-oblist atom))
      (begin
        (hash-remove! (oblist-value-entries (atom-value-oblist atom))
                      (atom-value-pname atom))
        (set-atom-value-oblist! atom #f)
        atom)
      (mdl-false '())))

;; Host-only introspection for reference comparisons (never an MDL
;; primitive, never reachable from MDL code): the PNAMEs currently on an
;; OBLIST, sorted.
(define (mdl-oblist-pnames oblist)
  (require-oblist 'mdl-oblist-pnames oblist)
  (sort (hash-keys (oblist-value-entries oblist)) string<?))

(define (mdl-oblist-of atom)
  (require-atom 'mdl-oblist? atom)
  (or (atom-value-oblist atom) (mdl-false '())))

(define (mdl-pname atom)
  (require-atom 'mdl-pname atom)
  (string-copy (atom-value-pname atom)))

(define (mdl-spname atom)
  (require-atom 'mdl-spname atom)
  (string->immutable-string (atom-value-pname atom)))

(define (validate-oblist-lookup who value)
  (unless (and (mpair? value)
               (let ([items (mdl-list->list value)])
                 (and (pair? items) (andmap mdl-oblist? items))))
    (error who "expected a nonempty LIST of OBLISTs"))
  value)

;; Manual 15.6: BLOCK pushes the current LVAL of OBLIST and SETs its
;; argument; ENDBLOCK pops and SETs. The stack belongs to the session and is
;; "entirely independent of functional application, binding, etc.": a
;; BLOCK inside a frame that binds OBLIST sets that binding, and a later
;; ENDBLOCK sets whichever binding is current then (Confusion
;; block-in-function-with-oblist-binding).
(define (mdl-block lookup)
  (validate-oblist-lookup 'mdl-block lookup)
  (define space (current-mdl-atom-space))
  (define previous (current-lookup-path 'mdl-block))
  (mdl-set! (mdl-root-atom "OBLIST") lookup)
  (set-atom-space-lookup-stack!
   space (cons previous (atom-space-lookup-stack space)))
  lookup)

(define (mdl-endblock)
  (define space (current-mdl-atom-space))
  (define stack (atom-space-lookup-stack space))
  (when (null? stack)
    (error 'mdl-endblock "ENDBLOCK without BLOCK"))
  (set-atom-space-lookup-stack! space (cdr stack))
  (mdl-set! (mdl-root-atom "OBLIST") (car stack)))

;; The ATOM the reader produces for NAME. With intern? #f nothing is created:
;; the result is #f when reading NAME would have to insert an ATOM or create
;; a trailer's OBLIST.
(define (resolve-pname who name intern?)
  (unless (string? name) (error who "expected a STRING PNAME"))
  (define trailer-match (regexp-match-positions #rx"!-" name))
  (define trailer-pos (and trailer-match (caar trailer-match)))
  (if trailer-pos
      (let* ([pname (substring name 0 trailer-pos)]
             [trailer (substring name (+ trailer-pos 2))])
        (when (string=? pname "")
          (error who "invalid OBLIST trailer ~a" name))
        ;; An empty trailer (A!-) names the session ROOT OBLIST directly,
        ;; with no .OBLIST lookup (Confusion prints ROOT atoms outside the
        ;; search path as A!-; review/R3R4-oblist-reference.json
        ;; empty-trailer-root). 81tell-repl.mud uses TOPLEVEL!-.
        (define oblist
          (cond [(string=? trailer "") (atom-space-root (current-mdl-atom-space))]
                [intern? (mdl-moblist (mdl-atom trailer))]
                ;; The OBLIST MOBLIST would return, if it exists already.
                [else (let ([owner (resolve-pname who trailer #f)])
                        (and owner
                             (hash-ref (atom-space-named (current-mdl-atom-space))
                                       owner #f)))]))
        (define found (if oblist (mdl-lookup pname oblist) (mdl-false '())))
        (cond [(not (mdl-false? found)) found]
              [intern? (mdl-insert pname oblist)]
              [else #f]))
      (let* ([lookups (mdl-list->list (current-lookup-path who))]
             [found (for/or ([oblist (in-list lookups)])
                      (define candidate (mdl-lookup name oblist))
                      (and (not (mdl-false? candidate)) candidate))])
        (or found (and intern? (mdl-insert name (car lookups)))))))

(define (mdl-atom name) (resolve-pname 'mdl-atom name #t))

;; Host-only (#199; never an MDL primitive): the ATOM that reading NAME in
;; this session would produce, or #f when no such ATOM exists yet. It never
;; interns and never creates an OBLIST, so a host read through it cannot
;; change the session's ATOMs.
(define (mdl-find-atom name) (resolve-pname 'mdl-find-atom name #f))

(define (mdl-list . vals)
  (foldr (lambda (value tail)
           (mdl-track-allocation! (mcons value tail) 2 "LIST"))
         '() vals))

(define (mdl-normalize-list value)
  (cond [(or (null? value) (mpair? value)) value]
        [(list? value) (apply mdl-list value)]
        [else (error 'mdl-list "expected LIST-primtype value")]))

(define (mdl-list->list value)
  (let loop ([remaining value] [seen (make-hasheq)])
    (cond [(null? remaining) '()]
          [(not (mpair? remaining)) (error 'mdl-list "improper LIST")]
          [(hash-has-key? seen remaining) (error 'mdl-list "cyclic LIST")]
          [else (hash-set! seen remaining #t)
                (cons (mcar remaining) (loop (mcdr remaining) seen))])))

(struct mdl-array (kind storage start length type-cell)
  #:constructor-name make-mdl-array)

(define (new-mdl-array kind storage start length element-type)
  (make-mdl-array kind storage start length (box element-type)))

(define (mdl-array-element-type array)
  (unbox (mdl-array-type-cell array)))

(define (set-mdl-array-element-type! array type)
  (set-box! (mdl-array-type-cell array) type))
(struct mdl-string-view (storage start length))
(struct mdl-typed-value (type value))
(struct mdl-word-value (bits))
(struct mdl-bits-value (width edge))

(define word-mask (sub1 (arithmetic-shift 1 36)))
(define fix-min (- (arithmetic-shift 1 35)))
(define fix-max (sub1 (arithmetic-shift 1 35)))

(define mdl-word? mdl-word-value?)

(define (mdl-string? value)
  (or (string? value) (mdl-string-view? value)))
(define (mdl-string-length value)
  (if (mdl-string-view? value)
      (mdl-string-view-length value)
      (string-length value)))
(define (mdl-string-ref value index)
  (if (mdl-string-view? value)
      (string-ref (mdl-string-view-storage value)
                  (+ (mdl-string-view-start value) index))
      (string-ref value index)))
(define (mdl-string-content value)
  (if (mdl-string-view? value)
      (substring (mdl-string-view-storage value)
                 (mdl-string-view-start value)
                 (+ (mdl-string-view-start value)
                    (mdl-string-view-length value)))
      value))
;; A primitive that consumes an MDL STRING argument by value (PNAMEs, OBLIST
;; keys, EVENT names, host file paths) accepts a native STRING or a shared
;; REST view, and takes an immutable copy of the visible characters. The
;; copy is the PNAME semantics (an atom's name never aliases user storage);
;; the user's STRING and its views keep sharing their own storage. Any
;; other TYPE fails with MESSAGE.
(define (mdl-string-snapshot who value message)
  (unless (mdl-string? value) (error who message))
  (string->immutable-string (mdl-string-content value)))
(define (mdl-string-set! value index ch)
  (define storage (if (mdl-string-view? value)
                      (mdl-string-view-storage value) value))
  (when (immutable? storage)
    (error 'mdl-put "immutable STRING literal cannot be mutated"))
  (string-set! storage
               (+ (if (mdl-string-view? value)
                      (mdl-string-view-start value) 0)
                  index)
               ch))
(define (mdl-string-rest value offset)
  (define start (if (mdl-string-view? value)
                    (mdl-string-view-start value) 0))
  (define storage (if (mdl-string-view? value)
                      (mdl-string-view-storage value) value))
  (mdl-string-view storage (+ start offset)
                   (- (mdl-string-length value) offset)))
(define mdl-word-bits mdl-word-value-bits)
(define (mdl-word value)
  (unless (and (exact-integer? value) (<= fix-min value word-mask))
    (error 'mdl-word "expected a 36-bit word value"))
  (mdl-word-value (bitwise-and value word-mask)))

(define (word-bits-of value)
  (define base (mdl-base value))
  (cond [(mdl-word? base) (mdl-word-bits base)]
        [(and (exact-integer? base) (<= fix-min base fix-max))
         (bitwise-and base word-mask)]
        [else (error 'mdl-word "expected FIX or WORD data")]))

(define (word-signed bits)
  (if (bitwise-bit-set? bits 35)
      (- bits (arithmetic-shift 1 36))
      bits))

(define (check-fix who value)
  (unless (and (exact-integer? value) (<= fix-min value fix-max))
    (error who "FIX overflow"))
  value)

(define (check-number who value)
  (unless (and (real? value) (= value value))
    (error who "expected MDL FIX or FLOAT"))
  (when (exact-integer? value) (check-fix who value))
  value)

(define (arithmetic-step who op left right)
  (check-number who left)
  (check-number who right)
  (if (and (exact-integer? left) (exact-integer? right))
      (check-fix who
                 (if (eq? who 'mdl-div)
                     (begin
                       (when (zero? right) (error who "division by zero"))
                       (quotient left right))
                     (op left right)))
      (let ([a (exact->inexact left)] [b (exact->inexact right)])
        (when (and (eq? who 'mdl-div) (zero? b))
          (error who "division by zero"))
        (define result (op a b))
        (when (or (eqv? result +inf.0) (eqv? result -inf.0)
                  (not (= result result)))
          (error who "FLOAT overflow"))
        result)))

(define (mdl-add . values)
  (for/fold ([acc 0]) ([value (in-list values)])
    (arithmetic-step 'mdl-add + acc value)))

(define (mdl-sub . values)
  (cond [(null? values) 0]
        [(null? (cdr values)) (arithmetic-step 'mdl-sub - 0 (car values))]
        [else (for/fold ([acc (check-number 'mdl-sub (car values))])
                        ([value (in-list (cdr values))])
                (arithmetic-step 'mdl-sub - acc value))]))

(define (mdl-mul . values)
  (for/fold ([acc 1]) ([value (in-list values)])
    (arithmetic-step 'mdl-mul * acc value)))

(define (mdl-div . values)
  (cond [(null? values) 1]
        [(null? (cdr values)) (arithmetic-step 'mdl-div / 1 (car values))]
        [else (for/fold ([acc (check-number 'mdl-div (car values))])
                        ([value (in-list (cdr values))])
                (arithmetic-step 'mdl-div / acc value))]))

;; The 36-bit target stores FLOAT in PDP-10 single precision: bit 0 sign,
;; bits 1-8 excess-128 exponent, bits 9-35 a normalized 27-bit fraction;
;; a negative FLOAT is the two's complement of the whole word. The host
;; keeps FLOAT as a flonum and derives this image only when a FLOAT is
;; reinterpreted as WORD-primtype data (CHTYPE). Flonums with no exact
;; 36-bit image fail instead of being rounded.
(define pdp10-fraction-bits 27)
(define pdp10-greatest-float
  (* (exact->inexact (sub1 (arithmetic-shift 1 pdp10-fraction-bits)))
     (expt 2.0 100)))

(define (float-word-bits who value)
  (define (unrepresentable)
    (error who "FLOAT has no exact PDP-10 FLOAT word image: ~a" value))
  (unless (and (flonum? value) (= value value)
               (not (eqv? value +inf.0)) (not (eqv? value -inf.0)))
    (unrepresentable))
  (if (zero? value)
      0
      (let* ([magnitude (inexact->exact (abs value))]
             [exponent (+ (- (integer-length (numerator magnitude))
                             (integer-length (denominator magnitude)))
                          1)]
             [fraction (* magnitude (expt 2 (- pdp10-fraction-bits exponent)))]
             [field (+ exponent 128)])
        (unless (and (exact-integer? fraction) (<= 0 field 255))
          (unrepresentable))
        (define positive (bitwise-ior (arithmetic-shift field pdp10-fraction-bits)
                                      fraction))
        (if (negative? value)
            (bitwise-and (- positive) word-mask)
            positive))))

(define (mdl-min . values)
  (if (null? values)
      pdp10-greatest-float
      (for/fold ([smallest (check-number 'mdl-min (car values))])
                ([value (in-list (cdr values))])
        (check-number 'mdl-min value)
        (define result (min smallest value))
        (if (or (inexact? smallest) (inexact? value))
            (exact->inexact result)
            result))))

;; M4 S5a (issue #122): MAX mirrors MIN: the same checked FIX/FLOAT
;; arguments, FLOAT contagion, a fold from the first argument. ADR-0059:
;; zero arguments give the least PDP-10 FLOAT, the exact negation of <MIN>
;; (not the pinned reference's host DBL_MIN, which is no identity for MAX).
(define pdp10-least-float (- pdp10-greatest-float))

(define (mdl-max . values)
  (if (null? values)
      pdp10-least-float
      (for/fold ([largest (check-number 'mdl-max (car values))])
                ([value (in-list (cdr values))])
        (check-number 'mdl-max value)
        (define result (max largest value))
        (if (or (inexact? largest) (inexact? value))
            (exact->inexact result)
            result))))

;; M4 S8 (issue #167): ABS of one checked FIX/FLOAT argument, keeping its
;; TYPE. -2^35 has no 36-bit FIX counterpart: check-fix makes it a strict
;; overflow (manual 3.5), never a wrap or a FLOAT (the pinned reference's
;; 64-bit FIX returns 2^35; documented deviation, docs/SEMANTICS.md).
(define (mdl-abs . args)
  (cond [(null? args) (error 'mdl-abs "TOO-FEW-ARGUMENTS-SUPPLIED")]
        [(pair? (cdr args)) (error 'mdl-abs "TOO-MANY-ARGUMENTS-SUPPLIED")]
        [else
         (define value (check-number 'mdl-abs (car args)))
         (if (exact-integer? value)
             (check-fix 'mdl-abs (abs value))
             (abs value))]))

;; M4 S9 (issue #169): the host sleeper of a live SLEEP. Host-only (never
;; reachable from MDL); tests install a recording fake. The default is
;; Racket's sleep, which a break (DrRacket Stop, Ctrl-C) interrupts.
(define current-mdl-sleeper
  (make-parameter (lambda (seconds) (sleep seconds))
                  (lambda (proc)
                    (unless (and (procedure? proc) (procedure-arity-includes? proc 1))
                      (raise-argument-error 'current-mdl-sleeper
                                            "(procedure-arity-includes/c 1)" proc))
                    proc)))

;; M4 S9 (issue #168, decision: emit the exact byte): IMAGE writes the one
;; byte CODE (0-127; control characters raw, never ^X) to a session PRINT
;; CHANNEL (default the LVAL of OUTCHAN) and returns CODE. No flush. Codes
;; outside 0-127 are strict (ADR-0050/0057; the reference writes CODE mod 256,
;; recorded deviation, docs/SEMANTICS.md).
(define (mdl-image . args)
  (cond [(null? args) (error 'IMAGE "TOO-FEW-ARGUMENTS-SUPPLIED")]
        [(> (length args) 2) (error 'IMAGE "TOO-MANY-ARGUMENTS-SUPPLIED")])
  (define code (car args))
  (unless (exact-integer? code)
    (error 'IMAGE "FIRST-ARG-WRONG-TYPE: expected a FIX character code"))
  (unless (<= 0 code 127)
    (error 'IMAGE "character code ~a is outside 0-127 (ADR-0050, ADR-0057)" code))
  (define host (channel-output-host 'IMAGE (if (null? (cdr args))
                                               (default-output-channel 'IMAGE)
                                               (cadr args))))
  (write-byte code (host-channel-output-port/strict 'IMAGE host))
  code)

;; M4 S9 (issue #169, decision: wait for real only on live clocks): SLEEP
;; validates a non-negative FIX (FLOAT refused, as the reference), then waits
;; through current-mdl-sleeper only if the session clock is live
;; (mdl-clock-live?: real, resumed, recording over a live source). It never
;; reads or advances the clock, and returns T in every mode. UNHANG is
;; accepted: no MDL interrupt can arrive during the wait in this runtime, so
;; it is never consulted. A break propagates unchanged.
(define (mdl-sleep . args)
  (cond [(null? args) (error 'SLEEP "TOO-FEW-ARGUMENTS-SUPPLIED")]
        [(> (length args) 2) (error 'SLEEP "TOO-MANY-ARGUMENTS-SUPPLIED")])
  (define seconds (car args))
  (unless (and (exact-integer? seconds) (<= fix-min seconds fix-max))
    (error 'SLEEP "FIRST-ARG-WRONG-TYPE: expected a FIX number of seconds"))
  (when (negative? seconds)
    (error 'SLEEP "ARGUMENT-OUT-OF-RANGE: SLEEP time negative"))
  (when (positive? seconds)
    ;; As READSTRING before it blocks: output written so far is visible
    ;; during the wait. Flushed in every clock mode, so that SLEEP's value
    ;; and errors (a port-less PRINT channel's strict S13 error) never
    ;; depend on the mode; only the wait does.
    (flush-terminal-output! 'SLEEP)
    (when (mdl-clock-live? (atom-space-clock (current-mdl-atom-space)))
      ((current-mdl-sleeper) seconds)))
  (mdl-root-atom "T"))

;; M4 S9 (issue #170, decision: a session-derived value with no clock read):
;; TIME ignores its (already evaluated) arguments and returns the FLOAT n.0
;; for the n-th TIME call of this session. Documented deviation from the
;; reference's CPU seconds (docs/SEMANTICS.md).
(define (mdl-time . _ignored)
  (define space (current-mdl-atom-space))
  (define n (add1 (atom-space-time-calls space)))
  (set-atom-space-time-calls! space n)
  (exact->inexact n))

(define (mdl-random . seeds)
  (when (> (length seeds) 2)
    (error 'mdl-random "RANDOM takes at most two FIX seeds"))
  (for ([seed (in-list seeds)])
    (unless (and (exact-integer? seed) (<= fix-min seed fix-max))
      (error 'mdl-random "RANDOM seeds must be signed 36-bit FIX values")))
  (apply random36-next! (atom-space-random-state (current-mdl-atom-space)) seeds))

;; ADR-0052: host-only observation of the current session's RANDOM state. A
;; detached copy; advancing it never consumes the session's sequence. No MDL
;; primitive exposes it.
(define (mdl-random-state-snapshot)
  (random36-state-copy (atom-space-random-state (current-mdl-atom-space))))

;; ADR-0054/ADR-0061: host-only copy of the messages of every MDL ERROR
;; signalled in the current session, oldest first.
(define (mdl-error-messages)
  (reverse (atom-space-mdl-errors (current-mdl-atom-space))))

(define (mdl-gettimedate . args)
  (unless (<= (length args) 2)
    (error 'mdl-gettimedate "too many arguments to GETTIMEDATE"))
  (define requested (if (null? args) (mdl-false '()) (car args)))
  (define utc? (and (= (length args) 2) (mdl-truthy? (cadr args))))
  (define-values (seconds micros)
    (cond
      ;; ADR-0052: only this "now" read uses the session clock, once.
      [(mdl-false? requested)
       (mdl-clock-now (atom-space-clock (current-mdl-atom-space)))]
      [(and (exact-integer? requested) (<= fix-min requested fix-max))
       (values requested 0)]
      [(and (mdl-array? requested)
            (eq? (mdl-array-kind requested) 'UVECTOR)
            (= (mdl-array-length requested) 2)
            (eq? (mdl-array-element-type requested) (mdl-root-atom "FIX")))
       (define sec (mdl-nth requested 1))
       (define usec (mdl-nth requested 2))
       (unless (and (exact-integer? sec) (exact-integer? usec)
                    (<= 0 usec 999999))
         (error 'mdl-gettimedate "invalid time UVECTOR"))
       (values sec usec)]
      [else (error 'mdl-gettimedate "wrong type of time to GETTIMEDATE")]))
  ;; ADR-0052: the session zone stands in for the host local zone.
  (define local? (and (not utc?)
                      (eq? (atom-space-time-zone (current-mdl-atom-space)) 'local)))
  (define date (seconds->date seconds local?))
  (mdl-uvector (date-second date) (date-minute date) (date-hour date)
               (date-day date) (date-month date) (date-year date) micros))

(define (mdl-mod left right)
  (check-fix 'mdl-mod left)
  (check-fix 'mdl-mod right)
  (when (zero? right) (error 'mdl-mod "division by zero"))
  (modulo left right))

(define (mdl-fix value)
  (check-number 'mdl-fix value)
  (check-fix 'mdl-fix (inexact->exact (truncate value))))

(define (mdl-float value)
  ;; Manual 3.4: FLOAT converts a FIX; pinned Confusion also rejects a
  ;; FLOAT argument ("Arg to FLOAT must be FIX").
  (unless (exact-integer? value)
    (error 'mdl-float "Arg to FLOAT must be FIX"))
  (exact->inexact (check-fix 'mdl-float value)))

(define (mdl-bits width [edge 0])
  (unless (and (exact-integer? width) (exact-integer? edge)
               (<= 0 width 36) (<= 0 edge 35) (<= (+ width edge) 36))
    (error 'mdl-bits "BITS range outside 36-bit WORD"))
  (mdl-bits-value width edge))

(define (bits-mask bits)
  (unless (mdl-bits-value? bits) (error 'mdl-bits "expected BITS value"))
  (sub1 (arithmetic-shift 1 (mdl-bits-value-width bits))))

(define (mdl-getbits from bits)
  (mdl-word (bitwise-and (arithmetic-shift (word-bits-of from)
                                          (- (mdl-bits-value-edge bits)))
                         (bits-mask bits))))

(define (mdl-putbits to bits [from 0])
  (define mask (arithmetic-shift (bits-mask bits) (mdl-bits-value-edge bits)))
  (mdl-word (bitwise-and word-mask
                         (bitwise-ior (bitwise-and (word-bits-of to)
                                                   (bitwise-not mask))
                                      (arithmetic-shift
                                       (bitwise-and (word-bits-of from)
                                                    (bits-mask bits))
                                       (mdl-bits-value-edge bits))))))

(define (word-fold op identity values)
  (mdl-word (bitwise-and word-mask
                         (for/fold ([acc identity]) ([value (in-list values)])
                           (op acc (word-bits-of value))))))

(define (mdl-andb . values) (word-fold bitwise-and word-mask values))
(define (mdl-orb . values) (word-fold bitwise-ior 0 values))
(define (mdl-xorb . values) (word-fold bitwise-xor 0 values))
(define (mdl-eqvb . values)
  (word-fold (lambda (a b) (bitwise-not (bitwise-xor a b)))
             word-mask values))

(define (mdl-lsh value amount)
  (check-fix 'mdl-lsh amount)
  (mdl-word (bitwise-and word-mask
                         (arithmetic-shift (word-bits-of value)
                                           (remainder amount 256)))))

(define (mdl-base value)
  (if (mdl-typed-value? value) (mdl-typed-value-value value) value))

;; STRING extraction and SEGMENT expansion must expose the same MDL
;; CHARACTER value. A host character remains accepted at the API boundary,
;; but source-visible extraction uses the typed WORD representation.
(define (mdl-character ch)
  (mdl-typed-value (mdl-root-atom "CHARACTER") (char->integer ch)))

(define (mdl-character-code value)
  (cond
    [(char? value) (char->integer value)]
    [(and (mdl-typed-value? value)
          (eq? (mdl-typed-value-type value) (mdl-root-atom "CHARACTER")))
     (define code (mdl-base value))
     (and (exact-integer? code)
          (<= 0 code #x10ffff)
          (not (<= #xd800 code #xdfff))
          code)]
    [else #f]))

(define (mdl-ascii value)
  (cond
    [(exact-integer? value)
     (unless (<= 0 value 127)
       (error 'mdl-ascii "Value for ASCII out of range"))
     (mdl-character (integer->char value))]
    [else
     (define code (mdl-character-code value))
     (unless code (error 'mdl-ascii "Argument to ASCII must be FIX or CHARACTER"))
     code]))

(define (mdl-type-name value)
  (cond [(mdl-typed-value? value) (mdl-atom-pname (mdl-typed-value-type value))]
        [(mdl-subr? value) "SUBR"]
        [(mdl-activation? value) "ACTIVATION"]
        [(mdl-error-frame? value) "FRAME"]
        [(mdl-word? value) "WORD"]
        [(mdl-bits-value? value) "BITS"]
        [(mdl-false? value) "FALSE"]
        [(mdl-tuple-value? value) "TUPLE"]
        [(mdl-macro? value) "MACRO"]
        [(mdl-function? value) "FUNCTION"]
        ;; ADR-0060: TYPE by representation (registry membership), never by a
        ;; name. A compiled DEFINE is a FUNCTION; a host built-in bound to a
        ;; ROOT name is a SUBR. Any other host procedure has no TYPE.
        [(compiled-function? value) "FUNCTION"]
        [(builtin-subr? value) "SUBR"]
        [(mdl-iheader? value) "IHEADER"]
        [(mdl-handler? value) "HANDLER"]
        [(mdl-decl-value? value) "DECL"]
        [(mdl-atom? value) "ATOM"]
        [(mdl-oblist? value) "OBLIST"]
        [(or (null? value) (mpair? value)) "LIST"]
        [(mdl-array? value) (symbol->string (mdl-array-kind value))]
        [(exact-integer? value) (check-fix 'mdl-type value) "FIX"]
        [(and (real? value) (inexact? value)) "FLOAT"]
        [(char? value) "CHARACTER"]
        [(mdl-string? value) "STRING"]
        [else (error 'mdl-type "unsupported MDL type ~a" value)]))

(define (mdl-vector . values)
  (define storage (list->vector values))
  (mdl-track-allocation! storage (+ (* 2 (length values)) 2) "VECTOR")
  (new-mdl-array 'VECTOR storage 0 (length values) #f))

;; Session-owned channels. A CHANNEL value is an MDL VECTOR of documented
;; slots; the host side lives in a host-channel record registered in the
;; current atom space, keyed by the VECTOR's shared backing storage (the
;; Racket vector inside the mdl-array), not by one mdl-array view. Every
;; view of that storage (CHTYPE round trips, REST/TOP/BACK views typed
;; CHANNEL again) therefore reaches the same host port; a shifted view still
;; has to pass the mode-slot check. port is the Racket port the channel
;; writes to (PRINT) or reads from (READ, READSTRING); #f means the host
;; supplied none, and every operation that needs it is a strict error
;; (ADR-0050: input, and from S13 part B also output). The only other value
;; is follow-current-output-port, the explicit opt-in of a PRINT channel that
;; writes to the host's current-output-port at each operation; only
;; mdl-ensure-terminal-channels! #:follow-current-output-port? #t creates it
;; (the process-wide default context and #lang mdl modules). A
;; CHANNEL VECTOR without a host record in the current space (forged by
;; CHTYPE, or belonging to another session) is rejected, never written.
;; at-eof? (ADR-0050) is the READ channel's host-side end-of-input flag: set
;; by a READSTRING that meets end of input, cleared by RESET. No CHANNEL slot
;; shows it (Confusion keeps it in STATUS, slot 11).
(struct host-channel (direction port [at-eof? #:mutable] file))
;; M4 S10 (#171, ADR-0055 amendment): the host record of a read-only file
;; CHANNEL (host-channel-file; #f for a terminal CHANNEL). spec: the file spec
;; "directory/name1.name2"; view: the CHANNEL's VECTOR view (slots updated at
;; end of file and CLOSE); length: the content length in characters; port: an
;; input port over the immutable content bytes, #f once closed. A file CHANNEL
;; has no terminal port (host-channel-port is #f), so no terminal operation
;; can reach it.
(struct file-channel (spec view length number [port #:mutable] [closed? #:mutable]))

;; ADR-0050 (review follow-up): terminal INPUT uses only a host-supplied
;; port. A session input channel without one is a strict error; READSTRING
;; never falls back to the process's own stdin.
(define (host-channel-port/strict who host)
  (or (host-channel-port host)
      (error who
             "this session's ~a CHANNEL has no host-supplied port; the runtime never falls back to the process's standard input (ADR-0050)"
             (host-channel-direction host))))

;; S13 part B (ADR-0050 "Explicit output port", maintainer decision
;; 2026-11-23): terminal OUTPUT uses only a host-supplied port too. Every
;; write and every flush resolves a PRINT channel's port here; a channel
;; without one is a strict error and nothing reaches a parameterized
;; current-output-port. The explicit opt-in marker (never a default of
;; make-mdl-session or make-mdl-context) follows current-output-port.
(define follow-current-output-port (string->uninterned-symbol "follow-current-output-port"))
(define (host-channel-output-port/strict who host)
  (define port (host-channel-port host))
  (cond [(output-port? port) port]
        [(eq? port follow-current-output-port) (current-output-port)]
        [else
         (error who
                "this session's PRINT CHANNEL has no host-supplied output port; the runtime never falls back to the host's current-output-port (ADR-0050)")]))

;; Exported host API (S13 review): a terminal CHANNEL made by a host must
;; carry a real port. A port-less PRINT channel registered beside OUTCHAN
;; would make every READSTRING pre-read flush and the final flush fail with
;; a misleading error; the only port-less terminal channels are a context's
;; own INCHAN/OUTCHAN, made by mdl-ensure-terminal-channels! below.
(define (mdl-make-terminal-channel mode port)
  (unless (or (input-port? port) (output-port? port))
    (error 'mdl-make-terminal-channel
           "a host-made ~a CHANNEL requires a Racket port (ADR-0050)" mode))
  (make-terminal-channel mode port))

;; ADR-0058: every backing vector of a CHANNEL made by make-terminal-channel,
;; in any atom space.
;; TOP refuses these: the reference has two slots before CHANNEL element 1
;; (the first is the script/echo channel LIST), this runtime models one.
(define channel-storages (make-weak-hasheq))

(define (make-terminal-channel mode [port #f])
  (unless (member mode '("READ" "PRINT"))
    (error 'mdl-make-terminal-channel "expected READ or PRINT mode"))
  (when (and port
             (not (and (equal? mode "PRINT") (eq? port follow-current-output-port))))
    (unless (if (equal? mode "PRINT") (output-port? port) (input-port? port))
      (error 'mdl-make-terminal-channel
             "~a CHANNEL requires a Racket ~a port" mode
             (if (equal? mode "PRINT") "output" "input"))))
  ;; #111: the host CHANNEL has one predecessor slot before its 19 visible
  ;; elements; original CONTIN uses BACK to reach it. #117 keys the host-port
  ;; registry by the shared backing storage, so the REST/BACK/TOP views of
  ;; this channel all resolve to the same port.
  ;; M4 #173: a PRINT channel starts with line width (element 13) 0, i.e.
  ;; unlimited, and column (element 14) 0, as pinned Confusion's terminal
  ;; OUTCHAN; the READ channel's element 13 is not interpreted.
  (define storage (mdl-vector 0 0 mode "" "" "" "" "" "" "TTY" ""
                              0 0 (if (equal? mode "PRINT") 0 80) 0 24 0 0 10 0))
  (hash-set! (atom-space-channels (current-mdl-atom-space))
             (mdl-array-storage storage)
             (host-channel (string->symbol mode) port #f #f))
  (hash-set! channel-storages (mdl-array-storage storage) #t)
  (mdl-typed-value (mdl-root-atom "CHANNEL") (mdl-rest storage 1)))

;; Execution contexts. A context is one globals table, one local frame
;; stack (whose last frame holds top-level LVALs) and one atom space. Every
;; context starts like a fresh interpreter (manual 11.2.7; Confusion
;; startup): INCHAN!-ROOT and OUTCHAN!-ROOT have the same terminal CHANNEL
;; as LVAL and GVAL. The bindings are stored in the tables when the context
;; is created, so GDECL, MANIFEST, SETG and ASSIGNED?/GASSIGNED? see them.
;; make-mdl-context builds a fresh context (used by make-mdl-session and by
;; hosts that want an isolated run); the process-wide default context (the
;; parameters' initial values) is initialized at the end of this module.
;; mdl-ensure-terminal-channels! is idempotent: it binds a fresh pair only
;; when neither the top-level LVAL nor the GVAL of that ATOM exists, so it
;; never replaces a host's or program's binding. #lang mdl modules call it
;; first; they run in the ambient context and therefore share it, and its
;; channels, with every other module run in that same context.
;; Output port (S13 part B, ADR-0050): make-mdl-context binds OUTCHAN to
;; OUTPUT-PORT, or to a port-less PRINT channel whose every write and flush
;; is a strict error. #:follow-current-output-port? #t on
;; mdl-ensure-terminal-channels! is the only way to get a PRINT channel that
;; writes to the host's current-output-port; it is an explicit opt-in used by
;; the process-wide default context and #lang mdl modules (low-level REPL/test
;; convenience) and is not accepted by make-mdl-context or make-mdl-session.
(struct mdl-context (globals locals atom-space))

(define (make-mdl-context #:output-port [output-port #f]
                          #:input-port [input-port #f]
                          #:clock [clock real-mdl-clock]
                          #:time-zone [time-zone 'local]
                          #:input-observer [input-observer #f]
                          #:read-only-files [read-only-files '()]
                          #:read-only-reader [read-only-reader #f]
                          #:decl-violation-recorder [decl-violation-recorder #f])
  (define context (mdl-context (make-hasheq) (list (make-hasheq))
                               (make-mdl-atom-space #:clock clock
                                                    #:time-zone time-zone
                                                    #:input-observer input-observer
                                                    #:read-only-files read-only-files
                                                    #:read-only-reader read-only-reader
                                                    #:decl-violation-recorder
                                                    decl-violation-recorder)))
  (call-with-mdl-context
   context
   (lambda ()
     (mdl-ensure-terminal-channels! #:output-port output-port
                                    #:input-port input-port)))
  context)

(define (call-with-mdl-context context thunk)
  (parameterize ([current-mdl-globals (mdl-context-globals context)]
                 [current-mdl-locals (mdl-context-locals context)]
                 [current-mdl-atom-space (mdl-context-atom-space context)])
    (thunk)))

(define (mdl-ensure-terminal-channels! #:output-port [output-port #f]
                                       #:input-port [input-port #f]
                                       #:follow-current-output-port? [follow? #f])
  (unless (boolean? follow?)
    (raise-argument-error 'mdl-ensure-terminal-channels! "boolean?" follow?))
  (when (and follow? output-port)
    (error 'mdl-ensure-terminal-channels!
           "give either #:output-port or #:follow-current-output-port?, not both (ADR-0050)"))
  (define space (current-mdl-atom-space))
  (define top-frame (last (current-mdl-locals)))
  (define globals (current-mdl-globals))
  (for ([atom (in-list (list (atom-space-inchan space)
                             (atom-space-outchan space)))]
        [mode (in-list '("READ" "PRINT"))]
        [port (in-list (list input-port
                             (if follow? follow-current-output-port output-port)))])
    (unless (or (hash-has-key? top-frame atom) (hash-has-key? globals atom))
      (define channel (make-terminal-channel mode port))
      (hash-set! top-frame atom channel)
      (mdl-setg! atom channel)))
  (void))

;; Manual 11.2.7 and pinned Confusion (mdl_setup_frame_for_print): an omitted
;; channel argument means the LVAL of OUTCHAN!-ROOT; the GVAL is not
;; consulted (review evidence r1-channel-reference.json).
(define (default-output-channel who)
  (define value (local-option (atom-space-outchan (current-mdl-atom-space))))
  (when (eq? value unassigned)
    (error who "no channel: OUTCHAN has no local value"))
  value)

;; Validate an output CHANNEL and return its host record. Mirrors Confusion's
;; checks: non-CHANNEL fails, then a non-PRINT mode slot fails; additionally
;; the CHANNEL must be open (registered) in this session. The Racket port is
;; resolved separately, after the operation's other arguments are validated
;; (S13 part B: a missing host port is a host error, so it never changes the
;; order of Confusion's argument errors).
(define (channel-output-host who channel)
  (unless (and (mdl-typed-value? channel)
               (equal? (mdl-atom-pname (mdl-typed-value-type channel)) "CHANNEL"))
    (error who "attempt to write to non-channel"))
  (define view (mdl-typed-value-value channel))
  (define host (and (mdl-array? view)
                    (hash-ref (atom-space-channels (current-mdl-atom-space))
                              (mdl-array-storage view) #f)))
  (unless (and host (eq? (mdl-typed-value-type channel) (mdl-root-atom "CHANNEL")))
    (error who "CHANNEL is not open in this MDL session"))
  (unless (and (eq? (host-channel-direction host) 'PRINT)
               (>= (mdl-array-length view) 2)
               (equal? (mdl-nth view 2) "PRINT"))
    (error who "~a requires an output channel"
           (case who
             [(mdl-printstring) "PRINTSTRING"]
             [(mdl-terpri) "TERPRI"]
             [(mdl-crlf) "CRLF"]
             [else who])))
  host)

;; ADR-0050: the host record of a CHANNEL registered in this session (TYPE the
;; ROOT atom CHANNEL, keyed by backing storage). A non-CHANNEL fails with
;; non-channel-message; a forged or foreign CHANNEL fails as not open.
(define (registered-channel-host who channel non-channel-message)
  (unless (and (mdl-typed-value? channel)
               (equal? (mdl-atom-pname (mdl-typed-value-type channel)) "CHANNEL"))
    (error who non-channel-message))
  (define view (mdl-typed-value-value channel))
  (define host (and (mdl-array? view)
                    (hash-ref (atom-space-channels (current-mdl-atom-space))
                              (mdl-array-storage view) #f)))
  (unless (and host (eq? (mdl-typed-value-type channel) (mdl-root-atom "CHANNEL")))
    (error who "CHANNEL is not open in this MDL session"))
  host)

;; Does the CHANNEL view's mode slot (element 2) still name the host
;; direction? A shifted (REST/BACK) or overwritten view does not.
(define (channel-mode-intact? channel host)
  (define view (mdl-typed-value-value channel))
  (and (>= (mdl-array-length view) 2)
       (equal? (mdl-nth view 2) (symbol->string (host-channel-direction host)))))

;; ADR-0050 RESET (manual 11.7.7; 77rooms.mud:303, 77defs.mud:433). For an
;; open terminal CHANNEL of this session it returns the same object. A READ
;; channel's end-of-input flag is cleared; queued unread input is kept (no
;; lookahead exists: READSTRING never peeks). No slot, predecessor slot or
;; association changes (deviation: Confusion zeroes STATUS and rewrites DEVN).
(define (mdl-reset . args)
  (unless (= (length args) 1)
    (error 'RESET "RESET takes exactly one CHANNEL argument (ADR-0050)"))
  (define channel (car args))
  (define host (registered-channel-host 'RESET channel
                                        "argument must be of type CHANNEL"))
  (unless (channel-mode-intact? channel host)
    (error 'RESET "CHANNEL is not open in this MDL session"))
  ;; M4 S10: natively RESET re-opens a file; not modelled (not used by the game).
  (when (host-channel-file host)
    (error 'RESET "RESET of a file CHANNEL is not supported (ADR-0055 amendment)"))
  (when (eq? (host-channel-direction host) 'READ)
    (set-host-channel-at-eof?! host #f))
  channel)

(define (mdl-ivector-build size make-element)
  (unless (and (exact-integer? size) (<= 0 size fix-max))
    (error 'mdl-ivector "IVECTOR length must be a nonnegative FIX"))
  (apply mdl-vector (for/list ([i (in-range size)]) (make-element))))

;; IVECTOR/IUVECTOR/ISTRING are ordinary SUBRs (manual 7.5.4; ILIST is not
;; implemented in this runtime yet and must reuse this policy): every
;; call path (compiled, interpreted, APPLY, MAPF) evaluates the arguments
;; once before the call, as for any SUBR. The optional second argument's
;; VALUE is then EVALed once per generated element, in element order, so
;; `<IVECTOR 3 '<SET A <+ .A 1>>>' counts 1 2 3 while
;; `<IVECTOR 3 <SET A <+ .A 1>>>' evaluates its argument once and fills
;; with the self-evaluating result.
(define (constructor-fill-thunk args default)
  (if (= (length args) 2)
      (let ([fill (cadr args)]) (lambda () (mdl-eval fill)))
      default))

(define (mdl-ivector . args)
  (unless (<= 1 (length args) 2)
    (error 'mdl-ivector "IVECTOR expects length and optional element"))
  (mdl-ivector-build (car args)
                     (constructor-fill-thunk
                      args (lambda () (mdl-chtype 0 (mdl-root-atom "LOSE"))))))

;; The first element fixes a UVECTOR's uniform TYPE; STRING is not a
;; permitted element TYPE.
(define (check-uvector-element! who value element-type)
  (when (or (string=? (mdl-type-name value) "STRING")
            (not (eq? (mdl-type value) element-type)))
    (error who "UVECTOR elements must have one permitted TYPE")))

(define (mdl-uvector . values)
  (define element-type (if (pair? values) (mdl-type (car values))
                           (mdl-root-atom "LOSE")))
  (for ([value (in-list values)])
    (check-uvector-element! 'mdl-uvector value element-type))
  (define storage (list->vector values))
  (mdl-track-allocation! storage (+ (length values) 2) "UVECTOR")
  (new-mdl-array 'UVECTOR storage 0 (length values) element-type))

(define (mdl-iuvector-build size make-element)
  (unless (and (exact-integer? size) (<= 0 size fix-max))
    (error 'mdl-iuvector "IUVECTOR length must be a nonnegative FIX"))
;; Validate each element as it is produced, so a non-uniform element stops
  ;; the per-element evaluation immediately (later fills never run).
  (define values
    (let loop ([i 0] [element-type #f] [acc '()])
      (if (= i size)
          (reverse acc)
          (let* ([value (make-element)]
                 [type (or element-type (mdl-type value))])
            (check-uvector-element! 'mdl-iuvector value type)
            (loop (add1 i) type (cons value acc))))))
  (if (null? values)
      (let ([storage (vector)])
        (mdl-track-allocation! storage 2 "UVECTOR")
        (new-mdl-array 'UVECTOR storage 0 0 (mdl-root-atom "LOSE")))
      (apply mdl-uvector values)))

(define (mdl-iuvector . args)
  (unless (<= 1 (length args) 2)
    (error 'mdl-iuvector "IUVECTOR expects length and optional element"))
  (mdl-iuvector-build (car args)
                      (constructor-fill-thunk
                       args (lambda () (mdl-chtype 0 (mdl-root-atom "LOSE"))))))

;; Unevaluated UVECTOR data may contain SEGMENT placeholders; uniformity is
;; enforced when the data is evaluated (see uniform-uvector).
(define (mdl-data-uvector . values)
  (define storage (list->vector values))
  (mdl-track-allocation! storage (+ (length values) 2) "UVECTOR")
  (new-mdl-array 'UVECTOR storage 0 (length values)
             (if (null? values) (mdl-root-atom "LOSE") #f)))

(define (mdl-list-head value who)
  (cond [(mdl-typed-value? value) (mdl-list-head (mdl-base value) who)]
        [(mdl-false? value) (mdl-false-value-payload value)]
        [(mdl-tuple-value? value) (mdl-tuple-value-payload value)]
        [(or (null? value) (mpair? value)) value]
        [else (error who "unsupported structured value ~a" value)]))

(define (mdl-list-tail value count who)
  (unless (and (exact-integer? count) (>= count 0))
    (error who "offset out of range"))
  (let loop ([remaining value] [n count])
    (cond [(zero? n) remaining]
          [(mpair? remaining) (loop (mcdr remaining) (sub1 n))]
          [else (error who "offset out of range")])))

(define (mdl-length value)
  (define base (mdl-base value))
  (cond [(mdl-array? base) (mdl-array-length base)]
        [(mdl-string? base) (mdl-string-length base)]
        [else (length (mdl-list->list (mdl-list-head value 'mdl-length)))]))

(define (mdl-rest value [offset 1])
  (unless (and (exact-integer? offset) (>= offset 0))
    (error 'mdl-rest "offset out of range"))
  (cond
    ;; REST of a TUPLE keeps the TUPLE type in the reference.
    [(mdl-tuple-value? value)
     (if (zero? offset)
         value
         (mdl-tuple-value
          (mdl-list-tail (mdl-tuple-value-payload value) offset 'mdl-rest)))]
    [else
     (define base (mdl-base value))
     (if (mdl-string? base)
         (begin
           (when (> offset (mdl-string-length base))
             (error 'mdl-rest "offset out of range"))
           (if (zero? offset) base (mdl-string-rest base offset)))
         (if (mdl-array? base)
         (begin
           (when (> offset (mdl-array-length base))
             (error 'mdl-rest "offset out of range"))
           (if (and (zero? offset) (not (mdl-typed-value? value))) value
               (make-mdl-array (mdl-array-kind base) (mdl-array-storage base)
                               (+ (mdl-array-start base) offset)
                               (- (mdl-array-length base) offset)
                               (mdl-array-type-cell base))))
         (mdl-list-tail (mdl-list-head value 'mdl-rest) offset 'mdl-rest)))]))

;; BACK (manual 7.6.2): the inverse of REST over the same storage. It keeps
;; the argument's exact TYPE (the TYPE atom itself, never its PNAME), as TOP
;; does and as pinned Confusion does; REST drops it (maintainer decision
;; 2026-11-23, ADR-0058 amendment; SEMANTICS "M3 BACK"). This covers the
;; terminal CHANNEL (previously the only TYPE kept) and every NEWTYPE of
;; VECTOR, UVECTOR or STRING.
(define (mdl-back value [offset 1])
  (unless (and (exact-integer? offset) (positive? offset) (<= offset fix-max))
    (error 'mdl-back "BACK requires a positive FIX offset"))
  (define base (mdl-base value))
  (define (retag result)
    (if (mdl-typed-value? value)
        (mdl-typed-value (mdl-typed-value-type value) result)
        result))
  (cond
    [(mdl-string? base)
     (define start (if (mdl-string-view? base) (mdl-string-view-start base) 0))
     (when (> offset start)
       (error 'mdl-back "BACK offset exceeds removed prefix"))
     (retag (mdl-string-view (mdl-string-view-storage base)
                             (- start offset)
                             (+ (mdl-string-length base) offset)))]
    [(mdl-array? base)
     (when (> offset (mdl-array-start base))
       (error 'mdl-back "BACK offset exceeds removed prefix"))
     (retag (make-mdl-array (mdl-array-kind base) (mdl-array-storage base)
                            (- (mdl-array-start base) offset)
                            (+ (mdl-array-length base) offset)
                            (mdl-array-type-cell base)))]
    [else (error 'mdl-back "BACK requires an array")]))

;; TOP (manual 7.6.2.2; SEMANTICS "M4 S4", ADR-0058): the inverse of every
;; REST. A new view over the SAME storage from its first element to its end
;; (never a copy; a UVECTOR keeps its shared UTYPE cell), re-tagged with the
;; argument's TYPE. Only the array PRIMTYPEs; LIST-primtype values, TUPLEs
;; and non-structured values are refused, as in the reference.
(define mdl-top
  (case-lambda
    [(value)
     (define base (mdl-base value))
     (define top
       (cond
         [(mdl-tuple-value? value) #f]
         [(mdl-string? base)
          (define storage (if (mdl-string-view? base) (mdl-string-view-storage base) base))
          (mdl-string-view storage 0 (string-length storage))]
         [(mdl-array? base)
          (when (hash-ref channel-storages (mdl-array-storage base) #f)
            (error 'mdl-top "TOP of CHANNEL storage is not supported (ADR-0058)"))
          (make-mdl-array (mdl-array-kind base) (mdl-array-storage base)
                          0 (vector-length (mdl-array-storage base))
                          (mdl-array-type-cell base))]
         [else #f]))
     (unless top
       (error 'mdl-top "Bad type for TOP: TOP requires a VECTOR, UVECTOR or STRING PRIMTYPE value"))
     (if (mdl-typed-value? value)
         (mdl-typed-value (mdl-typed-value-type value) top)
         top)]
    [() (error 'mdl-top "TOO-FEW-ARGUMENTS-SUPPLIED")]
    [(value . more) (error 'mdl-top "TOO-MANY-ARGUMENTS-SUPPLIED")]))

(define (mdl-check-index who value index)
  (unless (and (exact-integer? index) (<= 1 index) (<= index (mdl-length value)))
    (error who "index out of range")))

(define (mdl-nth value [index 1])
  (mdl-check-index 'mdl-nth value index)
  (define base (mdl-base value))
  (cond [(mdl-array? base)
         (vector-ref (mdl-array-storage base) (+ (mdl-array-start base) (sub1 index)))]
        [(mdl-string? base) (mdl-character (mdl-string-ref base (sub1 index)))]
        [else (mcar (mdl-list-tail (mdl-list-head value 'mdl-nth)
                                   (sub1 index) 'mdl-nth))]))

;; Association (property) storage (issue #53, D5; manual chapter 13). A PUT
;; whose dispatch does not reach the element store pairs the evaluated value
;; with an arbitrary (item indicator) pair; GET retrieves it. Both sides
;; match by ==?  identity (mdl-identical?): interning makes equal atom PNAMEs
;; the same atom, while reader-generated structures and strings stay
;; distinct, so a fresh (1 2 3) LIST and a new "abc" STRING miss, exactly as
;; recorded in docs/evidence/M2/atom-props-reference.json
;; (identity-keyed-retrieval, string-item-identity-miss). The table lives in
;; the atom space, so every session starts property-free; associations never
;; touch GVAL assignment (the recorded ,RAPPLIC UNBOUND-VARIABLE case) and
;; have no printed representation (no #ASOC output in the pinned build).
;; Strong item/indicator references are a documented garbage-collection
;; deviation until a weak store honoring MDL ==? can be established.
(define (mdl-association-table)
  (atom-space-associations (current-mdl-atom-space)))

;; Entries are (item indicator value). Lookup compares both keys using MDL
;; ==? and returns an (indicator . value) pair; the pair itself distinguishes
;; a stored FALSE value from an absent association.
(define (same-association? entry item indicator)
  (and (mdl-identical? (first entry) item)
       (mdl-identical? (second entry) indicator)))

(define (association-lookup item indicator)
  (for/first ([entry (in-list (unbox (mdl-association-table)))]
              #:when (same-association? entry item indicator))
    (cons (second entry) (third entry))))

(define (mdl-put-association! item indicator value)
  (set-box! (mdl-association-table)
            (cons (list item indicator value)
                  (for/list ([entry (in-list (unbox (mdl-association-table)))]
                             #:unless (same-association? entry item indicator))
                    entry)))
  item)

;; Two-argument PUT is the documented removal (manual 13.1.3); the pinned
;; build echoes the item, not the old value
;; (association-remove-two-arg-put).
(define (mdl-remove-association! item indicator)
  (set-box! (mdl-association-table)
            (for/list ([entry (in-list (unbox (mdl-association-table)))]
                       #:unless (same-association? entry item indicator))
              entry))
  item)

;; PUT/GET dispatch on structured primtypes: a FIX indicator on one of these
;; items reaches the original element store; every other indicator is an
;; association, including a FIX indicator on a non-structured item (the
;; recorded <PUT 5 DECL 'FIX> reference case). Pinned dispatch
;; mdl_builtin_eval_put, macros.cpp:4320-4330
;; (mdl_primtype_structured(arg->pt) && FIX/OFFSET indicator); OFFSET
;; indicators are out of this slice's scope and stay on the association path.
(define (mdl-structured-primtype? value)
  (and ;; Host procedures other than compiled DEFINEs are SUBRs (PRIMTYPE
       ;; WORD): unstructured, so they may carry FIX-keyed associations. A
       ;; compiled DEFINE is a FUNCTION, PRIMTYPE LIST (ADR-0060): it takes the
       ;; element path, which fails strictly because it has no body LIST.
       (not (and (procedure? value) (not (compiled-function? value))))
       (member (mdl-atom-pname (mdl-primtype value))
               '("LIST" "VECTOR" "UVECTOR" "TUPLE" "STRING"))
       #t))

;; PUT (manual 13.1): <PUT item indicator value> stores, <PUT item indicator>
;; removes, <PUT item> is TOO-FEW-ARGUMENTS-SUPPLIED (recorded diagnostic).
(define (mdl-put! . args)
  (case (length args)
    [(1) (error 'mdl-put "TOO-FEW-ARGUMENTS-SUPPLIED")]
    [(2)
     (define item (car args))
     (when (and (exact-integer? (cadr args)) (mdl-structured-primtype? item))
       (error 'mdl-put "TOO-FEW-ARGUMENTS-SUPPLIED"))
     (mdl-remove-association! item (cadr args))
     item]
    [(3)
     (define item (car args))
     (define indicator (cadr args))
     (define new-value (caddr args))
     (if (and (exact-integer? indicator) (mdl-structured-primtype? item))
         (mdl-put-element! item indicator new-value)
         (mdl-put-association! item indicator new-value))]
    [else (error 'mdl-put "TOO-MANY-ARGUMENTS-SUPPLIED")]))

;; The unchanged element store, with the reference's stderr diagnostics
;; (put-structured-fix-index-out-of-range and put-string-non-character).
(define (mdl-put-element! value index item)
  (unless (and (exact-integer? index) (>= index 1) (<= index (mdl-length value)))
    (error 'mdl-put "PUT index too large"))
  (define base (mdl-base value))
  (cond
    [(mdl-string? base)
     (define code (mdl-character-code item))
     (unless code
       (error 'mdl-put "Error in PUT: Strings may only contain CHARACTER type"))
     (mdl-string-set! base (sub1 index) (integer->char code))]
    [(mdl-array? base)
     (when (and (eq? (mdl-array-kind base) 'UVECTOR)
                (not (eq? (mdl-type item) (mdl-array-element-type base))))
       (error 'mdl-put "UVECTOR PUT type violation"))
     (vector-set! (mdl-array-storage base)
                  (+ (mdl-array-start base) (sub1 index)) item)]
    [else
     (set-mcar! (mdl-list-tail (mdl-list-head value 'mdl-put)
                                (sub1 index) 'mdl-put) item)])
  value)

;; GET (manual 13.1, inverse of PUT): a FIX indicator on a structured item
;; reads element `index` and rejects the optional exp with the recorded
;; diagnostic; otherwise the ==?-keyed association retrieval returns the
;; stored value, the exp value on a miss (get-exp-fallback), or #FALSE ()
;; (get-missing-property-false). Only the two-argument form and this one
;; optional exp exist in the pinned sources (grep evidence in ATOM-PROPS.md).
(define (mdl-get item [indicator unassigned] [exp unassigned])
  (when (and (eq? indicator unassigned) (not (mdl-structured-primtype? item)))
    (error 'mdl-get "GET requires an indicator for non-structured item"))
  (define selector (if (eq? indicator unassigned) 1 indicator))
  (cond
    [(and (exact-integer? selector) (mdl-structured-primtype? item))
     (unless (eq? exp unassigned)
       (error 'mdl-get "No EXP allowed for GET on structure"))
     (mdl-nth item selector)]
    [else
     (let ([found (association-lookup item selector)])
       (cond
         [found (cdr found)]
         [(not (eq? exp unassigned)) exp]
         [else (mdl-false '())]))]))

;; PUTREST rewires the tail of a LIST-primtype head. A TUPLE is its own
;; primitive type, so tuples must not expose or splice their payload
;; chains here; the primtype check also rejects typed values whose storage
;; is a tuple, as well as non-LIST operands.
(define (mdl-putrest! head tail)
  (define (require-list-primtype value)
    (define prim (mdl-primtype value))
    (unless (eq? prim (mdl-root-atom "LIST"))
      (error 'mdl-putrest "PUTREST requires LIST-primtype values, not ~a"
             (mdl-atom-pname prim))))
  (require-list-primtype head)
  (require-list-primtype tail)
  (define head-list (mdl-list-head head 'mdl-putrest))
  (unless (mpair? head-list)
    (error 'mdl-putrest "PUTREST requires nonempty LIST-primtype head"))
  (set-mcdr! head-list (mdl-list-head tail 'mdl-putrest))
  head)

(define (mdl-identical? left right)
  (define left-character (mdl-character-code left))
  (define right-character (mdl-character-code right))
  (cond [(and left-character right-character)
         (= left-character right-character)]
        [(and (mdl-typed-value? left) (mdl-typed-value? right))
         (and (eq? (mdl-typed-value-type left) (mdl-typed-value-type right))
              (mdl-identical? (mdl-base left) (mdl-base right)))]
        [(or (mdl-typed-value? left) (mdl-typed-value? right)) #f]
        [(and (mdl-word? left) (mdl-word? right))
         (= (mdl-word-bits left) (mdl-word-bits right))]
        [(and (mdl-bits-value? left) (mdl-bits-value? right))
         (and (= (mdl-bits-value-width left) (mdl-bits-value-width right))
              (= (mdl-bits-value-edge left) (mdl-bits-value-edge right)))]
        [(and (number? left) (number? right)) (eqv? left right)]
        [(and (mdl-false? left) (mdl-false? right))
         (eq? (mdl-false-value-payload left) (mdl-false-value-payload right))]
        [(and (mdl-array? left) (mdl-array? right))
      (and (eq? (mdl-array-kind left) (mdl-array-kind right))
           (eq? (mdl-array-storage left) (mdl-array-storage right))
           (= (mdl-array-start left) (mdl-array-start right))
           (= (mdl-array-length left) (mdl-array-length right)))]
        [(and (mdl-string? left) (mdl-string? right))
         (define left-storage (if (mdl-string-view? left)
                                  (mdl-string-view-storage left) left))
         (define right-storage (if (mdl-string-view? right)
                                   (mdl-string-view-storage right) right))
         (and (eq? left-storage right-storage)
              (= (if (mdl-string-view? left) (mdl-string-view-start left) 0)
                 (if (mdl-string-view? right) (mdl-string-view-start right) 0))
              (= (mdl-string-length left) (mdl-string-length right)))]
        [else (eq? left right)]))

(define (mdl-memq item structure)
  (define base (mdl-base structure))
  (cond
    [(mdl-string? base)
     ;; STRING MEMQ (MDL manual ch. 13): search each CHARACTER element for ==? identity.
     ;; A non-CHARACTER needle can never ==? a CHARACTER element in a STRING, so it
     ;; silently returns #FALSE () — Confusion confirms this for FIX and STRING needles.
     ;; On hit, return the string REST'd to that position (a view sharing storage with
     ;; the original — the view's start offset enables BACK to work correctly).
     (let ([char-code (mdl-character-code item)])
       (if (not char-code)
           (mdl-false '())
           (or (for/or ([i (in-range (mdl-string-length base))])
                 (and (= (char->integer (mdl-string-ref base i)) char-code)
                      (mdl-string-rest base i)))
               (mdl-false '()))))]
    [(or (null? base) (mpair? base) (mdl-array? base)
         (mdl-false? base) (mdl-tuple-value? base))
     (or (for/or ([offset (in-range (mdl-length structure))])
           (and (mdl-identical? item (mdl-nth structure (add1 offset)))
                (mdl-rest structure offset)))
         (mdl-false '()))]
    [else
     (error 'mdl-memq "Second arg to MEMQ must be structured")]))

;; MEMBER (manual §8.2.2; SEMANTICS "M3 primitive: MEMBER"; reference
;; docs/evidence/M3/MEMBER-REFERENCE.md). Structural =? search returning the
;; shared REST view, plus substring search when both arguments are PRIMTYPE
;; STRING. Not MEMQ: the comparison is mdl-equal?, never identity.
(define (mdl-member item structure)
  (define base (mdl-base structure))
  (cond
    [(mdl-string? base)
     (define needle (mdl-base item))
     (cond
       [(mdl-string? needle)
        (define n (mdl-string-content needle))
        (define h (mdl-string-content base))
        (define nlen (string-length n))
        (when (zero? nlen)
          (error 'mdl-member
                 "MEMBER: empty STRING needle in a STRING haystack is unsupported (the reference reads out of bounds; docs/evidence/M3/MEMBER-REFERENCE.md)"))
        (or (for/or ([i (in-range (add1 (- (string-length h) nlen)))])
              (and (for/and ([k (in-range nlen)])
                     (char=? (string-ref h (+ i k)) (string-ref n k)))
                   (mdl-rest structure i)))
            (mdl-false '()))]
       [else
        ;; Element search: =? against each CHARACTER element.
        (or (for/or ([i (in-range (mdl-string-length base))])
              (and (mdl-equal? item (mdl-character (mdl-string-ref base i)))
                   (mdl-rest structure i)))
            (mdl-false '()))])]
    [(mdl-array? base)
     (unless (memq (mdl-array-kind base) '(VECTOR UVECTOR))
       (error 'mdl-member "MEMBER: unsupported structured kind ~a"
              (mdl-array-kind base)))
     (or (for/or ([i (in-range (mdl-array-length base))])
           (and (mdl-equal? item (mdl-nth base (add1 i)))
                (mdl-rest structure i)))
         (mdl-false '()))]
    [(mdl-tuple-value? base)
     (error 'mdl-member
            "MEMBER: TUPLE haystack is unsupported (not probed against the reference)")]
    [(or (null? base) (mpair? base) (mdl-false? base))
     (define seen (make-hasheq))
     (let loop ([tail (mdl-list-head structure 'mdl-member)])
       (cond
         [(null? tail) (mdl-false '())]
         [(not (mpair? tail)) (error 'mdl-member "MEMBER: improper LIST")]
         [(hash-ref seen tail #f)
          (error 'mdl-member "MEMBER: cyclic LIST haystack without a match")]
         [else
          (hash-set! seen tail #t)
          (if (mdl-equal? item (mcar tail))
              tail
              (loop (mcdr tail)))]))]
    [else
     (error 'mdl-member "Second arg to MEMBER must be structured")]))

(define (mdl-equal? left right)
  (define active (make-hasheq))
  (define (compare-structured a b thunk)
    (define rights
      (hash-ref active a
                (lambda ()
                  (define fresh (make-hasheq))
                  (hash-set! active a fresh)
                  fresh)))
    (when (hash-has-key? rights b)
      (error 'mdl-equal? "unsupported cyclic structural equality"))
    (hash-set! rights b #t)
    (dynamic-wind void thunk (lambda () (hash-remove! rights b))))
  (define (loop a b)
    (cond [(mdl-identical? a b) #t]
          [(and (mdl-typed-value? a) (mdl-typed-value? b))
           (and (eq? (mdl-typed-value-type a) (mdl-typed-value-type b))
                (compare-structured a b
                  (lambda () (loop (mdl-base a) (mdl-base b)))))]
          [(or (mdl-typed-value? a) (mdl-typed-value? b)) #f]
          [(and (mdl-word? a) (mdl-word? b))
           (= (mdl-word-bits a) (mdl-word-bits b))]
          [(and (mdl-bits-value? a) (mdl-bits-value? b))
           (mdl-identical? a b)]
          [(and (mdl-array? a) (mdl-array? b))
           (and (eq? (mdl-array-kind a) (mdl-array-kind b))
                (= (mdl-array-length a) (mdl-array-length b))
                (compare-structured a b
                  (lambda ()
                    (for/and ([i (in-range (mdl-array-length a))])
                      (loop (mdl-nth a (add1 i))
                            (mdl-nth b (add1 i)))))))]
          [(and (mdl-string? a) (mdl-string? b))
           (string=? (mdl-string-content a) (mdl-string-content b))]
          [(and (mdl-false? a) (mdl-false? b))
           (compare-structured a b
             (lambda ()
               (loop (mdl-false-value-payload a)
                     (mdl-false-value-payload b))))]
          [(and (mdl-tuple-value? a) (mdl-tuple-value? b))
           (compare-structured a b
             (lambda ()
               (loop (mdl-tuple-value-payload a)
                     (mdl-tuple-value-payload b))))]
          [(or (mdl-tuple-value? a) (mdl-tuple-value? b)) #f]
          [(and (mpair? a) (mpair? b))
           (compare-structured a b
             (lambda ()
               (and (loop (mcar a) (mcar b))
                    (loop (mcdr a) (mcdr b)))))]
          [else (equal? a b)]))
  (loop left right))

(define (mdl-truthy? value)
  (when (boolean? value)
    (error 'mdl-truthy? "host Boolean escaped into an MDL truth test: ~a" value))
  (not (mdl-false? value)))

(define (mdl-boolean value)
  (if value (mdl-root-atom "T") (mdl-false '())))

(define (mdl-type value)
  (if (mdl-typed-value? value)
      (mdl-typed-value-type value)
      (mdl-root-atom (mdl-type-name value))))

(define (mdl-typeprim type)
  (require-atom 'mdl-typeprim type)
  (define prim
    (hash-ref (atom-space-types (current-mdl-atom-space)) type
              (lambda () (error 'mdl-typeprim "unknown MDL TYPE ~a" (mdl-atom-pname type)))))
  (mdl-root-atom prim))

(define (mdl-primtype value)
  (mdl-typeprim (mdl-type value)))

(define (check-decl-pattern-shape pattern who)
  ;; Referenced type ATOMs may be declared later in the same source file.
  ;; Reject unsupported syntax now; resolve those ATOMs on CHTYPE.
  (define (bad)
    (error who "unsupported declaration pattern"))
  (define (check-structure-elements elements)
    (when (null? elements) (bad))
    (for ([element (in-list elements)] [index (in-naturals)])
      (cond
        [(mdl-array? element)
         (unless (eq? (mdl-array-kind element) 'VECTOR) (bad))
         (define bracket (decl-bracket-items element))
         (unless (and (>= (length bracket) 2)
                      (or (and (eq? (car bracket) (mdl-root-atom "REST"))
                               (= index (sub1 (length elements))))
                          (and (exact-integer? (car bracket))
                               (positive? (car bracket)))))
           (bad))
         (for ([part (in-list (cdr bracket))]) (check part))]
        [else (check element)])))
  (define (check value)
    (cond
      [(mdl-atom? value) (void)]
      [(mdl-form? value)
       (define items (form-elements value))
       (unless (pair? items) (bad))
       (define head (car items))
       (cond
         [(mdl-atom? head)
          (case (string->symbol (mdl-atom-pname head))
            [(OR)
             (when (null? (cdr items)) (bad))
             (for ([part (in-list (cdr items))]) (check part))]
            [(PRIMTYPE)
             (unless (and (= (length items) 2) (mdl-atom? (cadr items)))
               (bad))]
            [(LIST VECTOR UVECTOR TUPLE)
             (check-structure-elements (cdr items))]
            [else
             (if (registered-structured-type? head)
                 (check-structure-elements (cdr items))
                 (bad))])]
         [(mdl-form? head)
          (define head-items (form-elements head))
          (unless (and (= (length head-items) 2)
                       (eq? (car head-items) (mdl-root-atom "PRIMTYPE"))
                       (mdl-atom? (cadr head-items)))
            (bad))
          (check-structure-elements (cdr items))]
         [else (bad)])]
      [else (bad)]))
  (check pattern))

(define (mdl-newtype name base-type . declaration)
  (require-atom 'mdl-newtype name)
  (when (> (length declaration) 1)
    (error 'mdl-newtype "TOO-MANY-ARGUMENTS-SUPPLIED"))
  (define prim (mdl-typeprim base-type))
  (define types (atom-space-types (current-mdl-atom-space)))
  (when (and (hash-has-key? types name)
             (not (string=? (hash-ref types name) (mdl-atom-pname prim))))
    (error 'mdl-newtype "MDL TYPE already exists with another primitive type: ~a"
           (mdl-atom-pname name)))
  (when (pair? declaration)
    (check-decl-pattern-shape (car declaration) 'mdl-newtype))
  (hash-set! types name (mdl-atom-pname prim))
  ;; The historical Pattern may refer to types defined later in the same
  ;; source file. Store its unevaluated value now and resolve it on CHTYPE.
  (when (pair? declaration)
    (mdl-put-association! name (mdl-root-atom "DECL") (car declaration)))
  name)

(define (mdl-chtype value type)
  (require-atom 'mdl-chtype type)
  (define desired-prim (mdl-typeprim type))
  (unless (eq? (mdl-primtype value) desired-prim)
    (error 'mdl-chtype "primitive type mismatch"))
  (define converted
    (if (eq? (mdl-type value) type)
      value
      ;; TARGET is the PNAME of a ROOT built-in TYPE, or #f for any other TYPE
      ;; atom (S2 review: a user TYPE merely named SEGMENT/LIST/FALSE must not
      ;; take a built-in conversion branch).
      (let* ([base (mdl-base value)]
             [builtin? (hash-has-key? (atom-space-builtins (current-mdl-atom-space)) type)]
             [target (and builtin? (mdl-atom-pname type))])
        (when (and builtin?
                   (not (member target '("ATOM" "LIST" "FALSE" "VECTOR" "UVECTOR" "STRING"
                                         "FIX" "WORD" "LOSE" "CHANNEL"
                                         "SEGMENT" "CHARACTER"))))
          (error 'mdl-chtype "unsupported built-in TYPE conversion"))
        (when (and (not (or (null? base) (mpair? base) (mdl-atom? base)
                            (mdl-string? base)
                            (mdl-false? base) (mdl-array? base)))
                   (not (string=? (mdl-atom-pname desired-prim) "WORD")))
          (error 'mdl-chtype "unsupported primitive storage conversion"))
        (cond [(string=? (mdl-atom-pname desired-prim) "WORD")
               (define bits
                 (if (flonum? base)
                     (float-word-bits 'mdl-chtype base)
                     (word-bits-of base)))
               (cond [(equal? target "FIX")
                      (word-signed bits)]
                     [(equal? target "WORD")
                      (mdl-word bits)]
                     ;; The one CHARACTER representation (`mdl-character`),
                     ;; within the documented 0..127 range (ADR-0057; the
                     ;; reference accepts any WORD value). FLOAT bits are
                     ;; not reinterpreted as a CHARACTER.
                     [(equal? target "CHARACTER")
                      (when (flonum? base)
                        (error 'mdl-chtype "unsupported FLOAT to CHARACTER conversion"))
                      (define code (word-signed bits))
                      (unless (<= 0 code 127)
                        (error 'mdl-chtype "CHARACTER code out of supported range 0..127: ~a" code))
                      (mdl-character (integer->char code))]
                     [(or (exact-integer? base) (mdl-word? base) (flonum? base))
                      (mdl-typed-value type (mdl-word bits))]
                     [else (error 'mdl-chtype "unsupported WORD reinterpretation")])]
              [(equal? target "LIST")
               (mdl-list-head base 'mdl-chtype)]
              [(equal? target "FALSE")
               (mdl-false (mdl-list-head base 'mdl-chtype))]
              ;; A SEGMENT tags the same LIST cells, like a FORM (ADR-0056).
              [(equal? target "SEGMENT")
               (mdl-typed-value type (mdl-list-head base 'mdl-chtype))]
              [(equal? target "ATOM") base]
              [(equal? target "STRING") base]
              [(or (equal? target "VECTOR") (equal? target "UVECTOR"))
               base]
              [(member (mdl-atom-pname desired-prim) '("ATOM" "LIST" "VECTOR" "UVECTOR" "STRING"))
               (mdl-typed-value type base)]
              [else (error 'mdl-chtype "unsupported primitive type conversion")]))))
  (define declared (association-lookup type (mdl-root-atom "DECL")))
  (when declared
    (define pattern (normalize-decl-pattern (cdr declared) #f #f "CHTYPE"))
    (unless (matches-decl? converted pattern)
      (error 'mdl-chtype "TYPE-MISMATCH: value does not satisfy NEWTYPE declaration")))
  converted)

(define (mdl-chutype value type)
  (define base (mdl-base value))
  (unless (and (mdl-array? base) (eq? (mdl-array-kind base) 'UVECTOR))
    (error 'mdl-chutype "CHUTYPE requires UVECTOR"))
  (require-atom 'mdl-chutype type)
  (define target-prim (mdl-typeprim type))
  (unless (member (mdl-atom-pname target-prim)
                  '("ATOM" "LIST" "WORD" "VECTOR" "UVECTOR"))
    (error 'mdl-chutype "TYPE not valid for UVECTOR"))
  (define old-type (mdl-array-element-type base))
  (unless (or (eq? old-type (mdl-root-atom "LOSE"))
              (eq? (mdl-typeprim old-type) target-prim))
    (error 'mdl-chutype "cannot change element primitive type"))
  (define converted
    (for/list ([index (in-range (vector-length (mdl-array-storage base)))])
      (define old (vector-ref (mdl-array-storage base) index))
      (if (eq? old-type (mdl-root-atom "LOSE"))
          (case (string->symbol (mdl-atom-pname target-prim))
            [(WORD) (mdl-chtype 0 type)]
            [(LIST) (mdl-chtype '() type)]
            [(VECTOR) (mdl-chtype (mdl-vector) type)]
            [(UVECTOR) (mdl-chtype (mdl-uvector) type)]
            [else (error 'mdl-chutype "uninitialized ATOM element unsupported")])
          (mdl-chtype old type))))
  (for ([new (in-list converted)] [index (in-naturals)])
    (vector-set! (mdl-array-storage base) index new))
  (set-mdl-array-element-type! base type)
  value)

(define (mdl-utype value)
  (define base (mdl-base value))
  (unless (and (mdl-array? base) (eq? (mdl-array-kind base) 'UVECTOR))
    (error 'mdl-utype "UTYPE requires UVECTOR"))
  (if (mdl-array-element-type base)
      (mdl-array-element-type base)
      (mdl-false '())))

(define (mdl-string . pieces)
  (apply string-append
         (for/list ([piece (in-list pieces)])
           (cond [(mdl-string? piece) (mdl-string-content piece)]
                 [(mdl-character-code piece)
                  (string (integer->char (mdl-character-code piece)))]
                 [else (error 'mdl-string
                              "STRING expects STRING or CHARACTER arguments")]))))

(define (mdl-istring-build size make-character)
  (unless (and (exact-integer? size) (<= 0 size fix-max))
    (error 'mdl-istring "ISTRING length must be a nonnegative FIX"))
  (define result (make-string size #\nul))
  (for ([index (in-range size)])
    (define code (mdl-character-code (make-character)))
    (unless code
      (error 'mdl-istring "ISTRING fill must evaluate to CHARACTER"))
    (string-set! result index (integer->char code)))
  result)

(define (mdl-istring . args)
  (unless (<= 1 (length args) 2)
    (error 'mdl-istring "ISTRING expects length and optional CHARACTER"))
  (mdl-istring-build (car args)
                     (constructor-fill-thunk
                      args (lambda () (mdl-character #\nul)))))

(define (mdl-printstring buffer [channel (default-output-channel 'mdl-printstring)]
                         [count #f])
  (define host (channel-output-host 'mdl-printstring channel))
  (unless (mdl-string? buffer)
    (error 'mdl-printstring "PRINTSTRING expects a STRING buffer"))
  (when (and count (not (and (exact-integer? count) (>= count 0))))
    (error 'mdl-printstring "PRINTSTRING count must be a nonnegative FIX"))
  (define written (if count (min count (mdl-string-length buffer))
                      (mdl-string-length buffer)))
  ;; PRINTSTRING never breaks a line, but it moves the column (M4 #173).
  (channel-output! 'mdl-printstring channel host
                   (lambda (out line)
                     (write-text! out line (substring (mdl-string-content buffer) 0 written))))
  ;; The MDL manual returns the number of characters printed. Pinned
  ;; Confusion returns the original STRING; see docs/SEMANTICS.md.
  written)

(define (mdl-terpri [channel (default-output-channel 'mdl-terpri)])
  (channel-output! 'mdl-terpri channel (channel-output-host 'mdl-terpri channel)
                   write-newline!)
  (mdl-false '()))

(define (mdl-crlf [channel (default-output-channel 'mdl-crlf)])
  (channel-output! 'mdl-crlf channel (channel-output-host 'mdl-crlf channel)
                   write-newline!)
  (mdl-root-atom "T"))

;; M4 #173: line width and column of an output CHANNEL (manual 11.1.2 and
;; 11.2.8.1; pinned Confusion, evidence/M4/i173-print-reference-raw.json).
;; Element 13 is the width W, element 14 the column C, both read from the
;; CHANNEL on every call (a PUT takes effect at the next output) and both
;; required to be nonnegative FIXes. When W is nonzero every written
;; character advances C (a control character other than TAB/LF/VT/FF/CR by
;; two, Confusion's ^X width), CR sets it to 0, and a newline written by
;; TERPRI, CRLF or PRINT sets it to 0; when W is 0 C is neither advanced nor
;; reset. A line feed inside written text counts as a column, as in
;; Confusion. Text is laid out into a string first and written at once, so a
;; failed operation writes nothing and leaves C unchanged.
(struct line-state (width [column #:mutable]))

(define (channel-line-slot who channel index label)
  (define view (mdl-typed-value-value channel))
  (unless (and (mdl-array? view) (>= (mdl-array-length view) index))
    (error who "CHANNEL has no element ~a (~a) (M4 #173)" index label))
  (define value (mdl-nth view index))
  (unless (and (exact-nonnegative-integer? value) (<= value fix-max))
    (error who "CHANNEL element ~a (~a) must be a nonnegative FIX (M4 #173)" index label))
  value)

(define (char-columns ch)
  (define code (char->integer ch))
  (if (and (or (< code 32) (= code 127)) (not (<= 9 code 13))) 2 1))

(define (text-columns text)
  (for/sum ([ch (in-string text)]) (char-columns ch)))

(define (write-text! out line text)
  (write-string text out)
  (unless (zero? (line-state-width line))
    (for ([ch (in-string text)])
      (set-line-state-column! line (if (char=? ch #\return)
                                       0
                                       (+ (line-state-column line) (char-columns ch)))))))

(define (write-newline! out line)
  (newline out)
  (unless (zero? (line-state-width line))
    (set-line-state-column! line 0)))

;; A token is (text . separated?): SEPARATED? means a separating space goes
;; before it. Before each token, when W and C are nonzero and the token (plus
;; its space) does not fit in W - C columns, a newline replaces the space.
(define (write-tokens! out line tokens)
  (for ([token (in-list tokens)])
    (define text (car token))
    (define separated? (cdr token))
    (define width (line-state-width line))
    (define column (line-state-column line))
    (cond [(and (positive? width) (positive? column)
                (> (+ (text-columns text) (if separated? 1 0)) (- width column)))
           (write-newline! out line)]
          [separated? (write-text! out line " ")])
    (write-text! out line text)))

;; Lay out one output operation on CHANNEL (HOST already validated): EMIT
;; writes into a string port while updating the line state; then the text
;; reaches the host port and the new column is stored in element 14.
(define (channel-output! who channel host emit)
  (define line (line-state (channel-line-slot who channel 13 "line width")
                           (channel-line-slot who channel 14 "column")))
  (define out (open-output-string))
  (emit out line)
  (unless (<= (line-state-column line) fix-max)
    (error who "CHANNEL column would exceed the FIX range (M4 #173)"))
  (write-string (get-output-string out) (host-channel-output-port/strict who host))
  (unless (zero? (line-state-width line))
    (mdl-put-element! (mdl-typed-value-value channel) 14 (line-state-column line))))

;; ADR-0050 terminal printing. Text reaches the port unchanged only when every
;; character is printable ASCII, CR or LF: Confusion prints other control
;; characters in ^X notation and non-ASCII is not a 1977 terminal character,
;; so both are strict errors here. The whole text is checked before anything
;; is written. Line breaking: see channel-output! (M4 #173).
(define (terminal-text who content)
  (for ([ch (in-string content)])
    (define code (char->integer ch))
    (when (or (and (< code 32) (not (memv code '(10 13)))) (= code 127))
      (error who "control character (code ~a) is not supported; Confusion prints ^X notation (ADR-0050)"
             code))
    (when (> code 127)
      (error who "non-ASCII character (code ~a) is not supported (ADR-0050)" code)))
  content)

;; One or two arguments: the object and an optional output CHANNEL whose
;; default is the LVAL of OUTCHAN. Returns the CHANNEL and its validated host
;; record; the port is resolved after the object's text is validated.
(define (print-arguments who args)
  (unless (<= 1 (length args) 2)
    (error who "~a takes an object and an optional CHANNEL (ADR-0050)" who))
  (define channel (if (null? (cdr args)) (default-output-channel who) (cadr args)))
  (values channel (channel-output-host who channel)))

;; PRINC (manual 11.1.2.3): STRING (native or view) without quotes, CHARACTER
;; bare, FIX in decimal, written as one token. Returns the object. Every other
;; TYPE is strict.
(define (princ-text value)
  (cond [(mdl-string? value) (terminal-text 'PRINC (mdl-string-content value))]
        [(mdl-character-code value)
         => (lambda (code) (terminal-text 'PRINC (string (integer->char code))))]
        [(exact-integer? value) (number->string (check-fix 'PRINC value))]
        [else (error 'PRINC "unsupported TYPE ~a (ADR-0050)" (mdl-type-name value))]))

(define (mdl-princ . args)
  (define-values (channel host) (print-arguments 'PRINC args))
  (define tokens (list (cons (princ-text (car args)) #f)))
  (channel-output! 'PRINC channel host (lambda (out line) (write-tokens! out line tokens)))
  (car args))

;; PRIN1 text (manual 11.1.2.2: the UNPARSE representation; M4 #173). A leaf
;; is a FIX, an ATOM, a STRING or a CHARACTER, printed by mdl-unparse-value
;; (so its strict refusals apply), except that a reachable ATOM with an empty
;; PNAME prints nothing (Confusion: the game's ,NULL). Every other TYPE is
;; strict.
(define (prin1-leaf-text who value)
  (cond [(and (mdl-atom? value) (string=? (atom-value-pname value) ""))
         (unless (atom-reachable? who value)
           (error who "empty-PNAME ATOM not reachable via current OBLIST path; its trailer is not evidenced (M4 #173 B2)"))
         ""]
        ;; (An ATOM with a non-empty PNAME never gets here: prin1-tokens
        ;; prints it with atom-print-tokens.)
        [(or (exact-integer? value) (mdl-string? value)
             (mdl-character-code value))
         (terminal-text who (mdl-unparse-value who value))]
        [else (error who "unsupported TYPE ~a (ADR-0050)" (mdl-type-name value))]))

;; The PRIN1 tokens of VALUE (see write-tokens!), as Confusion splits them: a
;; leaf is one token; a LIST is `()`, or `(`, its elements (all but the first
;; separated) and `)`; a FALSE is `#FALSE` followed by its LIST part as a
;; separated element. The traversal reads the structure only. ACTIVE holds
;; the LIST cells and FALSEs being printed, so a structure that contains an
;; enclosing one is refused (Confusion would not terminate); a cyclic tail is
;; refused too. Each nesting level adds a distinct cell, so it is bounded.
(define (prin1-tokens who value)
  (define active (make-hasheq))
  (define tokens '())
  (define (emit! text separated?) (set! tokens (cons (cons text separated?) tokens)))
  (define (enter! key)
    (when (hash-ref active key #f)
      (error who "self-referencing LIST or FALSE cannot be printed (M4 #173)"))
    (hash-set! active key #t))
  (define (walk-list head separated?)
    (cond
      [(null? head) (emit! "()" separated?)]
      [else
       (enter! head)
       (emit! "(" separated?)
       (let loop ([cell head] [first? #t] [seen (make-hasheq)])
         (cond [(null? cell) (void)]
               [(not (mpair? cell)) (error who "improper LIST cannot be printed (M4 #173)")]
               [(hash-ref seen cell #f) (error who "cyclic LIST cannot be printed (M4 #173)")]
               [else (hash-set! seen cell #t)
                     (walk (mcar cell) (not first?))
                     (loop (mcdr cell) #f seen)]))
       (emit! ")" #f)
       (hash-remove! active head)]))
  (define (walk value separated?)
    (cond
      [(or (null? value) (mpair? value)) (walk-list value separated?)]
      [(mdl-false? value)
       (enter! value)
       (emit! "#FALSE" separated?)
       (walk-list (mdl-false-value-payload value) #t)
       (hash-remove! active value)]
      [(and (mdl-atom? value) (not (string=? (atom-value-pname value) "")))
       (let ([parts (atom-print-tokens who value)])
         (emit! (terminal-text who (car parts)) separated?)
         (for ([part (in-list (cdr parts))]) (emit! (terminal-text who part) #t)))]
      [else (emit! (prin1-leaf-text who value) separated?)]))
  (walk value #f)
  (reverse tokens))

(define (mdl-prin1 . args)
  (define-values (channel host) (print-arguments 'PRIN1 args))
  (define tokens (prin1-tokens 'PRIN1 (car args)))
  (channel-output! 'PRIN1 channel host (lambda (out line) (write-tokens! out line tokens)))
  (car args))

;; PRINT (manual 11.1.2.1; M4 #173): a newline (the line feed TERPRI writes),
;; the PRIN1 text laid out from column 0, then one space. The object's text
;; is validated before anything is written. Returns the object itself.
(define (mdl-print . args)
  (define-values (channel host) (print-arguments 'PRINT args))
  (define tokens (prin1-tokens 'PRINT (car args)))
  (channel-output! 'PRINT channel host
                   (lambda (out line)
                     (write-newline! out line)
                     (write-tokens! out line tokens)
                     (write-text! out line " ")))
  (car args))

;; ADR-0049 part 3 / ADR-0050 host top-level loop, in the current context.
;; It replaces Confusion's LISTEN for a game session and is never an MDL
;; evaluator: it applies ENTRY-THUNK (the caller's fixed entry FUNCTION),
;; prints the value with PRIN1 and TERPRI to the LVAL of OUTCHAN (maintainer
;; decision D1: the REP print of SAVE-IT's ,NULL), then on every pass
;; re-reads the GVAL of ROOT REP and applies it with no arguments. It
;; returns only when the program QUITs (ADR-0054): the boundary catches
;; exactly mdl-quit-signal and returns an mdl-session-outcome whose kind is
;; 'quit, or 'quit-after-mdl-error when any MDL ERROR was signalled during
;; the run (resolved or not; the messages are in mdl-errors, oldest first).
;; Every other ending raises: input exhausted, a strict error, an unresolved
;; MDL ERROR, the pass bound, a break. Terminal output is flushed on every
;; exit, and
;; that final flush never replaces the outcome and never runs host code
;; (review F2 and its independent review): when a raised value is leaving
;; the loop it is re-raised unchanged (same object), and every flush failure
;; is recorded as a secondary failure of it, readable with
;; mdl-host-loop-secondary-failures; when nothing was raised (a host escape
;; out of ON-EVENT) the first flush failure is raised and the rest are its
;; secondaries. A QUIT is not a failure, so a failed final flush after a
;; QUIT is raised the same way (the outcome is dropped: a transcript that may
;; be incomplete is never reported as a clean quit). ON-EVENT receives
;; host-only observations:
;; (entry-returned value), (pass n). It is never called after the loop body
;; has been left, so a callback that escapes cannot turn a failure into a
;; normal return.
(define (mdl-run-host-loop entry-thunk #:max-passes [max-passes #f]
                           #:on-event [on-event void])
  (unless (or (not max-passes) (exact-positive-integer? max-passes))
    (raise-argument-error 'mdl-run-host-loop "(or/c #f exact-positive-integer?)" max-passes))
  ;; LEAVING: a box holding the raised value now leaving the loop, set only by
  ;; the boundary handler, so a raise caught inside the loop never counts.
  (define leaving #f)
  (define space (current-mdl-atom-space))
  (define errors-before (length (atom-space-mdl-errors space)))
  (define (quit-outcome)
    (define all (atom-space-mdl-errors space))
    (define new (reverse (take all (- (length all) errors-before))))
    (mdl-session-outcome (if (null? new) 'quit 'quit-after-mdl-error) new))
  (dynamic-wind
   void
   (lambda ()
    (with-handlers ([mdl-quit-signal? (lambda (signal) (quit-outcome))]
                    [(lambda (raised) #t)
                     (lambda (raised) (set! leaving (box raised)) (raise raised))])
     (define value (entry-thunk))
     (on-event (list 'entry-returned value))
     (define channel (default-output-channel 'host-loop))
     (mdl-prin1 value channel)
     (mdl-terpri channel)
     (define rep-atom (mdl-root-atom "REP"))
     (let loop ([pass 1])
       (when (and max-passes (> pass max-passes))
         (error 'host-loop "the host loop exceeded its bound of ~a passes (ADR-0049)" max-passes))
       (define rep (global-option rep-atom))
       (when (eq? rep unassigned)
         (error 'host-loop "the GVAL of REP is unassigned (ADR-0049)"))
       (unless (or (procedure? rep) (mdl-function? rep))
         (error 'host-loop "the GVAL of REP is not an applicable FUNCTION or SUBR (ADR-0049)"))
       (on-event (list 'pass pass))
       (mdl-apply-evaluated rep '())
       (loop (add1 pass)))))
   (lambda ()
     (define failures (flush-terminal-output/collect 'host-loop))
     (cond [leaving
            ;; The primary outcome continues unchanged after this thunk.
            (record-secondary-failures! (unbox leaving) failures)]
           [(pair? failures)
            (record-secondary-failures! (car failures) (cdr failures))
            (raise (car failures))]))))

;; ADR-0054: what a host loop returns when the program QUITs.
(struct mdl-session-outcome (kind mdl-errors) #:transparent)

;; Secondary failures of a raised value that ended a host loop, keyed by the
;; eq? identity of that value (weakly). Host-only diagnostics: a failed final
;; flush is reported here instead of replacing the primary outcome.
(define secondary-failures (make-weak-hasheq))
(define (record-secondary-failures! primary failures)
  (when (pair? failures)
    (hash-set! secondary-failures primary
               (append (hash-ref secondary-failures primary '()) failures))))
(define (mdl-host-loop-secondary-failures primary)
  (hash-ref secondary-failures primary '()))

;; ADR-0050 / maintainer decision D3 ("Mirror, then strict"): reading a
;; terminal CHANNEL whose input already ended. A host-level Racket exception,
;; never an MDL ERROR, so no MDL ERROR handler (the game's HANDLE) runs; a host
;; must report it as a failure.
(struct exn:fail:mdl-input-exhausted exn:fail ())
(define input-exhausted-message
  (string-append "READSTRING: input exhausted: the session input ended and the "
                 "mirrored end-of-input read was already returned "
                 "(maintainer decision D3; ADR-0050)"))

;; Flush every terminal output port of this session, so a prompt written
;; with PRINC is visible before a blocking read (Confusion flushes stdout).
;; Each distinct port once, even if several PRINT channels share it. A PRINT
;; channel without a host port is a strict error (S13 part B): the flush
;; never falls back to current-output-port.
(define (terminal-output-hosts)
  (for/list ([host (in-list (hash-values (atom-space-channels (current-mdl-atom-space))))]
             #:when (eq? (host-channel-direction host) 'PRINT))
    host))
(define (flush-terminal-output! who)
  (for-each flush-output
            (remove-duplicates
             (for/list ([host (in-list (terminal-output-hosts))])
               (host-channel-output-port/strict who host))
             eq?)))
;; The host loop's final flush: try every port, returning every value raised
;; (in order) instead of stopping at the first, so one failed port does not
;; leave another unflushed. Any raised value counts, not only exn:fail;
;; breaks are not caught. Resolving a port-less PRINT channel's port raises
;; the strict S13 error, which is collected like any other flush failure
;; (F2: a secondary failure when a primary is leaving the loop).
(define (flush-terminal-output/collect who)
  (define (attempt thunk)
    (with-handlers ([(lambda (v) (not (exn:break? v))) (lambda (v) (values #f (box v)))])
      (values (thunk) #f)))
  (define-values (ports resolve-failures)
    (for/fold ([ports '()] [failures '()] #:result (values (reverse ports) (reverse failures)))
              ([host (in-list (terminal-output-hosts))])
      (define-values (port failure)
        (attempt (lambda () (host-channel-output-port/strict who host))))
      (if failure
          (values ports (cons (unbox failure) failures))
          (values (if (memq port ports) ports (cons port ports)) failures))))
  (append resolve-failures
          (for*/list ([port (in-list ports)]
                      [failure (in-value (let-values ([(_ f) (attempt (lambda () (flush-output port)))]) f))]
                      #:when failure)
            (unbox failure))))

;; ADR-0050 READSTRING (manual 11.4.1.2): <READSTRING buffer channel [stop]>
;; exactly as RDCOM and YES/NO use it. Arguments are validated first; then
;; output is flushed; then a channel whose end-of-input flag is set raises
;; exn:fail:mdl-input-exhausted. Otherwise characters are read until the
;; buffer view is full, a stop character is read (consumed, not stored) or
;; input ends (flag set, partial count returned). Characters are stored from
;; the view's position 1; the rest of the buffer is unchanged. No echo. A
;; `!` escapes the next character (S13 part A, see the read loop).
(define (mdl-readstring . args)
  (define n (length args))
  (unless (<= 2 n 4)
    (error 'READSTRING
           "READSTRING takes a buffer, a CHANNEL and an optional stop STRING (ADR-0050)"))
  (when (= n 4)
    (error 'READSTRING "an EOF routine argument is not supported (ADR-0050)"))
  (define buffer (car args))
  (define channel (cadr args))
  (define host (registered-channel-host 'READSTRING channel
                                        "argument must be of type CHANNEL"))
  (unless (and (eq? (host-channel-direction host) 'READ)
               (channel-mode-intact? channel host))
    (error 'READSTRING "READSTRING requires an input channel"))
  (unless (and (mdl-string? buffer)
               (not (immutable? (if (mdl-string-view? buffer)
                                    (mdl-string-view-storage buffer)
                                    buffer))))
    (error 'READSTRING "buffer must be a mutable STRING (ADR-0050)"))
  (if (host-channel-file host)
      (readstring-file host buffer (and (= n 3) (caddr args)))
      (readstring-terminal host buffer channel args n)))

;; The ADR-0050 / S13 part A read loop shared by terminal and file READSTRING.
;; NEXT-CHAR yields the next character or eof; LIMIT is how many characters
;; may be stored (at most the buffer view's length); STOPS the stop
;; characters. One unit is read per free slot: a character c, or the escape
;; pair `!` c, which yields c (the `!` is never stored or counted). The stop
;; test and the ASCII check apply to c whether or not it was escaped, so an
;; escaped stop character still ends the read and is consumed. `!`
;; immediately followed by end of input is stored as a literal `!`. A unit
;; starts only when there is room, so pairing resumes on the next READSTRING.
;; Returns (values count reason), reason 'full, 'stop or 'eof.
(define (readstring-units next-char buffer limit stops)
  (define (store-and-continue count ch)
    (mdl-string-set! buffer count ch)
    (add1 count))
  (let loop ([count 0])
    (if (>= count limit)
        (values count 'full)
        (let* ([lead (next-char)]
               [escaped? (and (char? lead) (char=? lead #\!))]
               [ch (if escaped? (next-char) lead)])
          (cond
            [(eof-object? ch)
             (values (if escaped? (store-and-continue count #\!) count) 'eof)]
            [(> (char->integer ch) 127)
             (error 'READSTRING "non-ASCII character (code ~a) in channel input is not supported (ADR-0050)"
                    (char->integer ch))]
            [(memv ch stops) (values count 'stop)]
            [else (loop (store-and-continue count ch))])))))

;; M4 S10 (#171; ADR-0055 amendment): READSTRING from a read-only file
;; CHANNEL. No terminal flush, and the ADR-0061 input observer is never
;; called: a file read is not input. STOP: #f (until the buffer is full), a
;; STRING of stop characters, or a FIX count 0..buffer length (native crashes
;; on a negative count and writes past the buffer for a larger one: strict
;; here). Meeting end of file returns the partial count, sets the end-of-file
;; flag and CHANNEL element 11 (status) to 1, as natively; any later read is a
;; strict error (native host error "Unexpected EOF"), never the terminal's
;; exn:fail:mdl-input-exhausted.
(define (readstring-file host buffer stop)
  (define fc (host-channel-file host))
  (define size (mdl-string-length buffer))
  (define-values (limit stops)
    (cond [(not stop) (values size '())]
          [(mdl-string? stop) (values size (string->list (mdl-string-content stop)))]
          [(exact-integer? stop)
           (unless (<= 0 stop size)
             (error 'READSTRING "count ~a is outside 0..~a, the buffer length (ADR-0055 amendment)"
                    stop size))
           (values stop '())]
          [else (error 'READSTRING "stop must be a STRING or a FIX count")]))
  (when (file-channel-closed? fc)
    (error 'READSTRING "attempt to read from a closed channel (ADR-0055 amendment)"))
  (when (host-channel-at-eof? host)
    (error 'READSTRING "unexpected end of file: ~a was already read to its end (ADR-0055 amendment)"
           (file-channel-spec fc)))
  (define port (file-channel-port fc))
  (define-values (count reason)
    (readstring-units (lambda () (read-char port)) buffer limit stops))
  (when (eq? reason 'eof)
    (set-host-channel-at-eof?! host #t)
    (mdl-put! (file-channel-view fc) 11 1))
  count)

(define (readstring-terminal host buffer channel args n)
  (define stops
    (cond [(= n 2) '()]
          [(mdl-string? (caddr args)) (string->list (mdl-string-content (caddr args)))]
          [(exact-integer? (caddr args))
           (error 'READSTRING "a FIX stop is not supported (ADR-0050)")]
          [else (error 'READSTRING "stop must be a STRING (ADR-0050)")]))
  (flush-terminal-output! 'READSTRING)
  (when (host-channel-at-eof? host)
    (raise (exn:fail:mdl-input-exhausted input-exhausted-message
                                         (current-continuation-marks))))
  (define port (host-channel-port/strict 'READSTRING host))
  (define size (mdl-string-length buffer))
  ;; ADR-0061: the host-only observer sees this call's entry (before any
  ;; character is read) and, when the call returns, every raw character it
  ;; consumed (escape `!` included, stop character included) and why it
  ;; ended. It observes; it never supplies input or changes the result.
  (define observer (atom-space-input-observer (current-mdl-atom-space)))
  (define consumed (and observer (open-output-string)))
  (when observer
    (observer 'enter
              (hasheq 'buffer buffer 'channel channel 'stops stops
                      'activation-kinds
                      (map mdl-activation-kind (current-mdl-activations))
                      'local-frames (current-mdl-locals))))
  (define (next-char)
    (define c (read-char port))
    (when (and consumed (char? c)) (write-char c consumed))
    c)
  (define (finish count reason)
    (when observer
      (observer 'complete
                (hasheq 'raw (get-output-string consumed) 'reason reason 'count count)))
    count)
  ;; S13 part A (ADR-0050 §3 as amended 2026-11-23; maintainer decision:
  ;; follow pinned Confusion, evidence READSTRING-BANG-REFERENCE.md): the
  ;; unit rules of readstring-units. End of input sets the flag.
  (define-values (count reason) (readstring-units next-char buffer size stops))
  (when (eq? reason 'eof)
    (set-host-channel-at-eof?! host #t))
  (finish count reason))

;; SUBSTRUC (MDL manual ch. 7, section 7.1.7)
;;
;; Contract: `<SUBSTRUC from rest amount to>` copies `amount` elements of
;; `from` starting at index `rest` into a fresh structure (or into `to` when
;; supplied) and returns it.  All arguments except `from` are optional:
;;   rest   – FIX, default 0.  Must be in [0, length(from)].
;;   amount – FIX, default remaining length after rest.  Must be in
;;            [0, length(from)-rest].
;;   to     – structured of the same PRIMTYPE as `from`; receives the copied
;;            elements starting at its position 0 (may be a REST view).
;;            For UVECTOR `to`: element type must equal source element type.
;;            For LIST `to`: mutates the first `count` mcars in-place.
;;            Returned as-is after modification.
;;
;; Confusion-confirmed error messages (class → message):
;;   SECOND-ARG-WRONG-TYPE   → "Second argument to SUBSTRUC must be a FIX"
;;   THIRD-ARG-WRONG-TYPE    → "Third argument to SUBSTRUC must be a FIX"
;;   "SUBSTRUC rest cannot be negative"
;;   "SUBSTRUC rest too large"
;;   "SUBSTRUC amount cannot be negative"
;;   "SUBSTRUC amount too big for source"
;;   ARG-WRONG-TYPE          → "Last arg to SUBSTRUC must be same type as primtype of first arg"
;;   TYPES-DIFFER-IN-UNIFORM-VECTOR → "SUBSTRUC UVECTOR to and from must be same type"
;;   ARGUMENT-OUT-OF-RANGE   → "SUBSTRUC destination too short"
;;
;; Supported primitive types: STRING, VECTOR, UVECTOR, LIST.
;; LIST `to` is NOT implemented (strict error); see evidence note for Confusion
;; behaviours (overlap and too-short) that differ from each other and from us.
;; Copying is atomic (all source elements are snapshotted before any write).
;; This prevents corruption when `from` and `to` are views on the same storage.
;; `to` must have the primitive TYPE itself (not a NEWTYPE alias); Confusion rejects
;; CHTyped `to` with ARG-WRONG-TYPE "Last arg to SUBSTRUC must be same type…".
;;
;; Probe evidence: docs/evidence/M3/S3-SUBSTRUC.md
;; Reference SHA: 6df359f6…  source: mdlzork bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3
(define (mdl-substruc from [rest 0] [amount #f] [to #f])
  ;; Item 4: distinguish wrong-type from negative-value errors.
  (unless (exact-integer? rest)
    (error 'mdl-substruc "Second argument to SUBSTRUC must be a FIX"))
  (when (< rest 0)
    (error 'mdl-substruc "SUBSTRUC rest cannot be negative"))
  (when amount
    (unless (exact-integer? amount)
      (error 'mdl-substruc "Third argument to SUBSTRUC must be a FIX"))
    (when (< amount 0)
      (error 'mdl-substruc "SUBSTRUC amount cannot be negative")))
  (define base (mdl-base from))
  (cond
    ;; ---- STRING ----
    [(mdl-string? base)
     (define src-len (mdl-string-length base))
     (when (> rest src-len)
       (error 'mdl-substruc "SUBSTRUC rest too large"))
     (define avail (- src-len rest))
     (define count (or amount avail))
     (when (> count avail)
       (error 'mdl-substruc "SUBSTRUC amount too big for source"))
     (cond
       [to
        ;; Nit 2: check exact TYPE (not just PRIMTYPE) — Confusion rejects CHTyped to.
        (unless (eq? (mdl-type to) (mdl-root-atom "STRING"))
          (error 'mdl-substruc "Last arg to SUBSTRUC must be same type as primtype of first arg"))
        (define to-base (mdl-base to))
        ;; Item 2: check destination length before any write.
        (when (< (mdl-string-length to-base) count)
          (error 'mdl-substruc "SUBSTRUC destination too short"))
        ;; Item 3: snapshot all source chars atomically, then write.
        (define snapshot
          (for/list ([i (in-range count)])
            (mdl-string-ref base (+ rest i))))
        (for ([i (in-range count)] [ch (in-list snapshot)])
          (mdl-string-set! to-base i ch))
        to]
       [else
        ;; Allocate a fresh independent mutable string.
        (define result (make-string count))
        (for ([i (in-range count)])
          (string-set! result i (mdl-string-ref base (+ rest i))))
        result])]
    ;; ---- VECTOR / UVECTOR ----
    [(mdl-array? base)
     (define src-len (mdl-array-length base))
     (when (> rest src-len)
       (error 'mdl-substruc "SUBSTRUC rest too large"))
     (define avail (- src-len rest))
     (define count (or amount avail))
     (when (> count avail)
       (error 'mdl-substruc "SUBSTRUC amount too big for source"))
     (define kind (mdl-array-kind base))
     (define storage (mdl-array-storage base))
     (define src-start (mdl-array-start base))
     (cond
       [to
        ;; Nit 2: check exact TYPE (not just PRIMTYPE) — Confusion rejects CHTyped to.
        (unless (eq? (mdl-type to) (mdl-root-atom (symbol->string kind)))
          (error 'mdl-substruc "Last arg to SUBSTRUC must be same type as primtype of first arg"))
        (define to-base (mdl-base to))
        ;; Item 1: UVECTOR → also check element-type compatibility.
        (when (eq? kind 'UVECTOR)
          (define src-elem (mdl-array-element-type base))
          (define to-elem  (mdl-array-element-type to-base))
          (unless (or (not src-elem) (not to-elem) (mdl-equal? src-elem to-elem))
            (error 'mdl-substruc "SUBSTRUC UVECTOR to and from must be same type")))
        ;; Item 2: check destination length before any write.
        (when (< (mdl-array-length to-base) count)
          (error 'mdl-substruc "SUBSTRUC destination too short"))
        ;; Item 3: snapshot all source elements atomically, then write.
        (define to-storage (mdl-array-storage to-base))
        (define to-start   (mdl-array-start to-base))
        (define snapshot
          (for/list ([i (in-range count)])
            (vector-ref storage (+ src-start rest i))))
        (for ([i (in-range count)] [v (in-list snapshot)])
          (vector-set! to-storage (+ to-start i) v))
        to]
       [else
        (define new-storage (make-vector count))
        (for ([i (in-range count)])
          (vector-set! new-storage i (vector-ref storage (+ src-start rest i))))
        (define word-count
          (case kind
            [(VECTOR) (+ (* 2 count) 2)]
            [else     (+ count 2)]))      ; UVECTOR
        (mdl-track-allocation! new-storage word-count (symbol->string kind))
        ;; Preserve element type for UVECTOR; use #f for VECTOR.
        (define elem-type
          (if (eq? kind 'UVECTOR)
              (mdl-array-element-type base)
              #f))
        (new-mdl-array kind new-storage 0 count elem-type)])]
    ;; ---- LIST ----
    [(or (null? base) (mpair? base))
     (define elems (mdl-list->list (mdl-list-head from 'mdl-substruc)))
     (define src-len (length elems))
     (when (> rest src-len)
       (error 'mdl-substruc "SUBSTRUC rest too large"))
     (define avail (- src-len rest))
     (define count (or amount avail))
     (when (> count avail)
       (error 'mdl-substruc "SUBSTRUC amount too big for source"))
     (define src-slice (take (drop elems rest) count))
     (cond
       [to
        ;; Nit 1: LIST `to` is not implemented (strict error).
        ;; Confusion supports it but: (a) overlap writes non-atomically giving a
        ;; different result from STRING/VECTOR; (b) too-short is detected AFTER
        ;; partial writes.  Since the game never passes a LIST `to`, we refuse
        ;; rather than copy either Confusion behaviour.  See S3-SUBSTRUC.md §list-to.
        (error 'mdl-substruc "SUBSTRUC: to argument for LIST is not implemented")]
       [else
        (apply mdl-list src-slice)])]
    [else
     (error 'mdl-substruc "SUBSTRUC requires a structured argument")]))

;; UNPARSE (MDL manual ch. 7, section 7.6.6.4; appendix 2)
;;
;; Contract: `<UNPARSE any radix:fix>` returns a fresh mutable STRING
;; containing the character sequence PRINT would have output for `any`,
;; without the carriage-returns PRINT inserts for line-width control.
;;
;; Radix (manual contract): the optional FIX argument selects the number base
;; for FIX values, default 10. Pinned Confusion DEVIATES from the manual —
;; it ignores the radix argument completely (`<UNPARSE 22 8>` → "22", not "26";
;; `<UNPARSE 255 16>` → "255", not "FF"). We follow the manual, not Confusion:
;; radix=10 or omitted → decimal; any other valid radix → strict unsupported
;; error (the game never supplies a non-10 radix). Non-FIX radix → error.
;; The Confusion deviation is a reference implementation bug, not a semantic
;; contract (AGENTS.md: Confusion is the observable reference; the manual is
;; the semantic contract; record where they differ).
;;
;; Types implemented exactly against Confusion:
;;   FIX → decimal digits (radix 10 or omitted; non-10 radix → strict error)
;;   ATOM → PNAME, only for pnames in [A-Za-z0-9-] whitelist, non-numeric,
;;           AND reachable eq? via current OBLIST chain (B2 + B1);
;;           else strict unsupported error
;;   STRING → double-quoted with \" and \\ escaping; B4: control chars → strict error
;;   FALSE → "#FALSE ()" or "#FALSE (elem …)"
;;   CHARACTER → "!\" followed by the character; B3: control chars → strict error
;;   LIST → "(elem …)" with space-separated elements (recursive)
;;
;; Strict unsupported error for all other types (FLOAT, VECTOR, UVECTOR,
;; WORD, FORM, FUNCTION, …). Do not fall back to Racket's printer.

(define (mdl-unparse-escape-string s)
  ;; Escape \ as \\ first, then " as \" — order matters.
  (string-replace (string-replace s "\\" "\\\\") "\"" "\\\""))

;; Is ATOM the one found by looking its PNAME up on the current OBLIST path
;; (#118: the LVAL of ROOT OBLIST, not the session default)? Only then does
;; PRINT/UNPARSE/PRIN1 omit the trailer.
(define (atom-reachable? who atom)
  (define pname (atom-value-pname atom))
  (define found
    (for/or ([oblist (in-list (mdl-list->list (current-lookup-path who)))])
      (define candidate (mdl-lookup pname oblist))
      (and (not (mdl-false? candidate)) candidate)))
  (eq? found atom))

;; B2 (M2): only PNAMEs made of [A-Za-z0-9-], non-empty, and not parseable
;; as a number print without \-escapes; others are strict (escapes are not
;; implemented). Applies to every ATOM of an OBLIST trailer too.
(define (check-safe-pname who pname)
  (unless (and (not (string=? pname ""))
               (for/and ([ch (in-string pname)])
                 (or (char<=? #\A ch #\Z) (char<=? #\a ch #\z)
                     (char<=? #\0 ch #\9) (char=? ch #\-)))
               (not (string->number pname)))
    (error who
           "UNPARSE ATOM: PNAME ~s not in safe-char whitelist ([A-Za-z0-9-], non-numeric); not implemented"
           pname)))

;; M4 #173 B2 (manual 15.4, 15.2.1, 15.5, 15.7.4; SEMANTICS "M4 #173 B2"):
;; the printed tokens of an ATOM. Reachable (the first ATOM of its PNAME on
;; the current OBLIST path is this one): its PNAME. Otherwise PNAME!-
;; followed by the name of its OBLIST, printed by the same rule: nothing for
;; ROOT, `#FALSE ()` for no OBLIST, Confusion's `!-#FALSE ()` for an OBLIST
;; without a name. The trailer is glued to the first token of the name's
;; text; `#FALSE ()` is the two tokens `#FALSE` and `()` (as a FALSE prints).
;; An OBLIST visited twice (the trailer would not terminate, manual 15.4)
;; and a name that is not an ATOM are strict errors.
(define (atom-print-tokens who atom)
  (define root (atom-space-root (current-mdl-atom-space)))
  (define indicator (mdl-root-atom "OBLIST"))
  (define visited (make-hasheq))
  (let loop ([a atom] [prefix ""])
    (define pname (atom-value-pname a))
    (check-safe-pname who pname)
    (cond
      [(atom-reachable? who a) (list (string-append prefix pname))]
      [else
       (define head (string-append prefix pname "!-"))
       (define oblist (atom-value-oblist a))
       (cond
         [(not oblist) (list (string-append head "#FALSE") "()")]
         [(eq? oblist root) (list head)]
         [else
          (when (hash-ref visited oblist #f)
            (error who "UNPARSE ATOM: OBLIST trailer does not terminate (manual 15.4); atom ~s"
                   (atom-value-pname atom)))
          (hash-set! visited oblist #t)
          (define found (association-lookup oblist indicator))
          (cond
            [(not found) (list (string-append head "!-#FALSE") "()")]
            [(mdl-atom? (cdr found)) (loop (cdr found) head)]
            [else
             (error who "UNPARSE ATOM: OBLIST name is not an ATOM; atom ~s"
                    (atom-value-pname atom))])])])))

(define (mdl-unparse-value who value)
  (cond
    [(exact-integer? value)
     ;; FIX: decimal string.
     (check-fix who value)
     (number->string value)]
    [(mdl-atom? value)
     ;; The bare PNAME when reachable, else the OBLIST trailer (M4 #173 B2);
     ;; UNPARSE joins the trailer's tokens with single spaces.
     (string-join (atom-print-tokens who value) " ")]
    [(mdl-string? value)
     ;; STRING: double-quoted, internal " and \ escaped.
     ;; B4: control characters (codes 0-31, 127) in string content require the
     ;; Confusion "^A…" embedded-control notation, which is not implemented.
     (define content (mdl-string-content value))
     (for ([ch (in-string content)])
       (define code (char->integer ch))
       (when (or (< code 32) (= code 127))
         (error who
                "UNPARSE STRING: control character (code ~a) not implemented; Confusion uses \"^A\" notation"
                code)))
     (string-append "\"" (mdl-unparse-escape-string content) "\"")]
    [(mdl-false? value)
     ;; FALSE: "#FALSE ()" or "#FALSE (…)" for non-empty payload.
     (define items (mdl-false-payload value))
     (if (null? items)
         "#FALSE ()"
         (string-append "#FALSE ("
                        (string-join (map (lambda (v) (mdl-unparse-value who v)) items) " ")
                        ")"))]
    [(or (char? value)
         (and (mdl-typed-value? value)
              (eq? (mdl-typed-value-type value) (mdl-root-atom "CHARACTER"))))
     ;; CHARACTER: "!\" followed by the character (Confusion: !\A → "!\\A").
     ;; The returned string contains !, \, char (3 chars for printable ASCII).
     ;; B3: control characters (codes 0-31, 127) require Confusion's "!\^A"
     ;; notation, which is not implemented; strict error.
     (define code (mdl-character-code value))
     (unless code (error who "UNPARSE CHARACTER: invalid character code"))
     (when (or (< code 32) (= code 127))
       (error who
              "UNPARSE CHARACTER: control character (code ~a) not implemented; Confusion uses !\\^A notation"
              code))
     (string-append "!\\" (string (integer->char code)))]
    [(or (null? value) (mpair? value))
     ;; LIST: "(elem1 elem2 …)" with space-separated recursive elements.
     (define items (mdl-list->list value))
     (string-append "("
                    (string-join (map (lambda (v) (mdl-unparse-value who v)) items) " ")
                    ")")]
    [else
     (error who "UNPARSE: unsupported MDL type ~a; strict-failure per AGENTS.md"
            (mdl-type-name value))]))

(define (mdl-unparse value [radix #f])
  ;; Radix must be a FIX in [2,36] if supplied. Per the MDL manual, it
  ;; selects the base for FIX conversion; Confusion incorrectly ignores it
  ;; (reference deviation — see docs/evidence/M3/S1-UNPARSE.md). We follow
  ;; the manual: radix=10 (or omitted) → decimal output; any other valid
  ;; FIX radix → strict unsupported error (the game never uses non-10 radix).
  (when radix
    (unless (and (exact-integer? radix) (<= 2 radix 36))
      (error 'mdl-unparse "UNPARSE radix must be a FIX in range 2-36"))
    (unless (= radix 10)
      (error 'mdl-unparse
             "UNPARSE: non-decimal radix ~a not implemented; strict-failure per AGENTS.md"
             radix)))
  ;; Return a fresh mutable STRING so callers may PUT into it (Confusion
  ;; probe: `<PUT <UNPARSE 42> 1 !\\X>` succeeds).
  (string-copy (mdl-unparse-value 'mdl-unparse value)))

(define (mdl-error . args)
  ;; ERROR is undeferable: a registered handler runs only above the current
  ;; level. A normal handler return falls through to the original failure.
  (define (describe value)
    (cond [(mdl-atom? value) (mdl-atom-pname value)]
          [(mdl-string? value) (format "~s" (mdl-string-content value))]
          [else (format "~a" value)]))
  (define (message)
    (if (null? args) "ERROR" (string-join (map describe args) " ")))
  ;; ADR-0054: every signalled MDL ERROR is recorded, resolved or not, so a
  ;; session that later QUITs reports it (quit-after-mdl-error). The record
  ;; is a snapshot taken at signal time; the fall-through failure message
  ;; below is still formatted after handler delivery, as before S11, so a
  ;; handler that mutates an argument is reflected there (S11 review).
  (let ([space (current-mdl-atom-space)])
    (set-atom-space-mdl-errors! space (cons (message) (atom-space-mdl-errors space))))
  (define-values (value erret-level)
    (call/ec
     (lambda (resume)
       (define frame (mdl-error-frame (current-mdl-atom-space) resume #t))
       (dynamic-wind
         void
         (lambda ()
           (define header (hash-ref (atom-space-events (current-mdl-atom-space))
                                    "ERROR" #f))
           ;; ERROR occurrences are never queued (manual 21.8.11): deliver
           ;; this one now instead of appending it behind older pending
           ;; occurrences, where it could outlive its FRAME.
           (when (and header (active-iheader? header)
                      (> (mdl-iheader-priority header)
                         (mdl-interrupt-state-level (current-interrupt-state))))
             (mdl-deliver-occurrence!
              (mdl-interrupt-occurrence header (cons frame args))))
           (error 'mdl-error "~a" (message)))
         (lambda () (set-mdl-error-frame-live?! frame #f))))))
  ;; ERRET returns from this ERROR at the interrupt level current when ERRET
  ;; ran; the handler is responsible for <INT-LEVEL 0> (manual 21.8.11).
  ;; Handler cleanup restored older levels while unwinding; undo that here.
  (set-mdl-interrupt-state-level! (current-interrupt-state) erret-level)
  ;; Returning from ERROR is a safe point: deliver occurrences eligible at
  ;; the resumed level (e.g. left pending by an earlier raising handler).
  (mdl-drain-pending!)
  value)

(define (mdl-erret value frame)
  (unless (and (mdl-error-frame? frame)
               (eq? (mdl-error-frame-owner frame) (current-mdl-atom-space))
               (mdl-error-frame-live? frame))
    (error 'mdl-erret "ERRET requires a live ERROR FRAME in this session"))
  ((mdl-error-frame-resume frame)
   value (mdl-interrupt-state-level (current-interrupt-state))))

(define (mdl-map-structured? value)
  (define base (mdl-base value))
  (or (null? base) (mpair? base) (mdl-array? base)
      (mdl-string? base) (mdl-false? base) (mdl-tuple-value? base)))

(define (mdl-mapret . values)
  (define step (current-mdl-map-step))
  (unless step (error 'mdl-mapret "No map in MAPRET"))
  (step (mdl-map-transfer 'continue values)))

(define (mdl-mapstop . values)
  (define step (current-mdl-map-step))
  (unless step (error 'mdl-mapstop "No map in MAPSTOP"))
  (step (mdl-map-transfer 'stop values)))

(define (mdl-mapleave . values)
  (unless (<= (length values) 1)
    (error 'mdl-mapleave "TOO-MANY-ARGUMENTS-SUPPLIED"))
  (define leave (current-mdl-map-leave))
  (unless leave (error 'mdl-mapleave "No map in MAPLEAVE"))
  (leave (if (null? values) (mdl-root-atom "T") (car values))))

(define (mdl-map-core rest? finalf loopf structures)
  (for ([structure (in-list structures)])
    (unless (mdl-map-structured? structure)
      (error (if rest? 'mdl-mapr 'mdl-mapf)
             "Arguments to MAPF/R must be structured")))
  (let/ec leave
    (let loop ([index 1] [collected '()] [last-value (mdl-false '())])
      (define exhausted?
        (for/or ([structure (in-list structures)])
          (> index (mdl-length structure))))
      (if exhausted?
          (if (mdl-false? finalf)
              last-value
              (mdl-apply-evaluated finalf (reverse collected)))
          (let* ([step-values
                  (for/list ([structure (in-list structures)])
                    (if rest?
                        (mdl-rest structure (sub1 index))
                        (mdl-nth structure index)))]
                 [step-result
                  (let/ec step
                    (parameterize ([current-mdl-map-step step]
                                   [current-mdl-map-leave leave])
                      (mdl-map-transfer
                       'normal
                       (list (mdl-apply-evaluated loopf step-values)))))]
                 [new-collected
                  (if (mdl-false? finalf)
                      '()
                      (append (reverse (mdl-map-transfer-values step-result))
                              collected))]
                 [values (mdl-map-transfer-values step-result)]
                 [new-last
                  (if (and (mdl-false? finalf)
                           (not (eq? (mdl-map-transfer-kind step-result) 'normal)))
                      ;; Pinned Confusion returns the current first input
                      ;; when MAPRET/MAPSTOP transfers under FALSE finalf,
                      ;; even when control supplied different values.
                      (if (null? step-values) last-value (car step-values))
                      (if (null? values) last-value (last values)))])
            (if (eq? (mdl-map-transfer-kind step-result) 'stop)
                (if (mdl-false? finalf)
                    new-last
                    (mdl-apply-evaluated finalf (reverse new-collected)))
                (loop (add1 index) new-collected new-last)))))))

(define (mdl-mapf finalf loopf . structures)
  (mdl-map-core #f finalf loopf structures))

(define (mdl-mapr finalf loopf . structures)
  (mdl-map-core #t finalf loopf structures))

(define (mdl-typeq . args)
  (when (null? args)
    (error 'mdl-typeq "Not enough arguments to TYPE?"))
  (define actual (mdl-type (car args)))
  (if (member actual (cdr args) eq?) actual (mdl-false '())))

(define (mdl-andq . args)
  ;; mdl-dispatch-call evaluates the complete SUBR argument list before
  ;; invoking this procedure, including arguments after the first FALSE.
  (let loop ([remaining args])
    (cond [(null? remaining) (mdl-root-atom "T")]
          [(not (mdl-truthy? (car remaining))) (car remaining)]
          [(null? (cdr remaining)) (car remaining)]
          [else (loop (cdr remaining))])))

(define (mdl-emptyq . args)
  (case (length args)
    [(0) (error 'mdl-emptyq "Not enough arguments to EMPTY?")]
    [(1) (void)]
    [else (error 'mdl-emptyq "Too many args to EMPTY?")])
  (define object (car args))
  (unless (mdl-map-structured? object)
    (error 'mdl-emptyq "First arg to EMPTY? must be structured"))
  (define base (mdl-base object))
  (define empty?
    (if (or (mdl-array? base) (mdl-string? base))
        (zero? (mdl-length object))
        (null? (mdl-list-head object 'mdl-emptyq))))
  (if empty? (mdl-root-atom "T") (mdl-false '())))

(define (mdl-lengthq . args)
  (case (length args)
    [(0 1) (error 'mdl-lengthq "Not enough arguments to LENGTH?")]
    [(2) (void)]
    [else (error 'mdl-lengthq "Too many args to LENGTH?")])
  (define object (car args))
  (define maximum (cadr args))
  (unless (mdl-map-structured? object)
    (error 'mdl-lengthq "First arg to LENGTH? must be structured"))
  (unless (and (exact-integer? maximum) (<= fix-min maximum fix-max))
    (error 'mdl-lengthq "Second arg to LENGTH? must be FIX"))
  (define base (mdl-base object))
  (cond
    [(or (mdl-array? base) (mdl-string? base))
     (define count (mdl-length object))
     (if (or (zero? count) (<= count maximum)) count (mdl-false '()))]
    [else
     ;; Stop after MAX+1 cells; LENGTH itself need not terminate on a
     ;; circular LIST. Empty input is checked before MAX, matching the
     ;; pinned reference's empty/negative-MAX result of FIX 0.
     (let loop ([remaining (mdl-list-head object 'mdl-lengthq)] [count 0])
       (cond [(null? remaining) count]
             [(not (mpair? remaining))
              (error 'mdl-lengthq "improper structured LIST")]
             [(>= count maximum) (mdl-false '())]
             [else (loop (mcdr remaining) (add1 count))]))]))

(define (mdl-apply-subr . args)
  (when (null? args)
    (error 'mdl-apply-subr "TOO-FEW-ARGUMENTS-SUPPLIED in APPLY"))
  (define fn (car args))
  (when (mdl-macro? fn)
    (error 'mdl-apply-subr "Can't use APPLY with MACROs"))
  (define formal-kinds
    (cond [(mdl-function? fn)
           (map first
                (runtime-formal-specs (mdl-function-formals fn)))]
          [(procedure? fn)
           (hash-ref compiled-function-formals fn '())]
          [else '()]))
  (when (or (memq 'quoted formal-kinds)
            (memq 'quoted-optional formal-kinds))
    (error 'mdl-apply-subr "Can't use APPLY to call a function with quoted arguments"))
  (when (memq 'rest-args formal-kinds)
    (error 'mdl-apply-subr "ARGS not allowed when called from APPLY"))
  (mdl-apply-evaluated fn (cdr args)))

(define builtin-table
  (hash "TYPE" mdl-type
        "TYPE?" mdl-typeq
        "AND?" mdl-andq
        "EMPTY?" mdl-emptyq
        "LENGTH?" mdl-lengthq
        "LVAL" mdl-lval
        "GVAL" mdl-gval
        "VALUE" mdl-value
        "SET" mdl-set!
        "SETG" mdl-setg!
        "GASSIGNED?" mdl-gassigned?
        "ASSIGNED?" mdl-assigned?
        "MANIFEST" mdl-manifest
        "DECL?" mdl-decl?
        "GUNASSIGN" mdl-gunassign!
        "PRIMTYPE" mdl-primtype
        "TYPEPRIM" mdl-typeprim
        "NEWTYPE" mdl-newtype
        "CHTYPE" mdl-chtype
        "CHUTYPE" mdl-chutype
        "FIX" mdl-fix
        "FLOAT" mdl-float
        "BITS" mdl-bits
        "GETBITS" mdl-getbits
        "PUTBITS" mdl-putbits
        "ANDB" mdl-andb
        "ORB" mdl-orb
        "XORB" mdl-xorb
        "EQVB" mdl-eqvb
        "LSH" mdl-lsh
        "UTYPE" mdl-utype
        "LIST" mdl-list
        "VECTOR" mdl-vector
        "IVECTOR" mdl-ivector
        "UVECTOR" mdl-uvector
        "IUVECTOR" mdl-iuvector
        "STRING" mdl-string
        "ISTRING" mdl-istring
        "GC" mdl-gc
        "BLOAT" mdl-bloat
        "ASCII" mdl-ascii
        "UNPARSE" mdl-unparse
        "PRINTSTRING" mdl-printstring
        "SUBSTRUC" mdl-substruc
        "TERPRI" mdl-terpri
        "CRLF" mdl-crlf
        "RESET" mdl-reset
        "PRINC" mdl-princ
        "PRIN1" mdl-prin1
        "PRINT" mdl-print
        "READSTRING" mdl-readstring
        "ERROR" mdl-error
        "ERRET" mdl-erret
        "EVENT" mdl-event
        "HANDLER" mdl-install-handler
        "OFF" mdl-off
        "ON" mdl-on
        "SAVE" mdl-save
        "RESTORE" mdl-restore
        "QUIT" mdl-quit
        "OPEN" mdl-open
        "FILE-LENGTH" mdl-file-length
        "CLOSE" mdl-close
        "REP" mdl-default-rep
        "INT-LEVEL" mdl-int-level
        "ENABLE" mdl-enable
        "DISABLE" mdl-disable
        "MAPF" mdl-mapf
        "MAPR" mdl-mapr
        "MAPRET" mdl-mapret
        "MAPSTOP" mdl-mapstop
        "MAPLEAVE" mdl-mapleave
        "APPLY" mdl-apply-subr
        "LENGTH" mdl-length
        "REST" mdl-rest
        "BACK" mdl-back
        "TOP" mdl-top
        "NTH" mdl-nth
        "PUT" mdl-put!
        "GET" mdl-get
        "MEMQ" (lambda args
                 (case (length args)
                   [(2) (mdl-memq (car args) (cadr args))]
                   [(0 1) (error 'mdl-memq "TOO-FEW-ARGUMENTS-SUPPLIED")]
                   [else (error 'mdl-memq "TOO-MANY-ARGUMENTS-SUPPLIED")]))
        "MEMBER" (lambda args
                   (case (length args)
                     [(2) (mdl-member (car args) (cadr args))]
                     [(0 1) (error 'mdl-member "TOO-FEW-ARGUMENTS-SUPPLIED")]
                     [else (error 'mdl-member "TOO-MANY-ARGUMENTS-SUPPLIED")]))
        "PUTREST" mdl-putrest!
        "FORM" (lambda elems (mdl-make-form (apply mdl-list elems)))
        "EXPAND" mdl-expand
        "ATOM" (lambda (name)
                 (atom-value (mdl-string-snapshot 'mdl-atom name "expected a STRING PNAME")
                             #f))
        "MOBLIST" mdl-moblist
        "BLOCK" mdl-block
        "ENDBLOCK" mdl-endblock
        "ROOT" mdl-root
        "LOOKUP" mdl-lookup
        "INSERT" mdl-insert
        "REMOVE" mdl-remove
        "OBLIST?" mdl-oblist-of
        "PNAME" mdl-pname
        "SPNAME" mdl-spname
        "+" mdl-add
        "-" mdl-sub
        "*" mdl-mul
        "/" mdl-div
        "MIN" mdl-min
        "MAX" mdl-max
        "ABS" mdl-abs
        "IMAGE" mdl-image
        "SLEEP" mdl-sleep
        "TIME" mdl-time
        "RANDOM" mdl-random
        "GETTIMEDATE" mdl-gettimedate
        "MOD" mdl-mod
        "0?" (lambda (number) (mdl-boolean (= (check-number 'mdl-zero? number) 0)))
        "1?" (lambda (number) (mdl-boolean (= (check-number 'mdl-one? number) 1)))
        "L?" (lambda (a b) (mdl-boolean (< a b)))
        "L=?" (lambda (a b) (mdl-boolean (<= a b)))
        "G?" (lambda (a b) (mdl-boolean (> a b)))
        "G=?" (lambda (a b) (mdl-boolean (>= a b)))
        "=?" (lambda (a b) (mdl-boolean (mdl-equal? a b)))
        "N=?" (lambda args
                 (case (length args)
                   [(2) (mdl-boolean (not (mdl-equal? (car args) (cadr args))))]
                   [(0 1) (error 'mdl-neq "TOO-FEW-ARGUMENTS-SUPPLIED")]
                   [else (error 'mdl-neq "TOO-MANY-ARGUMENTS-SUPPLIED")]))
        "==?" (lambda (a b) (mdl-boolean (mdl-identical? a b)))
        "N==?" (lambda (a b) (mdl-boolean (not (mdl-identical? a b))))))

;; ADR-0060: the host built-ins bound to ROOT names are SUBRs (pinned
;; Confusion: every builtin-table name is a SUBR). The set is fixed at module
;; load and compared by eq?; REP is an mdl-subr and is typed before this.
(define builtin-subr-values
  (for/hasheq ([value (in-hash-values builtin-table)]) (values value #t)))
(define (builtin-subr? value)
  (and (procedure? value) (hash-ref builtin-subr-values value #f)))

;; The default session is created after builtin-table exists, because a
;; session's ROOT is seeded with every builtin SUBR name. Definitions
;; above only read the parameter when called.
(define current-mdl-atom-space (make-parameter (make-mdl-atom-space)))

(define (mdl-apply name . args)
  (define atom (binding-atom 'mdl-apply name))
  (define global (global-option atom))
  (define fn (if (eq? global unassigned) (local-option atom) global))
  (when (eq? fn unassigned)
    (error 'mdl-apply "unassigned or non-applicable MDL operator ~a"
           (mdl-atom-pname atom)))
  (when (mdl-macro? fn)
    (error 'mdl-apply "raw MACRO arguments are unavailable through the value API"))
  (mdl-apply-evaluated fn args))

(module+ test
  (require rackunit)
  (define (body-item thunk) (cons 'expr thunk))
  (define leaked #f)
  (check-equal?
   (mdl-with-prog-activation
    (vector (body-item (lambda ()
                         (set! leaked (car (current-mdl-activations)))
                         (mdl-return 17)
                         99))))
   17)
  (check-false (mdl-activation-live? leaked))
  (check-equal? (current-mdl-activations) '())
  (check-exn #rx"no active PROG"
             (lambda ()
               (parameterize ([current-mdl-activations (list leaked)])
                 (mdl-return 19))))
  (check-exn #rx"no active PROG or REPEAT"
             (lambda ()
               (parameterize ([current-mdl-activations (list leaked)])
                 (mdl-again))))
  (define abandoned #f)
  (check-exn #rx"intentional failure"
             (lambda ()
               (mdl-with-prog-activation
                (vector (body-item (lambda ()
                                     (set! abandoned (car (current-mdl-activations)))
                                     (error 'test "intentional failure")))))))
  (check-false (mdl-activation-live? abandoned))
  (check-equal? (current-mdl-activations) '())
  (check-equal?
   (mdl-with-prog-activation
    (vector (body-item (lambda ()
                         (check-exn #rx"no active PROG"
                                    (lambda ()
                                      (mdl-with-function-scope
                                       (lambda () (mdl-return 7)))))
                         (mdl-return 8)))))
   8)
  (check-equal?
   (mdl-with-prog-activation
    (vector (body-item (lambda ()
                        (define outer (car (current-mdl-activations)))
                        (define inner
                          (mdl-with-prog-activation
                           (vector (body-item
                                    (lambda ()
                                      (define current (car (current-mdl-activations)))
                                      (check-false (eq? current outer))
                                      (check-eq? (cadr (current-mdl-activations)) outer)
                                      current)))))
                        (check-false (mdl-activation-live? inner))
                        (check-true (mdl-activation-live? outer))
                        (mdl-return 23)))))
   23)
  ;; Function-formal binder invariants (v2 ordered specs).
  (define binder-atom (mdl-atom "M2-BINDER-CHECK"))
  (check-equal?
   (mdl-bind-function-formals
    binder-atom
    (list (list 'required (mdl-atom "A"))
          (list 'optional (mdl-atom "B") #f)
          (list 'aux (mdl-atom "C") (lambda () (mdl-lval (mdl-atom "A")))))
    '(7) #f
    (lambda () (mdl-lval (mdl-atom "A"))))
   7)
  (check-equal? (length (current-mdl-locals)) 1)
  (check-exn #rx"TOO-FEW-ARGUMENTS-SUPPLIED"
             (lambda ()
               (mdl-bind-function-formals
                binder-atom (list (list 'required (mdl-atom "A")))
                '() #f void)))
  (check-exn #rx"TOO-MANY-ARGUMENTS-SUPPLIED"
             (lambda ()
               (mdl-bind-function-formals binder-atom '() '(1) #f void)))
  (define tuple-check
    (mdl-bind-function-formals
     binder-atom
     (list (list 'rest 'tuple (mdl-atom "T")))
     '(1 2 3) #f
     (lambda () (mdl-lval (mdl-atom "T")))))
  (check-equal? (mdl-atom-pname (mdl-type tuple-check)) "TUPLE")
  (check-equal? (mdl-atom-pname (mdl-primtype tuple-check)) "TUPLE")
  (check-equal? (mdl-length (mdl-rest tuple-check)) 2)
  (check-equal? (mdl-atom-pname (mdl-type (mdl-rest tuple-check))) "TUPLE")
  (check-true (mdl-equal? tuple-check
                          (mdl-tuple-value (mdl-list 1 2 3))))
  (check-false (mdl-equal? tuple-check (mdl-list 1 2 3)))
  ;; GO label mechanics: labels are skipped; GO resumes after the label.
  (define go-log '())
  (check-equal?
   (mdl-with-prog-activation
    (vector (body-item (lambda () (set! go-log (cons 'a go-log))))
            (body-item (lambda () (mdl-go (mdl-atom "M2-LBL")) 'never))
            (cons 'label (mdl-atom "M2-LBL"))
            (body-item (lambda () (set! go-log (cons 'b go-log)) 'b))))
   'b)
  (check-equal? go-log '(b a))
  (check-exn #rx"GO label not found"
             (lambda ()
               (mdl-with-prog-activation
                (vector (body-item (lambda () (mdl-go (mdl-atom "M2-NONE"))))))))
  ;; UNWIND: cleanup only when an MDL transfer crosses below it; a raised
  ;; error propagates unchanged without the cleanup (ADR-0051).
  (check-equal? (mdl-unwind (lambda () 5) (lambda () (set! go-log 'cleaned)))
                5)
  (check-equal? go-log '(b a))
  (define unwind-cleaned? #f)
  (check-equal?
   (mdl-with-prog-activation
    (vector (body-item (lambda ()
                         (mdl-unwind
                          (lambda () (mdl-return 9) 'never)
                          (lambda () (set! unwind-cleaned? #t)))
                         99))))
   9)
  (check-true unwind-cleaned?)
  (define error-cleaned? #f)
  (check-exn #rx"boom"
             (lambda ()
               (mdl-unwind (lambda () (error 'test "boom"))
                           (lambda () (set! error-cleaned? #t)))))
  (check-false error-cleaned?)
  ;; Function activation formals: explicit targets work; bare transfers
  ;; skip function frames.
  (check-equal?
   (mdl-with-function-scope
    (lambda ()
      (mdl-call-with-activation
       binder-atom
       (list (list 'name (mdl-atom "M2-SELF")))
       '()
       (lambda ()
         (mdl-return 7 (mdl-lval (mdl-atom "M2-SELF"))) 99))))
   7)
  (check-exn #rx"no active PROG"
             (lambda ()
               (mdl-with-function-scope
                (lambda ()
                  (mdl-call-with-activation binder-atom '() '()
                                            (lambda () (mdl-return 5)))))))
  (define self-again-count 0)
  (check-equal?
   (mdl-with-function-scope
    (lambda ()
      (mdl-call-with-activation
       binder-atom
       (list (list 'aux (mdl-atom "N") (lambda () 0)))
       '()
       (lambda ()
         (set! self-again-count (add1 self-again-count))
         (define n (mdl-lval (mdl-atom "N")))
         (mdl-set! (mdl-atom "N") (add1 n))
         (if (= (mdl-lval (mdl-atom "N")) 3)
             (mdl-lval (mdl-atom "N"))
             (mdl-again (car (current-mdl-activations))))))))
   3)
  (check-equal? self-again-count 3))

;; Initialize the process-wide default context (see "Execution contexts").
;; Explicit opt-in (S13 part B, ADR-0050): this ambient context, used by core
;; unit tests and #lang mdl modules, never by a session, follows the host's
;; current-output-port.
(mdl-ensure-terminal-channels! #:follow-current-output-port? #t)

;; Delivery-path guard for sourceless predefined events (ADR-0047 IPC,
;; ADR-0048 BLOCKED). No MDL-level path can queue such an occurrence, so this
;; host-level test injects one directly to prove the defensive check bites.
(module+ test
  (for ([name (in-list '("IPC" "BLOCKED"))]
        [priority (in-list '(1 100))])
    (parameterize ([current-mdl-globals (make-hasheq)]
                   [current-mdl-locals (list (make-hasheq))]
                   [current-mdl-atom-space (make-mdl-atom-space)])
      (define header (mdl-event name priority))
      (check-exn (regexp (string-append "^mdl-deliver-occurrence!: " name ": "))
                 (lambda ()
                   (mdl-deliver-occurrence!
                    (mdl-interrupt-occurrence header '()))))
      (check-exn (regexp (string-append name ": "))
                 (lambda () (mdl-emit-event! name '()))))))
