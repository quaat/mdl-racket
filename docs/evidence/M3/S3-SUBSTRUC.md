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

Probe JSONs: `docs/evidence/M3/substruc-cases.json`, `docs/evidence/M3/substruc-reference.json`
Review probes: `/tmp/.../scratchpad/substruc-review-cases.json`

Key observations vs. manual (initial probes):
- STRING without `to`: returns fresh mutable Racket string (TYPE=STRING), never aliased
- STRING with `to` (STRING or STRING view): copies chars, returns `to` as TYPE=STRING
- Partial fill: only `amount` chars written; remainder of `to` unchanged
- REST-view as `to`: copies into view's underlying storage at view's start offset
- Independence confirmed: mutating source after SUBSTRUC does not affect result
- View source: SUBSTRUC on `<REST "hello" 2>` returns "llo" (fresh, not aliased)
- UVECTOR: returns new UVECTOR with same element type as source; `to` path modifies in-place
- VECTOR: returns new VECTOR; `to` path modifies in-place
- LIST: returns new LIST (no `to` probe initially; game sources don't use it)
- NEWTYPE FOO STRING source: `<TYPE <SUBSTRUC ...>>` → STRING (PRIMTYPE, not FOO)
- NEWTYPE BAR VECTOR source: result TYPE → VECTOR
- FORM has PRIMTYPE LIST: `<TYPE <SUBSTRUC '<+ 1 2> 0 2>>` → LIST
- Error: `<SUBSTRUC "abc" 4>` → ARGUMENT-OUT-OF-RANGE "SUBSTRUC rest too large"
- Error: `<SUBSTRUC "abc" 0 4>` → ARGUMENT-OUT-OF-RANGE "SUBSTRUC amount too big for source"

Review probe observations (Confusion-confirmed, items 1-6):
- **Item 1 (UVECTOR type)**: `<SUBSTRUC <IUVECTOR 2 !\\a> 0 2 <IUVECTOR 2 0>>` →
  TYPES-DIFFER-IN-UNIFORM-VECTOR "SUBSTRUC UVECTOR to and from must be same type"
- **Item 2 (dest too short)**:
  - `<SUBSTRUC "abcde" 0 4 <ISTRING 2>>` → ARGUMENT-OUT-OF-RANGE "SUBSTRUC destination too short"
  - `to` is left unchanged (confirmed: "zz" stays "zz" after error)
  - Same for VECTOR/UVECTOR to with insufficient length
- **Item 3 (overlap)**:
  - STRING forward: `<SUBSTRUC .S 0 4 <REST .S 1>>` with S="abcdef" → "aabcdf" (Confusion)
  - Our a40e5e4 gave "aaaaaf" (non-atomic write-through)
  - UVECTOR: `<SUBSTRUC .V 0 4 <REST .V 1>>` → `![1 1 2 3 4 6!]` (Confusion)
- **Item 4 (error messages)**:
  - Non-FIX rest: SECOND-ARG-WRONG-TYPE "Second argument to SUBSTRUC must be a FIX"
  - FALSE `<>` rest: same error (not special-cased)
  - Non-FIX amount: THIRD-ARG-WRONG-TYPE "Third argument to SUBSTRUC must be a FIX"
  - Wrong `to` type: ARG-WRONG-TYPE "Last arg to SUBSTRUC must be same type as primtype of first arg"
- **Item 5 (LIST to)**:
  - `<SET T '(0 0 0)> <SUBSTRUC '(1 2 3) 0 2 .T> .T` → `(1 2 0)` (Confusion)
  - Confusion mutates first `count` mcars of `to` list pairs in-place and returns `to`
  - `(LIST 0 0 0)` = 4-element list (LIST,0,0,0); SUBSTRUC count=2 → `(1 2 0 0)` confirmed
  - Destination too short → "SUBSTRUC destination too short"
- **Item 6 (NEWTYPE/FORM)**:
  - `<NEWTYPE FOO STRING>` source → result TYPE=STRING (confirmed)
  - `<NEWTYPE BAR VECTOR>` source → result TYPE=VECTOR (confirmed)
  - FORM (`'<+ 1 2>`) SUBSTRUC → LIST (FORM has PRIMTYPE LIST) (confirmed)

**Deviations from spec**: None. The manual says "result type is PRIMTYPE of from"; Confusion
confirms STRING→STRING, VECTOR→VECTOR, UVECTOR→UVECTOR, LIST→LIST. Manual does not specify
the return value with `to`; Confusion confirms it is `to` itself. LIST `to` confirmed supported
(item 5 above); implemented.

## Implementation

**File**: `mdl/runtime/core.rkt`

Added `mdl-substruc` function handling STRING, VECTOR/UVECTOR, and LIST (incl. LIST `to`):
- Pre-checks: non-FIX rest/amount → type error messages; negative → value error messages
- STRING path: `mdl-string-ref` for view-safe reads; snapshot list → `mdl-string-set!` writes
- VECTOR/UVECTOR path: snapshot list → `vector-set!` with start offset; GC-tracked via
  `mdl-track-allocation!` on new-storage (VECTOR: `(+ (* 2 count) 2)` words;
  UVECTOR: `(+ count 2)` words); element type preserved from source; UVECTOR `to` type-checked
- LIST path: `drop`+`take` snapshot; no-to returns `mdl-list`; with-to mutates mcars in-place
- All `to` paths: length check BEFORE any write; snapshot BEFORE writing (atomic copy)
- Registered as `"SUBSTRUC"` in `builtin-table`; exported as `mdl-substruc`

**Changes**:
- `/mdl/runtime/core.rkt`: add `mdl-substruc`, register in builtin-table, export
- `/tests/substruc_test.rkt`: 62 tests (initial 42 + 20 review fixes; in smoke suite)
- `/scripts/test_racket.sh`: add substruc_test.rkt
- `/tests/historical_saveit_test.rkt`: update XFAIL anchor to ON

## Red→green evidence

**Before** (base commit 58db803):
```
unassigned or non-applicable MDL operator SUBSTRUC
```

**After** (initial, a40e5e4):
```
raco test: "tests/substruc_test.rkt"
SUBSTRUC tests passed
42 tests passed
```

**After review fixes** (b54a5a9):
```
raco test: "tests/substruc_test.rkt"
SUBSTRUC tests passed
62 tests passed
```

**SAVE-IT new frontier** (unchanged from initial):
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
make test (full smoke, PLTCOLLECTS="$PWD:" dangerouslyDisableSandbox):
  2859 total, 0 failures (commit b54a5a9)
  
  Without PLTCOLLECTS (worktree environment):
  6 pre-existing failures in compiler_test.rkt, channel_port_test.rkt,
  channel_root_identity_test.rkt, historical_channel_start_test.rkt,
  printstring_channel_test.rkt, terminal_channel_test.rkt — all due to
  "collection not found: mdl/lang/reader" (needs `raco pkg install --auto --link`)
  
make test-m3-saveit:
  5 tests passed

make m3-source-progress:
  1229 completed, 0 skipped (loader exit 0)
```

## Supported / unsupported

**Supported**: STRING (all game uses), VECTOR, UVECTOR, LIST (without AND with `to`)  
**Unsupported (strict error)**: BYTES (not in game path);
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

Supported primitive types: STRING, VECTOR, UVECTOR, LIST (incl. LIST `to`).

For STRING: result is a fresh mutable Racket string. With STRING `to`, the view's
underlying storage is written via `mdl-string-set!`. Copy is atomic: all source
elements snapshotted before any write (handles overlapping from/to views).
For UVECTOR `to`: element type must equal source element type (TYPES-DIFFER error).
For LIST `to`: mutates first `count` mcars of `to` pairs in-place, returns `to`.
Destination length is always checked before any write (ARGUMENT-OUT-OF-RANGE if too short).
```
