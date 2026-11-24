# M4 Phase 1: single-run per-turn scenario runner (2026-11-24)

Branch `feat/m4-single-run-runner` (based on `main` = `522b563`). Upstream
pins (`sources.lock.json`): mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`,
MIT zork `d94501340842e006791fce0757dc0043b8ec8916`; reference interpreter
`mdli` sha256 `6df359f6…` (unchanged; no new native capture was taken, no
reference JSON or native capture was changed). Local toolchain: Racket v7.9
[bc] (CI: racket:8.10-bc, not run for this record). Every game run: fixed
session clock 250776000, zone UTC, START's RANDOM seed from it (ADR-0052).

Result: **PASS (branch evidence)** for the runner slice. It is test
infrastructure only: no runtime file changed, so no MDL semantics, no
SCENARIO_PARITY claim and no PLAYABLE claim changes.

## Protocol

`tests/m4_scenario_runner.rkt` is the shared driver of the ten scenario tests
(house-cellar, mailbox-drop, orphan-prompt, top-parser, sword-glow,
troll-combat, parser-ambiguity, cyclops-room, mirror-bat, strange-passage;
the last two through `tests/m4_p0prims_scenario.rkt`). The full description
is in TESTING ("M4 scenario runner") and ADR-0062. In short:

- **single-run (default):** one boot, all n commands. At READSTRING entry k
  (k = 0..n), observed by the host-only ADR-0061 observer: the output so far
  equals the native prefix-k stdout (D1 only) through its (k+1)-th prompt;
  the checkpoint equals reference diagnostic checkpoint k (X1, also taken at
  READSTRING entry); READSTRING call k consumed exactly command k+1 and `\n`
  (or met end of input at k = n); reading the checkpoint changed neither the
  RANDOM state nor the logical storage ledger. After end of input: the whole
  output equals T1 byte for byte and the state equals end checkpoint n.
  Prefixes whose native end-of-input tail is not standard are re-run per
  prefix (below).
- **per-prefix:** the pre-runner protocol through the same module (one boot
  per prefix, whole output vs Pkk/T1, state after end of input vs end
  checkpoint k).

### What the reference records about the EOF split (brief question 2)

(a) Yes. Every native prefix-k stdout is "game text through the (k+1)-th
RDCOM prompt" followed by its end-of-input tail; the probe records exactly
this split: `checks.prefix_runs_consistent_with_t1` asserts that each Pkk
starts with `prompt_head(T1, k)`, and the newer probes report
`prefix_runs_with_demon_text_after_eof` instead of requiring the house-cellar
`prefix_expected` tail. All ten references have exactly k+2 prompts in Pkk
and n+2 in T1 (checked by the runner on every run).

(b) The snapshot at READSTRING entry k corresponds to the **diagnostic
per-turn checkpoint k** (`diagnostic.checkpoints[k]`, X1's DIAG-STATE runs at
READSTRING entry). `end_checkpoints[k]` is the last checkpoint of Dkk, taken
*after* the end-of-input empty command; `end_checkpoints[n]` equals
`diagnostic.checkpoints[n+1]` (asserted).

(c) Native end-of-input tails, classified from the references:

| scenario | n | non-standard tails (k < n) | why | single-run boots |
|---|---|---|---|---|
| house-cellar | 11 | none (no end_checkpoints; tail text standard) | | 1 |
| mailbox-drop | 8 | none | | 1 |
| orphan-prompt | 9 | none | | 1 |
| top-parser | 10 | none | | 1 |
| sword-glow | 13 | 0 | end checkpoint: SWORD-DEMON HACTION disarmed by the first (empty) turn | 2 |
| troll-combat | 22 | 0 | same | 2 |
| parser-ambiguity | 34 | none, with the declared `after-empty-command` transform (LEXV empty, PARSE-WON false; asserted for all 35 end checkpoints) | | 1 |
| cyclops-room | 40 | none | | 1 |
| mirror-bat | 37 | 33 | tail `Beg pardon?\nYour sword has begun to glow very brightly.\n>`; sword OTVAL | 2 |
| strange-passage | 31 | none | | 1 |

**Lost coverage (single-run mode only).** For each standard prefix k < n
(11 + 8 + 9 + 10 + 12 + 21 + 34 + 40 + 36 + 31 = 212 prefixes) this
runtime's own reply to the end-of-input empty command at the state of turn
k is not executed, and that turn runs the DEMONS loop after the reply
(77rooms.mud:642-647: SWORD-GLOW, and ROBBER with a `<PROB 30>` RANDOM
draw; not FIGHTING or CLOCKER, since PARSE-WON is false). For the six
scenarios with `end_checkpoints` the reference shows the native reply is
exactly `Beg pardon?\n>` with no compared field changed (or exactly the
declared transform). For house-cellar, mailbox-drop, orphan-prompt and
top-parser it shows only the reply text (end checkpoint k falls back to the
entry checkpoint, so the state check is vacuous; their native end-of-input
state is evidenced only at k = n). No reference records the RANDOM draws of
a prefix's end-of-input turn. The same `Beg pardon?` branch (77rooms.mud:641)
still runs at k = n of every scenario, in every reboot, and mid-run for
parser-ambiguity's empty (`""`) command; its blank command (`"   "`, INPLEN
3) takes the EPARSE branch (77rooms.mud:620, `Huh?`), not this one. `make m4-scenarios-per-prefix` keeps
the full per-prefix coverage.

**Lost coverage: allocating reads.** `LIT?` (77rooms.mud:1026) reaches
`LFCN` in a dark room, which evaluates a FUNCTION form and charges the
logical storage ledger (observed: 438 words at house-cellar entry 10, used
180,118 of capacity 262,144). The ledger is game-visible (DIVERT-AGC/GC
timing, ADR-0044), so the runner's perturbation guard rejected that read
(first attempt: house-cellar k = 10, parser-ambiguity k = 22, kind
`run-guard`). The field `lit` (house-cellar, parser-ambiguity) is therefore
declared `#:end-only-keys '(lit)`: compared after end of input (single-run
k = n and per-prefix), not at READSTRING entries k < n. All other fields of
all ten scenarios are read mid-run with the RNG and ledger unchanged.

