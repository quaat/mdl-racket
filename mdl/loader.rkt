#lang racket/base
;; Local, root-restricted MDL source execution. No network entry point.
(require racket/file racket/list racket/path racket/string
         "parser.rkt" "compiler.rkt" "runtime/core.rkt" "runtime/clock.rkt"
         (only-in "runtime/random36.rkt" random36-state-words random36-state-draws))
(provide make-mdl-session mdl-session? mdl-session-load!
         mdl-session-atom mdl-session-global mdl-session-call
         mdl-session-save-records exn:fail:mdl-load?
         exn:fail:mdl-load-diagnostic
         mdl-session-run-interactive
         exn:fail:mdl-input-exhausted exn:fail:mdl-input-exhausted?
         mdl-session-random-snapshot random36-state-words random36-state-draws
         mdl-session-mdl-errors mdl-session-storage-stats
         mdl-clock? make-mdl-clock make-fixed-mdl-clock real-mdl-clock
         mdl-host-loop-secondary-failures
         mdl-quit-signal? mdl-session-outcome? mdl-session-outcome-kind
         mdl-session-outcome-mdl-errors
         mdl-session-open-records mdl-open-record? mdl-open-record-mode
         mdl-open-record-file-spec mdl-open-record-status
         mdl-read-only-file mdl-read-only-file? mdl-session-file-channels)

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
;; CHANNELs. READSTRING reads input-port (ADR-0050). Neither has a fallback:
;; a session made without #:input-port refuses READSTRING, and one made
;; without #:output-port refuses every terminal write and flush (PRINC, PRIN1,
;; PRINTSTRING, TERPRI, CRLF, READSTRING's pre-read flush, the host loop's
;; prints and final flush) with a strict ADR-0050 error; it never writes to
;; the host's current-output-port (S13 part B). A host that wants the
;; process's stdout passes (current-output-port) explicitly.
;; clock / time-zone (ADR-0052): the session's own host clock for
;; GETTIMEDATE's "now" (default: the real wall clock) and its local zone
;; ('local, the host zone, by default; or 'utc). Stored in the session's atom
;; space; never process-global.
;; input-observer (ADR-0061): an optional host-only procedure called by
;; READSTRING ('enter at each call's entry, 'complete with the raw characters
;; the call consumed); the replay persistence host uses it. MDL code cannot
;; reach it. File READSTRING (below) never calls it.
;; read-only-files (M4 S10, #171; ADR-0055 amendment): the host's read-only
;; allowlist, a list of mdl-read-only-file entries (default: none, so OPEN
;; "READ" reads nothing). Each names directory/name1.name2 inside SOURCE-ROOT;
;; read-only-file-bytes below reads it at each granted OPEN.
(define (make-mdl-session source-root #:output-port [output-port #f]
                          #:input-port [input-port #f]
                          #:clock [clock real-mdl-clock]
                          #:time-zone [time-zone 'local]
                          #:input-observer [input-observer #f]
                          #:read-only-files [read-only-files '()])
  (define root (canonical-path (path->complete-path source-root)))
  (unless (directory-exists? root)
    (raise-argument-error 'make-mdl-session "existing source-root directory" source-root))
  (when (and output-port (not (output-port? output-port)))
    (raise-argument-error 'make-mdl-session "(or/c #f output-port?)" output-port))
  (when (and input-port (not (input-port? input-port)))
    (raise-argument-error 'make-mdl-session "(or/c #f input-port?)" input-port))
  (unless (mdl-clock? clock)
    (raise-argument-error 'make-mdl-session "mdl-clock?" clock))
  (unless (mdl-time-zone? time-zone)
    (raise-argument-error 'make-mdl-session "(or/c 'local 'utc)" time-zone))
  ;; The shared context constructor binds INCHAN/OUTCHAN (LVAL and GVAL)
  ;; to this session's terminal CHANNELs before any source runs.
  ;; ADR-0050: there is no input or output default; READSTRING on a session
  ;; made without #:input-port is a strict error (never the process's stdin),
  ;; and so is any terminal output without #:output-port (S13 part B; never
  ;; the host's current-output-port). The follow-current-output-port opt-in
  ;; of mdl-ensure-terminal-channels! is deliberately not offered here.
  (define context (make-mdl-context #:output-port output-port
                                    #:input-port input-port
                                    #:clock clock #:time-zone time-zone
                                    #:input-observer input-observer
                                    #:read-only-files read-only-files
                                    #:read-only-reader
                                    (lambda (entry) (read-only-file-bytes root entry))))
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
      ;; FLOAD is a SUBR (pinned Confusion <TYPE ,FLOAD> = SUBR; ADR-0060).
      (mdl-define-subr! (mdl-root-atom "FLOAD")
                   (lambda (name)
                     (load-internal!
                      session
                      (mdl-string-snapshot 'mdl-fload name
                                           "FLOAD expects a STRING path"))))))
  session)

;; M4 S10 (#171; ADR-0055 amendment): the content of one allowlisted file,
;; ROOT/directory/name1.name2 (ROOT is the session's canonical root). Strict
;; on: a symbolic link as the directory or the file, a missing directory or
;; file (a broken install, never FALSE), a non-regular file, a size other than
;; the pinned one (checked before reading), a file whose identity changed
;; between the checks and the open, and a content length other than the
;; pinned size. The host file is closed on every path, including a failure
;; (call-with-input-file*, independent review of S10); the runtime checks
;; the sha256. Only paths inside ROOT are touched, and only for reading.
(define (read-only-file-bytes root entry)
  (define rel (mdl-read-only-file-relative-path entry))
  (define (fail fmt . args)
    (apply error 'OPEN (string-append "~a: " fmt " (ADR-0055 amendment)") rel args))
  (define dir (build-path root (mdl-read-only-file-directory entry)))
  (define file (build-path dir (string-append (mdl-read-only-file-name1 entry) "."
                                              (mdl-read-only-file-name2 entry))))
  (define size (mdl-read-only-file-size entry))
  (when (link-exists? dir) (fail "the directory is a symbolic link"))
  (unless (directory-exists? dir) (fail "the pinned file is missing (no directory)"))
  (when (link-exists? file) (fail "the file is a symbolic link"))
  (cond [(directory-exists? file) (fail "not a regular file")]
        [(not (file-exists? file)) (fail "the pinned file is missing")])
  (unless (inside-root? root file) (fail "outside the game directory"))
  (unless (= (file-size file) size) (fail "size ~a differs from the pinned size ~a" (file-size file) size))
  (call-with-input-file* file
    (lambda (in)
      (unless (equal? (port-file-identity in) (file-or-directory-identity file #t))
        (fail "the opened file is not the checked file"))
      (define content (read-bytes (add1 size) in))
      (define got (if (eof-object? content) #"" content))
      (unless (= (bytes-length got) size)
        (fail "size ~a differs from the pinned size ~a" (bytes-length got) size))
      (bytes->immutable-bytes got))))

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
                  (with-handlers ([mdl-quit-signal?
                                   ;; ADR-0054 item 6 (S11 review): a QUIT while
                                   ;; loading ends the program; record where,
                                   ;; then re-raise the same signal.
                                   (lambda (q)
                                     (record! session
                                              (hash 'status "QUIT" 'file file
                                                    'expression_index index
                                                    'line (mdl-node-line node)
                                                    'column (mdl-node-column node)
                                                    'construct (construct-name node)
                                                    'load_chain (chain-names session)))
                                     (raise q))]
                                  [exn:fail:mdl-load?
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
        (define quit? #f)
        (define result #f)
        (define skipped (box 0))
        (with-handlers ([exn:fail:mdl-load?
                         (lambda (e)
                           (set! failure (exn:fail:mdl-load-diagnostic e))
                           (void))]
                        ;; ADR-0054 item 6: the program QUIT during the load;
                        ;; the report says so (status "QUIT", never "PASS")
                        ;; and its last event locates the QUIT.
                        [mdl-quit-signal? (lambda (q) (set! quit? #t))])
          (set! result (load-internal! session entry max-expressions skipped)))
        (define events (reverse (unbox (mdl-session-events session))))
        (hash 'status (cond [failure "FAIL"]
                            [quit? "QUIT"]
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

;; Test/introspection boundary (ADR-0052): a detached copy of the session's
;; RANDOM state. Host-only; observing it never consumes the game's sequence.
(define (mdl-session-random-snapshot session)
  (call-in-session session mdl-random-state-snapshot))

;; Host-only (ADR-0054, ADR-0061): the messages of every MDL ERROR signalled
;; in the session so far, oldest first.
(define (mdl-session-mdl-errors session)
  (call-in-session session mdl-error-messages))

;; Host-only (ADR-0044, ADR-0061): the session's logical storage ledger
;; (capacity, used, free), read without collecting.
(define (mdl-session-storage-stats session)
  (call-in-session session mdl-logical-storage-stats))

;; Test/introspection boundary (ADR-0055): the session's denied OPEN calls
;; (mode, file spec, status), oldest first. Host-only; no MDL primitive
;; exposes them.
(define (mdl-session-open-records session)
  (call-in-session session mdl-open-records))

;; Test/introspection boundary (ADR-0048): the session's SAVE records,
;; oldest first. Host-only; no MDL primitive exposes them.
;; Host introspection (M4 S10): the session's read-only file CHANNELs,
;; oldest first, as (file-spec open|closed).
(define (mdl-session-file-channels session)
  (call-in-session session mdl-file-channels))

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
;; standard input. It returns an mdl-session-outcome only when the program
;; QUITs: kind 'quit, or 'quit-after-mdl-error when an MDL ERROR was
;; signalled during the run (ADR-0054; an acceptance run requires 'quit).
;; Every other ending raises: exhausted input is exn:fail:mdl-input-exhausted,
;; strict failures keep their exn, a break stays a break; a host reports each
;; as a failure.
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
