# M3 duplicate attached ATOM declarations — issue #100

**Scoped slice: PASS on `feat/m3-duplicate-decl`; formal M3 gate:
INCOMPLETE.** Base main commit `bf26a7297b24097640aad89dc6b07f09c5125ad8`.
Locked source commits: MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916`, mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

The original `BALLOON` function at `77act2.mud:424` declares `M` twice,
first `<OR FALSE <PRIMTYPE VECTOR>>`, then the narrower
`<OR FALSE <<PRIMTYPE VECTOR> ANY ROOM>>`. The
[MDL manual §14](https://mdl-language.readthedocs.io/en/latest/14-data-type-declarations/)
allows repeated `(atoms:list Pattern)` pairs but gives no duplicate-name
precedence rule. Four [pinned Confusion probes](duplicate-decl-reference.json)
show that duplicate declaration values and FUNCTION definitions are
accepted. The command
`.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M3/duplicate-decl-cases.json --output docs/evidence/M3/duplicate-decl-reference.json`
exited **0**. Each case used a separate local process, fixed expression
plus `<QUIT>`, no RNG/game input. Native binary SHA256:
`bd70657059954cbb706fe93e8aceb14c64a58f51f227cfa4e69841d7df9ef340`.
Confusion does not enforce attached declarations, so it cannot establish
which duplicate Pattern would win at call time. The Racket runtime now
conjoins them in source order as a conservative inference that preserves
both written constraints. Duplicate VALUE remains an error in this slice.
The inference is recorded in `docs/SEMANTICS.md` and `docs/DECISIONS.md`;
it is not a historical precedence claim.

`TMPDIR=/tmp raco test tests/duplicate_decl_test.rkt` exited **1 before
implementation** with `duplicate declaration for X`. After the change,
`TMPDIR=/tmp raco test tests/duplicate_decl_test.rkt tests/declaration_test.rkt`
exited **0**, 62 checks, verifying that either duplicate constraint can
reject a value, that a matching value passes, that the original `BALLOON`
shape is accepted, and that duplicate VALUE stays strict. `TMPDIR=/tmp
make test` exited **0**, **1,235 Racket checks and 23 Python tests**.
`TMPDIR=/tmp make m2-check` exited **0** with historical G3 58 assertions,
native 12-expression primitive probe and five-turn reference capture.
`TMPDIR=/tmp make m3-source-progress` exited **0 as a partial-progress
measurement** after source SHA verification and parsing 36 historical
text files. Its underlying loader exited **1** after **430 completed
original forms, zero skipped**, up 67 from 363, fully loading
`77act1.mud`, `77act2.mud` and `77act3.mud`. The next failure is
`77rooms.mud` expression 13, line 92, unassigned `HANDLER`; see
[source summary](source-progress-duplicate-decl.json) and
[raw report](source-load-duplicate-decl.json). The source report records
`77rooms.mud` SHA256
`e89337af98565292f84cfb10e9239924e99918325c9e1ac39b6bce692f5aff94`.

No upstream source, GPLv3 code, public license, or network service changed.
Unsupported MDL forms remain errors. Full source load, initialization,
interactive input, smoke parity and gameplay are unverified. Next:
[issue #102](https://github.com/quaat/mdl-racket/issues/102) under
[event issue #71](https://github.com/quaat/mdl-racket/issues/71) must probe
HANDLER and EVENT semantics before implementing them.

Reproduce after `make reference-build`:

```bash
TMPDIR=/tmp raco test tests/duplicate_decl_test.rkt tests/declaration_test.rkt
TMPDIR=/tmp make test
TMPDIR=/tmp make m2-check
TMPDIR=/tmp make m3-source-progress
git diff --check
```
