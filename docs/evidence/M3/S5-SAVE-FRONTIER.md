# SAVE frontier at 77rooms.mud:26: reference investigation

<!-- Copied into the repository by S5-SAVE-RECORD (2026-11-23) from the
read-only reference investigation of 2026-11-22. File names in the table
below were renamed on copy: sf_probe.py -> s5_sf_probe.py (paths now derived
from the repository root), make_boot_cases.py -> s5_make_boot_cases.py,
primitives-*.json -> s5-save-frontier-primitives-*.json, boot-*.json ->
s5-save-frontier-boot-*.json. The recorded "workdir" values are the original
scratch directories. Line references into Confusion sources are citations
only; no GPLv3 code is copied. The maintainer decisions taken on this
evidence are ADR-0048; see S5-SAVE-RECORD.md. -->


Date 2026-11-22. This was a read-only investigation. No repository file was changed, nothing under `.cache/` was written, and mdli was never run in `.cache/upstream`.

- Pinned Confusion `mdli` sha256: `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789`
- mdlzork upstream: `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3` (the porcelain status was clean after every run)
- The pinned `MDL/MADADV.SAVE` still has sha256 `6293a39f…`, so it was not touched.
- Runtime checked: worktree `agent-a9e7baaa4092848be` @ `d865094` (`mdl/runtime/core.rkt`)
- Probe-tool worktree: `agent-a44b553475c81f22e` @ `ffd1388`

## Files

| File | Content |
|---|---|
| `s5_sf_probe.py` | Scratch driver. It runs one mdli process per case. The working directory is a fresh `$TMPDIR/sf-work/<case>-*` directory, either empty or a byte copy of `patched_confusion/`. It records stdin, stdout, stderr, the exit status, and the files created or changed (with sha256). I did **not** use `scripts.mdl_probe`, because its `cwd` is hard-wired to the pinned game directory (`reference_runner.GAME`). A SAVE run there would overwrite `MDL/MADADV.SAVE` in the pinned checkout. |
| `s5-save-frontier-primitives-cases.json` → `s5-save-frontier-primitives-reference.json` | 12 SAVE/RESTORE/SAVE-EVAL/INT-LEVEL primitive cases |
| `s5_make_boot_cases.py` → `s5-save-frontier-boot-cases.json` → `s5-save-frontier-boot-reference.json` | 5 whole-game cases: plain boot, traced boot, boot without an `MDL/` directory, restore of the freshly written `MADADV.SAVE`, and restore of `SAVEFILE/ZORK.SAVE` |

The commands were `python3 -I sf_probe.py primitives-cases.json primitives-reference.json` and `python3 -I make_boot_cases.py && python3 -I sf_probe.py boot-cases.json boot-reference.json`. Both drivers exited 0, and every mdli case exited 0. Confusion's REPL returns 0 even on errors and EOF, so the stderr text is the real signal. Every boot ends with `Error: Unexpected EOF` on stderr, because stdin is exhausted at the next READSTRING.

The traced boot uses the two forms of `run.mud` with a prelude typed in between. The prelude rebinds the GVALs of SAVE, INT-LEVEL, ON, HANDLER, DSKDATE, GETTIMEDATE, RANDOM, RESET, READSTRING, STARTER, GETSYS, XUNAME, GET-NAME, START, CONTIN, ROOM-INFO, RDCOM and others to wrappers. Each wrapper prints `{n NAME il=<INT-LEVEL> args}` and the result. No source file was edited. Two tracer limitations were found in Confusion itself:
- Splicing an empty TUPLE (`!.A`) into a 0-argument FUNCTION raises TOO-MANY-ARGUMENTS.
- Splicing a TUPLE into a FUNCTION (as opposed to a SUBR) raises ILLEGAL-SEGMENT.

Wrappers for FUNCTIONs therefore use a fixed arity.

## Q1: what SAVE returns, and what happens on RESTORE

**Fresh save.** `<SAVE .FN>` returns the STRING `"SAVED"`, as recorded in `save-return-and-intlevel` and in the trace step `{7 SAVE il=100000 "<MDL>MADADV.SAVE"}{=> SAVE "SAVED"}`.
- `,MUDDLE` is `101`, so `FN` is `"<MDL>MADADV.SAVE"`. Confusion resolves that to `./MDL/MADADV.SAVE`.
- If `fopen` fails (case `save-mdl-dir`, where the directory is missing), SAVE returns `#FALSE ()`. Source: Confusion `macros.cpp:7339-7346`.

