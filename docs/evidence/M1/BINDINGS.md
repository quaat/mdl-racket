# M1 issue #7 — local and global binding evidence

**Local slice gate: PASS; PR/CI review pending. M1 milestone: NOT YET PASS.**
Base feature commit (issue #6): `8fec75dca12bbb9800e8c8987a30d55edaa81fa4`.
Record this slice's feature SHA after commit. Locked upstream commits are MIT
Zork `d94501340842e006791fce0757dc0043b8ec8916` and patched Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

| Command | Exit | Result |
|---|---:|---|
| `make test-racket` before implementation | 2 | `current-mdl-locals` unbound in `tests/binding_test.rkt` |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M1/bindings-cases.json --output docs/evidence/M1/bindings-reference.json` | 0 | Nine Confusion cases; all child exits 0, empty stderr |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M1/bindings-error-cases.json --output docs/evidence/M1/bindings-error-reference.json` | 1 | Three deliberate error cases; child exits 0, error output and stderr captured |
| `raco make mdl/lang/main.rkt tests/fixtures/basic.mdl` | 0 | Refreshed stale linked-language exports after the first post-change test reported `mdl-with-bindings` unbound; Makefile now runs `raco make mdl/lang/main.rkt` automatically |
| `make sources` | 0 | Both pinned upstream SHAs verified; checkouts clean |
| `make test` after implementation | 0 | 176 Racket checks; 13 Python tests |
| `make reference-capture` | 0 | Five turns captured, `complete=true`, no runner error; SIGHUP cleanup signal 1 |
| `make reference-probe` | 0 | Existing 12 cases passed |
| Python JSON comparison of house capture with approved M0 golden, omitting only `captured_at` | 0 | Exact match |

Successful probe inputs and raw output are in `bindings-cases.json` and
`bindings-reference.json`. Expected error cases and raw output are in
`bindings-error-cases.json` and `bindings-error-reference.json`.
Confusion binary SHA-256:
`99728037f046ee68fdbb6ef69f44155e3c03f9c0b2b0840fbc218c75024c21e3`;
game SHA-256:
`92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6a1b0ffb7a4`.
Approved M0 golden SHA-256:
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
The house input is fixed and has no controlled RNG seed. Binding probes have
no time or random input and exit via `<QUIT>`. Native build time is embedded
in Confusion's banner.

Supported: separate local and global values keyed by ATOM identity, simple
function parameter shadowing/restoration, dynamic free variable lookup and
assignment, computed ATOM operands, VALUE precedence, GUNASSIGN, and errors
for unassigned reads and non-ATOM operands. A FORM's global operator takes
precedence over a local operator on the supported callable subset. The tests
also check that replacing a built-in global prevents silent fallback.

Limits: Confusion reports `UNASSIGN` as an unbound operator, despite the
historical manual documenting it; this slice leaves it unsupported. Explicit
ENVIRONMENT arguments, OPTIONAL/AUX/TUPLE, named ACTIVATIONs, concurrent
PROCESS stacks, and UNSPECIAL optimization remain unsupported. No game
execution or whole-language parity is claimed. No upstream checkout, game
rule, license, or exposed service changed. Confusion's GPLv3 code and binary
remain local reference dependencies. Next: issue #8, 36-bit arithmetic.
