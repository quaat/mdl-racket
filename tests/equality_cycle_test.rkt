#lang racket/base
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")

(define-namespace-anchor anchor)
(define test-namespace (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace test-namespace]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

;; Bound tests while the pre-fix comparator may recurse forever.
(define (bounded-run source)
  (define custodian (make-custodian))
  (define output (make-channel))
  (parameterize ([current-custodian custodian])
    (thread (lambda ()
              (channel-put output
                           (with-handlers ([exn:fail? values])
                             (run source))))))
  (define result (sync/timeout 2 output))
  (custodian-shutdown-all custodian)
  (cond [(not result) (error 'bounded-run "cyclic comparison did not terminate")]
        [(exn:fail? result) (raise result)]
        [else result]))

(define (true? value)
  (and (mdl-atom? value) (string=? (mdl-atom-pname value) "T")))

(check-true
 (true? (bounded-run "<SETG X (1)> <PUTREST ,X ,X> <=? ,X ,X>")))
(check-true
 (true? (bounded-run "<SETG X (1)> <PUTREST ,X ,X> <==? ,X ,X>")))
(check-exn #rx"unsupported cyclic structural equality"
           (lambda ()
             (bounded-run "<SETG X (1)> <SETG Y (1)> <PUTREST ,X ,X> <PUTREST ,Y ,Y> <=? ,X ,Y>")))
(check-true
 (mdl-false? (bounded-run "<SETG X (1)> <SETG Y (2)> <PUTREST ,X ,X> <PUTREST ,Y ,Y> <=? ,X ,Y>")))
(check-true
 (true? (bounded-run "<SETG X (1 2)> <=? <LIST ,X ,X> <LIST <LIST 1 2> <LIST 1 2>>>")))
(check-true
 (true? (bounded-run "<SETG X [0]> <PUT ,X 1 ,X> <=? ,X ,X>")))
(check-exn #rx"unsupported cyclic structural equality"
           (lambda ()
             (bounded-run "<SETG X [0]> <SETG Y [0]> <PUT ,X 1 ,X> <PUT ,Y 1 ,Y> <=? ,X ,Y>")))
(check-true
 (true? (bounded-run "<SETG X #FALSE (1)> <PUT ,X 1 ,X> <=? ,X ,X>")))
(check-exn #rx"unsupported cyclic structural equality"
           (lambda ()
             (bounded-run "<SETG X #FALSE (1)> <SETG Y #FALSE (1)> <PUT ,X 1 ,X> <PUT ,Y 1 ,Y> <=? ,X ,Y>")))
(check-exn #rx"unsupported cyclic structural equality"
           (lambda ()
             (bounded-run "<NEWTYPE M2-T VECTOR> <SETG X <CHTYPE [0] M2-T>> <SETG Y <CHTYPE [0] M2-T>> <PUT ,X 1 ,X> <PUT ,Y 1 ,Y> <=? ,X ,Y>")))
(check-exn #rx"unsupported cyclic structural equality"
           (lambda ()
             (bounded-run "<SETG X ![![]!]> <SETG Y ![![]!]> <PUT ,X 1 ,X> <PUT ,Y 1 ,Y> <=? ,X ,Y>")))
(displayln "cyclic structural equality boundary tests passed")
