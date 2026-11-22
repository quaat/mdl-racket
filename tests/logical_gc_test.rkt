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
