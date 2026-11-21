# M3 `!\` CHARACTER reader notation — issue #92

**Gate: PASS for the scoped reader slice; full M3 gate incomplete.**
The completed original-form count stays 157; the source failure moves
within expression 23. Parent merged main commit: `66e7032` (PR #93).
Pinned upstream commits in `sources.lock.json`: MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

The first blocked token was `!\ ` at `81tell-repl.mud` expression 23,
line 45, `<PRINC !\ >`. The
[MDL manual §7](https://mdl-language.readthedocs.io/en/latest/07-structured-objects/)
defines `!\` plus one ASCII character as a CHARACTER value. Five
isolated pinned Confusion probes in
[`space-character-cases.json`](space-character-cases.json) and
[`space-character-reference.json`](space-character-reference.json)
confirm TYPE CHARACTER, PRIMTYPE WORD, ASCII 32 for space, identity
and function return. Native binary SHA256:
`cd7bfffe22265b3f63dfd2713330507c53e6182ec9f41ba4aa3d818127252580`.
Each case uses one local process and `<QUIT>`, no RNG or game input.

`TMPDIR=/tmp raco test tests/space_character_test.rkt` initially
exited 1: three reader assertions failed because `!\ ` became a
SEGMENT, then the compiler raised `unsupported SEGMENT notation`.
After the reader/compiler change, it exits 0 with 12 checks.
`make test` exits 0 with 1,160 Racket and 22 Python tests.
`make m2-check` exits 0 with G3 58, 12 native probes and five-turn
capture. `make m3-source-progress` exits 0: 36 historical text files
parsed, four nontext, 157 original forms completed, 133 beyond the
accepted M2 prefix, zero skipped. The full loader itself exits 1 at
`81tell-repl.mud` expression 23, line 46 column 31: unsupported
`%<STRING <ASCII 10>>` read macro. See
[`source-progress-space-character.json`](source-progress-space-character.json)
for every encountered source SHA256 and exact failure diagnostic.

Reproduce after `make reference-build`:

```bash
make test
make m2-check
make m3-source-progress
git diff --check
```

Local versions: Racket 7.9 bc, Python 3.13, BDW GC 8.0.4. `!\`
CHARACTER syntax works in data and expression positions; existing
SEGMENT tests still pass. The Racket `ASCII` SUBR and general percent
read macros remain unsupported. Full source load, initialization,
runtime equivalence and gameplay parity remain unverified. No
`.cache/upstream/` bytes, GPLv3 source, public license or exposed
evaluator changed. Next task:
[issue #94](https://github.com/quaat/mdl-racket/issues/94).
