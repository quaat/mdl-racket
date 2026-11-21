#lang racket/base
;; Exact-source issue #80 regression: AND? evaluates all five MSETG calls.
(require racket/file racket/path racket/port racket/string racket/runtime-path rackunit
         "../mdl/loader.rkt")

(define-runtime-path repository-root "..")
(define source-root
  (build-path repository-root ".cache" "upstream" "mdlzork" "mdlzork_771212"
              "patched_confusion"))
(define expected-shas
  '(("77loadall.mud" . "389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa")
    ("81prim.mud" . "8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571")
    ("77defs.mud" . "566ebcc32be9b9226dd7cefd77a517583eebab80a03f452df39e13b85eed734e")))
(define sha-tool (find-executable-path "sha256sum"))
(unless sha-tool (error 'historical-andq "sha256sum is required"))
(for ([pair (in-list expected-shas)])
  (define source (build-path source-root (car pair)))
  (unless (file-exists? source)
    (error 'historical-andq "pinned source missing: ~a" source))
  (define-values (proc stdout stdin stderr)
    (subprocess #f #f #f (path->string sha-tool) (path->string source)))
  (close-output-port stdin)
  (define output (port->string stdout))
  (define error-output (port->string stderr))
  (subprocess-wait proc)
  (check-equal? (subprocess-status proc) 0)
  (check-equal? error-output "")
  (check-equal? (car (string-split output)) (cdr pair)))

(define root (make-temporary-file "/tmp/mdl-andq-test~a" 'directory))
(dynamic-wind
 void
 (lambda ()
   (for ([pair (in-list expected-shas)])
     (define name (car pair))
     (call-with-output-file (build-path root name) #:exists 'truncate/replace
       (lambda (out)
         (write-bytes (file->bytes (build-path source-root name)) out))))
   (define session (make-mdl-session root))
   (define out (open-output-string))
   (define entry
     (parameterize ([current-output-port out])
       (mdl-session-load! session "77loadall.mud" #:max-expressions 1)))
   (define prim
     (parameterize ([current-output-port out])
       (mdl-session-load! session "81prim.mud")))
   (define defs
     (parameterize ([current-output-port out])
       (mdl-session-load! session "77defs.mud" #:max-expressions 28)))
   (check-equal? (hash-ref entry 'status) "PARTIAL")
   (check-equal? (hash-ref prim 'status) "PASS")
   (check-equal? (hash-ref defs 'status) "PARTIAL")
   (check-equal? (hash-ref defs 'completed_expressions) 28)
   ;; The bounded regression intentionally leaves 68 later forms unread;
   ;; the separate unchanged full-loader progress report must skip zero.
   (check-equal? (hash-ref defs 'skipped_expressions) 68)
   (check-equal? (hash-ref defs 'failure) #f)
   (check-equal? (get-output-string out) "")
   (for ([pair (in-list '(("OFLAG" . 1) ("OVERB" . 2)
                          ("OSLOT1" . 3) ("OPREP" . 4)
                          ("ONAME" . 5)))])
     (check-equal? (mdl-session-global session (car pair)) (cdr pair)))
   (displayln "historical AND? side effects passed: 5 original MSETG globals"))
 (lambda () (delete-directory/files root)))
