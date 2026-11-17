# Status — 2026-11-17 (M1 gate PASS on main)

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
