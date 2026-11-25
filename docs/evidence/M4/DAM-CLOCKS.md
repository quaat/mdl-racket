# M4 Phase 3b: beyond the house — match clock, boat and river, dam frontier (INV-11)

Date: 2026-11-25. Branch `feat/m4-dam` from `main` `67bd41f`. Epic #163
Phase 3b (objects beyond the house; other clock events). Gate label:
**scenario evidence on a local branch** (two more native-parity scenarios,
each under one fixed clock and seed, and one frontier finding recorded as a
tracked expected failure). Not a PLAYABLE, GAMEPLAY_RELIABILITY or M4 claim.

## Provenance

| Item | Value |
|---|---|
| Upstream game | `mdlzork` bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3 (`sources.lock.json`), `mdlzork_771212/patched_confusion`, unmodified |
| Pinned reference | `.cache/build/confusion_patched/mdli`, sha256 `6df359f6…b789`, unchanged before and after every capture (checked by the probe and with `sha256sum`); `make reference-build` not run |
| Clock / RNG | fixed epoch 250776000 (1977-12-12 12:00 UTC), TZ UTC; START seeds RANDOM from DSKDATE (seed 10438660480); no RANDOM override, no seed search, no game-specific random override |
| Native protocol | `scripts/probe_death_scenario_reference.py NAME OUT.json` with two new checkpoint profiles, "dam" and "boat" (below); a fresh copy of the game directory under `$TMPDIR` for every run, pipe mode; each reference captured twice, transcripts byte-identical |
| Ours | Racket v7.9 [bc]; the shared runner `tests/m4_scenario_runner.rkt`, unchanged; guarded (no write or delete, empty cwd, game-directory hashes unchanged) and watchdogged |
| Runtime | **unchanged** (no file under `mdl/` or `zork/` touched) |

## The dam: a frontier, not a scenario (INV-11)

The intended slice was the Flood Control Dam #3 puzzle (the yellow button,
the wrench and bolt, the sluice gates, the drained reservoir) and its own
clock event MNTIN (the blue button's leak, MAINT-ROOM 77act1.mud:737,
`<CLOCK-INT ,MNTIN -1>`: fires on every clock pass). Both are reachable
cheaply natively under this seed, and both native references were captured
twice (byte-identical transcripts):

| Route | Commands | Native key turns | Reference |
|---|---|---|---|
| dam-sluice | 41: troll-combat's 16; `north` `north` `down` `up` `east` `north` `north` (Maintenance Room, command 23); `take wrench`; back to the Dam; `turn bolt with wrench`; back; `push yellow button`; back; `look`; `turn bolt with wrench`; `look`; `south` `nw` `look` `take trunk` `north` `score` | 27: "The bolt won't turn with your best effort." (GATE-FLAG unset); 30: "Click." (GATE-FLAG T); 33: "The green bubble is glowing."; 34: "The sluice gates open and water pours through the dam." (LOW-TIDE T, the trunk's OVISON set); 38: the drained reservoir's text and the trunk; 39: trunk taken, RAW-SCORE 40 -> 55; 40: across the reservoir bed to Reservoir North (the LOW-TIDE exit) | `dam-sluice-reference.json` (85 runs, sha256 `03d60d92…8f9f`; 22 RANDOM draws) |
| maint-leak | 35: the same 23; `push blue button` `look` `take tube` `open tube` `take putty` `wait` `plug leak with putty` `wait` `look` `push blue button` `south` `score` | 24: the leak; MNTIN queued `(MNTIN T -1)`, RVARS 2 and "The water level here is now up to your shin."; one level per turn (RVARS 3–6); 29 `wait`: five passes (RVARS 6 -> 11; WAIT's three CLOCK-DEMON passes, the room action after the verb, which sees PRSVEC 1 left at C-INT, 77rooms.mud:632, and the turn's own pass); 30: "By some miracle of elven technology, you have managed to stop the leak in the dam." (RVARS -1, MNTIN CTICK 0); 31 `wait`: no level text; 33: "The blue button appears to be jammed." | `maint-leak-reference.json` (73 runs, sha256 `7ab681cb…f16a`; 14 RANDOM draws) |

**Divergence (first, and the stop).** This runtime matches both references
at READSTRING entries 0–22 (output and checkpoint) and stops at command 23,
entering the Maintenance Room:

