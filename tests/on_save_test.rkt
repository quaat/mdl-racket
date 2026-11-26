#lang racket/base
;; S4-ON-SAVE (issue #112, ADR-0047) and S5-SAVE-RECORD (ADR-0048).
;; (1) ON = EVENT + HANDLER (manual ch.21) returning the new HANDLER; the
;;     predefined "IPC" and "BLOCKED" may be registered but can never be
;;     emitted (no source).
;; (2) SAVE (ADR-0048, superseding ADR-0047 part 2) returns a fresh
;;     "SAVED", writes no file, performs no GC and no interrupt side effect,
;;     and appends a host-visible session record. RESTORE stays refused.
;; Each `run` builds a fresh atom space; never compare atoms across runs.
(require rackunit racket/list racket/file
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (session thunk)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (thunk)))
(define (eval-source source)
  (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
    (eval expr)))
(define (run source) (session (lambda () (eval-source source))))
(define (type-name value) (mdl-atom-pname (mdl-type value)))
(define (true? value) (and (mdl-atom? value) (string=? (mdl-atom-pname value) "T")))

;; --- ON returns a HANDLER (compiled path) -------------------------------
(check-equal? (type-name (run "<ON \"M3-USER\" <FUNCTION (X) .X> 7>")) "HANDLER")
(check-equal? (type-name (run "<ON \"IPC\" ,TYPE 1>")) "HANDLER")
(check-equal? (mdl-atom-pname (run "<PRIMTYPE <ON \"IPC\" ,TYPE 1>>")) "VECTOR")
;; OFF removes it and returns the same object; HANDLER on the IHEADER found
;; by EVENT reattaches it, so ON used that very IHEADER.
(check-true (true? (run "<SETG H <ON \"IPC\" ,TYPE 1>> <==? ,H <OFF ,H>>")))
(check-true (true? (run "<SETG H <ON \"IPC\" ,TYPE 1>> <OFF ,H>
                         <==? ,H <HANDLER <EVENT \"IPC\" 1> ,H>>")))
(check-true (true? (run "<SETG H <ON \"M3-USER\" <FUNCTION (X) .X> 7>> <OFF ,H>
                         <==? ,H <HANDLER <EVENT \"M3-USER\" 7> ,H>>")))
;; EVENT on the same name returns the IHEADER ON created (priority ignored).
(check-true (true? (run "<SETG H <ON \"IPC\" ,TYPE 1>> <OFF ,H>
                         <==? ,H <HANDLER <EVENT \"IPC\" 5> ,H>>")))
;; OFF of the IHEADER drops the association; a later ON makes a new one.
(check-exn #rx"HANDLER already in use or belongs to another IHEADER"
           (lambda () (run "<SETG H <ON \"IPC\" ,TYPE 1>> <OFF ,H> <OFF <EVENT \"IPC\" 1>>
                            <ON \"IPC\" ,TYPE 1> <HANDLER <EVENT \"IPC\" 1> ,H>")))

