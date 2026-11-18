#lang racket/base
;; Bootstrap MDL runtime: intentionally incomplete and NOT a gameplay engine.
(require racket/mpair racket/list)
(provide current-mdl-globals current-mdl-locals
         mdl-setg! mdl-gval mdl-define!
         mdl-set! mdl-lval mdl-with-bindings mdl-with-aux-bindings
         mdl-bind-function-formals
         mdl-with-function-scope mdl-with-prog-activation mdl-return mdl-again
         mdl-apply mdl-list mdl-list->list
         mdl-vector mdl-uvector mdl-rest mdl-nth mdl-put! mdl-putrest!
         mdl-word mdl-word? mdl-word-bits
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
(struct mdl-activation (owner escape [restart #:mutable] [live? #:mutable]))
(struct mdl-tuple-value (payload))
(define current-mdl-function-owner (make-parameter (gensym 'mdl-top-level)))
(define current-mdl-activations (make-parameter '()))
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

;; Function application for OPTIONAL, AUX, TUPLE, and ARGS formal sections.
;; Confusion's mdl_bind_args processes the formal list at call time in order:
;; required atoms, then OPTIONAL (with defaults evaluated in the growing
;; frame), then one ARGS or TUPLE rest binding, then AUX locals. An
;; unsupplied OPTIONAL or bare AUX binding stays unassigned, like a PROG
;; auxiliary. TUPLE wraps its arguments in a TUPLE-typed value; ARGS yields a
;; LIST. Error names follow the observed reference behavior.
(define (mdl-bind-function-formals fn required optional rest aux args thunk)
  (define frame (make-hasheq))
  (define (bind! atom value)
    (require-atom 'mdl-bind-function-formals atom)
    (when (hash-has-key? frame atom)
      (error 'mdl-bind-function-formals
             "BAD-ARGUMENT-LIST: duplicate formal argument"))
    (hash-set! frame atom value))
  (parameterize ([current-mdl-locals (cons frame (current-mdl-locals))])
    (define remaining args)
    (for ([atom (in-list required)])
      (when (null? remaining)
        (error 'mdl-bind-function-formals
               "TOO-FEW-ARGUMENTS-SUPPLIED for ~a" (mdl-atom-pname fn)))
      (bind! atom (car remaining))
      (set! remaining (cdr remaining)))
    (for ([spec (in-list optional)])
      (if (null? remaining)
          (bind! (car spec) (if (cdr spec) ((cdr spec)) unassigned))
          (begin
            (bind! (car spec) (car remaining))
            (set! remaining (cdr remaining)))))
    (cond
      [(null? remaining)
       ;; An absent rest binding is still bound, to an empty value.
       (when rest
         (bind! (cdr rest)
                (if (eq? (car rest) 'tuple)
                    (mdl-tuple-value '())
                    '())))]
      [(not rest)
       (error 'mdl-bind-function-formals
              "TOO-MANY-ARGUMENTS-SUPPLIED for ~a" (mdl-atom-pname fn))]
      [(eq? (car rest) 'tuple)
       (bind! (cdr rest) (mdl-tuple-value (apply mdl-list remaining)))]
      [else (bind! (cdr rest) (apply mdl-list remaining))])
    (for ([spec (in-list aux)])
      (bind! (car spec) (if (cdr spec) ((cdr spec)) unassigned)))
    (thunk)))

(define (mdl-with-aux-bindings specs thunk)
  (define frame (make-hasheq))
  (parameterize ([current-mdl-locals (cons frame (current-mdl-locals))])
    (for ([entry (in-list specs)])
      (define atom (binding-atom 'mdl-with-aux-bindings (car entry)))
      (when (hash-has-key? frame atom)
        (error 'mdl-with-aux-bindings "duplicate auxiliary binding"))
      ;; Evaluate before installing this binding. Earlier auxiliary bindings
      ;; are visible, while this initializer may still see an outer binding.
      (define initializer (cdr entry))
      (hash-set! frame atom (if initializer (initializer) unassigned)))
    (thunk)))

(define (mdl-with-function-scope thunk)
  (parameterize ([current-mdl-function-owner (gensym 'mdl-function)])
    (thunk)))

(define restart-token (gensym 'mdl-restart))

(define (mdl-with-prog-activation body [specs '()] [repeat? #f] [name #f])
  (let/ec escape
    (define frame (mdl-activation (current-mdl-function-owner) escape #f #t))
    (dynamic-wind
      void
      (lambda ()
        (parameterize ([current-mdl-activations
                        (cons frame (current-mdl-activations))])
          (define (run-body)
            (mdl-with-aux-bindings
             specs
             (lambda ()
               (let loop ()
                 (define result
                   (let/ec restart
                     (set-mdl-activation-restart! frame restart)
                     (body)))
                 (if (or repeat? (eq? result restart-token))
                     (loop)
                     result)))))
          (if name
              (mdl-with-bindings (list (cons name frame)) run-body)
              (run-body))))
      (lambda () (set-mdl-activation-live?! frame #f)))))

(define (current-mdl-activation)
  (for/first ([frame (in-list (current-mdl-activations))]
              #:when (eq? (mdl-activation-owner frame)
                          (current-mdl-function-owner)))
    frame))

(define implicit-activation (gensym 'mdl-implicit-activation))

(define (resolve-activation who supplied)
  (if (eq? supplied implicit-activation)
      (let ([target (current-mdl-activation)])
        (unless (and target (mdl-activation-live? target))
          (error who "no active PROG or REPEAT in current function"))
        target)
      (begin
        (unless (mdl-activation? supplied)
          (error who "expected ACTIVATION target"))
        (unless (and (mdl-activation-live? supplied)
                     (memq supplied (current-mdl-activations)))
          (error who "inactive ACTIVATION target"))
        supplied)))

(define (mdl-return value [supplied implicit-activation])
  (define target (resolve-activation 'mdl-return supplied))
  ((mdl-activation-escape target) value))

(define (mdl-again [supplied implicit-activation])
  (define target (resolve-activation 'mdl-again supplied))
  (unless (mdl-activation-restart target)
    (error 'mdl-again "ACTIVATION body restart is unavailable"))
  ((mdl-activation-restart target) restart-token))

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
                          ("WORD" . "WORD") ("BITS" . "WORD")
                          ("FRAME" . "FRAME")
                          ("TUPLE" . "TUPLE")
                          ("ACTIVATION" . "FRAME")))])
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
(struct mdl-word-value (bits))
(struct mdl-bits-value (width edge))

(define word-mask (sub1 (arithmetic-shift 1 36)))
(define fix-min (- (arithmetic-shift 1 35)))
(define fix-max (sub1 (arithmetic-shift 1 35)))

(define mdl-word? mdl-word-value?)
(define mdl-word-bits mdl-word-value-bits)
(define (mdl-word value)
  (unless (and (exact-integer? value) (<= fix-min value word-mask))
    (error 'mdl-word "expected a 36-bit word value"))
  (mdl-word-value (bitwise-and value word-mask)))

(define (word-bits-of value)
  (define base (mdl-base value))
  (cond [(mdl-word? base) (mdl-word-bits base)]
        [(and (exact-integer? base) (<= fix-min base fix-max))
         (bitwise-and base word-mask)]
        [else (error 'mdl-word "expected FIX or WORD data")]))

(define (word-signed bits)
  (if (bitwise-bit-set? bits 35)
      (- bits (arithmetic-shift 1 36))
      bits))

(define (check-fix who value)
  (unless (and (exact-integer? value) (<= fix-min value fix-max))
    (error who "FIX overflow"))
  value)

(define (check-number who value)
  (unless (and (real? value) (= value value))
    (error who "expected MDL FIX or FLOAT"))
  (when (exact-integer? value) (check-fix who value))
  value)

(define (arithmetic-step who op left right)
  (check-number who left)
  (check-number who right)
  (if (and (exact-integer? left) (exact-integer? right))
      (check-fix who
                 (if (eq? who 'mdl-div)
                     (begin
                       (when (zero? right) (error who "division by zero"))
                       (quotient left right))
                     (op left right)))
      (let ([a (exact->inexact left)] [b (exact->inexact right)])
        (when (and (eq? who 'mdl-div) (zero? b))
          (error who "division by zero"))
        (define result (op a b))
        (when (or (eqv? result +inf.0) (eqv? result -inf.0)
                  (not (= result result)))
          (error who "FLOAT overflow"))
        result)))

(define (mdl-add . values)
  (for/fold ([acc 0]) ([value (in-list values)])
    (arithmetic-step 'mdl-add + acc value)))

(define (mdl-sub . values)
  (cond [(null? values) 0]
        [(null? (cdr values)) (arithmetic-step 'mdl-sub - 0 (car values))]
        [else (for/fold ([acc (check-number 'mdl-sub (car values))])
                        ([value (in-list (cdr values))])
                (arithmetic-step 'mdl-sub - acc value))]))

(define (mdl-mul . values)
  (for/fold ([acc 1]) ([value (in-list values)])
    (arithmetic-step 'mdl-mul * acc value)))

(define (mdl-div . values)
  (cond [(null? values) 1]
        [(null? (cdr values)) (arithmetic-step 'mdl-div / 1 (car values))]
        [else (for/fold ([acc (check-number 'mdl-div (car values))])
                        ([value (in-list (cdr values))])
                (arithmetic-step 'mdl-div / acc value))]))

(define (mdl-mod left right)
  (check-fix 'mdl-mod left)
  (check-fix 'mdl-mod right)
  (when (zero? right) (error 'mdl-mod "division by zero"))
  (modulo left right))

(define (mdl-fix value)
  (check-number 'mdl-fix value)
  (check-fix 'mdl-fix (inexact->exact (truncate value))))

(define (mdl-float value)
  (check-number 'mdl-float value)
  (exact->inexact value))

(define (mdl-bits width [edge 0])
  (unless (and (exact-integer? width) (exact-integer? edge)
               (<= 0 width 36) (<= 0 edge 35) (<= (+ width edge) 36))
    (error 'mdl-bits "BITS range outside 36-bit WORD"))
  (mdl-bits-value width edge))

(define (bits-mask bits)
  (unless (mdl-bits-value? bits) (error 'mdl-bits "expected BITS value"))
  (sub1 (arithmetic-shift 1 (mdl-bits-value-width bits))))

(define (mdl-getbits from bits)
  (mdl-word (bitwise-and (arithmetic-shift (word-bits-of from)
                                          (- (mdl-bits-value-edge bits)))
                         (bits-mask bits))))

(define (mdl-putbits to bits [from 0])
  (define mask (arithmetic-shift (bits-mask bits) (mdl-bits-value-edge bits)))
  (mdl-word (bitwise-and word-mask
                         (bitwise-ior (bitwise-and (word-bits-of to)
                                                   (bitwise-not mask))
                                      (arithmetic-shift
                                       (bitwise-and (word-bits-of from)
                                                    (bits-mask bits))
                                       (mdl-bits-value-edge bits))))))

(define (word-fold op identity values)
  (mdl-word (bitwise-and word-mask
                         (for/fold ([acc identity]) ([value (in-list values)])
                           (op acc (word-bits-of value))))))

(define (mdl-andb . values) (word-fold bitwise-and word-mask values))
(define (mdl-orb . values) (word-fold bitwise-ior 0 values))
(define (mdl-xorb . values) (word-fold bitwise-xor 0 values))
(define (mdl-eqvb . values)
  (word-fold (lambda (a b) (bitwise-not (bitwise-xor a b)))
             word-mask values))

(define (mdl-lsh value amount)
  (check-fix 'mdl-lsh amount)
  (mdl-word (bitwise-and word-mask
                         (arithmetic-shift (word-bits-of value)
                                           (remainder amount 256)))))

(define (mdl-base value)
  (if (mdl-typed-value? value) (mdl-typed-value-value value) value))

(define (mdl-type-name value)
  (cond [(mdl-typed-value? value) (mdl-atom-pname (mdl-typed-value-type value))]
        [(mdl-activation? value) "ACTIVATION"]
        [(mdl-word? value) "WORD"]
        [(mdl-bits-value? value) "BITS"]
        [(mdl-false? value) "FALSE"]
        [(mdl-tuple-value? value) "TUPLE"]
        [(mdl-atom? value) "ATOM"]
        [(mdl-oblist? value) "OBLIST"]
        [(or (null? value) (mpair? value)) "LIST"]
        [(mdl-array? value) (symbol->string (mdl-array-kind value))]
        [(exact-integer? value) (check-fix 'mdl-type value) "FIX"]
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
        [(mdl-tuple-value? value) (mdl-tuple-value-payload value)]
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
  (cond
    ;; REST of a TUPLE keeps the TUPLE type in the reference.
    [(mdl-tuple-value? value)
     (if (zero? offset)
         value
         (mdl-tuple-value
          (mdl-list-tail (mdl-tuple-value-payload value) offset 'mdl-rest)))]
    [else
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
         (mdl-list-tail (mdl-list-head value 'mdl-rest) offset 'mdl-rest))]))

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

;; PUTREST rewires the tail of a LIST-primtype head. A TUPLE is its own
;; primitive type, so tuples must not expose or splice their payload
;; chains here; the primtype check also rejects typed values whose storage
;; is a tuple, as well as non-LIST operands.
(define (mdl-putrest! head tail)
  (define (require-list-primtype value)
    (define prim (mdl-primtype value))
    (unless (eq? prim (mdl-atom "LIST"))
      (error 'mdl-putrest "PUTREST requires LIST-primtype values, not ~a"
             (mdl-atom-pname prim))))
  (require-list-primtype head)
  (require-list-primtype tail)
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
        [(and (mdl-word? left) (mdl-word? right))
         (= (mdl-word-bits left) (mdl-word-bits right))]
        [(and (mdl-bits-value? left) (mdl-bits-value? right))
         (and (= (mdl-bits-value-width left) (mdl-bits-value-width right))
              (= (mdl-bits-value-edge left) (mdl-bits-value-edge right)))]
        [(and (number? left) (number? right)) (eqv? left right)]
        [(and (mdl-false? left) (mdl-false? right))
         (eq? (mdl-false-value-payload left) (mdl-false-value-payload right))]
        [(and (mdl-array? left) (mdl-array? right))
      (and (eq? (mdl-array-kind left) (mdl-array-kind right))
           (eq? (mdl-array-storage left) (mdl-array-storage right))
           (= (mdl-array-start left) (mdl-array-start right))
           (= (mdl-array-length left) (mdl-array-length right)))]
        [else (eq? left right)]))

(define (mdl-equal? left right)
  (define active (make-hasheq))
  (define (compare-structured a b thunk)
    (define rights
      (hash-ref active a
                (lambda ()
                  (define fresh (make-hasheq))
                  (hash-set! active a fresh)
                  fresh)))
    (when (hash-has-key? rights b)
      (error 'mdl-equal? "unsupported cyclic structural equality"))
    (hash-set! rights b #t)
    (dynamic-wind void thunk (lambda () (hash-remove! rights b))))
  (define (loop a b)
    (cond [(mdl-identical? a b) #t]
          [(and (mdl-typed-value? a) (mdl-typed-value? b))
           (and (eq? (mdl-typed-value-type a) (mdl-typed-value-type b))
                (compare-structured a b
                  (lambda () (loop (mdl-base a) (mdl-base b)))))]
          [(or (mdl-typed-value? a) (mdl-typed-value? b)) #f]
          [(and (mdl-word? a) (mdl-word? b))
           (= (mdl-word-bits a) (mdl-word-bits b))]
          [(and (mdl-bits-value? a) (mdl-bits-value? b))
           (mdl-identical? a b)]
          [(and (mdl-array? a) (mdl-array? b))
           (and (eq? (mdl-array-kind a) (mdl-array-kind b))
                (= (mdl-array-length a) (mdl-array-length b))
                (compare-structured a b
                  (lambda ()
                    (for/and ([i (in-range (mdl-array-length a))])
                      (loop (mdl-nth a (add1 i))
                            (mdl-nth b (add1 i)))))))]
          [(and (mdl-false? a) (mdl-false? b))
           (compare-structured a b
             (lambda ()
               (loop (mdl-false-value-payload a)
                     (mdl-false-value-payload b))))]
          [(and (mdl-tuple-value? a) (mdl-tuple-value? b))
           (compare-structured a b
             (lambda ()
               (loop (mdl-tuple-value-payload a)
                     (mdl-tuple-value-payload b))))]
          [(or (mdl-tuple-value? a) (mdl-tuple-value? b)) #f]
          [(and (mpair? a) (mpair? b))
           (compare-structured a b
             (lambda ()
               (and (loop (mcar a) (mcar b))
                    (loop (mcdr a) (mcdr b)))))]
          [else (equal? a b)]))
  (loop left right))

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
                   (not (member target '("LIST" "FALSE" "VECTOR" "UVECTOR"
                                         "FIX" "WORD"))))
          (error 'mdl-chtype "unsupported built-in TYPE conversion"))
        (when (and (not (or (null? base) (mpair? base)
                            (mdl-false? base) (mdl-array? base)))
                   (not (string=? (mdl-atom-pname desired-prim) "WORD")))
          (error 'mdl-chtype "unsupported primitive storage conversion"))
        (cond [(string=? (mdl-atom-pname desired-prim) "WORD")
               (cond [(string=? target "FIX")
                      (word-signed (word-bits-of base))]
                     [(string=? target "WORD")
                      (mdl-word (word-bits-of base))]
                     [(or (exact-integer? base) (mdl-word? base))
                      (mdl-typed-value type (mdl-word (word-bits-of base)))]
                     [else (error 'mdl-chtype "unsupported WORD reinterpretation")])]
              [(string=? target "LIST")
               (mdl-list-head base 'mdl-chtype)]
              [(string=? target "FALSE")
               (mdl-false (mdl-list-head base 'mdl-chtype))]
              [(or (string=? target "VECTOR") (string=? target "UVECTOR"))
               base]
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
        "FIX" mdl-fix
        "FLOAT" mdl-float
        "BITS" mdl-bits
        "GETBITS" mdl-getbits
        "PUTBITS" mdl-putbits
        "ANDB" mdl-andb
        "ORB" mdl-orb
        "XORB" mdl-xorb
        "EQVB" mdl-eqvb
        "LSH" mdl-lsh
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
        "+" mdl-add
        "-" mdl-sub
        "*" mdl-mul
        "/" mdl-div
        "MOD" mdl-mod
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

(module+ test
  (require rackunit)
  (define leaked #f)
  (check-equal?
   (mdl-with-prog-activation
    (lambda ()
      (set! leaked (car (current-mdl-activations)))
      (mdl-return 17)
      99))
   17)
  (check-false (mdl-activation-live? leaked))
  (check-equal? (current-mdl-activations) '())
  (check-exn #rx"no active PROG"
             (lambda ()
               (parameterize ([current-mdl-activations (list leaked)])
                 (mdl-return 19))))
  (check-exn #rx"no active PROG or REPEAT"
             (lambda ()
               (parameterize ([current-mdl-activations (list leaked)])
                 (mdl-again))))
  (define abandoned #f)
  (check-exn #rx"intentional failure"
             (lambda ()
               (mdl-with-prog-activation
                (lambda ()
                  (set! abandoned (car (current-mdl-activations)))
                  (error 'test "intentional failure")))))
  (check-false (mdl-activation-live? abandoned))
  (check-equal? (current-mdl-activations) '())
  (check-equal?
   (mdl-with-prog-activation
    (lambda ()
      (check-exn #rx"no active PROG"
                 (lambda ()
                   (mdl-with-function-scope (lambda () (mdl-return 7)))))
      (mdl-return 8)))
   8)
  (check-equal?
   (mdl-with-prog-activation
    (lambda ()
      (define outer (car (current-mdl-activations)))
      (define inner
        (mdl-with-prog-activation
         (lambda ()
           (define current (car (current-mdl-activations)))
           (check-false (eq? current outer))
           (check-eq? (cadr (current-mdl-activations)) outer)
           current)))
      (check-false (mdl-activation-live? inner))
      (check-true (mdl-activation-live? outer))
      (mdl-return 23)))
   23)
  ;; Function-formal binder invariants.
  (define binder-atom (mdl-atom "M2-BINDER-CHECK"))
  (check-equal?
   (mdl-bind-function-formals
    binder-atom
    (list (mdl-atom "A"))
    (list (cons (mdl-atom "B") #f))
    #f
    (list (cons (mdl-atom "C") (lambda () (mdl-lval (mdl-atom "A")))))
    '(7)
    (lambda () (mdl-lval (mdl-atom "A"))))
   7)
  (check-equal? (length (current-mdl-locals)) 1)
  (check-exn #rx"TOO-FEW-ARGUMENTS-SUPPLIED"
             (lambda ()
               (mdl-bind-function-formals
                binder-atom (list (mdl-atom "A")) '() #f '() '() void)))
  (check-exn #rx"TOO-MANY-ARGUMENTS-SUPPLIED"
             (lambda ()
               (mdl-bind-function-formals
                binder-atom '() '() #f '() '(1) void)))
  (define tuple-check
    (mdl-bind-function-formals
     binder-atom '() '() (cons 'tuple (mdl-atom "T")) '() '(1 2 3)
     (lambda () (mdl-lval (mdl-atom "T")))))
  (check-equal? (mdl-atom-pname (mdl-type tuple-check)) "TUPLE")
  (check-equal? (mdl-atom-pname (mdl-primtype tuple-check)) "TUPLE")
  (check-equal? (mdl-length (mdl-rest tuple-check)) 2)
  (check-equal? (mdl-atom-pname (mdl-type (mdl-rest tuple-check))) "TUPLE")
  (check-true (mdl-equal? tuple-check
                          (mdl-tuple-value (mdl-list 1 2 3))))
  (check-false (mdl-equal? tuple-check (mdl-list 1 2 3))))
