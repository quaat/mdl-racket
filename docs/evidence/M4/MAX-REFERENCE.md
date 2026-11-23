# M4 S5a reference: the MAX SUBR

Date: 2026-11-23. Read-only reference investigation for issue #122. Pinned
mdli sha256 `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789`
before and after (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; fixed clock 250776000, TZ=UTC
(shim `scripts/reference/fixed_time.c`, sha256 `d1fa8652…b925`).

Command: `python3 -I scripts/probe_max_reference.py docs/evidence/M4/max-probe.json`
→ exit 0, 29 cases (one bare mdli process each, pipe mode, each in a fresh
empty `$TMPDIR/max-probes` directory; no game load). Record: `max-probe.json`
(sha256 `fd35efd3…8c93`), raw stdout/stderr per case (latin-1). Script sha256
`1745d191…b54`.

Manual: *The MDL Programming Language* chapter 3: §3.4 one FLOAT argument
makes the result FLOAT; §3.5 MIN/MAX take any number of FIX/FLOAT arguments,
zero-argument identities "`0`, `0`, `1`, `1`, the greatest `FLOAT`, and the
least `FLOAT`" for `+ - * / MIN MAX` (quoted in `../M3/review/R6.md`).

## The game's MAX calls (grep of the pinned `.mud` files)

| Site | Form | Arguments |
|---|---|---|
| `78melee.mud:447` BLOW, LIGHT-WOUND | `<SET DEF <MAX 0 <- .DEF 1>>>` | FIX 0, FIX (DEF DECLed FIX at `:381`) |
| `78melee.mud:448` BLOW, SERIOUS-WOUND | `<SET DEF <MAX 0 <- .DEF 2>>>` | FIX 0, FIX |
| `77rooms.mud:741` RECORD | `<ACCESS .CH <MAX 0 <- .FL 1>>>` | FIX 0, FIX; only after OPEN "PRINTO" succeeds (denied, ADR-0055) |

No zero-argument MAX and no FLOAT argument occurs in the source.

## Findings

| Case | Observation |
|---|---|
| fix-two | `<MAX 1 2>` 2, `<MAX 2 1>` 2, TYPE FIX; `<MAX 3 3>` 3 (FIX); `<MAX 0 0>` 0 |
| fix-negative | `<MAX -1 -2>` -1, `<MAX -2 -1>` -1, `<MAX -5 0>` 0, `<MAX 0 -5>` 0, `<MAX -7 -7>` -7, `<MAX -1 1>` 1 |
| fix-many | `<MAX 1 5 3>`, `<MAX 5 1 3>`, `<MAX 1 3 5>` 5; `<MAX 4 4 4 4>` 4; `<MAX -3 -9 -1 -4>` -1; `<MAX 1 … 10>` 10 |
| single | `<MAX 7>` 7 FIX; `<MAX -7>` -7; `<MAX 2.5>` 2.5000000 FLOAT; `<MAX 0>` 0 |
| mixed | `<MAX 1 2.0>`, `<MAX 2.0 1>` 2.0000000; `<MAX 3 2.0>`, `<MAX 2.0 3>` **3.0000000**; `<MAX 2 2.0>`, `<MAX 2.0 2>` 2.0000000; TYPE FLOAT in every case (contagion regardless of which operand is larger) |
| mixed-many | `<MAX 1 2 3.0>` 3.0000000; `<MAX 5 1.0 3>`, `<MAX 1.0 5 3>` 5.0000000 FLOAT; `<MAX -1 -2.5>` -1.0000000 FLOAT |
| float-float | `<MAX 1.5 2.5>`, `<MAX 2.5 1.5>` 2.5000000 FLOAT; **`<MAX -1.5 -2.5>` 0.0000000**; `<MAX 0.5 0.5>` 0.5000000; `<MAX 1.0 2.0 0.5>` 2.0000000 |
| float-negative | `<MAX -1.5 -2.5>`: TYPE FLOAT, CHTYPE FIX **4503599627370496** (host `DBL_MIN`), `G?` 0 T, `==?` `<MAX>` T; `<MAX -2.5 -1.5>`, `<MAX -1.5>`, `<MAX -1.5 -2>` 0.0000000; **`<MAX -2 -1.5>` -1.5000000**; `<CHTYPE <MAX 0.0 -1.0> FIX>` 4503599627370496 (`<CHTYPE 0.0 FIX>` 0); `<MAX -1.0 0.5>`, `<MAX 0.5 -1.0>` 0.5000000 |
| min-float-positive | `<MIN 1.5 2.5>`, `<MIN 2.5 1.5>` 1.5000000; `<MIN -1.5 -2.5>` -2.5000000; `<MIN 1.5>` 1.5000000 (MIN has no such defect) |
| min-mixed-compare | `<MIN 1 2.0>` 1.0000000 FLOAT; `<MIN 3 2.0>` 2.0000000; `<MIN 2 2.0>` 2.0000000 FLOAT |
| fix-36bit-boundaries | `<MAX 34359738367 0>`, `<MAX 0 34359738367>` 34359738367; `<MAX -34359738368 0>` 0; `<MAX -34359738368 -34359738367>` -34359738367; `<MAX 34359738367 -34359738368>` 34359738367; equal 2^35−1 operands 34359738367; **`<MAX 34359738368 0>` 34359738368** (64-bit host FIX); `<MAX -34359738369 0>` 0 |
| zero | `<TYPE <MAX>>` FLOAT; `<CHTYPE <MAX> FIX>` **4503599627370496** (= 0x0010000000000000, host `DBL_MIN`); `<G? <MAX> 0>` T; `<L? <MAX> 0>` FALSE; `<0? <MAX>>` FALSE; `<==? <MAX> 0.0>` FALSE; `<MAX <MAX> -1>` **0.0000000**; `<MAX <MAX> 1>` 1.0000000; `<L? <MAX> <MIN>>` T; `<CHTYPE <MIN> FIX>` 9218868437227405311 (`DBL_MAX`, as in R6) |
| zero-print | `<MAX>` prints `0.0000000` (no crash, unlike `<MIN>` in R6) |
| err-string, err-string-first, err-atom, err-quoted-atom, err-list, err-false, err-character, err-single-atom | stderr **`Arguments to MAX must be FIX OR FLOAT`**, back at LISTENING-AT-LEVEL 1 (no ERROR frame); same for a single non-number `<MAX 'A>` and for STRING first |
| err-min-string | `<MIN 1 "A">`: `Arguments to MIN must be FIX OR FLOAT` |
| melee-def-neg3 / 0 / 1 / 2 / 3 / 5 | `<MAX 0 <- .DEF 1>>` / `<MAX 0 <- .DEF 2>>`: DEF −3 → 0 / 0; 0 → 0 / 0; 1 → 0 / 0; 2 → 1 / 0; 3 → 2 / 1; 5 → 4 / 3; TYPE FIX; `<SET DEF <MAX …>>` returns and stores the same value |
| record-access-shape | `<MAX 0 <- .FL 1>>` with FL 0 → 0, 1 → 0, 100 → 99 |

## Summary for the specification

* MAX returns the largest argument; all-FIX gives FIX; any FLOAT makes the
  result FLOAT whichever operand wins (same contagion as MIN and `+`).
  Equal operands and negatives behave normally for FIX.
* A non-number in any position (including a single argument) is refused:
  `Arguments to MAX must be FIX OR FLOAT`.
* The game's three uses are two-argument FIX and behave as `max(0, n)`.
* **Zero arguments:** the reference returns host `DBL_MIN`, the smallest
  *positive* double (it prints as `0.0000000`). That is not the "least
  FLOAT" in the sense of an identity: it is greater than every negative
  number (`<MAX <MAX> -1>` is ~0, not -1).
* **Reference defect, consequence of the same seed:** when the first
  argument is FLOAT the reference folds from `DBL_MIN`, so an all-negative
  FLOAT MAX (`<MAX -1.5 -2.5>`, `<MAX -1.5>`, `<MAX -1.5 -2>`) returns
  `DBL_MIN`; a FIX first argument (`<MAX -2 -1.5>`) gives the right answer.
  MIN's `DBL_MAX` seed is a true identity, so MIN has no such defect.
* For comparison, R6 decided `<MIN>` = the greatest PDP-10 FLOAT
  (2^27−1)·2^100 instead of the reference's `DBL_MAX` (SEMANTICS "M3 MIN").
  The MAX decision is ADR-0059 (SEMANTICS "M4 S5a: MAX").
* FIX range: the reference's FIX is 64-bit; the runtime's 36-bit FIX and
  reader rule (out-of-range literal → FLOAT) are the existing M1 decisions.
