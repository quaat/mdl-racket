# M2 reference investigation — structured `#DECL` patterns for `PSETG` (issue #48, D3)

Read-only reference probe against the pinned patched Confusion build. No
implementation, test, script, or Makefile file was touched; only the five
files referenced below were created. Interpreter:
`.cache/build/confusion_patched/mdli`, SHA-256
`a29c756df5c973e462a6ad2b318e28ec265934e89e72d825bc7672387317e629`
(matching the declaration- and segment-slice reference files).

## Expected semantics (manual chapter 14, https://mdl-language.readthedocs.io/en/latest/14-data-type-declarations/)

After `pattern ::= pat | <UNSPECIAL pat> | <SPECIAL pat>` and
`pat ::= unit | <OR unit ... unit>`, the manual's `unit` includes the
structured construction `<struc elts>` (and its SEGMENT-marked exact-count
variant `!<struc elts>`), where `struc ::= structured-type |
<PRIMTYPE structured-type>` and also `<<OR struc ... struc> elts>`. `elts`
is one or more `pat`s, optionally including NTH
repetitions `[fix pat ... pat]`, an `[opt pat ... pat]` construction, and an
indefinite `[REST pat ... pat]` construction, which "must always be the last
element of the structure declaration" and allows "any number of repetitions,
from zero on up"; at most one `[opt ...]` may appear and "only a REST
construction can follow an OPT construction". `DECL?` (section 14.7.4)
checks one value against one such pattern; its recorded examples return `T`
on a match and `#FALSE ()` otherwise — although pinned Confusion carries the
value and pattern in the `#FALSE` for ordinary element mismatches (D1
evidence). For the `PSETG` acceptance subset, `#DECL ((PL) <LIST [REST
ATOM]>)` therefore means: `.PL` is a LIST whose elements are all ATOMs, with
zero or more of them — the empty LIST `()` satisfies it, `(A)` and `(A B)`
satisfy it, and a LIST containing a non-ATOM fails it. Required element
patterns before a `[REST ...]` (e.g. `<LIST FIX [REST ATOM]>`) must be
matched in order and in full; a structure shorter than its required prefix
fails. A non-LIST value fails the pattern outright.

## Commands and exit codes

All from the repository root:

```
PYTHONPATH="$PWD/.sandbox-pydeps/lib" /usr/bin/python3 -m scripts.mdl_probe \
  --cases docs/evidence/M2/declaration-pattern-cases.json \
  --output docs/evidence/M2/declaration-pattern-reference.json
# exit 0 — "Probed 22 expressions; review: docs/evidence/M2/declaration-pattern-reference.json"
PYTHONPATH="$PWD/.sandbox-pydeps/lib" /usr/bin/python3 -m scripts.mdl_probe \
  --cases docs/evidence/M2/declaration-pattern-error-cases.json \
  --output docs/evidence/M2/declaration-pattern-error-reference.json
# exit 1 — EXPECTED BY DESIGN (deliberate-error file; complete: false)
```

Each case runs in a fresh Confusion process (stdin expression + `<QUIT>`,
cwd `.cache/upstream/mdlzork/mdlzork_771212/patched_confusion`). Every output
below is quoted from the recorded JSON files; `result_output` is the value of
the probe expression. Break-level cases keep process exit code 0 but print a
`*ERROR*` block and enter `LISTENING-AT-LEVEL 2`; the probe tool flags them
via stderr (`Atom REP has neither LVAL nor GVAL`, a pre-existing break-level
artifact also documented in `SEGMENTS.md`, not a DECL diagnostic).

## Success cases (22/22 clean) — `declaration-pattern-cases.json`, `declaration-pattern-reference.json`

