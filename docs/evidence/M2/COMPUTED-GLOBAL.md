# Computed global reader correction — issue #58

**Result:** focused reader slice PASS on `feat/m2-computed-global`; integrated
M2 G3 remains **FAIL**. The original `MSETG` conflicting-repeat path now
reaches unsupported `ERROR` ([issue #60](https://github.com/quaat/mdl-racket/issues/60)).
M3 has not started.

## Provenance and contract

This branch is stacked on `cfca370` (`N=?`), `e6d295d` (D5), and merged-main
`419fc5c`. `sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and reconstructed
mdlzork/Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
`81prim.mud` SHA256 was independently verified as
`8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`.
The [MDL manual chapter 4](https://mdl-language.readthedocs.io/en/latest/04-values-of-atoms/)
and pinned Confusion both treat `,.FOO` as GVAL of FOO's local value.
Reference cases and exact outputs are in `computed-global-cases.json` and
`computed-global-reference.json`: direct lookup returns `3`, nested addition
returns `4`, and original `MSETG` first/equal-repeat returns `T`, `T`.
Reference inputs ran in one local process per case with no RNG inputs.

## Red to green and commands

Before the parser change, `TMPDIR=/tmp raco test tests/parser_test.rkt
tests/binding_test.rkt` failed: `,.FOO` parsed as literal global `.FOO`;
compiled evaluation raised `mdl-gval: unassigned MDL global .FOO`. The
hash-verified original MSETG equal-repeat failed at the same boundary.

After the change:

| Command | Exit | Evidence |
|---|---:|---|
| `TMPDIR=/tmp raco test tests/parser_test.rkt tests/binding_test.rkt` | 0 | 56 checks |
| `make test` | 0 | 884 Racket checks; 13 Python tests |
| `make test-historical` | 0 | VFLOAD 23, DECL 20, and MSETG first/equal-repeat assertions |
| `racket scripts/mdl_load.rkt --source-root .cache/upstream/mdlzork/mdlzork_771212/patched_confusion --entry 77loadall.mud --report artifacts/m2/computed-global-load.json` | 1, expected | 24 completed expressions, then unassigned `EMPTY?` at `77defs.mud` expression 15 |

The historical probe copies pinned `81prim.mud` bytes into an isolated
temporary root, verifies their SHA and equality, loads all eight top-level
expressions without skips, invokes `MSETG` twice, and verifies the global
remains `3`. Plain `,FOO` and existing `,<FORM>` paths remain covered by
the ordinary suite. Unknown globals still fail explicitly.

## Limits and next action

The source-defined `MSETG` conflicting-repeat branch reaches `ERROR`,
which is not yet implemented; this is a known G3 failure, not a passing
error-path assertion. Original `PSETG` still awaits `MEMQ`; the integrated
G3 branch must be rerun after corrections. This change is reader-only:
no upstream or GPLv3 source was changed or copied, no production service
was exposed, and no gameplay parity is claimed. Probe `ERROR` against the
pinned reference, implement it in issue #60, then rerun G3.
