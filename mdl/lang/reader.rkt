#lang racket/base
;; Enables #lang mdl after `raco pkg install --auto --link`.
(require racket/port "../parser.rkt" "../compiler.rkt")
(provide read read-syntax)

(define (read-syntax src in)
  (define source (if src (format "~a" src) "<input>"))
  (define nodes (parse-mdl (port->string in) #:source source))
  (define forms (compile-program nodes))
  (datum->syntax #f `(module mdl-program mdl/lang/main ,@forms)))

(define (read in)
  (syntax->datum (read-syntax #f in)))