| Case | Expression | Recorded result |
|---|---|---|
| `list-empty-vs-rest-atom` | `<DECL? () '<LIST [REST ATOM]>>` | `T` |
| `list-atoms-vs-rest-atom` | `<DECL? (A B) '<LIST [REST ATOM]>>` | `T` |
| `list-nonatom-vs-rest-atom` | `<DECL? (A 1) '<LIST [REST ATOM]>>` | `#FALSE (1 ATOM)` |
| `string-vs-list-pattern` | `<DECL? "s" '<LIST [REST ATOM]>>` | `#FALSE ()` |
| `list-fixes-vs-rest-fix` | `<DECL? (1 2 3) '<LIST [REST FIX]>>` | `T` |
| `list-prefix-plus-rest-good` | `<DECL? (1 A B) '<LIST FIX [REST ATOM]>>` | `T` |
| `list-prefix-plus-rest-missing-prefix` | `<DECL? (A B) '<LIST FIX [REST ATOM]>>` | `#FALSE (A FIX)` |
| `vector-rest-fix-good` | `<DECL? [1 2] '<VECTOR [REST FIX]>>` | `T` |
| `vector-rest-fix-bad` | `<DECL? [1 A] '<VECTOR [REST FIX]>>` | `#FALSE (A FIX)` |
| `uvector-rest-fix-good` | `<DECL? ![1 2] '<UVECTOR [REST FIX]>>` | `T` |
| `nested-or-in-rest-good` | `<DECL? (1 A) '<LIST [REST <OR FIX ATOM>]>>` | `T` |
| `nested-or-in-rest-bad` | `<DECL? (1 "s") '<LIST [REST <OR FIX ATOM>]>>` | `#FALSE ("s" ATOM)` |
| `rest-multi-pattern` | `<DECL? (1 A 2 B) '<LIST [REST FIX ATOM]>>` | `T` |
| `psetg-empty-list` | `<DECL? () '<LIST [REST ATOM]>>` | `T` |
| `psetg-single-atom` | `<DECL? (A) '<LIST [REST ATOM]>>` | `T` |
| `psetg-two-atoms` | `<DECL? (A B) '<LIST [REST ATOM]>>` | `T` |
| `psetg-non-atom-element` | `<DECL? (A 1) '<LIST [REST ATOM]>>` | `#FALSE (1 ATOM)` |
| `attached-compound-decl-good` | `<DEFINE F (P) #DECL ((P) <LIST [REST ATOM]>) .P> <F (A B)>` | `F` / `(A B)` |
| `attached-compound-decl-empty` | same define, `<F ()>` | `F` / `()` |
| `nth-repeat-two-fixes` | `<DECL? (1 2 3 4) '<LIST [2 FIX] [REST FIX]>>` | `T` |
| `segment-exact-pattern-good` | `<DECL? (1 2) !<LIST FIX FIX>>` | `#FALSE ((1 2) FIX)` |
| `segment-exact-pattern-extra` | `<DECL? (1 2 3) !<LIST FIX FIX>>` | `#FALSE ((1 2 3) FIX)` |

What each shows:

- **`DECL?` in the pinned build does implement the core structured
  subset** — `<LIST elts>`, `<VECTOR elts>`, `<UVECTOR elts>` element
  patterns, element-by-element checking, `#FALSE (offending-value
  offending-pattern)` payloads for element mismatches, and `T` on a match.
- **`[REST ...]` is supported, zero-or-more, and last only.** The empty
  LIST matches `[REST ATOM]` (`list-empty-vs-rest-atom`), any count of
  ATOMs matches, and a non-ATOM element fails with the offending pair
  `(1 ATOM)`. Multi-pattern REST sequences repeat element-wise
  (`rest-multi-pattern`: `(1 A 2 B)` matches the repeating `FIX ATOM`).
- **Required prefixes are enforced in order.** `(1 A B)` with
  `<LIST FIX [REST ATOM]>` passes; `(A B)` fails with `#FALSE (A FIX)` —
  the first required-prefix element is reported, not "too short".
- **The mismatch payload differs by failure mode.** Element-level
  mismatches carry `#FALSE (value pattern)`; a non-structured value (or any
  wrong overall TYPE, e.g. STRING against a LIST pattern, or the FIX
  `wrong-type-value-vs-structured-pattern` in the error file) yields bare
  `#FALSE ()` — the pinned source returns the plain FALSE object before
  structured checking when `val->type != typenum`
  (`mdl_decl.cpp:127-128,142`), so no payload is synthesized.
