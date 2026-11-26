#lang racket/base
;; Issue #90: positional RSUBR-style #DECL used as FUNCTION metadata.
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

(check-equal? (run "<DEFINE M3FD (X) #DECL (\"VALUE\" FIX FIX) .X> <M3FD 7>") 7)
(check-equal? (run "<DEFINE M3FD (X \"OPTIONAL\" (Y 2)) #DECL (\"VALUE\" FIX FIX \"OPTIONAL\" FIX) <+ .X .Y>> <M3FD 3>") 5)
(check-equal? (run "<DEFINE M3FD (X \"OPTIONAL\" (Y 2)) #DECL (\"VALUE\" FIX FIX \"OPTIONAL\" FIX) <+ .X .Y>> <M3FD 3 4>") 7)

;; Confusion preserves but does not enforce an RSUBR-style declaration
;; attached to FUNCTION. Mismatches here must not become ATOM declarations.
(check-equal? (run "<DEFINE M3FD (X) #DECL (\"VALUE\" FIX FIX) .X> <M3FD \"BAD\">") "BAD")
(check-equal? (run "<DEFINE M3FD (X) #DECL (\"VALUE\" FIX FIX) \"BAD\"> <M3FD 1>") "BAD")
(check-equal? (run "<DEFINE M3FD (X \"OPTIONAL\" (Y 2)) #DECL (\"VALUE\" FIX FIX \"OPTIONAL\" FIX) .X> <M3FD 1 \"BAD\">") 1)
(check-equal? (run "<DEFINE M3FD (X) #DECL (\"VALUE\" FIX FIX FIX) .X> <M3FD 1>") 1)
(check-equal? (run "<DEFINE M3FD (X) #DECL (\"VALUE\" FIX) .X> <M3FD 1>") 1)

;; Grammar and Pattern errors remain strict. ATOM declarations are attached
;; declarations, not enforced at the call since M4 #196.
(check-exn #rx"must start with VALUE"
           (lambda () (run "<DEFINE M3FD (X) #DECL (\"WRONG\" FIX FIX) .X>")))
(check-exn #rx"unsupported positional declaration marker QUOTE"
           (lambda () (run "<DEFINE M3FD (X) #DECL (\"VALUE\" FIX \"QUOTE\" FIX) .X>")))
(check-exn #rx"OPTIONAL requires a Pattern"
           (lambda () (run "<DEFINE M3FD (X) #DECL (\"VALUE\" FIX \"OPTIONAL\") .X>")))
(check-exn #rx"unknown declaration type M3-UNKNOWN"
           (lambda () (run "<DEFINE M3FD (X) #DECL (\"VALUE\" M3-UNKNOWN FIX) .X>")))
(check-equal? (run "<DEFINE M3FD (X) #DECL ((X) FIX) .X> <M3FD \"BAD\">") "BAD")

(displayln "positional FUNCTION declaration metadata tests passed")
