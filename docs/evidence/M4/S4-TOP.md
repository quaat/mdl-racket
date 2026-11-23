# M4 S4: the TOP SUBR (issue #157)

Date: 2026-11-23. Branch `feat/m4-top` at `main` `c8964bf` (uncommitted
working tree at the time of these runs). Upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3` (`sources.lock.json`); mit_zork
`d94501340842e006791fce0757dc0043b8ec8916` (not used). Racket v7.9 [bc],
Python 3.9.2. Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before
and after every capture (`make reference-build` not run).

Result: **S4 scenario PASS (scoped: the top-parser scenario, every prefix,
transcript plus checkpoints)**; frontier item 3 (TOP at `77np.mud:126`)
resolved; the next strict failure on a TOP path is recorded as F4. Not a
PLAYABLE claim and not the M4 gate.

## Order of work

1. Reference probes (read-only): `scripts/probe_top_reference.py` →
   `top-probe.json`, [TOP-REFERENCE.md](TOP-REFERENCE.md) (28 cases); the
   game path: `scripts/probe_top_parser_reference.py` →
   `top-parser-reference.json`, [TOP-PARSER-REFERENCE.md](TOP-PARSER-REFERENCE.md)
   (T1, T1b, diagnostic X1 with a TOP wrapper and 12 checkpoints, F4, P00–P09).
2. Specification: `docs/SEMANTICS.md` "M4 S4: TOP of arrays";
   `docs/DECISIONS.md` ADR-0058.
3. Red tests: `tests/top_test.rkt` (registered in `scripts/test_racket.sh`),
   `tests/historical_top_parser_test.rkt` (`make test-m4-top-parser`, also in
   `.github/workflows/reference.yml`).
4. Implementation: `mdl-top` in `mdl/runtime/core.rkt` (≈30 lines) and the
   `channel-storages` registry; `"TOP"` added to the builtin table.
5. Frontier: `tests/historical_m4_frontier_test.rkt` and
   [S1-HOUSE-CELLAR-FRONTIER.md](S1-HOUSE-CELLAR-FRONTIER.md) (TOP resolved,
   F4 recorded, F3 unchanged); `tests/historical_session_quit_test.rkt` C3 now
   runs the whole reference session (its `put leaflet in` reaches TOP).

## Reference findings (summary)

TOP is defined on VECTOR, UVECTOR and STRING PRIMTYPEs only; it returns the
same storage from its first element (no copy, mutations visible both ways,
`==?` to the unrested original, to any other TOP and to a BACK reaching the
start), keeps the argument's TYPE (`#FOO`, CHANNEL; REST drops it first),
shares a UVECTOR's UTYPE. LIST, a REST of a LIST, FORM, FALSE, SEGMENT,
TUPLE, FIX, ATOM, CHARACTER: stderr `Bad type for TOP`. `<TOP>` /
`<TOP [1] 2>`: TOO-FEW/TOO-MANY-ARGUMENTS-SUPPLIED. GROW is unbound in the
reference. Terminal CHANNELs: `<TOP ,INCHAN>` is a 21-element CHANNEL whose
slot 1 is `()` (script/echo LIST) and slot 2 the FIX 0 of `<BACK ,INCHAN>`.

## Semantics implemented, refusals, deviations

* `<TOP x>` for a VECTOR/UVECTOR/STRING (plain, REST or BACK view, or a TYPE
  over one): a new view record over the same Racket vector (same UTYPE cell)
  or the same backing string, start 0, full length; the TYPE tag of x is
  re-applied. Dispatch is on the value representation, never on a TYPE
  PNAME.
* Refused: every non-array value (`mdl-top: Bad type for TOP: …`), arity
  (`TOO-FEW-/TOO-MANY-ARGUMENTS-SUPPLIED`).
* Deviation (ADR-0058): TOP of any view of a terminal CHANNEL's storage is
  refused (`mdl-top: TOP of CHANNEL storage is not supported (ADR-0058)`);
  the reference returns the 21-element CHANNEL. Game reach: only the script
  code after a successful OPEN "PRINT" (denied, ADR-0055).