- **`PSETG` acceptance cases all pass** (`psetg-*`): exactly the behavior
  the original declaration `#DECL ((FOO) ATOM (PL) <LIST [REST ATOM]>)`
  (`81prim.mud:10-19`) requires — `()`, `(A)`, `(A B)` accept and `(A 1)`
  rejects. This is the D3 acceptance basis.
- **Nested `<OR ...>` inside REST composes** (`nested-or-in-rest-*`),
  matching the manual's rule that element patterns may be any legal
  Pattern.
- **VECTOR and UVECTOR structures work the same way** (`[1 2]` vs
  `<VECTOR [REST FIX]>` → `T`; `[1 A]` → `#FALSE (A FIX)`; the UVECTOR
  written in this build's own `![`/`!]` input syntax).
- **An attached compound pattern reads and installs.** `#DECL ((P) <LIST
  [REST ATOM]>)` inside `DEFINE` parses and the call returns its argument
  (`(A B)`, `()`) — Confusion does not enforce attached declarations (the
  D1 recorded deviation), so this only establishes reader acceptance.
- **NTH repetition works** (`nth-repeat-two-fixes`; out of D3 scope but the
  recorded observation confirms `[fix ...]` is live).

## Deliberate-error cases — `declaration-pattern-error-cases.json`, `declaration-pattern-error-reference.json` (probe exit 1, expected)

| Case | Expression | Recorded diagnostic |
|---|---|---|
| `wrong-type-value-vs-structured-pattern` | `<DECL? 1 '<LIST [REST ATOM]>>` | clean `#FALSE ()` (no error; see below) |
| `empty-structure-pattern` | `<DECL? () '<LIST>>` | clean `T` (no error; see below) |
| `opt-empty-list` | `<DECL? () '<LIST [OPT ATOM]>>` | result `T` but stderr `O1\n` |
| `opt-first-non-atom` | `<DECL? (1) '<LIST [OPT ATOM]>>` | `#FALSE (1 ATOM)` but stderr `O1\nO2 1\n` |
| `opt-then-rest` | `<DECL? (1 2) '<LIST [OPT FIX] [REST FIX]>>` | `T` but stderr `O1\nO2 1\n` |
| `nth-zero-repetition` | `<DECL? (1) '<LIST [0 FIX]>>` | `*ERROR* "BAD-TYPE-SPECIFICATION4"` at break level 2 |
| `special-wrapper` | `<DECL? 3 '<SPECIAL FIX>>` | `*ERROR* "DECL-ELEMENT-NOT-FORM-OR-ATOM"` |
| `unspecial-wrapper` | `<DECL? 3 '<UNSPECIAL FIX>>` | same `DECL-ELEMENT-NOT-FORM-OR-ATOM` |
| `primtype-structured-composition` | `<DECL? (1 A) '<<PRIMTYPE LIST> [REST FIX ATOM]>>` | same `DECL-ELEMENT-NOT-FORM-OR-ATOM` |
| `or-of-structures-composition` | `<DECL? (1 2) '<<OR LIST VECTOR> [REST FIX]>>` | same `DECL-ELEMENT-NOT-FORM-OR-ATOM` |
| `compound-name-any` | `<DECL? "s" 'ANY>` | `*ERROR* "BAD-TYPE-SPECIFICATION1"` |
| `compound-name-any-in-rest` | `<DECL? (1 2 3) '<LIST [REST ANY]>>` | same `BAD-TYPE-SPECIFICATION1` |
| `compound-name-structured-unquoted` | `<DECL? [1 2] STRUCTURED>` | same `BAD-TYPE-SPECIFICATION1` |
| `cycle-attempt-gloc` | `<SET L '(1 2 3)> <PUT <REST .L 2> 1 <GLOC L>>` | `*ERROR* "UNBOUND-VARIABLE" "In apply of form" GLOC` |

What each shows, and the deviations from the manual grammar:

1. **Non-structured value vs a structured pattern is a `#FALSE ()`, not an
   error.** The clean result is correct per manual `DECL?` semantics
   (section 14.7.4); it is recorded here only because the task asked for the
   observation. Note the bare `#FALSE ()` payload difference from the D1
   `#FALSE (value pattern)` behavior.
2. **Empty structure pattern `<LIST>` is accepted by Confusion but is
   malformed per the manual BNF** (`elts ::= pat | pat elts | ...` requires
   at least one `pat`; the manual prose likewise says patterns correspond
   "one-to-one" with elements, with extras allowed). Confusion reads it,
   matches any LIST, and returns `T`. Recorded as accepted-with-note rather
   than moved to the success file because the manual does not license it.
3. **`[OPT ...]` computes the manual-correct result but pollutes stderr.**
   `[OPT ATOM]` on `()` → `T`, on `(1)` → `#FALSE (1 ATOM)`, and
   `[OPT FIX] [REST FIX]` on `(1 2)` → `T` (the manual-legal
   OPT-then-REST sequence). But every OPT scan prints debug lines `O1` /
   `O2 1` to stderr — leftover `fprintf` probes in the pinned
   `mdl_decl.cpp` (lines 219 and 224). Out of D3 scope; any implementation
   reproducing OPT only needs the observed results, and no probe of `[OPT
   ...]` in this interpreter is "clean".
4. **NTH with a non-positive count is an explicit error:**
   `[0 FIX]` → `*ERROR* "BAD-TYPE-SPECIFICATION4"`. The positive-count NTH
   form itself works (success file).
5. **`<SPECIAL pat>` / `<UNSPECIAL pat>` wrappers are not implemented** in
   `DECL?`: both raise `*ERROR* "DECL-ELEMENT-NOT-FORM-OR-ATOM"`, although
   the manual's top-level `pattern` rule allows them (and the manual's own
   examples use `<UNSPECIAL FIX>` on `#DECL` payloads).
