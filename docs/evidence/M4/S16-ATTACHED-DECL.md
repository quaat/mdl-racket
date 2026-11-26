# M4 S16: attached declarations are not enforced (#196, INV-12) and the balloon scenario

Date: 2026-11-26. Branch `feat/m4-attached-decl-unenforced` from `main`
`8c398fe`. Issue #196 (INV-12; to be closed by the PR). Gate label:
**PASS (local branch, not merged; scenario-scoped)** for the declaration amendment and the promoted balloon-ledge
scenario. Not a PLAYABLE, GAMEPLAY_RELIABILITY or M4 claim.

## Maintainer decision (#196, 2026-11-26)

"Stop enforcing attached declarations. Amend the attached-declaration ADR:
attached #DECLs are not enforced at all, matching Confusion. DECL?,
GDECL/SETG, positional declarations and CHTYPE stay strict. A recorded
deviation from the manual. Promote balloon-ledge to a gated scenario. The
recorder stays test-only for future sweeps."

Recorded as the amendment "M4 issue #196, INV-12" under "ADR: Defer
unresolved TYPE atoms in attached declarations (M3 issue #98)" in
[DECISIONS.md](../../DECISIONS.md) and specified in
[SEMANTICS.md](../../SEMANTICS.md) ("Amendment: attached declarations are not
enforced"; notes added to the D1, NTH, #193, recorder and #100 sections).

## Provenance

| Item | Value |
|---|---|
| Commits | `02f145c` (ADR, SEMANTICS), `604cf59` (tests first, scenario, manifest, sweep), `8896f03` (runtime), then the evidence commit(s) |
| Upstream | `mdlzork` bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3, `mit_zork` d94501340842e006791fce0757dc0043b8ec8916 (`sources.lock.json`) |
| Reference | pinned Confusion `.cache/build/confusion_patched/mdli` sha256 `6df359f6…b789`; balloon-ledge reference committed in Phase 3c (captured twice, byte-identical), **not recaptured** |
| Clock / RNG | fixed session clock 250776000 (1977-12-12 12:00 UTC), TZ UTC; START seeds RANDOM from DSKDATE (10438660480); no override, no seed search |
| Racket | v7.9 [bc]; Python 3 `/usr/bin/python3` |

## Semantics implemented

* **Call time (production): no check.** `check-declared!`
  (`mdl/runtime/core.rkt`), the single attached-check point for argument,
  OPTIONAL, REST, AUX, PROG/REPEAT auxiliary, NAME, `SET` of a declared local
  and VALUE results, reads the recorder first; without one it returns the
  value at once. No Pattern is matched, so nothing matching could raise (a
  `DECL` association added after the definition to an unknown or cyclic
  name, the traversal limit, a cyclic LIST under `[REST ...]`) is raised.
  The message `NAME does not satisfy declaration` no longer exists.
* **Definition time: unchanged.** `mdl-make-declaration` still parses and
  normalizes the `#DECL` when its function is defined or its PROG entered;
  malformed pairs, non-ATOM names, duplicate VALUE, empty OR, unsupported
  Patterns and unknown structure keywords, bad NTH counts, OPT, misplaced
  SPECIAL and cyclic associations stay strict errors with their messages;
  unknown TYPE ATOMs are retained (#98). Pinned Confusion's behaviour for a
  malformed attached Pattern at definition is **not recorded** (no case under
  `docs/evidence/M3/`), so today's behaviour is kept and the question is open.
* **Strict, unchanged messages:** `DECL?`, GDECL (existing value) and SETG
  of a GDECLed global, positional declarations, CHTYPE to a NEWTYPE with a
  `DECL` association, NEWTYPE's Pattern validation.
* **Recorder (test hosts only).** With `#:decl-violation-recorder` the check
  is evaluated exactly as before (the #98/#193/#100/#96 rules); a mismatch is
  reported once and proceeds; an error raised while evaluating still raises
  in that host. Chosen as the simplest correct implementation: one `when`
  guard on the recorder, which stays the only read site.
* **Recorded deviation** from the manual (chapter 14) and alignment with
  pinned Confusion, which checks no attached declaration.

## Changed assertions (old → new)

Line numbers are those of `8c398fe`. Every one asserted an attached-check
failure; each now asserts that the call proceeds with its value, except where
noted. No assertion was deleted without a replacement.

| File:line | Old | New |
|---|---|---|
| declaration_test.rkt:21 | `<F "bad">`, `(X) FIX` raises `DECL.*X` | returns `"bad"` |
| declaration_test.rkt:22 | `<SET X "bad">` raises | returns `"bad"` |
| declaration_test.rkt:24 | `(VALUE) FIX` body `"bad"` raises | returns `"bad"` |
| declaration_test.rkt:25 | `<RETURN "bad" .A>` raises | returns `"bad"` |
| declaration_test.rkt:29 | OPTIONAL default `"bad"` raises | returns `"bad"` |
| declaration_test.rkt:30 | AUX `<SET X "bad">` raises | returns `"bad"` |
| declaration_test.rkt:32 | quoted formal `(X) FORM`, `<F 1>` raises | returns 1 |
| declaration_test.rkt:35 | `<OR FIX STRING>`, `<F []>` raises | `<LENGTH <F []>>` = 0 |
| declaration_test.rkt:37 | `<PRIMTYPE WORD>`, `"bad"` raises | returns `"bad"` |
| declaration_test.rkt:41 | PROG `<SET X "bad">` raises | returns `"bad"` |
| declaration_test.rkt:42 | PROG `(VALUE) FIX` raises | returns `"bad"` |
| declaration_test.rkt:81 | doubled `#DECL #DECL`, `"bad"` raises | returns `"bad"` |
| declaration_test.rkt:100 | DEFMAC `('X) FIX`, `"s"` raises `DECL.*X` | raises `mdl-add: expected MDL FIX or FLOAT` (the expansion's `+`) |
| declaration_test.rkt:106 | F `(VALUE) FIX` over PROG `"x"` raises `DECL.*VALUE` | returns `"x"` |
| declaration_test.rkt:133 | `MSETG "bad" 3` raises `DECL.*FOO` | `MSETG 5 3` raises `mdl-gassigned?: expected an MDL ATOM` (as pinned Confusion, at GASSIGNED?); plus a tracked XFAIL: `MSETG "M2-D1-STRING" 3` returns T (see Limitations) |
| declaration_pattern_test.rkt:109 | `<LIST [REST ATOM]>`, `(A 1)` raises | list of length 2 |
| declaration_pattern_test.rkt:112 | SET `(A 1)` raises | length 2 |
| declaration_pattern_test.rkt:122 | VALUE `(A 1)` raises | length 2 |
| declaration_pattern_test.rkt:129 | interpreted, `(A 1)` raises | length 2 |
| declaration_pattern_test.rkt:131 | interpreted SET raises | length 2 |
| atom_props_test.rkt:152 | `(X) A`, A's DECL FIX, `"x"` raises | returns `"x"` |
| mapf_test.rkt:78 | MAPF FUNCTION `(X) FIX` over `(1 A)` raises | `(1 A)` |
| applicable_decl_test.rkt:43 | `<OR APPLICABLE ATOM FIX>`, `'(1 2)` raises | returns 7 |
| function_decl_metadata_test.rkt:38 | `(X) FIX`, `"BAD"` raises | returns `"BAD"` |
| nth_decl_test.rkt:32 | `<VECTOR [3 ANY]>`, `[1 2]` raises | returns T |
| duplicate_decl_test.rkt:16 | `(X) FIX (X) ANY`, `"BAD"` raises | returns `"BAD"` |
| duplicate_decl_test.rkt:19 | `(X) ANY (X) FIX`, `"BAD"` raises | returns `"BAD"` |
| special_decl_test.rkt:16 | `<SPECIAL FIX>`, `"bad"` raises | returns `"bad"` |
| historical_decl_test.rkt:71 | pinned `MSETG "bad" 3` raises `DECL.*FOO` | `MSETG 5 3` raises `mdl-gassigned?: expected an MDL ATOM` |
| historical_g3_test.rkt:144 | pinned `MSETG "bad" 3` raises `DECL.*FOO` | `MSETG 5 3` raises `mdl-gassigned?: expected an MDL ATOM` |
| deferred_decl_type_test.rkt:53, 58, 66, 68, 70, 74, 82, 84, 87, 91, 94, 96, 101, 105, 107, 116, 141, 143, 145, 147 (20) | each raised `... does not satisfy declaration` (#193: known or later-defined types strict) | `check-violation`: production returns the value (as is, or its LENGTH/TYPE/PNAME), **and** the recorder reports exactly that binding (`X`, `PV` or `VALUE`) |
| deferred_decl_type_test.rkt:120 | later association to NOWHERE raises `unknown declaration type NOWHERE` | production returns 1; with the recorder it still raises that error |
| deferred_decl_type_test.rkt (8 #193 accepted cases) | production value only | also `check-accepted`: the recorder reports nothing |
| decl_violation_recorder_test.rkt:60 | without recorder raises `DECL 1:15: X does not satisfy declaration` | returns `"s"` |
| decl_violation_recorder_test.rkt:174 | default toy session `CHECKED "s"` raises | returns `"s"`; LATE (a check that raises when evaluated) returns 7; a recorder session's LATE raises `unknown declaration type NOWHERE` |
| decl_violation_recorder_test.rkt:183 | "MDL cannot enable it": raises after PUT FIX DECL ANY | LATE still returns 7 after it |
| decl_violation_recorder_test.rkt:191 | run-zork on the toy game raises | run-zork reaches the game's QUIT (`'quit`), output `booted\ns\n7\n` (LATE would raise under a recorder) |
| decl_violation_recorder_test.rkt:201 | replay-record raises | replay-record reaches QUIT, output contains `booted\ns\n7\n` |
| decl_violation_recorder_test.rkt (static) | — | added: the runtime no longer contains the attached error text |
| historical_balloon_frontier_test.rkt:106-108 (retired) | XFAIL: run fails at k = 57 with `DECL 424:9: PRSO does not satisfy declaration` | file retired; its native assertions moved to `historical_balloon_ledge_test.rkt`, which runs the whole scenario |

Isolation is not weakened: the static checks (one read site, immutable field,
not exported, no production host or MDL name) are unchanged, and the
behavioural ones now use a check that can only raise when evaluated, so a
production host that silently had a recorder would fail them.

## New tests

* `tests/attached_decl_unenforced_test.rkt` (in `make test`): every binding
  kind (argument compiled and interpreted, OPTIONAL default and supplied,
  REST TUPLE/ARGS, AUX, SET, VALUE by body/RETURN/inner PROG, PROG and REPEAT
  auxiliaries, NAME, DEFMAC, MAPF FUNCTION) and nested Patterns (OR,
  PRIMTYPE, LIST/VECTOR elements and REST, NTH length, duplicate name,
  SPECIAL, APPLICABLE, a DECL association, BALLOON's PRSO shape) proceed in
  production, each with the bindings the recorder still reports; the four
  errors raised while matching (late unknown and cyclic association,
  traversal limit, cyclic value) are absent in production and still raised
  with a recorder; definition-time errors with their exact messages and
  positions; DECL?, GDECL, SETG, positional and CHTYPE strict with exact
  messages, also with a recorder.
* `tests/historical_balloon_ledge_test.rkt` (`make test-m4-balloon-ledge`).

## Tests before and after

| Run | Before (strict core `8c398fe` runtime, new tests) | After (`8896f03`) |
|---|---|---|
| `make test-racket` | exit 2; raco `32/4707 test failures`: 11 modules abort at their first converted assertion (`... does not satisfy declaration`: applicable_decl, atom_props, attached_decl_unenforced, decl_violation_recorder, declaration_pattern, declaration, duplicate_decl, function_decl_metadata, mapf, nth_decl, special_decl) and deferred_decl_type has 21 failing checks | `make test` exit 0: raco 5165 tests passed (the 12 modules included), pytest 104 passed, 1 deselected |
| `racket tests/historical_decl_test.rkt` | exit 1 (`expected an error matching mdl-gassigned?...`) | exit 0 within `make test-historical` ("historical DECL probe passed: 20 assertions") |
| `racket tests/historical_g3_test.rkt` | exit 1 (same) | exit 0 (`make test-m2-g3`: 58 assertions) |
| `racket tests/historical_balloon_ledge_test.rkt` | exit 1: `earliest failing k = 57, kind run-guard ... DECL 424:9: PRSO does not satisfy declaration` | exit 0 |

## The balloon

`tests/historical_balloon_ledge_test.rkt` runs the 81 commands through the
shared runner against the committed reference (not recaptured), with the
puzzles checkpoint and `#:eof-classification-ignore-keys '(robber_hroom)`,
plus the retired frontier test's native assertions (the rope, torch and
glacier at entries 21-54; the balloon's HERE, AVEHICLE, BLOC, BINF, BTIE,
receptacle, BINT and BRNIN at 16 entries; the key transcript lines) and
`#:check-turn` checks on our side (burned from 59, tied from 68, untied from
71, landed from 79).

* Single-run (`make test-m4-balloon-ledge`): exit 0, "all 82 turns match the
  reference (D1 only); 5 boots; 77 of 81 shorter prefixes have a standard
  end-of-input tail (not re-run)", prefixes 50, 51, 52 and 60 re-run and
  equal, 29.7 s.
* Per-prefix (`M4_SCENARIO_MODE=per-prefix make test-m4-balloon-ledge`):
  exit 0, "all 82 turns match the reference (D1 only); 82 boots, 644.2 s".
* Before the runtime change: exit 1 at k = 57 (above). No later divergence
  was found.

## Coverage

`objects.puzzles-beyond-the-house` is **covered** (gameplay-branches.json):
checks test-m4-dam-sluice, test-m4-boat-river, test-m4-balloon-ledge,
test-m4-coal-machine, test-m4-gas-room, one route each under the fixed clock
and seed:

* the dam: wrench, bolt refused, yellow button, sluice gates opened, the
  trunk from the drained reservoir;
* the boat: pumped up at the Dam Base, boarded, launched onto RIVR1, landed,
  deflated;
* the balloon: receptacle, guidebook burned, risen to the Narrow Ledge, the
  wire tied and untied, landed at the Volcano Bottom;
* the coal mine: basket lowered and raised, the empty-handed passage, the
  machine turning the coal into the diamond;
* the gas room: walked into with the lamp only and with the burning candles
  (the explosion).

Out of scope: the river downstream (RIVR2 on, the falls, the buoy), the
reservoir refilling, the gas room's ON branch, the balloon's other
destinations (VAIR3, VAIR4, the upper ledge, the Volcano View), the balloon
crashing or BRNIN expiring in the air, the volcano gnome, and a switch
command without an indirect object (the sweep's MSWITCH probe only).
INV-12 moved to `resolved_inventory`; timers.other-clock-events' note now
cites BINT and BRNIN as checkpointed in balloon-ledge.

## Sweep re-run

`make m4-decl-sweep` (exit 0) on `e98fe9b`; report
[decl-violation-sweep.json](decl-violation-sweep.json). The sweep now runs
every unit twice, each in its own process: with the recorder and without it
(production). 27 units (25 gated scenarios, balloon-ledge now among them;
the MSWITCH probe route; the SPHERE direct call), none crashed.

* **With the recorder: the same 4 sites as the original sweep**, with the same
  occurrence counts: BALLOON BINF (77act2.mud:424, aux, 43) and PRSO (aux,
  40) on balloon-ledge (now "on a gated scenario route"); MSWITCH-FUNCTION IMP
  (77act2.mud:142, aux, 3) on the probe; SPHERE-FUNCTION PV (77act3.mud:245,
  aux, 1) by the direct call. 0 on the other 24 gated scenarios.
* **Without the recorder every unit matches:** all 25 gated scenario modules
  PASS (balloon-ledge included), the MSWITCH probe's whole transcript equals
  native T1, and the SPHERE direct call returns with the same output as with
  the recorder (the game's poisoning; ours only). 0 violations recorded in
  production runs, as expected (no recorder).

## make m4-check

`make m4-check` exit 0 on `8896f03` with the evidence docs uncommitted
("dirty"); all 25 scenario targets, the persistence check and the PLAYABLE
sub-checks PASS.

| Term | Status | Scope / reasons |
|---|---|---|
| SCENARIO_PARITY | PASS | 25 scenarios, each under one fixed clock and seed (250776000, UTC) |
| GAMEPLAY_RELIABILITY | NOT YET | 19 of 23 required branches covered (PROVISIONAL list); uncovered: combat.thief, save.game-save-command, save.game-restore-command, save.player-facing-resume; open blockers INV-06, INV-07 |
| PLAYABLE | NOT RUN | sub-checks only; no PLAYABLE gate; player-facing save/resume and a full playthrough missing |
| FULL_COMPLETION | NOT RUN | no complete-game check |
| M4_ACCEPTED | NOT YET | R2-R5 not met |

## Commands and results

All with `PLTCOLLECTS=":$PWD" TMPDIR=/tmp PYTHON=/usr/bin/python3`, one heavy
job at a time; logs under `artifacts/s16/` (not committed).

| Command | Exit | Notes |
|---|---|---|
| `make test-racket` (before, runtime of `8c398fe`, new tests) | 2 | raco 32/4707 failures (12 modules) |
| `racket tests/historical_balloon_ledge_test.rkt` (before) | 1 | k = 57, `DECL 424:9: PRSO does not satisfy declaration` |
| `racket tests/historical_decl_test.rkt`, `racket tests/historical_g3_test.rkt` (before) | 1, 1 | expected the GASSIGNED? error |
| `make test-m4-balloon-ledge` | 0 | 82 turns, single-run |
| `M4_SCENARIO_MODE=per-prefix make test-m4-balloon-ledge` | 0 | 82 boots |
| `make test` | 0 | raco 5165 passed; pytest 104 passed, 1 deselected |
| `make test-historical` | 0 | |
| `make test-m2-g3` | 0 | 58 assertions |
| `make m3-check` | 0 | overall PASS, native fresh capture included |
| `make m4-check` | 0 | table above |
| `make m4-decl-sweep` | 0 | 27 units x 2 modes; 4 sites |
| `git diff --check` | 0 | |

Reproduce: `make test`, `make test-m4-balloon-ledge`,
`M4_SCENARIO_MODE=per-prefix make test-m4-balloon-ledge`, `make m4-check`,
`make m4-decl-sweep`.

## Limitations and risks

* **A newly visible divergence (not fixed here).** Pinned Confusion stops
  `<MSETG "x" 3>` at GASSIGNED? ("1st arg to GASSIGNED? must be atom",
  `docs/evidence/M2/decl-error-reference.json` original-msetg-wrong-atom).
  This runtime's `binding-atom` accepts an MDL STRING as an ATOM name, so
  GASSIGNED?/SETG (and other binding-atom users) proceed. MSETG's attached
  `(FOO) ATOM` used to hide this. Tracked as an XFAIL assertion in
  `tests/declaration_test.rkt`; it needs its own slice (binding-atom is also
  the host-call path, so the fix must separate MDL calls from host calls).
  The gated routes never pass a STRING there (the sweep found no attached
  violation on them).
* **Lost safety net.** A runtime bug that produces a wrongly typed value is no
  longer stopped at an attached binding; it must show in output or state. The
  scenario checkpoints compare both; `make m4-decl-sweep` remains the
  diagnostic and must be re-run when scenarios are added.
* **Recorder hosts differ from production on check-time errors** (a later
  malformed association, the traversal limit): they raise only with a
  recorder. By design; a sweep would report them as a finding.
* **Definition-time behaviour of Confusion** for malformed attached Patterns
  is not recorded; this runtime keeps rejecting them (possibly stricter than
  the oracle).
* Scenario PASS is scoped to one fixed clock and seed per route.

Security and licensing: no change to exposure (the recorder stays host-only
and unreachable from MDL; no evaluator exposed), no GPLv3 code copied, no
upstream bytes changed.
