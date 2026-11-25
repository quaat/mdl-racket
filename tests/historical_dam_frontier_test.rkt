#lang racket/base
;; M4 Phase 3b FRONTIER record (epic #163; INV-11 in
;; docs/evidence/M4/GAMEPLAY-FAILURE-INVENTORY.md): the Flood Control Dam #3
;; puzzle and its leak clock MNTIN are not reachable in this runtime. A
;; tracked expected failure (XFAIL), not a parity check: it passes while the
;; runtime still stops where recorded, and fails (XPASS) once the
;; Maintenance Room can be entered, so that the two routes are promoted to
;; gated scenarios with their committed native references.
;;
;; Both routes (tests/scenarios/dam-sluice.json, tests/scenarios/maint-leak.json)
;; share troll-combat's first sixteen commands, then north, north, down, up,
;; east (the Dam), north (Dam Lobby), north (the Maintenance Room, command 23).
;; Natively (docs/evidence/M4/dam-sluice-reference.json, maint-leak-reference.json,
;; captured twice, byte-identical transcripts) the game goes on: the yellow
;; button sets GATE-FLAG, the wrench opens the sluice gates (LOW-TIDE), the
;; trunk appears in the drained reservoir; the blue button starts the leak,
;; MNTIN raises the Maintenance Room's RVARS on every clock tick and the putty
;; plugs it. In this runtime, entering the room applies the room action
;; MAINT-ROOM (77act1.mud:737), whose attached #DECL names PRSO's type as
;; PRSOBJ (77act1.mud:741), a type no 1977 source file defines; the attached
;; declaration check raises "unknown declaration type PRSOBJ" (strict by the
;; deferred-declaration ADR, issue #98; pinned Confusion does not check
;; attached declarations). The runner reports READSTRING entries 0-22 equal to
;; the reference and the earliest failing k = 23.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_dam_frontier_test.rkt   (exit status is authoritative)
(require rackunit racket/list racket/string "m4_scenario_runner.rkt" "m4_dam_checkpoint.rkt")

(current-check-handler (lambda (e) (raise e)))

(define troll16
  '("north" "east" "open window" "west" "west" "take sword" "inventory" "take lamp" "move rug"
    "open trap door" "turn on lamp" "down" "east"
    "kill troll with sword" "kill troll with sword" "kill troll with sword"))
(define to-maint '("north" "north" "down" "up" "east" "north" "north"))
(define dam-sluice
  (append troll16 to-maint
          '("take wrench" "south" "south" "turn bolt with wrench"
            "north" "north" "push yellow button" "south" "south" "look" "turn bolt with wrench" "look"
            "south" "nw" "look" "take trunk" "north" "score")))
(define maint-leak
  (append troll16 to-maint
          '("push blue button" "look" "take tube" "open tube" "take putty" "wait"
            "plug leak with putty" "wait" "look" "push blue button" "south" "score")))

(define (cps-of name) (hash-ref (hash-ref (m4-reference name) 'diagnostic) 'checkpoints))
(define ((cp-of name) k key) (strip-trailers (hash-ref (list-ref (cps-of name) k) key)))
(define (t1-of name) (hash-ref (hash-ref (m4-reference name) 'transcript) 'game_output_raw))

;; --- native facts (reference only) -------------------------------------------------------
(check-equal? (hash-ref (m4-reference "dam-sluice") 'commands) dam-sluice)
(check-equal? (hash-ref (m4-reference "maint-leak") 'commands) maint-leak)
(for ([name '("dam-sluice" "maint-leak")])
  (check-equal? (remove-duplicates (hash-ref (m4-reference name) 'endings)) '("eof"))
  (check-equal? ((cp-of name) 23 'here) "MAINT")
  ;; the thief never meets the hero on either route
  (check-equal? (remove-duplicates (for/list ([k (in-range (length (cps-of name)))])
                                     (list ((cp-of name) k 'thief_oroom) ((cp-of name) k 'robber_hobjs))))
                '(("#FALSE ()" "()"))))
;; dam-sluice: refused bolt (27), yellow button (30), gates open (34), the
;; trunk taken from the drained reservoir (39), across it to Reservoir North (40).
(define ds (cp-of "dam-sluice"))
(check-equal? (for/list ([k '(26 27 30 33 34 39 40)])
                (list k (ds k 'here) (ds k 'gate_flag) (ds k 'low_tide) (ds k 'trunk_visible) (ds k 'raw_score)))
              '((26 "DAM" "#FALSE ()" "#FALSE ()" "#FALSE ()" "40")
                (27 "DAM" "#FALSE ()" "#FALSE ()" "#FALSE ()" "40")
                (30 "MAINT" "T" "#FALSE ()" "#FALSE ()" "40")
                (33 "DAM" "T" "#FALSE ()" "#FALSE ()" "40")
                (34 "DAM" "T" "T" "T" "40")
                (39 "RESES" "T" "T" "T" "55")
                (40 "RESEN" "T" "T" "T" "55")))
(check-true (string-contains? (t1-of "dam-sluice")
                              ">The bolt won't turn with your best effort.\n>"))
(check-true (string-contains? (t1-of "dam-sluice")
                              "The green bubble is glowing.\n>The sluice gates open and water pours through the dam.\n>"))
;; maint-leak: the leak (24) queues MNTIN with CTICK -1 (fires on every
;; CLOCK-DEMON pass); RVARS rises once per pass (five passes during `wait`);
;; the putty (30) sets RVARS -1 and MNTIN's CTICK 0.
(define ml (cp-of "maint-leak"))
(check-equal? (for/list ([k (in-range 23 36)]) (list k (ml k 'maint_rvars) (ml k 'mntin_ctick)))
              '((23 "0" "0") (24 "2" "-1") (25 "3" "-1") (26 "4" "-1") (27 "5" "-1") (28 "6" "-1")
                (29 "11" "-1") (30 "-1" "0") (31 "-1" "0") (32 "-1" "0") (33 "-1" "0") (34 "-1" "0")
                (35 "-1" "0")))
(check-equal? (ml 24 'clock_events) "((MNTIN T -1) (CURIN #FALSE () 0) (LNTIN T 336))")
(check-equal? (remove-duplicates (for/list ([k (in-range 0 37)]) (ml k 'maint_munged))) '("#FALSE ()"))
(check-equal? (length (regexp-match* #rx"The water level here is now " (t1-of "maint-leak"))) 10)
(check-true (string-contains? (t1-of "maint-leak")
                              "you have managed to stop the\r\nleak in the dam.\n>Time passes...\n>"))

;; --- the expected failure in this runtime ------------------------------------------------
(define (expect-frontier name commands)
  (define msg
    (with-handlers ([exn:fail? exn-message])
      (run-m4-scenario name commands
                       #:checkpoint dam-checkpoint
                       #:eof-classification-ignore-keys '(robber_hroom))
      #f))
  (check-true (string? msg) (format "~a: XPASS - the Maintenance Room is reachable now; promote the scenario" name))
  (check-true (string-contains? msg "earliest failing k = 23, kind run-guard") msg)
  (check-true (string-contains? msg "unknown declaration type PRSOBJ") msg)
  (printf "~a: XFAIL as recorded (entries 0-22 equal the reference; k = 23: PRSOBJ)\n" name))
(expect-frontier "dam-sluice" dam-sluice)
(expect-frontier "maint-leak" maint-leak)
