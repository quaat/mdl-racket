# Test strategy, reference capture, and parity contract

## M3 NTH declaration checkpoint (2026-11-21)

Issue #96 adds `tests/nth_decl_test.rkt` to the Racket suite. Run
`TMPDIR=/tmp raco test tests/nth_decl_test.rkt` for focused repeated
Pattern, malformed-count, large-count, attached FUNCTION and NEWTYPE checks.
Run `make test`, `make m2-check`, then `make m3-source-progress` against the
locked upstream checkout. The last command exits 0 for a valid partial-load
measurement: inspect `artifacts/m3/source-progress.json` for the underlying
loader exit 1 and first failure. Native probes and frozen source results are
in [NTH-DECL.md](evidence/M3/NTH-DECL.md).

## M3 `%` read-time evaluation checkpoint (2026-11-21)

Issue #94 adds `tests/percent_read_test.rkt` to the explicit Racket
suite and a validator regression in `tests/test_m3_source_progress.py`.
The focused Racket test initially exited 1 because the first `%` made
the load fail; after two independent review corrections it exits 0
with 40 focused checks. The 22 clean pinned Confusion cases and eight
deliberate error observations are saved in
`evidence/M3/percent-read-*-reference.json`. Run:

```bash
TMPDIR=/tmp raco test tests/percent_read_test.rkt
make test
make m2-check
make m3-source-progress
```

The final target validates 188 original forms and zero skips but does
not certify a complete load. Its underlying loader exits 1 at the NTH
declaration Pattern in `77act1.mud` expression 10. A `read-eval`
failure is now a distinct allowed report stage. See
[`PERCENT-READ.md`](evidence/M3/PERCENT-READ.md).

## M3 `!\` CHARACTER checkpoint (2026-11-21)

Issue #92 adds `tests/space_character_test.rkt` with 12 focused
reader and runtime checks. Its first run exited 1 because the reader
made a SEGMENT; after implementation it exits 0. Five native Confusion
cases confirm the CHARACTER value and code. `make test` exits 0 with
1,160 Racket and 22 Python tests; `make m2-check` exits 0;
`make m3-source-progress` exits 0 with 157 completed, zero skipped
original forms. This source slice advances the failure location within
expression 23, but the completed-form count stays 157. The full loader
itself exits 1 at `%<STRING <ASCII 10>>` in `81tell-repl.mud`.
See [evidence](evidence/M3/SPACE-CHARACTER.md) and
[`source-progress-space-character.json`](evidence/M3/source-progress-space-character.json).

## M3 positional declaration metadata checkpoint (2026-11-21)

Issue #90 adds `tests/function_decl_metadata_test.rkt` with 13
focused checks. Its first run exited 1 at `expected atom-list/pattern
pairs`; after implementation it exits 0. Four clean and five
deliberately mismatched pinned Confusion cases establish that a
positional RSUBR-style declaration attached to FUNCTION is accepted
but not enforced. `make test` exits 0 with 1,148 Racket and 22
Python tests; `make m2-check` exits 0; `make m3-source-progress`
exits 0 with 157 completed, zero skipped original forms. The full
loader itself exits 1 at `!\ ` in `81tell-repl.mud` expression 23.
See [evidence](evidence/M3/FUNCTION-DECL.md) and
[`source-progress-function-decl.json`](evidence/M3/source-progress-function-decl.json).

## M3 custom WORD literal checkpoint (2026-11-21)

Issue #88 adds `tests/pstring_literal_test.rkt` with 14 focused
reader, runtime, AUX default and strict-error checks. Its first run
exited 1 after the parser split `#PSTRING 0` into two atoms. After
implementation it exits 0. `make test` exits 0 with 1,135 Racket
and 22 Python tests; `make m2-check` exits 0;
`make m3-source-progress` exits 0 with 144 completed, zero skipped
original forms. The full loader itself exits 1 at a function-style
declaration in `81tell-repl.mud` expression 10. See
[evidence](evidence/M3/PSTRING-LITERAL.md) and
[`source-progress-pstring-literal.json`](evidence/M3/source-progress-pstring-literal.json).

