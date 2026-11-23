#lang racket/base
;; Review R8: ERROR / ERRET interaction with the session interrupt queue,
;; interrupt level, nested handlers and ERROR FRAME liveness.
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (for/fold ([value #f]) ([expr (in-list (compile-program (parse-mdl source)))])
    (eval expr)))
;; Each scenario runs in a fresh session and its own test-case, so one
;; failure or exception does not hide the others.
(define-syntax-rule (scenario label body ...)
  (test-case label
    (parameterize ([current-namespace ns]
                   [current-mdl-globals (make-hasheq)]
                   [current-mdl-locals (list (make-hasheq))]
                   [current-mdl-atom-space (make-mdl-atom-space)])
      body ...)))
(define (level) (mdl-apply "INT-LEVEL"))

;; ERROR occurrences cannot be queued (manual 21.8.11). An older eligible
;; occurrence left pending by a raising handler must not capture the ERROR
;; occurrence in the queue, where it would outlive its FRAME.
(scenario "ERROR is never queued behind an older pending occurrence"
  (define e-calls 0)
  (define e-header (mdl-apply "EVENT" "E" 5))
  (mdl-apply "HANDLER" e-header
             (lambda (n)
               (set! e-calls (add1 e-calls))
               (when (<= e-calls 2) (error 'e-handler "E-BOOM ~a" e-calls))))
  (define error-frames '())
  (mdl-apply "HANDLER" (mdl-apply "EVENT" "ERROR" 8)
             (lambda (frame . args)
               (set! error-frames (cons frame error-frames))
               (mdl-apply "ERRET" 42 frame)))
  (mdl-apply "INT-LEVEL" 10)
  (mdl-emit-event! "E" '(1))
  (mdl-emit-event! "E" '(2))
  (check-exn #rx"E-BOOM 1" (lambda () (mdl-apply "INT-LEVEL" 0)))
  (check-equal? (level) 0)
  ;; The ERROR handler runs for this ERROR and resumes it.
  (check-equal? (mdl-apply "ERROR" (mdl-atom "PROBE")) 42)
  (check-equal? (length error-frames) 1)
  ;; The older E occurrence is still delivered at a later safe point.
  (check-exn #rx"E-BOOM 2" (lambda () (mdl-apply "INT-LEVEL" 0)))
  ;; No stale ERROR occurrence is delivered afterwards.
  (mdl-apply "INT-LEVEL" 0)
  (check-equal? (length error-frames) 1)
  (check-equal? e-calls 2))

;; Manual 21.8.11: a handler that resolves the error "can reset the
;; interrupt level to 0 and return a value from the error frame with
;; ERRET". ERRET itself does not restore the pre-interrupt level, so
;; occurrences queued during the handler stay queued until INT-LEVEL is
;; lowered; none is left eligible but undelivered.
(scenario "ERRET without INT-LEVEL keeps the handler level and the queue"
  (define e-seen '())
  (mdl-apply "HANDLER" (mdl-apply "EVENT" "E" 5)
             (lambda (n) (set! e-seen (cons n e-seen))))
  (mdl-apply "HANDLER" (mdl-apply "EVENT" "ERROR" 8)
             (lambda (frame . args)
               (mdl-emit-event! "E" '(7))
               (mdl-apply "ERRET" 1 frame)))
  (check-equal? (mdl-apply "ERROR" (mdl-atom "PROBE")) 1)
  (check-equal? (level) 8)
  (check-equal? e-seen '())
  (check-equal? (mdl-apply "INT-LEVEL" 0) 8)
  (check-equal? e-seen '(7))
  (check-equal? (level) 0))

(scenario "INT-LEVEL 0 then ERRET (the source HANDLE pattern) leaves level 0"
  (define e-seen '())
  (mdl-apply "HANDLER" (mdl-apply "EVENT" "E" 5)
             (lambda (n) (set! e-seen (cons n e-seen))))
  (mdl-apply "HANDLER" (mdl-apply "EVENT" "ERROR" 8)
             (lambda (frame . args)
               (mdl-emit-event! "E" '(3))
               (check-equal? e-seen '())
               (mdl-apply "INT-LEVEL" 0)
               ;; Lowering the level delivers the queued occurrence at once.
               (check-equal? e-seen '(3))
               (mdl-apply "ERRET" (mdl-atom "T") frame)))
  (mdl-apply "INT-LEVEL" 3)
  (check-eq? (mdl-apply "ERROR" (mdl-atom "PROBE")) (mdl-atom "T"))
  (check-equal? (level) 0)
  (check-equal? e-seen '(3)))

(scenario "source-shaped MDL handler: INT-LEVEL 0 and ERRET T"
  (run "<SETG ERRH <HANDLER <EVENT \"ERROR\" 8>
                     <FUNCTION (FRM \"TUPLE\" ZORK)
                       <INT-LEVEL 0>
                       <ERRET T .FRM>>>>")
  (check-eq? (run "<ERROR CONTROL-G?>") (mdl-atom "T"))
  (check-equal? (level) 0))

;; Nested ERROR inside an ERROR handler runs at level 8, which is not
;; below the ERROR priority: real ERROR is called, not the handler again.
;; The host exception restores the level and kills both frames.
(scenario "nested ERROR in a handler falls into the real error"
  (define calls 0)
  (define outer #f)
  (mdl-apply "HANDLER" (mdl-apply "EVENT" "ERROR" 8)
             (lambda (frame . args)
               (set! calls (add1 calls))
               (set! outer frame)
               (mdl-apply "ERROR" (mdl-atom "INNER"))))
  (check-exn #rx"INNER" (lambda () (mdl-apply "ERROR" (mdl-atom "OUTER"))))
  (check-equal? calls 1)
  (check-equal? (level) 0)
  (check-exn #rx"live ERROR FRAME" (lambda () (mdl-apply "ERRET" 1 outer))))

;; A higher-priority handler running inside the ERROR handler may ERRET the
;; outer ERROR frame; both handler activations are left, and the level is
;; the one current at ERRET.
(scenario "ERRET from a nested higher-priority handler"
  (define outer #f)
  (mdl-apply "HANDLER" (mdl-apply "EVENT" "HIGH" 10)
             (lambda () (mdl-apply "ERRET" 99 outer)))
  (mdl-apply "HANDLER" (mdl-apply "EVENT" "ERROR" 8)
             (lambda (frame . args)
               (set! outer frame)
               (mdl-emit-event! "HIGH" '())
               (error 'test "unreachable after nested ERRET")))
  (check-equal? (mdl-apply "ERROR" (mdl-atom "PROBE")) 99)
  (check-equal? (level) 10)
  (check-exn #rx"live ERROR FRAME" (lambda () (mdl-apply "ERRET" 1 outer)))
  (check-equal? (mdl-apply "INT-LEVEL" 0) 10))

(scenario "handler fallthrough and handler exceptions clean up"
  (define frame #f)
  (define mode 'return)
  (mdl-apply "HANDLER" (mdl-apply "EVENT" "ERROR" 8)
             (lambda (current . args)
               (set! frame current)
               (when (eq? mode 'raise) (error 'test "HANDLER-BOOM"))))
  (check-exn #rx"FALL" (lambda () (mdl-apply "ERROR" (mdl-atom "FALL"))))
  (check-equal? (level) 0)
  (check-exn #rx"live ERROR FRAME" (lambda () (mdl-apply "ERRET" 1 frame)))
  (set! mode 'raise)
  (check-exn #rx"HANDLER-BOOM" (lambda () (mdl-apply "ERROR" (mdl-atom "X"))))
  (check-equal? (level) 0)
  (check-exn #rx"live ERROR FRAME" (lambda () (mdl-apply "ERRET" 1 frame))))

;; Documented limitation: primitive (SUBR) failures stay strict host
;; failures. They do not run the "ERROR" interrupt and never succeed.
(scenario "primitive failures do not enter the ERROR interrupt"
  (define calls 0)
  (mdl-apply "HANDLER" (mdl-apply "EVENT" "ERROR" 8)
             (lambda (frame . args)
               (set! calls (add1 calls))
               (mdl-apply "ERRET" 0 frame)))
  (check-exn exn:fail? (lambda () (run "<+ 1 \"a\">")))
  (check-exn exn:fail? (lambda () (run ".UNBOUND-R8-LVAL")))
  (check-exn exn:fail? (lambda () (run "</ 1 0>")))
  (check-equal? calls 0)
  (check-equal? (level) 0))

;; Returning from ERROR via ERRET is a safe point: once ERRET's level is
;; established, pending occurrences whose priority exceeds it are delivered
;; exactly once; lower ones stay queued until the level is lowered.
(define (leave-pending! name priority calls-box)
  ;; The handler raises on its first call, so the second occurrence stays
  ;; pending while the level returns to 0.
  (mdl-apply "HANDLER" (mdl-apply "EVENT" name priority)
             (lambda (n)
               (set-box! calls-box (add1 (unbox calls-box)))
               (when (= (unbox calls-box) 1) (error 'pending "PENDING-BOOM"))))
  (mdl-apply "INT-LEVEL" 20)
  (mdl-emit-event! name '(1))
  (mdl-emit-event! name '(2))
  (check-exn #rx"PENDING-BOOM" (lambda () (mdl-apply "INT-LEVEL" 0)))
  (check-equal? (unbox calls-box) 1)
  (check-equal? (mdl-apply "INT-LEVEL") 0))

(scenario "ERRET delivers pending occurrences above the resumed level"
  (define high (box 0))
  (leave-pending! "HIGH" 10 high)
  (mdl-apply "HANDLER" (mdl-apply "EVENT" "ERROR" 8)
             (lambda (frame . args) (mdl-apply "ERRET" 1 frame)))
  (check-equal? (mdl-apply "ERROR" (mdl-atom "PROBE")) 1)
  (check-equal? (level) 8)
  (check-equal? (unbox high) 2)
  (mdl-apply "INT-LEVEL" 0)
  (check-equal? (unbox high) 2))

(scenario "ERRET keeps pending occurrences at or below the resumed level"
  (define low (box 0))
  (leave-pending! "LOW" 8 low)
  (mdl-apply "HANDLER" (mdl-apply "EVENT" "ERROR" 9)
             (lambda (frame . args)
               (mdl-apply "INT-LEVEL" 8)
               (mdl-apply "ERRET" 1 frame)))
  (check-equal? (mdl-apply "ERROR" (mdl-atom "PROBE")) 1)
  (check-equal? (level) 8)
  (check-equal? (unbox low) 1)
  (check-equal? (mdl-apply "INT-LEVEL" 0) 8)
  (check-equal? (unbox low) 2))

;; Nested ERROR and ERRET: the outer handler lowers the level so a second
;; ERROR is handled; the inner ERRET at level 8 resumes the inner ERROR, and
;; the outer handler continues at level 8 (ERRET keeps the current level).
(scenario "nested ERROR with inner ERRET continues the outer handler at 8"
  (define outer-level-after-inner #f)
  (define inner-result #f)
  (mdl-apply "HANDLER" (mdl-apply "EVENT" "ERROR" 8)
             (lambda (frame tag)
               (cond
                 [(eq? tag (mdl-atom "INNER")) (mdl-apply "ERRET" 5 frame)]
                 [else
                  (mdl-apply "INT-LEVEL" 0)
                  (set! inner-result (mdl-apply "ERROR" (mdl-atom "INNER")))
                  (set! outer-level-after-inner (level))
                  (mdl-apply "ERRET" 6 frame)])))
  (check-equal? (mdl-apply "ERROR" (mdl-atom "OUTER")) 6)
  (check-equal? inner-result 5)
  (check-equal? outer-level-after-inner 8)
  (check-equal? (level) 8))
