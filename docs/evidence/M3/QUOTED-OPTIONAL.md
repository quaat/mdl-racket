# M3 quoted OPTIONAL default slice — issue #82

**Gate: PASS for the scoped formals slice; full M3 gate remains incomplete.**
The parent mainline commit is `7cb89415c962acbfd0eac12c57399253fb618367`.
Pinned upstream commits in `sources.lock.json` are MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

The first blocked construct was original `77defs.mud` expression 61,
line 338, `('WINNER ',WINNER)` in `TAKE-OBJECT`. Source SHA256 values are
`77loadall.mud` `389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa`,
`81prim.mud` `8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`,
and `77defs.mud` `566ebcc32be9b9226dd7cefd77a517583eebab80a03f452df39e13b85eed734e`.

The [MDL manual §9.9](https://mdl-language.readthedocs.io/en/latest/09-functions/)
permits this syntax. Six isolated clean pinned Confusion probes in
[`quoted-optional-cases.json`](quoted-optional-cases.json) and
[`quoted-optional-reference.json`](quoted-optional-reference.json)
show omitted defaults evaluated in the new frame, explicit arguments
bound raw, explicit arguments skipping defaults, and `',WINNER` yielding
a FORM. The local native binary SHA256 is
`cd7bfffe22265b3f63dfd2713330507c53e6182ec9f41ba4aa3d818127252580`.
Inputs use one isolated process per case and `<QUIT>`, no RNG or game input.

The focused regression initially exited 1 at
`mdl-compiler: 1:25: quoted formal cannot take a default`. After the
compiler and runtime formal parser correction,
`TMPDIR=/tmp raco test tests/quoted_optional_test.rkt tests/macro_test.rkt`
exits 0 with 59 checks. `make test` exits 0 with 1,097 Racket checks
and 22 Python tests. `make m2-check` exits 0: G3 58, 12 native
primitive probes and five-turn native capture. `make m3-source-progress`
exits 0 with 36 historical text files parsed, four nontext, 87 original
forms completed, 63 beyond the accepted M2 prefix, and zero skipped.
The full loader exits 1 at `77defs.mud` expression 78, line 448:
`mdl-decl: DECL ... unknown declaration type APPLICABLE`. See
[`source-progress-quoted-optional.json`](source-progress-quoted-optional.json).

Reproduce after `make reference-build`:

```bash
make test
make m2-check
make m3-source-progress
git diff --check
```

Local versions: Racket 7.9 bc, Python 3.13, BDW GC 8.0.4. This slice
supports quoted required formals and quoted OPTIONAL defaults through
the interpreted binder; explicit raw forms and default timing match the
six scoped reference cases. `BIND`/`CALL` formals remain unsupported.
Full source load, game initialization, runtime equivalence and gameplay
parity remain unverified. No `.cache/upstream/` bytes, GPLv3 code,
public license or exposed evaluator changed. Next task is
[issue #84](https://github.com/quaat/mdl-racket/issues/84).
