#lang racket/base
;; Local, root-restricted MDL source execution. No network entry point.
(require racket/file racket/list racket/path racket/string
         "parser.rkt" "compiler.rkt" "runtime/core.rkt")
(provide make-mdl-session mdl-session? mdl-session-load!
         mdl-session-global mdl-session-call exn:fail:mdl-load?
         exn:fail:mdl-load-diagnostic)

(struct mdl-session (root globals locals atoms namespace events) #:transparent)
(struct exn:fail:mdl-load exn:fail (diagnostic) #:transparent)
(define current-load-chain (make-parameter '())) ; canonical paths, entry first
(define-namespace-anchor anchor)
(define loader-namespace (namespace-anchor->namespace anchor))
(define max-load-depth 32)

(define (call-in-session session thunk)
  (parameterize ([current-namespace (mdl-session-namespace session)]
                 [current-mdl-globals (mdl-session-globals session)]
                 [current-mdl-locals (mdl-session-locals session)]
                 [current-mdl-atom-space (mdl-session-atoms session)])
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

(define (make-mdl-session source-root)
  (define root (canonical-path (path->complete-path source-root)))
  (unless (directory-exists? root)
    (raise-argument-error 'make-mdl-session "existing source-root directory" source-root))
  (define session
    (mdl-session root (make-hasheq) (list (make-hasheq))
                 (make-mdl-atom-space) loader-namespace (box '())))
  (call-in-session session
    (lambda ()
      (mdl-define! "FLOAD"
                   (lambda (name)
                     (unless (string? name)
                       (error 'mdl-fload "FLOAD expects a STRING path"))
                     (load-internal! session name)))))
  session)

(define (inside-root? root path)
  (define rel (find-relative-path root path))
  (not (memq 'up (explode-path rel))))

(define (canonical-path absolute)
  ;; simplify-path does not follow a final symlink. Resolve every component
  ;; before checking containment, including links to directories.
  (define pieces (explode-path (simplify-path absolute #f)))
  (define (follow-link path)
    (let loop ([candidate path] [hops 0])
      (when (> hops 32) (error 'mdl-loader "symlink depth limit exceeded"))
      (if (link-exists? candidate)
          (loop (simplify-path
                 (path->complete-path (resolve-path candidate)
                                      (path-only candidate)) #f)
                (add1 hops))
          candidate)))
  (for/fold ([current (car pieces)]) ([piece (in-list (cdr pieces))])
    (follow-link (build-path current piece))))

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

(define (load-internal! session requested)
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
    (define nodes
      (with-handlers ([exn:fail:mdl-reader?
                       (lambda (e)
                         (fail! session "reader" "parse" file #f
                                (mdl-node 'file #f
                                          (exn:fail:mdl-reader-line e)
                                          (exn:fail:mdl-reader-column e))
                                (exn-message e)))]
                      [exn:fail?
                       (lambda (e)
                         (fail! session "reader" "parse" file #f #f
                                (exn-message e)))])
        (parse-mdl source #:source file)))
    (for ([node (in-list nodes)] [index (in-naturals 1)])
      (define compiled
        (with-handlers ([exn:fail:mdl-compiler?
                         (lambda (e)
                           (fail! session "compiler" "compile" file index
                                  (exn:fail:mdl-compiler-node e)
                                  (exn-message e)))]
                        [exn:fail?
                         (lambda (e)
                           (fail! session "compiler" "compile" file index node
                                  (exn-message e)))])
          (compile-expression node)))
      (with-handlers ([exn:fail:mdl-load?
                       (lambda (e)
                         (record! session
                                  (hash-set
                                   (diagnostic session "nested-load" "execute"
                                               file index node (exn-message e))
                                   'status "FAIL"))
                         (raise e))]
                      [exn:fail?
                       (lambda (e)
                         (fail! session "runtime" "execute" file index node
                                (exn-message e)))])
        (eval compiled)
        (record! session
                 (hash 'status "PASS" 'file file 'expression_index index
                       'line (mdl-node-line node) 'column (mdl-node-column node)
                       'construct (construct-name node)
                       'load_chain (chain-names session)))))
    "DONE"))

(define (mdl-session-load! session entry)
  (unless (mdl-session? session)
    (raise-argument-error 'mdl-session-load! "mdl-session?" session))
  (unless (string? entry)
    (raise-argument-error 'mdl-session-load! "string?" entry))
  (set-box! (mdl-session-events session) '())
  (call-in-session session
    (lambda ()
      (parameterize ([current-load-chain '()])
        (define failure #f)
        (with-handlers ([exn:fail:mdl-load?
                         (lambda (e)
                           (set! failure (exn:fail:mdl-load-diagnostic e))
                           (void))])
          (load-internal! session entry))
        (define events (reverse (unbox (mdl-session-events session))))
        (hash 'status (if failure "FAIL" "PASS")
              'entry entry
              'completed_expressions
              (length (filter (lambda (e) (equal? (hash-ref e 'status) "PASS")) events))
              'events events
              'failure failure)))))

(define (mdl-session-global session name)
  (call-in-session session (lambda () (mdl-gval name))))

(define (mdl-session-call session name . args)
  (call-in-session session (lambda () (apply mdl-apply name args))))
