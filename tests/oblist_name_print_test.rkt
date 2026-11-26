#lang racket/base
;; Maintainer decision 2026-11-26 on PR #208 (ADR-0064 amendment, accepted):
;; an ATOM of an OBLIST whose name association was removed prints, when a
;; trailer is required, as P!-!-#FALSE () (reference-resolved ambiguity of
;; manual 15.2.1). Removing the name changes nothing else: ATOM identity,
;; OBLIST membership, local/global bindings, other associations and the
;; OBLIST path stay as they were, and a reachable ATOM still prints with no
;; trailer. Renaming or restoring the name changes only the printed trailer.
;; PRIN1, PRINT and UNPARSE agree (PRINT adds its newline and space).
;; Reference: docs/evidence/M4/i173-oblist-name-reference-raw.json (exact
;; stdout bytes of pinned Confusion 6df359f6...), cases in
;; i173-oblist-name-cases.json. READ/PARSE of these representations is not
;; claimed (language-conformance backlog, #177).
(require rackunit racket/runtime-path json
         "../mdl/parser.rkt" "../mdl/compiler.rkt" "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define-runtime-path cases-path "../docs/evidence/M4/i173-oblist-name-cases.json")
(define-runtime-path raw-path "../docs/evidence/M4/i173-oblist-name-reference-raw.json")

;; Each case is one PROG; LISTEN's echo (PRIN1 of the value, then a newline)
;; is emulated with this runtime's own PRIN1 and TERPRI. No normalisation.
(define (listen source)
  (define out (open-output-string))
  (parameterize ([current-namespace ns])
    (call-with-mdl-context
     (make-mdl-context #:input-port (open-input-string "") #:output-port out)
     (lambda ()
       (for ([expr (in-list (compile-program (parse-mdl source)))])
         (mdl-apply (mdl-root-atom "PRIN1") (eval expr))
         (mdl-apply (mdl-root-atom "TERPRI"))))))
  (get-output-string out))

(define cases
  (for/list ([c (in-list (hash-ref (call-with-input-file cases-path read-json) 'cases))])
    (cons (hash-ref c 'name) (hash-ref c 'expression))))
(define native
  (for/hash ([c (in-list (hash-ref (call-with-input-file raw-path read-json) 'cases))])
    (values (hash-ref c 'name) c)))
(check-equal? (map car cases)
              '("name-removed-membership-identity" "name-removed-bindings-properties-path"
                "name-removed-reachable-no-trailer" "name-removed-restored-renamed"
                "printers-agree"))
(for ([c (in-list cases)])
  (define row (hash-ref native (car c)))
  (check-equal? (hash-ref row 'exit_code) 0 (car c))
  (check-equal? (hash-ref row 'stderr_bytes) "" (car c))
  (check-equal? (listen (cdr c)) (hash-ref row 'result_bytes) (car c)))

;; The same facts, stated directly (they are what the native bytes say).
(define (out-of name) (hash-ref (hash-ref native name) 'result_bytes))
;; Membership, identity, and the name->OBLIST association survive.
(check-equal? (out-of "name-removed-membership-identity") "(T T T)\n")
;; GVAL, LVAL, an unrelated association and the OBLIST path survive.
(check-equal? (out-of "name-removed-bindings-properties-path") "(42 7 9 T)\n")
;; Reachable: no trailer; off the path: the unnamed form.
(check-equal? (out-of "name-removed-reachable-no-trailer") "QX3\nQX3!-!-#FALSE ()\n0\n")
;; Restoring and renaming the name changes only the trailer.
(check-equal? (out-of "name-removed-restored-renamed")
              "QX4!-!-#FALSE ()\nQX4!-OBQ4\nQX4!-OTHERNAME\nT\n")
