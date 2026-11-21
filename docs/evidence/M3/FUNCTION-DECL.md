# M3 positional `#DECL` metadata on FUNCTION — issue #90

**Gate: PASS for the scoped declaration slice; full M3 gate incomplete.**
Parent merged main commit: `fcbb281` (PR #91). Pinned upstream commits
in `sources.lock.json`: MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

The first blocked source form was `81tell-repl.mud` expression 10,
line 27–28, `#DECL ("VALUE" ATOM <PRIMTYPE STRING> "OPTIONAL" FIX
<OR STRING FALSE> <OR STRING FALSE>)` in DEFINE TELL. The
[MDL manual §14.9](https://mdl-language.readthedocs.io/en/latest/14-data-type-declarations/)
defines this as positional RSUBR declaration data, unlike ATOM
declaration pairs. Four clean pinned Confusion cases in
[`function-decl-cases.json`](function-decl-cases.json) and
[`function-decl-reference.json`](function-decl-reference.json)
show definitions and calls succeed. Five deliberately mismatched
cases in [`function-decl-error-cases.json`](function-decl-error-cases.json)
and [`function-decl-error-reference.json`](function-decl-error-reference.json)
show that Confusion does not enforce positional Patterns when this
declaration is attached to FUNCTION. The probe target exits 0 for
those cases because non-enforcement is the observation. Native
binary SHA256:
`cd7bfffe22265b3f63dfd2713330507c53e6182ec9f41ba4aa3d818127252580`.
Each case uses an isolated local process and `<QUIT>`, no RNG or game
input.

`TMPDIR=/tmp raco test tests/function_decl_metadata_test.rkt`
initially exited 1 at `mdl-decl: expected atom-list/pattern pairs`.
After the declaration-data parser change it exits 0 with 13 checks.
`make test` exits 0 with 1,148 Racket and 22 Python tests.
`make m2-check` exits 0 with G3 58, 12 native probes and five-turn
capture. `make m3-source-progress` exits 0: 36 historical text files
parsed, four nontext, 157 original forms completed, 133 beyond the
accepted M2 prefix, zero skipped. The full loader itself exits 1 at
`81tell-repl.mud` expression 23, line 45 column 11, `!\ ` treated as
unsupported SEGMENT notation. See
[`source-progress-function-decl.json`](source-progress-function-decl.json)
for every encountered source SHA256 and the exact failure diagnostic.

Reproduce after `make reference-build`:

```bash
make test
make m2-check
make m3-source-progress
git diff --check
```

Local versions: Racket 7.9 bc, Python 3.13, BDW GC 8.0.4. The
positional declaration is validated and retained as metadata, but
not enforced on FUNCTION, matching pinned Confusion. `"QUOTE"`,
`"TUPLE"`, `"ARGS"` and `"CALL"` positional markers and actual
RSUBR execution remain unsupported. Full source load, game
initialization, runtime equivalence and gameplay parity remain
unverified. No `.cache/upstream/` bytes, GPLv3 source, public license
or exposed evaluator changed. Next task:
[issue #92](https://github.com/quaat/mdl-racket/issues/92).
