#lang racket/base
;; M2-D1 historical probe: load the pinned 81prim.mud through the shared
;; session, verify the original MSETG source hash, and exercise the retained
;; definition. Run from the repository root via make test-historical, which
;; fetches the pinned sources first; this file mirrors the cwd-based path
;; convention of historical_vfload_test.rkt.
(require racket/file racket/path racket/port racket/string rackunit
         "../mdl/loader.rkt" "../mdl/runtime/core.rkt")

(define historical
  (build-path ".cache" "upstream" "mdlzork" "mdlzork_771212"
              "patched_confusion" "81prim.mud"))
(define expected-sha
  "8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571")
(define checks 0)
(define (check actual expected)
  (set! checks (add1 checks))
  (unless (equal? actual expected)
    (error 'historical-decl "expected ~s, got ~s" expected actual)))
(define (check-exn-verb thunk pattern)
  (set! checks (add1 checks))
  (define raised?
    (with-handlers ([exn:fail?
                     (lambda (e) (regexp-match? pattern (exn-message e)))])
      (thunk)
      #f))
  (unless raised?
    (error 'historical-decl "expected an error matching ~s" pattern)))

(unless (file-exists? historical)
  (error 'historical-decl
         "pinned sources missing: ~a; run make sources first" historical))
(define sha-tool (find-executable-path "sha256sum"))
(unless sha-tool (error 'historical-decl "sha256sum is required"))
(define-values (proc stdout stdin stderr)
  (subprocess #f #f #f (path->string sha-tool) (path->string historical)))
(close-output-port stdin)
(define sha-output (port->string stdout))
(define sha-error (port->string stderr))
(subprocess-wait proc)
(check (subprocess-status proc) 0)
(check sha-error "")
(check (car (string-split sha-output)) expected-sha)

;; The complete original file now attempts cleanly: since D3 (structured
;; declaration patterns, issue #48) the PSETG declaration <LIST [REST ATOM]>
;; at 11:9 normalizes at install time, so all eight expressions of
;; 81prim.mud load, and the file's load stops... nowhere: 81prim.mud loads
;; in full. The D3-relevant chain failure moved downstream: driving the
;; pinned 77loadall.mud entry stops at 77defs.mud expression 1, whose
;; <AND <L? ,MUDDLE 100> ...> needs the unassigned global MUDDLE - a
;; non-declaration runtime blocker for a later slice.
(define root (make-temporary-file "/tmp/mdl-decl-test~a" 'directory))
(dynamic-wind
 void
 (lambda ()
   ;; Copy the exact pinned bytes into a dedicated authorized root; the
   ;; pinned checkout itself is never executed from or modified.
   (define original-bytes (file->bytes historical))
   (define local-source (build-path root "81prim.mud"))
   (call-with-output-file local-source #:exists 'truncate/replace
     (lambda (out) (write-bytes original-bytes out)))
   (check (file->bytes local-source) original-bytes)
   (define session (make-mdl-session root))
   (define report (mdl-session-load! session "81prim.mud"))
   (check (hash-ref report 'status) "PASS")
   (check (hash-ref report 'completed_expressions) 8)
   ;; The original MSETG definition, from the pinned bytes, is retained and
   ;; executes; the PSETG definition installs with its compound declaration
   ;; and, when invoked, stops explicitly at its <MEMQ .FOO .PL> (no MEMQ
   ;; primitive in this slice, by scope).
   (check-exn-verb
    (lambda () (mdl-session-call session "MSETG" "bad" 3))
    #rx"DECL.*FOO")
   (define atom (mdl-session-call session "ATOM" "M2-D1-TEMP"))
   (check (mdl-atom-pname (mdl-session-call session "MSETG" atom 3)) "T")
   (check (mdl-session-global session atom) 3)
   (define psetg-atom (mdl-session-call session "ATOM" "M2-D3-LVAL"))
   (check-exn-verb
    (lambda () (mdl-session-call session "PSETG" psetg-atom 3))
    #rx"unassigned or non-applicable MDL operator MEMQ")
   (check (mdl-session-global session psetg-atom) 3)

   ;; The pinned 77loadall chain: copy the exact bytes of the entry and the
   ;; two files its load chain reaches, then assert the new failure exactly.
   (define source-root
     (build-path ".cache" "upstream" "mdlzork" "mdlzork_771212"
                 "patched_confusion"))
   (for ([name '("77loadall.mud" "81prim.mud" "77defs.mud")])
     (call-with-output-file (build-path root name) #:exists 'truncate/replace
       (lambda (out)
         (write-bytes (file->bytes (build-path source-root name)) out))))
   (define chain-session (make-mdl-session root))
   (define chain-report
     (mdl-session-load! chain-session "77loadall.mud"))
   (check (hash-ref chain-report 'status) "FAIL")
   ;; Since D4 (the interpreter-supplied MUDDLE global, issue #51) the
   ;; 77defs.mud:1 guard <L? ,MUDDLE 100> is false with ,MUDDLE = 101, so the
   ;; AND short-circuits and the chain advances past it; the next blocker is
   ;; 77defs.mud expression 3, <PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>,
   ;; whose atom-property PUT form is a later slice.
   (check (hash-ref chain-report 'completed_expressions) 12)
   (define failure (hash-ref chain-report 'failure))
   (check (hash-ref failure 'file) "77defs.mud")
   (check (hash-ref failure 'expression_index) 3)
   (check (hash-ref failure 'stage) "execute")
   (check (hash-ref failure 'construct) "PUT")
   (check (hash-ref failure 'line) 5)
   (check (hash-ref failure 'column) 1)
   (check (string-contains? (hash-ref failure 'exception)
                            "index out of range")
          #t))
 (lambda ()
   (with-handlers ([exn:fail? void])
     (delete-directory/files root))))

(displayln (format "historical DECL probe passed: ~a assertions" checks))
