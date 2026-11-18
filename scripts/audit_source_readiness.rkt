#lang racket/base
;; Read-only M2 audit: compile every top-level form, then execute each file
;; in a fresh in-memory runtime until its first failure. This is not a loader.
(require json racket/cmdline racket/file racket/list racket/path racket/string
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")

(define source-root
  (build-path ".cache" "upstream" "mdlzork" "mdlzork_771212"
              "patched_confusion"))
(define output-path (build-path "artifacts" "m2" "source-readiness.json"))
(command-line
 #:once-each
 [("--source-root") path "Pinned reconstructed source directory"
  (set! source-root (string->path path))]
 [("--output") path "JSON report path"
  (set! output-path (string->path path))])

(define filenames
  '("77loadall.mud" "81prim.mud" "77defs.mud" "77makstr.mud"
                    "77patch.mud"))
(define-namespace-anchor anchor)
(define test-namespace (namespace-anchor->namespace anchor))

(define (node-label node)
  (if (and (eq? (mdl-node-kind node) 'form)
           (pair? (mdl-node-value node))
           (eq? (mdl-node-kind (car (mdl-node-value node))) 'atom))
      (string-upcase (mdl-node-value (car (mdl-node-value node))))
      (symbol->string (mdl-node-kind node))))

(define (failure stage filename index node exn completed)
  (hash 'status "FAIL"
        'stage stage
        'file filename
        'expression_index index
        'line (mdl-node-line node)
        'column (mdl-node-column node)
        'construct (node-label node)
        'completed_expressions completed
        'exception (exn-message exn)))

(define (compile-audit filename nodes)
  (let/ec stop
    (for ([node (in-list nodes)] [index (in-naturals 1)])
      (with-handlers ([exn:fail?
                       (lambda (exn)
                         (stop (failure "compile" filename index node exn
                                        (sub1 index))))])
        (compile-expression node)))
    (hash 'status "PASS" 'completed_expressions (length nodes))))

(define (execute-audit filename nodes)
  (parameterize ([current-namespace test-namespace]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (let/ec stop
      (for ([node (in-list nodes)] [index (in-naturals 1)])
        (with-handlers ([exn:fail?
                         (lambda (exn)
                           (stop (failure "compile-or-execute" filename index
                                          node exn (sub1 index))))])
          (eval (compile-expression node))))
      (hash 'status "PASS" 'completed_expressions (length nodes)))))

(define (audit-file filename)
  (define path (build-path source-root filename))
  (define nodes (parse-mdl (file->string path) #:source filename))
  (hash 'file filename
        'top_level_expressions (length nodes)
        'first_compile_barrier (compile-audit filename nodes)
        'first_execution_barrier (execute-audit filename nodes)))

(define report
  (hash 'schema_version 1
        'method "each file independently; compile every top-level expression, then execute sequentially in a fresh in-memory runtime until first failure"
        'files (map audit-file filenames)))
(make-directory* (or (path-only output-path) (current-directory)))
(call-with-output-file output-path #:exists 'truncate/replace
  (lambda (out) (write-json report out) (newline out)))
(printf "Audited ~a pinned files; report: ~a\n" (length filenames) output-path)
