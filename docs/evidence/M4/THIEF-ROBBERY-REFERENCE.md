# M4 Phase 3 reference: the thief takes the painting; scenario `thief-robbery`

Date: 2026-11-25. Read-only reference investigation for epic #163 Phase 3
(timers, objects, scoring); slice record [TIMERS-SCORING.md](TIMERS-SCORING.md).
Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before and
after every capture (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; game directory
`mdlzork_771212/patched_confusion`, unmodified, copied fresh under `$TMPDIR`
for every run. Fixed clock: shim `scripts/reference/fixed_time.c` (sha256
`d1fa8652…b925`), LD_PRELOAD, `MDL_FIXED_EPOCH=250776000`, `TZ=UTC`; seed
10438660480, never overridden; no seed search. This is the first treasure route tried
(see [TREASURE-DEPOSIT-REFERENCE.md](TREASURE-DEPOSIT-REFERENCE.md)); the
thief's appearance was observed, not sought, and is kept as a scenario of its
own.

## Captures

Checkpoint profile "timers" of `scripts/probe_death_scenario_reference.py`
(sha256 `51316c47…4a9f`): the death fields plus the lamp's LIGHT-INT count,
LNTIN, the CLOCKER's event list, the painting, the trophy case, the thief and
the ROBBER demon. The Dkk cases keep their log's sha256 and size instead of
the log (their last checkpoints are `end_checkpoints`; X1's log is kept).

| Command | Exit | Record |
|---|---|---|
| `python3 -I scripts/probe_death_scenario_reference.py thief-robbery docs/evidence/M4/thief-robbery-reference.json` | 0 (`CAPTURE OK`) | 45 runs (T1, T1b, X1, Pkk, Dkk); sha256 `f2d2f1ab…04b5`; T1 stdout sha256 `f7297ef1…5fc5`; scenario file sha256 `62efe29f…aa39` |
| same, second capture to `$TMPDIR/thief-robbery-2.json` (not committed) | 0 (`CAPTURE OK`) | every transcript case's stdout, stderr, exit status and input identical; X1 checkpoints, RANDOM draws, end checkpoints and endings identical |

## Findings (pinned Confusion)

Commands (21): `north` `east` `open window` `west` `west` `take lamp` `move
rug` `open trap door` `turn on lamp` `down` `south` `south` `take painting`
`south` `up` `west` `open case` `put painting in case` `look` `score`
`inventory`.

- The ROBBER demon (77act1.mud:1284) walks the thief's HROOM one room per
  turn: TREAS, MAINT, LOBBY, TOMB, LLD2, BWELL, MPEAR, RIDDL, DEAD6, DEAD5,
  TCAVE, CAVE4, then GALLE at entry 13, with the hero.
- Command 13 `take painting` (two RANDOM draws): "Taken." (SCORE-OBJ: OFVAL 4
  scored, RAW-SCORE 39), then "A seedy-looking individual with a large bag
  just wandered through the room.  On the way through, he quietly abstracted
  all valuables from the room and from your possession, mumbling something
  about \"Doing unto others before..\"" Entry 13: the hero holds only the
  lamp; the painting is in the ROBBER demon's HOBJS (his bag), HFLAG T; the
  thief object is in no room.
- Command 14 `south` to the Studio (HROOM STUDI): "A 'lean and hungry'
  gentleman just wandered through.  Finding nothing of value, he left
  disgruntled."
- Commands 15–21: up the chimney, `west`, `open case` ("Opened."), `put
  painting in case` ("I can't see a paint here."), `look` (no collection),
  `score` (39: the painting's OFVAL stays scored), `inventory` ("A lamp").
  The bag keeps the painting to the end (HROOM MINE4 at the end of input).
- The thief is never seen in a room with the hero (thief OROOM always
  false), never fights and is never fought; his treasure room is not reached.
- Eight RANDOM draws (START seeding; commands 13 (two), 14 (two), 15, 16, 19).
- Endings: every prefix ends by end of input. The thief's HROOM moves on
  every shorter prefix's end-of-input turn except prefix 0. **Prefix 12**
  (input ends in the Gallery before `take painting`): the end-of-input turn
  prints "Beg pardon?" and the same "seedy-looking individual" text; the
  thief takes the painting from the room (its OROOM false, HOBJS (PAINT)).
  No run writes MDL/ZORK.LOG; every run rewrites MDL/MADADV.SAVE.

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source was copied.
