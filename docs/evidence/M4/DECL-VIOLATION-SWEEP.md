# M4 #196: attached-declaration violation sweep (diagnostic only)

> **Decision taken (2026-11-26, M4 S16):** option 2a. Attached `#DECL`s are
> no longer enforced in production (the attached-declaration ADR amendment);
> balloon-ledge is a gated scenario and `make xfail-m4-balloon-frontier` is
> retired. The recorder and `make m4-decl-sweep` remain the diagnostic; the
> sweep now runs each unit with and without the recorder. The text below is
> the record of the original sweep; the re-run after the decision is at the
> end ("Re-run after the decision") and in
> [S16-ATTACHED-DECL.md](S16-ATTACHED-DECL.md).

Issue #196, INV-12. Maintainer decision 2026-11-26, "Sweep first": add a
host-only, test-only recorder for attached-declaration violations, run every
gated scenario and the balloon route with it, publish the violating sites,
then decide with real data.

This slice **gathers data only**. Production behaviour is unchanged and
strict. `run-zork`, the command line and the replay host never enable the
recorder, and `make xfail-m4-balloon-frontier` still XFAILs. No option below
is implemented.

Machine-readable result: [decl-violation-sweep.json](decl-violation-sweep.json).
Native probe capture: [decl-sweep-probes-reference.json](decl-sweep-probes-reference.json).

## Provenance

| Item | Value |
|---|---|
| Branch | `feat/m4-decl-sweep` (local, from `main` 58c3e4f); the report's `repository_commit` is the commit the sweep ran on |
| Upstream | `mdlzork` bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3, `mit_zork` d94501340842e006791fce0757dc0043b8ec8916 (`sources.lock.json`) |
| Reference | pinned Confusion `.cache/build/confusion_patched/mdli`, sha256 `6df359f6…b789` (checked before and after the probe capture) |
| Clock / RNG | fixed session clock, epoch 250776000 (1977-12-12 12:00 UTC), TZ UTC, microseconds 0; START seeds RANDOM from DSKDATE (seed 10438660480); no override, no seed search |
| Racket | v7.9 [bc] |

## The recorder

The recorder is specified in SEMANTICS, "Diagnostic-only: attached-declaration
violation recorder".

- **Interface.** `make-mdl-session #:decl-violation-recorder proc`. The
  keyword is threaded through `make-mdl-context` to `make-mdl-atom-space`
  and stored in an immutable atom-space field. It is read in exactly one
  place: the mismatch branch of `check-declared!`.
- **When it is set.** A failing attached check calls `proc` once with
  `binding`, `kind`, `pattern`, `value-type`, `value-summary`, `value`,
  `line` and `column`. The check then proceeds as if it had passed.
- **When it is absent.** The check raises the same
  `DECL l:c: X does not satisfy declaration` as before.
- **Checks it never touches.** DECL?, GDECL/SETG, positional declarations,
  CHTYPE, definition-time errors and errors raised while checking all stay
  strict.
- **Code changes on the strict path.** None beyond the new optional `kind`
  argument passed at the attached-check call sites.
- **Isolation tests.** `tests/decl_violation_recorder_test.rkt` checks
  isolation in two ways:
  - *Static (grep):* one read site; no mutator; not exported; not mentioned
    in `zork/*.rkt`, `mdl/replay.rkt`, the compiler, the parser or
    `#lang mdl`; no ROOT name.
  - *Behaviour:* the default session, `run-zork` and `replay-record` all
    fail strictly on a toy game's violation.

The test failed first on the unknown keyword (exit 1) and passes after the
change.

## Units

Every unit ran in its own racket process, one at a time, with the recorder
on. k is the number of READSTRING entries made when the violation happened,
so the violation belongs to command k (1-based).

