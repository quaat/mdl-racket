#lang racket/base
;; Issue #92: !\ followed by one ASCII character is a CHARACTER.
(require rackunit racket/list "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

(define space-node (car (parse-mdl "!\\ ")))
(check-equal? (mdl-node-kind space-node) 'character)
(check-equal? (mdl-node-value space-node) #\space)
(check-equal? (length (parse-mdl "<PRINC !\\ >")) 1)
(check-equal? (mdl-node-kind (second (mdl-node-value (car (parse-mdl "<PRINC !\\ >")))))
              'character)

(check-equal? (mdl-atom-pname (run "<TYPE !\\ >")) "CHARACTER")
(check-equal? (mdl-atom-pname (run "<PRIMTYPE !\\ >")) "WORD")
(check-equal? (mdl-base (run "!\\ ")) 32)
(check-equal? (mdl-base (run "!\\A")) 65)
(check-equal? (mdl-atom-pname (run "<==? !\\  !\\ >")) "T")
(check-equal? (mdl-base (run "<DEFINE M3CH () !\\ > <M3CH>")) 32)
(check-exn exn:fail:mdl-reader? (lambda () (parse-mdl "!\\")))

;; The existing SEGMENT reader remains distinct from !\ CHARACTER.
(check-equal? (mdl-node-kind (car (parse-mdl "!<LIST 1 2>"))) 'splice)

(displayln "space CHARACTER reader tests passed")
