# M4 S9 reference capture: the Strange Passage and C-INT (scenario `strange-passage`)

Date: 2026-11-24. Read-only reference capture for issue #170 (TIME). Pinned
mdli sha256 `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789`
before and after (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; game directory
`mdlzork_771212/patched_confusion`, copied fresh under `$TMPDIR` for every run
(only SAVE-IT's `MDL/MADADV.SAVE` is written in the copy). Fixed clock: shim
`scripts/reference/fixed_time.c` (sha256 `d1fa8652…b925`), LD_PRELOAD,
`MDL_FIXED_EPOCH=250776000`, `TZ=UTC`; RANDOM seeded with 10438660480.

Command: `python3 -I scripts/probe_p0prims_scenario_reference.py strange-passage docs/evidence/M4/strange-passage-reference.json`
→ exit 0 (65 runs: T1, T1b, X1, P00–P30, D00–D30; pipe mode). Record:
`strange-passage-reference.json` (sha256 `7c5ca890…dbf4`), T1 stdout sha256
`4a3dde98…6194`. Script sha256 `c8702a9b…8325`; scenario file sha256
`fec364c7…43e3`.

Capture checks (all true): T1 = T1b byte for byte; X1's game text = T1's;
every Pkk = the T1 prefix (no demon text after end of input); every Dkk game
text = Pkk's; 33 checkpoints in X1 and k + 2 in Dkk; every exit status 0.
**Second capture** (not committed): every transcript byte-identical; every
diagnostic game text and DIAG.LOG identical (only the printed temporary
DIAG.LOG path differs); end checkpoints and RANDOM draws identical.

## Scenario

`<FLOAD "77loadall.mud">`, `<SAVE-IT>`, then 31 commands: the first 26 of
case F8 (`tests/scenarios/failure-inventory-cases.json`) and five more:

| # | Commands | Purpose |
|---|---|---|
| 1–16 | troll-combat path (`north` … `kill troll with sword` ×3) | the troll dies on the third blow |
| 17–24 | `south` `south` `east` `up` `sw` `east` `south` `ne` | the maze into the Cyclops Room (FIGHTING's FIRST? call evaluates ABS, M4 S8) |
| 25 | `odysseus` | SINBAD (77act1.mud:1190): "The cyclops, hearing the name of his deadly nemesis, flees the room by knocking down the wall on the north of the room."; CYCLOPS-FLAG and MAGIC-FLAG T, the cyclops removed |
| 26 | `north` | BLROO, the Strange Passage: ROOM-INFO applies its room action, the ATOM TIME (77dung.mud:1385; 77rooms.mud:553-555) |
| 27 | `c-int` | the internal verb C-INT, verb function TIME (77dung.mud:2904); then RDCOM applies BLROO's TIME (:634); no TELL ran, so "Nothing happens." |
| 28 | `look` | BLROO again (room action TIME after the command) |
| 29 | `east` | the living room ("a cyclops-shaped hole in an old wooden door") |
| 30 | `c-int` | "Nothing happens." outside BLROO |
| 31 | `score` | 45 points in 31 moves |

## Native highlights

* TIME's value never appears in the transcript (the game only tests it for
  truth), so the run is byte-deterministic natively although TIME is CPU
  time there. Both `c-int` responses are exactly `Nothing happens.\n`.
* RANDOM: 13 draws (START, the troll fight, two in the Cyclops Room).
* End state: HERE LROOM, MOVES 31, RAW-SCORE 45, MAGIC-FLAG and CYCLOPS-FLAG
  T, the cyclops's OROOM FALSE.
