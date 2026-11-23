# OPEN failure payload and RECORD's retry branch: pinned Confusion reference (Probe D)

This is a read-only reference investigation, 2026-11-23. It establishes the **shape** of a
failed OPEN for the file specs that RECORD uses, and which status values keep RECORD out of
its busy/retry loop.

The maintainer-approved policy ("OPEN returns FALSE, no file is created") is unchanged; this
record supports it and does not propose a different policy.

- **Data:** [`open-failure-probe.json`](open-failure-probe.json)
- **Driver:** [`scripts/probe_session_reference.py`](../../../scripts/probe_session_reference.py) `open`
- **Provenance and settings:** identical to [SESSION-QUIT-REFERENCE.md](SESSION-QUIT-REFERENCE.md)
  - mdli sha256 `6df359f6…b789` (the same before and after)
  - mdlzork `bdcd4a67`
  - fixed clock 250776000, `TZ=UTC`

**Command** (sandboxed; exit 0; every mdli exit 0):

```
python3 -I scripts/probe_session_reference.py open docs/evidence/M3/open-failure-probe.json \
  --shim-src <boot-ref worktree>/scripts/reference/fixed_time.c
```

**Modes in the manifests.** Each manifest records the file modes as the run left them. The
driver then restores u+rw so it can hash the files, and any unreadable file is listed with
sha256 `UNREADABLE` in the "before" manifest.

## The exact OPEN forms RECORD uses (`77rooms.mud:722-752`, quoted)

```
<DEFINE RECORD RECORD (SCORE MOVES DEATHS QUIT? LOC
                "AUX" (CH <>) (STR ,RECORD-STRING) FL (CT 0) (MUDDLE ,MUDDLE)
                (DEV <VALUE DEV>) (SNM <VALUE SNM>))
  ...
        <UNWIND
         <PROG ()
          <PROG ()
                <COND (<SET CH <OPEN "READB" "ZORK" "LOG" .DEV .SNM>>
                       <COND (<G=? <SET FL <FILE-LENGTH .CH>> 1>
                              <ACCESS .CH <- .FL 1>>
                              <SET CT <READSTRING .STR .CH ,RECORDER-STRING>>)>
                       <CLOSE .CH>
                       <COND (<SET CH <OPEN "PRINTO" "ZORK" "LOG" .DEV .SNM>>)
                             (<AND <G? .MUDDLE 100> <==? <3 .CH> *600123*>>
                              ; "Can't win--no write access"
                              <RETURN T .RECORD>)
                             (T <SLEEP 1> <AGAIN>)>
                       <ACCESS .CH <MAX 0 <- .FL 1>>>
                       <PRINTSTRING .STR .CH .CT>)
                      (<OR <AND <L? .MUDDLE 100> <N==? <3 .CH> *4000000*>>
                           <AND <G? .MUDDLE 100> <==? <3 .CH> *600130*>>>
                       ;"on 10x, must get FILE BUSY to try again"
                       <SLEEP 1>
                       <AGAIN>)
                      (<SET CH <OPEN "PRINT" "ZORK" "LOG" .DEV .SNM>>)
                      (<AND <G? .MUDDLE 100> <==? <3 .CH> *600117*>>
                       ; "No write access"
                       <RETURN T .RECORD>)
                      (<RETURN T .RECORD>)>>
```

The UNWIND cleanup (`77rooms.mud:795`) is `<AND .CH <NOT <0? <1 .CH>>> <CLOSE .CH>>`. When
CH is a FALSE, the AND stops at `.CH` and the cleanup closes nothing.

These arguments are in force when RECORD runs:
- `.DEV` = `"DSK"` and `.SNM` = `"MDL"`, set by SAVE-IT at `77rooms.mud:18-21` because `,MUDDLE` is 101.
- So the forms are `<OPEN "READB" "ZORK" "LOG" "DSK" "MDL">`, then `<OPEN "PRINT" "ZORK" "LOG" "DSK" "MDL">`.
- When the log exists, the sequence is READB, CLOSE, then `<OPEN "PRINTO" "ZORK" "LOG" "DSK" "MDL">`.
- RECORD never uses `"READ"`. It is probed here only because the task asked for it.