**Coverage gained (single-run mode).** The READSTRING-entry checkpoints
k = 0..n, which the end-checkpoint scenarios (sword-glow, troll-combat,
parser-ambiguity, cyclops-room, mirror-bat, strange-passage) never compared
before (e.g. parser-ambiguity's LEXV and PARSE-WON as left by each command,
not as cleared by the empty command); one READSTRING per command; and the
fake SLEEP sleeper guard now applies to all ten scenarios (before: S9 only).

## Equivalence: both modes on every scenario

Runs at an intermediate local commit of the runner (before two later
changes: a reference prefix that is inconsistent with T1 became a failing
turn instead of a pre-run error, and per-prefix timeouts are attributed to
the prefix; both modes were re-run on the final code, below), sequential, compiled `.zo` in a scratch `PLTCOMPILEDROOTS`:
`M4_SCENARIO_MODE=<mode> racket tests/historical_<scenario>_test.rkt`.

| scenario | single-run | per-prefix |
|---|---|---|
| house-cellar | exit 0, 12 turns, 1 boot, 5.9 s | exit 0, 12 boots, 69.3 s |
| mailbox-drop | exit 0, 9 turns, 1 boot (+1 load-only), 11.2 s | exit 0, 9 boots, 50.8 s |
| orphan-prompt | exit 0, 10 turns, 1 boot (+1 load-only), 11.5 s | exit 0, 10 boots, 55.4 s |
| top-parser | exit 0, 11 turns, 1 boot (+1 load-only), 11.6 s | exit 0, 11 boots, 60.6 s |
| sword-glow | exit 0, 14 turns, 2 boots (+1 load-only), 17.0 s | exit 0, 14 boots, 77.8 s |
| troll-combat | exit 0, 23 turns, 2 boots, 11.3 s | exit 0, 23 boots, 123.4 s |
| parser-ambiguity | exit 0, 35 turns, 1 boot, 6.5 s | exit 0, 35 boots, 198.6 s |
| cyclops-room | exit 0, 41 turns, 1 boot, 6.6 s | exit 0, 41 boots, 239.7 s |
| mirror-bat | exit 0, 38 turns, 2 boots, 11.1 s | exit 0, 38 boots, 216.5 s |
| strange-passage | exit 0, 32 turns, 1 boot, 5.5 s | exit 0, 32 boots, 177.7 s |

No scenario showed a single-run/per-prefix disagreement (no state leaking
across turns differently from a reboot).

## Mutation checks (same earliest failing k in both modes)

Each mutation was applied to the worktree, both modes were run for the
scenario, the earliest failing k was read from the divergence JSON, and the
mutation was reverted with `git checkout` (reference edits re-sealed the
case's `stdout_sha256` so the integrity check passes and the comparison is
reached). Script: a scratch `mutate.py` (not committed); `git status` clean
after every batch; `core.rkt` recompiled after the RANDOM revert.

