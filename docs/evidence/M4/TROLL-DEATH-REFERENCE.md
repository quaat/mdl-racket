# M4 Phase 2 reference: killed by the troll; scenario `troll-death`

Date: 2026-11-25. Read-only reference investigation for epic #163 Phase 2
(death and recovery; combat); slice record
[DEATH-BRANCHES.md](DEATH-BRANCHES.md). Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before and
after every capture (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; game directory
`mdlzork_771212/patched_confusion`, unmodified, copied fresh under `$TMPDIR`
for every run. Fixed clock: shim `scripts/reference/fixed_time.c` (sha256
`d1fa8652…b925`), LD_PRELOAD, `MDL_FIXED_EPOCH=250776000`, `TZ=UTC`; seed
10438660480, never overridden. No seed search: the first command sequence
tried (the troll-combat path without the sword, then `wait`) reaches the
death; a first exploration with nine `wait`s showed the death on the eighth
(the ninth was consumed as the answer), so the scenario uses eight.

## Captures

| Command | Exit | Record |
|---|---|---|
| `python3 -I scripts/probe_death_scenario_reference.py troll-death $TMPDIR/troll-death-a.json` | 0 (`CAPTURE OK`) | 51 runs (T1, T1b, X1, P00–P23, D00–D23); committed as `troll-death-reference.json` (sha256 `f0afa954…189c`); T1 stdout sha256 `5311da67…0107`; script sha256 `aa763608…b4d5`; scenario file sha256 `015ecc77…80b7` |
| same, second capture to `$TMPDIR/troll-death-b.json` (not committed) | 0 (`CAPTURE OK`) | identical (only the LISTEN echo of the random `$TMPDIR` log directory differs in the diagnostic stdouts) |

## Findings (pinned Confusion)

Commands (24): `north` `east` `open window` `west` `west` `take lamp` `move
rug` `open trap door` `turn on lamp` `down` `east`, eight `wait`, `y`,
`look`, `inventory`, `diagnose`, `score`.

- Entry 11: in the troll room (MTROL) with the lit lamp; no weapon.
- One RANDOM draw during command 11 (`east` into the troll room) and one
  during each of the first five `wait`s; the troll does not attack.
- Command 17 (sixth `wait`, three draws): "You stagger back under a hail of
  axe strokes." Entry 17: ASTAGGERED set, the troll FIGHTBIT set.
- Command 18 (seventh `wait`, two draws): "The flat of the troll's axe skins
  across your forearm." Entry 18: ASTRENGTH -1, ASTAGGERED cleared, CURIN
  enabled (CTICK 29).
- Command 19 (eighth `wait`, two draws): "The troll's axe removes your
  head." then JIGS-UP "It appears that that last blow was too much for you.
  I'm afraid you are dead." SCORE-UPD -10 (35 -> 25), DEATHS 1.
- Entry 19 is YES/NO's (`YES/NO-ENTRY 19`; prompt `Do you want me to try to
  patch you?`). `y`: the carried lit lamp goes to LROOM (still lit, OLIGHT?
  1), the hero to FORE1 empty handed, the trap door's OTOUCH? reset to
  false; the wound and the cure clock stay (`diagnose`: "You have a light
  wound, which will be cured after 27 moves. ... You have been killed
  once."). `score`: 25, 23 moves, Amateur Adventurer.
- Endings: every prefix ends by end of input. **Prefix 19** (input ends at
  the question) resurrects too: YES/NO meets end of input, returns 0, and
  the stale `w` of `wait` in INBUF is not in "NnfF" (NO-IS-BAD? is T), so
  it is a yes; then RDCOM's next READSTRING dies. Its tail is the
  resurrection text and `>`, its end state the forest: non-standard (the
  runner re-runs it per prefix). No run writes MDL/ZORK.LOG; every run
  rewrites MDL/MADADV.SAVE.

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source was copied.
