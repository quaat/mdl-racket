#lang racket/base
;; Historical proof chain for the session clock (issue #135 part 1, ADR-0052):
;; with the reference instant (fixed clock 250776000 = 1977-12-12 12:00:00,
;; zone UTC), the ORIGINAL startup code computes
;;   DSKDATE (81tell-repl.mud:57)
;;   -> the seed <RANDOM <CHTYPE <DSKDATE> FIX>> passed by START (77rooms.mud:291)
;;   -> the resulting session RANDOM state,
;; and SAVE-IT builds the "This version created" line from DSKDATE
;; (REMARKABLY-DISGUSTING-CODE, 77rooms.mud:158).
;;
;; Observation is host-only: the RANDOM state is read through
;; mdl-session-random-snapshot (a detached copy), and later outputs are
;; computed from that copy, so the game's sequence is never consumed. No game
;; function, global or call site is wrapped or patched.
;;
;; Every value below AGREES with the native pinned-Confusion reference
;; (mdli 6df359f6..., fixed_time.c shim, TZ=UTC, usec 0) recorded as Probe E in
;; CLOCK-SEED-REFERENCE.md / clock-seed-probe.json on branch
;; evidence/m3-session-probes (sha256 66b5f5d2... / 0250e007...; not yet
;; merged). Comparison: docs/evidence/M3/S8-SESSION-CLOCK.md.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: make test-m3-clock-seed   (or: raco test tests/historical_clock_seed_test.rkt)
(require rackunit racket/runtime-path
         "../mdl/loader.rkt" "../mdl/runtime/core.rkt" "../mdl/runtime/random36.rkt")

(define-runtime-path source-root
  "../.cache/upstream/mdlzork/mdlzork_771212/patched_confusion")
(unless (directory-exists? source-root)
  (error 'historical-clock-seed "pinned source missing: ~a" source-root))

(define fixed-epoch 250776000)          ; tests/fixtures/house-boot-golden.json fixed_epoch
(define out (open-output-string))
(define session (make-mdl-session source-root #:output-port out
                                  #:clock (make-fixed-mdl-clock fixed-epoch)
                                  #:time-zone 'utc))
(define load-report (mdl-session-load! session "77loadall.mud"))
(check-equal? (hash-ref load-report 'status) "PASS")
(check-equal? (hash-ref load-report 'completed_expressions) 1229)

;; --- DSKDATE: the documented bit layout (81tell-repl.mud:49-55) -----------------
;; 1977-12-12 12:00:00.000000 UTC: half-seconds 12*7200 in bits 0-17, day 12 at
;; bit 18, month 12 at bit 23, year-of-century 77 at bit 27.
(define expected-dskdate
  (+ (* 12 7200) (arithmetic-shift 12 18) (arithmetic-shift 12 23) (arithmetic-shift 77 27)))
(check-equal? expected-dskdate 10438660480)
;; The game's own DSKDATE, applied by the host (a pure function of the clock).
(define dskdate (mdl-session-call session "DSKDATE"))
(check-pred mdl-word? dskdate)
(check-equal? (mdl-word-bits dskdate) expected-dskdate)
;; The fixed clock never advances: a second read is identical.
(check-equal? (mdl-word-bits (mdl-session-call session "DSKDATE")) expected-dskdate)

;; --- RANDOM state before START: nothing in the load consumed RANDOM -----------
(define before (mdl-session-random-snapshot session))
(check-equal? (random36-state-words before) (list #o267762113337 #o155256071112))

;; --- SAVE-IT -> START -> <RANDOM <CHTYPE <DSKDATE> FIX>> -> CONTIN -> ,NULL ----
(define load-output-length (string-length (get-output-string out)))
(check-eq? (mdl-session-call session "SAVE-IT") (mdl-session-global session "NULL"))
(define saveit-output (substring (get-output-string out) load-output-length))
(define seed expected-dskdate)
;; START's INTIME is the same DSKDATE (77rooms.mud:277).
(check-equal? (mdl-word-bits (mdl-session-global session "INTIME")) seed)

;; The state after START equals exactly one one-seed RANDOM step from the
;; pre-START state with seed = DSKDATE: the second word holds the seed and
;; nothing else consumed RANDOM between the seed and CONTIN's return.
(define after (mdl-session-random-snapshot session))
(define independent (random36-state-copy before))
(define seeded-value (random36-next! independent seed))
(check-equal? (random36-state-words after) (random36-state-words independent))
(check-equal? (random36-state-words after) (list 16566282405 10438660480))
(check-equal? seeded-value 16566282405)

;; The next twelve RANDOM outputs of the game's sequence, from a COPY
;; (reference: the values after the seeding call's 16566282405).
(define next-twelve
  (let ([copy (random36-state-copy after)])
    (for/list ([_ (in-range 12)]) (random36-next! copy))))
(check-equal? next-twelve
              '(-21802663835 12914488375 -6577089531 34210328094 3437552668 13814526739
                -20114144995 11990399124 31711279130 25894896720 24534915165 -5538612619))
;; The first game draw is west's <PROB 80> (77rooms.mud:446, 521-525):
;; <MOD <RANDOM> 100> = 65 <= 80, so ROOM-INFO prints the brief text.
(check-equal? (modulo (car next-twelve) 100) 65)
;; The copies did not consume the session's sequence.
(check-equal? (random36-state-words (mdl-session-random-snapshot session))
              (list 16566282405 10438660480))

;; --- the version line (REMARKABLY-DISGUSTING-CODE via SAVE-IT's VERS) ----------
(check-equal? (mdl-session-global session "VERS") "This version created December 12.")
(check-equal? saveit-output "Welcome to Dungeon.\r\nThis version created December 12.\n")
