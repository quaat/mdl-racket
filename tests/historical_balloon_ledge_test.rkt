#lang racket/base
;; M4 Phase 3c scenario "the balloon" (epic #163, objects beyond the house;
;; tests/scenarios/balloon-ledge.json). Gated since M4 #196 (INV-12 resolved;
;; maintainer decision 2026-11-26: attached declarations are not enforced,
;; DECISIONS.md, the attached-declaration ADR amendment). It replaces the
;; tracked expected failure tests/historical_balloon_frontier_test.rkt (make
;; xfail-m4-balloon-frontier, retired), whose native assertions are kept below.
;;
;; The faithful run.mud path, <FLOAD "77loadall.mud"> then SAVE-IT through the
;; host top-level loop, on the fixed session clock (fixed_epoch 250776000,
;; zone UTC; ADR-0052), with the unmodified pinned sources and no RANDOM
;; override. The route (81 commands): troll-combat's sixteen; the studio and
;; the chimney to the kitchen, the attic's rope, back through the trap door;
;; the Dam Lobby (guidebook, matchbook); the Dome Room (`tie rope to
;; railing`), the Torch Room (`take torch`); the Glacier Room (`throw torch
;; at glacier`); the Ruby Room, the Lava Room, the Volcano Bottom (54);
;; `open receptacle`, `put guide in receptacle`, `board basket` (57), `light
;; match`, `burn guide with match` (59: BINF GUIDE, BINT and BRNIN queued),
;; the balloon rises to VAIR1 (61) and VAIR2 (64), lands on the Narrow Ledge
;; (66), the wire is tied to the hook (68: WIRE-FUNCTION, BTIE T, BINT
;; disabled) and untied (71), the balloon leaves the ledge (73), descends
;; after `close receptacle` (76) and lands at the Volcano Bottom (79);
;; `disembark`, `score`.
;;
;; Until #196 this runtime stopped at command 57: after the demons RDCOM
;; (77rooms.mud:651) applies the vehicle's action BALLOON with READ-OUT;
;; CLOCK-DEMON (77rooms.mud:1633) has put #FALSE () in <2 ,PRSVEC>, and
;; BALLOON binds (PRSO <2 .PRSVEC>) under its attached #DECL (PRSO) <OR OBJECT
;; DIRECTION> (77act2.mud:424-425); from command 59 on its (BINF ,BINF!-FLAG)
;; <OR FALSE ROOM> holds the OBJECT GUIDE (77act2.mud:426, 488). Pinned
;; Confusion checks no attached declaration; neither does this runtime now.
;;
;; The ROBBER demon moves the thief (HROOM) on every turn: robber_hroom is
;; compared at every READSTRING entry, at the end and in per-prefix mode, but
;; not used to classify end-of-input tails (#:eof-classification-ignore-keys,
;; ADR-0062 amendment).
;;
;; Compared with the pinned Confusion captures in
;; docs/evidence/M4/balloon-ledge-reference.json (BALLOON-LEDGE-REFERENCE.md,
;; captured twice, byte-identical transcripts) through the shared runner
;; tests/m4_scenario_runner.rkt, byte for byte after D1 only, with the
;; puzzles checkpoint profile. Scenario evidence for M4, not a PLAYABLE claim.
;;
;; Requires the pinned upstream source: .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/
;; Run with: racket tests/historical_balloon_ledge_test.rkt   (exit status is authoritative)
(require rackunit racket/list racket/string "m4_scenario_runner.rkt" "m4_puzzles_checkpoint.rkt")

(current-check-handler (lambda (e) (raise e)))