Constants, as Confusion prints them (`D*` cases):
- `,MUDDLE` = **101**
- `*600130*` = **196696**
- `*600117*` = 196687
- `*600123*` = 196691
- `*4000000*` = 1048576

## Direct OPEN probes (plain LISTEN, no game; cwd = an empty `$TMPDIR` dir)

For each mode the probe evaluates the following. CH is the OPEN result.

| Expression | What it reports |
|---|---|
| `<TYPE .CH>` | type of the result |
| `<LENGTH .CH>` | number of elements |
| `<MAPF ,LIST ,TYPE .CH>` | type of each element |
| `<1 .CH>`, `<2 .CH>`, `<3 .CH>` | each element |
| `<==? <3 .CH> *600130*>` | RECORD's busy test (MUDDLE > 100 branch) |
| `<N==? <3 .CH> *4000000*>` | RECORD's busy test (MUDDLE < 100 branch) |

| Case | Setup | READB | PRINTO | PRINT | READ |
|---|---|---|---|---|---|
| D1 | no `MDL` dir | `#FALSE ("No such file or directory" "MDL/ZORK.LOG" 2)` | same | same | same |
| D2 | `MDL` mode 0555, no log | `#FALSE ("No such file or directory" "MDL/ZORK.LOG" 2)` | same (ENOENT) | **`#FALSE ("Permission denied" "MDL/ZORK.LOG" 13)`** | ENOENT, 2 |
| D3 | `MDL/ZORK.LOG` mode 0000 | `#FALSE ("Permission denied" "MDL/ZORK.LOG" 13)` | 13 | 13 | 13 |
| D5 | `MDL` is a regular file | `#FALSE ("Not a directory" "MDL/ZORK.LOG" 20)` | 20 | 20 | 20 |
| D4 (control) | readable log | CHANNEL | CHANNEL | CHANNEL (**truncates** the file to 0 bytes: PRINT opens for writing) | CHANNEL |

Every failure has the same shape:

- `<TYPE .CH>` = `FALSE`, `<LENGTH .CH>` = **3**, and the element types are `(STRING STRING FIX)`.
- `<1 .CH>` is the reason: the C `strerror` text.
- `<2 .CH>` is the file spec: the relative pathname Confusion built (`"MDL/ZORK.LOG"`, from
  SNM + `/` + NM1 + `.` + NM2).
- `<3 .CH>` is the status: the Unix errno as a FIX.
- `<==? <3 .CH> *600130*>` → `#FALSE ()`, and `<N==? <3 .CH> *4000000*>` → `T`, for every observed errno.

No file was created in any failing case. The D1, D2 and D5 manifests are unchanged, and D3's
file keeps its bytes.

Manual §11.2.1 says a failed OPEN returns a FALSE holding the reason, the file specification
and a status. Confusion matches that order and those types. The status and reason values are
host-specific (errno and strerror), not the ITS/TENEX codes the game was written for.

## Game probes: what RECORD does with each payload (boot, `north`, `quit`, `y`)

The diagnostic cases wrap OPEN, CLOSE and QUIT before FLOAD and log to a side file. D9-D12
also **fake** the result of OPENs whose third argument is `"LOG"`; that is a diagnostic of
RECORD's control flow only.