## M3 `%<>` read macro checkpoint (2026-11-21)

Issue #86 adds `tests/percent_empty_test.rkt` with eight focused
checks. Its first run exited 1 at an unsupported percent data node;
after implementation it exits 0. Six native Confusion probes cover
TYPE, truth, identity and source-shaped use. `make test` exits 0 with
1,121 Racket and 22 Python tests; `make m2-check` exits 0;
`make m3-source-progress` exits 0 with 136 completed, zero skipped
original forms. The full loader itself exits 1 at a three-element
typed AUX formal in `81tell-repl.mud` expression 2. See
[evidence](evidence/M3/PERCENT-EMPTY.md) and
[`source-progress-percent-empty.json`](evidence/M3/source-progress-percent-empty.json).

## M3 APPLICABLE declaration checkpoint (2026-11-21)

Issue #84 adds `tests/applicable_decl_test.rkt`: 16 focused checks for
callable and noncallable values, OR and structured Patterns, attached
declaration checking, and strict unknown types. Its first run exited 1
at unknown APPLICABLE; after implementation it exits 0. `make test`
exits 0 with 1,113 Racket and 22 Python tests; `make m2-check` exits 0;
`make m3-source-progress` exits 0 with 112 completed, zero skipped
original forms. The full loader itself exits 1 at the `%<>` data
construct in `77makstr.mud` expression 6. See
[evidence](evidence/M3/APPLICABLE-DECL.md) and
[`source-progress-applicable-decl.json`](evidence/M3/source-progress-applicable-decl.json).

## M3 quoted OPTIONAL default checkpoint (2026-11-21)

Issue #82 adds focused `DEFINE`/`DEFMAC` binding tests in
`tests/quoted_optional_test.rkt` against six pinned Confusion cases.
`make test` exits 0 with 1,097 Racket checks and 22 Python tests;
`make m2-check` exits 0 with G3, primitive probes and five-turn native
capture; `make m3-source-progress` exits 0 and reports 87 completed,
zero skipped original forms. The full loader itself exits 1 at the
`APPLICABLE` declaration in `77defs.mud` expression 78. See
[evidence](evidence/M3/QUOTED-OPTIONAL.md) and
[`source-progress-quoted-optional.json`](evidence/M3/source-progress-quoted-optional.json).

## M3 eager AND? checkpoint (2026-11-21)

Issue #80 implements AND? as a SUBR with all arguments evaluated before
truth selection. `make test` passes 1,086 Racket and 22 Python checks.
`make test-m3-andq` loads a SHA-verified original-source prefix and
asserts all five MSETG globals from `77defs.mud` expression 28;
`make m3-source-progress` now runs that regression and reports 70
completed forms with zero skipped before the quoted OPTIONAL default
failure in expression 61. See [AND? evidence](evidence/M3/ANDQ.md) and
[`source-progress-andq.json`](evidence/M3/source-progress-andq.json).

## M3 GDECL checkpoint (2026-11-21)

Issue #78 implements source-data GDECL and SETG declaration checking.
After `make reference-build`, run `make test`, `make m2-check`, and
`make m3-source-progress`. `make test` passes 1,077 Racket and 22 Python
checks. The unchanged loader completes 37 forms with zero skips and
stops at original `AND?` in `77defs.mud` expression 28. Pinned
Confusion's GDECL is an explicit no-op; this manual/reference deviation
is supported by ten native cases in `evidence/M3/gdecl-reference.json`.
See [GDECL evidence](evidence/M3/GDECL.md) and
[`source-progress-gdecl.json`](evidence/M3/source-progress-gdecl.json).

## M3 NEWTYPE declaration checkpoint (2026-11-21)

