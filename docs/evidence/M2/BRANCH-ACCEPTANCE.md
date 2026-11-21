# M2 stacked branch acceptance — 2026-11-20

**Decision:** G3 execution **PASS on the stacked branch**; M2 milestone
acceptance **NOT RUN on `main`**. This report covers implementation commit
`3622b2299ed5681cc389da9bb685c9c2fe67963b` in
[PR #70](https://github.com/quaat/mdl-racket/pull/70), based on
[PR #68](https://github.com/quaat/mdl-racket/pull/68) at `8ec526b`.
PR #54 and its dependent stack remain unmerged. Mainline acceptance needs
authorized integration, review, final-head checks, and a fresh gate report
from `main`.

## Reproduction and results

| Command or check | Result at implementation commit |
|---|---|
| `make m2-check` | exit 0; includes doctor, sources, check-source, test, historical, G3, reference-probe, reference-capture, and `git diff --check` |
| `make test` | exit 0; 986 Racket checks and 13 Python tests |
| `make test-historical` | exit 0; original VFLOAD 23 assertions, DECL 21 assertions, MSETG/PSETG probes |
| `make test-m2-g3` | exit 0; 59 assertions in one session from hash-verified original definitions |
| `make reference-probe` | exit 0; 12 native primitive cases |
| `make reference-capture` | exit 0; five-turn native house transcript |
| `make compare CANDIDATE=artifacts/reference/house.json` | exit 0, native self-check only; fresh capture has the approved M0 golden's scenario, commands, completion and game SHA |
| `make check-source` | exit 0; 36 parsed text and four nontext files; `m2-check` redirects sweep output under `artifacts/m2/` |
| `git diff --check` | exit 0 |

The local native Confusion binary SHA256 was
`1d540d2df348479d4740290d4190533b71d94a8308193811b96e52898798b886`.
The two locked upstream commits are MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and
mdlzork/Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
The exact G3 source SHA256 values and original definition paths are in
[G3-GATE-MAPF.md](G3-GATE-MAPF.md). `make sources` found clean upstream
checkouts; no upstream bytes were edited.

GitHub Actions on `3622b22`: [Harness run 44810007078](https://github.com/quaat/mdl-racket/actions/runs/44810007078)
completed successfully, as did [Native Confusion run 44810007073](https://github.com/quaat/mdl-racket/actions/runs/44810007073).
The MAPF parent `8ec526b` passed both required workflows too
(runs 44807433837 and 44807434019). Later documentation-only commits
require their own final-head check before merge.

## Scope and next gate

The [requirements matrix](REQUIREMENTS-AUDIT.md) traces the tested M2
surface. [MAPF](MAPF.md), [indirect APPLY](INDIRECT-APPLY.md), and the
[original G3 scenario](G3-GATE-MAPF.md) have separate reference evidence.
The full `77loadall.mud` loader still exits 1 after 24 completed forms
at unassigned `EMPTY?` inside original `NEWSTRUC`; it is an M3 dependency,
not a successful boot. Explicit CLOSURE, MAPR, TAG, resumable ERROR/ERRET,
broader applicable values, parser startup and gameplay remain unsupported
or unverified. The UNWIND error-level behavior differs from pinned
Confusion as recorded in [CONTROL.md](CONTROL.md).

No GPLv3 Confusion code was copied into the MIT-0 runtime, and no raw MDL
evaluator was exposed on a network service. The next M2 action is review
and authorized integration of PRs #54, #59, #61, #62, #64, #66, #68 and
#70 in dependency order. Retarget and verify each after its prerequisite
merges, then rerun acceptance on `main` and publish its gate report.
M3 implementation must wait for that result.
