#lang racket/base
;; M2 G3 integrated gate probe: load the pinned original chain in ONE shared
;; MDL session and exercise the installed original definitions together --
;; cross-file VFLOAD, MSETG, the partially available PSETG, the RAPPLIC atom
;; property, shared globals, mutation aliasing, and session independence.
;; Run from the repository root via make test-m2-g3, which fetches the pinned
;; sources first. This gate currently exits nonzero after all observations
;; because original FLAGWORD still reaches unsupported MAPF.
(require racket/file racket/list racket/path racket/port racket/string rackunit
         "../mdl/loader.rkt" "../mdl/runtime/core.rkt")

(define source-root
  (build-path ".cache" "upstream" "mdlzork" "mdlzork_771212"
              "patched_confusion"))
(define expected-shas
  '(("77loadall.mud" . "389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa")
    ("81prim.mud" . "8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571")
    ("77defs.mud" . "566ebcc32be9b9226dd7cefd77a517583eebab80a03f452df39e13b85eed734e")))
(define checks 0)
(define (check actual expected)
  (set! checks (add1 checks))
  (unless (equal? actual expected)
    (error 'historical-g3 "expected ~s, got ~s" expected actual)))
(define (check-true actual)
  (set! checks (add1 checks))
  (unless (eq? actual #t)
    (error 'historical-g3 "expected #t, got ~s" actual)))
(define (check-exn-verb thunk pattern)
  (set! checks (add1 checks))
  (define raised?
    (with-handlers ([exn:fail?
                     (lambda (e) (regexp-match? pattern (exn-message e)))])
      (thunk)
      #f))
  (unless raised?
    (error 'historical-g3 "expected an error matching ~s" pattern)))

(unless (directory-exists? source-root)
  (error 'historical-g3
         "pinned sources missing: ~a; run make sources first" source-root))
(define sha-tool (find-executable-path "sha256sum"))
(unless sha-tool (error 'historical-g3 "sha256sum is required"))
(for ([pair expected-shas])
  (define-values (proc stdout stdin stderr)
    (subprocess #f #f #f (path->string sha-tool)
                (path->string (build-path source-root (car pair)))))
  (close-output-port stdin)
  (define sha-output (port->string stdout))
  (define sha-error (port->string stderr))
  (subprocess-wait proc)
  (check (subprocess-status proc) 0)
  (check sha-error "")
  (check (car (string-split sha-output)) (cdr pair)))

;; Render an MDL value in the pinned Confusion notation, inside the session
;; context (atom identity is per-session; rendering must happen before the
;; session's atom space is gone).
(define (render session value)
  (cond
    [(mdl-atom? value) (mdl-atom-pname value)]
    [(mdl-false? value)
     (format "#FALSE (~a)"
             (string-join (map (lambda (item) (render session item))
                               (mdl-false-payload value)) " "))]
    [(string? value) (format "~s" value)]
    [(or (null? value) (mpair? value))
     (format "(~a)" (string-join (map (lambda (item) (render session item))
                                      (mdl-list->list value)) " "))]
    [(string=? (mdl-atom-pname (mdl-session-call session "TYPE" value)) "FORM")
     (format "<~a>" (string-join
                      (map (lambda (item) (render session item))
                           (mdl-list->list (mdl-base value))) " "))]
    [(number? value) (format "~a" value)]
    [else (format "~s" value)]))

(define root (make-temporary-file "/tmp/mdl-g3-test~a" 'directory))
(dynamic-wind
 void
 (lambda ()
   ;; Copy the exact pinned bytes into a dedicated authorized root; the
   ;; pinned checkout itself is never executed from or modified. The chain
   ;; reaches exactly these three files.
   (for ([name '("77loadall.mud" "81prim.mud" "77defs.mud")])
     (call-with-output-file (build-path root name) #:exists 'truncate/replace
       (lambda (out)
         (write-bytes (file->bytes (build-path source-root name)) out))))

   ;; --- Integrated load: ONE session, the whole pinned chain -----------

   ;; The original VFLOAD (defined in 77loadall.mud expression 1, invoked
   ;; as expressions 2-3) prints its own text on success only; the chain
   ;; fails inside 77defs.mud, so exactly the 81prim.mud line appears and
   ;; the failure propagates out of the original definition.
   (define session (make-mdl-session root))
   (define out (open-output-string))
   (define report
     (parameterize ([current-output-port out])
       (mdl-session-load! session "77loadall.mud")))
   (check (hash-ref report 'status) "FAIL")
   (check (hash-ref report 'completed_expressions) 24)
   (check (hash-ref report 'skipped_expressions) 0)
   (check (get-output-string out) "81prim.mud loaded\n")
   (define failure (hash-ref report 'failure))
   (check (hash-ref failure 'file) "77defs.mud")
   (check (hash-ref failure 'expression_index) 15)
   (check (string-contains? (hash-ref failure 'exception)
                            "unassigned or non-applicable MDL operator EMPTY?")
          #t)
   ;; Failure propagation: no PASS events after the failure event, and the
   ;; events stop at the barrier instead of continuing the chain.
   (define events (hash-ref report 'events))
   (define fail-pos
     (index-of events (findf (lambda (e) (equal? (hash-ref e 'status) "FAIL"))
                             events)))
   (check-true (and fail-pos (fail-pos . < . (length events))))
   (check (length (filter (lambda (e) (equal? (hash-ref e 'status) "PASS"))
                          events))
          24)
   (check-true
    (empty?
     (filter (lambda (e) (equal? (hash-ref e 'status) "PASS"))
             (drop events (add1 fail-pos)))))
   (check-true
    (andmap (lambda (e) (if (member (hash-ref e 'status)
                                     '("PASS" "FAIL")) #t #f))
            events))

   ;; --- Shared session state ---------------------------------------------

   ;; The interpreter-seeded MUDDLE global (D4 reference value).
   (check (mdl-session-global session "MUDDLE") 101)

   ;; Invoke the original VFLOAD again in the already populated session.
   ;; The local one-form fixture is intentionally controlled by this test;
   ;; the VFLOAD definition itself came from the hash-verified original file.
   (call-with-output-file (build-path root "g3-controlled.mud")
     #:exists 'truncate/replace
     (lambda (port) (display "<SETG G3-VF 17>\n" port)))
   (define vf-out (open-output-string))
   (define vf-result
     (parameterize ([current-output-port vf-out])
       (mdl-session-call session "VFLOAD" "g3-controlled.mud")))
   (check (mdl-false? vf-result) #t)
   (check (get-output-string vf-out) "g3-controlled.mud loaded\n")
   (check (mdl-session-global session "G3-VF") 17)

   ;; --- Original MSETG (81prim.mud expression 2) --------------------------

   (define atom (mdl-session-atom session "G3-TEMP"))
   (check (mdl-atom-pname (mdl-session-call session "MSETG" atom 3)) "T")
   (check (mdl-session-global session atom) 3)
   ;; Original MSETG's equal-repeat and conflicting-repeat paths now both
   ;; execute through the stacked N=?, computed-global, and ERROR slices.
   (check (mdl-atom-pname (mdl-session-call session "MSETG" atom 3)) "T")
   (check (mdl-session-global session atom) 3)
   (check-exn-verb
    (lambda () (mdl-session-call session "MSETG" atom 4))
    #rx"MSETG.*G3-TEMP.*ALREADY-GASSIGNED.*3")
   ;; The original declaration still rejects a non-ATOM first argument at
   ;; the boundary and the global is unchanged after the failed conflict.
   (check-exn-verb
    (lambda () (mdl-session-call session "MSETG" "bad" 3))
    #rx"DECL.*FOO")
   (check (mdl-session-global session atom) 3)

   ;; --- Original PSETG (81prim.mud expression 3) --------------------------

   ;; PSETG completes through MEMQ and preserves PURE-LIST membership on a
   ;; repeated call; these are exact original-source paths.
   (define psetg-atom (mdl-session-atom session "G3-P"))
   (check (mdl-session-call session "PSETG" psetg-atom 3) 3)
   (check (mdl-session-global session psetg-atom) 3)
   (check (render session (mdl-session-global session "PURE-LIST")) "(G3-P)")
   (check (mdl-session-call session "PSETG" psetg-atom 4) 4)
   (check (mdl-session-global session psetg-atom) 4)
   (check (render session (mdl-session-global session "PURE-LIST")) "(G3-P)")

   ;; The next installed original definition needed for M2's MAPF build
   ;; surface is FLAGWORD. Pinned Confusion returns 1 for this empty-TUPLE
   ;; call; the current Racket runtime must fail explicitly at MAPF.
   (check-exn-verb
    (lambda () (mdl-session-call session "FLAGWORD"))
    #rx"unassigned or non-applicable MDL operator MAPF")

   ;; --- Original RAPPLIC declaration property (77defs.mud:5) -------------

   ;; The historical atom-property PUT installed RAPPLIC's DECL association
   ;; in this same session; GET (D5 dispatch) retrieves the exact stored
   ;; FORM and the atom is otherwise untouched.
   (define rapplic (mdl-session-atom session "RAPPLIC"))
   (define decl-atom (mdl-session-atom session "DECL"))
   (check (render session (mdl-session-call session "GET" rapplic decl-atom))
          "<OR ATOM FALSE NOFFSET>")
   (check (mdl-atom-pname (mdl-session-call session "TYPE"
                                             (mdl-session-call
                                              session "GET" rapplic decl-atom)))
          "FORM")
   (check (mdl-atom-pname (mdl-session-call session "TYPE" rapplic)) "ATOM")
   (check (mdl-atom-pname (mdl-session-call session "PRIMTYPE" rapplic)) "ATOM")
   (check (mdl-false? (mdl-session-call session "GASSIGNED?" rapplic)) #t)
   ;; DECL? consults the original property: a NOFFSET-typed value (the type
   ;; created by 77defs.mud expression 1's original NEWTYPE) satisfies the
   ;; stored pattern; a FIX value misses with the pattern's leaf in the
   ;; FALSE payload (reference g3-declq-rapplic-hit and the D5 miss case).
   (define noffset (mdl-session-atom session "NOFFSET"))
   (define noffset-1 (mdl-session-call session "CHTYPE" 1 noffset))
   (check (mdl-atom-pname
           (mdl-session-call session "DECL?" noffset-1 rapplic))
          "T")
   (check (render session (mdl-session-call session "DECL?" 3 rapplic))
          "#FALSE (3 NOFFSET)")

   ;; The original 77defs.mud DEFMAC TRNN installs in this session. EXPAND
   ;; invokes its original body without evaluating OFLAGS (which belongs to
   ;; later source). The exact result matches g3-expand-trnn in Confusion.
   (define trnn-call
     (mdl-session-call session "FORM"
                       (mdl-session-atom session "TRNN")
                       (mdl-session-atom session "OBJ") 2))
   (check (render session (mdl-session-call session "EXPAND" trnn-call))
          "<N==? <CHTYPE <ANDB 2 <OFLAGS OBJ>> FIX> 0>")

   ;; --- Mutation aliasing over shared globals ------------------------------

   ;; Two globals referencing the SAME structure: PUT through one name is
   ;; visible through the other (reference g3-global-alias-put).
   (define ga (mdl-session-atom session "G3-L"))
   (define gb (mdl-session-atom session "G3-M"))
   (define lst (mdl-session-call session "LIST" 1 2 3))
   (mdl-session-call session "SETG" ga lst)
   (mdl-session-call session "SETG" gb (mdl-session-global session "G3-L"))
   (mdl-session-call session "PUT" lst 1 99)
   (check (mdl-session-call session "NTH"
                            (mdl-session-global session "G3-M") 1)
          99)

   ;; --- Session independence ----------------------------------------------

   ;; A fresh session on the same root starts property-free and definition-
   ;; free: no RAPPLIC association, no installed MSETG, and the interpreter
   ;; globals re-seeded independently.
   (define fresh (make-mdl-session root))
   (define fresh-rapplic (mdl-session-atom fresh "RAPPLIC"))
   (define fresh-decl (mdl-session-atom fresh "DECL"))
   (check (render fresh (mdl-session-call fresh "GET" fresh-rapplic fresh-decl))
          "#FALSE ()")
   (check-exn-verb
    (lambda () (mdl-session-call fresh "MSETG" fresh-rapplic 1))
    #rx"unassigned MDL global MSETG")
   (check (mdl-session-global fresh "MUDDLE") 101)
   ;; The first session's state is unaffected by the fresh session.
   (check (render session (mdl-session-call session "GET" rapplic decl-atom))
          "<OR ATOM FALSE NOFFSET>")
   (check (mdl-session-global session atom) 3))
 (lambda ()
   (with-handlers ([exn:fail? void])
     (delete-directory/files root))))

(displayln (format "historical G3 integrated observations passed: ~a assertions" checks))
(error 'historical-g3
       "G3 FAIL: original FLAGWORD requires unsupported MAPF")
