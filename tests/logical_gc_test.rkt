#lang racket/base
(require rackunit racket/mpair "../mdl/runtime/core.rkt")

(define (session thunk)
  (parameterize ([current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (thunk)))

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
   (check-exn #rx"BLOAT|FIX" (lambda () (mdl-apply "BLOAT" -1)))))

(session
 (lambda ()
   (define before (mdl-logical-storage-stats))
   (define shared (mdl-list 1 2 3))
   (define tail (mcdr shared))
   (check-eq? (mdl-apply "REST" shared) tail)
   (check-equal? (- (hash-ref (mdl-logical-storage-stats) 'used)
                    (hash-ref before 'used)) 6)
   (define vector-value (mdl-vector 1 2))
   (check-equal? (- (hash-ref (mdl-logical-storage-stats) 'used)
                    (hash-ref before 'used)) 12)
   ;; The head is dead after REST; the retained tail and vector stay live.
   (check-equal? (mdl-apply "GC") 2)
   (check-equal? (mdl-list->list tail) '(2 3))
   (check-equal? (mdl-apply "NTH" vector-value 2) 2)))

(define (discard-list)
  (mdl-list 1 2 3)
  (void))
(session
 (lambda ()
   (discard-list)
   (check-equal? (mdl-apply "GC") 6)
   (check-equal? (mdl-apply "GC") 0)))

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
   (check-true (>= (hash-ref (mdl-logical-storage-stats) 'free) 10))))

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
   (check-equal? (mdl-apply "NTH" retained 1) 7)))

(session
 (lambda ()
   (define cycle (mdl-list 1))
   (mdl-putrest! cycle cycle)
   (check-equal? (mdl-apply "GC") 0)
   (check-eq? (mcdr cycle) cycle)))

(session
 (lambda ()
   (define initial (hash-ref (mdl-logical-storage-stats) 'used))
   (define base (mdl-apply "UVECTOR" 1 2 3))
   (define tail (mdl-apply "REST" base 1))
   (check-equal? (- (hash-ref (mdl-logical-storage-stats) 'used) initial) 5)
   (check-equal? (mdl-apply "GC") 0)
   (check-equal? (mdl-apply "NTH" tail 1) 2)
   (check-equal? (mdl-apply "NTH" base 2) 2)))

(define (discard-cycle)
  (define cycle (mdl-list 1))
  (mdl-putrest! cycle cycle)
  (void))
(session
 (lambda ()
   (discard-cycle)
   (check-equal? (mdl-apply "GC") 2)
   (check-equal? (mdl-apply "GC") 0)))

(session
 (lambda ()
   (define header (mdl-apply "EVENT" "DIVERT-AGC" 1000))
   (mdl-apply "HANDLER" header
              (lambda (_words _initiator) (error 'pressure-handler "probe")))
   (mdl-set-logical-storage-capacity! 0)
   (check-exn #rx"probe" (lambda () (mdl-list 1)))
   (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) 0)
   (mdl-apply "BLOAT" 2)
   (check-equal? (mdl-list->list (mdl-list 1)) '(1))
   (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) 2)))

(define first-space (make-mdl-atom-space))
(define second-space (make-mdl-atom-space))
(parameterize ([current-mdl-atom-space first-space])
  (define retained (mdl-list 1 2))
  (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) 4)
  (parameterize ([current-mdl-atom-space second-space])
    (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) 0)
    (define other (mdl-vector 1))
    (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) 4)
    (check-equal? (mdl-apply "NTH" other 1) 1))
  (check-equal? (hash-ref (mdl-logical-storage-stats) 'used) 4)
  (check-equal? (mdl-apply "NTH" retained 1) 1))
