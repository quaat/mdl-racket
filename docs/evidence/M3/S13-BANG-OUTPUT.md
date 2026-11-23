# S13: typed `!` in READSTRING (part A) and explicit output for game sessions (part B)

Implementation record, 2026-11-23. Branch `feat/m3-bang-output`, base commit
`067f093195514b6c30c46a76538f86623263971a` (uncommitted working tree at the
time of these runs). Upstream: mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`,
mit_zork `d94501340842e006791fce0757dc0043b8ec8916` (`sources.lock.json`).
Racket v7.9 [bc]. Both parts are maintainer decisions and amend ADR-0050.
Reference authority for part A: `READSTRING-BANG-REFERENCE.md` and
`readstring-bang-probe.json` (pinned Confusion `6df359f6…`). No GPLv3 code was
copied; no game source, upstream file or provenance changed.

## Part A: the `!` escape in READSTRING

**Decision:** follow pinned Confusion (ADR-0050 §3 amended; contract in
SEMANTICS, READSTRING). A unit is a character `c` or the pair `!` `c`; the pair
stores `c` in one slot and the `!` is never stored or counted. The stop test
and the >127 check apply to `c` whether or not it was escaped, so an escaped
CR/LF/ESC still stops the read and is consumed. `!` immediately before end of
input is stored as a literal `!`, counted, and sets the end-of-input flag (the
next READSTRING raises the D3 exhausted error). A unit starts only when the
buffer has room, so pairing resumes on the next READSTRING. Code:
`mdl/runtime/core.rkt`, `mdl-readstring` read loop.

**Tests (one assertion group per reference case):**
- `tests/readstring_bang_test.rkt` (registered in `scripts/test_racket.sh`):
  bang-mid, bang-double, bang-double-between, bang-multiple, bang-before-lf,
  bang-before-cr, bang-before-crlf, bang-before-esc, bang-before-tab,
  bang-before-backslash, backslash-plain, bang-before-eof (+ next read
  exhausted), bang-only-eof (+ next read exhausted),
  bang-buffer-boundary-last-slot, bang-buffer-boundary-straddle (+ unread
  remainder `!cd\n`), bang-buffer-boundary-2; bang-fix-stop and
  bang-before-nonascii assert the unchanged strict errors.
- `tests/historical_bang_input_test.rkt`, new target `make test-m3-bang`
  (also added to `.github/workflows/reference.yml`): loads `77loadall.mud`
  into a fresh session per case on the reference clock (fixed epoch
  250776000, `'utc`), runs SAVE-IT and RDCOM through the host loop on the
  case's typed bytes and compares `canonical_text(raw)` (pipe captures: no
  ONLCR) with the reference `result_after_listening` minus its `"DONE"` line.
  Cases: game-baseline-north, game-bang-mid-word (`nor!th`, also asserted
  equal to the `north` transcript), game-bang-first (`!north`, equal to
  `north`), game-mixed-case-bang, game-bang-double, game-bang-before-lf,
  game-bang-before-esc, game-bang-before-eof (north runs, no `Beg pardon?`),
  game-buffer-boundary. Every run must end with
  `exn:fail:mdl-input-exhausted`.

**Reference cases not matched (recorded deviations, unchanged by S13):**
- bang-fix-stop: a FIX stop is a strict unsupported error (ADR-0050 §3).
- nonascii-latin1, nonascii-utf8, bang-before-nonascii, game-nonascii:
  Confusion stores raw bytes (negative `ASCII`); this runtime refuses any
  character above 127, escaped or not (a raw 0xE9 decodes to U+FFFD, code
  65533; both are refused). No loosening.
- pty cases: same results as pipe in the reference; not separately run.

**Red → green:**

| Command | Before implementation | After |
| --- | --- | --- |
| `raco test tests/readstring_bang_test.rkt` | exit 1 (raised: `READSTRING: '!' in terminal input is not supported …`) | exit 0 |
| `make test-m3-bang` | exit 2, 18/86 failures (every `!` case; baseline `north` already matched) | exit 0, 86 tests passed |

The old assertion in `tests/readstring_test.rkt` that refused `Ab!cD` was
removed (it encoded the superseded rule); its non-ASCII refusal stays.

**Mutations** (`$TMPDIR/s13/mutate.py`: apply, run, restore; each killed):

