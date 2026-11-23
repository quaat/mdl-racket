#lang racket/base
;; M4 KNOWN FRONTIER (not parity). Records the first strict failures observed
;; next to scenario 1 (docs/evidence/M4/S1-HOUSE-CELLAR-FRONTIER.md), so a
;; change that moves the frontier is noticed: each case asserts the exact text
;; printed before the failure and the exact error. When a slice implements the
;; construct, the case must be replaced by a reference-compared scenario.
;;
;;   F1  drop leaflet -> DROPPER (77rooms.mud:1239) -> DEFMAC INSERT-OBJECT
;;       (77defs.mud:332-336) expands <CHTYPE <FORM ROBJS .ROOM> SEGMENT>:
;;       TYPE SEGMENT is unknown to the runtime. Native prints "Dropped.".
;;   F2  kill troll (from the cellar) -> ORTELL (77np.mud:226) -> PRSTR ->
;;       FOOSTR (77np.mud:241) <CHTYPE <+ 32 <ASCII ...>> CHARACTER>:
;;       FIX -> CHARACTER is an unsupported built-in conversion. Native
;;       prints "with what?".
;;
;; (The game sources have CRLF line ends; a multi-line string literal keeps its
;; CR, exactly as Confusion prints it.)
;; Fixed session clock 250776000 / UTC; guarded like the S1 test (no writes);
;; watchdogged. Run with: racket tests/historical_m4_frontier_test.rkt
(require rackunit racket/runtime-path racket/port racket/string racket/list
         racket/file "../mdl/loader.rkt")

(current-check-handler (lambda (e) (raise e)))

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(unless (directory-exists? source-root)
  (error 'historical-m4-frontier "pinned source missing: ~a" source-root))

(define original-guard (current-security-guard))
(define (run-game lines)
  (define input (open-input-string (apply string-append (map (lambda (l) (string-append l "\n")) lines))))
  (define output (open-output-string))
  (define cwd (make-temporary-file "m4-frontier-cwd-~a" 'directory))
  (define writes '())
  (define guard
    (make-security-guard
     original-guard
     (lambda (who path modes)
       (when (and path (or (memq 'write modes) (memq 'delete modes)))
         (set! writes (cons (list who path modes) writes))))
     (lambda (who host port mode) (void))))
  (define session
    (make-mdl-session source-root #:input-port input #:output-port output
                      #:clock (make-fixed-mdl-clock 250776000) #:time-zone 'utc))
  (define done (make-channel))
  (define worker
    (parameterize ([current-security-guard guard] [current-directory cwd])
      (thread
       (lambda ()
         (channel-put
          done
          (with-handlers ([(lambda (v) #t) (lambda (v) (list #f v))])
            (define report (mdl-session-load! session "77loadall.mud"))
            (list report
                  (with-handlers ([(lambda (v) #t) values])
                    (mdl-session-run-interactive session "SAVE-IT")))))))))
  (define outcome
    (or (sync/timeout 300 done) (begin (kill-thread worker) (list #f 'timed-out))))
  (delete-directory/files cwd)
  (check-equal? writes '())
  (check-equal? (hash-ref (first outcome) 'status) "PASS")
  (values (second outcome) (get-output-string output) (port->string input)))

(define (check-frontier label lines expected-tail expected-message)
  (define-values (result raw unread) (run-game lines))
  (check-pred exn:fail? result label)
  (check-false (exn:fail:mdl-input-exhausted? result) label)
  (check-equal? (exn-message result) expected-message label)
  (check-true (string-suffix? raw expected-tail)
              (format "~a: output tail ~s" label
                      (substring raw (max 0 (- (string-length raw) 200)))))
  (check-equal? unread "" label)
  (printf "~a: strict failure as recorded: ~a\n" label expected-message))

(check-frontier "F1 drop"
                '("open mailbox" "take leaflet" "drop leaflet")
                ">Opening the mailbox reveals a leaflet.\n>Taken.\n>"
                "mdl-typeprim: unknown MDL TYPE SEGMENT")

(check-frontier "F2 orphan prompt"
                '("north" "east" "open window" "west" "west" "take lamp" "move rug"
                  "open trap door" "turn on lamp" "down" "east" "kill troll")
                "A nasty-looking troll, brandishing a bloody axe, blocks all passages\r\nout of the room.\n>"
                "mdl-chtype: unsupported built-in TYPE conversion")
