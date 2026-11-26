# M4 combat.thief: the thief fights and is fought (thief-fight)

Date: 2026-11-26. Branch `feat/m4-thief-fight` from `main` `e98e46c`. Epic
#163, required gameplay branch `combat.thief` ("the thief (ROBBER) fights,
steals and is fought"). Gate label: **PASS (local branch, not merged;
scenario-scoped)** for the new gated scenario thief-fight. Not a PLAYABLE,
GAMEPLAY_RELIABILITY or M4 claim; not mainline acceptance.

## Provenance

| Item | Value |
|---|---|
| Upstream game | `mdlzork` bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3 (`sources.lock.json`), `mdlzork_771212/patched_confusion`, unmodified |
| Pinned reference | `.cache/build/confusion_patched/mdli`, sha256 `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789`, unchanged before and after every capture (checked by the probe and with `sha256sum`); `make reference-build` not run |
| Clock / RNG | fixed epoch 250776000 (1977-12-12 12:00 UTC), TZ UTC; START seeds RANDOM from DSKDATE (seed 10438660480); no RANDOM override, no seed search, no game-specific random override |
| Native protocol | `scripts/probe_death_scenario_reference.py thief-fight OUT.json` with the new checkpoint profile "thief" (below); a fresh copy of the game directory under `$TMPDIR` for every run, pipe mode; captured twice |
| Ours | Racket v7.9 [bc]; the shared runner `tests/m4_scenario_runner.rkt`, unchanged; guarded and watchdogged |
| Runtime | **unchanged** (no file under `mdl/` or `zork/` touched; `mdl/loader.rkt` untouched) |

## Route choice (no seed search)

The ROBBER demon (77act1.mud:1284) walks the thief over `,ROOMS` one room
per turn, sacred rooms skipped (one pass takes 111 turns in this boot, logged natively). He shows
himself in the hero's room only by chance: when his walk reaches the hero's
room and `<PROB 30>` holds ("Someone carrying a large bag is casually
leaning against one of the walls here."). A native exploration run (lamp,
sword, 150 `wait`s in the cellar) met him once on the cycle, and that draw
robbed the hero instead ("A seedy-looking individual ...").

The Treasure Room is deterministic instead. Its room action TREASURE-ROOM
(77act1.mud:623) acts on the walk-in: if the thief is not already there it
prints "You hear a scream of anguish as you violate the robber's hideaway.
Using passages unknown to you, he rushes to its defense.", moves him there
(HROOM, OROOM) and sets his FIGHTBIT; the FIGHTING demon (78melee.mud:282)
then has him strike the same turn. No PROB decides that he comes. The room
is up the Cyclops Room's staircase, open once the cyclops has fled
(CYCLOPS-FLAG). strange-passage's first 25 commands (gated since S9) end
exactly there: the troll killed with the sword, the maze, `odysseus`. So the
route is that prefix plus `up` and the fight; the blows themselves are
RANDOM-driven, deterministic for this seed and input.

Native exploration runs (scratch, not committed; same protocol, disposable
`$TMPDIR` copies):

| Variant after `odysseus` | Native result |
|---|---|
| `up`, `kill thief with sword` x6, `look` | the scenario's fight; the hero dies on the second blow exchange |
| `up`, `kill`, `down`, `diagnose`, `up`, `kill` x2 | the hero flees wounded; the thief leaves the room ("leave if victim left"); on re-entry he rushes back and kills the hero with one blow |
| `up`, `take chalice`, `kill` x3, ... | "Realizing just in time that you'd be stabbed in the back ..."; a longer fight (the thief staggered, both miss), the hero alive after five rounds |
| `up`, `kill` x2, `y`, `look`, `inventory`, `diagnose`, `score` | **the scenario** |

The scenario is the shortest one that shows both sides striking and ends
cleanly (death, `y`, patched). Neither the hero killing the thief nor the
thief's booty was reached: the hero's fighting strength is 2 at RAW-SCORE
60 (FIGHT-STRENGTH, 78melee.mud:364) against the thief's OCAPAC 4.

## Scenario

`tests/scenarios/thief-fight.json`, 33 commands: strange-passage's 1-25,
then `up` `kill thief with sword` `kill thief with sword` `y` `look`
`inventory` `diagnose` `score`. READSTRING entry 28 is YES/NO's
(`entry_prompts` {"28": "Do you want me to try to patch you?"}); the
diagnostic logged YES/NO-ENTRY 28 only, result T.

Native findings by command (checkpoints at READSTRING entries):

