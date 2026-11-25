# M4 Phase 3c reference: the coal-mine machine and the basket; scenario `coal-machine`

Date: 2026-11-25. Read-only reference investigation for epic #163 Phase 3c
(the puzzles beyond the house); slice record [PUZZLES.md](PUZZLES.md).
Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before and
after every capture (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; game directory
`mdlzork_771212/patched_confusion`, unmodified, copied fresh under `$TMPDIR`
for every run. Fixed clock: shim `scripts/reference/fixed_time.c` (sha256
`d1fa8652…b925`), LD_PRELOAD, `MDL_FIXED_EPOCH=250776000`, `TZ=UTC`; seed
10438660480, never overridden; no seed search.

## Route choice (no seed search)

The machine needs the coal (the Dead End at the bottom of the mine), the
screwdriver (the Maintenance Room at the dam) and light in the Lower Shaft,
which can only be entered empty-handed from the Timber Room (NO-OBJS,
EMPTY-HANDED, 77act2.mud:177). So the coal and a second light go down in
the basket (DUMBWAITER, 77act2.mud:74), and the lamp is dropped in the
Timber Room. The second light is the Altar's burning candles. The mine
side (the Slide Room) is reached without the round room's RANDOM exits by
draining the reservoir (dam-sluice's yellow button and bolt) and crossing
it to the Atlantis Room and Mirror Room 1; the Altar is reached through the
mirror (Mirror Room 2, the crawlway, the Grail Room, the Temple).
Commands 1-24 are dam-sluice's. Three native exploration runs:

1. The route with `down` `south` `sw` to leave the Temple (the Temple has
   only west and east exits): "There is no way to go in that direction.",
   the hero wanders back through the round room; rejected.
2. The corrected return (`west` `west` `east` `sw` `rub mirror`), through
   the mine to the machine, `take diamond`, `inventory`, `score`: works
   (score 60).
3. The same, with `nw`, `put diamond in basket`, `raise basket` before
   `inventory` and `score` (the basket raised too): the scenario.

## Captures

Checkpoint profile "puzzles" of `scripts/probe_death_scenario_reference.py`
(PUZZLES_DIAG_FORMS; the reference's `diag_forms` equals the probe's
profile): the "boat" fields ([BOAT-RIVER-REFERENCE.md](BOAT-RIVER-REFERENCE.md))
plus the balloon, the rope and torch, the basket (CAGE-TOP, TBASK, FBASK),
the coal, the machine, the diamond, the screwdriver, LIGHT-SHAFT,
EMPTY-HANDED, the candles and CNDIN, and the bracelet (field list:
[PUZZLES.md](PUZZLES.md)). The Dkk cases keep their log's sha256 and size
instead of the log.

| Command | Exit | Record |
|---|---|---|
| `python3 -I scripts/probe_death_scenario_reference.py coal-machine $TMPDIR/cap1/coal-machine-reference.json` (copied to `docs/evidence/M4/`) | 0 (`CAPTURE OK`) | 191 runs (T1, T1b, X1, Pkk, Dkk); sha256 `7089b521…bc80`; T1 stdout sha256 `6432361a…6068`; scenario file sha256 `961765e8…` |
| same, second capture to `$TMPDIR/cap2` (not committed) | 0 (`CAPTURE OK`) | all 96 transcript cases' stdout byte-identical; the 95 diagnostic cases' game parts and logs (or their sha256), X1 checkpoints, RANDOM draws and end checkpoints identical |

## Findings (pinned Confusion)

Commands (94). Key READSTRING entries (entry k follows command k):

- 25 `take screwdriver`; 26 `push yellow button` (GATE-FLAG T); 29 `turn
  bolt with wrench`: "The sluice gates open and water pours through the
  dam." (LOW-TIDE T); 32 Reservoir North across the drained bed.
- 36 `rub mirror` in Mirror Room 1: "There is a rumble from deep within the
  earth and the room shakes." (Mirror Room 2); 41 `take candles` at the
  Altar: CANDLES queues CNDIN (CTICK 49 at the entry); 46 `rub mirror` back.
- 50 the Shaft Room ("At the end of the chain is a basket."); 51-58 the
  Wooden Tunnel, four "non-descript" mine rooms, Ladder Top, Ladder Bottom,
  the Dead End; 59 `take coal`; 60-65 back up to the Shaft Room.
- 66-68 "Done." three times (TBASK OCONTENTS (CANDL SCREW COAL)); 69 `lower
  basket`: "The basket is lowered to the bottom of the shaft." (CAGE-TOP
  false; TBASK in BSHAF, FBASK in TSHAF).
- 70-77 through the mine to the Timber Room; 78 `drop all` (sword, lamp,
  wrench; EMPTY-HANDED T); 79 `sw`: the Lower Shaft, "The basket contains: A
  pair of candles A screwdriver A small pile of coal"; LIGHT-SHAFT 10 -> 0,
  RAW-SCORE 40 -> 50.
- 80-82 the three taken; 83 `east`: the Machine Room's description, "The lid
  on the machine is closed."; 84 "The lid opens."; 85 "Done." (MACHI
  OCONTENTS (COAL)); 86 "The lid closes."; 87 `turn switch with
  screwdriver`: "The machine comes to life (figuratively) with a dazzling
  display of colored lights and bizarre noises. ..." (MACHI OCONTENTS
  (DIAMO), the diamond's OCAN MACHI); 88 "The lid opens."; 89 `take
  diamond` (RAW-SCORE 60).
- 90 `nw` (CNDIN's first 50-tick interval ends: "The candles grow
  shorter.", CTICK 20); 91 the diamond in the basket; 92 `raise basket`:
  "The basket is raised to the top of the shaft." (CAGE-TOP T, TBASK in
  TSHAF); 93 `inventory`: the candles, the screwdriver; 94 `score`: 60 in 94
  moves.
- Native quirks: an object in the basket keeps the OROOM it had when put in
  (the coal and the candles TSHAF after the basket went down; the diamond
  BSHAF after it went up); the coal spliced out of the machine keeps OROOM
  and OCAN MACHI.
- RANDOM: 36 draws. The thief takes the trident (HOBJS (TRIDE)) and the
  trunk ((TRUNK TRIDE)) from rooms the hero has left; never in the hero's
  room at a READSTRING entry. Shorter prefixes differ from the next entry
  only in HROOM, except 36 and 38 (the sword's glow on the end-of-input
  turn), 53 (his bag) and 61 (his bag and the trunk's OROOM).
- Endings: every prefix ends by end of input. No run writes MDL/ZORK.LOG;
  every run rewrites MDL/MADADV.SAVE.

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source was copied.
