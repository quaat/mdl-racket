#lang racket/base
;; Local, root-restricted MDL source execution. No network entry point.
(require racket/file racket/list racket/path racket/string
         "parser.rkt" "compiler.rkt" "runtime/core.rkt")
(provide make-mdl-session mdl-session? mdl-session-load!
         mdl-session-atom mdl-session-global mdl-session-call
         mdl-session-save-records exn:fail:mdl-load?
         exn:fail:mdl-load-diagnostic
         mdl-session-run-interactive
         exn:fail:mdl-input-exhausted exn:fail:mdl-input-exhausted?)

;; input-port/output-port: the explicit host ports given to make-mdl-session
;; (#f when omitted); the host top-level loop requires both (ADR-0050).
(struct mdl-session (root globals locals atoms namespace events read-values
                          input-port output-port) #:transparent)
(struct exn:fail:mdl-load exn:fail (diagnostic) #:transparent)
(define current-load-chain (make-parameter '())) ; canonical paths, entry first
(define-namespace-anchor anchor)
(define loader-namespace (namespace-anchor->namespace anchor))
(define max-load-depth 32)

(define (call-in-session session thunk)
  (parameterize ([current-namespace (mdl-session-namespace session)]
                 [current-mdl-globals (mdl-session-globals session)]
                 [current-mdl-locals (mdl-session-locals session)]
                 [current-mdl-atom-space (mdl-session-atoms session)]
                 [current-mdl-read-values (mdl-session-read-values session)])
    (thunk)))

(define (relative-name session path)
  (path->string (find-relative-path (mdl-session-root session) path)))

(define (chain-names session [next #f])
  (map (lambda (path) (relative-name session path))
       (if next (append (current-load-chain) (list next))
           (current-load-chain))))

(define (record! session event)
  (set-box! (mdl-session-events session)
            (cons event (unbox (mdl-session-events session)))))

(define (construct-name node)
  (cond
    [(and node (eq? (mdl-node-kind node) 'form)
          (pair? (mdl-node-value node))
          (eq? (mdl-node-kind (car (mdl-node-value node))) 'atom))
     (string-upcase (mdl-node-value (car (mdl-node-value node))))]
    [(and node (eq? (mdl-node-kind node) 'atom))
     (string-upcase (mdl-node-value node))]
    [node (symbol->string (mdl-node-kind node))]
    [else "<file>"]))

(define (diagnostic session classification stage file index node message [chain #f])
  (hash 'classification classification 'stage stage 'file file
        'expression_index index
        'line (and node (mdl-node-line node))
        'column (and node (mdl-node-column node))
        'construct (construct-name node)
        'load_chain (or chain (chain-names session))
        'exception message))

(define (fail! session classification stage file index node message [chain #f])
  (define info (diagnostic session classification stage file index node message chain))
  (record! session (hash-set info 'status "FAIL"))
  (raise (exn:fail:mdl-load message (current-continuation-marks) info)))

;; output-port / input-port: host ports owned by this session's terminal
;; CHANNELs. #f (default) follows the current Racket port at each operation.
;; READSTRING reads input-port (ADR-0050).
(define (make-mdl-session source-root #:output-port [output-port #f]
                          #:input-port [input-port #f])
  (define root (canonical-path (path->complete-path source-root)))
  (unless (directory-exists? root)
    (raise-argument-error 'make-mdl-session "existing source-root directory" source-root))
  (when (and output-port (not (output-port? output-port)))
    (raise-argument-error 'make-mdl-session "(or/c #f output-port?)" output-port))
  (when (and input-port (not (input-port? input-port)))
    (raise-argument-error 'make-mdl-session "(or/c #f input-port?)" input-port))
  ;; The shared context constructor binds INCHAN/OUTCHAN (LVAL and GVAL)
  ;; to this session's terminal CHANNELs before any source runs.
  ;; ADR-0050: there is no input default; READSTRING on a session made
  ;; without #:input-port is a strict error (never the process's stdin).
  (define context (make-mdl-context #:output-port output-port
                                    #:input-port input-port))
  (define session
    (mdl-session root (mdl-context-globals context) (mdl-context-locals context)
                 (mdl-context-atom-space context) loader-namespace (box '())
                 (make-hash) input-port output-port))
  (call-in-session session
    (lambda ()
      ;; Interpreter-supplied globals (MUDDLE, issue #51) intern in THIS
      ;; session's atom space, so they must be seeded with the session's
      ;; space current — interning earlier would produce a different atom
      ;; identity than later GVAL lookups.
      (hash-set! (current-mdl-globals)
                 (mdl-root-atom "MUDDLE") mdl-interpreter-version)
      (mdl-define! (mdl-root-atom "FLOAD")
                   (lambda (name)
                     (load-internal!
                      session
                      (mdl-string-snapshot 'mdl-fload name
                                           "FLOAD expects a STRING path"))))))
  session)

(define (inside-root? root path)
  (define rel (find-relative-path root path))
  (not (memq 'up (explode-path rel))))

(define (canonical-path absolute)
  ;; A link target can itself contain links in intermediate components.
  ;; Replay every target from its root, then continue with the remaining
  ;; suffix, so containment checks match the file that will be opened.
  (define (pieces path)
    (explode-path (path->complete-path path)))
  (let loop ([pending (pieces absolute)] [current #f] [hops 0])
    (cond
      [(null? pending) current]
      [else
       (define part (car pending))
       (when (eq? part 'up)
         (unless current (error 'mdl-loader "parent component before path root")))
       (define next
         (if current (build-path current part) part))
       (cond
         [(eq? part 'up)
          (loop (cdr pending) (simplify-path next #f) hops)]
         [(link-exists? next)
          (when (>= hops 32)
            (error 'mdl-loader "symlink depth limit exceeded"))
          (loop (append
                 (pieces (path->complete-path (resolve-path next)
                                            (path-only next)))
                 (cdr pending))
                #f (add1 hops))]
         [else (loop (cdr pending) next hops)])])))

(define (resolve-source session requested)
  (define base
    (if (null? (current-load-chain))
        (mdl-session-root session)
        (path-only (last (current-load-chain)))))
  (define raw (string->path requested))
  (when (memq 'up (explode-path raw))
    (fail! session "security" "resolve" "<outside-root>" #f #f
           "parent path component is not permitted"))
  (define absolute (path->complete-path raw base))
  (define canonical (canonical-path absolute))
  (unless (inside-root? (mdl-session-root session) canonical)
    (fail! session "security" "resolve" "<outside-root>" #f #f
           "source path escapes authorized root"))
  canonical)

(define (load-internal! session requested [max-expressions #f]
                        [skipped-box (box 0)])
  (define path
    (with-handlers ([exn:fail:mdl-load? raise]
                    [exn:fail?
                     (lambda (e)
                       (fail! session "filesystem" "resolve" requested #f #f
                              (exn-message e)))])
      (resolve-source session requested)))
  (define file (relative-name session path))
  (when (member path (current-load-chain))
    (fail! session "cycle" "resolve" file #f #f
           "cyclic FLOAD chain" (chain-names session path)))
  (when (>= (length (current-load-chain)) max-load-depth)
    (fail! session "cycle" "resolve" file #f #f
           "FLOAD depth limit exceeded" (chain-names session path)))
  (parameterize ([current-load-chain (append (current-load-chain) (list path))])
    (define source
      (with-handlers ([exn:fail?
                       (lambda (e)
                         (fail! session "filesystem" "read" file #f #f
                                (exn-message e)))])
        (file->string path)))
    (define reading-index (box 1))
    (define (read-eval percent-node)
      (with-handlers ([exn:fail:mdl-load? raise]
                      [exn:fail?
                       (lambda (e)
                         (fail! session "reader" "read-eval" file
                                (unbox reading-index) percent-node
                                (exn-message e)))])
        (define value (eval (compile-expression (mdl-node-value percent-node))))
        (mdl-node 'read-value (mdl-register-read-value! value)
                  (mdl-node-line percent-node) (mdl-node-column percent-node))))
    (define next-node
      (make-mdl-node-reader source #:source file #:read-eval read-eval))
    (let loop ([index 1])
      (set-box! reading-index index)
      (if (and max-expressions (> index max-expressions))
          (let ([total
                 ;; Counting skipped forms is diagnostic only. An explicit
                 ;; prefix never evaluates or requires the remaining forms.
                 (with-handlers ([exn:fail? (lambda (_) #f)])
                   (length (parse-mdl source #:source file)))])
            (set-box! skipped-box (and total (- total max-expressions)))
            (if (and total (= total max-expressions)) "DONE" "PARTIAL"))
          (let ([node
                 (with-handlers ([exn:fail:mdl-load? raise]
                                 [exn:fail:mdl-reader?
                                  (lambda (e)
                                    (fail! session "reader" "parse" file index
                                           (mdl-node 'file #f
                                                     (exn:fail:mdl-reader-line e)
                                                     (exn:fail:mdl-reader-column e))
                                           (exn-message e)))]
                                 [exn:fail?
                                  (lambda (e)
                                    (fail! session "reader" "parse" file index #f
                                           (exn-message e)))])
                   (next-node))])
            (if (not node)
                "DONE"
                (let ([compiled
                       (with-handlers ([exn:fail:mdl-compiler?
                                        (lambda (e)
                                          (fail! session "compiler" "compile"
                                                 file index
                                                 (exn:fail:mdl-compiler-node e)
                                                 (exn-message e)))]
                                       [exn:fail?
                                        (lambda (e)
                                          (fail! session "compiler" "compile"
                                                 file index node (exn-message e)))])
                         (compile-expression node))])
                  (with-handlers ([exn:fail:mdl-load?
                                   (lambda (e)
                                     (record! session
                                              (hash-set
                                               (diagnostic session "nested-load"
                                                           "execute" file index node
                                                           (exn-message e))
                                               'status "FAIL"))
                                     (raise e))]
                                  [exn:fail?
                                   (lambda (e)
                                     (fail! session "runtime" "execute" file
                                            index node (exn-message e)))])
                    (eval compiled)
                    (record! session
                             (hash 'status "PASS" 'file file
                                   'expression_index index
                                   'line (mdl-node-line node)
                                   'column (mdl-node-column node)
                                   'construct (construct-name node)
                                   'load_chain (chain-names session))))
                  (loop (add1 index)))))))))

(define (mdl-session-load! session entry #:max-expressions [max-expressions #f])
  (unless (mdl-session? session)
    (raise-argument-error 'mdl-session-load! "mdl-session?" session))
  (unless (string? entry)
    (raise-argument-error 'mdl-session-load! "string?" entry))
  (when (and max-expressions
             (not (exact-positive-integer? max-expressions)))
    (raise-argument-error 'mdl-session-load!
                          "exact-positive-integer?" max-expressions))
  (set-box! (mdl-session-events session) '())
  (call-in-session session
    (lambda ()
      (parameterize ([current-load-chain '()])
        (define failure #f)
        (define result #f)
        (define skipped (box 0))
        (with-handlers ([exn:fail:mdl-load?
                         (lambda (e)
                           (set! failure (exn:fail:mdl-load-diagnostic e))
                           (void))])
          (set! result (load-internal! session entry max-expressions skipped)))
        (define events (reverse (unbox (mdl-session-events session))))
        (hash 'status (cond [failure "FAIL"]
                            [(equal? result "PARTIAL") "PARTIAL"]
                            [else "PASS"])
              'entry entry
              'skipped_expressions (unbox skipped)
              'completed_expressions
              (length (filter (lambda (e) (equal? (hash-ref e 'status) "PASS")) events))
              'events events
              'failure failure)))))

(define (mdl-session-global session name)
  (call-in-session session (lambda () (mdl-gval name))))

;; Test/introspection boundary: obtain the atom interned by this session's
;; source reader without exposing arbitrary evaluation.
(define (mdl-session-atom session name)
  (call-in-session session (lambda () (mdl-atom name))))

;; Test/introspection boundary (ADR-0048): the session's SAVE records,
;; oldest first. Host-only; no MDL primitive exposes them.
(define (mdl-session-save-records session)
  (call-in-session session mdl-save-records))

(define (apply-global name args)
  (define fn (mdl-gval name))
  (cond
    [(mdl-macro? fn) (mdl-eval (mdl-apply-interpreted fn args))]
    [(mdl-function? fn) (mdl-apply-interpreted fn args #t)]
    [else (apply mdl-apply name args)]))

(define (mdl-session-call session name . args)
  (call-in-session session (lambda () (apply-global name args))))

;; ADR-0049 part 3 / ADR-0050: run a loaded game session interactively. Local
;; host API only: no network or web entry point, and no MDL evaluator; input
;; reaches MDL only through the program's own READSTRING. ENTRY names the
;; GVAL applied with no arguments (for run.mud: "SAVE-IT", after the caller
;; has loaded 77loadall.mud). The session must have been made with explicit
;; #:input-port and #:output-port, so the loop never reads the process's own
;; standard input. It ends only by an exception; exhausted input is
;; exn:fail:mdl-input-exhausted, which a host reports as a failure.
(define (mdl-session-run-interactive session entry #:max-passes [max-passes #f]
                                     #:on-event [on-event void])
  (unless (mdl-session? session)
    (raise-argument-error 'mdl-session-run-interactive "mdl-session?" session))
  (unless (string? entry)
    (raise-argument-error 'mdl-session-run-interactive "string?" entry))
  (unless (and (mdl-session-input-port session) (mdl-session-output-port session))
    (error 'mdl-session-run-interactive
           "requires a session made with explicit #:input-port and #:output-port (ADR-0050)"))
  (call-in-session
   session
   (lambda ()
     (mdl-run-host-loop (lambda () (apply-global entry '()))
                        #:max-passes max-passes #:on-event on-event))))
