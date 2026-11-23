#lang racket/base
;; A deliberately narrow, tested MDL-to-Racket bootstrap compiler.
;; Anything outside this subset raises an error rather than guessing semantics.
(require racket/list racket/mpair racket/string
         (rename-in "parser.rkt" [mdl-node-value raw-node-value])
         "runtime/core.rkt")
(provide compile-program compile-expression
         exn:fail:mdl-compiler? exn:fail:mdl-compiler-node)

(struct exn:fail:mdl-compiler exn:fail (node) #:transparent)

(define (unsupported n message)
  (raise (exn:fail:mdl-compiler
          (format "mdl-compiler: ~a:~a: ~a"
                  (mdl-node-line n) (mdl-node-column n) message)
          (current-continuation-marks) n)))

(define (read-substitution? n)
  (and (mdl-node? n) (eq? (mdl-node-kind n) 'read-value)))

(define (substitution-value n)
  (mdl-read-value (raw-node-value n)))

;; The value remains in the session registry. Syntactic consumers may
;; inspect a one-level projection, whose children still refer to the
;; original MDL objects; they do not rebuild mutable structures.
(define (source-node-kind n)
  (if (read-substitution? n)
      (let ([value (substitution-value n)])
        (cond [(mdl-atom? value) 'atom]
              [(string? value) 'string]
              [(mdl-form? value) 'form]
              [(mdl-segment? value) 'splice]
              [(or (null? value) (mpair? value)) 'list]
              [(mdl-array? value)
               (string->symbol (string-downcase
                                (symbol->string (mdl-array-kind value))))]
              [(mdl-false? value) 'false]
              [else 'read-value]))
      (mdl-node-kind n)))

(define (source-node-value n)
  (if (read-substitution? n)
      (let ([value (substitution-value n)])
        (define (children items)
          (for/list ([item (in-list items)])
            (mdl-node 'read-value (mdl-register-read-value! item)
                      (mdl-node-line n) (mdl-node-column n))))
        (cond [(mdl-atom? value) (mdl-atom-pname value)]
              [(mdl-form? value) (children (form-elements value))]
              [(or (null? value) (mpair? value))
               (children (mdl-list->list value))]
              [(mdl-array? value)
               (children (for/list ([i (in-range (mdl-array-length value))])
                           (mdl-nth value (add1 i))))]
              [(mdl-false? value) (children (mdl-false-payload value))]
              [else value]))
      (raw-node-value n)))

(define (is-kind? n kind)
  (and (mdl-node? n) (eq? (source-node-kind n) kind)))

;; True for both ordinary and escaped-atom nodes: an escaped atom has the
;; same PNAME semantics as a plain atom but must bypass numeric/# classification.
(define (is-atom-node? n)
  (or (is-kind? n 'atom) (is-kind? n 'escaped-atom)))

(define (atom-name n)
  (unless (is-atom-node? n) (unsupported n "expected an MDL atom"))
  (when (and (read-substitution? n)
             (not (eq? (substitution-value n)
                       (mdl-atom (mdl-atom-pname (substitution-value n))))))
    (unsupported n "substituted ATOM outside the current OBLIST is unsupported here"))
  (string-upcase (source-node-value n)))

(define (mdl-constant n)
  (if (read-substitution? n)
      `(mdl-read-value ,(raw-node-value n))
      (mdl-constant/plain n)))

(define (mdl-constant/plain n)
  (define val (source-node-value n))
  (define upper (string-upcase val))
  (define (fix-or-float number)
    (if (and (exact-integer? number)
             (or (< number -34359738368) (> number 34359738367)))
        (let ([float (exact->inexact number)])
          (when (or (eqv? float +inf.0) (eqv? float -inf.0))
            (unsupported n "FLOAT literal overflow"))
          float)
        number))
  ;; An escaped atom (produced by a `\`-prefixed PNAME in source) is always
  ;; an ATOM regardless of its PNAME.  `\5` has PNAME "5" but is ATOM, not
  ;; FIX; `\#FOO` has PNAME "#FOO" but is ATOM, not an unsupported # token.
  ;; See MDL chapter 15 and issue I119.
  (if (is-kind? n 'escaped-atom)
      (atom-ref val)
      (cond
        [(string=? upper "#FALSE") (unsupported n "#FALSE requires a LIST payload")]
        [(string=? upper "#WORD") (unsupported n "#WORD requires a numeric payload")]
        [(member upper '("T" "ELSE" "NIL")) (atom-ref upper)]
        [(regexp-match? #px"^[+-]?[0-9]+$" val)
         (fix-or-float (string->number val))]
        [(regexp-match? #px"^[+-]?[0-9]+\\.$" val)
         (fix-or-float (string->number (substring val 0 (sub1 (string-length val)))))]
        [(regexp-match? #px"^[+-]?[0-9]+\\.[0-9]+$" val) (string->number val)]
        ;; Leading-dot FLOATs: `.5` → 0.5, `.05` → 0.05 (MDL ch.7; Confusion I124)
        [(regexp-match? #px"^\\.[0-9]+$" val) (string->number val)]
        [(regexp-match? #px"^\\.[0-9]+[Ee][+-]?[0-9]+$" val)
         (unsupported n "unsupported numeric token")]
        [(regexp-match? #px"^\\*[0-7]+\\*$" val)
         (fix-or-float (string->number (substring val 1 (sub1 (string-length val))) 8))]
        [(regexp-match? #px"^\\*[0-9]+\\*$" val)
         (unsupported n "invalid octal FIX token")]
        [(regexp-match? #px"^[+-]?[0-9]+(\\.[0-9]*)?[Ee][+-]?[0-9]+$" val)
         (unsupported n "unsupported numeric token")]
        [(string-prefix? val "#") (unsupported n "unsupported # reader token")]
        [else (atom-ref val)])))

(define (compile-typed n)
  (define tagged (source-node-value n))
  (define name (string-upcase (car tagged)))
  (define value (cdr tagged))
  (unless (regexp-match? #px"^#[A-Z]" name)
    (unsupported n (format "unsupported typed literal ~a" name)))
  (when (and (is-kind? value 'string) (string=? name "#WORD"))
    (unsupported n "#WORD requires a numeric literal"))
  (if (is-kind? value 'string)
      `(mdl-chtype ,(source-node-value value) ,(atom-ref (substring name 1)))
      (compile-typed-word n name value)))

(define (compile-typed-word n name value)
  (unless (is-atom-node? value)
    (unsupported n "#WORD requires a numeric literal"))
  (define raw (source-node-value value))
  (define bits
    (cond [(regexp-match? #px"^\\*[0-7]+\\*$" raw)
           (string->number (substring raw 1 (sub1 (string-length raw))) 8)]
          [(regexp-match? #px"^[+-]?[0-9]+$" raw)
           (string->number raw)]
          [else (unsupported n "numeric WORD literal requires a decimal or octal integer")]))
  (define word-expression `(mdl-word ,bits))
  (if (string=? name "#WORD")
      word-expression
      `(mdl-chtype ,word-expression ,(atom-ref (substring name 1)))))

;; A splice node compiles to a runtime SEGMENT object in data positions
;; (quoted structures, interpreted bodies, raw call arguments) and to a
;; splice marker inside structures being evaluated. The mark's payload is
;; the segment position, retained for diagnostics.
(define (splice-element? n) (is-kind? n 'splice))

(define (compile-splice-data n)
  (define payload (source-node-value n))
  (case (mdl-node-kind payload)
    [(local global form quote)
     `(mdl-make-segment ,(compile-data payload)
                        ,(mdl-node-line n) ,(mdl-node-column n))]
    [else (unsupported n "unsupported SEGMENT notation")]))

(define current-structured-context (make-parameter #f))

(define (compile-data n)
  (case (mdl-node-kind n)
    [(character) `(mdl-character ,(source-node-value n))]
    [(read-value) `(mdl-read-value ,(raw-node-value n))]
    [(percent)
     ;; Syntax-only callers may still compile the old side-effect-free
     ;; %<> case. Executable loading has already evaluated every percent
     ;; payload and supplies a read-value node instead.
     (define payload (source-node-value n))
     (unless (and (is-kind? payload 'form)
                  (null? (source-node-value payload)))
       (unsupported n "unsupported percent reader macro"))
     (if (current-mdl-literals)
         (retain-literal n `(mdl-false '()))
         `(mdl-false '()))]
    [(decl) `(mdl-make-declaration
              (mdl-list ,@(map compile-data (source-node-value n)))
              ,(mdl-node-line n) ,(mdl-node-column n))]
    [(atom escaped-atom) (mdl-constant n)]
    [(string) (source-node-value n)]
    [(splice) (compile-splice-data n)]
    [(list) `(mdl-list ,@(map compile-data (source-node-value n)))]
    [(vector) `(mdl-vector ,@(map compile-data (source-node-value n)))]
    ;; SEGMENT objects in unevaluated UVECTOR data are placeholders, so data
    ;; construction must not enforce element uniformity; the runtime
    ;; evaluator does that when the data is evaluated.
    [(uvector)
     (if (ormap splice-element? (source-node-value n))
         `(mdl-data-uvector ,@(map compile-data (source-node-value n)))
         `(mdl-uvector ,@(map compile-data (source-node-value n))))]
    [(false) `(mdl-false (mdl-list ,@(map compile-data (source-node-value n))))]
    [(form) `(mdl-make-form
              (mdl-list ,@(map compile-data (source-node-value n))))]
    [(local) `(mdl-make-form
               (mdl-list (mdl-root-atom "LVAL")
                         ,(atom-ref (string-upcase (source-node-value n)))))]
    [(global)
     `(mdl-make-form
       (mdl-list (mdl-root-atom "GVAL")
                 ,(if (string? (source-node-value n))
                      (atom-ref (string-upcase (source-node-value n)))
                      (compile-data (source-node-value n)))))]
    [(quote) `(mdl-make-form
               (mdl-list (mdl-root-atom "QUOTE")
                         ,(compile-data (source-node-value n))))]
    [(typed) (compile-typed n)]
    [else (unsupported n "this MDL data construct is not implemented")]))

(define current-mdl-literals (make-parameter #f))

;; Atom identity is fixed when a top-level expression is read (manual 15.3:
;; READ looks each PNAME up in .OBLIST), not each time compiled code runs.
;; Every user-text ATOM reference in one top-level expression is therefore
;; resolved once, in first-occurrence order, through the runtime's single
;; search path before the expression body runs; function bodies close over
;; those atoms. Binding OBLIST at run time affects only later reads.
(define current-mdl-atom-refs (make-parameter #f))

(define (atom-ref name)
  (define refs (current-mdl-atom-refs))
  (unless refs
    (error 'mdl-compiler "ATOM reference outside a top-level expression: ~a" name))
  (define table (car refs))
  (or (hash-ref table name #f)
      (let ([id (gensym 'mdl-atom)])
        (hash-set! table name id)
        (set-box! (cdr refs) (cons (list id `(mdl-atom ,name)) (unbox (cdr refs))))
        id)))

(define (retain-literal n [compiled #f])
  (define id (gensym 'mdl-literal))
  (set-box! (current-mdl-literals)
            (cons (list id (or compiled (compile-data n)))
                  (unbox (current-mdl-literals))))
  id)

(define (compile-quote n)
  (if (is-atom-node? n)
      (mdl-constant n)
      (retain-literal n)))

(define (compile-sequence body locals)
  (when (null? body) (error 'mdl-compiler "empty body"))
  `(begin ,@(map (lambda (n) (compile-expression n locals)) body)))

(define (split-declaration owner body)
  (define decl (and (pair? body) (is-kind? (car body) 'decl) (car body)))
  (define expressions (if decl (cdr body) body))
  (for ([item (in-list expressions)])
    (when (is-kind? item 'decl)
      (unsupported item "#DECL must immediately follow the formal or auxiliary list")))
  (when (null? expressions) (unsupported owner "declaration requires a body"))
  (values decl expressions))

(define (compile-definition n xs)
  ;; Historical DEFINE admits an activation name ATOM between the function
  ;; name and the formal list: <DEFINE F SELF (ARGS) BODY>. The 1977
  ;; sources use this form (SEARCH-LIST SL ...); "NAME"/"ACT" markers in
  ;; the formal list bind the same activation.
  (define-values (leading-act args-node body-xs)
    (cond [(and (>= (length xs) 4)
                (is-atom-node? (second xs))
                (is-kind? (third xs) 'list))
           (values (atom-name (second xs)) (third xs) (cdddr xs))]
          [(and (>= (length xs) 3) (is-kind? (second xs) 'list))
           (values #f (second xs) (cddr xs))]
          [else (unsupported n "DEFINE expects a name, argument list, and body")]))
  (define-values (decl body) (split-declaration n body-xs))
  (define decl-expr (if decl (compile-data decl) #f))
  (define fn-name (atom-name (first xs)))
  (define specs (parse-formal-list args-node))
  ;; The leading activation atom binds before all formals, like the
  ;; reference binding it before mdl_bind_args runs.
  (define all-specs
    (if leading-act
        (cons (list 'name leading-act #f) specs)
        specs))
  (define has-activation?
    (or leading-act (memq 'name (map first specs))))
  (define names
    (append (if leading-act (list leading-act) '())
            (for/list ([spec (in-list specs)]) (second spec))))
  (if (ormap (lambda (spec) (memq (first spec) '(quoted quoted-optional))) specs)
      `(mdl-define-interpreted!
        ,(atom-ref fn-name)
        ,(compile-data args-node)
        (list ,@(map compile-data body))
        ,(if leading-act (atom-ref leading-act) #f)
        ,decl-expr)
      `(let ([definition-decl ,decl-expr])
         (mdl-define! ,(atom-ref fn-name)
     (lambda mdl-given-args
       (mdl-with-function-scope
        (lambda ()
         ,(if has-activation?
              `(mdl-call-with-activation
                ,(atom-ref fn-name)
                (list ,@(map (lambda (spec) (spec-expression spec names)) all-specs))
                mdl-given-args
                (lambda () ,(compile-sequence body names))
                definition-decl)
              `(mdl-bind-function-formals
                ,(atom-ref fn-name)
                (list ,@(map (lambda (spec) (spec-expression spec names)) all-specs))
                mdl-given-args
                #f
                (lambda () ,(compile-sequence body names))
                definition-decl)))))
         ',(for/list ([spec (in-list specs)])
             (if (and (eq? (first spec) 'rest)
                      (eq? (third spec) 'args))
                 'rest-args
                 (first spec)))))))

;; Historical formal lists mark sections with STRINGs: "OPT"/"OPTIONAL",
;; "ARGS", "TUPLE", "AUX"/"EXTRA", and "NAME"/"ACT" for the function's own
;; activation. ATOMs are ordinary formals, and an ATOM named AUX is not a
;; marker. Two-element LISTs give an optional or auxiliary binding its
;; initial-value expression. Section order follows the pinned Confusion
;; state machine: required atoms, then OPTIONAL, then one ARGS or TUPLE
;; binding, then AUX, with the activation name last.
(define (formal-marker-section marker item section)
  ;; Section transitions for the STRING markers in a formal list.
  (case marker
    [("OPT" "OPTIONAL")
     (unless (eq? section 'required)
       (unsupported item "OPTIONAL in wrong place in formal list"))
     'optional]
    [("ARGS" "TUPLE")
     (unless (memq section '(required optional))
       (unsupported item (format "~a in wrong place in formal list" marker)))
     'rest]
    [("AUX" "EXTRA")
     (unless (memq section '(required optional after-rest))
       (unsupported item "AUX in wrong place in formal list"))
     'aux]
    [("NAME" "ACT")
     (unless (memq section '(required optional after-rest aux))
       (unsupported item "NAME in wrong place in formal list"))
     'name]
    [("BIND" "CALL")
     (unsupported item
                 (format "activation formal ~a is not supported in this slice"
                         marker))]
    [else (unsupported item "unknown formal list marker")]))

(define (parse-formal-list args-node)
  (define specs '())
  (define seen '())
  (define (add-name! name item)
    (when (member name seen)
      (unsupported item "BAD-ARGUMENT-LIST: duplicate formal argument"))
    (set! seen (cons name seen)))
  (define (add-spec! item kind name [init #f])
    (add-name! name item)
    (set! specs (cons (list kind name init) specs)))
  (let loop ([items (source-node-value args-node)] [section 'required])
    (unless (null? items)
      (define item (car items))
      (cond
        [(is-kind? item 'string)
         (define marker (string-upcase (source-node-value item)))
         (define next (formal-marker-section marker item section))
         (cond
           [(memq next '(optional aux name)) (loop (cdr items) next)]
           [else ; one ARGS or TUPLE rest binding
            (when (or (null? (cdr items))
                      (not (is-atom-node? (cadr items))))
              (unsupported item "ARGS or TUPLE requires an ATOM formal"))
            (define target (cadr items))
            (add-spec! item 'rest (atom-name target)
                       (if (string=? marker "TUPLE") 'tuple 'args))
            (loop (cddr items) 'after-rest)])]
        [(is-atom-node? item)
         (define name (atom-name item))
         (define next-section
           (case section
             [(required) (add-spec! item 'required name) section]
             [(optional) (add-spec! item 'optional name) section]
             [(aux) (add-spec! item 'aux name) section]
             [(name) (add-spec! item 'name name) 'after-name]
             [else (unsupported item "ATOM formal not allowed in this section")]))
         (loop (cdr items) next-section)]
        [(is-kind? item 'quote)
         (unless (is-atom-node? (source-node-value item))
           (unsupported item "quoted formal must name an ATOM"))
         (define kind
           (case section
             [(required) 'quoted]
             [(optional) 'quoted-optional]
             [else (unsupported item "quoted formal not allowed in this section")]))
         (add-spec! item kind (atom-name (source-node-value item)))
         (loop (cdr items) section)]
        [(and (is-kind? item 'list) (= (length (source-node-value item)) 2))
         (unless (memq section '(optional aux))
           (unsupported item
                        "2-list defaults are allowed only in OPTIONAL or AUX sections"))
         (define pair (source-node-value item))
         (define quoted? (is-kind? (first pair) 'quote))
         (when (and quoted? (not (eq? section 'optional)))
           (unsupported item "quoted formal not allowed in this section"))
         (define name-node (if quoted? (source-node-value (first pair)) (first pair)))
         (unless (is-atom-node? name-node)
           (unsupported item (if quoted? "quoted formal must name an ATOM"
                                 "formal name must be an ATOM")))
         (add-spec! item (if quoted? 'quoted-optional section)
                    (atom-name name-node) (second pair))
         (loop (cdr items) section)]
        [(is-kind? item 'form)
         (unsupported item "unsupported FORM in formal list")]
        [else (unsupported item "unsupported formal argument")])))
  (reverse specs))

;; One bound formal becomes one ordered runtime spec entry; the rest entry
;; carries its kind symbol instead of an initializer.
(define (spec-expression spec names)
  (define kind (first spec))
  (define name (second spec))
  (define (default-thunk)
    (define init (third spec))
    (if init `(lambda () ,(compile-expression init names)) #f))
  (case kind
    [(required) `(list 'required ,(atom-ref name))]
    [(optional) `(list 'optional ,(atom-ref name) ,(default-thunk))]
    [(rest) `(list 'rest ',(third spec) ,(atom-ref name))]
    [(aux) `(list 'aux ,(atom-ref name) ,(default-thunk))]
    [(name) `(list 'name ,(atom-ref name))]
    [else (error 'mdl-compiler "unknown formal specification ~a" spec)]))

;; Atom-shaped reader tokens that constant compilation never treats as
;; ATOM values: decimal, FLOAT, and scientific literals, octal asterisk
;; forms (including malformed digits, which must reach mdl-constant's
;; explicit invalid-octal error), and # reader tokens. Everything else is
;; an atom name. PROG/REPEAT label detection shares this classification
;; with constant compilation.
;; An escaped-atom node (produced by a \-prefixed PNAME) is NEVER a constant
;; token regardless of PNAME text: `\5` is an ATOM named "5", not FIX 5.
(define (atom-node-constant-token? n)
  (and (not (is-kind? n 'escaped-atom))
       (let ([val (source-node-value n)])
         (or (regexp-match? #px"^[+-]?[0-9]" val)
             (regexp-match? #px"^\\.[0-9]" val)       ; leading-dot FLOAT: `.5`, `.5E1`
             (regexp-match? #px"^\\*[0-9]+\\*$" val)
             (string-prefix? val "#")))))

;; PROG and REPEAT bodies run as ordered items: top-level ATOMs are labels
;; skipped in normal flow and addressed by GO; other expressions compile to
;; thunks. Bare atom nodes also carry number, octal, and # reader tokens,
;; which constant compilation rejects or turns into FIX/FLOAT/WORD values;
;; only true atom names can be labels.
(define (prog-label-name n)
  (and (is-atom-node? n)
       (not (atom-node-constant-token? n))
       (atom-name n)))

(define (compile-prog-items body locals)
  (for/list ([n (in-list body)])
    (define label (prog-label-name n))
    (if label
        `(cons 'label ,(atom-ref label))
        `(cons 'expr (lambda () ,(compile-expression n locals))))))

(define (compile-prog n args locals [repeat? #f])
  (define name (if repeat? "REPEAT" "PROG"))
  (when (null? args)
    (unsupported n (format "~a requires an auxiliary LIST and body" name)))
  (define named?
    (and (>= (length args) 2)
         (is-atom-node? (car args))
         (is-kind? (second args) 'list)))
  (define activation-name (and named? (atom-name (car args))))
  (define operands (if named? (cdr args) args))
  (define aux (car operands))
  (unless (is-kind? aux 'list)
    (unsupported aux (format "~a requires an auxiliary LIST" name)))
  (when (null? (cdr operands))
    (unsupported n (format "~a requires a body" name)))
  (define-values (decl body) (split-declaration n (cdr operands)))
  (define names '())
  (define specs
    (for/list ([item (in-list (source-node-value aux))])
      (define-values (name initializer)
        (cond [(is-atom-node? item) (values (atom-name item) #f)]
              [(and (is-kind? item 'list)
                    (= (length (source-node-value item)) 2))
               (define pair (source-node-value item))
               (values (atom-name (first pair)) (second pair))]
              [else (unsupported item "PROG auxiliary must be an ATOM or two-element LIST")]))
      (when (member name names)
        (unsupported item "duplicate PROG auxiliary binding"))
      (set! names (cons name names))
      `(cons ,(atom-ref name)
             ,(if initializer
                  `(lambda () ,(compile-expression initializer locals))
                  #f))))
  (when (and activation-name (member activation-name names))
    (unsupported n "activation name duplicates an auxiliary binding"))
  `(mdl-with-prog-activation
    (vector ,@(compile-prog-items body locals))
    (list ,@specs)
    ,repeat?
    ,(if activation-name (atom-ref activation-name) #f)
    ,(if decl (compile-data decl) #f)))

(define (compile-cond n clauses locals)
  (when (null? clauses) (unsupported n "COND requires at least one clause"))
  (define (compile-clause clause)
    (unless (and (is-kind? clause 'list) (pair? (source-node-value clause)))
      (unsupported clause "COND requires nonempty parenthesized clauses"))
    (source-node-value clause))
  (define (loop remaining)
    (define exprs (compile-clause (car remaining)))
    (define test-id (gensym 'mdl-test))
    `(let ([,test-id ,(compile-expression (car exprs) locals)])
       (if (mdl-truthy? ,test-id)
           ,(if (null? (cdr exprs)) test-id
                (compile-sequence (cdr exprs) locals))
           ,(if (null? (cdr remaining)) test-id
                (loop (cdr remaining))))))
  (loop clauses))

(define (compile-and args locals)
  (if (null? args)
      '(mdl-root-atom "T")
      (let loop ([remaining args])
        (if (null? (cdr remaining))
            (compile-expression (car remaining) locals)
            (let ([value-id (gensym 'mdl-and)])
              `(let ([,value-id ,(compile-expression (car remaining) locals)])
                 (if (mdl-truthy? ,value-id)
                     ,(loop (cdr remaining))
                     ,value-id)))))))

(define (compile-or args locals)
  (if (null? args)
      '(mdl-false '())
      (let loop ([remaining args])
        (if (null? (cdr remaining))
            (compile-expression (car remaining) locals)
            (let ([value-id (gensym 'mdl-or)])
              `(let ([,value-id ,(compile-expression (car remaining) locals)])
                 (if (mdl-truthy? ,value-id)
                     ,value-id
                     ,(loop (cdr remaining)))))))))

(define (compile-call-thunks args locals)
  `(list ,@(map (lambda (a)
                  (parameterize ([current-structured-context #t])
                    `(lambda () ,(compile-expression a locals))))
                args)))

(define (compile-form n locals)
  (define xs (source-node-value n))
  (if (null? xs)
      '(mdl-false '())
      (let* ([op-node (car xs)]
             [op (and (is-atom-node? op-node) (atom-name op-node))]
             [args (cdr xs)])
        (if (and op (not (number? (mdl-constant op-node))))
        (case (string->symbol op)
          [(DEFINE) (compile-definition n args)]
          [(FUNCTION)
           (define-values (leading-act formals-node body-xs)
             (cond [(and (>= (length args) 3)
                         (is-atom-node? (first args))
                         (is-kind? (second args) 'list))
                    (values (atom-name (first args)) (second args) (cddr args))]
                   [(and (>= (length args) 2) (is-kind? (first args) 'list))
                    (values #f (first args) (cdr args))]
                   [else (unsupported n "FUNCTION expects a formal LIST and body")]))
           (parse-formal-list formals-node)
           (define-values (decl body) (split-declaration n body-xs))
           `(mdl-function-literal ,(compile-data formals-node)
                                  (list ,@(map compile-data body))
                                  ,(if leading-act (atom-ref leading-act) #f)
                                  ,(if decl (compile-data decl) #f))]
          [(DEFMAC)
           (unless (and (pair? args) (is-atom-node? (first args)))
             (unsupported n "First argument of DEFMAC must be an atom"))
           (define-values (leading-act formals-node body-xs)
             (cond [(and (>= (length args) 4)
                         (is-atom-node? (second args))
                         (is-kind? (third args) 'list))
                    (values (atom-name (second args)) (third args) (cdddr args))]
                   [(and (>= (length args) 3) (is-kind? (second args) 'list))
                    (values #f (second args) (cddr args))]
                   [else (unsupported n "DEFMAC expects an ATOM name, formal list, and body")]))
           (parse-formal-list formals-node)
           (define-values (decl body) (split-declaration n body-xs))
           `(mdl-defmac! ,(atom-ref (atom-name (first args)))
                         ,(compile-data formals-node)
                         (list ,@(map compile-data body))
                         ,(if leading-act (atom-ref leading-act) #f)
                         ,(if decl (compile-data decl) #f))]
          [(PROG) (compile-prog n args locals)]
          [(REPEAT) (compile-prog n args locals #t)]
          [(RETURN)
           (when (> (length args) 2)
             (unsupported n "RETURN accepts at most a value and activation"))
           `(mdl-return ,(if (null? args)
                             '(mdl-root-atom "T")
                             (compile-expression (car args) locals))
                        ,@(if (= (length args) 2)
                              (list (compile-expression (second args) locals))
                              '()))]
          [(AGAIN)
           (when (> (length args) 1)
             (unsupported n "AGAIN accepts at most one activation"))
           (if (null? args)
               '(mdl-again)
               `(mdl-again ,(compile-expression (car args) locals)))]
          [(GO)
           (unless (= (length args) 1)
             (unsupported n "GO expects exactly one label argument"))
           `(mdl-go ,(compile-expression (first args) locals))]
          [(UNWIND)
           (unless (= (length args) 2)
             (unsupported n "UNWIND expects a value and cleanup expression"))
           `(mdl-unwind (lambda () ,(compile-expression (first args) locals))
                        (lambda () ,(compile-expression (second args) locals)))]
          [(GDECL)
           ;; FSUBR: preserve each source argument as MDL data. Pattern
           ;; forms and the ATOM-list must not be evaluated.
           `(mdl-gdecl (mdl-list ,@(map compile-data args)))]
          [(SETG)
           (unless (= (length args) 2) (unsupported n "SETG expects name and value"))
           `(mdl-setg! ,(compile-expression (first args) locals)
                       ,(compile-expression (second args) locals))]
          [(GVAL)
           (unless (= (length args) 1) (unsupported n "GVAL expects one atom"))
           `(mdl-gval ,(compile-expression (first args) locals))]
          [(SET)
           (unless (= (length args) 2) (unsupported n "SET expects name and value"))
           `(mdl-set! ,(compile-expression (first args) locals)
                      ,(compile-expression (second args) locals))]
          [(COND) (compile-cond n args locals)]
          [(AND) (compile-and args locals)]
          [(OR) (compile-or args locals)]
          [(NOT)
           (unless (= (length args) 1) (unsupported n "NOT expects one argument"))
           `(if (mdl-truthy? ,(compile-expression (first args) locals))
                (mdl-false '())
                (mdl-root-atom "T"))]
          [(QUOTE)
           (unless (= (length args) 1) (unsupported n "QUOTE expects one argument"))
           (compile-quote (first args))]
          [else
           `(mdl-apply-form ,(atom-ref op)
                            (lambda () (list ,@(map compile-data args)))
                            ,(compile-call-thunks args locals))])
        `(mdl-apply-computed ,(compile-expression op-node locals)
                             (lambda () (list ,@(map compile-data args)))
                             ,(compile-call-thunks args locals))))))

(define (compile-expression n [locals '()])
  ;; Retain each source literal once per compiled top-level expression.
  ;; A DEFINE then closes over the literal, retaining its identity on calls.
  ;; Atoms are bound outside literals, which may refer to them.
  (if (current-mdl-literals)
      (compile-expression/body n locals)
      (let ([literals (box '())]
            [atoms (cons (make-hash) (box '()))])
        (parameterize ([current-mdl-literals literals]
                       [current-mdl-atom-refs atoms])
          (define body (compile-expression/body n locals))
          (define with-literals
            (if (null? (unbox literals))
                body
                `(let ,(reverse (unbox literals)) ,body)))
          (if (null? (unbox (cdr atoms)))
              with-literals
              `(let ,(reverse (unbox (cdr atoms))) ,with-literals))))))

;; Structures whose elements include a SEGMENT compile every element to a
;; thunk handled by the runtime splice constructors: elements evaluate in
;; strict left-to-right order and SEGMENT payloads contribute their elements
;; (chapter 7.5.2), the last one by reference for LIST construction.
(define (compile-spliced-structure n spliced-constructor plain-constructor locals)
  (define elements (source-node-value n))
  (if (ormap splice-element? elements)
      `(,spliced-constructor
        ,@(for/list ([element (in-list elements)])
            (parameterize ([current-structured-context #t])
              `(lambda () ,(compile-expression element locals)))))
      `(,plain-constructor ,@(map (lambda (e) (compile-expression e locals)) elements))))

(define (compile-expression/body n locals)
  (case (mdl-node-kind n)
    [(character) `(mdl-character ,(source-node-value n))]
    [(read-value)
     (if (mdl-segment? (substitution-value n))
         (if (current-structured-context)
             `(mdl-splice-result
               (mdl-eval (mdl-segment-payload
                          (mdl-read-value ,(raw-node-value n))))
               ,(mdl-node-line n) ,(mdl-node-column n))
             `(mdl-eval (mdl-read-value ,(raw-node-value n))))
         `(mdl-eval (mdl-read-value ,(raw-node-value n))))]
    [(percent) (compile-data n)]
    [(atom escaped-atom) (mdl-constant n)]
    [(false) (retain-literal n)]
    [(string) (source-node-value n)]
    [(splice)
     ;; A SEGMENT only exists at a structured-evaluation position; the
     ;; reference breaks with ILLEGAL-SEGMENT anywhere else.
     (unless (current-structured-context)
       (unsupported n "SEGMENT outside a structured construction"))
     `(mdl-splice-result ,(compile-expression (source-node-value n) locals)
                         ,(mdl-node-line n) ,(mdl-node-column n))]
    [(local)
     `(mdl-lval ,(atom-ref (string-upcase (source-node-value n))))]
    [(global)
     `(mdl-gval ,(if (string? (source-node-value n))
                     (atom-ref (string-upcase (source-node-value n)))
                     (compile-expression (source-node-value n) locals)))]
    [(quote) (compile-quote (source-node-value n))]
    [(list) (compile-spliced-structure n 'mdl-splice-list 'mdl-list locals)]
    [(vector) (compile-spliced-structure n 'mdl-splice-vector 'mdl-vector locals)]
    [(uvector) (compile-spliced-structure n 'mdl-splice-uvector 'mdl-uvector locals)]
    [(typed)
     (if (string-ci=? (car (source-node-value n)) "#WORD")
         (compile-typed n)
         (retain-literal n))]
    [(decl) (compile-data n)]
    ;; Entering a FORM resets the structured context: only the form's own
    ;; argument positions (re-established by compile-apply and the spliced
    ;; structure constructors) may splice, so a bare SEGMENT nested in an
    ;; FSUBR body or a sibling element stays an explicit compile error
    ;; instead of laundering a splice marker into a call (PR #49 review).
    [(form) (parameterize ([current-structured-context #f])
              (compile-form n locals))]
    [else (unsupported n (format "unsupported MDL construct ~a" (mdl-node-kind n)))]))

(define (compile-program nodes)
  (map compile-expression nodes))
