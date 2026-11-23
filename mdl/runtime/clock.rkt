#lang racket/base
;; Session-owned host clock for GETTIMEDATE's "now" read (issue #135,
;; ADR-0052). A clock is a host dependency stored in a session's atom space;
;; nothing here is process-global, and nothing here touches Racket monotonic
;; time, timeouts, scheduling or CPU time.
(provide mdl-clock? make-mdl-clock make-fixed-mdl-clock real-mdl-clock
         mdl-clock-now mdl-time-zone?)

;; read: host thunk returning (values epoch-seconds microseconds).
(struct mdl-clock (read))

(define fix-min (- (expt 2 35)))
(define fix-max (sub1 (expt 2 35)))

(define (valid-seconds? v) (and (exact-integer? v) (<= fix-min v fix-max)))
(define (valid-micros? v) (and (exact-integer? v) (<= 0 v 999999)))

(define (make-mdl-clock thunk)
  (unless (and (procedure? thunk) (procedure-arity-includes? thunk 0))
    (raise-argument-error 'make-mdl-clock "(-> (values exact-integer? exact-integer?))" thunk))
  (mdl-clock thunk))

;; A constant instant. It never advances: every read returns the same
;; values, matching the reference capture shim (scripts/reference/fixed_time.c
;; on PR #131), whose wall-clock calls return MDL_FIXED_EPOCH with zero
;; microseconds on every call.
(define (make-fixed-mdl-clock seconds #:micros [micros 0])
  (unless (valid-seconds? seconds)
    (raise-argument-error 'make-fixed-mdl-clock "signed 36-bit exact integer seconds" seconds))
  (unless (valid-micros? micros)
    (raise-argument-error 'make-fixed-mdl-clock "exact integer microseconds in 0..999999" micros))
  (mdl-clock (lambda () (values seconds micros))))

;; The host wall clock, read exactly as GETTIMEDATE did before issue #135.
(define real-mdl-clock
  (mdl-clock
   (lambda ()
     (define now (/ (current-inexact-milliseconds) 1000.0))
     (define whole (inexact->exact (floor now)))
     (values whole (min 999999 (max 0 (inexact->exact (round (* 1000000 (- now whole))))))))))

;; One validated read. An invalid read is a strict error, never a fallback.
(define (mdl-clock-now clock)
  (define results (call-with-values (mdl-clock-read clock) list))
  (unless (and (= (length results) 2)
               (valid-seconds? (car results))
               (valid-micros? (cadr results)))
    (error 'mdl-gettimedate "session clock returned an invalid time: ~e" results))
  (values (car results) (cadr results)))

;; The supported session zones: exactly host local time and UTC.
(define (mdl-time-zone? v) (and (memq v '(local utc)) #t))
