#lang racket/base
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")

(define-namespace-anchor anchor)
(define test-namespace (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace test-namespace]
                 [current-mdl-globals (make-hash)])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

(check-true (mdl-atom? (run "'M1-PLAIN")))
(check-equal? (mdl-atom-pname (run "'M1-PLAIN")) "M1-PLAIN")
(check-eq? (run "'M1-PLAIN") (run "'M1-PLAIN"))
(check-eq? (run "<TYPE 'M1-PLAIN>") (mdl-atom "ATOM"))
(check-true (mdl-false? (run "<LOOKUP \"MISSING\" <MOBLIST 'M1-LOOKUP>>")))
(check-equal? (run "<PNAME 'M1-PLAIN>") "M1-PLAIN")
(check-false (eq? (run "<PNAME 'M1-PLAIN>")
                  (run "<PNAME 'M1-PLAIN>")))
(check-true (mdl-false? (run "<==? <ATOM \"M1-X\"> <ATOM \"M1-X\">>")))
(check-eq? (run "<==? <MOBLIST 'M1-O> <MOBLIST 'M1-O>>") (mdl-atom "T"))
(check-eq? (run "<TYPE <MOBLIST 'M1-O>>") (mdl-atom "OBLIST"))
(check-eq? (run (string-append
                 "<SETG M1-O <MOBLIST 'M1-O>> "
                 "<SETG M1-X <INSERT \"M1-X\" ,M1-O>> "
                 "<==? ,M1-X <LOOKUP \"M1-X\" ,M1-O>>"))
           (mdl-atom "T"))
(check-eq? (run (string-append
                 "<SETG M1-O <MOBLIST 'M1-O>> "
                 "<SETG M1-X <OR <LOOKUP \"M1-X\" ,M1-O> "
                 "<INSERT \"M1-X\" ,M1-O>>> "
                 "<==? <OBLIST? ,M1-X> ,M1-O>"))
           (mdl-atom "T"))
(check-true (mdl-false? (run (string-append
                              "<SETG M1-OA <MOBLIST 'M1-OA>> "
                              "<SETG M1-OB <MOBLIST 'M1-OB>> "
                              "<SETG M1-XA <INSERT \"M1-X\" ,M1-OA>> "
                              "<SETG M1-XB <INSERT \"M1-X\" ,M1-OB>> "
                              "<=? ,M1-XA ,M1-XB>"))))
(check-eq? (run (string-append
                 "<SETG M1-OR <MOBLIST 'M1-OR>> "
                 "<SETG M1-XR <INSERT \"M1-X\" ,M1-OR>> "
                 "<REMOVE ,M1-XR> <OBLIST? ,M1-XR>"))
           (mdl-false '()))
(check-eq? (run (string-append
                 "<SETG M1-OR2 <MOBLIST 'M1-OR2>> "
                 "<SETG M1-XR2 <INSERT \"M1-X\" ,M1-OR2>> "
                 "<REMOVE ,M1-XR2> <==? ,M1-XR2 <INSERT ,M1-XR2 ,M1-OR2>>"))
           (mdl-atom "T"))
(check-eq? (run "<MOBLIST 'M1-TRAILER> <==? 'M1-X!-M1-TRAILER 'M1-X!-M1-TRAILER>")
           (mdl-atom "T"))
(check-eq? (run "<MOBLIST 'M1-TRAILER> <==? <OBLIST? 'M1-X!-M1-TRAILER> <MOBLIST 'M1-TRAILER>>")
           (mdl-atom "T"))
(check-exn #rx"already" (lambda ()
  (run "<SETG M1-D <MOBLIST 'M1-D>> <INSERT \"X\" ,M1-D> <INSERT \"X\" ,M1-D>")))
(check-exn #rx"already" (lambda ()
  (run "<INSERT 'M1-PLAIN <MOBLIST 'M1-OTHER>>")))
(define isolated-a
  (parameterize ([current-mdl-atom-space (make-mdl-atom-space)])
    (mdl-atom "M1-ISOLATED")))
(define isolated-b
  (parameterize ([current-mdl-atom-space (make-mdl-atom-space)])
    (mdl-atom "M1-ISOLATED")))
(check-false (eq? isolated-a isolated-b))
(displayln "atom and OBLIST tests passed")
