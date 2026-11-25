# M4 Phase 3c reference: the gas room; scenario `gas-room`

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

BOOM-ROOM (77act2.mud:3), the Gas Room's action, acts on the walk-in (and
on ON): if the hero carries burning candles or a burning torch, the room
explodes (JIGS-UP). The Gas Room lies below the Smelly Room, west of the
Wooden Tunnel north of the Shaft Room. coal-machine's first fifty commands
reach the Shaft Room carrying the lamp and the Altar's burning candles, so
both sides of the rule are one short detour away: enter with the lamp only
(candles dropped in the Smelly Room), then with the candles. One native
exploration run, which is the scenario.

## Captures

Checkpoint profile "puzzles" (PUZZLES_DIAG_FORMS; see
[COAL-MACHINE-REFERENCE.md](COAL-MACHINE-REFERENCE.md)). READSTRING entry 58
is YES/NO's (`entry_prompts` {"58": "Do you want me to try to patch
you?"}); the diagnostic logged YES/NO-ENTRY 58 only, result T.

| Command | Exit | Record |
|---|---|---|
| `python3 -I scripts/probe_death_scenario_reference.py gas-room $TMPDIR/cap1/gas-room-reference.json` (copied to `docs/evidence/M4/`) | 0 (`CAPTURE OK`) | 127 runs; sha256 `b7aad3f3…0ff8`; T1 stdout sha256 `a23a2923…45d3`; scenario file sha256 `ed3e9ca7…` |
| same, second capture to `$TMPDIR/cap2` (not committed) | 0 (`CAPTURE OK`) | all 64 transcript cases' stdout byte-identical; the 63 diagnostic cases' game parts and logs (or their sha256), X1 checkpoints, RANDOM draws and end checkpoints identical |

## Findings (pinned Confusion)

Commands (62): coal-machine's first 50; `north` `west` `drop candles`
`down` `take bracelet` `up` `take candles` `down` `y` `look` `inventory`
`score`.

- 53 `drop candles` in the Smelly Room ("Dropped."; the candles keep
  burning, CNDIN counting).
- 54 `down` with the lamp, sword, wrench and screwdriver: "You are in a
  small room which smells strongly of coal gas. There is a
  sapphire-encrusted bracelet here." Nothing else happens.
- 55 `take bracelet` (RAW-SCORE 40 -> 45); 56 `up`; 57 `take candles`.
- 58 `down` carrying the burning candles: "Gas Room", "Oh dear.  It appears
  that the smell coming from this room was coal\r\ngas.  I would have
  thought twice about carrying a pair of candles in here.", six BEL bytes
  (FWEEP 7), "   BOOOOOOOOOOOM      ", then JIGS-UP: DEATHS 1, RAW-SCORE
  45 -> 35, and the question "Do you want me to try to patch you?" (no
  CRLF).
- 59 `y`: "Now, let me see...", "Well, we weren't quite able to restore
  your state.  You can't have everything.", the forest (FORE1), the objects
  scattered (the candles to the kitchen, the lamp to the living room, the
  bracelet to ALISM). 60 `look`: the forest. 61 `inventory`: "You are empty
  handed." 62 `score`: 35 in 61 moves.
- Prefix 58 (input ends at the question): YES/NO's end-of-input read leaves
  INBUF's stale "down"; its first character is not one of "NnfF", so the
  hero is patched as well.
- RANDOM: 24 draws. The thief takes the trident and the trunk from rooms
  the hero has left; never in the hero's room at a READSTRING entry.
  Shorter prefixes differ from the next entry only in HROOM, except 36 and
  38 (the sword's glow), 53 (his bag) and 58 (the question).
- Endings: every prefix ends by end of input. No run writes MDL/ZORK.LOG;
  every run rewrites MDL/MADADV.SAVE.

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source was copied.
