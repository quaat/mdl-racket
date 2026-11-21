#lang racket/base
;; Bootstrap MDL runtime: intentionally incomplete and NOT a gameplay engine.
(require racket/mpair racket/list racket/string)
(provide current-mdl-globals current-mdl-locals
         current-mdl-read-values mdl-register-read-value! mdl-read-value
         mdl-interpreter-version
         mdl-setg! mdl-gval mdl-define!
         mdl-set! mdl-lval mdl-with-bindings mdl-with-aux-bindings mdl-type
         mdl-bind-function-formals mdl-call-with-activation
         mdl-with-function-scope mdl-with-prog-activation
         mdl-return mdl-again mdl-go mdl-unwind
         mdl-eval mdl-make-form mdl-form? mdl-macro? mdl-function?
         mdl-apply-form mdl-apply-computed mdl-apply-interpreted mdl-function-literal
         mdl-expand mdl-defmac! mdl-define-interpreted!
         mdl-apply mdl-list mdl-list->list
         mdl-make-declaration mdl-gdecl
         mdl-vector mdl-uvector mdl-data-uvector mdl-rest mdl-nth mdl-put! mdl-get mdl-putrest!
         mdl-array? mdl-array-kind mdl-array-length form-elements mdl-base
         mdl-length mdl-equal? mdl-identical?
         mdl-segment mdl-segment? mdl-segment-payload mdl-segment-line
         mdl-segment-column mdl-make-segment mdl-splice-result
         mdl-splice-result-value mdl-splice-list mdl-splice-vector
         mdl-splice-uvector
         mdl-word mdl-word? mdl-word-bits mdl-chtype mdl-character
         mdl-truthy? mdl-atom mdl-atom? mdl-atom-pname mdl-oblist?
         current-mdl-atom-space make-mdl-atom-space
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
(define compiled-function-formals (make-weak-hasheq))
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

(define (binding-atom who value)
  (cond [(mdl-atom? value) value]
        [(string? value) (mdl-atom value)]
        [else (error who "expected an MDL ATOM")]))

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

;; The structured declaration types of this slice (issue #48) are the head
;; ATOMs LIST, VECTOR, UVECTOR, and TUPLE of the `<struc elts>` pattern
;; construction. Anything else -- NEWTYPE names with element patterns,
;; BYTES, TEMPLATE-like heads -- stays an explicit unsupported-pattern error
;; for a later slice.

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
                       (eq? (car head-items) (mdl-atom "PRIMTYPE")))
            (decl-error origin line column "malformed declaration pattern"))
          (define normalized (normalize-decl-pattern head line column origin))
          (unless (eq? (car normalized) 'primtype)
            (decl-error origin line column
                        "structured declaration head must be PRIMTYPE"))
          (cadr normalized))
        head))
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

