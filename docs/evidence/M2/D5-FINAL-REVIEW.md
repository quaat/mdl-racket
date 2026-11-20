# D5 final-head independent local review — issue #53 / PR #54

**Review scope:** D5 diff from merged `main` `419fc5c` through prior head
`e6d295d`, including association storage, PUT/GET dispatch, declaration
aliases, CHARACTER values, aliasing, original-source regressions, and
session isolation. The hosted Codex review request on `e6d295d` was
declined because of a service usage limit; this local review examines the
source, tests, and pinned reference directly. It does not grant merge
authorization. Integrated M2 G3 remains FAIL on the dependent stack.

| Severity | Finding and disposition |
|---|---|
| **P2, corrected (#67)** | FIX-indicator PUT/GET on a native SUBR previously called `mdl-primtype` on a host procedure and raised `unsupported MDL type`. Pinned Confusion stores and retrieves the association. The dispatch now treats host procedures, which represent native SUBRs, as unstructured association items. Two focused regressions failed before the fix and pass after it. |
| **P3, retained M2 limit** | Pinned Confusion reads the first structural element of a FUNCTION with `GET`. This runtime has no general `FUNCTION` literal evaluator or mutable FUNCTION structure view; direct `<FUNCTION ...>` remains an explicit unassigned-operator failure. This is an M2 function/application task, outside the D5 association slice. |
| **Documented deviations** | Association entries hold strong references until removal/session end; DECL alias cycles raise explicitly while pinned Confusion loops; immutable host STRING literals cannot be PUT-mutated. None silently returns a false result. |

The prior three D5 inline findings remain corrected: item/indicator
matching uses `mdl-identical?` for WORD and REST-view keys; nested DECL
aliases are normalized with cycle detection; STRING GET and SEGMENT share
the CHARACTER representation, and indexed PUT accepts it. Two-argument
structured PUT with a FIX selector still raises the reference's arity
error. `tests/atom_props_test.rkt` covers these paths, property-free fresh
sessions, false-valued associations, removal, and original RAPPLIC source.

## Reference and regression evidence

`sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and reconstructed
mdlzork/Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
The original `77loadall.mud` SHA256 is
`389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa`;
`81prim.mud` is
`8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`.
The freshly rebuilt native executable SHA256 is
`1d540d2df348479d4740290d4190533b71d94a8308193811b96e52898798b886`.
`d5-final-review-{cases,reference}.json` records six clean native cases
with no RNG input. SUBR FIX association lookup returns `9`, removal
leaves `#FALSE ()`, and non-FIX SUBR and FUNCTION associations work.
The sixth FUNCTION indexed-GET case returns `(X)` in Confusion and is
retained as a separate M2 gap, not a passing local D5 case.

Before the correction, `TMPDIR=/tmp raco test tests/atom_props_test.rkt`
exited **1** at `mdl-type: unsupported MDL type #<procedure:mdl-add>`
after 22 preceding checks. After the correction it exits **0** with 65
focused checks. `make test` exits **0** with 868 Racket checks and 13
Python tests; `make test-historical` exits **0** with 23 VFLOAD and 20
DECL assertions. The exact original loader command
`racket scripts/mdl_load.rkt --source-root .cache/upstream/mdlzork/mdlzork_771212/patched_confusion --entry 77loadall.mud --report artifacts/m2/d5-final-review-load.json`
exits **1 as expected** after 24 completed expressions, at unassigned
`EMPTY?` in original `NEWSTRUC` (`77defs.mud` expression 15).

The review uses no edited upstream files, no GPLv3 implementation code in
the MIT-0 runtime, and no network evaluator. No Racket game boot or
gameplay parity is claimed. The D5 slice has no remaining identified
blocking finding after #67; it still needs final-head CI and maintainer
approval before merge. M2 requires the dependent G3 and language-surface
work described in `G3-GATE.md`.
