# Test strategy, reference capture, and parity contract

## Test layers

1. `make test-racket`: reader, bootstrap compiler, FALSE, atom/OBLIST,
   mutable sequences, type constructors, local/global bindings, the
   documented 36-bit FIX/WORD subset, and scoped M2 execution semantics
   (PROG/REPEAT/RETURN/AGAIN activations and function formals) on the
   explicitly supported subset. The target refreshes the linked `#lang mdl`
   module before tests so changed runtime exports are visible.
2. `python -m pytest -q tests/test_harness.py`: source lock, reference
   interchange format, exact comparator and transcript normalization.
3. `racket scripts/mdl_check.rkt ...`: syntax parse coverage on pinned
   historical source. Record file-by-file results; no unsupported syntax skips.
4. `make reference-build`: native Confusion compile (requires GC/libgc-dev).
5. `make reference-capture`: actual game run on pinned 1977 reconstructed save.
6. `make reference-probe`: run isolated Confusion primitive probes through stdin. The native REPL has no prompt; each case ends with `<QUIT>`. Raw output, stderr, and exit code are captured for review.
7. `python scripts/compare_transcripts.py REF CAND`: strict differential
   transcript comparison (once a candidate game engine is available).
8. Future: state diff, randomized test corpus, complete 500-point game, browser.

The M1 gate also runs `tests/integration_test.rkt` for structural
versus identity equality and left-to-right argument evaluation. Three
matching Confusion cases are saved under `docs/evidence/M1/integration-*`.
See `docs/evidence/M1/GATE.md` for the merged gate matrix and exact
commands. This is a semantic micro-runtime gate, not a Zork gameplay gate.

The first M2 slice runs `tests/prog_test.rkt` and a `#lang mdl` fixture for
unnamed PROG auxiliaries and bare RETURN. Focused Confusion cases and expected
errors are under `docs/evidence/M2/prog-*`; see `PROG.md` there for commands,
reference hashes, the deliberately nonzero expected-error probe suite, a
separate Confusion signal-11 crash during auxiliary initialization, and
unsupported activation behavior. These tests do not satisfy the full M2 gate.
Issue #22 adds `module+ test` checks in `mdl/runtime/core.rkt` for activation
identity, ownership, stale-frame rejection, and cleanup on return or error.
Issue #23 adds bounded `tests/equality_cycle_test.rkt` checks so pre-fix
unbounded recursion cannot hang the suite. Confusion timeout and crash cases
are saved separately from successful observations under `docs/evidence/M2/`.
Issue #26 adds `tests/repeat_test.rkt` for unnamed REPEAT and bare AGAIN,
including auxiliary initialization once, PROG restart, nested RETURN,
function ownership, stale-frame rejection, and a 1,000-step stack check.
Focused native inputs and results are under `docs/evidence/M2/repeat-*`.
Issue #28 adds `tests/activation_target_test.rkt` for named PROG/REPEAT,
ACTIVATION/FRAME type reporting, name visibility during auxiliary binding,
explicit RETURN/AGAIN across nested and called functions, and wrong-type or
stale-target rejection. Eleven successful Confusion observations and six
separate error/crash observations are under `docs/evidence/M2/activation-target-*`.
The function-formals slice adds `tests/formals_test.rkt` for OPTIONAL, AUX,
TUPLE, and ARGS sections, in-frame defaults, unassigned optional/aux reads,
TUPLE type/primtype/equality behavior, historical arity error names, and
compile-time rejection of malformed formal lists; binder invariants are in
`mdl/runtime/core.rkt`'s test submodule. Twenty-four successful Confusion
observations and eleven error observations are under
`docs/evidence/M2/formals-*`; see `FORMALS.md` there for the compile-time
validation deviation.
The control slice adds `tests/control_test.rkt` for activation formals
(leading ATOM and `"NAME"`/`"ACT"`), explicit RETURN/AGAIN to a function's
own activation, bare transfers skipping function frames, GO labels and
transfers, and UNWIND cleanup on transfers and errors; frame, GO, and UNWIND
invariants are in `mdl/runtime/core.rkt`'s test submodule. Sixteen
successful Confusion observations and seven error observations are under
`docs/evidence/M2/control-*`; see `CONTROL.md` there for the GO and
UNWIND-on-error reference deviations.
The macro slice adds `tests/macro_test.rkt` to `make test-racket` for DEFMAC,
FORM, EXPAND, quoted formals, caller-frame argument evaluation, ARGS/TUPLE,
and an expansion that defines a function. Twenty-five successful Confusion
observations and eight deliberate error observations are under
`docs/evidence/M2/macro-*`; see `MACROS.md` there for commands, hashes,
and reference deviations. The full M2 gate remains open.

## Frozen 1977 baseline

The archived MIT source omits some components required to run the game.
`heasm66/mdlzork` supplies a patched reconstruction and a prebuilt
`SAVEFILE/ZORK.SAVE` image; this is **not** the original archival binary.
A Confusion baseline is independently verified only when its build and
interactive command playback succeed.

Commands:

```bash
make sources
make reference-build
python scripts/reference_runner.py capture \
  --scenario tests/scenarios/house.json \
  --output artifacts/reference/house.json
```

The runner uses a PTY because the original reader expects terminal behavior.
It waits for a `>` prompt. Timeouts, unexpected early exits, and missing
binaries are failures, not passing tests. If the prompt protocol differs on
some platform, fix the PTY bridge with documented, tested input handling.
The M0 baseline was built and captured locally and in CI; see the M0 report.

## Transcript JSON schema v1

```json
{
  "schema_version": 1,
  "engine": "confusion-patched-1977",
  "scenario": "house-smoke",
  "initial_output": "...",
  "complete": true,
  "commands": [
    { "input": "look", "output": "...", "prompt_returned": true }
  ]
}
```

Reference captures additionally record interpreter image SHA256, game image
SHA256, timestamp, exit status, and errors. A Racket candidate must produce
identical `scenario`, command order, initial output, and per-command output
fields, plus `complete=true`; the `engine` and binary hashes may differ.
Future captures can include read-only `state` snapshots for deeper tests.

### Normalization

The current reference runner removes PTY ANSI SGR/control sequences matching
`ESC [ digits/semicolon <letter>` and normalizes CRLF/CR to LF. It does **not**
strip spaces, remove prompt text from responses (beyond the consumed `>`),
reword descriptions, ignore score differences, or normalize random behavior.
Any further normalization must be explicit and reviewed, with a negative test.

### Golden approval and evidence

Do NOT auto-update goldens when assertions fail. Review the output manually,
record the SHA256 and captured source commits, and only then copy a curated
fixture to `docs/evidence/<milestone>/`. Failed capture JSON belongs in
`artifacts/` and must not be treated as truth. Avoid including private data,
credentials, or host paths in published evidence.

M0's locally reviewed and maintainer-approved fixture is
`docs/evidence/M0/house-golden.json`; hashes, exact command sequence, output
review, timestamp limitation, and PTY exit behavior are in
`docs/evidence/M0/REPORT.md`. The second observed capture matched the first
except for `captured_at`. Rebuilding native Confusion changes its banner's
compile timestamp and thus the exact `initial_output` field.
Approval was given in the Codex conversation on 2026-11-17 for the fixture
with SHA256 `ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.

## Cross-engine limitations

Random NPC actions, runtime timing, and historical save/restore features may
produce legitimate nondeterminism. Deal with that through controlled seeds,
instrumentation, or scenario design rather than weakening strict comparisons.
The earliest endgame is incomplete in some variants; the playable December
1977 reconstruction is documented as a 500-point game.
