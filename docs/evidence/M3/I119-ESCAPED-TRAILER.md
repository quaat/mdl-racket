# I119 — Backslash-escaped OBLIST trailer PNAME fix

**Branch**: `fix/m3-119-escaped-trailer`
**Base commit**: `124f60c82007ef9f07213850d8c78d3ee9f08b13` (origin/feat/m3-logical-gc umbrella)
**Reference binary**: pinned Confusion `6df359f6…` (full SHA256 `b5fcb91bbe9326c60a3fdb936eb089a5482ba15d2726f3dff212548cda83b177`)

## Finding restated

`DEAD\!!-WORDS`, `IN\!!-WORDS`, `OUT\!!-WORDS` (77act1.mud:379-384 and
78melee.mud) produced atoms whose PNAME kept the backslash (`DEAD\!`) where
pinned Confusion gives `DEAD!`.  The atoms are vocabulary words compared with
`==?` during gameplay.  With read-time interning (#118) the wrong atoms were
created on WORDS during load, so `==?` verb comparisons on those lines compared
against the wrong atom (gameplay-relevant).

The historical placement test (`tests/historical_oblist_placement_test.rkt`)
allowlisted `DEAD\!`, `IN\!`, `OUT\!` on `@WORDS` as a "separate issue".  The
fix removes those allowlist entries; with the fix, the allowlist entries become
stale, which the test actively checks (it would fail if any stale entry
remained).

## Reproduction (test name and failing output BEFORE fix)

Before the fix, `tests/escaped_atom_test.rkt` (new test) would have reported:

```
--------------------
DEAD\!!-WORDS: PNAME is DEAD!, oblist is WORDS
FAILURE
  actual: "DEAD\\!"
  expected: "DEAD!"
--------------------
```

The raw parser output for `,DEAD\!!-WORDS` before fix:

```
parsed atom raw string: "DEAD\\!!-WORDS"  ; backslash retained
```

After fix:

```
parsed atom raw string: "DEAD!!-WORDS"    ; backslash stripped
```

## Root cause (file:line)

`mdl/parser.rkt` lines 74–81 (`read-atom!` escape branch):

```racket
;; OLD — retains backslash ("MDL escape semantics are a later milestone")
(write-char #\\ out)
(write-char escaped out)
```

The backslash was deliberately retained with a TODO comment.  With the string
`"DEAD\\!!-WORDS"` (containing a literal backslash), the existing
`(regexp-match-positions #rx"!-" ...)` in `mdl-atom` (core.rkt ~2277) found the
first `!-` AFTER the backslash-exclamation pair, yielding pname=`"DEAD\\!"`.

## Manual contract

**MDL manual chapter 15 (OBLISTs / reading)**: `\` quotes the next character,
making it a literal constituent of the PNAME.  The backslash is NOT retained.
The `!-` oblist trailer split operates on the processed (backslash-stripped)
string.

**Confusion observations** (probe 2026-11-22, binary `6df359f6…`; cases/reference
JSON: `docs/evidence/M3/I119-escaped-trailer-{cases,reference}.json`):

| Expression         | Confusion result | Explanation                                       |
|--------------------|------------------|---------------------------------------------------|
| `SPNAME DEAD\!!-WORDS` | `"DEAD!"`    | `\!` → `!`; then unescaped `!-WORDS` → split    |
| `SPNAME IN\!!-WORDS`   | `"IN!"`      | same                                              |
| `SPNAME OUT\!!-WORDS`  | `"OUT!"`     | same                                              |
| `SPNAME A\!B`          | `"A!B"`      | `\!` → `!`; no `-` follows → no split            |
| `SPNAME A\-B`          | `"A-B"`      | `\-` → `-`                                       |
| `SPNAME A\\B`          | `"A\B"`      | `\\` → `\`                                       |
| `SPNAME \!A`           | `"!A"`       | leading escape                                    |
| `==? DEAD\!!-WORDS DEAD\!!-WORDS` | `T` | intern identity                              |
| `SPNAME A\!-B`         | `"A"`        | `\!` → `!` in buffer, then `-` → `!-` split, PNAME=A |
| `SPNAME A\!!-B`        | `"A!"`       | `\!` → `!` (kept), then unescaped `!-` → split, PNAME=A! |

**Key semantic rule**: the `!-` trailer split operates on the escape-processed
string.  `\!` contributes a literal `!` to the processed string; if the
immediately following source character is `-`, this `!-` sequence is the trailer
separator (PNAME does NOT include that trailing `!`; it goes as the separator
marker).  This matches `A\!-B` → PNAME `A` (not `A!`).

## Design decision

Strip the backslash in `read-atom!` (parser.rkt only).  The `mdl-atom` function
in `core.rkt` already splits on the first `!-` via `#rx"!-"`, which is correct
for the processed (backslash-free) string:

- `DEAD\!!-WORDS` → parser → `"DEAD!!-WORDS"` → first `!-` at pos 5 → pname `DEAD!`, oblist `WORDS`. ✓
- `A\!-B` → parser → `"A!-B"` → first `!-` at pos 1 → pname `A`, oblist `B`. ✓ (matches Confusion)
- `A\!B` → parser → `"A!B"` → no `!-` → pname `A!B`. ✓

No change to `mdl-atom` or the `#rx"!-"` regex in `core.rkt` is needed.

## Changed files

- `mdl/parser.rkt`: drop `(write-char #\\ out)` in `read-atom!` escape branch
- `tests/escaped_atom_test.rkt`: new smoke test (15 cases covering all probe scenarios)
- `tests/historical_oblist_placement_test.rkt`: remove 3 stale allowlist entries
- `scripts/test_racket.sh`: add `tests/escaped_atom_test.rkt`
- `docs/evidence/M3/I119-escaped-trailer-cases.json`: probe case definitions
- `docs/evidence/M3/I119-escaped-trailer-reference.json`: Confusion observations

## Red→green evidence

Before fix (parser retains backslash):
- `tests/escaped_atom_test.rkt` would fail: `DEAD\!!-WORDS: PNAME is DEAD!, oblist is WORDS` → actual `"DEAD\\!"`, expected `"DEAD!"`
- `tests/historical_oblist_placement_test.rkt` (make test-historical): passes only because of the 3 allowlist entries

After fix:
- `raco test tests/escaped_atom_test.rkt` → `15 tests passed` (exit 0)
- `make test-historical` → `historical OBLIST placement matches pinned Confusion (2350 entries)` (exit 0)
  - No `DEAD\!`, `IN\!`, `OUT\!` entries on `@WORDS` (removed from allowlist)
  - Stale-allowlist check passes (would fail if entries were left in)
- `bash scripts/test_racket.sh` → `3/2055 test failures` (3 from `loader_test.rkt` sandbox `/tmp` restriction, pre-existing)
- `make m3-source-progress` → `M3 source progress LOADED: 1229 completed, delta +1205, 0 skipped`
- `python3 -m pytest tests/test_harness.py` → `10 passed`

## Exact commands and exit codes

```
export PLTCOLLECTS=":$PWD" TMPDIR=$TMPDIR

# new smoke test - RED before fix, GREEN after
raco test tests/escaped_atom_test.rkt       # exit 0, 15 tests passed

# allowlist removal - would fail without fix (stale entries)
make test-historical                        # exit 0
# output: historical OBLIST placement matches pinned Confusion (2350 entries)

# full smoke (3 pre-existing sandbox /tmp failures in loader_test.rkt)
bash scripts/test_racket.sh                 # exit 1 (3/2055 failures, pre-existing)

# source load
make m3-source-progress                     # exit 0, 1229 forms, 0 skipped

# python
PYTHONPATH="$PWD/.sandbox-pydeps/lib" /usr/bin/python3 -m pytest -q tests/test_harness.py
# exit 0, 10 passed
```

## Remaining risks / unsupported cases

- **Trailing escape `\` at EOF**: the parser raises `"unterminated MDL escape"` (correct).
- **Trailing `\!` before delimiter**: writes `!` to PNAME, delimiter stops the reader.  E.g., `FOO\!>` → pname `FOO!` (the `>` is the form close). Consistent with Confusion.
- **`!-` in PNAME without escaping**: always splits (no way to create an atom literally named `A!-B` via source text; use `INSERT` with a string instead). This is MDL's design.
- **Interaction with `;` comment atom reads**: the `;` reader calls `read-node!` → `read-atom!` for comment text.  After fix, escapes in comment atoms are also stripped (irrelevant for PNAME correctness, since comment atoms are discarded).

## Proposed docs/SEMANTICS.md section

```
### Backslash escape in ATOM names (chapter 15)

`\` before any character in an atom name makes that character a literal
constituent of the PNAME: the backslash is dropped, only the escaped
character is retained.

The `!-` OBLIST trailer split is performed on the processed
(backslash-stripped) string by `mdl-atom`.  Consequently:

- `DEAD\!!-WORDS` → pname `DEAD!`, oblist `WORDS` (the `\!` contributes
  `!` to the pname; the following unescaped `!-WORDS` is the trailer).
- `A\!-B` → pname `A`, oblist `B` (the `\!` writes `!` to the buffer;
  the immediately following `-` forms a `!-` split, consuming the `!`
  as a separator, not as a pname character).
- `A\!B` → pname `A!B` (no `-` follows `!`; no split).
- `A\\B` → pname `A\B` (double backslash → single backslash).

Pinned Confusion confirms all cases (evidence M3/I119-escaped-trailer-reference.json).
Implementation: `mdl/parser.rkt` `read-atom!`, fixed in PR #119.
```
