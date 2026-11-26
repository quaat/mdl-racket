# PR #180 infrastructure remediation

The integration base is `522b56339865ed1226550e00968f330807d74525`.
The evidence-producing runner is
`65ec0f4069caa2c0e1590ca7c4d396f9c2209fb2`. Its MDL source tree has
the same digest as the base. The [PR verification record](https://github.com/quaat/mdl-racket/pull/180)
binds the complete final candidate and the CI jobs. No production MDL
implementation, historical source, golden, or existing workflow changes
are included.

## Reproduction and observations

Use Racket 8.10 BC, matching project CI. These local captures used
Python 3.13.5 with the pinned project requirements. The manual
transcription is `89707367b951ea79bedc71f51ab213886e0f62ce`. The source
locks and build details are in [the baseline record](BASELINE.md).

| Command | Observation |
| --- | --- |
| `make test-manual` | Exit 0. Both execution paths ran for each of 44 fixtures. 72 PASS, 16 XFAIL, zero FAIL and zero XPASS. |
| `python scripts/inventory_manual.py .cache/conformance-manual --check` | Exit 0. Regeneration checks the pinned source objects and validates retained results and native agreement. |
| `make test-conformance-harness` | Exit 0, 32 tests passed. Tests stale fixture records, missing and duplicate modes, inconsistent statuses, exact diagnostics, process failure, malformed worker replies, collection isolation and declaration relocation. |
| `python -m scripts.probe_manual --output artifacts/l0/native.json` | Exit 1. Of 44 native observations, 40 ran without diagnostics. Three hit native gaps and the deliberate NTH range test signaled `ARGUMENT-OUT-OF-RANGE`. The 20 previously reviewed input/output pairs were compared again before recording their new evidence digests. |

See the [typed results](manual-summary.json), [native observations](native-examples.json)
and [reviewed native agreement](native-agreement.json). The reference
checkout was locked at `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
Each native fixture used a fresh empty working directory, UTC, default
RNG and an explicit final QUIT. The reference stayed local.

The deadline and resource limits constrain the workers. Tests use reviewed
local fixtures. The worker protocol keeps startup, process and observation
failures distinct from an MDL failure. No general object serializer or
new execution entry point is part of PR #180.

## Review and remaining work

Independent review found an ambient collection resolution problem as well
as validation gaps involving incomplete result mode sets, native agreement,
non-finite values and numeric type aliases. The runner now resolves the
frontend from this checkout, and the evidence validator rejects those
malformed or stale records. Structural discovery reads declarations
without loading the production modules. The runner records both workspace
source bytes and the matching committed revision when available.

L0 acceptance stays open in [#178](https://github.com/quaat/mdl-racket/issues/178).
A follow-up after infrastructure integration will classify the outstanding
manual examples and annotate verified semantics by coverage dimension.
[#179](https://github.com/quaat/mdl-racket/issues/179) remains the first
runtime slice, subject to L0 acceptance and the explicit removal policy.

The first hosted conformance attempt at `ce88b643f5dcd8e9f7db2f6b3c21c61e0b7c6d7e`
exited 2 during inventory validation. Git rejected the container-mounted
workspace's ownership before any fixture ran. The workflow now registers
the single GitHub workspace path in the job's Git configuration.
[Initial CI log](https://github.com/quaat/mdl-racket/actions/runs/45372653150)
