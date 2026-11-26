#lang racket/base
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns])
    (for/fold ([value #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

(define (session thunk)
  (parameterize ([current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (thunk)))

(session
 (lambda ()
   (define header (mdl-apply (mdl-atom "EVENT") "ERROR" 8))
   (define seen '())
   (define frame #f)
   (mdl-apply (mdl-atom "HANDLER") header
              (lambda (current-frame . args)
                (set! frame current-frame)
                (set! seen args)
                (check-equal? (mdl-atom-pname (mdl-type current-frame)) "FRAME")
                (mdl-apply (mdl-atom "ERRET") 42 current-frame)))
   (check-equal? (mdl-apply (mdl-atom "ERROR") (mdl-atom "PROBE") 9) 42)
   (check-equal? seen (list (mdl-atom "PROBE") 9))
   (check-exn #rx"FRAME|ERRET|live" (lambda () (mdl-apply (mdl-atom "ERRET") 1 frame)))))

(session
 (lambda ()
   (define header (mdl-apply (mdl-atom "EVENT") "ERROR" 8))
   (define calls 0)
   (mdl-apply (mdl-atom "HANDLER") header
              (lambda args (set! calls (add1 calls))))
   (check-exn #rx"FALLTHROUGH" (lambda () (mdl-apply (mdl-atom "ERROR") (mdl-atom "FALLTHROUGH"))))
   (check-equal? calls 1)
   (mdl-apply (mdl-atom "INT-LEVEL") 8)
   (check-exn #rx"SUPPRESSED" (lambda () (mdl-apply (mdl-atom "ERROR") (mdl-atom "SUPPRESSED"))))
   (check-equal? calls 1)
   (mdl-apply (mdl-atom "INT-LEVEL") 0)
   (check-equal? calls 1)))

(session
 (lambda ()
   (run "<SETG EH <HANDLER <EVENT \"ERROR\" 8>
                        <FUNCTION (FRM \"TUPLE\" ZORK)
                          <SETG SEEN-FRAME-TYPE <TYPE .FRM>>
                          <SETG SEEN-ARG-COUNT <LENGTH .ZORK>>
                          <ERRET 17 .FRM>>>>")
   (check-equal? (mdl-apply (mdl-atom "ERROR") (mdl-atom "ONE") 2) 17)
   (check-eq? (mdl-gval (mdl-atom "SEEN-FRAME-TYPE")) (mdl-atom "FRAME"))
   (check-equal? (mdl-gval (mdl-atom "SEEN-ARG-COUNT")) 2)))
