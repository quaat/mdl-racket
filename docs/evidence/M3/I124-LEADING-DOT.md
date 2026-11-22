# I124 — Leading-dot FLOAT literals (`.5` read as LVAL of atom `5`)

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
| `'. 5`            | `.5` (unparse of LVAL 5)                  | LVAL of atom 5     |
| `..5`             | ERROR Type Mismatch: LVAL arg must be atom| LVAL of float 0.5  |
| `'(.5)`           | `(0.5000000)`                             | FLOAT in list      |
| `<+ .5 1>`        | `1.5000000`                               | arithmetic FLOAT   |
| `<FIX <+ .5 0>>`  | `0`                                       | FIX of 0.5 = 0     |

**Key discriminator:** `.5A` → LVAL of atom `5A` (not FLOAT).  Confusion
reads the full atom name after `.` and only treats it as a leading-dot float
if the name consists entirely of float-numeral characters (`[0-9]+(.[0-9]*)?([Ee][+-]?[0-9]+)?`).

Note: `-.5` is an ATOM in Confusion, not a FLOAT.  The `-` triggers
the else/atom branch in the reader, and `-` followed by `.` (not a digit)
does not start a signed number.  Our existing compiler correctly leaves
`"-.5"` as an atom-ref, so no change needed there.

## Design decision

**Parser**: in the `#\.` case, after reading `name` via `read-atom!`, check
whether `name` matches `^[0-9]+(\.[0-9]*)?([Ee][+-]?[0-9]+)?$`.  If so,
emit `(node 'atom (string-append "." name))` so the compiler can classify it.
Otherwise emit `(node 'local name)` as before.

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
53 tests passed   (was 41; +12 new I124 assertions)

make test (outside sandbox):
2204 tests passed   (Racket) + 23 passed (Python)

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
- `. 5` (space between `.` and `5`) — Confusion treats as LVAL of atom `5`;
  our reader raises "empty local reference".  Not present in the game source.
  Separate issue if ever needed.

## Proposed docs/SEMANTICS.md section

```markdown
### Leading-dot FLOAT literals (I124)

MDL allows FLOAT literals that begin with a decimal point: `.5` = 0.5,
`.05` = 0.05.  The reader identifies a leading-dot FLOAT by the following
rule:

1. Consume the `.`.
2. Read the atom name until the next delimiter → `name`.
3. If `name` matches `^[0-9]+(\.[0-9]*)?([Ee][+-]?[0-9]+)?$` (all float-
   numeral characters), the token is a FLOAT: value = `.` + `name`.
4. Otherwise the token is an LVAL reference to atom `name`.

Consequence: `.5A` is LVAL of atom `"5A"`, not FLOAT 0.5 (Confusion-
confirmed).  `-.5` is an ATOM named `"-.5"`, not a negative FLOAT (Confusion-
confirmed; the `-` prefix only introduces a signed number when followed
immediately by a digit).

Scientific notation with a leading dot (`.5E1`) maps to Racket's
`string->number` correctly (= 5.0) but is currently marked `unsupported`
consistent with the existing policy for `1E2`.  It does not appear in the
pinned 1977 game source.
```
