# M4 S9: IMAGE, SLEEP and TIME (issues #168, #169, #170; scenarios `mirror-bat`, `strange-passage`)

Date: 2026-11-24. Branch `feat/m4-image-sleep-time` at `main` `9f16d47`.
Upstream mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`, mit_zork
`d94501340842e006791fce0757dc0043b8ec8916` (`sources.lock.json`). Pinned mdli
sha256 `6df359f6…b789` before and after every capture (never rebuilt). Racket
v7.9 [bc], Python 3.9.2.

Result: **IMAGE, SLEEP and TIME implemented per the maintainer decisions;
scenario `mirror-bat` PASS (all 38 prefixes, k = 0..37) and scenario
`strange-passage` PASS (all 32 prefixes, k = 0..31): transcripts byte for byte
(D1 only; the Bat Room's three BEL bytes included) and every end checkpoint
equal to the pinned native reference (branch evidence, scenario-scoped, one
seed).** No further divergence was found on either path, so no frontier entry
was added. Inventory rows INV-02, INV-03 and INV-04 are fixed. Not a
PLAYABLE claim and not the M4 gate.

## Decisions (issue comments, 2026-11-24; final)

* #168 IMAGE: emit the exact byte (BEL appears in transcripts as natively).
* #169 SLEEP: wait for real only on live clocks (real, resumed, recording over
  a live source); return at once under fixed, replaying and recording-over-fixed
  clocks; never read or advance the session clock; same value in every mode.
* #170 TIME: a session-derived FLOAT with no clock read, documented deviation.

## Semantics (docs/SEMANTICS.md "M4: IMAGE, SLEEP, TIME (#168–#170)", written before the code)

* `<IMAGE code [channel]>`: FIX 0–127; writes exactly that byte (control
  characters raw) to a session PRINT channel (default LVAL OUTCHAN); returns
  `code`. Strict: arity, non-FIX, codes outside 0–127 (reference writes code
  mod 256 — recorded deviation, ADR-0050/0057), non-PRINT/non-CHANNEL channels
  (reference: silent / host error — recorded deviations).
* `<SLEEP seconds [unhang]>`: non-negative FIX (FLOAT refused, as the reference;
  the manual allows it); returns T always; waits through the host-only
  `current-mdl-sleeper` (default Racket `sleep`, breakable) only when
  `mdl-clock-live?` of the session clock is true; any SLEEP of more than 0
  seconds first flushes the terminal output ports, in every mode (so its errors
  are mode-independent). UNHANG accepted (no MDL interrupt can arrive during the
  wait). No clock read or observation.
* `<TIME arg ...>`: arguments evaluated and ignored; returns the FLOAT n.0 for
  the n-th TIME call of the session (counter in the atom space). Chosen because
  it reads no clock, is reproduced exactly by replay, and keeps every native
  property the game or a program can rely on (FLOAT, positive, true,
  non-decreasing, successive calls not `==?`); the magnitude is calls, not CPU
  seconds.
* `mdl/runtime/clock.rkt`: `mdl-clock-live?` (real yes; fixed no; custom per
  `make-mdl-clock … #:live?`, default no; recording as its source; replaying
  no; resumed yes — read per call, so a finished replay becomes live).
* ADR-0052 amendment and ADR-0061 note in `docs/DECISIONS.md`; checkpoint
  format unchanged.

## Reference probes

[P0PRIMS-REFERENCE.md](P0PRIMS-REFERENCE.md), `p0prims-probe.json` (48
bare-mdli cases). Native: `<IMAGE 65>` writes `A`, returns 65; `<IMAGE 7>`
0x07; controls raw; codes ≥ 128 / negative written mod 256; `.INCHAN` silently
nothing; errors FIRST-ARG-WRONG-TYPE / TOO-FEW / TOO-MANY. `<SLEEP 1>` T after
1.01 s (fixed-clock shim too; GETTIMEDATE unchanged across it); FLOAT time
FIRST-ARG-WRONG-TYPE without waiting; negative ARGUMENT-OUT-OF-RANGE "SLEEP
time negative"; `<SLEEP 1 <>>` T. `<TIME>` FLOAT CPU seconds (0.0055),
arguments evaluated and ignored, `<G? <TIME> 0.0>` T, two calls not `==?`,
SLEEP consumes no CPU time. IMAGE, SLEEP, TIME are SUBRs.

The function-type probe was re-recorded with IMAGE, SLEEP, TIME
(`function-type-probe.json` sha256 `6d48dd72…2fb3`; 117 names, all SUBR). The
operator sweep was regenerated (`operator-head-sweep.json`: builtin 118 → 120,
missing 23 → 21; TIME leaves `root_name_data_refs`);
`tests/test_sweep_operator_heads.py` updated.

## Tests first (red, then green)

