#lang racket/base
(require racket/cmdline racket/file "../mdl/parser.rkt")
(define inputs (command-line #:program "mdl_check.rkt" #:args paths paths))
(when (null? inputs)
  (eprintf "Usage: racket scripts/mdl_check.rkt file1 [file2 ...]\n")
  (exit 2))
(define (count-nodes n)
  (+ 1
     (case (mdl-node-kind n)
       [(form list vector uvector brace)
        (for/sum ([item (in-list (mdl-node-value n))]) (count-nodes item))]
       [(quote percent splice) (count-nodes (mdl-node-value n))]
       [(typed) (count-nodes (cdr (mdl-node-value n)))]
       [else 0])))
(for ([path (in-list inputs)])
  (with-handlers ([exn:fail? (lambda (e)
                               (eprintf "FAIL ~a: ~a\n" path (exn-message e))
                               (exit 1))])
    (define forms (parse-mdl (file->string path) #:source path))
    (printf "PARSED ~a: ~a top-level forms; ~a nodes\n"
            path (length forms) (for/sum ([n (in-list forms)]) (count-nodes n)))))
