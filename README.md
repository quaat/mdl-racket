# MDL on Racket — original Zork preservation harness

> **Status (2026-11-23): `main` (`2a86d5d`) — M0, M1, M2 PASS; M3 accepted on mainline: the original 1977 game loads, initializes, matches native Confusion exactly on the fixed-clock fresh-boot house smoke (SMOKE_PARITY PASS, scoped) and completes a local session that quits through its own code (local session smoke PASS). PLAYABLE NOT RUN. NOT a complete playable game.** This repository is a starting
> point for developing an MDL-compatible `#lang mdl` in Racket and validating it
> against the reconstructed December 1977 Zork running in Confusion.
>
> The historical game sources and interpreter are **not bundled**. The included
> fetcher retrieves two immutable upstream GitHub commits after network access is
> available. All verification below is local and reproducible, modulo toolchain
> versions and original input/time/randomness.

## Verified status (2026-11-23)

**Mainline (`main` = `2a86d5d`, M3 acceptance 2026-11-23).** M0, M1, M2:
**PASS (mainline)**. M3, gate rerun on `main` with `M3_NATIVE=require` (local
Racket v7.9 BC; CI racket:8.10-bc runs 45176163020 and 45176121779;
[acceptance record](docs/evidence/M3/M3-MAINLINE-ACCEPTANCE.md)):

| M3 stage | State on `main` |
|---|---|
| PARSED | PASS (mainline) |
| LOADED | PASS (mainline): 1,229 forms, zero skipped |
| INITIALIZED | PASS (mainline, scoped): faithful `<FLOAD "77loadall.mud">` + `<SAVE-IT>`; SAVE is an in-session record (ADR-0048) |
| INTERACTIVE | PASS (mainline, scoped): the six house-boot commands through the host loop |
| SMOKE_PARITY | **PASS (mainline, scoped)**: house-boot at the fixed session clock 250776000/UTC; one strict comparator, only D1/D2 differ (ADR-0053); committed schema-3 reference == fresh native capture == this runtime |
| Local session smoke | **PASS (mainline)**: quit/n, a further command, quit/y through the game's FINISH → RECORD → QUIT, byte-identical to native, no files written |
| PLAYABLE | NOT RUN (M4) |

