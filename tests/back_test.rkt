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

;; BACK keeps the argument's TYPE (maintainer decision 2026-11-23; ADR-0058
;; amendment), matching pinned Confusion (native: <TYPE <BACK <CHTYPE <REST
;; [1 2 3] 2> FOO> 2>> = FOO, <==? <TOP .F> <BACK .F 2>> = T, BS for a NEWTYPE
;; of STRING). REST still drops the tag.
(define (tname v) (mdl-atom-pname (mdl-type v)))
(check-equal? (mdl-atom-pname (run "<NEWTYPE FOO VECTOR> <TYPE <BACK <CHTYPE <REST [1 2 3] 2> FOO> 2>>")) "FOO")
(check-equal? (mdl-atom-pname (run "<NEWTYPE FOO VECTOR> <TYPE <BACK <CHTYPE <REST [1 2 3] 2> FOO> 1>>")) "FOO")
(check-equal? (mdl-atom-pname (run "<NEWTYPE FOO VECTOR> <SET F <CHTYPE <REST [1 2 3] 2> FOO>> <==? <TOP .F> <BACK .F 2>>"))
              "T")
(check-equal? (mdl-atom-pname (run "<NEWTYPE BS STRING> <TYPE <BACK <CHTYPE <REST \"abc\" 1> BS> 1>>")) "BS")
(check-equal? (mdl-atom-pname (run "<NEWTYPE BS STRING> <SET B <CHTYPE <REST \"abc\" 3> BS>> <==? <TOP .B> <BACK .B 3>>"))
              "T")
(check-equal? (mdl-atom-pname (run "<NEWTYPE UF UVECTOR> <TYPE <BACK <CHTYPE <REST ![1 2 3!] 2> UF> 1>>")) "UF")
;; Shared storage, mutation visibility and the UVECTOR UTYPE stay as before.
(check-equal? (run "<NEWTYPE FOO VECTOR> <SETG V [1 2 3]> <SETG B <BACK <CHTYPE <REST ,V 2> FOO> 1>> <PUT ,B 1 9> <2 ,V>") 9)
(check-equal? (mdl-atom-pname (run "<NEWTYPE UF UVECTOR> <UTYPE <BACK <CHTYPE <REST ![1 2 3!] 2> UF> 1>>")) "FIX")
;; REST of the typed BACK result drops the tag again.
(check-equal? (mdl-atom-pname (run "<NEWTYPE FOO VECTOR> <TYPE <REST <BACK <CHTYPE <REST [1 2 3] 2> FOO> 2>>>")) "VECTOR")
;; Identity is by TYPE atom: a same-named atom in another OBLIST is a different TYPE.
(check-equal? (mdl-atom-pname (run "<NEWTYPE FOO VECTOR> <SET A <ATOM \"FOO\">> <NEWTYPE .A VECTOR> <SET X <CHTYPE <REST [1 2 3] 2> .A>> <==? <TYPE <BACK .X 1>> .A>"))
              "T")
;; Bounds checks are unchanged for typed values.
(check-exn #rx"BACK|offset" (lambda () (run "<NEWTYPE FOO VECTOR> <BACK <CHTYPE <REST [1 2] 1> FOO> 2>")))

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