| Case | OPEN sequence (side log) | Outcome |
|---|---|---|
| D8 control | READB → ENOENT 2; PRINT → CHANNEL | ZORK.LOG written (131 B), CLOSE, QUIT, exit 0 |
| D6 log mode 0000 | READB → `#FALSE ("Permission denied" "MDL/ZORK.LOG" 13)`; PRINT → same | `RETURN T .RECORD`, then QUIT. Exit 0 in 0.17 s; the file is unchanged (`pre-existing\n`). |
| D7 / D7b `MDL` dir 0555 | READB → ENOENT 2; PRINT → EACCES 13 | `RETURN T`, then QUIT. Exit 0; no ZORK.LOG. SAVE-IT still succeeds because `MDL/MADADV.SAVE` exists and is writable. |
| D10 fake status 13 | READB → `#FALSE ("FAKE DENIED" "MDL/ZORK.LOG" 13)`; PRINT → same | `RETURN T`, QUIT, exit 0, 0.18 s, no file |
| **D9 fake `*600130*` ×3, then 13** | READB ×3 → `#FALSE ("FAKE BUSY" "MDL/ZORK.LOG" 196696)`; 4th READB → 13; PRINT → 13 | **Loops**: `SLEEP 1`, then `AGAIN` (re-runs the inner PROG), three times. **3.19 s**, then QUIT and exit 0. With a permanent `*600130*` it would never end. |
| D11 fake 2-element FALSE | READB → `#FALSE ("FAKE DENIED" "MDL/ZORK.LOG")` | `<3 .CH>` at 744 fails. Stdout gains `\n *ERROR* \n "ARGUMENT-OUT-OF-RANGE" \nLISTENING-AT-LEVEL 2 PROCESS 1\n`; stderr is `Atom REP has neither LVAL nor GVAL\nError: Unexpected EOF\n`. No QUIT, no ZORK.LOG, exit 0. FINISH's UNWIND `<QUIT>` cleanup did **not** run on the error, consistent with ADR-0051. |
| D12 fake `#FALSE ()` | READB → `#FALSE ()` | Same ARGUMENT-OUT-OF-RANGE failure as D11 |

## Which status a virtual-filesystem "denied" OPEN should return

- **When the loop is selected.** With `,MUDDLE` = 101 (Confusion, and this runtime per
  `mdl/runtime/core.rkt:1659`), RECORD loops only when `<==? <3 .CH> *600130*>`, i.e. when the
  status is the FIX **196696** (744-747).
- **Safe statuses.** Any other value in element 3 takes the fallback, and RECORD then returns T:
  - After READB fails, RECORD tries `OPEN "PRINT"` (748).
  - If that also fails, both remaining clauses `RETURN T .RECORD`, whatever the status (749-752).
  - `*600117*` (196687) selects the explicit "No write access" comment clause. Its effect is
    identical to any other status.
- **Required shape.** The FALSE **must have at least 3 elements**. A shorter FALSE makes
  `<3 .CH>` raise ARGUMENT-OUT-OF-RANGE (D11, D12), and in this runtime that error would reach
  the live ERROR handler.
- **Recommended payload:** reason STRING, file STRING, status FIX, mirroring Confusion. Of the
  candidates, D7 is the exact Confusion observation for "the log cannot be created":
  - READB: `#FALSE ("No such file or directory" "MDL/ZORK.LOG" 2)`
  - PRINT: `#FALSE ("Permission denied" "MDL/ZORK.LOG" 13)`

  A uniform `("Permission denied" "MDL/ZORK.LOG" 13)` (D6, D10) is equally safe.
- **Never return `*600130*`.** Note also: if this runtime ever had `,MUDDLE` < 100, the ITS
  branch (743) would loop on **every** status except `*4000000*` (1048576). It is MUDDLE=101
  that makes errno-style statuses safe.
- **The PRINTO branch (736-740)** is reached only after a *successful* READB, that is, when
  the log already exists. There it loops on every failure except `*600123*` (196691). A
  "denied" policy whose READB fails never reaches that branch. A policy that *allowed*
  reading but refused writing would hit that loop unless it returned `*600123*`.

## Limitations

- **Fakes.** D9-D12 replace OPEN's result through a wrapper. They show RECORD's reaction to a
  payload, not something Confusion's OPEN can itself return: errno never equals 196696.
- **Manual text.** The manual's ITS/TENEX status values were not re-fetched for this record.
  The §11.2.1 statement is taken as given in the task.
- **D4 truncation.** D4 shows Confusion's PRINT truncating an existing file (stdio `"w"`).
  RECORD avoids this by using PRINTO (`"rb+"`) when the log exists.
