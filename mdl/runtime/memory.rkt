#lang racket/base
;; Session-local logical movable-storage ledger. Entries never retain values.
(provide make-mdl-memory mdl-memory? mdl-memory-capacity mdl-memory-used
         set-mdl-memory-capacity! mdl-memory-register! mdl-memory-collect!
         mdl-memory-free mdl-memory-bloat!)

(struct allocation (reference words))
(struct mdl-memory ([entries #:mutable] [capacity #:mutable] [used #:mutable]))

(define (make-mdl-memory [capacity 262144])
  (mdl-memory '() capacity 0))

(define (mdl-memory-free memory)
  (- (mdl-memory-capacity memory) (mdl-memory-used memory)))

(define (mdl-memory-register! memory value words)
  (unless (and (exact-integer? words) (positive? words))
    (error 'mdl-memory-register! "expected positive logical word count"))
  (set-mdl-memory-entries! memory
                           (cons (allocation (make-weak-box value) words)
                                 (mdl-memory-entries memory)))
  (set-mdl-memory-used! memory (+ (mdl-memory-used memory) words))
  value)

(define (mdl-memory-collect! memory)
  (define started (current-inexact-milliseconds))
  (collect-garbage 'major)
  (define elapsed (max 0.0 (/ (- (current-inexact-milliseconds) started) 1000.0)))
  (define reclaimed 0)
  (define survivors
    (for/list ([entry (in-list (mdl-memory-entries memory))]
               #:when (let ([alive? (weak-box-value (allocation-reference entry))])
                        (unless alive?
                          (set! reclaimed (+ reclaimed (allocation-words entry))))
                        alive?))
      entry))
  (set-mdl-memory-entries! memory survivors)
  (set-mdl-memory-used! memory (- (mdl-memory-used memory) reclaimed))
  (values reclaimed elapsed))

(define (mdl-memory-bloat! memory free-words)
  (unless (and (exact-integer? free-words) (>= free-words 0))
    (error 'mdl-memory-bloat! "expected nonnegative FIX"))
  (when (< (mdl-memory-free memory) free-words)
    (set-mdl-memory-capacity! memory (+ (mdl-memory-used memory) free-words)))
  (mdl-memory-free memory))
