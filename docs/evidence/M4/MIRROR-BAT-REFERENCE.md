# M4 S9 reference capture: the mirror and the bat (scenario `mirror-bat`)

Date: 2026-11-24. Read-only reference capture for issues #168 (IMAGE) and
#169 (SLEEP). Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before and
after (not rebuilt); upstream mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`;
game directory `mdlzork_771212/patched_confusion`, copied fresh under
`$TMPDIR` for every run (the only file written is SAVE-IT's
`MDL/MADADV.SAVE` in the copy). Fixed clock: shim
`scripts/reference/fixed_time.c` (sha256 `d1fa8652…b925`), LD_PRELOAD,
`MDL_FIXED_EPOCH=250776000`, `TZ=UTC` (wall clock only: SLEEP waits
natively); RANDOM seeded by START with 10438660480 as in every M4 scenario.

Command: `python3 -I scripts/probe_p0prims_scenario_reference.py mirror-bat docs/evidence/M4/mirror-bat-reference.json`
→ exit 0 (77 runs: T1, T1b, X1, P00–P36, D00–D36; pipe mode). Record:
`mirror-bat-reference.json` (sha256 `29336459…411c`), T1 stdout sha256
`a8ded207…2330`. Script sha256 `c8702a9b…8325`; scenario file sha256
`68ddb9db…aca5`. Local paths (diagnostic DIAG.LOG names) are written as
`$TMPDIR` / `<repo>`; the transcript cases contain none (asserted).

Capture checks (all true): T1 = T1b byte for byte; X1's game text = T1's;
every Pkk's game text up to its last prompt = T1's (prefix 33 then prints the
sword's "begun to glow very brightly" on the end-of-input empty command — the
demons run on it; recorded in `prefix_runs_with_demon_text_after_eof`); every
Dkk game text = Pkk's; 39 checkpoints in X1 and k + 2 in Dkk; every exit
status 0. **Second capture** (same command, output under `$TMPDIR`, not
committed): every transcript case's stdout byte-identical to the first, every
diagnostic case's game text and DIAG.LOG identical (only the printed temporary
DIAG.LOG path in the diagnostic echo differs), end checkpoints and RANDOM
draws identical.

## Scenario

`<FLOAD "77loadall.mud">`, `<SAVE-IT>`, then the 37 commands of case F10
(`tests/scenarios/failure-inventory-cases.json`):

| # | Commands | Purpose |
|---|---|---|
| 1–16 | `north` `east` `open window` `west` `west` `take sword` `inventory` `take lamp` `move rug` `open trap door` `turn on lamp` `down` `east` `kill troll with sword` ×3 | the troll-combat path (troll dead on the third blow) |
| 17–28 | `north` `east` `se` `south` `se` `east` `se` `south` `se` `south` `look` `se` | the round room: CAROUSEL-OUT draws RANDOM; under this clock the detours land in the Grail Room |
| 29–31 | `east` `sw` `rub mirror` | crawlway, Mirror Room 2; MIRROR-MIRROR swaps the mirror rooms ("There is a rumble from deep within the earth") |
| 32–35 | `west` `west` `north` `nw` | to the Squeaky Room |
| 36 | `west` | the Bat Room without garlic: BATS-ROOM → FLY-ME → `<FWEEP 4 1>` |
| 37 | `look` | the RANDOM drop room (MINE2) |

## Native highlights

* Response 36: `You are in a small room which has only one door, to the
  east.\nThere is an exquisite jade figurine here.\n` then **three 0x07
  bytes** (FWEEP's `<IMAGE 7>`), then `A deranged giant vampire bat (a reject
  from WUMPUS) swoops down\r\nfrom his belfry and lifts you away....\n` and
  `You are in a non-descript part of a coal mine.\n` (MINE2). Exactly 3 BEL
  bytes in T1.
* Wall time: every run that enters the Bat Room takes 3.22–3.28 s (T1 3.28,
  T1b 3.24, X1 3.25, P36 3.22, D36 3.24) against ≤ 0.3 s for the others: three
  real `<SLEEP 1>`s.
* RANDOM: 28 draws: START's seed, the troll fight as in `troll-combat`, the
  round-room landings, two during `north` (command 34), two during `west`
  into the Bat Room (command 36; FLY-ME's PICK-ONE of BAT-DROPS draws one)
  and one during the final `look`.
* End state: HERE MINE2, MOVES 37, RAW-SCORE 40; MIRROR-MUNG stays FALSE
  (rubbing does not break the mirror).
