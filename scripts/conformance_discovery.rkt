#lang racket/base

;; Read declaration syntax for the conformance inventory. The source modules
;; are never expanded or instantiated, and reader extensions are disabled.
(require json racket/list racket/match syntax/parse)

(define CORE "mdl/runtime/core.rkt")
(define COMPILER "mdl/compiler.rkt")
(define LOADER "mdl/loader.rkt")
(match-define (vector root) (current-command-line-arguments))

(define (read-forms file)
  (call-with-input-file (build-path root file)
    (lambda (input)
      (port-count-lines! input)
      (unless (equal? (read-line input 'any) "#lang racket/base")
        (error 'conformance-discovery "~a must use #lang racket/base" file))
      (parameterize ([read-accept-reader #f]
                     [read-accept-lang #f]
                     [read-accept-compiled #f])
        (for/list ([form (in-producer (lambda () (read-syntax file input)) eof)])
          form)))))

(define (top-definition forms name)
  (or (for/or ([form (in-list forms)])
        (syntax-parse form #:datum-literals (define)
          [(define (function:id . _) body ...)
           (and (eq? (syntax-e #'function) name) #'(body ...))]
          [(define binding:id value)
           (and (eq? (syntax-e #'binding) name) #'(value))]
          [_ #f]))
      (error 'conformance-discovery "definition ~a not found" name)))

;; A syntax walk over call sites, skipping literal data and compiler templates.
(define (find-forms body select)
  (let walk ([form body])
    (cond
      [(select form) => list]
      [else
       (syntax-parse form #:datum-literals (quote quasiquote syntax quasisyntax)
         [((~or quote quasiquote syntax quasisyntax) . _) '()]
         [(child ...) (append-map walk (syntax->list #'(child ...)))]
         [_ '()])])))

(define locations (make-hasheq))

(define (record! name-syntax kind)
  (define raw-name (syntax-e name-syntax))
  (define name (if (string? raw-name) (string->symbol raw-name) raw-name))
  (define site (hasheq 'file (syntax-source name-syntax)
                       'line (syntax-line name-syntax)
                       'kind kind))
  (hash-update! locations name (lambda (previous) (cons site previous)) '()))

(define core (read-forms CORE))
(define compiler (read-forms COMPILER))
(define loader (read-forms LOADER))

(define builtin (car (syntax->list (top-definition core 'builtin-table))))
(syntax-parse builtin #:datum-literals (hash)
  [(hash (~seq name:str value) ...+)
   (for ([name (in-list (syntax->list #'(name ...)))])
     (record! name "runtime operator binding"))]
  [_ (error 'conformance-discovery "expected a literal hash in builtin-table")])

(define (type-registration form)
  (syntax-parse form #:datum-literals (for in-list quote define seed-root! car cdr hash-set! types)
    [(for ([binding:id (in-list (quote ((name:str . primtype:str) ...+)))])
       (define type-atom:id (seed-root! (car key:id)))
       (hash-set! types registered:id (cdr value:id))
       _ ...)
     (and (eq? (syntax-e #'binding) (syntax-e #'key))
          (eq? (syntax-e #'binding) (syntax-e #'value))
          (eq? (syntax-e #'type-atom) (syntax-e #'registered))
          (syntax->list #'(name ...)))]
    [_ #f]))

(match (find-forms (top-definition core 'make-mdl-atom-space) type-registration)
  [(list names)
   (for ([name (in-list names)])
     (record! name "runtime type registration"))]
  [_ (error 'conformance-discovery "expected one startup type registration loop")])

(define (record-specials forms function selector kind)
  (define (dispatch form)
    (syntax-parse form #:datum-literals (case)
      [(case key clause ...)
       (and (equal? (syntax->datum #'key) selector)
            (syntax->list #'(clause ...)))]
      [_ #f]))
  (match (find-forms (top-definition forms function) dispatch)
    [(list clauses)
     (for ([clause (in-list clauses)])
       (syntax-parse clause #:datum-literals (else)
         [((name:id ...+) _ ...+)
          (for ([name (in-list (syntax->list #'(name ...)))])
            (record! name kind))]
         [(else _ ...+) (void)]
         [_ (error 'conformance-discovery "unrecognized operator clause in ~a" function)]))]
    [_ (error 'conformance-discovery "expected one operator case in ~a" function)]))

(record-specials compiler 'compile-form '(string->symbol op) "compiler special form")
(record-specials core 'mdl-eval-form '(string->symbol (mdl-atom-pname op))
                 "interpreted evaluator special form")

(define (loader-subroutine form)
  (syntax-parse form #:datum-literals (mdl-define-subr! mdl-root-atom)
    [(mdl-define-subr! (mdl-root-atom name:str) _) #'name]
    [_ #f]))

(for ([name (in-list (find-forms (top-definition loader 'make-mdl-session)
                                loader-subroutine))])
  (record! name "loader-only operator binding"))

(write-json
 (for/hasheq ([(name sites) (in-hash locations)])
   (values name (reverse sites))))
(newline)
