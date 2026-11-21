# M2 indirect APPLY and computed FORM dispatch — issue #69

**Branch:** `feat/m2-indirect-apply`, based on MAPF PR #68 head
`8ec526b571e0f9e99a8146358234e35f37944194`.
The original M2 build in `docs/PLAN.md` requires indirect APPLY/DISPATCH.
Before this slice, `<APPLY ,+ 1 2 3>` raised unassigned APPLY, and the
compiler rejected a computed FORM head such as `<.F 1 2>`.

## Native reference and semantics

The [MDL manual section 9.10](https://mdl-language.readthedocs.io/en/latest/09-functions/)
specifies evaluated APPLY arguments and forbids a FUNCTION with raw
quoted or ARGS/CALL formals. `indirect-apply-{cases,reference}.json`
contains **15 clean cases** from the pinned native Confusion executable:
native SUBR, interpreted FUNCTION, compiled DEFINE with TUPLE, indexed FIX
reads/writes, MAPF via APPLY, structured value preservation, left-to-right
operator/argument evaluation, local/global computed heads, quoted formal
binding for a computed head, and a RETURN through APPLY to an outer
activation. `indirect-apply-error-{cases,reference}.json` keeps **nine
deliberate invalid cases** separate: missing target, non-applicable
objects, quoted/ARGS/MACRO restrictions, excess FIX arguments, and
rebinding `+` to a FIX that then tries to PUT into an unstructured item.
The error probe command exits 1 by design; reference error levels and
stderr are preserved, not counted as passing calls.

`sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and reconstructed
mdlzork/Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
The native binary SHA-256 is
`1d540d2df348479d4740290d4190533b71d94a8308193811b96e52898798b886`.
The probe protocol is one local process per case, expression followed by
`<QUIT>`, timeout three seconds. No RNG or game input is involved.

## Red to green and implementation

`raco test tests/indirect_apply_test.rkt` initially exited 1 at
unassigned APPLY. After implementing APPLY and computed-head compilation,
focused tests found two gaps: the FORM result of a quoted formal was
checked outside its atom space (test correction), and compiled DEFINE
with ARGS needed metadata to enforce APPLY's native rejection. A full
`make test` run then failed an existing rebinding regression: a FIX
operator with two arguments had incorrectly used general PUT association
dispatch. The corrected path requires a structured target and performs
indexed element PUT, as pinned Confusion does. A further red test showed
`mdl-session-call` re-evaluated an already evaluated LIST containing a
FORM when invoking an interpreted FUNCTION; it now passes values directly.
The host `mdl-apply` value API uses the same evaluated application path.

Computed FORM dispatch now evaluates the head first and calls a shared
runtime dispatcher. The dispatcher retains raw argument forms for a
MACRO or interpreted FUNCTION with quoted formals; native procedures and
FIX applicables receive evaluated arguments once. APPLY uses evaluated
arguments and checks MACRO, quoted formal and ARGS restrictions before
invoking the target. Unknown applicable types raise explicit errors.
The resulting focused suite passes 26 assertions, loader/session tests
pass, `make test` exits 0 with 986 Racket checks and 13 Python tests,
`make test-historical` exits 0 (VFLOAD 23, DECL 21, original MSETG/PSETG),
and `make test-m2-g3` exits 0 with 59 original-definition assertions.
`make m2-check` exits 0 and repeats doctor, locked-source verification,
source sweep (36 parsed, four nontext), the 986/13 suites, historical
and G3 targets, twelve native reference primitive probes, a five-turn
capture, and `git diff --check`. The sweep is written to
`artifacts/m2/reader-sweep.json`, leaving frozen M0 evidence untouched.

**Remaining limits:** FSUBR targets are not first-class values in this
subset, `"CALL"` formals are rejected by the compiler, and broader MDL
applicable types (including explicit CLOSURE) are still unsupported.
These are strict failures, not silent fallbacks. The complete source
loader remains at the separate M3 EMPTY? barrier after 24 original
expressions. No upstream source was changed, no GPLv3 Confusion code was
copied into the MIT-0 runtime, and no network MDL evaluator was added.
