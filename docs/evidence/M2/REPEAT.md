# M2 issue #26 — unnamed REPEAT and bare AGAIN

**Local slice: PASS. M2 milestone: NOT YET PASS.** Base main commit:
`801d7c67b8b96872abf0925e084dc2cccf65a552`. The feature commit and CI
result are recorded in the PR comment after publication. `sources.lock.json`
pins MIT Zork `d94501340842e006791fce0757dc0043b8ec8916` and patched
Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`. Upstream trees
were clean.

The [MDL looping chapter](https://mdl-language.readthedocs.io/en/latest/10-looping/)
defines REPEAT as PROG with an implicit final AGAIN. Auxiliaries bind once;
AGAIN restarts the body of the nearest PROG or REPEAT in the current function
without rebinding. RETURN exits that frame. The implementation retains one
owned frame and one auxiliary scope across tail-recursive body iterations.

| Command | Exit | Result |
|---|---:|---|
| `raco test tests/repeat_test.rkt` before implementation | 1 | `mdl-lval: unassigned MDL local M2-N` in the first REPEAT assertion |
| `raco test tests/repeat_test.rkt mdl/runtime/core.rkt tests/prog_test.rkt` after implementation | 1, environment | Racket tried to write test state in read-only `/var/tmp` |
| `TMPDIR=/tmp raco test tests/repeat_test.rkt mdl/runtime/core.rkt tests/prog_test.rkt` | 0 | 43 focused checks before the final two assertions were added |
| `make doctor` | 0 | Python 3.13.0, Racket 7.9 [bc], BDW GC 8.0.4 and build tools available |
| `make sources` | 0 | Two locked commits verified; upstream trees clean |
| `TMPDIR=/tmp make test` | 0 | 331 Racket checks, 13 Python tests |
| `make test` repeated without TMPDIR override | 0 | 331 Racket checks, 13 Python tests; earlier `/var/tmp` failure did not recur |
| `make check-source` | 0 | 36 parsed, 0 failed, 4 non-text; frozen M0 sweep restored afterward |
| `make reference-build` | 0 | Native Confusion rebuilt with build-only `-include cstdint`, upstream unchanged |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/repeat-cases.json --output docs/evidence/M2/repeat-reference.json --timeout 5` | 0 | Five children exited 0 with empty stderr |
| `make reference-capture` | 0 | Five-turn `artifacts/reference/house.json`, `complete=true`, `error=null`, PTY cleanup signal 1 |
| `make reference-probe` | 0 | 12 baseline expressions probed |
| M1 gate report's reference/golden comparison script | 0 | `M1 mainline reference and golden comparisons PASS` |
| `git diff --check` | 0 | No whitespace errors |

The five focused results are `3` for implicit REPEAT repetition and RETURN,
`0` then `1` for global initialization followed by once-only auxiliary
initialization, `3` for PROG bare AGAIN, `3` for REPEAT bare AGAIN, and `3`
for nested PROG RETURN inside REPEAT. Exact input, stdout, stderr, exit status,
and embedded build banner are in `repeat-reference.json`. No focused case
uses time or randomness. The house scenario has fixed commands but no
controlled RNG seed. Confusion embeds build time in its banner; the approved
comparison excludes capture time, rebuilt binary hash, and banner timestamp
only. All gameplay output and command input match the approved fixture.

The rebuilt Confusion binary SHA-256 is
`1e6a668290faf9cb70aaade60bbf43f236459782c15db4c1c35150bb54aa49c0`;
the reconstructed game image SHA-256 is
`92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6a1b0ffb7a4`;
the approved M0 golden SHA-256 is
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.

Supported: unnamed REPEAT, bare AGAIN in current function's PROG or REPEAT,
bare RETURN from REPEAT, once-only auxiliary initialization, and nested frame
unwinding. Named activations, explicit target RETURN/AGAIN, GO, UNWIND,
function activation formals, and original source execution remain unsupported.
AGAIN during an auxiliary initializer currently fails explicitly because the
body restart point is not yet established; this edge has not been corroborated
against Confusion. The M2 integrated gate remains open; the original Zork
does not run in Racket. No game rule, upstream source, public license,
deployed service, or GPLv3 Confusion code changed. No evaluator endpoint was
exposed. Next: named activation values and explicit target control transfer,
with separate reference-backed tests before implementation.
