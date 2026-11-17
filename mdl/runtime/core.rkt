#lang racket/base
;; Bootstrap MDL runtime: intentionally incomplete and NOT a gameplay engine.
(require racket/mpair racket/list)
(provide current-mdl-globals mdl-setg! mdl-gval mdl-define! mdl-apply mdl-list
         mdl-truthy? mdl-atom mdl-false mdl-false? mdl-false-payload)

(struct mdl-false-value (payload) #:transparent)
(define empty-mdl-false (mdl-false-value '()))
(define (mdl-false payload)
  (if (null? payload) empty-mdl-false (mdl-false-value payload)))
(define mdl-false? mdl-false-value?)
(define mdl-false-payload mdl-false-value-payload)

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
  (when (boolean? value)
    (error 'mdl-truthy? "host Boolean escaped into an MDL truth test: ~a" value))
  (not (mdl-false? value)))

(define (mdl-boolean value)
  (if value (mdl-atom "T") (mdl-false '())))

(define (mdl-type value)
  (cond [(mdl-false? value) (mdl-atom "FALSE")]
        [(symbol? value) (mdl-atom "ATOM")]
        [else (error 'mdl-type "TYPE currently supports FALSE and ATOM only: ~a" value)]))

(define builtin-table
  (hash "TYPE" mdl-type
        "+" +
        "-" -
        "*" *
        "/" /
        "MOD" modulo
        "L?" (lambda (a b) (mdl-boolean (< a b)))
        "L=?" (lambda (a b) (mdl-boolean (<= a b)))
        "G?" (lambda (a b) (mdl-boolean (> a b)))
        "G=?" (lambda (a b) (mdl-boolean (>= a b)))
        "=?" (lambda (a b) (mdl-boolean (equal? a b)))
        "==?" (lambda (a b) (mdl-boolean (eq? a b)))
        "N==?" (lambda (a b) (mdl-boolean (not (eq? a b))))
        "LENGTH" (lambda (v)
                    (cond [(string? v) (string-length v)]
                          [(vector? v) (vector-length v)]
                          [else (error 'mdl-length "unsupported type ~a" v)]))))

(define (mdl-apply name . args)
  (define fn (hash-ref builtin-table name #f))
  (apply (if fn fn (mdl-gval name)) args))
