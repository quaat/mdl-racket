#lang racket/base

(require json racket/match racket/path
         "../../mdl/loader.rkt" "../../mdl/runtime/core.rkt")

;; One process and one temporary source root per case and execution path.
(define (describe value call)
  (define type (mdl-atom-pname (call "TYPE" value)))
  (define primtype (mdl-atom-pname (call "PRIMTYPE" value)))
  (define data
    (match type
      [(or "FIX" "FLOAT") value]
      ["ATOM" (mdl-atom-pname value)]
      ["STRING" (mdl-string-snapshot 'manual-test value "expected STRING")]
      ["CHARACTER" (call "ASCII" value)]
      ["WORD" (mdl-word-bits value)]
      ["FALSE" (map (lambda (item) (describe item call)) (mdl-false-payload value))]
      [(or "LIST" "VECTOR" "UVECTOR")
       (for/list ([index (in-range 1 (add1 (mdl-length value)))])
         (describe (mdl-nth value index) call))]
      [_ (error 'manual-test "no observation for MDL TYPE ~a" type)]))
  (hash 'value data 'type type 'primtype primtype))

(match-define (vector mode filename) (current-command-line-arguments))
(define file (path->complete-path filename))
(define result-port (current-output-port))
(define output (open-output-string))
(define (observations get call)
  (hash 'result (describe (get "CONFORMANCE-RESULT") call)
        'effect (describe (get "CONFORMANCE-EFFECT") call)))

(define report
  (parameterize ([current-output-port output]
                 [current-input-port (open-input-string "")]
                 ;; Keep the module host printer separate from explicit MDL I/O.
                 [current-print void])
    (cond
      [(equal? mode "loader")
       (define session (make-mdl-session (path-only file)
                                         #:output-port output
                                         #:input-port (current-input-port)
                                         #:clock (make-fixed-mdl-clock 250776000)
                                         #:time-zone 'utc))
       (define load-report (mdl-session-load! session (path->string (file-name-from-path file))))
       (cond
         [(equal? (hash-ref load-report 'status) "PASS")
          (observations (lambda (name) (mdl-session-global session name))
                        (lambda args (apply mdl-session-call session args)))]
         [else (hash 'status (hash-ref load-report 'status)
                     'failure (or (hash-ref load-report 'failure) 'null))])]
      [(equal? mode "lang")
       ;; The instantiation is eligible for a fixture diagnostic. A failure
       ;; while observing the result must fail the entire worker process.
       (define failure
         (with-handlers ([exn:fail? (lambda (e) (exn-message e))])
           (dynamic-require file #f)
           #f))
       (if failure
           (hash 'status "FAIL" 'failure (hash 'exception failure))
           (observations mdl-gval mdl-apply))]
      [else (error 'manual-test "unknown execution path ~a" mode)])))
(write-json (hash-set report 'output (get-output-string output)) result-port)
(newline result-port)