**Restore in Confusion.** Confusion's SAVE does not capture the control stack. `mdl_write_image` (`mdl_binary_io.cpp:1273-1327`) writes the oblists, GVALs, top-level LVALs, associations and types. RESTORE works like this:
- `mdl_read_image` swaps in that heap, reopens file channels numbered above 2, and longjmps to the toplevel frame (`mdl_binary_io.cpp:1604-1619`).
- `mdl_toplevel` then evaluates the SAVE-EVAL form, if there is one, and enters LISTEN with its banner suppressed (`macros.cpp:3718-3745`).
- LISTEN loops forever, applying the **current GVAL of REP** on each pass (`macros.cpp:3686-3694`).

As a result, the SAVE call never returns a second time, and `"RESTORED"` is never observed: the `return "RESTORED"` at `macros.cpp:7426` cannot be reached when restore succeeds. The probes show this:
- `save-midprogram-restore-r`: neither `[B]` nor `RESTORED` is printed. `MARK` reverts to its saved GVAL. INT-LEVEL stays 100000, because it is a GVAL and is restored with the image.
- `restore-subr-same-process`: `[C]` is printed and the continuation is dropped (`[D]` never appears). Reading resumes at the next toplevel form.
- `restore-applies-rep(-r)` and `save-eval-*`: these confirm that LISTEN applies ,REP and that the SAVE-EVAL form runs after a restore.

**Restore of the image that SAVE-IT itself writes** (`restore-madadv-from-boot`): the result is a bare REPL. `<INT-LEVEL>` is 100000, REP is the default SUBR, and VERS is set. **The game does not start.**

**The manual (§11.6.2, read at mdl-language.readthedocs.io/en/latest/11-input-output/)** says something different: RESTORE "never returns", and it "causes a SAVE done some time ago to return again (this time with the value "RESTORED")". Execution then continues after that SAVE.

**Each branch of the source:**

- **Original rooms.99 text** (`(<=? <SAVE .FN> "SAVED"> <INT-LEVEL 0> T) (T …STARTER… <START "WHOUS" .ST>)`):
  - Under the manual's semantics, the build session saves, lowers INT-LEVEL to 0 and returns T, and the session ends.
  - Each player then RESTOREs `MADADV.SAVE`. SAVE returns `"RESTORED"` and the T clause runs STARTER, the WINNERS/XUNAME gate, `ON "BLOCKED"` and START. INT-LEVEL is still 100000 from the saved image and stays there until START's own `<INT-LEVEL 0>`.
  - A failed SAVE (`#FALSE`) also falls into the T clause.
  - Under Confusion, this text never starts the game, because RESTORE does not resume the SAVE.
- **Patched text** (`;"T) (T"` comments out the clause boundary):
  - There is a single clause, so `"SAVED"` → `<INT-LEVEL 0>` → the whole startup runs in the same session.
  - If SAVE returns `#FALSE` (case `boot-no-mdl-dir`), the COND has no matching clause and SAVE-IT returns `#FALSE ()`. No game starts, and the default REP echoes `look`.
  - `"RESTORED"` would behave like `#FALSE`. The patch is therefore only correct for "fresh SAVE, then continue in-session".

## Q2: side effects of SAVE that later code can observe

- **File.** `MDL/MADADV.SAVE` is created or overwritten: 874,610 to 888,353 bytes, versus the shipped 879,667-byte artifact. This is the only side effect. **Nothing after SAVE in SAVE-IT, START, CONTIN or RDCOM reads FN or the file, or depends on it.** The only other SAVE/RESTORE uses are DO-SAVE and DO-RESTORE (`77patch.mud:9-14`). Those run at player-command time and use a separate file, `<SAVEFILE>ZORK.SAVE`.
- **Return value.** Only `=? … "SAVED"` uses it.
- **INT-LEVEL** is unchanged by SAVE (it stays 100000 in both the probe and the trace).
- **Channels** are not touched; they are reopened only on restore.
- **Interrupts.** Confusion stubs ON, EVENT and HANDLER (they return `T`), so there are none (traces `{3 ON … => T}` and `{4 HANDLER il=0 T T}`). DIVERT-INT and DIVERT-HAND are themselves `T`.
- **GC.** Confusion reads the `gc?` argument but ignores it (`macros.cpp:7327`), and no GC happens. The manual says SAVE collects garbage unless `gc?` is FALSE.
- SAVE binds NM1 and NM2 in its own frame only (`macros.cpp:7331-7334`), so the binding is not observable afterwards.

