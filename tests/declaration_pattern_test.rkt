#lang racket/base
;; M2 D3 regression tests: structured #DECL declaration patterns
;; (<LIST ...>/<VECTOR ...>/<UVECTOR ...>/<TUPLE ...> with required element
;; patterns and [REST pat ...] repetitions), per issue #48.
;;
;; The reference observations are the pinned Confusion runs recorded in
;; docs/evidence/M2/DECLARATION-PATTERNS.md and its
;; declaration-pattern-*.json evidence files (interpreter SHA-256
;; a29c756df5c973e462a6ad2b318e28ec265934e89e72d825bc7672387317e629).
;; DECL? is a SUBR in both the reference and this implementation, and a
;; round-paren structure evaluates as LIST data, so the recorded value
;; operands run verbatim. Where this implementation fails explicitly on a
;; construct the reference supports but D3 leaves out of scope (OPT,
;; quoted-object element patterns), the test pins the explicit failure.
(require rackunit racket/file racket/path racket/list racket/string
         "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/runtime/core.rkt" "../mdl/loader.rkt")

(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([result #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))

(define (pname value) (mdl-atom-pname value))

;; A DECL? result renders as the ATOM T on success or as #FALSE (payload ...);
;; payload elements are checked one by one through their printed notation.
(define (check-decl-true result)
  (check-equal? (pname result) "T"))
(define (check-decl-false result payload-checks)
  (check-true (mdl-false? result))
  (define payload (mdl-false-payload result))
  (check-equal? (length payload) (length payload-checks))
  (for ([check (in-list payload-checks)] [item (in-list payload)])
    (check-true (check item))))
(define (atom-named? name)
  (lambda (item) (and (mdl-atom? item) (string=? (mdl-atom-pname item) name))))
(define (is-value? expected)
  (lambda (item) (equal? item expected)))

;; --- DECL? structured matching (the 22 recorded reference observations) ----

;; list-empty-vs-rest-atom / psetg-empty-list: empty LIST satisfies [REST ...]
(check-decl-true (run "<DECL? () '<LIST [REST ATOM]>>"))
;; list-atoms-vs-rest-atom / psetg-single-atom / psetg-two-atoms
(check-decl-true (run "<DECL? (A) '<LIST [REST ATOM]>>"))
(check-decl-true (run "<DECL? (A B) '<LIST [REST ATOM]>>"))
;; list-nonatom-vs-rest-atom / psetg-non-atom-element: element mismatch carries
;; the offending element and the element pattern
(check-decl-false (run "<DECL? (A 1) '<LIST [REST ATOM]>>")
                  (list (is-value? 1) (atom-named? "ATOM")))
;; string-vs-list-pattern: overall TYPE mismatch is the bare #FALSE ()
(check-decl-false (run "<DECL? \"s\" '<LIST [REST ATOM]>>") '())
;; list-fixes-vs-rest-fix
(check-decl-true (run "<DECL? (1 2 3) '<LIST [REST FIX]>>"))
;; list-prefix-plus-rest-good / -missing-prefix: required prefixes match in
;; order and in full, and the first prefix element is reported
(check-decl-true (run "<DECL? (1 A B) '<LIST FIX [REST ATOM]>>"))
(check-decl-false (run "<DECL? (A B) '<LIST FIX [REST ATOM]>>")
                  (list (atom-named? "A") (atom-named? "FIX")))
;; vector-rest-fix-good / -bad
(check-decl-true (run "<DECL? [1 2] '<VECTOR [REST FIX]>>"))
(check-decl-false (run "<DECL? [1 A] '<VECTOR [REST FIX]>>")
                  (list (atom-named? "A") (atom-named? "FIX")))
;; uvector-rest-fix-good (the recorded ![1 2] input syntax)
(check-decl-true (run "<DECL? ![1 2] '<UVECTOR [REST FIX]>>"))
;; nested-or-in-rest-good / -bad: the OR reports its last failed alternative
(check-decl-true (run "<DECL? (1 A) '<LIST [REST <OR FIX ATOM>]>>"))
(check-decl-false (run "<DECL? (1 \"s\") '<LIST [REST <OR FIX ATOM>]>>")
                  (list (is-value? "s") (atom-named? "ATOM")))
;; rest-multi-pattern: multi-pattern REST sequences repeat element-wise
(check-decl-true (run "<DECL? (1 A 2 B) '<LIST [REST FIX ATOM]>>"))
;; Cyclic repetition restarts the sequence each period, so a trailing partial
;; period fails against its next pattern (Confusion's REST loop; derived from
;; the pinned source, not separately pinned by a recorded probe).
(check-decl-false (run "<DECL? (1 A B) '<LIST [REST FIX ATOM]>>")
                  (list (atom-named? "B") (atom-named? "FIX")))
;; Manual: additional undeclared elements are allowed; only the declared
;; prefix is checked. A structure shorter than its prefix fails with the
;; reference's bare #FALSE () (Confusion returns the plain FALSE when the
;; value runs out below its required prefix).
(check-decl-true (run "<DECL? (1 2) '<LIST FIX>>"))
(check-decl-true (run "<DECL? (1 2) '<LIST FIX FIX [REST FIX]>>"))
(check-decl-false (run "<DECL? () '<LIST FIX>>") '())

;; TUPLE structured patterns (the FLAGWORD declaration mechanism): TUPLE
;; participates in the same element matching.
(check-decl-true
 (run "<DEFINE MK (\"TUPLE\" T) .T> <DECL? <MK 1 2> '<TUPLE [REST FIX]>>"))
(check-decl-false
 (run "<DEFINE MK (\"TUPLE\" T) .T> <DECL? <MK 1 \"s\"> '<TUPLE [REST FIX]>>")
 (list (is-value? "s") (atom-named? "FIX")))

;; --- attached compound declarations (compiled and interpreted paths) -------

;; attached-compound-decl-good / -empty: the definition installs and its
;; declared argument accepts ATOM-of-any-count lists
(check-equal?
 (map pname (mdl-list->list
             (run "<DEFINE F (P) #DECL ((P) <LIST [REST ATOM]>) .P> <F (A B)>")))
 '("A" "B"))
(check-true (null? (run "<DEFINE F (P) #DECL ((P) <LIST [REST ATOM]>) .P> <F ()>")))
;; the same declaration rejects a bad argument at the binding boundary
(check-exn #rx"DECL.*P" (lambda ()
  (run "<DEFINE F (P) #DECL ((P) <LIST [REST ATOM]>) .P> <F (A 1)>")))
;; a later SET in the owning frame is checked (compiled path)
(check-exn #rx"DECL.*P" (lambda ()
  (run "<DEFINE F (P) #DECL ((P) <LIST [REST ATOM]>) <SET P (A 1)> .P> <F (B)>")))
(check-equal? (map pname (mdl-list->list
             (run "<DEFINE F (P) #DECL ((P) <LIST [REST ATOM]>) <SET P (B)> .P> <F (A)>")))
              '("B"))
;; a declared VALUE result is checked (compiled path), good and bad
(check-equal?
 (map pname (mdl-list->list
             (run "<DEFINE F () #DECL ((VALUE) <LIST [REST ATOM]>) (A B)> <F>")))
 '("A" "B"))
(check-exn #rx"DECL.*VALUE" (lambda ()
  (run "<DEFINE F () #DECL ((VALUE) <LIST [REST ATOM]>) (A 1)> <F>")))
;; interpreted twins: a quoted formal forces the interpreted FUNCTION path
(check-equal?
 (map pname (mdl-list->list
             (run "<DEFINE F ('P) #DECL ((P) <LIST [REST ATOM]>) .P> <F (A B)>")))
 '("A" "B"))
(check-exn #rx"DECL.*P" (lambda ()
  (run "<DEFINE F ('P) #DECL ((P) <LIST [REST ATOM]>) .P> <F (A 1)>")))
(check-exn #rx"DECL.*P" (lambda ()
  (run "<DEFINE F ('P) #DECL ((P) <LIST [REST ATOM]>) <SET P (A 1)> .P> <F (B)>")))

;; --- explicit failures for constructs outside the D3 scope -----------------

;; SPECIAL/UNSPECIAL wrappers (reference: DECL-ELEMENT-NOT-FORM-OR-ATOM)
(check-exn #rx"DECL\\?: unsupported declaration pattern SPECIAL"
           (lambda () (run "<DECL? 3 '<SPECIAL FIX>>")))
(check-exn #rx"DECL\\?: unsupported declaration pattern UNSPECIAL"
           (lambda () (run "<DECL? 3 '<UNSPECIAL FIX>>")))
;; NTH repetition is covered by nth_decl_test.rkt; invalid counts stay strict.
(check-decl-true (run "<DECL? (1 2 3 4) '<LIST [2 FIX] [REST FIX]>>"))
(check-exn #rx"DECL\\?: NTH repetition requires a positive count"
           (lambda () (run "<DECL? (1) '<LIST [0 FIX]>>")))
;; [OPT ...] is a later slice (reference computes its results but pollutes
;; its own stderr with leftover probe prints)
(check-exn #rx"DECL\\?: unsupported declaration pattern OPT"
           (lambda () (run "<DECL? () '<LIST [OPT ATOM]>>")))
;; Empty structured pattern: Confusion reads <LIST> and matches any LIST,
;; but the manual BNF (elts ::= pat | pat elts | ...) requires at least one
;; element pattern -- recorded deviation, rejected here.
(check-exn #rx"DECL\\?: structured declaration pattern"
           (lambda () (run "<DECL? () '<LIST>>")))
;; Issue #76 enables the manual's <<PRIMTYPE struc> elts> composition for
;; NEWTYPE declarations. Pinned Confusion rejects this in explicit DECL?,
;; although it silently discards a NEWTYPE third-argument declaration.
(check-decl-true (run "<DECL? (1 A) '<<PRIMTYPE LIST> [REST FIX ATOM]>>"))
;; <<OR struc ... struc> elts> remains malformed.
(check-exn #rx"DECL\\?: malformed declaration pattern"
           (lambda () (run "<DECL? (1 2) '<<OR LIST VECTOR> [REST FIX]>>")))
;; Quoted-object element patterns (manual example [REST 'T FIX]; D1 rule)
(check-exn #rx"DECL\\?: unsupported declaration pattern QUOTE"
           (lambda () (run "<DECL? (T 1) '<LIST [REST 'T FIX]>>")))
;; STRUCTURED as a compound-name pattern (reference BAD-TYPE-SPECIFICATION1;
;; here STRUCTURED is neither registered as a TYPE nor an alias)
(check-exn #rx"unknown declaration type STRUCTURED"
           (lambda () (run "<DECL? [1 2] STRUCTURED>")))
;; ANY used as a structured-type name (with elements) is an explicit failure,
;; while ANY as a simple or element pattern stays D1-supported
(check-exn #rx"DECL\\?: unsupported declaration pattern ANY"
           (lambda () (run "<DECL? (1 2) '<ANY [REST FIX]>>")))
(check-decl-true (run "<DECL? (1 \"s\") '<LIST [REST ANY]>>"))
;; !<struc elts> exact-count SEGMENT patterns splice into DECL?'s operand
;; list through the SUBR argument-splice path in the reference (recorded
;; #FALSE ((1 2) FIX) with the spliced extras ignored); here the same splice
;; reaches DECL? with extra operands and fails explicitly.
(check-exn exn:fail? (lambda () (run "<DECL? (1 2) !<LIST FIX FIX>>")))
(check-exn exn:fail? (lambda () (run "<DECL? (1 2 3) !<LIST FIX FIX>>")))

;; --- bounded traversal: cycles and nesting limits are explicit errors ------

;; A cyclic LIST value (PUTREST self-reference) is caught by LIST traversal
;; -- an explicit error naming the cycle, never an unbounded loop.
(check-exn #rx"cyclic LIST"
           (lambda ()
             (run "<SET L '(1 2)> <PUTREST .L .L> <DECL? .L '<LIST [REST FIX]>>")))
;; A structured pattern nested deeper than the traversal limit raises an
;; explicit, source-naming limit error instead of unbounded recursion. The
;; limit guard is entered from the pattern side, so it also bounds cyclic
;; values reachable through nested structure patterns.
(let* ([depth 210]
       [limit (number->string decl-match-max-depth)]
       [deep-pattern-text
        (string-append "'"
                       (for/fold ([s "FIX"]) ([i (in-range depth)])
                         (string-append "<LIST " s ">")))]
       [deep-value-text
        (string-append "'"
                       (for/fold ([s "1"]) ([i (in-range depth)])
                         (string-append "(" s ")")))]
       [source
        (format "<DECL? ~a ~a>" deep-value-text deep-pattern-text)])
  (define message
    (with-handlers ([exn:fail? exn-message]) (run source) "no error"))
  (check-true
   (string-contains? message "declaration pattern nesting exceeds traversal limit"))
  (check-true (string-contains? message limit)
              "the error text names the limit"))

;; --- loader session: the original pinned 81prim.mud PSETG installs ---------

;; The exact PSETG definition bytes from the pinned 81prim.mud (SHA-256
;; 8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571, verified
;; against the pinned file by tests/historical_decl_test.rkt; lines 10-19,
;; CRLF endings). The declaration <LIST [REST ATOM]> is the D3 acceptance; the
;; definition must now install. Its body then stops where MEMQ - a primitive
;; this slice deliberately does not add - is applied.
(define psetg-source
  (string-append
   "<DEFINE PSETG (FOO BAR \"AUX\" PL)\r\n"
   "        #DECL ((FOO) ATOM (PL) <LIST [REST ATOM]>)\r\n"
   "        <SETG .FOO .BAR>\r\n"
   "        <COND (<GASSIGNED? PURE-LIST> <SET PL ,PURE-LIST>)\r\n"
   "              (ELSE <SET PL <SETG PURE-LIST ()>>)>\r\n"
   "        <COND (<NOT <MEMQ .FOO .PL>>\r\n"
   "               <SETG PURE-LIST <SET PL (.FOO !.PL)>>)\r\n"
   "              (<AND <GASSIGNED? PURE-CAREFUL> ,PURE-CAREFUL>\r\n"
   "               <ERROR PSETG-DUPLICATE .FOO>)>\r\n"
   "        .BAR>\r\n"))
(define scratch-root
  (let ([p (make-temporary-file "mdl-decl-pattern-test~a" #f (find-system-path 'temp-dir))])
    (delete-file p)
    (make-directory* p)
    p))
(dynamic-wind
 void
 (lambda ()
   (define (put relative contents)
     (call-with-output-file (build-path scratch-root relative)
       #:exists 'truncate/replace (lambda (out) (display contents out))))
   (define (status report) (hash-ref report 'status))
   (put "psetg.mud" psetg-source)
   (define session (make-mdl-session scratch-root))
   ;; The declaration now normalizes at install time: the load PASSes.
   (check-equal? (status (mdl-session-load! session "psetg.mud")) "PASS")
   ;; Invoking the installed PSETG with a valid ATOM argument advances through
   ;; SETG and completes its MEMQ-backed PURE-LIST update.
   (define psetg-atom (mdl-session-call session "ATOM" "M2-D3-LVAL"))
   (check-equal? (mdl-session-call session "PSETG" psetg-atom 3) 3)
   (check-equal? (mdl-session-global session psetg-atom) 3)
   (check-equal? (mdl-list->list (mdl-session-global session "PURE-LIST"))
                 (list psetg-atom))
   ;; The repeat call updates the value without duplicating membership.
   (check-equal? (mdl-session-call session "PSETG" psetg-atom 4) 4)
   (check-equal? (mdl-list->list (mdl-session-global session "PURE-LIST"))
                 (list psetg-atom))
   (check-equal? (mdl-session-global session psetg-atom) 4))
 (lambda () (delete-directory/files scratch-root)))

;; --- review regressions (PR #50 independent review) -------------------------
;; A UVECTOR bracket (![...]) is not a repetition construction: the reference
;; errors DECL-ELEMENT-NOT-FORM-OR-ATOM; it must be an explicit error here
;; (review P2-1 - it was silently accepted as [REST ...]).
(check-exn #rx"repetition bracket must be a VECTOR"
           (lambda () (run "<DECL? (1 2) '<LIST ![REST FIX]>>")))
(check-exn #rx"repetition bracket must be a VECTOR"
           (lambda () (run "<DECL? [1 2] '<VECTOR ![REST FIX]>>")))
;; A failing <PRIMTYPE ...> check is the reference's plain FALSE: both as a
;; structured element and at the top level, the payload is bare #FALSE ()
;; (review P2-2 - it carried (element atom) instead).
(check-equal? (mdl-false-payload (run "<DECL? (1) '<LIST <PRIMTYPE ATOM>>>")) '())
(check-equal? (mdl-false-payload (run "<DECL? 1 '<PRIMTYPE LIST>>")) '())
(check-equal? (mdl-false-payload
               (run "<DECL? (1) '<LIST [REST <OR ATOM <PRIMTYPE ATOM>>]>>"))
              '())
;; A prefix-only structured pattern consumes only its prefix, so it matches
;; the prefix of a cyclic LIST like the reference (review P2-3 - the eager
;; traversal rejected the value); the REST loop keeps the explicit cycle
;; error as the documented safety deviation.
(check-equal? (mdl-atom-pname
               (run "<SET L '(1 2)> <PUTREST .L .L> <DECL? .L '<LIST FIX>>"))
              "T")
(check-exn #rx"cyclic"
           (lambda () (run "<SET L '(1 2)> <PUTREST .L .L> <DECL? .L '<LIST [REST FIX]>>")))
;; OR alternatives consume traversal budget too, so a pathological nested
;; pattern reports the documented limit instead of running unbounded
;; (review P3-4).
(let ([deep-or
       (let build ([n 250] [acc "FIX"])
         (if (zero? n) acc (build (sub1 n) (string-append "<OR " acc ">"))))])
  (check-exn #rx"traversal limit"
             (lambda () (run (string-append "<DECL? 1 '" deep-or ">")))))

(displayln "declaration pattern tests passed")
