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

**Key deviation:** Confusion ignores the optional `radix` argument and always prints
decimal. That is a reference deviation from the manual, not behaviour to copy. The
runtime **rejects** any radix other than 10 with an explicit "not implemented" error
instead of silently returning a decimal string (AGENTS.md strict-failure rule). The game
never supplies a radix.

---

## Final behaviour (after independent review rounds; PR #125)

Implementation history:
- `04e3004`: first implementation.
- `e854766` (round 1): strict radix and escape rules.
- `30cec5d` (round 2): ATOM whitelist and reachability; control characters.
- `c09bb02`: ASCII-only whitelist.
- Propagation merge onto the #107 remediation: reachability via the #118 search path.

Exact against pinned Confusion, otherwise a strict error:

- **FIX:** decimal, including the 36-bit extremes 34359738367 / -34359738368. The radix
  must be omitted or 10. Any other FIX in 2–36 raises "UNPARSE: non-decimal radix N not
  implemented". A non-FIX or out-of-range radix also raises an error.
- **ATOM:** the bare PNAME, only when both hold:
  - (a) the PNAME is non-empty, consists only of ASCII `[A-Za-z0-9-]`, and does not
    parse as a number;
  - (b) looking the PNAME up on the **current** OBLIST search path finds this exact atom
    (`eq?`).

  The current path is #118's single authority `current-lookup-path`, i.e. the LVAL of
  ROOT OBLIST including PROG/AUX/formal bindings and BLOCK, not the session's default
  path. Otherwise a strict error is raised. Confusion escapes `!`, `.`, `#`, `%`, `<`, `>`
  and prints `!-oblist` trailers for unreachable atoms; neither is implemented.
- **STRING:** double-quoted, with `\"` and `\\`. Content with control characters
  (codes 0–31, 127) raises a strict error; Confusion prints `^A` notation.
- **CHARACTER:** `!\c`. Control codes 0–31 and 127 raise a strict error.
- **FALSE:** `#FALSE ()` or `#FALSE (elem …)`.
- **LIST:** `(elem …)`, recursive.
- **FLOAT, VECTOR, UVECTOR, WORD, FORM and other types:** strict unsupported error.

Manual §7.6.6.4: the result is the character sequence PRINT would output, with no
line-width breaks. It is always a fresh mutable STRING.

## Tests (final)

- `tests/unparse_test.rkt`: **44 checks** covering interpreted, compiled and APPLY
  paths. These include:
  - the radix strict errors;
  - ASCII-only and number-like PNAME rejection;
  - unreachable-atom rejection;
  - an atom unreachable under a PROG-bound OBLIST of `(<ROOT>)`, which failed with the
    stale default-path accessor and now raises the strict trailer error;
  - control-character rejection.
- `tests/historical_saveit_test.rkt` (`make test-m3-saveit`, run via `raco test`):
  asserts the 1,229-form load and the next faithful SAVE-IT frontier as a known XFAIL.
  The frontier is now advanced by later slices (MEMQ → SUBSTRUC). It is not an
  INITIALIZED claim.

## Remaining risks / unsupported cases

1. Radix other than 10, ATOM escaping and trailers, control-character `^` notation, and
   FLOAT/VECTOR/UVECTOR/WORD/FORM printing are all strict errors. None is used by the
   game's single UNPARSE call (77rooms.mud:164, a day-of-month FIX).

## Proposed docs/SEMANTICS.md section

```markdown
### UNPARSE (manual 7.6.6.4)
`<UNPARSE any radix:fix>` returns a fresh mutable STRING with the characters PRINT
would output, without line-width breaks.
Implemented exactly (pinned Confusion probes):
- FIX in decimal;
- STRING (quoted; `\"`, `\\`);
- CHARACTER (`!\c`);
- FALSE;
- LIST;
- plain ATOMs: an ASCII `[A-Za-z0-9-]` non-numeric PNAME that is reachable as the same
  atom on the current OBLIST search path (LVAL of ROOT OBLIST).
Strict errors:
- a radix other than 10. Confusion ignores the radix: a documented reference deviation,
  not copied.
- ATOMs needing escaping or a trailer;
- control characters in STRING/CHARACTER;
- FLOAT, VECTOR, UVECTOR, WORD, FORM and other types.
Source use: 77rooms.mud:164 only (a day-of-month FIX).
```
