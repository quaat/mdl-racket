#lang racket/base
;; Bootstrap MDL runtime: intentionally incomplete and NOT a gameplay engine.
(require racket/mpair racket/list)
(provide current-mdl-globals mdl-setg! mdl-gval mdl-define! mdl-apply mdl-list
         mdl-truthy? mdl-atom)

(define current-mdl-globals (make-parameter (make-hash)))

(define (mdl-setg! name value)
  (hash-set! (current-mdl-globals) name value)
  value)

(define (mdl-gval name)
  (hash-ref (current-mdl-globals) name
            (lambda () (error 'mdl-gval "unassigned MDL global ~a" name))))

(define (mdl-define! name fn)
  (mdl-setg! name fn))

(define (mdl-atom name)
  ;; No symbol-table package semantics yet; a placeholder until M1.
  (string->symbol name))

(define (mdl-list . vals)
  (foldr mcons '() vals))

(define (mdl-truthy? value)
  ;; M0: only Racket #f is false. Historical MDL FALSE is richer: M1 gate.
  (not (eq? value #f)))

(define builtin-table
  (hash "+" +
        "-" -
        "*" *
        "/" /
        "MOD" modulo
        "L?" <
        "L=?" <=
        "G?" >
        "G=?" >=
        "=?" equal?
        "==?" eq?
        "N==?" (lambda (a b) (not (eq? a b)))
        "LENGTH" (lambda (v)
                    (cond [(string? v) (string-length v)]
                          [(vector? v) (vector-length v)]
                          [else (error 'mdl-length "unsupported type ~a" v)]))))

(define (mdl-apply name . args)
  (define fn (hash-ref builtin-table name #f))
  (apply (if fn fn (mdl-gval name)) args))
