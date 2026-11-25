# M4 Phase 3 reference: a treasure in the trophy case; scenario `treasure-deposit`

Date: 2026-11-25. Read-only reference investigation for epic #163 Phase 3
(timers, objects, scoring); slice record [TIMERS-SCORING.md](TIMERS-SCORING.md).
Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before and
after every capture (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; game directory
`mdlzork_771212/patched_confusion`, unmodified, copied fresh under `$TMPDIR`
for every run. Fixed clock: shim `scripts/reference/fixed_time.c` (sha256
`d1fa8652…b925`), LD_PRELOAD, `MDL_FIXED_EPOCH=250776000`, `TZ=UTC`; seed
10438660480, never overridden; no seed search. Route choice, stated exactly: the 1977
sources have no tree or egg; the nearest treasure is the painting (OFVAL 4,
OTVAL 7) in the Gallery, two rooms south of the cellar, and the Studio's
chimney leads back to the kitchen. Four deterministic routes were tried
natively (exploration runs, not committed): the direct route (the thief takes
the painting from the hero: kept as [thief-robbery](THIEF-ROBBERY-REFERENCE.md)),
a detour south and north (the thief takes it from the Gallery), and a `look`
in the cellar or at West of Chasm (both reach the case). The scenario uses the
`look` in the cellar. Different routes draw RANDOM at different turns; the
seed itself was never changed.

## Captures

Checkpoint profile "timers" of `scripts/probe_death_scenario_reference.py`
(sha256 `51316c47…4a9f`): the death fields plus the lamp's LIGHT-INT count,
LNTIN, the CLOCKER's event list, the painting, the trophy case, the thief and
the ROBBER demon. The Dkk cases keep their log's sha256 and size instead of
the log (their last checkpoints are `end_checkpoints`; X1's log is kept).

| Command | Exit | Record |
|---|---|---|
| `python3 -I scripts/probe_death_scenario_reference.py treasure-deposit docs/evidence/M4/treasure-deposit-reference.json` | 0 (`CAPTURE OK`) | 45 runs (T1, T1b, X1, Pkk, Dkk); sha256 `754ec591…6e37`; T1 stdout sha256 `1bd6d52b…8818`; scenario file sha256 `dacbcc40…53cc` |
| same, second capture to `$TMPDIR/treasure-deposit-2.json` (not committed) | 0 (`CAPTURE OK`) | every transcript case's stdout, stderr, exit status and input identical; X1 checkpoints, RANDOM draws, end checkpoints and endings identical |

## Findings (pinned Confusion)

Commands (21): `north` `east` `open window` `west` `west` `take lamp` `move
rug` `open trap door` `turn on lamp` `down` `look` `south` `south` `take
painting` `south` `up` `west` `open case` `put painting in case` `look`
`score`.

- Entry 10: the cellar (RAW-SCORE 35; the trap door crashes shut, OTOUCH? T).
- Entry 13: the Gallery; the painting there (OFVAL 4, OTVAL 7).
- Command 14 `take painting`: "Taken." SCORE-OBJ: RAW-SCORE and ASCORE 39,
  OFVAL 0. The ROBBER demon's HROOM is the Gallery at entries 13 and 14 but
  the thief stays unseen (thief OROOM false, HFLAG false, bag empty).
- Command 16 `up` from the Studio: CHIMNEY-FUNCTION lets the hero up with
  two objects (painting, lamp): the kitchen.
- Command 18 `open case`: "Opened." (OOPEN? T). Command 19 `put painting in
  case`: "Done."; the painting's OROOM LROOM, OCAN TCASE; the living room's
  action sets ASCORE to RAW-SCORE + 7 = 46 (RAW-SCORE stays 39).
- Command 20 `look`: "Your collection of treasures consists of:\n A
  painting". Command 21 `score`: "Your score would be 46 [total of 500
  points], in 21 moves." (Amateur Adventurer).
- Eleven RANDOM draws (the START seeding, then commands 11, 13 (two), 14
  (two), 15 (two), 16, 17, 20).
- Endings: every prefix ends by end of input. The end-of-input turn runs the
  ROBBER demon: the thief's HROOM moves at every shorter prefix except 0, 13,
  14 and 15 (a non-standard end checkpoint when compared); at prefix 15 (the
  Studio, where his HROOM already is) he appears instead: "Someone carrying a large bag is casually leaning
  against one of the walls here. ..." (thief OROOM STUDI, HFLAG T). No run
  writes MDL/ZORK.LOG; every run rewrites MDL/MADADV.SAVE.

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source was copied.
