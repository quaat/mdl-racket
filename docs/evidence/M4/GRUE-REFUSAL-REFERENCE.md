# M4 Phase 2 reference: death by grue, refused; scenario `grue-refusal`

Date: 2026-11-25. Read-only reference investigation for epic #163 Phase 2
(death and recovery); slice record [DEATH-BRANCHES.md](DEATH-BRANCHES.md).
Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before and
after every capture (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; game directory
`mdlzork_771212/patched_confusion`, unmodified, copied fresh under `$TMPDIR`
for every run (never the upstream checkout as the writable cwd: these runs
write MDL/ZORK.LOG natively). Fixed clock: shim
`scripts/reference/fixed_time.c` (sha256 `d1fa8652…b925`), LD_PRELOAD,
`MDL_FIXED_EPOCH=250776000`, `TZ=UTC`; seed 10438660480, never overridden.

Origin: the discovery run F13 of
[GAMEPLAY-FAILURE-INVENTORY.md](GAMEPLAY-FAILURE-INVENTORY.md), promoted
unchanged: the T1 stdout sha256 `3d904d0c…7b39` is the F13 capture's.

## Captures

| Command | Exit | Record |
|---|---|---|
| `python3 -I scripts/probe_death_scenario_reference.py grue-refusal $TMPDIR/grue-refusal-a.json` | 0 (`CAPTURE OK`) | 19 runs (T1, T1b, X1, P00–P07, D00–D07); committed as `grue-refusal-reference.json` (sha256 `cce3089b…26d1`); T1 stdout sha256 `3d904d0c…7b39`; script sha256 `aa763608…b4d5`; scenario file sha256 `21625e42…05d1` |
| same, second capture to `$TMPDIR/grue-refusal-b.json` (not committed) | 0 (`CAPTURE OK`) | identical (as for grue-resurrection: only the LISTEN echo of the random `$TMPDIR` log directory differs in the diagnostic stdouts) |

## Findings (pinned Confusion)

Commands (8): `north` `east` `open window` `west` `up` `north` `n` `look`.

- Command 6 (`north` in the dark attic, read at entry 5): WALK's
  `<PROB 75>` succeeds (the only RANDOM draw after START's seeding call);
  JIGS-UP: SCORE-UPD -10, DEATHS 1.
- Entry 6 is YES/NO's (`YES/NO-ENTRY 6`; prompt `Do you want me to try to
  patch you?`, no `>`). `n` answers `#FALSE ()`: "What?  You don't trust me?
  ...", FINISH <> prints `Your score is 0 [total of 500 points], in 6
  moves.` and `This score gives you the rank of Beginner.` (no question:
  ASK? is false), RECORD, QUIT (QUIT-NARGS 0). `look` is never read.
- The diagnostic's last checkpoint is taken in the QUIT wrapper: equal to
  entry 6's (the refusal changes no compared field).
- Endings: prefixes 0–5 end by end of input; **prefixes 6, 7 and 8 end by
  QUIT** (empty stderr). Prefix 6: YES/NO meets end of input, returns 0, and
  the stale `n` of `north` refuses; prefixes 7 (`n`) and 8 (`n`, `look`
  unread) print the same text as T1.
- Native file effects: each quitting run appends
  ```
          (MTRZORK)       December 12 at 12:00 PM
  Played for 0 seconds.
  0/500 points, 6 moves, 1 death.  In Attic. Died.
  /KI
  ```
  to MDL/ZORK.LOG in its game copy (RECORD: `OPEN "READB"` fails for the
  absent file, `OPEN "PRINT"` creates it); every run rewrites
  MDL/MADADV.SAVE. Under ADR-0055 this runtime denies both OPENs
  (`READB MDL/ZORK.LOG` status 2, `PRINT MDL/ZORK.LOG` status 13) and writes
  nothing; RECORD prints nothing to the console either way, so the
  transcripts are identical (documented deviation, as F13 and M3 S11).

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source was copied.