(define (normalize-decl-pattern pattern line column
                                 [origin "DECL"])
  (cond
    [(mdl-atom? pattern)
     (cond [(string=? (mdl-atom-pname pattern) "ANY") '(any)]
           [(string=? (mdl-atom-pname pattern) "APPLICABLE") '(applicable)]
           [(hash-has-key? (atom-space-types (current-mdl-atom-space)) pattern)
            (list 'type pattern)]
           [else
            (define associated (association-lookup pattern (mdl-atom "DECL")))
            (unless associated
              (decl-error origin line column "unknown declaration type ~a"
                          (mdl-atom-pname pattern)))
            (when (memq pattern (current-decl-alias-path))
              (decl-error origin line column "cyclic DECL association at ~a"
                          (mdl-atom-pname pattern)))
            (parameterize ([current-decl-alias-path
                            (cons pattern (current-decl-alias-path))])
              (normalize-decl-pattern (cdr associated) line column origin))])]
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
       [(LIST VECTOR UVECTOR TUPLE)
        (normalize-decl-structure items line column origin)]
       [else (decl-error origin line column "unsupported declaration pattern ~a"
                         (mdl-atom-pname (car items)))]))]
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
          (define pattern (normalize-decl-pattern (list-ref items (add1 i)) line column))
          (for ([name (in-list (mdl-list->list names))])
            (unless (mdl-atom? name)
              (decl-error "DECL" line column "declaration name must be an ATOM"))
            (if (string=? (mdl-atom-pname name) "VALUE")
                (begin
                  (when result (decl-error "DECL" line column "duplicate VALUE declaration"))
                  (set! result pattern))
                (begin
                  (when (hash-has-key? bindings name)
                    (decl-error "DECL" line column "duplicate declaration for ~a"
                                (mdl-atom-pname name)))
                  (hash-set! bindings name pattern)))))
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
    [(type) (cadr pattern)]
    [(applicable) (mdl-atom "APPLICABLE")]
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
;; (declq-consults-atom-decl). Attached #DECL checking does not consult atom
;; properties in this slice. SETG likewise ignores them (the recorded
;; setg-ignores-atom-decl case, consistent with D1's non-enforcement).
(define (mdl-decl? value pattern)
  (define resolved?
    (and (mdl-atom? pattern)
         (not (hash-has-key? (atom-space-types (current-mdl-atom-space)) pattern))
         (association-lookup pattern (mdl-atom "DECL"))))
  (define normalized
    (normalize-decl-pattern pattern #f #f "DECL?"))
  (define result (decl-match value normalized decl-match-max-depth))
  (cond
    [(eq? result #t) (mdl-atom "T")]
    [(eq? result #f)
     (if resolved?
         (mdl-false (list value (decl-failure-leaf normalized)))
         (mdl-false (list value pattern)))]
    [(eq? (car result) 'element)
     (mdl-false (list (cadr result) (caddr result)))]
    [else (mdl-false '())]))

(define (check-declared! decl name value)
  (when (and decl (not (eq? value unassigned)))
    (define pattern (if (eq? name 'VALUE)
                        (mdl-decl-value-result decl)
                        (hash-ref (mdl-decl-value-bindings decl) name #f)))
    (when (and pattern (not (matches-decl? value pattern)))
      (decl-error "DECL" (mdl-decl-value-line decl) (mdl-decl-value-column decl)
                  "~a does not satisfy declaration"
                  (if (eq? name 'VALUE) "VALUE" (mdl-atom-pname name)))))
  value)

(define (check-frame-binding! frame atom value)
  (check-declared! (hash-ref local-declarations frame #f) atom value))

(define (check-result! decl value)
  (check-declared! decl 'VALUE value))

(define (local-option atom)
  (let loop ([frames (current-mdl-locals)])
    (cond [(null? frames) unassigned]
          [(hash-has-key? (car frames) atom) (hash-ref (car frames) atom)]
          [else (loop (cdr frames))])))

(define (mdl-lval name)
  (define atom (binding-atom 'mdl-lval name))
  (define result (local-option atom))
  (if (eq? result unassigned)
      (error 'mdl-lval "unassigned MDL local ~a" (mdl-atom-pname atom))
      result))

(define (mdl-set! name value)
  (define atom (binding-atom 'mdl-set name))
  (define frames (current-mdl-locals))
  (define target
    (or (for/or ([frame (in-list frames)])
          (and (hash-has-key? frame atom) frame))
        (last frames)))
  (check-frame-binding! target atom value)
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
  (define (bind! atom value)
    (require-atom 'mdl-bind-function-formals atom)
    (when (hash-has-key? frame atom)
      (error 'mdl-bind-function-formals
             "BAD-ARGUMENT-LIST: duplicate formal argument"))
    (check-frame-binding! frame atom value)
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
         (bind! (second spec) (car remaining))
         (set! remaining (cdr remaining))]
        [(optional)
         (if (null? remaining)
             (bind! (second spec) (spec-value spec))
             (begin
               (bind! (second spec) (car remaining))
               (set! remaining (cdr remaining))))]
        [(rest)
         (define kind (second spec))
         (bind! (third spec)
                (if (null? remaining)
                    (if (eq? kind 'tuple) (mdl-tuple-value '()) '())
                    (if (eq? kind 'tuple)
                        (mdl-tuple-value (apply mdl-list remaining))
                        (apply mdl-list remaining))))
         (set! remaining '())]
        [(aux) (bind! (second spec) (spec-value spec))]
        [(name)
         (unless activation-frame
           (error 'mdl-bind-function-formals
                  "NAME formal without a function activation"))
         (bind! (second spec) activation-frame)]
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
      (check-frame-binding! frame atom value)
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

;; UNWIND evaluates its first expression and returns its value. If a
;; nonlocal transfer or an error crosses below this point, the cleanup
;; expression runs first in the environment of the UNWIND call, its value
;; is ignored, and the transfer completes. Normal completion never runs the
;; cleanup. The dynamic-wind post runs for escape-continuation jumps and
;; exceptions alike.
(define (mdl-unwind std-thunk erre-thunk)
  (define completed-normally? #f)
  (dynamic-wind
    void
    (lambda ()
      (define value (std-thunk))
      (set! completed-normally? #t)
      value)
    (lambda ()
      (unless completed-normally? (erre-thunk) (void)))))

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
(struct mdl-segment (payload line column) #:transparent)
(struct mdl-splice-result (value line column) #:transparent)

(define (mdl-make-segment payload line column)
  (mdl-segment payload line column))

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
    [(string? value)
     (for/list ([ch (in-string value)])
       (mdl-character ch))]
    [else
     (error 'mdl-segment
            "ILLEGAL-SEGMENT: Segment evaluated to nonstructured type")]))

;; A trailing SEGMENT whose value has PRIMTYPE LIST shares its storage in
;; LIST construction instead of being copied (macros.cpp:2716-2724).
(define (segment-shares-tail? value)
  (eq? (mdl-primtype value) (mdl-atom "LIST")))
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
      (mdl-array 'UVECTOR (vector) 0 0 #f)
      (let ([element-type (mdl-type (car items))])
        (for ([value (in-list items)])
          (unless (eq? (mdl-type value) element-type)
            (error 'mdl-splice-uvector
                   "TYPES-DIFFER-IN-UNIFORM-VECTOR: UVECTOR elements must have one permitted TYPE")))
        (when (string=? (mdl-type-name (car items)) "STRING")
          (error 'mdl-splice-uvector
                 "UVECTOR elements must have one permitted TYPE"))
        (mdl-array 'UVECTOR (list->vector items) 0 (length items) element-type))))

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
  (mdl-typed-value (mdl-atom "FORM") lst))

(define (mdl-form? value)
  (and (mdl-typed-value? value)
       (eq? (mdl-typed-value-type value) (mdl-atom "FORM"))))

(define (form-elements form)
  (mdl-list->list (mdl-typed-value-value form)))

(define (quoted-formal-name item)
  ;; A quoted formal is the form <QUOTE atom> as stored data.
  (and (mdl-form? item)
       (let ([elements (form-elements item)])
         (and (= 2 (length elements))
              (eq? (car elements) (mdl-atom "QUOTE"))
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
          (define (bind! atom value)
            (when (hash-has-key? locals atom)
              (error 'mdl-bind-interpreted
                     "BAD-ARGUMENT-LIST: duplicate formal argument"))
            (check-frame-binding! locals atom value)
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
                 (bind! name (arg-value (car remaining) (not (eq? kind 'quoted))))
                 (set! remaining (cdr remaining))]
                [(optional quoted-optional)
                 (if (null? remaining)
                     (bind! name (if default (mdl-eval default) unassigned))
                     (begin
                       (bind! name (arg-value (car remaining)
                                              (not (eq? kind 'quoted-optional))))
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
                                     (apply mdl-list (map cdr remaining)))))
                 (set! remaining '())]
                [(aux) (bind! name (if default (mdl-eval default) unassigned))]
                [(name) (bind! name frame)]
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
            (mdl-atom "T"))]
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
      (mdl-atom "T")
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
  (cond [(hash-has-key? globals atom) (hash-ref globals atom)]
        [(eq? atom (mdl-atom (mdl-atom-pname atom)))
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
  (define redefine (hash-ref globals (mdl-atom "REDEFINE") unassigned))
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
  (mdl-atom "T"))

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

(define (mdl-manifest . names)
  (for ([name (in-list names)])
    (define atom (binding-atom 'mdl-manifest name))
    (hash-set! (atom-space-manifests (current-mdl-atom-space)) atom #t)
    (unless (hash-has-key? (current-mdl-globals) atom)
      (hash-set! (current-mdl-globals) atom unassigned)))
  (mdl-atom "T"))

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

(define (mdl-define! name fn [formal-kinds '()])
  (when (procedure? fn)
    (hash-set! compiled-function-formals fn formal-kinds))
  (mdl-setg! name fn))

(struct atom-value (pname [oblist #:mutable]))
(struct oblist-value (name entries size))
(struct atom-space (initial root named types builtins manifests associations
                            global-declarations))

(define mdl-atom? atom-value?)
(define mdl-atom-pname atom-value-pname)
(define mdl-oblist? oblist-value?)

(define (make-mdl-atom-space)
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
  (for ([entry (in-list '(("ATOM" . "ATOM") ("OBLIST" . "UVECTOR")
                          ("LIST" . "LIST") ("FORM" . "LIST")
                          ("FALSE" . "LIST") ("DECL" . "LIST")
                          ("VECTOR" . "VECTOR")
                          ("UVECTOR" . "UVECTOR") ("STRING" . "STRING")
                          ("FIX" . "WORD") ("FLOAT" . "WORD")
                          ("WORD" . "WORD") ("BITS" . "WORD")
                          ("CHARACTER" . "WORD")
                          ("FRAME" . "FRAME")
                          ("TUPLE" . "TUPLE")
                          ("MACRO" . "LIST")
                          ("FUNCTION" . "LIST")
                          ("ACTIVATION" . "FRAME")))])
    (define type-atom
      (if (string=? (car entry) "OBLIST")
          oblist-name
          (atom-value (car entry) initial)))
    (unless (eq? type-atom oblist-name)
      (hash-set! (oblist-value-entries initial) (car entry) type-atom))
    (hash-set! types type-atom (cdr entry))
    (hash-set! builtins type-atom #t))
  (atom-space initial root named types builtins (make-hasheq)
              ;; Session-owned association entries. Key comparison must use
              ;; mdl-identical?, which is broader than Racket eq? for WORDs
              ;; and independently constructed REST views.
              (box (list (list initial-name oblist-name initial)
                         (list root-name oblist-name root)
                         (list initial oblist-name initial-name)
                         (list root oblist-name root-name)))
              (make-hasheq)))

(define current-mdl-atom-space (make-parameter (make-mdl-atom-space)))

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
              oblist)))

(define (mdl-root . args)
  (unless (null? args)
    (error 'mdl-root "Too many arguments to ROOT"))
  (atom-space-root (current-mdl-atom-space)))

(define (mdl-lookup name oblist)
  (unless (string? name) (error 'mdl-lookup "expected a STRING PNAME"))
  (require-oblist 'mdl-lookup oblist)
  (hash-ref (oblist-value-entries oblist) name (lambda () (mdl-false '()))))

(define (mdl-insert value oblist)
  (require-oblist 'mdl-insert oblist)
  (define atom
    (cond [(string? value) (atom-value value #f)]
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

(define (mdl-oblist-of atom)
  (require-atom 'mdl-oblist? atom)
  (or (atom-value-oblist atom) (mdl-false '())))

(define (mdl-pname atom)
  (require-atom 'mdl-pname atom)
  (string-copy (atom-value-pname atom)))

(define (mdl-atom name)
  (unless (string? name) (error 'mdl-atom "expected a STRING PNAME"))
  (define trailer-match (regexp-match-positions #rx"!-" name))
  (define trailer-pos (and trailer-match (caar trailer-match)))
  (if trailer-pos
      (let* ([pname (substring name 0 trailer-pos)]
             [trailer (substring name (+ trailer-pos 2))])
        (when (or (string=? pname "") (string=? trailer ""))
          (error 'mdl-atom "invalid OBLIST trailer ~a" name))
        (define oblist (mdl-moblist (mdl-atom trailer)))
        (define found (mdl-lookup pname oblist))
        (if (mdl-false? found) (mdl-insert pname oblist) found))
      (let* ([space (current-mdl-atom-space)]
             [initial (atom-space-initial space)]
             [root (atom-space-root space)]
             [found (mdl-lookup name initial)])
        (if (mdl-false? found)
            (let ([root-found (mdl-lookup name root)])
              (if (mdl-false? root-found)
                  (mdl-insert name initial)
                  root-found))
            found))))

(define (mdl-list . vals)
  (foldr mcons '() vals))

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

(struct mdl-array (kind storage start length element-type))
(struct mdl-typed-value (type value))
(struct mdl-word-value (bits))
(struct mdl-bits-value (width edge))

(define word-mask (sub1 (arithmetic-shift 1 36)))
(define fix-min (- (arithmetic-shift 1 35)))
(define fix-max (sub1 (arithmetic-shift 1 35)))

(define mdl-word? mdl-word-value?)
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

(define (mdl-mod left right)
  (check-fix 'mdl-mod left)
  (check-fix 'mdl-mod right)
  (when (zero? right) (error 'mdl-mod "division by zero"))
  (modulo left right))

(define (mdl-fix value)
  (check-number 'mdl-fix value)
  (check-fix 'mdl-fix (inexact->exact (truncate value))))

(define (mdl-float value)
  (check-number 'mdl-float value)
  (exact->inexact value))

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
  (mdl-typed-value (mdl-atom "CHARACTER") (char->integer ch)))

(define (mdl-character-code value)
  (cond
    [(char? value) (char->integer value)]
    [(and (mdl-typed-value? value)
          (eq? (mdl-typed-value-type value) (mdl-atom "CHARACTER")))
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
        [(mdl-activation? value) "ACTIVATION"]
        [(mdl-word? value) "WORD"]
        [(mdl-bits-value? value) "BITS"]
        [(mdl-false? value) "FALSE"]
        [(mdl-tuple-value? value) "TUPLE"]
        [(mdl-macro? value) "MACRO"]
        [(mdl-function? value) "FUNCTION"]
        [(mdl-decl-value? value) "DECL"]
        [(mdl-atom? value) "ATOM"]
        [(mdl-oblist? value) "OBLIST"]
        [(or (null? value) (mpair? value)) "LIST"]
        [(mdl-array? value) (symbol->string (mdl-array-kind value))]
        [(exact-integer? value) (check-fix 'mdl-type value) "FIX"]
        [(and (real? value) (inexact? value)) "FLOAT"]
        [(char? value) "CHARACTER"]
        [(string? value) "STRING"]
        [else (error 'mdl-type "unsupported MDL type ~a" value)]))

(define (mdl-vector . values)
  (mdl-array 'VECTOR (list->vector values) 0 (length values) #f))

(define (mdl-uvector . values)
  (define element-type (and (pair? values) (mdl-type (car values))))
  (for ([value (in-list values)])
    (when (or (string=? (mdl-type-name value) "STRING")
              (not (eq? (mdl-type value) element-type)))
      (error 'mdl-uvector "UVECTOR elements must have one permitted TYPE")))
  (mdl-array 'UVECTOR (list->vector values) 0 (length values) element-type))

;; Unevaluated UVECTOR data may contain SEGMENT placeholders; uniformity is
;; enforced when the data is evaluated (see uniform-uvector).
(define (mdl-data-uvector . values)
  (mdl-array 'UVECTOR (list->vector values) 0 (length values) #f))

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
        [(string? base) (string-length base)]
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
     (if (mdl-array? base)
         (begin
           (when (> offset (mdl-array-length base))
             (error 'mdl-rest "offset out of range"))
           (if (and (zero? offset) (not (mdl-typed-value? value))) value
               (mdl-array (mdl-array-kind base) (mdl-array-storage base)
                          (+ (mdl-array-start base) offset)
                          (- (mdl-array-length base) offset)
                          (mdl-array-element-type base))))
         (mdl-list-tail (mdl-list-head value 'mdl-rest) offset 'mdl-rest))]))

(define (mdl-check-index who value index)
  (unless (and (exact-integer? index) (<= 1 index) (<= index (mdl-length value)))
    (error who "index out of range")))

(define (mdl-nth value [index 1])
  (mdl-check-index 'mdl-nth value index)
  (define base (mdl-base value))
  (cond [(mdl-array? base)
         (vector-ref (mdl-array-storage base) (+ (mdl-array-start base) (sub1 index)))]
        [(string? base) (mdl-character (string-ref base (sub1 index)))]
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
  (and ;; Native SUBRs are represented as host procedures; they are
       ;; unstructured MDL items and may carry FIX-keyed associations.
       (not (procedure? value))
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
    [(string? base)
     (define code (mdl-character-code item))
     (unless code
       (error 'mdl-put "Error in PUT: Strings may only contain CHARACTER type"))
     (when (immutable? base)
       (error 'mdl-put "immutable STRING literal cannot be mutated"))
     (string-set! base (sub1 index) (integer->char code))]
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
    (unless (eq? prim (mdl-atom "LIST"))
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
        [else (eq? left right)]))

(define (mdl-memq item structure)
  (define base (mdl-base structure))
  (when (string? base)
    (error 'mdl-memq "unsupported STRING MEMQ"))
  (unless (or (null? base) (mpair? base) (mdl-array? base)
              (mdl-false? base) (mdl-tuple-value? base))
    (error 'mdl-memq "Second arg to MEMQ must be structured"))
  (or (for/or ([offset (in-range (mdl-length structure))])
        (and (mdl-identical? item (mdl-nth structure (add1 offset)))
             (mdl-rest structure offset)))
      (mdl-false '())))

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
  (if value (mdl-atom "T") (mdl-false '())))

(define (mdl-type value)
  (if (mdl-typed-value? value)
      (mdl-typed-value-type value)
      (mdl-atom (mdl-type-name value))))

(define (mdl-typeprim type)
  (require-atom 'mdl-typeprim type)
  (define prim
    (hash-ref (atom-space-types (current-mdl-atom-space)) type
              (lambda () (error 'mdl-typeprim "unknown MDL TYPE ~a" (mdl-atom-pname type)))))
  (mdl-atom prim))

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
                      (or (and (eq? (car bracket) (mdl-atom "REST"))
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
            [else (bad)])]
         [(mdl-form? head)
          (define head-items (form-elements head))
          (unless (and (= (length head-items) 2)
                       (eq? (car head-items) (mdl-atom "PRIMTYPE"))
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
    (mdl-put-association! name (mdl-atom "DECL") (car declaration)))
  name)

(define (mdl-chtype value type)
  (require-atom 'mdl-chtype type)
  (define desired-prim (mdl-typeprim type))
  (unless (eq? (mdl-primtype value) desired-prim)
    (error 'mdl-chtype "primitive type mismatch"))
  (define converted
    (if (eq? (mdl-type value) type)
      value
      (let ([base (mdl-base value)] [target (mdl-atom-pname type)])
        (when (and (hash-has-key? (atom-space-builtins (current-mdl-atom-space)) type)
                   (not (member target '("LIST" "FALSE" "VECTOR" "UVECTOR"
                                         "FIX" "WORD"))))
          (error 'mdl-chtype "unsupported built-in TYPE conversion"))
        (when (and (not (or (null? base) (mpair? base)
                            (mdl-false? base) (mdl-array? base)))
                   (not (string=? (mdl-atom-pname desired-prim) "WORD")))
          (error 'mdl-chtype "unsupported primitive storage conversion"))
        (cond [(string=? (mdl-atom-pname desired-prim) "WORD")
               (cond [(string=? target "FIX")
                      (word-signed (word-bits-of base))]
                     [(string=? target "WORD")
                      (mdl-word (word-bits-of base))]
                     [(or (exact-integer? base) (mdl-word? base))
                      (mdl-typed-value type (mdl-word (word-bits-of base)))]
                     [else (error 'mdl-chtype "unsupported WORD reinterpretation")])]
              [(string=? target "LIST")
               (mdl-list-head base 'mdl-chtype)]
              [(string=? target "FALSE")
               (mdl-false (mdl-list-head base 'mdl-chtype))]
              [(or (string=? target "VECTOR") (string=? target "UVECTOR"))
               base]
              [(member (mdl-atom-pname desired-prim) '("LIST" "VECTOR" "UVECTOR"))
               (mdl-typed-value type base)]
              [else (error 'mdl-chtype "unsupported primitive type conversion")]))))
  (define declared (association-lookup type (mdl-atom "DECL")))
  (when declared
    (define pattern (normalize-decl-pattern (cdr declared) #f #f "CHTYPE"))
    (unless (matches-decl? converted pattern)
      (error 'mdl-chtype "TYPE-MISMATCH: value does not satisfy NEWTYPE declaration")))
  converted)

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
           (cond [(string? piece) piece]
                 [(mdl-character-code piece)
                  (string (integer->char (mdl-character-code piece)))]
                 [else (error 'mdl-string
                              "STRING expects STRING or CHARACTER arguments")]))))

(define (mdl-printstring buffer)
  (unless (string? buffer)
    (error 'mdl-printstring "PRINTSTRING expects a STRING buffer"))
  (display buffer)
  ;; The MDL manual returns the number of characters printed. Pinned
  ;; Confusion returns the original STRING; see docs/SEMANTICS.md.
  (string-length buffer))

(define (mdl-terpri)
  (newline)
  (mdl-false '()))

(define (mdl-error . args)
  ;; ERROR transfers control out of the current evaluation. The native
  ;; reference enters a resumable error level; this local runtime has no
  ;; error-frame/ERRET support, so preserve the failure as an exception.
  (define (describe value)
    (cond [(mdl-atom? value) (mdl-atom-pname value)]
          [(string? value) (format "~s" value)]
          [else (format "~a" value)]))
  (error 'mdl-error "~a"
         (if (null? args) "ERROR" (string-join (map describe args) " "))))

(define (mdl-map-structured? value)
  (define base (mdl-base value))
  (or (null? base) (mpair? base) (mdl-array? base)
      (string? base) (mdl-false? base) (mdl-tuple-value? base)))

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
  (leave (if (null? values) (mdl-atom "T") (car values))))

(define (mdl-mapf finalf loopf . structures)
  (for ([structure (in-list structures)])
    (unless (mdl-map-structured? structure)
      (error 'mdl-mapf "Arguments to MAPF must be structured")))
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
                    (mdl-nth structure index))]
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

(define (mdl-typeq . args)
  (when (null? args)
    (error 'mdl-typeq "Not enough arguments to TYPE?"))
  (define actual (mdl-type (car args)))
  (if (member actual (cdr args) eq?) actual (mdl-false '())))

(define (mdl-andq . args)
  ;; mdl-dispatch-call evaluates the complete SUBR argument list before
  ;; invoking this procedure, including arguments after the first FALSE.
  (let loop ([remaining args])
    (cond [(null? remaining) (mdl-atom "T")]
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
    (if (or (mdl-array? base) (string? base))
        (zero? (mdl-length object))
        (null? (mdl-list-head object 'mdl-emptyq))))
  (if empty? (mdl-atom "T") (mdl-false '())))

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
    [(or (mdl-array? base) (string? base))
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
        "UVECTOR" mdl-uvector
        "STRING" mdl-string
        "ASCII" mdl-ascii
        "PRINTSTRING" mdl-printstring
        "TERPRI" mdl-terpri
        "ERROR" mdl-error
        "MAPF" mdl-mapf
        "MAPRET" mdl-mapret
        "MAPSTOP" mdl-mapstop
        "MAPLEAVE" mdl-mapleave
        "APPLY" mdl-apply-subr
        "LENGTH" mdl-length
        "REST" mdl-rest
        "NTH" mdl-nth
        "PUT" mdl-put!
        "GET" mdl-get
        "MEMQ" (lambda args
                 (case (length args)
                   [(2) (mdl-memq (car args) (cadr args))]
                   [(0 1) (error 'mdl-memq "TOO-FEW-ARGUMENTS-SUPPLIED")]
                   [else (error 'mdl-memq "TOO-MANY-ARGUMENTS-SUPPLIED")]))
        "PUTREST" mdl-putrest!
        "FORM" (lambda elems (mdl-make-form (apply mdl-list elems)))
        "EXPAND" mdl-expand
        "ATOM" (lambda (name)
                 (unless (string? name) (error 'mdl-atom "expected a STRING PNAME"))
                 (atom-value name #f))
        "MOBLIST" mdl-moblist
        "ROOT" mdl-root
        "LOOKUP" mdl-lookup
        "INSERT" mdl-insert
        "REMOVE" mdl-remove
        "OBLIST?" mdl-oblist-of
        "PNAME" mdl-pname
        "+" mdl-add
        "-" mdl-sub
        "*" mdl-mul
        "/" mdl-div
        "MOD" mdl-mod
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
  ;; UNWIND: cleanup only when a transfer or error crosses below it.
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
  (check-true error-cleaned?)
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
