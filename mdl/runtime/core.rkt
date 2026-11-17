#lang racket/base
;; Bootstrap MDL runtime: intentionally incomplete and NOT a gameplay engine.
(require racket/mpair racket/list)
(provide current-mdl-globals mdl-setg! mdl-gval mdl-define! mdl-apply mdl-list
         mdl-truthy? mdl-atom mdl-atom? mdl-atom-pname mdl-oblist?
         current-mdl-atom-space make-mdl-atom-space
         mdl-false mdl-false? mdl-false-payload)

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

(struct atom-value (pname [oblist #:mutable]))
(struct oblist-value (name entries size))
(struct atom-space (initial root named))

(define mdl-atom? atom-value?)
(define mdl-atom-pname atom-value-pname)
(define mdl-oblist? oblist-value?)

(define (make-mdl-atom-space)
  (define named (make-hasheq))
  (define root (oblist-value #f (make-hash) 151))
  (define root-name (atom-value "ROOT" root))
  (hash-set! (oblist-value-entries root) "ROOT" root-name)
  (hash-set! named root-name root)
  (define initial-name (atom-value "INITIAL" root))
  (hash-set! (oblist-value-entries root) "INITIAL" initial-name)
  (define initial (oblist-value initial-name (make-hash) 151))
  (hash-set! named initial-name initial)
  (atom-space initial root named))

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

(define (mdl-truthy? value)
  (when (boolean? value)
    (error 'mdl-truthy? "host Boolean escaped into an MDL truth test: ~a" value))
  (not (mdl-false? value)))

(define (mdl-boolean value)
  (if value (mdl-atom "T") (mdl-false '())))

(define (mdl-type value)
  (cond [(mdl-false? value) (mdl-atom "FALSE")]
        [(mdl-atom? value) (mdl-atom "ATOM")]
        [(mdl-oblist? value) (mdl-atom "OBLIST")]
        [else (error 'mdl-type "TYPE currently supports FALSE, ATOM, and OBLIST only: ~a" value)]))

(define builtin-table
  (hash "TYPE" mdl-type
        "ATOM" (lambda (name)
                 (unless (string? name) (error 'mdl-atom "expected a STRING PNAME"))
                 (atom-value name #f))
        "MOBLIST" mdl-moblist
        "LOOKUP" mdl-lookup
        "INSERT" mdl-insert
        "REMOVE" mdl-remove
        "OBLIST?" mdl-oblist-of
        "PNAME" mdl-pname
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
