# M4 Phase 2 reference: death by grue, resurrection; scenario `grue-resurrection`

Date: 2026-11-25. Read-only reference investigation for epic #163 Phase 2
(death and recovery); slice record [DEATH-BRANCHES.md](DEATH-BRANCHES.md).
Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before and
after every capture (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; game directory
`mdlzork_771212/patched_confusion`, unmodified, copied fresh under `$TMPDIR`
for every run (never the upstream checkout as the writable cwd). Fixed
clock: shim `scripts/reference/fixed_time.c` (sha256 `d1fa8652…b925`),
LD_PRELOAD, `MDL_FIXED_EPOCH=250776000`, `TZ=UTC`; START seeds RANDOM from
DSKDATE (seed 10438660480), never overridden.

Origin: the discovery run F12 of
[GAMEPLAY-FAILURE-INVENTORY.md](GAMEPLAY-FAILURE-INVENTORY.md). Its label
"patched" is the game's own word: JIGS-UP asks "Do you want me to try to
patch you?" and `y` accepts. Nothing in the sources or the protocol was
patched. F12 carried nothing (only the lamp, left in the living room, was
scattered); this scenario adds `take sack`, `take bottle` and the sword, so
the scatter of carried possessions is exercised.

## Captures

| Command | Exit | Record |
|---|---|---|
| `python3 -I scripts/probe_death_scenario_reference.py grue-resurrection $TMPDIR/grue-resurrection-a.json` | 0 (`CAPTURE OK`) | 43 runs (T1, T1b, X1, P00–P19, D00–D19); committed as `grue-resurrection-reference.json` (sha256 `52898df1…fccf`); T1 stdout sha256 `1d7857b3…6ac1`; script sha256 `aa763608…b4d5`; scenario file sha256 `30f19fda…1ac2` |
| same, second capture to `$TMPDIR/grue-resurrection-b.json` (not committed) | 0 (`CAPTURE OK`) | every case's stdout and stderr, every diagnostic log, the checkpoints, endings and entry prompts identical to the first; the diagnostic stdouts differ only in the random name of the `$TMPDIR` log directory echoed by LISTEN (not game output) |

The capture is rejected unless: T1 and T1b are byte-identical; every
diagnostic run's game part equals its transcript run's; every run's ending
(stderr) equals the declared one; the diagnostic's YES/NO entries equal the
declared entry prompts; every prefix holds exactly the counted `>`
(`expected_prefix_gt_counts`); every prefix's head is consistent with T1.

## Findings (pinned Confusion)

Commands (20): `north` `east` `open window` `west` `take sack` `take bottle`
`west` `take sword` `east` `up` `north` `y` `look` `inventory` `east` `west`
`east` `west` `west` `score`.

- Command 11 (`north` in the dark attic, read at entry 10, carrying
  `(SWORD BOTTL SBAG)`): one RANDOM draw, WALK's `<PROB 75>`
  (77rooms.mud:1063), succeeds; the attic has
  no north exit, so JIGS-UP "Oh, no!  You walked into the slavering fangs of
  a lurking grue." (77rooms.mud:1081). SCORE-UPD -10 (10 -> 0), DEATHS 1.
- Entry 11 is YES/NO's READSTRING (diagnostic `YES/NO-ENTRY 11`): its prompt
  is `Do you want me to try to patch you?`, printed with no CRLF and followed
  by no `>`. `y` answers T.
- Entry 12: in FORE1, empty handed. The lamp (in the living room) was put
  first in AOBJS; ROB-ADV found no valuable; the possessions went one each
  to the first rooms of RANDOM-LIST: lamp -> LROOM (back where it was),
  sword -> KITCH, bottle -> CLEAR, sack -> FORE3. The answer is not a move
  (19 moves after 20 commands). EGYPT-FLAG was already T; the trap door's
  OTOUCH? stays false.
- The walk back shows "A sandwich bag is here." (FORE3), "There is an elvish
  sword here." (kitchen), "A battery-powered brass lantern is on the trophy
  case." (living room); `score`: 0 points, 19 moves, Beginner.
- RANDOM draws (diagnostic): START's seeding call, one during command 9,
  WALK's `<PROB 75>` during command 11, one during each of commands 16–19.
- Endings: every prefix ends by end of input (stderr `Error: Unexpected
  EOF`) except **prefix 11**, which ends by the game's QUIT (empty stderr):
  YES/NO's READSTRING meets end of input, returns 0, and the stale first
  character of INBUF (`n` of `north`) refuses, so FINISH <> -> RECORD -> QUIT.
  Natively that run appends
  `0/500 points, 11 moves, 1 death.  In Attic. Died.` to MDL/ZORK.LOG in its
  game copy; every run rewrites MDL/MADADV.SAVE (SAVE-IT).
- Non-standard end-of-input tails: prefix 11 only (the quit).

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source was copied.
