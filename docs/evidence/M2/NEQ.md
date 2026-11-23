# M2 G3 correction #57 — structural N=?

**Local primitive slice PASS on `feat/m2-structural-neq`; integrated G3
still FAIL.** This branch is based on D5 PR #54 head
`e6d295d61d8031e2523c66c2b1efa86db04bfa4a`, which is not merged.
The exact original MSETG now reaches past unassigned `N=?` and exposes a
separate reader defect: `,.FOO` is parsed as a literal global named `.FOO`
instead of a computed GVAL over local FOO. That defect is [issue
#58](https://github.com/quaat/mdl-racket/issues/58). This slice does not
claim M2 G3 PASS or start M3.

## Semantics and provenance

The [MDL manual chapter 8](https://mdl-language.readthedocs.io/en/latest/08-truth/)
defines `N=?` as the complement of structural `=?`, distinct from `N==?`
(the identity complement). The pinned Confusion reference confirms this
for finite FIX, ATOM, LIST, STRING, and NEWTYPE values. It requires exactly
two arguments; zero/one report TOO-FEW-ARGUMENTS-SUPPLIED and three report
TOO-MANY-ARGUMENTS-SUPPLIED. The implementation calls existing
`mdl-equal?`, complements its result, and wraps it as MDL T or FALSE.

`sources.lock.json`: MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916`; mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`. The source file exercised
by MSETG, `81prim.mud`, has SHA-256
`8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`.
The unchanged chain files are `77loadall.mud`
`389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa`
and `77defs.mud`
`566ebcc32be9b9226dd7cefd77a517583eebab80a03f452df39e13b85eed734e`.
Pinned native binary SHA-256 at probe time:
`987471cf0e568ad7f83a10b893484cd3fa99a86a69444c3b7d5554b16829f475`.

## Reference observations

Run from repository root after `make reference-build`:

```
.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/neq-cases.json --output docs/evidence/M2/neq-reference.json --timeout 10
# exit 0 — 8 clean cases, empty stderr
.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/neq-error-cases.json --output docs/evidence/M2/neq-error-reference.json --timeout 3
# exit 1 by design — 3 arity errors and 2 bounded cyclic timeouts
.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/computed-global-cases.json --output docs/evidence/M2/computed-global-reference.json --timeout 10
# exit 0 — 3 clean cases, including original MSETG equal repeat
```

Clean N=? outputs: equal FIX, same ATOM, separately allocated equal LIST
and STRING, and equal typed values produce `#FALSE ()`; different FIX,
LIST, and typed types produce `T`. Original MSETG after FLOAD returns T
on both its first and same-value second call; the conflicting call produces
the source's ALREADY-GASSIGNED error in
`g3-integrated-error-reference.json`. `computed-global-reference.json`
confirms `,.FOO` reads the global of the atom in local FOO, including in
another FORM. The three arity error rows have process exit 0 but `ok:false`
and an error block with the exact named diagnostic; stderr contains the
reference's unrelated `Atom REP has neither LVAL nor GVAL` line. Both
cyclic probes time out after three seconds and have no exit-code or output
fields, which must not be treated as passing parity.

For cyclic self-comparison, Racket's already documented `=?` boundary
returns T and `N=?` therefore returns FALSE; for two distinct equal-content
cycles, the comparator raises explicit unsupported cyclic structural
equality. Pinned Confusion's tested N=? cases timed out. This is a
deliberate bounded failure/deviation, not a claim of cyclic parity.

## Red to green and validation

Before implementation, `TMPDIR=/tmp raco test tests/neq_test.rkt` exited 1
at the first case with `unassigned or non-applicable MDL operator N=?`.
`racket tests/historical_neq_test.rkt` likewise exited 1 at original MSETG.
After the five-line builtin registration, the focused test exited 0 with
13 assertions. The original MSETG probe then advanced to its next blocker,
`mdl-gval: unassigned MDL global .FOO`, because the reader parses
`,.FOO` incorrectly; the test is retained for issue #58 and is not yet
part of this PR's historical target.

`make test` exited 0 (879 Racket checks, 13 Python tests). The existing
historical target as committed at D5 was run with
`git show HEAD:Makefile > /tmp/mdl-neq-base-Makefile && make -f
/tmp/mdl-neq-base-Makefile test-historical`; it exited 0 (VFLOAD 23,
DECL 20). Direct invocations of both existing historical test files
also exited 0. The unchanged full loader command
`racket scripts/mdl_load.rkt --source-root
.cache/upstream/mdlzork/mdlzork_771212/patched_confusion --entry
77loadall.mud --report artifacts/m2/neq-load.json` exited 1 as expected:
24 completed expressions and first failure at original NEWSTRUC's
unassigned EMPTY? in `77defs.mud` expression 15, line 37. `git diff
--check` exited 0. No original source was skipped or edited.

The existing M2 G3 gate remains FAIL; correcting this primitive exposed
the independent computed-global reader gap rather than satisfying the
entire original MSETG path. **Next action:** implement issue #58 in its own
branch/PR, then rerun the original-source G3 gate. No GPLv3 Confusion code
was copied into the MIT-0 runtime and no network evaluator was added.
