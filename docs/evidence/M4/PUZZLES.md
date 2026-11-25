# M4 Phase 3c: the puzzles beyond the house — coal mine, gas room, balloon frontier (INV-12)

Date: 2026-11-25. Branch `feat/m4-puzzles` from `main` `6cd1b68`. Epic #163
Phase 3c (objects beyond the house: the remaining listed puzzles). Gate
label: **PASS (local branch, not merged; scenario-scoped)** for the two new
gated scenarios coal-machine and gas-room; **BLOCKED (INV-12)** for the
balloon, recorded as a frontier finding with a tracked expected failure.
Not a PLAYABLE, GAMEPLAY_RELIABILITY or M4 claim.

## Provenance

| Item | Value |
|---|---|
| Upstream game | `mdlzork` bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3, `mit_zork` d94501340842e006791fce0757dc0043b8ec8916 (`sources.lock.json`); `mdlzork_771212/patched_confusion`, unmodified |
| Pinned reference | `.cache/build/confusion_patched/mdli`, sha256 `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789`, unchanged before and after every capture (checked by the probe and with `sha256sum`); `make reference-build` not run |
| Clock / RNG | fixed epoch 250776000 (1977-12-12 12:00 UTC), TZ UTC; START seeds RANDOM from DSKDATE (seed 10438660480); no RANDOM override, no seed search, no game-specific random override |
| Native protocol | `scripts/probe_death_scenario_reference.py NAME OUT.json` with the new checkpoint profile "puzzles" (below); a fresh copy of the game directory under `$TMPDIR` for every run, pipe mode; each reference captured twice, transcripts byte-identical |
| Ours | Racket v7.9 [bc]; the shared runner `tests/m4_scenario_runner.rkt`, unchanged; guarded and watchdogged |
| Runtime | **unchanged** (no file under `mdl/` or `zork/` touched) |

## Route choice (no seed search)

Details and the exploration runs: the three reference records.

* **coal-machine** ([reference](COAL-MACHINE-REFERENCE.md)). The machine
  needs the coal (the Dead End, bottom of the mine), the screwdriver (the
  Maintenance Room) and light in the Lower Shaft, which only the
  empty-handed may enter from the Timber Room (NO-OBJS). So the coal, the
  screwdriver and a second light go down in the basket and the lamp is
  dropped in the Timber Room; the second light is the Altar's burning
  candles. The mine side is reached through the drained reservoir and the
  mirror, avoiding the round room's RANDOM exits. Commands 1-24 are
  dam-sluice's. Three native runs: a wrong exit from the Temple (rejected),
  the working route, the scenario (with the basket raised too).
* **gas-room** ([reference](GAS-ROOM-REFERENCE.md)). coal-machine's first 50
  commands reach the Shaft Room with the lamp and the burning candles; the
  Gas Room is two rooms away. BOOM-ROOM's rule is exercised both ways: in
  with the lamp only (nothing), in with the candles (the explosion). One
  native run.