After `make reference-build`, run `make test`, `make m2-check`, and
`make m3-source-progress`. The issue #76 branch stores and checks the
manual's optional NEWTYPE declaration Pattern and enables the original
`77defs.mud` three-argument form. The unchanged loader now completes
36 forms with zero skips, stopping at unassigned `GDECL` in expression
27. The native Confusion reference discards the Pattern, a documented
runtime deviation; its seven clean and six deliberate-error cases are in
`evidence/M3/newtype-decl-*`. See [M3 NEWTYPE evidence](evidence/M3/NEWTYPE-DECL.md)
and [`source-progress-newtype.json`](evidence/M3/source-progress-newtype.json).

## M3 first original-source correction (2026-11-21)

Run `make test`, `make m2-check`, and `make m3-source-progress` after
`make reference-build`. On the issue #75 branch these exit 0: 1,046
Racket checks, 22 Python tests, 58 bounded G3 assertions, 12 native
primitive probes, five reference turns, 36 parsed historical text files,
and 26 unchanged original-source forms with zero skips. The full loader
itself exits 1 at `77defs.mud` expression 17, three-argument NEWTYPE;
the source-progress target exits 0 because this is an accurately reported
partial advance. See [M3 slice evidence](evidence/M3/EMPTYQ.md) and
[`source-progress-emptyq.json`](evidence/M3/source-progress-emptyq.json).
Confusion `EMPTY?`, `LENGTH?`, `ASSIGNED?` and `ROOT` cases have separate
clean and deliberate-error corpus files in `evidence/M3/`.

## Current M2 mainline checkpoint (2026-11-21)

The [mainline gate](evidence/M2/MAINLINE-GATE.md) passes at integrated
code baseline `7d34195`. Run `make reference-build` once, then
`make m2-check` for doctor, locked sources, reader sweep, offline tests,
historical original-definition probes, G3, native primitive probe and
five-turn capture. On that baseline the target exits 0 with 986 Racket
checks, 13 Python tests and 59 G3 assertions. The direct comparison of
the freshly rebuilt native capture to the approved M0 golden exits 2
solely for Confusion's build timestamp; a comparison with only that line
normalized finds zero mismatches and the game SHA matches. This does not
compare a Racket game transcript. The complete original loader separately
exits 1 at EMPTY? after 24 forms. Issue #73 has now decoupled the fixed
24-form expectation from all M2 tests. On the issue #73 branch the same
target exits 0 with 986 Racket checks, 22 Python tests and 58 G3
assertions from a bounded original-source prefix. The full unchanged
entry is measured by `make m3-source-progress`; its validator fails on
fewer than 24 completed forms, skipped execution, changed accepted prefix,
wrong file order, malformed diagnostics or false completion. See
[`SOURCE-PROGRESS.md`](evidence/M3/SOURCE-PROGRESS.md). The native
reference CI job runs this source-progress target after G3.

## Earlier M2 branch checkpoint (2026-11-20)

Run `make test` for the offline Racket and Python suites,
`make test-historical` for hash-verified original definitions, and
`make test-m2-g3` for the same-session G3 gate. The latter now exits 0
with 59 assertions on `feat/m2-mapf`; the exact source hashes, reference
cases, and distinct full-loader EMPTY? barrier are in
[`G3-GATE-MAPF.md`](evidence/M2/G3-GATE-MAPF.md). Focused MAPF controls,
interpreted FUNCTION application, TYPE?, and startup OBLIST association
cases are in [`MAPF.md`](evidence/M2/MAPF.md). `make test` passes 958
Racket checks and 13 Python tests. The native reference job
provisions pinned sources and runs G3; the fast smoke job remains offline.
M2 mainline acceptance remains pending.

On `feat/m2-indirect-apply`, issue #69 adds 15 clean native APPLY/computed
FORM cases and nine separate deliberate errors; see
[`INDIRECT-APPLY.md`](evidence/M2/INDIRECT-APPLY.md) and the
[requirements matrix](evidence/M2/REQUIREMENTS-AUDIT.md). `make test`
passes 986 Racket and 13 Python checks; the historical target and G3
still pass. `make m2-check` runs the full local technical acceptance
sequence after `make reference-build`. It writes the source sweep to
`artifacts/m2/reader-sweep.json`, preserving the frozen M0 evidence file.
Review, authorization, required CI and verification on `main` are separate
milestone gates.

