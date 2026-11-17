# M1 issue #4 — atom and OBLIST evidence

**Local slice gate: PASS; PR/CI review pending. M1 milestone: NOT YET PASS.**
Base commit (merged PR #10): `f823898732078c06ee48341d742dcf84acd157ba`.
Record this slice's feature SHA in the PR comment after push. Locked upstream
commits: MIT Zork `d94501340842e006791fce0757dc0043b8ec8916` and patched
Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

| Command | Exit | Result |
|---|---:|---|
| `racket --version`; `.venv/bin/python --version` | 0 each | Racket 7.9 [bc]; Python 3.13.0 |
| `make sources` | 0 | Both locked commits verified; upstream trees clean |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M1/atoms-cases.json --output docs/evidence/M1/atoms-reference.json` | 0 | Seven local Confusion processes exited 0, empty stderr; raw input/output saved |
| `make test-racket` before implementation | 2 | `mdl-atom?` unbound in `tests/atom_test.rkt` |
| `make test` after implementation | 0 | 83 Racket checks, 13 Python tests |
| `make reference-capture` | 0 | Five turns captured; every JSON field except `captured_at` matches the approved M0 golden |
| `make reference-probe` | 0 | Existing 12 primitive cases passed |
| `git diff --check` | 0 | No whitespace errors |

Confusion binary SHA-256:
`99728037f046ee68fdbb6ef69f44155e3c03f9c0b2b0840fbc218c75024c21e3`;
game SHA-256:
`92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6a1b0ffb7a4`.
Approved M0 golden SHA-256:
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
The reference game PTY ends with SIGHUP cleanup after five commands; each bare
REPL probe ends with `<QUIT>` and exits 0. No controlled RNG seed was needed
for these atom probes; the same fixed house input was used for capture.

Supported: direct atom interning, explicit OBLIST trailers, fresh `ATOM`, named
`MOBLIST`, `LOOKUP`, `INSERT`, `REMOVE`, `OBLIST?`, `PNAME`, and `TYPE` of ATOM
and OBLIST. Separate atom spaces can be used for session isolation. Duplicate
insertion and invalid types error rather than becoming FALSE.

Limits: full `.OBLIST` read context and BLOCK/ENDBLOCK, OBLIST association
properties, hash bucket structure, MDL print notation, and nested quoted atom
data inside LIST/FALSE literals are not implemented. Confusion's default
MOBLIST prints 17 buckets; the historical manual says 13. The implementation
does not expose bucket geometry, so neither value is claimed as equivalent.
Global/local bindings still use the bootstrap string model pending issue #7.
No game runtime, parser, or puzzle rule was changed. No GPLv3 code or binary
was copied into the MIT-0 runtime. Next dependency slice: mutable sequences
and shared REST views (issue #5), then type constructors (issue #6).
