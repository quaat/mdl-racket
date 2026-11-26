#lang racket/base
;; Issue #104 foundation: deterministic source exercises scheduler, not GC.
(require rackunit racket/list "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (session thunk)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (thunk)))
(define (run source)
  (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
    (eval expr)))
(define (mdl-test-signal-event! name . args)
  (mdl-emit-event! name args))

(session
 (lambda ()
   (define seen '())
   (define header (mdl-apply (mdl-atom "EVENT") "TEST" 7))
   (define old (mdl-apply (mdl-atom "HANDLER") header
                          (lambda (value) (set! seen (append seen (list (list 'old value)))))))
   (define new (mdl-apply (mdl-atom "HANDLER") header
                          (lambda (value) (set! seen (append seen (list (list 'new value)))))))
   (check-equal? (mdl-apply (mdl-atom "INT-LEVEL")) 0)
   (check-true (mdl-test-signal-event! "TEST" 12))
   (check-equal? seen '((new 12) (old 12)))
   (mdl-apply (mdl-atom "OFF") new)
   (mdl-test-signal-event! "TEST" 13)
   (check-equal? seen '((new 12) (old 12) (old 13)))
   (mdl-apply (mdl-atom "HANDLER") header new)
   (mdl-test-signal-event! "TEST" 14)
   (check-equal? (take-right seen 2) '((new 14) (old 14)))
   (check-eq? (mdl-apply (mdl-atom "DISABLE") header) header)
   (check-false (mdl-test-signal-event! "TEST" 15))
   (check-eq? (mdl-apply (mdl-atom "ENABLE") header) header)
   (check-true (mdl-test-signal-event! "TEST" 16))
   (check-equal? (take-right seen 2) '((new 16) (old 16)))
   (mdl-apply (mdl-atom "OFF") header)
   (check-false (mdl-test-signal-event! "TEST" 17))))

(session
 (lambda ()
   (define seen '())
   (define low (mdl-apply (mdl-atom "EVENT") "LOW" 3))
   (define high (mdl-apply (mdl-atom "EVENT") "HIGH" 9))
   (mdl-apply (mdl-atom "HANDLER") low (lambda (x) (set! seen (append seen (list x)))))
   (mdl-apply (mdl-atom "HANDLER") high (lambda (x) (set! seen (append seen (list x)))))
   (check-equal? (mdl-apply (mdl-atom "INT-LEVEL") 5) 0)
   (mdl-test-signal-event! "LOW" 1)
   (mdl-test-signal-event! "LOW" 2)
   (mdl-test-signal-event! "HIGH" 3)
   (check-equal? seen '(3))
   (check-equal? (mdl-apply (mdl-atom "INT-LEVEL") 0) 5)
   (check-equal? seen '(3 1 2))))

(session
 (lambda ()
   (define seen '())
   (define a (mdl-apply (mdl-atom "EVENT") "A" 4))
   (define b (mdl-apply (mdl-atom "EVENT") "B" 8))
   (define last (mdl-apply (mdl-atom "HANDLER") a (lambda () (set! seen (append seen '(last))))))
   (mdl-apply (mdl-atom "HANDLER") a
              (lambda ()
                (check-equal? (mdl-apply (mdl-atom "INT-LEVEL")) 4)
                (mdl-test-signal-event! "B")
                (mdl-apply (mdl-atom "OFF") last)
                (set! seen (append seen '(first)))))
   (mdl-apply (mdl-atom "HANDLER") b
              (lambda ()
                (check-equal? (mdl-apply (mdl-atom "INT-LEVEL")) 8)
                (set! seen (append seen '(nested)))))
   (mdl-test-signal-event! "A")
   (check-equal? seen '(nested first))
   (check-equal? (mdl-apply (mdl-atom "INT-LEVEL")) 0)))

(session
 (lambda ()
   (define h (mdl-apply (mdl-atom "EVENT") "ERR" 2))
   (mdl-apply (mdl-atom "HANDLER") h (lambda () (error 'test-handler "boom")))
   (check-exn #rx"boom" (lambda () (mdl-test-signal-event! "ERR")))
   (check-equal? (mdl-apply (mdl-atom "INT-LEVEL")) 0)
   (check-exn #rx"unknown|unregistered" (lambda () (mdl-emit-event! "MISSING" '() #t)))
   (check-exn #rx"FIX" (lambda () (mdl-apply (mdl-atom "INT-LEVEL") "BAD")))))

(session
 (lambda ()
   ;; The handler is an interpreted MDL FUNCTION. Its argument is a value,
   ;; never an expression to evaluate again during callback application.
   (run "<SETG E <EVENT \"INTERPRETED\" 5>>
         <SETG H <HANDLER ,E <FUNCTION (X) <SETG MARK .X>>>>")
   (mdl-test-signal-event! "INTERPRETED" 42)
   (check-equal? (mdl-gval (mdl-atom "MARK")) 42)
   (define unevaluated-form
     (mdl-make-form (mdl-list (mdl-atom "SETG") (mdl-atom "TRAP") 99)))
   (mdl-test-signal-event! "INTERPRETED" unevaluated-form)
   (check-eq? (mdl-gval (mdl-atom "MARK")) unevaluated-form)
   (check-exn #rx"unassigned" (lambda () (mdl-gval (mdl-atom "TRAP"))))))

(session
 (lambda ()
   (define seen '())
   (define h (mdl-apply (mdl-atom "EVENT") "QUEUED" 1))
   (mdl-apply (mdl-atom "HANDLER") h (lambda (x) (set! seen (cons x seen))))
   (mdl-apply (mdl-atom "INT-LEVEL") 2)
   (mdl-test-signal-event! "QUEUED" 1)
   (mdl-apply (mdl-atom "DISABLE") h)
   (mdl-apply (mdl-atom "INT-LEVEL") 0)
   (check-equal? seen '())
   (mdl-apply (mdl-atom "ENABLE") h)
   (mdl-test-signal-event! "QUEUED" 2)
   (check-equal? seen '(2))))

(session
 (lambda ()
   (define seen '())
   (define low (mdl-apply (mdl-atom "EVENT") "AFTER-ERROR" 2))
   (define high (mdl-apply (mdl-atom "EVENT") "RAISES" 8))
   (mdl-apply (mdl-atom "HANDLER") low (lambda () (set! seen '(delivered))))
   (mdl-apply (mdl-atom "HANDLER") high
              (lambda ()
                (mdl-test-signal-event! "AFTER-ERROR")
                (error 'raises "original failure")))
   (check-exn #rx"original failure"
              (lambda () (mdl-test-signal-event! "RAISES")))
   (check-equal? (mdl-apply (mdl-atom "INT-LEVEL")) 0)
   (check-equal? seen '())
   ;; Explicit interpreter safe point drains the queued occurrence after
   ;; the exception is observed, even when the level is already zero.
   (check-equal? (mdl-apply (mdl-atom "INT-LEVEL") 0) 0)
   (check-equal? seen '(delivered))))

(session
 (lambda ()
   (define seen '())
   (define low (mdl-apply (mdl-atom "EVENT") "OLD-PENDING" 2))
   (define high (mdl-apply (mdl-atom "EVENT") "ERROR-FIRST" 8))
   (define next (mdl-apply (mdl-atom "EVENT") "NEW-SIGNAL" 3))
   (mdl-apply (mdl-atom "HANDLER") low
              (lambda () (set! seen (append seen '(old)))))
   (mdl-apply (mdl-atom "HANDLER") next
              (lambda () (set! seen (append seen '(new)))))
   (mdl-apply (mdl-atom "HANDLER") high
              (lambda ()
                (mdl-test-signal-event! "OLD-PENDING")
                (error 'error-first "original failure")))
   (check-exn #rx"original failure"
              (lambda () (mdl-test-signal-event! "ERROR-FIRST")))
   (mdl-test-signal-event! "NEW-SIGNAL")
   (check-equal? seen '(old new))))

(session
 (lambda ()
   (define seen '())
   (define old (mdl-apply (mdl-atom "EVENT") "OLD-ERROR" 2))
   (define first (mdl-apply (mdl-atom "EVENT") "FIRST-ERROR" 8))
   (define next (mdl-apply (mdl-atom "EVENT") "RETAIN-NEW" 3))
   (mdl-apply (mdl-atom "HANDLER") old (lambda () (error 'old "older failure")))
   (mdl-apply (mdl-atom "HANDLER") first
              (lambda ()
                (mdl-test-signal-event! "OLD-ERROR")
                (error 'first "first failure")))
   (mdl-apply (mdl-atom "HANDLER") next (lambda () (set! seen '(newer))))
   (check-exn #rx"first failure"
              (lambda () (mdl-test-signal-event! "FIRST-ERROR")))
   ;; The next occurrence has happened even if processing the older queued
   ;; occurrence fails. It must remain queued for the following safe point.
   (check-exn #rx"older failure"
              (lambda () (mdl-test-signal-event! "RETAIN-NEW")))
   (check-equal? seen '())
   (mdl-apply (mdl-atom "INT-LEVEL") 0)
   (check-equal? seen '(newer))))

(define foreign (session (lambda () (mdl-apply (mdl-atom "EVENT") "FOREIGN" 5))))
(session
 (lambda ()
   (check-exn #rx"session" (lambda () (mdl-apply (mdl-atom "ENABLE") foreign)))
   (check-exn #rx"session" (lambda () (mdl-apply (mdl-atom "DISABLE") foreign)))
   (check-equal? (mdl-apply (mdl-atom "INT-LEVEL")) 0)))

(session
 (lambda ()
   ;; Chapter 21 names these as predefined interrupts. Accepting their
   ;; registration without a source would silently lose callbacks.
   (for ([name (in-list '("UNBLOCKED" "SYSDOWN" "INFERIOR" "RUNT"
                          "REALT" "MPV" "PURE" "ILOPR" "PARITY" "IOC"))])
     (check-exn #rx"unsupported predefined EVENT"
                (lambda () (mdl-apply (mdl-atom "EVENT") name 5))))))
