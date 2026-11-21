# M3 original GDECL global declaration correction — 2026-11-21

**Issue #78 slice PASS; full M3 source-load gate INCOMPLETE.** Branch
`feat/m3-gdecl` starts from merged main commit
`53a92195c62c3b08d416144fac3cfcd58e0f8349`. The final
implementation commit and CI results are recorded on its PR.

## Provenance and reference difference

`sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and
mdlzork/Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
Verified SHA256: `77loadall.mud`
`389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa`,
`81prim.mud` `8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`,
and `77defs.mud` `566ebcc32be9b9226dd7cefd77a517583eebab80a03f452df39e13b85eed734e`.
Local native Confusion binary SHA256:
`cd7bfffe22265b3f63dfd2713330507c53e6182ec9f41ba4aa3d818127252580`.

The [MDL manual §14.5.1](https://mdl-language.readthedocs.io/en/latest/14-data-type-declarations/)
defines GDECL as a global value declaration FSUBR. The first source
call is `77defs.mud` expression 27, line 139, declaring `ORPHANS`
against a VECTOR Pattern. Ten clean separate-process local native cases
in [`gdecl-reference.json`](gdecl-reference.json), with input in
[`gdecl-cases.json`](gdecl-cases.json), establish that pinned Confusion
returns T for even empty/malformed inputs and permits a later SETG that
violates a FIX declaration. Its pinned `confusion_patched/macros.cpp`
labels GDECL unimplemented and returns T without inspecting arguments.
The reference corpus uses appended `<QUIT>`, no game input and no RNG
seed. This Racket slice intentionally implements the manual operation
instead of a silent no-op; direct runtime-equivalence on GDECL is not
claimed.

The Racket compiler preserves raw GDECL arguments as MDL data; it does
not evaluate a nested Pattern form. The session stores declarations
under global ATOM identity, creates an unassigned slot for newly
declared names, validates already assigned values before installation,
and checks every subsequent SETG. A failing SETG leaves the old value.
Supported Patterns use the existing type/OR/PRIMTYPE and structured
LIST/VECTOR/UVECTOR/TUPLE matcher with required and REST elements.
Forward referenced type names resolve at assignment. Malformed name
lists, missing pairs, duplicate names and unsupported Pattern shapes
fail explicitly. `GET-DECL`/`PUT-DECL`, global locatives and switching
declaration checking off are not implemented by this slice.

## Red to green and command evidence

`TMPDIR=/tmp raco test tests/gdecl_test.rkt` initially exited 1 at
`mdl-eval: unassigned or non-applicable MDL operator GDECL`; after the
implementation it exits 0 with 15 checks, including a failed SETG
preserving its previous global value. `make test` exits 0 with 1,077
Racket checks and 22 Python tests. `make m2-check` exits 0 with
original VFLOAD 23, DECL 20, MSETG/PSETG, G3 58, 12 native primitive
probes and a five-turn native capture. `make m3-source-progress` exits
0 as a validated partial observation: 36 historical text files
parsed, four nontext, 37 completed original forms, 13 beyond the
accepted M2 prefix, zero skipped. Its underlying unchanged full
loader exits 1 at `77defs.mud` expression 28, line 146, execute
stage, unassigned `AND?`. The exact report is
[`source-progress-gdecl.json`](source-progress-gdecl.json).
`git diff --check` exits 0. Reproduce after `make reference-build`:

```bash
make test
make m2-check
make m3-source-progress
git diff --check
```

Relevant local versions: Racket 7.9 bc, Python 3.13, BDW GC 8.0.4.
The next source-backed task is
[issue #80](https://github.com/quaat/mdl-racket/issues/80), original
AND? with MSETG side effects. Full load, initialization and a Racket
gameplay transcript remain unverified. No upstream bytes, GPLv3 code,
public license or exposed evaluator changed.
