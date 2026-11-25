# M4 Phase 3 reference: the cure clock heals the wound; scenario `cure-recovery`

Date: 2026-11-25. Read-only reference investigation for epic #163 Phase 3
(timers, objects, scoring); slice record [TIMERS-SCORING.md](TIMERS-SCORING.md).
Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before and
after every capture (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; game directory
`mdlzork_771212/patched_confusion`, unmodified, copied fresh under `$TMPDIR`
for every run. Fixed clock: shim `scripts/reference/fixed_time.c` (sha256
`d1fa8652…b925`), LD_PRELOAD, `MDL_FIXED_EPOCH=250776000`, `TZ=UTC`; seed
10438660480, never overridden; no seed search. One exploration run (troll-death's path
for seven `wait`s, `west`, `diagnose`, nine `wait`/`diagnose` pairs, `score`)
showed the recovery in the sixth pair; the scenario keeps seven pairs.

## Captures

Checkpoint profile "timers" of `scripts/probe_death_scenario_reference.py`
(sha256 `51316c47…4a9f`): the death fields plus the lamp's LIGHT-INT count,
LNTIN, the CLOCKER's event list, the painting, the trophy case, the thief and
the ROBBER demon. The Dkk cases keep their log's sha256 and size instead of
the log (their last checkpoints are `end_checkpoints`; X1's log is kept).

| Command | Exit | Record |
|---|---|---|
| `python3 -I scripts/probe_death_scenario_reference.py cure-recovery docs/evidence/M4/cure-recovery-reference.json` | 0 (`CAPTURE OK`) | 73 runs (T1, T1b, X1, Pkk, Dkk); sha256 `fffaf765…072d`; T1 stdout sha256 `72e9a3c6…6230`; scenario file sha256 `f563830d…a99e` |
| same, second capture to `$TMPDIR/cure-recovery-2.json` (not committed) | 0 (`CAPTURE OK`) | every transcript case's stdout, stderr, exit status and input identical; X1 checkpoints, RANDOM draws, end checkpoints and endings identical |

## Findings (pinned Confusion)

Commands (35): troll-death's first eighteen (`north` `east` `open window`
`west` `west` `take lamp` `move rug` `open trap door` `turn on lamp` `down`
`east`, seven `wait`), `west`, `diagnose`, seven times `wait` `diagnose`,
`score`.

- Commands 12–18 are troll-death's, with the same RANDOM draws: the sixth
  `wait` staggers the hero ("You stagger back under a hail of axe
  strokes."), the seventh wounds him ("The flat of the troll's axe skins
  across your forearm."). Entry 18: ASTRENGTH -1, CURIN enabled and queued
  ((CURIN T 29) (LNTIN T 319)), the troll fighting.
- Command 19 `west`: the cellar; the troll's FIGHTBIT cleared at entry 19;
  one RANDOM draw in that turn. No later draw.
- `diagnose` reports "You have a light wound, which will be cured after N
  moves." with N = 28, 23, 18, 13, 8, 3: CURIN's CTICK falls by 1 per
  ordinary turn and by 4 per `wait` (WAIT, 77rooms.mud:1619: CLOCK-DEMON up
  to three more times, then the turn's own clock tick).
- Command 31 (the sixth `wait`): CURIN reaches 0 inside WAIT; CURE-CLOCK
  (78melee.mud:504) raises ASTRENGTH to 0 and disables CURIN; WAIT stops
  early (three lamp ticks, 292 -> 289). Entry 31: ASTRENGTH 0, (CURIN
  #FALSE () 0). `diagnose`: "You are in perfect health.\nYou can be killed
  by a serious wound." (twice). `score`: 35, 35 moves.
- The thief never meets the hero and takes nothing.
- Endings: every prefix ends by end of input; the thief's HROOM moves on
  every shorter prefix's end-of-input turn except prefix 0, nothing else
  changes. No run writes MDL/ZORK.LOG; every run rewrites MDL/MADADV.SAVE.

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source was copied.