(define troll16 (take (hash-ref (m4-reference "troll-combat") 'commands) 16))
(define commands
  (append troll16
          '("east" "south" "up" "up" "take rope" "down" "west" "open trap door" "down"
            "east" "north" "north" "down" "up" "east" "north" "take guide" "take match"
            "south" "south" "nw" "south" "west" "east" "tie rope to railing" "down" "take torch"
            "down" "east" "north" "north" "west" "nw" "up" "throw torch at glacier"
            "west" "west" "south"
            "open receptacle" "put guide in receptacle" "board basket" "light match"
            "burn guide with match" "look" "look" "look" "look" "look" "look" "west" "disembark"
            "tie wire to hook" "south" "north" "untie wire" "board basket" "look" "look" "look"
            "close receptacle" "look" "look" "look" "disembark" "score")))

;; --- native facts (reference only; from the retired frontier test) ----------------------
(define reference (m4-reference "balloon-ledge"))
(define cps (hash-ref (hash-ref reference 'diagnostic) 'checkpoints))
(define (cp k key) (strip-trailers (hash-ref (list-ref cps k) key)))
(define t1 (hash-ref (hash-ref reference 'transcript) 'game_output_raw))
(check-equal? (hash-ref reference 'commands) commands)
(check-equal? (length commands) 81)
(check-equal? (list-ref commands 56) "board basket")
(check-equal? (remove-duplicates (hash-ref reference 'endings)) '("eof"))
;; the way there: the rope (21), tied (41), the torch (43) thrown (51)
(check-equal? (for/list ([k '(21 41 43 51 54)])
                (list k (cp k 'here) (cp k 'rope_oroom) (cp k 'dome_flag) (cp k 'torch_oroom)
                      (cp k 'torch_olight) (cp k 'glacier_flag)))
              '((21 "ATTIC" "#FALSE ()" "#FALSE ()" "MTORC" "1" "#FALSE ()")
                (41 "DOME" "DOME" "T" "MTORC" "1" "#FALSE ()")
                (43 "MTORC" "DOME" "T" "#FALSE ()" "1" "#FALSE ()")
                (51 "ICY" "DOME" "T" "STREA" "0" "T")
                (54 "VLBOT" "DOME" "T" "STREA" "0" "T")))
;; the balloon by READSTRING entry:
;; (HERE AVEHICLE BLOC BINF BTIE RECEP-OOPEN BINT-CFLAG BINT-CTICK BRNIN-CTICK)
(define (ball k) (map (lambda (key) (cp k key))
                      '(here winner_avehicle bloc binf btie recep_oopen bint_cflag bint_ctick brnin_ctick)))
(check-equal?
 (for/list ([k '(55 56 57 59 60 61 64 66 67 68 71 72 73 76 79 80)]) (cons k (ball k)))
 '((55 "VLBOT" "#FALSE ()" "VLBOT" "#FALSE ()" "#FALSE ()" "T" "T" "0" "0")       ; open receptacle
   (56 "VLBOT" "#FALSE ()" "VLBOT" "#FALSE ()" "#FALSE ()" "T" "T" "0" "0")       ; guide put in
   (57 "VLBOT" "BALLO" "VLBOT" "#FALSE ()" "#FALSE ()" "T" "T" "0" "0")           ; board basket
   (59 "VLBOT" "BALLO" "VLBOT" "GUIDE" "#FALSE ()" "T" "T" "2" "99")              ; burn guide
   (60 "VLBOT" "BALLO" "VLBOT" "GUIDE" "#FALSE ()" "T" "T" "1" "98")
   (61 "VAIR1" "BALLO" "VAIR1" "GUIDE" "#FALSE ()" "T" "T" "3" "97")              ; rises
   (64 "VAIR2" "BALLO" "VAIR2" "GUIDE" "#FALSE ()" "T" "T" "3" "94")              ; ascends
   (66 "LEDG2" "BALLO" "LEDG2" "GUIDE" "#FALSE ()" "T" "T" "1" "92")              ; west: the ledge
   (67 "LEDG2" "#FALSE ()" "LEDG2" "GUIDE" "#FALSE ()" "T" "T" "2" "91")          ; disembark
   (68 "LEDG2" "#FALSE ()" "LEDG2" "GUIDE" "T" "T" "#FALSE ()" "2" "90")          ; tie wire to hook
   (71 "LEDG2" "#FALSE ()" "LEDG2" "GUIDE" "#FALSE ()" "T" "T" "2" "87")          ; untie wire
   (72 "LEDG2" "BALLO" "LEDG2" "GUIDE" "#FALSE ()" "T" "T" "1" "86")
   (73 "VAIR2" "BALLO" "VAIR2" "GUIDE" "#FALSE ()" "T" "T" "3" "85")              ; leaves the ledge
   (76 "VAIR1" "BALLO" "VAIR1" "GUIDE" "#FALSE ()" "#FALSE ()" "T" "3" "82")      ; close receptacle
   (79 "VLBOT" "BALLO" "VLBOT" "GUIDE" "#FALSE ()" "#FALSE ()" "T" "3" "79")      ; landed
   (80 "VLBOT" "#FALSE ()" "VLBOT" "GUIDE" "#FALSE ()" "#FALSE ()" "T" "2" "78"))) ; disembark
(define burns ">The tour guidebook burns inside the receptacle.\nThe cloth bag inflates as it fills with hot air.\n")
(check-true (string-contains? t1 burns))
(check-true (string-contains? t1 ">The balloon is fastened to the hook.\n"))
(check-true (string-contains? t1 ">The wire falls off of the hook.\n"))
(check-true (string-contains? t1 "The balloon has landed.\n"))
(check-true (string-contains? t1 "Your score would be 54 [total of 500 points], in 81 moves."))

;; --- the scenario ------------------------------------------------------------------------
;; Every READSTRING entry's output and puzzles checkpoint, the whole transcript
;; and the end state against the native reference (the runner); and, on our
;; side, the key turns: the guidebook burned (59), the wire tied (68) and
;; untied (71), the balloon landed (79).
(run-m4-scenario "balloon-ledge" commands
                 #:checkpoint puzzles-checkpoint
                 #:eof-classification-ignore-keys '(robber_hroom)
                 #:check-turn
                 (lambda (k transcript)
                   (when (>= k 59) (check-true (string-contains? transcript burns)))
                   (when (>= k 68)
                     (check-true (string-contains? transcript ">The balloon is fastened to the hook.\n")))
                   (when (>= k 71)
                     (check-true (string-contains? transcript ">The wire falls off of the hook.\n")))
                   (when (>= k 79)
                     (check-true (string-contains? transcript "The balloon has landed.\n")))))