`tests/p0prims_test.rkt` (in `scripts/test_racket.sh`): IMAGE bytes, channels,
refusals; clock liveness of every mode; SLEEP under fixed / recording-over-fixed
/ replaying (no sleeper call, no clock read, no observation), under live clocks
(sleeper gets exactly the seconds; BELs written before each wait), refusals in
both modes, the real sleeper (`<SLEEP 1>` ≥ 0.95 s on the real clock) and a
break interrupting `<SLEEP 60>`; TIME values, arguments, truthiness, per-session
counter, no clock read.

* red (clock predicate and sleeper parameter present, builtins absent):
  `raco test tests/p0prims_test.rkt` → exit 1, `70/81 test failures`
  (`unassigned or non-applicable MDL operator IMAGE/SLEEP/TIME`);
* green: `81 tests passed`.

## Scenarios

[MIRROR-BAT-REFERENCE.md](MIRROR-BAT-REFERENCE.md) (77 pipe runs) and
[STRANGE-PASSAGE-REFERENCE.md](STRANGE-PASSAGE-REFERENCE.md) (65 pipe runs),
both by `scripts/probe_p0prims_scenario_reference.py`; each captured twice
(transcripts byte-identical; diagnostic logs identical).

* `mirror-bat` (F10, 37 commands): troll16, `north` `east` `se` `south` `se`
  `east` `se` `south` `se` `south` `look` `se`, `east` `sw` `rub mirror`,
  `west` `west` `north` `nw`, `west` (Bat Room), `look`. Native: three 0x07
  bytes then "A deranged giant vampire bat … lifts you away...." and MINE2;
  runs entering the Bat Room take 3.22–3.28 s natively. Ours: identical bytes,
  no wait (fixed clock; a recording fake sleeper is installed and must stay
  uncalled).
* `strange-passage` (31 commands): troll16, `south` `south` `east` `up` `sw`
  `east` `south` `ne`, `odysseus`, `north` (BLROO, room action TIME), `c-int`,
  `look`, `east`, `c-int`, `score`. Native: the cyclops flees; both `c-int`
  give "Nothing happens."; 45 points in 31 moves.

`tests/historical_mirror_bat_test.rkt` and
`tests/historical_strange_passage_test.rkt` (shared driver
`tests/m4_p0prims_scenario.rkt`, modelled on the cyclops-room test): reference
integrity, then for every prefix a guarded, watchdogged run ending by D3 input
exhaustion, raw output equal to the reference after D1 only, end checkpoint
equal (HERE, AOBJS, ASTRENGTH, ASTAGGERED, cyclops OROOM, TROLL/CYCLOPS/MAGIC/
MIRROR-MUNG/CAROUSEL-FLIP/CAROUSEL-ZOOM flags, sword OTVAL, RAW-SCORE, ASCORE,
MOVES, DEATHS), no host-sleeper call. Targets `make test-m4-mirror-bat`,
`make test-m4-strange-passage`; CI steps after the cyclops step.

`tests/replay_sleep_time_test.rkt` (run by `make test-m4-replay-persistence`):
mirror-bat recorded on a recording clock over the fixed source equals native
T1 with no sleeper call; the checkpoints before and after the bat have the
same 3 observations; restoring the post-bat checkpoint replays FWEEP without a
sleeper call, verifies, and pre-save + post-restore output = native T1
(restore 5.7 s); strange-passage checkpoint after `c-int` restores, the TIME
counter after restore (5.0) equals the recorded session's, and the output
equals native T1.

## Commands and results

