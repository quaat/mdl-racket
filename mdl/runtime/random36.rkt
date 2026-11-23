#lang racket/base
;; Independent 36-bit two-word state transition for MDL RANDOM.
(provide make-random36-state random36-next! random36-state?
         random36-state-copy random36-state-words)

(struct random36-state ([first #:mutable] [second #:mutable]))

(define modulus (arithmetic-shift 1 36))
(define sign-bit (arithmetic-shift 1 35))
(define mask (sub1 modulus))

(define (word36 value)
  (bitwise-and value mask))

(define (signed36 value)
  (if (>= value sign-bit) (- value modulus) value))

(define (make-random36-state)
  ;; Fixed historical default state, checked by the pinned no-seed fixture.
  (random36-state #o267762113337 #o155256071112))

;; Host-only observation (ADR-0052): a detached copy, so a caller can
;; compute later outputs without consuming the session's sequence.
(define (random36-state-copy state)
  (random36-state (random36-state-first state) (random36-state-second state)))

;; The two unsigned 36-bit words, first then second.
(define (random36-state-words state)
  (list (random36-state-first state) (random36-state-second state)))

(define (random36-next! state [first-seed #f] [second-seed #f])
  (when first-seed
    (set-random36-state-first! state (word36 first-seed)))
  (when second-seed
    (set-random36-state-second! state (word36 second-seed)))
  (define first (random36-state-first state))
  (define second (random36-state-second state))
  ;; Work on unsigned words so host integer sign extension cannot escape
  ;; the 36-bit FIX range. This advances both words exactly once per call.
  (define next-first
    (word36 (bitwise-xor first
                         (arithmetic-shift second -1)
                         (arithmetic-shift (bitwise-and first 1) 35))))
  (set-random36-state-first! state next-first)
  (set-random36-state-second! state first)
  (signed36 next-first))
