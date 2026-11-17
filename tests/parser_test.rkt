#lang racket/base
(require rackunit racket/list "../mdl/parser.rkt")

(define nodes
  (parse-mdl "; commentary\n<DEFINE PROB (NUM) <L=? <MOD <RANDOM> 100> .NUM>>\n#ROOM {\"WHOUS\" \"West of House\"}\n"))
(check-equal? (length nodes) 2)
(check-equal? (map mdl-node-kind nodes) '(form typed))
(check-equal? (mdl-node-line (car nodes)) 2)
(check-equal? (mdl-node-value (car (mdl-node-value (car nodes)))) "DEFINE")
(define typed (second nodes))
(check-equal? (car (mdl-node-value typed)) "#ROOM")
(check-equal? (mdl-node-kind (cdr (mdl-node-value typed))) 'brace)

(define extras (parse-mdl "'![1 2] ,VALUE .NUM %<> !.ROOMS"))
(check-equal? (map mdl-node-kind extras) '(quote global local percent splice))
(check-exn exn:fail? (lambda () (parse-mdl "<DEFINE X (A) <+ .A 1>")))
(check-exn exn:fail? (lambda () (parse-mdl "\"unterminated")))
(displayln "reader smoke tests passed")
