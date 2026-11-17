# M1 semantic micro-runtime candidate gate

**Candidate gate: PASS on the stacked M1 branch. Mainline integration: NOT
RUN.** This report audits issue #17 on top of primitive commits
`766741efdee997a7a5f0a70a7e23dd3ad934d3d9` (#4),
`6037ecf7f354fdd5af67ab707ea56b825cef9d00` (#5),
`8fec75dca12bbb9800e8c8987a30d55edaa81fa4` (#6),
`cf1f3b809747519381e24ba8fe53ba2cc3a4fe97` (#7), and
`4ee6284cb0e79a2b00ff2fa3d18c4f68b8a75111` (#8). The gate audit
commit SHA is recorded in the PR comment after publication. M1 issue #3
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
| Automated code review | **BLOCKED** | GitHub Codex review did not run because its usage limit was reached; no inline findings were produced. Maintainer review remains pending. |
| Gate audit PR CI | **PASS on initial audit head** | [Harness run 44149060898](https://github.com/quaat/mdl-racket/actions/runs/44149060898) and [native run 44149060434](https://github.com/quaat/mdl-racket/actions/runs/44149060434) both succeeded; final documentation-head CI is recorded in the PR comment |
| M1 merged to `main` | **NOT RUN** | PRs #12–#16 and gate closure await maintainer review and merge in dependency order |

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
dependency under its own license. Next action: review and merge the M1 PRs
in dependency order, verify the combined head on `main`, then begin M2
with a narrowly scoped control/binding or source-loader issue.
