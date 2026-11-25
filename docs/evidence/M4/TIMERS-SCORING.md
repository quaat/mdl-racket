# M4 Phase 3: timers, objects and scoring (treasure-deposit, thief-robbery, cure-recovery, lamp-burnout)

Date: 2026-11-25. Branch `feat/m4-timers-scoring` from `main` `903ba6c`.
Epic #163 Phase 3 (timers, objects, scoring). Gate label: **scenario
evidence on a local branch** (four more native-parity scenarios, each under
one fixed clock and seed). Not a PLAYABLE, GAMEPLAY_RELIABILITY or M4 claim.

## Provenance

| Item | Value |
|---|---|
| Upstream game | `mdlzork` bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3 (`sources.lock.json`), `mdlzork_771212/patched_confusion`, unmodified |
| Pinned reference | `.cache/build/confusion_patched/mdli`, sha256 `6df359f6…b789`, unchanged before and after every capture (checked by the probe and with `sha256sum`); `make reference-build` not run |
| Clock / RNG | fixed epoch 250776000 (1977-12-12 12:00 UTC), TZ UTC; START seeds RANDOM from DSKDATE (seed 10438660480); no RANDOM override, no seed search, no game-specific random override |
| Native protocol | `scripts/probe_death_scenario_reference.py NAME OUT.json`, generalised with checkpoint profiles (below): a fresh copy of the game directory under `$TMPDIR` for every run, pipe mode; each reference captured twice, transcripts byte-identical |
| Ours | Racket v7.9 [bc]; the shared runner `tests/m4_scenario_runner.rkt` with one opt-in option (`#:eof-classification-ignore-keys`, default `'()`); guarded (no write or delete, empty cwd, game-directory hashes unchanged) and watchdogged |

## Route choice (no seed search)

* **treasure-deposit.** The 1977 sources have no tree and no egg. The nearest
  treasure is the painting (OFVAL 4, OTVAL 7) in the Gallery, two rooms
  south of the cellar; the Studio's chimney leads back up to the kitchen
  with the lamp and one more object. Four deterministic routes were tried
  natively: the direct one (the thief takes the painting from the hero),
  a detour south and north (the thief takes it from the Gallery), a `look`
  in the cellar and a `look` at West of Chasm (both reach the case). The
  scenario uses the `look` in the cellar. The routes draw RANDOM at
  different turns; the seed itself never changed.
* **thief-robbery.** The direct route above, kept as a scenario because the
  thief appeared in it under the fixed seed (observed, not sought).
* **cure-recovery.** troll-death's first eighteen commands (the wound), then
  `west` out of the troll's reach and `wait`/`diagnose` until healed.
* **lamp-burnout.** The lamp's lifetime is in the source: LNTIN 350 ticks
  (77dung.mud:2388), then LAMP-TICKS 50 30 20 10 4 0 (77act1.mud:1855), 464
  ticks with the lamp on. WAIT (77rooms.mud:1619) is the game's multi-tick
  wait (CLOCK-DEMON up to three more times per `wait`, stopping when an event
  fires), so 118 `wait`s in the lit living room reach the burn-out.

## Scenarios

| Scenario | Target | Commands | Native finding (details: reference records) |
|---|---|---|---|
| treasure-deposit | `test-m4-treasure-deposit` | 21 | `take painting` (command 14): RAW-SCORE 35 -> 39 (SCORE-OBJ). Up the chimney, `open case`, `put painting in case` (command 19): "Done.", painting in TCASE, ASCORE 46 = RAW-SCORE 39 + OTVAL 7; `look` lists "Your collection of treasures consists of: A painting"; `score` 46. [Reference](TREASURE-DEPOSIT-REFERENCE.md) |
| thief-robbery | `test-m4-thief-robbery` | 21 | Command 13 `take painting`: "Taken." then the thief "quietly abstracted all valuables from the room and from your possession"; the painting in the ROBBER demon's HOBJS; in the Studio he finds nothing; `put painting in case`: "I can't see a paint here."; `score` 39. Prefix 12's end-of-input turn: he takes it from the room. [Reference](THIEF-ROBBERY-REFERENCE.md) |
| cure-recovery | `test-m4-cure-recovery` | 35 | Wounded at command 18 (ASTRENGTH -1, CURIN 29), `west`; `diagnose`: cured after 28, 23, 18, 13, 8, 3 moves; command 31 (`wait`): CURE-CLOCK, ASTRENGTH 0, CURIN disabled; "You are in perfect health." [Reference](CURE-RECOVERY-REFERENCE.md) |
| lamp-burnout | `test-m4-lamp-burnout` | 131 | `turn on lamp` (command 7): LNTIN on, 349. Dimmer warnings after commands 95, 108, 116, 121; "The lamp is dying." 124; "I hope you have more light than from a lamp." 125 (OLIGHT? 0, LNTIN at 0); `turn on lamp`: "You can't turn that on."; `down`: "It is pitch black. ..." Capture 74 s (265 native runs). [Reference](LAMP-BURNOUT-REFERENCE.md) |

