#lang racket/base
;; Bootstrap MDL runtime: intentionally incomplete and NOT a gameplay engine.
(require racket/mpair racket/list)
(provide current-mdl-globals mdl-setg! mdl-gval mdl-define! mdl-apply mdl-list
         mdl-vector mdl-uvector mdl-rest mdl-nth mdl-put! mdl-putrest!
         mdl-truthy? mdl-atom mdl-atom? mdl-atom-pname mdl-oblist?
         current-mdl-atom-space make-mdl-atom-space
         mdl-false mdl-false? mdl-false-payload)

(struct mdl-false-value (payload) #:transparent)
(define empty-mdl-false (mdl-false-value '()))
(define (mdl-false payload)
  (define list-payload (mdl-normalize-list payload))
  (if (null? list-payload) empty-mdl-false (mdl-false-value list-payload)))
(define mdl-false? mdl-false-value?)
(define (mdl-false-payload value)
  (unless (mdl-false? value) (error 'mdl-false-payload "expected FALSE"))
  (mdl-list->list (mdl-false-value-payload value)))

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

(define (mdl-type-name value)
  (cond [(mdl-false? value) "FALSE"]
        [(mdl-atom? value) "ATOM"]
        [(mdl-oblist? value) "OBLIST"]
        [(or (null? value) (mpair? value)) "LIST"]
        [(mdl-array? value) (symbol->string (mdl-array-kind value))]
        [(exact-integer? value) "FIX"]
        [(and (real? value) (inexact? value)) "FLOAT"]
        [(string? value) "STRING"]
        [else (error 'mdl-type "unsupported MDL type ~a" value)]))

(define (mdl-vector . values)
  (mdl-array 'VECTOR (list->vector values) 0 (length values) #f))

(define (mdl-uvector . values)
  (define element-type (and (pair? values) (mdl-type-name (car values))))
  (for ([value (in-list values)])
    (when (or (string=? (mdl-type-name value) "STRING")
              (not (string=? (mdl-type-name value) element-type)))
      (error 'mdl-uvector "UVECTOR elements must have one permitted TYPE")))
  (mdl-array 'UVECTOR (list->vector values) 0 (length values) element-type))

(define (mdl-list-head value who)
  (cond [(mdl-false? value) (mdl-false-value-payload value)]
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
  (cond [(mdl-array? value) (mdl-array-length value)]
        [(string? value) (string-length value)]
        [else (length (mdl-list->list (mdl-list-head value 'mdl-length)))]))

(define (mdl-rest value [offset 1])
  (unless (and (exact-integer? offset) (>= offset 0))
    (error 'mdl-rest "offset out of range"))
  (if (mdl-array? value)
      (begin
        (when (> offset (mdl-array-length value))
          (error 'mdl-rest "offset out of range"))
        (if (zero? offset) value
            (mdl-array (mdl-array-kind value) (mdl-array-storage value)
                       (+ (mdl-array-start value) offset)
                       (- (mdl-array-length value) offset)
                       (mdl-array-element-type value))))
      (mdl-list-tail (mdl-list-head value 'mdl-rest) offset 'mdl-rest)))

(define (mdl-check-index who value index)
  (unless (and (exact-integer? index) (<= 1 index) (<= index (mdl-length value)))
    (error who "index out of range")))

(define (mdl-nth value [index 1])
  (mdl-check-index 'mdl-nth value index)
  (if (mdl-array? value)
      (vector-ref (mdl-array-storage value) (+ (mdl-array-start value) (sub1 index)))
      (mcar (mdl-list-tail (mdl-list-head value 'mdl-nth) (sub1 index) 'mdl-nth))))

(define (mdl-put! value index item)
  (mdl-check-index 'mdl-put value index)
  (if (mdl-array? value)
      (begin
        (when (and (eq? (mdl-array-kind value) 'UVECTOR)
                   (not (string=? (mdl-type-name item)
                                  (mdl-array-element-type value))))
          (error 'mdl-put "UVECTOR PUT type violation"))
        (vector-set! (mdl-array-storage value)
                     (+ (mdl-array-start value) (sub1 index)) item))
      (set-mcar! (mdl-list-tail (mdl-list-head value 'mdl-put)
                                 (sub1 index) 'mdl-put) item))
  value)

(define (mdl-putrest! head tail)
  (define head-list (mdl-list-head head 'mdl-putrest))
  (unless (mpair? head-list)
    (error 'mdl-putrest "PUTREST requires nonempty LIST-primtype head"))
  (set-mcdr! head-list (mdl-list-head tail 'mdl-putrest))
  head)

(define (mdl-identical? left right)
  (if (and (mdl-array? left) (mdl-array? right))
      (and (eq? (mdl-array-kind left) (mdl-array-kind right))
           (eq? (mdl-array-storage left) (mdl-array-storage right))
           (= (mdl-array-start left) (mdl-array-start right))
           (= (mdl-array-length left) (mdl-array-length right)))
      (eq? left right)))

(define (mdl-equal? left right)
  (cond [(and (mdl-array? left) (mdl-array? right))
         (and (eq? (mdl-array-kind left) (mdl-array-kind right))
              (= (mdl-array-length left) (mdl-array-length right))
              (for/and ([i (in-range (mdl-array-length left))])
                (mdl-equal? (mdl-nth left (add1 i))
                            (mdl-nth right (add1 i)))))]
        [(and (mdl-false? left) (mdl-false? right))
         (mdl-equal? (mdl-false-value-payload left)
                     (mdl-false-value-payload right))]
        [(and (mpair? left) (mpair? right))
         (and (mdl-equal? (mcar left) (mcar right))
              (mdl-equal? (mcdr left) (mcdr right)))]
        [else (equal? left right)]))

(define (mdl-truthy? value)
  (when (boolean? value)
    (error 'mdl-truthy? "host Boolean escaped into an MDL truth test: ~a" value))
  (not (mdl-false? value)))

(define (mdl-boolean value)
  (if value (mdl-atom "T") (mdl-false '())))

(define (mdl-type value)
  (mdl-atom (mdl-type-name value)))

(define (mdl-utype value)
  (unless (and (mdl-array? value) (eq? (mdl-array-kind value) 'UVECTOR))
    (error 'mdl-utype "UTYPE requires UVECTOR"))
  (if (mdl-array-element-type value)
      (mdl-atom (mdl-array-element-type value))
      (mdl-false '())))

(define builtin-table
  (hash "TYPE" mdl-type
        "UTYPE" mdl-utype
        "LIST" mdl-list
        "VECTOR" mdl-vector
        "UVECTOR" mdl-uvector
        "LENGTH" mdl-length
        "REST" mdl-rest
        "NTH" mdl-nth
        "PUT" mdl-put!
        "PUTREST" mdl-putrest!
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
        "=?" (lambda (a b) (mdl-boolean (mdl-equal? a b)))
        "==?" (lambda (a b) (mdl-boolean (mdl-identical? a b)))
        "N==?" (lambda (a b) (mdl-boolean (not (mdl-identical? a b))))))

(define (mdl-apply name . args)
  (define fn (hash-ref builtin-table name #f))
  (apply (if fn fn (mdl-gval name)) args))