| # | mutation | scenario | single-run (exit, k, kind, stage, s) | per-prefix (exit, k, kind, s) |
|---|---|---|---|---|
| i-a | P14 stdout byte 2749 `w`→`x` (command 14's reply) | troll-combat | 1, **14**, transcript, single-run, 11.9 | 1, **14**, transcript, 80.9 |
| i-b | P06 stdout byte 1848 `n`→`x` | house-cellar | 1, **6**, transcript, single-run, 5.8 | 1, **6**, transcript, 39.9 |
| i-c | P20 tail `Beg pardon?`→`Beg pardoN?` | mirror-bat | 1, **20**, transcript, reboot, 11.8 | 1, **20**, transcript, 112.6 |
| ii-a | end checkpoint 25 `moves` 25→99 | mirror-bat | 1, **25**, checkpoint, reboot, 11.9 | 1, **25**, checkpoint, 143.7 |
| ii-b | end checkpoint 10 `aobjs` →`()` | strange-passage | 1, **10**, checkpoint, reboot, 10.2 | 1, **10**, checkpoint, 56.2 |
| ii-c | diagnostic checkpoint 7 `moves` 7→99 (no end_checkpoints) | house-cellar | 1, **7**, checkpoint, single-run, 5.4 | 1, **7**, checkpoint, 40.8 |
| iii-a | `mdl-random`: 3rd draw returns r+50 (core.rkt, temporary) | troll-combat | 1, **14**, transcript, single-run, 10.8 | 1, **14**, transcript, 77.1 |
| iii-b | same | cyclops-room | 1, **17**, transcript, single-run, 5.4 | 1, **17**, transcript, 97.0 |
| iii-c | same | parser-ambiguity | 0 (no observable effect), 5.6 | 0 (no observable effect), 202.0 |

Further observations:

- End-checkpoint 15 of troll-combat, end-checkpoint 30 of cyclops-room and
  diagnostic checkpoint 15 of troll-combat: both modes exit 1 in 0.3 s,
  before any game run, in the tests' own reference assertions (end = entry
  checkpoints, kept unchanged from the pre-runner tests); no k is reported.
- Diagnostic checkpoint 25 `moves` of mirror-bat: single-run exit 1, k 25,
  checkpoint; per-prefix **exit 0** — the per-prefix mode of the
  end-checkpoint scenarios never compares the READSTRING-entry checkpoints
  (coverage gained, above), so this mutation is not an equivalence case.
- The RANDOM mutation changes draw index 2: troll-combat's first blow
  (before checkpoint 14) and cyclops-room's first blow (before 17); in
  parser-ambiguity draw 2 is WALK's `<PROB 75>` leaving the attic, whose
  outcome +50 does not change, so neither mode sees a difference.

Example report (i-a, single-run, abbreviated): `failure_kind`
`transcript`, `earliest_failing_k` 14, `command_at_k` `kill troll with
sword`, `transcript.byte_offset` 2398, `expected_context` `…The troll
sxings his axe…`, `actual_context` `…The troll swings his axe…`.

## Watchdog

| setting | scenario | single-run | per-prefix |
|---|---|---|---|
| `M4_SCENARIO_TURN_TIMEOUT=2` | strange-passage | exit 1, timeout, k 0, `last_k_reached` null (boot > 2 s), 2.3 s | exit 1, timeout, k 0, 2.3 s |
| `M4_SCENARIO_TIMEOUT=8` | strange-passage | exit 0 (6.3 s < 8 s) | exit 1, timeout, k 1 (`prefix 1 run: scenario limit of 8 s…`), 8.3 s |
| `M4_SCENARIO_TIMEOUT=5.9` | cyclops-room | exit 1, timeout, k 28, `last_k_reached` 27, `command_at_k` `give lunch to cyclops` | not run |

(The per-prefix timeout attribution was fixed after a first run that
reported the entry count of the prefix-1 run, 0, instead of prefix 1.)

## Timings (`make test-m4-*`, sequential, no compiled `.zo`, as CI runs them)

Before: `main` = `522b563` (`git archive` copy, same `.cache`). After: the
final runner and tests (code tree identical to commit `d1f2539`). Wall seconds, all exit 0.

