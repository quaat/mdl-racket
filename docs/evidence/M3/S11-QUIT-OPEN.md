# S11: QUIT as a session outcome, OPEN denial, a complete local quit session

Implementation record for ADR-0054 (QUIT and the host-loop outcome) and ADR-0055
(OPEN under the virtual no-file policy). Contracts: SEMANTICS "M3 session end:
`QUIT` and the host-loop outcome" and "M3 file system: `OPEN` denial", both
written before the implementation.

| Item | Value |
|---|---|
| Branch / base | `feat/m3-quit-open` at `d653d5f` (S7 host loop, F2, S8 clock, S9 MEMBER) |
| Upstream (`sources.lock.json`) | mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; MITDDC/zork `d94501340842e006791fce0757dc0043b8ec8916` |
| Reference | pinned Confusion mdli `6df359f6…b789`; `session-quit-probe.json` (C1, C2, C3), `open-failure-probe.json` |
| Clock / input | fixed session clock 250776000 (1977-12-12 12:00:00), zone `'utc`; LF-terminated lines, no echo |
| Toolchain | Racket v7.9 [bc]; `export PLTCOLLECTS=":$PWD"` |

No file under `.cache/upstream/` was modified. `tests/scenarios/house-boot.json`
and its golden are unchanged.

## What changed

- `mdl/runtime/core.rkt`
  - `QUIT` SUBR: zero arguments only; raises `mdl-quit-signal` (a plain struct, not an
    `exn`). One argument: `QUIT: an exit-status argument is not supported (ADR-0054)`;
    two or more: `QUIT: TOO-MANY-ARGUMENTS-SUPPLIED`.
  - `mdl-unwind` is unchanged: its existing raise mark already treats the signal as a
    raise passing through, so cleanups are skipped (verified by mutation M2).
  - `ERROR` records each signalled message in the session (host-only).
  - `mdl-run-host-loop` catches exactly `mdl-quit-signal` at the boundary and returns
    `mdl-session-outcome` (`kind` = `'quit` | `'quit-after-mdl-error`, `mdl-errors`).
  - `OPEN` SUBR: the five-STRING RECORD form, modes READB/PRINT/PRINTO, returns
    `#FALSE (reason "dir/name1.name2" status)`; records `mdl-open-record`s.
- `mdl/loader.rkt`: exports the outcome API and `mdl-session-open-records`.
- Tests: `tests/quit_open_test.rkt` (smoke suite), `tests/historical_session_quit_test.rkt`
  (`make test-m3-session`), `tests/scenarios/house-quit.json`; `tests/unwind_raise_test.rkt`
  updated (its "unassigned QUIT" case now asserts the quit signal and no cleanup).

## Outcome taxonomy (host API)

| Ending | `mdl-session-run-interactive` |
|---|---|
| Game QUIT, no MDL ERROR during the run | returns `mdl-session-outcome`, kind `'quit` |
| Game QUIT after an MDL ERROR was signalled (HANDLE → FINISH → QUIT, or ERRET then play) | returns kind `'quit-after-mdl-error`, messages in `mdl-session-outcome-mdl-errors` |
| Input exhausted (D3) | raises `exn:fail:mdl-input-exhausted` |
| Host cancellation | raises the `exn:break` |
| Strict host/runtime failure, unresolved MDL ERROR, pass bound | raises that `exn:fail` (same object) |
| QUIT with a failing final flush | raises the first flush failure (others are its secondaries) |

The game's HANDLE (77rooms.mud:213-252) can reach QUIT through
`FINISH #FALSE (". Error.")` after any MDL ERROR, but in this runtime it first applies
`PRINT` (77rooms.mud:251; XUNM is `"MTRZORK"`, not in WINNERS), which is unsupported,
so today that path ends as a strict failure, never as a quit.

## OPEN call sites

See the table in SEMANTICS "M3 file system: `OPEN` denial". Supported (denied FALSE):
77rooms.mud:731 READB, 736 PRINTO, 748 PRINT (RECORD), and the same PRINT form at 354
(DO-SCRIPT, not exercised). Strict: 316, 392, 412 (one file-spec STRING), 350, 352,
381, 384, 961 (`"READ"`), 392 (`"PRINTB"`).

## Transcript comparison

The reference pipe captures are compared with our raw output byte for byte after D1
only (drop the Confusion banner through `LISTENING-AT-LEVEL 1 PROCESS 1` and the
`"DONE"` line). No ONLCR/D2 step is needed because the reference is a pipe capture;
each reference stdout is checked against its recorded sha256 first.

- **C1 complete session** (house-boot six, `quit`, `n`, `inventory`, `quit`, `y`,
  `look`): **identical**. Outcome `'quit`, no MDL ERROR. Two quit prompts; the scores
  say 7 and 9 moves (quit counts, y/n do not); `MOVES` = 9, `DEATHS` = 0,
  `RAW-SCORE` = 0. Open records exactly `READB MDL/ZORK.LOG 2`, `PRINT MDL/ZORK.LOG 13`
  (RECORD ran once, no busy loop, no CLOSE). `look\n` is still unread in the input
  port. Reference deviation (documented, invisible): Confusion writes
  `MDL/ZORK.LOG` (130 bytes) and rewrites `MDL/MADADV.SAVE`; we write nothing.
