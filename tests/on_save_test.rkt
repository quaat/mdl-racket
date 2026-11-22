#lang racket/base
;; S4-ON-SAVE (issue #112): maintainer decisions of 2026-11-22.
;; (1) ON = EVENT + HANDLER (manual ch.21) returning the new HANDLER; the
;;     predefined "IPC" may be registered but can never be emitted.
;; (2) SAVE (and RESTORE) are strict, intentional unsupported errors that
;;     write no file.
;; Each `run` builds a fresh atom space; never compare atoms across runs.
(require rackunit racket/list racket/file
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (session thunk)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (thunk)))
(define (eval-source source)
  (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
    (eval expr)))
(define (run source) (session (lambda () (eval-source source))))
(define (type-name value) (mdl-atom-pname (mdl-type value)))
(define (true? value) (and (mdl-atom? value) (string=? (mdl-atom-pname value) "T")))

;; --- ON returns a HANDLER (compiled path) -------------------------------
(check-equal? (type-name (run "<ON \"M3-USER\" <FUNCTION (X) .X> 7>")) "HANDLER")
(check-equal? (type-name (run "<ON \"IPC\" ,TYPE 1>")) "HANDLER")
(check-equal? (mdl-atom-pname (run "<PRIMTYPE <ON \"IPC\" ,TYPE 1>>")) "VECTOR")
;; OFF removes it and returns the same object; HANDLER on the IHEADER found
;; by EVENT reattaches it, so ON used that very IHEADER.
(check-true (true? (run "<SETG H <ON \"IPC\" ,TYPE 1>> <==? ,H <OFF ,H>>")))
(check-true (true? (run "<SETG H <ON \"IPC\" ,TYPE 1>> <OFF ,H>
                         <==? ,H <HANDLER <EVENT \"IPC\" 1> ,H>>")))
(check-true (true? (run "<SETG H <ON \"M3-USER\" <FUNCTION (X) .X> 7>> <OFF ,H>
                         <==? ,H <HANDLER <EVENT \"M3-USER\" 7> ,H>>")))
;; EVENT on the same name returns the IHEADER ON created (priority ignored).
(check-true (true? (run "<SETG H <ON \"IPC\" ,TYPE 1>> <OFF ,H>
                         <==? ,H <HANDLER <EVENT \"IPC\" 5> ,H>>")))
;; OFF of the IHEADER drops the association; a later ON makes a new one.
(check-exn #rx"HANDLER already in use or belongs to another IHEADER"
           (lambda () (run "<SETG H <ON \"IPC\" ,TYPE 1>> <OFF ,H> <OFF <EVENT \"IPC\" 1>>
                            <ON \"IPC\" ,TYPE 1> <HANDLER <EVENT \"IPC\" 1> ,H>")))

