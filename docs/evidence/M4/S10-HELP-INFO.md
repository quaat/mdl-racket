# M4 S10: help and info under a read-only allowlist (issue #171; scenario `help-info`)

Date: 2026-11-25. Branch `feat/m4-help-info-allowlist` from `main` `6b826d5`.
Upstream mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`, mit_zork
`d94501340842e006791fce0757dc0043b8ec8916` (`sources.lock.json`). Pinned mdli
sha256 `6df359f6…b789` before and after every capture (never rebuilt). Racket
v7.9 [bc], Python 3.9.2.

Result: **`help`, `info` and `?` print the shipped files exactly as native
Confusion; scenario `help-info` PASS in both runner modes (single run: all 9
turns, output and checkpoints including the 100 codes of `,INBUF`; per prefix:
all 9 prefixes, k = 0..8), and a replay checkpoint taken after `help` or `?`
restores exactly (branch evidence, scenario-scoped, one seed).** Inventory
INV-05 is fixed and INV-08 partly (FILE-LENGTH, file READSTRING, CLOSE for the
allowlisted CHANNELs only). Frontier F3 is now a positive regression. Not a
PLAYABLE claim and not the M4 gate.

## Decisions

* Maintainer, #171, 2026-11-24: **"Read-only allowlist"**: OPEN "READ"
  succeeds only for exactly `MDL/MADADV.HELP` and `MDL/MADADV.INFO` in the
  pinned game directory, hash-checked and read-only; everything else stays
  denied (ADR-0055 amendment, accepted).
* Orchestrator, 2026-11-25, within that decision (recorded in the
  amendment): (a) a missing allowlisted file is a strict error; (b) a second
  CLOSE returns the CHANNEL, as natively; (c) CHANNEL element 10 holds the
  requested directory, never a host path; (d) native crashes are strict
  errors; (e) the runner's prompt split is a per-scenario option
  (`#:prompt-split 'line-initial`, ADR-0062 amendment).

## Native findings ([HELP-INFO-REFERENCE.md](HELP-INFO-REFERENCE.md))

* FILE-LENGTH is in **characters = bytes** (4274, 1527), not 36-bit words.
* READSTRING from a file: a FIX third argument is an exact count; a STRING
  stops (stop consumed, not stored); end of file returns the partial count
  (74 / 27 in the game) and sets CHANNEL element 11 to 1; any further read is
  the host error `Unexpected EOF`; `!` escapes as on the terminal.
* CLOSE returns the CHANNEL and clears elements 1 and 7–10; a second CLOSE
  returns it again.
* No case folding; the device is not part of the file spec; element 10 is the
  absolute host directory natively.
* The game prints CRLF, the file, CRLF; `help`/`info`/`?` each count as a
  move; the help text contains two mid-line `>`.

## Design

* `mdl/runtime/core.rkt`: `mdl-read-only-file` (validated entry: four names
  of `[A-Za-z0-9]{1,32}`, lowercase sha256, size ≤ 1 MiB); the session's
  allowlist and host reader live in its atom space (host-only, never
  reachable from MDL). `OPEN "READ"` compares the four request strings with
  each entry by `equal?` (exact, case-sensitive) **before any file-system
  access**; no match is the strict error (`mode "READ" is not supported for
  …: it is not on this session's read-only allowlist`). A match calls the
  host reader, checks size and sha256, and builds a 19-element CHANNEL whose
  host record holds an input port over the immutable content bytes (no host
  file handle). `FILE-LENGTH`, `CLOSE`, and a file branch of `READSTRING`
  that never flushes and never calls the ADR-0061 observer; the terminal
  branch is unchanged (shared unit loop `readstring-units`). RESET and TOP
  refuse file CHANNELs.
* `mdl/loader.rkt`: `make-mdl-session #:read-only-files` (default empty) and
  the host reader `read-only-file-bytes`: path `root/directory/name1.name2`
  from the validated entry only; refuses a symbolic-link directory or file, a
  missing or non-regular file, a size ≠ pinned (before reading), and an
  opened file whose identity differs from the checked path; reads at most
  size+1 bytes; closes the file. `mdl-session-file-channels` for hosts.
