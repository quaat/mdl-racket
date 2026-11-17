#lang racket/base
;; Bootstrap MDL runtime: intentionally incomplete and NOT a gameplay engine.
(require racket/mpair racket/list)
(provide current-mdl-globals current-mdl-locals mdl-setg! mdl-gval mdl-define!
         mdl-set! mdl-lval mdl-with-bindings mdl-apply mdl-list
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

(define current-mdl-globals (make-parameter (make-hasheq)))
(define current-mdl-locals (make-parameter (list (make-hasheq))))
(define unassigned (gensym 'mdl-unassigned))

(define (binding-atom who value)
  (cond [(mdl-atom? value) value]
        [(string? value) (mdl-atom value)]
        [else (error who "expected an MDL ATOM")]))

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

(define (global-option atom)
  (define globals (current-mdl-globals))
  (cond [(hash-has-key? globals atom) (hash-ref globals atom)]
        [(eq? atom (mdl-atom (mdl-atom-pname atom)))
         (hash-ref builtin-table (mdl-atom-pname atom) unassigned)]
        [else unassigned]))

(define (mdl-setg! name value)
  (hash-set! (current-mdl-globals) (binding-atom 'mdl-setg name) value)
  value)

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

(define (mdl-define! name fn)
  (mdl-setg! name fn))

(struct atom-value (pname [oblist #:mutable]))
(struct oblist-value (name entries size))
(struct atom-space (initial root named types builtins))

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
  (for ([entry (in-list '(("ATOM" . "ATOM") ("OBLIST" . "UVECTOR")
                          ("LIST" . "LIST") ("FORM" . "LIST")
                          ("FALSE" . "LIST") ("VECTOR" . "VECTOR")
                          ("UVECTOR" . "UVECTOR") ("STRING" . "STRING")
                          ("FIX" . "WORD") ("FLOAT" . "WORD")
                          ("WORD" . "WORD")))])
    (define type-atom (atom-value (car entry) initial))
    (hash-set! (oblist-value-entries initial) (car entry) type-atom)
    (hash-set! types type-atom (cdr entry))
    (hash-set! builtins type-atom #t))
  (atom-space initial root named types builtins))

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
(struct mdl-typed-value (type value))

(define (mdl-base value)
  (if (mdl-typed-value? value) (mdl-typed-value-value value) value))

(define (mdl-type-name value)
  (cond [(mdl-typed-value? value) (mdl-atom-pname (mdl-typed-value-type value))]
        [(mdl-false? value) "FALSE"]
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
  (define element-type (and (pair? values) (mdl-type (car values))))
  (for ([value (in-list values)])
    (when (or (string=? (mdl-type-name value) "STRING")
              (not (eq? (mdl-type value) element-type)))
      (error 'mdl-uvector "UVECTOR elements must have one permitted TYPE")))
  (mdl-array 'UVECTOR (list->vector values) 0 (length values) element-type))

(define (mdl-list-head value who)
  (cond [(mdl-typed-value? value) (mdl-list-head (mdl-base value) who)]
        [(mdl-false? value) (mdl-false-value-payload value)]
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
        [(string? value) (string-length value)]
        [else (length (mdl-list->list (mdl-list-head value 'mdl-length)))]))

(define (mdl-rest value [offset 1])
  (unless (and (exact-integer? offset) (>= offset 0))
    (error 'mdl-rest "offset out of range"))
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
      (mdl-list-tail (mdl-list-head value 'mdl-rest) offset 'mdl-rest)))

(define (mdl-check-index who value index)
  (unless (and (exact-integer? index) (<= 1 index) (<= index (mdl-length value)))
    (error who "index out of range")))

(define (mdl-nth value [index 1])
  (mdl-check-index 'mdl-nth value index)
  (define base (mdl-base value))
  (if (mdl-array? base)
      (vector-ref (mdl-array-storage base) (+ (mdl-array-start base) (sub1 index)))
      (mcar (mdl-list-tail (mdl-list-head value 'mdl-nth) (sub1 index) 'mdl-nth))))

(define (mdl-put! value index item)
  (mdl-check-index 'mdl-put value index)
  (define base (mdl-base value))
  (if (mdl-array? base)
      (begin
        (when (and (eq? (mdl-array-kind base) 'UVECTOR)
                   (not (eq? (mdl-type item)
                             (mdl-array-element-type base))))
          (error 'mdl-put "UVECTOR PUT type violation"))
        (vector-set! (mdl-array-storage base)
                     (+ (mdl-array-start base) (sub1 index)) item))
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
  (cond [(and (mdl-typed-value? left) (mdl-typed-value? right))
         (and (eq? (mdl-typed-value-type left) (mdl-typed-value-type right))
              (mdl-identical? (mdl-base left) (mdl-base right)))]
        [(or (mdl-typed-value? left) (mdl-typed-value? right)) #f]
        [(and (mdl-false? left) (mdl-false? right))
         (eq? (mdl-false-value-payload left) (mdl-false-value-payload right))]
        [(and (mdl-array? left) (mdl-array? right))
      (and (eq? (mdl-array-kind left) (mdl-array-kind right))
           (eq? (mdl-array-storage left) (mdl-array-storage right))
           (= (mdl-array-start left) (mdl-array-start right))
           (= (mdl-array-length left) (mdl-array-length right)))]
        [else (eq? left right)]))

(define (mdl-equal? left right)
  (cond [(and (mdl-typed-value? left) (mdl-typed-value? right))
         (and (eq? (mdl-typed-value-type left) (mdl-typed-value-type right))
              (mdl-equal? (mdl-base left) (mdl-base right)))]
        [(or (mdl-typed-value? left) (mdl-typed-value? right)) #f]
        [(and (mdl-array? left) (mdl-array? right))
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

(define (mdl-newtype name base-type)
  (require-atom 'mdl-newtype name)
  (define prim (mdl-typeprim base-type))
  (define types (atom-space-types (current-mdl-atom-space)))
  (when (hash-has-key? types name)
    (error 'mdl-newtype "MDL TYPE already exists: ~a" (mdl-atom-pname name)))
  (hash-set! types name (mdl-atom-pname prim))
  name)

(define (mdl-chtype value type)
  (require-atom 'mdl-chtype type)
  (define desired-prim (mdl-typeprim type))
  (unless (eq? (mdl-primtype value) desired-prim)
    (error 'mdl-chtype "primitive type mismatch"))
  (if (eq? (mdl-type value) type)
      value
      (let ([base (mdl-base value)] [target (mdl-atom-pname type)])
        (when (and (hash-has-key? (atom-space-builtins (current-mdl-atom-space)) type)
                   (not (member target '("LIST" "FALSE" "VECTOR" "UVECTOR"))))
          (error 'mdl-chtype "unsupported built-in TYPE conversion"))
        (when (and (not (or (null? base) (mpair? base)
                            (mdl-false? base) (mdl-array? base)))
                   (not (string=? (mdl-atom-pname desired-prim) "WORD")))
          (error 'mdl-chtype "unsupported primitive storage conversion"))
        (cond [(string=? target "LIST")
               (mdl-list-head base 'mdl-chtype)]
              [(string=? target "FALSE")
               (mdl-false (mdl-list-head base 'mdl-chtype))]
              [(or (string=? target "VECTOR") (string=? target "UVECTOR"))
               base]
              [(string=? (mdl-atom-pname desired-prim) "WORD")
               (error 'mdl-chtype "unsupported WORD reinterpretation")]
              [(member (mdl-atom-pname desired-prim) '("LIST" "VECTOR" "UVECTOR"))
               (mdl-typed-value type base)]
              [else (error 'mdl-chtype "unsupported primitive type conversion")]))))

(define (mdl-utype value)
  (define base (mdl-base value))
  (unless (and (mdl-array? base) (eq? (mdl-array-kind base) 'UVECTOR))
    (error 'mdl-utype "UTYPE requires UVECTOR"))
  (if (mdl-array-element-type base)
      (mdl-array-element-type base)
      (mdl-false '())))

(define builtin-table
  (hash "TYPE" mdl-type
        "LVAL" mdl-lval
        "GVAL" mdl-gval
        "VALUE" mdl-value
        "SET" mdl-set!
        "SETG" mdl-setg!
        "GUNASSIGN" mdl-gunassign!
        "PRIMTYPE" mdl-primtype
        "TYPEPRIM" mdl-typeprim
        "NEWTYPE" mdl-newtype
        "CHTYPE" mdl-chtype
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
  (define atom (binding-atom 'mdl-apply name))
  (define global (global-option atom))
  (define fn (if (eq? global unassigned) (local-option atom) global))
  (unless (procedure? fn)
    (error 'mdl-apply "unassigned or non-applicable MDL operator ~a"
           (mdl-atom-pname atom)))
  (apply fn args))
