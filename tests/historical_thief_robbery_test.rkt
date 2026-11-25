#lang racket/base
;; M4 Phase 3 scenario "the thief takes the painting" (epic #163; the thief,
;; observed, not chased; tests/scenarios/thief-robbery.json). The faithful
;; run.mud path, <FLOAD "77loadall.mud"> then SAVE-IT through the host
;; top-level loop, on the fixed session clock (fixed_epoch 250776000, zone
;; UTC; ADR-0052), with the unmodified pinned sources and no RANDOM override:
;; the treasure route of treasure-deposit without its `look` in the cellar.
;; This was the first route tried for the trophy case; under this clock and
;; seed the ROBBER demon (77act1.mud:1284) walks the thief into the Gallery
;; on the turn of `take painting` (SCORE-OBJ has already scored its OFVAL 4,
;; RAW-SCORE 39) and he takes the painting from the hero: "A seedy-looking
;; individual with a large bag just wandered through the room.  On the way
;; through, he quietly abstracted all valuables from the room and from your
;; possession, ..." (the painting goes to the ROBBER demon's HOBJS, his bag).
;; In the Studio he passes again: "A 'lean and hungry' gentleman just wandered
;; through.  Finding nothing of value, he left disgruntled." Up the chimney,
;; `west`, `open case`, `put painting in case` ("I can't see a paint here."),
;; `look`, `score` (39), `inventory` (the lamp only). The thief is never seen
;; in a room with the hero, never fought, and never fights.
;;
;; Prefix 12 (input ends in the Gallery before `take painting`): natively the
;; end-of-input turn's ROBBER takes the painting from the room instead
;; ("Beg pardon?" then the same seedy-looking text); it is re-run per prefix,
;; like every prefix whose end-of-input turn moves the thief (HROOM).
;;
;; Compared with the pinned Confusion captures in
;; docs/evidence/M4/thief-robbery-reference.json (THIEF-ROBBERY-REFERENCE.md)
;; through the shared runner tests/m4_scenario_runner.rkt, byte for byte
;; after D1 only. Scenario evidence for M4, not a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_thief_robbery_test.rkt   (exit status is authoritative)
(require rackunit racket/list racket/string "m4_scenario_runner.rkt" "m4_timers_checkpoint.rkt")

(current-check-handler (lambda (e) (raise e)))

(define commands '("north" "east" "open window" "west" "west" "take lamp" "move rug"
                   "open trap door" "turn on lamp" "down" "south" "south" "take painting"
                   "south" "up" "west" "open case" "put painting in case" "look" "score"
                   "inventory"))
(define seedy (string-append
               "Taken.\nA seedy-looking individual with a large bag just wandered through\r\n"
               "the room.  On the way through, he quietly abstracted all valuables\r\n"
               "from the room and from your possession, mumbling something about\r\n"
               "\"Doing unto others before..\"\n>"))

;; --- reference-side checks (no game run) ------------------------------------------------
(define reference (m4-reference "thief-robbery"))
(define ref-checks (hash-ref reference 'checks))
(define diagnostic (hash-ref reference 'diagnostic))
(define cps (hash-ref diagnostic 'checkpoints))
(define ends (hash-ref reference 'end_checkpoints))
(define (cp k key) (strip-trailers (hash-ref (list-ref cps k) key)))
(define (end k key) (strip-trailers (hash-ref (list-ref ends k) key)))
(check-equal? (remove-duplicates (hash-ref reference 'endings)) '("eof"))
;; By READSTRING entry: the thief's walk reaches the Gallery with the hero
;; at entry 13 (after `take painting`): the painting is in his bag, not with
;; the hero; RAW-SCORE keeps the painting's OFVAL. He stays out of sight
;; (thief_oroom false), and the bag keeps the painting to the end.
(define (row k) (list (cp k 'here) (cp k 'aobjs) (cp k 'raw_score) (cp k 'ascore)
                      (cp k 'paint_oroom) (cp k 'paint_ofval) (cp k 'robber_hroom)
                      (cp k 'robber_hflag) (cp k 'robber_hobjs) (cp k 'thief_oroom)))
(check-equal? (row 12) '("GALLE" "(LAMP)" "35" "35" "GALLE" "4" "CAVE4" "#FALSE ()" "()" "#FALSE ()"))
(check-equal? (row 13) '("GALLE" "(LAMP)" "39" "39" "#FALSE ()" "0" "GALLE" "T" "(PAINT)" "#FALSE ()"))
(check-equal? (row 14) '("STUDI" "(LAMP)" "39" "39" "#FALSE ()" "0" "STUDI" "T" "(PAINT)" "#FALSE ()"))
(check-equal? (row 22) '("LROOM" "(LAMP)" "39" "39" "#FALSE ()" "0" "MINE4" "#FALSE ()" "(PAINT)" "#FALSE ()"))
(check-equal? (list (cp 18 'tcase_oopen) (cp 22 'tcase_contents)) '("T" "()"))
(check-equal? (remove-duplicates (for/list ([k (in-range 0 23)]) (cp k 'thief_oroom))) '("#FALSE ()"))
;; Prefix 12's end of input: the thief takes the painting from the room.
(check-equal? (list (end 12 'paint_oroom) (end 12 'robber_hflag) (end 12 'robber_hobjs) (end 12 'aobjs))
              '("#FALSE ()" "T" "(PAINT)" "(LAMP)"))
(define t1 (hash-ref (hash-ref reference 'transcript) 'game_output_raw))
(check-true (string-contains? t1 seedy))
(check-true (string-contains? t1 ">I can't see a paint here.\n>"))
(check-true (string-contains? t1 "Your score would be 39 [total of 500 points], in 20 moves."))
(check-equal? (remove-duplicates (hash-ref ref-checks 'prefix_files_changed)) '(("MDL/MADADV.SAVE")))

;; --- the scenario ------------------------------------------------------------------------
(run-m4-scenario "thief-robbery" commands
                 #:checkpoint timers-checkpoint
                 #:check-turn
                 (lambda (k transcript)
                   (when (>= k 14)
                     (check-true (string-contains? transcript seedy)))))
