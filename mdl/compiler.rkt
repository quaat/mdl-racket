#lang racket/base
;; A deliberately narrow, tested MDL-to-Racket bootstrap compiler.
;; Anything outside this subset raises an error rather than guessing semantics.
(require racket/list racket/string "parser.rkt")
(provide compile-program compile-expression)

(define (unsupported n message)
  (error 'mdl-compiler "~a:~a: ~a" (mdl-node-line n) (mdl-node-column n) message))

(define (is-kind? n kind)
  (and (mdl-node? n) (eq? (mdl-node-kind n) kind)))

(define (atom-name n)
  (unless (is-kind? n 'atom) (unsupported n "expected an MDL atom"))
  (string-upcase (mdl-node-value n)))

(define (mdl-constant n)
  (define val (mdl-node-value n))
  (define upper (string-upcase val))
  (define (fix-or-float number)
    (if (and (exact-integer? number)
             (or (< number -34359738368) (> number 34359738367)))
        (let ([float (exact->inexact number)])
          (when (or (eqv? float +inf.0) (eqv? float -inf.0))
            (unsupported n "FLOAT literal overflow"))
          float)
        number))
  (cond
    [(string=? upper "#FALSE") (unsupported n "#FALSE requires a LIST payload")]
    [(string=? upper "#WORD") (unsupported n "#WORD requires a numeric payload")]
    [(member upper '("T" "ELSE" "NIL")) `(mdl-atom ,upper)]
    [(regexp-match? #px"^[+-]?[0-9]+$" val)
     (fix-or-float (string->number val))]
    [(regexp-match? #px"^[+-]?[0-9]+\\.$" val)
     (fix-or-float (string->number (substring val 0 (sub1 (string-length val)))))]
    [(regexp-match? #px"^[+-]?[0-9]+\\.[0-9]+$" val) (string->number val)]
    [(regexp-match? #px"^\\*[0-7]+\\*$" val)
     (fix-or-float (string->number (substring val 1 (sub1 (string-length val))) 8))]
    [(regexp-match? #px"^\\*[0-9]+\\*$" val)
     (unsupported n "invalid octal FIX token")]
    [(regexp-match? #px"^[+-]?[0-9]+(\\.[0-9]*)?[Ee][+-]?[0-9]+$" val)
     (unsupported n "unsupported numeric token")]
    [(string-prefix? val "#") (unsupported n "unsupported # reader token")]
    [else `(mdl-atom ,val)]))

(define (compile-typed n)
  (define tagged (mdl-node-value n))
  (define name (string-upcase (car tagged)))
  (define value (cdr tagged))
  (unless (string=? name "#WORD")
    (unsupported n (format "unsupported typed literal ~a" name)))
  (unless (is-kind? value 'atom)
    (unsupported n "#WORD requires a numeric literal"))
  (define raw (mdl-node-value value))
  (define bits
    (cond [(regexp-match? #px"^\\*[0-7]+\\*$" raw)
           (string->number (substring raw 1 (sub1 (string-length raw))) 8)]
          [(regexp-match? #px"^[+-]?[0-9]+$" raw)
           (string->number raw)]
          [else (unsupported n "#WORD requires a decimal or octal integer")]))
  `(mdl-word ,bits))

(define (compile-data n)
  (case (mdl-node-kind n)
    [(atom) (mdl-constant n)]
    [(string) (mdl-node-value n)]
    [(list) `(mdl-list ,@(map compile-data (mdl-node-value n)))]
    [(vector) `(mdl-vector ,@(map compile-data (mdl-node-value n)))]
    [(uvector) `(mdl-uvector ,@(map compile-data (mdl-node-value n)))]
    [(false) `(mdl-false (mdl-list ,@(map compile-data (mdl-node-value n))))]
    [(typed) (compile-typed n)]
    [else (unsupported n "this MDL data construct is not implemented")]))

(define current-mdl-literals (make-parameter #f))

(define (retain-literal n)
  (define id (gensym 'mdl-literal))
  (set-box! (current-mdl-literals)
            (cons (list id (compile-data n))
                  (unbox (current-mdl-literals))))
  id)

(define (compile-quote n)
  (if (is-kind? n 'atom)
      (mdl-constant n)
      (retain-literal n)))

(define (compile-sequence body locals)
  (when (null? body) (error 'mdl-compiler "empty body"))
  `(begin ,@(map (lambda (n) (compile-expression n locals)) body)))

(define (compile-definition n xs)
  (unless (>= (length xs) 3)
    (unsupported n "DEFINE expects a name, argument list, and body"))
  (let* ([fn-name (atom-name (first xs))]
         [args (second xs)])
    (unless (is-kind? args 'list)
      (unsupported args "DEFINE requires a parenthesized formal list"))
    (let-values ([(required optional rest aux)
                  (parse-formal-list args)])
      (define names (append required
                            (map car optional)
                            (map car aux)
                            (if rest (list (cdr rest)) '())))
      `(mdl-define! (mdl-atom ,fn-name)
                    (lambda mdl-given-args
                      (mdl-with-function-scope
                       (lambda ()
                         (mdl-bind-function-formals
                          (mdl-atom ,fn-name)
                          (list ,@(map (lambda (name) `(mdl-atom ,name)) required))
                          (list ,@(map formal-spec-expression optional))
                          ,(if rest
                               `(cons ',(car rest) (mdl-atom ,(cdr rest)))
                               #f)
                          (list ,@(map formal-spec-expression aux))
                          mdl-given-args
                          (lambda () ,(compile-sequence (cddr xs) names))))))))))

;; Historical formal lists mark sections with STRINGs: "OPT"/"OPTIONAL",
;; "ARGS", "TUPLE", and "AUX"/"EXTRA". ATOMs are ordinary formals, and an
;; ATOM named AUX is not a marker. Two-element LISTs give an optional or
;; auxiliary binding its initial-value expression. Section order follows the
;; pinned Confusion state machine: required atoms, then OPTIONAL, then one
;; ARGS or TUPLE binding, then AUX.
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
    [("BIND" "CALL" "NAME" "ACT")
     (unsupported item
                 (format "activation formal ~a is not supported in this slice"
                         marker))]
    [else (unsupported item "unknown formal list marker")]))

(define (parse-formal-list args-node)
  (define required '())
  (define optional '())
  (define aux '())
  (define rest #f)
  (define seen '())
  (define (add-name! name item)
    (when (member name seen)
      (unsupported item "BAD-ARGUMENT-LIST: duplicate formal argument"))
    (set! seen (cons name seen)))
  (let loop ([items (mdl-node-value args-node)] [section 'required])
    (unless (null? items)
      (define item (car items))
      (cond
        [(is-kind? item 'string)
         (define marker (string-upcase (mdl-node-value item)))
         (define next (formal-marker-section marker item section))
         (cond
           [(memq next '(optional aux)) (loop (cdr items) next)]
           [else ; one ARGS or TUPLE rest binding
            (when rest
              (unsupported item "only one ARGS or TUPLE formal is allowed"))
            (when (or (null? (cdr items))
                      (not (is-kind? (cadr items) 'atom)))
              (unsupported item "ARGS or TUPLE requires an ATOM formal"))
            (define target (cadr items))
            (define name (atom-name target))
            (add-name! name target)
            (set! rest (cons (if (string=? marker "TUPLE") 'tuple 'args) name))
            (loop (cddr items) 'after-rest)])]
        [(is-kind? item 'atom)
         (define name (atom-name item))
         (case section
           [(required) (add-name! name item)
                        (set! required (cons name required))]
           [(optional) (add-name! name item)
                        (set! optional (cons (cons name #f) optional))]
           [(aux) (add-name! name item)
                  (set! aux (cons (cons name #f) aux))]
           [else (unsupported item "ATOM formal not allowed in this section")])
         (loop (cdr items) section)]
        [(and (is-kind? item 'list) (= (length (mdl-node-value item)) 2))
         (unless (memq section '(optional aux))
           (unsupported item
                        "2-list defaults are allowed only in OPTIONAL or AUX sections"))
         (define pair (mdl-node-value item))
         (define name (atom-name (first pair)))
         (add-name! name item)
         (case section
           [(optional) (set! optional (cons (cons name (second pair)) optional))]
           [(aux) (set! aux (cons (cons name (second pair)) aux))])
         (loop (cdr items) section)]
        [(is-kind? item 'form)
         (unsupported item "quoted formal arguments are not supported")]
        [else (unsupported item "unsupported formal argument")])))
  (values (reverse required) (reverse optional) rest (reverse aux)))

(define (formal-spec-expression spec)
  `(cons (mdl-atom ,(car spec))
         ,(if (cdr spec)
              `(lambda () ,(compile-expression (cdr spec) '()))
              #f)))

(define (compile-prog n args locals [repeat? #f])
  (define name (if repeat? "REPEAT" "PROG"))
  (when (null? args)
    (unsupported n (format "~a requires an auxiliary LIST and body" name)))
  (define named?
    (and (>= (length args) 2)
         (is-kind? (car args) 'atom)
         (is-kind? (second args) 'list)))
  (define activation-name (and named? (atom-name (car args))))
  (define operands (if named? (cdr args) args))
  (define aux (car operands))
  (unless (is-kind? aux 'list)
    (unsupported aux (format "~a requires an auxiliary LIST" name)))
  (when (null? (cdr operands))
    (unsupported n (format "~a requires a body" name)))
  (define names '())
  (define specs
    (for/list ([item (in-list (mdl-node-value aux))])
      (define-values (name initializer)
        (cond [(is-kind? item 'atom) (values (atom-name item) #f)]
              [(and (is-kind? item 'list)
                    (= (length (mdl-node-value item)) 2))
               (define pair (mdl-node-value item))
               (values (atom-name (first pair)) (second pair))]
              [else (unsupported item "PROG auxiliary must be an ATOM or two-element LIST")]))
      (when (member name names)
        (unsupported item "duplicate PROG auxiliary binding"))
      (set! names (cons name names))
      `(cons (mdl-atom ,name)
             ,(if initializer
                  `(lambda () ,(compile-expression initializer locals))
                  #f))))
  (when (and activation-name (member activation-name names))
    (unsupported n "activation name duplicates an auxiliary binding"))
  `(mdl-with-prog-activation
    (lambda () ,(compile-sequence (cdr operands) locals))
    (list ,@specs)
    ,repeat?
    ,(if activation-name `(mdl-atom ,activation-name) #f)))

(define (compile-cond n clauses locals)
  (when (null? clauses) (unsupported n "COND requires at least one clause"))
  (define (compile-clause clause)
    (unless (and (is-kind? clause 'list) (pair? (mdl-node-value clause)))
      (unsupported clause "COND requires nonempty parenthesized clauses"))
    (mdl-node-value clause))
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
      '(mdl-atom "T")
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

(define (compile-form n locals)
  (define xs (mdl-node-value n))
  (if (null? xs)
      '(mdl-false '())
      (let* ([op-node (car xs)]
             [op (atom-name op-node)]
             [args (cdr xs)])
        (case (string->symbol op)
          [(DEFINE) (compile-definition n args)]
          [(PROG) (compile-prog n args locals)]
          [(REPEAT) (compile-prog n args locals #t)]
          [(RETURN)
           (when (> (length args) 2)
             (unsupported n "RETURN accepts at most a value and activation"))
           `(mdl-return ,(if (null? args)
                             '(mdl-atom "T")
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
                (mdl-atom "T"))]
          [(QUOTE)
           (unless (= (length args) 1) (unsupported n "QUOTE expects one argument"))
           (compile-quote (first args))]
          [else
           `(mdl-apply ,op ,@(map (lambda (a) (compile-expression a locals)) args))]))))

(define (compile-expression n [locals '()])
  ;; Retain each source literal once per compiled top-level expression.
  ;; A DEFINE then closes over the literal, retaining its identity on calls.
  (if (current-mdl-literals)
      (compile-expression/body n locals)
      (let ([literals (box '())])
        (parameterize ([current-mdl-literals literals])
          (define body (compile-expression/body n locals))
          (if (null? (unbox literals))
              body
              `(let ,(reverse (unbox literals)) ,body))))))

(define (compile-expression/body n locals)
  (case (mdl-node-kind n)
    [(atom) (mdl-constant n)]
    [(false) (retain-literal n)]
    [(string) (mdl-node-value n)]
    [(local)
     `(mdl-lval (mdl-atom ,(string-upcase (mdl-node-value n))))]
    [(global)
     `(mdl-gval ,(if (string? (mdl-node-value n))
                     `(mdl-atom ,(string-upcase (mdl-node-value n)))
                     (compile-expression (mdl-node-value n) locals)))]
    [(quote) (compile-quote (mdl-node-value n))]
    [(list) `(mdl-list ,@(map (lambda (a) (compile-expression a locals))
                              (mdl-node-value n)))]
    [(vector) `(mdl-vector ,@(map (lambda (a) (compile-expression a locals))
                                 (mdl-node-value n)))]
    [(uvector) `(mdl-uvector ,@(map (lambda (a) (compile-expression a locals))
                                   (mdl-node-value n)))]
    [(typed) (compile-typed n)]
    [(form) (compile-form n locals)]
    [else (unsupported n (format "unsupported MDL construct ~a" (mdl-node-kind n)))]))

(define (compile-program nodes)
  (map compile-expression nodes))
