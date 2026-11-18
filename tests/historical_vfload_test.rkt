#lang racket/base
;; G2 partial-source probe: execute the first unmodified pinned definition.
(require racket/file racket/path racket/port racket/string
         "../mdl/loader.rkt" "../mdl/runtime/core.rkt")

(define historical
  (build-path ".cache" "upstream" "mdlzork" "mdlzork_771212"
              "patched_confusion" "77loadall.mud"))
(define expected-sha
  "389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa")
(define checks 0)
(define (check actual expected)
  (set! checks (add1 checks))
  (unless (equal? actual expected)
    (error 'historical-vfload "expected ~s, got ~s" expected actual)))
(define (raises predicate thunk)
  (set! checks (add1 checks))
  (with-handlers ([predicate values])
    (thunk)
    (error 'historical-vfload "expected failure")))
(define sha-tool (find-executable-path "sha256sum"))
(unless sha-tool (error 'historical-vfload "sha256sum is required"))
(define-values (proc stdout stdin stderr)
  (subprocess #f #f #f (path->string sha-tool) (path->string historical)))
(close-output-port stdin)
(define sha-output (port->string stdout))
(define sha-error (port->string stderr))
(subprocess-wait proc)
(check (subprocess-status proc) 0)
(check sha-error "")
(check (car (string-split sha-output)) expected-sha)

(define root (make-temporary-file "/tmp/mdl-vfload-test~a" 'directory))
(dynamic-wind
 void
 (lambda ()
   ;; Copy the exact pinned bytes into a dedicated authorized root. The pinned
   ;; checkout remains untouched; the loader will execute only form 1.
   (define original-bytes (file->bytes historical))
   (define local-source (build-path root "77loadall.mud"))
   (call-with-output-file local-source #:exists 'truncate/replace
     (lambda (out) (write-bytes original-bytes out)))
   (check (file->bytes local-source) original-bytes)
   (define fixture (build-path root "controlled.mud"))
   (call-with-output-file fixture #:exists 'truncate/replace
     (lambda (out) (display "<SETG HISTORICAL-RESULT 27>\n" out)))
   (define session (make-mdl-session root))
   (define prefix
     (mdl-session-load! session "77loadall.mud" #:max-expressions 1))
   (check (hash-ref prefix 'status) "PARTIAL")
   (check (hash-ref prefix 'completed_expressions) 1)
   (check (hash-ref prefix 'skipped_expressions) 12)
   (check (procedure? (mdl-session-global session "VFLOAD")) #t)
   (define out (open-output-string))
   (define result
     (parameterize ([current-output-port out])
       (mdl-session-call session "VFLOAD" (path->string fixture))))
   (check (mdl-false? result) #t)
   (check (get-output-string out) (string-append (path->string fixture) " loaded\n"))
   (check (mdl-session-global session "HISTORICAL-RESULT") 27)
   (raises exn:fail? (lambda () (mdl-session-call session "VFLOAD" 5)))
   (raises exn:fail:mdl-load?
           (lambda () (mdl-session-call session "VFLOAD" "missing.mud")))
   (check (mdl-session-call session "STRING" "ab" "cd") "abcd")
   (check (mdl-session-call session "STRING") "")
   (raises exn:fail? (lambda () (mdl-session-call session "STRING" "a" 5)))
   (define printed (open-output-string))
   (check (parameterize ([current-output-port printed])
            (mdl-session-call session "PRINTSTRING" "abc")) 3)
   (check (get-output-string printed) "abc")
   (raises exn:fail? (lambda () (mdl-session-call session "PRINTSTRING" 5)))
   (define newline-out (open-output-string))
   (check (mdl-false?
           (parameterize ([current-output-port newline-out])
             (mdl-session-call session "TERPRI"))) #t)
   (check (get-output-string newline-out) "\n")
   (printf "historical VFLOAD partial-source probe passed: ~a assertions\n" checks))
 (lambda () (delete-directory/files root)))
