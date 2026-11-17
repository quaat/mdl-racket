# M1 issue #8 — 36-bit FIX and WORD evidence

**Local slice gate: PASS for the documented subset; PR/CI review pending.
M1 milestone: NOT YET PASS.** Base feature commit (issue #7):
`cf1f3b809747519381e24ba8fe53ba2cc3a4fe97`.
Record this slice's feature SHA after commit. Locked upstream commits are MIT
Zork `d94501340842e006791fce0757dc0043b8ec8916` and patched Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

| Command | Exit | Result |
|---|---:|---|
| `make test-racket` before implementation | 2 | Reader saw two nodes for `#WORD *777777777777*`; `mdl-word-bits` unbound in `tests/word_test.rkt` |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M1/word-cases.json --output docs/evidence/M1/word-reference.json` | 0 | Nine Confusion cases; every child exit 0, empty stderr |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M1/word-error-cases.json --output docs/evidence/M1/word-error-reference.json` | 1 | Deliberate ROT and division-by-zero error cases captured |
| `make sources` | 0 | Both locked SHAs verified and upstream checkouts clean |
| `make test` after implementation | 0 | 262 Racket checks; 13 Python tests |
| `make check-source` | 0 | 36/36 selected historical text files parsed; four non-text files classified |
| `make reference-capture` | 0 | Five turns, `complete=true`, no runner error; SIGHUP cleanup signal 1 |
| `make reference-probe` | 0 | Existing 12 cases passed |
| Python JSON comparison of house capture with approved M0 golden, omitting only `captured_at` | 0 | Exact match |

Probe inputs and full stdout/stderr are in `word-cases.json`,
`word-reference.json`, `word-error-cases.json`, and
`word-error-reference.json`. The current reader sweep was copied to
`docs/evidence/M1/reader-sweep.json` after `make check-source`; the frozen
M0 sweep was restored unchanged. Confusion binary SHA-256:
`99728037f046ee68fdbb6ef69f44155e3c03f9c0b2b0840fbc218c75024c21e3`;
game SHA-256:
`92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6a1b0ffb7a4`.
Approved M0 golden SHA-256:
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
The house input is fixed and has no controlled RNG seed. Numeric probes
have no time or random input and end via `<QUIT>`. Native build time is
embedded in Confusion's banner.

**Reference deltas:** Confusion outputs 22 octal digits for WORD (native
64-bit storage), evaluates `*777777777777*` as positive FIX 68719476735,
accepts `<+ 34359738367 1>` as FIX 34359738368, and returns 0 from `</>`.
The historical manual specifies 36-bit WORD/FIX bounds, FLOAT conversion
of out-of-range input, FIX overflow errors, and `</>` = 1. Confusion also
reports ROT unbound. The Racket implementation follows the manual on the
width/overflow/division points and leaves ROT unsupported. In-range
arithmetic and low-bit results match the pinned Confusion probes.

Supported: source-located #WORD numeric literals, octal FIX, 36-bit FIX
overflow and identity, FIX/FLOAT type distinction, FIX-to-WORD casts and
back, bitwise ANDB/ORB/XORB/EQVB, LSH, and BITS/GETBITS/PUTBITS on the
documented subset. Tests cover 36 shift positions, negative values,
arithmetic boundaries, and bit-field insertion/extraction. Unknown type
conversions and invalid bit ranges raise errors.

Limits: PDP-10 FLOAT precision/bit layout, ROT, overflow-control switches,
random-number behavior, and the complete arithmetic library are not
implemented. The bootstrap compiler still cannot execute the original
game. No upstream checkout, game rule, license, or exposed service changed;
Confusion's GPLv3 code and binary remain local reference dependencies.
The next task is the integrated M1 gate audit and reviewer feedback.
