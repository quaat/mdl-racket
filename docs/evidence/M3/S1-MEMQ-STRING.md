# S1-MEMQ-STRING — MEMQ on STRING Haystacks

**Branch:** `feat/m3-startup-memq-string`
**Base commit:** `c09bb02` (origin/feat/m3-startup-unparse, stacked on PR #125/#111)
**RID:** S1-MEMQ-STRING
**Date:** 2026-11-22

---

## Finding

`<FLOAD "77loadall.mud">` then `<SAVE-IT>` fails at:

```
mdl-memq: unsupported STRING MEMQ
```

Call chain: `SAVE-IT` (77rooms.mud:12) → `UNSPEAKABLE-CODE` (77rooms.mud:146-157) →
`<MEMQ !\/ <OREAD .O>>` (77rooms.mud:148).

Anchored XFAIL pinned in `tests/historical_saveit_test.rkt` before this fix.

## Reproduction (before fix)

```
raco test tests/memq_test.rkt
```

The test `(check-exn #rx"unsupported STRING MEMQ" ...)` passed — meaning the error was
reliably reproduced.

## Root Cause

`mdl-memq` in `mdl/runtime/core.rkt` (line 2795 at base) raised a hard error for any
STRING haystack unconditionally. MEMQ on STRING is used by UNSPEAKABLE-CODE and also
at 77rooms.mud:55 (another MEMQ on STRING in SAVE-IT path), so this blocked the
faithful boot sequence.

## Manual Contract (MDL manual ch. 13)

MEMQ on a STRING searches for a `==?` element (CHARACTER) and returns the STRING
REST'd to that element (a view sharing storage with the original — not a copy), or
`#FALSE ()` if not found. The returned view's internal start offset equals the absolute
position of the found character in the underlying storage, so BACK works correctly on
the result.

## Confusion Observations

Probe: `docs/evidence/M3/memq-string-cases.json`
Reference: `docs/evidence/M3/memq-string-reference.json`
Interpreter SHA256: `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789`
(rebuilt 2026-11-22 from pinned source mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; identical output)

| Case | Confusion result |
|------|-----------------|
| `<MEMQ !\a "abc">` | `"abc"` (hit at start) |
| `<MEMQ !\b "abc">` | `"bc"` (hit at middle) |
| `<MEMQ !\c "abc">` | `"c"` (hit at end) |
| `<MEMQ !\z "abc">` | `#FALSE ()` (miss) |
| `<MEMQ !\a "">` | `#FALSE ()` (empty string) |
| `<TYPE <MEMQ !\b "abc">>` | `STRING` |
| `<LENGTH <MEMQ !\b "abc">>` | `2` |
| `<1 <MEMQ !\b "abc">>` | `!\b` |
| aliasing: PUT into result mutates original | `"zaa"` (confirmed) |
| `<MEMQ !\b <REST "xbc" 1>>` | `"bc"` (view haystack works) |
| `<MEMQ 97 "abc">` | `#FALSE ()` ← **deviation** |
| `<MEMQ "a" "abc">` | `#FALSE ()` ← **deviation** |

**Confusion deviation from strict `==?` semantics:** Confusion accepts non-CHARACTER
needles (FIX, STRING) silently and returns `#FALSE ()` rather than erroring. This is
semantically consistent: a FIX or STRING is never `==?` to a CHARACTER element in a
STRING, so the result is always a miss. Our implementation follows Confusion here.

## Design Decision

Implement STRING MEMQ by:
1. Extracting `base = (mdl-base structure)` (strips typed-value wrappers).
2. If `base` is a string/view: check needle via `mdl-character-code`. Non-CHARACTER
   needle → `mdl-false`. CHARACTER needle → scan by index, compare char codes.
3. On hit at index `i`: return `(mdl-string-rest base i)` — an `mdl-string-view` with
   the same `storage`, `start = (view-start + i)`, `length = (view-length - i)`. This
   shares storage, supports PUT aliasing, and enables BACK up to `start` positions.
4. On miss: return `mdl-false`.
5. Existing LIST/VECTOR/UVECTOR/TUPLE paths unchanged; non-structured types still error.

## Changed Files

- `mdl/runtime/core.rkt`: `mdl-memq` — replaced early error with cond-dispatch on
  STRING vs. structured vs. error
- `tests/memq_test.rkt`: Updated the placeholder `check-exn STRING MEMQ` test to
  verify the now-successful CHARACTER-in-STRING MEMQ case
- `tests/memq_string_test.rkt`: New comprehensive test file (21 checks covering hit,
  miss, empty, type, length, NTH, aliasing, view haystack, BACK compat, nested MEMQ,
  non-CHARACTER needle)
- `scripts/test_racket.sh`: Added `tests/memq_string_test.rkt` to smoke suite
- `tests/historical_saveit_test.rkt`: Updated XFAIL frontier to next actual failure

## Red → Green Evidence

Before fix:
```
(check-exn #rx"unsupported STRING MEMQ" (lambda () ...))  ; PASSED
```

After fix:
```
raco test tests/memq_test.rkt tests/memq_string_test.rkt
31 tests passed
```

Full smoke:
```
bash scripts/test_racket.sh
2068 tests passed
```

M3 targets:
```
make test-m3-saveit   → 5 tests passed
make test-m3-start-back → 6 tests passed
make m3-source-progress → 1229 completed, 0 skipped
```

## Updated SAVE-IT XFAIL Frontier

After STRING MEMQ fix, SAVE-IT gets through UNSPEAKABLE-CODE's MEMQ/BACK/REST chain
but fails at:

```
mdl-eval: unassigned or non-applicable MDL operator SUBSTRUC
```

Call chain: `SAVE-IT` (77rooms.mud:12) → `UNSPEAKABLE-CODE` (77rooms.mud:146-157) →
`<SUBSTRUC .STR 0 <- <LENGTH .STR> <LENGTH .NSTR>>>` (77rooms.mud:155).

SUBSTRUC is not implemented. Next slice: implement SUBSTRUC on STRING (and possibly
VECTOR/UVECTOR per manual ch. 7.6.3). `tests/historical_saveit_test.rkt` now asserts
`#rx"unassigned or non-applicable MDL operator SUBSTRUC"`.

## Commands Run

```
# Confusion probe
PYTHONPATH=".sandbox-pydeps/lib" python3 -m scripts.mdl_probe \
  --cases docs/evidence/M3/memq-string-cases.json \
  --output docs/evidence/M3/memq-string-reference.json

# Unit tests
export PLTCOLLECTS=":$PWD"
raco test tests/memq_test.rkt tests/memq_string_test.rkt   # 31 passed
racket tests/historical_saveit_test.rkt                     # 5 passed (exit 0)
bash scripts/test_racket.sh                                 # 2068 passed

# M3 targets
make PYTHON=/usr/bin/python3 test-m3-saveit test-m3-start-back m3-source-progress
```

## Remaining Risks / Unsupported Cases

- SUBSTRUC not implemented: blocks UNSPEAKABLE-CODE and therefore SAVE-IT completing.
- MEMBER on STRING: not tested here (no game source usage found in 77rooms.mud).
  MEMBER uses structural equality (`=?`); on STRING it would compare CHARACTERs
  structurally vs. `==?`. Not needed for the current path.

## Proposed docs/SEMANTICS.md section

```markdown
### MEMQ on STRING (ch. 13)

MEMQ with a CHARACTER needle and a STRING haystack searches each position using
`==?` identity (character-code equality). On hit at position i, it returns the
string REST'd to i (an mdl-string-view sharing storage with the original), enabling
BACK and PUT aliasing. On miss, returns #FALSE ().

Non-CHARACTER needles (FIX, STRING, etc.) silently return #FALSE () — they can
never be `==?` to a CHARACTER element. Confusion confirms this, though the manual
does not explicitly address the type mismatch; strict error was not observed.

The returned view's start offset equals the absolute position in the backing storage,
so BACK N works correctly if N <= i.
```
