# S6-REP — inert REP SUBR; host top-level loop specified

**RID**: S6-REP (local task record; no GitHub issue/PR was opened for this slice)
**Branch**: feat/m3-startup-rep
**Base commit**: e42f8bc8da673edb671dd9888478a8121c3fd9bb (PR #137, S5 review nits)
**Reference binary SHA256**: 6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789
**Upstream SHAs (sources.lock.json)**: mdlzork bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3; MITDDC/zork d94501340842e006791fce0757dc0043b8ec8916
**Toolchain**: Racket v7.9 [bc], /usr/bin/python3 (3.9.2)
**Decision**: [ADR-0049](../../DECISIONS.md) (maintainer, 2026-11-23, "Inert REP + host loop")

## Scope

1. The GVAL of ROOT `REP` is a predefined SUBR value in every session:
   GASSIGNED, `<TYPE ,REP>` = SUBR, APPLICABLE, `<SETG SAVEREP ,REP>` keeps the
   same object (`==?`). Represented by a new `mdl-subr` struct (a Racket
   procedure via `prop:procedure`) used only for REP; `mdl-type-name` maps it to
   SUBR. Other built-ins are unchanged.
2. Applying the default REP by any path (FORM call, APPLY, MAPF, HANDLER
   delivery, host `mdl-apply`/`mdl-session-call`) evaluates the arguments and
   then raises `REP: the default REP SUBR is inert; this runtime never provides
   a raw MDL read-eval-print loop (maintainer decision 2026-11-23; ADR-0049)`.
   It reads no input and prints nothing.
3. The host top-level loop is **specified only** (SEMANTICS "M3 startup: inert
   REP and the host top-level loop"): it starts after the entry form returns,
   re-reads GVAL REP on each pass and applies it with no arguments, never applies
   the default REP (strict error), ends when the program QUITs, fails strictly on
   exhausted input or any error, and is local-only. It is not implemented: it
   cannot run before RESET, PRINC and READSTRING exist.

## Reference probe (pinned Confusion)

Cases `S6-rep-cases.json`, results `S6-rep-reference.json` (13 cases, all `ok`,
`complete: true`; one local process per case, stdin then `<QUIT>`; no case writes
a file). Command: `PYTHONPATH=$PWD/.sandbox-pydeps/lib /usr/bin/python3 -m
scripts.mdl_probe --cases docs/evidence/M3/S6-rep-cases.json --output
docs/evidence/M3/S6-rep-reference.json` → exit 0.

| case | Confusion result |
|---|---|
| `<TYPE ,REP>` | `SUBR` |
| `<GASSIGNED? REP>` | `T` |
| `<==? <OBLIST? REP> <ROOT>>` | `T` |
| `<GASSIGNED? SAVEREP>` (fresh) | `#FALSE ()` |
| `<SETG SAVEREP ,REP>` `<TYPE ,SAVEREP>` | `#SUBR *0000000000000000000227*`, `SUBR` |
| `<SETG SAVEREP ,REP>` `<==? ,REP ,SAVEREP>` | `T` |
| `<TYPE? ,REP SUBR FSUBR>` (BLO, 77act1.mud:3) | `SUBR` |
| `<PRIMTYPE ,REP>` / `<TYPEPRIM SUBR>` | `WORD` / `WORD` |
| `<TYPE ,TYPE>` | `SUBR` |
| `<REP>` then `<+ 1 2>` | `3` (printed by REP), `3` (REP's value printed by LISTEN) |
| `<APPLY ,REP>` then `<+ 3 4>` | `7`, `7` |
| `<SETG REP ,F>` (F prints and QUITs) then `<+ 5 6>` | LISTEN applies F on the very next pass; `<+ 5 6>` is never read |

An earlier draft case (`<SETG REP ,F>` with F returning 1) timed out after 20 s:
LISTEN applied F forever. It was replaced by the QUIT case above, recorded in
the committed JSON. The ROOT placement matches `root-names.rktd`.

## Source paths that restore SAVEREP

`grep -nw` over the pinned game `.mud` files (read-only): `SAVEREP` appears only
at 77rooms.mud:301 (`<SETG SAVEREP ,REP>`, CONTIN) and 77rooms.mud:222
(`<AND <GASSIGNED? SAVEREP> <SETG REP ,SAVEREP>>`, in the ERROR handler HANDLE,
taken only when XUNM is unassigned or in WINNERS). On that path the host loop
would next meet the default REP and fail loudly (ADR-0049). `,REP` is also read
by BLO (77act1.mud:3), which acts only while REP is a SUBR/FSUBR; BLOCKED never
fires (ADR-0048).

## Red → green (sandboxed, `PLTCOLLECTS=":$PWD"`)

| step | command | exit | result |
|---|---|---|---|
| red, base `e42f8bc` + new tests | `raco test tests/rep_test.rkt` | 1 | FAILURE at `rep_test.rkt:38` (`<GASSIGNED? REP>` is FALSE), then `mdl-gval: unassigned MDL global REP` |
| red, base + advanced historical test | `make test-m3-saveit` | 2 | 1/21 failures: actual `mdl-gval: unassigned MDL global REP`, expected the RESET message; then `unassigned MDL global SAVEREP` |
| green | `raco test tests/rep_test.rkt` | 0 | 53 tests passed |
| green | `make test-m3-saveit` | 0 | 31 tests passed |

## Mutation checks (each mutant applied to a copy of `mdl/` and `tests/`; `raco test` exit status, stdin `/dev/null`)

| mutant in `core.rkt` | rep_test | historical_saveit_test |
|---|---|---|
| M1 REP absent from the builtin table | exit 1 (exception) | exit 1 (1/21, exception) |
| M2 REP applicable, returns FIX 0 | exit 1 (14/53) | exit 1 (1/31) |
| M3 REP typed FSUBR | exit 1 (13/53) | exit 1 (1/31) |
| M4 REP a plain host procedure (no SUBR TYPE) | exit 1 (exception) | exit 1 (exception) |
| M5 REP typed FUNCTION | exit 1 (14/53) | exit 1 (1/31) |
| M6 a fresh REP object on every GVAL read (breaks `==?`) | exit 1 (4/53) | exit 0 |
| M7 REP raises a generic "unsupported" message | exit 1 (14/53) | exit 1 (1/31) |
| M8 REP reads and echoes one input line (REPL-like) | exit 1 (16/53) | exit 1 (1/31) |
| M9 TYPE built with an `(mdl-atom "SUBR")` literal | exit 1 (1/53, the static check) | exit 0 |

`rep_test` kills all 9 mutants (9/9), and the historical test kills 7/9. M9 does
not change behavior, because the literal resolves to the same ROOT atom; only
the static check over `core.rkt`, `loader.rkt` and `compiler.rkt` catches it, and
that check is what it is there for. The first attempt at this run hung on M8:
the mutant read the inherited stdin. That attempt was stopped and rerun with
stdin `/dev/null` and a per-test timeout.

## New frontier (faithful `run.mud` path: `<FLOAD "77loadall.mud">`, `<SAVE-IT>`)

Unchanged through START (SAVE record 1 `"<MDL>MADADV.SAVE"` at INT-LEVEL 100000,
`<INT-LEVEL 0>`, GETSYS, ON "BLOCKED", welcome text). CONTIN then runs
296-302: ALT-FLAG FALSE, the PUT on `<1 <BACK ,INCHAN>>`, **`<SETG SAVEREP ,REP>`
(SAVEREP is the REP SUBR) and `<SETG REP ,RDCOM>` (GVAL REP `==` GVAL RDCOM)**.

**XFAIL at 77rooms.mud:303 `<RESET ,INCHAN>`: `mdl-eval: unassigned or
non-applicable MDL operator RESET`.** Location check (scratch host trace, not
committed, no source edited): a temporary host procedure SETG'd as RESET in a
scratch session recorded its first call as one argument `==` GVAL INCHAN, with
GVAL REP already `==` RDCOM and SAVEREP of TYPE SUBR. Of the three RESET sites
(77defs.mud:433 YES/NO, 77rooms.mud:303 CONTIN, 77rooms.mud:888 JIGS-UP), only
CONTIN runs after 302, so the first failure is 77rooms.mud:303.

`make test-m3-saveit` asserts the exact message, that SAVEREP has TYPE SUBR and
applying it raises the ADR-0049 error, that REP `==` RDCOM, and that RESET is
still unassigned, together with all S5 assertions.

> Later update (M4 S5b, ADR-0060): the TYPE limits recorded below are
> resolved. A compiled DEFINE such as RDCOM is TYPE FUNCTION, and every
> builtin-table SUBR (for example `<TYPE ,TYPE>`) is TYPE SUBR, so BLO's
> `<TYPE? ,REP SUBR FSUBR>` is FALSE after CONTIN, as in the reference. See
> `docs/evidence/M4/S5B-FUNCTION-TYPE.md`. The text below records the M3 state.

Observed limit: RDCOM is a compiled DEFINE, which is a host procedure, and
`<TYPE ,RDCOM>` (so `<TYPE ,REP>` after CONTIN) is still `mdl-type: unsupported
MDL type #<procedure>`. This was already the case before this slice, and the
historical test asserts it as a known limit. It matters for BLO's
`<TYPE? ,REP SUBR FSUBR>` once REP is RDCOM, but BLO cannot run because
BLOCKED never fires.

**INITIALIZED remains FAIL.** INTERACTIVE, SMOKE_PARITY and PLAYABLE: NOT RUN.

## Commands (sandboxed; `PLTCOLLECTS=":$PWD" PYTHONPATH=$PWD/.sandbox-pydeps/lib PYTHON=/usr/bin/python3`)

| command | exit | result |
|---|---|---|
| `make test` | 2 | test-racket: 3/2951 failures. The only failing files are `loader_test`, `declaration_test` and `percent_read_test`, where `make-directory` under hardcoded `/tmp` fails with `Read-only file system` (a known sandbox limit). `rep_test` passed. test-python did not run because make stopped. |
| `make test-python` | 0 | 23 passed |
| `raco test tests/rep_test.rkt` | 0 | 53 tests passed |
| `raco test tests/on_save_test.rkt` | 0 | 146 tests passed |
| `make test-m3-saveit` | 0 | 31 tests passed |
| `make test-m3-start-back` | 0 | 6 tests passed (direct START still stops at TENEX?, unchanged) |
| `make test-m3-andq` | 2 | `make-directory: cannot make directory` (read-only `/tmp`) |
| `git diff --check` | 0 | |

**These need an unsandboxed run by the maintainer:** `make test` (full gate),
`make test-historical`, `make test-m3-historical-gc`, `make m3-source-progress`,
`make test-m3-andq`. No sandboxed result above is a full-gate PASS. Gate status
for this slice: **NOT RUN** (full gate) until then.

## Deviations (recorded)

- Confusion's `<REP>`/`<APPLY ,REP>` perform a real read-eval-print step; ours
  is a strict error (decision).
- `<PRIMTYPE ,REP>` and `<TYPEPRIM SUBR>` are WORD in Confusion; here they are
  strict errors (`unknown MDL TYPE SUBR`), as are CHTYPE of REP, DECL patterns
  naming SUBR and UNPARSE of REP. Confusion prints `#SUBR *…227*`.
- Built-in SUBRs other than REP still have no TYPE (`<TYPE ,TYPE>` is SUBR in
  Confusion and an unsupported-type error here, as before this slice).
- No LISTEN loop exists, so there is no top-level behavior after the entry form.

## Security and licensing

- No evaluator, REPL, channel or file access is added. The only new behavior
  is a value whose application always fails. The host loop is specified as
  local-only and as never applying the default REP.
- No GPLv3 code was copied. Confusion is used only as a black-box reference.

## Risks / next

- Next slice: RESET of INCHAN (77rooms.mud:303), then the host loop, PRINC and
  READSTRING. The loop needs a QUIT/termination model and an exhausted-input
  error before it can be tested.
- TYPE of compiled DEFINE values (and other built-in SUBRs) is unsupported. Any
  later `TYPE?` on REP or on built-ins will fail strictly until that is fixed.
- The default REP value is one module-level object that all sessions share.
  It is immutable, and associations on it are owned by each session.

## Unsandboxed full gate (orchestrator, 2026-11-23)

Run outside the sandbox as the normal user, with `PLTCOLLECTS=":$PWD" TMPDIR=/tmp
PYTHON=/usr/bin/python3 PYTHONPATH=$PWD/.sandbox-pydeps/lib`, at `1f3e66c` and again
with the review follow-ups below:

| command | exit |
|---|---|
| `make test` | 0 |
| `make test-historical` | 0 (placement matches pinned Confusion, 2350 entries) |
| `make m3-source-progress` | 0 |
| `make test-m3-historical-gc` | 0 |
| `make test-m3-start-back` | 0 |
| `make test-m3-saveit` | 0 (31 tests passed) |
| `make test-m3-andq` | 0 |
| `git diff --check` | 0 |

No log contained `test failures`, `FAILURE` or `raised an exception`.

**Full gate: PASS.** This is not an INITIALIZED claim: startup stops at 77rooms.mud:303.

## Independent review (APPROVE WITH NITS) and follow-ups

The reviewer exercised every apply route and all raised the ADR-0049 error:
- `<REP>`, `<,REP>` and a local alias;
- APPLY, including nested;
- MAPF and MAPR;
- HANDLER delivery;
- a direct host call.

The reviewer also confirmed that associations on the shared REP object stay
per-session. Follow-ups:

- `mdl-subr` sets `prop:object-name`, so Racket diagnostics print
  `#<procedure:REP>` instead of a source location.
- `rep_test` now covers MAPR, a direct host call (also checking
  `object-name` is `REP`), and cross-session association isolation (PUT in
  one session, GET in another is FALSE). The file now has 58 tests.
- Not changed: after CONTIN, BLO's `<TYPE? ,REP SUBR FSUBR>` would raise an
  error, because RDCOM is a host procedure without an MDL TYPE. This is
  harmless while BLOCKED never fires (ADR-0048). It is recorded under Risks.
