# S8-SESSION-CLOCK — session-owned host clock and time zone (issue #135 part 1)

**RID**: S8-SESSION-CLOCK (local task record; the orchestrator owns the issue/PR)
**Branch**: feat/m3-session-clock
**Base commit**: 8e3d103 (tip of PR #141 with review fixes). Changes are uncommitted
when this record was written; the orchestrator reviews and commits.
**Upstream SHAs (sources.lock.json)**: mdlzork bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3;
MITDDC/zork d94501340842e006791fce0757dc0043b8ec8916
**Toolchain**: Racket v7.9 [bc]; host zone CET (offset +3600 at the test epoch)
**Decision**: [ADR-0052](../../DECISIONS.md). **Specification**: SEMANTICS "M3
session-owned host clock and time zone (issue #135; ADR-0052)", written before the code.

## Design

- `make-mdl-session root #:clock c #:time-zone z`. The default `c` is `real-mdl-clock`,
  the same `current-inexact-milliseconds` read as before. The default `z` is `'local`.
  Both are stored in the session's atom space (new `atom-space` fields `clock` and
  `time-zone`), next to the RANDOM state. They are not process-global parameters.
  `make-mdl-context` and `make-mdl-atom-space` accept the same keywords.
- `mdl/runtime/clock.rkt` provides:
  - `make-mdl-clock thunk`: the thunk returns `(values seconds micros)`;
  - `make-fixed-mdl-clock seconds #:micros m`, a constant instant;
  - `real-mdl-clock`, `mdl-clock?` and `mdl-clock-now`.
  Every read is validated: seconds must be a signed 36-bit integer and micros must be in
  0..999999. Otherwise it is a strict error.
- The fixed clock never advances. This matches the reference shim
  `scripts/reference/fixed_time.c` (PR #131 worktree, commit e616ac0). Its `gettimeofday`,
  `time` and `clock_gettime(CLOCK_REALTIME*)` return `MDL_FIXED_EPOCH` with `tv_usec`/`tv_nsec`
  = 0 on every call. Monotonic and CPU clocks are not frozen, and the child runs with `TZ=UTC`.
- Zone: a truthy second GETTIMEDATE argument still selects UTC. Otherwise the session
  zone decomposes both "now" and explicit timestamps, as `localtime_r` does under `TZ`.
  The default `'local` gives exactly the old results. The supported set is `'local` and
  `'utc` only.
- Only the no-argument (or FALSE) GETTIMEDATE reads the clock, once per call. No game
  source, global, or DSKDATE/START/RANDOM call site is touched.
- Host-only observation: `mdl-session-random-snapshot` returns a detached copy of the
  RANDOM state (`random36-state-copy`, `random36-state-words`).

## Proof chain and reference comparison

`tests/historical_clock_seed_test.rkt` (`make test-m3-clock-seed`) runs with the fixed
clock 250776000 and zone `'utc`:

| Quantity | This runtime | Native Confusion (Probe E) | Agreement |
|---|---|---|---|
| GETTIMEDATE now | [0 0 12 12 12 1977 0] | [0 0 12 12 12 1977 0] | yes |
| DSKDATE (game function) | 10438660480 | 10438660480 | yes |
| RANDOM state before START | default (#o267762113337, #o155256071112): nothing in the load draws RANDOM | — | — |
| START seed `<CHTYPE <DSKDATE> FIX>` | 10438660480 (= second word after START) | 10438660480 | yes |
| seeding call's value | 16566282405 | 16566282405 | yes |
| next 12 values (from a copy) | -21802663835 12914488375 -6577089531 34210328094 3437552668 13814526739 -20114144995 11990399124 31711279130 25894896720 24534915165 -5538612619 | same | yes |
| west `<PROB 80>` draw | `<MOD -21802663835 100>` = 65, so the brief text | 65, brief | yes |
| version line | `This version created December 12.` | same | yes |
| INTIME | 10438660480 | equal to the seed (three identical DSKDATE reads) | yes |

The reference values come from `docs/evidence/M3/CLOCK-SEED-REFERENCE.md` and
`clock-seed-probe.json`, produced by the separate reference investigator in worktree
`.claude/worktrees/probes`. They belong on branch evidence/m3-session-probes but are
**untracked, not committed**, as of this record. Their sha256 values are 66b5f5d2…9f89 and
0250e007…2854. The reference also gives two cases this runtime does not test:
- epoch 251036100 → seed 10439448712. This agrees with the DSKDATE formula; it was not run
  through this runtime.
- `TZ=America/New_York` → 10438624480. Named zones are deliberately unsupported here.

## Golden comparison (step 6)

A scratch run with `#:clock (make-fixed-mdl-clock 250776000) #:time-zone 'utc` matched
the approved candidate golden exactly in 3 of 3 runs. The comparison used
`canonical_text(ONLCR(raw))` against the golden with only the D1 lines removed, and no
date normalisation. `tests/historical_interactive_test.rkt` therefore:
- now builds its session from the golden's `fixed_epoch` and `tz`;
- no longer normalises the date line;
- compares `west` exactly, without the full-description alternative.

The golden file is unchanged (sha256 76edf0ad…00b8).

## Red → green (sandboxed, `export PLTCOLLECTS=":$PWD"`)

| Test | Red (base 8e3d103 + new test) | Green |
|---|---|---|
| `tests/session_clock_test.rkt` | exit 1: `make-fixed-mdl-clock: unbound identifier` | exit 0, 55 tests |
| `tests/historical_clock_seed_test.rkt` | exit 1: `make-fixed-mdl-clock: unbound identifier` | exit 0, 17 tests |
| `tests/historical_interactive_test.rkt` | (modified after green clock; earlier version accepted both `west` forms) | exit 0, 31 tests, 3 consecutive runs |

## Mutation checks (`session_clock_test.rkt`; each mutant applied alone, recompiled, restored)

| Mutant | Result |
|---|---|
| M1: "now" reads `real-mdl-clock` | killed, 23 failures |
| M2: session zone ignored | killed, 14 failures. Killed only because the host zone is not UTC. |
| M3: fixed clock advances 1 s per read | killed, 10 failures |
| M4: snapshot returns the live state | killed, 1 failure |
| M5: no micros validation on read | killed, 2 failures |

The first M4 run survived only because a stale `loader.zo` had inlined the old body across
modules. After `raco make`, the mutant was killed.

## Commands and exit statuses

| Command | Exit | Result |
|---|---|---|
| `raco test tests/session_clock_test.rkt` | 0 | 55 passed |
| `bash scripts/test_racket.sh` (sandbox) | 1 | 3/3244 failures, all `Read-only file system` on hardcoded `/tmp` in `loader_test`, `declaration_test` and `percent_read_test`. Sandbox only. |
| `bash scripts/test_racket.sh` (unsandboxed) | 0 | 3396 passed |
| `make test-m3-clock-seed` | 0 | 17 passed |
| `make test-m3-interactive` | 0 | 31 passed |
| `make test-m3-saveit` | 0 | 32 passed |
| `make test-m3-start-back` | 0 | 6 passed |
| `make test-historical` (sandbox) | 2 | `historical_vfload_test` hardcodes `/tmp`. Sandbox only. |
| `make test-historical` (unsandboxed) | 0 | passed |
| `git diff --check` | 0 | clean |

`make test-python` and the native reference (`make reference-*`) were **NOT RUN**. This
slice does not change Python tooling or the reference engine.

## Limitations and risks

- SMOKE_PARITY is still not claimed. The golden is a candidate, and this slice runs no
  strict SMOKE_PARITY comparison.
- On a UTC host, the default `'local` zone and `'utc` give the same results. There the
  smoke test cannot tell them apart; M2 is killed only on a non-UTC host.
- Named and offset zones are unsupported. The reference's America/New_York case is not
  reproducible here by design.
- The real clock still uses `current-inexact-milliseconds`, exactly as before.
- The reference evidence is not yet committed on its branch. Its file hashes are recorded
  above.
- README not updated: this slice is not a milestone gate. STATUS rows were updated.

## Security and licensing

The change is local host API only. It adds no network or web entry point, and no MDL
primitive exposes the clock or the RANDOM snapshot. No GPLv3 code was copied; the shim was
only read to confirm the behaviour to match. No upstream, provenance or license change.