;; --- ON places the HANDLER first, and OFF stops delivery -----------------
(session
 (lambda ()
   (define seen '())
   (define (recorder tag) (lambda (v) (set! seen (append seen (list (list tag v))))))
   (define old (mdl-apply (mdl-atom "ON") "M3-USER" (recorder 'old) 7))
   (define new (mdl-apply (mdl-atom "ON") "M3-USER" (recorder 'new) 7))
   (check-equal? (type-name new) "HANDLER")
   (check-true (mdl-emit-event! "M3-USER" '(1)))
   (check-equal? seen '((new 1) (old 1)))
   (check-eq? (mdl-apply (mdl-atom "OFF") new) new)
   (mdl-emit-event! "M3-USER" '(2))
   (check-equal? seen '((new 1) (old 1) (old 2)))
   ;; ON finds the existing IHEADER and re-enables it (manual 21.6).
   (define header (mdl-apply (mdl-atom "EVENT") "M3-USER" 99))
   (mdl-apply (mdl-atom "DISABLE") header)
   (check-false (mdl-emit-event! "M3-USER" '(3)))
   (mdl-apply (mdl-atom "ON") "M3-USER" (recorder 'third) 7)
   (check-true (mdl-emit-event! "M3-USER" '(4)))
   (check-equal? (drop seen 3) '((third 4) (old 4)))))

;; --- APPLY path ----------------------------------------------------------
(check-equal? (type-name (run "<APPLY ,ON \"IPC\" ,TYPE 1>")) "HANDLER")
(check-equal? (type-name (run "<APPLY ,ON \"M3-USER\" <FUNCTION (X) .X> 7>")) "HANDLER")
(check-true (true? (run "<SETG H <APPLY ,ON \"IPC\" ,TYPE 1>> <==? ,H <APPLY ,OFF ,H>>")))
(check-exn #rx"ON priority must be a positive FIX"
           (lambda () (run "<APPLY ,ON \"IPC\" ,TYPE 0>")))

;; --- strict validation (Confusion's stub returns T for all of these) -----
(check-exn #rx"ON name must be STRING" (lambda () (run "<ON 1 ,TYPE 1>")))
(check-exn #rx"ON name must be STRING" (lambda () (run "<ON IPC ,TYPE 1>")))
(check-exn #rx"unsupported ON applicable" (lambda () (run "<ON \"IPC\" 1 1>")))
(check-exn #rx"unsupported ON applicable" (lambda () (run "<ON \"IPC\" \"BAD\" 1>")))
(check-exn #rx"unsupported ON applicable"
           (lambda () (run "<SETG H <ON \"IPC\" ,TYPE 1>> <ON \"IPC\" ,H 1>")))
(check-exn #rx"ON priority must be a positive FIX" (lambda () (run "<ON \"IPC\" ,TYPE 0>")))
(check-exn #rx"ON priority must be a positive FIX" (lambda () (run "<ON \"IPC\" ,TYPE -1>")))
(check-exn #rx"ON priority must be a positive FIX" (lambda () (run "<ON \"IPC\" ,TYPE \"X\">")))
(check-exn #rx"ON priority must be a positive FIX" (lambda () (run "<ON \"IPC\" ,TYPE 1.5>")))
(check-exn #rx"ON expects name, applicable and priority" (lambda () (run "<ON>")))
(check-exn #rx"ON expects name, applicable and priority" (lambda () (run "<ON \"IPC\" ,TYPE>")))
(check-exn #rx"ON expects name, applicable and priority"
           (lambda () (run "<ON \"IPC\" ,TYPE 1 2 3 4>")))
(check-exn #rx"ON process and which arguments are unsupported"
           (lambda () (run "<ON \"IPC\" ,TYPE 1 2>")))
(check-exn #rx"ON process and which arguments are unsupported"
           (lambda () (run "<ON \"IPC\" ,TYPE 1 2 3>")))
;; Every other refused predefined name stays refused, through ON and EVENT.
;; ("BLOCKED" moved to the sourceless names by ADR-0048; see below.)
(for ([name '("CHAR" "READ" "WRITE" "UNBLOCKED" "CLOCK" "SYSDOWN")])
  (check-exn #rx"unsupported predefined EVENT"
             (lambda () (run (format "<ON ~s ,TYPE 100>" name))))
  (check-exn #rx"unsupported predefined EVENT"
             (lambda () (run (format "<EVENT ~s 100>" name)))))
;; A rejected ON registers nothing.
(session
 (lambda ()
   (for ([bad (list (list "M3-NEW" 1 7) (list "M3-NEW" mdl-type 0)
                    (list "M3-NEW" mdl-type 7 1))])
     (check-exn exn:fail? (lambda () (apply mdl-apply (mdl-atom "ON") bad))))
   (check-exn #rx"unknown or unregistered event M3-NEW"
              (lambda () (mdl-emit-event! "M3-NEW" '() #t)))))

;; --- IPC registration works; IPC emission is a strict error ---------------
(define ipc-rx #rx"IPC: this session has no inter-process message source")
(session
 (lambda ()
   (define seen '())
   (define handler (mdl-apply (mdl-atom "ON") "IPC" (lambda args (set! seen (cons args seen))) 1))
   (check-equal? (type-name handler) "HANDLER")
   (check-exn ipc-rx (lambda () (mdl-emit-event! "IPC" '())))
   (check-exn ipc-rx (lambda () (mdl-emit-event! "IPC" '("message") #t)))
   ;; Nothing was queued: a later safe point delivers nothing.
   (check-equal? (mdl-apply (mdl-atom "INT-LEVEL") 0) 0)
   (check-equal? seen '())
   (check-eq? (mdl-apply (mdl-atom "OFF") handler) handler)
   (check-exn ipc-rx (lambda () (mdl-emit-event! "IPC" '())))
   (check-equal? seen '())))
;; Emission is refused even with no IPC registration at all.
(session (lambda () (check-exn ipc-rx (lambda () (mdl-emit-event! "IPC" '())))))

;; --- BLOCKED registers (ADR-0048); BLOCKED emission is a strict error ----
(define blocked-rx
  #rx"^mdl-emit-event!: BLOCKED: this session has no blocked-input source; BLOCKED occurrences cannot be emitted \\(maintainer decision 2026-11-23; ADR-0048\\)$")
(check-equal? (type-name (run "<ON \"BLOCKED\" ,TYPE 100>")) "HANDLER")
(check-equal? (type-name (run "<EVENT \"BLOCKED\" 100>")) "IHEADER")
(check-equal? (type-name (run "<APPLY ,ON \"BLOCKED\" ,TYPE 100>")) "HANDLER")
(check-true (true? (run "<SETG H <ON \"BLOCKED\" ,TYPE 100>> <==? ,H <OFF ,H>>")))
(check-true (true? (run "<SETG H <ON \"BLOCKED\" ,TYPE 100>> <OFF ,H>
                         <==? ,H <HANDLER <EVENT \"BLOCKED\" 1> ,H>>")))
(check-true (true? (run "<SETG E <EVENT \"BLOCKED\" 100>> <==? ,E <OFF ,E>>")))
(session
 (lambda ()
   (define seen '())
   (define handler (mdl-apply (mdl-atom "ON") "BLOCKED" (lambda args (set! seen (cons args seen))) 100))
   (check-equal? (type-name handler) "HANDLER")
   (check-exn blocked-rx (lambda () (mdl-emit-event! "BLOCKED" '())))
   (check-exn blocked-rx (lambda () (mdl-emit-event! "BLOCKED" '(1) #t)))
   (check-equal? (mdl-apply (mdl-atom "INT-LEVEL") 0) 0)
   (check-equal? seen '())
   (check-eq? (mdl-apply (mdl-atom "OFF") handler) handler)
   (check-exn blocked-rx (lambda () (mdl-emit-event! "BLOCKED" '())))
   (check-equal? seen '())
   ;; IPC keeps its own ADR-0047 message.
   (check-exn ipc-rx (lambda () (mdl-emit-event! "IPC" '())))))
(session (lambda () (check-exn blocked-rx (lambda () (mdl-emit-event! "BLOCKED" '())))))

;; --- session isolation --------------------------------------------------
(define foreign-handler (session (lambda () (mdl-apply (mdl-atom "ON") "IPC" mdl-type 1))))
(session
 (lambda ()
   (check-exn #rx"another MDL session" (lambda () (mdl-apply (mdl-atom "OFF") foreign-handler)))
   (check-exn #rx"unknown or unregistered event M3-USER"
              (lambda () (mdl-emit-event! "M3-USER" '() #t)))))
(define foreign-user (session (lambda () (mdl-apply (mdl-atom "ON") "M3-USER" mdl-type 7))))
(session
 (lambda ()
   (define header (mdl-apply (mdl-atom "EVENT") "M3-USER" 7))
   (check-exn #rx"belongs to another IHEADER|another MDL session"
              (lambda () (mdl-apply (mdl-atom "HANDLER") header foreign-user)))))

;; --- SAVE: session record (ADR-0048) -----------------------------------
(check-equal? (run "<SAVE \"S5PROBE.SAVE\">") "SAVED")
(check-equal? (type-name (run "<SAVE \"S5PROBE.SAVE\">")) "STRING")
(check-false (immutable? (run "<SAVE \"S5PROBE.SAVE\">")))
(check-equal? (run "<APPLY ,SAVE \"S5PROBE.SAVE\">") "SAVED")
(check-true (true? (run "<=? <SAVE \"S5PROBE.SAVE\"> \"SAVED\">")))
;; Fresh object every call: =? but not ==?.
(check-true (mdl-false? (run "<==? <SAVE \"X\"> <SAVE \"X\">>")))
(check-true (true? (run "<=? <SAVE \"X\"> <SAVE \"X\">>")))
;; Mutating one result does not affect the next.
(check-equal? (run "<SETG S <SAVE \"X\">> <PUT ,S 1 !\\Z> <SAVE \"X\">") "SAVED")
(check-equal? (run "<SETG S <SAVE \"X\">> <PUT ,S 1 !\\Z> <SAVE \"X\"> ,S") "ZAVED")
;; Optional FALSE gc? (manual 11.6.1: no GC before saving).
(check-equal? (run "<SAVE \"X\" <>>") "SAVED")
(check-equal? (run "<SAVE \"X\" #FALSE (1)>") "SAVED")
(check-equal? (run "<APPLY ,SAVE \"X\" <>>") "SAVED")
;; REST view file-spec.
(check-equal? (run "<SAVE <REST \"ZZB.SAVE\" 2>>") "SAVED")

;; Records: sequence, file-spec snapshot, INT-LEVEL at the call.
(define (record->list r)
  (list (mdl-save-record-sequence r) (mdl-save-record-file-spec r)
        (mdl-save-record-int-level r)))
(session
 (lambda ()
   (check-equal? (mdl-save-records) '())
   (eval-source "<INT-LEVEL 7> <SAVE \"A.SAVE\"> <INT-LEVEL 0>
                 <SAVE <REST \"XXB.SAVE\" 2> <>>
                 <SETG F <STRING \"MUT.SAVE\">> <INT-LEVEL 100000> <SAVE ,F>
                 <PUT ,F 1 !\\Z> <INT-LEVEL 0>")
   (define records (mdl-save-records))
   (check-true (andmap mdl-save-record? records))
   (check-equal? (map record->list records)
                 '((1 "A.SAVE" 7) (2 "B.SAVE" 0) (3 "MUT.SAVE" 100000)))
   (check-true (andmap (lambda (r) (immutable? (mdl-save-record-file-spec r))) records))
   ;; The argument was mutated after SAVE; the record kept its snapshot.
   (check-equal? (eval-source ",F") "ZUT.SAVE")
   ;; Failed calls append nothing.
   (for ([bad '("<SAVE>" "<SAVE 1>" "<SAVE \"X\" T>" "<SAVE \"X\" <> 3>")])
     (check-exn exn:fail? (lambda () (eval-source bad)) bad))
   (check-equal? (length (mdl-save-records)) 3)))
;; Records are per session; the counter restarts at 1.
(session
 (lambda ()
   (check-equal? (mdl-save-records) '())
   (eval-source "<SAVE \"OTHER.SAVE\">")
   (check-equal? (map record->list (mdl-save-records)) '((1 "OTHER.SAVE" 0)))))

;; No interrupt side effects: SAVE neither changes INT-LEVEL nor delivers a
;; queued occurrence nor runs a (GC-signalling) collection.
(session
 (lambda ()
   (define seen '())
   (mdl-apply (mdl-atom "ON") "M3-USER" (lambda args (set! seen (cons (cons 'user args) seen))) 5)
   (mdl-apply (mdl-atom "ON") "GC" (lambda args (set! seen (cons (cons 'gc args) seen))) 1)
   (define stats-before (mdl-logical-storage-stats))
   (mdl-apply (mdl-atom "INT-LEVEL") 10)
   (check-true (mdl-emit-event! "M3-USER" '(1)) "recorded, queued below INT-LEVEL")
   (check-true (true? (mdl-apply (mdl-atom "=?") (mdl-apply (mdl-atom "SAVE") "Q.SAVE") "SAVED")))
   (check-equal? seen '())
   (check-equal? (mdl-apply (mdl-atom "INT-LEVEL")) 10)
   (check-equal? (mdl-save-record-int-level (car (mdl-save-records))) 10)
   (check-equal? (hash-ref (mdl-logical-storage-stats) 'capacity)
                 (hash-ref stats-before 'capacity))
   ;; The queued occurrence is still pending and arrives at the next safe point.
   (mdl-apply (mdl-atom "INT-LEVEL") 0)
   (check-equal? seen '((user 1)))
   ;; At level 0 SAVE still neither collects nor signals GC.
   (mdl-apply (mdl-atom "SAVE") "Q2.SAVE")
   (check-equal? seen '((user 1)))))

;; Strict errors (Confusion: <SAVE> writes MUDDLE.SAVE, <SAVE 1> SIGSEGV).
(define save-arity-rx #rx"SAVE expects a file-spec STRING and an optional FALSE gc\\?")
(define save-spec-rx #rx"SAVE file-spec must be STRING")
(define save-gc-rx #rx"SAVE gc\\? must be FALSE; this session never collects on SAVE")
(for ([case (list (cons "<SAVE>" save-arity-rx)
                  (cons "<APPLY ,SAVE>" save-arity-rx)
                  (cons "<SAVE \"X\" <> 3>" save-arity-rx)
                  (cons "<SAVE \"MUDDLE\" \"SAVE\" \"DSK\" \"MDL\">" save-arity-rx)
                  (cons "<SAVE 1>" save-spec-rx)
                  (cons "<APPLY ,SAVE 1>" save-spec-rx)
                  (cons "<SAVE FOO>" save-spec-rx)
                  (cons "<SAVE (\"X\")>" save-spec-rx)
                  (cons "<SAVE 1 <>>" save-spec-rx)
                  (cons "<SAVE \"X\" T>" save-gc-rx)
                  (cons "<SAVE \"X\" \"SAVE\">" save-gc-rx)
                  (cons "<SAVE \"X\" 0>" save-gc-rx))])
  (check-exn (cdr case) (lambda () (run (car case))) (car case)))
;; SAVE evaluates its arguments as a SUBR (before validating them).
(session
 (lambda ()
   (check-exn save-spec-rx (lambda () (eval-source "<SETG X 0> <SAVE <SETG X 1>>")))
   (check-equal? (eval-source ",X") 1)
   (check-equal? (eval-source "<SAVE <STRING \"A\" \"B\">>") "SAVED")
   (check-equal? (mdl-save-record-file-spec (car (mdl-save-records))) "AB")))

;; --- RESTORE: still refused; SAVE/RESTORE write and delete no file --------
(define restore-rx
  #rx"^RESTORE: restoring a saved image is not supported \\(maintainer decision 2026-11-23; ADR-0048\\)$")
(define (snapshot dir) (sort (map path->string (directory-list dir)) string<?))
(define scratch (make-temporary-file "on-save-test-~a" 'directory))
;; Record every write/delete file access the SAVE/RESTORE calls attempt,
;; anywhere on the filesystem. A guard (rather than a before/after listing
;; of the shared temp directory) is immune to concurrent processes.
(define attempted-writes '())
(define write-recorder
  (make-security-guard
   (current-security-guard)
   (lambda (who path modes)
     (when (and path (or (memq 'write modes) (memq 'delete modes)))
       (set! attempted-writes (cons (list who path modes) attempted-writes))))
   (lambda (who host port mode) (void))))
(dynamic-wind
 void
 (lambda ()
   (parameterize ([current-directory scratch]
                  [current-security-guard write-recorder])
     (define cwd-before (snapshot scratch))
     (for ([source '("<SAVE \"S4PROBE.SAVE\">" "<SAVE \"<MDL>MADADV.SAVE\">"
                     "<APPLY ,SAVE \"S4PROBE.SAVE\">" "<SAVE \"S4PROBE.SAVE\" <>>"
                     "<=? <SAVE \"S4PROBE.SAVE\"> \"SAVED\">")])
       (check-not-exn (lambda () (run source)) source))
     (for ([source '("<SAVE>" "<SAVE 1>" "<SAVE \"S4PROBE.SAVE\" T>")])
       (check-exn exn:fail? (lambda () (run source)) source))
     (for ([source '("<RESTORE \"S4PROBE.SAVE\">" "<RESTORE>"
                     "<APPLY ,RESTORE \"S4PROBE.SAVE\">"
                     "<SAVE \"S4PROBE.SAVE\"> <RESTORE \"S4PROBE.SAVE\">")])
       (check-exn restore-rx (lambda () (run source)) source))
     (check-equal? (snapshot scratch) cwd-before)
     (check-equal? cwd-before '())
     (check-equal? attempted-writes '())
     (check-false (file-exists? (build-path scratch "S4PROBE.SAVE")))
     (check-false (directory-exists? (build-path scratch "MDL")))))
 (lambda () (delete-directory/files scratch)))
;; RESTORE evaluates its arguments as a SUBR before refusing.
(session
 (lambda ()
   (check-exn restore-rx (lambda () (eval-source "<SETG X 0> <RESTORE <SETG X 1>>")))
   (check-equal? (eval-source ",X") 1)))
