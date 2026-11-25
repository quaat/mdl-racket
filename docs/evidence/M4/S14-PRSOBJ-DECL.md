# M4 S14: still-undefined attached TYPE names (#193, INV-11) and the dam scenarios

Date: 2026-11-25. Branch `feat/m4-prsobj-decl` from `main` `69f3334`.
Issue #193 (INV-11). Gate label: **PASS (local branch, not merged;
scenario-scoped)** for the declaration amendment and the two promoted
scenarios. Not a PLAYABLE, GAMEPLAY_RELIABILITY or M4 claim.

## Maintainer decision (#193, 2026-11-25)

"Amend the deferred-declaration ADR: a type name in an attached declaration
that is still undefined when checked is not enforced, matching Confusion.
This is a recorded deviation from the manual's strict reading, limited to
undefined type names; known types stay strict. No source change. Then
promote the dam scenarios to gated tests."

Recorded as the amendment under "ADR: Defer unresolved TYPE atoms in
attached declarations (M3 issue #98)" in [DECISIONS.md](../../DECISIONS.md)
and specified in [SEMANTICS.md](../../SEMANTICS.md) ("Amendment:
still-undefined attached TYPE names are not enforced").

## Provenance

| Item | Value |
|---|---|
| Upstream game | `mdlzork` bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3, `mit_zork` d94501340842e006791fce0757dc0043b8ec8916 (`sources.lock.json`); `mdlzork_771212/patched_confusion`, unmodified |
| Pinned reference | `.cache/build/confusion_patched/mdli` sha256 `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` (checked); no native run in this slice; the committed references `dam-sluice-reference.json` and `maint-leak-reference.json` are used unchanged (captured twice, byte-identical transcripts, [DAM-CLOCKS.md](DAM-CLOCKS.md)) |
| Clock / RNG | fixed epoch 250776000, TZ UTC; START seeds RANDOM from DSKDATE (10438660480); no RANDOM override |
| Ours | Racket v7.9 [bc]; `PLTCOLLECTS=":$PWD" TMPDIR=/tmp`, outside the tool sandbox |
| Upstream source | **not changed**; PRSOBJ stays undefined |

## Semantics implemented

`mdl/runtime/core.rkt`, `decl-match`, case `(unresolved)` (a TYPE ATOM an
attached `#DECL` retained under #98):

* still no registered TYPE and no `DECL` association at this check →
  matches (any value, at that Pattern position only);
* otherwise → normalized strictly and matched, as before (a late NEWTYPE is
  that TYPE; a late `DECL` association is its Pattern, whose own unknown
  names, cycles and malformed forms still raise).

`decl-failure-leaf` gains the `(unresolved)` case (the name ATOM). Without
it, a nested name defined later that then *fails* (for example
`<LIST [REST FUTURE]>` after `<NEWTYPE FUTURE VECTOR>`, called with `(1)`)
raised the internal `unknown normalized declaration pattern` instead of
`X does not satisfy declaration`. This was latent since #98 and surfaced by
the new nested late-definition tests; the check failed before as well, only
with the wrong message. Attached checks never report the leaf.

Unchanged and strict: explicit `DECL?`, positional (`"VALUE"`)
declarations, GDECL (at SETG and against an existing value), CHTYPE's
NEWTYPE declaration check, every known type, and every error message on
those paths.

**Recorded deviation.** The manual checks every attached declaration; this
runtime leaves a position whose TYPE name is undefined when checked
unchecked. Pinned Confusion checks no attached declaration at all, so the
runtime still differs from it on known types (it checks them).

## Tests (failing first)

`tests/deferred_decl_type_test.rkt` (49 checks; unexpected exceptions are
turned into a failing actual value so that one run counts every failing
check) and one changed check in `tests/declaration_test.rkt`
(`#DECL ((X) UNKNOWN-TYPE)` called with 1 now returns 1). Commit `0b56eb0`
(tests and docs, before the runtime change):

| Command | Exit | Result |
|---|---|---|
| `raco test tests/deferred_decl_type_test.rkt` | 1 | 25/49 test failures (`unknown declaration type PRSOBJ` / `FUTURE` raised at the call, or "Wrong exception raised") |
| `raco test tests/declaration_test.rkt` | 1 | raised `unknown declaration type UNKNOWN-TYPE` at the changed check |

After `e923425` (runtime change):

| Command | Exit | Result |
|---|---|---|
| `raco test tests/deferred_decl_type_test.rkt` | 0 | 49 tests passed |
| `raco test tests/declaration_test.rkt` | 0 | 56 tests passed |

The intermediate run with only the `(unresolved)` change (no
`decl-failure-leaf` case) had 3/49 failures, lines 94, 96, 107: the nested
late-definition failures raising `unknown normalized declaration pattern`.

Covered: undefined names accepting FIX, FALSE, an ATOM, a STRING and an
OBJECT-like NEWTYPE value; MAINT-ROOM's shape (AUX PRSO from a vector, a
known-type `(PV) VECTOR` still enforced); SET and VALUE; nested in OR,
`<VECTOR ...>`, `<LIST UNDEF FIX>` (FIX element, structure TYPE and length
still strict), `[REST ...]` and NTH; late NEWTYPE (wrong FIX and FALSE
fail, right value passes; the same function before and after the NEWTYPE;
nested); late DECL association (`'FIX`, `'<OR FIX FALSE>`, nested; an
association to an unknown name stays an error); `DECL?` alone and in OR;
positional declarations; GDECL at SETG and against an existing value;
known types (FIX, `<OR FALSE FIX>`, `<OR FALSE OBJECT>`, VALUE FIX).

## The dam scenarios

dam-sluice (41 commands) and maint-leak (35 commands) are gated by
`tests/historical_dam_sluice_test.rkt` (`make test-m4-dam-sluice`) and
`tests/historical_maint_leak_test.rkt` (`make test-m4-maint-leak`) through
`run-m4-scenario` with the "dam" checkpoint and
`#:eof-classification-ignore-keys '(robber_hroom)`. The committed native
references are used as they are (no re-capture). The retired XFAIL's
native key-turn assertions (the bolt refused, the yellow button, the gates,
the trunk, the score; MNTIN's CTICK and RVARS by turn, the ten level
messages, the putty) moved into them, plus per-turn transcript checks past
the Maintenance Room entry.

## Results

Run with `PLTCOLLECTS=":$PWD" TMPDIR=/tmp PYTHONPATH=$PWD/.sandbox-pydeps/lib`,
`PYTHON=/usr/bin/python3`, outside the tool sandbox, one job at a time.

| Command | Exit | Result |
|---|---|---|
| `racket tests/historical_dam_sluice_test.rkt` (single-run) | 0 | all 42 turns match the reference (D1 only); 1 boot; 41 of 41 shorter prefixes standard; 6.1 s |
| `racket tests/historical_maint_leak_test.rkt` (single-run) | 0 | all 36 turns match; 1 boot; 35 of 35 shorter prefixes standard; 5.8 s |
| `M4_SCENARIO_MODE=per-prefix make test-m4-dam-sluice` | 0 | all 42 turns match; 42 boots, 252.5 s |
| `M4_SCENARIO_MODE=per-prefix make test-m4-maint-leak` | 0 | all 36 turns match; 36 boots, 208.2 s |
| `make test PYTHON=/usr/bin/python3` | 0 | 4968 Racket tests passed; Python 104 passed, 1 deselected; 101 s |
| `make test-historical` | 0 | 15 s |
| `make m3-check` | 0 | overall PASS; 23 s |
| `make m4-check PYTHON=/usr/bin/python3` | 0 | 555 s; see below |
| `git diff --check 69f3334` | 0 | |

No divergence was found at any turn after the fix, so no new frontier
finding is recorded.

## make m4-check

Manifest completeness PASS; `sources` and all twenty-two scenario targets
PASS (the new ones: dam-sluice 5.8 s, maint-leak 5.8 s),
`test-m4-replay-persistence` PASS, `test-m3-session` and `test-m3-launcher`
PASS; 555 s at `6d3eed8` (dirty: documentation only).

| Term | Status | Scope / reasons |
|---|---|---|
| SCENARIO_PARITY | PASS | 22 scenarios, each under one fixed clock and seed (250776000, UTC); per scenario, not gameplay coverage |
| GAMEPLAY_RELIABILITY | NOT YET | 18 of 23 required branches covered (unchanged: maint-leak adds a second check to an already covered branch); uncovered: combat.thief, objects.puzzles-beyond-the-house, save.game-save-command, save.game-restore-command, save.player-facing-resume; open blockers INV-06, INV-07 (INV-11 no longer blocking) |
| PLAYABLE | NOT RUN | sub-checks only; no PLAYABLE gate |
| FULL_COMPLETION | NOT RUN | no complete-game check |
| M4_ACCEPTED | NOT YET | R2–R5 unmet |

A local branch result, not a mainline acceptance.

## Mutation checks (each reverted with `git checkout mdl/runtime/core.rkt`; `git status` clean of code changes afterwards)

| # | Mutation of `decl-match`'s `(unresolved)` case | Result |
|---|---|---|
| M1 | revert the #193 branch (the #98 call-time rule; the `decl-failure-leaf` case kept) | `historical_dam_sluice_test.rkt` exit 1 and `historical_maint_leak_test.rkt` exit 1: `earliest failing k = 23, kind run-guard`, `unknown declaration type PRSOBJ`; `deferred_decl_type_test.rkt` 22/49 failures |
| M2 | an undefined name matches only FALSE (`(mdl-false? value)` for `#t`) | `deferred_decl_type_test.rkt` exit 1, 14/49 failures (lines 36, 38, 39, 41, 52, 56, 57, 63, 64, 72, 73, 76, 89, 137) |
| M3 | a later NEWTYPE does not define the name (only a DECL association counts) | `deferred_decl_type_test.rkt` exit 1, 6/49 failures (lines 82, 84, 87, 91, 94, 96: the late-NEWTYPE checks) |

## Coverage and records

* `gameplay-branches.json`: `timers.other-clock-events` cites
  `test-m4-match-clock` and `test-m4-maint-leak` (MATIN and MNTIN);
  `objects.puzzles-beyond-the-house` stays UNCOVERED, with the boat and the
  dam as exercised evidence (`evidence_only`: test-m4-boat-river,
  test-m4-dam-sluice) and the balloon, the coal-mine machine and basket and
  the gas room unexercised; INV-11 moved to `resolved_inventory`.
* Manifest: S14a dam-sluice, S14b maint-leak (no longer in
  `excluded_scenario_files`); Makefile `test-m4-dam-sluice`,
  `test-m4-maint-leak`, `M4_SCENARIO_TESTS`; `xfail-m4-dam-frontier` and
  `tests/historical_dam_frontier_test.rkt` removed.
* [GAMEPLAY-FAILURE-INVENTORY.md](GAMEPLAY-FAILURE-INVENTORY.md) INV-11
  marked fixed; [DAM-CLOCKS.md](DAM-CLOCKS.md) carries an update note;
  TESTING, STATUS and README updated.

## Security and licensing

One runtime rule relaxed for one narrowly defined case (an undefined name in
an attached declaration); no new file, network or evaluator access. No
upstream file changed; mdli not rebuilt; no native run. No Confusion code
copied; new tests are original MIT-0 code.

## Open risks

* A misspelled type name in an attached declaration is no longer reported
  at call time (still reported by `DECL?`, positional declarations, GDECL).
  The sources' only undefined attached name is PRSOBJ (MAINT-ROOM,
  WIRE-FUNCTION, GNOME-FUNCTION); a later independent sweep could list
  every attached TYPE name that stays undefined after load.
* The undefined check is repeated at every attached check (an `eq?` hash
  lookup and an association lookup); no measurable scenario slowdown.
* WIRE-FUNCTION and GNOME-FUNCTION are now unchecked for PRSO/PRSI as well,
  but not run by any scenario.
* Each scenario is one fixed clock and seed.

## Next actionable task

Independent review of the `decl-match` change and its invariants
(declarations are in AGENTS.md's mandatory-review list), then merge; next
the remaining uncovered branches (`make m4-check`).
