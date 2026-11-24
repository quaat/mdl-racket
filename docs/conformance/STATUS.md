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
and 11 passing M4 scenarios in the [verification record](../evidence/L0/BASELINE.md).

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
  work still needed. Exact matched transcript examples can be verified
  in isolation. There is no overall conformance percentage.
- `make test-manual` exercises 44 fixtures across 21 chapters in the
  executable loader and `#lang mdl`. On 8.10 BC, 72 checks passed and 16
  matched tracked gaps. The runner reports fixture, chapter, feature and
  execution path. See the [fixture manifest](../../tests/conformance/manifest.json).
- The supplied candidate Racket tests passed all 10 test cases when run with
  adjusted import paths. The new corpus incorporates and labels relevant
  adaptations. The supplied gap notes were treated as candidate input.
  Native Confusion confirmed nested LVAL and explicit property lookup.
  It rejected SQRT, SETLOC and double-percent reader macros in the recorded
  probes. The range-error example signaled ARGUMENT-OUT-OF-RANGE.
  The three missing facilities are reference limits, with expected MDL results still
  drawn from the manual. [Native observations](../evidence/L0/native-examples.json)
- The independent review checked source citations, failure classification,
  multiline signatures, reference cross-checks and unchanged production
  sources. Marking a passing case as a known gap caused XPASS in both
  paths. Substituting an unrelated diagnostic caused FAIL. The review found
  an initial FALSE-payload observation bug and a bad sweep filename, both
  corrected. [Verification record](../evidence/L0/BASELINE.md)

## Next iteration

Complete L0's semantic annotations and fixture classification. Draft
[PR #180](https://github.com/quaat/mdl-racket/pull/180) contains the current
infrastructure and evidence. The matrix
indexes the remainder so the next pass can resolve setup, expectations and
platform requirements from stable source locations. Review L0 before
starting runtime changes.

For L1, the chosen issue is [#179](https://github.com/quaat/mdl-racket/issues/179).
The manual and pinned Confusion agree on identity, numeric dispatch and
fallback evaluation, but disagree on the explicit removal result. The
[preflight record](../evidence/L1-properties/PREFLIGHT.md) gives the observed
results, options and recommendation. Resolving that decision and completing
L0 are prerequisites for implementation.

## PR #180 infrastructure hardening

The inventory now describes a **historical** runtime snapshot. The generator
reads the manual, runtime declarations, existing tests and lexical evidence
from pinned Git objects. Moving lines before a declaration preserves the
candidate names and updates their source locations. The live workflow
runs the fixture corpus on every checkout of the shared runtime.

The evidence schema binds each expected and observed result to a canonical
fixture digest and one execution mode. It requires exactly one result per
fixture/mode pair. Retained results also name the exact runtime and runner
commits and digests, the manual revision and the observed toolchain. Native
agreement refers to a specific fixture, observation and reference binary.
Fixture changes require new observations and, where appropriate, renewed
native review. A runtime change is tested live without changing the
historical inventory.

The next L0 slice after infrastructure integration is the chapter-by-chapter
classification in #178. Keep operator, reader, type, error, transcript and
platform denominators separate. Existing semantic contracts and test paths
should be linked from the inventory where evidence is available. The
remaining historical platform examples and every unclassified transcript
candidate still need review before L0 acceptance.

Racket 9.3 CS custom-port compatibility is tracked independently in
[#181](https://github.com/quaat/mdl-racket/issues/181). The remaining manual
gaps have scoped owners for
[SQRT #182](https://github.com/quaat/mdl-racket/issues/182),
[reader literals and macros #183](https://github.com/quaat/mdl-racket/issues/183),
[EVAL and environments #184](https://github.com/quaat/mdl-racket/issues/184)
and [locatives #185](https://github.com/quaat/mdl-racket/issues/185).
