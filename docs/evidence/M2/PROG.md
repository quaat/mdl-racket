# M2 issue #20 — scoped PROG and bare RETURN

**Local slice: PASS. M2 milestone: NOT YET PASS.** Base `main` commit:
`0ed68bda80b98a6e0b544af77557ca33eda757ad`. The feature commit and CI
results are recorded in the issue/PR comment after publication. Pinned source
commits from `sources.lock.json`: MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916`, patched Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`. No upstream checkout was
edited.

The [MDL manual's looping chapter](https://mdl-language.readthedocs.io/en/latest/10-looping/)
defines PROG's required auxiliary list, sequential body evaluation, and
RETURN's implicit target. Its
[function activation chapter](https://mdl-language.readthedocs.io/en/latest/09-functions/)
defines the function boundary: an ordinary FUNCTION does not create an
implicit activation for a caller's PROG. The exact reference inputs and full
stdout/stderr are in `prog-cases.json`, `prog-reference.json`,
`prog-error-cases.json`, and `prog-error-reference.json` here. A separate
Confusion crash observation is in `prog-crash-cases.json` and
`prog-crash-reference.json`.

| Command | Exit | Observed result |
|---|---:|---|
| `make doctor` | 0 | Python 3.13.0; Racket 7.9 [bc]; BDW GC 8.0.4; build tools found |
| `make sources` | 0 | `Verified 2 source repositories`; both locked upstream checkouts clean |
| `make test-racket` after adding tests, before implementation | 2 | First new case failed with `mdl-apply: unassigned or non-applicable MDL operator PROG`; `1/275 test failures` |
| `make test-racket` after implementation | 0 | `289 tests passed` before the extra `#lang mdl` fixture assertion |
| `make test` after final regressions | 0 | `294 tests passed`; `13 passed` in Python |
| `make check-source` | 0 | `{'parsed': 36, 'failed': 0, 'non-text': 4}`; frozen M0 sweep restored afterward |
| `make reference-build` | 0 | Rebuilt local Confusion using build-only `-include cstdint`; upstream checkout unchanged |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/prog-cases.json --output docs/evidence/M2/prog-reference.json` | 0 | Nine isolated children exit 0 with empty stderr |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/prog-error-cases.json --output docs/evidence/M2/prog-error-reference.json` | 1, expected | Three deliberate error observations; each child exits 0, with nonempty error stderr |
| Initial `prog-cases.json` probe including `return-during-aux-initialization` | 1 | That child exited `-11` (signal 11), with no result output or stderr; the row was saved separately, then the nine successful cases were reprobed |
| `make reference-capture` | 0 | Five turns captured in `artifacts/reference/house.json`; `complete=true`, `error=null`, PTY cleanup SIGHUP (`process_signalstatus=1`) |
| `make reference-probe` | 0 | Twelve baseline expressions probed |
| M1 gate report's embedded reference/golden comparison script | 0 | `M1 mainline reference and golden comparisons PASS` |

Reference outputs: normal completion `2`, ordered aux initializer `5`,
initializer shadowing `10` then `11`, unassigned aux followed by SET `4`,
outer-local restoration `5`, `7`, `5`, early RETURN `42`, default RETURN `T`,
nested RETURN `1`, and mutation before RETURN `0`, `1`, `1`. The three error
cases observe unassigned auxiliary access, RETURN outside PROG, and bare RETURN
from a helper called inside a PROG. Confusion's unassigned-variable error
enters its level-2 REPL and emits an additional `Atom REP` stderr line; Racket
and Confusion agree on the error boundary, not the error printer text.
The manual specifies that PROG's activation is generated before its
auxiliaries bind. Racket therefore returns `6` from `<PROG ((M2-X <RETURN 6>))
99>`, as asserted in `tests/prog_test.rkt`. Pinned Confusion crashes on this
case, so it is excluded from the successful oracle count and from any parity
claim. The crash probe used fixed input and produced exit code `-11`, empty
stdout, and empty stderr; the complete row and binary hash are retained.

The rebuilt interpreter SHA-256 is
`25f3ca662a801e57cb207b076b77fa3d7ab4658d8b4539e6fe057346d587c201`;
the reconstructed game image SHA-256 is
`92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6a1b0ffb7a4`.
The maintainer-approved house golden SHA-256 is
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
The house input is fixed but has no controlled RNG seed. Confusion embeds a
build timestamp in its banner; the M1 comparison excludes capture time,
binary hash, and that banner timestamp only. The focused primitive cases
contain no time or randomness. Each bare REPL case ends with `<QUIT>`; the
three expected-error cases are intentionally not counted as successful
reference processes.

Supported in this slice: unnamed PROG with an auxiliary list and nonempty
body; bare or initialized auxiliary variables, ordered initialization and
shadowing, normal last-value return, bare RETURN with value or default `T`,
nested escapes, and restoration of dynamic locals. `RETURN` outside an active
PROG in the current function raises an error. Named activations, explicit
target RETURN, REPEAT, AGAIN, GO, UNWIND, OPTIONAL/AUX/TUPLE function formals,
macros, declarations, and original-source loading are still unsupported.
No Zork game code runs in Racket; M2's integrated gate remains open.

No game rule, upstream source, public license, deployed service, or GPLv3
Confusion code was changed. The new continuation stays within a local Racket
evaluation and is not exposed through a server. Next action: implement
reference-backed activation and REPEAT/AGAIN behavior in a separate issue,
then progress toward executing initial original MDL definitions.
