# M2 reference investigation — atom properties (GET/PUT associations, issue #53, D5)

Read-only reference probe against the pinned patched Confusion build. No
implementation, test, script, Makefile, or `.cache/upstream/` file was touched;
only the five files listed at the end were created. Interpreter:
`.cache/build/confusion_patched/mdli`, SHA-256
`a29c756df5c973e462a6ad2b318e28ec265934e89e72d825bc7672387317e629`
(unchanged from the D4 note). The manual chapter
(https://mdl-language.readthedocs.io/en/latest/13-association-properties/) was
fetched successfully this session; all rules quoted below are from it.

## Expected semantics (from the manual, chapter 13)

Association storage pairs an arbitrary *item* with an arbitrary *indicator*
and a value. `<PUTPROP item indicator value>` returns item, having associated
value with item under indicator. `<PUT item indicator value>` is identical to
PUTPROP except that, when item is structured and indicator is of TYPE FIX or
OFFSET, it instead does `<SETLOC <AT item indicator> value>` — an integral
selector stores in the structure itself; otherwise it goes to association
space. PUT (like AT) errors when the indicator is out of range; PUTPROP does
not. Two-argument PUT/PUTPROP *removes* the association, returning the old
value or `#FALSE ()` if none existed. Retrieval: `<GETPROP item indicator exp>`
returns the associated value, EVAL of exp on miss (exp optional), or
`#FALSE ()`; `<GET item indicator exp>` is the inverse of PUT, using NTH
(structured item, FIX/GET indicator) or GETPROP. Note the manual's warning:
item and indicator must be `==?` to the objects used to establish the
association — READ-generated structures do not match (its `<GET .N '(1 2 3 4)>`
example misses). Chapter 13.4 additionally has ASSOCIATIONS, NEXT, ITEM,
INDICATOR, AVALUE over a doubly-linked association chain that prints
`#ASOC (item indicator value)` (newest first). The dungeoneer mechanism of
77defs expression 3, `<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>`, is the
property form of `<PUT atom indicator value>` (atom ⇒ non-structured ⇒
association), attaching a type declaration to a NEWTYPE name atom without
assigning it (recorded in D4).

## Commands and exit codes

All from the repository root:

```
PYTHONPATH="$PWD/.sandbox-pydeps/lib" /usr/bin/python3 -m scripts.mdl_probe \
  --cases docs/evidence/M2/atom-props-cases.json \
  --output docs/evidence/M2/atom-props-reference.json --timeout 300
# exit 0 — "Probed 18 expressions; review: docs/evidence/M2/atom-props-reference.json"
PYTHONPATH="$PWD/.sandbox-pydeps/lib" /usr/bin/python3 -m scripts.mdl_probe \
  --cases docs/evidence/M2/atom-props-error-cases.json \
  --output docs/evidence/M2/atom-props-error-reference.json --timeout 300
# exit 1 — EXPECTED BY DESIGN (deliberate-error observations recorded)
```

Each case runs in a fresh Confusion process (stdin expression + `<QUIT>`, cwd
`.cache/upstream/mdlzork/mdlzork_771212/patched_confusion`). Every output below
is quoted from the recorded `result_output` of the JSON files.

## Success cases (18/18 clean exits) — `atom-props-cases.json`, `atom-props-reference.json`

| Case | Expression | Recorded result |
|---|---|---|
| `defs-line3-put-decl` | `<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>` | `RAPPLIC`, empty stderr |
| `get-decl-after-put` | same PUT, then `<GET RAPPLIC DECL>` and `<TYPE <GET RAPPLIC DECL>>` | `RAPPLIC`, `<OR ATOM FALSE NOFFSET>`, `FORM` |
| `getprop-subr-retrieval` | `<PUT RAPPLIC P V> <GETPROP RAPPLIC P> <TYPE <GETPROP RAPPLIC P>>` | `RAPPLIC`, `V`, `ATOM` |
| `putprop-subr-computed-value` | `<PUTPROP RAPPLIC P <+ 1 2>> <GET RAPPLIC P> <TYPE <GET RAPPLIC P>>` | `RAPPLIC`, `3`, `FIX` |
| `get-exp-fallback` | `<PUT RAPPLIC P V> <GET RAPPLIC P 'FALLBACK> <GET RAPPLIC Q 'FALLBACK>` | `RAPPLIC`, `V`, `FALLBACK` |
| `rapplic-still-unassigned` | `<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>> <GASSIGNED? RAPPLIC>` | `RAPPLIC`, `#FALSE ()` |
| `second-property-independence` | `<PUT RAPPLIC OTHER 5> <PUT RAPPLIC DECL 'FIX> <GET RAPPLIC OTHER> <GET RAPPLIC DECL>` | `RAPPLIC`, `RAPPLIC`, `5`, `FIX` |
| `overwrite-latest-wins` | `<PUT W W 1> <PUT W W 2> <GET W W>` | `W`, `W`, `2` |
| `list-value-preserved` | `<PUT RAPPLIC L '(1 2 3)> <GET RAPPLIC L> <TYPE <GET RAPPLIC L>>` | `RAPPLIC`, `(1 2 3)`, `LIST` |
| `atom-echo-no-property-markup` | `<PUT RAPPLIC DECL 'FIX> RAPPLIC 'RAPPLIC` | `RAPPLIC`, `RAPPLIC`, `RAPPLIC` |
| `type-primtype-after-put` | `<PUT RAPPLIC DECL 'FIX> <TYPE RAPPLIC> <PRIMTYPE RAPPLIC>` | `RAPPLIC`, `ATOM`, `ATOM` |
| `declq-consults-atom-decl` | `<NEWTYPE NOFFSET WORD> <PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>> <DECL? <CHTYPE 1 NOFFSET> RAPPLIC> <DECL? 3 RAPPLIC>` | `NOFFSET`, `RAPPLIC`, `T`, `#FALSE (3 NOFFSET)` |
| `setg-ignores-atom-decl` | `<PUT SOMETHING DECL 'FIX> <SETG SOMETHING "str"> ,SOMETHING <GASSIGNED? SOMETHING>` | `SOMETHING`, `"str"`, `"str"`, `T` |
| `get-missing-property-false` | `<GET FOO MISSING-PROP>` | `#FALSE ()` |
| `fix-item-association` | `<PUT 5 DECL 'FIX> <GET 5 DECL> <TYPE <GET 5 DECL>>` | `5`, `FIX`, `ATOM` |
| `association-remove-two-arg-put` | `<PUT RAPPLIC P V> <PUT RAPPLIC P> <GET RAPPLIC P>` | `RAPPLIC`, `RAPPLIC`, `#FALSE ()` |
| `identity-keyed-retrieval` | `<SET L (1 2 3)> <PUT .L FOO VAL> <GET .L FOO> <GET (1 2 3) FOO>` | `(1 2 3)`, `(1 2 3)`, `VAL`, `#FALSE ()` |
| `string-item-identity-miss` | `<PUT "abc" P X> <GET "abc" P>` | `"abc"`, `#FALSE ()` |

What each shows:

- **The exact 77defs expression 3 blocker succeeds on the unassigned atom**
  and returns the item: `RAPPLIC` echoed, empty stderr (same fresh-process
  result as D4). GET then returns the stored FORM and `<TYPE ...>` of it is
  `FORM` — the `'<OR ATOM FALSE NOFFSET>` reader-quote stored its FORM value
  intact, printing `<OR ATOM FALSE NOFFSET>`.
- **PUTPROP exists and shares the table.** `<PUT RAPPLIC P V>` then
  `<GETPROP RAPPLIC P>` retrieves the atom `V` (`TYPE` `ATOM`);
  `<PUTPROP RAPPLIC P <+ 1 2>>` stores the computed `FIX 3`; GET (the PUT-style
  SUBR) sees both. PUT and PUTPROP evaluate their arguments normally
  (verified separately: `<PUT RAPPLIC P <QUOTE V2>>` and
  `<PUTPROP RAPPLIC P <QUOTE V2>>` both store the atom `V2`; `<PUT RAPPLIC P
  <+ 1 2>>` stores `3`). Note during probing: `(QUOTE V2)` *with parentheses*
  is a LIST literal in MDL, so a value argument written that way stores the
  two-element LIST and prints `(QUOTE V2)` — reader syntax, not an
  association defect; do not read that output as an unevaluated-argument bug.
- **GET's optional third argument works on the association path:**
  present property → `V` (exp not evaluated as the result), missing indicator
  `Q` → `FALLBACK`. A missing property with no exp returns `#FALSE ()`
  (`get-missing-property-false`) — so the task's suggested error case
  "GET on an unset property" is **not** an error in the reference; it is
  exactly the manual's documented `#FALSE ()` miss.
- **Properties live with the atom, are independent per indicator, overwrite
  replaces, and the atom stays unassigned and unchanged.**
  `second-property-independence` retrieves `5` (OTHER) and `FIX` (DECL)
  independently; `overwrite-latest-wins` retrieves `2`; after all PUTs
  `<GASSIGNED? RAPPLIC>` is still `#FALSE ()` and bare evaluation of an
  unbound atom returns the atom itself (recorded here, consistent with
  SEGMENTS.md's unbound-atom observation), while a `,RAPPLIC` GVAL read
  still breaks UNBOUND-VARIABLE (error file) — the DECL property attaches
  nothing to GVAL. Two-argument PUT removes the association
  (`association-remove-two-arg-put` → `#FALSE ()`, the manual's 13.1.3).
- **Complex values round-trip:** a LIST value is retrieved intact,
  `(1 2 3)` with TYPE `LIST`.
- **The printer shows no properties.** Bare `RAPPLIC`, the PUT echo, and
  `'<RAPPLIC>`-style `RAPPLIC` all print the plain atom name with no
  annotation of its DECL property. No `#ASOC (...)` form ever appears —
  associations have no printed representation in this build.
- **TYPE/PRIMTYPE of a property-carrying atom stay ATOM/ATOM** after the
  property PUT.
- **The atom's DECL property is consulted by the DECL engine.**
  `declq-consults-atom-decl`: after `<PUT RAPPLIC DECL '<OR ATOM FALSE
  NOFFSET>>`, `<DECL? <CHTYPE 1 NOFFSET> RAPPLIC>` is `T` and
  `<DECL? 3 RAPPLIC>` is `#FALSE (3 NOFFSET)` — a FALSE-typed value that
  embeds the offending value and the unmatched type rather than the manual's
  plain `#FALSE ()` (the pinned source marks this "FIXME: no fancy falses",
  `mdl_decl.cpp:63-67`). Mechanism: when the typespec is a TYPE atom, the
  DECL checker follows the atom's `DECL` association
  (`mdl_decl.cpp:66` in the pinned build). This is exactly the purpose of
  the dungeoneer's PUT on RAPPLIC.
- **SETG does not check the atom's DECL property.** After
  `<PUT SOMETHING DECL 'FIX>`, `<SETG SOMETHING "str">` succeeds and
  `,SOMETHING` reads `"str"` (`GASSIGNED?` T) — global assignment is not
  enforced against an association-declared type (consistent with the D1
  note that the reference does not enforce declarations on SETG).
- **PUT on a non-ATOM item is a legal association.** `<PUT 5 DECL 'FIX>`
  succeeds (returns `5`) and `<GET 5 DECL>` retrieves `FIX` — the manual's
  own example puts on a number (`<PUT 0 .L "list on a zero">`). The
  "non-structured item + FIX indicator ⇒ index error" hypothesis in the
  task is wrong for this build: the FIX/OFFSET structure path only applies
  when the *item* is structured (pinned dispatch
  `mdl_builtin_eval_put`, `macros.cpp:4320-4330`:
  `mdl_primtype_structured(arg->pt) && (indicator FIX or OFFSET)`).
- **Retrieval is keyed by `==?` identity of item and indicator**
  (the manual's note). A fresh `(1 2 3)` LIST misses an association made on
  `.L`'s LIST (`identity-keyed-retrieval` → `#FALSE ()`), and two
  reader-produced STRINGs with the same spelling are distinct objects, so
  `<PUT "abc" P X> <GET "abc" P>` stores then misses (`string-item-identity-miss`).
  Atom items/indicators always match by name because interning makes equal
  print names the same atom.

## Deliberate-error cases — `atom-props-error-cases.json`, `atom-props-error-reference.json` (probe exit 1, expected)

All process exit codes are 0; the probe flags non-ok rows via stderr output
or error breaks, which is the deliberate-error design. As in prior notes,
break-level cases also write the pre-existing handler artifact
`Atom REP has neither LVAL nor GVAL` to stderr, which is not the diagnostic.

| Case | Expression | Recorded diagnostic |
|---|---|---|
| `put-too-few-args` | `<PUT RAPPLIC>` | `*ERROR* "TOO-FEW-ARGUMENTS-SUPPLIED"`, break `LISTENING-AT-LEVEL 2` |
| `getprop-too-many-args` | `<PUT RAPPLIC P V> <GETPROP RAPPLIC Q 'FALLBACK 77>` | stderr `Too many ARGS in GETPROP`, fresh `LISTENING-AT-LEVEL 1` prompt (no `*ERROR*` break) |
| `put-structured-fix-index-out-of-range` | `<PUT '(1 2 3) 9 'X>` | stderr `PUT index too large`, fresh level-1 prompt |
| `put-string-non-character` | `<PUT "ab" 1 3>` | stderr `Error in PUT: Strings may only contain CHARACTER type`, fresh level-1 prompt |
| `get-structured-with-exp` | `<GET '(1 2 3) 1 'X>` | `*ERROR* "TOO-MANY-ARGUMENTS-SUPPLIED" "No EXP allowed for GET on structure"`, break level 2 |
| `rapplic-gval-unassigned-with-decl-prop` | `<PUT RAPPLIC DECL 'FIX> ,RAPPLIC` | `*ERROR* "UNBOUND-VARIABLE" "GVAL" RAPPLIC`, break level 2 |

- **PUT arity:** one argument is too few (`TOO-FEW-ARGUMENTS-SUPPLIED`,
  `GETNEXTREQARG` on the indicator at `macros.cpp:4316-4320`); two arguments
  on an atom are the documented *removal* form and do not error (success
  case above).
- **GETPROP/PUTPROP arity errors are their own messages**
  ("Not enough ARGS in GETPROP" / "Too many ARGS in GETPROP" and the PUTPROP
  twins, `macros.cpp:6248-6276`); extra GET args are likewise rejected via
  `NOMOREARGS`. Note two extra GET *properties* args are simply ignored
  positions (`GETPROP RAPPLIC Q 'FALLBACK 77` errors only because 4 items
  trip `LHASITEM(args, 3)`, the message names GETPROP).
- **The structure-index error is a plain stderr message, not an `*ERROR*`
  break:** `PUT index too large` (out-of-range FIX indicator on a structured
  item), and the STRING element PUT requires CHARACTER
  (`Error in PUT: Strings may only contain CHARACTER type`). The process
  returns to a fresh `LISTENING-AT-LEVEL 1` prompt in both cases.
- **GET on a structured item rejects the optional exp** with
  `TOO-MANY-ARGUMENTS-SUPPLIED` / "No EXP allowed for GET on structure"
  (`macros.cpp:4352-4356`), where the manual's inverse-of-PUT rule has no
  such carve-out.
- **A `,RAPPLIC` GVAL read still breaks UNBOUND-VARIABLE with the DECL
  property present** — properties and assignment are fully separate in the
  reference.

## Reference support matrix (quoted above, not inferred)

The pinned build implements: `PUT` and `GET` SUBRs
(`mdl_builtins.cpp:32-33`) plus `GETPROP` and `PUTPROP`
(`mdl_builtins.cpp:96-97`), with the association table in
`mdl_assoc.cpp` (hash table; `mdl_internal_eval_putprop` /
`mdl_internal_eval_getprop` at `macros.cpp:3432-3440`). The manual's
chapter 13.4 association-examination SUBRs — `ASSOCIATIONS`, `NEXT`,
`ITEM`, `INDICATOR`, `AVALUE` — and the `#ASOC (item indicator value)`
printer are **not implemented anywhere in the pinned build** (grep of all
`.cpp`/`.hpp` under `.cache/build/confusion_patched/` finds no occurrences);
association order (manual: newest first) is therefore not observable.

## What the pinned sources actually use (file:line)

- **Atom-property GET (association retrieval) is the only GET pattern in the
  December-1977 source set; there is no PUTPROP/GETPROP and no 3-arg GET
  anywhere (`grep -rn "PUTPROP\|GETPROP" 77*.mud 78*.mud 81*.mud` → 0 matches):**
  - `77dung.mud:59` `<SETG WORDS <OR <GET WORDS OBLIST> <MOBLIST WORDS 23>>>`
  - `77dung.mud:61` `<GET OBJECTS OBLIST>`, `77dung.mud:63` `<GET ROOMS OBLIST>`
  - `77np.mud:2` `<GET WORDS OBLIST>`, `77np.mud:4` `<GET OBJECTS OBLIST 23>`-era
    `(MOBLIST OBJECTS 23)` pair
  - `77makstr.mud:1` `(OBL <GET INITIAL OBLIST>)`; `77makstr.mud:24-25`
    `<GET FLAG OBLIST>`
  - `77rooms.mud:259,265` `<GET PACKAGE OBLIST>`; `77rooms.mud:261,268`
    `<GET ERROR!-INTERRUPTS INTERRUPT>`; `77rooms.mud:451` `(O <GET INITIAL
    OBLIST>)`; `77rooms.mud:804` `<GET FLAG OBLIST>` / `<GET INITIAL OBLIST>`
  - `81prim.mud:27,67` `<GET INITIAL OBLIST>`
- **PUT forms span both dispatch arms** — atom/structured item with *atom
  indicators* (association space) and FIX indicators (element store):
  - atom-property declaration, the D5 blocker itself: `77defs.mud:5`
    `<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>`
  - macro-generated element stores (`<FORM PUT .OBJ ,OFLAGS ...>`,
    `,RBITS`): `77defs.mud:23,25,27,29,31`
  - association PUTs with atom indicators on NEWTYPE objects:
    `77defs.mud:324,326,328,329,330` (`<PUT .OBJ ,OROOM <>>`,
    `<PUT .WINNER ,AOBJS ...>`), `77defs.mud:336,342,345,350,369,385,426,429`;
    `78melee.mud:16` `<PUT .OBJ ,ORAND .REM>`, `78melee.mud:464,469` `<PUT
    .HERO ,ASTRENGTH ...>`; `77act1.mud:80,90` `<PUT .L ,ORAND 1>`,
    `77act1.mud:128-130` `<PUT .T ,ODESC1 ...>`, `77act1.mud:283` `<PUT
    .DOOR ,OTOUCH? T>`
  - element stores with FIX indicators: `78melee.mud:293,299,306,308`
    (`<PUT .OV 1 .O>`, `<PUT ,PRSVEC 1 ...>`), `78melee.mud:298,322,324`
    (`<PUT .O ,OCAPAC ...>` where OCAPAC has FIX-typed storage per its
    NEWSTRUC slot), `77act1.mud:5` `<PUT <IVECTOR 256 0> ...>`,
    `77act1.mud:8` `<PUT <ALLTYPES> 6 ...>`

  An implementation that covers `<PUT item-atom indicator-atom value>`,
  `<PUT structured-item indicator-atom value>`, and
  `<PUT structured-item FIX value>` plus `<GET item indicator>` with the
  `#FALSE ()` miss therefore covers every property form the sources use;
  PUTPROP/GETPROP and the 3-arg GET/GETPROP exp are unexercised by the
  load set but implemented by the reference.

## Deviations and manual-vs-reference notes

1. **`DECL?` miss prints an augmented FALSE** — `#FALSE (3 NOFFSET)` style
   values embed the offender; the manual describes plain `#FALSE ()` for
   association misses (GET) and the pinned source flags the nonstandard
   false at `mdl_decl.cpp:63-67`. Association misses themselves (GET
   without exp) do return plain `#FALSE ()` as the manual says.
2. **GET on a structured item with an exp errors**
   ("No EXP allowed for GET on structure"), where the manual defines the
   optional exp uniformly for GET. Only the association branch of GET
   honors exp in the pinned build.
3. **Chapter 13.4 examination machinery absent** — no ASSOCIATIONS/NEXT/
   ITEM/INDICATOR/AVALUE SUBRs and no `#ASOC` printing; also no removal
   via separate PUTPROP-nil-arg syntax (the PUT 2-arg and PUTPROP-less-arg
   removals work; PUTPROP removal was not separately probed — the
   PUTPROP SUBR passes a NULL value to `mdl_internal_eval_putprop`, the
   same delete path, `macros.cpp:6281-6285`).
4. **PUT on a non-structured item with a FIX indicator is an association,
   not an error** (`<PUT 5 DECL 'FIX>` → `5`), matching the manual's
   "identical to PUTPROP except..." wording and its own numeric-item
   example; both task hypotheses to the contrary were recorded as clean
   successes instead.
5. **Two-argument PUT removal returns the item, not the previous value.**
   The manual (13.1.3 wording) says removal "returns the value that was
   associated"; the pinned reference's `association-remove-two-arg-put`
   observation shows `<PUT RAPPLIC P V>` → `RAPPLIC`, then
   `<PUT RAPPLIC P>` → `RAPPLIC` (the item echoed, NOT the old value `V`),
   then `<GET RAPPLIC P>` → `#FALSE ()` (the removal itself confirmed).
   The same shape holds for the item/indicator used, so the manual's
   "previous value" reading cannot be reproduced in the reference. The
   runtime follows the reference (removal echoes the item); this is a
   recorded manual-vs-reference adjudication, chosen because the reference
   is the executable parity target and the pinned sources discard the
   removal return value anyway.
6. **SETG ignores an atom's association-declared type** — no enforcement
   beyond the DECL? predicate (which is where the DECL property is actually
   consulted in the reference).

## Files created

- `docs/evidence/M2/atom-props-cases.json` (18 clean-exit cases)
- `docs/evidence/M2/atom-props-reference.json` (generated by the probe tool,
  `complete: true`)
- `docs/evidence/M2/atom-props-error-cases.json` (6 deliberate-error cases)
- `docs/evidence/M2/atom-props-error-reference.json` (generated by the probe
  tool, `complete: false` — by design)
- `docs/evidence/M2/ATOM-PROPS.md` (this note)

## Independent review follow-up (2026-11-20)

A read-only reviewer examined the D5 implementation against `main` at
`419fc5c` and found that the first association table used weak Racket `eq?`
keys for items, though the documented contract is MDL `==?` for both keys.
Pinned Confusion confirms that separately constructed WORDs, large FIXes,
and independently constructed VECTOR/UVECTOR REST views retrieve the same
association. The original D5 test suite missed WORD and array-view keys;
new regressions failed in three of five identity checks (`3/48` focused
failures). The store now scans session-owned entries with `mdl-identical?`
on item and indicator. This corrects key selection, but keeps both keys
strongly reachable until removal or session end. Historical association
garbage collection on unreachable keys remains unsupported. No weak table
that implements the full `==?` equivalence was justified for this slice.

The same review found that two-argument PUT on a structured item with a FIX
indicator erroneously removed an association; pinned Confusion raises
TOO-FEW-ARGUMENTS-SUPPLIED. It also found that `DECL?` stopped after one
DECL alias and let a property override a registered type. Reference cases
confirm A → B → FIX, the `#FALSE ("x" FIX)` miss, and FIX retaining its
intrinsic meaning after `<PUT FIX DECL 'STRING>`. An A ↔ B alias cycle timed
out after three seconds in the pinned interpreter; the runtime now raises
a bounded explicit cyclic-DECL error. Further reference probes establish
indexed STRING GET returning CHARACTER (PRIMTYPE WORD), one-argument GET
on structures selecting the first element, and PUT of a CHARACTER into a
mutable STRING. Those are implemented in the same dispatch path; mutation
of immutable Racket string literals remains an explicit limitation.

Reproduction from the repository root (Racket 7.9 bc, Python 3.13.0):

```text
make doctor                         exit 0, required tools found
make sources                        exit 0, two pinned repositories clean
raco test tests/atom_props_test.rkt  pre-fix exit 1 (3/48 identity failures;
                                   then structured PUT and alias failure)
raco test tests/atom_props_test.rkt  post-fix exit 0, 61 checks
make test                           exit 0, 864 Racket + 13 Python checks
make test-historical                exit 0, VFLOAD 23 + DECL 20 assertions
make check-source                   exit 0, 36 parsed, 4 non-text, 0 failed
make reference-build                exit 0, native Confusion built
make reference-capture              exit 0, five turns captured
make reference-probe                exit 0, 12 expressions probed
git diff --check                    exit 0
```

The fresh native binary SHA256 is
`167f8de42bcf92e9a424edf00a13594c9cdf3a15df34ed35b0b47eefe5c0db51`;
its embedded build timestamp makes it differ from the initial D5 binary.
The new 11 success and two deliberate-error/timeout inputs are in
`atom-props-review-cases.json` and `atom-props-review-error-cases.json`;
their raw reference outputs are in the matching `*-reference.json` files.
The success probe exits 0; the error probe exits 1 because the structured
PUT error reports stderr and the alias cycle times out. Repeating all four
saved D5 probe sets after the native rebuild produced **zero per-case
differences** in `name`, input, exit code, result output, stderr, and `ok`
status; the alias cycle remained a timeout. Verification outputs are under
ignored `artifacts/m2/verify-atom-props*.json`.

The unchanged source hashes are `77loadall.mud`
`389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa`,
`81prim.mud`
`8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`,
and `77defs.mud`
`566ebcc32be9b9226dd7cefd77a517583eebab80a03f452df39e13b85eed734e`.
`racket scripts/mdl_load.rkt --source-root
.cache/upstream/mdlzork/mdlzork_771212/patched_confusion --entry
77loadall.mud --report artifacts/m2/d5-review-load.json` exits 1 as
expected after **24** completed expressions, at `77defs.mud` expression
15, line 37, execute stage: `EMPTY?` is unassigned inside the original
`NEWSTRUC`. This is the next source-backed dependency; no source form was
skipped. Neither upstream checkout was edited. The work adds no network
evaluator and copies no GPLv3 Confusion code into the MIT-0 runtime.
