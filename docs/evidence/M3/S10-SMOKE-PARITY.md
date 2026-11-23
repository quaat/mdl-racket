# S10-SMOKE-PARITY — deterministic fresh-boot comparison (WP2; issues #131/#135)

**RID**: S10-SMOKE-PARITY (local task record; the orchestrator owns the issue/PR and commits)
**Branch**: feat/m3-smoke-parity, base `a4e72ba` (changes uncommitted when this record was written)
**Decision**: [ADR-0053](../../DECISIONS.md) (proposed), building on ADR-0050 (D1/D2/D3) and
ADR-0052 (session clock)
**Upstream SHAs (`sources.lock.json`)**: mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`
(checked-out HEAD equal, clean); MITDDC/zork `d94501340842e006791fce0757dc0043b8ec8916`
**Native reference**: `.cache/build/confusion_patched/mdli` sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` (pinned build, not rebuilt;
`make reference-build` was not run)
**Clock shim**: `scripts/reference/fixed_time.c` sha256 `d1fa8652…ab925`; scenario
`tests/scenarios/house-boot.json` sha256 `b1f9d961…74df7` (fixed_epoch 250776000, TZ UTC)
**Toolchain**: Racket v7.9 [bc]; /usr/bin/python3 3.9.2 (pytest/pexpect from `.sandbox-pydeps`);
gcc 10.2.1. All runs inside the Claude Code sandbox, `PLTCOLLECTS=":$PWD"`.

## What changed (tooling, tests and docs only; nothing under `mdl/` or `.cache/`)

| File | Change |
|---|---|
| `scripts/smoke_parity.py` (new) | The single comparator `compare_records`. It builds the candidate record from raw run facts, applies D1/D2, and checks D3 termination. CLI: `run`, `candidate`, `compare`, `native`. |
| `scripts/m3_house_boot_run.rkt` (new) | Runs this runtime on the scenario (`mdl-session-load!` + `mdl-session-run-interactive "SAVE-IT"`, fixed clock, UTC, LF input, no echo) and emits the raw facts as JSON. It compares nothing. |
| `scripts/m3_check.py` (new), `Makefile` | `make m3-check`, `make m3-native-parity`; `test-python` now includes `tests/test_smoke_parity.py`. |
| `scripts/boot_reference.py` | Record schema 2 → 3: `provenance.immutable_inputs` and `provenance.save_artifacts`. The capture fails if the run writes anything else. `compare` delegates to the single comparator; `compare_gameplay` was removed. |
| `tests/test_smoke_parity.py` (new), `tests/test_boot_reference.py` | Comparator positive and negative checks; schema-3 provenance tests; the native test is updated. |
| `docs/evidence/M3/S10-house-boot-reference.json` (new) | Fresh schema-3 Confusion capture, from a disposable copy. |
| `docs/evidence/M3/S10-racket-house-boot-run.json` (new) | Raw facts of one run of this runtime. It is the base of the comparator unit tests; it is not a golden. |
| `.github/workflows/reference.yml` | The `make m3-check` step runs before the native build, so its native stage is NOT RUN. The `make m3-native-parity` step runs after `make reference-build`. Both steps have a time limit and a tee'd log; `artifacts/m3/` is uploaded. The job limit goes from 30 to 45 min. |
| `docs/DECISIONS.md` (ADR-0053), `docs/TESTING.md`, `BOOT-REFERENCE.md`, `S7-frontier/INTERACTIVE-FRONTIER.md` | Contract; the RNG claim and the MADADV.SAVE input claim are corrected. |

Unchanged: `tests/scenarios/house.json` and its saved-image reference, and
`tests/fixtures/house-boot-golden.json` (sha256 `76edf0ad…`). The approved
`docs/evidence/M3/house-boot-candidate.json` also stays as it was: sha256 `eb194115…`,
schema 2, never regenerated.

## Comparison contract (ADR-0053)

There is one comparator, `scripts/smoke_parity.py: compare_records(expected, actual)`.
The only allowed presentation differences are these:

- **D1**: the reference `boot_output` must start with `LISTENING-AT-LEVEL 1 PROCESS 1\n` and
  contain `"DONE"\n` exactly once. Both lines are removed once, and from the reference only. The
  REP print of `,NULL` (the blank line after `This version created December 12.`) is compared.
- **D2**: the candidate becomes `canonical_text(ONLCR(raw))`, then is split at `^>`, the
  reference's own prompt rule. The reference already holds `canonical_text` of PTY bytes, where
  the line discipline applied ONLCR. No CR or ESC may remain in compared text.

Everything else is compared exactly:

- scenario, `fixed_epoch`, `tz`, entry forms;
- command inputs: order, missing and extra commands;
- the boot text and all six responses, byte for byte;
- the date line (exactly one, identical);
- the score line (points, total, moves), with moves equal to the number of commands;
- the candidate's `MOVES` global, which must equal its score line.

