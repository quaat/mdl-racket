# Codex agent contract — MDL on Racket / 1977 Zork

Read this file **before doing any development**. Read `docs/PLAN.md`,
`docs/STATUS.md`, `docs/TESTING.md`, `docs/SEMANTICS.md`, and
`docs/PROVENANCE.md` next. Also read actual source before editing.

## Mission and non-negotiable rules

- Primary objective: run the December 1977 Zork as faithfully as possible from
  original MDL code in a Racket-based `#lang mdl` language implementation.
- Distinguish **archival exactness**, **playable reconstruction**, and **runtime
  equivalence**. Never silently mix them.
- Do not modify anything under `.cache/upstream/`. Create separately versioned
  patches and a provenance manifest if changes are required.
- Never replace the original parser, puzzle rules, or random behavior with new
  simplified implementations to make tests green.
- Maintain strict failure on unknown MDL constructs. Never turn unsupported
  expressions into implicit `nil`, ignored forms, or no-ops.
- Before implementing an MDL construct, document its semantics and tests in
  `docs/SEMANTICS.md`. Confirm tricky cases against Confusion and the MDL manual.
- Never claim game parity from reader tests, or native builds from static checks.
  Report attempted command, exit status, output excerpt, and known limitations.
- No production game server may expose raw MDL interpreter/REPL functionality.
  Keep all reference execution local and isolated; do not give a web client
  arbitrary filesystem or evaluator access.
- Respect copyright/licenses. Keep GPLv3 Confusion as a reference dependency;
  do not copy source code into the MIT-0 runtime without appropriate review.

## Autonomous execution workflow

1. Inspect `docs/STATUS.md`; identify the **first unmet milestone gate**.
2. Inspect relevant source and its tests, plus upstream pinned source as needed.
3. Create/update a GitHub issue for the exact task when GitHub integration is
   available. Use a small branch and PR; otherwise write a local task record.
4. Write regression tests or golden transcript assertions before implementing
   the corresponding behavior. Track known XFAILs rather than suppressing them.
5. Make the smallest semantics-preserving change; refactor when it improves
   clarity without changing behavior.
6. Run `make test` (or report missing toolchain precisely). Run reference
   validation for any behavior change. Check source SHA before comparing runs.
7. Record evidence under `docs/evidence/<milestone>/` and update `docs/STATUS.md`,
   `docs/SEMANTICS.md`, and `docs/DECISIONS.md` when relevant. At every milestone
   gate, update `README.md` with the verified status, supported and unsupported
   capabilities, reproduction commands, evidence links, and next milestone.
   Keep its claims consistent with the gate result; update it for a failed or
   blocked gate as well as a passing one.
8. Record a final issue/PR comment including commands, exit statuses, and
   how to reproduce; label gate PASS / FAIL / BLOCKED / NOT RUN.
9. Do **not** continue to the next gate if this gate failed. If blocked, record
   the blocker, root cause, options, and a single recommended next action.

## Mandatory development evidence

For every milestone or PR, include:

- Git commit SHA and the upstream SHA(s) from `sources.lock.json`;
- supported/unsupported MDL forms and deviations from historical semantics;
- exact commands executed and their results (tool versions when material);
- failing-then-passing test evidence where relevant;
- Confusion transcript paths, approved golden comparisons, and RNG/input settings;
- security and licensing impact; unresolved risks; next actionable task.
- for each milestone gate, a README update stating its result and limits.

For web features, also include screenshots and manual accessibility checks.
Never write a 'fully passing' report if the reference engine or language tests
were not executed.

## Scope discipline

Use `docs/STATUS.md` to identify the first unmet milestone gate. M0 established
the approved reference baseline. The bootstrap compiler is only a demonstration
and not part of a faithful game engine yet.

Do not implement the whole language in one PR. Preferred vertical slices:
reader -> semantic primitive -> reference probe -> property test -> translation
-> differential validation. See `docs/PLAN.md` for acceptance gates.

## Agent roles and subagent delegation

Roles, isolation and review are fixed; the model or provider behind each
role is not. Sessions choose models through their own tool configuration.

- **The main session orchestrates and is accountable for every merged
  change, whatever wrote it:** maintaining `docs/STATUS.md` and
  `docs/PLAN.md`, choosing the next slice and its acceptance criteria,
  architecture and integration decisions, semantic adjudications (manual
  vs. reference conflicts), verification and evidence review, and
  issue/PR management. Merges follow the escalation policy below.
- **Bounded slices may be delegated** to subagents, including the
  project definitions in `.claude/agents/` (`mdl-reference-investigator`
  for read-only Confusion probe recording; `mdl-segment-implementer`,
  `mdl-declaration-implementer` for worktree-isolated, tests-first
  implementation). These definitions use `model: inherit`; do not pin a
  model or provider in a checked-in definition unless every supported
  environment can serve it. If a configured agent type cannot run in the
  current environment, use a general-purpose subagent with the same
  brief rather than skipping the role.
- Subagents work in isolated worktrees or non-overlapping scopes. Two
  agents must never concurrently edit `mdl/runtime/core.rkt` (or any
  single file) without coordination. The main session reviews every
  subagent diff in full and re-runs the suites.
- Reference probes that can reach SAVE, OPEN, RECORD or other file I/O
  run in a disposable copy of the game directory under `$TMPDIR`, never
  with an upstream checkout as the writable working directory.
- Changes affecting equality, association storage, declarations, shared
  mutation, control flow, channel ownership or error handling always get
  an independent review of the implementation and its invariants — not
  just passing tests. Self-review is not labelled independent.

## Escalation policy

Do not request routine confirmations when a safe, reversible choice is obvious.
Do request approval before: changing upstream provenance, accepting semantic
regressions, distributing mixed-license binaries, changing public repository
license, or deploying an exposed MDL execution service.