| target | before | after |
|---|---|---|
| test-m4-house-cellar (+ frontier test) | 115.1 | 48.4 |
| test-m4-mailbox-drop | 58.9 | 12.3 |
| test-m4-orphan-prompt | 64.9 | 12.4 |
| test-m4-top-parser | 71.3 | 12.1 |
| test-m4-sword-glow | 90.5 | 17.2 |
| test-m4-troll-combat | 144.8 | 12.4 |
| test-m4-parser-ambiguity | 230.6 | 7.4 |
| test-m4-replay-persistence (untouched) | 160.9 | 142.3 |
| test-m4-cyclops-room | 267.6 | 7.8 |
| test-m4-mirror-bat | 223.8 | 12.6 |
| test-m4-strange-passage | 180.5 | 7.4 |
| **total** | **1608.9** | **292.3** |
| total without replay-persistence | 1448.0 | 150.0 |

## Verification commands

- `raco test tests/m4_scenario_runner.rkt` (unit tests of the reference-side
  split, classification, differences, configuration and the report; also in
  `make test` via `scripts/test_racket.sh`): 32 tests passed.
- The equivalence, mutation and watchdog runs above.
- Every `make test-m4-*` target, default mode, sequential: exit 0 (timing
  table).
- `make m4-scenarios-per-prefix` at the final code (`d1f2539`): exit 0 in 1298 s, all ten scenarios PASS per prefix (12, 9, 10,
  11, 14, 23, 35, 41, 38, 32 boots).
- `make test` (outside the command sandbox; `PLTCOLLECTS=":$PWD"
  TMPDIR=/tmp`; `PYTHON=` the main checkout's `.venv/bin/python`, because
  the worktree has no `.venv` and the 3.9 `.sandbox-pydeps` do not import
  under that 3.13 interpreter): exit 0, 4884 Racket tests passed (runner
  unit tests included), 74 Python passed, 1 deselected. A first attempt with
  `PYTHONPATH=.sandbox-pydeps/lib` failed only in pytest collection
  (`No module named 'ptyprocess'`), an environment issue.
- `git diff --check`: exit 0.

## Security and licensing

Test-only change. The runner adds no network or file access: every run keeps
the no-write/no-delete guard, the empty temporary cwd and the game-directory
manifest check; the only file it writes is the divergence report under
`artifacts/` (gitignored, uploaded by the reference workflow). No GPL
Confusion code was copied.

## Risks and next steps

- The prompt split relies on `>` appearing only as RDCOM prompts in the
  native stdout; the runner refuses (strict error) any scenario where the
  count is not k+2, and such a scenario must use the per-prefix mode until
  the split is recorded by the probe itself.
- Checkpoint functions run inside READSTRING; any future field whose read
  allocates or draws RANDOM is rejected by the perturbation guard and must be
  declared end-only.
- CI timing on racket:8.10-bc is not measured here.

## Independent review (2026-11-24)

A read-only independent review of `origin/main...HEAD` independently
recomputed the prompt counts and the tail classification from the ten
references, and diffed every migrated test. It found no assertion dropped
and no path where single-run passes while per-prefix fails, beyond the stated
lost coverage. Verdict: approve with nits. Changes made in response:

* **Defect: after a single-run watchdog stop, the earliest failing k was wrong.**
  The reboots below the timed-out turn shared the scenario deadline, so each
  timed out at once and the smallest was reported. The runner now skips
  reboots after a single-run timeout and reports the timeout with the last k
  reached. Checked on troll-combat, whose k = 0 reboot is non-standard:
  with `M4_SCENARIO_TIMEOUT=5.5` and `5.55`, the fixed runner reports
  "earliest failing k = 9" and "k = 11" (kind timeout, stage single-run).
  With the skip disabled, both report "k = 0, stage reboot … after 0
  READSTRING entries". A timeout after a single run that passed, while the
  reboots are running, is still reported in the reboot that was running
  (sword-glow with `M4_SCENARIO_TIMEOUT=5.7`: prefix 0), which is accurate.
* **The snapshot guard is wider.** A read at a READSTRING entry must also
  leave the session output and the record of signalled MDL errors unchanged.
  TESTING.md now says which other mutation is not observed (interning a new
  ATOM, game code that sets state), and that checkpoint functions must stay
  pure reads.
* **Docs corrected.**
  * Only the six scenarios with `end_checkpoints` evidence the native
    end-of-input state at k < n.
  * The skipped end-of-input turn runs the DEMONS loop.
  * Parser-ambiguity's blank command takes the EPARSE branch, not
    `Beg pardon?`.
  * Post-run checkpoint reads run outside the game-thread guard.
* **A stale divergence report is removed when a scenario starts.** Before,
  it was removed only when the scenario passed.

Not changed: the boundary race between the worker's `channel-put` and the
deadline, and `exn?` catching a break during `check-turn`. Both are harmless.
