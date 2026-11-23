# M3 `%<>` reader macro value — issue #86

**Gate: PASS for the scoped `%<>` slice; full M3 gate incomplete.**
Parent merged main commit: `bf434f7` (PR #87). Pinned upstream commits
in `sources.lock.json`: MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

The first blocked construct was `%<>` inside `SOBJECT` in
`77makstr.mud` expression 6, line 73. The
[MDL manual §17.1.1](https://mdl-language.readthedocs.io/en/latest/17-macro-operations/)
defines `%` as an immediate read-time evaluation and substitution.
The empty FORM has no side effects and yields canonical empty FALSE.
Six isolated pinned Confusion cases in
[`percent-empty-cases.json`](percent-empty-cases.json) and
[`percent-empty-reference.json`](percent-empty-reference.json)
confirm TYPE FALSE, false truth, identity across occurrences and
calls, and source-shaped use. The native binary SHA256 is
`cd7bfffe22265b3f63dfd2713330507c53e6182ec9f41ba4aa3d818127252580`.
Each case uses one local process and `<QUIT>`, no RNG or game input.

`TMPDIR=/tmp raco test tests/percent_empty_test.rkt` initially exited
1 at `mdl-compiler: 1:7: this MDL data construct is not implemented`.
After the narrow compiler change, it exits 0 with eight checks.
`make test` exits 0 with 1,121 Racket checks and 22 Python tests.
`make m2-check` exits 0 with G3 58, 12 native probes and five-turn
native capture. `make m3-source-progress` exits 0: 36 historical
text files parsed, four nontext, 136 original forms complete, 112
beyond the accepted M2 prefix, zero skipped. The full loader itself
exits 1 at `81tell-repl.mud` expression 2, line 3 column 38:
unsupported three-element AUX formal `(OBJ #PSTRING 0)`. See
[`source-progress-percent-empty.json`](source-progress-percent-empty.json).
The source SHA256 values for every encountered file are in that report.

Reproduce after `make reference-build`:

```bash
make test
make m2-check
make m3-source-progress
git diff --check
```

Local versions: Racket 7.9 bc, Python 3.13, BDW GC 8.0.4. Only
`%<>` is supported; other `%` payloads and `%%` remain unsupported
and fail explicitly. The broader read-time macro operation, full
source load, initialization, runtime equivalence and gameplay parity
remain unverified. No `.cache/upstream/` bytes, GPLv3 source, public
license or exposed evaluator changed. Next task:
[issue #88](https://github.com/quaat/mdl-racket/issues/88).
