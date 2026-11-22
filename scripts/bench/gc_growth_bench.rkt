#lang racket/base
;; Benchmark: logical GC capacity-growth behavior under a steadily-growing live set.
;; Measures collection count and wall time for N retained MDL LIST cells.
;; Not part of the smoke suite (run directly: racket scripts/bench/gc_growth_bench.rkt).
;; R2 fix: amortised geometric capacity growth (factor 3/2) gives O(log n) collections
;; instead of O(n) with the flat +8192 linear bump.
;;
;; Reading the results: 'collections' counts how many logical GC sweeps happen
;; during allocation. With 2 words per cell, N cells = 2N logical words.
;; Expected collection counts:
;;   Linear (+8192): ceil((2N - cap0) / 8192) ≈ N/4096
;;   Geometric (×1.5): ceil(log_1.5(2N/cap0)) ≈ 1.7·log2(N/cap0)
(require racket/mpair
         "../../mdl/runtime/core.rkt")

(define (run-bench label n-cells capacity-hint)
  (define atom-space (make-mdl-atom-space))
  (parameterize ([current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space atom-space])
    (mdl-set-logical-storage-capacity! capacity-hint)
    (define collections 0)
    (define header (mdl-apply "EVENT" "GC" 11))
    (mdl-apply "HANDLER" header
               (lambda (_elapsed _reason _initiator)
                 (set! collections (+ collections 1))))
    (define t0 (current-inexact-milliseconds))
    (define retained '())
    (for ([i (in-range n-cells)])
      (set! retained (cons (mdl-list i) retained)))
    (define elapsed-ms (- (current-inexact-milliseconds) t0))
    (define stats (mdl-logical-storage-stats))
    (printf "  ~a: n=~a cap0=~a → collections=~a used=~a cap=~a time=~ams~n"
            label n-cells capacity-hint collections
            (hash-ref stats 'used)
            (hash-ref stats 'capacity)
            (inexact->exact (round elapsed-ms)))
    ;; Invariant checks
    (unless (= (+ (hash-ref stats 'used) (hash-ref stats 'free))
               (hash-ref stats 'capacity))
      (error 'bench "invariant violation: used+free ≠ capacity"))
    (unless (>= (hash-ref stats 'used) 0)
      (error 'bench "invariant violation: used < 0"))
    collections))

(printf "=== GC capacity-growth benchmark (R2) ===~n")
(printf "Each MDL list cell = 2 logical words.~n~n")

(printf "Tight initial capacity (cap0=1000), growing live set:~n")
(define c10k  (run-bench "AFTER-FIX" 10000  1000))
(define c100k (run-bench "AFTER-FIX" 100000 1000))
(define c500k (run-bench "AFTER-FIX" 500000 1000))

(printf "~nExpected collections with geometric growth (×3/2):~n")
(for ([n '(10000 100000 500000)])
  (define words (* 2 n))
  (define expected (inexact->exact (ceiling (/ (log (/ words 1000)) (log 3/2)))))
  (printf "  n=~a words=~a: expected ≈ ~a GCs~n" n words expected))

(printf "~nFormula prediction, old policy (flat +8192, NOT measured here):~n")
(printf "  (Run at git commit 850a87f to get actual measurements)~n")
(for ([n '(10000 100000 500000)])
  (define words (* 2 n))
  (define expected (inexact->exact (ceiling (/ (- words 1000) 8192))))
  (printf "  n=~a words=~a: formula ≈ ~a GCs~n" n words expected))

(printf "~nDefault capacity (cap0=262144, most allocations never GC):~n")
(run-bench "AFTER-FIX" 50000  262144)
(run-bench "AFTER-FIX" 200000 262144)