* Reference error texts go to stderr without an ERROR frame; this runtime
  raises (as for CHTYPE's `PRIMTYPES do not match`).

## Game path

Scenario `tests/scenarios/top-parser.json`: `open mailbox`, `take leaflet`,
`drop leaflet in` (SPARSE TOP), `put all in mailbox`, `take all` (EVERYTHING
TOP), `take leaflet`, `drop all`, `take all` (EVERYTHING TOP), `put leaflet
in` (SPARSE TOP), `inventory`. Six TOP calls natively (X1 log), asserted
from the reference in the test.

## Commands and results

All Racket runs with `export PLTCOLLECTS=":$PWD"` in the worktree.

| Command | Exit | Output excerpt |
|---|---|---|
| `python3 -I scripts/probe_top_reference.py docs/evidence/M4/top-probe.json` | 0 | 28 cases, exit 0 each; mdli sha256 before = after = pinned |
| `python3 -I scripts/probe_top_parser_reference.py docs/evidence/M4/top-parser-reference.json` | 0 | T1/T1b byte-identical, X1 game part = T1, 12 checkpoints, prefixes consistent |
| **red** `racket tests/top_test.rkt` (before `mdl-top`) | 1 | `mdl-eval: unassigned or non-applicable MDL operator TOP` |
| **red** `racket tests/historical_top_parser_test.rkt` (before) | 1 | prefixes 0–2 pass; prefix 3 (`drop leaflet in`) ends with `mdl-eval: unassigned or non-applicable MDL operator TOP` after `>Taken.\n>` |
| `racket tests/top_test.rkt` | 0 | 12 probe cases equal the reference (1 known XFAIL, below); refusals; properties |
| `make test-m4-top-parser` | 0 | `prefix 0..10: transcript and checkpoint k equal the reference`; `operands: … (INCHAN refused, ADR-0058)` (68 s) |
| `make test-m4-house-cellar` (includes the frontier test) | 0 | S1 12 prefixes; F1, F2, F2b, **F-TOP** resolved; **F4** strict as recorded; F3 help/info unchanged (109 s) |
| `make test-m4-mailbox-drop` | 0 | (56 s) |
| `make test-m4-orphan-prompt` | 0 | (63 s) |
| `make test-m3-interactive` | 0 | `31 tests passed` |
| `make test-m3-session` | 0 | `85 tests passed` (C3 now the whole reference session incl. `put leaflet in`) |
| `bash scripts/test_racket.sh` | 1 | `3/3922 test failures`: only `loader_test.rkt`, `declaration_test.rkt`, `percent_read_test.rkt`, each `make-directory: … /tmp/… Read-only file system` (hardcoded /tmp, sandbox-only); no other FAILURE line; `top_test.rkt` passes |

`make test` (full) was not run.

## Mutation checks (each restored from a saved copy; `cmp` identical afterwards)

| Mutant of `mdl-top` | `tests/top_test.rkt` | First failing check |
|---|---|---|
| (a) copy the storage (vector copy, new UTYPE box; `string-copy`) | exit 1 | `vector-top: <==? <TOP .R> .V>` → `#FALSE ()`, expected `T` |
| (b) return the argument's view itself | exit 1 | `vector-top: <TOP .R>` → `[3 4]` |
| (c) wrong offset (start 1) | exit 1 | `vector-top: <TOP .R>` → `[2 3 4]` |
| (c') wrong length (one short) | exit 1 | `vector-top: <TOP .R>` → `[1 2 3]` |
| (c'') STRING start 1 | exit 1 | host index error on `<TOP "">` |
| (d) accept a LIST (return it) | exit 1 | refusal check `<TOP (1 2)>` |

Game-level: mutant (b) fails `tests/historical_top_parser_test.rkt` at
prefix 3; mutant (a) passes all 11 prefixes (the scenario never fills all 20
OBJ-UV slots, and SPARSE's caller does not depend on the TOP result's
identity) and fails only the operands section (`<==? <TOP ,OBJ-UV> <BACK
,OBJ-UV 20>>`). Copying is therefore caught by the unit tests and the
operand check, not by the transcript.

## Known XFAIL (pre-existing, not TOP)

Probe form `string-top: <==? <TOP .R> "abcdef">` is FALSE in the reference
and T here: two equal STRING literals read separately are one host string in
this runtime (`<==? "abc" "abc">` is T here, FALSE in Confusion). Tracked in
`tests/top_test.rkt` with the current answer. Candidate for a separate
reader/literal slice.

## Next strict failure on the TOP path (F4)

`take all` in the living room (or `take sword`): SWORD `77act1.mud:1903`
`<TYPE? ,SWORD-GLOW NOFFSET>`: TYPE of a DEFINEd FUNCTION's GVAL is
unsupported (`mdl-type: unsupported MDL type #<procedure>`). Call path and
native output: [S1-HOUSE-CELLAR-FRONTIER.md](S1-HOUSE-CELLAR-FRONTIER.md)
"F4". Not stubbed.

## Limitations and risks

* CHANNEL TOP is a deliberate refusal (ADR-0058), not parity.
* The reference prints TOP's type error to stderr without an ERROR frame;
  this runtime raises a host error (same policy as earlier CHTYPE errors).
* VALUABLES (`77rooms.mud:1330`) and the balloon's `<TOP ,SCRSTR>` are
  covered by unit tests and operand checks only, not by a native scenario.
* README/STATUS not updated (orchestrator). Changes touching shared mutation
  and equality need an independent review (AGENTS.md); none was done here.

Security and licensing: local runs only, no network or exposed evaluator;
Confusion (GPLv3) used only as a reference binary, no source copied.