* **balloon-ledge** ([reference](BALLOON-LEDGE-REFERENCE.md)). The torch
  (under the Dome Room, by the attic's rope) melts the glacier; the
  guidebook and the matchbook come from the Dam Lobby. Two native runs: the
  rope taken before the troll changed the fight and the troll killed the
  hero (rejected: a death); troll-combat's sixteen commands unchanged and
  the chimney back to the house for the rope (the scenario).

## Scenarios

| Scenario | Target | Commands | Native finding |
|---|---|---|---|
| coal-machine | `test-m4-coal-machine` | 94 | 41 `take candles` (CNDIN queued); 59 `take coal`; 66-68 coal, screwdriver, candles in the basket; 69 `lower basket` (CAGE-TOP false, TBASK in BSHAF); 78 `drop all` (EMPTY-HANDED T); 79 `sw`: the Lower Shaft lit by the candles in the basket, LIGHT-SHAFT scored (RAW-SCORE 40 -> 50); 84-86 the lid, the coal in; 87 `turn switch with screwdriver`: "The machine comes to life (figuratively) ..." (MACHI OCONTENTS (DIAMO)); 89 `take diamond` (60); 92 `raise basket` (CAGE-TOP T). The thief takes the trident and the trunk elsewhere |
| gas-room | `test-m4-gas-room` | 62 | 54 `down` with the lamp only: "You are in a small room which smells strongly of coal gas." and nothing else; 55 the bracelet (45); 58 `down` with the burning candles: "Oh dear.  It appears that the smell coming from this room was coal gas. ...", six BELs, "   BOOOOOOOOOOOM      ", JIGS-UP's question (entry 58, DEATHS 1, 35); 59 `y`: patched in the forest, the objects scattered |
| balloon-ledge (native only) | `xfail-m4-balloon-frontier` (not counted) | 81 | 57 `board basket`; 59 `burn guide with match`: the bag inflates (BINF GUIDE, BINT, BRNIN); 61 rises (VAIR1), 64 ascends (VAIR2), 66 `west` onto the Narrow Ledge; 68 `tie wire to hook` (BTIE T, BINT disabled); 71 `untie wire`; 73 leaves the ledge; 76 `close receptacle`: descends; 79 "The balloon has landed." |

## The balloon: a frontier, not a scenario (INV-12)

**Divergence (first, and the stop).** This runtime matches the balloon-ledge
reference at READSTRING entries 0-56 (output and checkpoint) and stops on
the turn of command 57, `board basket`:

* native: "You are in the basket." then `>`; play goes on (`light match`:
  "One of the matches starts to burn.");
* ours: "You are in the basket." then the strict failure `mdl-decl: DECL
  424:9: PRSO does not satisfy declaration`; the runner reports `earliest
  failing k = 57, kind run-guard` (report
  `artifacts/scenario-divergence/balloon-ledge-single-run.json`, not
  committed).

Root cause (confirmed from the source, the error position and a native
diagnostic run): after the demons, RDCOM applies the vehicle's action with
READ-OUT (77rooms.mud:648-651). CLOCK-DEMON, a demon that runs whenever the
parse won, has just set PRSVEC 2 and 3 to `<>` (77rooms.mud:1633-1634).
BALLOON (77act2.mud:419) binds `(PRSO <2 .PRSVEC>)` under its attached
declaration `(PRSO) <OR OBJECT DIRECTION>` (77act2.mud:424-425). The value is
`#FALSE ()`: a native diagnostic run (BALLOON wrapped after FLOAD to print
`<TYPE <2 ,PRSVEC>>`) shows READ-IN with an OBJECT and READ-OUT with a FALSE
on both the `board basket` and the `light match` turns. Pinned Confusion
checks no attached declaration; this runtime checks those of known TYPEs
(the #98 ADR; the #193 amendment relaxed only still-undefined names, such as
WIRE-FUNCTION's PRSOBJ, which this route never reaches in our runtime).
Source-derived, not run: after the burn, BALLOON's `(BINF) <OR FALSE ROOM>`
binding receives the burning OBJECT (77act2.mud:426, 488), a second
violation of the same declaration. BUCKET, the other vehicle action with
such a binding, declares `<OR DIRECTION FALSE OBJECT>` (77act3.mud:44).

As the slice brief requires, no runtime semantics were changed. The finding
is INV-12 in [GAMEPLAY-FAILURE-INVENTORY.md](GAMEPLAY-FAILURE-INVENTORY.md)
(class (a), P1) and a new open item in `gameplay-branches.json`'s
`blocking_inventory` (no GitHub issue yet). Options: (1) keep it strict (the
balloon and the volcano stay unreachable); (2) a further ADR amendment, for
example not enforcing attached declarations (or those of AUX bindings),
following pinned Confusion, as a recorded deviation; (3) a separately
versioned source patch widening BALLOON's declaration, which changes
upstream provenance and needs approval. **Recommended next action:** a
maintainer decision between (2) and (3), informed by a sweep of attached
declarations the game violates on normal play paths; then promote
balloon-ledge with the committed reference.

**Tracked expected failure.** `make xfail-m4-balloon-frontier`
(`tests/historical_balloon_frontier_test.rkt`; not in the manifest's
scenarios, not counted by m4-check) checks the native reference's key turns
(the rope, the torch, the glacier; the balloon by entry: HERE, AVEHICLE,
BLOC, BINF, BTIE, the receptacle, BINT and BRNIN) and asserts that the route
still fails exactly at k = 57 with `DECL 424:9: PRSO does not satisfy
declaration`; it fails (XPASS) once the balloon can be boarded.
`tests/scenarios/balloon-ledge.json` is listed in the manifest's
`excluded_scenario_files` with that reason.

## Checkpoint profile "puzzles" (probe extended)

`scripts/probe_death_scenario_reference.py` gains PUZZLES_DIAG_FORMS: the
boat forms, then, found once at diagnostic setup (FIND-OBJ on existing IDs):
the balloon's OROOM; BLOC (RID); BINF!-FLAG (OID); BTIE!-FLAG; the
receptacle's OOPEN? and OCONTENTS; BINT's and BRNIN's CFLAG and CTICK; the
guidebook's OROOM, OCAN and OLIGHT?; the rope's OROOM and DOME-FLAG; the
torch's OROOM and OLIGHT? and GLACIER-FLAG; CAGE-TOP!-FLAG, the OROOM of TBASK
and FBASK, TBASK's OCONTENTS; the coal's OROOM and OCAN; the machine's OOPEN?
and OCONTENTS; the diamond's OROOM and OCAN; the screwdriver's OROOM;
LIGHT-SHAFT; EMPTY-HANDED!-FLAG; the candles' OROOM, OCAN and OLIGHT?; CNDIN's
CFLAG and CTICK; the bracelet's OROOM. The earlier profiles' forms are
byte-identical: every committed reference's `diag_forms` equals its profile
(checked for all fourteen references of this probe, the eleven earlier ones
included). `tests/m4_puzzles_checkpoint.rkt` renders exactly these with pure
reads, on top of `boat-checkpoint`; the runner's snapshot guard saw no
RANDOM, storage, output or error-record change at any read. All three
scenarios declare `#:eof-classification-ignore-keys '(robber_hroom)`;
gas-room declares the death question (`#:entry-prompts`, entry 58).

## Results

RESULTS-PLACEHOLDER

## Security and licensing

No runtime code changed. The new test files, checkpoint module and probe
profile are test infrastructure; no new file access (the guard shows no
write or delete attempt). Native runs used disposable `$TMPDIR` copies only;
`.cache/upstream` was not written; mdli was not rebuilt. Confusion (GPLv3)
was used only as a behaviour reference; no Confusion code was copied. New
scripts and tests are original MIT-0 code.

## Open risks and limits

- Each scenario is one fixed clock and seed; other seeds take other branches
  (the thief's moves, the troll fight: one balloon exploration run died to
  the troll).
- `objects.puzzles-beyond-the-house` stays UNCOVERED: four of the five
  listed puzzles are exercised; the balloon is blocked by INV-12. The gas
  room's ON branch (a flame lit inside it) and the torch variant of its rule
  are not exercised.
- INV-12 is likely not alone: other attached declarations of known types may
  be violated by the game's own values on paths not yet run (a source sweep
  is recommended before the maintainer decision).
- The new references are large (gas-room 3.7 MB, balloon-ledge 5.3 MB,
  coal-machine 6.2 MB; lamp-burnout's 4.1 MB is the earlier maximum).
- robber_hroom does not decide reboots in the three routes; it is still
  compared at every entry.

## Next actionable task

A maintainer decision on INV-12 (a further attached-declaration ADR
amendment or a provenance-recorded BALLOON patch), preceded by a sweep of
attached declarations violated on normal play paths; then promote
balloon-ledge to a gated scenario, after which
`objects.puzzles-beyond-the-house` can be covered.
