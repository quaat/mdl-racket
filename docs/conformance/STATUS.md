# Language conformance status

**L0 is in progress.** The inventory and the initial executable corpus are
reviewable. The remaining L0 work is to audit semantic contracts beyond the
initial annotations and classify or convert the remaining manual examples.
Track that work in [#178](https://github.com/quaat/mdl-racket/issues/178)
under the language epic [#177](https://github.com/quaat/mdl-racket/issues/177).

## Repository and toolchain

The clean local `main` matched the fetched `origin/main` at
`522b56339865ed1226550e00968f330807d74525` before development. The remote is
`git@github.com:quaat/mdl-racket.git`. This iteration uses
`feat/mdl-l0-conformance` from that commit. GitHub showed no open PRs at the
baseline. Six remote branch tips were outside mainline, for deferred DECL
resolution, duplicate DECL, the event handler, the interrupt dispatcher,
NTH declarations and M3 acceptance integration. The open game epic is #163.
PRINT is #173 and needs the maintainer's ERROR-routing decision. Other open
issues inspected were #113, #120, #121, #126, #127, #129, #134, #171 and #172.
No source conflict with the L0 changes was found.

Racket 8.10 BC, matching the CI version and VM, passed the language suite and
historical source checks. The initial Racket 9.3 CS run exposed six
host-loop assertion failures on the baseline. See the commands, lock SHAs,
and scenario outcomes in the [verification record](../evidence/L0/BASELINE.md).

## Coverage

- The generated inventory indexes all 35 manual pages, 418 headings, 599
  distinct documented names and 308 transcript prompt candidates. The name
  count combines primitive signatures, predefined types, error atoms and
  name-index entries, including names with multiple roles. Chapter coverage
  appears in the [coverage matrix](MDL-COVERAGE.md).
- Source locations are implementation candidates. Existing test and native
  mentions are lexical leads. The status `PARTIAL` on a registry match does
  not validate the operator's full semantics. Whole constructs remain
  unclassified as `VERIFIED` until their semantics, negative cases, and both
  execution paths have been audited. The inventory's unfilled fields record
  work still needed. There is no overall conformance percentage.
- `make test-manual` exercises 38 fixtures across 17 chapters in the
  executable loader and `#lang mdl`. On 8.10 BC, 60 checks passed and 16
  matched tracked gaps. The runner reports fixture, chapter, feature and
  execution path. See the [fixture manifest](../../tests/conformance/manifest.json).
- The supplied candidate Racket tests passed all 10 test cases when run with
  adjusted import paths. The new corpus incorporates and labels relevant
  adaptations. The supplied gap notes were treated as candidate input.
  Native Confusion confirmed nested LVAL and explicit property lookup.
  It rejected SQRT, SETLOC and double-percent reader macros in the recorded
  probes. Those are reference limits, with expected MDL results still
  drawn from the manual. [Native observations](../evidence/L0/native-examples.json)
- The independent review checked source citations, failure classification,
  multiline signatures, reference cross-checks and unchanged production
  sources. Marking a passing case as a known gap caused XPASS in both
  paths. Substituting an unrelated diagnostic caused FAIL. The review found
  an initial FALSE-payload observation bug and a bad sweep filename, both
  corrected. [Verification record](../evidence/L0/BASELINE.md)

## Next iteration

Complete L0's semantic annotations and fixture classification. The matrix
indexes the remainder so the next pass can resolve setup, expectations and
platform requirements from stable source locations. Review L0 before
starting runtime changes.

For L1, the chosen issue is [#179](https://github.com/quaat/mdl-racket/issues/179).
The manual and pinned Confusion agree on identity, numeric dispatch and
fallback evaluation, but disagree on the explicit removal result. The
[preflight record](../evidence/L1-properties/PREFLIGHT.md) gives the observed
results, options and recommendation. Resolving that decision and completing
L0 are prerequisites for implementation.
