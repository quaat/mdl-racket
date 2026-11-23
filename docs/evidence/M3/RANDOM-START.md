# M3 RANDOM follow-up: original START reaches BACK

Date: 2026-11-22. Branch `feat/m3-session-random` is stacked on draft PR
#107, source-load head `850a87f01f6187b3c9bf87373a033ff431923d84`.
The first RNG commit after rebase is `0e35b2f`. Issue #108 tracks this slice.
M3 remains **FAIL / incomplete**.

## Provenance and observed stages

`sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`. The source root is the
playable December 1977 reconstruction; no file under `.cache/upstream/`
was modified. The local reference engine SHA256 and raw stdin/stdout/stderr
for each case are in [`random-reference.json`](random-reference.json).
Racket v7.9 [bc] and Python 3.13.0 were used locally.

| Stage | Result |
|---|---|
| PARSED | PASS: prior 36 historical text files |
| LOADED | PASS on branch: 1,229 original forms, zero skips, all 13 files, loader exit 0 |
| INITIALIZED | FAIL: original START passes RANDOM and stops at `BACK` in `CONTIN`, `77rooms.mud:297` |
| INTERACTIVE | NOT RUN |
| SMOKE_PARITY | NOT RUN |
| PLAYABLE | NOT RUN |

The startup probe runs `mdl-session-load!` on unchanged `77loadall.mud`,
then `mdl-session-call` on original `START` with `"WHOUS"` and `""`.
Its load report is PASS with 1,229 completed and zero skipped. START emits
`"Welcome to Dungeon.\r\n\n"`, then raises
`mdl-eval: unassigned or non-applicable MDL operator BACK`. The wrapper
catches this expected failure, so the exploratory shell command exits 0;
`tests/historical_start_random_test.rkt` records it as a known XFAIL
frontier. It is not a successful initialization.

## RANDOM semantics and tests

The historical manual requires a deterministic unseeded sequence and signed
FIX output across the full range. The pinned reference observations cover
three unseeded calls, repeated and reversed two-seed calls, one-seed calls,
zero and boundary seeds, and type/arity errors. A Racket session owns two
36-bit state words; no process-global Racket RNG is used. A one-seed call
replaces the first word only; a two-seed call replaces both before advancing.
The original START passes one seed from DSKDATE. The runtime rejects
non-FIX, out-of-range, and excessive seed arguments.

The pinned Confusion executable returns `-68719476736` for the first
`<RANDOM -1 -2>` call, outside signed 36-bit FIX. The Racket runtime
normalizes every transition and returns `0`; its next value is the same
`34359738367` as Confusion. This is a documented reference deviation.
The reference engine's error-level REPL returns process status 0 while
writing errors to stderr; the fixture retains stderr and does not mark
those calls clean successes.

| Command | Exit | Evidence |
|---|---:|---|
| `TMPDIR=/tmp raco test tests/random36_test.rkt` before implementation | 1 | unassigned global RANDOM |
| `TMPDIR=/tmp raco test tests/random36_test.rkt` after implementation | 0 | 525 checks, including 500 signed-range samples |
| `TMPDIR=/tmp make test` | 0 | 1,996 Racket checks and 23 Python tests |
| `TMPDIR=/tmp make test-m3-start-random` | 0 | 6 assertions; source verified before known BACK XFAIL |
| `TMPDIR=/tmp make m2-check` | 0 | M2 regression, native 12-case probe and five-turn capture |
| `TMPDIR=/tmp make m3-source-progress` | 0 | LOADED, 1,229 completed, zero skipped, loader exit 0 |

Required CI must run on this follow-up's final PR head. The
reference five-command house scenario is unchanged; there is no candidate
transcript, RNG game call-order comparison, or state parity claim yet.

Security and licensing: no network evaluator, server, arbitrary input path,
or source patch was added. The bit recurrence is independently expressed in
the MIT-0 runtime and checked against observable GPLv3 reference outputs;
no Confusion implementation source was copied. Independent review of the
recurrence and its negative-seed deviation is required. The next source
dependency is BACK on the terminal CHANNEL; follow its manual semantics
and a pinned reference probe, then advance CONTIN to the next actual stop.
