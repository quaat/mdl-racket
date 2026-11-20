# M2 requirements traceability audit — 2026-11-20

Source: the original M2 Build and Gate in [`docs/PLAN.md`](../../PLAN.md).
This audit applies to the stacked `feat/m2-indirect-apply` branch after
issue #69's correction. **PASS** means tested within the stated M2
surface, not complete historical MDL compatibility or game parity.
The branch-level G3 scenario passes; M2 milestone acceptance remains
**NOT RUN on `main`** until authorized integration and required CI/review.

| Required capability | Classification on this branch | Behavioral evidence and limit |
|---|---|---|
| DEFINE required, OPTIONAL, AUX, TUPLE, ARGS, declarations | PASS | [`FORMALS.md`](FORMALS.md), [`DECLARATIONS.md`](DECLARATIONS.md), [`DECLARATION-PATTERNS.md`](DECLARATION-PATTERNS.md); `tests/formals_test.rkt`, `declaration*_test.rkt`, original MSETG/FLAGWORD. `"BIND"`/`"CALL"` markers remain explicit unsupported forms outside this stated subset. |
| DEFMAC and runtime expansion | PASS | [`MACROS.md`](MACROS.md), `tests/macro_test.rkt`, original TRNN expansion in G3. |
| COND and direct function application | PASS | `tests/integration_test.rkt`, `macro_test.rkt`, original MSETG/FLAGWORD branching in G3. |
| PROG and REPEAT | PASS | [`PROG.md`](PROG.md), [`REPEAT.md`](REPEAT.md), `tests/prog_test.rkt`, `repeat_test.rkt`; named and unnamed frames. |
| RETURN and AGAIN, implicit/explicit targets | PASS | [`ACTIVATIONS.md`](ACTIVATIONS.md), [`ACTIVATION-TARGETS.md`](ACTIVATION-TARGETS.md), [`CONTROL.md`](CONTROL.md); `tests/activation_target_test.rkt`, `control_test.rkt`, and issue #69 APPLY to an outer activation. |
| MAPF iteration and map control | PASS | [`MAPF.md`](MAPF.md), 28 clean basic and 11 clean control native cases, `tests/mapf_test.rkt`, original FLAGWORD in G3. MAPR and `#FUNCTION` reader syntax are outside the tested MAPF slice and remain explicit unsupported capabilities. |
| UNWIND | PASS for the documented M2 manual contract | [`CONTROL.md`](CONTROL.md) and `tests/control_test.rkt` cover normal return, nonlocal RETURN/AGAIN, and error cleanup; MAPLEAVE cleanup is in `tests/mapf_test.rkt`. Pinned Confusion skips cleanup on an error-level break, while this runtime follows the manual and runs it. That recorded deviation prevents a claim of full runtime equivalence on errors. |
| Indirect APPLY and computed operator dispatch | PASS for tested applicable types | [`INDIRECT-APPLY.md`](INDIRECT-APPLY.md), 15 clean native cases and separate deliberate errors; `tests/indirect_apply_test.rkt`, `loader_test.rkt`. Native SUBR, interpreted/compiled FUNCTION, MAPF, and FIX indexing/PUT are covered. MACRO and raw-argument formal restrictions are checked. Other applicable types still fail explicitly. |
| Cross-file loading and shared state | PASS for the M2 prefix | [`SOURCE-LOADER.md`](SOURCE-LOADER.md), [`HISTORICAL-VFLOAD.md`](HISTORICAL-VFLOAD.md), [`G3-GATE-MAPF.md`](G3-GATE-MAPF.md). Original 77loadall executes 24 forms and zero skips before the separate M3 EMPTY? dependency. |
| Aliasing and mutation | PASS | `tests/sequence_test.rkt`, `segment_test.rkt`, original G3 global LIST alias observed through PUT/NTH; MAPF passes already evaluated structured elements without copying. |
| Continuation ownership, validity and transfer | PASS for tested M2 paths | `tests/activation_target_test.rkt`, `control_test.rkt`, `mapf_test.rkt`, indirect APPLY outer RETURN, and core activation invariants. Stale frames and invalid targets fail; dynamic-wind cleanup clears escaped map context. General error resumption/ERRET and TAG remain unsupported, with no claim of complete MDL continuation parity. |

The first uncovered item was indirect APPLY/DISPATCH: before issue #69,
`<APPLY ,+ 1 2 3>` failed at unassigned APPLY and `<.F 1 2>` failed
compilation. Its native reference and red-to-green fix are in
[`INDIRECT-APPLY.md`](INDIRECT-APPLY.md). No required row remains
unverified within the documented M2 subset. This matrix is not a
substitute for final-head CI, review, and mainline verification.

**Separate historical progress:** the complete `77loadall.mud` chain
still exits 1 at EMPTY? inside source-defined NEWSTRUC after 24 completed
expressions. This is the observed first M3 source dependency and must
not be presented as a successful game boot. `ERROR` remains
non-resumable locally; reference error-level behavior, weak association
GC, explicit CLOSURE, TAG, and broad applicable types are known limits.

**Provenance and security:** `sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and
mdlzork/Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
The exact G3 source hashes are in [`G3-GATE-MAPF.md`](G3-GATE-MAPF.md).
No upstream bytes were changed, no GPLv3 source was copied into the
MIT-0 runtime, and no MDL evaluator was exposed to a network client.
