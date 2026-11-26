#lang racket/base
;; M4 Phase 3c scenario "the gas room" (epic #163, objects beyond the house;
;; tests/scenarios/gas-room.json). The faithful run.mud path, <FLOAD
;; "77loadall.mud"> then SAVE-IT through the host top-level loop, on the fixed
;; session clock (fixed_epoch 250776000, zone UTC; ADR-0052), with the
;; unmodified pinned sources and no RANDOM override.
;;
;; Commands 1-50 are coal-machine's (to the Shaft Room, carrying the lamp and
;; the burning candles). Then `north` (Wooden Tunnel), `west` (Smelly Room),
;; `drop candles` (53), `down` (54) into the Gas Room with the lamp and no
;; flame: BOOM-ROOM (77act2.mud:3) checks the walk-in, finds neither burning
;; candles nor a burning torch carried, and nothing happens; `take bracelet`
;; (55, RAW-SCORE 40 -> 45); `up`; `take candles` (57); `down` (58) carrying
;; the burning candles: "Oh dear.  It appears that the smell coming from this
;; room was coal gas.  I would have thought twice about carrying a pair of
;; candles in here.", FWEEP's six bells, "   BOOOOOOOOOOOM      " and JIGS-UP
;; (DEATHS 1, RAW-SCORE 45 -> 35). READSTRING entry 58 is YES/NO's: its
;; prompt is the death question, not `>` (#:entry-prompts, ADR-0062
;; amendment); `y` (patched: the forest, the objects scattered, the bracelet
;; to ALISM); `look`, `inventory`, `score`. Prefix 58 (input ends at the
;; question) is patched too: YES/NO's end-of-input read returns 0 and the
;; stale first character of INBUF, "d" of "down", answers: not one of
;; "NnfF", so yes (77defs.mud:431-438).
;;
;; The thief (ROBBER demon) takes the trident and the trunk from rooms the
;; hero has left and never meets the hero. Prefixes 36 and 38 (the sword's
;; glow), 53 (his bag at the end-of-input turn) and 58 (the question) are
;; re-run; robber_hroom is compared at every READSTRING entry, at the end and
;; in per-prefix mode, but not used to classify end-of-input tails
;; (#:eof-classification-ignore-keys, ADR-0062 amendment).
;;
;; Compared with the pinned Confusion captures in
;; docs/evidence/M4/gas-room-reference.json (GAS-ROOM-REFERENCE.md, captured
;; twice, byte-identical transcripts) through the shared runner
;; tests/m4_scenario_runner.rkt, byte for byte after D1 only. Scenario
;; evidence for M4, not a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_gas_room_test.rkt   (exit status is authoritative)
(require rackunit racket/list racket/string "m4_scenario_runner.rkt" "m4_puzzles_checkpoint.rkt")

(current-check-handler (lambda (e) (raise e)))

(define question "Do you want me to try to patch you?")
(define commands
  (append (take (hash-ref (m4-reference "coal-machine") 'commands) 50)
          '("north" "west" "drop candles" "down" "take bracelet" "up" "take candles" "down"
            "y" "look" "inventory" "score")))

;; --- reference-side checks (no game run) ------------------------------------------------
(define reference (m4-reference "gas-room"))
(define ref-checks (hash-ref reference 'checks))
(define cps (hash-ref (hash-ref reference 'diagnostic) 'checkpoints))
(define (cp k key) (strip-trailers (hash-ref (list-ref cps k) key)))
(define t1 (hash-ref (hash-ref reference 'transcript) 'game_output_raw))
(check-equal? (hash-ref reference 'commands) commands)
(check-equal? (length commands) 62)
(check-equal? (list-ref commands 50) "north")
(check-equal? (hash-ref reference 'entry_prompts) (hasheq '|58| question))
(check-equal? (hash-ref ref-checks 'diag_yes_no_entries) '(58))
(check-equal? (hash-ref ref-checks 'diag_yes_no_results) '("T"))
(check-equal? (remove-duplicates (hash-ref reference 'endings)) '("eof"))
;; (HERE AOBJS CANDL-OROOM CANDL-OLIGHT BRACE-OROOM DEATHS RAW-SCORE) by entry
(define (gas k) (map (lambda (key) (cp k key))
                     '(here aobjs candl_oroom candl_olight brace_oroom deaths raw_score)))
(check-equal?
 (for/list ([k (in-range 50 63)]) (cons k (gas k)))
 '((50 "TSHAF" "(CANDL SCREW WRENC LAMP SWORD)" "#FALSE ()" "1" "BOOM" "0" "40")
   (51 "TUNNE" "(CANDL SCREW WRENC LAMP SWORD)" "#FALSE ()" "1" "BOOM" "0" "40")
   (52 "SMELL" "(CANDL SCREW WRENC LAMP SWORD)" "#FALSE ()" "1" "BOOM" "0" "40")
   (53 "SMELL" "(SCREW WRENC LAMP SWORD)" "SMELL" "1" "BOOM" "0" "40")          ; drop candles
   (54 "BOOM" "(SCREW WRENC LAMP SWORD)" "SMELL" "1" "BOOM" "0" "40")           ; no flame: nothing
   (55 "BOOM" "(BRACE SCREW WRENC LAMP SWORD)" "SMELL" "1" "#FALSE ()" "0" "45")
   (56 "SMELL" "(BRACE SCREW WRENC LAMP SWORD)" "SMELL" "1" "#FALSE ()" "0" "45")
   (57 "SMELL" "(CANDL BRACE SCREW WRENC LAMP SWORD)" "#FALSE ()" "1" "#FALSE ()" "0" "45")
   (58 "BOOM" "(CANDL BRACE SCREW WRENC LAMP SWORD)" "#FALSE ()" "1" "#FALSE ()" "1" "35") ; the question
   (59 "FORE1" "()" "KITCH" "1" "ALISM" "1" "35")                               ; patched
   (60 "FORE1" "()" "KITCH" "1" "ALISM" "1" "35")
   (61 "FORE1" "()" "KITCH" "1" "ALISM" "1" "35")
   (62 "FORE1" "()" "KITCH" "1" "ALISM" "1" "35")))
;; the thief: takes the trident and the trunk, never in the hero's room
(check-equal? (remove-duplicates (for/list ([k (in-range 0 63)]) (cp k 'thief_oroom))) '("#FALSE ()"))
;; shorter prefixes: non-standard through the thief (HROOM, his bag at 53) and
;; the question (58: the patch at the end-of-input answer)
(define ends (hash-ref reference 'end_checkpoints))
(check-equal? (for/list ([k (in-range 0 62)]
                         #:when (for/or ([(key v) (in-hash (list-ref cps k))])
                                  (and (not (memq key '(n robber_hroom)))
                                       (not (equal? v (hash-ref (list-ref ends k) key))))))
                k)
              '(53 58))
(check-equal? (cp 58 'here) "BOOM")
(check-equal? (strip-trailers (hash-ref (list-ref ends 58) 'here)) "FORE1")
(check-true (string-contains? t1 ">You are in a small room which smells strongly of coal gas.\nThere is a sapphire-encrusted bracelet here.\n>Taken.\n"))
(check-true (string-contains? t1 (string-append
                                  ">Gas Room\nOh dear.  It appears that the smell coming from this room was coal\r\n"
                                  "gas.  I would have thought twice about carrying a pair of candles in here.\n"
                                  "\a\a\a\a\a\a   BOOOOOOOOOOOM      \n" question "Now, let me see...")))
(check-true (string-contains? t1 "Your score would be 35 [total of 500 points], in 61 moves."))

;; --- the scenario ------------------------------------------------------------------------
(run-m4-scenario "gas-room" commands
                 #:checkpoint puzzles-checkpoint
                 #:entry-prompts (hasheqv 58 question)
                 #:eof-classification-ignore-keys '(robber_hroom)
                 #:check-turn
                 (lambda (k transcript)
                   (when (>= k 59)
                     (check-true (string-contains? transcript (string-append "BOOOOOOOOOOOM      \n" question))))))
