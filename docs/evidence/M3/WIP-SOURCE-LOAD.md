# M3 WIP: full source load, startup frontier

Date: 2026-11-22. Base `main` commit:
`fdf48e4a5d1baa4f02faf00b824aa1e275f2e365`. Implementation WIP commit:
`c5a6027a56017c12f7081e1025937490a9fbc164` on
`feat/m3-logical-gc`. This document records the pre-integration result;
the formal M3 gate remains **FAIL / incomplete**.

## Source identity and gate results

`sources.lock.json`: MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916`; mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`. The locked
`77rooms.mud` SHA256 is
`e89337af98565292f84cfb10e9239924e99918325c9e1ac39b6bce692f5aff94`.
No `.cache/upstream/` file or source lock was changed.

| Stage | Result | Evidence |
|---|---|---|
| PARSED | PASS | 36 text files parsed, 4 nontext files identified |
| LOADED | PASS on branch | 1,229 original forms, 0 skipped, loader exit 0, all 13 expected files in order |
| INITIALIZED | FAIL | Original `START "WHOUS" ""` reaches unassigned `RANDOM` after welcome output and CRLF |
| INTERACTIVE | NOT RUN | Original loop and input channel path not yet available |
| SMOKE_PARITY | NOT RUN | No Racket transcript or state comparison |
| PLAYABLE | NOT RUN | No complete original game startup |

`TMPDIR=/tmp make m3-source-progress` exits 0 and reports `LOADED`; its
machine-readable output is `artifacts/m3/source-progress.json` (generated).
The progress command still treats a partial loader as a measurement, so it
is not an aggregate M3 acceptance command. A strict `m3-check` remains to
be built once initialization and interaction tests exist.

## Implemented source dependencies

The WIP branch adds a session-local weak-box logical allocation ledger for
LIST cells and VECTOR/UVECTOR backing storage, explicit real host GC and
logical reclaimed-word returns, BLOAT free-space requests, and safe automatic
pressure dispatch. Original `GC-FCN` and `DIVERT-FCN` source handlers are
exercised in `tests/historical_gc_handler_test.rkt`. This model does not
claim PDP-10 byte identity, count atoms/closures/strings, or reproduce the
historical automatic GC threshold.

Further source-driven slices cover SPECIAL/UNSPECIAL declarations, LOSE and
CHANNEL types, ERROR interrupt/ERRET, numeric predicates, ISTRING and shared
STRING REST views, structured TYPE heads, BLOCK/ENDBLOCK lookup, IUVECTOR,
CHUTYPE, IVECTOR, MAPR, MIN, custom ATOM/STRING typing, `#NEXIT` strings,
named OBLIST associations, empty UVECTOR UTYPE, and SPNAME. Startup probes
then led to GETTIMEDATE, default terminal CHANNEL metadata, and
PRINTSTRING's channel/count arguments. Unsupported constructs still error.
The exact behavioral boundaries are documented in `docs/SEMANTICS.md`.

## Commands and failures

Toolchain: Racket v7.9 [bc], Python 3.13.0.

| Command | Exit | Result |
|---|---:|---|
| `TMPDIR=/tmp make test` | 0 | 1,471 Racket checks, 23 Python tests after CI fixture repair and GC/UVECTOR regressions |
| `TMPDIR=/tmp make m2-check` | 0 | M2 reference and regression gate |
| `TMPDIR=/tmp make m3-source-progress` | 0 | LOADED, 1,229 forms, 0 skipped, loader exit 0 |
| `TMPDIR=/tmp raco test tests/printstring_channel_test.rkt tests/terminal_channel_test.rkt tests/gettimedate_test.rkt` | 0 | 17 focused checks |
| `TMPDIR=/tmp raco test tests/crlf_test.rkt` | 0 | 3 focused checks after a missing-operator failure |
| `TMPDIR=/tmp raco test tests/iuvector_chutype_test.rkt` | 1 then 0 | New alias checks failed with FIX, then passed with shared UTYPE header and complete storage conversion |
| `TMPDIR=/tmp raco test tests/logical_gc_test.rkt` | 0 | 44 checks including shared storage, cycle collection, callback exception and session isolation |
| `TMPDIR=/tmp make test-m3-historical-gc` | 0 | Source lock verified; 18 checks including exact 1,229 form load, zero skips and file order |
| GitHub Actions Native Confusion reference, run 45048914454, head `5719b3f` | 2 | `raco test` was unavailable in the container because `compiler-lib` was omitted; source verification and source-progress steps passed before this failure |
| direct `mdl-session-load!` then `mdl-session-call` of original `START` | shell 0; semantic failure | `mdl-eval: unassigned or non-applicable MDL operator RANDOM`; wrapper caught the exception, so shell exit 0 is not a startup pass |

The focused tests were observed failing first on their respective missing
operators or behavior. `tests/empty_uvector_test.rkt` failed on a FALSE
UTYPE before the fix; `tests/moblist_association_test.rkt` failed on missing
associations. The full suite later passed. Pinned Confusion probes for
SPECIAL and ISTRING are saved as
[`special-reference.json`](special-reference.json) and
[`istring-reference.json`](istring-reference.json). The
[`chutype-alias-reference.json`](chutype-alias-reference.json) probe records
the shared UVECTOR UTYPE header in pinned Confusion. The original M2
reference capture remains available through `make m2-check`. Confusion's
GC/BLOAT stubs cannot validate the new logical memory semantics. The MIN
zero-argument cast differs in magnitude because Confusion uses host-sized
FLOAT bits; the branch models 36-bit FIX behavior.

Reference game conditions: approved scenario
`tests/scenarios/house.json` uses `west`, `open mailbox`, `take leaflet`,
`inventory`, `score` from the north side of the house. No candidate RNG
sequence or candidate transcript exists yet. GETTIMEDATE reads the host
clock unless an explicit timestamp is supplied. No golden comparison is
claimed.

Security and licensing: all interpreter execution remains local to a
source-root-restricted session; no network service or evaluator endpoint was
added. Confusion remains a separately built GPLv3 reference; no Confusion
source was copied into the MIT-0 runtime. The branch needs independent
review of evaluation, memory and loader changes before integration.

The follow-up CI repair installs `compiler-lib` in the Native Confusion
reference workflow before its source-dependent GC test. The Harness checks
workflow passed on `5719b3f`. Both required workflows must pass on the
final PR head before this review checkpoint is considered CI-clean.

After adding CRLF, the next executable task is a session-owned 36-bit RANDOM
with reference-validated seed and call-order behavior. Review its provenance
before implementation; GPLv3 Confusion is a reference, not MIT-0 code to
copy. Continue the original `START` call through initialization. Then connect
`READSTRING`, the original parser/game loop, and a strict five-command
house-smoke parity gate. The startup failure is a feature dependency, not
an approval blocker.
