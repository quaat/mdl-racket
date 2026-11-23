#lang racket/base
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns])
    (for/fold ([value #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

(parameterize ([current-mdl-globals (make-hasheq)]
               [current-mdl-locals (list (make-hasheq))]
               [current-mdl-atom-space (make-mdl-atom-space)])
  (run "<MOBLIST FLAG>")
  (define initial-lookup (mdl-lval "OBLIST"))
  (define block-value
    (run "<BLOCK (<OR <GET FLAG OBLIST> <MOBLIST FLAG>> <GET INITIAL OBLIST> <ROOT>)>"))
  (check-eq? (car (mdl-list->list block-value))
             (mdl-apply "MOBLIST" (mdl-atom "FLAG")))
  (check-eq? (mdl-lval "OBLIST") block-value)
  (define flag-only (run "'FLAG-ONLY"))
  (check-eq? (mdl-apply "OBLIST?" flag-only)
             (car (mdl-list->list block-value)))
  (check-eq? (run "<ENDBLOCK>") initial-lookup)
  (check-eq? (mdl-lval "OBLIST") initial-lookup)
  (check-eq? (mdl-apply "OBLIST?" (run "'AFTER-BLOCK"))
             (car (mdl-list->list initial-lookup)))
  (check-exn #rx"ENDBLOCK|BLOCK" (lambda () (run "<ENDBLOCK>")))
  (check-exn #rx"BLOCK|OBLIST" (lambda () (run "<BLOCK (1)>"))))
