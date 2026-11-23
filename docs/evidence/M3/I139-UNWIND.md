# I139: UNWIND cleanups only on MDL transfers, never on raised errors

**Gate result: PASS (scoped to issue #139).** M3 overall remains incomplete.
The source LOADED gate is unchanged.

- Branch: `fix/m3-139-unwind-raise`, based on `248b9b1` (`origin/feat/m3-logical-gc`, umbrella #107).
- Decision: [ADR-0051](../../DECISIONS.md) (maintainer decision 2026-11-23, option a). It supersedes the error clause of ADR-0018.
- Upstream (`sources.lock.json`): mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`, MIT zork `d94501340842e006791fce0757dc0043b8ec8916`.
- Reference: pinned Confusion `.cache/build/confusion_patched/mdli`, SHA-256 `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789`. The binary was not rebuilt.
- Environment: Racket v7.9 [bc] and system Python 3.9 with the pinned wheels in `.sandbox-pydeps`.

## Finding

Before this change, `mdl-unwind` was a `dynamic-wind` whose post thunk ran the cleanup on every exit except normal completion, Racket exceptions included. That amounted to an automatic `<ERRET>` after every error, which neither the manual nor Confusion does. It also broke strict failure:

- `<PROG P () <UNWIND <OPEN-NOT-DEFINED "X"> <RETURN 7 .P>>>` returned **7**, so the strict error disappeared.
- `<UNWIND <ERROR FOO> <ERROR BAR>>` reported **BAR**, so FOO was lost.
- In the FINISH-shaped case `<UNWIND <PROG () <OPEN-NOT-DEFINED "X"> 1> <PROG () <SETG CL 1> <QUIT>>>`, the error reported **`operator QUIT`**. The body's error was lost.

Run against the pre-fix runtime, the probe recorded these cases in `I139-uw-runtime-before.json`.

### Why ADR-0018 was wrong

ADR-0018 relied on the M2 probe `unwind-cleanup-on-error` (`docs/evidence/M2/control-error-*`), which read `,M2-C` while Confusion was **still at error level 2**.

- At that point the manual does not run the cleanup either:
  - §16.2: ERROR is a LISTEN on the intact stack.
  - §16.4: only ERRET/RETRY strip the stack.
  - §16.6: the FLOAD cleanup runs "if the user attempts to ERRET".
- Confusion runs the cleanup once the level is left by ERRET or by a RETURN that crosses the UNWIND.

So the "manual vs Confusion deviation" never existed.

## Reference evidence (pinned Confusion)

- Files:
  - Cases: `I139-uw-cases.json` (25 cases) and `I139-uw-cases-2.json` (5 cases).
  - Results: `I139-uw-confusion.json` and `I139-uw-confusion-2.json`.
  - Driver: `I139-uw-probe.py`. It runs one `mdli` process per case, with stdin as a pipe, from a fresh empty `$TMPDIR/uw-work/<case>-*` directory. It never uses `.cache/upstream` as the working directory.
- The input was fixed. No time or randomness was involved.
- Originally recorded 2026-11-23 06:35 UTC. Re-run for this change with the committed driver:

| Command (repository root) | Exit | Result |
|---|---:|---|
| `python3 -I docs/evidence/M3/I139-uw-probe.py docs/evidence/M3/I139-uw-cases.json $TMPDIR/i139/rerun.json` | 0 | 25 cases, interpreter `6df359f6…`, stdout, stderr and exit status **identical** to `I139-uw-confusion.json` |
| same with `I139-uw-cases-2.json` | 0 | 5 cases, **identical** to `I139-uw-confusion-2.json` |

Every `mdli` process exited 0.

| Case | Confusion observation | Cleanup |
|---|---|---|
| `error-stay-at-level2`, `error-eof-at-level2` | `*ERROR* FOO`, level 2; EOF prints `Error: Unexpected EOF` | no |
| `error-erret-value` (`<ERRET 5>`) | `5`: the ERROR frame is above the UNWIND | no |
| `error-erret-noargs`, `error-erret-frame-below`, `error-return-activation` | `CLEANUP` …, `CLEANUP7` | yes, only when leaving the level by a crossing transfer |
| `quit-in-body`, `quit-in-body-nested` | process ends, nothing printed | no |
| `unbound-fn-cleanup-quits` (FINISH-shaped) | `UNBOUND-VARIABLE … OPEN-NOT-DEFINED` stays visible at level 2 | no |
| `internal-error-in-body` (C-level `mdl_error`) | `Too many arguments to QUIT`, fresh level 1 | no |
| `return-crosses`, `again-crosses`, `nested-return-order` | `C1`, `CC3`, `INNEROUTER1` | yes, inner then outer |
| `error-inside-cleanup` / `-erret-value` | `BAR` at level 2; after `<ERRET 3>` the original `RETURN 1` completes (`1`) | the transfer is suspended, not lost |
| `handler-*` | the handler is never invoked: Confusion stubs EVENT/HANDLER | not evidence |

Manual sources: [chapter 16](https://mdl-language.readthedocs.io/en/latest/16-errors-frames-etc/) §16.1–16.7, and [chapter 23](https://mdl-language.readthedocs.io/en/latest/23-mdl-as-a-system-process/) §23.3 (QUIT "causes MDL to stop running").

### Game-source reachability (read only, `patched_confusion/`)

These sites contain UNWIND:

- `77act1.mud:1061` ECHO-ROOM
- `77act2.mud:12` BOOM-ROOM and `:41` FLY-ME
- `77rooms.mud:323` FLUSH-ME, `:702` FINISH, `:728` RECORD, `:880` JIGS-UP and `:968` FILE-TO-TTY

Only one cleanup is reachable on an error-free path: RECORD's `<RETURN T .RECORD>`, an MDL transfer, which still runs the cleanup. FLUSH-ME, FINISH and JIGS-UP QUIT inside their bodies. If QUIT or a raise ran the cleanups, FINISH/RECORD would run twice. The game's ERROR handler (`77rooms.mud:215`) either FINISHes or ERRETs to the ERROR frame. Both are above every UNWIND.

## Change

`mdl/runtime/core.rkt` `mdl-unwind`:

```racket
(define value
  (call-with-exception-handler
   (lambda (raised) (set! raised-through? #t) raised)
   std-thunk))
...
(unless (or completed-normally? raised-through?) (erre-thunk) (void))
```

- The handler only marks the raise. It returns the value, so the raise continues to the next enclosing handler unchanged.
- A raise caught inside the body never reaches it.
- Host bookkeeping (activation liveness, binding restoration, OBLIST path and interrupt level) still unwinds through its own `dynamic-wind`/`parameterize`.
- QUIT is still not implemented. When it is, it must be a raised non-`exn:fail` signal, and the test "a raised non-exn value … skips cleanups" pins that design.

## Tests: red, then green

New file `tests/unwind_raise_test.rkt`, added to `scripts/test_racket.sh`. It has 26 test cases.

**Red** on the base runtime (`248b9b1`): `raco test tests/unwind_raise_test.rkt` exited **1** with **11/26 test failures**. The failing cases:

- strict error: a cleanup RETURN past it cannot swallow it (`no-exception`)
- strict error with the issue's exact cleanup shape (no exception raised)
- MDL ERROR: a cleanup RETURN past it cannot swallow it
- `<UNWIND <ERROR FOO> <ERROR BAR>>` surfaces FOO (actual `mdl-error: BAR`)
- FINISH-shaped (actual `operator QUIT`)
- host strict error in the body (`CL` 1)
- unassigned QUIT in the body (`CL` 1)
- ERROR handler falls through (`CL` 1)
- a raise under two UNWINDs (`CL`/`OUT` 1)
- a raised non-exn value (2 cleanups)
- an error in an inner cleanup abandons the transfer (`OUT` 1)

The 15 transfer and handler cases passed before and after the change, which confirms that RETURN, AGAIN, GO and MAPLEAVE behaviour is preserved.

**Green:**

| Command | Exit | Result |
|---|---:|---|
| `raco test tests/unwind_raise_test.rkt` | 0 | 26 tests passed |
| `raco test tests/unwind_raise_test.rkt tests/control_test.rkt tests/mapf_test.rkt mdl/runtime/core.rkt tests/error_interrupt_test.rkt tests/erret_interrupt_cleanup_test.rkt tests/oblist_identity_test.rkt` | 0 | 193 tests passed |
| `make test-racket` (sandboxed) | 2 | 3 files abort writing to hard-coded `/tmp/mdl-*` (`Read-only file system`): `loader_test`, `declaration_test`, `percent_read_test`. Not a code failure. |
| `make test-racket` (outside the sandbox) | 0 | **2261 tests passed** |
| `make test-python` (outside the sandbox) | 0 | 23 passed |

### Changed existing expectations

- **`tests/control_test.rkt`** (`<SETG M2-C 0> <UNWIND <M2-BOOM> <SETG M2-C 1>>`): the error still raises `unassigned or non-applicable`, but `,M2-C` is now **0** instead of 1. The old expectation encoded ADR-0018's cleanup-on-error rule. The comment now cites ADR-0051.
- **`mdl/runtime/core.rkt` test submodule:** `error-cleaned?` after `(mdl-unwind (lambda () (error 'test "boom")) …)` changes from `check-true` to `check-false`, for the same reason.
- **`tests/mapf_test.rkt`:** no change. Its only UNWIND test is MAPLEAVE, a transfer, and it still runs the cleanup once.

## Mutation checks

Script: `PLTCOLLECTS=":$PWD" python3 -I docs/evidence/M3/I139-mutations.py`. Each mutant replaces the `mdl-unwind` body, recompiles, runs the four files, and restores the file. The restored tree was green afterwards (193 tests passed, exit 0).

| Mutant | unwind_raise | control | mapf | core submodule |
|---|---|---|---|---|
| M1 plain `dynamic-wind` (cleanup on every exit) | exit 1, 14/26 | exit 1, 3/44 | exit 0 | exit 1, 2/38 |
| M2 old ADR-0018 flagged wind (cleanup on raise) | exit 1, 11/26 | exit 1, 1/44 | exit 0 | exit 1, 1/38 |
| M3 drop cleanup on transfers | exit 1, 13/26 | exit 1, 2/44 | exit 1, 1/40 | exit 1, 1/38 |
| M4 swallow errors raised inside cleanups | exit 1, 2/26 | exit 0 | exit 0 | exit 0 |
| M5 only `exn` raises skip (non-exn QUIT signal would clean) | exit 1, 1/26 | exit 0 | exit 0 | exit 0 |

## Game load path

| Command | Sandboxed | Outside the sandbox |
|---|---|---|
| `make test-historical` | exit 2: `historical_vfload_test` cannot create `/tmp/mdl-vfload-test*` (read-only) | **exit 0**, no FAILURE lines; OBLIST placement matches Confusion (2350 entries); START still stops at unassigned `RANDOM`, as before |
| `make test-m3-historical-gc` | exit 2: `/tmp/mdl-historical-gc*` (read-only) | **exit 0**, 18 tests passed |
| `make m3-source-progress` | exit 2: `historical_g3_test` cannot create `/tmp/mdl-g3-test*` (read-only) | **exit 0**: reader sweep 36 parsed / 0 failed / 4 non-text; G3 58 assertions; AND? 5 globals; `M3 source progress LOADED: 1229 completed, delta +1205, 0 skipped` (same as the I119/I124 baseline) |

The sandboxed failures are environmental only: those tests hard-code `/tmp` scratch directories. No tracked file was modified by these runs.

Runtime probe after the fix: `PLTCOLLECTS=":$PWD" racket docs/evidence/M3/I139-uw-runtime-probe.rkt OUT.json` exited 0 and wrote `I139-uw-runtime-after.json`. Every raised case now shows `CL` = 0 and the original error. Transfers are unchanged. On this branch `UNPARSE` is unassigned, so its case reports the unassigned-operator error. With the fix, the non-exn QUIT model runs no cleanup.

## Deviations (documented, not emulated)

- **No interactive error level.** A raised error is terminal here. Confusion's outcome is the same when its error level is never left. The following need an operator at level 2 and are **not modelled**:
  - ERRET with no arguments
  - ERRET to a frame below the UNWIND
  - RETRY (Confusion's own RETRY fails with `Bad longjmp`)
  - a RETURN typed at level 2

  Confusion would run the cleanup in those cases.
- **Error inside a cleanup during a transfer.** Confusion suspends the transfer at level 2 and completes it after ERRET. Here the cleanup's error propagates unchanged and is terminal. The pending transfer and any outer cleanups on that path are abandoned. An ERROR handler that ERRETs inside the cleanup still lets the transfer complete, matching Confusion's `error-inside-cleanup-erret-value`.
- **Interrupt-handler transfers** (a handler RETURNs past the UNWIND) run the cleanup. This follows the manual. Confusion stubs HANDLER, so it cannot confirm it.
- **No diagnostics for skipped cleanups.** The original exception is the only report, and nothing is printed to stdout.

## Risks

- **Resumed breaks.** If a handler outside the UNWIND resumed a break, so that control re-entered the body through a resumed `exn:break` continuation, the raise mark would stay set and a later transfer would skip its cleanup. That is the only real hole. No runtime code resumes breaks: `grep raise-continuable|exn:break mdl/ scripts/` finds nothing. Continuable raises cannot happen here: `raise-continuable` is unbound in the Racket 7.9 BC used by this project (independent review, 2026-11-23).
- **Older M2 records.** `REQUIREMENTS-AUDIT.md`, `MAINLINE-GATE.md` and `BRANCH-ACCEPTANCE.md` in `docs/evidence/M2/` still describe the old deviation. They are historical gate records. `docs/evidence/M2/CONTROL.md` carries a supersession note.

## Security and licensing

- No REPL, evaluator service or filesystem access was added.
- No upstream source, provenance, public license or deployed service changed.
- No GPLv3 Confusion code was copied. Confusion was used only as a local black-box reference. The manual is cited by URL with short quotes.

## Next action

Implement QUIT as a raised non-`exn:fail` session signal caught by the host loop, which skips cleanups per ADR-0051. Track it with the RNG and terminal I/O work on the M3 INITIALIZED frontier.

## Orchestrator gate and independent review (2026-11-23)

Unsandboxed full gate at `644465f`, run as the normal user with
`PLTCOLLECTS=":$PWD" TMPDIR=/tmp PYTHON=/usr/bin/python3 PYTHONPATH=$PWD/.sandbox-pydeps/lib`:

| command | exit |
|---|---|
| `make test` | 0 |
| `make test-historical` | 0 (placement matches pinned Confusion, 2350 entries) |
| `make m3-source-progress` | 0 |
| `make test-m3-historical-gc` | 0 |
| `git diff --check` | 0 |

No log contained `test failures`, `FAILURE` or `raised an exception`.

Independent review verdict: **APPROVE WITH NITS**. It found no case where an error is swallowed or a transfer skips its cleanup.
- **Transfers:** every MDL transfer is an escape continuation, never an exception: `let/ec` for PROG/REPEAT and activations, MAPLEAVE/MAPRET/MAPSTOP, and `call/ec` for ERRET.
- **Raise mark:** it is local to each UNWIND call.
- **Bookkeeping:** host state is restored after a raise.
- **Reviewer's own mutations, all caught:**
  - handler no longer sets the mark: 11/26;
  - cleanup ignores the mark: 11/26;
  - one mark shared by all UNWINDs: 13/26.
- **Nits fixed after the gate (docs and a test comment only, no code change):**
  - ADR-0051 notes the loader's `exn:fail:mdl-load` wrapper for nested FLOAD;
  - the risk note names resumed breaks as the only real hole;
  - `unwind_raise_test` documents which scenarios pin per-call mark independence.
