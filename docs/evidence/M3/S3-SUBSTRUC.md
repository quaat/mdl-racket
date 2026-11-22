# S3-SUBSTRUC — SUBSTRUC implementation

**RID**: S3-SUBSTRUC  
**Branch**: feat/m3-startup-substruc  
**Base commit**: 58db8036f85e273737d34c28b62ea2e247f0a69b (origin/feat/m3-startup-memq-string, PR #128)  
**Reference binary SHA256**: 6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789  
**mdlzork source SHA**: bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3

## Task scope

Implement `SUBSTRUC` to unblock the faithful SAVE-IT call chain. Prior to this slice,
`<FLOAD "77loadall.mud">` succeeds (1,229/0) but `<SAVE-IT>` fails at:
```
unassigned or non-applicable MDL operator SUBSTRUC
```
at 77rooms.mud:155 inside `UNSPEAKABLE-CODE`.

## All SUBSTRUC uses in the 1977 game source

Grep: `.cache/upstream/mdlzork/mdlzork_771212/patched_confusion/`

| File | Line | Expression | Shape |
|------|------|------------|-------|
| 77rooms.mud | 52 | `<SETG SNM <SUBSTRUC ,SCRATCH-STR 0 <- ...>>>` | STRING, no to |
| 77rooms.mud | 139 | `<SUBSTRUC .CMA 0 .LFST .TSTR>` | STRING, to=.TSTR |
| 77rooms.mud | 141 | `<SUBSTRUC .NM 0 .LLST .TSTR>` | STRING, to=.TSTR |
| 77rooms.mud | 142 | `<SUBSTRUC .JR 0 <LENGTH .JR> <REST .TSTR .LLST>>` | STRING, to=REST view |
| 77rooms.mud | 155 | `<SUBSTRUC .STR 0 <- <LENGTH .STR> <LENGTH .NSTR>>>` | STRING, no to |
| 77rooms.mud | 279 | `<SUBSTRUC .XUNM 0 3>` | STRING, no to |
| 77rooms.mud | 1571 | `<SUBSTRUC "HELP" 0 4 <BACK <1 .V> 4>>` | STRING literal, to=BACK view |
| 77rooms.mud | 1587 | `<UPPERCASE <SUBSTRUC .S ...>>` | STRING, no to |
| 77act2.mud | 525, 533, 577 | `<SUBSTRUC <SPNAME ...> 0 4 .S>` | STRING, to=.S |

## Contract (MDL manual ch. 7, section 7.1.7 + Confusion probes)

```
<SUBSTRUC from rest amount to>
```
- `from`: required, must be LIST/VECTOR/UVECTOR/STRING/BYTES PRIMTYPE
- `rest`: FIX, default 0, must be in [0, length(from)]
- `amount`: FIX, default remaining after rest, must be in [0, length(from)-rest]
- `to`: optional structured of same PRIMTYPE; receives copied elements starting at
  its position 0 (may be a REST view), is returned as-is after modification
- Without `to`: returns a fresh independent structure of PRIMTYPE of `from`
- Copying is atomic ("one fell swoop")
- Result never shares storage with `from`

**Confusion-confirmed error messages:**
- `"SUBSTRUC rest cannot be negative"` (rest < 0)
- `"SUBSTRUC rest too large"` (rest > length)
- `"SUBSTRUC amount cannot be negative"` (amount < 0)
- `"SUBSTRUC amount too big for source"` (amount > length - rest)

## Confusion probe observations

Probe JSON: `/tmp/.../scratchpad/substruc-reference.json`

Key observations vs. manual:
- STRING without `to`: returns fresh mutable Racket string (TYPE=STRING), never aliased
- STRING with `to` (STRING or STRING view): copies chars, returns `to` as TYPE=STRING
- Partial fill: only `amount` chars written; remainder of `to` unchanged
- REST-view as `to`: copies into view's underlying storage at view's start offset
- Independence confirmed: mutating source after SUBSTRUC does not affect result
- View source: SUBSTRUC on `<REST "hello" 2>` returns "llo" (fresh, not aliased)
- UVECTOR: returns new UVECTOR with same element type as source; `to` path modifies in-place
- VECTOR: returns new VECTOR; `to` path modifies in-place
- LIST: returns new LIST (no `to` probe; game sources don't use it)
- CHTYPED source: `<CHTYPE "abc" STRING>` → result is STRING (uses PRIMTYPE)
- Error: `<SUBSTRUC "abc" 4>` → ARGUMENT-OUT-OF-RANGE "SUBSTRUC rest too large"
- Error: `<SUBSTRUC "abc" 0 4>` → ARGUMENT-OUT-OF-RANGE "SUBSTRUC amount too big for source"

**Deviations from spec**: None. The manual says "result type is PRIMTYPE of from"; Confusion
confirms STRING→STRING, VECTOR→VECTOR, UVECTOR→UVECTOR, LIST→LIST. Manual does not specify
the return value with `to`; Confusion confirms it is `to` itself.

## Implementation

**File**: `mdl/runtime/core.rkt`

Added `mdl-substruc` function (~80 lines) handling STRING, VECTOR/UVECTOR, and LIST:
- STRING path: `mdl-string-ref` for view-safe reads; `mdl-string-set!` for view-safe writes
- VECTOR/UVECTOR path: direct `vector-ref`/`vector-set!` with start offset; GC-tracked via
  `mdl-track-allocation!` on new-storage (VECTOR: `(+ (* 2 count) 2)` words;
  UVECTOR: `(+ count 2)` words); element type preserved from source
- LIST path: `drop`+`take`+`mdl-list`; no `to` support (strict error, not in game path)
- Registered as `"SUBSTRUC"` in `builtin-table`; exported as `mdl-substruc`

**Changes**:
- `/mdl/runtime/core.rkt`: add `mdl-substruc`, register in builtin-table, export
- `/tests/substruc_test.rkt`: 42 tests (new, in smoke suite)
- `/scripts/test_racket.sh`: add substruc_test.rkt
- `/tests/historical_saveit_test.rkt`: update XFAIL anchor to ON

## Red→green evidence

**Before** (base commit 58db803):
```
unassigned or non-applicable MDL operator SUBSTRUC
```

**After**:
```
raco test: "tests/substruc_test.rkt"
SUBSTRUC tests passed
42 tests passed
```

**SAVE-IT new frontier**:
```
mdl-eval: unassigned or non-applicable MDL operator ON
```
at 77rooms.mud:16: `<SET IH <ON "IPC" ,ILO 1>>`

SAVE-IT steps that now execute successfully:
1. `<PUT <FIND-OBJ "PAPER"> ,ODESC1 <UNSPEAKABLE-CODE>>` (line 12) — SUBSTRUC at line 155
2. `<SETG VERS .ST>` (line 13) — REMARKABLY-DISGUSTING-CODE date string
3. `<SETG SCRIPT-CHANNEL <>>`  (line 14)
4. `<SETG RAW-SCORE 0>` (line 15)
5. `<SET IH <ON "IPC" ,ILO 1>>` (line 16) — NEW BARRIER

## Test counts

```
make test (full smoke, dangerouslyDisableSandbox):
  2115 total, 2 pre-existing failures in memq_string_test.rkt:76-77
  (atom equality across separate eval contexts, pre-existing at base 58db803)
  
make test-m3-saveit:
  5 tests passed

make m3-source-progress:
  1229 completed, 0 skipped (loader exit 0)
```

## Supported / unsupported

**Supported**: STRING (all game uses), VECTOR, UVECTOR, LIST (without `to`)  
**Unsupported (strict error)**: LIST with `to` (raises explicit error); BYTES (not in game);
  TUPLE (not tested; raises "SUBSTRUC requires a structured argument")

## Next frontier

**Operator**: `ON` ("IPC" interrupt registration)  
**Call**: 77rooms.mud:16 `<SET IH <ON "IPC" ,ILO 1>>`  
**Call chain**: SAVE-IT → ON

## Proposed docs/SEMANTICS.md section

```markdown
### SUBSTRUC

`<SUBSTRUC from rest amount to>` — copies structured elements (MDL manual ch. 7 §7.1.7).

- `rest` (FIX, default 0): starting index into `from`; must be in [0, length(from)]
- `amount` (FIX, default remaining): number of elements; must be in [0, length(from)-rest]
- `to` (structured, optional): destination of same PRIMTYPE; receives elements at
  positions [0, amount); returned after modification

Without `to`: returns a fresh independent structure of the PRIMTYPE of `from`.
Never shares storage with `from`. Copying is atomic.

Error messages (Confusion-confirmed):
- `SUBSTRUC rest cannot be negative`
- `SUBSTRUC rest too large`
- `SUBSTRUC amount cannot be negative`
- `SUBSTRUC amount too big for source`

Supported primitive types: STRING, VECTOR, UVECTOR, LIST (no `to`).

For STRING: result is a fresh mutable Racket string. With STRING `to`, the view's
underlying storage is written via `mdl-string-set!`. With `to`, element type for
UVECTOR is NOT re-checked (Confusion copies blindly).
```
