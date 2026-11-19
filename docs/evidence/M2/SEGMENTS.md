# M2 reference investigation — SEGMENT (`!` splice) evaluation (issue #46)

Read-only reference probe against the pinned patched Confusion build. No
implementation, test, script, or Makefile file was touched; only the four
files referenced below were created. Interpreter:
`.cache/build/confusion_patched/mdli`, SHA-256
`a29c756df5c973e462a6ad2b318e28ec265934e89e72d825bc7672387317e629`
(matching the declaration-slice reference file).

## Expected semantics (from the historical manual, ch. 7, as quoted in the task)

`!` before an object marks it as a SEGMENT, evaluated even where ordinary
elements would not be: `!.ATOM` denotes a segment of `<LVAL ATOM>`, `!,ATOM`
a segment of `<GVAL ATOM>`, and `!<FORM...!>` a segment of the FORM's value,
with the trailing `!` optional on input. SEGMENTs are evaluated while a
structure is being built; what is inserted are the *elements* of the
segment's value, which had better be a structured object. Segments splice
into LISTs, VECTORs, and FORM argument lists (`<+ !.A 5>` with
`<SET A '![1 2 3 4]>` gives `15`). A LIST-valued segment in the final
position of a LIST is not copied — it shares its tail, so `PUT` mutation is
visible through both structures; non-final LIST segments and VECTOR
constructions copy. Strings splice as their characters. A SEGMENT must be
evaluated inside the EVAL of a structure.

## Commands and exit codes

All from the repository root:

```
PYTHONPATH="$PWD/.sandbox-pydeps/lib" /usr/bin/python3 -m scripts.mdl_probe \
  --cases docs/evidence/M2/segment-cases.json \
  --output docs/evidence/M2/segment-reference.json
# exit 0 — "Probed 18 expressions; review: docs/evidence/M2/segment-reference.json"
PYTHONPATH="$PWD/.sandbox-pydeps/lib" /usr/bin/python3 -m scripts.mdl_probe \
  --cases docs/evidence/M2/segment-error-cases.json \
  --output docs/evidence/M2/segment-error-reference.json
# exit 1 — EXPECTED BY DESIGN (deliberately failing observations recorded)
```

Each case runs in a fresh Confusion process (stdin expression + `<QUIT>`,
cwd `.cache/upstream/mdlzork/mdlzork_771212/patched_confusion`). Every output
below is quoted from the recorded JSON files. `result_output` shows the value
printed for each top-level form in sequence (the probe feeds several forms on
one line); the last line is the probe expression's result.

## Success cases (18/18 clean exits) — `segment-cases.json`, `segment-reference.json`

| Case | Expression | Recorded result |
|---|---|---|
| `list-splice-lval` | `<SET ARF '(B 3 4)> <SET ZOP '![2 3 4]> (.ARF !.ZOP)` | `(B 3 4)`, `![2 3 4!]`, `((B 3 4) 2 3 4)` |
| `manual-unquoted-arf` | `<SET ARF (B 3 4)> <SET ZOP '![2 3 4]> (.ARF !.ZOP)` | same, `((B 3 4) 2 3 4)`; empty stderr |
| `gval-splice` | `<SETG GSEG '![7 8 9]> (!,GSEG)` | `![7 8 9!]`, `(7 8 9)` |
| `form-segment-explicit-bang` | `<SET ARF '(B 3 4)> (!<REST .ARF!>)` | `(B 3 4)`, `(3 4)` |
| `form-segment-implicit-bang` | `<SET ARF '(B 3 4)> (!<REST .ARF>)` | `(B 3 4)`, `(3 4)` |
| `subr-arg-splice` | `<SET A '![1 2 3 4]> <+ !.A 5>` | `![1 2 3 4!]`, `15` |
| `vector-splice` | `<SET ZOP '![2 3 4]> [1 !.ZOP]` | `![2 3 4!]`, `[1 2 3 4]` |
| `vector-nested-segments` | `... [1 !.ZOP !<REST .ARF>]` | `[1 2 3 4 3 4]` |
| `uvector-uniform-splice` | `... ![!.ZOP !<REST .ARF>!]` | `![2 3 4 3 4!]` |
| `splice-order-side-effects` | `<DEFINE F (I) <PRINT .I> ![.I]> (1 !<F 10> 20 !<F 30>)` | see below |
| `list-tail-sharing-final` | `... <SET DOG (1 2 !.ARF)> <PUT .ARF 1 "BOWOW"> (.ARF .DOG)` | see below |
| `nonfinal-segment-copies` | `... <SET CAT (1 !.ARF 2)> <PUT .ARF 1 "BOWOW"> (.ARF .CAT)` | see below |
| `empty-segment-quoted` | `(1 !'() 2)` | `(1 2)` |
| `empty-segment-lval` | `<SET E '()> (1 !.E 2)` | `()`, `(1 2)` |
| `string-splice` | `<SET S "STRUNG."> (!.S)` | `"STRUNG."`, `(!\S !\T !\R !\U !\N !\G !\.)` |
| `quoted-segment-unevaluated` | `... '(1 !.X !.A)` | `(1 !.X !.A)` |
| `quoted-segment-prog` | `... '<PROG () !.X>` | `<PROG () !.X>` |
| `nested-segments-list` | `(!.ZOP !<REST .ARF>)` | `(2 3 4 3 4)` |

