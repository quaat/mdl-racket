#lang racket/base
;; Tests for the logical movable-storage GC ledger.
;; R10: assertions replaced with optimizer-liveness-independent invariants:
;;   - reclaimed >= N (lower bound on expected freed words)
;;   - used = initial after all allocated objects gone
;;   - used + free = capacity (always)
;;   - retained objects never reclaimed (structural checks)
;;   - cycles collectable
;;   - session isolation
;; Mutation sensitivity: breaking the sweep (always reporting alive) makes
;; reclaimed = 0 and final-used > initial, failing the >= and = checks.
;; Breaking set-mdl-memory-used! makes invariant used+free=capacity fail.
(require rackunit racket/mpair "../mdl/runtime/core.rkt")

;; Helper: check the fundamental ledger invariant.
(define (check-invariant! [label ""])
  (define s (mdl-logical-storage-stats))
  (check-equal? (+ (hash-ref s 'used) (hash-ref s 'free))
                (hash-ref s 'capacity)
                (string-append "used+free=capacity invariant" label))
  (check-true (>= (hash-ref s 'used) 0)
              (string-append "used >= 0" label)))

(define (session thunk)
  (parameterize ([current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (thunk)))

;; --- Basic GC event interface ---
(session
 (lambda ()
   (define header (mdl-apply "EVENT" "GC" 11))
   (define observed '())
   (mdl-apply "HANDLER" header
              (lambda (elapsed reason operation)
                (set! observed (cons (list elapsed reason operation) observed))))
   (define live (mdl-list 1 2))
   (check-equal? (mdl-apply "GC") 0)
   (check-equal? (length observed) 1)
   (check-true (and (real? (caar observed)) (inexact? (caar observed))
                    (>= (caar observed) 0.0)))
   (check-equal? (cadar observed) 1)
   (check-eq? (caddar observed) (mdl-atom "GC"))
   (check-equal? (mdl-list->list live) '(1 2))
   (check-exn #rx"GC|argument" (lambda () (mdl-apply "GC" "BAD")))
   (check-equal? (length observed) 1)
   (check-true (exact-integer? (mdl-apply "BLOAT" 200)))
   (check-exn #rx"BLOAT|FIX" (lambda () (mdl-apply "BLOAT" -1)))
   (check-invariant!)))

;; --- REST shares backing storage; head cell is reclaimed when only tail is retained ---
;; R10: Wrap shared in a nested function so its frame is gone before GC.
;; This avoids dependence on whether BC or CS kills a binding after last use.
;; Mutation sensitivity: if the sweep never frees entries, reclaimed = 0 → (>= 2) fails;
;; if retained objects are incorrectly freed, structural checks below fail.
(define (make-shared-and-return-tail)
  ;; shared goes out of scope when this function returns.
  (define shared (mdl-list 1 2 3))
  (define tail (mcdr shared))
  ;; Verify REST returns the same mcons as mcdr.
  (check-eq? (mdl-apply "REST" shared) tail)
  tail)

(session
 (lambda ()
   (define before (mdl-logical-storage-stats))
   (define tail (make-shared-and-return-tail))
   (check-equal? (- (hash-ref (mdl-logical-storage-stats) 'used)
                    (hash-ref before 'used)) 6)
   (define vector-value (mdl-vector 1 2))
   (check-equal? (- (hash-ref (mdl-logical-storage-stats) 'used)
                    (hash-ref before 'used)) 12)
   ;; The head cell (2 words) is dead; tail (4 words) + vector (6 words) are live.
   ;; At least 2 words must be reclaimed. Exact count depends on host liveness;
   ;; we do NOT assert exactly 2 to stay robust across BC and CS.
   (define reclaimed (mdl-apply "GC"))
   (check-true (>= reclaimed 2)
               "head cell (2 words) must be reclaimed when only tail is retained")
   ;; Retained objects are still live and structurally correct.
   (check-equal? (mdl-list->list tail) '(2 3))
   (check-equal? (mdl-apply "NTH" vector-value 2) 2)
   (check-invariant!)))

;; --- Discarded LIST: all words reclaimed after function returns ---
;; R10: Use total-used invariant instead of exact reclaimed count.
;; Mutation sensitivity: if sweep is broken, used > initial-used → check fails;
;; if double-counted, used < 0 → (>= 0) fails.
(define (discard-list)
  (mdl-list 1 2 3)
  (void))
(session
 (lambda ()
   (define initial-used (hash-ref (mdl-logical-storage-stats) 'used))
   (discard-list)
   ;; At least 6 words (3 cells × 2) must be reclaimed from the discarded list.
   (define reclaimed (mdl-apply "GC"))
   (check-true (>= reclaimed 6)
               "discarded 3-cell list (6 words) must be fully reclaimed")
   ;; After reclamation, used must equal what it was before discard-list.
   (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) initial-used
                 "used must return to initial after all words reclaimed")
   ;; Second GC: nothing new to collect.
   (check-equal? (mdl-apply "GC") 0)
   (check-invariant!)))

;; --- DIVERT-AGC with BLOAT handler: GC not triggered when BLOAT satisfies request ---
(session
 (lambda ()
   (define diverted '())
   (define collected '())
   (define divert-header (mdl-apply "EVENT" "DIVERT-AGC" 1000))
   (define gc-header (mdl-apply "EVENT" "GC" 11))
   (mdl-apply "HANDLER" divert-header
              (lambda (words initiator)
                (set! diverted (list words initiator))
                (mdl-apply "BLOAT" (+ words 10))))
   (mdl-apply "HANDLER" gc-header
              (lambda (elapsed reason initiator)
                (set! collected (list elapsed reason initiator))))
   (mdl-set-logical-storage-capacity! 0)
   (define retained (mdl-list 7))
   (check-equal? (car diverted) 2)
   (check-eq? (cadr diverted) (mdl-atom "LIST"))
   (check-equal? collected '())
   (check-equal? (mdl-list->list retained) '(7))
   (check-true (>= (hash-ref (mdl-logical-storage-stats) 'free) 10))
   (check-invariant!)))

;; --- DIVERT-AGC with no handler: GC triggered when capacity exhausted ---
(session
 (lambda ()
   (define observed '())
   (define header (mdl-apply "EVENT" "GC" 11))
   (mdl-apply "HANDLER" header
              (lambda (elapsed reason initiator)
                (set! observed (list elapsed reason initiator))))
   (mdl-set-logical-storage-capacity! 0)
   (define retained (mdl-vector 7))
   (check-equal? (cadr observed) 2)
   (check-eq? (caddr observed) (mdl-atom "VECTOR"))
   (check-equal? (mdl-apply "NTH" retained 1) 7)
   (check-invariant!)))

;; --- Live cycles are NOT collected (host weak-box still sees them) ---
(session
 (lambda ()
   (define cycle (mdl-list 1))
   (mdl-putrest! cycle cycle)
   (check-equal? (mdl-apply "GC") 0)
   (check-eq? (mcdr cycle) cycle)
   (check-invariant!)))

;; --- UVECTOR REST shares storage: single registration, no double-count ---
(session
 (lambda ()
   (define initial (hash-ref (mdl-logical-storage-stats) 'used))
   (define base (mdl-apply "UVECTOR" 1 2 3))
   (define tail (mdl-apply "REST" base 1))
   (check-equal? (- (hash-ref (mdl-logical-storage-stats) 'used) initial) 5)
   (check-equal? (mdl-apply "GC") 0)
   (check-equal? (mdl-apply "NTH" tail 1) 2)
   (check-equal? (mdl-apply "NTH" base 2) 2)
   (check-invariant!)))

;; --- Discarded cycle: words reclaimed after function returns ---
;; R10: Use >= and total-used invariant instead of exact reclaimed count.
;; Mutation sensitivity: if the GC sweep never frees cycle entries,
;; used > initial-used → check fails.
(define (discard-cycle)
  (define cycle (mdl-list 1))
  (mdl-putrest! cycle cycle)
  (void))
(session
 (lambda ()
   (define initial-used (hash-ref (mdl-logical-storage-stats) 'used))
   (discard-cycle)
   ;; The single-cell cycle (2 words) must be reclaimed.
   (define reclaimed (mdl-apply "GC"))
   (check-true (>= reclaimed 2)
               "discarded single-cell cycle (2 words) must be reclaimed")
   (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) initial-used
                 "used must return to initial after cycle is reclaimed")
   ;; Second GC: nothing new to collect.
   (check-equal? (mdl-apply "GC") 0)
   (check-invariant!)))

;; --- Exception safety: DIVERT-AGC handler raises; state stays consistent ---
(session
 (lambda ()
   (define header (mdl-apply "EVENT" "DIVERT-AGC" 1000))
   (mdl-apply "HANDLER" header
              (lambda (_words _initiator) (error 'pressure-handler "probe")))
   (mdl-set-logical-storage-capacity! 0)
   (check-exn #rx"probe" (lambda () (mdl-list 1)))
   ;; No words must be charged: the failed allocation was not registered.
   (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) 0)
   (check-invariant!)
   ;; After BLOAT, subsequent allocations succeed cleanly.
   (mdl-apply "BLOAT" 2)
   (check-equal? (mdl-list->list (mdl-list 1)) '(1))
   (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) 2)
   (check-invariant!)))

;; --- Exception safety: GC event handler raises; already-swept state stays consistent ---
;; R10 task 4: GC sweep completes (entries/used updated), then GC event handler raises.
;; The allocation fails (exception propagates) but ledger state must be consistent.
;; Ordering: allocate-discard while capacity is large, then tighten, then install
;; the raising handler, then try a new allocation.  This ensures the raising handler
;; only fires during the deliberate allocation attempt, not during setup.
(define (make-some-words)
  ;; Allocates 2 words (single-element list cell) and discards them.
  (mdl-list 10)
  (void))
(session
 (lambda ()
   ;; Make some garbage while capacity is generous.
   (make-some-words)
   ;; Tighten capacity so the next allocation must trigger GC.
   (mdl-set-logical-storage-capacity! (hash-ref (mdl-logical-storage-stats) 'used))
   ;; Now install the raising GC handler.
   (define gc-header (mdl-apply "EVENT" "GC" 11))
   (mdl-apply "HANDLER" gc-header
              (lambda (_elapsed _reason _initiator)
                (error 'gc-handler "deliberate-raise")))
   ;; This allocation triggers DIVERT-AGC → GC sweep (runs, reclaims dead words)
   ;; → GC event fires → handler raises.  The exception must propagate out.
   (check-exn #rx"deliberate-raise" (lambda () (mdl-list 99)))
   ;; Ledger must be internally consistent despite the raise.
   (check-invariant! " after GC-event-handler raise")))

;; --- Session isolation: two atom spaces have independent ledgers ---
(define first-space (make-mdl-atom-space))
(define second-space (make-mdl-atom-space))
(parameterize ([current-mdl-atom-space first-space])
  (define retained (mdl-list 1 2))
  (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) 4)
  (parameterize ([current-mdl-atom-space second-space])
    (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) 0)
    (define other (mdl-vector 1))
    (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) 4)
    (check-equal? (mdl-apply "NTH" other 1) 1)
    (check-invariant! " second-space"))
  (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) 4)
  (check-equal? (mdl-apply "NTH" retained 1) 1)
  (check-invariant! " first-space"))
