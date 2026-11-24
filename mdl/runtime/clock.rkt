#lang racket/base
;; Session-owned host clock for GETTIMEDATE's "now" read (issue #135,
;; ADR-0052). A clock is a host dependency stored in a session's atom space;
;; nothing here is process-global, and nothing here touches Racket monotonic
;; time, timeouts, scheduling or CPU time.
(provide mdl-clock? make-mdl-clock make-fixed-mdl-clock real-mdl-clock
         mdl-clock-now mdl-time-zone? mdl-clock-live?
         ;; ADR-0061 replay modes (host-only)
         make-recording-mdl-clock make-replaying-mdl-clock make-resumed-mdl-clock
         mdl-clock-mode mdl-clock-observations mdl-clock-finish-replay!
         (struct-out clock-observation)
         (struct-out exn:fail:mdl-clock-replay))

;; read: host thunk returning (values epoch-seconds microseconds).
;; declared-live?: whether a plain clock follows real time (M4 S9, issue #169): only a
;; live clock makes SLEEP wait. Logging clocks decide by mode instead (see
;; mdl-clock-live?), so their field is #f.
(struct mdl-clock (read declared-live?))

(define fix-min (- (expt 2 35)))
(define fix-max (sub1 (expt 2 35)))

(define (valid-seconds? v) (and (exact-integer? v) (<= fix-min v fix-max)))
(define (valid-micros? v) (and (exact-integer? v) (<= 0 v 999999)))

;; A host-supplied clock is not known to follow real time (tests use
;; advancing fake clocks), so it is non-live unless the host says #:live? #t.
(define (make-mdl-clock thunk #:live? [live? #f])
  (unless (and (procedure? thunk) (procedure-arity-includes? thunk 0))
    (raise-argument-error 'make-mdl-clock "(-> (values exact-integer? exact-integer?))" thunk))
  (unless (boolean? live?)
    (raise-argument-error 'make-mdl-clock "boolean?" live?))
  (mdl-clock thunk live?))

;; A constant instant. It never advances: every read returns the same
;; values, matching the reference capture shim (scripts/reference/fixed_time.c
;; on PR #131), whose wall-clock calls return MDL_FIXED_EPOCH with zero
;; microseconds on every call.
(define (make-fixed-mdl-clock seconds #:micros [micros 0])
  (unless (valid-seconds? seconds)
    (raise-argument-error 'make-fixed-mdl-clock "signed 36-bit exact integer seconds" seconds))
  (unless (valid-micros? micros)
    (raise-argument-error 'make-fixed-mdl-clock "exact integer microseconds in 0..999999" micros))
  (mdl-clock (lambda () (values seconds micros)) #f))

;; The host wall clock, read exactly as GETTIMEDATE did before issue #135.
(define real-mdl-clock
  (mdl-clock
   (lambda ()
     (define now (/ (current-inexact-milliseconds) 1000.0))
     (define whole (inexact->exact (floor now)))
     (values whole (min 999999 (max 0 (inexact->exact (round (* 1000000 (- now whole))))))))
   #t))

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

;; --- ADR-0061: recording, replaying and resumed clocks --------------------------
;; One observation: a validated (seconds, micros) read and the input-turn index
;; the host's turn thunk reported at that read.
(struct clock-observation (seconds micros turn) #:transparent)
(struct exn:fail:mdl-clock-replay exn:fail ())

(define (replay-error fmt . args)
  (raise (exn:fail:mdl-clock-replay (apply format (string-append "mdl-clock replay: " fmt) args)
                                    (current-continuation-marks))))

(define (valid-observation? o)
  (and (clock-observation? o)
       (valid-seconds? (clock-observation-seconds o))
       (valid-micros? (clock-observation-micros o))
       (exact-nonnegative-integer? (clock-observation-turn o))))

;; State of a logging clock. mode: 'recording, 'replaying or 'resumed.
;; log: every observation served, newest first. pending: replay observations
;; not yet served, oldest first; served: how many replay observations were
;; served. source: the recorded clock ('recording) or the wall clock
;; ('resumed); base-micros/wall-start-micros: the resumed clock's anchors.
(struct log-state ([mode #:mutable] [log #:mutable] [pending #:mutable] [served #:mutable]
                   turn [source #:mutable] [base-micros #:mutable]
                   [wall-start-micros #:mutable]
                   ;; resumed: the last instant served; never gone below
                   [last-micros #:mutable]))
(struct logging-clock mdl-clock (state))

(define (check-turn-thunk who turn)
  (unless (and (procedure? turn) (procedure-arity-includes? turn 0))
    (raise-argument-error who "(-> exact-nonnegative-integer?)" turn)))
(define (current-turn st)
  (define t ((log-state-turn st)))
  (unless (exact-nonnegative-integer? t)
    (error 'mdl-clock "turn thunk returned ~e, not an exact nonnegative integer" t))
  t)
(define (total-micros seconds micros) (+ (* seconds 1000000) micros))
(define (read-micros clock)
  (call-with-values (lambda () (mdl-clock-now clock)) total-micros))

(define (log! st seconds micros)
  (set-log-state-log! st (cons (clock-observation seconds micros (current-turn st))
                               (log-state-log st)))
  (values seconds micros))

(define (resumed-read st)
  (define elapsed (max 0 (- (read-micros (log-state-source st)) (log-state-wall-start-micros st))))
  ;; Monotonic (review L3): a wall clock that regresses after advancing
  ;; holds the live time instead of taking it backwards.
  (define now (max (log-state-last-micros st) (+ (log-state-base-micros st) elapsed)))
  (set-log-state-last-micros! st now)
  (define seconds (floor (/ now 1000000)))
  (log! st seconds (- now (* seconds 1000000))))

(define (state-read st)
  (case (log-state-mode st)
    [(recording)
     (define-values (seconds micros) (mdl-clock-now (log-state-source st)))
     (log! st seconds micros)]
    [(replaying)
     (define pending (log-state-pending st))
     (define turn (current-turn st))
     (when (null? pending)
       (replay-error "extra clock read at turn ~a: all ~a recorded observations were already served"
                     turn (log-state-served st)))
     (define o (car pending))
     (unless (= turn (clock-observation-turn o))
       (replay-error "clock read order diverged: observation ~a belongs to turn ~a but was read at turn ~a"
                     (log-state-served st) (clock-observation-turn o) turn))
     (set-log-state-pending! st (cdr pending))
     (set-log-state-served! st (add1 (log-state-served st)))
     (log! st (clock-observation-seconds o) (clock-observation-micros o))]
    [(resumed) (resumed-read st)]))

(define (make-logging-clock st) (logging-clock (lambda () (state-read st)) #f st))

;; Logs every read of SOURCE, in order, with the turn index.
(define (make-recording-mdl-clock source #:turn turn)
  (unless (mdl-clock? source)
    (raise-argument-error 'make-recording-mdl-clock "mdl-clock?" source))
  (check-turn-thunk 'make-recording-mdl-clock turn)
  (make-logging-clock (log-state 'recording '() '() 0 turn source #f #f #f)))

;; Serves OBSERVATIONS in order; strict on extra reads and order divergence.
(define (make-replaying-mdl-clock observations #:turn turn)
  (unless (and (list? observations) (andmap valid-observation? observations))
    (raise-argument-error 'make-replaying-mdl-clock "(listof valid clock-observation?)"
                          observations))
  (check-turn-thunk 'make-replaying-mdl-clock turn)
  (make-logging-clock (log-state 'replaying '() observations 0 turn #f #f #f #f)))

;; live = base + max(0, wall_now - wall_at_creation); logged like the others.
(define (make-resumed-mdl-clock base-seconds base-micros wall #:turn turn)
  (unless (valid-seconds? base-seconds)
    (raise-argument-error 'make-resumed-mdl-clock "signed 36-bit exact integer seconds" base-seconds))
  (unless (valid-micros? base-micros)
    (raise-argument-error 'make-resumed-mdl-clock "exact integer microseconds in 0..999999" base-micros))
  (unless (mdl-clock? wall)
    (raise-argument-error 'make-resumed-mdl-clock "mdl-clock?" wall))
  (check-turn-thunk 'make-resumed-mdl-clock turn)
  (define st (log-state 'resumed '() '() 0 turn wall #f #f #f))
  (resume! st (total-micros base-seconds base-micros) wall)
  (make-logging-clock st))

(define (resume! st base wall)
  (set-log-state-source! st wall)
  (set-log-state-base-micros! st base)
  (set-log-state-last-micros! st base)
  (set-log-state-wall-start-micros! st (read-micros wall))
  (set-log-state-mode! st 'resumed))

;; End of replay: every observation must have been served (else a missing
;; read); the clock then resumes from the last observation on WALL.
(define (mdl-clock-finish-replay! clock #:wall wall)
  (unless (logging-clock? clock)
    (raise-argument-error 'mdl-clock-finish-replay! "replaying mdl-clock" clock))
  (unless (mdl-clock? wall)
    (raise-argument-error 'mdl-clock-finish-replay! "mdl-clock?" wall))
  (define st (logging-clock-state clock))
  (unless (eq? (log-state-mode st) 'replaying)
    (error 'mdl-clock-finish-replay! "the clock is not replaying (mode ~a)" (log-state-mode st)))
  (define left (length (log-state-pending st)))
  (unless (zero? left)
    (replay-error "missing clock read: ~a observation~a of ~a left unread at the end of replay"
                  left (if (= left 1) "" "s") (+ left (log-state-served st))))
  (when (null? (log-state-log st))
    (error 'mdl-clock-finish-replay! "no observation to resume from"))
  (define last (car (log-state-log st)))
  (resume! st (total-micros (clock-observation-seconds last) (clock-observation-micros last)) wall))

(define (mdl-clock-mode clock)
  (unless (mdl-clock? clock) (raise-argument-error 'mdl-clock-mode "mdl-clock?" clock))
  (if (logging-clock? clock) (log-state-mode (logging-clock-state clock)) 'plain))

;; Every observation served so far, oldest first (a fresh list), or #f for a
;; clock that does not log (real, fixed, custom).
(define (mdl-clock-observations clock)
  (unless (mdl-clock? clock) (raise-argument-error 'mdl-clock-observations "mdl-clock?" clock))
  (and (logging-clock? clock) (reverse (log-state-log (logging-clock-state clock)))))

;; M4 S9 (issue #169, maintainer decision 2026-11-24): does this clock follow
;; real time, so that SLEEP waits for real? Reads no time and logs nothing.
;; real: yes; fixed: no; custom: as declared (#:live?, default no);
;; recording: as its source; replaying: no; resumed: yes. Decided at each
;; call, so a replaying clock becomes live when replay finishes and resumes.
(define (mdl-clock-live? clock)
  (unless (mdl-clock? clock) (raise-argument-error 'mdl-clock-live? "mdl-clock?" clock))
  (if (logging-clock? clock)
      (let ([st (logging-clock-state clock)])
        (case (log-state-mode st)
          [(recording) (mdl-clock-live? (log-state-source st))]
          [(replaying) #f]
          [(resumed) #t]))
      (mdl-clock-declared-live? clock)))