* native: the room's long description, "There is an object which looks like
  a tube of toothpaste here.", "There is a wrench here.", "There is a
  screwdriver here.", then `>`; play goes on;
* ours: the same text up to "There is a screwdriver here.\n", then the strict
  failure `mdl-decl: DECL 740:9: unknown declaration type PRSOBJ`; the
  runner reports `earliest failing k = 23, kind run-guard` (report
  `artifacts/scenario-divergence/dam-sluice-single-run.json`, not committed).

Root cause (confirmed from the source and the error position): MAINT-ROOM's
attached `#DECL` (77act1.mud:739–741) gives PRSO the type `PRSOBJ`, which no
1977 source file defines (the name occurs otherwise only as a local variable:
HELLO, RING, EAT and ROBBER-FUNCTION in 77act1.mud, SHAKE in 77act2.mud). The deferred-declaration ADR (issue #98,
DECISIONS.md "Defer unresolved TYPE atoms in attached declarations") lets
such a definition load but keeps the check strict at call time and never
lets an unknown name match as ANY; pinned Confusion does not check attached
declarations at all, so the native game runs. WIRE-FUNCTION (77act2.mud:585,
the balloon's wire) declares the same type (source-derived; not run).

As the slice brief requires, no runtime semantics were changed. The finding
is INV-11 in [GAMEPLAY-FAILURE-INVENTORY.md](GAMEPLAY-FAILURE-INVENTORY.md)
(class (a), P1) and a new open item in `gameplay-branches.json`'s
`blocking_inventory`. Options: (1) keep it strict (the dam, the leak and the
balloon wire stay unreachable); (2) amend the ADR so that an attached
declaration's still-undefined TYPE name is not checked, following the pinned
reference (a recorded deviation, limited to unresolved names); (3) a
separately versioned source patch defining PRSOBJ (changes upstream
provenance; needs approval). **Recommended next action:** a maintainer
decision between (2) and (3) (issue to be filed), then promote dam-sluice
and maint-leak to gated scenarios with the committed references.

**Tracked expected failure.** `make xfail-m4-dam-frontier`
(`tests/historical_dam_frontier_test.rkt`; not in the manifest's scenarios,
not counted by m4-check) checks the two native references' key turns and
asserts that both routes still fail exactly at k = 23 with the PRSOBJ
message; it fails (XPASS) once the room can be entered. The scenario files
`tests/scenarios/dam-sluice.json` and `maint-leak.json` are listed in the
manifest's `excluded_scenario_files` with that reason.

## Route choice for the gated scenarios (no seed search)

* **match-clock** (`timers.other-clock-events`). With MNTIN out of reach,
  the nearest other clock is on the same route: the matchbook in the Dam
  Lobby (MATCH-FUNCTION 77act1.mud:1925, `<CLOCK-INT ,MATIN 2>`). One
  exploration run (three lights) worked; the scenario adds the last two
  matches. [Reference](MATCH-CLOCK-REFERENCE.md).
* **boat-river** (`objects.puzzles-beyond-the-house`). The pump is in
  Reservoir North, reachable with the reservoir full only through the
  Atlantis Room; mirror-bat's first 31 commands reach Mirror Room 1. Four
  exploration runs: a wrong exit from the Cave (rejected), the working
  route, a river trip downstream that drowns the hero on `disembark`
  (rejected: a death), and the scenario (`land` at the first river room).
  [Reference](BOAT-RIVER-REFERENCE.md).

## Scenarios

| Scenario | Target | Commands | Native finding (details: reference records) |
|---|---|---|---|
| match-clock | `test-m4-match-clock` | 34 | `light match` (24, 27, 29, 31): ORAND 5 -> 1, `(MATIN T 1)` after the turn's tick; 25 `look`: "The match has gone out."; 28 `wait`: fires at WAIT's first extra pass, WAIT stops; 30 `turn off match`: "The match is out.", CTICK 0; 32: "I'm afraid that you have run out of matches." then the lit one goes out. [Reference](MATCH-CLOCK-REFERENCE.md) |
| boat-river | `test-m4-boat-river` | 58 | 35 `take pump`; 49 `inflate boat with pump`: "The boat inflates and appears seaworthy." (IBOAT -> RBOAT); 50 `board boat` (AVEHICLE RBOAT); 51 `launch` (RIVR1); 52 `land`; 53 `disembark`: "You are on your own feet again."; 55 `deflate boat`: "The boat deflates."; 56 `take boat`. The thief takes the grail and the trident from rooms the hero has left. [Reference](BOAT-RIVER-REFERENCE.md) |

## Checkpoint profiles "dam" and "boat" (probe extended)

`scripts/probe_death_scenario_reference.py` gains DAM_DIAG_FORMS (the timers
forms, then GATE-FLAG, LOW-TIDE, the Maintenance Room's RVARS and RMUNGBIT,
MNTIN's CFLAG and CTICK, the wrench's OROOM, the tube's OOPEN?, the putty's
OROOM and OCAN, the trunk's OROOM and OVISON bit, the matchbook's ORAND,
OLIGHT? and FLAMEBIT, MATIN's CFLAG and CTICK) and BOAT_DIAG_FORMS (the dam
forms, then the winner's AVEHICLE and the OROOM of IBOAT, RBOAT and the
pump). Objects and the room are found once at diagnostic setup (FIND-OBJ,
FIND-ROOM on existing IDs). The existing profiles' forms are byte-identical:
every committed reference's `diag_forms` equals its profile (checked for all
eleven M4 probe references). `tests/m4_dam_checkpoint.rkt` and
`tests/m4_boat_checkpoint.rkt` render exactly these with pure reads (GVALs,
NTH on NEWSTRUC offsets, ANDB/CHTYPE on flag words, FIND-OBJ and FIND-ROOM
on existing IDs), on top of `timers-checkpoint`; the runner's snapshot guard
saw no RANDOM, storage, output or error-record change at any read. Both
scenarios declare `#:eof-classification-ignore-keys '(robber_hroom)`.

