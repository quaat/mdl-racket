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
| Ours | Racket v7.9 [bc]; the shared runner `tests/m4_scenario_runner.rkt`, unchanged; guarded (no write or delete, empty cwd, game-directory hashes unchanged) and watchdogged |

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

## Checkpoint profile "timers" (probe generalised, runner unchanged)

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

**The thief's end-of-input move.** The ROBBER demon moves the thief's HROOM
on every turn, the end-of-input turn included (the documented single-run
coverage loss, docs/TESTING.md). With HROOM in the checkpoint every shorter
prefix except k = 0 is non-standard and re-run (one boot each).
thief-robbery compares HROOM everywhere (21 boots). treasure-deposit,
cure-recovery and lamp-burnout declare `#:ignore-keys '(robber_hroom)`
(checkpoint `timers-checkpoint/no-hroom`): HROOM is not compared there, the
thief's room, HFLAG and bag are. The full comparison was run once for
treasure-deposit (single-run, 19 boots, 117 s, exit 0) and cure-recovery
(single-run, 35 boots, 227 s, exit 0) before the declaration was added
(treasure-deposit's test as committed in `e4c1f02`; cure-recovery's the
same test with `timers-checkpoint`, not committed in that form);
lamp-burnout's (131 boots) was not run.

## Results

RESULTS-PLACEHOLDER

## Mutation checks (each reverted; `git status` clean afterwards)

Native mutations change one byte in every reference transcript from the key
turn on (the prefix stdouts P_k, k >= K, and T1; their sha256 updated so the
integrity check passes). Checkpoint mutations change one field of diagnostic
checkpoint K; the "a" variant shows the test's own reference assertion
failing first, the "b" variant comments out the asserting lines so that the
runner itself has to find it. Every mutation and test edit was reverted with
`git checkout`; `git status` was clean after each.

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

M4CHECK-PLACEHOLDER

## Security and licensing

No runtime code changed, and the runner is unchanged. The new test files,
checkpoint module and probe profile are test infrastructure; no new file
access (the guard shows no write or delete attempt). Native runs used
disposable `$TMPDIR` copies only; `.cache/upstream` was not written; mdli was
not rebuilt. Confusion (GPLv3) was used only as a behaviour reference; no
Confusion code was copied. New scripts and tests are original MIT-0 code.

## Open risks and limits

- Each scenario is one fixed clock and seed; other seeds take other branches
  (the thief may take the painting on the deposit route, or not on the
  robbery route).
- robber_hroom is not compared in three of the four scenarios (above).
- lamp-burnout's reference is 4.1 MB; its per-prefix run is about 20 minutes.
- The four single-run targets add about two and a half minutes to `make
  m4-check` (thief-robbery's 21 boots dominate).
- The Phase 3 references drop the Dkk logs (hash and size kept); an auditor
  who wants them re-runs the probe (deterministic, 2 minutes in all).

## Next actionable task

Phase 3 continues with the objects branch beyond the house (the dam, the
boat, the balloon, the coal mine) and a thief fight; the maintainer may
decide whether `combat.thief` should be split into stealing and fighting.
