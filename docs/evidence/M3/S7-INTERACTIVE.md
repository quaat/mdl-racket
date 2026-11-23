# S7-INTERACTIVE — terminal RESET, PRINC, PRIN1, READSTRING, end of input and the host loop

> **Reconciliation note (2026-11-23).** Since this record was written: the slice is now PR #141 (`feat/m3-interactive-io` -> `feat/m3-startup-rep`). The #139 UNWIND risk under "Risks and open questions" is resolved on this branch: PR #140 (ADR-0051) was merged into the umbrella and propagated to #141 at `45c387f`. The gate labels below are unchanged. Current status: [STATUS](../../STATUS.md).

**RID**: S7-INTERACTIVE (local task record; no GitHub issue/PR was opened for this slice)
**Branch**: feat/m3-interactive-io
**Base commit**: aea622a (PR #138, S6 review nits)
**Reference binary SHA256**: 6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789
**Upstream SHAs (sources.lock.json)**: mdlzork bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3; MITDDC/zork d94501340842e006791fce0757dc0043b8ec8916
**Toolchain**: Racket v7.9 [bc], /usr/bin/python3 (3.9.2)
**Decision**: [ADR-0050](../../DECISIONS.md) (maintainer decisions D1 "keep the ,NULL
print", D2 "canonical_text(ONLCR(raw))", D3 "Mirror, then strict"); implements ADR-0049 part 3.
**Specification**: SEMANTICS "M3 interactive terminal I/O and the host top-level loop (ADR-0050)",
written and committed (ef9c848) before any code.
**Reference investigation**: [`S7-frontier/INTERACTIVE-FRONTIER.md`](S7-frontier/INTERACTIVE-FRONTIER.md)
with its probe cases and pinned Confusion outputs (copied unchanged; driver paths made repo-relative).

## Commits

| SHA | Content |
|---|---|
| ef9c848 | ADR-0050, SEMANTICS section, probe evidence copy, house-boot scenario, golden extract |
| 15ece03 | RESET (+ `reset_test.rkt`; `historical_saveit_test.rkt`: SAVE-IT now returns `,NULL`) |
| c37b0b9 | PRINC (+ `princ_test.rkt`) |
| 24dbd49 | READSTRING, end-of-input flag, `exn:fail:mdl-input-exhausted` (+ `readstring_test.rkt`) |
| 629ca33 | PRIN1 (+ `prin1_test.rkt`; OBLIST reachability shared with UNPARSE) |
| 7f6e18a | Host loop `mdl-session-run-interactive` / `mdl-run-host-loop` (+ `host_loop_test.rkt`) |
| 5d519d6 | `historical_interactive_test.rkt`, `make test-m3-interactive`, raw transcript evidence |

## What is implemented (all strict outside this list)

- **RESET** of an open terminal CHANNEL of the session: returns the same object; on INCHAN
  clears the host-side end-of-input flag. Queued input, every slot, the BACK predecessor and
  its associations are unchanged. Refused: arity ≠ 1, non-CHANNEL, forged/foreign CHANNEL,
  shifted view.
- **PRINC** STRING (native/view), CHARACTER, FIX; **PRIN1** FIX, empty-PNAME ATOM reachable on
  the OBLIST path (prints nothing: the game's `,NULL`), other ATOMs by the UNPARSE rules.
  Default channel = LVAL OUTCHAN. CR/LF raw; other control characters and non-ASCII refused;
  everything is validated before anything is written. No line breaking.
- **READSTRING** `<READSTRING buffer channel [stop-string]>`: mutable STRING/view buffer, open
  READ CHANNEL, STRING stop. Flushes terminal output, then reads until full / stop (consumed,
  not stored) / end of input. Stale buffer characters kept; overflow leaves the rest of the
  line. Refused: 0-1 args (default channel), FIX stop, EOF routine (4th arg), 5+ args,
  immutable/typed buffer, `!` or non-ASCII in input.
- **End of input (D3)**: first read at end of input returns its count (0 → `Beg pardon?`)
  and sets the flag; the next READSTRING raises `exn:fail:mdl-input-exhausted` with
  `READSTRING: input exhausted: the session input ended and the mirrored end-of-input read
  was already returned (maintainer decision D3; ADR-0050)`. Host-level, not an MDL ERROR:
  a live ERROR handler does not run (tested). RESET clears the flag.
- **Host loop** `mdl-session-run-interactive session entry #:max-passes #:on-event`
  (`mdl/loader.rkt`; core `mdl-run-host-loop`): requires explicit session ports; applies the
  entry, PRIN1+TERPRI of its value (D1), then re-reads and applies the GVAL of ROOT REP every
  pass; default REP stays the ADR-0049 error; ends only by an exception; flushes on exit.
  Local only: no network/web entry point, no MDL evaluator; input reaches MDL only through
  the game's own READSTRING.

## Red → green (sandboxed, `export PLTCOLLECTS=":$PWD"`; exit status of `raco test FILE`)

| Test | Red (before implementation) | Green |
|---|---|---|
| `tests/reset_test.rkt` | exit 1: `mdl-eval: unassigned or non-applicable MDL operator RESET` | exit 0, 22 tests |
| `tests/princ_test.rkt` | exit 1: unassigned operator PRINC | exit 0, 35 tests |
| `tests/readstring_test.rkt` | exit 1: `exn:fail:mdl-input-exhausted?: unbound identifier` | exit 0, 50 tests |
| `tests/prin1_test.rkt` | exit 1: unassigned operator PRIN1 | exit 0, 26 tests |
| `tests/host_loop_test.rkt` | exit 1: `mdl-session-run-interactive: unbound identifier` | exit 0, 48 tests |
| `tests/historical_saveit_test.rkt` | after RESET, the S6 XFAIL assertion failed (SAVE-IT returned an ATOM): exit 1 | updated: exit 0, 32 tests |
| `tests/historical_interactive_test.rkt` | (new; first run exposed a test bug: the `<DATE>` placeholder contained `>`) | exit 0, 30 tests, 8 consecutive runs |

## Mutation checks (each mutant applied alone, test run, file restored)

All exit 1 (killed) unless noted.

- RESET: return a different CHANNEL (3 failures); skip mode-slot check; accept 2+ args;
  skip the registration check (2); unregister RESET (raised); rewrite DEVN slot (2); drain a
  line of input (1). An equivalent mutant (a fresh typed wrapper of the same storage, `==?`
  in MDL terms) survives, as expected.
- PRINC: return FALSE (4); insert line breaks (1); no control-character check (5); CR not
  raw (raised); FIX unsupported (raised); GVAL instead of LVAL OUTCHAN (1); write before
  validating (7).
- READSTRING: store the stop character (14); no mirrored read (raised); never strict at end
  of input (6); no flush (1); MDL ERROR instead of host error (7); accept `!` (1); RESET keeps
  the flag (raised); overflow drops the line (4); clear the rest of the buffer (1); EOF check
  before argument validation (1).
- PRIN1: no empty-PNAME case (raised); no reachability check (1); return FALSE (2); STRING
  accepted (3); PRIN1 as PRINC (raised).
- Host loop: no D1 print (8); REP cached across passes (2); no flush on exit (1, after
  adding the "no later read" flush test; the first version of that test did not bite); no
  applicability check (1); input exhaustion swallowed as success (raised); port requirement
  removed (3). The first "no D1 print" run hung (an unbounded REP that returns), so the
  test's helper now bounds passes and the runner uses a timeout.
- Faithful path (`historical_interactive_test.rkt`): no D1 print (2), no mirrored read (3),
  host error as MDL ERROR (2, HANDLE ran) are killed. Storing the stop character and PRINC
  line breaking at 40 columns **survive** here (LEX ignores a stored LF; no PRINC string in
  this scenario exceeds 40), and are killed by the unit tests.
- RNG branches: forcing `<RANDOM>` to 99 (full "west" text) and to 0 (brief text): both pass.

## Faithful path: six-command run vs the approved golden

`make test-m3-interactive` (= `raco test tests/historical_interactive_test.rkt`): exit 0,
30 tests. Input: `north`, `west`, `open mailbox`, `take leaflet`, `inventory`, `score`
(`tests/scenarios/house-boot.json`), LF-terminated, no echo, unfixed host clock.

- **(a) INITIALIZED**: load PASS (1,229 forms, 0 skipped); SAVE-IT returns `,NULL`
  (`entry-returned` event, `eq?` GVAL NULL); pass 1 applies RDCOM; boot text up to the
  first `>` equals the golden boot text.
- **(b) INTERACTIVE**: all six command responses equal the golden (`west`: see below);
  MOVES = 6; the input port is fully consumed; one pass (RDCOM never returns).
- **(c) end of input**: the transcript ends `…rank of Beginner.\n>Beg pardon?\n>`, then
  `exn:fail:mdl-input-exhausted` with the exact message; no HANDLE/FINISH text.
- **Comparison** (D2): `canonical_text(ONLCR(raw))` vs the golden (`tests/fixtures/house-boot-golden.json`,
  an unchanged extract of `house-boot-candidate.json`, sha256 `eb194115…`, BOOT-REF branch
  e616ac0) after removing `LISTENING-AT-LEVEL 1 PROCESS 1` and `"DONE"` (D1) and normalising
  `This version created <Month> <day>.` in both texts.
- **Raw bytes** ([`S7-racket-vs-confusion.txt`](S7-racket-vs-confusion.txt)): 10 runs, each
  byte-identical (CR kept) to Confusion's `boot-six` pipe output from `81prim.mud loaded`
  onward after removing `"DONE"` and the date — 6 with the brief `west` text, 4 against the
  Confusion text with the full West of House description. One raw run:
  [`S7-racket-six-raw.txt`](S7-racket-six-raw.txt).

**Correction to the investigation.** It stated that no RNG-visible text appears in the
scenario. That is wrong: ROOM-INFO (77rooms.mud:521-525) prints a seen room's brief text
only if `<PROB 80>` holds, so the `west` response depends on RANDOM, which START seeds from
DSKDATE (the host clock). Observed locally over 21 runs of the faithful path: 15 brief,
6 full (the 10 runs in `S7-racket-vs-confusion.txt` plus 11 ad-hoc runs). Until a
fixed clock exists (#135) the test accepts exactly those two source-defined texts for
`west` and compares every other response exactly. SMOKE_PARITY is therefore **not** claimed.

## Deviations (recorded in ADR-0050 and SEMANTICS)

- RESET does not touch STATUS/DEVN slots (Confusion: STATUS 0, DEVN rewritten) and drops no
  lookahead (none exists).
- PRINC/PRIN1 never break lines (manual/Confusion do at the CHANNEL width; RDCOM sets 1000).
- Control characters other than CR/LF are refused (Confusion prints `^X`); `!` in input is
  refused (Confusion: reader escape; manual silent — open question).
- End of input: host-level strict error instead of Confusion's `Error: Unexpected EOF` and
  channel close, or the manual's MDL ERROR.
- The host prints the entry value (D1) but never the LISTEN banner or FLOAD's `"DONE"`.
- READSTRING's default channel, FIX stop and EOF routine are not modelled.

## Full suite and gate record (sandboxed; `export PLTCOLLECTS=":$PWD"`)

| Command | Exit | Result |
|---|---|---|
| `make test-racket` (first run) | 2 | 4/3137 failures: `oblist_identity_test.rkt:294` used PRINC as its example of an unimplemented ROOT SUBR (now PRINC is implemented; changed to PRINT) + the 3 known sandbox `/tmp` failures |
| `make test-racket` (after the fix) | 2 | 3/3137 failures, all `Read-only file system` on hard-coded `/tmp` (`loader_test`, `declaration_test`, `percent_read_test`), as before this slice |
| `PYTHONPATH=$PWD/.sandbox-pydeps/lib make test-python PYTHON=/usr/bin/python3` | 0 | 23 passed |
| `raco test tests/historical_interactive_test.rkt` (= `make test-m3-interactive` without `sources`) | 0 | 30 tests; 8 further consecutive runs exit 0 |
| `raco test tests/historical_saveit_test.rkt` | 0 | 32 tests |
| `raco test tests/historical_start_back_test.rkt` | 0 | 6 tests |
| `racket tests/historical_oblist_placement_test.rkt`, `historical_channel_start_test.rkt` | 0 | pass |
| `racket tests/historical_{vfload,decl,computed_global,error,memq,g3,andq}_test.rkt`, `raco test tests/historical_gc_handler_test.rkt` | 1 | `Read-only file system` on `/tmp` only (sandbox) |

**Needs the maintainer's unsandboxed run** (they write to `/tmp` or fetch sources):
`TMPDIR=/tmp make test`, `make test-historical`, `make test-m2-g3`, `make test-m3-andq`,
`make test-m3-historical-gc`, `make test-m3-start-back`, `make test-m3-saveit`,
`make test-m3-interactive`, `make m3-source-progress`. `make reference-build` was not run.

**Gate labels (this slice):** INITIALIZED **PASS (scoped)**, INTERACTIVE **PASS (scoped)**,
both on the faithful path by `historical_interactive_test.rkt`; SMOKE_PARITY **NOT CLAIMED**
(#135); PLAYABLE **NOT RUN**. Full-suite gate: **PASS in the sandbox except the known `/tmp`
targets; unsandboxed run NOT RUN by the implementer.**

## Security and licensing

The host loop is a local Racket API with explicit ports; it exposes no evaluator, opens no
file or socket, and refuses to run on a session without explicit ports, so it never reads
the process's own stdin. Isolation per session is unchanged (channels keyed per atom space;
foreign CHANNELs refused). No GPLv3 Confusion code was copied; Confusion sources were read
as behaviour references only. No file is written next to the game source (asserted).

## Risks and open questions

- `!` in terminal input (strict now): mirror Confusion's escape, or keep refusing?
- UNWIND cleanups still run on host exceptions (#139); not on the tested path (RDCOM is not
  inside an UNWIND), but `quit`/death paths are.
- QUIT, OPEN/CLOSE (D5), MEMBER (needed by HANDLE) remain unimplemented: `quit`, an MDL
  ERROR during play, and RECORD fail strictly.
- `scripts/m3_source_progress.py` still hard-codes INITIALIZED/INTERACTIVE false: it only
  loads the source and does not run SAVE-IT; this slice's gate evidence is the historical test.

## Independent review (APPROVE WITH NITS) and follow-ups

The scoped INITIALIZED and INTERACTIVE claims held up under review:
- **Real path:** the full faithful path runs with the six house-boot commands.
- **Gates asserted, not inferred:** the entry-returned and pass-1 events,
  the golden boot text, MOVES=6, and the input fully consumed.
- **"west" exception:** limited to `<OR ,BRIEF!-FLAG <PROB 80>>`
  (77rooms.mud:523) and to that one response.
- **Golden fixture:** a faithful extract of the approved candidate
  (sha256 eb194115…).

Follow-ups:

1. **Medium (fixed for input):** READSTRING fell back to the process's
   stdin when the session had no host input port. It now raises a strict
   error (ADR-0050 "Host input port only").
   - A new `readstring_test` check: a parameterized stdin holding `SECRET`
     is left unread. Restoring the fallback fails 2/55.
   - Making output strict as well was tried and reverted. It broke
     pre-existing tests (PRINTSTRING, CRLF, VFLOAD, G3, start-back) that
     capture output through the host's `current-output-port` parameter.
     That is a runtime-wide contract older than S7, and the leak finding
     was about input, so output strictness is left for a separate decision.
   - `historical_saveit_test` now passes an explicit output port anyway.
2. **Low (fixed):** `historical_interactive_test` runs the game loop in a
   thread with a 300 s limit, and a timeout is a failure (`timed-out`).
   Checked by setting the limit to 1 ms. Before this, a mutant that stopped
   consuming input hung the test.
3. **Low (recorded):** a PRINC mutant that drops CR passes the historical
   test, because the six commands send no CR through PRINC. `princ_test`
   catches it (1 failure). It joins the two mutants above that only unit
   tests catch.
4. **Nit (fixed):** READSTRING now has its own test refusing a CHANNEL from
   another session. Before, only RESET's shared check was tested.

## Next action

Fixed clock (#135) so `west` and the date line are deterministic, then a strict SMOKE_PARITY
comparison against the approved golden.