| Unit | Class | Violations | Result with the recorder on (native comparison) |
|---|---|---|---|
| 24 gated scenarios (house-cellar … gas-room) | gated | **0** in every one | PASS: each scenario test module unchanged (every READSTRING entry's output and checkpoint, the whole transcript, the end state, the declared prefix re-runs) |
| balloon-ledge (81 commands) | frontier (INV-12) | 83 (2 sites) | **PASS: all 82 READSTRING entries match the committed native reference** (output and puzzles checkpoint), and so do the whole transcript, the end state and the re-run prefixes 52 and 60 |
| mswitch-push-take (92 commands) | targeted probe | 3 (1 site) | **PASS: the whole transcript equals native T1** (D1 only; transcript-only capture, T1 = T1b) |
| sphere-clock-direct | direct host call | 1 (1 site) | Ours only. With the recorder, the call goes on to the poisoning death the game intends ("Time passes...and you die from some obscure poisoning." and the patch question). Strict: `DECL 245:9: PV does not satisfy declaration` |

## Sites

| # | Function (#DECL) | Binding | Kind | Declared | Observed values | Where (k = command) | Native match when allowed to proceed | Reachability |
|---|---|---|---|---|---|---|---|---|
| 1 | BALLOON, 77act2.mud:424 (declaration line 425) | PRSO | aux `(PRSO <2 .PRSVEC>)` | `<OR OBJECT DIRECTION>` | `#FALSE ()` | balloon-ledge k 57–66, 72–79 (`board basket` first; every turn in the balloon: READ-OUT after CLOCK-DEMON, and C-INT of BINT); 40 occurrences including the prefix-60 re-run | yes: balloon-ledge PASS through all 81 commands | balloon-ledge route (INV-12 frontier); ordinary play to the balloon |
| 2 | BALLOON, 77act2.mud:424 (declaration line 426) | BINF | aux `(BINF ,BINF!-FLAG)` | `<OR FALSE ROOM>` | `#OBJECT GUIDE` | balloon-ledge k 59–67, 72–80 (`burn guide with match` first); 43 occurrences. The game itself stores the burning OBJECT: `<SETG BINF!-FLAG .PRSO>` (77act2.mud:488) | yes (same run) | balloon-ledge route |
| 3 | MSWITCH-FUNCTION, 77act2.mud:142 | IMP | aux `(IMP <3 ,PRSVEC>)` | `OBJECT` | `#FALSE ()` | mswitch-push-take k 87 `push switch` (two calls), k 88 `take switch` | yes: the transcript equals native ("Pushing the switch isn't very interesting.", "Chomp, Chomp.", then the machine turns the coal into the diamond as in coal-machine) | targeted probe; any switch command without an indirect object in the Machine Room |
| 4 | SPHERE-FUNCTION, 77act3.mud:245 | PV | aux `(PV ,PRSVEC)` | `<VECTOR VERB OBJECT>` | `[C-INT #FALSE () #FALSE ()]` (rendered `#VECTOR`) | direct host call with PRSVEC exactly as CLOCK-DEMON leaves it for a clock action (77rooms.mud:1633-1648) | not compared (ours only); the game proceeds to its intended poisoning | direct call only. The route (the robot, the carousel, the caged sphere, ten turns) was not built. Source-derived: SPHIN fires only when the hero is caged and never freed |

All four violated sites are **AUX bindings** whose initializer reads a value
the 1977 game legitimately leaves FALSE (PRSVEC slots 2 and 3) or sets to a
type the declaration omits (BINF!-FLAG). No argument, OPTIONAL, SET, VALUE or
PROG binding was violated on any unit.

### Static candidates (not run)

The sweep also scans the source of every DEFINE, FUNCTION and PROG binding
list. A binding is a candidate when:

- it is initialized from PRSVEC slot 2 or 3 (directly, or through a local
  bound to `,PRSVEC`) and its Pattern names neither FALSE nor ANY; or
- it binds `,PRSVEC` itself with a positional Pattern that admits no FALSE
  in element 2 or 3.

The scan finds 55 bindings. Four of them declare the undefined PRSOBJ, so
they are not enforced since #193. That leaves **51 enforced bindings in 45
`#DECL`s**, listed in the JSON (`static_prsvec_candidates`). Of these, the
sweep observed violations only in BALLOON PRSO, MSWITCH IMP and SPHERE PV.

Most of the rest are verb handlers (TAKE, OPENER, PUTTER, LOCKER, …) or
object actions. The parser's syntax supplies a direct object to these, and
several of them run without a violation in the gated scenarios. The list is
an upper bound for the PRSVEC-sourced class, not a list of violations.

What the scan cannot see:

- arguments passed in by callers;
- values from other sources (BINF is an example);
- whether a site is reachable.

## Scale

- The 12 loaded game files have **356 attached `#DECL`s** with 1070 declared
  name entries (VALUE included), plus 1 positional declaration.
- **4 distinct violated sites** (4 bindings in 3 functions) on everything
  run:
  - **0 on the 24 gated scenario routes**;
  - **2 on an ordinary play path**, the balloon (BALLOON PRSO and BINF,
    on every turn in the balloon);
  - **1 confirmed by an ordinary command** in a targeted probe (MSWITCH IMP;
    `push switch` or `take switch` in the Machine Room kills a strict
    session);
  - **1 confirmed only by a direct call** (SPHERE PV; route reachability
    source-derived).
- Static upper bound for the PRSVEC-sourced class: 51 bindings in 45
  `#DECL`s.
- Allowed to proceed, every run that has a native comparison matches native
  byte for byte: 24 gated scenarios, the 81-command balloon route and the
  MSWITCH probe.

## Options for the maintainer (none implemented)

1. **Keep strict.**
   - *Consequences:* the balloon and the volcano beyond it stay
     unreachable, since every turn in the balloon violates BALLOON's
     declaration. Any MSWITCH command without an indirect object ends the
     session. The SPHIN poisoning, if reached, ends it with a strict error
     instead of the game's death.
   - *Native parity:* none at those points.
   - *Upside:* the manual's attached-check rule is kept everywhere.
2. **Change the attached-declaration ADR again.** Each variant would be a
   recorded deviation from the manual.
   - **(2a) Do not enforce attached declarations at all** (alignment with
     pinned Confusion, which checks none).
     - *Evidence:* every recorder-on run above uses exactly this behaviour
       for attached checks, and every run with a native comparison matches.
     - *Cost:* a genuine runtime bug that produces a wrongly typed value is
       no longer caught at the attached check. That bug would still have to
       change the game's output or state to be noticed, and the scenario
       checkpoints compare both.
     - *Mitigation:* keep the recorder as the diagnostic, and re-run
       `make m4-decl-sweep` whenever scenarios are added.
     - DECL?, GDECL/SETG, positional declarations and CHTYPE stay as they
       are.
   - **(2b) Narrower variants.**
     - *"Do not enforce AUX bindings"* fits all four observed sites, and the
       data shows no other kind violated. The boundary is fitted to the
       data, not principled: the manual draws no such line, and Confusion
       checks no kind at all.
     - *"Do not enforce bindings sourced from PRSVEC"* is principled: PRSVEC
       slots are FALSE by design after CLOCK-DEMON and without an indirect
       object. But it does **not** cover BALLOON's BINF, which holds the
       burning OBJECT from a global, so the balloon would still stop at
       command 59. It would also need a source-sensitive check that the
       runtime does not have.
     - *"Do not enforce known-type mismatches whose value is FALSE"* covers
       PRSO, IMP and PV but not BINF either.
3. **Per-site, separately versioned source patches**, which change upstream
   provenance and need approval.
   - *Observed sites:* 3 functions, 4 bindings:
     - BALLOON `(PRSO) <OR OBJECT DIRECTION FALSE>` and
       `(BINF) <OR FALSE OBJECT>`;
     - MSWITCH `(IMP) <OR OBJECT FALSE>`;
     - SPHERE `(PV) <VECTOR VERB <OR OBJECT FALSE>>`.
   - *Coverage gap:* the static upper bound is 51 bindings in 45 `#DECL`s.
     Sites that no run reaches stay unknown until a player reaches them.

### Recommendation

**Option 2a.** Stop enforcing attached `#DECL` checks, as a recorded
deviation that aligns with the pinned oracle. Keep the recorder (test-only)
and `make m4-decl-sweep` as the diagnostic, and promote balloon-ledge to a
gated scenario.

Reasons:

- With 2a, every route run here matches the native reference exactly.
- The violations are latent defects of the 1977 sources (a declaration
  typo: ROOM for OBJECT; FALSE omitted where the game's own control flow
  produces it) that the original engine never checked.
- 2b's principled variant does not cover BINF, and its data-fitted variant
  has no basis in the manual or the reference.
- Option 3 changes provenance and cannot be shown to be complete.

This is a recommendation only. The decision, and an ADR amendment with tests
written before the change, belong to the maintainer and the next slice.

## Commands and results

| Command | Exit | Notes |
|---|---|---|
| `racket tests/decl_violation_recorder_test.rkt` (before the change) | 1 | `make-mdl-atom-space`: unknown keyword `#:decl-violation-recorder` |
| `racket tests/decl_violation_recorder_test.rkt` | 0 | `decl_violation_recorder_test: OK` |
| `python3 -I scripts/probe_decl_sweep_reference.py docs/evidence/M4/decl-sweep-probes-reference.json` | 0 | CAPTURE OK; T1 = T1b; mdli sha256 pinned before and after |
| `make m4-decl-sweep` | 0 | 27 units, all with a result; 4 distinct sites; report `decl-violation-sweep.json` |
| `make test` | 0 | raco: 5042 tests passed (the recorder test included); pytest: 104 passed, 1 deselected |
| `make test-historical` | 0 | |
| `make m3-check` | 0 | overall PASS (native fresh capture parity included) |
| `make xfail-m4-balloon-frontier` | 0 | XFAIL as recorded: entries 0-56 equal the reference, k = 57 BALLOON's PRSO #DECL. Production is still strict |
| `make m4-check` | 0 | SCENARIO_PARITY PASS (24 scenarios); persistence and PLAYABLE sub-checks PASS; GAMEPLAY_RELIABILITY NOT YET (18 of 23 branches; open blockers INV-06, INV-07, INV-12); M4_ACCEPTED NOT YET (run on 141eacf with only a SEMANTICS wording fix uncommitted) |
| `git diff --check` | 0 | |

All runs: Racket v7.9 [bc], Python 3 from `/usr/bin/python3`,
`PLTCOLLECTS=":$PWD"`, `TMPDIR=/tmp`. Each heavy job ran on its own.

## Limitations

- **The SPHERE continuation (independent review).** The poisoning line
  follows the source (77act3.mud, the SPHIN branch). The "Now, let me
  see..." text after it does not come from the game's flow. It is YES/NO's
  RESET plus a READSTRING at exhausted input during a host call. Natively,
  that point would be "Unexpected EOF". This is not a native comparison.
- **Prefix re-runs.** The balloon's re-run prefixes 52 and 60 come from the
  runner's own output. The JSON records 60, through its violations, but not
  52. Whether `--reuse` was used for the probe capture is not recorded either.

- **SPHERE-FUNCTION's site** is shown only by a direct host call, not by a
  route, and is not compared with native.
- **The MSWITCH probe** is compared on the whole transcript only. There are
  no per-turn checkpoints, because its native capture is transcript-only.
- **Coverage.** The sweep covers only the routes it runs. The static scan
  bounds one class (values read from PRSVEC) and cannot see arguments or
  other values.
- **Recorder values.** The recorder renders values in a bounded way. OBJECT
  and ROOM are shown by OID and RID.

## Re-run after the decision (2026-11-26, M4 S16)

After the #196 amendment (attached `#DECL`s not enforced in production) the
sweep runs each unit twice, with and without the recorder; balloon-ledge is a
gated unit. `make m4-decl-sweep` exit 0 on `e98fe9b`: 27 units, none crashed.
With the recorder: **the same 4 sites** (BALLOON BINF 43 and PRSO 40
occurrences, MSWITCH IMP 3, SPHERE PV 1; 0 on the other 24 gated
scenarios). Without it: every gated scenario PASS, the MSWITCH probe equal to
native T1, the SPHERE direct call with the same output. The JSON above is the
re-run's report (the original run's figures are in the tables above). Record:
[S16-ATTACHED-DECL.md](S16-ATTACHED-DECL.md).

**Re-run with thief-fight (combat.thief slice, 2026-11-26).**
- `make m4-decl-sweep` exit 0 on `614be36`, with 28 units, none crashed.
- `thief-fight` records 0 violations and PASSes with and without the recorder.
- The distinct sites are still the same 4.
- `decl-violation-sweep.json` is regenerated.
