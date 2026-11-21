# M3 deferred attached declaration TYPE names — issue #98

**Scoped slice: PASS on `feat/m3-deferred-decl-type`; formal M3 gate:
INCOMPLETE.** Base main commit `cdc851056b5530fe091373dbdf331eafcfa558e9`.
Locked commits in `sources.lock.json`: MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916`, mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

An attached `#DECL` now retains an unresolved TYPE atom as a Pattern,
resolving it when a bound value, assignment or result is checked. If it
remains unknown, the check raises `unknown declaration type`; it does not
match arbitrary values. A later NEWTYPE or DECL association can satisfy
the stored Pattern. Nested OR and structure Patterns retain unresolved
atoms. Explicit `DECL?` and positional metadata remain strict immediately;
malformed and unsupported Pattern shapes are still rejected. ADR and
specification are in `docs/DECISIONS.md` and `docs/SEMANTICS.md`.

Four [clean pinned Confusion probes](deferred-decl-reference.json) show
definition and invocation with an unknown `PRSOBJ`, later NEWTYPE use,
and an unknown name in OR metadata. The command
`.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M3/deferred-decl-cases.json --output docs/evidence/M3/deferred-decl-reference.json`
exited **0**. Two [error-level probes](deferred-decl-errors-reference.json)
show that explicit `DECL?` with unknown `PRSOBJ`, alone or in OR, enters
`BAD-TYPE-SPECIFICATION1`; their analogous command using the
`deferred-decl-errors-*` files exited **1 as expected** because native
stderr is nonempty. Each case used a separate local process, fixed input
followed by `<QUIT>`, no RNG/game input. Native binary SHA256:
`bd70657059954cbb706fe93e8aceb14c64a58f51f227cfa4e69841d7df9ef340`.
Confusion does not enforce attached declarations, so its successful unknown
invocation is an explicit reference deviation from this runtime's
manual-based checking. It is evidence for accepting the definition, not
for treating the unknown name as `ANY`.

`TMPDIR=/tmp raco test tests/deferred_decl_type_test.rkt` exited **1 before
implementation** with `DECL 1:15: unknown declaration type PRSOBJ`. After
the change, `TMPDIR=/tmp raco test tests/deferred_decl_type_test.rkt
tests/declaration_test.rkt` exited **0**, 66 checks. The old immediate
unknown-type assertion was moved to call time. `TMPDIR=/tmp make test`
exited **0**, **1,229 Racket checks and 23 Python tests**. `TMPDIR=/tmp
make m2-check` exited **0** with historical G3 58 assertions, native
12-expression primitive probe and five-turn reference capture.
`TMPDIR=/tmp make m3-source-progress` exited **0 as a partial-progress
measurement** after verifying both locked source commits and 36 historical
text files parsed. Its underlying loader exited **1** after **363 completed
original forms, zero skipped**, up 130 from 233, and fully loaded
`77act1.mud`. The first failure is `77act2.mud` expression 39, line 424:
duplicate declaration for `M` in `BALLOON`; see [source summary](source-progress-deferred-decl.json)
and [raw report](source-load-deferred-decl.json). The source report records
the SHA256 of each encountered file, including `77act2.mud`
`b1efdaa199be939d5bae046776563bb6b5ef8ca054c17f4ff0d75a74e35693bb`.

No upstream source, GPLv3 reference code, public license, or network
service changed. Unsupported MDL forms still fail explicitly. The runtime
is local and incomplete; full load, initialization, interactive input,
smoke parity and gameplay remain unverified. Next:
[issue #100](https://github.com/quaat/mdl-racket/issues/100) must probe
duplicate attached declarations before changing their semantics.

Reproduce after `make reference-build`:

```bash
TMPDIR=/tmp raco test tests/deferred_decl_type_test.rkt tests/declaration_test.rkt
TMPDIR=/tmp make test
TMPDIR=/tmp make m2-check
TMPDIR=/tmp make m3-source-progress
git diff --check
```