* `zork/game-files.rkt`: the two pinned entries. Passed by `run-zork`, the
  replay profile (`replay-profile-read-only-files`, new field) and the M4
  scenario runner. `mdl-open-records` keeps recording denials only.
* `tests/m4_scenario_runner.rkt`: `#:prompt-split 'line-initial` (strict
  count kept; must equal the reference's `prompt_split`); guard: no file
  CHANNEL left open.

## Security analysis

* **No new reachable file.** MDL cannot add allowlist entries; hosts pass a
  fixed list. Denied requests (any other name, case, device, directory,
  `..`, separators, empty names, the one-spec and 3/4-argument forms) fail
  before the host is consulted: `tests/file_read_test.rkt` records **zero**
  file-system accesses for twelve such requests under a security guard.
* **Path construction** uses only the validated entry (no separator, dot or
  empty component can occur), inside the session's canonical root.
* **Integrity**: size pre-check, symbolic links refused (directory and file),
  port identity = path identity after open, bounded read (size+1), sha256
  check; any failure is strict. Content is served from immutable bytes read
  once, so there is no window between check and use and no host handle stays
  open.
* **Read-only**: the CHANNEL is READ; every output primitive refuses it; no
  write mode was added; the launcher, replay and runner keep their no-write
  security guards (every scenario and replay run recorded no write or delete
  and left the game directory hashes unchanged).
* **Residual risk** (local attacker with write access to the game
  directory): the identity check covers the final path component; a race on
  the `MDL` directory component between the link check and the open could
  make the host open a same-named file elsewhere. Its bytes are served only
  if they hash to the pinned value, so no other content can reach the game.
* **Sessions** never share file CHANNELs (tested); CLOSE releases the
  content; the runner fails a run that leaves one open.
* No server or web client can reach OPEN; no MDL evaluator is exposed.

## Deviations (recorded in SEMANTICS and the ADR-0055 amendment)

1. CHANNEL element 10 is `"MDL"`, not the absolute host directory.
2. Channel number (element 1): lowest free ≥ 3 among the session's open file
   CHANNELs (natively the host descriptor; 3 for the game's opens either way).
3. Native crashes are strict errors: FILE-LENGTH of a non-CHANNEL, a negative
   READSTRING count, a count larger than the buffer (natively writes past it).
4. FILE-LENGTH on a terminal CHANNEL (`FILE-LENGTH-UNAVAILABLE`) and after
   CLOSE (`CHANNEL-CLOSED`) are strict host errors, not MDL ERRORs.
5. A read after end of file is a strict error (natively a host error that
   returns to LISTEN level 1).
6. A missing or altered allowlisted file is a strict error (natively FALSE /
   `File not found.` or the altered text).
7. Every other OPEN "READ" is strict, including forms that natively open the
   same file (another device, `MDL/../MDL`, the one-spec form).
8. RESET of a file CHANNEL and CLOSE of a terminal CHANNEL are strict;
   ACCESS stays unimplemented.
9. PRINTSTRING still returns the count (M3 deviation; FILE-TO-TTY discards it).

## Tests (failing first)

* `tests/file_read_test.rkt` (in `make test`): failed before the
  implementation (the module did not compile: `mdl-read-only-file` missing),
  17 tests pass after: CHANNEL layout, numbering, FILE-LENGTH, count / stop /
  two-argument reads, end of file, `!`, CLOSE (value, slots, double close),
  output and RESET refusals, denials with zero accesses, integrity (sha256,
  size, missing, non-regular, symbolic link file and directory), entry
  validation, observer never called by file reads, session isolation, the
  game's FILE-TO-TTY verbatim on partial and exact last chunks, and the two
  pinned files read back byte for byte.
* `tests/historical_help_info_test.rkt` (`make test-m4-help-info`).
* `tests/help_info_replay_test.rkt` (in `make test-m4-replay-persistence`):
  the save boundary is offered only at the 9 RDCOM prompts (never inside the
  102 file reads); checkpoints after `help` and `?` log only the typed
  commands; both restore exactly (pre-save + post-restore = native T1); a
  changed MADADV.HELP makes the restore fail strictly (sha256).
* Runner unit tests for `#:prompt-split` (`tests/m4_scenario_runner.rkt`).
* Updated: frontier F3 (now positive regressions against reference P02/P04),
  `quit_open_test`, `launcher_test` and `historical_session_quit_test` (their
  strict example moves from `info` to `restore`), `replay_checkpoint_test`
  (profile field), `function_type_test` (FILE-LENGTH, CLOSE: SUBR, re-recorded
  probe), `test_sweep_operator_heads.py`.

## Mutation checks (each reverted by rewriting the original file; tree clean after)

| Mutation | Command | Exit | Detected by |
|---|---|---|---|
| M1 allowlist matches case-insensitively | `raco test tests/file_read_test.rkt` | 1 | "every OPEN READ off the allowlist …" |
| M2 allowlist ignores name2 (a third file opens) | same | 1 | same test |
| M3 zork allowlist gains MADADV.SAVE | same | 1 | "exactly the two pinned files" / SAVE not readable |
| M4 sha256 check disabled | same | 1 | "pinned content: hash, size, …" |
| M5 symbolic-link check on the file removed | same | 1 | same test |
| M6 file READSTRING calls the input observer | same / `racket tests/historical_help_info_test.rkt` | 1 / 1 | observer test / earliest failing k = 2 (transcript) |
| M7 FILE-LENGTH in 36-bit words | same two | 1 / 1 | FILE-LENGTH checks / earliest failing k = 2 (transcript) |
| M8 read after EOF raises the terminal input-exhausted exn | `raco test tests/file_read_test.rkt` | 1 | "end of file: partial count, …" |
| M9 a second CLOSE is an error | same | 1 | CLOSE test (error) |
| M10 runner ignores `#:prompt-split` | `racket tests/historical_help_info_test.rkt` | 1 | `P02-help-info-prefix: expected 4 prompts … found 6` |
| M11 end of file clears the stale buffer tail | same | 1 | earliest failing k = 2 (checkpoint: `,INBUF`) |

## Commands and results

| Command | Exit | Notes |
|---|---|---|
| `python3 -I scripts/probe_file_read_reference.py docs/evidence/M4/file-read-probe.json` | 0 | 53 cases; mdli sha256 unchanged |
| `python3 -I scripts/probe_help_info_scenario_reference.py docs/evidence/M4/help-info-reference.json` (twice; second to `$TMPDIR`) | 0, 0 | 19 runs each; identical transcripts, hashes and checkpoints |
| `python3 -I scripts/probe_function_type_reference.py docs/evidence/M4/function-type-probe.json` | 0 | 119 names, all SUBR (FILE-LENGTH, CLOSE added) |
| `python3 -I scripts/sweep_operator_heads.py docs/evidence/M4/operator-head-sweep.json` | 0 | builtin 122, missing 19 |
| `racket tests/file_read_test.rkt` before the implementation | 1 | module did not compile (`mdl-read-only-file` missing) |
| `raco test tests/file_read_test.rkt` | 0 | 17 passed |
| `raco test tests/m4_scenario_runner.rkt` | 0 | 39 passed |
| `racket tests/historical_help_info_test.rkt` | 0 | single run, 9 turns, 5.7 s |
| `M4_SCENARIO_MODE=per-prefix racket tests/historical_help_info_test.rkt` | 0 | 9 boots, 51.4 s |
| `racket tests/help_info_replay_test.rkt` | 0 | 26 s |
| `racket tests/historical_m4_frontier_test.rkt` | 0 | F3 help / info resolved |
| `raco test tests/historical_session_quit_test.rkt` | 0 | 85 passed |
| `raco test tests/function_type_test.rkt` | 0 | 340 passed |
| `pytest tests/test_sweep_operator_heads.py` | 0 | 6 passed |

Final sequential verification: see the next section.

## Licensing

No Confusion source was copied (GPLv3 reference only). The help and info
files are read from the pinned upstream checkout at run time, as the game
sources are; nothing new is bundled.
