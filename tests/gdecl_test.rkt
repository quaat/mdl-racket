#lang racket/base
;; Manual §14.5.1; pinned Confusion's no-op reference is recorded in
;; docs/evidence/M3/gdecl-reference.json.
(require rackunit "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (execute source)
  (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
    (eval expr)))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (execute source)))

;; Red at the unchanged 77defs.mud GDECL operator.
(check-equal? (mdl-atom-pname (run "<GDECL (M3G) FIX>")) "T")
(check-true (mdl-false? (run "<GDECL (M3G) FIX> <GASSIGNED? M3G>")))
(check-equal? (run "<GDECL (M3G) FIX> <SETG M3G 3> ,M3G") 3)
(check-equal? (run "<GDECL (M3G M3H) FIX> <SETG M3G 1> <SETG M3H 2> ,M3H") 2)
(check-equal? (run "<GDECL (M3G) FIX (M3H) STRING> <SETG M3G 3> <SETG M3H \"s\"> ,M3H") "s")
(check-equal? (mdl-atom-pname (run "<GDECL (M3G) <VECTOR FIX [REST ATOM]>> <SETG M3G '[1 A B]> <TYPE ,M3G>")) "VECTOR")
(check-exn #rx"declaration|DECL|TYPE-MISMATCH"
           (lambda () (run "<GDECL (M3G) FIX> <SETG M3G \"s\">")))
(check-exn #rx"declaration|DECL|TYPE-MISMATCH"
           (lambda () (run "<SETG M3G \"s\"> <GDECL (M3G) FIX>")))
(check-exn #rx"declaration|DECL|TYPE-MISMATCH"
           (lambda () (run "<GDECL (M3G) <VECTOR FIX>> <SETG M3G '[A]>")))
(parameterize ([current-namespace ns]
               [current-mdl-globals (make-hasheq)]
               [current-mdl-locals (list (make-hasheq))]
               [current-mdl-atom-space (make-mdl-atom-space)])
  (execute "<GDECL (M3G) FIX> <SETG M3G 3>")
  (check-exn #rx"declaration|DECL|TYPE-MISMATCH"
             (lambda () (execute "<SETG M3G \"bad\">")))
  (check-equal? (execute ",M3G") 3))
(check-exn #rx"GDECL|declaration"
           (lambda () (run "<GDECL>")))
(check-exn #rx"GDECL|declaration"
           (lambda () (run "<GDECL (M3G)>")))
(check-exn #rx"GDECL|declaration"
           (lambda () (run "<GDECL M3G FIX>")))
(check-exn #rx"GDECL|declaration"
           (lambda () (run "<GDECL (M3G) <ERROR SHOULD-NOT-RUN>>")))
