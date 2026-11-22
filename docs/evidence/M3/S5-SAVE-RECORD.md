# S5-SAVE-RECORD — SAVE as a session record; BLOCKED registers without a source

**RID**: S5-SAVE-RECORD (local task record; no GitHub issue/PR was opened for this slice)
**Branch**: feat/m3-startup-save-record
**Base commit**: aef40a0b0b70cb51651cbba15454a235187f81d4 (PR #136, S4-ON-SAVE umbrella)
**Reference binary SHA256**: 6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789
**Upstream SHAs (sources.lock.json)**: mdlzork bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3; MITDDC/zork d94501340842e006791fce0757dc0043b8ec8916
**Toolchain**: Racket v7.9 [bc], /usr/bin/python3 (3.9)
**Decision**: [ADR-0048](../../DECISIONS.md) (maintainer, 2026-11-23; supersedes ADR-0047 part 2)

## Scope

1. `<SAVE file-spec>` returns a fresh STRING `"SAVED"`, writes no file, performs no
   GC and has no interrupt side effect, and appends a session record
   (sequence, file-spec snapshot, INT-LEVEL). Host accessors: `mdl-save-records`
   (core) and `mdl-session-save-records` (loader). No new MDL primitive.
2. Strict arguments: one STRING file-spec, optional FALSE `gc?` (manual 11.6.1:
   a FALSE `gc?` "causes no garbage collection to occur before SAVEing", which is
   exactly what this SAVE does). `<SAVE>`, a non-STRING spec, a non-FALSE `gc?`
   (including the manual's multi-name form) and more than two arguments are strict
   errors, raised before anything is recorded.
3. RESTORE stays refused: `RESTORE: restoring a saved image is not supported
   (maintainer decision 2026-11-23; ADR-0048)`.
4. `"BLOCKED"` moves from `unsupported-predefined-interrupt-names` to the sourceless
   names: ON/EVENT/HANDLER/OFF work; emit/deliver raises
   `BLOCKED: this session has no blocked-input source; BLOCKED occurrences cannot be
   emitted (maintainer decision 2026-11-23; ADR-0048)`. The IPC message is unchanged.

Reference evidence: [S5-SAVE-FRONTIER.md](S5-SAVE-FRONTIER.md) with
`s5-save-frontier-{primitives,boot}-{cases,reference}.json` (pinned Confusion
`6df359f6…`, upstream `bdcd4a67`), copied from the read-only investigation of
2026-11-22. Its scripts are `s5_sf_probe.py` and `s5_make_boot_cases.py`, with paths
now derived from the repository root. Regenerating the boot cases reproduces the
copied JSON byte for byte (`cmp` exit 0).

## Changes

- `mdl/runtime/core.rkt`: `mdl-save` (record + fresh `"SAVED"`), `mdl-restore`
  message, `mdl-save-record` struct and `mdl-save-records`, the atom-space
  `save-records` field, and the sourceless-interrupt table (IPC, BLOCKED) with a
  message for each name.
- `mdl/loader.rkt`: `mdl-session-save-records`.
- `tests/on_save_test.rkt`: BLOCKED and SAVE/RESTORE sections rewritten.
- `tests/historical_saveit_test.rkt`: the new frontier.
- Docs: ADR-0048 (with ADR-0047 marked as superseded in part), SEMANTICS
  "M3 startup: ON (IPC) and SAVE", STATUS and README.

## Red → green (sandboxed, `PLTCOLLECTS=":$PWD"`)

| step | command | exit | result |
|---|---|---|---|
| red, base `aef40a0` with the new tests | `raco test tests/on_save_test.rkt` | 1 | `mdl-save-record-sequence: unbound identifier` |
| red, base `aef40a0` with the new tests | `raco test tests/historical_saveit_test.rkt` | 1 | `mdl-session-save-records: unbound identifier` |
| red, accessor added, SAVE/BLOCKED unchanged | `raco test tests/on_save_test.rkt` | 1 | `mdl-on: unsupported predefined EVENT BLOCKED`, 59 checks passed before the abort |
| red, BLOCKED done, SAVE still refused | `raco test tests/on_save_test.rkt` | 1 | `SAVE: saving a restorable image is not supported (… issue #112)`, 78 checks passed before the abort |
| green | `raco test tests/on_save_test.rkt` | 0 | 146 tests passed |
| green | `make test-m3-saveit` | 0 | 27 tests passed |

## Mutation checks (each mutant applied to a copy of the tree; `raco test` exit status)

| mutant in `core.rkt` | on_save_test | historical_saveit_test |
|---|---|---|
| M1 SAVE returns one shared `"SAVED"` string | exit 1 (8/146 failures) | exit 0 |
| M2 SAVE writes a file (`S5MUT.SAVE`) | exit 1 (2/146) | exit 0 |
| M3 BLOCKED emission allowed | exit 1 (6/146) | exit 0 |
| M4 BLOCKED still refused | exit 1 (exception) | exit 1 (2/16) |
| M5 record keeps the argument, not a snapshot | exit 1 (2/146) | exit 0 |
| M6 SAVE runs `GC` | exit 1 (2/146) | exit 0 |
| M7 SAVE lowers INT-LEVEL to 0 | exit 1 (2/146) | exit 0 |
| M8 non-FALSE `gc?` accepted | exit 1 (6/146) | exit 0 |
| M9 non-STRING file-spec accepted | exit 1 (12/146) | exit 0 |
| M10 record INT-LEVEL always 0 | exit 1 (2/146) | exit 1 (1/27) |
| M11 RESTORE returns `"RESTORED"` | exit 1 (5/146) | exit 0 |
| M12 SAVE refused again (S4 behavior) | exit 1 (exception) | exit 1 (2/8) |

All 12 mutants are killed by `on_save_test` (12/12); the historical test kills 3/12
(M4, M10, M12). The file-write check uses a security guard that records every
write/delete access, so it does not depend on a directory listing.

## New frontier (faithful `run.mud` path: `<FLOAD "77loadall.mud">`, `<SAVE-IT>`)

Host trace (scratch probe that wraps the GVALs of SAVE and INT-LEVEL with Racket
closures; it was not committed, and no source was edited):

```
before: INT-LEVEL=0 DIVERT-CNT=0 DIVERT-AMT=0
trace: (INT-LEVEL (100000) => 0 ...)                                   ; 77rooms.mud:25
trace: (SAVE ("<MDL>MADADV.SAVE") "SAVED" il 100000 divert-cnt 0
        stats #hash((capacity . 262144) (free . 130518) (used . 131626)))  ; :26
trace: (INT-LEVEL (0) => 100000 (divert-cnt 0 ...) after (divert-cnt 0 ...)) ; :26
trace: (INT-LEVEL (0) => 0 ...)                                        ; START :292
result: "mdl-gval: unassigned MDL global REP"
output: "Welcome to Dungeon.\r\nThis version created November 23.\n"
record: #(struct:mdl-save-record 1 "<MDL>MADADV.SAVE" 100000)
```

- SAVE was called once with `"<MDL>MADADV.SAVE"` at INT-LEVEL 100000 and returned
  `"SAVED"`. SAVE-IT took its single COND clause, and `<INT-LEVEL 0>` at
  77rooms.mud:26 executed (it returned the old level, 100000).
- **GC/DIVERT-AGC at `<INT-LEVEL 0>`:** nothing was delivered. DIVERT-CNT and
  DIVERT-AMT stayed 0 across both `INT-LEVEL 0` calls. Logical storage at SAVE
  was 131,626 of 262,144 words used, so no DIVERT-AGC (emitted only under
  allocation pressure) and no automatic collection could have been queued while
  the level was 100000. Delivery was not suppressed; it simply did not occur on
  this path.
- STARTER, then GETSYS (77rooms.mud:56; TENEX? = FALSE), then `ON "BLOCKED" ,BLO 100`
  (59; registers), then START (60). START's XUNAME (`"MTRZORK"`), GET-NAME (`""`),
  TELL welcome text, RANDOM and `INT-LEVEL 0` (292) ran, and then CONTIN ran.
- CONTIN: `SETG ALT-FLAG <>` (296) and the PUT on `<1 <BACK ,INCHAN>>` (297-300)
  ran. **XFAIL at 77rooms.mud:301 `<SETG SAVEREP ,REP>`: `mdl-gval: unassigned MDL
  global REP`.** In Confusion, REP is a SUBR used by the LISTEN loop. CONTIN then sets
  `REP` to `,RDCOM`, and LISTEN applies it (S5-SAVE-FRONTIER.md Q3 steps 11-12).
- Expected next blockers after REP (from the reference trace): RESET of INCHAN,
  a LISTEN/REP top-level loop that re-reads GVAL REP, PRINC, READSTRING. None of
  these was implemented here, and no game-specific bypass was added.
- `make test-m3-saveit` asserts the exact message, the single record
  (1, `"<MDL>MADADV.SAVE"`, 100000), INT-LEVEL 0, DIVERT-CNT/AMT 0, TENEX? FALSE,
  the welcome output (with a regexp, because the date depends on the clock),
  DEATHS/MOVES 0, XUNM `"MTRZORK"`, USER-NAME `""`, ALT-FLAG FALSE, SAVEREP
  unassigned, and an unchanged source directory.

**INITIALIZED remains FAIL.** INTERACTIVE, SMOKE_PARITY and PLAYABLE: NOT RUN.

## Commands (sandboxed; `PLTCOLLECTS=":$PWD" PYTHONPATH=$PWD/.sandbox-pydeps/lib PYTHON=/usr/bin/python3`)

| command | exit | result |
|---|---|---|
| `make test` | 2 | test-racket: 3/2894 failures. The only failing files are `loader_test`, `declaration_test` and `percent_read_test`: `make-directory` under hardcoded `/tmp` fails with `Read-only file system`, a known sandbox limit. test-python did not run because make stopped. |
| `make test-python` | 0 | 23 passed |
| `make test-m3-saveit` | 0 | 27 tests passed |
| `make test-m3-start-back` | 0 | 6 tests passed (direct START still stops at TENEX?, unchanged) |
| `make test-historical` | 2 | `historical_vfload_test` hits read-only `/tmp`. Run one by one: `historical_oblist_placement_test` exit 0, `historical_channel_start_test` exit 0. vfload, decl, computed_global, error and memq exit 1, all on read-only `/tmp`. |
| `make test-m3-historical-gc` | 2 | read-only `/tmp` |
| `make m3-source-progress` | 2 | reader sweep: 36 parsed, 0 failed. Then read-only `/tmp` in the G3 test. |

**These need an unsandboxed run by the maintainer:** `make test` (full gate),
`make test-historical`, `make test-m3-historical-gc`, `make m3-source-progress`.
No sandboxed result above should be read as a full-gate PASS.

## Deviations (recorded)

- SAVE writes no image. Confusion writes one, and returns `#FALSE ()` when it cannot
  open the file. `<SAVE>` (Confusion writes `MUDDLE.SAVE`) is a strict error.
  `<SAVE 1>` (Confusion: SIGSEGV) is a strict error. The manual's GC on SAVE is not
  performed, and the multi-name form is refused.
- RESTORE is not modeled. Confusion re-enters LISTEN and applies `,REP`, so SAVE
  never returns again. The manual makes SAVE return `"RESTORED"`. This disagreement
  is open for any future RESTORE slice.
- `ON "BLOCKED"` returns a real HANDLER; Confusion's stub returns `T`.

## Security and licensing

- No file I/O, channel or evaluator access is added. Save records can be read only
  from Racket.
- No GPLv3 code was copied. Confusion line numbers in the frontier memo are
  citations only.

## Risks / next

- REP: Confusion's GVAL REP is a SUBR, and LISTEN applies the current GVAL of REP on
  every pass. A faithful next slice needs a maintainer decision on the REP SUBR and
  the top-level loop, then RESET, PRINC and READSTRING. Goldens need a fixed clock
  (DSKDATE affects the welcome text and the RANDOM seed).
- ADR-0048 assumes that no parallel branch has claimed that number.
