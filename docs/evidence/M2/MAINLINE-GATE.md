# M2 mainline acceptance — 2026-11-21

**Decision: PASS for the documented M2 Build and Gate.** The integrated
code baseline is `7d341955a5fd3263dc2c724cc778730187eeb64d` on `main`.
This is an execution-semantics and initial-definition gate, not a complete
MDL implementation, full game load, initialized game, or gameplay parity.
The [requirements matrix](REQUIREMENTS-AUDIT.md) defines the tested surface.

## Integration and review

The maintainer explicitly authorized this dependency stack on 2026-11-21.
Each PR was retargeted to `main` after its prerequisite, its ancestry and
changed-file list were checked, and GitHub reported it mergeable. No force
merge or branch-protection bypass was used. All PR review threads were
resolved before integration; the D5 independent review and red-to-green
fixes are recorded in [D5-FINAL-REVIEW.md](D5-FINAL-REVIEW.md). The MAPF
and APPLY application/control paths were reviewed with their focused
native evidence and tests. The historical FAIL reports were retained.

| PR | Merge commit on `main` | `main` harness run |
|---|---|---|
| [#54](https://github.com/quaat/mdl-racket/pull/54) | `21753bc9e4a609d4d83c3964847b482eb4e77b37` | [44889209069](https://github.com/quaat/mdl-racket/actions/runs/44889209069), success |
| [#59](https://github.com/quaat/mdl-racket/pull/59) | `ae5bafb62bbad2dfa87b787e5bd84b1bbca87e49` | [44889288139](https://github.com/quaat/mdl-racket/actions/runs/44889288139), success |
| [#61](https://github.com/quaat/mdl-racket/pull/61) | `ca8b244674c783de0aa6dddddc6b329b659c15a5` | [44889317729](https://github.com/quaat/mdl-racket/actions/runs/44889317729), success |
| [#62](https://github.com/quaat/mdl-racket/pull/62) | `bf4fd1bd1eeb1df9d31bcc27bd2dad264eb6e854` | [44889409008](https://github.com/quaat/mdl-racket/actions/runs/44889409008), success |
| [#64](https://github.com/quaat/mdl-racket/pull/64) | `f543d7005a99c77133585ce4111dcaf95d7614ff` | [44889514817](https://github.com/quaat/mdl-racket/actions/runs/44889514817), success |
| [#66](https://github.com/quaat/mdl-racket/pull/66) | `9b1a8ffdf284ffaf88997b69c5c5743ab7c6cb0f` | [44889582954](https://github.com/quaat/mdl-racket/actions/runs/44889582954), success |
| [#68](https://github.com/quaat/mdl-racket/pull/68) | `fc5e0dc2b5d9e71b66ff5fed2c8c50cff79bd793` | [44889648153](https://github.com/quaat/mdl-racket/actions/runs/44889648153), success |
| [#70](https://github.com/quaat/mdl-racket/pull/70) | `7d341955a5fd3263dc2c724cc778730187eeb64d` | [44889721673](https://github.com/quaat/mdl-racket/actions/runs/44889721673), success |

Both required PR-head workflows passed on all eight final heads (16/16).
On the final #70 head, Harness run 44810524348 and Native Confusion run
44810524316 succeeded. The native job runs the pinned sources, original
G3 and Confusion capture/probe; `main` itself triggers the harness job.

## Exact mainline checks

Local toolchain: Racket 7.9 [bc], Python 3.13.0, BDW GC 8.0.4. All commands
below ran from `7d34195`. `make m2-check` invokes the listed subcommands;
its full local log was `/tmp/mdl-m2-main-check.log` at gate time. The reader
sweep was redirected to `artifacts/m2/reader-sweep.json` to preserve M0
evidence.

| Command | Exit and observed result |
|---|---|
| `make reference-build` | 0; rebuilt pinned Confusion; upstream checkout clean |
| `make doctor` (inside `make m2-check`) | 0; required tools found |
| `make sources` (inside `make m2-check`) | 0; both locked repositories verified |
| `make check-source` (inside `make m2-check`) | 0; 36 parsed text files, zero failures, four nontext files |
| `make test` (inside `make m2-check`) | 0; 986 Racket checks, 13 Python tests |
| `make test-historical` (inside `make m2-check`) | 0; VFLOAD 23, DECL 21, original MSETG/PSETG probes |
| `make test-m2-g3` (inside `make m2-check`) | 0; 59 assertions from exact original definitions in one session |
| `make reference-probe` (inside `make m2-check`) | 0; 12 native expressions |
| `make reference-capture` (inside `make m2-check`) | 0; five-turn house-smoke native capture |
| `make m2-check` | 0; all above plus `git diff --check` |
| `make compare CANDIDATE=artifacts/reference/house.json` | 0; native self-check only |
| `make compare CANDIDATE=docs/evidence/M0/house-golden.json` | 2; sole mismatch is Confusion's native build timestamp in initial banner |
| In-memory comparator after replacing only that build-timestamp line in both captures | 0; zero differential mismatches, matching game SHA, five complete turns |
| `racket scripts/mdl_load.rkt --source-root .cache/upstream/mdlzork/mdlzork_771212/patched_confusion --entry 77loadall.mud --report artifacts/m2/mainline-full-load.json` | 1; expected next M3 barrier, 24 completed and zero skipped forms at `EMPTY?` |
| `git diff --check` | 0 |

The capture used the approved house-smoke inputs `west`, `open mailbox`,
`take leaflet`, `inventory`, `score`. No seed was set; these five native
turns did not exercise observable random behavior. Fresh capture and M0
golden both use game SHA256
`92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6a1b0ffb7a4`.
The fresh native binary SHA256 was
`cd7bfffe22265b3f63dfd2713330507c53e6182ec9f41ba4aa3d818127252580`.
The direct golden comparison's timestamp mismatch is reported rather than
called a strict PASS; no Racket game transcript exists to compare yet.
The normalized observation above is reproducible without writing either
capture:

```bash
python3 - <<'PY'
import json, re
from pathlib import Path
from scripts.compare_transcripts import differences
a = json.loads(Path('artifacts/reference/house.json').read_text())
b = json.loads(Path('docs/evidence/M0/house-golden.json').read_text())
for value in (a, b):
    value['initial_output'] = re.sub(
        r'This Confusion created [^\n]+',
        'This Confusion created <build timestamp>', value['initial_output'])
assert a['game_sha256'] == b['game_sha256']
assert differences(a, b) == []
print('normalized native golden: 5 turns, zero mismatches')
PY
```

## Source, semantics and first M3 dependency

`sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`. SHA256 of the exact
executed `77loadall.mud`, `81prim.mud` and `77defs.mud` is respectively
`389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa`,
`8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`,
and `566ebcc32be9b9226dd7cefd77a517583eebab80a03f452df39e13b85eed734e`.
No pinned source bytes changed.

Supported M2 surface includes the audited DEFINE formals and declarations,
DEFMAC and expansion, COND, PROG/REPEAT, activation RETURN/AGAIN,
MAPF and map control, UNWIND's documented manual contract, indirect APPLY,
computed operators, initial cross-file loading and shared mutation views.
The [matrix](REQUIREMENTS-AUDIT.md) and individual slice reports detail
native observations and red-to-green tests. The full original loader
returns **FAIL** at `77defs.mud` expression 15, line 37, execute stage:
`mdl-eval: unassigned or non-applicable MDL operator EMPTY?` inside
original NEWSTRUC. It has loaded the complete `81prim.mud` and a partial
`77defs.mud`. This is neither full source execution nor game initialization.

The plan's earlier random/event task-list entry was outside the M2 Build
and Gate; ADR-0030 assigns it explicitly to [M3 issue #71](https://github.com/quaat/mdl-racket/issues/71).
Explicit CLOSURE, MAPR, TAG, general applicable types, resumable ERROR/ERRET,
weak association GC and full historical continuation equivalence remain
unsupported or deviant. In particular, local UNWIND runs cleanup on an
error-level break while pinned Confusion skips it. No GPLv3 Confusion
implementation was copied into the MIT-0 runtime; no network evaluator
was exposed. No parser, puzzle, randomness, or gameplay parity is claimed.

**Next action:** preserve the M2 original-definition tests while removing
their exact 24-expression full-loader failure assertion. Add a separate
machine-readable M3 source-progress gate, then implement EMPTY? from
the pinned reference and rerun both suites. This architectural correction
must precede M3 implementation so new source progress cannot falsely fail
M2.
