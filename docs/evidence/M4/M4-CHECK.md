# `make m4-check`: the M4 acceptance-term report (Phase 7 of epic #163)

Date: 2026-11-25. Branch `feat/m4-check` from `main` 513272f.
Gate label: **technical check scaffold; a local branch result. Not a
mainline acceptance, and not a PLAYABLE, FULL_COMPLETION or M4 claim.**

## What was added

- `scripts/m4_check.py` and the Makefile target `m4-check`
  (`M4_CHECK_ARGS` passes options). Rules, statuses, options and exit policy
  are in [TESTING](../../TESTING.md) ("M4 acceptance-term check"); the
  decision record is ADR-0063 (proposed).
- [`tests/scenarios/m4-manifest.json`](../../../tests/scenarios/m4-manifest.json):
  the single declared list of checks (11 scenarios, 1 persistence check, 2
  PLAYABLE sub-checks), the PLAYABLE gaps, the FULL_COMPLETION reason, the M4
  PLAN requirements, and the scenario JSON files excluded with a reason.
- [`gameplay-branches.json`](gameplay-branches.json): 23 required branches in
  the epic's six categories (PROVISIONAL list), the checks covering each, and
  the blocking inventory items INV-06 and INV-07 (open).
- `tests/test_m4_check.py` (30 tests, in `make test-python`): term rules on
  fake results and completeness of the real manifests.
- CI (`.github/workflows/reference.yml`): the twelve per-scenario steps
  (eleven scenarios plus replay persistence) are replaced by one `make
  m4-check` step that runs the same targets in the same order, so the job
  does no more work. It skips `test-m3-session` and `test-m3-launcher`, which
  earlier steps of the job already run; those two appear NOT RUN in the CI
  report. Per-target logs are uploaded (`artifacts/m4-check/`), and a failing
  target's last 40 log lines are printed in the step output. Not yet observed
  in CI: no push or PR was made from this branch.

No runtime file was changed.

## Provenance

| Item | Value |
|---|---|
| Commit run | `013af376e3f8f8033b13f8da08b69bcdbb58d938` (`feat/m4-check`; worktree clean for tracked files) |
| Base | `main` 513272f |
| Upstream (`sources.lock.json`) | `mdlzork` bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3; `mit_zork` d94501340842e006791fce0757dc0043b8ec8916 |
| Racket | `Welcome to Racket v7.9 [bc].` |
| Python | 3.9.2 |
| mdli sha256 (provenance only; the scenario targets compare with committed native captures and do not run mdli) | `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` |
| Manifest sha256 | `m4-manifest.json` 5dacbb76…9817; `gameplay-branches.json` 563898c4…e8ca |
| Clock / RNG | fixed session clock 250776000 (1977-12-12 12:00 UTC), seed 10438660480, for every scenario |

## Commands and exit statuses

Environment: `PLTCOLLECTS=":$PWD" TMPDIR=/tmp
PYTHONPATH=$PWD/.sandbox-pydeps/lib`, `PYTHON=/usr/bin/python3`. The commands
ran one at a time, outside the sandbox (Racket needs it).

| Command | Exit | Notes |
|---|---|---|
| `python3 -m pytest -q tests/test_m4_check.py` | 0 | 30 passed |
| `make test` | 0 | 4909 Racket tests passed; pytest 104 passed, 1 deselected (native) |
| `make m4-check` (default) at 013af37 | **0** | 15 checks, 385.3 s total; table below |
| `make m4-check` (default) at 17a4805 + uncommitted docs/CI edits | 0 | same terms; an earlier run, dirty tree |
| `m4_check.py --scenarios-only --require-accepted --skip <all 11 scenarios>` | **3** | policy demo: SCENARIO_PARITY NOT RUN, M4_ACCEPTED NOT YET, nothing FAIL |
| the same without `--require-accepted`, with an extra `tests/scenarios/zz-unlisted.json` (removed afterwards) | **1** | manifest completeness FAIL, so SCENARIO_PARITY FAIL |
| `git diff --check` | 0 | |

Not run: `--per-prefix` (`make m4-scenarios-per-prefix`; about 27 minutes on
this machine for the ten pre-S10 scenarios: 1608.9 s per SINGLE-RUN-RUNNER.md).

## Per-check results (`make m4-check` at 013af37)

| Kind | Target | Status | Exit | Time (s) |
|---|---|---|---|---|
| prerequisite | `sources` | PASS | 0 | 0.1 |
| scenario | `test-m4-house-cellar` | PASS | 0 | 45.5 |
| scenario | `test-m4-mailbox-drop` | PASS | 0 | 11.4 |
| scenario | `test-m4-orphan-prompt` | PASS | 0 | 11.8 |
| scenario | `test-m4-top-parser` | PASS | 0 | 11.8 |
| scenario | `test-m4-sword-glow` | PASS | 0 | 16.7 |
| scenario | `test-m4-troll-combat` | PASS | 0 | 11.6 |
| scenario | `test-m4-parser-ambiguity` | PASS | 0 | 6.5 |
| scenario | `test-m4-cyclops-room` | PASS | 0 | 6.6 |
| scenario | `test-m4-mirror-bat` | PASS | 0 | 11.9 |
| scenario | `test-m4-strange-passage` | PASS | 0 | 6.2 |
| scenario | `test-m4-help-info` | PASS | 0 | 6.1 |
| persistence | `test-m4-replay-persistence` | PASS | 0 | 173.6 |
| playable | `test-m3-session` | PASS | 0 | 23.0 |
| playable | `test-m3-launcher` | PASS | 0 | 42.5 |

