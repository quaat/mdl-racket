# Status — 2026-11-19 (M2 historical VFLOAD slice under review)

## M2 source execution audit (G0)

**G0 PASS; M2 integrated gate NOT RUN.** The baseline on
`36df3cefccfb9e382cef113752dcd16457e1e95c` reproduces 513 local Racket
checks, 13 Python tests, 36 parsed source files, the native build, capture and
probe. The 508 count on Racket 8.10 is a RackUnit nested-check reporting
difference, verified with a deliberately failing nested assertion in a
disposable copy. First actual source barriers are `FLOAD`, `#DECL`, the
native `MUDDLE` global, and source ordering. See
[`SOURCE-READINESS.md`](evidence/M2/SOURCE-READINESS.md) and its JSON inventory.
Next: a controlled source loader and shared MDL session (G1). Original source
execution and gameplay have not been demonstrated.

## M2 shared-session source loader (G1)

**G1 PASS locally; M2 integrated gate NOT RUN.** A root-restricted local
loader compiles and executes top-level forms in order, shares MDL state across
files, and routes nested `FLOAD` through the same session. Controlled fixture
tests cover ordering, definitions/macros, fresh-session isolation,
partial failure, missing files, traversal, symlink escape, cycles, repeated
loads and source diagnostics. The original `77loadall.mud` now executes its
`VFLOAD` definition and begins `81prim.mud`; it stops on the genuine
unsupported `#DECL` at line 3:9. See
[`SOURCE-LOADER.md`](evidence/M2/SOURCE-LOADER.md) and the structured
[load report](evidence/M2/source-load-first-barrier.json). G2 must invoke the
unmodified definition with controlled input; no gameplay is claimed.
The PR #41 review follow-up fixes an indirect symlink escape and preserves
completed forms before later reader errors. The first native CI run failed
because the minimal image lacks `raco make`; the conditional precompile fix
passed both the harness and native reference CI workflows on the follow-up
commit. That follow-up reported 561 Racket checks and 13 Python tests. See
the review section of `SOURCE-LOADER.md`.
The second PR #41 review identified link targets containing `..` after a
symlink and interpreted definitions rejected by `mdl-session-call`. Both now
have focused regressions and local fixes; see the same report for validation.
The current suite reports 568 Racket checks and 13 Python tests.
G1 remains a local slice PASS while the PR is under review. G2 has a separate
stacked PR #43; the integrated M2 gate remains open.

## M2 historical VFLOAD partial-source probe (G2)

**G2 PASS locally; integrated M2 G3 NOT RUN.** The test verifies the pinned
`77loadall.mud` SHA256, copies its bytes unchanged into a disposable
authorized root, executes only its first `DEFINE VFLOAD`, and invokes that
original reconstructed-source definition on a controlled file. The loader
explicitly reports PARTIAL (one completed, 12 unexecuted forms); the call
prints `<fixture-path> loaded`, returns empty FALSE and installs the fixture's
global value. Six focused pinned Confusion cases corroborate the relevant
output and state. See [`HISTORICAL-VFLOAD.md`](evidence/M2/HISTORICAL-VFLOAD.md).
`PRINTSTRING` follows the manual's count return while Confusion returns the
buffer, a recorded deviation that does not affect VFLOAD's final value.
The full source sequence remains blocked at `#DECL`; the next slice must
implement verified declaration semantics. No gameplay is claimed.
The [M2 source execution inventory](evidence/M2/SOURCE-EXECUTION.md) keeps
the integrated G3 gate at NOT RUN.
PR #43's first two native CI runs failed before reference capture because the
minimal Racket image lacked `compatibility-lib` for `racket/mpair`, then
`rackunit-lib` for the runtime's test submodule. The review
also found that a negative-test helper accepted its own assertion exception.
Both have follow-up fixes: the workflow installs both libraries, and a
failing-then-passing helper self-check makes wrong-type tests meaningful.
Local G2 validation now reports 23 historical assertions, 568 Racket checks,
13 Python tests, and matching reference output; follow-up CI is pending.

