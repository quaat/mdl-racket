# S4-ON-SAVE — ON (IPC registration) and strict SAVE

**RID**: S4-ON-SAVE  
**Branch**: feat/m3-startup-on-save  
**Base commit**: ea19d68d7d6d01a52debfecfae0ff87e7d15edbf (origin/feat/m3-startup-substruc, PR #130)  
**Reference binary SHA256**: 6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789  
**Upstream SHAs (sources.lock.json)**: mdlzork bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3; MITDDC/zork d94501340842e006791fce0757dc0043b8ec8916  
**Toolchain**: Racket v7.9 [bc], /usr/bin/python3

## Scope and maintainer decisions (2026-11-22, issue #112)

Before this slice, `<FLOAD "77loadall.mud">` loads all 1,229 forms, but `<SAVE-IT>`
stops at `<SET IH <ON "IPC" ,ILO 1>>` (77rooms.mud:16) with
`unassigned or non-applicable MDL operator ON`.

1. **ON "IPC": register, never fires.** ON = EVENT + HANDLER (manual ch.21.6) and
   returns the new HANDLER, which goes to the front of the action list. OFF removes it.
   "IPC" registration is allowed. The session has no inter-process message source,
   so emitting or delivering an IPC occurrence is a strict error. All other refused
   predefined names stay refused.
2. **SAVE: strict unsupported.** It raises an explicit error that names the decision,
   never returns "SAVED", and writes no file. RESTORE is refused the same way.

## Contract (manual ch.21, fetched 2026-11-22)

- `<ON name applicable priority:fix process which>` ≡
  `<HANDLER <EVENT name priority which> applicable process>`. It "creates (or finds)
  the IHEADER, associates and enables it", adds a HANDLER to the front of the list,
  and returns that HANDLER.
- `<OFF handler>` returns *handler* after removing it from its list of actions.
  `<HANDLER iheader handler>` re-adds it.
- "IPC" (21.8.12) occurs when a message arrives on the ITS IPC device.

Runtime rules (`mdl-on`, mdl/runtime/core.rkt):
- ON takes exactly 3 arguments. With 4 or 5 it fails with "ON process and which
  arguments are unsupported in this slice". Any other count fails with
  "ON expects name, applicable and priority".
- The name must be a STRING. The applicable must be a FUNCTION or SUBR, the same set
  HANDLER accepts; a HANDLER object is rejected. The priority must be a positive FIX.
  The name must not be one of the still-refused predefined events.
- All arguments are validated **before** anything is registered. A rejected ON leaves
  no IHEADER behind (tested).
- ON then runs `EVENT name priority`, `ENABLE`s the result (manual: "associates and
  enables"), and calls `HANDLER`. EVENT ignores the priority when an IHEADER already
  exists for the name.
- `"IPC"` is removed from `unsupported-predefined-interrupt-names` and added to
  `sourceless-predefined-interrupt-names`. `mdl-emit-event!` and
  `mdl-deliver-occurrence!` both reject it with
  `IPC: this session has no inter-process message source; IPC occurrences cannot be emitted (maintainer decision 2026-11-22; issue #112)`.
  EVENT "IPC" is allowed too, so that ON stays equivalent to HANDLER+EVENT.
- `SAVE` and `RESTORE` are builtin SUBRs (both are in the historical ROOT inventory).
  After normal argument evaluation they raise
  `SAVE: saving a restorable image is not supported (maintainer decision 2026-11-22; issue #112)`
  or `RESTORE: restoring a saved image is not supported (…)`.

## Confusion probe (`on-save-cases.json` → `on-save-reference.json`)

Each case ran in a fresh, empty `$TMPDIR` directory, never `.cache/upstream`
(scratch driver: `scripts.mdl_probe.probe_case` with that cwd). `files_after` lists
the directory after the process exited.

| case | Confusion |
|---|---|
| `<TYPE <ON "IPC" ,TYPE 1>>` | `ATOM` |
| `<ON "IPC" ,TYPE 1>` | `T` |
| `<OFF <ON "M3-USER" ,TYPE 7>>` | `T` |
| invalid action `<ON "IPC" 1 1>`, name `<ON 1 ,TYPE 1>`, priority 0 / "X", 2 args, 7 args | `T` (no error) |
| `<TYPE <EVENT "IPC" 1>>`, `<TYPE <HANDLER <EVENT "IPC" 1> ,TYPE>>`, `<TYPE <ON "BLOCKED" ,TYPE 100>>` | `ATOM` |
| `<SAVE "S4PROBE.SAVE">` | `"SAVED"`, writes `S4PROBE.SAVE` |
| `<SAVE>` | `"SAVED"`, writes `MUDDLE.SAVE` |
| `<SAVE 1>` | exit −11 (SIGSEGV) |
| `<RESTORE "S4-MISSING.SAVE">` | `#FALSE ()` |

**Deviations (recorded):** Confusion stubs ON, EVENT and HANDLER: they return `T` with
TYPE ATOM and validate nothing. The runtime follows the manual instead: it returns a
real HANDLER and validates strictly. Confusion's SAVE writes an image and returns
"SAVED". The runtime refuses it by maintainer decision.

## Red → green

- Red, on base `ea19d68` with the new test: `raco test tests/on_save_test.rkt` exits 1 with
  `mdl-eval: unassigned or non-applicable MDL operator ON` (at the first case).
  SAVE was unassigned too, so the anchored SAVE assertions could not match.
- Green: `raco test tests/on_save_test.rkt` reports **79 tests passed**, exit 0.
- `tests/historical_saveit_test.rkt` (XFAIL tracker) now asserts the exact anchored SAVE
  message, empty output, `INT-LEVEL` = 100000, DEV "DSK", SNM "MDL", RAW-SCORE 0,
  32-char SCRATCH-STR, and an unchanged source directory listing: **12 tests passed**.

## Commands (outside the sandbox; `PLTCOLLECTS=":$PWD" PYTHONPATH=$PWD/.sandbox-pydeps/lib`)

| command | exit | result |
|---|---|---|
| `make test PYTHON=/usr/bin/python3` | 0 | Racket 2936 tests passed; pytest 23 passed |
| `make test-m3-saveit` | 0 | 12 tests passed |
| `make test-m3-start-back` | 0 | 6 tests passed |
| `make test-historical` | 0 | all historical scripts passed (START outcome unchanged: unassigned TENEX?) |
| `make m3-source-progress` | 0 | LOADED: 1229 completed, 0 skipped |

`PLTCOLLECTS` is needed: without it, `make test` exits 2 with 6/2926 failures, all of them
`collection not found: mdl/lang/reader`. The host's linked `mdl` collection points at the
main checkout, not this worktree.

## New frontier (faithful `run.mud` path)

`SAVE-IT` → `<SAVE .FN>` at **77rooms.mud:26**, FN = `"<MDL>MADADV.SAVE"`:
`SAVE: saving a restorable image is not supported (maintainer decision 2026-11-22; issue #112)`.
These steps run before it: ON IPC (16), HANDLER DIVERT (17), ISTRING/DEV/SNM (19-21),
INT-LEVEL 100000 (25). INITIALIZED is **BLOCKED** at SAVE by maintainer decision. The level
stays at 100000 after the error, because the host has no MDL error loop that would reset it.

## Supported / unsupported

- Supported: ON with a user STRING event or "IPC"; OFF/HANDLER reattach; compiled, APPLY
  and host `mdl-apply` paths; per-session registries.
- Unsupported (strict): ON's process/which arguments; non-FUNCTION/SUBR applicables;
  every other predefined event (BLOCKED, CHAR, READ, …); IPC emission; SAVE; RESTORE.
- Security/licensing: no file I/O is added, nothing is exposed to clients, and no
  GPLv3 code was copied.

## Risks / next

- Lifting SAVE needs a separately approved design: a session snapshot (option b) or a
  boot adapter (option c). The next startup steps are ON "BLOCKED" (77rooms.mud:59),
  START/CONTIN, RESET and READSTRING (see the platform adapter memo).
- ADR-0047 assumes that no parallel branch has claimed that number.