**Termination (D3).** The candidate must end with exactly one mirrored empty read
(`Beg pardon?` and `>`), then `exn:fail:mdl-input-exhausted` with the exact ADR-0050 message.
All input must be consumed, the load must be PASS 1229/0, the events must be
`entry-returned`, `pass`, and the game directory must be unchanged. This is input exhaustion,
not a user QUIT. The reference PTY capture stops at the last prompt, so the tail is checked
against its exact expectation.

**Tamper check.** Every compared candidate field is re-derived from `run.raw_output`.

## Results

### Fresh native capture vs committed record vs this runtime (strict, D1/D2 only)

Fresh capture (disposable `$TMPDIR` copy, never `.cache/upstream` as cwd):

```
python3 scripts/boot_reference.py capture --scenario tests/scenarios/house-boot.json \
  --output docs/evidence/M3/S10-house-boot-reference.json --timeout 90     -> exit 0, 6 turns
```

| Comparison | Result |
|---|---|
| committed `house-boot-candidate.json` (schema 2) vs fresh `S10-house-boot-reference.json` (schema 3) | **PASS**, 0 mismatches |
| committed reference vs this runtime (`S10-racket-house-boot-run.json` → candidate record) | **PASS**, 0 mismatches |
| fresh reference vs this runtime | **PASS**, 0 mismatches |
| `make m3-check` live: this runtime vs committed; fresh native vs committed; this runtime vs fresh native | **PASS** each (`artifacts/m3/*.json`) |
| live run's raw facts vs committed `S10-racket-house-boot-run.json` | identical (whole JSON) |

No mismatch appeared, so no normalisation was added. In this runtime the run ends by
`input-exhausted` (D3), with 6 commands answered, MOVES 6 and `0 [total of 500 points], in 6
moves.`

Provenance of the fresh capture:

- The immutable game files equal the approved capture's `boot_input_state.files` minus
  `MDL/MADADV.SAVE`, byte for byte; aggregate `a9eba087…8053`.
- `MDL/MADADV.SAVE` is a SAVE artifact: its before hash is `6293a39f…` (the upstream file),
  and its after hash differs between identical captures (three captures, three hashes: Confusion's
  heap image). The after hash is recorded and never compared.
- No other file was written; the capture enforces this.

### Clock → seed → RNG

`west` is RNG-dependent: ROOM-INFO's `<OR ,BRIEF!-FLAG <PROB 80>>` (`77rooms.mud:521-525`).
Under the fixed clock its draw is `<MOD <RANDOM> 100>` = 65 ≤ 80, so the brief text is printed
(`tests/historical_clock_seed_test.rkt`; reference: [CLOCK-SEED-REFERENCE.md](CLOCK-SEED-REFERENCE.md),
[clock-seed-probe.json](clock-seed-probe.json); S8: [S8-SESSION-CLOCK.md](S8-SESSION-CLOCK.md)).
This corrects #131's claim that the scenario has no RNG-visible output; see BOOT-REFERENCE.md,
"S10 corrections".

### Negative checks (each must FAIL the comparator): `tests/test_smoke_parity.py`

All of these fail the comparator on the named check, as required. The tests pass.

| Mutation (applied to the raw run facts unless stated) | Failing check(s) |
|---|---|
| date line `December 12.` → `December 13.` | `boot_output`, `date_line` |
| `west` → full West of House description (the `PROB 80` false branch) | `command[1] 'west'` only, at offset 0 |
| `Taken.` → `Taken!` | `command[3] 'take leaflet'` at offset 5 (exact bytes reported) |
| missing command (`inventory` dropped) | `command_inputs` (+ outputs) |
| extra command (`look`) | `command_inputs` |
| reordered commands | `command_inputs` |
| `in 6 moves` → `in 7 moves` | `score_line`, `command[5] 'score'`, MOVES≠score line |
| MOVES global 7 (text unchanged) | `actual-record` (MOVES differs from score line) |
| score points 0 → 10 | `score_line` |
| incomplete: output cut after `take leaflet`, outcome `timed-out` | not D3, incomplete run, missing `command[4]`/`[5]`, `complete` |
| outcome `error` / `returned` (e.g. QUIT) | `actual-record`: not D3 input exhaustion |
| input exhausted but no `Beg pardon?` tail | `actual-record`: D3 tail |
| unconsumed input | `actual-record` |
| `,NULL` blank line removed (D1 not widened) | `boot_output` |
| `"DONE"` line in candidate (not stripped) | `boot_output` |
| reference without `"DONE"` | `expected-record` (D1 needs exactly 1) |
| raw CR dropped (`boarded\r\n` → `boarded\n`) | `boot_output` |
| trailing space added | `command[2] 'open mailbox'` |
| edited candidate field, raw unchanged | `actual-record`: edited record |
| fresh reference with full `west` text (reference vs reference) | `command[1] 'west'` |
| `fixed_epoch` / `tz` changed | `fixed_epoch` / `tz` |
| unknown engine | `ParityError` |

