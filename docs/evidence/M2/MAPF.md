# M2 MAPF and original FLAGWORD correction — 2026-11-20

**Scope:** issue #65 on `feat/m2-mapf`, based on MEMQ stack commit
`8c847933f81297457dd096a14a57677f01b15d2b`. The original 81prim.mud
and all `.cache/upstream/` files remain unchanged. This is a branch result,
not an M2 mainline PASS.

## Provenance and reference

`sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and reconstructed
mdlzork/Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
The exact `81prim.mud` SHA-256 is
`8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`;
the rebuilt local native Confusion binary SHA-256 is
`1d540d2df348479d4740290d4190533b71d94a8308193811b96e52898798b886`.
All probes use one local Confusion process per case, with the case expression
followed by `<QUIT>` and a three or five second timeout. No RNG or game
commands are involved.

| Corpus | Outcome | Coverage |
|---|---|---|
| `mapf-{cases,reference}.json` | 28/28 clean; exit 0 | LIST/VECTOR/UVECTOR, multi-input, shortest termination, empty, native/interpreted/final FUNCTION, structured values passed once, integer applicable, MAPRET/STOP/LEAVE, nested and zero-input maps, original FLAGWORD. |
| `mapf-control-{cases,reference}.json` | 11/11 clean; exit 0 | Left-to-right order, final FUNCTION, declaration, FALSE-final map-control behavior, default MAPLEAVE, UNWIND cleanup. |
| `mapf-error-{cases,reference}.json` | 4 deliberately invalid observations, one interpreter break; harness exit 1 | No live MAPRET/STOP/LEAVE and non-structured input. The non-applicable loop case enters the reference error level; it is not a clean result. |
| `mapf-function-context-{cases,reference}.json` | 2 clean, 1 deliberate error; harness exit 1 | Nested function call and live outer local work; an escaped FUNCTION does not implicitly capture an expired PROG local in Confusion. |
| `typeq-{cases,reference}.json` / `typeq-error-*` | 6 clean; one missing-value error, two valid misses | Original FLAGWORD's TYPE? dependency. |
| `get-initial-oblist-{cases,reference}.json` | 6/6 clean; exit 0 | Native startup OBLIST associations and GROUP-GLUE miss. |
| `flagword-error-{cases,reference}.json` | deliberate break; harness exit 1 | Repeated ATOM invokes original MSETG conflict. |

The native results follow the [manual's MAPF basics and map control](https://mdl-language.readthedocs.io/en/latest/10-looping/)
except that a FALSE final function with MAPRET/MAPSTOP yields the current
first input element in the pinned build, independent of control arguments.
This was fixed after three additional red regressions. The TYPE? behavior
was confirmed against the [MDL Primer's predicate description](https://ifarchive.org/if-archive/infocom/info/MDL_Programming_Primer.pdf)
and direct native probes. Native startup source (`macros.cpp`,
`mdl_interp_init`) seeds four reciprocal INITIAL/ROOT OBLIST associations;
the Racket session now seeds matching associations.

## Red to green and integration

`raco test tests/mapf_test.rkt` initially exited 1 at unassigned MAPF,
then passed 26 assertions after the first implementation. Three new
FALSE-final control checks failed (actual FALSE/9/9 versus native 1/7/7);
the corrected traversal passes 40 checks. `raco test tests/typeq_test.rkt`
initially exited 1 at unassigned TYPE?, then passes 9 checks.
`raco test tests/startup_oblist_assoc_test.rkt` initially failed two
association checks and raised on LOOKUP's FALSE OBLIST; it now passes
4 checks. The G3 run advanced from MAPF to TYPE?, then to the startup
OBLIST association, before passing 59 assertions. These are distinct
observed original-source dependencies, not source substitutions.

`make test-historical` exits 0: VFLOAD 23, DECL 21, original MSETG and
PSETG probes pass. `make test-m2-g3` exits 0: 59 original-definition
assertions pass in one session. `racket scripts/mdl_load.rkt --source-root
.cache/upstream/mdlzork/mdlzork_771212/patched_confusion --entry
77loadall.mud --report artifacts/m2/mapf-full-load.json` exits 1 after
24 completed expressions at original NEWSTRUC's unassigned EMPTY?
(`77defs.mud` expression 15). That full-loader result is separately
recorded and is not a G3 success.

Final local command results on the uncommitted branch head: `make doctor`
exit 0 (Python 3.13.0, Racket 7.9 bc, BDW GC 8.0.4); `make sources`
exit 0 (two pinned repos); `make check-source` exit 0 (36 parsed text,
four nontext, zero parse failures); `make test` exit 0 (958 Racket checks,
13 Python tests); `make test-historical` and `make test-m2-g3` exit 0 as
above; `make reference-probe` exit 0 (12 cases); `make reference-capture`
exit 0 (five turns); `git diff --check` exit 0. `make compare
CANDIDATE=artifacts/reference/house.json` exits 0 as a transport/self
check only, not Racket parity. A separate comparison of the fresh capture
to approved `docs/evidence/M0/house-golden.json` finds identical scenario,
five command records, completion, and game SHA; the native build banner
timestamp and executable hash differ as documented in M0.

## Implementation and limits

The runtime accepts an inline FUNCTION and applies already evaluated MAPF
elements without rebuilding nested MDL structures. Map-control escapes
unwind existing function activations; tests verify nested control,
UNWIND cleanup, and no surviving map context after an exception.
STRUCTURED values currently covered are LIST, VECTOR, UVECTOR, STRING,
TUPLE and FALSE. Integer applicable indexing is supported; other
historical applicable types are not claimed. `#FUNCTION` reader notation,
explicit `CLOSURE`, MAPR, and full indirect APPLY remain unsupported.
Unknown constructs continue to fail strictly. The runtime still has the
documented strong-reference association and non-resumable ERROR deviations.
Confusion's GPLv3 implementation remains an isolated reference dependency;
no source was copied into the MIT-0 runtime. No exposed evaluator or server
was added.

**Next task:** audit indirect APPLY/DISPATCH and continuation requirements,
then rerun G3 and the complete M2 acceptance suite on the integrated head.
