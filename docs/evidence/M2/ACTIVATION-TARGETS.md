# M2 issue #28 — named activations and explicit targets

**Local slice: PASS. M2 milestone: NOT YET PASS.** Base main commit:
`40cbebb1f6d4cb2fcf708a51e2cd98b85f95b4e8`. The feature commit and CI
result are recorded in the PR comment after publication. `sources.lock.json`
pins MIT Zork `d94501340842e006791fce0757dc0043b8ec8916` and patched
Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; `make sources`
verified both upstream trees clean before the reference probes. Original
reconstructed source uses named PROG and explicit RETURN in `77rooms.mud`,
`77act1.mud`, and `77np.mud`.

The [manual's function chapter](https://mdl-language.readthedocs.io/en/latest/09-functions/)
defines an ACTIVATION as one evaluation of a Function and permits explicit
RETURN and AGAIN transfers across called functions. Its
[looping chapter](https://mdl-language.readthedocs.io/en/latest/10-looping/)
specifies a PROG/REPEAT name before auxiliaries and restart without rebinding.
This slice gives named PROG/REPEAT frames identity, live-state tracking, and
explicit transfer to an active enclosing frame. TYPE yields ACTIVATION;
PRIMTYPE and TYPEPRIM yield FRAME. Bare transfer ownership remains unchanged.

| Command | Exit | Observed result |
|---|---:|---|
| `make sources` | 0 | Two locked commits verified; upstream checkouts clean |
| `make test` before implementation | 0 | Existing 331 Racket checks and 13 Python tests passed |
| `raco test tests/activation_target_test.rkt` before implementation | 1 | `mdl-compiler: 1:1: named PROG activation is not implemented` |
| `python3` isolated probe helper | 1, environment | System Python lacked `pexpect`; reran with `.venv/bin/python` |
| `raco test tests/activation_target_test.rkt tests/prog_test.rkt tests/repeat_test.rkt mdl/runtime/core.rkt` | 1, environment | Racket attempted to write test state under read-only `/var/tmp` |
| `TMPDIR=/tmp raco test tests/activation_target_test.rkt tests/prog_test.rkt tests/repeat_test.rkt mdl/runtime/core.rkt` | 0 | 60 focused checks before the final binding-order assertion |
| `make doctor` | 0 | Python 3.13.0, Racket 7.9 [bc], BDW GC 8.0.4, build tools present |
| `make test` final | 0 | 347 Racket checks, 13 Python tests |
| `make check-source` | 0 | 36 parsed, 0 failed, 4 non-text; frozen M0 sweep restored afterward |
| `make reference-build` | 0 | Native Confusion rebuilt with build-only `-include cstdint`; upstream unchanged |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/activation-target-cases.json --output docs/evidence/M2/activation-target-reference.json --timeout 5` | 0 | Eleven children exited 0 with empty stderr |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/activation-target-error-cases.json --output docs/evidence/M2/activation-target-error-reference.json --timeout 5` | 1, expected | Six deliberately invalid cases recorded separately, including one child signal-11 crash |
| `make reference-capture` | 0 | Five turns, `complete=true`, `error=null`, PTY cleanup signal 1 |
| `make reference-probe` | 0 | Twelve baseline expressions |
| M1 gate report's reference/golden comparison script | 0 | `M1 mainline reference and golden comparisons PASS` |
| `git diff --check` | 0 | No whitespace errors |

The eleven successful reference results cover ACTIVATION and FRAME type
reporting, name visibility in auxiliary initialization, restoration of an
outer same-name binding, named PROG RETURN, RETURN to an outer PROG, named
PROG AGAIN, named REPEAT RETURN, and RETURN/AGAIN from a called simple
function. Exact input, stdout, stderr, and child exit status are saved in
`activation-target-reference.json`. The six separate observations in
`activation-target-error-reference.json` are not passing parity cases:
wrong-type RETURN crashes Confusion with signal 11; wrong-type AGAIN and
stale RETURN/AGAIN report a frame error; duplicate activation/auxiliary name
reports `BAD-ARGUMENT-LIST`; `LEGAL?` is unbound in this Confusion build.
Racket raises explicit wrong-type, inactive-target, or compile-time errors
instead of reproducing those failures.

The rebuilt Confusion binary SHA-256 is
`2c58ef023d2ac306bdf661ee0afc0123eef94a8608c108a36ddc2e8808ab4d95`;
the reconstructed game image SHA-256 is
`92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6a1b0ffb7a4`;
the approved M0 golden SHA-256 is
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
Focused expressions have fixed inputs with no time or randomness. The house
scenario has fixed commands but no controlled RNG seed. Confusion embeds
build time in its banner; the approved comparison excludes capture time,
rebuilt binary hash, and banner timestamp only. All gameplay output and
command input match the approved fixture.

Supported: named PROG/REPEAT, explicit RETURN/AGAIN to a live enclosing
PROG/REPEAT, nonlocal transfer across a called simple DEFINE, frame identity
and type, once-only auxiliary binding, and explicit stale/wrong-type errors.
Unsupported: function activation formals, GO, UNWIND, `LEGAL?`, general
FRAME operations, non-enclosing activation transfers, complex function
formal lists, source loading, and original game execution. The implementation
rejects a duplicate activation/auxiliary name at compile time, consistent
with the observed Confusion error. The M2 integrated gate remains open.
No game rule, upstream source, public license, deployed service, or GPLv3
Confusion code changed; no evaluator endpoint was exposed. Next: function
argument binding and activation formals, then source loading and initial
historical definitions.
