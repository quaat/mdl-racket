#lang racket/base
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([value #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

(check-equal? (run "<LENGTH <ISTRING 3>>") 3)
(check-equal? (run "<ASCII <NTH <ISTRING 3> 1>>") 0)
(check-equal? (run "<STRING <ISTRING 3 !\\X>>") "XXX")
(check-equal? (mdl-atom-pname (run "<TYPE <REST <ISTRING 3> 3>>")) "STRING")
(check-equal? (run "<LENGTH <REST <ISTRING 3> 3>>") 0)
(check-equal? (run "<SETG S <ISTRING 3 !\\X>> <SETG T <REST ,S 1>> <PUT ,T 1 !\\Y> <STRING ,S>")
              "XYX")
(check-equal? (run "<SETG C 64> <SETG S <ISTRING 3 '<ASCII <SETG C <+ ,C 1>>>>> <STRING ,S>")
              "ABC")
(check-exn #rx"ISTRING|length|FIX" (lambda () (run "<ISTRING -1>")))
(check-exn #rx"ISTRING|CHARACTER" (lambda () (run "<ISTRING 2 7>")))
(check-exn #rx"out of range" (lambda () (run "<REST <ISTRING 2> 3>")))
