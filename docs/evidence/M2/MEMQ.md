# MEMQ correction for original PSETG — issue #63

**Slice result:** PASS on `feat/m2-memq`. **Integrated M2 G3:** FAIL at
original `FLAGWORD`'s missing `MAPF` ([issue #65](https://github.com/quaat/mdl-racket/issues/65));
M3 has not started. This branch is stacked on G3 gate commit `d9472a3`,
`ERROR` commit `3589652`, computed-global `209b6c6`, `N=?` `cfca370`,
D5 `e6d295d`, and merged-main `419fc5c`.

## Provenance and reference contract

`sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and reconstructed
mdlzork/Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
Pinned `81prim.mud` SHA256 is
`8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`;
native executable SHA256 is
`987471cf0e568ad7f83a10b893484cd3fa99a86a69444c3b7d5554b16829f475`.

The [MDL manual chapter 8](https://mdl-language.readthedocs.io/en/latest/08-truth/)
defines `MEMQ` as `MEMBER` with `==?` identity: return the REST view from
the first identical element or `#FALSE ()`. Eight clean Confusion cases
in `memq-{cases,reference}.json` confirm LIST hit/miss, rejection of
structurally equal but distinct LIST elements, mutable LIST tail aliasing,
VECTOR and UVECTOR tails, and original `PSETG` first/repeat behavior.
Original `PSETG` returns `3`, then `4` on repeat; `PURE-LIST` stays
`(G3-P)` after both. Two clean original `FLAGWORD` cases in
`flagword-mapf-*` return `1` with no args and `2` with one FALSE arg;
those pin the next gate blocker.

`memq-error-*` records three deliberate failures: one argument crashes
the pinned Confusion process with signal 11; three arguments report
`Too many args to MEMQ`; a non-structured second argument reports
`Second arg to MEMQ must be structured`. The Racket implementation raises
explicit arity and type errors. This is a deliberate safety deviation
from the one-argument reference crash. All probes ran in local isolated
processes with no RNG or gameplay input. Clean probe command exited 0;
the deliberate-error probe exited 1 by design.

## Red to green and commands

Before the runtime change, `TMPDIR=/tmp raco test tests/memq_test.rkt`
exited 1 at unassigned `MEMQ`; `racket tests/historical_memq_test.rkt`
exited 1 at the exact original PSETG call. After implementation:

| Command | Exit | Result |
|---|---:|---|
| `TMPDIR=/tmp raco test tests/memq_test.rkt` | 0 | 14 identity, alias, kind, arity, and type checks |
| `racket tests/historical_memq_test.rkt` | 0 | SHA-verified original PSETG first/repeat calls |
| `make test` | 0 | 903 Racket checks; 13 Python tests |
| `make test-historical` | 0 | VFLOAD 23, DECL 21, MSETG equal/conflict, PSETG first/repeat |
| `make test-m2-g3` | **2** | 52 integrated assertions pass; explicit FAIL at original FLAGWORD/MAPF |
| `make doctor` | 0 | Python 3.13.0, BDW GC 8.0.4, required tools found |
| `make check-source` | 0 | 36 text files parsed; four non-text; no parse failures |
| `make reference-probe` | 0 | 12 baseline expressions |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/memq-cases.json --output docs/evidence/M2/memq-reference.json` | 0 | eight clean native cases |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/memq-error-cases.json --output docs/evidence/M2/memq-error-reference.json` | 1, expected | three deliberate error observations, including one native crash |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/flagword-mapf-cases.json --output docs/evidence/M2/flagword-mapf-reference.json` | 0 | two clean original FLAGWORD cases |
| `racket scripts/mdl_load.rkt --source-root .cache/upstream/mdlzork/mdlzork_771212/patched_confusion --entry 77loadall.mud --report artifacts/m2/memq-load.json` | 1, expected | 24 completed expressions; `EMPTY?` at `77defs.mud` expression 15 |
| `git diff --check` | 0 | no whitespace errors |

The existing `mdl-identical?` comparator and `mdl-rest` views preserve
the tested identity and aliasing. STRING MEMQ remains an explicit
`unsupported STRING MEMQ` error: a faithful mutable STRING REST view is
not yet established. This is a declared partial primitive, not an
implicit miss. Other original-source MAPF, indirect APPLY/DISPATCH,
broader continuations, full game boot, and gameplay remain unverified.

No upstream checkout or GPLv3 reference source changed or entered the
MIT-0 runtime. No production evaluator or web service was exposed. Next:
reference-backed MAPF slice (#65), then a fresh current-head G3 decision.
