#lang racket/base
;; Reference-backed OBLIST placement after the full 1977 source load
;; (PR #118 maintainer review). Needs the pinned source (.cache/upstream);
;; run by `make test-historical`, not by the smoke suite.
;;
;; Reference: docs/evidence/M3/review/confusion-77loadall-placement.json,
;; recorded by `python3 -m scripts.confusion_oblist_dump placement`
;; (pinned Confusion, <FLOAD "77loadall.mud"> in a $TMPDIR copy of the game
;; directory). Each entry is (label PNAME): label is ROOT, INITIAL, or
;; @NAME for the OBLIST associated with atom NAME on ROOT or INITIAL. The
;; same projection of this runtime's session must match exactly, except
;; for the documented allowlist below; stale allowlist entries also fail.
(require racket/list racket/runtime-path racket/set racket/string json
         "../mdl/loader.rkt" "../mdl/runtime/core.rkt")

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(define-runtime-path reference-path
  "../docs/evidence/M3/review/confusion-77loadall-placement.json")

;; (side label pname reason). side: 'reference-only or 'runtime-only.
;; (side label pname reason). side: 'reference-only or 'runtime-only.
;; Every entry is a known, separately tracked deviation; see
;; docs/evidence/M3/review/R3R4.md "Placement allowlist".
(define allowlist
  (append
   ;; Separate reader issue: `;` comments the next OBJECT, which MDL READs
   ;; (81tell-repl.mud:40-42 `; Read a line ...`, `; (ALT not supported
   ;; yet)`), interning its atoms; this reader discards comment text.
   (for/list ([name (in-list '("Read" "not" "supported" "yet"))])
     (list 'reference-only "INITIAL" name
           "`;` comment object not READ by this reader (separate issue)"))
   ;; Confusion's startup INTERRUPTS OBLIST contents (interpreter-internal
   ;; names, four with trailing blanks), present before any source is read;
   ;; the INTERRUPTS OBLIST inventory is not modelled (follow-up).
   (for/list ([name (in-list '("INT-LEVEL" "L-ERR " "L-LEVEL " "LMAP " "LPROG "))])
     (list 'reference-only "@INTERRUPTS" name
           "Confusion startup INTERRUPTS OBLIST content not modelled (follow-up)"))))

(define (reference-entries)
  (define data (call-with-input-file reference-path read-json))
  (unless (and (hash-ref data 'ok #f) (eqv? (hash-ref data 'exit_code #f) 0))
    (error 'placement "reference dump is not a successful recording"))
  (for/set ([entry (in-list (hash-ref data 'entries))])
    (cons (first entry) (second entry))))

(define (runtime-entries)
  (define session (make-mdl-session source-root))
  (define result (mdl-session-load! session "77loadall.mud"))
  (unless (equal? (hash-ref result 'status) "PASS")
    (error 'placement "source load failed: ~a" (hash-ref result 'failure)))
  (define (call name . args) (apply mdl-session-call session name args))
  (define oblist-indicator (mdl-session-atom session "OBLIST!-"))
  (define root (call "ROOT"))
  (define initial (call "GET" (mdl-session-atom session "INITIAL!-") oblist-indicator))
  (define entries (mutable-set))
  (define (dump! label oblist)
    (for ([pname (in-list (mdl-oblist-pnames oblist))])
      (set-add! entries (cons label pname))))
  (dump! "ROOT" root)
  (dump! "INITIAL" initial)
  (for ([oblist (in-list (list root initial))])
    (for ([pname (in-list (mdl-oblist-pnames oblist))])
      (define atom (call "LOOKUP" pname oblist))
      (define named (call "GET" atom oblist-indicator))
      (when (and (mdl-oblist? named) (not (eq? named root)) (not (eq? named initial)))
        (dump! (string-append "@" pname) named))))
  (for/set ([e (in-set entries)]) e))

(define reference (reference-entries))
(define runtime (runtime-entries))
(define reference-only (set-subtract reference runtime))
(define runtime-only (set-subtract runtime reference))

(define (allowed? side entry)
  (for/or ([a (in-list allowlist)])
    (and (eq? (first a) side) (equal? (second a) (car entry))
         (equal? (third a) (cdr entry)))))

(define failures '())
(define (fail! fmt . args)
  (set! failures (cons (apply format fmt args) failures)))

(for ([side (in-list '(reference-only runtime-only))]
      [diff (in-list (list reference-only runtime-only))])
  (for ([entry (in-list (sort (set->list diff)
                              (lambda (a b) (string<? (format "~a" a) (format "~a" b)))))])
    (if (allowed? side entry)
        (printf "ALLOWLISTED ~a ~a ~s: ~a\n" side (car entry) (cdr entry)
                (fourth (findf (lambda (a) (and (eq? (first a) side)
                                                (equal? (second a) (car entry))
                                                (equal? (third a) (cdr entry))))
                               allowlist)))
        (fail! "~a ~a ~s" side (car entry) (cdr entry)))))

(for ([a (in-list allowlist)])
  (define entry (cons (second a) (third a)))
  (unless (set-member? (if (eq? (first a) 'reference-only) reference-only runtime-only)
                       entry)
    (fail! "stale allowlist entry ~a ~a ~s" (first a) (second a) (third a))))

(printf "placement: reference ~a entries, runtime ~a entries, ~a reference-only, ~a runtime-only\n"
        (set-count reference) (set-count runtime)
        (set-count reference-only) (set-count runtime-only))
(unless (null? failures)
  (for ([f (in-list (reverse failures))]) (eprintf "MISMATCH ~a\n" f))
  (error 'placement "~a OBLIST placement mismatches against pinned Confusion"
         (length failures)))
(printf "historical OBLIST placement matches pinned Confusion (~a entries)\n"
        (set-count reference))
