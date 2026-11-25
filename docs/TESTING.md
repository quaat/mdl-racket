# Test strategy, reference capture, and parity contract

## M4 acceptance-term check (`make m4-check`, 2026-11-25)

`make m4-check` (`scripts/m4_check.py`, epic #163 Phase 7) runs every check
declared in [`tests/scenarios/m4-manifest.json`](../tests/scenarios/m4-manifest.json),
one at a time: `make sources`; the eighteen M4 native-parity scenario targets;
the WP4 persistence check `test-m4-replay-persistence` (a separate entry,
never counted as a scenario); and the PLAYABLE evidence sub-checks
`test-m3-session` and `test-m3-launcher`. It then reports the five
acceptance terms of [STATUS](STATUS.md) separately, never as one PASS:

| Term | Rule in `m4_check.py` |
|---|---|
| SCENARIO_PARITY | PASS only if every declared scenario target exits 0 (scope: N scenarios, each under one fixed clock and seed); FAIL if any fails, if `--per-prefix` fails, or if the manifest is incomplete; NOT RUN if any scenario did not run |
| GAMEPLAY_RELIABILITY | per required branch of [`gameplay-branches.json`](evidence/M4/gameplay-branches.json): UNCOVERED (no covering check), PASS (all covering checks ran and passed), FAIL, or NOT RUN. The term is FAIL if a covering check failed; NOT YET while any required branch is UNCOVERED or a blocking inventory item is open; NOT RUN if a covering check did not run; PASS only otherwise. Discovery runs (failure-inventory cases) never count as coverage |
| PLAYABLE | NOT RUN: no verified PLAYABLE gate exists. The sub-checks are run as evidence; a failing one makes the term FAIL; passing ones never make it PASS |
| FULL_COMPLETION | NOT RUN: no complete-game check is declared (Phase 6) |
| M4_ACCEPTED | PASS only if all four terms PASS and every `m4_plan_requirements` entry is met (a manual requirement needs a committed maintainer record); otherwise NOT YET with the unmet list |

**Statuses.** PASS; FAIL; NOT RUN (not executed: skipped, prerequisite
failed, or no check exists); NOT YET (what exists was executed, the
requirements are not met).

**Exit policy.** 0 when no term and no executed check is FAIL (NOT RUN and
NOT YET are allowed); 1 on any FAIL, including an incomplete manifest or a
failed `make sources`; with `--require-accepted`, 3 when M4_ACCEPTED is not
PASS and nothing failed.

**Options** (`make m4-check M4_CHECK_ARGS="..."`): `--scenarios-only` (only
`sources` and the scenario targets; persistence and PLAYABLE sub-checks NOT
RUN); `--per-prefix` (adds `make m4-scenarios-per-prefix`, slow);
`--skip TARGET` (repeatable; reported NOT RUN, so a skipped scenario makes
SCENARIO_PARITY NOT RUN); `--require-accepted`. `M4_TARGET_TIMEOUT` bounds
each target (default 1800 s; a timeout is a FAIL).

**Output.** `artifacts/m4-check/m4-check.json` (git commit, branch and dirty
flag, `sources.lock.json` commits, Racket and Python versions, mdli sha256
for provenance, manifest sha256s, every command with exit code, duration and
log, the terms with scope and reasons, the exit code) and one log per target
in `artifacts/m4-check/logs/`; a failing target's last 40 log lines are
printed. A result is the technical result of that commit; a local branch run
is never mainline acceptance.

**Manifest completeness.** `tests/test_m4_check.py` (in `make test-python`)
fails when a `test-m4-*` Makefile target is not in the manifest, a
`tests/scenarios/*.json` file is neither a scenario nor excluded with a
reason, the manifest's `runner_test` list differs from the Makefile's
`M4_SCENARIO_TESTS` (`m4-scenarios-per-prefix`), a target does not run its
runner test, or a gameplay branch cites a check m4-check does not run. The
same check runs at the start of `make m4-check`. The term rules are tested on
fake results there (any scenario failure fails SCENARIO_PARITY; an uncovered
branch or an open blocker keeps GAMEPLAY_RELIABILITY from PASS; M4_ACCEPTED
is never PASS unless all four terms PASS).

**CI.** The reference workflow runs one `make m4-check` step (skipping the
two M3 sub-checks that earlier steps already ran) in place of the twelve
per-scenario steps; per-target logs are uploaded with
`artifacts/m4-check/`. Evidence: [M4-CHECK.md](evidence/M4/M4-CHECK.md).

## M4 scenario runner (2026-11-24)

The eighteen M4 native-parity scenarios (`make test-m4-house-cellar`,
`-mailbox-drop`, `-orphan-prompt`, `-top-parser`, `-sword-glow`,
`-troll-combat`, `-parser-ambiguity`, `-cyclops-room`, `-mirror-bat`,
`-strange-passage`, `-help-info`, `-grue-resurrection`, `-grue-refusal`,
`-troll-death`, `-treasure-deposit`, `-thief-robbery`, `-cure-recovery`,
`-lamp-burnout`) run through one shared driver,
`tests/m4_scenario_runner.rkt`. Each test file keeps only its command list,
its scenario-specific reference assertions, its read-only checkpoint function
and its post-FLOAD sections. Every comparison is byte-exact after ADR-0053
D1 only (the Confusion/LISTEN banner and the `"DONE"` line); nothing else is
normalised. Evidence: [SINGLE-RUN-RUNNER.md](evidence/M4/SINGLE-RUN-RUNNER.md).

**Single-run mode (default).** One boot (`<FLOAD "77loadall.mud">`, then
SAVE-IT through the host loop on the fixed clock 250776000/UTC) is fed all n
commands. The host-only READSTRING observer (ADR-0061, `#:input-observer`;
no runtime hook was added) snapshots, at the entry of READSTRING call k
(k = 0..n, k commands consumed):

- the output so far, which must equal the native prefix-k stdout up to and
  including its (k+1)-th RDCOM prompt `>` (the reference probe's own
  `prompt_head` split; the runner requires exactly k+2 prompts in that stdout
  and n+2 in T1, so an ambiguous split is a strict error, never a guess);
- the scenario's read-only checkpoint, which must equal the reference
  diagnostic checkpoint k (run X1, taken at READSTRING entry k). Reading the
  checkpoint must not change the RNG state or the storage ledger;
- the characters READSTRING call k consumed: exactly command k+1 and its
  newline (k < n), or end of input (k = n).

At the end of the run (D3 input exhaustion) the whole output must equal the
native T1 stdout, which includes T1's own end-of-input tail, and the final
state must equal end checkpoint n.

*Prompt split (ADR-0062 amendment, M4 S10).* By default every `>` of a
native stdout counts as a prompt. A scenario whose game text itself contains
`>` declares `#:prompt-split 'line-initial` (today only help-info: the help
file's `'attack <villain> with <weapon>'`), and then only a `>` at the start
of a line counts. The count check is the same strict one; the reference
records the split its capture used (`prompt_split`) and the runner requires
the scenario to declare the same. Only terminal READSTRINGs are entries: a
READSTRING from a read-only file CHANNEL (FILE-TO-TTY) never calls the
observer (ADR-0055 amendment). The run guard also fails on a file CHANNEL
left open at the end of a run. Unit tests: `tests/m4_scenario_runner.rkt`'s
test submodule.

*Death question and declared QUIT endings (ADR-0062 amendment, M4 Phase 2;
opt-in, today only the three death scenarios).* JIGS-UP's question `Do you
want me to try to patch you?` is printed without CRLF and answered through
YES/NO's terminal READSTRING, with no `>`. A scenario declares such entries
with `#:entry-prompts` (entry index -> prompt text; the reference records the
same `entry_prompts`, checked by the capture against a YES/NO wrapper in the
diagnostic): the head of such an entry ends after that text, and no counted
`>` may lie before it. The count stays strict: a prefix whose last observed
entry is e holds one `>` per entry 0..e that is not declared, plus one for
the READSTRING that dies at end of input (always RDCOM's `>`, as it follows
the empty command); without declarations this is k + 2 as before.
A scenario also declares the prefixes whose run ends by the game's own QUIT
(`#:quit-prefixes`, with `#:quit-open-records`): the reference records every
prefix's native ending from its stderr (`endings`: end of input =
`Error: Unexpected EOF`, QUIT = empty) and the declaration must equal it.
For a declared quit prefix the run must end with the host loop's `'quit`
outcome and no MDL ERROR (never input exhaustion or a strict failure), leave
exactly the input after the quitting answer unread, and have recorded
exactly the declared OPENs (RECORD's denied `READB`/`PRINT` of MDL/ZORK.LOG,
ADR-0055); every other run must still end by D3 with no OPEN recorded, and
the no-write guard holds for all. The end checkpoint of a quit prefix is the
reference's state at QUIT (taken in a QUIT wrapper). In single-run mode the
run is observed at entries 0..q (q = n, or the entry whose answer quit) and
compared at its own end (QUIT or end of input) with T1 and end checkpoint n;
every declared quit prefix below n is re-run per prefix (it never meets the
end of input that single-run turn k stands for). Natively a quitting run
appends a line to MDL/ZORK.LOG in its game copy; this runtime writes no file
(ADR-0055; ADR-0048 for SAVE-IT's MADADV.SAVE), and RECORD prints nothing,
so the transcripts are identical. An end of input inside YES/NO is not a
quit by itself: YES/NO's READSTRING returns 0 and the stale first character
of INBUF answers (grue prefixes: `n` of `north`, a refusal and QUIT;
troll-death prefix 19: `w` of `wait`, a yes).

*End-of-input tails.* A native prefix-k run ends with input exhaustion: RDCOM
reads an empty line, prints `Beg pardon?`, the demons run, a prompt follows,
and the next READSTRING dies. From the reference alone the runner classifies
each prefix k < n as *standard* when that tail is exactly `Beg pardon?\n>` and
its end checkpoint equals its READSTRING-entry checkpoint (after the
scenario's declared, reference-verified `#:eof-transform`: parser-ambiguity
declares that the empty command empties LEXV and sets PARSE-WON false). Every
non-standard prefix is re-run by the per-prefix protocol (a reboot): today
sword-glow k = 0 and troll-combat k = 0 (the first empty turn disarms
SWORD-DEMON) and mirror-bat k = 33 (the sword glows brighter on the empty
turn).

