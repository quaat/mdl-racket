#lang racket/base
;; Historical regression: the faithful SAVE-IT entry after the 1,229-form load.
;;
;; Tracks source progress toward INITIALIZED on the faithful run.mud entry
;; path (<FLOAD "77loadall.mud"> then <SAVE-IT>).
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: make test-m3-saveit   (or: racket tests/historical_saveit_test.rkt)
(require rackunit racket/runtime-path "../mdl/loader.rkt" "../mdl/runtime/core.rkt")

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(unless (directory-exists? source-root)
  (error 'historical-saveit "pinned source missing: ~a" source-root))

;; Terminal output goes only to this explicit session port (ADR-0050: the
;; runtime never writes to the process's own stdout).
(define terminal-out (open-output-string))
(define session (make-mdl-session source-root #:output-port terminal-out))
(define load-report (mdl-session-load! session "77loadall.mud"))
(define load-output-length (string-length (get-output-string terminal-out)))
(check-equal? (hash-ref load-report 'status) "PASS")
(check-equal? (hash-ref load-report 'completed_expressions) 1229)
(check-equal? (hash-ref load-report 'skipped_expressions) 0)

;; S7 (ADR-0050): SAVE-IT now returns. SAVE is a session record (ADR-0048):
;; <SAVE .FN> returns a fresh "SAVED", writes no file, and is recorded with
;; INT-LEVEL 100000. The patched SAVE-IT has a single COND clause, so it
;; continues in the same session: <INT-LEVEL 0> (77rooms.mud:26), STARTER,
;; GETSYS (56), ON "BLOCKED" (59; registers, never fires), START (60).
;; ADR-0049: the GVAL of REP is the predefined, inert REP SUBR, so CONTIN's
;; <SETG SAVEREP ,REP> (301) and <SETG REP ,RDCOM> (302) complete. ADR-0050:
;; <RESET ,INCHAN> (303) returns INCHAN, and CONTIN returns ,NULL (306), the
;; value SAVE-IT returns. The game loop itself (RDCOM, applied by the host
;; top-level loop) is tested in historical_interactive_test.rkt.
;;
;; Call chain: SAVE-IT (77rooms.mud:60) -> START (77rooms.mud:293)
;;   -> CONTIN (77rooms.mud:296-306) -> returns ,NULL
;; No host top-level loop is run here.
(define (listing dir) (sort (map path->string (directory-list dir)) string<?))
(define source-before (listing source-root))
(check-equal? (mdl-session-global session "ALT-FLAG") (mdl-session-atom session "T"))
(check-equal? (mdl-session-save-records session) '())
(define returned (mdl-session-call session "SAVE-IT"))
;; Only the text SAVE-IT wrote after the load.
(define saveit-output (substring (get-output-string terminal-out) load-output-length))
;; SAVE-IT returns CONTIN's ,NULL: the ATOM with an empty PNAME that
;; 81tell-repl.mud inserts on ROOT.
(check-eq? returned (mdl-session-global session "NULL"))
(check-equal? (mdl-atom-pname returned) "")
;; SAVE (77rooms.mud:26) ran once, returned "SAVED" (the COND clause was
;; taken) and was recorded with the file-spec and INT-LEVEL 100000.
(define records (mdl-session-save-records session))
(check-equal? (length records) 1)
(check-equal? (mdl-save-record-sequence (car records)) 1)
(check-equal? (mdl-save-record-file-spec (car records)) "<MDL>MADADV.SAVE")
(check-equal? (mdl-save-record-int-level (car records)) 100000)
;; <INT-LEVEL 0> after SAVE (77rooms.mud:26) and in START (292) executed.
(check-equal? (mdl-session-call session "INT-LEVEL") 0)
;; No GC/DIVERT-AGC occurrence was pending at either INT-LEVEL 0: the
;; DIVERT handler (enabled at 77rooms.mud:17) never ran.
(check-equal? (mdl-session-global session "DIVERT-CNT") 0)
(check-equal? (mdl-session-global session "DIVERT-AMT") 0)
;; STARTER/GETSYS (56): TENEX? is FALSE.
(check-true (mdl-false? (mdl-session-global session "TENEX?")))
;; START ran through TELL (289-290) and its INT-LEVEL 0 (292).
(check-true
 (regexp-match? #rx"^Welcome to Dungeon\\.\r?\nThis version created [A-Z][a-z]+ [0-9]+\\.\n$"
                saveit-output)
 saveit-output)
(check-equal? (mdl-session-global session "DEATHS") 0)
(check-equal? (mdl-session-global session "MOVES") 0)
;; XUNAME/GET-NAME as in the Confusion trace (S5-SAVE-FRONTIER.md Q3 step 6).
(check-equal? (mdl-session-global session "XUNM") "MTRZORK")
(check-equal? (mdl-session-global session "USER-NAME") "")
;; CONTIN 77rooms.mud:296-306 ran.
(check-true (mdl-false? (mdl-session-global session "ALT-FLAG")))
(define (type-of value) (mdl-atom-pname (mdl-session-call session "TYPE" value)))
;; 301: SAVEREP holds the predefined REP SUBR (ADR-0049) ...
(define saverep (mdl-session-global session "SAVEREP"))
(check-equal? (type-of saverep) "SUBR")
(check-exn #rx"REP: the default REP SUBR is inert; .*ADR-0049"
           (lambda () (mdl-session-call session "APPLY" saverep)))
;; ... and 302 made REP the game's command reader RDCOM (a FUNCTION).
(check-eq? (mdl-session-global session "REP") (mdl-session-global session "RDCOM"))
;; (RDCOM is a compiled DEFINE, a host procedure: its TYPE is still an
;; unsupported-type error, a pre-existing limit recorded in S6-REP.md.)
(check-exn #rx"mdl-type: unsupported MDL type"
           (lambda () (type-of (mdl-session-global session "REP"))))
;; 303: RESET returned the same INCHAN; 304-305 completed.
(check-eq? (mdl-session-global session "WINNER") (mdl-session-global session "PLAYER"))
(check-true (mdl-false? (mdl-session-call session "NTH" (mdl-session-global session "PRSVEC") 2)))
;; State established by 77rooms.mud:13-21 before SAVE was reached.
(check-equal? (mdl-session-global session "DEV") "DSK")
(check-equal? (mdl-session-global session "SNM") "MDL")
(check-equal? (mdl-session-global session "RAW-SCORE") 0)
(check-equal? (string-length (mdl-session-global session "SCRATCH-STR")) 32)
;; No image was written next to the source.
(check-equal? (listing source-root) source-before)