6. **`<<PRIMTYPE LIST> elts>` and `<<OR struc ... struc> elts>` are not
   implemented** (manual rules for `struc`): both raise
   `DECL-ELEMENT-NOT-FORM-OR-ATOM`. Only a bare structured TYPE name
   (LIST/VECTOR/UVECTOR/... per the observed `struc`-as-atom path of
   `mdl_decl.cpp:123-131`) reaches structured checking.
7. **Compound type names `ANY` and `STRUCTURED` are broken in this
   build.** Used directly or inside `[REST ...]`, both reach
   `*ERROR* "BAD-TYPE-SPECIFICATION1"` (the source falls through the
   equality checks against its own root-oblist atoms to the `getprop(...,
   DECL)`-and-fail line, `mdl_decl.cpp:45-69`; `LOCATIVE`/`APPLICABLE` take
   the same path and are expected to fail identically, untested). The D1
   implementation supports `ANY`, so this is another Confusion-vs-manual
   deviation to record, not to copy.
8. **The exact-count SEGMENT pattern `!<struc elts>` is unusable as a
   `DECL?` pattern in this build.** `!<LIST FIX FIX>` splices into
   `DECL?`'s operand list (the SUBR argument-splice path documented in
   `SEGMENTS.md`): both "good" and "extra" probes returned
   `#FALSE ((value) FIX)`, i.e. the LIST value was checked against a bare
   FIX with leftover operands. The manual's `unit ::= !<struc elts>`
   exact-count rule cannot be exercised through `DECL?` in the pinned
   interpreter (out of D3 scope; recorded here for completeness).
9. **A cyclic value was not constructible in the probe form.** Two attempts
   — `<SET L '(1 2 3)> <PUT <REST .L 2> 1 <GLOC L>>` (local `L`) and the
   same with `<SETG L '(1 2 3)>` / `,L` — both failed with
   `*ERROR* "UNBOUND-VARIABLE" "In apply of form" GLOC`, i.e. the pinned
   build does not apply `GLOC` in this form, so no self-referential value
   existed to feed `DECL?`. The pinned source walks structures by
   `NTH`/`REST` from the head (`mdl_decl.cpp:183-210`), which terminates on
   every PUT-mutable value reachable here; this is recorded as *not
   constructed*, not as an observed termination property.

## D3-relevant summary

