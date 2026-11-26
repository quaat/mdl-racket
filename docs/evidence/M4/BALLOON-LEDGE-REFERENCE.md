# M4 Phase 3c reference: the balloon; scenario `balloon-ledge` (native only, INV-12)

> **Since 2026-11-26 (M4 S16, #196) this reference gates the scenario**
> `make test-m4-balloon-ledge` (`tests/historical_balloon_ledge_test.rkt`);
> the XFAIL `make xfail-m4-balloon-frontier` is retired. The reference itself
> is unchanged (not recaptured). See [S16-ATTACHED-DECL.md](S16-ATTACHED-DECL.md).

Date: 2026-11-25. Read-only reference investigation for epic #163 Phase 3c
(the puzzles beyond the house); slice record [PUZZLES.md](PUZZLES.md).
This runtime stops at command 57 of this route (INV-12 in
[GAMEPLAY-FAILURE-INVENTORY.md](GAMEPLAY-FAILURE-INVENTORY.md)); the
reference is committed for the scenario's promotion and checked by
`make xfail-m4-balloon-frontier`. Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before and
after every capture (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; game directory
`mdlzork_771212/patched_confusion`, unmodified, copied fresh under `$TMPDIR`
for every run. Fixed clock: shim `scripts/reference/fixed_time.c` (sha256
`d1fa8652…b925`), LD_PRELOAD, `MDL_FIXED_EPOCH=250776000`, `TZ=UTC`; seed
10438660480, never overridden; no seed search.

## Route choice (no seed search)

The balloon is in the Volcano Bottom, behind the Glacier Room's glacier,
which only the torch melts (GLACIER, 77act1.mud:116). The torch is in the
Torch Room below the Dome Room, reached by the attic's rope tied to the
railing (ROPE-FUNCTION, 77act1.mud:898). The balloon needs something
burning in its receptacle: the Dam Lobby's guidebook (BURNBIT), lit with
the matchbook from the same room. Two native exploration runs:

1. The rope taken before the troll (`take lamp`, `turn on lamp`, the attic,
   back down, the trap door): the troll fight goes differently ("The force
   of your blow knocks the troll back, stunned." ...) and the troll kills
   the hero at command 21; rejected (a death, not this branch).
2. troll-combat's sixteen commands unchanged, then the studio and the
   chimney (CHIMNEY-FUNCTION: the lamp and one more object) to the kitchen
   and the attic, back down through the trap door; the Dam Lobby, the Dome
   Room, the Torch Room, the glacier, the volcano; the balloon flown to the
   Narrow Ledge and back; works. The scenario is this run with three
   trailing `look`s removed.

## Captures

Checkpoint profile "puzzles" (PUZZLES_DIAG_FORMS; see
[COAL-MACHINE-REFERENCE.md](COAL-MACHINE-REFERENCE.md)).

| Command | Exit | Record |
|---|---|---|
| `python3 -I scripts/probe_death_scenario_reference.py balloon-ledge $TMPDIR/cap1/balloon-ledge-reference.json` (copied to `docs/evidence/M4/`) | 0 (`CAPTURE OK`) | 165 runs; sha256 `ff0c3e1a…7640`; T1 stdout sha256 `c4b57400…e133`; scenario file sha256 `2da12250…` |
| same, second capture to `$TMPDIR/cap2` (not committed) | 0 (`CAPTURE OK`) | all 83 transcript cases' stdout byte-identical; the 82 diagnostic cases' game parts and logs (or their sha256), X1 checkpoints, RANDOM draws and end checkpoints identical |

## Findings (pinned Confusion)

Commands (81). Key READSTRING entries:

- 19 `up` the chimney ("Kitchen"); 21 `take rope`; 24-25 the trap door
  opened again and crashing shut; 33-34 the guidebook and the matchbook.
- 41 `tie rope to railing`: "The rope drops over the side and comes within
  ten feet of the floor." (DOME-FLAG T); 43 `take torch` (RAW-SCORE 54);
  51 `throw torch at glacier`: "The torch hits the glacier and explodes into
  a great ball of flame, ..." (GLACIER-FLAG T; the burned-out torch in the
  Stream, OLIGHT? 0).
- 54 the Volcano Bottom: the balloon ("a very large and extremely heavy
  wicker basket with a cloth bag"); 55 `open receptacle` "Opened."; 56
  "Done." (the guidebook's OCAN RECEP); 57 `board basket`: "You are in the
  basket." (AVEHICLE BALLO; **this runtime stops here**, INV-12).
- 58 `light match`: "One of the matches starts to burn."; 59 `burn guide
  with match`: "The tour guidebook burns inside the receptacle." "The cloth
  bag inflates as it fills with hot air." (BINF GUIDE, BINT CTICK 2 at the
  entry, BRNIN 99 counting from 100), "The match has gone out.".
- 61 (third `look`): "The balloon rises slowly from the ground." (VAIR1);
  64: "The balloon ascends." (VAIR2); 66 `west`: the Narrow Ledge, in the
  balloon; 67 `disembark`; 68 `tie wire to hook`: "The balloon is fastened
  to the hook." (WIRE-FUNCTION, BTIE T, BINT disabled); 69-70 the Library
  and back; 71 `untie wire`: "The wire falls off of the hook." (BINT
  re-enabled); 72 `board basket`; 73: "The balloon leaves the ledge."
  (VAIR2); 76 `close receptacle`: "Closed." and "The balloon descends."
  (VAIR1); 79: "The balloon has landed." (VLBOT); 80 `disembark`; 81
  `score`: 54 in 81 moves.
- RANDOM: 46 draws. The thief takes the ruby; never in the hero's room at a
  READSTRING entry. Shorter prefixes differ from the next entry only in
  HROOM, except 52 (he appears beside the hero on the end-of-input turn)
  and 60 (he takes the rope at the end-of-input turn: DOME-FLAG cleared).
- Endings: every prefix ends by end of input. No run writes MDL/ZORK.LOG;
  every run rewrites MDL/MADADV.SAVE.

## The divergence (INV-12)

A native diagnostic run (not a committed reference; BALLOON wrapped after
FLOAD to print its arguments and `<TYPE <2 ,PRSVEC>>`) shows, on the `board
basket` turn, `[BALLOON args=() PRSA=#VERB [BOARD!-WORDS BOARD]
PRSO-TYPE=OBJECT]` (the verb's object action) and then `[BALLOON
args=(READ-OUT) ... PRSO-TYPE=FALSE]` after the demons; on `light match`,
READ-IN with an OBJECT and READ-OUT with a FALSE. BALLOON's attached
declaration gives PRSO `<OR OBJECT DIRECTION>` (77act2.mud:424-425);
CLOCK-DEMON set PRSVEC 2 to `<>` (77rooms.mud:1633). This runtime matches
entries 0-56 and then raises `mdl-decl: DECL 424:9: PRSO does not satisfy
declaration` (earliest failing k = 57, kind run-guard).

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source was copied.
