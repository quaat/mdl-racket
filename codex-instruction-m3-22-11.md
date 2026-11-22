# Codex Instruction — M3: From Source Execution to a Bootable and Playable Zork

## Mission

Continue autonomous development of [quaat/mdl-racket](https://github.com/quaat/mdl-racket), advancing milestone M3 toward its formal acceptance gate: **the original reconstructed December 1977 Zork must load, initialize, accept player commands, and execute the original game logic within Racket.**

Your assignment is not merely to fix the next reported error. You are responsible for advancing the project through the next major development stage, using sound runtime architecture, source-backed MDL semantics, regression-driven implementation, independent review, and reproducible evidence.

Work autonomously through multiple small, reviewable PRs. Continue after successful integration of each slice until M3 reaches its acceptance criteria or a genuine, documented blocker prevents further progress.

Do not weaken semantic correctness to manufacture source-loading progress.

## 1. Establish and verify the baseline

Repository: `https://github.com/quaat/mdl-racket`

Last reported integrated main:

`5cabf3714074b927881d16142c214e69283e2810`

Current reported verification:

| Measurement | Status |
|---|---|
| M0, M1, M2 | PASS |
| Original source forms executed | 433 |
| Original forms skipped | 0 |
| Racket checks | 1,252 passing |
| Python tests | 23 passing |
| `make m2-check` | PASS |
| `make m3-source-progress` | PASS as partial measurement |
| Underlying original-source loader | FAIL at next unsupported construct |
| M3 full source loading | INCOMPLETE |
| Game initialization | NOT VERIFIED |
| Interactive gameplay | NOT VERIFIED |
| House-smoke parity | NOT VERIFIED |

Current blocker: [issue #104](https://github.com/quaat/mdl-racket/issues/104).

The loader stops at `77rooms.mud`, expression 16, line 101, while executing the original registration:

```mdl
<SETG GC-HAND
  <HANDLER
    <SETG GC-INT <EVENT "GC" 11>>
    ,GC-FCN>>
```

The current runtime explicitly refuses `"GC"` because it has no verified automatic GC event source or callback dispatch.

**Do not assume the reported baseline is still current.** Verify `main`, active branches, GitHub issues, CI, and the working tree before changing code.

Read in full:

- `AGENTS.md`
- `docs/PLAN.md`
- `docs/STATUS.md`
- `docs/SEMANTICS.md`
- `docs/TESTING.md`
- `docs/PROVENANCE.md`
- `docs/evidence/M3/EVENT-REGISTRATION.md`
- `mdl/runtime/core.rkt`
- `mdl/compiler.rkt`
- `tests/event_registration_test.rkt`
- `scripts/m3_source_progress.py`

Inspect all relevant upstream source before implementing or editing behavior.

Preserve user-owned untracked paths. Never reset, remove, overwrite, or clean untracked files without determining their ownership. Use a dedicated branch or worktree.

Verify the source locks:

- MIT Zork: `d94501340842e006791fce0757dc0043b8ec8916`
- mdlzork/Confusion: `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`
- `77rooms.mud` SHA256: `e89337af98565292f84cfb10e9239924e99918325c9e1ac39b6bce692f5aff94`

Do not modify source files under `.cache/upstream/`.

## 2. Architectural assessment — implement a real interrupt runtime

The immediate task is GC event delivery, but its implementation must fit a more general interrupt model.

Use these authoritative references:

- [MDL Manual, Chapter 21 — Interrupts](https://mdl-language.readthedocs.io/en/latest/21-interrupts/)
- [MDL Manual, Chapter 22 — Storage Management](https://mdl-language.readthedocs.io/en/latest/22-storage-management/)

An important correction: the MDL manual classifies `"GC"` as an **internal interrupt**, since MDL detects it itself. The existing runtime groups it with unsupported external events. Correct this conceptual distinction in the implementation and documentation.

The manual requires `"GC"` to occur after garbage collection, with three handler arguments:

1. `FLOAT`: elapsed garbage-collection time in seconds.
2. `FIX`: reason for collection; explicit `<GC>` is reason 1.
3. `ATOM`: operation initiating collection, such as `GC`, `LIST`, or `VECTOR`.

`"DIVERT-AGC"` is a different event delivered before eligible automatic collections. Its handler receives a requested storage size and an initiating operation.

### Architectural requirements

Develop a small, explicit, session-owned interrupt subsystem rather than adding callback-specific special cases to the evaluator.

It should support, as required by the source and tests:

- Event registration and association with `IHEADER`.
- Handler installation, identity, removal, and reattachment.
- Dispatch of already evaluated arguments.
- Correct handler execution order.
- Enabled and disabled headers.
- `OFF` semantics, including removal during dispatch.
- Interrupt priorities and interrupt-level restoration.
- Pending-event queuing and delivery at interpreter safe points.
- Error propagation and cleanup on exceptional control flow.
- Isolation between independent MDL sessions.

The existing `mdl-iheader`, `mdl-handler`, and `atom-space-events` facilities are the starting point. Preserve their accepted behavior and test coverage.

Integrate invocation with the existing interpreted-function and evaluated-argument application mechanisms. Do not create a second, semantically different function evaluator.

### Interrupt scheduling

Implement the required subset of Chapter 21.7 deliberately:

- Normal interpretation operates at interrupt level 0.
- An interrupt may dispatch immediately only when its priority exceeds the current level and execution is at a safe delivery point.
- Otherwise, record its occurrence for later delivery.
- Preserve occurrence ordering when processing pending events.
- Restore the previous interrupt level after a handler completes or exits abnormally.
- Ensure repeated events, nested interrupts, and handler removal do not corrupt scheduler state.

Review whether the source requires `INT-LEVEL`, `DISMISS`, `ON`, `ENABLE`, `DISABLE`, or `INTERRUPT` in this stage. Implement the necessary subset against documented semantics, not speculative stubs.

Unsupported interrupt types must continue to fail explicitly.

Avoid unnecessary implementation of complete MDL multiprocessing. Process-targeted handlers may remain a separately documented limitation unless required for actual source execution, but they must never silently run in the wrong process.

## 3. Solve GC delivery without confusing Racket GC and MDL GC

This is the most important technical decision in the stage.

Racket provides memory management, but Racket's allocation patterns, collector timing, and reclaimed-byte counts do not automatically reproduce historical MDL behavior.

Do not make the following incorrect assumptions:

- Every Racket garbage collection corresponds to a historical MDL GC.
- Racket collection timing matches Confusion.
- A Racket GC notification can safely execute arbitrary MDL handler code immediately.
- Calling `collect-garbage` automatically reproduces MDL's `GC` return value.
- Successful registration without future event delivery constitutes an implemented GC interrupt.

### Required investigation

Before implementation:

1. Identify the GC facilities and safe callback mechanisms available in the installed Racket version.
2. Inspect the relevant original Zork calls to `GC`, `BLOAT`, `"GC"`, and `"DIVERT-AGC"`.
3. Examine how those mechanisms interact with the current interpreter's mutable structures, activation frames, and session state.
4. Compare the documented historical behavior with the capabilities of the existing runtime.
5. Document the implementation options, constraints, semantic differences, and chosen approach in `docs/DECISIONS.md`.

Favor a **testable GC-event source abstraction** with explicit origins and a safe delivery boundary.

Where possible, separate:

- Explicit MDL `<GC>` operations.
- Automatic memory-pressure-triggered collection.
- Pending event delivery.
- Test-only deterministic event generation.

Test injection is useful for verifying scheduling but must not be presented as evidence that an actual GC source works.

For explicit MDL collection, use a real and documented runtime operation. Verify its observable arguments, return value, and timing semantics. Do not invent reclaimed-word counts or historical GC reasons.

If automatic GC parity is not feasible without a virtual MDL memory allocator, document that limitation and evaluate whether a controlled MDL allocation-accounting layer is justified for this milestone.

Do not implement a large virtual memory manager merely for completeness. Choose the smallest architecture that can support defensible M3 behavior and subsequent M4 fidelity improvements.

### Original Zork-specific requirements

Inspect the sequence in `77rooms.mud`:

- Registration of `"DIVERT-AGC"` at priority 1000.
- Registration of `"GC"` at priority 11.
- Installation and immediate removal of the associated handlers.
- Reattachment of `GC-HAND` inside `DIVERT-FCN`.
- Removal of `GC-HAND` inside `GC-FCN`.
- Calls to `BLOAT`, `GC`, and `GC-FCN`.

These are meaningful runtime operations, not decorative declarations.

Tests must demonstrate their side effects and the lifecycle of the original handlers.

Do not substitute `T`, FALSE, ignored callbacks, fabricated arguments, or arbitrary no-op implementations.

**Acceptance for issue #104:** `"GC"` registration becomes available only alongside a verified, executable GC event delivery path, with appropriate documentation of any remaining limitations.

If there is no defensible way to support the required behavior, leave the guard in place and report the precise blocker. Do not falsely mark the issue complete.

## 4. Implement the first delivery slice using red-to-green tests

Split the interrupt work into small PRs if necessary.

Suggested sequence:

**PR A — Interrupt dispatcher and lifecycle**

Build the minimal dispatcher and pending-event state independently of host GC behavior.

Test:

- Registration identity and header reuse.
- Multiple handlers in front-insertion order.
- Correct already-evaluated callback arguments.
- Handler removal and reattachment.
- Disabled and removed associations.
- Priority-based deferral.
- FIFO delivery of queued occurrences.
- Nested dispatch and interrupt-level restoration.
- Exception cleanup and safe continuation.
- Cross-session isolation.
- Unknown event and invalid argument errors.

Use a deterministic test-only event source to exercise the dispatcher. Keep it separate from production event generation.

**PR B — Verified MDL GC generation**

Connect the dispatcher to the chosen GC operation and event source.

Test:

- Explicit collection.
- Correct GC event argument types.
- Callback delivery after collection.
- No callback execution inside an unsafe collector context.
- Disabled handler suppression.
- Handler removal during dispatch.
- Reentrant and nested callback behavior.
- Event delivery under nonzero interrupt level.
- The actual `GC-FCN` and `DIVERT-FCN` lifecycle from original source.

Implement `BLOAT` and `"DIVERT-AGC"` only to the extent necessary for supported behavior; track other storage-management requirements separately.

Where Confusion is capable of furnishing trustworthy observations, capture clean and error cases. Where it only returns its stub `T` values, use the manual, focused runtime assertions, and explicit reference-deviation records.

Record the failing test before the implementation and the passing result after the implementation.

**PR C — Original source integration**

Run the unmodified `77loadall.mud` entry and verify that the original registration executes.

The previous 433 successful forms must still execute identically, with zero skipped forms.

Record the new frontier whether or not the completed-form count increases.

A successful source progression is necessary evidence, but is not sufficient evidence that GC callback delivery works.

Each PR must have an independent semantic review before integration.

## 5. Continue beyond GC — complete original source loading

Once the GC slice is accepted, do not stop simply because `77rooms.mud` progresses.

Continue the existing evidence-driven source-frontier workflow.

For each new failure:

1. Record the exact source file, line, expression, and complete diagnostic.
2. Determine whether it is a reader, compiler, runtime, declaration, type, I/O, or historical-environment dependency.
3. Read the original construct and related definitions.
4. Consult the MDL manual and pinned Confusion where useful.
5. Write the semantic contract and expected results.
6. Create a focused regression test that fails on the existing implementation.
7. Implement the smallest correct semantic change.
8. Verify the regression and all existing gates.
9. Record the new source frontier.
10. Open a focused PR, review, and integrate when accepted.
11. Continue to the next genuine failure.

Do not combine unrelated missing primitives into one unreviewable change.

Do not modify the original MDL game source to work around unsupported runtime behavior.

Do not change the progress validator to count failed or skipped forms as successful execution.

### Target: complete historical loader execution

The pinned Confusion reference loads these twelve game modules:

```text
81prim.mud
77defs.mud
77makstr.mud
81tell-repl.mud
77act1.mud
77act2.mud
77act3.mud
77rooms.mud
77patch.mud
77np.mud
78melee.mud
77dung.mud
```

The immediate goal is for the Racket implementation to execute the same full loading chain, from the unchanged `77loadall.mud` entry, in the required order.

The loader must:

- Execute all original top-level forms.
- Skip zero forms.
- Preserve original definitions, globals, and mutable object identity.
- Preserve cross-file effects.
- Produce a genuine successful completion status.
- Retain useful source-located errors for future failures.

The resulting report must distinguish a fully loaded source chain from initialized game state.

## 6. Implement actual game initialization

Once source loading succeeds, investigate and execute the original startup sequence.

The pinned reconstruction includes `run.mud`:

```mdl
<FLOAD "77loadall.mud">
<SAVE-IT>
```

`SAVE-IT` invokes additional original game initialization and environment-dependent behavior. It is not sufficient merely to compile this definition.

Inspect the original startup flow, including `START`, game-state initialization, input channels, and saved-image assumptions.

Establish how the native reference enters its playable state and how the Racket runtime can reproduce an equivalent starting condition.

Pay particular attention to:

- Initial room and player state.
- Global state and object relationships.
- Vocabulary/parser initialization.
- Input/output channel semantics.
- Random state and event scheduling.
- Platform-dependent MDL functions.
- Differences between the reconstructed source and the saved Confusion game image.

Do not replace the original startup logic with a manually constructed sample room.

If initialization requires an explicit compatibility adapter for unavailable historical operating-system facilities, isolate it and document its semantics.

**Initialization acceptance:** a clean Racket session executes the verified game startup path and reaches a persistent, internally consistent game state ready to accept player input.

## 7. Add the first interactive Racket game runner

Once initialization is established, introduce a minimal local game runner using the real original MDL parser and game loop.

The runner should:

- Start a new isolated MDL session.
- Load the original source or verified equivalent initialization path.
- Accept player text commands.
- Route commands through original game logic.
- Capture game output deterministically.
- Preserve world state between turns.
- Handle quit, end-of-input, and runtime errors cleanly.
- Allow scripted execution without an interactive terminal.

Use a small, testable I/O abstraction so the same runtime can support interactive console sessions and automated differential testing.

Keep platform-specific I/O out of the core language semantics wherever practical.

Do not implement the browser interface in this milestone.

Do not expose a general MDL evaluator or arbitrary file access through an eventual user-facing interface.

## 8. Establish the original house-smoke differential gate

Use the existing scenario:

`tests/scenarios/house.json`

Its approved command sequence is:

```text
west
open mailbox
take leaflet
inventory
score
```

Execute the same commands against the pinned Confusion reference and the Racket candidate.

The comparison must use a documented contract for:

- Starting game state.
- Command sequence.
- Reference source/version.
- Input encoding.
- Random seed or deterministic event strategy.
- Output formatting and normalization.
- State transitions where observable.

Implement or extend the transcript comparison harness to report the first divergence precisely.

Separate semantically meaningful differences from formatting-only differences.

Do not alter the golden reference merely to make a failing candidate pass.

If deterministic RNG is not yet available, prove that the selected smoke scenario does not depend on random behavior, or classify parity as unverified until the necessary controls are available.

The main M3 acceptance target is successful execution of the approved house-smoke scenario using original game logic.

Full map, puzzle, NPC, save/restore, and 500-point completion equivalence remain part of M4 unless required to satisfy this gate.

## 9. Test gates and evidence requirements

At every implementation slice, execute the relevant focused tests and the established regression commands.

Baseline commands:

```bash
TMPDIR=/tmp make test
TMPDIR=/tmp make m2-check
TMPDIR=/tmp make m3-source-progress
git diff --check
```

Run native reference probes when the affected behavior can be meaningfully tested against Confusion.

For each run, record:

- Exact command.
- Exit code.
- Relevant passing/failing check counts.
- Candidate commit SHA.
- Source commit SHAs.
- Relevant source-file SHA256 values.
- First original-source failure, if any.
- Whether source progression is real.
- Known semantic deviations.

**Important:** `make m3-source-progress` returning 0 does not mean the original loader succeeded. Inspect `loader_exit`, `stage`, `failure`, and `milestones` in its JSON output.

Do not let the source-progress harness silently assert initialized or interactive status. Add separate verifiable gates for those stages when implemented.

Require evidence for both positive and negative behavior: valid operations must work, invalid or unsupported operations must fail clearly.

Add regression tests for relevant source-loader behavior and session isolation.

## 10. Explicit milestone progress model

Maintain the following stages separately:

| Stage | Acceptance evidence |
|---|---|
| PARSED | All selected historical source text files are parsed successfully |
| LOADED | Entire original loader finishes, with zero skipped forms |
| INITIALIZED | Original startup creates a valid game state |
| INTERACTIVE | Original game loop accepts and executes commands |
| SMOKE_PARITY | Approved house-smoke scenario matches the reference under its comparison contract |
| PLAYABLE | Original game supports the agreed playable behavior, without substituting synthetic game logic |

Never infer a later stage from successful completion of an earlier stage.

When M3 passes, clearly separate its verified smoke-scenario coverage from the broader M4 requirements.

## 11. Project management, PR quality, and review

Use GitHub issues and PRs as the authoritative development record.

Start with #104, under the broader [event/RNG issue #71](https://github.com/quaat/mdl-racket/issues/71).

Create additional issues for independently testable source blockers or substantial architectural dependencies.

Each PR must:

- Link its issue.
- Describe the semantic change.
- Identify manual and reference evidence.
- Include red-to-green testing evidence.
- Report source-loading impact.
- Describe compatibility limitations.
- Pass applicable CI workflows.
- Receive an independent review for semantic correctness and regressions.

For interrupt, control-flow, mutation, equality, identity, or declaration changes, request a particularly careful review of invariants and lifetime behavior.

Respond to review findings with tests and fixes, not assertions that the implementation is correct.

Do not merge with unresolved material review findings or failing required checks. Honor existing repository approval and merge policies.

After an accepted merge, update local `main` and verify that the accepted behavior remains present on the integrated baseline before starting the next slice.

Keep branch/worktree isolation clean and preserve unrelated local work.

## 12. Mandatory persistent reporting

Write results back to the repository. Do not leave critical implementation knowledge only in the Codex conversation.

Maintain:

- `docs/STATUS.md`
- `docs/PLAN.md`
- `docs/SEMANTICS.md`
- `docs/TESTING.md`
- `docs/DECISIONS.md`
- `README.md`, especially at milestone gates
- The appropriate files under `docs/evidence/M3/`

Introduce or extend evidence files for interrupt scheduling, GC delivery, complete loading, initialization, and house-smoke parity as the work progresses.

Each report must distinguish:

- Verified facts.
- Interpretation of the MDL manual.
- Confusion reference observations.
- Design assumptions or inferred semantics.
- Tested deviations.
- Known unsupported behavior.

Keep historical evidence intact; add new checkpoint reports rather than rewriting old failures as successes.

At each significant checkpoint, publish a concise GitHub issue/PR comment with the current integrated SHA, test status, achieved milestones, evidence references, and exact next action.

The repository should contain enough information for a new independent reviewer to reconstruct what was implemented, why the semantics were chosen, and whether the resulting behavior is credible.

## 13. Completion criteria and autonomous execution

Proceed in the following order:

**Gate A — Interrupt foundations:** Verified event dispatch, lifecycle, priorities, and session isolation.

**Gate B — GC integration:** Verified GC source and callback delivery, original `"GC"` registration accepted, and current loader blocker resolved without dummy semantics.

**Gate C — Full source execution:** The unchanged twelve-module chain loads successfully with no skipped forms.

**Gate D — Initialization:** The original startup path establishes a runnable game state.

**Gate E — Interactive smoke:** Commands execute through the original parser, and the approved house-smoke scenario passes differential validation.

A gate may only be marked PASS when the specified evidence exists.

If a gate fails, diagnose and repair it. If a genuine environmental or architectural obstacle prevents completion, record BLOCKED with the evidence, evaluated alternatives, and recommended resolution. Do not disguise a failed gate as partial success.

Continue through subsequent gates without waiting for routine approval, while respecting explicit escalation requirements and review policies.

### First actions

1. Verify the current repository state and reproduce the 433-form baseline.
2. Review issue #104, the event registration code, and the relevant original `77rooms.mud` sequence.
3. Produce a short GC/interrupt architecture decision based on MDL Chapters 21 and 22.
4. Write focused failing tests for callback delivery and lifecycle.
5. Implement and independently review the minimal scheduler.
6. Implement and verify the GC event source.
7. Re-run the unchanged loader and record the actual new failure frontier.
8. Continue through the next source-backed slices toward complete loading and game boot.

### Required final development report

When reporting back, include:

**Integrated baseline:** SHA and relevant merged PRs.

**Milestone status:** PARSED / LOADED / INITIALIZED / INTERACTIVE / SMOKE_PARITY / PLAYABLE.

**Source progress:** completed original forms, skipped forms, loaded files, and first failure.

**Runtime capabilities:** newly supported semantics and known limitations.

**Verification:** exact test commands, exit codes, CI outcomes, and reference comparisons.

**Evidence:** repository paths and links to decisions, tests, and results.

**Remaining blockers:** prioritized by their effect on reaching an interactive game.

**Next action:** one concrete recommended continuation, including the relevant issue.

## Governing principle

The objective is not the number of MDL expressions executed. The objective is a faithful, maintainable implementation capable of running the original Zork.

Every runtime feature should be justified by authentic source usage, documented semantics, and observable tests.

Prefer correct, bounded implementation over speculative language completeness. Prefer measurable original-source progress over artificial benchmark improvement.

**Do not stop at the first successful GC fix. Continue toward a running, interactive Zork, while preserving the original game logic and every accepted regression guarantee.**