- 26 `up`: "This is a large room ... There is a silver chalice, intricately
  engraved, here.", the scream, "You dodge as the thief comes in low." (the
  thief's blow, MISSED), "Your sword has begun to glow very brightly."
  Entry 26: HERE TREAS, thief OROOM TREAS, FIGHTBIT T, OCAPAC 4, the
  chalice's TAKEBIT cleared, RAW-SCORE 35 -> 60 (the room's value 25).
- 27 `kill thief with sword`: "Your sword pinks the thief on the wrist, but
  it's not serious." (the thief's OCAPAC 4 -> 3), "A quick thrust pinks your
  left arm, and blood starts to trickle down." (ASTRENGTH 0 -> -1, CURIN
  enabled, CTICK 29).
- 28 `kill thief with sword`: "The thief is struck on the arm, blood begins
  to trickle down." (OCAPAC 2), "The thief knocks you out." (UNCONSCIOUS
  against the hero; FIGHTING sets its OUT counter), "The thief, who is
  essentially a pragmatist, dispatches you as a threat to his livelihood."
  (SITTING-DUCK), "It appears that that last blow was too much for you.
  I'm afraid you are dead." and the question (JIGS-UP: DEATHS 1, RAW-SCORE
  60 -> 50).
- 29 `y`: "Now, let me see...", "Well, we weren't quite able to restore your
  state.  You can't have everything.", the forest (FORE1), the sword to
  ALISM and the lamp to the living room. The thief is still in the Treasure
  Room at entry 29 and gone at entry 30 (the ROBBER demon's "leave if
  victim left").
- 30 `look`: the forest. 31 `inventory`: "You are empty handed." 32
  `diagnose`: "You have a serious wound, which will be cured after 57
  moves. You can be killed by one more light wound. You have been killed
  once." 33 `score`: 50 in 32 moves.
- Before entry 26 the thief is never in any room (thief OROOM `#FALSE ()`
  at entries 0-25); his stiletto stays in his hand (OCAN THIEF) and HACTION
  stays ROBBER throughout (he is never knocked out or killed).
- Prefix 28 (input ends at the question): YES/NO's end-of-input read leaves
  the stale "k" of "kill" in INBUF, not one of "NnfF", so the hero is
  patched (end checkpoint 28: FORE1). Prefix 29's end-of-input turn: the
  thief leaves the Treasure Room. These two are the only shorter prefixes
  whose end state differs from the next entry's checkpoint, HROOM aside.

## Checkpoint profile "thief"

`scripts/probe_death_scenario_reference.py` gains THIEF_DIAG_FORMS: the
"timers" fields (unchanged), then the thief's OCAPAC, FIGHTBIT and STAGGERED
bits, the stiletto's OROOM and OCAN, the chalice's OROOM and TAKEBIT, and
the ROBBER demon's HACTION. The earlier profiles are built as before (the
new profile is derived from TIMERS_DIAG_FORMS by string replacement; the
other profiles' strings are not touched): each of the 14 earlier committed
references' `diag_forms` still equals its profile string, checked after
the change. `tests/m4_thief_checkpoint.rkt`
renders exactly these fields with pure reads (GVALs, NTH on NEWSTRUC
offsets, ANDB/CHTYPE on flag words, FIND-OBJ on existing IDs) on top of
`timers-checkpoint`. Dkk logs are compacted to sha256 and size, as for the
timers profile.

## Captures

| Command | Exit | Record |
|---|---|---|
| `sha256sum .cache/build/confusion_patched/mdli` (before) | 0 | `6df359f6…b789` |
| `python3 -I scripts/probe_death_scenario_reference.py thief-fight $SCRATCH/cap1.json` (copied to `docs/evidence/M4/thief-fight-reference.json`) | 0 (`CAPTURE OK`) | 69 runs (35 transcript, 34 diagnostic), 16 s; reference sha256 `1bc5e2cd…3643`; T1 stdout sha256 `ffb62385…8d92`; shim sha256 `d1fa8652…b925`; probe sha256 at capture `08816e35…44fe` |
| same, second capture to `$SCRATCH/cap2.json` (not committed) | 0 (`CAPTURE OK`) | all 35 transcript cases' stdout byte-identical; transcript, diagnostic (X1 checkpoints and 24 RANDOM draws) and end checkpoints identical; the 34 diagnostic cases' logs identical (sha256) and game parts identical; their raw stdouts differ only in the echoed disposable log path (as in every M4 reference, TESTING "Diagnostic stdout hashes") |

The scenario file's `description` was edited after the capture (the record's
file name); the reference holds the commands, not the description, and the
commands are unchanged (the test asserts `commands` equal the reference's).

## Results (ours)

Run with `PLTCOLLECTS=":$PWD" TMPDIR=/tmp/claude-1000
PYTHONPATH=$PWD/.sandbox-pydeps/lib make PYTHON=/usr/bin/python3 …`, one
heavy job at a time.

| Command | Exit | Result |
|---|---|---|
| `racket tests/historical_thief_fight_test.rkt` (first run, before the target existed) | 0 | 34 turns; 3 boots (prefixes 28, 29 re-run); 16.6 s |
| `make test-m4-thief-fight` (single-run) | 0 | 34 turns; 3 boots; 17.5 s |
| `M4_SCENARIO_MODE=per-prefix make test-m4-thief-fight` | 0 | 34 turns; 34 boots; 197.0 s |
| `make test` | @@MAKETEST@@ | @@MAKETEST_RESULT@@ |
| `make m4-check` | @@M4CHECK@@ | @@M4CHECK_RESULT@@ |
| `git diff --check origin/main HEAD` | @@DIFFCHECK@@ | |

No divergence: our runtime matches the native reference at every READSTRING
entry and at every prefix end in both modes. No XFAIL was needed.

## Mutation checks (each reverted; the tree clean afterwards)

Mutations of the committed reference (and, for the "b"/"c" variants, of the
test's own assertions) to show the test fails when the expectation is wrong.
Restored from a copy after each run; `git diff --quiet` on both files
confirmed the revert.

| # | Mutation | Result |
|---|---|---|
| M1 | checkpoint 27 `thief_ocapac` 3 -> 4 | exit 1 at the test's reference check (the fight table, line 71) |
| M1b | M1 with the fight table removed | exit 1 at the next reference check (the non-standard prefix list, line 79: prefix 27 now looks non-standard) |
| M1c | M1 with both removed | exit 1: earliest failing k = 27, kind checkpoint, field `thief_ocapac` (expected 4, actual 3) |
| M2 | "The thief knocks you out." -> "... oUt." in T1 and every transcript prefix from 28 on (7 cases, sha256 updated) | exit 1 at the test's reference check (the fight text in T1, line 112) |
| M2b | M2 with the T1 fight-text check and the per-turn check removed | exit 1: earliest failing k = 28, kind transcript, stage single-run |

## Gameplay branches (`gameplay-branches.json`)

| Branch | Change |
|---|---|
| `combat.thief` | UNCOVERED -> covered by `test-m4-thief-robbery` (steals) and `test-m4-thief-fight` (fights, is fought) together; the note lists what is not exercised |
| `combat.hero-wounded` | adds thief-fight (the thief's light wound on the sword-armed hero) |
| `combat.hero-staggered-or-unconscious` | adds thief-fight: knocked unconscious, transiently only (the same turn's next blow kills; no READSTRING entry sees the hero unconscious) |
| `death.killed-in-combat` | adds thief-fight (killed by the thief) |

Not exercised by any gated check (stated in the combat.thief note): the
thief appearing by chance in another room (PROB 30) or leaving a fight
("Your opponent, determining discretion ..."), the hero killing or knocking
out the thief (his booty, the treasures reappearing; ROBBER-FUNCTION's DEAD!,
OUT!, IN!), the stiletto knocked from his hand, giving or throwing him
objects, the chalice taken, and the thief robbing the hero while present.

## Security and licensing

No runtime code changed. New: one scenario file, one native reference, one
probe profile, one checkpoint module and one test (test infrastructure; no
new file access; the runner's guard saw no write or delete). Native runs
used disposable `$TMPDIR` copies only; `.cache/upstream` was not written;
mdli was not rebuilt. Confusion (GPLv3) was used only as a behaviour
reference; no Confusion code was copied. New scripts and tests are original
MIT-0 code.

## Open risks and limits

- One fixed clock and seed. Under another seed the blows differ: the hero
  may survive longer or kill the thief; the thief's arrival in the Treasure
  Room does not depend on the seed.
- The thief's chance appearance elsewhere, his retreat, his death and the
  hero's recovery from unconsciousness stay unexercised.
- `make m4-decl-sweep` (diagnostic only) reads the manifest and would now
  include thief-fight; it was not re-run in this slice, so
  `decl-violation-sweep.json` does not list it.
- robber_hroom does not decide reboots here (as in the other thief-walking
  scenarios); it is compared at every entry, at the end and per prefix.

## Next actionable task

The maintainer decides whether `combat.thief` is acceptably covered by two
scenarios together; otherwise a scenario that kills the thief (a stronger
hero, i.e. a higher score first) would cover his death and booty.
