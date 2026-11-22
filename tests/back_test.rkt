#lang racket/base
(require rackunit racket/file "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/loader.rkt" "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([value #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

(check-equal? (run "<SETG V [1 2 3]> <SETG T <REST ,V 2>> <SETG B <BACK ,T 1>> <PUT ,B 1 9> <2 ,V>") 9)
(check-equal? (run "<SETG V ![1 2 3!]> <SETG T <REST ,V 2>> <SETG B <BACK ,T 1>> <PUT ,B 1 9> <2 ,V>") 9)
(check-equal? (run "<SETG S <ISTRING 5 !\\A>> <SETG T <REST ,S 3>> <SETG B <BACK ,T 2>> <PUT ,B 1 !\\Z> <STRING ,S>") "AZAAA")
(check-equal? (mdl-atom-pname (run "<SETG U ![1 2 3!]> <UTYPE <BACK <REST ,U 2> 1>>")) "FIX")
(check-exn #rx"BACK|offset" (lambda () (run "<BACK [1 2]>")))
(check-exn #rx"BACK|offset" (lambda () (run "<BACK <REST [1 2]> 2>")))
(check-exn #rx"BACK|offset" (lambda () (run "<BACK <REST [1 2]> 0>")))
(check-exn #rx"BACK|offset" (lambda () (run "<BACK <REST [1 2]> -1>")))
(check-exn #rx"BACK|array|type" (lambda () (run "<BACK 1>")))

(define root (make-temporary-file "mdl-back-terminal~a" 'directory))
(dynamic-wind
 void
 (lambda ()
   (define session (make-mdl-session root))
   (define channel (mdl-session-global session "INCHAN"))
   (define predecessor (mdl-session-call session "BACK" channel))
   (check-equal? (mdl-atom-pname (mdl-session-call session "TYPE" predecessor))
                 "CHANNEL")
   (check-equal? (mdl-session-call session "LENGTH" predecessor) 20)
   (check-equal? (mdl-session-call session "NTH" predecessor 1) 0)
   (check-equal? (mdl-session-call session "NTH" channel 2) "READ"))
 (lambda () (delete-directory/files root)))