| Gate | State | Evidence / limitation |
|---|---|---|
| Source SHA verification | **PASS** | `make sources` verified both locked commits and clean upstream trees; see `artifacts/environment/sources.json` |
| Racket and Python tests | **PASS** | Plain `make test`: 26 Racket and 13 Python tests pass with pinned dependencies in ignored `.venv`; Makefile selects the venv and `/tmp`. Earlier failures on read-only `/var/tmp` and missing `pexpect` are recorded in the report. |
| December 1977 text reader sweep | **PASS for parsing** | `make check-source`: 36/36 selected UTF-8 MDL text files parsed, four non-text files classified separately; per-file offsets, hashes and counts in `docs/evidence/M0/reader-sweep.json` |
| Native Confusion build | **PASS** | `make reference-build` built `mdli` from pinned `mdlzork` without changing checkout |
| Opening scene plus five commands | **PASS** | `make reference-capture`: all prompts returned, no observed reference errors; maintainer approved `docs/evidence/M0/house-golden.json` in the Codex conversation on 2026-11-17 |
| Primitive reference probes | **PASS for reference only** | `make reference-probe`: 12/12 processes exited 0 with empty stderr; `docs/evidence/M0/primitives.json` |
| CI offline job | **PASS** | [Harness checks run 44125722477](https://github.com/quaat/mdl-racket/actions/runs/44125722477) completed successfully on PR #2 |
| CI native reference job | **PASS** | [Run 44125722256](https://github.com/quaat/mdl-racket/actions/runs/44125722256) verified 36 text files, built Confusion, captured five turns, and probed 12 cases. First run failed on missing `<cstdint>`; build-only flag fixed it. |
| Archive/reconstruction deltas | **PASS for inventory** | Explicit source and semantic differences are listed in `docs/PROVENANCE.md`, based on pinned `mdlzork_771212/README.md` |
| Candidate Racket gameplay / parity | **NOT IMPLEMENTED** | M0 compiler is demonstrative only |

**M0 gate: PASS.** The maintainer approved the exact golden fixture in the
Codex conversation on 2026-11-17; its SHA256 is
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
[GitHub issue #1](https://github.com/quaat/mdl-racket/issues/1) and merged
[PR #2](https://github.com/quaat/mdl-racket/pull/2) track M0. Both PR workflows
passed. **M1 is PASS on `main`; M2 is current.** This status does not claim Racket
game execution or runtime equivalence.

The M1 issue list and dependency graph are in `docs/PLAN.md`. Slice sections
below preserve each feature's status at its PR head; the final combined gate
result is at the end of this file.

See `docs/evidence/M0/REPORT.md` for exact commands, hashes, and limits.

## M1 issue #3: FALSE values (merged)

**Local slice checks: PASS. M1 milestone: NOT YET PASS.** The reader now groups
`#FALSE (items)` as one source-located node. The bootstrap compiler/runtime
represent FALSE separately from `NIL`, preserve literal payloads, and return
MDL values from `NOT`, `AND`, `OR`, `COND`, and supported predicates. `TYPE`
currently recognizes only FALSE and placeholder ATOM values. `make test`
passes 63 Racket checks and 13 Python tests; the source sweep parses 36/36
text files; reference capture matches the approved M0 golden except for its
timestamp. Thirteen focused Confusion processes exited zero with empty stderr.
M1 FALSE evidence and limitations are in `docs/evidence/M1/REPORT.md`; the
slice merged in [PR #10](https://github.com/quaat/mdl-racket/pull/10).

## M1 issue #4: atom identity and OBLIST (merged)

**Local slice checks: PASS. M1 milestone: NOT YET PASS.** Identity-bearing ATOM
and OBLIST values replace the symbol placeholder. Direct reader names and
`!-` trailers intern through an atom space; `ATOM`, `MOBLIST`, `LOOKUP`,
`INSERT`, `REMOVE`, `OBLIST?`, and `PNAME` have focused implementations.
`make test` passes 83 Racket checks and 13 Python tests; seven focused
Confusion processes exited zero with empty stderr. Dynamic `.OBLIST`,
associations, full OBLIST structure, and general binding semantics remain
unsupported. See `docs/evidence/M1/ATOMS.md` for commands and deviations.

## M1 issue #5: mutable sequences and shared views (merged)

**Local slice checks: PASS. M1 milestone: NOT YET PASS.** LIST values now use
mutable shared tails; VECTOR and UVECTOR values use shared storage views.
`REST`, `NTH`, `LENGTH`, `PUT`, `PUTREST`, and `UTYPE` have tested behavior on
the supported sequence types. Direct FALSE payloads and quoted structured
literals retain MDL atoms and mutable structure identity. `make test` passes
125 Racket checks and 13 Python tests. Ten successful Confusion probes exited
zero with empty stderr; one deliberate UVECTOR error case is recorded
separately. The five-turn capture matches the approved M0 golden except for
`captured_at`. See `docs/evidence/M1/SEQUENCES.md` for exact evidence and
limits. Type constructors, full bindings, and 36-bit arithmetic remain open.

## M1 issue #6: type tags and constructors (merged)

**Local slice checks: PASS. M1 milestone: NOT YET PASS.** `PRIMTYPE`,
`TYPEPRIM`, `NEWTYPE`, and structured `CHTYPE` now preserve user type tags
and shared LIST/VECTOR/UVECTOR storage. The implementation rejects mismatched
primitive types and unimplemented built-in and WORD conversions. Nine focused
Confusion cases exited zero with empty stderr; `make test` passes 152 Racket
checks and 13 Python tests. Source sweep remains 36/36 text files, and the
five-turn reference capture matches the approved golden except for timestamp.
See `docs/evidence/M1/TYPES.md` for commands, hashes, and limits. Local/global
binding semantics and 36-bit arithmetic remain open.

## M1 issue #7: local and global bindings (merged)

**Local slice checks: PASS. M1 milestone: NOT YET PASS.** Atom-keyed globals
and dynamic local frames replace the bootstrap string table and lexical-only
parameter lookup. `SET`, `SETG`, `LVAL`, `GVAL`, `VALUE`, and `GUNASSIGN` have
reference-backed behavior on the supported function subset. Nine focused
Confusion cases exited zero with empty stderr; three expected error probes
are preserved separately, including Confusion's missing `UNASSIGN` builtin.
`make test` passes 176 Racket checks and 13 Python tests. The approved house
golden still matches except for timestamp. See `docs/evidence/M1/BINDINGS.md`.
Optional/auxiliary arguments, explicit environments, and 36-bit arithmetic
remain open.

## M1 issue #8: 36-bit FIX and WORD operations (merged)

**Local slice checks: PASS for the documented subset. M1 milestone: NOT YET
PASS.** FIX input and arithmetic now enforce the manual's 36-bit signed
range; WORD values use a 36-bit mask. The slice implements octal and `#WORD`
literals, integer division, MOD, WORD casts, ANDB/ORB/XORB/EQVB, LSH,
BITS/GETBITS/PUTBITS, and type-sensitive numeric identity. `make test`
passes 262 Racket checks and 13 Python tests; the selected historical text
sweep still parses 36/36 files. Nine focused Confusion cases exit zero with
empty stderr, and two deliberate error cases are saved. The house capture
matches the approved golden except for timestamp. Confusion uses 64-bit
WORD output, allows FIX beyond the PDP-10 range, returns zero for `</>`,
and lacks ROT; the Racket target follows the historical manual on 36-bit
limits and `</>` and leaves ROT unsupported. See
`docs/evidence/M1/WORDS.md` for exact evidence and limits.

## M1 integrated gate on main

**PASS on `main` at merge commit
`a68cbb970b7028853fbcf7885c6c7c42f9470fe5`.**
The M1 gate in `docs/PLAN.md` requires independent Confusion-backed primitive
tests, property and mutation-aliasing tests, and explicit failure on
unsupported constructs. All five primitive slices have local and harness/
native CI PASS. The integrated audit adds three Confusion cases for equality
and evaluation order, nine Racket assertions, and three red-to-green strict
compiler checks. `make test` passes 274 Racket checks and 13 Python tests;
`make sources` verifies both pins; the current M1 sweep parses all 36 text
files. A fresh native build changes the binary hash and its embedded banner
timestamp. The five-turn reference capture matches the approved M0 golden
after excluding `captured_at`, `engine_sha256`, and that banner timestamp.
All 60 successful M1 probe results and six expected error observations match
their saved outputs on the rebuilt oracle. Details, exact commands, merge
SHAs, and limitations are in `docs/evidence/M1/GATE.md`. No Racket Zork
execution or gameplay parity is claimed.

## M2 issue #20: scoped PROG and bare RETURN

**Local slice: PASS. M2 milestone: NOT YET PASS.** Unnamed
`PROG` now creates an auxiliary local frame and returns its last body value;
bare `RETURN` exits the closest `PROG` within the current function. Initializers
run in order before their own new binding is installed, so they can read an
outer binding, while later initializers see earlier new bindings. An unassigned
auxiliary can be assigned with `SET`. Nested exits restore local frames, and a
bare `RETURN` in a called function cannot exit its caller's `PROG`.

`make test` passes 294 Racket checks and 13 Python tests. Nine focused pinned
Confusion cases exited zero with empty stderr; three expected error cases are
saved separately. Confusion crashes with signal 11 on `RETURN` in a PROG
auxiliary initializer; Racket follows the manual's activation-on-entry rule
for that case, and the deviation is recorded separately. `make check-source`
still parses 36/36 selected text files.
The five-turn reference capture and baseline probes pass, and the M1 golden
comparison passes with its documented build-metadata exclusions. Named
activations, explicit target `RETURN`, `REPEAT`, `AGAIN`, `GO`, `UNWIND`,
complex function formals, macros, and source loading remain unsupported.
Exact commands, hashes, and observations are in `docs/evidence/M2/PROG.md`.

## M2 issue #22: activation frames and function ownership

**Local hardening slice: PASS. M2 milestone: NOT YET PASS.** The unnamed PROG
subset now has an explicit dynamic stack of activation frames. Each frame
belongs to one function invocation and becomes invalid on normal completion,
RETURN, or an error. Bare RETURN resolves the nearest live frame belonging to
the current function; a called DEFINE cannot consume its caller's frame.
`make test` passes 308 Racket checks and 13 Python tests. Pinned source
verification and the 36/36 text reader sweep pass. A rebuilt Confusion
reproduces the nine saved successful M2 cases and three expected errors; the
five-turn capture, 12 baseline probes, and approved M1 comparison pass under
the documented build-metadata exclusions. Named/explicit activation targets
remain unsupported. Cyclic structural equality is tracked separately in
issue #23. See `docs/evidence/M2/ACTIVATIONS.md` for exact evidence and limits.

## M2 issue #23: cyclic structural equality boundary

**Local hardening slice: PASS. M2 milestone: NOT YET PASS.** `=?` now returns
true for the same cyclic object, false when two cycles differ before a repeated
comparison, and an explicit unsupported error when a pair of distinct
structured objects repeats on the active comparison path. Finite acyclic
values, including shared substructures, retain their structural result.
`==?` identity behavior is unchanged. `make test` passes 319 Racket checks
and 13 Python tests; source sweep remains 36/36 selected text files. Five
focused Confusion cases succeed, while one distinct LIST-cycle probe times out
at two seconds and one distinct VECTOR-cycle probe exits by signal 11. These
are recorded separately, not counted as passing oracle cases. The five-turn
capture, 12 baseline probes, and M1 approved comparison pass with documented
build-metadata exclusions. See `docs/evidence/M2/EQUALITY.md` for exact
commands, hashes, and unresolved semantics.

## M2 issue #26: unnamed REPEAT and bare AGAIN

**Local slice: PASS. M2 milestone: NOT YET PASS.** Unnamed REPEAT binds
auxiliaries once, repeats its body until RETURN, and shares the activation
stack with PROG. Bare AGAIN restarts the nearest PROG or REPEAT within the
current function without rebinding auxiliaries. Bare RETURN exits either.
Named activations and explicit target transfers remain unsupported and fail
at compile time. `make test` passes 331 Racket checks and 13
Python tests; the 36/36 selected historical text files still parse. Five
finite Confusion cases exited zero with empty stderr and match the Racket
assertions. The five-turn capture, 12 baseline probes, and approved M1
reference/golden comparison pass. See `docs/evidence/M2/REPEAT.md` for
commands, hashes, one transient `/var/tmp` test-runner failure, and remaining limits.

## M2 issue #28: named activations and explicit targets

**Local slice: PASS. M2 milestone: NOT YET PASS.** Named PROG/REPEAT now
bind an opaque ACTIVATION before their auxiliaries. Explicit RETURN/AGAIN
can target a live enclosing PROG/REPEAT, including across a called simple
DEFINE; bare transfers still obey current-function ownership. TYPE reports
ACTIVATION and PRIMTYPE reports FRAME. Wrong-type and stale targets fail
explicitly. `make test` passes 347 Racket checks and 13 Python tests; the
source sweep parses 36/36 selected text files. Eleven focused Confusion
processes exited zero with empty stderr. Six separate invalid-target,
duplicate-name, and unbound-LEGAL? observations include one signal-11 crash
and are not counted as successes. Native build, five-turn capture, 12 baseline
probes, and the approved M1 golden comparison pass locally. Function
activation formals, GO, UNWIND, and original game execution remain open.
See `docs/evidence/M2/ACTIVATION-TARGETS.md` for exact commands, hashes,
deviations, and remaining limits.

## M2 local task: OPTIONAL/AUX/TUPLE/ARGS function formals

**Local slice: PASS. M2 milestone: NOT YET PASS.** `DEFINE` now accepts
historical formal-list sections marked by strings: `"OPT"`/`"OPTIONAL"`,
`"AUX"`/`"EXTRA"`, `"ARGS"`, and `"TUPLE"`, in the reference order required
→ OPTIONAL → one ARGS/TUPLE rest binding → AUX. Defaults evaluate left to
right in the growing function frame; unsupplied optionals and bare AUX locals
stay unassigned; AUX restores outer locals on return. TUPLE binds remaining
arguments as a value with TYPE and PRIMTYPE `TUPLE` (its own primitive type;
`TYPEPRIM TUPLE` is `TUPLE`, `REST` keeps the TUPLE type); ARGS binds them as
a LIST. Arity failures use the historical `TOO-FEW/TOO-MANY-ARGUMENTS-SUPPLIED`
and `BAD-ARGUMENT-LIST` error names. An ATOM named AUX is an ordinary formal.
Malformed formal lists fail at compile time; Confusion validates them at call
time, a documented stricter deviation. The slice is tracked by
[issue #30](https://github.com/quaat/mdl-racket/issues/30) and
[PR #32](https://github.com/quaat/mdl-racket/pull/32); the full task record
is `docs/evidence/M2/FORMALS.md`.
`make test` passes 408 Racket checks and 13 Python tests (the sandboxed
session ran the Python half under system Python 3.9 with repo-local pinned
wheels; see the report). The Codex review of PR #32 found PUTREST splicing
TUPLE storage; both PUTREST operands are now validated through PRIMTYPE
and non-LIST-primtype values fail explicitly (fix commit `72ac750`). The 36/36 text reader sweep passes; the five-turn
capture, 12 baseline probes, the approved M1 golden comparison, and all 69
saved M2 success cases plus 20 expected-error observations reproduce exactly
against the pinned binary. Twenty-four focused Confusion formals probes
succeeded; eleven error observations are recorded separately.
`"NAME"`/`"ACT"`/`"BIND"`/`"CALL"` activation formals, quoted formals,
activation-name atoms before the formal list, GO, UNWIND, macros, and source
loading remain unsupported. See `docs/evidence/M2/FORMALS.md` for commands,
hashes, deviations, and remaining limits.

## M2 local task: activation formals, GO, and UNWIND

**Local slice: PASS. M2 milestone: NOT YET PASS.** `DEFINE` now accepts a
function activation name ATOM between the name and the formal list (the form
the 1977 reconstruction uses 14 times, e.g. `SEARCH-LIST SL`) plus the
`"NAME"`/`"ACT"` markers after any formal section. The activation exists
before formal binding, so RETURN during an AUX initializer exits the call;
explicit RETURN/AGAIN target it from any depth, unwinding intervening PROGs;
AGAIN re-runs the body without re-binding; bare transfers never target
function frames. `GO` follows the MDL manual chapter 10: top-level atoms in
PROG/REPEAT bodies are labels skipped in normal flow, and GO resumes at the
following expression in the nearest owned frame; the pinned Confusion has no
GO or TAG, a recorded reference deviation, and TAG values remain
unsupported. `UNWIND` runs its cleanup when a nonlocal transfer or an error
crosses below it and returns the guarded expression's value otherwise;
Confusion skips the cleanup on errors, a deviation the Racket runtime does
not copy (manual chapter 16). `make test` passes 465 Racket checks and 13
Python tests under the documented sandbox environment after both Codex
review fixes (PUTREST TUPLE rejection in PR #32 and octal-token label
exclusion here); the 36/36 reader
sweep passes; the five-turn capture, 12 baseline probes, the approved M1
golden comparison, and all 65 saved M2 success cases plus 27 expected-error
observations reproduce against the pinned binary. Sixteen focused Confusion
control probes succeeded; seven error observations are recorded separately.
`"BIND"`/`"CALL"` markers, TAG, the FSUBR `BIND`, and macros/source loading
remain unsupported. The slice is tracked by
[issue #31](https://github.com/quaat/mdl-racket/issues/31) and
[PR #33](https://github.com/quaat/mdl-racket/pull/33); the full task record
is `docs/evidence/M2/CONTROL.md` with commands, hashes, deviations, and
remaining limits.

## M2 local task: DEFMAC expansion and quoted formals

**Local slice: PASS. M2 milestone: NOT YET PASS.** The macro slice adds
`DEFMAC`, FORM construction and evaluation, one-step `EXPAND`, and quoted
formals in interpreted DEFINE and DEFMAC. Plain supplied arguments and
TUPLE rest arguments evaluate in the caller frame; ARGS keeps raw source
arguments. A macro expansion can define a callable function. Interpreted
function ownership prevents a bare RETURN from escaping the caller's PROG.
`make test` passes 513 Racket checks and 13 Python tests. The selected text
sweep still parses 36/36 files. Twenty-five pinned Confusion success cases
exit zero with empty stderr, and eight separate error observations match
their saved outputs. The five-turn house capture matches the approved M0
golden after the documented capture/build timestamp exclusions. Confusion's
caller-local expansion behavior differs from the manual's top-level wording;
Confusion also evaluates non-macro EXPAND input and prints a debug message,
while Racket keeps the form unchanged. Malformed formal-list error order
also differs. Full details and commands are in
[`docs/evidence/M2/MACROS.md`](evidence/M2/MACROS.md), tracked by
[issue #34](https://github.com/quaat/mdl-racket/issues/34).
Source loading, declarations, general APPLY/DISPATCH, and original game
execution remain open. The first unmet **milestone** gate is still M2.
The PR review follow-up fixes empty auxiliary LISTs in interpreted
PROG/REPEAT and keeps a leading activation name separate from quoted
formals in directly compiled and generated definitions. Ten new pinned
Confusion cases match the Racket regressions; the red-to-green record is in
[`docs/evidence/M2/MACROS.md`](evidence/M2/MACROS.md#review-follow-up).

## M2 infrastructure task: faster CI Racket setup

**CI task: PASS. M2 milestone: NOT YET PASS.** Both workflows passed on the
digest-pinned minimal Racket `8.10-bc` container: [harness run
44353286644](https://github.com/quaat/mdl-racket/actions/runs/44353286644)
and [native run
44353286715](https://github.com/quaat/mdl-racket/actions/runs/44353286715).
The harness log spans about 32 seconds and the native log about 43 seconds,
including image pull, dependencies, and cleanup. The same-day apt baselines
were 40 seconds for the harness and 84 seconds for one native run; a later
native apt run took about 17 minutes due to its dependency install. These
are individual runs, not a controlled benchmark. The full comparison,
commands, and limitations are in
[`docs/evidence/M2/CI-SETUP.md`](evidence/M2/CI-SETUP.md), tracked by
[issue #36](https://github.com/quaat/mdl-racket/issues/36) and
[PR #37](https://github.com/quaat/mdl-racket/pull/37). No MDL semantics or
upstream source changed. Source loading and original game execution remain
the next M2 work.