## Earlier M2 D5 and G3 checkpoints (retained for provenance)

On `feat/m2-atom-props`, `make test` runs 868 Racket checks and 13 Python
tests, including `tests/atom_props_test.rkt` (65 focused checks).
`make test-historical` verifies the 23 assertion original VFLOAD and 20
assertion original DECL probes. D5 reference cases are in
`evidence/M2/atom-props-{cases,reference}.json` and the corresponding
`atom-props-error-*` files; independent review cases are in
`atom-props-review-*` and four clean `character-review-*` cases. The
independent local final-head review and SUBR FIX-indicator regressions are
in [`D5-FINAL-REVIEW.md`](evidence/M2/D5-FINAL-REVIEW.md) and
`d5-final-review-*`.
unchanged `77loadall.mud` load exits 1 after
24 completed expressions at `EMPTY?` in `77defs.mud` expression 15.
M2 G3 has not passed: a separate pre-merge integration run found missing
`N=?` in original MSETG's repeat path (issue #57). Reproduce D5 with `make test`,
`make test-historical`, and the loader command below. Earlier sections
retain their slice-era context.

On the stacked `feat/m2-structural-neq` correction branch, `make test`
adds 13 focused `N=?` checks (879 Racket, 13 Python total). The original
MSETG historical probe is recorded as failing at the next reader gap
`,.FOO`; it is reserved for issue #58, while the D5 historical target
still passes. See [`NEQ.md`](evidence/M2/NEQ.md).

On stacked `feat/m2-computed-global`, `make test` passes 884 Racket checks
and 13 Python tests. `make test-historical` adds a hash-verified original
MSETG first/equal-repeat probe (exit 0); the historical conflicting-repeat
case remains blocked by unassigned `ERROR` and is tracked as G3 FAIL.
Reference inputs and outputs are in `computed-global-*` and the method and
limitations are in [`COMPUTED-GLOBAL.md`](evidence/M2/COMPUTED-GLOBAL.md).

On stacked `feat/m2-error-primitive`, `make test` passes 888 Racket checks
and 13 Python tests; `make test-historical` adds the exact original MSETG
conflicting-repeat assertion. The deliberate Confusion `ERROR` probes exit
the harness with status 1 because the subsequent `<QUIT>` is read in the
reference's error-level REPL; their `*ERROR*` outputs are retained in
`error-reference.json`. This is a tested error path, not a clean-success
probe. See [`ERROR.md`](evidence/M2/ERROR.md).

`make test-m2-g3` on `feat/m2-g3-current` exits 2 deliberately after 48
passing same-session assertions. Original MSETG paths pass; original
PSETG reaches unassigned `MEMQ` after observable side effects. The
full source chain still stops at `EMPTY?` after 24 expressions.
See [`G3-GATE.md`](evidence/M2/G3-GATE.md); issue #63 tracks MEMQ.

After issue #63's MEMQ correction, `make test` exits 0 (903 Racket
checks, 13 Python), and `make test-historical` exits 0 (VFLOAD 23,
DECL 21, MSETG and PSETG original-source probes). `make test-m2-g3`
exits **2** after 52 passing observations because original `FLAGWORD`
reaches missing `MAPF`; pinned Confusion returns `1` for that call.
See [`MEMQ.md`](evidence/M2/MEMQ.md) and the updated G3 report.

The M2 G0 audit is reproducible with
`racket scripts/audit_source_readiness.rkt --output artifacts/m2/source-readiness.json`.
Its JSON separates independent compile probes from sequential execution
probes; `PASS` for the command means the audit completed, not that source
execution succeeded. See [`SOURCE-READINESS.md`](evidence/M2/SOURCE-READINESS.md)
for file hashes, first failures, baseline commands, and the Racket 7.9/8.10
check-count investigation.

