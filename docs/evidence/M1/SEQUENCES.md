# M1 issue #5 — mutable sequence evidence

**Local slice gate: PASS; PR/CI review pending. M1 milestone: NOT YET PASS.**
Base feature commit (issue #4): `766741efdee997a7a5f0a70a7e23dd3ad934d3d9`.
Record this slice's feature SHA after commit. Locked upstream commits are MIT
Zork `d94501340842e006791fce0757dc0043b8ec8916` and patched Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`. `make sources` confirmed
both pins and clean upstream checkouts before reference comparison.

| Command | Exit | Result |
|---|---:|---|
| `make test-racket` before implementation | 2 | `mdl-rest` unbound in `tests/sequence_test.rkt`; tests were red |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M1/sequences-cases.json --output docs/evidence/M1/sequences-reference.json` | 0 | 10 Confusion cases; each child exit 0, empty stderr |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M1/sequences-error-cases.json --output docs/evidence/M1/sequences-error-reference.json` | 1 | Intentional UVECTOR PUT type error: child exit 0 but stderr nonempty and `*ERROR*` printed; probe correctly rejected the case |
| `make sources` | 0 | Locked SHAs verified; upstream checkouts clean |
| `make test` after implementation | 0 | 125 Racket checks; 13 Python tests |
| `make reference-capture` | 0 | Five prompts returned, `complete=true`, no runner error; SIGHUP cleanup signal 1 |
| `make reference-probe` | 0 | Existing 12 cases passed |
| Python JSON comparison of house capture against `docs/evidence/M0/house-golden.json`, excluding only `captured_at` | 0 | Exact match |

The successful probe inputs and full stdout/stderr are in
`sequences-cases.json` and `sequences-reference.json`. The deliberate error
probe's raw input and output are in `sequences-error-reference.json`.
Confusion binary SHA-256:
`99728037f046ee68fdbb6ef69f44155e3c03f9c0b2b0840fbc218c75024c21e3`;
game SHA-256:
`92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6a1b0ffb7a4`.
Approved M0 golden SHA-256:
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
The house scenario uses the same five inputs and has no controlled RNG seed;
these deterministic primitive probes do not require time or random input.
The game banner embeds the native build time, so rebuilding the binary can
change the initial transcript and its hash. The probe REPL exits via `<QUIT>`.

Supported in this slice: shared LIST tails, VECTOR/UVECTOR REST views,
1-based NTH/PUT, LIST PUTREST, LENGTH, TYPE and UTYPE of the supported values,
retained quoted structures, and mutation through FALSE payload LIST views.
The alias property sweep covers LIST lengths 2 through 10. Bounds and UVECTOR
type violations raise errors. No unsupported construct falls through to a
no-op or implicit false value.

Limits: general dynamic type tags, GROW/BACK/TOP, segment syntax, STRING/BYTES
views, and MDL printing remain unsupported. `GET` is not aliased to NTH.
Racket's compiler remains a bootstrap subset; this does not establish game
execution or whole-language equivalence. No upstream checkout, game rule,
license, or deployed service changed. Confusion's GPLv3 source and binary
remain reference dependencies and were not copied into the MIT-0 runtime.
The next dependency slice is issue #6, types and constructors.