| Mutant | Test | Result |
| --- | --- | --- |
| A1 `!` stored literally (`escaped?` forced #f) | readstring_bang_test | exit 1, 14/24 failures |
| A1 | historical_bang_input_test | exit 1, 4/86 failures |
| A2 escape suppresses stop termination | readstring_bang_test | exit 1, 4/24 failures |
| A2 | historical_bang_input_test | exit 1, 2/86 failures |
| A3 non-ASCII after `!` accepted | readstring_bang_test | exit 1, 3/24 failures |
| A4 trailing `!` before EOF dropped | readstring_bang_test | exit 1, 2/24 failures |
| A4 | historical_bang_input_test | exit 0 (not killed: RDCOM's output for INBUF "north!" equals "north"; the unit test kills it) |

## Part B: explicit output port for game sessions

**Decision:** "explicit output for game sessions" (ADR-0050 "Explicit output
port", amended; SEMANTICS "Host ports"). A PRINT CHANNEL created by
`make-mdl-session` or `make-mdl-context` without `#:output-port` has no port.
Every operation that resolves it raises
`<who>: this session's PRINT CHANNEL has no host-supplied output port; the runtime never falls back to the host's current-output-port (ADR-0050)`:
PRINC, PRIN1, PRINTSTRING, TERPRI, CRLF, READSTRING's pre-read flush
(`who` = READSTRING, before any input is consumed), the host loop's entry
print (PRIN1/TERPRI) and its final flush (`who` = host-loop). Argument errors
are still reported first (the port is resolved after the other arguments are
validated), so Confusion's argument-check order does not depend on host
configuration. `mdl-session-run-interactive` keeps its explicit-port check.

**F2:** the final flush resolves each PRINT channel's port inside its failure
collector, so the strict error is collected like any flush failure: with a
primary leaving the loop it is a secondary failure
(`mdl-host-loop-secondary-failures`), the primary is re-raised unchanged
(same object); with nothing raised (host escape out of ON-EVENT) it is raised.

**Opt-in for non-session use:** `mdl-ensure-terminal-channels!
#:follow-current-output-port? #t` (mutually exclusive with `#:output-port`)
creates a PRINT channel that writes to the host's `current-output-port` at
each operation, via a private marker value that is not exported. Exactly two
callers use it: the process-wide default context at the end of `core.rkt`
(core unit tests and hosts that never create a context) and `#lang mdl`
modules (`mdl/lang/reader.rkt`), which run in that ambient context. Neither
`make-mdl-session` nor `make-mdl-context` accepts the keyword (tested:
`exn:fail:contract`). A keyword on the low-level initializer was chosen over
a new constructor because the ambient context is not built by a constructor:
it is the parameters' initial values, initialized once by
`mdl-ensure-terminal-channels!`.

**Tests:** `tests/session_output_port_test.rkt` (registered in
`scripts/test_racket.sh`, 108 checks): with `current-output-port`
parameterized to a sentinel string port, each of PRINC, PRIN1, PRINTSTRING,
TERPRI, CRLF (default and explicit channel) in a port-less session; the
READSTRING pre-read flush (input left unread); output during a load (load
FAIL with the strict message); `mdl-session-run-interactive` refusal; the
same five ops plus READSTRING in a port-less `make-mdl-context`; the host
loop's entry print (primary) with the final-flush error as its secondary;
an entry primary re-raised unchanged with the flush error as secondary; an
ON-EVENT escape that raises the flush error; argument errors before the port
error. Every case asserts the sentinel stays empty. Positive cases: all five
ops and READSTRING reach the supplied port; the host loop's entry print goes
to the supplied port; a context with `#:output-port`; the ambient opt-in and
a fresh space with/without the opt-in.

**Red → green:** `raco test tests/session_output_port_test.rkt` exit 1
(28/32 failures, then an uncaught exception) before; exit 0 (108 checks)
after.

**Mutations** (each killed):

| Mutant | Result |
| --- | --- |
| B0 fallback for every op (`else` → `current-output-port`) | exit 1, 28/41 failures |
| B1 fallback for PRINC only | exit 1, 8/102 failures |
| B1 fallback for PRIN1 only | exit 1, 10/104 failures |
| B1 fallback for PRINTSTRING only | exit 1, 7/105 failures |
| B1 fallback for TERPRI only | exit 1, 6/105 failures |
| B1 fallback for CRLF only | exit 1, 6/105 failures |
| B2 READSTRING pre-read flush falls back | exit 1, 3/106 failures |
| B2 host-loop final flush falls back | exit 1, 1/78 failures |
| B3 `make-mdl-context` silently opts in when no port | exit 1, 28/41 failures |

**Migrated callers** (all now pass an explicit port; behaviour otherwise
unchanged):
- `scripts/mdl_load.rkt`: `#:output-port (current-output-port)` (the game's
  `… loaded` lines still reach the driver's stdout; `m3_source_progress.py`
  records them as before).
- `scripts/audit_source_readiness.rkt`: `make-mdl-context #:output-port
  (current-output-port)`.
- `tests/channel_port_test.rkt`: `in-fresh-context` gives each context its
  own string port; `capture` reads that port and asserts nothing reaches
  `current-output-port`; test 7 now states that only the default context
  follows the current port per call; test 12 contexts get explicit ports.
- `tests/printstring_channel_test.rkt`, `tests/crlf_test.rkt`,
  `tests/string_view_consumers_test.rkt`, `tests/oblist_identity_test.rkt`.
- `tests/historical_andq_test.rkt`, `historical_g3_test.rkt`,
  `historical_gc_handler_test.rkt`, `historical_start_back_test.rkt`,
  `historical_vfload_test.rkt`, `historical_oblist_placement_test.rkt`
  (each read output from the session port instead of a parameterized
  `current-output-port`).
- Unchanged (already explicit or never write): every other `make-mdl-session`
  caller; `#lang mdl` fixtures (opt-in).

## Commands and results

All with `export PLTCOLLECTS=":$PWD"` in the worktree.

| Command | Exit | Result |
| --- | --- | --- |
| `bash scripts/test_racket.sh` (baseline, before S13) | 1 | 3/3333 failures: `loader_test`, `declaration_test`, `percent_read_test` hardcode `/tmp` (read-only in the sandbox) |
| `bash scripts/test_racket.sh` (final) | 1 | 3/3466 failures: the same three `/tmp` files only |
| the three `/tmp` files as scratch copies with `/tmp` → `$TMPDIR` | 0 | 155 tests passed (originals unchanged) |
| `make test-m3-saveit` | 0 | 32 tests passed |
| `make test-m3-interactive` | 0 | 31 tests passed |
| `make test-m3-clock-seed` | 0 | 17 tests passed |
| `make test-m3-session` | 0 | 85 tests passed |
| `make test-m3-bang` | 0 | 86 tests passed |
| `make m3-source-progress` | 2 | stops at `test-m2-g3`: `/tmp` read-only in the sandbox (after `check-source`: 36 parsed, 0 failed) |
| `python3 scripts/m3_source_progress.py --output $TMPDIR/… --raw-output $TMPDIR/…` | 0 | LOADED: 1229 completed, 0 skipped, loader exit 0 |
| every `tests/historical_*.rkt` as a scratch copy (`/tmp` → `$TMPDIR`) run with `racket` from the worktree root | 0 each | 16 files, no FAILURE lines (G3 58 assertions, VFLOAD 23, OBLIST placement 2350 entries, AND? 5 globals, …) |
| `racket scripts/audit_source_readiness.rkt --output $TMPDIR/…` | 0 | 5 pinned files audited |
| `PYTHONPATH=.sandbox-pydeps/lib python3 -m pytest -q` (the `test-python` file list) | 0 | 23 passed (`make test-python` itself: exit 2, no system pytest) |

## Limitations and risks

- Part A follows Confusion by decision. The manual is silent on `!` in
  terminal input; whether ITS MDL interpreted it is undetermined.
- Non-ASCII input and FIX stops remain strict (deviations above).
- Part B changes a runtime-wide contract: any out-of-tree host that relied
  on the implicit stdout fallback now gets a strict error until it passes
  `#:output-port`. Racket's own module-level result printing in `#lang mdl`
  modules is not an MDL terminal operation and still goes to
  `current-output-port`.
- `make m3-source-progress`, `make test-m2-g3` and `make test-m3-andq` could
  not run unmodified in the sandbox (`/tmp`); equivalent scratch-copy runs
  passed.
- Security: no new host capability; part B removes the last implicit host
  port from sessions. Licensing: unchanged.