What each shows:

- **LIST splice and manual setup.** `(.ARF !.ZOP)` inserts the elements of
  `.ZOP`'s value after `.ARF`'s value: `((B 3 4) 2 3 4)`, exactly the manual
  example. Notably the manual's unquoted setup works verbatim:
  `<SET ARF (B 3 4)>` evaluated the unbound atom `B` to the atom `B`
  (result `(B 3 4)`, empty stderr) rather than raising an unbound error.
  `'![2 3 4]` evaluates to an object that prints `![2 3 4!]` (see the
  UVECTOR syntax note below — bang-brackets are a structure type in this
  build, printing with a trailing `!`).
- **`!,ATOM`.** `(!,GSEG)` gives `(7 8 9)`; elements (not the UVECTOR) are
  inserted.
- **Explicit vs implicit trailing `!`.** Both `(!<REST .ARF!>)` and
  `(!<REST .ARF>)` give `(3 4)`. The reader's explicit close is `!>`
  (`mdl_read.cpp:106`), and `>` alone also closes a SEGMENT
  (`mdl_read.cpp:663-668`), so the manual's "trailing `!` is optional" holds
  only when the `!` sits immediately before the closing bracket.
- **FORM argument splice.** `<+ !.A 5>` → `15`: the four elements splice into
  the SUBR call's operand list and are not re-evaluated as a nested
  structure.
- **VECTOR splice.** Plain `[...]` is a VECTOR in this build (`[1 !.ZOP]` →
  `[1 2 3 4]`); segment elements splice inside it
  (`vector-nested-segments` → `[1 2 3 4 3 4]`).
- **UVECTOR construction with segments.** `![!.ZOP !<REST .ARF>!]` builds a
  uniform-FIX UVECTOR, printed `![2 3 4 3 4!]`. In pinned Confusion
  `![`/`!]` open/close a UVECTOR and `![...]` also closes it with plain
  `]` (`mdl_read.cpp:99-106`, `:670-675`; printed form at
  `mdl_output.cpp:863,893`). Uniformity is enforced (see error case).
