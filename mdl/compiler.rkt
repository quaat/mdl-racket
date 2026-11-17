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
    [(string=? upper "T") #t]
    [(string=? upper "ELSE") #t]
    [(string=? upper "NIL") #f]
    [(regexp-match? #px"^[+-]?[0-9]+$" val) (string->number val)]
    [(regexp-match? #px"^[+-]?[0-9]+\\.[0-9]+$" val) (string->number val)]
    [(regexp-match? #px"^\\*[0-7]+\\*$" val)
     (string->number (substring val 1 (sub1 (string-length val))) 8)]
    [else `(mdl-atom ,val)]))

(define (quote-datum n)
  (case (mdl-node-kind n)
    [(atom) (string->symbol (mdl-node-value n))]
    [(string) (mdl-node-value n)]
    [(list) (map quote-datum (mdl-node-value n))]
    [(vector uvector) (list->vector (map quote-datum (mdl-node-value n)))]
    [else (unsupported n "quoting this MDL form is not implemented")]))

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
      `(mdl-define! ,fn-name
                    (lambda ,(map local-id names)
                      ,(compile-sequence (cddr xs) names))))))

(define (compile-cond n clauses locals)
  (define (compile-clause clause)
    (unless (and (is-kind? clause 'list) (pair? (mdl-node-value clause)))
      (unsupported clause "COND requires nonempty parenthesized clauses"))
    (let ([exprs (mdl-node-value clause)])
      (list `(mdl-truthy? ,(compile-expression (car exprs) locals))
            (if (null? (cdr exprs))
                (compile-expression (car exprs) locals)
                (compile-sequence (cdr exprs) locals)))))
  `(cond ,@(map compile-clause clauses) [else #f]))

(define (compile-form n locals)
  (define xs (mdl-node-value n))
  (if (null? xs)
      #f
      (let* ([op-node (car xs)]
             [op (atom-name op-node)]
             [args (cdr xs)])
        (case (string->symbol op)
          [(DEFINE) (compile-definition n args)]
          [(SETG)
           (unless (= (length args) 2) (unsupported n "SETG expects name and value"))
           `(mdl-setg! ,(atom-name (first args))
                       ,(compile-expression (second args) locals))]
          [(GVAL)
           (unless (= (length args) 1) (unsupported n "GVAL expects one atom"))
           `(mdl-gval ,(atom-name (first args)))]
          [(SET)
           (unless (= (length args) 2) (unsupported n "SET expects name and value"))
           (let ([name (atom-name (first args))])
             (unless (member name locals)
               (unsupported n "SET currently supports function parameters only"))
             (let ([ident (local-id name)])
               `(let ([new-value ,(compile-expression (second args) locals)])
                  (set! ,ident new-value)
                  new-value)))]
          [(COND) (compile-cond n args locals)]
          [(AND)
           `(and ,@(map (lambda (a)
                         `(mdl-truthy? ,(compile-expression a locals))) args))]
          [(OR) `(or ,@(map (lambda (a) (compile-expression a locals)) args))]
          [(NOT)
           (unless (= (length args) 1) (unsupported n "NOT expects one argument"))
           `(not (mdl-truthy? ,(compile-expression (first args) locals)))]
          [(QUOTE)
           (unless (= (length args) 1) (unsupported n "QUOTE expects one argument"))
           `(quote ,(quote-datum (first args)))]
          [else
           `(mdl-apply ,op ,@(map (lambda (a) (compile-expression a locals)) args))]))))

(define (compile-expression n [locals '()])
  (case (mdl-node-kind n)
    [(atom) (mdl-constant n)]
    [(string) (mdl-node-value n)]
    [(local)
     (let ([name (string-upcase (mdl-node-value n))])
       (unless (member name locals)
         (unsupported n (format "unbound MDL local .~a" name)))
       (local-id name))]
    [(global) `(mdl-gval ,(string-upcase (mdl-node-value n)))]
    [(quote) `(quote ,(quote-datum (mdl-node-value n)))]
    [(list) `(mdl-list ,@(map (lambda (a) (compile-expression a locals))
                              (mdl-node-value n)))]
    [(vector) `(vector ,@(map (lambda (a) (compile-expression a locals))
                             (mdl-node-value n)))]
    [(form) (compile-form n locals)]
    [else (unsupported n (format "unsupported MDL construct ~a" (mdl-node-kind n)))]))

(define (compile-program nodes)
  (map compile-expression nodes))