The reference supports, for the `PSETG` pattern: structured `<TYPE elts>`
patterns with required prefixes, `[REST pat ...]` (last position, zero or
more), nested `<OR ...>` inside REST, across LIST (`()`-literal values),
VECTOR, and UVECTOR values, with `T` on match, `#FALSE (value pattern)` on
element mismatch, and bare `#FALSE ()` on overall-type mismatch. Everything
the manual adds on top of that subset — `<SPECIAL>`/`<UNSPECIAL>` wrappers,
`<PRIMTYPE structured-type>`/`<OR-of-structures> elts`, the compound names
`ANY`/`STRUCTURED`, and empty/`[OPT]` edge cases — is either
unimplemented (`DECL-ELEMENT-NOT-FORM-OR-ATOM`), broken
(`BAD-TYPE-SPECIFICATION1`), or debug-polluted (`O1`/`O2` stderr) in the
pinned build. An implementation following the manual grammar's full
`unit`/`elts` rules supersedes the reference here; per the D1 precedent,
reference success, errors, and this SHA establish the acceptance
observations, while manual semantics win where the reference is incomplete.

## Files created

- `docs/evidence/M2/declaration-pattern-cases.json` (22 clean-exit cases)
- `docs/evidence/M2/declaration-pattern-reference.json` (generated by the
  probe tool, `complete: true`)
- `docs/evidence/M2/declaration-pattern-error-cases.json` (14 deliberate-
  error cases; two of them — the non-structured value and the empty
  structure pattern — turn out to be clean results and are annotated in the
  recorded output)
- `docs/evidence/M2/declaration-pattern-error-reference.json` (generated by
  the probe tool, `complete: false` — by design)
- `docs/evidence/M2/DECLARATION-PATTERNS.md` (this note)