Each scenario log shows the runner's per-turn lines ("output and checkpoint
at READSTRING entry k equal the reference") and its final summary, so these
are real game runs, not skips.

## Acceptance terms (output of that run)

| Term | Status | Scope / reasons |
|---|---|---|
| SCENARIO_PARITY | **PASS** | 11 scenarios, each under one fixed clock and seed (250776000, UTC); per scenario, not gameplay coverage |
| GAMEPLAY_RELIABILITY | **NOT YET** | 9 of 23 required branches have a covering check (all passed). 14 have none: combat.hero-wounded, combat.hero-staggered-or-unconscious, combat.thief, death.resurrection-accepted, death.resurrection-refused-quit, death.killed-in-combat, timers.lamp-burnout, timers.cure-clock-recovery, timers.other-clock-events, objects.puzzles-beyond-the-house, scoring.treasure-deposit, save.game-save-command, save.game-restore-command, save.player-facing-resume. Open blocking inventory items: INV-06, INV-07. The branch list is PROVISIONAL |
| PLAYABLE | NOT RUN | no PLAYABLE gate. Sub-checks run and passed. Missing: a declared PLAYABLE gate; player-facing save and resume (WP4.7), with the game's own RESTORE strict (INV-06); the full playthrough (Phase 6) |
| FULL_COMPLETION | NOT RUN | no complete-game run (Phase 6) |
| M4_ACCEPTED | **NOT YET** | unmet: R2 (GAMEPLAY_RELIABILITY NOT YET), R3 (PLAYABLE NOT RUN), R4 (FULL_COMPLETION NOT RUN), R5 "accepted exceptions are source-justified" (no maintainer record) |

Exit 0 under the policy (no FAIL; NOT RUN and NOT YET allowed). With
`--require-accepted` the same results would exit 3.

## Conservative readings that need a maintainer decision

1. **The required-branch list** (`gameplay-branches.json`) is this slice's
   reading of the epic's six categories, PLAN's "Build" line and the
   inventory's unexercised areas. It is labelled PROVISIONAL. Discovery runs
   (failure inventory F3, F12, F13: save text, death with resurrection, death
   with refusal) match native but are not gated checks, so they do not count.
   Promoting F12/F13 to scenario targets would cover two death branches.
2. **Coverage is partial by nature**: a branch counts as covered when one
   gated scenario exercises it under the fixed clock and seed. It does not
   mean every variant of the branch is covered.
3. **PLAYABLE** stays NOT RUN until a PLAYABLE gate is declared, even if
   every sub-check passes.
4. **M4_ACCEPTED** needs a committed maintainer record for the manual PLAN
   requirement R5 (`maintainer_record` in the manifest).
5. **Issue numbers** #172 (INV-06) and #173 (INV-07) come from the
   orchestrator brief. GAMEPLAY-FAILURE-INVENTORY.md still says "to create".
   They could not be checked here because `gh` is not authenticated.

### Maintainer decisions (2026-11-26)

The readings above are decided (ADR-0063 amendment):

1. The 23-branch list is approved unchanged as the initial required baseline
   (`list_status` APPROVED, `baseline_version` 1, `baseline_history`). It is
   a minimum contract; later additions are versioned. `m4_check.py` now
   refuses GAMEPLAY_RELIABILITY PASS for a list that is not APPROVED.
2. `combat.thief` is covered by thief-robbery and thief-fight together; the
   thief behaviour neither covers is in `full_completion_backlog`.
3. PLAYABLE and FULL_COMPLETION have approved definitions (a reproducible
   save/terminate/restore/continue/quit session; the real 500-point game),
   recorded in the manifest. Both stay NOT RUN until their gates exist.
4. R5 is a committed maintainer record; `m4_check.py` checks its form
   (`maintainer_record_policy`). A draft for the maintainer is
   `R5-MAINTAINER-RECORD-DRAFT.md`; it is not cited and does not count.
5. Exit policy 0/1/3 approved. `make m4-accept` is the final gate
   (`--require-accepted --per-prefix`); `make m4-check` is the PR regression
   gate. Both print the regression result and the milestone acceptance on
   separate lines and in the JSON (`regression_result`,
   `milestone_acceptance`).
6. #172 and #173 are decided (ADR-0048 and ADR-0061 amendments; ADR-0064);
   INV-06 and INV-07 stay open blockers until implemented.

## Security and licensing

There is no runtime change, and no network service or evaluator is exposed.
The check only runs existing make targets in the repository. Logs and the
report go to the gitignored `artifacts/m4-check/`. All new files are
original MIT-0 code and data; nothing was taken from Confusion.

## Next actionable task

The maintainer reviews the provisional branch list and the exit policy
(ADR-0063). The next slice after that is the first uncovered combat or
death branch: promote F12/F13 to native-parity scenario targets in the
manifest.