## Q3: operations from SAVE returning "SAVED" to the first READSTRING (patched path, Confusion trace order)

| # | Operation (source) | Confusion observation | Racket runtime @d865094 |
|---|---|---|---|
| 1 | `=?` with `"SAVED"` (rooms:26) | true | `=?` registered |
| 2 | `<INT-LEVEL 0>` (rooms:26) | trace 8: old value 100000 | registered. **In our runtime this delivers any queued GC or DIVERT-AGC occurrences; Confusion never delivers any.** |
| 3 | `<SET STV <STARTER>>`, `TYPE? FIX`, `G? .STV 3` (rooms:31-32) | STARTER (81tell-repl:97) → 1, so the gate is skipped | MDL FUNCTION; TYPE? and G? registered |
| — | XUNAME/MEMBER/OFF "CHAR"/TELL/QUIT gate (rooms:33-50); `SUBSTRUC`/`MEMQ`/`ASCII` (rooms:51-55); `APPLY ,IPC-OFF` (rooms:57) | not executed | (MEMBER and QUIT are unregistered, but they are not reached) |
| 4 | `<SETG TENEX? <GETSYS>>` (rooms:56) | `#FALSE ()` | MDL FUNCTION |
| 5 | `<SET BH <ON "BLOCKED" ,BLO 100>>` (rooms:59) | stub returns `T` | **BLOCKED: `"BLOCKED"` is in `unsupported-predefined-interrupt-names` (core.rkt:1870; ADR-0047). This is the next frontier after SAVE.** |
| 6 | START: `XUNAME`→MAPF ,STRING/GXUNAME; SETG PTEMP (CHTYPE PHRASE, FIND-OBJ); `SETG INTIME <DSKDATE>` (GETTIMEDATE, PUTBITS); `GET-NAME` (`<10/7/8 .OUTCHAN>`, EMPTY?) | `"MTRZORK"`, `""` | Mostly registered (MAPF, STRING, CHTYPE, PUTBITS, GETTIMEDATE). The channel slots 7, 8 and 10 need checking against the CHANNEL vector. |
| 7 | SETG USER-NAME/DEATHS/MOVES/WINNER; `PUT ,WINNER ,AROOM <SETG HERE <FIND-ROOM "WHOUS">>` | | registered |
| 8 | `TELL "Welcome to Dungeon.\n" 1 .ST` (PRINTSTRING, CRLF, ANDB, GETBITS) | prints the welcome line and `This version created <today>.` | registered (S4 reached this point) |
| 9 | `<RANDOM <CHTYPE <DSKDATE> FIX>>` | seed depends on the clock (e.g. 3587874897) | registered (session RNG) |
| 10 | `<INT-LEVEL 0>` (rooms:292) | 0 → 0 | registered |
| 11 | CONTIN: SETG ALT-FLAG; `PUT <1 <BACK ,INCHAN>> 6 #LOSE *12*` (TENEX? false); `SETG SAVEREP ,REP`; **`SETG REP ,RDCOM`**; **`RESET ,INCHAN`**; SETG WINNER; `PUT ,PRSVEC 2 <>`; `,NULL` | trace 21-22 | BACK and PUT registered. **`RESET` is not registered.** `,REP` must have a GVAL: Confusion's REP is a SUBR (`#SUBR …227`), but `"REP"` is not registered in our runtime. `,NULL` comes from 81tell-repl:137. |
| 12 | SAVE-IT returns; FLOAD returns `"DONE"`; **LISTEN re-reads GVAL REP and applies RDCOM with no arguments** | trace 23 | **Missing: there is no LISTEN/REP toplevel loop.** Our loader/session must apply ,REP after `run.mud`. |
| 13 | RDCOM: AUX `,READER-STRING`, `,INBUF`, `,OUTCHAN`; `PUT .OUTCHAN 13 1000`; `ROOM-INFO T` (TELL, MAPF, object predicates, RACTION) | prints the West of House description | Mostly MDL code; not traced deeper |
| 14 | `PRINC ">"`; `SETG TELL-FLAG <>`; **`READSTRING .INBUF ,INCHAN .STR`** | trace 25: `il=0`, reads `look` → 4 | **`PRINC` is unregistered (tests/oblist_identity_test.rkt:294 asserts this). `READSTRING` is unregistered (only a comment mentions it, core.rkt:2715).** |

