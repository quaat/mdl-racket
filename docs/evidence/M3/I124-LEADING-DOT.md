# I124 — Leading-dot FLOAT literals (`.5` read as LVAL of atom `5`)

> **Reconciliation note (2026-11-23).** Consolidated into [SEMANTICS §M3 reader: leading-dot FLOAT vs LVAL (issue #124)](../../SEMANTICS.md). Fixed by PR #133, merged into the umbrella `feat/m3-logical-gc` and every stack branch; not integrated into `main` (issue #124 stays open until then).

## Finding

`78melee.mud:369` contains `<FIX <+ .5 …>>` where `.5` is the MDL FLOAT `0.5`.
Before this fix our reader produced `(node 'local "5")` — LVAL of atom `5` —
causing an unbound-variable error at runtime and interning a spurious atom `5`
on the INITIAL oblist.  Confusion reads `.5` as `FLOAT 0.5` (no atom `5`
after `<FLOAD "77loadall.mud">`).

## Reproduction (pre-fix)

```
$ racket -e '(require "mdl/parser.rkt") (parse-mdl ".5")'
((local 5))   ; LVAL of atom "5", not FLOAT 0.5
```

The historical_oblist_placement_test allowlisted `(runtime-only "INITIAL" "5")`
as a known deviation; removing the entry before the fix would have produced:

```
MISMATCH runtime-only INITIAL "5"
placement "1 OBLIST placement mismatches against pinned Confusion"
```

## Root cause

`mdl/parser.rkt` lines 148–152 (pre-fix): when the reader sees `.`, it
unconditionally reads the next atom-name and emits `(node 'local name)`.
For `.5` the atom-name is `"5"` → LVAL of atom `5`.

## MDL manual contract (ch. 7)

A FLOAT literal may begin with `.` when the period is immediately followed by
one or more digits: `.D2` is equivalent to `0.D2`.  Examples: `.5` = 0.5,
`.05` = 0.05.  With an exponent: `.5E1` = 5.0.  A period followed by a
non-digit starts an LVAL.

> Source: MDL Language Manual, chapter 7 "Numbers and Floats".
> (Fetched from mdl-language.readthedocs.io — network unavailable during this
> session; citation is from memory, confirmed by Confusion probe below.)

## Confusion probe evidence

Probe file: `scratchpad/i124-probe-cases.json`
Result file: `scratchpad/i124-probe-results.json`
Interpreter SHA256: `6df359f6…` (pinned build from bdcd4a67)

| Expression        | Confusion output                          | Conclusion         |
|-------------------|-------------------------------------------|--------------------|
| `<TYPE .5>`       | `FLOAT`                                   | FLOAT              |
| `.5`              | `0.5000000`                               | FLOAT 0.5          |
| `<TYPE '.5>`      | `FLOAT`                                   | FLOAT in quoted    |
| `-.5`             | `\-.5` (atom unparse)                     | ATOM `-.5`         |
| `.5E1`            | `5.0000000`                               | FLOAT 5.0          |
| `.05`             | `0.0500000`                               | FLOAT 0.05         |
| `1.`              | `1`                                       | FIX 1              |
| `1.5`             | `1.5000000`                               | FLOAT 1.5          |
| `<TYPE .A>`       | ERROR UNBOUND-VARIABLE LVAL A             | LVAL of atom A     |
| `<TYPE .5A>`      | ERROR UNBOUND-VARIABLE LVAL **5A**        | LVAL of atom `5A`  |
| `'. 5`            | `.5` (unparse: LVAL of FIX 5)             | LVAL of FIX 5 (type error on eval) |
| `..5`             | ERROR Type Mismatch: LVAL arg must be atom| LVAL of FLOAT 0.5 → type error |
| `'(.5)`           | `(0.5000000)`                             | FLOAT in list      |
| `<+ .5 1>`        | `1.5000000`                               | arithmetic FLOAT   |
| `<FIX <+ .5 0>>`  | `0`                                       | FIX of 0.5 = 0     |

**Key discriminator:** `.5A` → LVAL of atom `5A` (not FLOAT).  Confusion
reads the full atom-name after `.` and only treats it as a leading-dot FLOAT
if the suffix consists entirely of digits plus optional exponent
(`^[0-9]+([Ee][+-]?[0-9]+)?$`).  An embedded decimal in the suffix (`.5.`,
`.5.5`) produces LVAL of atom `"5."` / `"5.5"` — NOT a FLOAT.

Note on `..5`: Confusion evaluates `..5` as LVAL of FLOAT 0.5 → type mismatch
("1st arg to LVAL must be atom").  After the first `.`, Confusion's reader
sees the second `.5` as a leading-dot FLOAT literal, then tries to take its
LVAL.  Our reader raises a strict parse error at this point.

Note on `. 5`: Confusion prints `.5` for `'. 5`, meaning it parsed `. 5` as
"LVAL of FIX 5" (the space is skipped by Confusion's atom reader, leaving `5`
as the LVAL argument — which is a FIX, not an ATOM, causing a type mismatch
when evaluated).  Our reader raises "empty local reference" (strict parse
error), which is acceptable.

Note: `-.5` is an ATOM in Confusion, not a FLOAT.  The `-` triggers
the else/atom branch in the reader, and `-` followed by `.` (not a digit)
does not start a signed number.  Our existing compiler correctly leaves
`"-.5"` as an atom-ref, so no change needed there.

## Design decision

**Parser**: in the `#\.` case, after reading `name` via `read-atom!`:
1. If `name` starts with `.`, raise a strict reader error (`..X` not supported).
2. If `name` matches `^[0-9]+([Ee][+-]?[0-9]+)?$` (no embedded decimal —
   the `(\.[0-9]*)?` group is intentionally absent; `.5.`/`.5.5` are LVALs),
   emit `(node 'atom (string-append "." name))` for the compiler to classify.
3. Otherwise emit `(node 'local name)` as before.

**Compiler `mdl-constant/plain`**: add `^\.[0-9]+$` → `(string->number val)`
(Racket's `string->number` correctly handles `".5"` → `0.5`).  Add
`^\.[0-9]+[Ee][+-]?[0-9]+$` → `unsupported` (consistent with existing
treatment of scientific notation; not needed by the game source).

**Compiler `atom-node-constant-token?`**: add `^\.[0-9]` so that leading-dot
float atom values are not misclassified as atom names (e.g., in PROG labels).

## Changed files

- `mdl/parser.rkt` — `#\.` case: detect leading-dot FLOAT
- `mdl/compiler.rkt` — `atom-node-constant-token?` and `mdl-constant/plain`
- `tests/parser_test.rkt` — 12 new assertions for I124 cases
- `tests/historical_oblist_placement_test.rkt` — remove stale allowlist entry for `"5"`

## Red → green evidence

**Before fix:**
```
$ racket -e '(require "mdl/parser.rkt") (parse-mdl ".5")'
; → (local "5")  ← LVAL, not FLOAT
```
historical_oblist_placement_test: allowlist entry `(runtime-only "INITIAL" "5")`
would become a MISMATCH without the allowlist.

**After fix:**
```
$ racket -e '(require "mdl/parser.rkt") (parse-mdl ".5")'
; → (atom ".5")  ← correct
$ racket … (run ".5") → 0.5  (FLOAT)
$ racket … (run "<FIX <+ .5 0>>") → 0  (matches Confusion)
```

```
raco test tests/parser_test.rkt tests/compiler_test.rkt
58 tests passed   (was 41; +17 new I124 assertions incl. review fixes)

make test (outside sandbox):
2209 tests passed   (Racket) + 23 passed (Python)

make m3-source-progress:
M3 source progress LOADED: 1229 completed, delta +1205, 0 skipped

racket tests/historical_oblist_placement_test.rkt:
historical OBLIST placement matches pinned Confusion (2350 entries)
   [no MISMATCH lines; "5" allowlist entry removed]
```

Smoke suite (`bash scripts/test_racket.sh`): 3 failures on `loader_test.rkt`,
`declaration_test.rkt`, `percent_read_test.rkt` — all "Read-only file system
errno=30" sandbox artifacts that pass outside the sandbox (confirmed).

## Remaining risks / unsupported cases

- `.5E1` (scientific notation with leading dot) — left as `unsupported` per
  the existing policy for scientific notation.  Does not appear in the pinned
  game source.
- `-.5` — remains an ATOM; Confusion confirms.  Not needed by the game source.
- `. 5` (space between `.` and digit) — Confusion evaluates as LVAL of FIX 5
  (type error on eval); our reader raises "empty local reference" (strict parse
  error), which is acceptable.  Not present in the game source.
- `..5` — Confusion evaluates as LVAL of FLOAT 0.5 → type mismatch; our reader
  raises a strict parse error.  Not present in the game source.
- `.5.` / `.5.5` — Confusion: LVAL of atom `"5."` / `"5.5"` (UNBOUND-VARIABLE);
  our reader: same (LVAL of atom `"5."` / `"5.5"`).  Correct.  Not in game source.

## Proposed docs/SEMANTICS.md section

Merged directly into `docs/SEMANTICS.md` as section
"M3 reader: leading-dot FLOAT vs LVAL (issue #124)".
See that file for the authoritative contract text.
