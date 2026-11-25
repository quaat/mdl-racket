# M4 Phase 3 reference: the lamp burns out; scenario `lamp-burnout`

Date: 2026-11-25. Read-only reference investigation for epic #163 Phase 3
(timers, objects, scoring); slice record [TIMERS-SCORING.md](TIMERS-SCORING.md).
Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before and
after every capture (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; game directory
`mdlzork_771212/patched_confusion`, unmodified, copied fresh under `$TMPDIR`
for every run. Fixed clock: shim `scripts/reference/fixed_time.c` (sha256
`d1fa8652…b925`), LD_PRELOAD, `MDL_FIXED_EPOCH=250776000`, `TZ=UTC`; seed
10438660480, never overridden; no seed search. The lamp's lifetime is in the source:
LNTIN starts at 350 ticks (77dung.mud:2388) and LAMP-TICKS re-arms it 50, 30,
20, 10, 4, 0 (77act1.mud:1855), 464 ticks with the lamp on. The game has a
multi-tick wait (WAIT, 77rooms.mud:1619: up to four clock ticks per `wait`).
One exploration run with 125 `wait`s showed the burn-out on the 118th; the
scenario uses 118. Capture time: 74 s for 265 native runs (T1 0.29 s).

## Captures

Checkpoint profile "timers" of `scripts/probe_death_scenario_reference.py`
(sha256 `51316c47…4a9f`): the death fields plus the lamp's LIGHT-INT count,
LNTIN, the CLOCKER's event list, the painting, the trophy case, the thief and
the ROBBER demon. The Dkk cases keep their log's sha256 and size instead of
the log (their last checkpoints are `end_checkpoints`; X1's log is kept).

| Command | Exit | Record |
|---|---|---|
| `python3 -I scripts/probe_death_scenario_reference.py lamp-burnout docs/evidence/M4/lamp-burnout-reference.json` | 0 (`CAPTURE OK`) | 265 runs (T1, T1b, X1, Pkk, Dkk); sha256 `7add14b0…949d`; T1 stdout sha256 `7fe61e8a…0bd7`; scenario file sha256 `059108a1…f2e7` |
| same, second capture to `$TMPDIR/lamp-burnout-2.json` (not committed) | 0 (`CAPTURE OK`) | every transcript case's stdout, stderr, exit status and input identical; X1 checkpoints, RANDOM draws, end checkpoints and endings identical |

## Findings (pinned Confusion)

Commands (131): `north` `east` `open window` `west` `west` `take lamp` `turn
on lamp`, 118 `wait`, `turn on lamp` `look` `move rug` `open trap door`
`down` `score`.

- Entries 0–6: LNTIN queued but disabled ((LNTIN #FALSE () 350)), the lamp
  off (OLIGHT? -1). Command 7 `turn on lamp`: "The lamp is now on."; LNTIN
  enabled, 349 after the turn's tick; OLIGHT? 1.
- Each `wait` takes four ticks (345 at entry 8). The countdown, by command
  (all `wait`s), with LIGHT-INT's count <1 <ORAND lamp>> and LNTIN's new
  CTICK at the next entry: 95 "The lamp appears to be getting dimmer." (1,
  49); 108 the same (2, 29); 116 the same (3, 19); 121 the same (4, 9); 124
  "The lamp is dying." (5, 3); 125 "I hope you have more light than from a
  lamp." (6, 0): OLIGHT? 0, LNTIN left enabled at tick 0 (never fires
  again).
- Command 126 `turn on lamp`: "You can't turn that on." Commands 127–129:
  the lit living room, the rug, the trap door. Command 130 `down`: "It is
  pitch black.  You are likely to be eaten by a grue." (HERE CELLA; RVAL 25
  scored). Command 131 `score`: 35, 131 moves.
- LNTIN is the only clock event ever queued. Two RANDOM draws (START seeding,
  and one during command 127, `look`). The thief never meets the hero and takes
  nothing (thief OROOM false, HFLAG false, bag empty throughout).
- Endings: every prefix ends by end of input; on every shorter prefix's
  end-of-input turn except prefix 0 the thief's HROOM moves and nothing else
  changes; every tail is "Beg pardon?" and a prompt. No run writes
  MDL/ZORK.LOG; every run rewrites MDL/MADADV.SAVE.

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source was copied.