In short, the gaps in order of reachability are: `ON "BLOCKED"` → `RESET` → GVAL `REP` plus a LISTEN loop that applies ,REP → `PRINC` → `READSTRING`. The channel slots used by `GET-NAME` and `PUT .OUTCHAN 13` also need checking.

## Q4: INT-LEVEL

At the first READSTRING, INT-LEVEL is **0** (trace 25, `il=0`). It is lowered from 100000 twice:
- at rooms:26 (`<INT-LEVEL 0>` right after SAVE; trace 8 returns the old value 100000)
- again at START, rooms:292 (trace 20)

Nothing else touches it. In the restored image, INT-LEVEL is 100000 (`restore-madadv-from-boot`). This is consistent with the original design: interrupts stay masked during startup after a restore, until START lowers the level.

## Q5: options for a minimal faithful SAVE (the maintainer decides)

- **A. Session-owned "SAVED" with an observable record.** SAVE validates its arguments and returns `"SAVED"`. It writes no host file, and appends a session record: the decoded filename, INT-LEVEL at the time of the save, and a sequence number. RESTORE stays strictly refused.
  - Pros: smallest change. It matches every value the later source observes (Q2). It has no filesystem or security exposure.
  - Cons: Confusion's file write and its `#FALSE` on a missing directory are not reproduced, so this is a documented deviation. It is not archival-exact RESTORE.
- **B. A as above, plus a heap snapshot** (deep copy of GVALs and associations) so that a later RESTORE can be faithful.
  - With Confusion semantics, this means jumping to the toplevel and applying ,REP.
  - With manual semantics, it means capturing a Racket continuation so that SAVE returns `"RESTORED"`. That would make the *unpatched* rooms.99 text work.
  - Pros: enables archival exactness.
  - Cons: large and risky. Mutable-state snapshotting is hard, and the Confusion and manual semantics diverge, so one of them has to be chosen.
- **C. A real image file in a session-owned sandbox directory.**
  - Pros: closest to Confusion's observable side effect.
  - Cons: the image format can never match Confusion's. It gives the evaluator a host filesystem write, which conflicts with AGENTS.md's no-filesystem rule for exposed servers. Not recommended.
- **D. A documented boot adapter** that runs SAVE-IT with SAVE stubbed, or calls the post-SAVE code directly.
  - Cons: game-specific, and it bypasses original control flow. This is what the task brief warns against.

Whichever option is chosen:
- `ON "BLOCKED"` (step 5) is the next strict refusal after SAVE. It needs its own maintainer decision, analogous to ADR-0047 for IPC: register it, with no source of blocked-input occurrences.
- A LISTEN/REP loop is required: it has to re-read GVAL REP on every iteration (`macros.cpp:3686`).
- Our runtime has real interrupts while Confusion has none. Step 2, `<INT-LEVEL 0>`, is the first point where the two can diverge: a queued DIVERT-AGC (priority 1000) or GC occurrence would be delivered there. A faithful SAVE that performs the manual's GC could queue exactly such an occurrence. GC-HAND is OFF at that point, but DIVERT-HAND is enabled (rooms:17).

## Open questions

1. Should SAVE follow Confusion's semantics (no resume) or the manual's (`"RESTORED"` resume)? The patched source only needs `"SAVED"`.
2. Should a SAVE that cannot write model `#FALSE`, given that the patched SAVE-IT then silently does not boot?
3. Should SAVE perform the GC the manual specifies, given the DIVERT-AGC delivery risk at step 2?
4. The `This version created …` and RANDOM seed values depend on the clock (DSKDATE). Goldens need a fixed clock.