- **C2 EOF at the quit prompt**: **identical** through the final `>`; then
  `exn:fail:mdl-input-exhausted` (Confusion: `Error: Unexpected EOF`). No OPEN.
- **C3 prefix** (`xyzzy`, `frobozzle`, `blorfintz`, `qqq`, `take`, `open the`, then
  `quit`, `y`): the boot and the six replies are **identical** to the C3 reference
  segments; the quit segment equals C3's with this session's move count (7).
  The full C3 input is blocked at `put leaflet in`: **frontier** `TOP`
  (`77np.mud:126`, in SPARSE's dangling-preposition clause), reached
  RDCOM → EPARSE → SPARSE. Not stubbed.
- **Strict host operation**: `north`, `info` → FILE-TO-TTY's
  `<OPEN "READ" "MADADV" … >` (77rooms.mud:961) raises
  `OPEN: mode "READ" is not supported…`; no HANDLE text, no quit, `quit\ny\n` unread.

Every historical run: no write/delete attempt recorded by the security guard during
load and play, the game directory's manifest (path, size, sha256 of every file) is
unchanged, the empty temporary cwd stays empty, no `MDL/ZORK.LOG` exists.

## Commands and results

All with `export PLTCOLLECTS=":$PWD"` in this worktree.

**Red first.**
- `raco test tests/quit_open_test.rkt` before the implementation: exit 1,
  `mdl-quit-signal?: unbound identifier` (the API did not exist).
- The C1 input through `mdl-session-run-interactive` before the implementation
  (probe script, same session setup as the historical test): the transcript matched up
  to the second quit prompt, then `mdl-eval: unassigned or non-applicable MDL operator
  OPEN` (RECORD, 77rooms.mud:731); `look\n` unread. With OPEN and QUIT in place, no
  further unsupported construct was reached on that path.

**Green.**

| Command | Exit | Result |
|---|---|---|
| `raco test tests/quit_open_test.rkt` | 0 | 55 tests passed |
| `raco test tests/unwind_raise_test.rkt` | 0 | 26 tests passed |
| `bash scripts/test_racket.sh` | 1 | 3/3325 failures: `loader_test`, `declaration_test`, `percent_read_test` cannot create `/tmp/...` in the sandbox (`Read-only file system; errno=30`); hardcoded `/tmp`, known, unchanged. Every other file passes, including `quit_open_test`, `host_loop_test`, `unwind_raise_test` |
| `make test-m3-interactive` | 0 | 31 tests passed |
| `make test-m3-clock-seed` | 0 | 17 tests passed |
| `make test-m3-saveit` | 0 | 32 tests passed |
| `make test-m3-session` (new) | 0 | 85 tests passed (four game runs, about 22 s) |

**Mutations** (each applied alone to `core.rkt`, recompiled, both new test files run,
then the original restored; restore verified with `cmp`):

| Mutation | `quit_open_test` | `test-m3-session` | Notes |
|---|---|---|---|
| M1 QUIT signal is an `exn:fail` subtype | exit 1 (1 failure) | exit 0 | the loop still catches it first; the unit test catches `exn:fail?` interception |
| M2 `mdl-unwind` runs cleanups for the QUIT signal | exit 1 (2) | exit 0 | FINISH's cleanup is itself `<QUIT>`, so the game transcript cannot show it; the synthetic FIN cleanup and nested UNWIND cases do |
| M3 OPEN returns `#FALSE ()` | exit 1 (2) | exit 1 (4) | `<3 .CH>` at 77rooms.mud:744: `mdl-nth: index out of range`, strict, no quit |
| M4 OPEN status 196696 (`*600130*`) | exit 1 (2) | exit 1 (4) | RECORD takes the busy branch; in the game the next form is `SLEEP` (unsupported), so it fails strictly instead of hanging; the unit RECORD model counts the AGAIN loop (bounded at 3) |
| M5 OPEN creates the file | exit 1 (3) | exit 1 (4) | guard records `with-output-to-file ZORK.LOG (read write)`; the cwd is no longer empty |
| M6 host loop does not catch the signal | exit 1 | exit 1 (2) | the raw `#<mdl-quit-signal>` escapes the loop |
| M7 ERROR not recorded | exit 1 (4) | exit 0 | `'quit` instead of `'quit-after-mdl-error` (no game ERROR on the historical path) |

Each historical run has a 300 s wall-clock watchdog (worker thread + `sync/timeout`).

## Limitations

- QUIT's optional argument, CLOSE, FILE-LENGTH, ACCESS, SLEEP, PRINT, TOP and READ/PRINTB
  OPEN modes are unsupported (strict).
- The HANDLE → FINISH → QUIT path is not reachable yet (PRINT); the outcome kind is
  tested with a synthetic HANDLE-shaped handler only.
- `script` would print `I can't open the script channel.` (policy deviation, not run).
- On a quit with a failing final flush the outcome is dropped in favour of the flush
  failure.
- This is not a SMOKE_PARITY claim; it is INTERACTIVE evidence for one scenario family.