The fixes for #119, #124, #139, the #113 review findings R1-R8/R10, the
host-loop flush masking (F2) and the session clock (#135 part 1) are on
`main`. See [STATUS](docs/STATUS.md).

**Supported on `main`:** the S7 terminal subset (RESET, PRINC, PRIN1,
READSTRING as RDCOM/YES-NO use it) and the local host loop
`mdl-session-run-interactive` (explicit ports; no MDL evaluator; never a
network service); a session-owned clock (`#:clock`, `#:time-zone`,
ADR-0052); MEMBER (structural search, STRING substring); QUIT as a session
outcome (`'quit` / `'quit-after-mdl-error`, ADR-0054); OPEN under a virtual
no-file policy (RECORD's form only, ADR-0055); SAVE as an in-session record.

**Read-only files (M4 S10, #171, ADR-0055 amendment):** `help`, `info` and
`?` print the two shipped files `MDL/MADADV.HELP` and `MDL/MADADV.INFO` as
natively (OPEN "READ", FILE-LENGTH, file READSTRING, CLOSE); only those two
files, hash-checked against pinned sha256 values, can be read; every other
OPEN "READ" is a strict error (`make test-m4-help-info`,
[record](docs/evidence/M4/S10-HELP-INFO.md)).

**Unsupported (strict errors):** RESTORE, writing files, any other file read,
ACCESS, PRINT (the game's ERROR handler path), non-ASCII
terminal input, a session without an explicit output port (S13, ADR-0050),
and every MDL construct not listed in [SEMANTICS](docs/SEMANTICS.md). Typed
`!` follows pinned Confusion (S13: `nor!th` reads as `north`).

**Play locally (preview):** see the section below; `make play` or
`racket zork/cli.rkt`.

**Reproduce** (after `make sources`; local runs used Racket v7.9 BC, CI the
racket:8.10-bc container; in the sandbox `export PLTCOLLECTS=":$PWD"`):
`make test`, `make test-historical`, `make test-m2-g3`,
`make m3-source-progress`, `make test-m3-historical-gc`,
`make test-m3-start-back`, `make test-m3-saveit`, `make test-m3-interactive`,
`make test-m3-clock-seed`, `make test-m3-session`, `make test-m3-launcher`,
`make test-m3-bang`,
`make m3-check` (aggregate M3 SMOKE_PARITY check; native stage NOT RUN
without `mdli`), `make m3-native-parity` (after `make reference-build`).
The reference CI workflow runs all of these.

**Evidence:** [S10 SMOKE_PARITY](docs/evidence/M3/S10-SMOKE-PARITY.md),
[S11 QUIT/OPEN](docs/evidence/M3/S11-QUIT-OPEN.md),
[S12 launcher](docs/evidence/M3/S12-LAUNCHER.md),
[S8 clock](docs/evidence/M3/S8-SESSION-CLOCK.md),
[S9 MEMBER](docs/evidence/M3/S9-MEMBER.md),
[F1/F2](docs/evidence/M3/F1-F2-STACK-FIXES.md),
[native reference probes](docs/evidence/M3/), [S7](docs/evidence/M3/S7-INTERACTIVE.md),
[compatibility inventory](docs/evidence/M3/COMPATIBILITY-INVENTORY.md).

**M4 is in progress.** Its acceptance terms are tracked separately in
[STATUS](docs/STATUS.md) and epic
[#163](https://github.com/quaat/mdl-racket/issues/163):

`make m4-check` computes the five terms from the declared
[scenario manifest](tests/scenarios/m4-manifest.json) and
[gameplay branches](docs/evidence/M4/gameplay-branches.json) and reports
them separately ([TESTING](docs/TESTING.md),
[record](docs/evidence/M4/M4-CHECK.md)). The column is a **local branch
result** (`feat/m4-check`, `main` 513272f plus the check scaffold, no
runtime change; Racket v7.9 BC; exit 0), not mainline acceptance:

| Term | State (local `make m4-check`, 2026-11-25) |
|---|---|
| SCENARIO_PARITY | PASS for the 11 declared scenarios (S1–S10), each under one fixed clock and seed |
| GAMEPLAY_RELIABILITY | NOT YET: 9 of 23 declared required branches covered (provisional list); open blockers INV-06 RESTORE, INV-07 PRINT in HANDLE |
| PLAYABLE | NOT RUN: no PLAYABLE gate; quit-session and launcher sub-checks pass |
| FULL_COMPLETION | NOT RUN (Phase 6) |
| M4_ACCEPTED | NOT YET |

**Native scenarios (merged on `main`).** Each is compared with pinned Confusion
turn by turn, with state checkpoints, and each PASS is
scenario-scoped. The targets run each scenario in one boot and check every
turn at its READSTRING prompt (`tests/m4_scenario_runner.rkt`,
[record](docs/evidence/M4/SINGLE-RUN-RUNNER.md)); `make
m4-scenarios-per-prefix` runs the slower one-boot-per-prefix protocol:

| Scenario | Target | Notes |
|---|---|---|
| Enter the house and open the cellar | `make test-m4-house-cellar` | |
| Drop | `test-m4-mailbox-drop` | SEGMENT |
| Orphan prompts | `test-m4-orphan-prompt` | CHARACTER |
| TOP and the parser | `test-m4-top-parser` | |
| Take the sword | `test-m4-sword-glow` | FUNCTION/SUBR TYPEs |
| Troll combat with the sword | `test-m4-troll-combat` | one combat branch |
| Parser rejection and ambiguity | `test-m4-parser-ambiguity` | `Which door?` |
| The cyclops (S8) | `test-m4-cyclops-room` | ABS |
| The mirror and the bat (S9) | `test-m4-mirror-bat` | IMAGE, SLEEP |
| The Strange Passage (S9) | `test-m4-strange-passage` | TIME |
| Help and info (S10) | `test-m4-help-info` | read-only allowlist |
| Death by grue, resurrection (Phase 2, branch `feat/m4-death-branches`) | `test-m4-grue-resurrection` | possessions scattered |
| Death by grue, refused (Phase 2, same branch) | `test-m4-grue-refusal` | the game's QUIT; native ZORK.LOG not written (ADR-0055) |
| Killed by the troll (Phase 2, same branch) | `test-m4-troll-death` | staggered, wounded, killed, resurrected |
| A treasure in the trophy case (Phase 3, branch `feat/m4-timers-scoring`) | `test-m4-treasure-deposit` | the painting, score 46 |
| The thief takes the painting (Phase 3, same branch) | `test-m4-thief-robbery` | observed under the fixed seed; no fight |
| The cure clock heals a wound (Phase 3, same branch) | `test-m4-cure-recovery` | CURIN countdown, CURE-CLOCK |
| The lamp burns out (Phase 3, same branch) | `test-m4-lamp-burnout` | 118 `wait`s, LIGHT-INT warnings |
| The match clock (Phase 3b, branch `feat/m4-dam`) | `test-m4-match-clock` | MATIN: fires, `wait`, turned off, out of matches |
| The boat and the river (Phase 3b, same branch) | `test-m4-boat-river` | the pump, inflate, board, launch, land, deflate |
| The dam's sluice gates (S14, branch `feat/m4-prsobj-decl`) | `test-m4-dam-sluice` | the Maintenance Room, the yellow button, the bolt, the trunk |
| The Maintenance Room leak (S14, same branch) | `test-m4-maint-leak` | the clock event MNTIN, the putty |
| The coal-mine machine and basket (Phase 3c, branch `feat/m4-puzzles`) | `test-m4-coal-machine` | the basket lowered and raised, the empty-handed passage, coal into diamond |
| The gas room (Phase 3c, same branch) | `test-m4-gas-room` | in with the lamp only, then with burning candles: the explosion |
| The thief fights (combat.thief, branch `feat/m4-thief-fight`) | `test-m4-thief-fight` | the Treasure Room: both sides strike; the thief kills the hero |

The three Phase 2 death scenarios ([record](docs/evidence/M4/DEATH-BRANCHES.md))
use two opt-in runner options (ADR-0062 amendment): the death question as the
prompt of its READSTRING entry, and declared prefixes that end by the game's
own QUIT instead of end of input. They are branch evidence until merged.

The four Phase 3 scenarios ([record](docs/evidence/M4/TIMERS-SCORING.md))
use a wider read-only checkpoint (lamp and clock events, painting, trophy
case, thief) and one opt-in runner option that keeps the thief's room out of
the end-of-input classification only (ADR-0062 amendment). They cover the treasure deposit, the cure
clock and the lamp burn-out; the thief is seen stealing but not fighting, so
the thief branch stayed uncovered there (covered since thief-fight, below). On that branch `make m4-check` exits 0:
SCENARIO_PARITY PASS for 18 scenarios, GAMEPLAY_RELIABILITY NOT YET with 17
of 23 required branches covered. They are branch evidence until merged.

The two Phase 3b scenarios ([record](docs/evidence/M4/DAM-CLOCKS.md)) go
beyond the house with wider read-only checkpoints (dam, clocks, boats) and no
runtime change. They cover one other clock event (the match clock) and one
listed puzzle (the boat). The dam was blocked there (INV-11): entering its
Maintenance Room ended the session, because the room's function declares the
undefined type PRSOBJ, which pinned Confusion does not check.

**S14 (#193, INV-11 fixed; branch `feat/m4-prsobj-decl`, gate PASS,
scenario-scoped; [record](docs/evidence/M4/S14-PRSOBJ-DECL.md)).** By
maintainer decision the #98 declaration ADR is amended: a TYPE name in an
attached declaration that is still undefined when checked is not enforced,
as in pinned Confusion. This is a recorded deviation from the manual,
limited to undefined names. Known types stay strict, as do `DECL?`,
positional declarations and GDECL. No source change. The dam (`make
test-m4-dam-sluice`) and its leak clock MNTIN (`make test-m4-maint-leak`)
now match the committed native references at every turn, in single-run and
per-prefix modes; `make xfail-m4-dam-frontier` is retired. Puzzles beyond
the house: two of the five listed (the boat, the dam) are exercised; the
balloon, the coal mine and the gas room are not, so that branch stays
uncovered. On that branch `make m4-check` exits 0: SCENARIO_PARITY PASS for 22
scenarios, GAMEPLAY_RELIABILITY NOT YET with 18 of 23 required branches
covered and open blockers INV-06 and INV-07. Branch evidence until merged.

**Phase 3c (branch `feat/m4-puzzles`; gate PASS for two scenarios,
scenario-scoped; the balloon BLOCKED; [record](docs/evidence/M4/PUZZLES.md)).**
No runtime change. Two more gated scenarios under the same clock and seed:
the coal-mine machine and basket (`make test-m4-coal-machine`) and the gas
room (`make test-m4-gas-room`). Both match pinned Confusion at every turn in
single-run and per-prefix modes. The balloon is a frontier finding (INV-12):
this runtime stops when the hero boards it, because the game's BALLOON
function receives a FALSE where its own attached declaration allows only an
OBJECT or DIRECTION; known types are checked here and nothing is checked
natively. The native reference is committed and `make
xfail-m4-balloon-frontier` tracks the failure (not a parity check). Puzzles
beyond the house: four of the five listed are exercised; the branch stays
uncovered until the balloon runs. On that branch `make m4-check` exits 0:
SCENARIO_PARITY PASS for 24 scenarios, GAMEPLAY_RELIABILITY NOT YET with 18
of 23 required branches covered and open blockers INV-06, INV-07 and INV-12.
Next: a maintainer decision on INV-12. Branch evidence until merged.

**#196 attached-declaration sweep (branch `feat/m4-decl-sweep`; diagnostic
only, no semantic change; [record](docs/evidence/M4/DECL-VIOLATION-SWEEP.md)).**
A host-only, test-only recorder (`make-mdl-session
#:decl-violation-recorder`, never passed by `run-zork`, the command line or
replay) lets `make m4-decl-sweep` run every gated scenario, the balloon route
and targeted probes with attached `#DECL` violations recorded instead of
fatal. Result: no violation on the 24 gated routes; the balloon violates
BALLOON's PRSO and BINF declarations and, allowed to proceed, matches pinned
Confusion through all 81 commands; MSWITCH (`push switch`) is confirmed on a
native-captured probe route, and SPHERE-FUNCTION only by a direct host call (no
route run, not compared with native). Production stays strict: the balloon is
still blocked (`make xfail-m4-balloon-frontier`). Next: the maintainer's INV-12 decision
(recommended: stop enforcing attached declarations, aligning with Confusion).
(Superseded by S16 below.)

**S16 (#196, INV-12 fixed; branch `feat/m4-attached-decl-unenforced`, gate
PASS, scenario-scoped; [record](docs/evidence/M4/S16-ATTACHED-DECL.md)).** By maintainer
decision attached `#DECL`s are no longer enforced at all, as in pinned
Confusion: a bound argument, OPTIONAL, REST, AUX, PROG auxiliary, NAME
formal, `SET` of a declared local or VALUE result is never checked in
production. This is a recorded deviation from the manual. An attached
`#DECL` is still validated when its function is defined (malformed Patterns
stay strict errors), and `DECL?`, GDECL/SETG, positional declarations and
CHTYPE stay strict with unchanged messages. The test-only recorder still
evaluates every attached check, so `make m4-decl-sweep` still finds the same
4 sites. The balloon (`make test-m4-balloon-ledge`, 81 commands: the
guidebook burned, the balloon up to the Narrow Ledge, the wire tied and
untied, the landing) now matches the committed native reference at every
turn in single-run and per-prefix modes; `make xfail-m4-balloon-frontier`
is retired. All five listed puzzles beyond the house are now exercised by
gated checks (one route each; the river downstream, the balloon's other
destinations and the volcano gnome are not). On that branch `make m4-check` exits 0: SCENARIO_PARITY PASS for 25 scenarios, GAMEPLAY_RELIABILITY NOT YET with 19 of 23 required branches covered (objects.puzzles-beyond-the-house now covered) and open blockers INV-06 and INV-07 only. Known
limitation found here: with MSETG's declaration no longer enforced, this
runtime's ATOM-taking binding primitives (`SETG`, `GVAL`, `GASSIGNED?`,
`SET`, `LVAL`, `VALUE`, `GUNASSIGN`, `MANIFEST`) accepted a STRING as an ATOM
name where Confusion stops (#199; fixed by branch `fix/199-binding-atom-string`,
below). Branch evidence until
merged.

**combat.thief (branch `feat/m4-thief-fight`, gate PASS, scenario-scoped;
[record](docs/evidence/M4/THIEF-FIGHT.md)).** No runtime change, no seed
search. One more gated scenario under the same clock and seed, `make
test-m4-thief-fight` (33 commands): strange-passage's way past the cyclops,
then `up` into the Treasure Room, whose room action brings the thief there
whatever the seed. He attacks at once (a miss); `kill thief with sword`
twice: the hero wounds him twice, he wounds the hero, then knocks him out
and kills him; `y`, patched in the forest. It matches pinned Confusion at
every turn in single-run and per-prefix modes (native reference captured
twice, transcripts byte-identical). With thief-robbery (stealing) this
covers the `combat.thief` branch; not exercised: the thief appearing by
chance elsewhere, leaving a fight, being knocked out or killed (his booty),
and the hero recovering from unconsciousness. On that branch `make m4-check` exits 0 (677.8 s, at `6d6e5b1`, clean tree): SCENARIO_PARITY PASS for 26 scenarios, GAMEPLAY_RELIABILITY NOT YET with 20 of 23 required branches covered (combat.thief now covered; uncovered: the three save branches) and open blockers INV-06 and INV-07; PLAYABLE NOT RUN, FULL_COMPLETION NOT RUN, M4_ACCEPTED NOT YET. Branch evidence
until merged.

**#199 binding primitives (branch `fix/199-binding-atom-string`, gate
PASS, no gameplay change; [record](docs/evidence/M4/I199-STRING-ATOM.md)).**
`SETG`, `GVAL`, `GASSIGNED?`, `SET`, `LVAL`, `VALUE`, `GUNASSIGN` and
`MANIFEST` now reject a STRING first argument (`mdl-<p>: expected an MDL
ATOM`, as for FIX and FORM) without interning or changing the ATOM it
spells; the original MSETG/PSETG with a STRING stop where pinned Confusion
stops. Limits: the error is a strict host error, not Confusion's level-1
abort or `*ERROR*` level; MANIFEST rejecting non-ATOMs is part of the
existing enforced-MANIFEST deviation (Confusion's MANIFEST does nothing);
`BOUND?`, `GBOUND?` and `UNASSIGN` are not implemented. Host callers name
globals by strings through `mdl-session-global`/`mdl-session-call`, which
now resolve them without interning. `make test` and `make m4-check` exit 0
on that branch (M4 terms unchanged). Branch evidence until merged.

`make m4-check` runs all twenty-six plus the persistence check; options
`M4_CHECK_ARGS="--scenarios-only"`, `"--per-prefix"`, `"--require-accepted"`.

Also on `main`:
- MAX (ADR-0059);
- BACK and TOP keep the TYPE (ADR-0058);
- the manual DrRacket checks (quit, Stop) passed.

**Persistence (proof of concept, `make test-m4-replay-persistence`;
ADR-0061, #165).** A game saved at the command prompt is restored by
deterministic replay in a fresh process. Its output and state are verified
against the native troll-combat run. Limits:
- It is not yet a player-facing save. `run-zork` writes no files.
- The game's own SAVE and RESTORE commands stay unsupported.

Evidence: [docs/evidence/M4](docs/evidence/M4/).

**Next steps** (epic #163; the failure inventory, the single-run runner and
the `make m4-check` scaffold are done):
1. Maintainer review of the provisional required-branch list
   (`gameplay-branches.json`).
2. Combat, death and recovery branches (the uncovered branches listed by
   `make m4-check`).
3. Lamp and clock events, objects, scoring.
4. RESTORE (INV-06) and player-facing saves, after an ADR-0055 amendment.

**Previous M3 S7 interactive terminal I/O (2026-11-23, `feat/m3-interactive-io`, ADR-0050):**
summarised above; details in [S7 evidence](docs/evidence/M3/S7-INTERACTIVE.md).
That record listed UNWIND under host errors (#139) as missing; it has since
been fixed on the branch (ADR-0051).

**Previous M3 S6 inert REP (2026-11-23, `feat/m3-startup-rep`, ADR-0049):**
By maintainer decision ("Inert REP + host loop") every session's GVAL of
REP is a predefined SUBR (`<TYPE ,REP>` is SUBR, `<SETG SAVEREP ,REP>` then
`<==? ,REP ,SAVEREP>` is T, as in pinned Confusion), but applying the default
REP by any path is a strict error: the runtime never provides a raw MDL
read-eval-print loop. The host top-level loop that will apply the current
GVAL of REP (by then the game's RDCOM) is specified in `docs/SEMANTICS.md`
but **not implemented**. The faithful `<SAVE-IT>` path now passes
77rooms.mud:301-302 (SAVEREP holds the REP SUBR, REP is RDCOM) and stops at
`<RESET ,INCHAN>` (77rooms.mud:303) with `mdl-eval: unassigned or
non-applicable MDL operator RESET` (known XFAIL, `make test-m3-saveit`).
Gate result for this slice: full gate PASS outside the sandbox (`make test`,
`test-historical`, `m3-source-progress`, `test-m3-historical-gc`,
`test-m3-start-back`, `test-m3-saveit`, `test-m3-andq`: all exit 0; see
`docs/evidence/M3/S6-REP.md`). RESET, the host loop, PRINC,
READSTRING, interactive input and smoke parity are unsupported.
**INITIALIZED, INTERACTIVE, SMOKE_PARITY and PLAYABLE have not passed; M3 is
incomplete.** Next: RESET of INCHAN. See
[S6 evidence](docs/evidence/M3/S6-REP.md).

**Previous M3 S5 SAVE session record (2026-11-23, `feat/m3-startup-save-record`, ADR-0048):**
By maintainer decision `<SAVE file-spec>` returns a fresh `"SAVED"`, writes
no file, performs no GC and no interrupt side effect, and appends a
host-visible session record (sequence, file-spec, INT-LEVEL); RESTORE stays
refused. `"BLOCKED"` registers like IPC but can never fire. The faithful
path (`<FLOAD "77loadall.mud">` then `<SAVE-IT>`) now records SAVE of
`"<MDL>MADADV.SAVE"` at INT-LEVEL 100000, runs `<INT-LEVEL 0>`
(77rooms.mud:26), GETSYS, `ON "BLOCKED"` and START (welcome text), then
stops in CONTIN at `77rooms.mud:301` with `mdl-gval: unassigned MDL global
REP` (known XFAIL, `make test-m3-saveit`, 27 assertions). Gate result for
this slice: full gate PASS outside the sandbox at `fe495b1` (`make test`,
`test-historical`, `m3-source-progress`, `test-m3-historical-gc`,
`test-m3-start-back`, `test-m3-saveit`, `test-m3-andq`: all exit 0; see
`docs/evidence/M3/S5-SAVE-RECORD.md`). RESET, the
LISTEN/REP loop, PRINC, READSTRING, interactive input and smoke parity are
unsupported. **INITIALIZED, INTERACTIVE, SMOKE_PARITY and PLAYABLE have not
passed; M3 is incomplete.** Next: a maintainer decision and slice for the
GVAL of REP and the LISTEN loop that applies it. See
[S5 evidence](docs/evidence/M3/S5-SAVE-RECORD.md).

**Previous M3 BACK follow-up (2026-11-22, `feat/m3-back-continuation`):**
The unchanged source chain still loads 1,229 forms with zero skips.
Manual and pinned Confusion cases support BACK on shared array views and
the terminal CHANNEL predecessor slot. Direct original START now passes
RANDOM and BACK, then stops at unassigned `TENEX?` in
`77rooms.mud:298`. The source's startup wrappers set that platform global
through GETSYS before START; the next slice must probe their execution.
`TMPDIR=/tmp make test` exits 0 with 2,009 Racket checks and 23 Python
tests; `TMPDIR=/tmp make m2-check` exits 0.
`TMPDIR=/tmp make test-m3-start-back` exits 0 with six source-backed
assertions for this known XFAIL. See [BACK evidence](docs/evidence/M3/BACK-CONTIN.md).
GETSYS, the full startup prelude, RESET, READSTRING, interactive input and
house smoke parity remain unsupported or unverified. **INITIALIZED,
INTERACTIVE, SMOKE_PARITY and PLAYABLE have not passed; M3 is incomplete.**
Next: execute the original startup prelude through its next real failure.

**Previous M3 RNG follow-up (2026-11-22, `feat/m3-session-random`):**
The unchanged source chain still loads all 1,229 forms with zero skips.
Session-owned 36-bit RANDOM advances original START through its one-seed
call; it now stops at unassigned `BACK` in `77rooms.mud:297`, after the
welcome output. `TMPDIR=/tmp make test` passes 1,996 Racket checks and 23
Python tests; `TMPDIR=/tmp make test-m3-start-random` passes six assertions
while recording BACK as the known XFAIL frontier. The pinned Confusion
negative-seed range deviation is recorded in
[RANDOM evidence](docs/evidence/M3/RANDOM-START.md). BACK, RESET,
READSTRING, interactive input, and house smoke parity remain unsupported
or unverified. **INITIALIZED, INTERACTIVE, SMOKE_PARITY and PLAYABLE have
not passed; M3 is incomplete.** Next: probe and implement the original
CONTIN path's BACK operation, then continue toward terminal input.

**Previous M3 source-load checkpoint (2026-11-22, `feat/m3-logical-gc`):**
`TMPDIR=/tmp make m3-source-progress` verifies all 1,229 forms in the unchanged
`77loadall.mud` chain, zero skipped, loader exit 0, and the approved source
hashes. `TMPDIR=/tmp make test` passes 1,471 Racket checks and 23 Python
tests; `TMPDIR=/tmp make m2-check` exits 0. Logical GC accounting, the
original GC handler lifecycle, additional language primitives, and default
terminal CHANNEL metadata enabled this load. Explicit GC is bounded to
tracked LIST, VECTOR and UVECTOR backing storage; historical automatic
collection timing and other allocations remain unmodeled. A direct call to
the original `START` emits the welcome line and newline, then stops at
unassigned `RANDOM`. **INITIALIZED, INTERACTIVE,
SMOKE_PARITY, and PLAYABLE remain NOT RUN or FAIL; M3 is not accepted.**
Reproduce with `TMPDIR=/tmp make test`, `TMPDIR=/tmp make m2-check`, and
`TMPDIR=/tmp make m3-source-progress`. See the
[WIP evidence](docs/evidence/M3/WIP-SOURCE-LOAD.md). Next: implement a
reference-validated session RNG, then terminal input and a strict `m3-check` with
the approved house smoke transcript.

**Previous M3 interrupt foundation checkpoint (2026-11-22, issue #104):**
The reviewed branch `feat/m3-interrupt-dispatcher` adds session-owned interrupt
dispatch, priority and pending-event scheduling, `INT-LEVEL`, `ENABLE`,
and `DISABLE`. Focused deterministic callbacks are verified (scoped Gate A
PASS); real GC delivery and historical automatic collection remain blocked
by missing MDL reclaimed-word accounting and event scheduling. Gate B and
the formal M3 gate are incomplete. Reproduce with
`TMPDIR=/tmp raco test tests/interrupt_dispatch_test.rkt
tests/event_registration_test.rkt`, `TMPDIR=/tmp make test`,
`TMPDIR=/tmp make m2-check`, and `TMPDIR=/tmp make m3-source-progress`.
The loader still exits 1 after **433 original forms and zero skips** at
`77rooms.mud` expression 16, line 101, `EVENT "GC"`; source loading,
initialization, interactive gameplay and house-smoke parity remain
unverified. See [interrupt evidence](docs/evidence/M3/INTERRUPT-FOUNDATION.md)
and [issue #104](https://github.com/quaat/mdl-racket/issues/104).

**Current M3 checkpoint (2026-11-21, `feat/m3-event-handler`):**
The scoped [issue #102](docs/evidence/M3/EVENT-REGISTRATION.md) change
represents user-defined EVENT IHEADERs and HANDLERs as session-owned
objects, with identity, registration, removal and reattachment. External
events and callback dispatch remain unsupported and fail explicitly; this
build does not substitute Confusion's `T` stubs for interrupt semantics.
The unchanged source loader completes **433 original forms with zero
skips**, then exits 1 at `77rooms.mud` expression 16, line 101:
`EVENT "GC"` requires actual GC callback delivery.
`make m3-source-progress` exits 0 only as a partial measurement. `make test`
and `make m2-check` pass; see the [evidence](docs/evidence/M3/EVENT-REGISTRATION.md).
M0/M1/M2 remain PASS; the formal M3 gate is **INCOMPLETE**. Full source
load, initialization, interactive input, smoke parity and gameplay are
unverified. Next: [issue #104](https://github.com/quaat/mdl-racket/issues/104)
under [event issue #71](https://github.com/quaat/mdl-racket/issues/71).

**Previous M3 checkpoint (issue #100):**
The scoped [issue #100](docs/evidence/M3/DUPLICATE-DECL.md) change retains
both Patterns when an ATOM appears twice in one attached `#DECL` and checks
both in source order. The manual does not state duplicate precedence;
conjunction is a documented conservative inference. The unchanged source
loader completes **430 original forms with zero skips**, fully loading
`77act1.mud`, `77act2.mud` and `77act3.mud`, then exits 1 at
`77rooms.mud` expression 13, line 92: unsupported `HANDLER`. The latter is
tracked in [issue #102](https://github.com/quaat/mdl-racket/issues/102),
under event API issue #71. `make m3-source-progress` exits 0 only as a
partial measurement. `make test` and `make m2-check` pass; see the
[evidence](docs/evidence/M3/DUPLICATE-DECL.md). M0/M1/M2 remain PASS;
the formal M3 gate remains **INCOMPLETE**. Full source load,
initialization, interactive input, smoke parity and gameplay are unverified.

**Previous M3 checkpoint (issue #98):**
The scoped [issue #98](docs/evidence/M3/DEFERRED-DECL-TYPE.md) change
retains an unresolved TYPE atom in an attached `#DECL` until a value is
checked. An unresolved name still raises an error at check time; explicit
`DECL?` still rejects it immediately. The unchanged source loader completes
**363 original forms with zero skips**, fully loading `77act1.mud`, then
exits 1 at `77act2.mud` expression 39, line 424: duplicate declaration
for `M` in `BALLOON`. `make m3-source-progress` exits 0 only as a partial
measurement. `make test` and `make m2-check` pass; see the
[evidence](docs/evidence/M3/DEFERRED-DECL-TYPE.md). M0/M1/M2 remain PASS;
the formal M3 gate is **INCOMPLETE**. Full source load, initialization,
interactive input, smoke parity and gameplay remain unverified. Next:
[issue #100](https://github.com/quaat/mdl-racket/issues/100).

**Previous M3 checkpoint (issue #96):**
The scoped [issue #96](docs/evidence/M3/NTH-DECL.md) change implements
positive-count `[n Pattern ...]` repetition in structured declarations,
including attached `#DECL` and NEWTYPE patterns. It rejects malformed
counts and short values and matches large counts without expanding them.
The unchanged source loader completes **233 original forms with zero skips**,
then exits 1 at `77act1.mud` expression 55, line 740: unknown declaration
type `PRSOBJ`. `make m3-source-progress` exits 0 as a partial-progress
measurement. `make test` and `make m2-check` pass; see the
[evidence](docs/evidence/M3/NTH-DECL.md) for native probes, exact commands,
and the one documented Confusion deviation. The formal M3 gate remains
**INCOMPLETE**: full load, initialization, interactive input, smoke parity,
and gameplay are unverified. The next task is
[issue #98](https://github.com/quaat/mdl-racket/issues/98) addressed above.

**Previous M3 checkpoint (issue #94):**
The scoped [issue #94](docs/evidence/M3/PERCENT-READ.md) change implements
session-aware `%` evaluation during executable reading, `ASCII`, and
CHARACTER arguments to `STRING`. The syntax-only parser remains free of
MDL side effects; `%%` and mutable read tables remain unsupported.
The unchanged source loader completes **188 original forms with zero
skips**, fully loading `81tell-repl.mud`, then exits 1 at
`77act1.mud` expression 10, line 78: unsupported `[3 ANY]` NTH
declaration repetition. `make m3-source-progress` exits 0 only as a
validated partial-load measurement. `make test` and `make m2-check`
pass on this branch; see the [evidence](docs/evidence/M3/PERCENT-READ.md)
for counts, native probes and reproduction commands. M0/M1/M2 remain
PASS; the formal M3 gate remains **INCOMPLETE**. Full source load,
initialization, interactive input, smoke parity and gameplay are unverified.
The next task is [issue #96](https://github.com/quaat/mdl-racket/issues/96):
probe and implement the NTH declaration Pattern without changing the
locked source.

**Previous integrated main checkpoint:** The authorized M2 stack, PRs #54, #59,
#61, #62, #64, #66, #68 and #70, is integrated on `main` at `7d34195`.
The [M2 mainline gate](docs/evidence/M2/MAINLINE-GATE.md) passes at its
accepted `7d34195` baseline. The permanent M2 suite now loads a bounded,
SHA-verified original-source prefix: `make m2-check` exits 0 with 986
Racket checks, 22 Python tests, and 58 G3 assertions. It includes original VFLOAD,
MSETG, PSETG and FLAGWORD, MAPF, indirect APPLY, declarations, macro
expansion, activation control, aliasing and session isolation. The
[requirements audit](docs/evidence/M2/REQUIREMENTS-AUDIT.md) lists tested
capabilities and limits. Reproduce after `make reference-build` with
`make m2-check`; the complete loader command is below.
The separate [M3 source-progress gate](docs/evidence/M3/SOURCE-PROGRESS.md),
`make m3-source-progress`, verifies 36 parsed historical text files. The
[predicate and ROOT slice](docs/evidence/M3/EMPTYQ.md) advanced the
unchanged `77loadall.mud` chain from 24 to 26 completed forms. The
[three-argument NEWTYPE slice](docs/evidence/M3/NEWTYPE-DECL.md) advanced
it to 36 forms, and the [GDECL slice](docs/evidence/M3/GDECL.md) to 37.
The [eager AND? slice](docs/evidence/M3/ANDQ.md) reached 70 forms.
The [quoted OPTIONAL default slice](docs/evidence/M3/QUOTED-OPTIONAL.md)
reached 87 forms. The [APPLICABLE declaration slice](docs/evidence/M3/APPLICABLE-DECL.md)
reached 112 and loaded `77defs.mud` in full.
The [`%<>` slice](docs/evidence/M3/PERCENT-EMPTY.md) reached 136 forms
and loaded `77makstr.mud` in full. The
[`#PSTRING 0` typed literal slice](docs/evidence/M3/PSTRING-LITERAL.md)
reached 144 forms. The
[positional `#DECL` slice](docs/evidence/M3/FUNCTION-DECL.md)
reached 157 forms. The earlier
[`!\ ` CHARACTER slice](docs/evidence/M3/SPACE-CHARACTER.md)
keeps 157 completed, zero skipped forms and moves the first failure
within `81tell-repl.mud` expression 23 to `%<STRING <ASCII 10>>`,
tracked in [issue #94](https://github.com/quaat/mdl-racket/issues/94).
NEWTYPE stores and checks its optional
declaration Pattern; GDECL installs and checks global value Patterns.
Pinned Confusion silently omits both checks, explicit reference
deviations. Its direct `DECL?` handling of `APPLICABLE` also errors,
while the Racket Pattern follows the MDL manual and native
`APPLICABLE?` type observations. `ASSIGNED?` with ENV remains unsupported;
`%%` read macros and mutable read tables remain unsupported;
custom `#type` literals currently support only integer WORD data;
positional `#DECL` is validated as metadata but is not enforced on FUNCTION,
matching the pinned reference;
full source loading, game boot and gameplay
parity are unverified. Reproduce with `make test`, `make m2-check`, and
`make m3-source-progress` after `make reference-build`.
Explicit CLOSURE, MAPR, TAG, resumable ERROR/ERRET, full loader completion,
parser/game boot and gameplay remain unsupported or unverified. Random/event
APIs are tracked as [M3 issue #71](https://github.com/quaat/mdl-racket/issues/71).
See [current status](docs/STATUS.md).
Historical progress notes below preserve
their original slice-level context.

**M2 G3 correction on `feat/m2-structural-neq`:** structural `N=?`
passes 13 focused checks and `make test` (879 Racket, 13 Python). The
original MSETG repeat path now reaches a separate computed-global reader
defect at `,.FOO` ([issue #58](https://github.com/quaat/mdl-racket/issues/58));
G3 remains FAIL and M2 remains open. See [N=? evidence](docs/evidence/M2/NEQ.md).

**Stacked reader correction (issue #58):** `,.FOO` now evaluates the local
FOO to obtain the global atom, as in the MDL manual and pinned Confusion.
The original `MSETG` equal-repeat path passes from hash-verified `81prim.mud`.
`make test` passes 884 Racket checks and 13 Python tests;
`make test-historical` passes the VFLOAD, DECL, and MSETG repeat probes.
The conflicting-repeat path reaches unsupported `ERROR`, so **G3 remains
FAIL**. The full source load still stops after 24 expressions at `EMPTY?`.
Reproduce with those two make targets and the loader command below; see
[reader evidence](docs/evidence/M2/COMPUTED-GLOBAL.md). Next: implement
the reference-backed `ERROR` path, then rerun G3. M3 has not started.

**Stacked `ERROR` correction (issue #60):** the source-defined `MSETG`
conflicting-repeat path raises an observable `ALREADY-GASSIGNED` exception.
`make test` passes 888 Racket checks and 13 Python tests;
`make test-historical` passes the original MSETG error probe too. Pinned
Confusion outputs and the non-resumable Racket deviation are in
[ERROR evidence](docs/evidence/M2/ERROR.md). Integrated G3 remains FAIL
at the next source-backed dependency; no game boot or gameplay parity is claimed.

**Earlier current-head G3 run:** `make test-m2-g3` exits 2 after 48 passing
integrated assertions because original `PSETG` reaches unassigned `MEMQ`
after its initial side effects. Original MSETG first/equal/conflict paths
pass. The exact-source chain still stops at `EMPTY?` after 24 expressions;
G3 and M2 remain **FAIL**. Reproduce with `make test-m2-g3`; see
[G3 evidence](docs/evidence/M2/G3-GATE.md). Next correction: issue #63
`MEMQ`, followed by a fresh G3 run. M3 remains unstarted.

**Current MEMQ/G3 result:** Original `PSETG` first/repeat calls now pass
using `==?` membership and shared REST views. `make test` exits 0 with
903 Racket checks and 13 Python tests; `make test-historical` exits 0
with VFLOAD 23, DECL 21, MSETG, and PSETG probes. `make test-m2-g3`
exits **2** after 52 passing integrated assertions: original `FLAGWORD`
reaches unsupported `MAPF`, while pinned Confusion returns `1` for its
empty-TUPLE call. G3 and M2 remain **FAIL**; M3 is unstarted. Reproduce
with those make targets; see [MEMQ evidence](docs/evidence/M2/MEMQ.md)
and [updated G3 evidence](docs/evidence/M2/G3-GATE.md). Next: issue #65.

The [M2 G0 source-readiness audit](docs/evidence/M2/SOURCE-READINESS.md)
passes: the baseline and pinned source are reproducible, and the first
historical load barriers are identified. Run
`racket scripts/audit_source_readiness.rkt` to reproduce its probes. The
[G1 local source loader](docs/evidence/M2/SOURCE-LOADER.md) executes the
existing MDL subset across files in a shared session and supports constrained
nested `FLOAD`. Its G1 local gate passes, including review regressions for
symlink lookup order, consecutive parent components, and interpreted session
calls; `make test`, both CI workflows, and the pinned Confusion
build/capture/probes pass. Reproduce its pinned-source failure with
`racket scripts/mdl_load.rkt --source-root .cache/upstream/mdlzork/mdlzork_771212/patched_confusion --entry 77loadall.mud --report artifacts/m2/source-load.json`.
That command exits 1 after **twenty-four** completed expressions, at the
`EMPTY?` primitive called by the original source-defined `NEWSTRUC` in
`77defs.mud` expression 15 (with D5's atom-property `PUT`/`GET`
associations, `81prim.mud` loads in full — including the original
`PSETG` with its structured declaration — and `77defs.mud` expressions
1–14 execute, including the historical
`<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>` declaration property);
game initialization is not supported. The
[G2 partial-source probe](docs/evidence/M2/HISTORICAL-VFLOAD.md) verifies
the pinned source hash and invokes the unmodified reconstructed `VFLOAD`
definition on a controlled file with matching Confusion output and state.
Its local gate passes; after two native CI failures for missing Racket
libraries, both workflows passed on the corrected dependency commit. The
latest G1 path fix is merged and passes locally, with combined-branch CI
also passing. Run
`make test-historical` to reproduce the probe. That G2 probe reports its 12
unexecuted forms explicitly. M2's integrated gate and gameplay remain
unverified; the current sequential loader blocker is `EMPTY?` inside
`77defs.mud`'s `NEWSTRUC`.
The [M2 source execution inventory](docs/evidence/M2/SOURCE-EXECUTION.md)
lists the loaded, invoked, blocked, and untested definitions separately.

The [MUDDLE slice](docs/evidence/M2/MUDDLE.md) binds the
interpreter-supplied version global `MUDDLE` to the pinned reference's
FIX `101` in every fresh session, so the `77defs.mud` version guard
short-circuits exactly like the reference. Its local gate is **PASS**.
The [structured declaration slice](docs/evidence/M2/DECLARATION-PATTERNS.md)
implements chapter-14 `<struc [REST ...]>` patterns for LIST, VECTOR,
UVECTOR, and TUPLE with required element prefixes, cyclic multi-pattern
REST repetition, nested `<OR ...>`, bounded traversal with explicit
cycle/depth errors, and the reference's `DECL?` payload distinction
(overall-type mismatch returns bare `#FALSE ()`; an element mismatch
carries the offending element). Its local gate is **PASS**, verified
against 22 pinned Confusion success observations and 14 deliberate-error
observations.
The [SEGMENT slice](docs/evidence/M2/SEGMENTS.md) implements chapter-7
SEGMENT evaluation: `!.ATOM`, `!,ATOM`, and `!<FORM...>` splice their
value's elements into LIST, VECTOR, UVECTOR, and FORM-argument construction
in strict left-to-right order, a final LIST-valued segment shares the
payload's tail (mutation visible through both), quoted structures keep
segments as data, and standalone or non-structured segment results raise
the reference's ILLEGAL-SEGMENT. Its local gate is **PASS**, verified
against 18 pinned Confusion success observations and 10 deliberate-error
observations.
The [declaration slice](docs/evidence/M2/DECLARATIONS.md) implements
chapter-14 `#DECL` for `DEFINE`, `DEFMAC`, `PROG`, and `REPEAT` in both
compiled and interpreted paths, checks bound formals, OPTIONAL/AUX
initializers, later `SET`s, and results against `ANY`, registered type
atoms, `<OR ...>`, and `<PRIMTYPE type>` patterns, and adds `DECL?`,
`GASSIGNED?`, and `MANIFEST` with the manifest-gated `SETG`. The unmodified
original `MSETG` installs and executes; thirteen pinned Confusion
observations back the semantics, and the deviations (Confusion does not
enforce attached declarations; the `DECL?` false payload follows Confusion)
are recorded in the slice evidence. Its local gate is **PASS**.

## Goals

1. Execute original MDL game code, not a newly designed text-adventure engine.
2. Keep the MIT 1977 source unchanged; track reconstructive patches separately.
3. Establish a working Confusion oracle and differential tests before translating
   complex semantics.
4. Build a source-located MDL parser and a `#lang mdl` implementation in Racket.
5. Eventually offer a browser UI; choose a server-backed Racket runtime first,
   and only commit to client-side WASM after feasibility experiments.
6. Keep research evidence in the repository: sources, tests, deviations, decisions,
   and reproducibility details.

## Prerequisites (Linux)

- Racket (the harness targets modern Racket; compatibility must be confirmed on
  your installed release)
- Python 3.11+ and `venv`/`pip`
- Git, GCC/G++, GNU Make, Perl, and `libgc-dev` for the patched Confusion interpreter
- Internet access to fetch source checkouts and Python packages

Ubuntu/Debian example:

```bash
sudo apt-get update
sudo apt-get install -y racket git build-essential make perl libgc-dev python3-venv
```

## Installation

```bash
unzip mdl-racket-zork-harness.zip
cd mdl-racket-zork-harness
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
raco pkg install --auto --link
make doctor
make test
```

`make doctor` reports detected tools and fails only if required commands are
missing. Successful detection does not mean the Racket tests or Confusion
gameplay have passed; run the validation targets explicitly.

`make test` requires Racket and the locally linked Racket package. It tests
**the bootstrap reader/compiler, implemented M1 primitives, and the documented
M2 control, formals, and macro slices**, not the original Zork
game. If `raco` reports that the package is already installed, inspect
`raco pkg show` rather than blindly reinstalling it.

### CI Racket installation

The GitHub Actions jobs use the Racket project's minimal `8.10-bc` Docker
image, pinned by digest, so each job starts with Racket installed. The harness
job installs `compiler-lib`, `rackunit-lib`, and `compatibility-lib` for the
test suite; the native reference job installs its C++ build tools. The
measured pilot and the apt alternatives are in
[the CI setup report](docs/evidence/M2/CI-SETUP.md). Run `make test` locally;
the CI harness uses `scripts/test_racket.sh` for the same Racket test list.
This CI setup passes both workflows, while the M2 game execution gate remains
open.

### Source checkout and historical reference

```bash
make sources               # downloads/locks original upstream checkouts
make reference-build       # builds native Confusion (may need toolchain fixes)
make reference-capture     # saves a JSON capture in artifacts/reference/house.json
make check-source          # sweeps selected 1977 text files with the Racket reader
make reference-probe       # captures isolated Confusion primitive observations
```

Reference source paths are:

- `.cache/upstream/mit_zork/zork/` — original MIT 1977 release
- `.cache/upstream/mdlzork/mdlzork_771212/patched_confusion/` — playable reconstruction
- `.cache/upstream/mdlzork/confusion_patched/` — patched C++ MDL interpreter

All `.cache` paths are excluded from Git. `sources.lock.json` pins the commits.
The `fetch_sources.py` script refuses to replace modified upstream checkouts.

Once a candidate game implementation exists, it must emit a JSON transcript
in the [documented interchange format](docs/TESTING.md):

```bash
python scripts/compare_transcripts.py \
  artifacts/reference/house.json artifacts/candidate/house.json
```

**No candidate transcript in this interchange format is produced yet.** On
`main` the original game runs in Racket for the six-command
house-boot scenario; the strict differential SMOKE_PARITY gate uses its own
record format and comparator (`scripts/smoke_parity.py`, `make m3-check`,
ADR-0053) and PASSES on `main` (see [STATUS](docs/STATUS.md)).

## Play locally (preview)

A thin local launcher runs the unchanged December 1977 source on this runtime
through the faithful `run.mud` path (`<FLOAD "77loadall.mud">`, then SAVE-IT
through the host loop). It is a **preview, not a PLAYABLE claim**: the
PLAYABLE and SMOKE_PARITY gates have not passed.

Setup: Racket (CI uses 8.10 BC; the launcher tests were run locally on 7.9 BC)
with the repository as a collection root (`raco pkg install --auto --link`, or
`export PLTCOLLECTS=":$PWD"`), then `make sources` to fetch the pinned game
directory `.cache/upstream/mdlzork/mdlzork_771212/patched_confusion/`.

```bash
make play                                   # or: racket zork/cli.rkt
racket zork/cli.rkt --fixed-clock 250776000 # fixed session clock (UTC), reproducible
racket zork/cli.rkt --no-notice             # omit the launcher notice
```

From DrRacket, open `zork/main.rkt` and click Run (it only defines the
library; nothing starts), or evaluate `(require zork)`; then call `(run-zork)`
in the interactions window and type commands into its input box. `run-zork`
creates a fresh session each call and **returns** a `zork-result` (`'quit`,
`'quit-after-mdl-error` or `'input-exhausted`); it never exits Racket. Stop
(a break) ends the game with `exn:break` and leaves DrRacket running. Strict
failures are raised, not swallowed. Options: `#:input`, `#:output`,
`#:source-root`, `#:clock`, `#:time-zone`, `#:notice? #f`.

| Exit code (`zork/cli.rkt`) | Meaning |
| --- | --- |
| 0 | the game quit normally (`'quit`) |
| 3 | the game quit after an MDL error (`'quit-after-mdl-error`) |
| 4 | input ended (EOF) before the game quit (`'input-exhausted`) |
| 1 | strict failure (unsupported construct, load not PASS); message on stderr |
| 2 | usage error, or the pinned game sources are missing (`make sources`) |
| 130 | interrupted (Ctrl-C) |

Disclosed limitations: SAVE makes an in-session record only and RESTORE is
unsupported (ADR-0048); the game never writes files (OPEN is denied except
read-only access to the two help/info files, ADR-0055; the launcher also
refuses file writes and network use under a
security guard); unsupported constructs stop the game strictly with an error
instead of being approximated. Known gaps include `put X in` (stops with a
strict failure in the parser path: unsupported TOP per the S11 record, or an
unsupported built-in CHTYPE conversion from the opening room) and file I/O
commands such as `script` (prints `I can't open the script channel.`);
`help` and `info` read only their two pinned files (ADR-0055 amendment).
There is no MDL REPL, evaluator, web server or persistence. Tests:
`make test-m3-launcher`; evidence:
[S12 launcher record](docs/evidence/M3/S12-LAUNCHER.md).

## Current implementation and milestone evidence

M0 passed its source, reader, native Confusion, test, and approved golden
transcript gates. M1's [FALSE slice](https://github.com/quaat/mdl-racket/pull/10),
[atoms](https://github.com/quaat/mdl-racket/pull/12),
[sequences](https://github.com/quaat/mdl-racket/pull/13),
[types](https://github.com/quaat/mdl-racket/pull/14),
[bindings](https://github.com/quaat/mdl-racket/pull/15),
[36-bit words](https://github.com/quaat/mdl-racket/pull/16), and
[integrated gate audit](https://github.com/quaat/mdl-racket/pull/18) are merged.
The M1 gate is **PASS on `main`** at merge commit
`a68cbb970b7028853fbcf7885c6c7c42f9470fe5`: 274 Racket checks and 13 Python
tests pass, all 36 selected historical text files parse, and 60 successful
Confusion cases plus six expected error observations reproduce their saved
results. The fresh native build changes its binary hash and embedded build
timestamp; the approved five-turn transcript matches after excluding those
fields and capture time. See the M1 gate report for the comparison contract.
The first M2 slice adds unnamed `PROG` auxiliary frames and bare `RETURN`
within the current function. Its local tests and focused Confusion probes pass;
the **M2 milestone gate is not yet PASS**. See the
[M2 PROG report](docs/evidence/M2/PROG.md) and
[issue #20](https://github.com/quaat/mdl-racket/issues/20). Confusion crashes on
`RETURN` during auxiliary initialization; that reference deviation is recorded
in the report.
The [activation-frame hardening slice](docs/evidence/M2/ACTIVATIONS.md)
records function ownership and frame lifetime before broader control flow.
The [cyclic equality hardening slice](docs/evidence/M2/EQUALITY.md) makes `=?`
terminate on tested self-referencing values and reports unresolved distinct
cycles explicitly. M2's integrated gate remains open.
The [REPEAT/AGAIN slice](docs/evidence/M2/REPEAT.md) adds unnamed `REPEAT`
and bare `AGAIN` in the current function; auxiliaries are bound once across
restarts. The [named activation slice](docs/evidence/M2/ACTIVATION-TARGETS.md)
adds named `PROG`/`REPEAT` frames and explicit `RETURN`/`AGAIN` targets,
including transfers from called functions.
The [function formals slice](docs/evidence/M2/FORMALS.md) adds the
historical `DEFINE` formal sections `"OPTIONAL"`, `"AUX"`, `"TUPLE"`, and
`"ARGS"` with in-frame defaults, TUPLE-typed rest values, and historical
arity error names.
The [control slice](docs/evidence/M2/CONTROL.md) adds function activation
formals (the leading `DEFINE` self-atom used by the 1977 sources and the
`"NAME"`/`"ACT"` markers) with explicit RETURN/AGAIN to a function's own
activation, `GO` to labels in the current function's PROG/REPEAT (manual
based; Confusion has no GO), and `UNWIND` cleanup on nonlocal transfers.
`"BIND"`/`"CALL"` markers, `TAG`, `GO` across function boundaries, and
source loading remain unsupported.
The [macro slice](docs/evidence/M2/MACROS.md) adds `DEFMAC`, first-class
FORM construction and evaluation, one-step `EXPAND`, and quoted formals.
Its local gate is **PASS**: `make test` passes 513 Racket checks and 13 Python
tests; 25 isolated pinned Confusion success cases, ten review-regression
cases, and eight separate error observations reproduce their saved outputs.
The [review follow-up](docs/evidence/M2/MACROS.md#review-follow-up) covers
empty interpreted PROG/REPEAT auxiliaries and leading activation names with
quoted formals. This is an M2 slice result; the
M2 milestone remains open until original source definitions execute.
Reproduce the checks with
`make test`, `make sources`, `make check-source`,
`make reference-build`, `make reference-capture`, and `make reference-probe`.
See the [M0 report](docs/evidence/M0/REPORT.md),
[M1 FALSE report](docs/evidence/M1/REPORT.md),
[M1 atom report](docs/evidence/M1/ATOMS.md),
[M1 sequence report](docs/evidence/M1/SEQUENCES.md),
[M1 type report](docs/evidence/M1/TYPES.md),
[M1 binding report](docs/evidence/M1/BINDINGS.md),
[M1 word report](docs/evidence/M1/WORDS.md),
[M1 gate report](docs/evidence/M1/GATE.md), and
[current gate status](docs/STATUS.md) for hashes, outputs, and limits.

- A custom `#lang mdl` reader for a small subset of angle-bracket MDL syntax.
- Source-located AST nodes and a conservative compiler.
- Basic `DEFINE` with simple parameters, `SETG`, `GVAL`, local/global references,
  arithmetic, comparisons, and a few collection forms.
- First-class MDL FALSE literals with mutable payloads, distinct from the `NIL` atom;
  stable literal identity across function calls; value-preserving `NOT`, `AND`,
  `OR`, and `COND` truth behavior; and limited `TYPE` recognition for FALSE and
  ATOM and OBLIST values.
- Identity-bearing ATOM values, named OBLISTs, lookup/insertion/removal, and
  explicit `!-` OBLIST trailers on reader atom literals.
- Mutable LIST, VECTOR, and UVECTOR values with shared `REST` views,
  1-based `NTH`/`PUT`, LIST `PUTREST`, and uniform UVECTOR element checks.
- Type tags and structured `CHTYPE`, with `PRIMTYPE`, `TYPEPRIM`, and `NEWTYPE`
  for the documented subset.
- Atom-keyed local/global values with dynamic parameter frames, `VALUE`
  lookup, and global unassignment on the supported subset.
- Historical 36-bit FIX and WORD behavior for the documented arithmetic,
  octal, bitwise, shift, and bit field subset.
- Unnamed `PROG` with sequential auxiliary initialization and bare `RETURN`
  from the closest PROG in the current function.
- `DEFINE` formal-list sections marked by strings — `"OPTIONAL"`, `"AUX"`,
  `"TUPLE"`, and `"ARGS"` — with defaults evaluated in the growing function
  frame, unassigned optional/auxiliary bindings, TUPLE-typed rest values
  (TYPE and PRIMTYPE `TUPLE`), and historical arity error names.
- Function activation formals: the leading `DEFINE` self-atom and the
  `"NAME"`/`"ACT"` markers bind a function's own ACTIVATION, targetable by
  explicit `RETURN`/`AGAIN` from any depth, with `AGAIN` re-running the body
  without re-binding.
- `GO` to top-level labels in the current function's PROG/REPEAT bodies,
  with labels skipped in normal flow, and `UNWIND` cleanup expressions that
  run when an MDL nonlocal transfer (RETURN, AGAIN, GO, MAPLEAVE/MAPRET/MAPSTOP)
  crosses below them. A raised error never runs them and propagates
  unchanged ([ADR-0051](docs/DECISIONS.md), [evidence](docs/evidence/M3/I139-UNWIND.md)).
- `DEFMAC` calls with runtime expansion, FORM values and `EXPAND`, quoted
  formals, and caller-frame evaluation of plain and TUPLE arguments.
- An intentionally incomplete compatibility runtime.
- Parser smoke tests, compile tests, native Confusion reference scripts,
  transcript comparison, and offline Python harness tests.

The list above is the M0-M2 baseline. Later M3 slices (NTH repetition,
declarations, events, interrupts and more on `main`; full source loading,
SPECIAL/UNSPECIAL wrappers, BLOCK/`.OBLIST`, BACK, STRING views, RANDOM,
PDP-10 FLOAT word images, startup and terminal I/O; on `main` since the M3 acceptance) are
specified in [SEMANTICS](docs/SEMANTICS.md) and tracked in
[STATUS](docs/STATUS.md).

**Not supported yet (2026-11-23, `main`):** complete original MDL
syntax, compile-time macro expansion, `[OPT ...]` declarations, GROW and
BYTES views, explicit environments, the `"BIND"`/`"CALL"` activation
formals, TAG values and `GO` across function boundaries, ILIST,
PRINT, CLOSE and file OPEN modes other than RECORD's denied form, RESTORE, FLOAT printing and FIX→FLOAT CHTYPE, automatic
event sources other than the logical GC model, an interactive error level,
gameplay beyond the recorded M4 scenarios, and client-side web execution.
Unsupported compile constructs fail with errors; the reader's acceptance of a
construct does not imply implemented semantics.

The current milestone is [M3: the actual 1977 game boots in Racket](docs/PLAN.md).
Its gate requires the approved house-smoke transcript; it does not assume a
new game engine.

## Working with Codex

Start at [`AGENTS.md`](AGENTS.md), then [`docs/CODEX_START.md`](docs/CODEX_START.md).
The plan and precise gates are in [`docs/PLAN.md`](docs/PLAN.md). Treat
[`docs/STATUS.md`](docs/STATUS.md) as the current source of truth: never label
any untested target as passing.

For each milestone, follow the first unmet gate in `docs/STATUS.md`, record
the evidence, and update this README when the gate result changes.

## Sources, provenance, licensing

- [MITDDC/zork](https://github.com/MITDDC/zork) — original historical sources;
  MIT-0 **to the extent MIT holds rights**.
- [heasm66/mdlzork](https://github.com/heasm66/mdlzork) — reconstructed
  December 1977 game and patched Confusion.
- Confusion is **GPLv3**; the reconstructed gameplay imports later Zork
  material. Review rights before redistributing binaries, sources, or hosted
  commercial variants. The harness MIT-0 license does **not** override upstream
  licenses. See [`docs/PROVENANCE.md`](docs/PROVENANCE.md).

This repository is an independent development scaffold. Local Racket and
Confusion checks, remote CI, and golden review completed on 2026-11-17.
See [`docs/STATUS.md`](docs/STATUS.md) for explicit M0 evidence and M1 limits.

## MDL language conformance

L0 is in progress. Run `make install` and `make test-manual` for an
isolated corpus of MDL manual examples. On Racket 8.10 BC the current
corpus records 72 passing loader/frontend checks and 16 tracked gaps.
The language-conformance workflow also checks the harness and reproducibility
of the historical inventory. The Zork gates run separately. Explicit associations
(`PUTPROP`, `GETPROP`) and general `EVAL` remain pending.
See the [coverage matrix](docs/conformance/MDL-COVERAGE.md),
[verification evidence](docs/evidence/L0/BASELINE.md) and
[L1 backlog](docs/conformance/PLAN.md).
