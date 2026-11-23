# ERROR primitive correction — issue #60

**Result:** focused slice PASS on `feat/m2-error-primitive`; integrated M2
G3 is still FAIL pending a current-head run. This branch follows
`209b6c6` (computed global), `cfca370` (`N=?`), and `e6d295d` (D5).

## Provenance and behavior

`sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and reconstructed
mdlzork/Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
Pinned original `81prim.mud` SHA256 is
`8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`.
Native Confusion executable SHA256 was
`987471cf0e568ad7f83a10b893484cd3fa99a86a69444c3b7d5554b16829f475`.

The [MDL manual chapter 1](https://mdl-language.readthedocs.io/en/latest/01-basic-introduction/)
describes an error as an evaluation interruption. [Chapter 21](https://mdl-language.readthedocs.io/en/latest/21-interrupts/)
describes error interrupts and `ERRET` recovery. Four local native cases
are saved in `error-cases.json` and `error-reference.json`: zero arguments,
one atom, multiple values, and the exact original MSETG conflicting repeat.
Confusion prints each evaluated argument and enters
`LISTENING-AT-LEVEL 2`. In the source-backed case the output includes
`"DONE"`, `T`, then `*ERROR*`, `MSETG`, `G3-FOO`,
`ALREADY-GASSIGNED`, and old value `3`. The probe command exits **1 by
design**: the following `<QUIT>` is processed at error level and emits
`Atom REP has neither LVAL nor GVAL` on stderr. These are deliberate
error observations, not clean successes. Inputs are one process per case;
there is no RNG input.

## Red to green

Before implementation, `TMPDIR=/tmp raco test tests/error_test.rkt`
exited 1: the multiple-value checks received `unassigned or non-applicable
MDL operator ERROR`, and the side-effect global remained unassigned.
`racket tests/historical_error_test.rkt` also exited 1 on the exact
original MSETG conflicting-repeat assertion.

After adding the strict `ERROR` builtin:

| Command | Exit | Result |
|---|---:|---|
| `TMPDIR=/tmp raco test tests/error_test.rkt` | 0 | four focused checks, including argument evaluation order and side effects |
| `racket tests/historical_error_test.rkt` | 0 | hash-verified original MSETG conflict raises `ALREADY-GASSIGNED` and preserves old global value |
| `make test` | 0 | 888 Racket checks; 13 Python tests |
| `make test-historical` | 0 | VFLOAD, DECL, MSETG equal repeat, MSETG conflict |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/error-cases.json --output docs/evidence/M2/error-reference.json` | 1, expected | four deliberate native error observations |
| `racket scripts/mdl_load.rkt --source-root .cache/upstream/mdlzork/mdlzork_771212/patched_confusion --entry 77loadall.mud --report artifacts/m2/error-load.json` | 1, expected | 24 completed expressions; unassigned `EMPTY?` at `77defs.mud` expression 15 |

The local `ERROR` raises a host exception and includes evaluated ATOM,
STRING, and scalar values in its message. It does not implement MDL's
resumable error level, error handlers, or `ERRET`; other structured
arguments use a host diagnostic representation. These deviations are
explicit and the primitive never returns a false or ignored value.

No upstream checkout or GPLv3 reference source changed or entered the
MIT-0 runtime. No network evaluator was exposed. Original PSETG/MEMQ,
general error recovery, game boot, and gameplay remain unverified. Next:
rerun G3 on the stacked correction head and record its actual first failure.