The G1 loader suite is `raco test tests/loader_test.rkt` and is included in
`make test-racket` and CI. It uses disposable local files under `/tmp` and
checks shared session state, macro/function persistence, nested/repeated
`FLOAD`, partial execution, path containment, cycles, and structured source
errors, including indirect symlink targets and malformed later forms after a
completed prefix. Review regressions also cover a symlink target with `..`
after another symlink, consecutive parent components in a link target, and
session calls to compiled, interpreted, generated,
and macro definitions. The local CLI can be run with
`racket scripts/mdl_load.rkt --source-root ROOT --entry FILE --report REPORT`;
it exits nonzero on actual source execution failure and writes JSON in both
cases. See [`SOURCE-LOADER.md`](evidence/M2/SOURCE-LOADER.md) for reference
probes, exact pinned-source run and known deviations.

The G2 source-backed probe is `make test-historical`, which first verifies
the pinned source checkouts and then runs
`racket tests/historical_vfload_test.rkt`. It verifies the actual
`77loadall.mud` SHA256, copies exact bytes into a disposable authorized root,
loads only its first definition with a PARTIAL report, invokes `VFLOAD`, and
checks output, return, global state and invalid calls. The native reference
workflow installs `compatibility-lib` for the runtime's `racket/mpair` import
and `rackunit-lib` for its test submodule,
then runs this target after source verification. Its negative-call helper has
a self-check that rejects unexpected success. The first two PR #43 native runs
failed on those missing libraries; see the
[`review evidence`](evidence/M2/HISTORICAL-VFLOAD.md#pr-43-review-follow-up-2026-11-19).
Focused Confusion
evidence is reproducible with
`.venv/bin/python -m scripts.probe_vfload_reference` after the native build.
See [`HISTORICAL-VFLOAD.md`](evidence/M2/HISTORICAL-VFLOAD.md).

## Test layers

1. `make test-racket`: reader, bootstrap compiler, FALSE, atom/OBLIST,
   mutable sequences, type constructors, local/global bindings, the
   documented 36-bit FIX/WORD subset, and scoped M2 execution semantics
   (PROG/REPEAT/RETURN/AGAIN activations and function formals), chapter-14
   `#DECL` declaration checking with `DECL?`, and chapter-7 SEGMENT (`!`
   splice) evaluation with LIST-tail sharing, and chapter-14 structured
   declaration patterns (`<struc [REST ...]>` with bounded traversal), on
   the explicitly supported subset. The target refreshes the linked `#lang mdl` module before tests
   so changed runtime exports are visible. Stale bytecode under the
   gitignored `compiled/` directories produces `instantiate-linket`
   dependency errors after module interface changes; delete those
   directories and rerun.
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
The PR #35 review added eleven Racket checks for empty auxiliary LISTs in
interpreted PROG/REPEAT, leading activation names with quoted formals,
runtime-generated definitions, binding order, and duplicate rejection.
Ten focused Confusion observations are saved in `macro-review-cases.json`
and `macro-review-reference.json`; see `MACROS.md` for the failing-then-passing
record. The integrated M2 gate remains open.

## CI toolchain

Both workflows run in the digest-pinned Racket project `8.10-bc` minimal
container. The harness job adds Git for the source-lock Python test and the
Racket packages `compiler-lib`, `rackunit-lib`, and `compatibility-lib` for
`raco make`, RackUnit, and `racket/mpair`. `make test-racket` and the CI job
both call `scripts/test_racket.sh`, keeping one test-file list. The native job
adds Git, G++, Make, Perl, and `libgc-dev`, verifies the locked source commits,
then builds and captures Confusion. The CI runner still downloads Python
dependencies and the listed Racket libraries on each job. See
[`CI-SETUP.md`](evidence/M2/CI-SETUP.md) for exact runs, timing, alternatives,
and limits. The CI run checks reference execution; it does not establish
Racket gameplay parity.

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