;; --- ON places the HANDLER first, and OFF stops delivery -----------------
(session
 (lambda ()
   (define seen '())
   (define (recorder tag) (lambda (v) (set! seen (append seen (list (list tag v))))))
   (define old (mdl-apply "ON" "M3-USER" (recorder 'old) 7))
   (define new (mdl-apply "ON" "M3-USER" (recorder 'new) 7))
   (check-equal? (type-name new) "HANDLER")
   (check-true (mdl-emit-event! "M3-USER" '(1)))
   (check-equal? seen '((new 1) (old 1)))
   (check-eq? (mdl-apply "OFF" new) new)
   (mdl-emit-event! "M3-USER" '(2))
   (check-equal? seen '((new 1) (old 1) (old 2)))
   ;; ON finds the existing IHEADER and re-enables it (manual 21.6).
   (define header (mdl-apply "EVENT" "M3-USER" 99))
   (mdl-apply "DISABLE" header)
   (check-false (mdl-emit-event! "M3-USER" '(3)))
   (mdl-apply "ON" "M3-USER" (recorder 'third) 7)
   (check-true (mdl-emit-event! "M3-USER" '(4)))
   (check-equal? (drop seen 3) '((third 4) (old 4)))))

;; --- APPLY path ----------------------------------------------------------
(check-equal? (type-name (run "<APPLY ,ON \"IPC\" ,TYPE 1>")) "HANDLER")
(check-equal? (type-name (run "<APPLY ,ON \"M3-USER\" <FUNCTION (X) .X> 7>")) "HANDLER")
(check-true (true? (run "<SETG H <APPLY ,ON \"IPC\" ,TYPE 1>> <==? ,H <APPLY ,OFF ,H>>")))
(check-exn #rx"ON priority must be a positive FIX"
           (lambda () (run "<APPLY ,ON \"IPC\" ,TYPE 0>")))

;; --- strict validation (Confusion's stub returns T for all of these) -----
(check-exn #rx"ON name must be STRING" (lambda () (run "<ON 1 ,TYPE 1>")))
(check-exn #rx"ON name must be STRING" (lambda () (run "<ON IPC ,TYPE 1>")))
(check-exn #rx"unsupported ON applicable" (lambda () (run "<ON \"IPC\" 1 1>")))
(check-exn #rx"unsupported ON applicable" (lambda () (run "<ON \"IPC\" \"BAD\" 1>")))
(check-exn #rx"unsupported ON applicable"
           (lambda () (run "<SETG H <ON \"IPC\" ,TYPE 1>> <ON \"IPC\" ,H 1>")))
(check-exn #rx"ON priority must be a positive FIX" (lambda () (run "<ON \"IPC\" ,TYPE 0>")))
(check-exn #rx"ON priority must be a positive FIX" (lambda () (run "<ON \"IPC\" ,TYPE -1>")))
(check-exn #rx"ON priority must be a positive FIX" (lambda () (run "<ON \"IPC\" ,TYPE \"X\">")))
(check-exn #rx"ON priority must be a positive FIX" (lambda () (run "<ON \"IPC\" ,TYPE 1.5>")))
(check-exn #rx"ON expects name, applicable and priority" (lambda () (run "<ON>")))
(check-exn #rx"ON expects name, applicable and priority" (lambda () (run "<ON \"IPC\" ,TYPE>")))
(check-exn #rx"ON expects name, applicable and priority"
           (lambda () (run "<ON \"IPC\" ,TYPE 1 2 3 4>")))
(check-exn #rx"ON process and which arguments are unsupported"
           (lambda () (run "<ON \"IPC\" ,TYPE 1 2>")))
(check-exn #rx"ON process and which arguments are unsupported"
           (lambda () (run "<ON \"IPC\" ,TYPE 1 2 3>")))
;; Every other refused predefined name stays refused, through ON and EVENT.
(for ([name '("BLOCKED" "CHAR" "READ" "WRITE" "UNBLOCKED" "CLOCK" "SYSDOWN")])
  (check-exn #rx"unsupported predefined EVENT"
             (lambda () (run (format "<ON ~s ,TYPE 100>" name))))
  (check-exn #rx"unsupported predefined EVENT"
             (lambda () (run (format "<EVENT ~s 100>" name)))))
;; A rejected ON registers nothing.
(session
 (lambda ()
   (for ([bad (list (list "M3-NEW" 1 7) (list "M3-NEW" mdl-type 0)
                    (list "M3-NEW" mdl-type 7 1))])
     (check-exn exn:fail? (lambda () (apply mdl-apply "ON" bad))))
   (check-exn #rx"unknown or unregistered event M3-NEW"
              (lambda () (mdl-emit-event! "M3-NEW" '() #t)))))

;; --- IPC registration works; IPC emission is a strict error ---------------
(define ipc-rx #rx"IPC: this session has no inter-process message source")
(session
 (lambda ()
   (define seen '())
   (define handler (mdl-apply "ON" "IPC" (lambda args (set! seen (cons args seen))) 1))
   (check-equal? (type-name handler) "HANDLER")
   (check-exn ipc-rx (lambda () (mdl-emit-event! "IPC" '())))
   (check-exn ipc-rx (lambda () (mdl-emit-event! "IPC" '("message") #t)))
   ;; Nothing was queued: a later safe point delivers nothing.
   (check-equal? (mdl-apply "INT-LEVEL" 0) 0)
   (check-equal? seen '())
   (check-eq? (mdl-apply "OFF" handler) handler)
   (check-exn ipc-rx (lambda () (mdl-emit-event! "IPC" '())))
   (check-equal? seen '())))
;; Emission is refused even with no IPC registration at all.
(session (lambda () (check-exn ipc-rx (lambda () (mdl-emit-event! "IPC" '())))))

;; --- session isolation --------------------------------------------------
(define foreign-handler (session (lambda () (mdl-apply "ON" "IPC" mdl-type 1))))
(session
 (lambda ()
   (check-exn #rx"another MDL session" (lambda () (mdl-apply "OFF" foreign-handler)))
   (check-exn #rx"unknown or unregistered event M3-USER"
              (lambda () (mdl-emit-event! "M3-USER" '() #t)))))
(define foreign-user (session (lambda () (mdl-apply "ON" "M3-USER" mdl-type 7))))
(session
 (lambda ()
   (define header (mdl-apply "EVENT" "M3-USER" 7))
   (check-exn #rx"belongs to another IHEADER|another MDL session"
              (lambda () (mdl-apply "HANDLER" header foreign-user)))))

;; --- SAVE / RESTORE: explicit decision error, no file written -------------
(define save-rx
  #rx"^SAVE: saving a restorable image is not supported \\(maintainer decision 2026-11-22; issue #112\\)$")
(define restore-rx
  #rx"^RESTORE: restoring a saved image is not supported \\(maintainer decision 2026-11-22; issue #112\\)$")
(define (snapshot dir) (sort (map path->string (directory-list dir)) string<?))
(define scratch (make-temporary-file "on-save-test-~a" 'directory))
(dynamic-wind
 void
 (lambda ()
   (parameterize ([current-directory scratch])
     (define temp-dir (find-system-path 'temp-dir))
     (define cwd-before (snapshot scratch))
     (define tmp-before (snapshot temp-dir))
     (for ([source '("<SAVE \"S4PROBE.SAVE\">" "<SAVE>" "<SAVE 1>"
                     "<SAVE \"<MDL>MADADV.SAVE\">" "<APPLY ,SAVE \"S4PROBE.SAVE\">"
                     "<=? <SAVE \"S4PROBE.SAVE\"> \"SAVED\">")])
       (check-exn save-rx (lambda () (run source)) source))
     (for ([source '("<RESTORE \"S4PROBE.SAVE\">" "<RESTORE>"
                     "<APPLY ,RESTORE \"S4PROBE.SAVE\">")])
       (check-exn restore-rx (lambda () (run source)) source))
     (check-equal? (snapshot scratch) cwd-before)
     (check-equal? cwd-before '())
     (check-equal? (snapshot temp-dir) tmp-before)
     (check-false (file-exists? (build-path scratch "S4PROBE.SAVE")))))
 (lambda () (delete-directory/files scratch)))
;; SAVE evaluates its arguments as a SUBR before refusing.
(session
 (lambda ()
   (check-exn save-rx (lambda () (eval-source "<SETG X 0> <SAVE <SETG X 1>>")))
   (check-equal? (eval-source ",X") 1)))
