#lang racket/base
;; M4 KNOWN FRONTIER (not parity). Records the first strict failures observed
;; next to scenario 1 (docs/evidence/M4/S1-HOUSE-CELLAR-FRONTIER.md), so a
;; change that moves the frontier is noticed: each case asserts the exact text
;; printed before the failure and the exact error. When a slice implements the
;; construct, the case must be replaced by a reference-compared scenario.
;;
;;   F1  RESOLVED by M4 S2 (docs/evidence/M4/S2-CHTYPE-SEGMENT.md): drop
;;       leaflet -> DROPPER (77rooms.mud:1239) -> DEFMAC INSERT-OBJECT
;;       (77defs.mud:332-336) -> <CHTYPE <FORM ROBJS .ROOM> SEGMENT>. The
;;       case below is now a positive regression: the output equals the
;;       pinned reference prefix P03 of tests/scenarios/mailbox-drop.json
;;       (D1 only) and the run ends by input exhaustion. Full parity with
;;       checkpoints is tests/historical_mailbox_drop_test.rkt.
;;   F2  RESOLVED by M4 S3 (docs/evidence/M4/S3-CHTYPE-CHARACTER.md): kill
;;       troll (from the cellar) -> ORTELL (77np.mud:226) -> PRSTR -> FOOSTR
;;       (77np.mud:241) <CHTYPE <+ 32 <ASCII ...>> CHARACTER>. Now a positive
;;       regression: S1 without `score`, `east`, `kill troll`, the answer
;;       `lamp`; the output equals the pinned reference case
;;       F2-kill-troll-pipe of docs/evidence/M4/orphan-prompt-reference.json
;;       ("with what?", then "Trying to kill a troll with a lamp is
;;       suicidal."), D1 only, ending by input exhaustion.
;;   F2b RESOLVED by M4 S3: throw leaflet (DROPPER's sibling verb THROW, no
;;       indirect object) -> ORTELL -> PRSTR -> FOOSTR. Positive regression:
;;       the output equals reference prefix P03 of
;;       tests/scenarios/orphan-prompt.json ("at what?"). Full parity with
;;       checkpoints, including the answers to both prompts, is
;;       tests/historical_orphan_prompt_test.rkt.
;;   No further strict failure is reached on the F2/F2b paths (S3 evidence).
;;   F3 help / info (maintainer decision 2026-11-23: leave strict for now):
;;     HELP/INFO -> FILE-TO-TTY (77rooms.mud:954-985) -> <OPEN "READ" "MADADV"
;;     "HELP"|"INFO" ...> (77rooms.mud:961) on the pinned MDL/MADADV.HELP /
;;     MDL/MADADV.INFO. OPEN supports only RECORD's denied write modes
;;     (ADR-0055), so this is a strict error. Native prints the file text.
;;
;; (The game sources have CRLF line ends; a multi-line string literal keeps its
;; CR, exactly as Confusion prints it.)
;; Fixed session clock 250776000 / UTC; guarded like the S1 test (no writes);
;; watchdogged. Run with: racket tests/historical_m4_frontier_test.rkt
(require rackunit racket/runtime-path racket/port racket/string racket/list
         racket/file json "../mdl/loader.rkt")

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

;; An unresolved frontier case.
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

;; A resolved frontier case: the output equals a pinned reference transcript
;; (D1 only) and the run ends by input exhaustion with all input consumed.
(define (check-resolved label reference-file case-name lines must-contain)
  (define reference (call-with-input-file reference-file read-json))
  (define c (findf (lambda (c) (equal? (hash-ref c 'name) case-name)) (hash-ref reference 'cases)))
  (define ref-raw (hash-ref c 'stdout_raw))
  (define banner "LISTENING-AT-LEVEL 1 PROCESS 1\n")
  (define expected
    (string-replace (cadr (regexp-match (regexp (string-append "^.*?" (regexp-quote banner) "(.*)$"))
                                        ref-raw))
                    "\"DONE\"\n" "" #:all? #f))
  (check-equal? (hash-ref reference 'interpreter_sha256_before)
                "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789" label)
  (check-equal? (hash-ref c 'input)
                (string-append "<FLOAD \"77loadall.mud\">\n<SAVE-IT>\n"
                               (apply string-append (map (lambda (l) (string-append l "\n")) lines)))
                label)
  (define-values (result raw unread) (run-game lines))
  (check-pred exn:fail:mdl-input-exhausted? result
              (if (exn? result) (exn-message result) (format "~a" result)))
  (check-true (string-contains? raw must-contain) label)
  (check-equal? raw expected label)
  (check-equal? unread "" label))

;; F1 (resolved by S2): positive regression against the pinned reference prefix.
(define-runtime-path drop-reference-file "../docs/evidence/M4/mailbox-drop-reference.json")
(check-resolved "F1 drop" drop-reference-file "P03-mailbox-drop-prefix"
                '("open mailbox" "take leaflet" "drop leaflet") ">Dropped.\n>")
(printf "F1 drop: resolved; output equals reference P03 (D1 only)\n")

;; F2 and F2b (resolved by S3): positive regressions against the pinned
;; orphan-prompt reference.
(define-runtime-path orphan-reference-file "../docs/evidence/M4/orphan-prompt-reference.json")
(check-resolved "F2 orphan prompt" orphan-reference-file "F2-kill-troll-pipe"
                '("north" "east" "open window" "west" "west" "take lamp" "move rug"
                  "open trap door" "turn on lamp" "down" "east" "kill troll" "lamp")
                "out of the room.\n>with what?\n>Trying to kill a troll with a lamp is suicidal.\n>")
(printf "F2 orphan prompt: resolved; output equals reference F2-kill-troll-pipe (D1 only)\n")
(check-resolved "F2b throw" orphan-reference-file "P03-orphan-prompt-prefix"
                '("open mailbox" "take leaflet" "throw leaflet")
                ">Taken.\n>at what?\n>")
(printf "F2b throw: resolved; output equals reference P03 (D1 only)\n")

;; F3 (strict by maintainer decision): help and info stop at OPEN "READ".
(check-frontier "F3 help" '("help") "There is a small mailbox here.\n>"
              "OPEN: mode \"READ\" is not supported; only READB, PRINT and PRINTO are (ADR-0055)")
(check-frontier "F3 info" '("info") "There is a small mailbox here.\n>"
              "OPEN: mode \"READ\" is not supported; only READB, PRINT and PRINTO are (ADR-0055)")
