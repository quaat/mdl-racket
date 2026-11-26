#lang racket/base
;; M2 issue #65: pinned Confusion results in docs/evidence/M2/mapf-reference.json.
(require rackunit racket/mpair racket/string
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))
(define (render value)
  (cond [(mdl-false? value) "#FALSE ()"]
        [(mdl-atom? value) (mdl-atom-pname value)]
        [(or (null? value) (mpair? value))
         (format "(~a)" (string-join (map render (mdl-list->list value)) " "))]
        [(mdl-array? value)
         (format "~a~a~a"
                 (if (eq? (mdl-array-kind value) 'VECTOR) "[" "![")
                 (string-join
                  (for/list ([i (in-range (mdl-array-length value))])
                    (render (mdl-nth value (add1 i)))) " ")
                 (if (eq? (mdl-array-kind value) 'VECTOR) "]" "!]"))]
        [else (format "~a" value)]))

;; The first assertion is deliberately red before MAPF exists.
(check-equal? (render (run "<MAPF ,LIST ,+ '(1 2 3) '(10 20 30)>")) "(11 22 33)")
(check-equal? (render (run "<MAPF ,VECTOR ,+ '[1 2 3]>")) "[1 2 3]")
(check-equal? (render (run "<MAPF ,LIST ,+ '![4 5 6]>")) "(4 5 6)")
(check-equal? (render (run "<MAPF ,LIST ,+ '(1 2 3) '(10 20)>")) "(11 22)")
(check-equal? (render (run "<MAPF ,LIST ,+ '()>")) "()")
(check-equal? (render (run "<MAPF ,VECTOR ,+ '[]>")) "[]")
(check-equal? (run "<MAPF <> ,+ '(1 2 3)>") 3)
(check-equal? (render (run "<MAPF <> ,+ '()>")) "#FALSE ()")
(check-equal? (run "<MAPF ,+ ,+ '(1 2 3)>") 6)
(check-equal? (render (run "<MAPF ,LIST <FUNCTION (X) <* .X .X>> '(2 3 4)>"))
              "(4 9 16)")
(check-equal? (render (run "<MAPF ,LIST <FUNCTION (X \"AUX\" (Y 2)) <+ .X .Y>> '(3 4)>"))
              "(5 6)")
(check-equal? (render (run "<SET N 10> <MAPF ,LIST <FUNCTION (X) <+ .X .N>> '(1 2)>"))
              "(11 12)")
(check-equal? (render (run "<SET F <FUNCTION (X) <+ .X 1>>> <MAPF ,LIST .F '(1 2)>"))
              "(2 3)")
(check-equal? (render (run "<MAPF ,LIST <FUNCTION (X) .X> '((A B) (C D))>"))
              "((A B) (C D))")
(check-equal? (render (run "<MAPF ,LIST <FUNCTION (X) .X> '([1 2] [3 4])>"))
              "([1 2] [3 4])")
(check-equal? (render (run "<MAPF ,LIST <FUNCTION (X) <MAPF ,LIST ,+ .X>> '((1 2) (3 4))>"))
              "((1 2) (3 4))")
(check-equal? (render (run "<DEFINE MAP-HELP (X) <+ .X 10>> <MAPF ,LIST <FUNCTION (Y) <MAP-HELP .Y>> '(1 2)>"))
              "(11 12)")
(check-equal? (render (run "<PROG ((N 10)) <MAPF ,LIST <FUNCTION (X) <+ .N .X>> '(1 2)>>"))
              "(11 12)")
(check-equal? (render (run "<MAPF ,LIST 1 '[(A B) (C D)]>")) "(A C)")
(check-equal? (render (run "<MAPF ,LIST <FUNCTION (X) <COND (<==? .X 2> <MAPRET>)> .X> '(1 2 3)>"))
              "(1 3)")
(check-equal? (render (run "<MAPF ,LIST <FUNCTION (X) <MAPRET .X <* .X 10>>> '(1 2)>"))
              "(1 10 2 20)")
(check-equal? (render (run "<MAPF ,LIST <FUNCTION (X) <COND (<==? .X 3> <MAPSTOP 99>)> .X> '(1 2 3 4)>"))
              "(1 2 99)")
(check-equal? (run "<MAPF ,LIST <FUNCTION (X) <COND (<==? .X 3> <MAPLEAVE .X>)> .X> '(1 2 3 4)>") 3)
(check-equal? (render (run "<SET N 0> <MAPF ,LIST <FUNCTION () <COND (<G? <SET N <+ .N 1>> 2> <MAPSTOP .N>)> .N>>"))
              "(1 2 3)")
(check-equal? (render (run "<MAPF ,LIST <FUNCTION (X) <MAPF ,LIST <FUNCTION (Y) <MAPSTOP .Y>> .X>> '((1 2) (3 4))>"))
              "((1) (3))")
(check-equal? (run "<SETG ORD 0> <MAPF <> <FUNCTION (X) <SETG ORD <+ <* 10 ,ORD> .X>>> '(1 2 3)> ,ORD") 123)
(check-equal? (run "<MAPF <FUNCTION (\"TUPLE\" X) <LENGTH .X>> ,+ '(1 2 3)>") 3)
(check-equal? (render (run "<MAPF ,LIST <FUNCTION (X) #DECL ((X) FIX) .X> '(1 2)>")) "(1 2)")
(check-equal? (run "<MAPF <> <FUNCTION (X) <MAPRET>> '(1)>") 1)
(check-equal? (run "<MAPF <> <FUNCTION (X) <MAPRET 9>> '(7)>") 7)
(check-equal? (run "<MAPF <> <FUNCTION (X) <MAPSTOP 9>> '(7)>") 7)
(check-equal? (render (run "<MAPF ,LIST <FUNCTION (X) <MAPSTOP>> '(1 2)>")) "()")
(check-equal? (render (run "<MAPF ,LIST <FUNCTION (X) <MAPLEAVE>> '(1)>")) "T")
(check-equal? (run "<SETG U 0> <MAPF ,LIST <FUNCTION (X) <UNWIND <MAPLEAVE 7> <SETG U 1>>> '(1)> ,U") 1)
;; the FUNCTION's attached declaration is not enforced (M4 #196)
(check-equal? (render (run "<MAPF ,LIST <FUNCTION (X) #DECL ((X) FIX) .X> '(1 A)>")) "(1 A)")
(check-exn #rx"No map|no active MAPF" (lambda () (run "<MAPRET 1>")))
(check-exn #rx"No map|no active MAPF" (lambda () (run "<MAPSTOP 1>")))
(check-exn #rx"No map|no active MAPF" (lambda () (run "<MAPLEAVE 1>")))

;; An error during loopf must not leave a usable map control continuation.
(parameterize ([current-namespace ns]
               [current-mdl-globals (make-hasheq)]
               [current-mdl-locals (list (make-hasheq))]
               [current-mdl-atom-space (make-mdl-atom-space)])
  (define expressions
    (compile-program
     (parse-mdl "<MAPF ,LIST <FUNCTION (X) <ERROR MAP-BOOM>> '(1)> <MAPRET 7>")))
  (check-exn #rx"MAP-BOOM" (lambda () (eval (car expressions))))
  (check-exn #rx"No map" (lambda () (eval (cadr expressions)))))
