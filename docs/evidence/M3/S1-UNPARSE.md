# S1-UNPARSE: Implement UNPARSE SUBR

**Branch:** `feat/m3-startup-unparse`  
**Base commit:** `9d6ff41dff86329abd8f3cc1830da5000cb29b90` (PR #111 head: #107 + #109 RANDOM + #111 BACK)  
**RID:** S1-UNPARSE  
**Date:** 2026-11-22  

---

## Finding

The faithful startup entry `run.mud` = `<FLOAD "77loadall.mud">` then `<SAVE-IT>` fails
immediately with `mdl-eval: unassigned or non-applicable MDL operator UNPARSE`.

The only UNPARSE call in the December 1977 Zork source is in `77rooms.mud:164`:
```
<UNPARSE <CHTYPE <GETBITS .N <BITS 5 18>> FIX>>
```
inside `REMARKABLY-DISGUSTING-CODE` (77rooms.mud:158), called as the AUX default for `ST`
in `SAVE-IT` (77rooms.mud:8-60). It converts the day-of-month FIX from DSKDATE into the
string `"This version created November 22."`.

Verified by grep:
```
grep -rn "UNPARSE" .cache/upstream/mdlzork/mdlzork_771212/patched_confusion/*.mud
77rooms.mud:164: <UNPARSE <CHTYPE <GETBITS .N <BITS 5 18>> FIX>>
```
(Binary SAVE files also match; MDL source has exactly one call.)

---

## Semantic contract

**Manual source:** MDL Programming Language, ch. 7, section 7.6.6.4; appendix 2.  
Fetched 2026-11-22 from https://raw.githubusercontent.com/taradinoc/mdl-docs/master/docs/07-structured-objects.md

> `<UNPARSE any radix:fix>`  
> Returns a STRING containing the character sequence PRINT would have output for `any`,
> without the carriage-returns PRINT inserts for channel line-width control.  
> The optional `radix` (FIX, default 10) is used when converting FIX values.

Appendix 2 summary: `UNPARSE (OBJECT "OPTIONAL" RADIX)`, VALUE is STRING, OBJECT is ANY,
RADIX is FIX.

---

## Confusion reference observations

Probe: `docs/evidence/M3/unparse-cases.json` → `docs/evidence/M3/unparse-reference.json`  
Interpreter SHA256: `b5fcb91bbe9326c60a3fdb936eb089a5482ba15d2726f3dff212548cda83b177`

| Expression | Confusion stdout (result_output) | Notes |
|---|---|---|
| `<UNPARSE 0>` | `"0"` | FIX zero → decimal |
| `<UNPARSE 1>` | `"1"` | FIX positive |
| `<UNPARSE 22>` | `"22"` | game day-of-month |
| `<UNPARSE -1>` | `"-1"` | FIX negative |
| `<UNPARSE 1073741823>` | `"1073741823"` | FIX max (2^35-1) |
| `<UNPARSE -1073741824>` | `"-1073741824"` | FIX min (-2^35) |
| `<UNPARSE 22 8>` | `"22"` | **radix IGNORED** (not "26") |
| `<UNPARSE 255 16>` | `"255"` | **radix IGNORED** (not "FF") |
| `<TYPE <UNPARSE 42>>` | `STRING` | result type is STRING |
| `<PUT <UNPARSE 42> 1 !\\X>` | `"X2"` | result is **fresh mutable** STRING |
| `<UNPARSE 42>` (after PUT above) | `"42"` | each call returns a fresh copy |
| `<UNPARSE FOO>` | `"FOO"` | ATOM → pname |
| `<UNPARSE "hello">` | `"\"hello\""` | STRING → double-quoted |
| `<UNPARSE <>>` | `"#FALSE ()"` | FALSE → `#FALSE ()` |
| `<UNPARSE !\\A>` | `"!\\A"` (3 chars: `!`, `\`, `A`) | CHARACTER → `!\` + char |
| `<UNPARSE 1.5>` | `"1.5000000"` | FLOAT → 7 decimal places |
| `<UNPARSE (1 2 3)>` | `"(1 2 3)"` | LIST → `(elem …)` space-separated |
| `<UNPARSE <CHTYPE 22 FIX>>` | `"22"` | game use case |

**Key deviation:** Confusion ignores the optional `radix` argument completely — it always
produces decimal output for FIX regardless of radix value. This matches the game's
usage (no radix argument supplied).

---

## Design decision

Implement UNPARSE as a Racket SUBR registered in the core dispatch table.

- **FIX** (required for the game): `(number->string value)` in base 10. Radix argument
  accepted as FIX in range 2–36 (error otherwise) but always treated as 10 per Confusion.
- **ATOM**: pname string. Exact for simple alphanumeric pnames; `\`-escaping for exotic
  atom names is not implemented (not needed by the game).
- **STRING**: double-quoted with `\"` and `\\` escaping of `"` and `\` in content.
- **FALSE**: `"#FALSE ()"` or `"#FALSE (elem …)"` for non-empty payload (recursive).
- **CHARACTER**: `"!\\"` + character string (3 chars for ASCII printable).
- **LIST**: `"(elem …)"` with space-separated recursively-unparsed elements.
- **FLOAT**: strict unsupported error (7-decimal-place format unconfirmed for all values;
  not used in the game). Per AGENTS.md strict-failure rule.
- **Other types** (VECTOR, UVECTOR, WORD, FORM, FUNCTION, …): strict unsupported error.

Result is always a **fresh mutable** Racket string (via `string-copy`), matching
Confusion's observed mutability.

---

## Changed files

| File | Change |
|---|---|
| `mdl/runtime/core.rkt` | Added `mdl-unparse-escape-string`, `mdl-unparse-value`, `mdl-unparse`; registered `"UNPARSE"` in dispatch table |
| `tests/unparse_test.rkt` | New: 25 tests (interpreted, compiled, APPLY paths; FIX, ATOM, STRING, FALSE, CHARACTER, LIST, error cases) |
| `tests/historical_saveit_test.rkt` | New: historical regression asserting 1229-form load + SAVE-IT XFAIL frontier |
| `scripts/test_racket.sh` | Added `tests/unparse_test.rkt` to smoke suite |
| `Makefile` | Added `test-m3-saveit` target; added to `.PHONY` |
| `docs/evidence/M3/unparse-cases.json` | Confusion probe cases |
| `docs/evidence/M3/unparse-reference.json` | Confusion probe reference output |

---

## Red → green evidence

**Before fix** (base commit, calling SAVE-IT after loading):
```
mdl-eval: unassigned or non-applicable MDL operator UNPARSE
```

**After fix** (probe-saveit.rkt output):
```
Load status: PASS
Completed expressions: 1229
Skipped expressions: 0

--- SAVE-IT call result ---
EXCEPTION: mdl-memq: unsupported STRING MEMQ
```

UNPARSE no longer fails. The 1,229-form load still completes with 0 skips.

---

## Test counts

```
raco test tests/unparse_test.rkt
25 tests passed

raco test tests/historical_saveit_test.rkt
5 tests passed

bash scripts/test_racket.sh
3/1882 test failures
```

The 3 failures are pre-existing sandbox artifacts (loader_test.rkt, declaration_test.rkt,
percent_read_test.rkt hardcode `/tmp` paths that the sandbox blocks; unrelated to this change).

Python tests and m3-source-progress: not affected (no semantic change to loaded forms).

---

## Source progress

- Completed expressions: 1229 / 1229 loaded
- Skipped expressions: 0
- SAVE-IT progress: UNPARSE ✓ → next frontier: STRING MEMQ

---

## Next SAVE-IT frontier

**Operator:** MEMQ  
**Function:** `UNSPEAKABLE-CODE` (77rooms.mud:146)  
**Call site:** 77rooms.mud:148  
**Expression:** `<SET STR <MEMQ !\/ <OREAD .O>>>`  
**Error:** `mdl-memq: unsupported STRING MEMQ`  
**Called from:** SAVE-IT at 77rooms.mud:12 (`<PUT <FIND-OBJ "PAPER"> ,ODESC1 <UNSPEAKABLE-CODE>>`)

MEMQ with a CHARACTER needle in a STRING haystack (the "search string for character"
form) is not currently implemented. This is distinct from MEMQ on LISTs which works.

---

## Remaining risks / unsupported cases

1. **Radix deviation:** Confusion ignores radix; the MDL manual says it should work. If
   any source ever passes a non-10 radix to UNPARSE and expects non-decimal output, we
   will deviate from the manual. The game does not use the radix argument.
2. **ATOM \-escaping:** ATOM PNAME is emitted without backslash-escaping special chars.
   Exact only for alphanumeric pnames. Not an issue for the game's atoms.
3. **FLOAT format:** Confusion uses 7 decimal places (e.g. `1.5000000`). Not implemented;
   strict error on FLOAT input. FLOAT not used in the game's UNPARSE calls.
4. **WORD, FORM, structured typed values:** not implemented; strict error. Not needed by
   the game's UNPARSE calls.

---

## Proposed docs/SEMANTICS.md section

```markdown
### UNPARSE

**Contract (MDL manual ch. 7, section 7.6.6.4; appendix 2):**
`<UNPARSE any radix:fix>` → STRING

Returns a fresh mutable STRING containing the character sequence PRINT would
emit for `any`, without line-break characters. The optional `radix` (FIX,
default 10) selects the number base for FIX values.

**Confusion reference (SHA256 b5fcb91b…):**
Confusion ignores the `radix` argument; always produces decimal FIX output
regardless of radix value. We match this behaviour.

**Implemented types (exact against Confusion):**
- FIX → decimal string (radix ignored per Confusion)
- ATOM → PNAME (exact only for alphanumeric pnames; \\-escaping not implemented)
- STRING → double-quoted with \" and \\ content escaping
- FALSE → `#FALSE ()` or `#FALSE (elem …)` (recursive)
- CHARACTER → `!\\` followed by the character
- LIST → `(elem …)` space-separated, recursive

**Strict unsupported error for:** FLOAT, VECTOR, UVECTOR, WORD, FORM, FUNCTION,
and all other types.

**Result mutability:** each call returns a fresh mutable STRING (string-copy),
matching Confusion's observed behaviour.

**Source use:** the only UNPARSE call in the December 1977 Zork is
`77rooms.mud:164` (`REMARKABLY-DISGUSTING-CODE`), which unparses a FIX
(day-of-month from DSKDATE). The radix and other-type paths are not exercised
by the game source.
```