**Comparator mutants** (each applied alone to `scripts/smoke_parity.py`, the tests run, the file
restored and checked with `cmp`): date substitution in the view; accepting the full `west` text;
no D3 kind check; D1 stripping on the candidate too; trailing-whitespace folding; D2 without
ONLCR; no tamper check; no score/moves check; no MOVES-global check. **All are killed** (pytest
exit 1; 1–15 failures each).

**Red → green, provenance split.** With the new tests and the HEAD `boot_reference.py`
(schema 2) swapped in: `pytest tests/test_boot_reference.py` → exit 1, `6 failed, 5 passed`.
With the new code: `11 passed` (plus the native test below).

### Commands and exit codes

| Command | Exit | Result |
|---|---|---|
| `pytest -q tests/test_smoke_parity.py` | 0 | 31 passed |
| `make test-python PYTHON=/usr/bin/python3` | 0 | 65 passed, 1 deselected (native) |
| `pytest -q -m native tests/test_boot_reference.py` (2 fresh captures) | 0 | 1 passed |
| `make m3-check PYTHON=/usr/bin/python3` | 0 | 7/7 PASS (below) |
| `python3 scripts/m3_check.py --native skip --stages comparator-unit-tests,native-fresh-capture-parity` | 0 | native **NOT RUN**, overall PASS |
| `MAKE=false python3 scripts/m3_check.py --stages sources,comparator-unit-tests` | 1 | `sources` FAIL → overall FAIL (nonzero exit demonstrated) |
| `bash scripts/test_racket.sh` | 1 | `3/3244 test failures`, all `Read-only file system; errno=30` on hard-coded `/tmp` (`loader_test`, `declaration_test`, `percent_read_test`), the known sandbox-only failures; no `.rkt` under `mdl/` or `tests/` changed |
| `git diff --check` | 0 | clean |

`make m3-check` output (2026-11-23, sandbox, mdli present):

```
m3-check: sources                            PASS     exit=0 0.1s
m3-check: test-m3-saveit                     PASS     exit=0 7.8s
m3-check: test-m3-clock-seed                 PASS     exit=0 7.9s
m3-check: test-m3-interactive                PASS     exit=0 8.2s
m3-check: comparator-unit-tests              PASS     exit=0 0.3s
m3-check: candidate-vs-committed-reference   PASS     exit=0 7.5s
m3-check: native-fresh-capture-parity        PASS     exit=0 1.6s
m3-check: overall PASS; report artifacts/m3/m3-check.json
```

The machine-readable report (`artifacts/m3/m3-check.json`, gitignored) records:

- each stage's status, exit code, duration, commands and log;
- the git commit and a dirty flag;
- the source-lock SHAs and the mdli sha256;
- the comparison contract and the limitations.

The CI workflow change has not been run on GitHub: **NOT RUN**.

## What is and is not claimed

**Claimed (technical evidence):** under the fixed clock 250776000 and TZ UTC, this runtime
matches the unchanged pinned Confusion. It runs the unchanged 1977 source on the faithful
`run.mud` path. The six house-boot commands produce the same output byte for byte, modulo only
D1 and D2. That covers the boot text, the date line, the RNG-dependent `west` response, every
other response, and `0 points … in 6 moves`. The match holds against the committed approved
record and against a fresh native capture. The run ends by documented D3 input exhaustion.

**Not claimed:**

- PLAYABLE;
- any other command sequence or scenario;
- play under the real wall clock or a non-UTC zone;
- save/restore, QUIT, death or error paths;
- Confusion's own end-of-input behaviour (`Error: Unexpected EOF`), which is not compared;
- CI results (the workflow is not run yet);
- `make test` outside the sandbox.

The approved candidate remains a CANDIDATE, not a strict golden. Promoting it, or replacing it
with the schema-3 capture, needs the maintainer.

## Security and licensing

- The runner is a local Racket script with explicit string ports. It exposes no evaluator, opens
  no socket, and opens the game directory read-only; the listing is checked unchanged.
- Native captures run in a disposable `$TMPDIR` copy, and the shim is compiled there.
- No GPLv3 Confusion code was copied. Confusion was used only as a binary reference.
- No license, upstream provenance or deployed service changed.

## Risks

- The schema-2 committed record keeps the documented `MADADV.SAVE` flaw until the maintainer
  decides whether to promote the schema-3 capture.
- The CI job now repeats the three `test-m3-*` targets inside `m3-check`, so the job limit was
  raised to 45 min. Its timing on GitHub is unmeasured.
- `scripts/test_racket.sh` has 3 sandbox-only `/tmp` failures (see the table above); an unsandboxed `make test` was NOT RUN.

## Recommended gate result

**SMOKE_PARITY: PASS (scoped to the house-boot scenario under the fixed clock, UTC)**. Grounds:

- The strict comparator has zero mismatches across all three pairings.
- The binary-free comparison runs in `make m3-check`.
- The fresh native capture agrees.
- The comparator itself is guarded by 22 negative tests and 9 killed mutants.

The orchestrator and maintainer decide the claim. If the gate requires the CI run, or an
unsandboxed `make test`, it stays **BLOCKED** until those have run.