| Command | Exit | Notes |
|---|---|---|
| `python3 -I scripts/probe_p0prims_reference.py docs/evidence/M4/p0prims-probe.json` | 0 | 48 cases; mdli sha256 unchanged |
| `python3 -I scripts/probe_function_type_reference.py docs/evidence/M4/function-type-probe.json` | 0 | IMAGE, SLEEP, TIME added |
| `python3 -I scripts/sweep_operator_heads.py docs/evidence/M4/operator-head-sweep.json` | 0 | builtin 120, missing 21 |
| `python3 -I scripts/probe_p0prims_scenario_reference.py mirror-bat …` (twice) | 0, 0 | 77 runs each; all checks true |
| `python3 -I scripts/probe_p0prims_scenario_reference.py strange-passage …` (twice) | 0, 0 | 65 runs each; all checks true |
| `raco test tests/p0prims_test.rkt` before the builtins | 1 | 70/81 failures (red) |
| `raco test tests/p0prims_test.rkt` | 0 | 81 passed |
| `raco test tests/function_type_test.rkt` | 0 | 338 passed |
| `pytest tests/test_sweep_operator_heads.py` | 0 | 6 passed |
| `racket tests/historical_strange_passage_test.rkt` | 0 | all 32 prefix runs match; 3 min 22 s |
| `racket tests/historical_mirror_bat_test.rkt` | 0 | all 38 prefix runs match; 4 min 7 s |
| `racket tests/replay_sleep_time_test.rkt` | 0 | 24 s |
| mutation 1: IMAGE writes `code xor 1`; `raco test tests/p0prims_test.rkt` / `racket tests/historical_mirror_bat_test.rkt` | 1 / 1 | 10/81 failures / prefixes 0–35 pass, prefix 36 fails at the transcript check |
| mutation 2: SLEEP waits regardless of liveness; same two | 1 / 1 | 5/81 failures (fake sleeper called) / prefixes 0–35 pass, prefix 36 fails at the no-sleeper check (`m4_p0prims_scenario.rkt:103`) |
| mutation 3: TIME reads the session clock; `raco test tests/p0prims_test.rkt` / `racket tests/replay_sleep_time_test.rkt` | 1 / 1 | 2/81 failures (counting clock read; replaying clock extra read) / part 1 passes, part 2 fails: extra observations in the checkpoint (`replay_sleep_time_test.rkt:143`) |
| mutation 4: P27 `Nothing happens.` → `Nothing happenz.` (strange-passage) and one of P36's three 0x07 bytes removed (mirror-bat), sha256 recomputed; both scenario tests | 1 / 1 | prefixes 0–26 pass, prefix 27 fails / prefixes 0–35 pass, prefix 36 fails, each at the transcript check (`m4_p0prims_scenario.rkt:231`); JSON restored (sha256 `29336459…`, `7c5ca890…` again) |

All mutations were reverted (`git show HEAD:<file> > <file>`; `git status` clean).

Final sequential runs on the slice (after all reverts):

| Command | Exit | Notes |
|---|---|---|
| `PYTHONPATH=.sandbox-pydeps/lib make PYTHON=/usr/bin/python3 test` (outside the sandbox: several pre-existing tests create directories directly under `/tmp`, read-only in the sandbox, where it exits 2 for that reason only) | 0 | 4850 Racket tests passed; pytest 74 passed, 1 deselected |
| `make PYTHON=/usr/bin/python3 test-historical` (outside the sandbox, same reason) | 0 | |
| `make PYTHON=/usr/bin/python3 test-m4-cyclops-room` | 0 | 41 prefixes (ABS regression path still matches) |
| `make PYTHON=/usr/bin/python3 test-m4-replay-persistence` | 0 | troll-combat persistence + `replay_sleep_time_test.rkt` |
| `make PYTHON=/usr/bin/python3 test-m4-mirror-bat` | 0 | 38 prefixes |
| `make PYTHON=/usr/bin/python3 test-m4-strange-passage` | 0 | 32 prefixes |
| `git diff --check` | 0 | |

## Security and licensing

Reference runs used disposable `$TMPDIR` copies; `.cache/upstream` was not
written; recorded paths are sanitized. No MDL evaluator is exposed; the
sleeper and the TIME counter are host-only. A live SLEEP blocks the session's
thread for the requested seconds (as natively) and is breakable; a server host
must bound sessions by other means (risk noted). Confusion (GPLv3) was used
only as a behaviour reference; no Confusion source was copied. The MDL manual
is cited from the public transcription (taradinoc/mdl-docs).

## Limits and next step

Scenario-scoped parity, one seed. Not compared: BOOM-ROOM `<FWEEP 7>` (six
BELs; covered by a unit test only), TIME's numeric value (never printed by the
game; deviation by decision), a live-clock game run that actually waits (unit
tests cover the live path with a fake sleeper and one real 1 s wait), IMAGE
codes ≥ 128 (strict here). Next: the remaining inventory items (INV-05
help/info, INV-06 restore) per the maintainer's ordering.

## Independent review (2026-11-24)

A read-only independent review of `origin/main...HEAD` found no defects.
Verdict: approve with nits. Changes made in response:

* **SLEEP errors depended on the clock mode.** The flush ran only before a
  live wait, so a port-less PRINT channel failed `<SLEEP 1>` on a live clock
  but returned T on a fixed one. SLEEP now flushes for every `seconds` > 0 in
  every mode. New test: a port-less context fails identically under the fixed
  and real clocks and never waits. It failed before the fix (1/83) and passes
  after.
* **The break test was timing-dependent.** It now breaks only after the real
  sleeper has signalled that the wait began, so it cannot pass by breaking
  context setup.
* **The flush test could not detect a missing flush.** It used an unbuffered
  bytes port. It now uses a port that buffers until flushed. Mutation check:
  replacing the flush with `(void)` gives 3/83 failures.

Kept as decided:

* A resumed clock is live whatever its wall source (maintainer decision
  #169). In production the wall is the real clock.
* `current-mdl-sleeper` stays a process-wide, host-only parameter. There is
  no multi-session host.
* Playing interactively with `zork/cli.rkt --fixed-clock` never pauses at the
  bat, per decision #169.
