# M3 APPLICABLE declaration Pattern — issue #84

**Gate: PASS for the scoped Pattern slice; full M3 gate incomplete.**
Parent merged main commit: `5f217fd` (PR #85). Pinned upstream commits
in `sources.lock.json`: MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

The first blocked form was `77defs.mud` expression 78, line 448,
`#DECL ((FN) <OR APPLICABLE ATOM FIX>)` in `DA`. The manual §14.1
defines `APPLICABLE` as a compound type name. Six isolated native
[`APPLICABLE?` cases](applicable-predicate-cases.json) produce T for
FIX, FUNCTION, MACRO and SUBR, FALSE for ATOM and LIST; see their
[`reference capture`](applicable-predicate-reference.json). Ten direct
[`DECL?` cases](applicable-decl-cases.json), including the original OR
shape, all enter Confusion's `BAD-TYPE-SPECIFICATION1` with `Atom REP
has neither LVAL nor GVAL`; see the retained
[`reference capture`](applicable-decl-reference.json). The probe target
exits 1 for these deliberately erroneous cases. The Racket Pattern
follows the manual and the native type applicability partition, an
explicit pinned-reference deviation. Native binary SHA256:
`cd7bfffe22265b3f63dfd2713330507c53e6182ec9f41ba4aa3d818127252580`.
Each probe runs in a separate local process with `<QUIT>`; no RNG,
game input or time-sensitive expression is used.

`TMPDIR=/tmp raco test tests/applicable_decl_test.rkt` first exited 1
at `mdl-decl: DECL?: unknown declaration type APPLICABLE`. After the
Pattern change it exits 0 with 16 checks. `make test` exits 0 with
1,113 Racket checks and 22 Python tests. `make m2-check` exits 0 with
G3 58, 12 native primitive probes and five-turn native capture.
`make m3-source-progress` exits 0: 36 historical text files parsed,
four nontext, 112 original forms completed, 88 beyond the accepted M2
prefix, zero skipped. The full loader itself exits 1 at
`77makstr.mud` expression 6, line 73 column 29, unsupported `%<>`
data construct. See [`source-progress-applicable-decl.json`](source-progress-applicable-decl.json).
Source SHA256 values: `77loadall.mud`
`389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa`,
`81prim.mud` `8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`,
`77defs.mud` `566ebcc32be9b9226dd7cefd77a517583eebab80a03f452df39e13b85eed734e`;
the `77makstr.mud` hash is in the source-progress JSON.

Reproduce after `make reference-build`:

```bash
make test
make m2-check
make m3-source-progress
git diff --check
```

Local versions: Racket 7.9 bc, Python 3.13, BDW GC 8.0.4. Only
callable representations supported by this runtime match APPLICABLE;
custom APPLYTYPE, CLOSURE, OFFSET and RSUBR remain unsupported.
`APPLICABLE?` as a runtime SUBR is also not implemented. Full source
load, game initialization, runtime equivalence and gameplay parity
remain unverified. No `.cache/upstream/` bytes, GPLv3 source, public
license or exposed evaluator changed. Next task:
[issue #86](https://github.com/quaat/mdl-racket/issues/86).
