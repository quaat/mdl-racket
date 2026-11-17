# M1 issue #6 — type constructor evidence

**Local slice gate: PASS; PR/CI review pending. M1 milestone: NOT YET PASS.**
Base feature commit (issue #5): `6037ecf7f354fdd5af67ab707ea56b825cef9d00`.
Record this slice's feature SHA after commit. Locked upstream commits are MIT
Zork `d94501340842e006791fce0757dc0043b8ec8916` and patched Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

| Command | Exit | Result |
|---|---:|---|
| `make test-racket` before implementation | 2 | `mdl-gval: unassigned MDL global PRIMTYPE` in `tests/type_test.rkt` |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M1/types-cases.json --output docs/evidence/M1/types-reference.json` | 0 | Nine pinned Confusion cases; every child exit 0, empty stderr |
| `make sources` | 0 | Both upstream SHAs verified; checkouts clean |
| `make test` after implementation | 0 | 152 Racket checks; 13 Python tests |
| `make check-source` | 0 | 36/36 selected MDL text files parsed; four non-text artifacts classified |
| `make reference-capture` | 0 | Five prompts, `complete=true`, no runner error; SIGHUP cleanup signal 1 |
| `make reference-probe` | 0 | Existing 12 cases passed |
| Python JSON comparison of house capture with approved M0 golden, omitting only `captured_at` | 0 | Exact match |

Probe inputs and raw stdout/stderr are in `types-cases.json` and
`types-reference.json`. Confusion binary SHA-256:
`99728037f046ee68fdbb6ef69f44155e3c03f9c0b2b0840fbc218c75024c21e3`;
game SHA-256:
`92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6a1b0ffb7a4`.
Approved M0 golden SHA-256:
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
The fixed house input was used without a controlled RNG seed. Type probes
have no random or time inputs and end with `<QUIT>`; the native binary embeds
its compile timestamp in its banner.

Supported: TYPE, PRIMTYPE, TYPEPRIM for the registered subset; NEWTYPE with
two arguments; CHTYPE for LIST/VECTOR/UVECTOR storage and FALSE/LIST views;
shared data and type-sensitive identity; REST dropping a custom type tag.
Primitive mismatch, duplicate type names, unregistered type atoms, and
dangerous built-in conversions raise errors. A type atom's identity, including
its OBLIST membership, determines registration.

Limits: the registered built-in type table is intentionally partial. General
declaration patterns, #NAME reader notation, PRINTTYPE/EVALTYPE/APPLYTYPE,
numeric WORD bit reinterpretation, and full type-directed evaluation are
unsupported. This is a bootstrap semantic slice, not a running Zork engine.
No upstream checkout, game rule, license, or exposed service changed.
Confusion's GPLv3 code and binary remain local reference dependencies.
Next dependency slice: local/global binding semantics in issue #7.