> Superseded by D4 (issue #51, `MUDDLE.md`): the twelve-expression
> progression and the atom-property PUT barrier below the MUDDLE guard
> replace the ten-expression state recorded in this D3-time evidence.

## Implementation record (D3, main-session verification)

Implemented on branch `feat/m2-decl-patterns` (merge of the
`glm-5.3-flash:cloud` implementer subagent's branch
`feat/m2-decl-patterns-impl`, commits `0f87ad9` tests, `6e7abff`
implementation, `a4c3365` cleanup), tracked by
[issue #48](https://github.com/quaat/mdl-racket/issues/48), based on the
review-fixed D2 head.

- **Red:** before the change, `tests/declaration_pattern_test.rkt` fails
  at its first structured case with
  `mdl-decl: DECL?: unsupported declaration pattern LIST`, and the
  pinned load stops at `81prim.mud` expression 3 with
  `DECL 11:9: unsupported declaration pattern LIST`.
- **Green (main session, freshly executed after the merge):** full suite
  785 Racket checks (`tests/declaration_pattern_test.rkt`: 73), loader
  57, historical VFLOAD probe 23 assertions, historical DECL probe 20
  assertions (rewritten for the new progression), Python 13,
  `git diff --check` clean.
- **Load progression:** `81prim.mud` now **loads in full** — all eight
  expressions, `PSETG`'s `<LIST [REST ATOM]>` normalizing at install.
  The pinned `77loadall.mud` chain completes **ten expressions** and
  stops at `77defs.mud` expression 1, `<AND <L? ,MUDDLE 100> ...>`,
  failing on the unassigned global `MUDDLE` (execute stage, construct
  AND) — a non-declaration runtime blocker, the historical
  interpreter-version global, for the next slice.
- **Installed `PSETG` execution:** with the exact pinned bytes
  (SHA-verified by the historical test), invoking `PSETG` with a valid
  ATOM argument advances through its `SETG` (the global is set), the
  `PURE-LIST` initialization, and stops explicitly at
  `<MEMQ .FOO .PL>` with `unassigned or non-applicable MDL operator
  MEMQ` — no MEMQ primitive in this slice, by scope; both the direct
  `81prim` entry (PASS 8/8) and the `77loadall` chain (10 completed)
  are asserted in `tests/historical_decl_test.rkt`.
- **Updated D1/D2 regressions, with reasons:** the D1
  `<LIST FIX>` unsupported-pattern check became an acceptance check
  (structured patterns now normalize; `<SPECIAL FIX>` replaces it as the
  explicit-failure example); the D2 segment-suite PSETG fixture now
  asserts install-PASS and the trimmed body's explicit unassigned-`PL`
  stop instead of the former declaration failure.
- **Architect decisions on the implementer's questions:** (1) `DECL?`
  keeps strict two-operand arity — Confusion's silent surplus-operand
  tolerance is not reproduced (strict-failure discipline); recorded as
  a deviation. (2) The multi-pattern REST partial-period
  `#FALSE (element leaf)` payload is derived from Confusion's REST loop
  (`rest-multi-pattern` pins the accepting case); recorded as derived.
  (3) Structured heads stay restricted to LIST/VECTOR/UVECTOR/TUPLE —
  Confusion accepts any NEWTYPE with structured PRIMTYPE, but no
  historical source needs more yet; `FLAGWORD`'s
  `<TUPLE [REST <OR ATOM FALSE>]>` normalizes and installs under the
  TUPLE support.
- **Not implemented, explicit errors (all test-pinned):** `[OPT ...]`
  (the reference computes correct results but its scan leaks debug
  stderr), NTH repetitions including `[0 FIX]`, `<SPECIAL>`/
  `<UNSPECIAL>`, `!<struc elts>` exact-count segment patterns,
  `<<PRIMTYPE struc> elts>` / `<<OR struc ...> elts>` compositions,
  empty `<struc>` (manual BNF wins over the reference's acceptance),
  NEWTYPE heads with elements, GDECL and global declarations.

## Independent review outcome (PR #50)

A fresh-context review (with direct probes against both this
implementation and the pinned reference for cases the recorded evidence
did not cover) returned REQUEST_CHANGES with three verified divergences
and three polish findings; all were fixed on `feat/m2-decl-patterns`
with regression tests:

1. **P2-1 (fixed):** a UVECTOR bracket (`![REST FIX]`) was silently
   accepted as the repetition construction — the reference errors
   (only MDL_TYPE_VECTOR is a bracket, `mdl_decl.cpp:169`). Brackets now
   require VECTOR kind; a UVECTOR bracket is an explicit error.
   Regressions pin both positions.
2. **P2-2 (fixed):** a failing `<PRIMTYPE ...>` check reported
   `#FALSE (element atom)` where the reference returns its plain FALSE
   (`mdl_decl.cpp:104`) — both as a structured element (including as an
   `<OR>`'s last alternative) and at `DECL?`'s top level (the D1-era
   top-level case had the same divergence, unprobed until the review).
   PRIMTYPE failures now yield the bare `#FALSE ()` record.
3. **P2-3 (fixed):** eager whole-value traversal rejected cyclic values
   even for prefix-only patterns, where the reference walks
   incrementally by NTH/REST and matches the prefix. The required prefix
   is now walked cell by cell in place (nothing duplicated or mutated);
   only the `[REST ...]` tail materializes through the cycle-checked
   conversion, and that explicit cyclic error stays the documented
   safety deviation (the reference's REST loop would hang instead).
4. **P3-4 (fixed):** `<OR ...>` alternatives now consume traversal
   budget, so a pathological nested pattern reports the documented
   limit; a regression drives a 250-deep OR past the 200 budget.
5. **P3-5 (fixed):** a repetition bracket starting with neither a
   keyword nor a FIX count reports its shape ("must start with REST,
   OPT, or a FIX count") instead of a false "unsupported pattern NTH".
6. **P3-6 (fixed):** `decl-match-structure` reindented; the unreachable
   PRIMTYPE/structure branches of `decl-failure-leaf` removed with a
   comment stating which failures carry leaves.

Verified clean by the review: the cyclic REST indexing matches the
reference's per-period restart including the `(B FIX)` partial-period
payload; failure-record propagation through nesting, all pinned
payloads, and the cross-type rejections match the reference by probe;
no hangs on any reachable value/pattern pair; attach integration
(bind/SET/VALUE, compiled and interpreted) matches; the historical
chain assertion reproduces byte-identically; docs and evidence match
the code except where corrected above.

Verification after the fixes (main session, fresh): declaration-pattern
suite 84 checks, full suite green (see commands below), historical
probes pass, `git diff --check` clean; the pinned load still completes
ten expressions with `81prim.mud` in full and stops at the `MUDDLE`
global.
