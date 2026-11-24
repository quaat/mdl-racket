#lang racket/base
;; M4 S9 (issues #168, #169, #170): the IMAGE, SLEEP and TIME SUBRs.
;; Contract: docs/SEMANTICS.md "M4: IMAGE, SLEEP, TIME (#168–#170)"; reference
;; observations docs/evidence/M4/P0PRIMS-REFERENCE.md (p0prims-probe.json).
;; Every SLEEP test that could wait replaces the host sleeper with a recording
;; fake, except the two that exercise the real one (a one-second wait, and a
;; long wait interrupted by a Racket break).
(require rackunit racket/list
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt"
         "../mdl/runtime/clock.rkt")

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define-syntax-rule (check* form) (test-case (format "~s" 'form) form))

;; A fresh context whose OUTCHAN writes to OUT, on CLOCK.
(define (fresh-context #:clock [clock (make-fixed-mdl-clock 250776000)]
                       #:out [out (open-output-bytes)])
  (make-mdl-context #:output-port out #:input-port (open-input-string "") #:clock clock))
(define (run-in ctx source)
  (call-with-mdl-context
   ctx
   (lambda ()
     (parameterize ([current-namespace ns])
       (for/fold ([value #f]) ([expr (in-list (compile-program (parse-mdl source)))])
         (eval expr))))))
;; Run SOURCE in a fresh fixed-clock context; returns (values result bytes-written).
(define (run/out source)
  (define out (open-output-bytes))
  (define v (run-in (fresh-context #:out out) source))
  (values v (get-output-bytes out)))
(define (run source) (let-values ([(v _) (run/out source)]) v))
(define (name v) (mdl-atom-pname v))
;; A strict failure that writes nothing.
(define (check-refused source rx)
  (define out (open-output-bytes))
  (define ctx (fresh-context #:out out))
  (check-exn rx (lambda () (run-in ctx source)) source)
  (check-equal? (get-output-bytes out) #"" source))

;; A recording fake sleeper: every call's argument, in order.
(define sleeps '())
(define (fake-sleeper seconds) (set! sleeps (cons seconds sleeps)))
(define-syntax-rule (with-fake-sleeper body ...)
  (begin (set! sleeps '())
         (parameterize ([current-mdl-sleeper fake-sleeper]) body ...)))

;; A clock that counts its reads (live or not).
(define (counting-clock #:live? [live? #f])
  (define reads 0)
  (values (make-mdl-clock (lambda () (set! reads (add1 reads)) (values 250776000 0))
                          #:live? live?)
          (lambda () reads)))

;; === IMAGE (#168) ==================================================================
(check* (let-values ([(v out) (run/out "<IMAGE 65>")])
          (check-equal? v 65) (check-equal? out #"A")))
(check* (let-values ([(v out) (run/out "<IMAGE 7>")])
          (check-equal? v 7) (check-equal? out #"\a")))
(check* (let-values ([(v out) (run/out "<TYPE <IMAGE 7>>")])
          (check-equal? (name v) "FIX") (check-equal? out #"\7")))
;; Control codes and DEL go out raw (probe image-controls), never ^X.
(check* (let-values ([(v out) (run/out "<IMAGE 0> <IMAGE 1> <IMAGE 10> <IMAGE 13> <IMAGE 27> <IMAGE 127>")])
          (check-equal? v 127) (check-equal? out (bytes 0 1 10 13 27 127))))
(check* (let-values ([(v out) (run/out "<IMAGE 66 .OUTCHAN>")])
          (check-equal? v 66) (check-equal? out #"B")))
(check* (let-values ([(v out) (run/out "<IMAGE 67 ,OUTCHAN>")])
          (check-equal? v 67) (check-equal? out #"C")))
(check* (check-equal? (name (run "<TYPE ,IMAGE>")) "SUBR"))
(check* (let-values ([(v out) (run/out "<APPLY ,IMAGE 68>")])
          (check-equal? v 68) (check-equal? out #"D")))
;; IMAGE and PRINC share the port, in order.
(check* (let-values ([(v out) (run/out "<PRINC \"a\"> <IMAGE 7> <PRINC \"b\">")])
          (check-equal? out #"a\ab")))
;; FWEEP (77act2.mud:53) with SLP 0, BOOM-ROOM's <FWEEP 7>: six BELs, no SLEEP
;; (probe image-fweep-no-sleep).
(define fweep "<DEFINE FWEEP (NUM \"OPTIONAL\" (SLP 0)) #DECL ((NUM SLP) FIX)
  <REPEAT ((N .NUM)) <AND <0? <SET N <- .N 1>>> <RETURN>> <IMAGE 7>
          <OR <0? .SLP> <SLEEP .SLP>>>>")
(check* (with-fake-sleeper
         (let-values ([(v out) (run/out (string-append fweep " <FWEEP 7>"))])
           (check-equal? (name v) "T") (check-equal? out (make-bytes 6 7))
           (check-equal? sleeps '()))))
;; Refusals: arity and TYPE (the reference's ERROR names), codes outside 0-127
;; (recorded deviation: the reference writes the code modulo 256), and non-PRINT
;; or non-CHANNEL channels (recorded deviations). Nothing is written.
(check* (check-refused "<IMAGE>" #rx"TOO-FEW-ARGUMENTS-SUPPLIED"))
(check* (check-refused "<IMAGE 65 .OUTCHAN 1>" #rx"TOO-MANY-ARGUMENTS-SUPPLIED"))
(for ([src '("<IMAGE \"A\">" "<IMAGE !\\A>" "<IMAGE 65.0>" "<IMAGE <>>" "<IMAGE A>")])
  (check* (check-refused src #rx"FIRST-ARG-WRONG-TYPE")))
(for ([src '("<IMAGE 128>" "<IMAGE 200>" "<IMAGE 255>" "<IMAGE 256>" "<IMAGE 321>" "<IMAGE -1>")])
  (check* (check-refused src #rx"0-127")))
(check* (check-refused "<IMAGE 65 .INCHAN>" #rx"requires an output channel"))
(check* (check-refused "<IMAGE 65 1>" #rx"non-channel"))
;; A port-less PRINT channel is the strict S13 error.
(check* (check-exn #rx"no host-supplied output port"
                   (lambda () (run-in (make-mdl-context) "<IMAGE 7>"))))

;; === SLEEP (#169) ==================================================================
;; Liveness of every clock mode.
(define (turn0) 0)
(check* (check-true (mdl-clock-live? real-mdl-clock)))
(check* (check-false (mdl-clock-live? (make-fixed-mdl-clock 250776000))))
(check* (check-false (mdl-clock-live? (make-mdl-clock (lambda () (values 0 0))))))
(check* (check-true (mdl-clock-live? (make-mdl-clock (lambda () (values 0 0)) #:live? #t))))
(check* (check-false (mdl-clock-live? (make-recording-mdl-clock (make-fixed-mdl-clock 0) #:turn turn0))))
(check* (check-true (mdl-clock-live? (make-recording-mdl-clock real-mdl-clock #:turn turn0))))
(check* (check-false (mdl-clock-live? (make-replaying-mdl-clock '() #:turn turn0))))
(check* (check-true (mdl-clock-live? (make-resumed-mdl-clock 0 0 (make-fixed-mdl-clock 0) #:turn turn0))))
(check* (check-exn exn:fail:contract? (lambda () (mdl-clock-live? 5))))
(check* (check-exn exn:fail:contract? (lambda () (make-mdl-clock (lambda () (values 0 0)) #:live? 'yes))))
;; A replaying clock is non-live while it replays and live once it resumes.
(check* (let ([c (make-replaying-mdl-clock (list (clock-observation 5 0 0)) #:turn turn0)])
          (check-false (mdl-clock-live? c))
          (mdl-clock-now c)
          (mdl-clock-finish-replay! c #:wall (make-fixed-mdl-clock 0))
          (check-true (mdl-clock-live? c))))

;; Non-live clocks: T at once, no sleeper call, no clock read.
(define (sleep-under clock source)
  (with-fake-sleeper (let ([v (run-in (fresh-context #:clock clock) source)])
                       (values v (reverse sleeps)))))
(check* (let-values ([(v s) (sleep-under (make-fixed-mdl-clock 250776000) "<SLEEP 1>")])
          (check-equal? (name v) "T") (check-equal? s '())))
(check* (let-values ([(v s) (sleep-under (make-fixed-mdl-clock 250776000) "<TYPE <SLEEP 0>>")])
          (check-equal? (name v) "ATOM") (check-equal? s '())))
(check* (let*-values ([(clock reads) (counting-clock)]
                      [(v s) (sleep-under clock "<SLEEP 1> <SLEEP 5>")])
          (check-equal? (name v) "T") (check-equal? s '()) (check-equal? (reads) 0)))
(check* (let*-values ([(src reads) (counting-clock)]
                      [(rec) (make-recording-mdl-clock src #:turn turn0)]
                      [(v s) (sleep-under rec "<SLEEP 1>")])
          (check-equal? (name v) "T") (check-equal? s '())
          (check-equal? (reads) 0) (check-equal? (mdl-clock-observations rec) '())))
(check* (let*-values ([(rep) (make-replaying-mdl-clock '() #:turn turn0)]
                      [(v s) (sleep-under rep "<SLEEP 1>")])
          ;; no extra read: a replaying clock with an empty log would raise on one
          (check-equal? (name v) "T") (check-equal? s '())
          (check-equal? (mdl-clock-observations rep) '())))
;; Live clocks: the sleeper gets exactly the requested seconds; still no read.
(check* (let*-values ([(clock reads) (counting-clock #:live? #t)]
                      [(v s) (sleep-under clock "<SLEEP 1> <SLEEP 0> <SLEEP 3>")])
          (check-equal? (name v) "T") (check-equal? s '(1 3)) (check-equal? (reads) 0)))
(check* (let-values ([(v s) (sleep-under real-mdl-clock "<SLEEP 2>")])
          (check-equal? (name v) "T") (check-equal? s '(2))))
(check* (let*-values ([(rec) (make-recording-mdl-clock real-mdl-clock #:turn turn0)]
                      [(v s) (sleep-under rec "<SLEEP 1>")])
          (check-equal? s '(1)) (check-equal? (mdl-clock-observations rec) '())))
(check* (let*-values ([(wall reads) (counting-clock)]
                      [(res) (make-resumed-mdl-clock 0 0 wall #:turn turn0)]
                      [(r0) (reads)]
                      [(v s) (sleep-under res "<SLEEP 1>")])
          (check-equal? s '(1)) (check-equal? (reads) r0)
          (check-equal? (mdl-clock-observations res) '())))
;; A buffered output port: written bytes stay pending until a flush (Racket
;; signals a flush as an empty write), then become visible. Returns the port
;; and a thunk giving the visible bytes.
(define (buffered-port)
  (define pending (open-output-bytes))
  (define visible (open-output-bytes))
  (values (make-output-port
           'buffered always-evt
           (lambda (bs start end non-block? breakable?)
             (if (= start end)
                 (write-bytes (get-output-bytes pending #t) visible)
                 (write-bytes bs pending start end))
             (- end start))
           void)
          (lambda () (get-output-bytes visible))))
;; FWEEP 4 1 (FLY-ME): three BELs and three one-second SLEEPs; under a live
;; clock each BEL is flushed (visible, not merely buffered) before its wait.
(check* (with-fake-sleeper
         (define-values (out visible) (buffered-port))
         (define seen '())
         (parameterize ([current-mdl-sleeper
                         (lambda (s) (set! seen (cons (visible) seen))
                                 (fake-sleeper s))])
           (define ctx (fresh-context #:out out #:clock (make-mdl-clock (lambda () (values 0 0))
                                                                         #:live? #t)))
           (check-equal? (name (run-in ctx (string-append fweep " <FWEEP 4 1>"))) "T")
           (check-equal? (reverse sleeps) '(1 1 1))
           (check-equal? (reverse seen) (list #"\a" #"\a\a" #"\a\a\a")))))
;; A port-less PRINT channel: <SLEEP 1> fails strictly (the flush cannot
;; resolve a port) in every clock mode, and never waits; <SLEEP 0> flushes
;; nothing and returns T.
(for ([clock (list (make-fixed-mdl-clock 0) real-mdl-clock)])
  (check* (with-fake-sleeper
           (check-exn #rx"PRINT CHANNEL has no host-supplied output port"
                      (lambda () (run-in (make-mdl-context #:clock clock) "<SLEEP 1>")))
           (check-equal? sleeps '())
           (check-equal? (name (run-in (make-mdl-context #:clock clock) "<SLEEP 0>")) "T"))))
(check* (let-values ([(v s) (sleep-under (make-fixed-mdl-clock 0) (string-append fweep " <FWEEP 4 1>"))])
          (check-equal? (name v) "T") (check-equal? s '())))
;; UNHANG is accepted (never consulted: no interrupt can arrive during SLEEP).
(check* (let-values ([(v s) (sleep-under (make-fixed-mdl-clock 0) "<SLEEP 0 T>")])
          (check-equal? (name v) "T")))
(check* (let-values ([(v s) (sleep-under real-mdl-clock "<SLEEP 1 <>>")])
          (check-equal? (name v) "T") (check-equal? s '(1))))
(check* (check-equal? (name (run "<TYPE ,SLEEP>")) "SUBR"))
(check* (with-fake-sleeper (check-equal? (name (run "<APPLY ,SLEEP 0>")) "T")))
;; Refusals, identical in every mode, and never a wait.
(define (check-sleep-refused source rx)
  (for ([clock (list (make-fixed-mdl-clock 0) real-mdl-clock)])
    (with-fake-sleeper
     (check-exn rx (lambda () (run-in (fresh-context #:clock clock) source)) source)
     (check-equal? sleeps '() source))))
(check* (check-sleep-refused "<SLEEP>" #rx"TOO-FEW-ARGUMENTS-SUPPLIED"))
(check* (check-sleep-refused "<SLEEP 0 T T>" #rx"TOO-MANY-ARGUMENTS-SUPPLIED"))
(check* (check-sleep-refused "<SLEEP -1>" #rx"ARGUMENT-OUT-OF-RANGE"))
(for ([src '("<SLEEP 0.5>" "<SLEEP 1.5>" "<SLEEP -0.5>" "<SLEEP \"1\">" "<SLEEP A>"
             "<SLEEP <>>" "<SLEEP !\\A>" "<SLEEP '(1)>")])
  (check* (check-sleep-refused src #rx"FIRST-ARG-WRONG-TYPE")))

;; The real sleeper, minimally: one second on the real clock.
(check* (let ([t0 (current-inexact-milliseconds)])
          (check-equal? (name (run-in (fresh-context #:clock real-mdl-clock) "<SLEEP 1>")) "T")
          (define ms (- (current-inexact-milliseconds) t0))
          (check-true (>= ms 950) (format "waited ~a ms" ms))
          (check-true (< ms 5000) (format "waited ~a ms" ms))))
;; A break (DrRacket Stop, Ctrl-C) interrupts a live wait: exn:break leaves
;; SLEEP unchanged, long before the requested 60 seconds.
;; The break is sent only once the real wait has begun (STARTED), so the
;; test cannot pass by breaking context setup instead of the wait.
(check* (let* ([result (box #f)]
               [started (make-semaphore 0)]
               [t0 (current-inexact-milliseconds)]
               [worker (thread
                        (lambda ()
                          (set-box! result
                                    (with-handlers ([exn:break? (lambda (e) e)])
                                      (parameterize ([current-mdl-sleeper
                                                      (lambda (s)
                                                        (semaphore-post started)
                                                        (sleep s))])
                                        (run-in (fresh-context #:clock real-mdl-clock)
                                                "<SLEEP 60>"))))))])
          (check-not-false (sync/timeout 30 started) "the wait began")
          (break-thread worker)
          (check-not-false (sync/timeout 10 worker) "worker ended")
          (check-true (exn:break? (unbox result)))
          (check-true (< (- (current-inexact-milliseconds) t0) 10000))))

;; === TIME (#170) ===================================================================
;; The n-th call in a session returns the FLOAT n.0.
(check* (check-equal? (run "<TIME>") 1.0))
(check* (check-equal? (run "<TIME> <TIME> <TIME>") 3.0))
(check* (check-equal? (name (run "<TYPE <TIME>>")) "FLOAT"))
(check* (check-equal? (name (run "<G? <TIME> 0.0>")) "T"))
(check* (check-equal? (name (run "<TYPE <TIME 1 \"a\" FOO <>>>")) "FLOAT"))
(check* (check-equal? (run "<TIME <SETG X 5>> ,X") 5))
(check* (check-equal? (run "<TIME <SETG X 5>>") 1.0))
(check* (check-equal? (run "<SET A <TIME>> <SET B <TIME>> <- .B .A>") 1.0))
(check* (check-equal? (name (run "<SET A <TIME>> <SET B <TIME>> <G=? .B .A>")) "T"))
(check* (check-false (mdl-truthy? (run "<==? <TIME> <TIME>>"))))
(check* (check-equal? (mdl-string-snapshot (quote t) (run "<COND (<TIME> \"true\") (T \"false\")>") "STRING")
                      "true"))
(check* (check-equal? (run "<APPLY <GVAL TIME>>") 1.0))
(check* (check-equal? (name (run "<TYPE ,TIME>")) "SUBR"))
;; Session-owned: two contexts count independently; TIME never reads the clock.
(check* (let ([a (fresh-context)] [b (fresh-context)])
          (check-equal? (run-in a "<TIME> <TIME>") 2.0)
          (check-equal? (run-in b "<TIME>") 1.0)
          (check-equal? (run-in a "<TIME>") 3.0)))
(check* (let*-values ([(clock reads) (counting-clock #:live? #t)])
          (define ctx (fresh-context #:clock clock))
          (check-equal? (run-in ctx "<TIME> <TIME>") 2.0)
          (check-equal? (reads) 0)))
(check* (let ([rep (make-replaying-mdl-clock '() #:turn turn0)])
          (check-equal? (run-in (fresh-context #:clock rep) "<TIME>") 1.0)
          (check-equal? (mdl-clock-observations rep) '())))
