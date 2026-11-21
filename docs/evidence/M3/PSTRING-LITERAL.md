# M3 custom WORD-primtype literal — issue #88

**Gate: PASS for the scoped literal slice; full M3 gate incomplete.**
Parent merged main commit: `87377b3` (PR #89). Pinned upstream commits
in `sources.lock.json`: MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

The first blocked source form was `81tell-repl.mud` expression 2,
line 3, `(OBJ #PSTRING 0)` in `PSTRING`. The parser split this into
three formal-list nodes even though `#PSTRING 0` is one typed literal.
The [MDL manual §6.2–6.3.4](https://mdl-language.readthedocs.io/en/latest/06-data-types/)
defines # notation as reading the primitive representation and changing
its TYPE. Six isolated pinned Confusion cases in
[`pstring-literal-cases.json`](pstring-literal-cases.json) and
[`pstring-literal-reference.json`](pstring-literal-reference.json)
confirm PSTRING TYPE, WORD primitive, equality to a CHTYPEd #WORD,
and binding as an AUX default. Three deliberate cases in
[`pstring-literal-error-reference.json`](pstring-literal-error-reference.json)
show an unknown-type error, plus native acceptance of a mismatched
LIST type and FLOAT representation. The Racket slice rejects those
last two under the manual's CHTYPE primitive check and the scoped
integer WORD representation. Native binary SHA256:
`cd7bfffe22265b3f63dfd2713330507c53e6182ec9f41ba4aa3d818127252580`.
Each probe uses an isolated local process and `<QUIT>`, no RNG or game
input.

`TMPDIR=/tmp raco test tests/pstring_literal_test.rkt` first exited 1:
the reader produced two nodes for `#PSTRING 0` and the test expected
one. After the parser and compiler change, it exits 0 with 14 checks.
`make test` exits 0 with 1,135 Racket and 22 Python tests.
`make m2-check` exits 0 with G3 58, 12 native primitive probes and
five-turn native capture. `make m3-source-progress` exits 0: 36
historical text files parsed, four nontext, 144 original forms
completed, 120 beyond the accepted M2 prefix, zero skipped. The
full loader itself exits 1 at `81tell-repl.mud` expression 10,
line 27–28: function-style `#DECL ("VALUE" ...)` is not yet accepted.
See [`source-progress-pstring-literal.json`](source-progress-pstring-literal.json)
for every encountered source SHA256 and the exact failure diagnostic.

Reproduce after `make reference-build`:

```bash
make test
make m2-check
make m3-source-progress
git diff --check
```

Local versions: Racket 7.9 bc, Python 3.13, BDW GC 8.0.4.
Custom `#type` literals with integer WORD data are supported after
type registration. Other primitive representations, FLOAT bit
reinterpretation and unknown types fail explicitly. Full source
load, initialization, runtime equivalence and gameplay parity
remain unverified. No `.cache/upstream/` bytes, GPLv3 source, public
license or exposed evaluator changed. Next task:
[issue #90](https://github.com/quaat/mdl-racket/issues/90).
