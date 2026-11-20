#lang racket/base
;; M2-D4: the interpreter-supplied MUDDLE global (issue #51).
;; The pinned reference binds MUDDLE to the FIX 101 (muddle-reference.json,
;; interpreter SHA a29c756df5c9...7317e629); every fresh shared-session
;; loader session seeds it identically, so the 77defs.mud:1 guard
;; <L? ,MUDDLE 100> is FALSE and its <AND ...> short-circuits without
;; evaluating USE (unbound in the reference).
(require rackunit racket/file racket/path
         "../mdl/loader.rkt" "../mdl/runtime/core.rkt")

(define scratch-root
  (let ([p (make-temporary-file "mdl-muddle-test~a" #f (find-system-path 'temp-dir))])
    (delete-file p)
    (make-directory* p)
    p))

(define (put relative contents)
  (call-with-output-file (build-path scratch-root relative)
    #:exists 'truncate/replace (lambda (out) (display contents out))))

(dynamic-wind
 void
 (lambda ()
   (put "probe.mud" "<TYPE ,MUDDLE>\n")
   (define session (make-mdl-session scratch-root))
   (check-equal? (hash-ref (mdl-session-load! session "probe.mud") 'status) "PASS")
   (check-equal? (mdl-session-global session "MUDDLE") 101)
   (check-equal? (mdl-atom-pname (mdl-session-call session "TYPE" 101)) "FIX")
   ;; The 77defs.mud:1 guard itself: false, with USE never evaluated.
   (put "guard.mud" "<L? ,MUDDLE 100>\n")
   (check-equal? (hash-ref (mdl-session-load! session "guard.mud") 'status) "PASS")
   (check-true (mdl-false?
                (mdl-session-call session "L?"
                                  (mdl-session-call session "GVAL" "MUDDLE")
                                  100)))
   (put "and.mud" "<AND <L? ,MUDDLE 100> <USE \"LSRTNS\">>\n")
   (check-equal? (hash-ref (mdl-session-load! session "and.mud") 'status) "PASS")
   ;; USE is unbound and must stay so: a direct call is an explicit error.
   (put "use.mud" "<USE \"LSRTNS\">\n")
   (check-equal? (hash-ref (mdl-session-load! session "use.mud") 'status) "FAIL")
   (check-equal? (hash-ref (hash-ref (mdl-session-load! session "use.mud") 'failure) 'construct) "USE")
   ;; GASSIGNED? is true: the global is assigned, not merely named (an
   ;; unassigned global would return #FALSE () without erroring, so the
   ;; result value is asserted, not just the load status).
   (check-equal? (mdl-atom-pname (mdl-session-call session "GASSIGNED?" "MUDDLE"))
                 "T")
   ;; And its TYPE is FIX, asserted directly (review P3-b).
   (check-equal? (mdl-atom-pname (mdl-session-call session "TYPE"
                                                   (mdl-session-call session "GVAL" "MUDDLE")))
                 "FIX"))
 (lambda () (delete-directory/files scratch-root)))

(displayln "muddle tests passed")