## Checkpoint profile "timers" (probe generalised)

`scripts/probe_death_scenario_reference.py` now maps each scenario to a
checkpoint profile (`PROFILES`). The death scenarios keep `DIAG_FORMS`
byte for byte (checked against the three committed references'
`diag_forms`). The "timers" profile adds, before `CP-END`: the lamp's
LIGHT-INT count `<1 <ORAND lamp>>`, LNTIN's CFLAG and CTICK, the CLOCKER
demon's whole event list as (CID CFLAG CTICK), the painting's OROOM, OCAN,
OFVAL and OTVAL, the trophy case's OOPEN? and OCONTENTS, the thief's OROOM,
and the ROBBER demon's HROOM, HFLAG and HOBJS. `tests/m4_timers_checkpoint.rkt`
renders exactly these with pure reads (GVALs, NTH on NEWSTRUC offsets,
FIND-OBJ on existing IDs, LENGTH/NTH over existing lists), on top of
`death-checkpoint`. For the timers profile the Dkk cases keep their log's
sha256 and size instead of the log (`diag_logs`; their last checkpoints are
`end_checkpoints`, X1's log is kept): lamp-burnout's reference is 4.1 MB with
that, 13.8 MB without.

**The thief's end-of-input move (runner option, ADR-0062 amendment).** The
ROBBER demon moves the thief's HROOM on every turn, the end-of-input turn
included. With HROOM in the checkpoint every shorter prefix except k = 0
would be classified non-standard and re-run (one boot each). thief-robbery
classifies with it (21 boots). treasure-deposit, cure-recovery and
lamp-burnout declare the new opt-in `#:eof-classification-ignore-keys
'(robber_hroom)` of `tests/m4_scenario_runner.rkt`: the field is removed from
both sides only in `non-standard-eof-tails`, and stays compared at every
READSTRING entry, at the single run's end, in reboots and in per-prefix mode.
The default `'()` leaves every other scenario unchanged; each listed key must
be a compared reference checkpoint field (strict error otherwise). Lost
coverage: for the prefixes classified standard thanks to the option, the
thief's move during the skipped end-of-input turn is not executed by this
runtime there; the same ROBBER code is compared at every regular turn
through HROOM. (A first version of this slice used `#:ignore-keys` instead,
which dropped the field entirely; replaced on review.)

**Rendering finding (test infrastructure, not a runtime divergence).**
Comparing HROOM in lamp-burnout failed at first at entry 105: expected `\!`,
actual `!`. The thief's walk over ,ROOMS reaches the room whose RID is `!`
(created by FIND-ROOM for NULEXIT, 77dung.mud:2053, through EXIT,
77makstr.mud:41); native PRIN1 prints that ATOM escaped (`\!!-ROOMS`), while
the checkpoint rendered the bare PNAME. The runtime's UNPARSE implements no
escaping (core.rkt `mdl-unparse-value`: safe PNAMEs only), and the game never
prints this name. `tests/m4_timers_checkpoint.rkt` now renders HROOM's RID
strictly: `[A-Za-z0-9-]` PNAMEs as they are, `!` as `\!`, any other PNAME a
strict error. The earlier `#:ignore-keys` version had hidden this.

## Results

Run with `PLTCOLLECTS=":$PWD"`, `TMPDIR=/tmp`, outside the tool sandbox
(inside it, the runner's `/tmp` work directories fail with "Read-only file
system").

| Command | Exit | Result |
|---|---|---|
| `python3 -I scripts/probe_death_scenario_reference.py NAME …` (four scenarios, twice each) | 0 | `CAPTURE OK` eight times; the second captures identical (10 s, 9 s, 17 s, 74 s) |
| `racket tests/historical_treasure_deposit_test.rkt` (single-run) | 0 | 22 turns; 2 boots (reboot of prefix 15: the thief appears); 11.5 s |
| `racket tests/historical_thief_robbery_test.rkt` (single-run) | 0 | 22 turns; 21 boots (20 reboots: HROOM moves on every end-of-input turn but k = 0); 128.5 s |
| `racket tests/historical_cure_recovery_test.rkt` (single-run) | 0 | 36 turns; 1 boot; 6.0 s |
| `racket tests/historical_lamp_burnout_test.rkt` (single-run) | 0 | 132 turns; 1 boot; 6.4 s |
| treasure-deposit and cure-recovery single-run with HROOM also used for classification (first version) | 0 | 19 boots 117.0 s; 35 boots 227.2 s |
| `M4_SCENARIO_MODE=per-prefix racket tests/historical_treasure_deposit_test.rkt` | 0 | 22 boots, 136.2 s |
| `M4_SCENARIO_MODE=per-prefix racket tests/historical_thief_robbery_test.rkt` | 0 | 22 boots, 135.3 s |
| `M4_SCENARIO_MODE=per-prefix racket tests/historical_cure_recovery_test.rkt` | 0 | 36 boots, 235.1 s |
| `M4_SCENARIO_MODE=per-prefix racket tests/historical_lamp_burnout_test.rkt` | 0 | 132 boots, 1315.6 s |
| `make test PYTHON=/usr/bin/python3` | 0 | 4927 Racket tests passed; Python 104 passed, 1 deselected |
| `make m4-check PYTHON=/usr/bin/python3` | 0 | 577 s; SCENARIO_PARITY PASS (18 scenarios); GAMEPLAY_RELIABILITY NOT YET (17 of 23); see [below](#make-m4-check) |
| `git diff --check` | 0 | |

The probe's sha256 at capture time was `51316c47…4a9f`; a later docstring
change (the `diag_logs` paragraph) makes it `7111e920…fa9f`, with no code
change.

## Mutation checks (each reverted; `git status` clean afterwards)

Native mutations change one byte in every reference transcript from the key
turn on (the prefix stdouts P_k, k >= K, and T1; their sha256 updated so the
integrity check passes). Checkpoint mutations change one field of diagnostic
checkpoint K; the "a" variant shows the test's own reference assertion
failing first, the "b" variant comments out the asserting lines so that the
runner itself has to find it. Every mutation and test edit was reverted with
`git checkout`; `git status` was clean after each. M1–M8b ran with the
first version of this slice (HROOM ignored in three scenarios); M9 and M10
with the classification option.

| # | Mutation | Result |
|---|---|---|
| M1 | treasure-deposit: `Done.` -> `DOne.` (the case deposit, K = 20) | exit 1: earliest failing k = 20, kind transcript (single-run head 20) |
| M2 | treasure-deposit: checkpoint 19 `ascore` 46 -> 45 | exit 1 at the test's reference check (row 19, line 59) |
| M2b | M2 with the row-19 and row-22 assertions removed | exit 1: earliest failing k = 19, kind checkpoint, field `ascore` |
| M3 | thief-robbery: `abstracted` -> `abstracteD` (the theft, K = 13) | exit 1: earliest failing k = 13, kind transcript (after the reboots of prefixes 1–12 passed) |
| M4 | thief-robbery: checkpoint 13 `robber_hobjs` (PAINT) -> () | exit 1 at the test's reference check (row 13, line 64) |
| M4b | M4 with the row-13 assertion removed | exit 1: earliest failing k = 13, kind checkpoint, field `robber_hobjs` |
| M5 | cure-recovery: `perfect` -> `pErfect` (first healed `diagnose`, K = 32) | exit 1: earliest failing k = 32, kind transcript |
| M6 | cure-recovery: checkpoint 31 `winner_astrength` 0 -> -1 (the healing turn) | exit 1 at the test's reference check (entries 31–36, line 65) |
| M6b | M6 with that assertion removed | exit 1: earliest failing k = 31, kind checkpoint, field `winner_astrength` |
| M7 | lamp-burnout: `I hope` -> `I hopE` (burn-out, K = 125) | exit 1: earliest failing k = 125, kind transcript |
| M8 | lamp-burnout: checkpoint 125 `lamp_olight` 0 -> 1 | exit 1 at the test's reference check (`(lamp 125)`, line 67) |
| M8b | M8 with the `(lamp 125)`, `(lamp 132)` and entry-versus-end assertions removed | exit 1: earliest failing k = 125, kind checkpoint, field `lamp_olight` |
| M9 | lamp-burnout: checkpoint 60 `robber_hroom` CRAW1 -> MAZE1 (a mid-run thief position; the field is in `#:eof-classification-ignore-keys`) | exit 1: earliest failing k = 60, kind checkpoint, field `robber_hroom` (still compared at every entry) |
| M10 | lamp-burnout declares `#:eof-classification-ignore-keys '(robber_hroomx)` | exit 1 before any run: "end-of-input classification key robber_hroomx is not a compared reference checkpoint field" |

## Gameplay branches (`gameplay-branches.json`)

| Branch | Covering checks | Precision |
|---|---|---|
| `scoring.treasure-deposit` | treasure-deposit | one treasure taken and put in the case (ASCORE = RAW-SCORE + OTVALs); several treasures and taking one out of the case are not exercised |
| `timers.cure-clock-recovery` | cure-recovery | one light wound healed; several wounds (CURIN re-armed per point) not exercised |
| `timers.lamp-burnout` | lamp-burnout | the lamp on and carried throughout; turning it off to pause the clock, the countdown away from the hero and moving in the dark are not exercised |

Not newly covered:

* `combat.thief` stays UNCOVERED. Its description asks for the thief to
  fight, steal and be fought; thief-robbery (gated) shows only the stealing
  (from the hero, and from the room at prefix 12's end of input). The note
  cites it. Splitting the branch would be a change of the required list, a
  maintainer decision.
* `timers.other-clock-events` stays UNCOVERED: LNTIN and CURIN are the only
  CEVENTs any scenario queues (the Phase 3 checkpoints record the whole
  CLOCKER list every turn).

## make m4-check

`PLTCOLLECTS=":$PWD" TMPDIR=/tmp PYTHONPATH=.sandbox-pydeps/lib make m4-check
PYTHON=/usr/bin/python3`, exit 0, 577 s, at commit `81d963e` (clean tree).
Manifest completeness PASS; `sources` and all eighteen scenario targets PASS
(the new ones: treasure-deposit 11.8 s, thief-robbery 124.4 s, cure-recovery
6.4 s, lamp-burnout 7.4 s), `test-m4-replay-persistence` PASS,
`test-m3-session` and `test-m3-launcher` PASS.

| Term | Status | Scope / reasons |
|---|---|---|
| SCENARIO_PARITY | PASS | 18 scenarios, each under one fixed clock and seed (250776000, UTC); per scenario, not gameplay coverage |
| GAMEPLAY_RELIABILITY | NOT YET | 17 of 23 required branches covered (was 14; PROVISIONAL list); uncovered: combat.thief, timers.other-clock-events, objects.puzzles-beyond-the-house, save.game-save-command, save.game-restore-command, save.player-facing-resume; open blockers INV-06, INV-07 |
| PLAYABLE | NOT RUN | sub-checks only; no PLAYABLE gate |
| FULL_COMPLETION | NOT RUN | no complete-game check |
| M4_ACCEPTED | NOT YET | R2–R5 unmet |

A local branch result, not a mainline acceptance.

## Security and licensing

No runtime code changed. The runner gained one opt-in option (default unchanged). The new test files,
checkpoint module and probe profile are test infrastructure; no new file
access (the guard shows no write or delete attempt). Native runs used
disposable `$TMPDIR` copies only; `.cache/upstream` was not written; mdli was
not rebuilt. Confusion (GPLv3) was used only as a behaviour reference; no
Confusion code was copied. New scripts and tests are original MIT-0 code.

## Open risks and limits

- Each scenario is one fixed clock and seed; other seeds take other branches
  (the thief may take the painting on the deposit route, or not on the
  robbery route).
- robber_hroom does not decide reboots in three of the four scenarios (above); the thief's end-of-input moves are executed by this runtime only in thief-robbery and in per-prefix mode.
- HROOM's RID rendering covers only the PNAMEs observed (`!` escaped); another unsafe PNAME fails strictly.
- lamp-burnout's reference is 4.1 MB; its per-prefix run is about 20 minutes.
- The four single-run targets add about two and a half minutes to `make
  m4-check` (thief-robbery's 21 boots: 124 s of the 150 s). CI's m4-check
  step has a 40-minute budget; this local run took 577 s in all.
- The Phase 3 references drop the Dkk logs (hash and size kept); an auditor
  who wants them re-runs the probe (deterministic, 2 minutes in all).

## Next actionable task

Phase 3 continues with the objects branch beyond the house (the dam, the
boat, the balloon, the coal mine) and a thief fight; the maintainer may
decide whether `combat.thief` should be split into stealing and fighting.