## Results

RESULTS_PLACEHOLDER

## Mutation checks (each reverted; `git status` clean afterwards)

MUTATIONS_PLACEHOLDER

## Gameplay branches (`gameplay-branches.json`)

| Branch | Covering checks | Precision |
|---|---|---|
| `timers.other-clock-events` | match-clock | one clock event, MATIN, queued, fired at a regular tick and at a `wait`, set to 0 by `turn off match`; MNTIN is recorded natively (maint-leak, `evidence_only`) but blocked by INV-11; the candle, balloon, burn, fuse, ledge, safe, gnome, bucket and sphere clocks are not reached |
| `objects.puzzles-beyond-the-house` | boat-river | ONE of the five listed puzzles, the boat: inflated with the pump, boarded, launched (first river room only), landed, deflated. Not exercised: the river downstream, the dam (recorded natively, `evidence_only`, blocked by INV-11), the balloon (its wire declares PRSOBJ too), the coal-mine machine and basket, the gas room. The maintainer may split the branch per puzzle; four would then be uncovered |

New blocking item: INV-11 (open, no issue yet). GAMEPLAY_RELIABILITY stays
NOT YET.

## Security and licensing

No runtime code changed. The new test files, checkpoint modules and probe
profiles are test infrastructure; no new file access (the guard shows no
write or delete attempt). Native runs used disposable `$TMPDIR` copies only;
`.cache/upstream` was not written; mdli was not rebuilt. Confusion (GPLv3)
was used only as a behaviour reference; no Confusion code was copied. New
scripts and tests are original MIT-0 code.

## Open risks and limits

- Each scenario is one fixed clock and seed; other seeds take other branches
  (boat-river reuses mirror-bat's RANDOM round-room route).
- `objects.puzzles-beyond-the-house` is covered by one of five listed
  puzzles; `combat.thief` was kept UNCOVERED for a similar partial match
  (its description asks for all three actions). The maintainer may prefer to
  split this branch rather than count it covered.
- The dam, its leak clock and the balloon's wire are unreachable in this
  runtime until INV-11 is decided; the native references are committed for
  that promotion.
- robber_hroom does not decide reboots in the two new scenarios (as in three
  Phase 3 scenarios); it is still compared at every entry.

## Next actionable task

File the INV-11 issue and obtain the maintainer decision on attached
declarations naming an undefined TYPE (ADR #98 amendment or a provenance
patch); then promote dam-sluice and maint-leak.
