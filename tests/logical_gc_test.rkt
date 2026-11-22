#lang racket/base
;; Tests for the logical movable-storage GC ledger.
;;
;; R10: assertions replaced with optimizer-liveness-independent invariants:
;;   - cached used = sum of surviving entry words (mdl-recompute-entry-words)
;;   - reclaimed >= N (lower bound on expected freed words)
;;   - used = initial after all allocated objects gone
;;   - retained objects never reclaimed (structural checks)
;;   - cycles collectable
;;   - session isolation
;;
;; R2 (growth policy) tests:
;;   - gc-min floor prevents repeated GCs on a nearly-full live set
;;   - geometric factor (ceil(cap × 3/2)) dominates over gc-min when cap is large
;;   - overflow error near fix-max
;;   - fix-max cap (via current-mdl-gc-min=2 to make it reachable)
;;
;; Mutation sensitivity annotated per test.
(require rackunit racket/mpair racket/list "../mdl/runtime/core.rkt")

(define fix-max (sub1 (arithmetic-shift 1 35)))  ; 2^35-1

;; Helper: verify the cached 'used' field matches the independent entry-word sum.
;; This catches bugs where set-mdl-memory-used! or register! corrupts the cache:
;;   - If register! adds to used but loses the entry → recompute < cached: check fails.
;;   - If collect! subtracts wrong amount → recompute ≠ cached: check fails.
;;   - Note: "used + free = capacity" is tautological (free := capacity-used) and
;;     is NOT checked here. We check the meaningful invariant: entries sum = used.
(define (check-invariant! [label ""])
  (define s (mdl-logical-storage-stats))
  (check-equal? (mdl-recompute-entry-words)
                (hash-ref s 'used)
                (string-append "entry-word-sum = cached used" label))
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

;; --- REST shares backing storage; head cell reclaimed when only tail is retained ---
;; R10: Wrap shared in a nested function so it goes out of scope before GC.
;; This avoids dependence on whether BC or CS kills a binding after last use.
;;
;; reclaimed = 2 exactly (the head cell only), not >= 2:
;;   The upper bound matters: if the sweep wrongly reclaims the live tail,
;;   reclaimed would be 6 and the test must fail.
;;
;; Mutation sensitivity:
;;   - Sweep never frees entries → reclaimed = 0 → (= 2) fails.
;;   - Sweep reclaims live tail → reclaimed = 6 → (= 2) fails.
;;   - register! loses entry → entry-word-sum < cached used → check-invariant! fails.
(define (make-shared-and-return-tail)
  ;; shared goes out of scope when this function returns.
  (define shared (mdl-list 1 2 3))
  (define tail (mcdr shared))
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
   (define reclaimed (mdl-apply "GC"))
   (check-equal? reclaimed 2
                 "exactly 2 words reclaimed: head cell only (tail and vector live)")
   (check-equal? (mdl-list->list tail) '(2 3))
   (check-equal? (mdl-apply "NTH" vector-value 2) 2)
   (check-invariant!)))

;; --- Discarded LIST: all words reclaimed after function returns ---
;; R10: Use total-used invariant instead of exact reclaimed count.
;; Mutation sensitivity: sweep never frees → used > initial → check fails.
(define (discard-list)
  (mdl-list 1 2 3)
  (void))
(session
 (lambda ()
   (define initial-used (hash-ref (mdl-logical-storage-stats) 'used))
   (discard-list)
   (define reclaimed (mdl-apply "GC"))
   (check-true (>= reclaimed 6)
               "discarded 3-cell list (6 words) must be fully reclaimed")
   (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) initial-used
                 "used must return to initial after all words reclaimed")
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
;; R10: Use >= and total-used invariant.
;; Mutation sensitivity: sweep never frees → used > initial → check fails.
(define (discard-cycle)
  (define cycle (mdl-list 1))
  (mdl-putrest! cycle cycle)
  (void))
(session
 (lambda ()
   (define initial-used (hash-ref (mdl-logical-storage-stats) 'used))
   (discard-cycle)
   (define reclaimed (mdl-apply "GC"))
   (check-true (>= reclaimed 2)
               "discarded single-cell cycle (2 words) must be reclaimed")
   (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) initial-used
                 "used must return to initial after cycle reclaimed")
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
   (check-invariant! " after DIVERT-AGC-handler raise")
   ;; After BLOAT, subsequent allocations succeed cleanly.
   (mdl-apply "BLOAT" 2)
   (check-equal? (mdl-list->list (mdl-list 1)) '(1))
   (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) 2)
   (check-invariant! " after recovery")))

;; --- Exception safety: GC event handler raises; already-swept state stays consistent ---
;; R10 task 4: GC sweep completes (entries/used updated), then GC event handler raises.
;; The allocation fails (exception propagates) but ledger must be consistent.
;;
;; Specific assertions: after the raise:
;;   - used = 0 (the garbage cell was reclaimed by the sweep before the raise)
;;   - recompute-entry-words = used (consistency)
(define (make-some-garbage)
  (mdl-list 10)
  (void))
(session
 (lambda ()
   ;; Allocate then discard while capacity is generous.
   (make-some-garbage)   ; 2 words registered then dead
   ;; Tighten capacity to used (= 2) so the next alloc triggers GC.
   (mdl-set-logical-storage-capacity! (hash-ref (mdl-logical-storage-stats) 'used))
   (define gc-header (mdl-apply "EVENT" "GC" 11))
   (mdl-apply "HANDLER" gc-header
              (lambda (_elapsed _reason _initiator)
                (error 'gc-handler "deliberate-raise")))
   ;; Triggers DIVERT-AGC → GC sweep (reclaims the 2 dead words) → GC event raises.
   (check-exn #rx"deliberate-raise" (lambda () (mdl-list 99)))
   ;; The sweep ran and reclaimed the garbage; used = 0 now.
   (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) 0
                 "used = 0: garbage reclaimed by sweep before handler raised")
   (check-invariant! " after GC-event-handler raise")))

;; ============================================================
;; --- Capacity growth policy: deterministic tests (R2 point 3) ---
;; ============================================================
;;
;; These tests assert exact GC counts and resulting capacity values.
;; Four mutants that the original abc8283 commit did NOT catch:
;;   M1) revert to flat +8192 (remove gc-min check, grow by +8192 when needed > cap)
;;   M2) grown = needed only (no geometric factor)
;;   M3) drop overflow error (allow needed > fix-max)
;;   M4) drop fix-max cap (allow grown > fix-max)
;;
;; Each test below names which mutants it catches.

;; Growth test A: gc-min floor prevents 499 repeated GCs.
;; Setup: 499 live cells (998 words, cap-2 of cap=1000), then 500 garbage allocs.
;; Without gc-min check: each alloc after the first triggers GC (499 GCs total).
;; With gc-min check: first GC grows cap; subsequent allocs fit without GC.
;;
;; Catches M1 (flat +8192 without gc-min check would behave like no-gc-min;
;;   but actually flat +8192 from pre-R2 code also lacks gc-min → 499 GCs).
;; Note: M2 (grown=needed only) ALSO catches this if gc-min check is present
;;   but needed = used + gc-min = 1998 (small enough that no further GC in 500 allocs).
;; The important distinction: gc-min check present vs absent.
(define (discard-one!)
  (mdl-list 9999)
  (void))
(session
 (lambda ()
   (define cap0 1000)
   (mdl-set-logical-storage-capacity! cap0)
   ;; Allocate 499 single-element lists = 499 cells × 2 words = 998 words live.
   (define live-cells (for/list ([i (in-range 499)]) (mdl-list i)))
   (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) 998)
   (define gc-count 0)
   (define header (mdl-apply "EVENT" "GC" 11))
   (mdl-apply "HANDLER" header (lambda _ (set! gc-count (+ gc-count 1))))
   ;; 500 garbage allocations. Without gc-min: 499 GCs. With gc-min: 1 GC.
   (for ([_ (in-range 500)]) (discard-one!))
   (check-equal? gc-count 1
                 "gc-min floor: 500 garbage allocs at cap-2 trigger exactly 1 GC")
   ;; Capacity grew during the 1 GC: needed=998+8192=9190, ceil(1000×1.5)=1500 → 9190.
   ;; Mutant M1 (no gc-min check): GC runs 499 times; cap stays near 1000 → cap ≠ 9190.
   ;; Note: free may be less than gc-min by this point because subsequent allocs after
   ;; growth were not followed by another GC (all 499 remaining garbage cells are
   ;; unreclaimed, reducing free to 9190-1996=7194). The cap is the stable witness.
   (check-equal? (hash-ref (mdl-logical-storage-stats) 'capacity) 9190
                 "capacity grew to max(needed=9190, ceil(1000×1.5)=1500) = 9190")
   (check-invariant! " gc-min-floor")
   ;; Live cells still accessible.
   (for-each (lambda (cell) (check-true (mpair? cell))) live-cells)))

;; Growth test B: geometric factor gives larger capacity than gc-min alone.
;; Setup: cap=50001, allocate big vector (50000 words live), trigger pressure.
;; After GC+growth:
;;   needed = 50000 + max(2, 8192) = 58192
;;   ceil(50001 × 1.5) = ceil(75001.5) = 75002
;;   grown = max(58192, 75002) = 75002
;;
;; Catches M2 (grown=needed=58192, not 75002).
;; Also catches flat +8192 FROM gc-min-enhanced code: flat-+8192 would give
;;   50000 + 8192 = 58192 for needed, +8192 gives 58193 — neither is 75002.
(session
 (lambda ()
   (define cap0 50001)
   (mdl-set-logical-storage-capacity! cap0)
   ;; mdl-vector with N elements: 2*N+2 words. N=24999 → 50000 words.
   (define big-vec (apply mdl-vector (make-list 24999 0)))
   (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) 50000)
   (define gc-count 0)
   (define header (mdl-apply "EVENT" "GC" 11))
   (mdl-apply "HANDLER" header (lambda _ (set! gc-count (+ gc-count 1))))
   ;; 2-word alloc: 50000+2=50002 > 50001 → GC → 0 freed → growth.
   (define sentinel (mdl-list 42))
   (check-equal? gc-count 1)
   (check-equal? (hash-ref (mdl-logical-storage-stats) 'capacity) 75002
                 "geometric: cap = ceil(50001 × 3/2) = 75002, dominating needed=58192")
   (check-invariant! " geometric-factor")
   (check-equal? (mdl-apply "NTH" big-vec 1) 0)
   (check-equal? (mdl-apply "NTH" sentinel 1) 42)))

;; Growth test C: overflow error when needed > fix-max.
;; Uses test hook to set used near fix-max, then tries a 2-word alloc.
;; needed = (fix-max - 1) + max(2, 8192) = fix-max + 8191 > fix-max → error.
;;
;; Catches M3 (drop overflow check): no error raised → test fails.
(session
 (lambda ()
   ;; Artificially set used = fix-max - 1, cap = fix-max - 1 (exactly full).
   (mdl-set-logical-storage-capacity! (- fix-max 1))
   (mdl-set-used-for-test! (- fix-max 1))
   ;; Any alloc triggers pressure → GC → 0 freed → gc-min check: free=0 → grow.
   ;; needed = (fix-max - 1) + max(2, 8192) > fix-max → overflow error.
   (check-exn #rx"storage overflow"
              (lambda () (mdl-list 42)))
   ;; After the error, used is still the artificially-set value (not changed by grow).
   ;; Reset for clean state.
   (mdl-set-used-for-test! 0)
   (mdl-set-logical-storage-capacity! 262144)))

;; Growth test D: fix-max cap clamps grown when geometric would exceed fix-max.
;; Uses current-mdl-gc-min=2 (small) so gc-min doesn't force needed above fix-max,
;; while ceil(cap × 1.5) still exceeds fix-max.
;; cap = fix-max - 1, used = fix-max - 2, gc-min = 2:
;;   needed = (fix-max - 2) + max(2, 2) = fix-max     ← does NOT exceed fix-max
;;   ceil((fix-max - 1) × 1.5) = 3 × 2^34 - 1 > fix-max ← geometric exceeds fix-max
;;   grown = min(fix-max, max(fix-max, >fix-max)) = fix-max
;;
;; Catches M4 (drop fix-max cap): grown = max(fix-max, >fix-max) > fix-max.
(session
 (lambda ()
   (parameterize ([current-mdl-gc-min 2])
     (define cap0 (- fix-max 1))
     (mdl-set-logical-storage-capacity! cap0)
     (mdl-set-used-for-test! (- fix-max 2))   ; used = cap - 1
     ;; 2-word alloc: (fix-max-2)+2 = fix-max > cap=(fix-max-1) → pressure.
     ;; GC: 0 freed (no entries). free = 1.
     ;; gc-min check: free=1 < max(2, 2)=2 → grow.
     ;; needed = (fix-max-2) + max(2,2) = fix-max ≤ fix-max → no overflow.
     ;; geometric: ceil((fix-max-1) × 1.5) > fix-max → cap clamps to fix-max.
     (define gc-count 0)
     (define header (mdl-apply "EVENT" "GC" 11))
     (mdl-apply "HANDLER" header (lambda _ (set! gc-count (+ gc-count 1))))
     (define sentinel (mdl-list 99))
     (check-equal? gc-count 1)
     (check-equal? (hash-ref (mdl-logical-storage-stats) 'capacity) fix-max
                   "fix-max cap: grown clamped to fix-max=2^35-1")
     ;; Mutant M4 (no clamp): capacity would be ceil((fix-max-1)*1.5) > fix-max.
     ;; Repair the artificial 'used' offset before checking invariant:
     ;; mdl-set-used-for-test! set used=(fix-max-2) without entries; then sentinel
     ;; (2 words) was registered, so used=fix-max but entries=[sentinel(2)].
     ;; Reset to used=2 so recompute-entry-words=used=2 for check-invariant!.
     (mdl-set-used-for-test! 2)
     (check-invariant! " fix-max-cap")
   )))

;; --- Exception safety: DIVERT-AGC handler raises; state stays consistent ---
;; (Already covered above; this confirms that after RECOVERY via BLOAT, used counts correctly.)

;; ============================================================
;; --- BLOAT handler satisfies request: gc-min NOT applied, 0 GCs ---
;;
;; R2 round-3 regression: 4e71e3a applied gc-min growth after every pressure
;; event, even when a DIVERT-AGC handler's BLOAT already satisfied the request
;; and no collection ran.  Result: cap jumped to 8192+ on each BLOAT, collapsing
;; a game-designed diversion schedule from ~85 diversions to ~2.
;;
;; Fix: `collected?` flag; gc-min growth only fires when a collection ran.
;;
;; Test (a): BLOAT handler exactly satisfies request (words+10).
;; Probe: cap=0, handler BLOATs words+10 → cap = 0 + (2+10) = 12.
;;   After fix:    cap = 12 exactly, 0 GCs.  ← PASS
;;   On 4e71e3a:   cap = 8192 (gc-min fires), 0 GCs.  ← FAIL (cap ≠ 12)
(session
 (lambda ()
   (define gc-count 0)
   (define diversions 0)
   (define gc-header (mdl-apply "EVENT" "GC" 11))
   (mdl-apply "HANDLER" gc-header (lambda _ (set! gc-count (+ gc-count 1))))
   (define divert-header (mdl-apply "EVENT" "DIVERT-AGC" 1000))
   (mdl-apply "HANDLER" divert-header
              (lambda (words _initiator)
                (set! diversions (+ diversions 1))
                (mdl-apply "BLOAT" (+ words 10))))
   (mdl-set-logical-storage-capacity! 0)
   ;; 2-word alloc: used=0, cap=0 → pressure → BLOAT(2+10=12) → cap=12.
   ;; Second pressure check: 0+2=2 > 12? No → no collection.
   (define retained (mdl-list 42))
   (check-equal? gc-count 0 "BLOAT handler: 0 GCs (no collection ran)")
   (check-equal? diversions 1 "BLOAT handler: 1 diversion")
   ;; Key: cap = used + words + 10 = 0 + 2 + 10 = 12, NOT 8192.
   ;; On 4e71e3a: gc-min fires unconditionally → cap = max(8192, ceil(0×1.5)) = 8192.
   (check-equal? (hash-ref (mdl-logical-storage-stats) 'capacity) 12
                 "BLOAT handler: cap = 12 (used=0+words=2+10), gc-min NOT applied")
   (check-equal? (mdl-list->list retained) '(42))
   (check-invariant! " BLOAT-no-gc")))

;; Test (b): Game-like DIVERT-AGC scenario — BLOAT(words+200) handler; 1010 live allocs.
;;
;; Hand-computed trace (each mdl-list = 2 words, BLOAT adds words+200=202 capacity):
;;   Alloc #1:   cap=0, used=0. 0+2>0 → pressure → BLOAT(202) → cap=202. No GC. used=2.
;;   Allocs 2-101: used 4,6,...,202. Fit without pressure (202 ≤ 202).
;;   Alloc #102: 202+2=204>202 → pressure → BLOAT(202) → cap=404. used=204.
;;   ...pattern: 1 diversion per 101 allocs. 1010 allocs → 10 diversions.
;;
;;   After fix: 10 diversions, 0 GCs.           ← PASS
;;   On 4e71e3a: after BLOAT diversion #1, gc-min fires → cap = max(needed=8192, 303) = 8192.
;;   Then 4095 allocs fit before next pressure (4095×2=8190 words). With 1010 allocs,
;;   that's only 1 more possible diversion at alloc #4097 — which never happens.
;;   → diversions = 1 (not 10).                 ← FAIL
(define (alloc-and-keep! sink i) (set-mcar! sink (mdl-list i)) (void))
(session
 (lambda ()
   (define diversions 0)
   (define gc-count 0)
   (define divert-header (mdl-apply "EVENT" "DIVERT-AGC" 1000))
   (define gc-header (mdl-apply "EVENT" "GC" 11))
   (mdl-apply "HANDLER" divert-header
              (lambda (words _init)
                (set! diversions (+ diversions 1))
                (mdl-apply "BLOAT" (+ words 200))))
   (mdl-apply "HANDLER" gc-header
              (lambda _ (set! gc-count (+ gc-count 1))))
   (mdl-set-logical-storage-capacity! 0)
   ;; Allocate 1010 single-cell lists, keeping them all live in a list.
   ;; Use a mutable sink to prevent the optimizer from treating allocations
   ;; as dead even if the loop variable isn't used after the loop.
   (define sink (mcons #f '()))
   (define live-cells
     (for/list ([i (in-range 1010)])
       (define c (mdl-list i))
       (set-mcar! sink c)   ; keep alive throughout the loop
       c))
   (check-equal? diversions 10
                 "game-like BLOAT(words+200): 10 diversions for 1010 allocs")
   (check-equal? gc-count 0 "game-like BLOAT: 0 GCs (handler always satisfied)")
   ;; Verify cells are still live
   (check-equal? (mdl-apply "NTH" (car live-cells) 1) 0)
   (check-equal? (mdl-apply "NTH" (car (reverse live-cells)) 1) 1009)
   (check-invariant! " game-like-BLOAT")))

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
