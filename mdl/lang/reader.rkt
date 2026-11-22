#lang racket/base
;; Enables #lang mdl after `raco pkg install --auto --link`.
(require racket/port "../parser.rkt" "../compiler.rkt")
(provide read read-syntax)

(define (read-syntax src in)
  (define source (if src (format "~a" src) "<input>"))
  (define nodes (parse-mdl (port->string in) #:source source))
  (define forms (compile-program nodes))
  ;; The module runs in the ambient MDL context; give that context its
  ;; initial INCHAN/OUTCHAN bindings if it has none (idempotent).
  (datum->syntax #f `(module mdl-program mdl/lang/main
                       (mdl-ensure-terminal-channels!)
                       ,@forms)))

(define (read in)
  (syntax->datum (read-syntax #f in)))
