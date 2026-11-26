#lang racket/base
;; M3 issue #102: manual chapter 21 registration and removal, no fake events.
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
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
(define (type-name value) (mdl-atom-pname (mdl-type value)))
(define (true? value) (and (mdl-atom? value) (string=? (mdl-atom-pname value) "T")))
(define (false? value) (mdl-false? value))

(check-equal? (type-name (run "<EVENT \"M3-USER\" 7>")) "IHEADER")
(check-equal? (mdl-atom-pname (run "<PRIMTYPE <EVENT \"M3-USER\" 7>>")) "VECTOR")
(check-true (true? (run "<SETG E <EVENT \"M3-USER\" 7>> <==? ,E <EVENT \"M3-USER\" 9>>")))
(check-equal? (type-name (run "<HANDLER <EVENT \"M3-USER\" 7> <FUNCTION (X) .X>>")) "HANDLER")
(check-equal? (mdl-atom-pname (run "<PRIMTYPE <HANDLER <EVENT \"M3-USER\" 7> <FUNCTION (X) .X>>>")) "VECTOR")
(check-true (true? (run "<SETG E <EVENT \"M3-USER\" 7>> <SETG H <HANDLER ,E <FUNCTION (X) .X>>> <==? ,H <OFF ,H>>")))
(check-true (true? (run "<SETG E <EVENT \"M3-USER\" 7>> <SETG H <HANDLER ,E <FUNCTION (X) .X>>> <OFF ,H> <==? ,H <HANDLER ,E ,H>>")))
(check-true (true? (run "<SETG E <EVENT \"M3-USER\" 7>> <==? ,E <OFF ,E>>")))
(check-true (true? (run "<SETG E <EVENT \"M3-USER\" 7>> <OFF ,E> <==? ,E <EVENT ,E>>")))
(check-true (false? (run "<SETG E <EVENT \"M3-USER\" 7>> <OFF ,E> <==? ,E <EVENT \"M3-USER\" 7>>")))
(check-false (eq? (run "<EVENT \"M3-USER\" 7>") (run "<EVENT \"M3-USER\" 7>")))
(define foreign-header (run "<EVENT \"M3-USER\" 7>"))
(parameterize ([current-mdl-globals (make-hasheq)]
               [current-mdl-locals (list (make-hasheq))]
               [current-mdl-atom-space (make-mdl-atom-space)])
  (check-exn #rx"session" (lambda () (mdl-apply (mdl-atom "EVENT") foreign-header))))
(check-exn #rx"priority|FIX" (lambda () (run "<EVENT \"M3-USER\" \"BAD\">")))
(check-exn #rx"IHEADER" (lambda () (run "<HANDLER 1 2>")))
(check-exn #rx"unsupported HANDLER action" (lambda () (run "<HANDLER <EVENT \"M3-USER\" 7> \"BAD\">")))
(check-equal? (type-name (run "<EVENT \"GC\" 11>")) "IHEADER")
(check-exn #rx"unassigned|unsupported" (lambda () (run "<INTERRUPT \"M3-USER\">")))
