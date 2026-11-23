#lang racket/base
;; Enables #lang mdl after `raco pkg install --auto --link`.
(require racket/port "../parser.rkt" "../compiler.rkt")
(provide read read-syntax)

(define (read-syntax src in)
  (define source (if src (format "~a" src) "<input>"))
  (define nodes (parse-mdl (port->string in) #:source source))
  (define forms (compile-program nodes))
  ;; The module runs in the ambient MDL context; give that context its
  ;; initial INCHAN/OUTCHAN bindings if it has none (idempotent). Explicit
  ;; opt-in (S13 part B, ADR-0050): a #lang mdl module is a low-level REPL/test
  ;; convenience, not a game session, so its OUTCHAN follows the host's
  ;; current-output-port. Sessions never take this path.
  (datum->syntax #f `(module mdl-program mdl/lang/main
                       (mdl-ensure-terminal-channels! #:follow-current-output-port? #t)
                       ,@forms)))

(define (read in)
  (syntax->datum (read-syntax #f in)))
