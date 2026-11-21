# MDL on Racket — original Zork preservation harness

> **Status: M0, M1 and M2 gates PASS; M3 source loading remains incomplete. NOT a playable game.** This repository is a starting
> point for developing an MDL-compatible `#lang mdl` in Racket and validating it
> against the reconstructed December 1977 Zork running in Confusion.
>
> The historical game sources and interpreter are **not bundled**. The included
> fetcher retrieves two immutable upstream GitHub commits after network access is
> available. All verification below is local and reproducible, modulo toolchain
> versions and original input/time/randomness.

**Current M3 checkpoint (2026-11-21, `feat/m3-duplicate-decl`):**
The scoped [issue #100](docs/evidence/M3/DUPLICATE-DECL.md) change retains
both Patterns when an ATOM appears twice in one attached `#DECL` and checks
both in source order. The manual does not state duplicate precedence;
conjunction is a documented conservative inference. The unchanged source
loader completes **430 original forms with zero skips**, fully loading
`77act1.mud`, `77act2.mud` and `77act3.mud`, then exits 1 at
`77rooms.mud` expression 13, line 17: unsupported `HANDLER`. The latter is
tracked in [issue #102](https://github.com/quaat/mdl-racket/issues/102),
under event API issue #71. `make m3-source-progress` exits 0 only as a
partial measurement. `make test` and `make m2-check` pass; see the
[evidence](docs/evidence/M3/DUPLICATE-DECL.md). M0/M1/M2 remain PASS;
the formal M3 gate remains **INCOMPLETE**. Full source load,
initialization, interactive input, smoke parity and gameplay are unverified.

**Previous M3 checkpoint (issue #98):**
The scoped [issue #98](docs/evidence/M3/DEFERRED-DECL-TYPE.md) change
retains an unresolved TYPE atom in an attached `#DECL` until a value is
checked. An unresolved name still raises an error at check time; explicit
`DECL?` still rejects it immediately. The unchanged source loader completes
**363 original forms with zero skips**, fully loading `77act1.mud`, then
exits 1 at `77act2.mud` expression 39, line 424: duplicate declaration
for `M` in `BALLOON`. `make m3-source-progress` exits 0 only as a partial
measurement. `make test` and `make m2-check` pass; see the
[evidence](docs/evidence/M3/DEFERRED-DECL-TYPE.md). M0/M1/M2 remain PASS;
the formal M3 gate is **INCOMPLETE**. Full source load, initialization,
interactive input, smoke parity and gameplay remain unverified. Next:
[issue #100](https://github.com/quaat/mdl-racket/issues/100).

**Previous M3 checkpoint (issue #96):**
The scoped [issue #96](docs/evidence/M3/NTH-DECL.md) change implements
positive-count `[n Pattern ...]` repetition in structured declarations,
including attached `#DECL` and NEWTYPE patterns. It rejects malformed
counts and short values and matches large counts without expanding them.
The unchanged source loader completes **233 original forms with zero skips**,
then exits 1 at `77act1.mud` expression 55, line 740: unknown declaration
type `PRSOBJ`. `make m3-source-progress` exits 0 as a partial-progress
measurement. `make test` and `make m2-check` pass; see the
[evidence](docs/evidence/M3/NTH-DECL.md) for native probes, exact commands,
and the one documented Confusion deviation. The formal M3 gate remains
**INCOMPLETE**: full load, initialization, interactive input, smoke parity,
and gameplay are unverified. The next task is
[issue #98](https://github.com/quaat/mdl-racket/issues/98) addressed above.

**Previous M3 checkpoint (issue #94):**
The scoped [issue #94](docs/evidence/M3/PERCENT-READ.md) change implements
session-aware `%` evaluation during executable reading, `ASCII`, and
CHARACTER arguments to `STRING`. The syntax-only parser remains free of
MDL side effects; `%%` and mutable read tables remain unsupported.
The unchanged source loader completes **188 original forms with zero
skips**, fully loading `81tell-repl.mud`, then exits 1 at
`77act1.mud` expression 10, line 78: unsupported `[3 ANY]` NTH
declaration repetition. `make m3-source-progress` exits 0 only as a
validated partial-load measurement. `make test` and `make m2-check`
pass on this branch; see the [evidence](docs/evidence/M3/PERCENT-READ.md)
for counts, native probes and reproduction commands. M0/M1/M2 remain
PASS; the formal M3 gate remains **INCOMPLETE**. Full source load,
initialization, interactive input, smoke parity and gameplay are unverified.
The next task is [issue #96](https://github.com/quaat/mdl-racket/issues/96):
probe and implement the NTH declaration Pattern without changing the
locked source.

**Previous integrated main checkpoint:** The authorized M2 stack, PRs #54, #59,
#61, #62, #64, #66, #68 and #70, is integrated on `main` at `7d34195`.
The [M2 mainline gate](docs/evidence/M2/MAINLINE-GATE.md) passes at its
accepted `7d34195` baseline. The permanent M2 suite now loads a bounded,
SHA-verified original-source prefix: `make m2-check` exits 0 with 986
Racket checks, 22 Python tests, and 58 G3 assertions. It includes original VFLOAD,
MSETG, PSETG and FLAGWORD, MAPF, indirect APPLY, declarations, macro
expansion, activation control, aliasing and session isolation. The
[requirements audit](docs/evidence/M2/REQUIREMENTS-AUDIT.md) lists tested
capabilities and limits. Reproduce after `make reference-build` with
`make m2-check`; the complete loader command is below.
The separate [M3 source-progress gate](docs/evidence/M3/SOURCE-PROGRESS.md),
`make m3-source-progress`, verifies 36 parsed historical text files. The
[predicate and ROOT slice](docs/evidence/M3/EMPTYQ.md) advanced the
unchanged `77loadall.mud` chain from 24 to 26 completed forms. The
[three-argument NEWTYPE slice](docs/evidence/M3/NEWTYPE-DECL.md) advanced
it to 36 forms, and the [GDECL slice](docs/evidence/M3/GDECL.md) to 37.
The [eager AND? slice](docs/evidence/M3/ANDQ.md) reached 70 forms.
The [quoted OPTIONAL default slice](docs/evidence/M3/QUOTED-OPTIONAL.md)
reached 87 forms. The [APPLICABLE declaration slice](docs/evidence/M3/APPLICABLE-DECL.md)
reached 112 and loaded `77defs.mud` in full.
The [`%<>` slice](docs/evidence/M3/PERCENT-EMPTY.md) reached 136 forms
and loaded `77makstr.mud` in full. The
[`#PSTRING 0` typed literal slice](docs/evidence/M3/PSTRING-LITERAL.md)
reached 144 forms. The
[positional `#DECL` slice](docs/evidence/M3/FUNCTION-DECL.md)
reached 157 forms. The earlier
[`!\ ` CHARACTER slice](docs/evidence/M3/SPACE-CHARACTER.md)
keeps 157 completed, zero skipped forms and moves the first failure
within `81tell-repl.mud` expression 23 to `%<STRING <ASCII 10>>`,
tracked in [issue #94](https://github.com/quaat/mdl-racket/issues/94).
NEWTYPE stores and checks its optional
declaration Pattern; GDECL installs and checks global value Patterns.
Pinned Confusion silently omits both checks, explicit reference
deviations. Its direct `DECL?` handling of `APPLICABLE` also errors,
while the Racket Pattern follows the MDL manual and native
`APPLICABLE?` type observations. `ASSIGNED?` with ENV remains unsupported;
`%%` read macros and mutable read tables remain unsupported;
custom `#type` literals currently support only integer WORD data;
positional `#DECL` is validated as metadata but is not enforced on FUNCTION,
matching the pinned reference;
full source loading, game boot and gameplay
parity are unverified. Reproduce with `make test`, `make m2-check`, and
`make m3-source-progress` after `make reference-build`.
Explicit CLOSURE, MAPR, TAG, resumable ERROR/ERRET, full loader completion,
parser/game boot and gameplay remain unsupported or unverified. Random/event
APIs are tracked as [M3 issue #71](https://github.com/quaat/mdl-racket/issues/71).
See [current status](docs/STATUS.md).
Historical progress notes below preserve
their original slice-level context.

**M2 G3 correction on `feat/m2-structural-neq`:** structural `N=?`
passes 13 focused checks and `make test` (879 Racket, 13 Python). The
original MSETG repeat path now reaches a separate computed-global reader
defect at `,.FOO` ([issue #58](https://github.com/quaat/mdl-racket/issues/58));
G3 remains FAIL and M2 remains open. See [N=? evidence](docs/evidence/M2/NEQ.md).

**Stacked reader correction (issue #58):** `,.FOO` now evaluates the local
FOO to obtain the global atom, as in the MDL manual and pinned Confusion.
The original `MSETG` equal-repeat path passes from hash-verified `81prim.mud`.
`make test` passes 884 Racket checks and 13 Python tests;
`make test-historical` passes the VFLOAD, DECL, and MSETG repeat probes.
The conflicting-repeat path reaches unsupported `ERROR`, so **G3 remains
FAIL**. The full source load still stops after 24 expressions at `EMPTY?`.
Reproduce with those two make targets and the loader command below; see
[reader evidence](docs/evidence/M2/COMPUTED-GLOBAL.md). Next: implement
the reference-backed `ERROR` path, then rerun G3. M3 has not started.

**Stacked `ERROR` correction (issue #60):** the source-defined `MSETG`
conflicting-repeat path raises an observable `ALREADY-GASSIGNED` exception.
`make test` passes 888 Racket checks and 13 Python tests;
`make test-historical` passes the original MSETG error probe too. Pinned
Confusion outputs and the non-resumable Racket deviation are in
[ERROR evidence](docs/evidence/M2/ERROR.md). Integrated G3 remains FAIL
at the next source-backed dependency; no game boot or gameplay parity is claimed.

**Earlier current-head G3 run:** `make test-m2-g3` exits 2 after 48 passing
integrated assertions because original `PSETG` reaches unassigned `MEMQ`
after its initial side effects. Original MSETG first/equal/conflict paths
pass. The exact-source chain still stops at `EMPTY?` after 24 expressions;
G3 and M2 remain **FAIL**. Reproduce with `make test-m2-g3`; see
[G3 evidence](docs/evidence/M2/G3-GATE.md). Next correction: issue #63
`MEMQ`, followed by a fresh G3 run. M3 remains unstarted.

**Current MEMQ/G3 result:** Original `PSETG` first/repeat calls now pass
using `==?` membership and shared REST views. `make test` exits 0 with
903 Racket checks and 13 Python tests; `make test-historical` exits 0
with VFLOAD 23, DECL 21, MSETG, and PSETG probes. `make test-m2-g3`
exits **2** after 52 passing integrated assertions: original `FLAGWORD`
reaches unsupported `MAPF`, while pinned Confusion returns `1` for its
empty-TUPLE call. G3 and M2 remain **FAIL**; M3 is unstarted. Reproduce
with those make targets; see [MEMQ evidence](docs/evidence/M2/MEMQ.md)
and [updated G3 evidence](docs/evidence/M2/G3-GATE.md). Next: issue #65.

The [M2 G0 source-readiness audit](docs/evidence/M2/SOURCE-READINESS.md)
passes: the baseline and pinned source are reproducible, and the first
historical load barriers are identified. Run
`racket scripts/audit_source_readiness.rkt` to reproduce its probes. The
[G1 local source loader](docs/evidence/M2/SOURCE-LOADER.md) executes the
existing MDL subset across files in a shared session and supports constrained
nested `FLOAD`. Its G1 local gate passes, including review regressions for
symlink lookup order, consecutive parent components, and interpreted session
calls; `make test`, both CI workflows, and the pinned Confusion
build/capture/probes pass. Reproduce its pinned-source failure with
`racket scripts/mdl_load.rkt --source-root .cache/upstream/mdlzork/mdlzork_771212/patched_confusion --entry 77loadall.mud --report artifacts/m2/source-load.json`.
That command exits 1 after **twenty-four** completed expressions, at the
`EMPTY?` primitive called by the original source-defined `NEWSTRUC` in
`77defs.mud` expression 15 (with D5's atom-property `PUT`/`GET`
associations, `81prim.mud` loads in full — including the original
`PSETG` with its structured declaration — and `77defs.mud` expressions
1–14 execute, including the historical
`<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>` declaration property);
game initialization is not supported. The
[G2 partial-source probe](docs/evidence/M2/HISTORICAL-VFLOAD.md) verifies
the pinned source hash and invokes the unmodified reconstructed `VFLOAD`
definition on a controlled file with matching Confusion output and state.
Its local gate passes; after two native CI failures for missing Racket
libraries, both workflows passed on the corrected dependency commit. The
latest G1 path fix is merged and passes locally, with combined-branch CI
also passing. Run
`make test-historical` to reproduce the probe. That G2 probe reports its 12
unexecuted forms explicitly. M2's integrated gate and gameplay remain
unverified; the current sequential loader blocker is `EMPTY?` inside
`77defs.mud`'s `NEWSTRUC`.
The [M2 source execution inventory](docs/evidence/M2/SOURCE-EXECUTION.md)
lists the loaded, invoked, blocked, and untested definitions separately.

The [MUDDLE slice](docs/evidence/M2/MUDDLE.md) binds the
interpreter-supplied version global `MUDDLE` to the pinned reference's
FIX `101` in every fresh session, so the `77defs.mud` version guard
short-circuits exactly like the reference. Its local gate is **PASS**.
The [structured declaration slice](docs/evidence/M2/DECLARATION-PATTERNS.md)
implements chapter-14 `<struc [REST ...]>` patterns for LIST, VECTOR,
UVECTOR, and TUPLE with required element prefixes, cyclic multi-pattern
REST repetition, nested `<OR ...>`, bounded traversal with explicit
cycle/depth errors, and the reference's `DECL?` payload distinction
(overall-type mismatch returns bare `#FALSE ()`; an element mismatch
carries the offending element). Its local gate is **PASS**, verified
against 22 pinned Confusion success observations and 14 deliberate-error
observations.
The [SEGMENT slice](docs/evidence/M2/SEGMENTS.md) implements chapter-7
SEGMENT evaluation: `!.ATOM`, `!,ATOM`, and `!<FORM...>` splice their
value's elements into LIST, VECTOR, UVECTOR, and FORM-argument construction
in strict left-to-right order, a final LIST-valued segment shares the
payload's tail (mutation visible through both), quoted structures keep
segments as data, and standalone or non-structured segment results raise
the reference's ILLEGAL-SEGMENT. Its local gate is **PASS**, verified
against 18 pinned Confusion success observations and 10 deliberate-error
observations.
The [declaration slice](docs/evidence/M2/DECLARATIONS.md) implements
chapter-14 `#DECL` for `DEFINE`, `DEFMAC`, `PROG`, and `REPEAT` in both
compiled and interpreted paths, checks bound formals, OPTIONAL/AUX
initializers, later `SET`s, and results against `ANY`, registered type
atoms, `<OR ...>`, and `<PRIMTYPE type>` patterns, and adds `DECL?`,
`GASSIGNED?`, and `MANIFEST` with the manifest-gated `SETG`. The unmodified
original `MSETG` installs and executes; thirteen pinned Confusion
observations back the semantics, and the deviations (Confusion does not
enforce attached declarations; the `DECL?` false payload follows Confusion)
are recorded in the slice evidence. Its local gate is **PASS**.

## Goals

1. Execute original MDL game code, not a newly designed text-adventure engine.
2. Keep the MIT 1977 source unchanged; track reconstructive patches separately.
3. Establish a working Confusion oracle and differential tests before translating
   complex semantics.
4. Build a source-located MDL parser and a `#lang mdl` implementation in Racket.
5. Eventually offer a browser UI; choose a server-backed Racket runtime first,
   and only commit to client-side WASM after feasibility experiments.
6. Keep research evidence in the repository: sources, tests, deviations, decisions,
   and reproducibility details.

## Prerequisites (Linux)

- Racket (the harness targets modern Racket; compatibility must be confirmed on
  your installed release)
- Python 3.11+ and `venv`/`pip`
- Git, GCC/G++, GNU Make, Perl, and `libgc-dev` for the patched Confusion interpreter
- Internet access to fetch source checkouts and Python packages

Ubuntu/Debian example:

```bash
sudo apt-get update
sudo apt-get install -y racket git build-essential make perl libgc-dev python3-venv
```

## Installation

```bash
unzip mdl-racket-zork-harness.zip
cd mdl-racket-zork-harness
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
raco pkg install --auto --link
make doctor
make test
```

`make doctor` reports detected tools and fails only if required commands are
missing. Successful detection does not mean the Racket tests or Confusion
gameplay have passed; run the validation targets explicitly.

`make test` requires Racket and the locally linked Racket package. It tests
**the bootstrap reader/compiler, implemented M1 primitives, and the documented
M2 control, formals, and macro slices**, not the original Zork
game. If `raco` reports that the package is already installed, inspect
`raco pkg show` rather than blindly reinstalling it.

### CI Racket installation

The GitHub Actions jobs use the Racket project's minimal `8.10-bc` Docker
image, pinned by digest, so each job starts with Racket installed. The harness
job installs `compiler-lib`, `rackunit-lib`, and `compatibility-lib` for the
test suite; the native reference job installs its C++ build tools. The
measured pilot and the apt alternatives are in
[the CI setup report](docs/evidence/M2/CI-SETUP.md). Run `make test` locally;
the CI harness uses `scripts/test_racket.sh` for the same Racket test list.
This CI setup passes both workflows, while the M2 game execution gate remains
open.

### Source checkout and historical reference

```bash
make sources               # downloads/locks original upstream checkouts
make reference-build       # builds native Confusion (may need toolchain fixes)
make reference-capture     # saves a JSON capture in artifacts/reference/house.json
make check-source          # sweeps selected 1977 text files with the Racket reader
make reference-probe       # captures isolated Confusion primitive observations
```

Reference source paths are:

- `.cache/upstream/mit_zork/zork/` — original MIT 1977 release
- `.cache/upstream/mdlzork/mdlzork_771212/patched_confusion/` — playable reconstruction
- `.cache/upstream/mdlzork/confusion_patched/` — patched C++ MDL interpreter

All `.cache` paths are excluded from Git. `sources.lock.json` pins the commits.
The `fetch_sources.py` script refuses to replace modified upstream checkouts.

Once a candidate game implementation exists, it must emit a JSON transcript
in the [documented interchange format](docs/TESTING.md):

```bash
python scripts/compare_transcripts.py \
  artifacts/reference/house.json artifacts/candidate/house.json
```

**No candidate Zork runtime exists yet.** Differential testing is a planned
acceptance gate, not a capability claimed for M0.

## Current implementation and milestone evidence

M0 passed its source, reader, native Confusion, test, and approved golden
transcript gates. M1's [FALSE slice](https://github.com/quaat/mdl-racket/pull/10),
[atoms](https://github.com/quaat/mdl-racket/pull/12),
[sequences](https://github.com/quaat/mdl-racket/pull/13),
[types](https://github.com/quaat/mdl-racket/pull/14),
[bindings](https://github.com/quaat/mdl-racket/pull/15),
[36-bit words](https://github.com/quaat/mdl-racket/pull/16), and
[integrated gate audit](https://github.com/quaat/mdl-racket/pull/18) are merged.
The M1 gate is **PASS on `main`** at merge commit
`a68cbb970b7028853fbcf7885c6c7c42f9470fe5`: 274 Racket checks and 13 Python
tests pass, all 36 selected historical text files parse, and 60 successful
Confusion cases plus six expected error observations reproduce their saved
results. The fresh native build changes its binary hash and embedded build
timestamp; the approved five-turn transcript matches after excluding those
fields and capture time. See the M1 gate report for the comparison contract.
The first M2 slice adds unnamed `PROG` auxiliary frames and bare `RETURN`
within the current function. Its local tests and focused Confusion probes pass;
the **M2 milestone gate is not yet PASS**. See the
[M2 PROG report](docs/evidence/M2/PROG.md) and
[issue #20](https://github.com/quaat/mdl-racket/issues/20). Confusion crashes on
`RETURN` during auxiliary initialization; that reference deviation is recorded
in the report.
The [activation-frame hardening slice](docs/evidence/M2/ACTIVATIONS.md)
records function ownership and frame lifetime before broader control flow.
The [cyclic equality hardening slice](docs/evidence/M2/EQUALITY.md) makes `=?`
terminate on tested self-referencing values and reports unresolved distinct
cycles explicitly. M2's integrated gate remains open.
The [REPEAT/AGAIN slice](docs/evidence/M2/REPEAT.md) adds unnamed `REPEAT`
and bare `AGAIN` in the current function; auxiliaries are bound once across
restarts. The [named activation slice](docs/evidence/M2/ACTIVATION-TARGETS.md)
adds named `PROG`/`REPEAT` frames and explicit `RETURN`/`AGAIN` targets,
including transfers from called functions.
The [function formals slice](docs/evidence/M2/FORMALS.md) adds the
historical `DEFINE` formal sections `"OPTIONAL"`, `"AUX"`, `"TUPLE"`, and
`"ARGS"` with in-frame defaults, TUPLE-typed rest values, and historical
arity error names.
The [control slice](docs/evidence/M2/CONTROL.md) adds function activation
formals (the leading `DEFINE` self-atom used by the 1977 sources and the
`"NAME"`/`"ACT"` markers) with explicit RETURN/AGAIN to a function's own
activation, `GO` to labels in the current function's PROG/REPEAT (manual
based; Confusion has no GO), and `UNWIND` cleanup on nonlocal transfers.
`"BIND"`/`"CALL"` markers, `TAG`, `GO` across function boundaries, and
source loading remain unsupported.
The [macro slice](docs/evidence/M2/MACROS.md) adds `DEFMAC`, first-class
FORM construction and evaluation, one-step `EXPAND`, and quoted formals.
Its local gate is **PASS**: `make test` passes 513 Racket checks and 13 Python
tests; 25 isolated pinned Confusion success cases, ten review-regression
cases, and eight separate error observations reproduce their saved outputs.
The [review follow-up](docs/evidence/M2/MACROS.md#review-follow-up) covers
empty interpreted PROG/REPEAT auxiliaries and leading activation names with
quoted formals. This is an M2 slice result; the
M2 milestone remains open until original source definitions execute.
Reproduce the checks with
`make test`, `make sources`, `make check-source`,
`make reference-build`, `make reference-capture`, and `make reference-probe`.
See the [M0 report](docs/evidence/M0/REPORT.md),
[M1 FALSE report](docs/evidence/M1/REPORT.md),
[M1 atom report](docs/evidence/M1/ATOMS.md),
[M1 sequence report](docs/evidence/M1/SEQUENCES.md),
[M1 type report](docs/evidence/M1/TYPES.md),
[M1 binding report](docs/evidence/M1/BINDINGS.md),
[M1 word report](docs/evidence/M1/WORDS.md),
[M1 gate report](docs/evidence/M1/GATE.md), and
[current gate status](docs/STATUS.md) for hashes, outputs, and limits.

- A custom `#lang mdl` reader for a small subset of angle-bracket MDL syntax.
- Source-located AST nodes and a conservative compiler.
- Basic `DEFINE` with simple parameters, `SETG`, `GVAL`, local/global references,
  arithmetic, comparisons, and a few collection forms.
- First-class MDL FALSE literals with mutable payloads, distinct from the `NIL` atom;
  stable literal identity across function calls; value-preserving `NOT`, `AND`,
  `OR`, and `COND` truth behavior; and limited `TYPE` recognition for FALSE and
  ATOM and OBLIST values.
- Identity-bearing ATOM values, named OBLISTs, lookup/insertion/removal, and
  explicit `!-` OBLIST trailers on reader atom literals.
- Mutable LIST, VECTOR, and UVECTOR values with shared `REST` views,
  1-based `NTH`/`PUT`, LIST `PUTREST`, and uniform UVECTOR element checks.
- Type tags and structured `CHTYPE`, with `PRIMTYPE`, `TYPEPRIM`, and `NEWTYPE`
  for the documented subset.
- Atom-keyed local/global values with dynamic parameter frames, `VALUE`
  lookup, and global unassignment on the supported subset.
- Historical 36-bit FIX and WORD behavior for the documented arithmetic,
  octal, bitwise, shift, and bit field subset.
- Unnamed `PROG` with sequential auxiliary initialization and bare `RETURN`
  from the closest PROG in the current function.
- `DEFINE` formal-list sections marked by strings — `"OPTIONAL"`, `"AUX"`,
  `"TUPLE"`, and `"ARGS"` — with defaults evaluated in the growing function
  frame, unassigned optional/auxiliary bindings, TUPLE-typed rest values
  (TYPE and PRIMTYPE `TUPLE`), and historical arity error names.
- Function activation formals: the leading `DEFINE` self-atom and the
  `"NAME"`/`"ACT"` markers bind a function's own ACTIVATION, targetable by
  explicit `RETURN`/`AGAIN` from any depth, with `AGAIN` re-running the body
  without re-binding.
- `GO` to top-level labels in the current function's PROG/REPEAT bodies,
  with labels skipped in normal flow, and `UNWIND` cleanup expressions that
  run when a nonlocal transfer or error crosses below them.
- `DEFMAC` calls with runtime expansion, FORM values and `EXPAND`, quoted
  formals, and caller-frame evaluation of plain and TUPLE arguments.
- An intentionally incomplete compatibility runtime.
- Parser smoke tests, compile tests, native Confusion reference scripts,
  transcript comparison, and offline Python harness tests.

**Not supported yet:** complete original MDL syntax, compile-time macro
expansion, dynamic `.OBLIST`,
SPECIAL/UNSPECIAL declaration wrappers, `[OPT ...]` and NTH
repetitions, actor/room types, GROW/BACK/TOP and STRING/BYTES views,
explicit environments, the `"BIND"`/`"CALL"` activation formals, TAG values,
and `GO` across function boundaries, general nonlocal
control flow beyond the supported RETURN/AGAIN/GO/UNWIND subset, source
loading, general APPLY/DISPATCH, ROT,
PDP-10 FLOAT bit layout, event scheduling,
original parser, gameplay, and client-side web execution.
Unsupported compile constructs fail with errors; the reader's acceptance of a
construct does not imply implemented semantics.

The current milestone is [M2 execution semantics and MDL compilation](docs/PLAN.md).
Its gate requires executing initial
original source definitions; it does not assume a new game engine.

## Working with Codex

Start at [`AGENTS.md`](AGENTS.md), then [`docs/CODEX_START.md`](docs/CODEX_START.md).
The plan and precise gates are in [`docs/PLAN.md`](docs/PLAN.md). Treat
[`docs/STATUS.md`](docs/STATUS.md) as the current source of truth: never label
any untested target as passing.

For each milestone, follow the first unmet gate in `docs/STATUS.md`, record
the evidence, and update this README when the gate result changes.

## Sources, provenance, licensing

- [MITDDC/zork](https://github.com/MITDDC/zork) — original historical sources;
  MIT-0 **to the extent MIT holds rights**.
- [heasm66/mdlzork](https://github.com/heasm66/mdlzork) — reconstructed
  December 1977 game and patched Confusion.
- Confusion is **GPLv3**; the reconstructed gameplay imports later Zork
  material. Review rights before redistributing binaries, sources, or hosted
  commercial variants. The harness MIT-0 license does **not** override upstream
  licenses. See [`docs/PROVENANCE.md`](docs/PROVENANCE.md).

This repository is an independent development scaffold. Local Racket and
Confusion checks, remote CI, and golden review completed on 2026-11-17.
See [`docs/STATUS.md`](docs/STATUS.md) for explicit M0 evidence and M1 limits.
