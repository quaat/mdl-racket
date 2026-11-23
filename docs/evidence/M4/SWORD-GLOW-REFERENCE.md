# M4 S5b reference capture: take the sword (scenario `sword-glow`)

Date: 2026-11-23. Read-only reference capture for the game path of frontier
F4. Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before and
after (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; game directory
`mdlzork_771212/patched_confusion`, copied fresh under `$TMPDIR` for every
run (SAVEFILE/ZORK.SAVE removed; the only file written is SAVE-IT's
`MDL/MADADV.SAVE` in the copy). Fixed clock: shim
`scripts/reference/fixed_time.c` (sha256 `d1fa8652…b925`), LD_PRELOAD,
`MDL_FIXED_EPOCH=250776000`, `TZ=UTC`.

Command: `python3 -I scripts/probe_sword_glow_reference.py docs/evidence/M4/sword-glow-reference.json`
→ exit 0 (29 runs, pipe mode). Record: `sword-glow-reference.json`
(sha256 `e13cd560…e9eb`), T1 stdout sha256 `5e25545d…820a`.

Scenario (`tests/scenarios/sword-glow.json`): `<FLOAD "77loadall.mud">`,
`<SAVE-IT>`, then `north`, `east`, `open window`, `west`, `west`,
`take sword`, `inventory`, `take lamp`, `move rug`, `open trap door`,
`turn on lamp`, `down`, `east`, then end of input.

## Runs and checks

* T1 / T1b: the transcript, byte-identical twice (`t1_equals_t1b_bytes`).
* P00–P12: the first k commands, then EOF; each equals T1 cut after the
  (k+1)-th prompt plus the end-of-input reply (`prefix_runs_consistent_with_t1`).
* X1: diagnostic (not a transcript). Forms typed after FLOAD and before
  SAVE-IT wrap RANDOM, READSTRING and TYPE? (the original SUBR is applied to
  the same arguments and its value returned) and log to `DIAG.LOG` outside
  the game copy; a read-only checkpoint at every READSTRING entry; every
  TYPE? whose TYPE arguments include NOFFSET is logged with its first
  argument's TYPE and the result. The game text equals T1's byte for byte
  (`diag_game_part_equals_t1_game_part_bytes`); 15 checkpoints.
* D00–D12: X1 cut after k commands. Their last checkpoint is taken at the
  READSTRING that meets end of input, after the empty command that end of
  input produces (`Beg pardon?`), which still runs the demons: the state a
  per-prefix candidate run ends in (`end_checkpoints`; k = 13 is X1's last).
  Each game text equals Pkk's.

## Transcript (game part, CRs as printed)

```
>You are facing the north side of a white house. ...           (north)
>You are behind the white house. ... slightly ajar.             (east)
>With great effort, you open the window ...                     (open window)
>You are in the kitchen ...                                     (west)
>You are in the living room. ... an elvish sword of great antiquity.  (west)
>Taken.                                                         (take sword)
>You are carrying:
A sword                                                         (inventory)
>Taken.                                                         (take lamp)
>With a great effort, the rug is moved ...                      (move rug)
>The door reluctantly opens ...                                 (open trap door)
>The lamp is now on.                                            (turn on lamp)
>You are in a dark and damp cellar ...
The trap door crashes shut, and you hear someone barring it.
Your sword is glowing with a faint blue glow.                   (down)
>You are in a small room with passages off in all directions. ...
A nasty-looking troll, brandishing a bloody axe, blocks all passages
out of the room.
Your sword has begun to glow very brightly.                     (east)
>Beg pardon?
>
```

stderr: `Error: Unexpected EOF`; exit status 0. Score 35 in 13 moves.

## Diagnostic findings

* TYPE? … NOFFSET: exactly one call, in `take sword` (before checkpoint 6):
  first argument TYPE **FUNCTION** (SWORD-GLOW), result FALSE.
* SWORD-DEMON HACTION / sword OTVAL by checkpoint: 0: `SWORD-GLOW` / 0 (the
  boot value); 1–5: FALSE / 0 (the demon's first run, in the first turn,
  disarms it: the sword is not carried); 6–11: `SWORD-GLOW` / 0 (re-armed
  with the ATOM by SWORD; living room, no villain near); 12: `SWORD-GLOW` / 1
  (cellar, the troll next door); 13–14: `SWORD-GLOW` / 2 (troll room).
  HROOM is MAZE1 throughout.
* End checkpoints equal the READSTRING-entry checkpoints except for prefix 0,
  where the end-of-input empty command is the first turn and disarms the
  demon (HACTION FALSE), exactly as `north` does.
* RANDOM: START's seeding `<RANDOM 10438660480>` → 16566282405, then one
  `<RANDOM>` → -21802663835 entering the troll room (checkpoint 13).
* Checkpoint 13 = 14: HERE MTROL, AOBJS (LAMP SWORD), lamp on, trap door
  closed (barred), RAW-SCORE/ASCORE 35, MOVES 13.

## Beyond the scenario (ad hoc, not committed as a reference case)

`kill troll with sword` after the scenario: native prints `Your sword pinks
the troll on the wrist, but it's not serious.` and `The troll swings his
axe, but it misses.`. See `S5B-FUNCTION-TYPE.md` for this runtime.

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source was copied.
