# M3 original NEWTYPE declaration correction — 2026-11-21

**Issue #76 slice PASS; complete M3 source-load gate INCOMPLETE.** The
branch `feat/m3-newtype-decl` starts from merged main commit
`b93029a12bbe850c8c258377373cf3771062b470`. The implementation
commit and final CI runs are recorded on the PR after publication.

## Provenance and semantic choice

`sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and
mdlzork/Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
Verified SHA256: `77loadall.mud`
`389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa`,
`81prim.mud` `8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`,
and `77defs.mud` `566ebcc32be9b9226dd7cefd77a517583eebab80a03f452df39e13b85eed734e`.
The local native Confusion binary SHA256 is
`cd7bfffe22265b3f63dfd2713330507c53e6182ec9f41ba4aa3d818127252580`.

The [MDL manual §14.6](https://mdl-language.readthedocs.io/en/latest/14-data-type-declarations/)
specifies that NEWTYPE's third quoted Pattern is stored as a `DECL`
association and checked by CHTYPE. The original
`77defs.mud` expression 17 supplies this form for EXIT. Pinned
Confusion reads but discards the third argument; the seven clean cases
in `newtype-decl-reference.json` show `GET EXIT DECL`/`GET M3N DECL`
returning empty FALSE and a FIX-only Pattern allowing an ATOM element.
The pinned `confusion_patched/macros.cpp` NEWTYPE routine confirms that
it reads `desc` but passes only the first two arguments to type
registration. Six deliberate errors in
`newtype-decl-error-reference.json` show missing/extra arguments,
invalid base type, incompatible redefinition, and non-ATOM name.
Each probe used a separate local Confusion process with appended
`<QUIT>`; no game input or RNG seed was involved. Deliberate error
captures are marked unsuccessful by the probe even if the process later
exits zero after QUIT.

This runtime follows the manual: it validates supported Pattern syntax
at NEWTYPE, stores the actual Pattern under the type's `DECL` association,
resolves forward type names at CHTYPE, and rejects a cast that violates
it, including an identical-type recast. It supports
`<<PRIMTYPE VECTOR> ...>` declaration heads required by original EXIT;
the same-primitive NEWTYPE call can replace a Pattern. Confusion's
omission and its explicit DECL? rejection of that headed form are
documented runtime-equivalence deviations, not silently emulated.
Unsupported pattern shapes and OPT repetition fail explicitly.

## Red to green and source progress

`TMPDIR=/tmp raco test tests/newtype_decl_test.rkt` initially exited
1 at `mdl-newtype: arity mismatch` for the exact three-argument shape.
The first implementation passed its focused tests and advanced the
unchanged loader to 36 forms. `make test` then exited 2 with two existing
declaration-pattern expectations: one now-supported PRIMTYPE-headed
form and one unrelated malformed OR head. The first expectation was
updated to a positive manual-backed assertion; the OR head again fails
as before. A later malformed-Pattern regression failed 2/16 focused
checks because NEWTYPE stored an unsupported Pattern without immediate
error; explicit shape validation fixed it. The final focused
`newtype_decl_test.rkt` passes 16 checks; declaration pattern tests pass
their existing checks plus the new positive case.

Reproduce after `make reference-build` with:

```bash
make test
make m2-check
make m3-source-progress
git diff --check
```

`make test` exits 0: 1,062 Racket checks and 22 Python tests.
`make m2-check` exits 0 with G3 58 assertions, original VFLOAD 23,
DECL 20, original MSETG/PSETG, 12 native primitive cases and five-turn
native capture. `make m3-source-progress` exits 0 as a validated partial
measurement: 36 parsed historical text files, four nontext, 36
completed original forms, 12 beyond the accepted M2 prefix, zero
skipped. The underlying unchanged full loader exits 1 at
`77defs.mud` expression 27, line 139, execute stage, because `GDECL`
is still unassigned. The exact report is
[`source-progress-newtype.json`](source-progress-newtype.json).
`git diff --check` exits 0. Racket 7.9 bc, Python 3.13 and BDW GC 8.0.4
are the relevant local tool versions.

The next source-backed task is
[issue #78](https://github.com/quaat/mdl-racket/issues/78), `GDECL`
global declarations. Full original load, initialization, Racket game
transcript and gameplay parity remain unverified. No upstream file,
public license, GPLv3 reference implementation, or exposed evaluator
was changed.
