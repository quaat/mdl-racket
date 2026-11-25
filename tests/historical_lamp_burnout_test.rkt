#lang racket/base
;; M4 Phase 3 scenario "the lamp burns out" (epic #163, timers;
;; tests/scenarios/lamp-burnout.json). The faithful run.mud path,
;; <FLOAD "77loadall.mud"> then SAVE-IT through the host top-level loop, on
;; the fixed session clock (fixed_epoch 250776000, zone UTC; ADR-0052), with
;; the unmodified pinned sources and no RANDOM override: into the living
;; room, `take lamp`, `turn on lamp` (LANTERN enables the clock event LNTIN,
;; CTICK 350, 77dung.mud:2388), then `wait` 118 times. WAIT (77rooms.mud:1619)
;; runs CLOCK-DEMON up to three more times after "Time passes..." and stops
;; when an event fires, so a `wait` is up to four lamp ticks. Each time LNTIN
;; fires, LIGHT-INT (77act1.mud:2006) counts it in <1 <ORAND lamp>>, re-arms
;; LNTIN from LAMP-TICKS [50 30 20 10 4 0] and prints LAMP-TELLS: "The lamp
;; appears to be getting dimmer." after `wait` 95, 108, 116 and 121 (commands),
;; "The lamp is dying." after 124, and after 125 (tick 0) "I hope you have
;; more light than from a lamp." with OLIGHT? 0. Then `turn on lamp` ("You
;; can't turn that on."), `look`, `move rug`, `open trap door`, `down` into
;; the cellar, now dark ("It is pitch black.  You are likely to be eaten by a
;; grue."), `score`.
;;
;; robber_hroom is not compared here (#:ignore-keys). The ROBBER demon moves
;; the thief on every turn, the end-of-input turn included, so with it every
;; one of the 131 shorter prefixes would have a non-standard end checkpoint
;; and be re-run per prefix (131 boots, about 20 minutes) in single-run mode.
;; The hero stays above ground until the last two commands, the thief never
;; meets him and his bag stays empty (thief_oroom, robber_hflag and
;; robber_hobjs are compared); the thief's walk (HROOM) is compared turn by
;; turn and at every prefix's end of input in treasure-deposit, thief-robbery
;; and cure-recovery.
;;
;; Compared with the pinned Confusion captures in
;; docs/evidence/M4/lamp-burnout-reference.json (LAMP-BURNOUT-REFERENCE.md)
;; through the shared runner tests/m4_scenario_runner.rkt, byte for byte
;; after D1 only. Scenario evidence for M4, not a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_lamp_burnout_test.rkt   (exit status is authoritative)
(require rackunit racket/list racket/string "m4_scenario_runner.rkt" "m4_timers_checkpoint.rkt")

(current-check-handler (lambda (e) (raise e)))

(define commands (append '("north" "east" "open window" "west" "west" "take lamp" "turn on lamp")
                         (make-list 118 "wait")
                         '("turn on lamp" "look" "move rug" "open trap door" "down" "score")))
(define dimmer "The lamp appears to be getting dimmer.\n")
(define dying "The lamp is dying.\n")
(define out "I hope you have more light than from a lamp.\n")

;; --- reference-side checks (no game run) ------------------------------------------------
(define reference (m4-reference "lamp-burnout"))
(define ref-checks (hash-ref reference 'checks))
(define diagnostic (hash-ref reference 'diagnostic))
(define cps (hash-ref diagnostic 'checkpoints))
(define (cp k key) (strip-trailers (hash-ref (list-ref cps k) key)))
(check-equal? (remove-duplicates (hash-ref reference 'endings)) '("eof"))
;; The lamp clock by READSTRING entry: off (CTICK 350) until `turn on lamp`;
;; then on, and LIGHT-INT's count goes 0 -> 6 at entries 95, 108, 116, 121,
;; 124 and 125; at 125 LNTIN is left at tick 0 (still enabled) and the lamp
;; gives no light.
(define (lamp k) (list (cp k 'lamp_cnt) (cp k 'lamp_olight) (cp k 'lntin_cflag) (cp k 'lntin_ctick)))
(check-equal? (lamp 6) '("0" "-1" "#FALSE ()" "350"))
(check-equal? (lamp 7) '("0" "1" "T" "349"))
(check-equal? (lamp 8) '("0" "1" "T" "345"))
(check-equal? (for/list ([k (in-range 7 133)]
                         #:when (not (equal? (cp k 'lamp_cnt) (cp (sub1 k) 'lamp_cnt))))
                (list k (cp k 'lamp_cnt) (cp k 'lntin_ctick)))
              '((95 "1" "49") (108 "2" "29") (116 "3" "19") (121 "4" "9") (124 "5" "3") (125 "6" "0")))
(check-equal? (lamp 125) '("6" "0" "T" "0"))
(check-equal? (lamp 132) (lamp 125))
;; LNTIN is the only clock event ever queued (the cure clock never is).
(check-equal? (remove-duplicates (for/list ([k (in-range 7 133)])
                                   (regexp-replace #rx"[0-9]+" (cp k 'clock_events) "N")))
              '("((LNTIN T N))"))
(check-equal? (list (cp 130 'here) (cp 132 'here) (cp 132 'aobjs)) '("CELLA" "CELLA" "(LAMP)"))
;; The thief never meets the hero and takes nothing.
(check-equal? (remove-duplicates (for/list ([k (in-range 0 133)])
                                   (list (cp k 'thief_oroom) (cp k 'robber_hflag) (cp k 'robber_hobjs))))
              '(("#FALSE ()" "#FALSE ()" "()")))
;; Every shorter prefix is non-standard only through the thief's move on its
;; end-of-input turn: the end checkpoint differs from the entry checkpoint in
;; robber_hroom and nothing else, and every tail is "Beg pardon?\n>".
(define ends (hash-ref reference 'end_checkpoints))
(check-equal? (remove-duplicates
               (for/list ([k (in-range 0 131)])
                 (for/list ([(key v) (in-hash (list-ref cps k))]
                            #:unless (eq? key 'n)
                            #:unless (equal? v (hash-ref (list-ref ends k) key)))
                   key)))
              '(() (robber_hroom)))
(define t1 (hash-ref (hash-ref reference 'transcript) 'game_output_raw))
(check-equal? (length (regexp-match* (regexp-quote dimmer) t1)) 4)
(check-equal? (length (regexp-match* (regexp-quote dying) t1)) 1)
(check-equal? (length (regexp-match* (regexp-quote out) t1)) 1)
(check-true (string-contains? t1 (string-append ">Time passes...\n" dying ">Time passes...\n" out
                                                ">You can't turn that on.\n")))
(check-true (string-contains? t1 ">It is pitch black.  You are likely to be eaten by a grue.\n>"))
(check-equal? (remove-duplicates (hash-ref ref-checks 'prefix_files_changed)) '(("MDL/MADADV.SAVE")))

;; --- the scenario ------------------------------------------------------------------------
(run-m4-scenario "lamp-burnout" commands
                 #:checkpoint timers-checkpoint/no-hroom
                 #:ignore-keys '(robber_hroom)
                 #:check-turn
                 (lambda (k transcript)
                   (when (>= k 126)
                     (check-true (string-contains? transcript (string-append dying ">Time passes...\n" out))))))
