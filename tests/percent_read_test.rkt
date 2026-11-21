#lang racket/base
(require rackunit racket/file "../mdl/parser.rkt" "../mdl/loader.rkt"
         "../mdl/runtime/core.rkt")

;; The inventory reader remains syntax-only, even for the original source.
(define original "<READSTRING .INBUF .INCHAN %<STRING <ASCII 10>>>")
(define parsed (parse-mdl original))
(check-equal? (mdl-node-kind (list-ref (mdl-node-value (car parsed)) 3)) 'percent)

(define root (make-temporary-file "/tmp/mdl-percent-read~a" 'directory))
(define (put name source) (call-with-output-file (build-path root name)
                            (lambda (out) (display source out))))
(define (status report) (hash-ref report 'status))
(define (failure report) (hash-ref report 'failure))
(dynamic-wind
  void
  (lambda ()
    (put "read.mud"
         (string-append
          "<SETG N 0>\n"
          "<SETG ORDER [%<SETG N <+ ,N 1>> %<SETG N <+ ,N 1>>]>\n"
          "<DEFINE ONCE () %<SETG N <+ ,N 1>>>\n"
          "<DEFINE KEEP () '%<LIST 1>>\n"
          "<SETG NEWLINE %<STRING <ASCII 10>>>\n"
          "<SETG BEFORE <LIST <SETG N 8> %<+ ,N 1>>>\n"
          "<SETG NEST '(%<LIST 1>)>\n"
          "<SETG EMPTY %<>>\n"
          "<SETG ASTR <STRING <ASCII 65> \"B\">>\n"
          "<SETG EVALFORM %'<+ 1 2>>\n"
          "<DEFINE %'DYNAMIC (X) .X>\n"
          "<DEFINE FORMAL (%'X) .X>\n"
          "<DEFINE FORMLIST %'(Y) .Y>\n"
          "<SETG QUOTEDFORM '%'<+ 1 2>>\n"
          "<SETG EVALLIST %'(1 <+ 1 1>)>\n"))
    (define session (make-mdl-session root))
    (check-equal? (status (mdl-session-load! session "read.mud")) "PASS")
    (check-equal? (mdl-session-global session "NEWLINE") "\n")
    (check-equal? (mdl-session-global session "ASTR") "AB")
    (check-equal? (mdl-session-global session "EVALFORM") 3)
    (check-equal? (mdl-session-call session "DYNAMIC" 7) 7)
    (check-equal? (mdl-session-call session "FORMAL" 5) 5)
    (check-equal? (mdl-session-call session "FORMLIST" 9) 9)
    (check-equal? (mdl-atom-pname
                   (mdl-session-call session "TYPE"
                                     (mdl-session-global session "QUOTEDFORM")))
                  "FORM")
    (check-equal? (mdl-list->list (mdl-session-global session "EVALLIST")) '(1 2))
    (check-equal? (mdl-session-global session "N") 8)
    (check-equal? (mdl-list->list (mdl-session-global session "BEFORE")) '(8 4))
    (check-equal? (mdl-session-call session "NTH"
                                     (mdl-session-global session "ORDER") 1) 1)
    (check-equal? (mdl-session-call session "NTH"
                                     (mdl-session-global session "ORDER") 2) 2)
    (check-equal? (mdl-session-call session "ONCE") 3)
    (check-equal? (mdl-session-call session "ONCE") 3)
    (check-equal? (mdl-session-global session "N") 8)
    (check-eq? (mdl-session-call session "KEEP")
               (mdl-session-call session "KEEP"))
    (check-true (mdl-false? (mdl-session-global session "EMPTY")))
    (define ch (mdl-session-call session "ASCII" 10))
    (check-equal? (mdl-atom-pname (mdl-session-call session "TYPE" ch)) "CHARACTER")
    (check-equal? (mdl-session-call session "ASCII" ch) 10)
    (check-exn exn:fail? (lambda () (mdl-session-call session "ASCII" 128)))
    (check-exn exn:fail? (lambda () (mdl-session-call session "STRING" 10)))
    (define independent (make-mdl-session root))
    (check-equal? (status (mdl-session-load! independent "read.mud")) "PASS")
    (check-false (eq? (mdl-session-call session "KEEP")
                      (mdl-session-call independent "KEEP")))
    (put "outer.mud" "<SETG SHARED 1>\n<FLOAD \"child.mud\">\n")
    (put "child.mud" "<SETG CHILD %<+ ,SHARED 2>>\n")
    (check-equal? (status (mdl-session-load! session "outer.mud")) "PASS")
    (check-equal? (mdl-session-global session "CHILD") 3)
    (put "bad.mud" "<SETG BAD %<M3-NO-SUCH>>\n")
    (define bad (mdl-session-load! session "bad.mud"))
    (check-equal? (status bad) "FAIL")
    (check-equal? (hash-ref (failure bad) 'stage) "read-eval")
    (check-equal? (hash-ref (failure bad) 'line) 1)
    (check-equal? (hash-ref (failure bad) 'column) 11)
    (put "bad-form.mud" "<SETG BADFORM %'<M3-NO-SUCH>>\n")
    (define bad-form (mdl-session-load! session "bad-form.mud"))
    (check-equal? (status bad-form) "FAIL")
    (check-equal? (hash-ref (failure bad-form) 'stage) "execute")
    (put "unsupported.mud" "<SETG BAD %%<SETG N 99>>\n")
    (check-equal? (status (mdl-session-load! session "unsupported.mud")) "FAIL")
    (check-equal? (mdl-session-global session "N") 8)
    (displayln "session-aware percent READ tests passed"))
  (lambda () (delete-directory/files root)))