*Coverage lost by the single-run mode, stated exactly.* For each standard
prefix k < n this runtime's own reply to an end-of-input empty command at the
state of turn k is not executed. That turn is not just a reply: after
`Beg pardon?` RDCOM runs the DEMONS loop (77rooms.mud:642-647), so SWORD-GLOW
and ROBBER (whose `<PROB 30>` draws RANDOM) run there; FIGHTING and CLOCKER
do not (PARSE-WON is false). What the reference evidences about the native
turn differs by scenario. Where `end_checkpoints` were recorded (sword-glow,
troll-combat, parser-ambiguity, cyclops-room, mirror-bat, strange-passage)
it shows the reply is exactly `Beg pardon?\n>` and no compared field changed
(or exactly the declared transform). For house-cellar, mailbox-drop,
orphan-prompt and top-parser it shows only the reply text: their end
checkpoint k falls back to the entry checkpoint, so the state half of the
classification is vacuous there, and their native end-of-input state is
evidenced only at k = n. No reference records the RANDOM draws of a
prefix's end-of-input turn. The same RDCOM empty-input branch (`Beg
pardon?`, 77rooms.mud:641) still runs in this runtime at k = n of every
scenario, in every reboot, and mid-run for parser-ambiguity's empty (`""`)
command; its blank command (`"   "`, INPLEN 3) takes the EPARSE branch
instead (77rooms.mud:620, `Huh?`). Second, a checkpoint field whose read
evaluates allocating game code is never read mid-run, because the logical
storage ledger it charges is game-visible (DIVERT-AGC/GC timing, ADR-0044):
the scenario declares it with `#:end-only-keys` and a `#:turn-checkpoint`
without it, and it is compared only after end of input (single-run k = n,
reboots, per-prefix). Today that is `lit` (the game's `LIT?` reaches LFCN,
which evaluates a FUNCTION form) in house-cellar and parser-ambiguity. A read
at a READSTRING entry that changes the RANDOM state, the storage ledger, the
session output or the record of signalled MDL errors fails with kind
`run-guard`; other mutation by a read (interning a new ATOM, game code that
sets state) is not observed, so checkpoint functions must stay pure reads of
existing names (as all eighteen do: pure SUBRs, and FIND-OBJ/FIND-ROOM on IDs that
exist). Coverage gained: the per-turn
checkpoints at READSTRING entry (the newer per-prefix tests compared only
end checkpoints) and the one-READSTRING-per-command check.

