# M4 S8 reference capture: the cyclops and ABS (scenario `cyclops-room`)

Date: 2026-11-24. Read-only reference capture for issue #167. Pinned mdli
sha256 `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789`
before and after (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; game directory
`mdlzork_771212/patched_confusion`, copied fresh under `$TMPDIR` for every
run (the only file written is SAVE-IT's `MDL/MADADV.SAVE` in the copy).
Fixed clock: shim `scripts/reference/fixed_time.c` (sha256 `d1fa8652…b925`),
LD_PRELOAD, `MDL_FIXED_EPOCH=250776000`, `TZ=UTC`; RANDOM seeded by START
with 10438660480 as in every M4 scenario.

Command: `python3 -I scripts/probe_cyclops_room_reference.py docs/evidence/M4/cyclops-room-reference.json`
→ exit 0 (83 runs: T1, T1b, X1, P00–P39, D00–D39; pipe mode). Record:
`cyclops-room-reference.json` (sha256 `16202bed…b45c`), T1 stdout sha256
`daae7937…8571`. Script sha256 `21d9fc00…e617`; scenario file sha256
`a490a0e4…f4dc`. Local paths in the record (diagnostic DIAG.LOG names) are
written as `$TMPDIR` / `<repo>`; the transcript cases contain none (asserted
by the script).

Capture checks (all true): T1 = T1b byte for byte (determinism, run twice);
X1's game text = T1's; every Pkk = the T1 prefix; every Dkk game text = Pkk's;
42 checkpoints in X1 and k + 2 in Dkk; every exit status 0.

## Scenario

`<FLOAD "77loadall.mud">`, `<SAVE-IT>`, then 40 commands:

| # | Commands | Purpose |
|---|---|---|
| 1–9 | `north`, `east`, `open window`, `west`, `open sack`, `take lunch`, `take bottle`, `inventory`, `west` | the lunch (FOOD, "hot peppers") and the bottle of water from the kitchen |
| 10–19 | `take sword`, `take lamp`, `move rug`, `open trap door`, `turn on lamp`, `down`, `east`, `kill troll with sword` ×3 | the troll-combat path; the fight is the same as in `troll-combat` (same RANDOM draws, troll dead on the third blow) |
| 20–27 | `south`, `south`, `east`, `up`, `sw`, `east`, `south`, `ne` | the maze route of issue #167 into the Cyclops Room |
| 28–40 | `give lunch to cyclops`, `look`, `take cyclops`, `open bottle`, `give water to cyclops`, `take cyclops`, `look`, `wake cyclops`, `look`, `west`, `diagnose`, `inventory`, `score` | the cyclops: anger counter negative, asleep, awake and positive, flee |

## Choosing the command list

Exploratory native runs (`$TMPDIR`, not recorded):

* troll16 + route + `look`/`wait` ×6: waiting never agitates the cyclops
  (only actions on him call AOS-SOS);
* troll16 + route + `take cyclops`, `give sword to cyclops`, `throw lamp at
  cyclops`, … : the counter rises 1..6 through CYCLOMAD; the next action
  meets `<G? <ABS .COUNT> 5>` (`77act1.mud:951`) and the cyclops eats the
  player (JIGS-UP), followed by a second death in the same turn (the
  cyclops's melee). Not used: the positive counter makes ABS the identity;
* with the lunch: `give lunch to cyclops` makes the counter negative, so
  CYCLOPS-ROOM's and AOS-SOS's `<ABS …>` really change the sign; `give
  water to cyclops` needs `open bottle` first ("I can't reach that.");
  going `up` past the sleeping cyclops leads to the thief's treasure room
  (a separate fight); `wake cyclops` directly after the sleeping `look`
  kills the player in that RANDOM state, while with the sleeping `take
  cyclops` (one more draw) the hero survives two blows and can flee west.

The chosen list exercises all four ABS sites with the values −1, −2 and
0 (FIRST? on entry, `77act1.mud:951`), −1 (`:1031`), −2 (`:1050`) and
−2 → 2 (`:949`), and ends at the RDCOM prompt (no YES/NO prompt meets end
of input).

## Native responses in the Cyclops Room (T1)

| # | Command | Response (abridged) |
|---|---|---|
| 27 | `ne` | Cyclops Room description; "A cyclops, who looks prepared to eat horses … blocks the staircase."; "Your sword has begun to glow very brightly." |
| 28 | `give lunch to cyclops` | "The cyclops says 'Mmm Mmm.  I love hot peppers! …'" |
| 29 | `look` | "… appears to be gasping. …"; "The cyclops seems somewhat agitated." (CYCLOMAD 1 = `<ABS -1>`) |
| 30 | `take cyclops` | "The cyclops appears to be getting more agitated." (AOS-SOS, `<ABS -2>`); "… rather heavy …" |
| 31 | `open bottle` | "Opened." |
| 32 | `give water to cyclops` | "The cyclops looks tired and quickly falls fast asleep …" |
| 33 | `take cyclops` | "You can't be serious." |
| 34 | `look` | "The cyclops, perhaps affected by a drug in your drink, is sleeping blissfully …" |
| 35 | `wake cyclops` | "The cyclops yawns and stares at the thing that woke him up."; "The Cyclops knocks you silly, and you reel back." |
| 36 | `look` | "The cyclops is standing in the corner, eyeing you closely. …" (RVARS 2 > 0); "The cyclops appears to be getting more agitated."; "The Cyclops grabs you, and almost strangles you …" |
| 37 | `west` | maze; "Your sword is glowing with a faint blue glow." |
| 38–40 | `diagnose`, `inventory`, `score` | "You are in perfect health." …; lamp, sword, glass bottle; "Your score would be 35 [total of 500 points], in 40 moves." |

## Reference state (X1 checkpoints at READSTRING entry k)

* Cyclops Room RVARS: 0 to cp 27; −1 at cp 28–29; −2 at cp 30–34; 2 from
  cp 35 (`wake cyclops`: `<ABS -2>`) to the end.
* SLEEPBIT and CYCLOPS-FLAG T at cp 32–34; FIGHTBIT T and `<3 ,OPPV>` the
  cyclops at cp 35–36; both cleared after `west` (FIGHTING's not-here
  branch, `78melee.mud:313-317`).
* FOOD leaves the winner at cp 28 (REMOVE-OBJECT: OROOM and OCAN FALSE);
  WATER leaves the bottle at cp 32 (bottle OCONTENTS `()`).
* Constant: cyclops OROOM CYCLO, OCAPAC 10000, STAGGERED FALSE;
  MAGIC-FLAG FALSE; `<3 ,VILLAIN-PROBS>` 0; winner ASTRENGTH 0; CURIN
  disabled. TROLL-FLAG T from cp 19. RAW-SCORE/ASCORE 35 from cp 15.
  MOVES 40 at cp 40 and 41.
* End checkpoints (Dkk last, X1 last) equal the READSTRING-entry
  checkpoints for every k.

RANDOM draws (args, result, before checkpoint): the seeding call
`(10438660480)` 16566282405 at 0; the troll fight as in `troll-combat`
(cp 16: 1, cp 17: 4, cp 18: 3, cp 19: 2); cp 29 `look` 1; cp 33 `take
cyclops` (asleep) 1; cp 34 `look` 1; cp 35 `wake cyclops` 3; cp 36 `look`
4; cp 37 `west` 1 — 22 draws in all, pinned in
`tests/historical_cyclops_room_test.rkt`.
