#lang racket/base
;; Issue #135 part 1 (ADR-0052): the session-owned host clock and time zone.
;; Smoke suite: needs no upstream source. See SEMANTICS "M3 session-owned
;; host clock and time zone".
(require rackunit racket/file racket/date
         "../mdl/loader.rkt" "../mdl/runtime/core.rkt" "../mdl/runtime/random36.rkt")

(define root (make-temporary-file "mdl-clock-test~a" 'directory))

(define (now-vector session . args)
  (define result (apply mdl-session-call session "GETTIMEDATE" args))
  (for/list ([i (in-range 1 8)]) (mdl-nth result i)))
(define (T session) (mdl-session-atom session "T"))
(define no (mdl-false '()))
;; A FIX UVECTOR built in the session itself (UTYPE atoms are per-session).
(define (uv session . items) (apply mdl-session-call session "UVECTOR" items))
(define (date->fields d micros)
  (list (date-second d) (date-minute d) (date-hour d)
        (date-day d) (date-month d) (date-year d) micros))

(dynamic-wind
 void
 (lambda ()
   ;; --- fixed clock: the reference golden instant, 1977-12-12 12:00:00 UTC ---
   (define fixed (make-fixed-mdl-clock 250776000))
   (check-true (mdl-clock? fixed))
   (check-true (mdl-clock? real-mdl-clock))
   (define s (make-mdl-session root #:clock fixed #:time-zone 'utc))
   (define golden '(0 0 12 12 12 1977 0))
   (check-equal? (now-vector s) golden)
   (check-equal? (now-vector s no) golden)              ; FALSE first argument = now
   (check-equal? (now-vector s no (T s)) golden)        ; explicit UTC
   ;; A fixed clock is a constant instant: it never advances.
   (sleep 0.01)
   (check-equal? (now-vector s) golden)
   ;; Microseconds are carried exactly.
   (define s-micro (make-mdl-session root #:clock (make-fixed-mdl-clock 250776000 #:micros 750000)
                                     #:time-zone 'utc))
   (check-equal? (now-vector s-micro) '(0 0 12 12 12 1977 750000))

   ;; --- two sessions, distinct fixed clocks, interleaved in one process ---
   (define a (make-mdl-session root #:clock (make-fixed-mdl-clock 250776000) #:time-zone 'utc))
   (define b (make-mdl-session root #:clock (make-fixed-mdl-clock 1000000000 #:micros 42)
                               #:time-zone 'utc))
   (define b-fields '(40 46 1 9 9 2001 42))
   (for ([_ (in-range 3)])
     (check-equal? (now-vector a) golden)
     (check-equal? (now-vector b) b-fields))
   (check-equal? (now-vector s) golden)

   ;; --- default clock: still the real wall clock, host local zone ---
   (define r (make-mdl-session root))
   (define before (current-seconds))
   (define fields (now-vector r no (T r)))
   (define after (current-seconds))
   (define seen (find-seconds (list-ref fields 0) (list-ref fields 1) (list-ref fields 2)
                              (list-ref fields 3) (list-ref fields 4) (list-ref fields 5) #f))
   (check-true (<= (- before 1) seen (+ after 1)) (format "~a not in [~a,~a]" seen before after))
   (check-true (<= 0 (list-ref fields 6) 999999))
   ;; Default zone is host local: a local "now" and a UTC "now" agree with
   ;; Racket's own decomposition of the same second (allowing a tick).
   (define local-fields (now-vector r))
   (define local-seen (find-seconds (list-ref local-fields 0) (list-ref local-fields 1)
                                    (list-ref local-fields 2) (list-ref local-fields 3)
                                    (list-ref local-fields 4) (list-ref local-fields 5) #t))
   (check-true (<= (- before 1) local-seen (+ (current-seconds) 1)))

   ;; --- explicit FIX / UVECTOR timestamps ignore the session clock ---
   (check-equal? (now-vector s 0 (T s)) '(0 0 0 1 1 1970 0))
   (check-equal? (now-vector a 86400 (T a)) '(0 0 0 2 1 1970 0))
   (check-equal? (now-vector b (uv b 0 123456) (T b)) '(0 0 0 1 1 1970 123456))
   (check-equal? (now-vector s (uv s 250776000 0)) golden)
   ;; Default ('local) zone: explicit timestamps decompose exactly as before.
   (check-equal? (now-vector r 250776000) (date->fields (seconds->date 250776000 #t) 0))
   (check-equal? (now-vector r (uv r 250776000 9)) (date->fields (seconds->date 250776000 #t) 9))
   (check-equal? (now-vector r 250776000 (T r)) golden)

   ;; --- zone handling: same clock, 'utc vs 'local ---
   (define l (make-mdl-session root #:clock (make-fixed-mdl-clock 250776000)))   ; default 'local
   (check-equal? (now-vector l) (date->fields (seconds->date 250776000 #t) 0))
   (check-equal? (now-vector l no (T l)) golden)              ; UTC flag still wins
   (check-equal? (now-vector s) golden)                       ; 'utc session

   ;; --- bad arguments are rejected ---
   (for ([bad (list 250776000 "now" #f (lambda () (values 1 2)) 'utc)])
     (check-exn exn:fail:contract? (lambda () (make-mdl-session root #:clock bad)) (format "~s" bad)))
   (for ([bad (list 'est "UTC" 'UTC 3600 #f)])
     (check-exn exn:fail:contract? (lambda () (make-mdl-session root #:time-zone bad)) (format "~s" bad)))
   (check-exn exn:fail:contract? (lambda () (make-fixed-mdl-clock 1.5)))
   (check-exn exn:fail:contract? (lambda () (make-fixed-mdl-clock (expt 2 35))))
   (check-exn exn:fail:contract? (lambda () (make-fixed-mdl-clock 0 #:micros 1000000)))
   (check-exn exn:fail:contract? (lambda () (make-fixed-mdl-clock 0 #:micros -1)))
   (check-exn exn:fail:contract? (lambda () (make-mdl-clock 5)))
   (check-exn exn:fail:contract? (lambda () (make-mdl-clock (lambda (x) x))))
   ;; A custom clock is read once per "now" call and validated strictly.
   (define reads 0)
   (define counting (make-mdl-clock (lambda () (set! reads (add1 reads)) (values 0 7))))
   (define c (make-mdl-session root #:clock counting #:time-zone 'utc))
   (check-equal? reads 0)
   (check-equal? (now-vector c) '(0 0 0 1 1 1970 7))
   (check-equal? reads 1)
   (check-equal? (now-vector c 86400 (T c)) '(0 0 0 2 1 1970 0))   ; explicit: no read
   (check-equal? reads 1)
   (for ([bad-read (list (lambda () (values 1.5 0)) (lambda () (values 0 1000000))
                         (lambda () (values 0 -1)) (lambda () 0)
                         (lambda () (values (expt 2 35) 0)))])
     (define bad (make-mdl-session root #:clock (make-mdl-clock bad-read) #:time-zone 'utc))
     (check-exn #rx"clock" (lambda () (mdl-session-call bad "GETTIMEDATE"))))

   ;; --- host-only RANDOM observation does not consume the sequence ---
   (define g (make-mdl-session root #:clock fixed #:time-zone 'utc))
   (mdl-session-call g "RANDOM" 12345)
   (define snap (mdl-session-random-snapshot g))
   (define predicted (for/list ([_ (in-range 6)]) (random36-next! snap)))
   (define actual (for/list ([_ (in-range 6)]) (mdl-session-call g "RANDOM")))
   (check-equal? actual predicted)
   ;; A second snapshot is detached from the first and from the session.
   (define snap2 (mdl-session-random-snapshot g))
   (random36-next! snap2)
   (check-equal? (random36-state-words (mdl-session-random-snapshot g))
                 (random36-state-words (mdl-session-random-snapshot g))))
 (lambda () (delete-directory/files root)))
