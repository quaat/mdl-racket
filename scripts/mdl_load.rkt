#lang racket/base
;; Local diagnostic driver for controlled MDL source execution.
(require json racket/cmdline racket/file racket/path "../mdl/loader.rkt")
(define source-root #f)
(define entry #f)
(define report-path #f)
(command-line
 #:once-each
 [("--source-root") path "Authorized local source directory" (set! source-root path)]
 [("--entry") path "Entry MDL file within that directory" (set! entry path)]
 [("--report") path "JSON diagnostic report" (set! report-path path)])
(unless (and source-root entry report-path)
  (error 'mdl-load "--source-root, --entry and --report are required"))
(define result
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (hash 'status "FAIL" 'entry entry
                           'completed_expressions 0 'events '()
                           'failure
                           (hash 'classification "filesystem" 'stage "session"
                                 'file #f 'expression_index #f
                                 'line #f 'column #f 'construct "<session>"
                                 'load_chain '() 'exception (exn-message e))))])
    (mdl-session-load! (make-mdl-session source-root) entry)))
(make-directory* (or (path-only report-path) (current-directory)))
(call-with-output-file report-path #:exists 'truncate/replace
  (lambda (out)
    (write-json (if (hash-ref result 'failure #f)
                    result
                    (hash-set result 'failure 'null)) out)
    (newline out)))
(printf "MDL source load ~a: ~a completed expressions; report: ~a\n"
        (hash-ref result 'status) (hash-ref result 'completed_expressions)
        report-path)
(when (equal? (hash-ref result 'status) "FAIL")
  (define failure (hash-ref result 'failure))
  (eprintf "~a: ~a (~a, expression ~a): ~a\n"
           (hash-ref failure 'classification) (hash-ref failure 'file)
           (hash-ref failure 'stage) (hash-ref failure 'expression_index)
           (hash-ref failure 'exception))
  (exit 1))
;; ADR-0054 item 6: the loaded program QUIT; not a PASS and not a load failure.
(when (equal? (hash-ref result 'status) "QUIT")
  (eprintf "the program QUIT during the load (last event in the report)\n")
  (exit 3))
