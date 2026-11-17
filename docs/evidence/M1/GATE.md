# M1 semantic micro-runtime gate

**M1 gate: PASS on `main` at
`a68cbb970b7028853fbcf7885c6c7c42f9470fe5`.** This report audits issue
#17 on top of primitive commits
`766741efdee997a7a5f0a70a7e23dd3ad934d3d9` (#4),
`6037ecf7f354fdd5af67ab707ea56b825cef9d00` (#5),
`8fec75dca12bbb9800e8c8987a30d55edaa81fa4` (#6),
`cf1f3b809747519381e24ba8fe53ba2cc3a4fe97` (#7), and
`4ee6284cb0e79a2b00ff2fa3d18c4f68b8a75111` (#8). The gate audit
commit was `193aebd3f35ece53762a2b0cadab334063d6e52a` (#18). M1 issue #3
(FALSE) merged as PR #10 at `f823898732078c06ee48341d742dcf84acd157ba`.
Locked upstream commits are MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and patched Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

| Gate from `docs/PLAN.md` | State | Evidence and limits |
|---|---|---|
| Independent primitive tests | **PASS** | `make test`: 274 Racket checks and 13 Python tests; nine source files, including integration assertions |
| Confusion corroboration | **PASS with documented deltas** | 60 successful isolated M1 cases (13 FALSE, 7 atoms, 10 sequences, 9 types, 9 bindings, 9 words, 3 integrated), every child exit 0 with empty stderr; six deliberate error observations stored separately |
| Property and mutation aliasing | **PASS** | LIST REST/PUT alias sweep for lengths 2–10, VECTOR/UVECTOR and FALSE payload alias tests, type cast round trips, and 36 shift-position checks |
| Equality and evaluation order | **PASS** | Three integrated reference cases and nine matching Racket assertions; numeric, LIST, and VECTOR structural versus identity checks; left-to-right argument mutation |
| Explicit unsupported failure | **PASS on tested boundaries** | Unknown `#` reader token, scientific notation in the unsupported compiler subset, invalid octal, unsupported typed literals, unassigned bindings, primitive type mismatch, invalid bit ranges, and ROT fail explicitly |
| Selected historical reader sweep | **PASS** | `make check-source`: 36/36 UTF-8 MDL files parsed; four binary/non-text files classified; `docs/evidence/M1/reader-sweep.json` |
| Native reference and golden | **PASS** | `make reference-capture`: complete opening plus five commands; every field except `captured_at` matches approved M0 fixture; `make reference-probe`: 12/12 |
| Harness and native CI for primitive heads | **PASS** | Both workflows succeeded for PRs #12–#16; links below |
| Ancillary automated code review | **BLOCKED** | GitHub Codex review did not run because its usage limit was reached; no inline findings were produced. The maintainer approved merging the passing M1 stack. |
| Gate audit PR CI | **PASS** | Final [harness run 44149484269](https://github.com/quaat/mdl-racket/actions/runs/44149484269) and [native run 44149484182](https://github.com/quaat/mdl-racket/actions/runs/44149484182) both succeeded |
| M1 merged to `main` | **PASS** | PRs #12, #13, #14, #15, #16, then #18 merged in dependency order; combined tree verified locally at `a68cbb970b7028853fbcf7885c6c7c42f9470fe5` |
| Mainline test and source sweep | **PASS** | `make test`: 274 Racket checks and 13 Python tests; `make check-source`: 36 parsed, 0 failed, 4 non-text |
| Mainline native comparison | **PASS with build metadata excluded** | Rebuilt Confusion; five-turn gameplay fields match approved M0 fixture after excluding capture time, binary hash, and embedded build timestamp; all 60 successful M1 results and six expected error observations match saved outputs |

## Reproduction and exact results

| Command | Exit | Observed output |
|---|---:|---|
| `make doctor` | 0 | Python 3.13.0; Racket 7.9 [bc]; Git, GCC/G++, Make, Perl, pkg-config found; BDW GC 8.0.4 |
| `make sources` | 0 | `Verified 2 source repositories`; locked SHAs and clean checkouts |
| `make test-racket` before strict-token fix | 2 | 3/274 failures: `#UNKNOWN`, `1E2`, and `*8*` compiled as atoms instead of failing |
| `make test` after fix | 0 | `274 tests passed`; `13 passed` in Python |
| `make check-source` | 0 | `{'parsed': 36, 'failed': 0, 'non-text': 4}`; current sweep copied under M1 and frozen M0 sweep restored |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M1/integration-cases.json --output docs/evidence/M1/integration-reference.json` | 0 | Three children exit 0, empty stderr |
| `make reference-capture` | 0 | Five-turn `artifacts/reference/house.json`, `complete=true`, runner `error=null`, PTY SIGHUP cleanup signal 1 |
| `make reference-probe` | 0 | Twelve primitive expressions probed |
| Python comparison of captured and approved house JSON after omitting only `captured_at` | 0 | `golden_match_excluding_time True` |
| `git diff --check` | 0 | No whitespace errors |

## Mainline integration verification

The approved merge sequence produced these commits: #12
`041f4c8f0edb22cd723d0dad495d9136870072ed`, #13
`2c24000c7b8101251257e057d206bae52b38227b`, #14
`0726518aea346dad6a2439817f33b700db9ca8b9`, #15
`b05a8c25fb5300de87c5e1b3c4db8a50ef1d9799`, #16
`acb86fe7d20ad8818e13be0d4d1f3996b24882d9`, and #18
`a68cbb970b7028853fbcf7885c6c7c42f9470fe5`. Each PR was retargeted
to `main` and checked to contain only its intended slice before merging.

| Command on merged `main` | Exit | Observed output |
|---|---:|---|
| `make doctor` | 0 | Python 3.13.0, Racket 7.9 [bc], BDW GC 8.0.4 and required build tools found |
| `make sources` | 0 | Two locked commits verified; upstream checkout clean |
| `make test` | 0 | `274 tests passed`; `13 passed` |
| `make check-source` | 0 | `{'parsed': 36, 'failed': 0, 'non-text': 4}`; generated M0 sweep restored after inspection |
| `make reference-build` | 0 | Native Confusion rebuilt from pinned source with build-only `-include cstdint` flag; no upstream changes |
| `make reference-capture` | 0 | Five turns captured, `complete=true`, `error=null`, `process_exitstatus=null`, PTY cleanup `process_signalstatus=1` |
| `make reference-probe` | 0 | 12 isolated reference expressions probed |
| Fresh M1 probes versus saved `result_output`, `input`, `stderr`, and exit status | 0 | 60 successful cases and six expected error observations matched |
| Golden JSON comparison excluding only capture time, binary hash, and embedded build timestamp | 0 | `True`; all gameplay transcript fields match |

The fresh Confusion binary SHA-256 is
`78b28eed48026f4e3390ceae296afa2d55d10a7a1275a1e96e298a79d63383c8`.
The game image SHA-256 remains
`92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6a1b0ffb7a4`.
The approved golden SHA-256 remains
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
The previous binary SHA above belongs to the earlier captured build; rebuilding
embeds the current compile time and changes both binary hash and the banner
line. Only those two build-dependent fields and the capture timestamp were
excluded; command input and all game output were compared. The house scenario
has fixed input but no controlled RNG seed. No observed output changed in this
scenario; this does not establish deterministic behavior for other paths.

To reproduce the focused comparison after `make reference-build`, run:

```bash
.venv/bin/python - <<'PY'
import json, re
from pathlib import Path
from scripts.mdl_probe import probe_case
from scripts.reference_runner import EXE, GAME

root = Path('docs/evidence/M1')
for stem in ('false', 'atoms', 'sequences', 'types', 'bindings', 'word', 'integration'):
    cases = json.loads((root / (stem + '-cases.json')).read_text())['cases']
    saved = json.loads((root / (stem + '-reference.json')).read_text())['cases']
    assert len(cases) == len(saved)
    for case, old in zip(cases, saved):
        new = probe_case(EXE, GAME, case, 20)
        assert new['ok'] and new['exit_code'] == 0 and new['stderr'] == ''
        assert (new['input'], new['result_output']) == (old['input'], old['result_output'])
for stem in ('sequences', 'bindings', 'word'):
    cases = json.loads((root / (stem + '-error-cases.json')).read_text())['cases']
    saved = json.loads((root / (stem + '-error-reference.json')).read_text())['cases']
    assert len(cases) == len(saved)
    for case, old in zip(cases, saved):
        new = probe_case(EXE, GAME, case, 20)
        assert (new['input'], new['exit_code'], new['stderr'], new['result_output']) == (
            old['input'], old['exit_code'], old['stderr'], old['result_output'])
a = json.loads(Path('artifacts/reference/house.json').read_text())
b = json.loads(Path('docs/evidence/M0/house-golden.json').read_text())
for obj in (a, b):
    obj.pop('captured_at')
    obj.pop('engine_sha256')
    obj['initial_output'] = re.sub(r'This Confusion created [^\n]+',
                                   'This Confusion created <build timestamp>',
                                   obj['initial_output'])
assert a == b
print('M1 mainline reference and golden comparisons PASS')
PY
```

The focused case inputs and full stdout/stderr are in this directory:
`false-*`, `atoms-*`, `sequences-*`, `types-*`, `bindings-*`, `word-*`, and
`integration-*`. Expected-error harness suites return 1 by design; their
individual Confusion children exit 0 after printing an error and writing
stderr. They are not counted as successful oracle cases. The Confusion
binary SHA-256 is
`99728037f046ee68fdbb6ef69f44155e3c03f9c0b2b0840fbc218c75024c21e3`;
the reconstructed game image SHA-256 is
`92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6a1b0ffb7a4`.
The maintainer-approved M0 golden SHA-256 is
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
The house scenario uses fixed text input without a controlled RNG seed;
these primitive cases have no time or random input. Confusion embeds its
compile time in its banner, so a rebuilt native binary can change the
initial output. The reference runner's SIGHUP follows its documented PTY
cleanup after the fifth command.

The five PR heads have passing [harness](https://github.com/quaat/mdl-racket/actions/runs/44140861715)
and [native](https://github.com/quaat/mdl-racket/actions/runs/44140861894)
CI for #12; [harness](https://github.com/quaat/mdl-racket/actions/runs/44143034040)
and [native](https://github.com/quaat/mdl-racket/actions/runs/44143033844)
for #13; [harness](https://github.com/quaat/mdl-racket/actions/runs/44144487597)
and [native](https://github.com/quaat/mdl-racket/actions/runs/44144489802)
for #14; [harness](https://github.com/quaat/mdl-racket/actions/runs/44145914564)
and [native](https://github.com/quaat/mdl-racket/actions/runs/44145913581)
for #15; and [harness](https://github.com/quaat/mdl-racket/actions/runs/44147925107)
and [native](https://github.com/quaat/mdl-racket/actions/runs/44147925290)
for #16.

## Supported semantics, deviations, and next action

Supported M1 subset: FALSE truth and payloads; ATOM identity and named
OBLIST membership; mutable LIST/VECTOR/UVECTOR REST views, PUT/PUTREST;
structured NEWTYPE/CHTYPE; atom-keyed global values and dynamic simple
parameter bindings; 36-bit FIX and WORD operations; value-preserving
truth/conditional evaluation; and tested structural/identity equality.
No unsupported form is converted to an implicit false value or no-op.

Historical/reference deltas remain explicit. Confusion uses a native 64-bit
WORD representation, accepts FIX values beyond the PDP-10 range, returns 0
for zero-argument division, and lacks ROT and UNASSIGN. The Racket target
follows the manual for 36-bit limits and division, while ROT and UNASSIGN
remain unsupported. Full PDP-10 FLOAT representation, general MDL types,
macro evaluation, complex function parameters, nonlocal control flow,
source linking, and the original game execution are outside M1. The reader
parses the selected text but does not implement these forms. No Zork parity
or playable port is claimed.

No upstream checkout, puzzle rule, public license, deployed service, or
GPLv3 Confusion code was changed. Confusion remains a local reference
dependency under its own license. The Codex automated review service hit its
usage limit, so that ancillary review remains unavailable; the maintainer
approved the merge sequence. The next milestone is M2, beginning with a
narrowly scoped control/binding or source-loader issue.
