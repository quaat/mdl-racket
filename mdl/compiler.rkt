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

(define (local-id name)
  ;; Exact symbols: don't remove punctuation in historical MDL identifiers.
  (string->symbol (string-append "mdl-local:" (string-upcase name))))

(define (mdl-constant n)
  (define val (mdl-node-value n))
  (define upper (string-upcase val))
  (cond
    [(string=? upper "#FALSE") (unsupported n "#FALSE requires a LIST payload")]
    [(member upper '("T" "ELSE" "NIL")) `(mdl-atom ,upper)]
    [(regexp-match? #px"^[+-]?[0-9]+$" val) (string->number val)]
    [(regexp-match? #px"^[+-]?[0-9]+\\.[0-9]+$" val) (string->number val)]
    [(regexp-match? #px"^\\*[0-7]+\\*$" val)
     (string->number (substring val 1 (sub1 (string-length val))) 8)]
    [else `(mdl-atom ,val)]))

(define (compile-data n)
  (case (mdl-node-kind n)
    [(atom) (mdl-constant n)]
    [(string) (mdl-node-value n)]
    [(list) `(mdl-list ,@(map compile-data (mdl-node-value n)))]
    [(vector) `(mdl-vector ,@(map compile-data (mdl-node-value n)))]
    [(uvector) `(mdl-uvector ,@(map compile-data (mdl-node-value n)))]
    [(false) `(mdl-false (mdl-list ,@(map compile-data (mdl-node-value n))))]
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
    (let* ([params (mdl-node-value args)]
           [names (and (andmap (lambda (p) (is-kind? p 'atom)) params)
                       (map atom-name params))])
      (unless names
        (unsupported args "DEFINE optional/AUX/TUPLE arguments not supported in M0"))
      (when (or (member "AUX" names) (member "OPTIONAL" names)
                (member "TUPLE" names) (check-duplicates names))
        (unsupported args "non-simple or duplicate DEFINE parameters"))
      `(mdl-define! (mdl-atom ,fn-name)
                    (lambda ,(map local-id names)
                      (mdl-with-bindings
                       (list ,@(map (lambda (name)
                                      `(cons (mdl-atom ,name) ,(local-id name)))
                                    names))
                       (lambda () ,(compile-sequence (cddr xs) names))))))))

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
    [(form) (compile-form n locals)]
    [else (unsupported n (format "unsupported MDL construct ~a" (mdl-node-kind n)))]))

(define (compile-program nodes)
  (map compile-expression nodes))
