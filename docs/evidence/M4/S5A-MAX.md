# M4 S5a: the MAX SUBR (issue #122)

Date: 2026-11-23. Branch `feat/m4-max` at `main` adbe41059524a48a692376d051bf79d0c9e7fe75
(uncommitted working tree; the orchestrator commits). Upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3` (unchanged). Pinned mdli sha256
`6df359f6…b789` before and after the probes. Racket v7.9 [bc],
`PLTCOLLECTS=":$PWD"`.

Gate label for this slice: **PASS** (language slice; no game scenario,
since combat needs the sword, frontier F4, a separate slice).

## Scope

MAX is used by BLOW's wound recovery (`78melee.mud:447-448`) and RECORD's
PRINTO branch (`77rooms.mud:741`, unreachable under ADR-0055), both with
two FIX arguments. Before this slice `<MAX 1 2>` failed with
`mdl-eval: unassigned or non-applicable MDL operator MAX`.

## Reference

[MAX-REFERENCE.md](MAX-REFERENCE.md), `max-probe.json`,
`scripts/probe_max_reference.py` (29 cases, exit 0). Key facts: FIX/FLOAT
contagion exactly as MIN; `Arguments to MAX must be FIX OR FLOAT` for any
non-number; game expressions give `max(0, DEF-n)` as FIX; `<MAX>` is host
`DBL_MIN` (prints `0.0000000`), which also leaks into all-negative FLOAT
results when the first argument is FLOAT (`<MAX -1.5 -2.5>` → `0.0000000`).

## Semantics and decision

SEMANTICS "M4 S5a: MAX (issue #122; ADR-0059)", written before the
implementation. ADR-0059 (status *proposed*, needs orchestrator
acceptance): `<MAX>` is −(2^27−1)·2^100, the least PDP-10 FLOAT and the
exact negation of R6's `<MIN>`; CHTYPE FIX image 400000000001₈ =
−34359738367. Chosen because R6 already decided MIN's identity from the
same manual sentence; the reference's DBL_MIN is neither the 36-bit target
nor an identity for MAX. A strict error was the alternative (recorded in the
ADR). Recorded deviations: `<MAX>` itself, all-negative FLOAT MAX with a
FLOAT first argument, and the reference's 64-bit FIX (existing M1 rule).

## Implementation

`mdl/runtime/core.rkt`: `pdp10-least-float` and `mdl-max`, the mirror of
`mdl-min` (shared `check-number`, fold from the first argument, FLOAT
contagion), registered as `"MAX"` in the builtin table; `mdl-max` is
provided so a test can pass a host integer outside the FIX range (no MDL
literal can: the reader makes it FLOAT). No game-specific path.

## Tests

`tests/max_test.rkt` (registered in `scripts/test_racket.sh` after
`min_test.rkt`): 96 isolated checks: two-FIX both orders/equal/negatives,
three or more arguments, single argument, contagion (both orders, equal
FIX/FLOAT, three arguments), FLOAT/FLOAT including the all-negative cases,
36-bit boundaries and host FIX overflow, zero arguments (value, TYPE,
identity, comparisons, WORD/FIX image), nine refusals, the game's own
`78melee.mud:447-448` COND for DEF −3, 0, 1, 2, 3, 5 under LIGHT-WOUND and
SERIOUS-WOUND, and the `77rooms.mud:741` argument shape.

| Command | Result |
|---|---|
| `raco make tests/max_test.rkt && raco test tests/max_test.rkt` before `mdl-max` (red) | exit 1, **96/96 test failures** (85 `non-applicable MDL operator MAX`, 9 refusal checks "Wrong exception raised", 2 host-overflow checks `dynamic-require: name is not provided`) |
| same, after (green) | exit 0, **96 tests passed** |
| `raco test tests/max_test.rkt tests/min_test.rkt` | exit 0, 144 tests passed (MIN unchanged) |
| `bash scripts/test_racket.sh` (sandboxed) | exit 1, **3/4022 test failures**, exactly the known sandbox artefacts: `loader_test.rkt`, `declaration_test.rkt`, `percent_read_test.rkt` (`make-directory: /tmp/...: Read-only file system`); no other FAILURE/ERROR line in the full output |
| `make test-m4-top-parser` | exit 0, all 11 prefix runs match the reference (D1 only) |
| `make test-m4-orphan-prompt` | exit 0, all 10 prefix runs match the reference (D1 only) |
| `make test-m3-interactive` | exit 0, 31 tests passed |

## Mutation check

Each mutant was applied to `mdl-max` alone, `raco make` + `raco test
tests/max_test.rkt` run, and the file restored from a byte copy.

| Mutant | Result |
|---|---|
| M1 MAX returns MIN (`max` → `min`) | exit 1, 48/96 failures |
| M2 no FLOAT contagion (`(if (> value largest) value largest)`) | exit 1, 12/96 |
| M3a no argument checks (both `check-number` calls removed) | exit 1, 11/96 |
| M3b non-numbers silently skipped (`(if (real? value) (max …) largest)`) | exit 1, 8/96 |
| M4a magnitude comparison (`abs`), wrong on negatives | exit 1, 24/96 |
| M4b fold seeded with 0 (the reference's defect, FIX analogue) | exit 1, 15/96 |
| M4c wrong result on equal operands (tie → value+1) | exit 1, 12/96 |
| M5 zero arguments return `0.0` (reference sentinel) | exit 1, 7/96 |
| M2b drop only the explicit `exact->inexact` | exit 0, 96 passed: **equivalent mutant**, Racket's `max` already returns an inexact result when any argument is inexact; the explicit branch is kept for symmetry with `mdl-min` |

## Security and licensing

No new I/O, no evaluator exposure. Confusion used only as a behaviour
reference; no Confusion source copied.

## Open risks / not covered

* ADR-0059 is a decision against the reference for an unused form; it
  needs acceptance.
* Negative zero (`<MAX 0 -0.0>`), PDP-10 FLOAT range/rounding and FLOAT
  printing remain out of scope, as for MIN.
* The game path (BLOW during troll combat) is not exercised end-to-end;
  that needs the sword (frontier F4) and is a separate slice.
* README's "Not supported yet" list (still naming MAX and TOP) is left for
  the orchestrator's milestone README update.
