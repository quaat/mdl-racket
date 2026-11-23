#lang racket/base
(require rackunit racket/file racket/list racket/path racket/port racket/runtime-path
         "../mdl/loader.rkt" "../mdl/runtime/core.rkt")

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(define source-files
  '("77loadall.mud" "81prim.mud" "77defs.mud" "77makstr.mud"
    "81tell-repl.mud" "77act1.mud" "77act2.mud" "77act3.mud"
    "77rooms.mud" "77patch.mud" "77np.mud" "78melee.mud" "77dung.mud"))
(define root (make-temporary-file "/tmp/mdl-historical-gc~a" 'directory))
(dynamic-wind
 void
 (lambda ()
   (for ([name (in-list source-files)])
     (define source (build-path source-root name))
     (unless (file-exists? source)
       (error 'historical-gc "pinned source missing: ~a" source))
     (call-with-output-file (build-path root name) #:exists 'truncate/replace
       (lambda (out) (write-bytes (file->bytes source) out))))
   (define session (make-mdl-session root))
   (define report
     (parameterize ([current-output-port (open-output-string)])
       (mdl-session-load! session "77loadall.mud")))
   (check-equal? (hash-ref report 'status) "PASS")
   (check-equal? (hash-ref report 'completed_expressions) 1229)
   (check-equal? (hash-ref report 'skipped_expressions) 0)
   (check-false (hash-ref report 'failure))
   (define events (hash-ref report 'events))
   (check-equal? (length events) 1229)
   (check-true (andmap (lambda (event)
                         (equal? (hash-ref event 'status) "PASS")) events))
   (check-equal? (remove-duplicates (map (lambda (event) (hash-ref event 'file)) events))
                 source-files)
   (define original-divert-hand (mdl-session-global session "DIVERT-HAND"))
   (define original-gc-hand (mdl-session-global session "GC-HAND"))
   (check-equal? (mdl-session-global session "DIVERT-CNT") 0)
   (check-equal? (mdl-session-global session "DIVERT-AMT") 0)
   (check-true (exact-integer?
                (mdl-session-call session "DIVERT-FCN" 2
                                  (mdl-session-atom session "LIST"))))
   (check-equal? (mdl-session-global session "DIVERT-CNT") 1)
   (check-equal? (mdl-session-global session "DIVERT-AMT") 4002)
   (check-eq? (mdl-session-global session "GC-HAND") original-gc-hand)
   (call-with-output-file (build-path root "gc-probe.mud")
     (lambda (out) (display "<GC>\n" out)))
   (define gc-report (mdl-session-load! session "gc-probe.mud"))
   (check-equal? (hash-ref gc-report 'status) "PASS")
   (check-equal? (mdl-session-global session "DIVERT-CNT") 0)
   (check-equal? (mdl-session-global session "DIVERT-AMT") 0)
   (check-eq? (mdl-session-global session "DIVERT-HAND") original-divert-hand)
   (check-eq? (mdl-session-global session "GC-HAND") original-gc-hand))
 (lambda () (delete-directory/files root)))
