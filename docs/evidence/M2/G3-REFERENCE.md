# M2 reference investigation — G3 integrated gate (pinned-source single-session behaviors)

Read-only reference probe against the pinned patched Confusion build. No
implementation, test, script, Makefile, or `.cache/upstream/` file was touched;
only the five files listed at the end were created. The goal is to record the
exact original-source behaviors the M2 G3 test will assert after loading the
pinned source files in a single session; each case runs in a fresh Confusion
process (stdin expression + `<QUIT>`, cwd
`.cache/upstream/mdlzork/mdlzork_771212/patched_confusion`).

Interpreter: `.cache/build/confusion_patched/mdli`, SHA-256
`a29c756df5c973e462a6ad2b318e28ec265934e89e72d825bc7672387317e629` — verified
with `sha256sum` before probing; it matches the value recorded in ATOM-PROPS.md
(unchanged from D4/D5).

## Expected semantics (stated before probing)

MSETG and PSETG are source-level `DEFINE`s in 81prim.mud (81prim.mud:2-19): MSETG
does `<SETG .FOO .BAR>` plus `<MANIFEST .FOO>`, but first errors with
`<ERROR MSETG .FOO ALREADY-GASSIGNED ,.FOO>` when the target is GASSIGNED and
the new value `N=?` the old one — so a repeat `<MSETG G X> <MSETG G X>` must
succeed (values are `=`) while a conflicting `<MSETG G 3> <MSETG G 4>` must
raise the ALREADY-GASSIGNED error. PSETG assigns the global, tracks assigned
atoms on the `PURE-LIST` global (creating it with `()` on first use), and is
"COMPLETE" in the sense of returning the assigned value. 77defs.mud attaches
the dungeoneer type declaration `<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>`
(77defs.mud:3) after `<NEWTYPE NOFFSET WORD>` (77defs.mud:2), so
`<GET RAPPLIC DECL>` must return the FORM and
`<DECL? <CHTYPE 1 NOFFSET> RAPPLIC>` must be `T` (per the D4/D5 findings: the
DECL checker follows an atom's DECL association). Global aliasing: SETG of the
same LIST structure under two globals shares the structure in the reference
(one structure object, two GVAL bindings), so a FIX-indicator PUT through one
global must be visible by element selection through the other. `,MUDDLE` is the
interpreter's own GVAL holding the MDL version, expected `101`.

## Commands and exit codes

All from the repository root:

```
PYTHONPATH="$PWD/.sandbox-pydeps/lib" /usr/bin/python3 -m scripts.mdl_probe \
  --cases docs/evidence/M2/g3-integrated-cases.json \
  --output docs/evidence/M2/g3-integrated-reference.json --timeout 300
# exit 1 — NOT clean: the two task-specified 77defs.mud-only cases break during
#   FLOAD (see deviation below), so the probe flags the file complete: false.
#   All other cases are ok: true with process exit 0.
PYTHONPATH="$PWD/.sandbox-pydeps/lib" /usr/bin/python3 -m scripts.mdl_probe \
  --cases docs/evidence/M2/g3-integrated-error-cases.json \
  --output docs/evidence/M2/g3-integrated-error-reference.json --timeout 300
# exit 1 — EXPECTED BY DESIGN (the MSETG ALREADY-GASSIGNED observation is the
#   deliberately non-ok row; per-case process exit code was 0)
```

## Success cases — `g3-integrated-cases.json`, `g3-integrated-reference.json`

Every row below is the verbatim `result_output` of the recorded JSON. 8 of the
10 cases are `ok: true` (clean, empty stderr); the two 77defs.mud-only cases
are recorded verbatim with an in-load error break (see the deviation note).

| Case | Expression | Recorded `result_output` (verbatim) | ok |
|---|---|---|---|
| `g3-msetg-after-fload` | `<FLOAD "81prim.mud"> <MSETG G3-TEMP 3>` | `"DONE"`<br>`T` | true |
| `g3-msetg-repeat` | `<FLOAD "81prim.mud"> <MSETG G3-TEMP 3> <MSETG G3-TEMP 3>` | `"DONE"`<br>`T`<br>`T` | true |
| `g3-psetg-complete` | `<FLOAD "81prim.mud"> <PSETG G3-P 3>` | `"DONE"`<br>`3` | true |
| `g3-psetg-purelist` | `<FLOAD "81prim.mud"> <PSETG G3-P 3> ,PURE-LIST` | `"DONE"`<br>`3`<br>`(G3-P)` | true |
| `g3-rapplic-prop-from-source` | `<FLOAD "77defs.mud"> <GET RAPPLIC DECL>` | ``<br>` *ERROR* ` ` "UNBOUND-VARIABLE" ` ` "In apply of form" ` ` NEWSTRUC ` `LISTENING-AT-LEVEL 2 PROCESS 1`<br>`<OR ATOM FALSE NOFFSET>` | false |
| `g3-declq-rapplic-hit` | `<FLOAD "77defs.mud"> <DECL? <CHTYPE 1 NOFFSET> RAPPLIC>` | ` *ERROR* "UNBOUND-VARIABLE" "In apply of form" NEWSTRUC`, `LISTENING-AT-LEVEL 2 PROCESS 1`<br>`T` | false |
| `g3-rapplic-prop-both-files` | `<FLOAD "81prim.mud"> <FLOAD "77defs.mud"> <GET RAPPLIC DECL>` | `"DONE"`<br>`"DONE"`<br>`<OR ATOM FALSE NOFFSET>` | true |
| `g3-declq-rapplic-hit-both-files` | `<FLOAD "81prim.mud"> <FLOAD "77defs.mud"> <DECL? <CHTYPE 1 NOFFSET> RAPPLIC>` | `"DONE"`<br>`"DONE"`<br>`T` | true |
| `g3-global-alias-put` | `<SETG G3-L (1 2 3)> <SETG G3-M ,G3-L> <PUT ,G3-L 1 99> <1 ,G3-M>` | `(1 2 3)`<br>`(1 2 3)`<br>`(99 2 3)`<br>`99` | true |
| `g3-muddle-value` | `,MUDDLE` | `101` | true |

What each shows:

- **MSETG after FLOAD prints `"DONE"` (the FLOAD) then `T`.** The value `T` is
  MSETG's return: its ELSE branch evaluates `<MANIFEST .FOO>` (81prim.mud:8),
  whose value prints `T`. Confirmed again in `g3-msetg-repeat`: the second
  `<MSETG G3-TEMP 3>` with the same value is not an error (the guard is
  `<AND <GASSIGNED? .FOO> <N=? .BAR ,.FOO>>`, 81prim.mud:4) and returns `T`
  again. So the G3 assertions would be: FLOAD echoes `"DONE"`, MSETG returns
  `T`, and a same-value repeat is legal.
- **PSETG returns the assigned value**: `"DONE"` then `3`.
- **PURE-LIST is exactly `(G3-P)`.** No atoms pre-existed from the source
  load itself: 81prim.mud only *defines* MSETG/PSETG/NEWSTRUC/FLAGWORD, it
  does not call PSETG anywhere, so the first PSETG call creates `PURE-LIST`
  with `()` (81prim.mud:14) and then conses the atom onto it. The recorded
  output is verbatim `(G3-P)` — nothing had to be forced or trimmed.
- **The RAPPLIC DECL property does come from source: `<GET RAPPLIC DECL>`
  prints `<OR ATOM FALSE NOFFSET>`** — but the two task-specified
  `77defs.mud`-only cases hit an in-load error first (see Deviations).
- **With the canonical dependency order (81prim first), both are flawless:**
  `g3-rapplic-prop-both-files` prints two `"DONE"` lines then the FORM
  `<OR ATOM FALSE NOFFSET>`; `g3-declq-rapplic-hit-both-files` prints `T`,
  so `<DECL? <CHTYPE 1 NOFFSET> RAPPLIC>` is `T` with the source PUT — the
  exact declaration-consultation behavior recorded per-expression in D4/D5,
  now reproduced by loading the original file's own PUT line. These two
  both-files cases are the clean single-session reference observations for
  the G3 gate.
- **Global aliasing through `<PUT ... 1 99>` is structural:** after
  `<SETG G3-L (1 2 3)> <SETG G3-M ,G3-L>`, evaluating `,G3-L` and `,G3-M`
  prints `(1 2 3)` then `(1 2 3)`; after `<PUT ,G3-L 1 99>` the shared
  structure is `(99 2 3)` (observed on the subsequent `<1 ,G3-M>` → `99`),
  i.e. PUT through the FIX indicator mutates the LIST in place, visible
  through the second GVAL.
- **`,MUDDLE` reads `101` with no source file loaded.**

## Deliberate-error case — `g3-integrated-error-cases.json`, `g3-integrated-error-reference.json` (probe exit 1, expected by design)

Per-case process exit code was 0; the probe flags the non-ok row, which is the
deliberate-error design (same convention as ATOM-PROPS.md).

| Case | Expression | Recorded `result_output` (verbatim) |
|---|---|---|
| `g3-msetg-conflict` | `<FLOAD "81prim.mud"> <MSETG G3-T2 3> <MSETG G3-T2 4>` | `"DONE"`<br>`T`<br>``<br>` *ERROR* `<br>` MSETG `<br>` G3-T2 `<br>` ALREADY-GASSIGNED `<br>` 3 `<br>`LISTENING-AT-LEVEL 2 PROCESS 1` |

- **The MSETG ALREADY-GASSIGNED error is exactly as the source constructs it**
  (81prim.mud:5): the `*ERROR*` break names `MSETG`, the atom `G3-T2`,
  `ALREADY-GASSIGNED`, and the *old value* `3`, breaking to
  `LISTENING-AT-LEVEL 2 PROCESS 1`. stderr contains
  `Atom REP has neither LVAL nor GVAL` in the saved probe; the first (legal) MSETG
  of `3` returned `T` before the conflicting `4` broke. This is the reference's
  repeat-assignment error for G3: a *different* value on an already-gassigned
  MSETG target is a hard error.

## Deviations from the task's expectations

1. **`<FLOAD "77defs.mud">` alone does not complete in the reference.** Both
   task cases 5 and 6 break during the load with
   `*ERROR* "UNBOUND-VARIABLE" "In apply of form" NEWSTRUC`, because
   `NEWSTRUC` is *defined in 81prim.mud* (81prim.mud:35) and 77defs.mud calls
   it (77defs.mud:37 onward, first at line 37) — a genuine source dependency,
   consistent with the canonical load order in `77loadall.mud`, which FLOADs
   `81prim.mud` before `77defs.mud`. Only the first three expressions of
   77defs.mud execute (the comment line, `<NEWTYPE NOFFSET WORD>` at line 2,
   `<PUT RAPPLIC DECL ...>` at line 3) before line 37's NEWSTRUC call breaks.
   The expected values are nevertheless observable because the remaining stdin
   lines (`<GET RAPPLIC DECL>` / `<DECL? ...>`) are evaluated inside the
   level-2 listening break loop and print `<OR ATOM FALSE NOFFSET>` and `T`
   respectively — so the reference *does* show the G3-relevant semantics from
   source, but not as a clean `"DONE"` load; the probe flags those two rows.
   The clean single-session observations are the added
   `g3-rapplic-prop-both-files` / `g3-declq-rapplic-hit-both-files` cases,
   which load 81prim first and are `ok: true`. Any G3 test that loads 77defs
   in a session must load 81prim first to match the reference's dependency
   order (77loadall.mud is the authority).
2. **Output ordering inside flagged cases:** the captured stdout shows the
   `*ERROR*` block before the later-printed value (the listening-loop
   evaluation's echo). Nothing was edited or reordered in the recordings.
3. **`g3-psetg-purelist` matches the task's simple expectation** — `PURE-LIST`
   contained no atoms from the file load itself (81prim.mud defines PSETG but
   never calls it), so `,PURE-LIST` printed exactly `(G3-P)` with no
   intervention needed.
4. All other expectations held exactly: MSETG returns `T` (the MANIFEST value)
   — not the assigned value; repeat MSETG with the *same* value is legal;
   PSETG returns the assigned value `3`; aliasing PUT is visible across both
   globals (`(99 2 3)` / `99`); `,MUDDLE` is `101`; the MSETG conflict error
   message carries the atom, `ALREADY-GASSIGNED`, and the old value.

## Files created

- `docs/evidence/M2/g3-integrated-cases.json` (10 cases: 8 task cases plus the
  two both-files supplemental cases)
- `docs/evidence/M2/g3-integrated-reference.json` (generated by the probe tool,
  `complete: false` — the two 77defs-only rows break during FLOAD, by reference
  behavior rather than probe error)
- `docs/evidence/M2/g3-integrated-error-cases.json` (1 deliberate-error case)
- `docs/evidence/M2/g3-integrated-error-reference.json` (generated by the probe
  tool, `complete: false` — by design)
- `docs/evidence/M2/G3-REFERENCE.md` (this note)

## Continuation on 2026-11-20

The earlier binary hash above identifies the first capture, not the later
rebuild. The rebuilt pinned Confusion binary had SHA-256
`987471cf0e568ad7f83a10b893484cd3fa99a86a69444c3b7d5554b16829f475`.
The eight clean cases were separated into `g3-integrated-clean-cases.json`
without altering the original ten-case investigation. Running the probe on
that clean set exited 0; all eight cases matched the saved result in name,
expression, input, exit status, result output, stderr, and `ok`. Repeating
the deliberate MSETG conflict probe exited 1 as designed and matched those
same fields, including its nonempty stderr. The original-source TRNN macro
expansion was recorded separately in `g3-macro-{cases,reference}.json`:
`<EXPAND '<TRNN OBJ 2>>` after loading 81prim then 77defs yielded
`<N==? <CHTYPE <ANDB 2 <OFLAGS OBJ>> FIX> 0>` with empty stderr and exit 0.
The pre-merge G3 gate decision and command matrix are in `G3-GATE.md`.
