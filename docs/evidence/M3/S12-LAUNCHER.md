# S12 (WP4): local launcher — implementation record

**Result: launcher tests PASS (local).** This is a host-side convenience over
the existing session API; it adds no MDL semantics and makes **no PLAYABLE or
SMOKE_PARITY claim**.

- Base: branch `feat/m3-launcher` at `1273b5e7d86f95ad12b460b504cd25a1c871b414`
  (uncommitted work at the time of this record; the orchestrator commits).
- Upstream (`sources.lock.json`): mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`,
  mit_zork `d94501340842e006791fce0757dc0043b8ec8916`.
- Reference compared: the pinned Confusion pipe captures in
  `docs/evidence/M3/session-quit-probe.json` (cases `C1-session-quit-pipe`,
  `C2-eof-at-yesno`; interpreter `6df359f6…`), D1 only — the same derivation
  as `tests/historical_session_quit_test.rkt`. Input: `tests/scenarios/house-quit.json`;
  clock: fixed session clock 250776000, zone UTC (ADR-0052).
- Toolchain: Racket v7.9 [bc] (local; CI uses 8.10 BC), `PLTCOLLECTS=":$PWD"`.

## Layout and API

- `zork/main.rkt` — library only (no `main` submodule, so running it in
  DrRacket starts nothing). Collection `zork` (the package is `'multi`), kept
  out of the `mdl` collection because it is a host application, not part of
  the language/runtime. Exports `run-zork`, `zork-result` (`kind`,
  `mdl-errors`, `message`), `exn:fail:zork-launcher`,
  `exn:fail:zork-launcher:missing-source`, `default-source-root`,
  `launcher-notice`, `exit-code-for`.
  `(run-zork #:input #:output #:source-root #:clock #:time-zone #:notice?)`
  resolves the pinned game directory with `define-runtime-path`, fails with
  `missing-source` (message names `make sources`) before printing anything,
  prints the `[launcher]`-marked notice unless `#:notice? #f`, makes a fresh
  `make-mdl-session` with the explicit ports, loads `77loadall.mud` (non-PASS
  → `exn:fail:zork-launcher`), runs `mdl-session-run-interactive` with
  `"SAVE-IT"`, and returns the outcome kind; `exn:fail:mdl-input-exhausted`
  becomes `'input-exhausted`. Every other raise (strict failures, `exn:break`)
  propagates. The run is under a security guard that refuses file
  writes/deletes and network use (defense in depth for ADR-0055).
- `zork/cli.rkt` — `main` submodule; the only code that calls `exit`.
- `Makefile`: `test-m3-launcher` (needs `sources`), `play`.

| Exit code | Meaning |
| --- | --- |
| 0 | `'quit` |
| 3 | `'quit-after-mdl-error` (MDL error messages on stderr) |
| 4 | `'input-exhausted` (EOF) |
| 1 | strict failure / load not PASS (message on stderr) |
| 2 | usage error or pinned sources missing |
| 130 | break (Ctrl-C) |

## Commands and results

| Command | Exit | Result |
| --- | --- | --- |
| `raco test tests/launcher_test.rkt` | 0 | 57 tests passed (~38 s) |
| `make test-m3-launcher` | 0 | 57 tests passed |
| `bash scripts/test_racket.sh` | 1 | 3/3325 failures: `loader_test`, `declaration_test`, `percent_read_test` write literal `/tmp/...` dirs the sandbox blocks (known, unrelated) |
| house-quit input piped to `racket zork/cli.rkt --fixed-clock 250776000` | 0 | notice + C1 transcript |
| `printf 'north\n' \| racket zork/cli.rkt --fixed-clock 250776000 --no-notice` | 4 | `Beg pardon?`, `>`, stderr `input ended (EOF)` |
| `printf 'north\ninfo\n' \| racket zork/cli.rkt --no-notice` | 1 | `strict failure: OPEN: mode "READ" is not supported…` |
| `racket zork/cli.rkt --fixed-clock abc` | 2 | usage message |
| `racket zork/cli.rkt --no-notice` on a held-open FIFO, then `kill -INT` | 130 | stderr `zork: interrupted` |
| `racket zork/main.rkt` | 0 | nothing runs (library only) |

`tests/launcher_test.rkt` asserts: the house-quit run returns
`(zork-result 'quit '() #f)` and its output equals the C1 reference byte for
byte (no `[launcher]` text, `look` left unread); C2 input returns
`'input-exhausted` with output equal to the C2 reference; the default notice
is a prefix of the output, every notice line is `[launcher]`-marked, and the
game text after it is unchanged; a second run in the same process boots the
same text, shows `You are empty handed.` and `in 2 moves.` (fails if run 1's
leaflet or move count leaked); a missing source root raises
`missing-source` mentioning `make sources` and prints nothing; the CLI as a
subprocess exits 0 (stdout = notice + C1), 4 (stdout = C2), 1 (strict `info`),
2 (bad flag); `zork/main.rkt` has no `main` submodule; and a break during the
blocking READSTRING (pipe input that never ends, `break-thread` after the
first prompt) ends the `run-zork` thread with `exn:break` (not `exn:fail`)
while the test process continues. Every game run has a 300 s watchdog.

Failing-then-passing (mutation) evidence: making `run-zork` catch
`exn:break` → 1/55 failures (`check-pred exn:break?`); reusing one session
across calls → failure. Both reverted; the suite passes.

## DrRacket behaviour

Not exercised in the DrRacket GUI (headless environment). Evidence is
structural: `run-zork` never calls `exit` (only `zork/cli.rkt`'s `main`
does); it returns a `zork-result` on quit; DrRacket's Stop is a break on the
evaluation thread, and the break test shows a break in the blocking read
leaves `run-zork` as `exn:break` without ending the process.

## Limitations

SAVE is an in-session record only; RESTORE unsupported (ADR-0048). No file is
written (ADR-0055; guard enforced). Unsupported constructs stop the game
strictly: `put leaflet in` from the opening room fails with
`mdl-chtype: unsupported built-in TYPE conversion` (exit 1); `info`/`help`
fail at OPEN `"READ"`; `script` prints `I can't open the script channel.`.
The default real clock makes START's RANDOM seed and the date line vary.
No REPL, evaluator, network service or persistence is exposed.

## Security and licensing

Local process only; input reaches MDL only through the game's READSTRING. No
GPLv3 code copied; no upstream file modified.