- **Evaluation order.** `<DEFINE F (I) <PRINT .I> ![.I]>` then
  `(1 !<F 10> 20 !<F 30>)` recorded `F\n\n10 \n30 (1 10 20 30)\n`: both
  PRINT side effects appear before the result, in left-to-right segment
  order; the segment of `![.I]` itself splices `[10]`'s element into the
  built LIST. (`F` and the blank line are Confusion's DEFINE/value echo.)
- **Final-position LIST tail sharing — YES, observable via PUT.**
  `<SET ARF '(B 3 4)> <SET DOG (1 2 !.ARF)> <PUT .ARF 1 "BOWOW">` recorded
  `("BOWOW" 3 4)` for `.ARF` and `(("BOWOW" 3 4) (1 2 "BOWOW" 3 4))` for the
  probe: the `PUT` through `.ARF` is visible through `.DOG`. Confusion
  implements this by linking the tail cells directly
  (`macros.cpp:2713-2724`, `result = seg->v.p.cdr`). The `PUT` inserted the
  STRING `"BOWOW"` (printed with quotes), while the untouched atom `B`
  printed without quotes in the pre-mutation echo `(1 2 B 3 4)`.
- **Non-final LIST segments copy.** Same mutation with
  `<SET CAT (1 !.ARF 2)>` recorded `(("BOWOW" 3 4) (1 B 3 4 2))`: `CAT`
  still shows the original `B`.
- **Empty segments.** Splicing `!'()` and a `()`-valued LVAL both leave
  `(1 2)` — nothing inserted, no error.
- **String splice.** `(!.S)` with `"STRUNG."` gives a seven-element LIST of
  CHARACTERs printed with a `!\` prefix (`!\S !\T !\R !\U !\N !\G !\.`).
- **Quoted structures keep segments unevaluated.** `'(1 !.X !.A)` prints
  back as `(1 !.X !.A)` and `'<PROG () !.X>` as `<PROG () !.X>`; the SEGMENT
  printer renders `!.ATOM` segments canonically (`mdl_output.cpp:780-799`).

## Deliberate-error cases — `segment-error-cases.json`, `segment-error-reference.json` (probe exit 1, expected)

All errors below are MDL-level `*ERROR*` breaks entering
`LISTENING-AT-LEVEL 2` with empty process exit code. One incidental artifact:
every recorded break-level case also writes
`Atom REP has neither LVAL nor GVAL` to stderr — a pre-existing Confusion
error-handler behavior (also present in `decl-error-reference.json`), not a
segment diagnostic except where noted.

| Case | Expression | Recorded diagnostic |
|---|---|---|
| `standalone-segment-form` | `!<SET B 2>` | `*ERROR* "ILLEGAL-SEGMENT" "Attempt to evaluate segment outside structured type"` |
| `standalone-segment-lval` | `!.ZOP` | same `ILLEGAL-SEGMENT` diagnostic |
| `segment-non-structured-value` | `<SET X 5> (!.X)` | `*ERROR* "ILLEGAL-SEGMENT" "Segment evaluated to nonstructured type" !.X` |
| `segment-atom-value` | `<SET A 'FOO> (!.A)` | same, offending `!.A` shown |
| `uvector-non-uniform` | `![1 !.X "s"!]` | `*ERROR* "TYPES-DIFFER-IN-UNIFORM-VECTOR"` |
| `uvector-pound-shorthand` | `#[1 !.X]` | stderr `ATOM with null PNAME not permitted` (reader), then break level; after the break the remaining input re-read as an ordinary VECTOR and printed `[1 2 3]` |
| `uvector-named-typecode` | `#UVECTOR [1 !.X]` | **interpreter crash: SIGSEGV, exit code -11**, only `![2 3!]` printed, no error marker |
| `segment-trailing-bang-in-list` | `(!<REST .ARF>!)` | stderr `Error: Unexpected EOF` (reader) |
| `segment-trailing-bang-end` | `!<SET B 2>!` | `ILLEGAL-SEGMENT` (as standalone), then the leftover `!` re-read at the break level printed `\!` and the REP diagnostic twice |
| `malformed-bang-in-list` | `(!)` | stderr `Error: Unexpected EOF` (reader) |

- **Standalone segments error, as the manual requires.** Both `!<SET B 2>`
  and `!.ZOP` at top level fail with `ILLEGAL-SEGMENT` /
  "Attempt to evaluate segment outside structured type"
  (`macros.cpp:2753-2755`); segments only evaluate inside structure-building
  EVAL.
- **Non-structured and atom segment values error.** `(!.X)` with 5 and
  `(!.A)` with atom `FOO` fail with `ILLEGAL-SEGMENT` /
  "Segment evaluated to nonstructured type"
  (`macros.cpp:2709-2711`); atoms are non-structured for this purpose.
- **UVECTOR uniformity is enforced** at splice/construction time with
  `TYPES-DIFFER-IN-UNIFORM-VECTOR`.
- **`#[...]` is not UVECTOR syntax in this build.** The reader treats `#` as
  a typed-object prefix requiring an atom name after it; `#[` produces
  "ATOM with null PNAME not permitted".
- **`#UVECTOR [...]` crashes the pinned interpreter** (`SIGSEGV`, exit -11,
  no error output beyond the earlier form's echo). This is a genuine defect
  of the pinned build, observable only with `#`-prefixed type syntax;
  reproduce with the recorded expression.
- **Trailing `!` outside the brackets is not segment syntax.** In
  `(!<REST .ARF>!)` the `>` already closed the segment and the dangling `!`
  caused `Error: Unexpected EOF`. In `!<SET B 2>!` the segment still read as
  `!<SET B 2>` and the leftover `!` was re-read at the error break — the
  literal task form is not rejected cleanly but surfaces as the standalone
  error plus stray output.

## Deviations and gaps vs the manual rules quoted in the task

1. **Trailing `!` ("optional on input"):** holds only with the `!`
   immediately before the closing bracket (`!<...!>` ≡ `!<...>`). A `!`
   written after the closing bracket (the notation variant attempted first,
   `!>!`-style) is not consumed as segment syntax: it yields
   `Unexpected EOF` or stray break-level output, not a segment.
2. **`![...]!` notation:** pinned Confusion's reader implements
   `![`/`!]` (and `![...]`) as the UVECTOR delimiters and the printer echoes
   UVECTORs as `![...!]`. The task's manual quotes cover SEGMENT semantics
   only and do not state the UVECTOR input syntax, so this could not be set
   against the manual page (the fetch was not permitted in this session);
   it is recorded from observed output and the pinned reader source.
   Implementers must not read `![2 3 4]` as a SEGMENT.
3. **`#[...]`/`#UVECTOR [...]`:** rejected as UVECTOR input; the latter
   segfaults the interpreter.
4. **Unbound atom evaluation:** evaluating the manual's unquoted setup
   `<SET ARF (B 3 4)>` bound `ARF` to `(B 3 4)` without error — the unbound
   atom evaluated to itself. Recorded as an observed behavior relevant to
   reproducing the manual example; not verified against the manual's
   unbound-variable rule in this session.
5. All core SEGMENT rules checked match the manual: LVAL/GVAL/FORM segment
   syntax, element insertion, FORM-argument splicing, final-position LIST
   tail sharing (visible via `PUT`), non-final copying, string
   character-splicing, quoted structures keeping segments unevaluated, and
   the two error conditions.

## Files created

- `docs/evidence/M2/segment-cases.json` (18 clean-exit cases)
- `docs/evidence/M2/segment-reference.json` (generated by the probe tool,
  `complete: true`)
- `docs/evidence/M2/segment-error-cases.json` (10 deliberate-error cases)
- `docs/evidence/M2/segment-error-reference.json` (generated by the probe
  tool, `complete: false` — by design)
- `docs/evidence/M2/SEGMENTS.md` (this note)

## Implementation record (D2, main-session verification)

Implemented on branch `feat/m2-segment` (merge `b0af6b8` of the
`glm-5.3-flash:cloud` implementer subagent's branch `feat/m2-segment-impl`,
commits `81d8286` tests-then `006674d` implementation), tracked by
[issue #46](https://github.com/quaat/mdl-racket/issues/46).

- **Red:** before the change, the pinned load failed at compile stage,
  `81prim.mud` expression 3, `unsupported MDL construct splice` (16:46) —
  independently observed live in the main session and recorded in
  `artifacts/m2/source-load.json` on the pre-merge branch; the new
  `tests/segment_test.rkt` against the pre-change modules aborts with
  unbound segment machinery (`mdl-array?` etc.) and cannot read
  `!<FORM...!>`.
- **Green (main session, freshly executed on merge `b0af6b8`):**
  `raco test tests/segment_test.rkt` 75 checks; `bash scripts/test_racket.sh`
  701 checks; `raco test tests/loader_test.rkt` 57; historical VFLOAD probe
  23 assertions; historical DECL probe 14 assertions (now asserting the new
  barrier below); `git diff --check` clean. Stale `compiled/` bytecode
  under gitignored directories was cleared once after the runtime's module
  interface changed (recorded in `docs/TESTING.md`).
- **Load progression:** `racket scripts/mdl_load.rkt --source-root
  .cache/upstream/mdlzork/mdlzork_771212/patched_confusion --entry
  77loadall.mud --report artifacts/m2/source-load.json` exits 1 with
  **3 completed expressions**; the failure moved past the splice compile
  barrier to the *runtime* stage, `mdl-decl: DECL 11:9: unsupported
  declaration pattern LIST` — `PSETG`'s compound `<LIST [REST ATOM]>`
  pattern, the D3 slice ([issue #48](https://github.com/quaat/mdl-racket/issues/48)).
  `MSETG` (D1 acceptance) still installs and executes.
- **Deviations decided by the main agent** (rationale in
  `docs/SEMANTICS.md`, M2 D2 section): interpreted call arguments splice
  segments (the pinned reference's interpreted path does not; its SUBR path
  does — the manual's general rule and compiled/interpreted agreement win);
  interpreted call assembly evaluates segment payloads eagerly before plain
  formals (unobserved in any reference case, not exercised by the sources).
- **Not implemented, explicit failures or out of scope:** `#[...]` and
  `#UVECTOR [...]` input syntaxes (the latter segfaults the pinned
  reference; not reproduced); `!` followed by a bare atom (the historical
  reader makes it part of an atom name; ours rejects the splice); compiled
  standalone `!X` (explicit compile error; the interpreted path reproduces
  the reference's `ILLEGAL-SEGMENT` message); GDECL and global declarations.
