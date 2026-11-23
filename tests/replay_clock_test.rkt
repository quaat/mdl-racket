#lang racket/base
;; ADR-0061 / SEMANTICS "M4 WP4": the recording, replaying and resumed session
;; clock modes, the READSTRING input observer and the host-only RANDOM draw
;; count. Smoke suite: needs no upstream source.
(require rackunit racket/file racket/list
         "../mdl/loader.rkt" "../mdl/runtime/clock.rkt" "../mdl/runtime/core.rkt"
         "../mdl/runtime/random36.rkt")

;; Plain `racket` must exit non-zero on any failed check.
(current-check-handler (lambda (e) (raise e)))

(define (read-now clock) (call-with-values (lambda () (mdl-clock-now clock)) list))
(define (obs->list o)
  (list (clock-observation-seconds o) (clock-observation-micros o) (clock-observation-turn o)))
;; A deterministic source that advances by STEP microseconds per read.
(define (stepping-clock start-seconds step-micros)
  (define n 0)
  (make-mdl-clock
   (lambda ()
     (define total (+ (* start-seconds 1000000) (* n step-micros)))
     (set! n (add1 n))
     (values (quotient total 1000000) (remainder total 1000000)))))

;; --- recording ---------------------------------------------------------------
(let ()
  (define turn 0)
  (define rec (make-recording-mdl-clock (stepping-clock 250776000 400000)
                                        #:turn (lambda () turn)))
  (check-true (mdl-clock? rec))
  (check-equal? (mdl-clock-mode rec) 'recording)
  (check-equal? (read-now rec) '(250776000 0))
  (check-equal? (read-now rec) '(250776000 400000))
  (set! turn 3)
  (check-equal? (read-now rec) '(250776000 800000))
  (check-equal? (read-now rec) '(250776001 200000))
  (check-equal? (map obs->list (mdl-clock-observations rec))
                '((250776000 0 0) (250776000 400000 0) (250776000 800000 3) (250776001 200000 3)))
  ;; the log is a detached copy
  (check-equal? (length (mdl-clock-observations rec)) 4)
  ;; an invalid source read is still a strict error, and nothing is logged
  (define bad (make-recording-mdl-clock (make-mdl-clock (lambda () (values 1 -5)))
                                        #:turn (lambda () 0)))
  (check-exn #rx"invalid time" (lambda () (mdl-clock-now bad)))
  (check-equal? (mdl-clock-observations bad) '()))

;; --- replaying: exact service, extra read, order divergence, missing read -----
(define (obs s m t) (clock-observation s m t))
(let ()
  (define turn 0)
  (define log (list (obs 10 1 0) (obs 10 2 0) (obs 11 0 2)))
  (define rp (make-replaying-mdl-clock log #:turn (lambda () turn)))
  (check-equal? (mdl-clock-mode rp) 'replaying)
  (check-equal? (read-now rp) '(10 1))
  (check-equal? (read-now rp) '(10 2))
  ;; observation 2 belongs to turn 2: a read at turn 1 is an order divergence
  (set! turn 1)
  (check-exn (lambda (e) (and (exn:fail:mdl-clock-replay? e)
                              (regexp-match? #rx"order diverged" (exn-message e))))
             (lambda () (mdl-clock-now rp)))
  (set! turn 2)
  (check-equal? (read-now rp) '(11 0))
  ;; extra read after the log is exhausted
  (check-exn (lambda (e) (and (exn:fail:mdl-clock-replay? e)
                              (regexp-match? #rx"extra clock read" (exn-message e))))
             (lambda () (mdl-clock-now rp)))
  (check-equal? (map obs->list (mdl-clock-observations rp)) '((10 1 0) (10 2 0) (11 0 2))))
(let ()
  ;; missing read: observations left unread at the end of replay
  (define rp (make-replaying-mdl-clock (list (obs 10 1 0) (obs 10 2 0)) #:turn (lambda () 0)))
  (check-equal? (read-now rp) '(10 1))
  (check-exn (lambda (e) (and (exn:fail:mdl-clock-replay? e)
                              (regexp-match? #rx"missing clock read: 1 observation" (exn-message e))))
             (lambda () (mdl-clock-finish-replay! rp #:wall (make-fixed-mdl-clock 0))))
  ;; the failed finish leaves the clock replaying
  (check-equal? (mdl-clock-mode rp) 'replaying))
(let ()
  ;; a replay log must be a list of valid observations
  (check-exn exn:fail:contract? (lambda () (make-replaying-mdl-clock '((1 2 3)) #:turn (lambda () 0))))
  (check-exn exn:fail:contract? (lambda () (make-replaying-mdl-clock (list (obs 1 1000000 0))
                                                                      #:turn (lambda () 0))))
  ;; a replay with no observations cannot resume: there is no base instant
  (define empty (make-replaying-mdl-clock '() #:turn (lambda () 0)))
  (check-exn #rx"no observation to resume from"
             (lambda () (mdl-clock-finish-replay! empty #:wall (make-fixed-mdl-clock 0)))))

;; --- replay -> resumed --------------------------------------------------------
(let ()
  (define turn 0)
  (define rp (make-replaying-mdl-clock (list (obs 250776000 0 0) (obs 250776005 250000 4))
                                       #:turn (lambda () turn)))
  (read-now rp)
  (set! turn 4)
  (read-now rp)
  ;; the wall clock is far in the future (downtime) and then advances by 1.5 s
  ;; per read; only the elapsed wall time since the resume reaches the game.
  (define wall (stepping-clock 1900000000 1500000))
  (mdl-clock-finish-replay! rp #:wall wall)
  (check-equal? (mdl-clock-mode rp) 'resumed)
  (set! turn 5)
  (check-equal? (read-now rp) '(250776006 750000))
  (check-equal? (read-now rp) '(250776008 250000))
  ;; the log keeps growing, so a restored session can be saved again
  (check-equal? (map obs->list (mdl-clock-observations rp))
                '((250776000 0 0) (250776005 250000 4) (250776006 750000 5) (250776008 250000 5)))
  ;; finishing twice is an error
  (check-exn #rx"not replaying" (lambda () (mdl-clock-finish-replay! rp #:wall wall))))
(let ()
  ;; the same continuation under a different absolute wall clock
  (define (continuation wall-start)
    (define c (make-resumed-mdl-clock 250776000 0 (stepping-clock wall-start 2000000)
                                      #:turn (lambda () 7)))
    (for/list ([_ 3]) (read-now c)))
  (check-equal? (continuation 1700000000) (continuation 2000000000))
  (check-equal? (continuation 1700000000) '((250776002 0) (250776004 0) (250776006 0)))
  ;; a wall clock that goes backwards contributes no elapsed time
  (define back-n 0)
  (define backwards (make-mdl-clock (lambda () (set! back-n (add1 back-n))
                                      (values (- 2000000000 (* 10 back-n)) 0))))
  (define c (make-resumed-mdl-clock 100 5 backwards #:turn (lambda () 0)))
  (check-equal? (read-now c) '(100 5))
  (check-equal? (read-now c) '(100 5))
  (check-exn exn:fail:contract? (lambda () (make-resumed-mdl-clock 100 2000000 backwards
                                                                    #:turn (lambda () 0)))))

;; --- the real and fixed clocks are unchanged -----------------------------------
(check-equal? (mdl-clock-mode (make-fixed-mdl-clock 5)) 'plain)
(check-equal? (mdl-clock-mode real-mdl-clock) 'plain)
(check-equal? (mdl-clock-observations (make-fixed-mdl-clock 5)) #f)

;; --- READSTRING observer and the RANDOM draw count -------------------------------
(define root (make-temporary-file "mdl-replay-clock~a" 'directory))
(dynamic-wind
 void
 (lambda ()
   (define events '())
   (define (observer kind info)
     (set! events (cons (cons kind (if (eq? kind 'enter)
                                       (hash-ref info 'stops)
                                       (list (hash-ref info 'raw) (hash-ref info 'reason)
                                             (hash-ref info 'count))))
                        events)))
   (define in (open-input-string "ab!cd\nlonger-than-four\nx!"))
   (define s (make-mdl-session root #:input-port in #:output-port (open-output-string)
                               #:input-observer observer))
   (call-with-output-file (build-path root "rd.mud") #:exists 'replace
     (lambda (o)
       (write-string "<SETG B <ISTRING 4>>\n<SETG L <ISTRING 20>>\n" o)
       (write-string "<DEFINE RD (BUF) <READSTRING .BUF ,INCHAN <STRING <ASCII 10>>>>\n" o)))
   (check-equal? (hash-ref (mdl-session-load! s "rd.mud") 'status) "PASS")
   ;; `!c` is an escape pair: one unit; the stop character is consumed and logged
   (check-equal? (mdl-session-call s "RD" (mdl-session-global s "L")) 4)
   ;; a full 4-character buffer: the rest of the line stays unread
   (check-equal? (mdl-session-call s "RD" (mdl-session-global s "B")) 4)
   (check-equal? (mdl-session-call s "RD" (mdl-session-global s "L")) 12)
   ;; `!` then end of input
   (check-equal? (mdl-session-call s "RD" (mdl-session-global s "L")) 2)
   (check-equal? (reverse events)
                 (list '(enter #\newline) '(complete "ab!cd\n" stop 4)
                       '(enter #\newline) '(complete "long" full 4)
                       '(enter #\newline) '(complete "er-than-four\n" stop 12)
                       '(enter #\newline) '(complete "x!" eof 2)))
   ;; once the end-of-input flag is set, READSTRING raises before 'enter
   (set! events '())
   (check-exn exn:fail:mdl-input-exhausted?
              (lambda () (mdl-session-call s "RD" (mdl-session-global s "L"))))
   (check-equal? events '())
   ;; an observer must accept two arguments
   (check-exn exn:fail:contract? (lambda () (make-mdl-session root #:input-observer (lambda (x) x))))

   ;; RANDOM draws: counted host-side; never changes a RANDOM result
   (define r (make-mdl-session root))
   (define plain (make-mdl-session root))
   (check-equal? (random36-state-draws (mdl-session-random-snapshot r)) 0)
   (define seq (list (mdl-session-call r "RANDOM") (mdl-session-call r "RANDOM" 1 2)
                     (mdl-session-call r "RANDOM")))
   (check-equal? seq (list -17002352646 -34359738368 -34359738368))
   (check-equal? (random36-state-draws (mdl-session-random-snapshot r)) 3)
   ;; the snapshot is detached: stepping it neither consumes nor counts in r
   (define snap (mdl-session-random-snapshot r))
   (random36-next! snap)
   (check-equal? (random36-state-draws snap) 4)
   (check-equal? (random36-state-draws (mdl-session-random-snapshot r)) 3)
   ;; same values as a session whose count is never read
   (check-equal? (list (mdl-session-call plain "RANDOM") (mdl-session-call plain "RANDOM" 1 2)
                       (mdl-session-call plain "RANDOM"))
                 seq))
 (lambda () (delete-directory/files root)))

(printf "replay clock modes, READSTRING observer and draw count: ok\n")