*The thief's end-of-input move (M4 Phase 3).* The Phase 3 checkpoint
(`tests/m4_timers_checkpoint.rkt`) reads the ROBBER demon's HROOM, which the
demon changes on every turn, the end-of-input turn included. With that field
almost every shorter prefix would have a non-standard end checkpoint
and be re-run (one boot each). thief-robbery classifies with it (21 boots in
single-run mode). treasure-deposit, cure-recovery and lamp-burnout declare
`#:eof-classification-ignore-keys '(robber_hroom)` (ADR-0062 amendment): the
field is left out only of that classification, and is still compared at
every READSTRING entry, at the single run's end, in reboots and in
per-prefix mode. Lost coverage, precisely: for those prefixes the thief's
move during the skipped end-of-input turn is not executed by this runtime
there; the same ROBBER demon code runs at every regular turn of the single
run and is compared there through HROOM (and in per-prefix mode at every
prefix's end of input). Rendering: the thief's walk reaches the room whose
RID is `!` (NULEXIT's FIND-ROOM), which PRIN1 prints as `\!`; the checkpoint
renders that one escaped PNAME and fails strictly on any other unsafe one.
The Phase 3 references keep each Dkk case's log as its sha256 and size
(`diag_logs`): their last checkpoints are `end_checkpoints`, and the logs
grow with k.

*Diagnostic stdout hashes.* In every M4 reference, the diagnostic runs'
(X1, Dkk) `stdout_sha256` is the hash of the raw native stdout. That stdout
echoes the disposable `$TMPDIR` log path, and the stored `stdout_raw` has the
path normalised. So the two do not match for those cases. This is not
corruption, and the runner never uses diagnostic stdouts. The P/T1/T1b
transcripts it compares contain no path, and their hashes are re-checked.

**Per-prefix mode** (`M4_SCENARIO_MODE=per-prefix`; `make
m4-scenarios-per-prefix` runs all eighteen; not on CI's default path). The
pre-runner protocol through the same module: one boot per prefix k = 0..n
with only k commands; the whole output equals the native prefix-k stdout and
the state after end of input equals the reference end checkpoint k
(`end_checkpoints` when recorded, otherwise diagnostic checkpoint k, as
before).

**Failures.** Both modes report the earliest failing k (single-run: the
single run's earliest failing turn, then the reboots below it). Before the
test fails (non-zero exit) the runner writes
`artifacts/scenario-divergence/<scenario>-<mode>.json` (directory overridable
with `M4_SCENARIO_DIVERGENCE_DIR`; uploaded by the reference workflow): mode,
`earliest_failing_k`, `command_at_k` (the last command consumed), kind
(`transcript`, `checkpoint`, `run-guard`, `timeout`, `scenario-check`),
stage, message, `last_k_reached`, the offset of the first differing byte with
200 bytes of expected and actual context, and the checkpoint field diffs. A
passing run removes a stale report of the same scenario and mode.

**Guards and watchdog.** Every game run (both modes, the reboots and the
load-only sections) is guarded while the game thread runs; the checkpoint
reads after a run and the load-only sections' later MDL calls run in the test
thread, outside the guard, watchdog and fake sleeper, as before the runner: no file write or delete (attributed to the
turn during which it happened), an empty temporary cwd, unchanged game
directory hashes, no open RECORD channel, and SLEEP's recording host sleeper
never called under the fixed clock. A whole-scenario wall-clock limit
(`M4_SCENARIO_TIMEOUT`, default 900 s single-run, 3600 s per-prefix) and a
no-progress limit between READSTRING entries (`M4_SCENARIO_TURN_TIMEOUT`,
default 120 s, boot included) stop the game thread and fail with kind
`timeout`, the earliest failing k (the turn being processed) and the last k
reached.

Reproduce:

```sh
export PLTCOLLECTS=":$PWD" TMPDIR=/tmp
make test-m4-mirror-bat                          # single-run (default)
M4_SCENARIO_MODE=per-prefix racket tests/historical_mirror_bat_test.rkt
make test-m4-grue-refusal                        # declared QUIT ending
make m4-scenarios-per-prefix                     # all eighteen, per-prefix
raco test tests/m4_scenario_runner.rkt           # runner unit tests (also in make test)
```

## M3 SMOKE_PARITY check (S10, 2026-11-23)

`make m3-check` (`scripts/m3_check.py`) runs, in order, `sources`,
`test-m3-saveit`, `test-m3-clock-seed`, `test-m3-interactive`, the comparator
unit tests (`tests/test_smoke_parity.py`), the strict comparison of this
runtime's fixed-clock run (`scripts/m3_house_boot_run.rkt`) with the committed
Confusion record `docs/evidence/M3/house-boot-reference.json` (the schema-3
reference promoted 2026-11-23; the schema-2 approved candidate
`house-boot-candidate.json` is kept as the historical baseline and compared
with it in `tests/test_smoke_parity.py`), and, when
`mdli` and `gcc` exist, a fresh native capture in a disposable copy compared
with both. Without them that last stage is NOT RUN, never PASS
(`M3_NATIVE=require` makes it a FAIL; `make m3-native-parity` runs only the
native part). Every comparison uses the single comparator
`scripts/smoke_parity.py` (ADR-0053): only D1 and D2 are tolerated, and the
candidate must end by D3 input exhaustion. The report goes to
`artifacts/m3/m3-check.json`, with logs in `artifacts/m3/logs/`. The
comparator unit tests are part of `make test-python` and need neither Racket
nor mdli. See [S10-SMOKE-PARITY.md](evidence/M3/S10-SMOKE-PARITY.md).

## M3 branch-stack targets (2026-11-23 reconciliation)

On the stack head (PR #141) the M3 make targets are `m3-source-progress`,
`test-m3-andq`, `test-m3-historical-gc`, `test-m3-start-back` (direct-START
XFAIL at TENEX?), `test-m3-saveit` and `test-m3-interactive` (scoped
INITIALIZED/INTERACTIVE evidence; see
[S7](evidence/M3/S7-INTERACTIVE.md)). The `make test-m3-start-random` target
named in the RANDOM checkpoint below was replaced by `test-m3-start-back`
and no longer exists. Since #141's review fixes (8e3d103) the reference
workflow runs `test-m3-saveit` and `test-m3-interactive`, and the smoke
workflow runs the shared `make test-python` (PLAN WP1 F1). `make m3-check` (S10) is described above.

## M3 BACK follow-up checkpoint (2026-11-22)

`tests/back_test.rkt` covers manual and pinned reference array BACK
semantics without upstream fixtures. `make test-m3-start-back` requires
`make sources`, checks all 1,229 original forms and zero skips, then
records the known direct-START XFAIL at TENEX? in `77rooms.mud:298`.
The required Native Confusion reference workflow runs this target after
source preparation. See [BACK-CONTIN.md](evidence/M3/BACK-CONTIN.md).

## M3 RANDOM follow-up checkpoint (2026-11-22)

`tests/random36_test.rkt` uses temporary session roots and belongs to the
source-independent Racket suite. `make test-m3-start-random` runs only after
`make sources` and asserts the unchanged 1,229-form load and known XFAIL
frontier at BACK in `77rooms.mud:297`. The required Native Confusion
reference workflow runs this target after source preparation. Pinned
RANDOM observations and the 36-bit negative-seed deviation are in
[RANDOM-START.md](evidence/M3/RANDOM-START.md).

## M3 source-load review checkpoint (2026-11-22)

`TMPDIR=/tmp make test` is source independent: terminal CHANNEL tests create
temporary source roots and the historical GC handler test is excluded. The
required Native Confusion reference workflow runs `make sources`, then
`make m3-source-progress` and `make test-m3-historical-gc`; the latter also
depends on `sources` locally and fails if any pinned file is missing. It
asserts the complete 1,229-form load, zero skips, and all 13 files in order.
Use `TMPDIR=/tmp make m2-check` for the existing M2 and native reference
regression. The scope and current START failure are recorded in
[WIP-SOURCE-LOAD.md](evidence/M3/WIP-SOURCE-LOAD.md).

## M3 interrupt foundation checkpoint (2026-11-22)

Issue #104 adds `tests/interrupt_dispatch_test.rkt` to the Racket suite.
Run `TMPDIR=/tmp raco test tests/interrupt_dispatch_test.rkt
tests/event_registration_test.rkt`, `TMPDIR=/tmp make test`,
`TMPDIR=/tmp make m2-check`, and `TMPDIR=/tmp make m3-source-progress`.
The focused deterministic event source exercises priority, FIFO pending
delivery, removal, disable/enable, interpreted callback values, exception
cleanup, and session isolation. It is not evidence of a real GC source.
The loader's underlying exit remains 1 at `EVENT "GC"`; consult
[INTERRUPT-FOUNDATION.md](evidence/M3/INTERRUPT-FOUNDATION.md).

## M3 user EVENT/HANDLER registration checkpoint (2026-11-21)

Issue #102 adds `tests/event_registration_test.rkt` to the Racket suite.
Run `TMPDIR=/tmp raco test tests/event_registration_test.rkt`, `make test`,
`make m2-check`, and `make m3-source-progress` against locked sources.
The source target exits 0 for a partial measurement and records the
underlying loader exit 1 at `EVENT "GC"`. Native Confusion stubs these
operators, so the manual and strict unsupported paths define this slice.
See [EVENT-REGISTRATION.md](evidence/M3/EVENT-REGISTRATION.md).

## M3 duplicate attached declaration checkpoint (2026-11-21)

Issue #100 adds `tests/duplicate_decl_test.rkt` to the Racket suite.
Run `TMPDIR=/tmp raco test tests/duplicate_decl_test.rkt
tests/declaration_test.rkt`, `make test`, `make m2-check` and
`make m3-source-progress` against locked sources. The last target records
the underlying loader exit 1 and source frontier despite its own exit 0.
Native probes and frozen source results are in
[DUPLICATE-DECL.md](evidence/M3/DUPLICATE-DECL.md).

## M3 deferred TYPE atom checkpoint (2026-11-21)

Issue #98 adds `tests/deferred_decl_type_test.rkt` to the Racket suite.
Run `TMPDIR=/tmp raco test tests/deferred_decl_type_test.rkt
tests/declaration_test.rkt`, `make test`, `make m2-check` and
`make m3-source-progress` against locked sources. The last target measures
the partial load and writes the underlying loader exit 1 to its report.
Native probes and frozen source results are in
[DEFERRED-DECL-TYPE.md](evidence/M3/DEFERRED-DECL-TYPE.md).

## M3 NTH declaration checkpoint (2026-11-21)

Issue #96 adds `tests/nth_decl_test.rkt` to the Racket suite. Run
`TMPDIR=/tmp raco test tests/nth_decl_test.rkt` for focused repeated
Pattern, malformed-count, large-count, attached FUNCTION and NEWTYPE checks.
Run `make test`, `make m2-check`, then `make m3-source-progress` against the
locked upstream checkout. The last command exits 0 for a valid partial-load
measurement: inspect `artifacts/m3/source-progress.json` for the underlying
loader exit 1 and first failure. Native probes and frozen source results are
in [NTH-DECL.md](evidence/M3/NTH-DECL.md).

## M3 `%` read-time evaluation checkpoint (2026-11-21)

Issue #94 adds `tests/percent_read_test.rkt` to the explicit Racket
suite and a validator regression in `tests/test_m3_source_progress.py`.
The focused Racket test initially exited 1 because the first `%` made
the load fail; after two independent review corrections it exits 0
with 40 focused checks. The 22 clean pinned Confusion cases and eight
deliberate error observations are saved in
`evidence/M3/percent-read-*-reference.json`. Run:

```bash
TMPDIR=/tmp raco test tests/percent_read_test.rkt
make test
make m2-check
make m3-source-progress
```

The final target validates 188 original forms and zero skips but does
not certify a complete load. Its underlying loader exits 1 at the NTH
declaration Pattern in `77act1.mud` expression 10. A `read-eval`
failure is now a distinct allowed report stage. See
[`PERCENT-READ.md`](evidence/M3/PERCENT-READ.md).

## M3 `!\` CHARACTER checkpoint (2026-11-21)

Issue #92 adds `tests/space_character_test.rkt` with 12 focused
reader and runtime checks. Its first run exited 1 because the reader
made a SEGMENT; after implementation it exits 0. Five native Confusion
cases confirm the CHARACTER value and code. `make test` exits 0 with
1,160 Racket and 22 Python tests; `make m2-check` exits 0;
`make m3-source-progress` exits 0 with 157 completed, zero skipped
original forms. This source slice advances the failure location within
expression 23, but the completed-form count stays 157. The full loader
itself exits 1 at `%<STRING <ASCII 10>>` in `81tell-repl.mud`.
See [evidence](evidence/M3/SPACE-CHARACTER.md) and
[`source-progress-space-character.json`](evidence/M3/source-progress-space-character.json).

## M3 positional declaration metadata checkpoint (2026-11-21)

Issue #90 adds `tests/function_decl_metadata_test.rkt` with 13
focused checks. Its first run exited 1 at `expected atom-list/pattern
pairs`; after implementation it exits 0. Four clean and five
deliberately mismatched pinned Confusion cases establish that a
positional RSUBR-style declaration attached to FUNCTION is accepted
but not enforced. `make test` exits 0 with 1,148 Racket and 22
Python tests; `make m2-check` exits 0; `make m3-source-progress`
exits 0 with 157 completed, zero skipped original forms. The full
loader itself exits 1 at `!\ ` in `81tell-repl.mud` expression 23.
See [evidence](evidence/M3/FUNCTION-DECL.md) and
[`source-progress-function-decl.json`](evidence/M3/source-progress-function-decl.json).

## M3 custom WORD literal checkpoint (2026-11-21)

Issue #88 adds `tests/pstring_literal_test.rkt` with 14 focused
reader, runtime, AUX default and strict-error checks. Its first run
exited 1 after the parser split `#PSTRING 0` into two atoms. After
implementation it exits 0. `make test` exits 0 with 1,135 Racket
and 22 Python tests; `make m2-check` exits 0;
`make m3-source-progress` exits 0 with 144 completed, zero skipped
original forms. The full loader itself exits 1 at a function-style
declaration in `81tell-repl.mud` expression 10. See
[evidence](evidence/M3/PSTRING-LITERAL.md) and
[`source-progress-pstring-literal.json`](evidence/M3/source-progress-pstring-literal.json).

## M3 `%<>` read macro checkpoint (2026-11-21)

Issue #86 adds `tests/percent_empty_test.rkt` with eight focused
checks. Its first run exited 1 at an unsupported percent data node;
after implementation it exits 0. Six native Confusion probes cover
TYPE, truth, identity and source-shaped use. `make test` exits 0 with
1,121 Racket and 22 Python tests; `make m2-check` exits 0;
`make m3-source-progress` exits 0 with 136 completed, zero skipped
original forms. The full loader itself exits 1 at a three-element
typed AUX formal in `81tell-repl.mud` expression 2. See
[evidence](evidence/M3/PERCENT-EMPTY.md) and
[`source-progress-percent-empty.json`](evidence/M3/source-progress-percent-empty.json).

## M3 APPLICABLE declaration checkpoint (2026-11-21)

Issue #84 adds `tests/applicable_decl_test.rkt`: 16 focused checks for
callable and noncallable values, OR and structured Patterns, attached
declaration checking, and strict unknown types. Its first run exited 1
at unknown APPLICABLE; after implementation it exits 0. `make test`
exits 0 with 1,113 Racket and 22 Python tests; `make m2-check` exits 0;
`make m3-source-progress` exits 0 with 112 completed, zero skipped
original forms. The full loader itself exits 1 at the `%<>` data
construct in `77makstr.mud` expression 6. See
[evidence](evidence/M3/APPLICABLE-DECL.md) and
[`source-progress-applicable-decl.json`](evidence/M3/source-progress-applicable-decl.json).

## M3 quoted OPTIONAL default checkpoint (2026-11-21)

Issue #82 adds focused `DEFINE`/`DEFMAC` binding tests in
`tests/quoted_optional_test.rkt` against six pinned Confusion cases.
`make test` exits 0 with 1,097 Racket checks and 22 Python tests;
`make m2-check` exits 0 with G3, primitive probes and five-turn native
capture; `make m3-source-progress` exits 0 and reports 87 completed,
zero skipped original forms. The full loader itself exits 1 at the
`APPLICABLE` declaration in `77defs.mud` expression 78. See
[evidence](evidence/M3/QUOTED-OPTIONAL.md) and
[`source-progress-quoted-optional.json`](evidence/M3/source-progress-quoted-optional.json).

## M3 eager AND? checkpoint (2026-11-21)

Issue #80 implements AND? as a SUBR with all arguments evaluated before
truth selection. `make test` passes 1,086 Racket and 22 Python checks.
`make test-m3-andq` loads a SHA-verified original-source prefix and
asserts all five MSETG globals from `77defs.mud` expression 28;
`make m3-source-progress` now runs that regression and reports 70
completed forms with zero skipped before the quoted OPTIONAL default
failure in expression 61. See [AND? evidence](evidence/M3/ANDQ.md) and
[`source-progress-andq.json`](evidence/M3/source-progress-andq.json).

## M3 GDECL checkpoint (2026-11-21)

Issue #78 implements source-data GDECL and SETG declaration checking.
After `make reference-build`, run `make test`, `make m2-check`, and
`make m3-source-progress`. `make test` passes 1,077 Racket and 22 Python
checks. The unchanged loader completes 37 forms with zero skips and
stops at original `AND?` in `77defs.mud` expression 28. Pinned
Confusion's GDECL is an explicit no-op; this manual/reference deviation
is supported by ten native cases in `evidence/M3/gdecl-reference.json`.
See [GDECL evidence](evidence/M3/GDECL.md) and
[`source-progress-gdecl.json`](evidence/M3/source-progress-gdecl.json).

## M3 NEWTYPE declaration checkpoint (2026-11-21)

After `make reference-build`, run `make test`, `make m2-check`, and
`make m3-source-progress`. The issue #76 branch stores and checks the
manual's optional NEWTYPE declaration Pattern and enables the original
`77defs.mud` three-argument form. The unchanged loader now completes
36 forms with zero skips, stopping at unassigned `GDECL` in expression
27. The native Confusion reference discards the Pattern, a documented
runtime deviation; its seven clean and six deliberate-error cases are in
`evidence/M3/newtype-decl-*`. See [M3 NEWTYPE evidence](evidence/M3/NEWTYPE-DECL.md)
and [`source-progress-newtype.json`](evidence/M3/source-progress-newtype.json).

## M3 first original-source correction (2026-11-21)

Run `make test`, `make m2-check`, and `make m3-source-progress` after
`make reference-build`. On the issue #75 branch these exit 0: 1,046
Racket checks, 22 Python tests, 58 bounded G3 assertions, 12 native
primitive probes, five reference turns, 36 parsed historical text files,
and 26 unchanged original-source forms with zero skips. The full loader
itself exits 1 at `77defs.mud` expression 17, three-argument NEWTYPE;
the source-progress target exits 0 because this is an accurately reported
partial advance. See [M3 slice evidence](evidence/M3/EMPTYQ.md) and
[`source-progress-emptyq.json`](evidence/M3/source-progress-emptyq.json).
Confusion `EMPTY?`, `LENGTH?`, `ASSIGNED?` and `ROOT` cases have separate
clean and deliberate-error corpus files in `evidence/M3/`.

## Current M2 mainline checkpoint (2026-11-21)

The [mainline gate](evidence/M2/MAINLINE-GATE.md) passes at integrated
code baseline `7d34195`. Run `make reference-build` once, then
`make m2-check` for doctor, locked sources, reader sweep, offline tests,
historical original-definition probes, G3, native primitive probe and
five-turn capture. On that baseline the target exits 0 with 986 Racket
checks, 13 Python tests and 59 G3 assertions. The direct comparison of
the freshly rebuilt native capture to the approved M0 golden exits 2
solely for Confusion's build timestamp; a comparison with only that line
normalized finds zero mismatches and the game SHA matches. This does not
compare a Racket game transcript. The complete original loader separately
exits 1 at EMPTY? after 24 forms. Issue #73 has now decoupled the fixed
24-form expectation from all M2 tests. On the issue #73 branch the same
target exits 0 with 986 Racket checks, 22 Python tests and 58 G3
assertions from a bounded original-source prefix. The full unchanged
entry is measured by `make m3-source-progress`; its validator fails on
fewer than 24 completed forms, skipped execution, changed accepted prefix,
wrong file order, malformed diagnostics or false completion. See
[`SOURCE-PROGRESS.md`](evidence/M3/SOURCE-PROGRESS.md). The native
reference CI job runs this source-progress target after G3.

## Earlier M2 branch checkpoint (2026-11-20)

Run `make test` for the offline Racket and Python suites,
`make test-historical` for hash-verified original definitions, and
`make test-m2-g3` for the same-session G3 gate. The latter now exits 0
with 59 assertions on `feat/m2-mapf`; the exact source hashes, reference
cases, and distinct full-loader EMPTY? barrier are in
[`G3-GATE-MAPF.md`](evidence/M2/G3-GATE-MAPF.md). Focused MAPF controls,
interpreted FUNCTION application, TYPE?, and startup OBLIST association
cases are in [`MAPF.md`](evidence/M2/MAPF.md). `make test` passes 958
Racket checks and 13 Python tests. The native reference job
provisions pinned sources and runs G3; the fast smoke job remains offline.
M2 mainline acceptance remains pending.

On `feat/m2-indirect-apply`, issue #69 adds 15 clean native APPLY/computed
FORM cases and nine separate deliberate errors; see
[`INDIRECT-APPLY.md`](evidence/M2/INDIRECT-APPLY.md) and the
[requirements matrix](evidence/M2/REQUIREMENTS-AUDIT.md). `make test`
passes 986 Racket and 13 Python checks; the historical target and G3
still pass. `make m2-check` runs the full local technical acceptance
sequence after `make reference-build`. It writes the source sweep to
`artifacts/m2/reader-sweep.json`, preserving the frozen M0 evidence file.
Review, authorization, required CI and verification on `main` are separate
milestone gates.

## Earlier M2 D5 and G3 checkpoints (retained for provenance)

On `feat/m2-atom-props`, `make test` runs 868 Racket checks and 13 Python
tests, including `tests/atom_props_test.rkt` (65 focused checks).
`make test-historical` verifies the 23 assertion original VFLOAD and 20
assertion original DECL probes. D5 reference cases are in
`evidence/M2/atom-props-{cases,reference}.json` and the corresponding
`atom-props-error-*` files; independent review cases are in
`atom-props-review-*` and four clean `character-review-*` cases. The
independent local final-head review and SUBR FIX-indicator regressions are
in [`D5-FINAL-REVIEW.md`](evidence/M2/D5-FINAL-REVIEW.md) and
`d5-final-review-*`.
unchanged `77loadall.mud` load exits 1 after
24 completed expressions at `EMPTY?` in `77defs.mud` expression 15.
M2 G3 has not passed: a separate pre-merge integration run found missing
`N=?` in original MSETG's repeat path (issue #57). Reproduce D5 with `make test`,
`make test-historical`, and the loader command below. Earlier sections
retain their slice-era context.

On the stacked `feat/m2-structural-neq` correction branch, `make test`
adds 13 focused `N=?` checks (879 Racket, 13 Python total). The original
MSETG historical probe is recorded as failing at the next reader gap
`,.FOO`; it is reserved for issue #58, while the D5 historical target
still passes. See [`NEQ.md`](evidence/M2/NEQ.md).

On stacked `feat/m2-computed-global`, `make test` passes 884 Racket checks
and 13 Python tests. `make test-historical` adds a hash-verified original
MSETG first/equal-repeat probe (exit 0); the historical conflicting-repeat
case remains blocked by unassigned `ERROR` and is tracked as G3 FAIL.
Reference inputs and outputs are in `computed-global-*` and the method and
limitations are in [`COMPUTED-GLOBAL.md`](evidence/M2/COMPUTED-GLOBAL.md).

On stacked `feat/m2-error-primitive`, `make test` passes 888 Racket checks
and 13 Python tests; `make test-historical` adds the exact original MSETG
conflicting-repeat assertion. The deliberate Confusion `ERROR` probes exit
the harness with status 1 because the subsequent `<QUIT>` is read in the
reference's error-level REPL; their `*ERROR*` outputs are retained in
`error-reference.json`. This is a tested error path, not a clean-success
probe. See [`ERROR.md`](evidence/M2/ERROR.md).

`make test-m2-g3` on `feat/m2-g3-current` exits 2 deliberately after 48
passing same-session assertions. Original MSETG paths pass; original
PSETG reaches unassigned `MEMQ` after observable side effects. The
full source chain still stops at `EMPTY?` after 24 expressions.
See [`G3-GATE.md`](evidence/M2/G3-GATE.md); issue #63 tracks MEMQ.

After issue #63's MEMQ correction, `make test` exits 0 (903 Racket
checks, 13 Python), and `make test-historical` exits 0 (VFLOAD 23,
DECL 21, MSETG and PSETG original-source probes). `make test-m2-g3`
exits **2** after 52 passing observations because original `FLAGWORD`
reaches missing `MAPF`; pinned Confusion returns `1` for that call.
See [`MEMQ.md`](evidence/M2/MEMQ.md) and the updated G3 report.

The M2 G0 audit is reproducible with
`racket scripts/audit_source_readiness.rkt --output artifacts/m2/source-readiness.json`.
Its JSON separates independent compile probes from sequential execution
probes; `PASS` for the command means the audit completed, not that source
execution succeeded. See [`SOURCE-READINESS.md`](evidence/M2/SOURCE-READINESS.md)
for file hashes, first failures, baseline commands, and the Racket 7.9/8.10
check-count investigation.

The G1 loader suite is `raco test tests/loader_test.rkt` and is included in
`make test-racket` and CI. It uses disposable local files under `/tmp` and
checks shared session state, macro/function persistence, nested/repeated
`FLOAD`, partial execution, path containment, cycles, and structured source
errors, including indirect symlink targets and malformed later forms after a
completed prefix. Review regressions also cover a symlink target with `..`
after another symlink, consecutive parent components in a link target, and
session calls to compiled, interpreted, generated,
and macro definitions. The local CLI can be run with
`racket scripts/mdl_load.rkt --source-root ROOT --entry FILE --report REPORT`;
it exits nonzero on actual source execution failure and writes JSON in both
cases. See [`SOURCE-LOADER.md`](evidence/M2/SOURCE-LOADER.md) for reference
probes, exact pinned-source run and known deviations.

The G2 source-backed probe is `make test-historical`, which first verifies
the pinned source checkouts and then runs
`racket tests/historical_vfload_test.rkt`. It verifies the actual
`77loadall.mud` SHA256, copies exact bytes into a disposable authorized root,
loads only its first definition with a PARTIAL report, invokes `VFLOAD`, and
checks output, return, global state and invalid calls. The native reference
workflow installs `compatibility-lib` for the runtime's `racket/mpair` import
and `rackunit-lib` for its test submodule,
then runs this target after source verification. Its negative-call helper has
a self-check that rejects unexpected success. The first two PR #43 native runs
failed on those missing libraries; see the
[`review evidence`](evidence/M2/HISTORICAL-VFLOAD.md#pr-43-review-follow-up-2026-11-19).
Focused Confusion
evidence is reproducible with
`.venv/bin/python -m scripts.probe_vfload_reference` after the native build.
See [`HISTORICAL-VFLOAD.md`](evidence/M2/HISTORICAL-VFLOAD.md).

## Test layers

1. `make test-racket`: reader, bootstrap compiler, FALSE, atom/OBLIST,
   mutable sequences, type constructors, local/global bindings, the
   documented 36-bit FIX/WORD subset, and scoped M2 execution semantics
   (PROG/REPEAT/RETURN/AGAIN activations and function formals), chapter-14
   `#DECL` declaration checking with `DECL?`, and chapter-7 SEGMENT (`!`
   splice) evaluation with LIST-tail sharing, and chapter-14 structured
   declaration patterns (`<struc [REST ...]>` with bounded traversal), on
   the explicitly supported subset. The target refreshes the linked `#lang mdl` module before tests
   so changed runtime exports are visible. Stale bytecode under the
   gitignored `compiled/` directories produces `instantiate-linket`
   dependency errors after module interface changes; delete those
   directories and rerun.
2. `python -m pytest -q tests/test_harness.py`: source lock, reference
   interchange format, exact comparator and transcript normalization.
3. `racket scripts/mdl_check.rkt ...`: syntax parse coverage on pinned
   historical source. Record file-by-file results; no unsupported syntax skips.
4. `make reference-build`: native Confusion compile (requires GC/libgc-dev).
5. `make reference-capture`: actual game run on pinned 1977 reconstructed save.
6. `make reference-probe`: run isolated Confusion primitive probes through stdin. The native REPL has no prompt; each case ends with `<QUIT>`. Raw output, stderr, and exit code are captured for review.
7. `python scripts/compare_transcripts.py REF CAND`: strict differential
   transcript comparison (once a candidate game engine is available).
8. Future: state diff, randomized test corpus, complete 500-point game, browser.

The M1 gate also runs `tests/integration_test.rkt` for structural
versus identity equality and left-to-right argument evaluation. Three
matching Confusion cases are saved under `docs/evidence/M1/integration-*`.
See `docs/evidence/M1/GATE.md` for the merged gate matrix and exact
commands. This is a semantic micro-runtime gate, not a Zork gameplay gate.

The first M2 slice runs `tests/prog_test.rkt` and a `#lang mdl` fixture for
unnamed PROG auxiliaries and bare RETURN. Focused Confusion cases and expected
errors are under `docs/evidence/M2/prog-*`; see `PROG.md` there for commands,
reference hashes, the deliberately nonzero expected-error probe suite, a
separate Confusion signal-11 crash during auxiliary initialization, and
unsupported activation behavior. These tests do not satisfy the full M2 gate.
Issue #22 adds `module+ test` checks in `mdl/runtime/core.rkt` for activation
identity, ownership, stale-frame rejection, and cleanup on return or error.
Issue #23 adds bounded `tests/equality_cycle_test.rkt` checks so pre-fix
unbounded recursion cannot hang the suite. Confusion timeout and crash cases
are saved separately from successful observations under `docs/evidence/M2/`.
Issue #26 adds `tests/repeat_test.rkt` for unnamed REPEAT and bare AGAIN,
including auxiliary initialization once, PROG restart, nested RETURN,
function ownership, stale-frame rejection, and a 1,000-step stack check.
Focused native inputs and results are under `docs/evidence/M2/repeat-*`.
Issue #28 adds `tests/activation_target_test.rkt` for named PROG/REPEAT,
ACTIVATION/FRAME type reporting, name visibility during auxiliary binding,
explicit RETURN/AGAIN across nested and called functions, and wrong-type or
stale-target rejection. Eleven successful Confusion observations and six
separate error/crash observations are under `docs/evidence/M2/activation-target-*`.
The function-formals slice adds `tests/formals_test.rkt` for OPTIONAL, AUX,
TUPLE, and ARGS sections, in-frame defaults, unassigned optional/aux reads,
TUPLE type/primtype/equality behavior, historical arity error names, and
compile-time rejection of malformed formal lists; binder invariants are in
`mdl/runtime/core.rkt`'s test submodule. Twenty-four successful Confusion
observations and eleven error observations are under
`docs/evidence/M2/formals-*`; see `FORMALS.md` there for the compile-time
validation deviation.
The control slice adds `tests/control_test.rkt` for activation formals
(leading ATOM and `"NAME"`/`"ACT"`), explicit RETURN/AGAIN to a function's
own activation, bare transfers skipping function frames, GO labels and
transfers, and UNWIND cleanup on transfers; frame, GO, and UNWIND
invariants are in `mdl/runtime/core.rkt`'s test submodule. Sixteen
successful Confusion observations and seven error observations are under
`docs/evidence/M2/control-*`; see `CONTROL.md` there for the GO reference
deviation. Issue #139 adds `tests/unwind_raise_test.rkt`: raised errors
(MDL ERROR, host strict errors, non-`exn` raises) propagate unchanged and
run no UNWIND cleanup, while every MDL transfer runs it exactly once
(ADR-0051, `docs/evidence/M3/I139-UNWIND.md`).
The macro slice adds `tests/macro_test.rkt` to `make test-racket` for DEFMAC,
FORM, EXPAND, quoted formals, caller-frame argument evaluation, ARGS/TUPLE,
and an expansion that defines a function. Twenty-five successful Confusion
observations and eight deliberate error observations are under
`docs/evidence/M2/macro-*`; see `MACROS.md` there for commands, hashes,
and reference deviations. The full M2 gate remains open.
The PR #35 review added eleven Racket checks for empty auxiliary LISTs in
interpreted PROG/REPEAT, leading activation names with quoted formals,
runtime-generated definitions, binding order, and duplicate rejection.
Ten focused Confusion observations are saved in `macro-review-cases.json`
and `macro-review-reference.json`; see `MACROS.md` for the failing-then-passing
record. The integrated M2 gate remains open.

## CI toolchain

Both workflows run in the digest-pinned Racket project `8.10-bc` minimal
container. The harness job adds Git for the source-lock Python test and the
Racket packages `compiler-lib`, `rackunit-lib`, and `compatibility-lib` for
`raco make`, RackUnit, and `racket/mpair`. `make test-racket` and the CI job
both call `scripts/test_racket.sh`, keeping one test-file list. The native job
adds Git, G++, Make, Perl, and `libgc-dev`, verifies the locked source commits,
then builds and captures Confusion. The CI runner still downloads Python
dependencies and the listed Racket libraries on each job. See
[`CI-SETUP.md`](evidence/M2/CI-SETUP.md) for exact runs, timing, alternatives,
and limits. The CI run checks reference execution; it does not establish
Racket gameplay parity.

## Frozen 1977 baseline

The archived MIT source omits some components required to run the game.
`heasm66/mdlzork` supplies a patched reconstruction and a prebuilt
`SAVEFILE/ZORK.SAVE` image; this is **not** the original archival binary.
A Confusion baseline is independently verified only when its build and
interactive command playback succeed.

Commands:

```bash
make sources
make reference-build
python scripts/reference_runner.py capture \
  --scenario tests/scenarios/house.json \
  --output artifacts/reference/house.json
```

The runner uses a PTY because the original reader expects terminal behavior.
It waits for a `>` prompt. Timeouts, unexpected early exits, and missing
binaries are failures, not passing tests. If the prompt protocol differs on
some platform, fix the PTY bridge with documented, tested input handling.
The M0 baseline was built and captured locally and in CI; see the M0 report.

## Transcript JSON schema v1

```json
{
  "schema_version": 1,
  "engine": "confusion-patched-1977",
  "scenario": "house-smoke",
  "initial_output": "...",
  "complete": true,
  "commands": [
    { "input": "look", "output": "...", "prompt_returned": true }
  ]
}
```

Reference captures additionally record interpreter image SHA256, game image
SHA256, timestamp, exit status, and errors. A Racket candidate must produce
identical `scenario`, command order, initial output, and per-command output
fields, plus `complete=true`; the `engine` and binary hashes may differ.
Future captures can include read-only `state` snapshots for deeper tests.

### Normalization

The current reference runner removes PTY ANSI SGR/control sequences matching
`ESC [ digits/semicolon <letter>` and normalizes CRLF/CR to LF. It does **not**
strip spaces, remove prompt text from responses (beyond the consumed `>`),
reword descriptions, ignore score differences, or normalize random behavior.
Any further normalization must be explicit and reviewed, with a negative test.

### Golden approval and evidence

Do NOT auto-update goldens when assertions fail. Review the output manually,
record the SHA256 and captured source commits, and only then copy a curated
fixture to `docs/evidence/<milestone>/`. Failed capture JSON belongs in
`artifacts/` and must not be treated as truth. Avoid including private data,
credentials, or host paths in published evidence.

M0's locally reviewed and maintainer-approved fixture is
`docs/evidence/M0/house-golden.json`; hashes, exact command sequence, output
review, timestamp limitation, and PTY exit behavior are in
`docs/evidence/M0/REPORT.md`. The second observed capture matched the first
except for `captured_at`. Rebuilding native Confusion changes its banner's
compile timestamp and thus the exact `initial_output` field.
Approval was given in the Codex conversation on 2026-11-17 for the fixture
with SHA256 `ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.

## Cross-engine limitations

Random NPC actions, runtime timing, and historical save/restore features may
produce legitimate nondeterminism. Deal with that through controlled seeds,
instrumentation, or scenario design rather than weakening strict comparisons.
The earliest endgame is incomplete in some variants; the playable December
1977 reconstruction is documented as a 500-point game.
