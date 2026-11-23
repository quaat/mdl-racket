# Session ending in QUIT: pinned Confusion reference (Probe C)

Read-only reference investigation, 2026-11-23. It records what pinned Confusion does
when a fresh-boot session ends in QUIT. Nothing under `mdl/`, `tests/` or
`.cache/upstream/` was changed, and mdli never ran inside `.cache/upstream`.

- **Data:** [`session-quit-probe.json`](session-quit-probe.json) holds every case: full
  input, raw stdout/stderr (latin-1, so CR is kept), the canonical form, the exit status,
  file manifests of the game copy before and after, the text of created files, and the
  side logs of the diagnostic cases.
- **Driver:** [`scripts/probe_session_reference.py`](../../../scripts/probe_session_reference.py) `session`.
- Companion records: [OPEN-FAILURE-REFERENCE.md](OPEN-FAILURE-REFERENCE.md) and
  [CLOCK-SEED-REFERENCE.md](CLOCK-SEED-REFERENCE.md).

## Provenance and settings

| Item | Value |
|---|---|
| Worktree / base | `evidence/m3-session-probes` at `45c387f` |
| mdli sha256 (before and after every probe set) | `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` |
| Upstream (`sources.lock.json`; checked out, clean afterwards) | mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; MITDDC/zork `d94501340842e006791fce0757dc0043b8ec8916` |
| Game dir | `mdlzork_771212/patched_confusion`. It is copied fresh per case to `$TMPDIR/session-probes/<case>-*/game`, and `SAVEFILE/ZORK.SAVE` is removed first (as in `boot_reference.py`). |
| Clock | `fixed_time.c` from BOOT-REF (`feat/m3-boot-reference` `e616ac0`, sha256 `d1fa8652…ab925`), compiled per run with `gcc -shared -fPIC -O2 … -ldl`. Settings: `MDL_FIXED_EPOCH=250776000` (1977-12-12 12:00:00 UTC), `TZ=UTC`, `tv_usec=0`. |
| Entry | `<FLOAD "77loadall.mud">` LF `<SAVE-IT>` LF, then the game lines, LF-terminated |
| Tools | Python 3.9.2, pexpect 4.8.0, gcc 10.2.1 |

The probe used this command, sandboxed:

```
python3 -I scripts/probe_session_reference.py session docs/evidence/M3/session-quit-probe.json \
  --shim-src <boot-ref worktree>/scripts/reference/fixed_time.c
```

The driver exited 0. Every mdli process exited 0. Confusion exits 0 even on
`Error: Unexpected EOF`, so stderr is the real signal.

**Diagnostic cases** (`kind: diagnostic`) type a prelude into LISTEN before the
FLOAD. The prelude `SETG`s RANDOM, READSTRING, OPEN, CLOSE and QUIT to logging
FUNCTIONs. Each one applies the original SUBR to the same arguments and returns
its value. The FUNCTIONs log to `DIAG.LOG`, which sits outside the game copy.

- Their stdout from `Welcome to Dungeon.` onward is **byte-identical** to the
  matching transcript run (checked for C1).
- They are not transcripts.
- The last `CLOSE-ARG-TYPE CHANNEL` line in each log is the wrapper closing its
  own log inside the QUIT wrapper. It is not game activity.

## C1: complete session (six house-boot commands, quit, n, inventory, quit, y, look)

Input bytes (sha256 `edc26d5f…d687`):

```
<FLOAD "77loadall.mud">\n<SAVE-IT>\nnorth\nwest\nopen mailbox\ntake leaflet\ninventory\nscore\nquit\nn\ninventory\nquit\ny\nlook\n
```

Raw stdout from `"DONE"` to the end, in pipe mode (`C1-session-quit-pipe`). The full
stdout sha256 is `da5c1468…1a51`, and the repeat run `C1b` is byte-identical:

```
"DONE"\nWelcome to Dungeon.\r\nThis version created December 12.\n\nYou are in an open field west of a big white house, with a boarded\r\nfront door.\nThere is a small mailbox here.\n
>You are facing the north side of a white house.  There is no door here,\r\nand all the windows are barred.\n
>West of House\nThere is a small mailbox here.\n
>Opening the mailbox reveals a leaflet.\n
>Taken.\n
>You are carrying:\nA leaflet\n
>\nYour score would be 0 [total of 500 points], in 6 moves.\nThis score gives you the rank of Beginner.\n
>\nYour score would be 0 [total of 500 points], in 7 moves.\nThis score gives you the rank of Beginner.\nDo you wish to leave the game? (Y is affirmative): \n
>You are carrying:\nA leaflet\n
>\nYour score would be 0 [total of 500 points], in 9 moves.\nThis score gives you the rank of Beginner.\nDo you wish to leave the game? (Y is affirmative): \n
```

The block is wrapped after each `\n` that precedes `>`, for readability only; the raw
bytes are continuous. stderr is empty and the exit status is 0.

The pty run (`C1-session-quit-pty`, pexpect settings as in `boot_reference.py`) has the
same text with ONLCR (`\r\n`, and `\r\r\n` where the game string has an embedded CR):

- The pattern `Do you wish to leave the game? (Y is affirmative): ` matches after each `quit`.
- The step after `n` outputs `\r\n` and then the prompt `>`.
- The final step sends `y\nlook\n` in one write. It outputs `\r\n` and then EOF. The
  process exits 0, and no response to `look` appears.

### Findings

1. **Quit confirmation prompt.** `TELL` (default `POST-CRLF`, `81tell-repl.mud:27-38`) prints
   `Do you wish to leave the game? (Y is affirmative): ` followed by CRLF (`\n` on the pipe,
   `\r\n` on the pty), *before* the answer is read (`77rooms.mud:705-708`). Before the prompt,
   `SCORE` with `ASK?`=T prints `\nYour score would be 0 [total of 500 points], in N moves.\n`
   `This score gives you the rank of Beginner.\n` (`77rooms.mud:668-698`). The game says
   "would be", not "is". The singular form `in 1 move.` appears in C2e.
2. **What `n` prints:** nothing at all. YES/NO returns false, the FINISH COND fails,
   FINISH returns, and RDCOM runs the demons and prints `>`.
3. **Move counting.** RDCOM increments `MOVES` for every line with `INPLEN > 0`, before
   parsing (`77rooms.mud:620-621`).
   - `quit` is an RDCOM command, so it counts. The score printed by FINISH already
     includes it (6 → 7).
   - The YES/NO answer is read by YES/NO's own READSTRING (`77defs.mud:434`), not by
     RDCOM, so `n`/`y` **never** count.
   - A declined quit's move stays counted: inventory → 8, the second quit → 9.
   - The final FINISH text reports 9 moves, and so does ZORK.LOG.
4. **RECORD activity.** On `y`, the side log shows exactly:
   - `OPEN ("READB" "ZORK" "LOG" "DSK" "MDL")` → `#FALSE ("No such file or directory" "MDL/ZORK.LOG" 2)`
   - `OPEN ("PRINT" "ZORK" "LOG" "DSK" "MDL")` → CHANNEL
   - CLOSE of that CHANNEL, then `QUIT` with 0 arguments.

   No console output follows the CRLF after the prompt.
5. **Files in the game copy:**
   - `MDL/ZORK.LOG` is **created** (130 bytes, sha256 `8ed56223…07c3`, mode 0644). Its exact bytes are:
     ```
     \n        (MTRZORK)       December 12 at 12:00 PM\nPlayed for 0 seconds.\n0/500 points, 9 moves, 0 deaths.  In West of House. Quit.\n\n
     ```
     USER-NAME is `""` and XUNM is `"MTRZORK"`, which is Confusion's XUNAME. `Played for 0 seconds.`
     appears because GET-TIME diffs two DSKDATEs of the frozen clock. No flag names are printed.
   - `MDL/MADADV.SAVE` (the pre-existing 879,667-byte image) is **rewritten** by SAVE-IT. Its
     content is not deterministic: C1 and C1b have equal sizes but different sha256, and the
     diagnostic runs have other sizes.
   - Nothing else is created, changed or removed. `SAVEFILE/ZORK.SAVE` was removed by the
     driver before boot (`removed_before_boot`).
6. **Exit status 0.** QUIT is Confusion's `exit(0)` (`macros.cpp:7898-7906`, cited as behaviour only).
7. **Input after the affirmative quit is not processed.**
   - The pipe input ends `…y\nlook\n`, but no output follows the prompt's CRLF.
   - READSTRING's last logged read is `"y"` (count 1), followed only by OPEN, OPEN, CLOSE and QUIT.
   - In the pty run, `look` was written in the same send as `y` and got no response.
   - Limitation: on a pipe, stdio may have buffered the `look` bytes into the process. "Not
     read" here means that no MDL READSTRING consumed them.
8. **Why `inventory` is used after the declined quit.** Its output (`You are carrying:\nA leaflet\n`)
   is fixed by state alone. The C1 diagnostic log shows **only two RANDOM calls in the whole
   session**: START's seed and `west`'s `PROB 80`. Nothing between `n` and the second `quit`
   touches RANDOM.

## C2: end of input while the confirmation is pending

| Case | Input tail | Observed |
|---|---|---|
| `C2-eof-at-yesno` | `…score\nquit\n` then EOF | Stdout ends `…Do you wish to leave the game? (Y is affirmative): \n>`. stderr is `Error: Unexpected EOF\n`, the exit status is 0, and **no ZORK.LOG** is written. |
| `C2b` (diag) | same | YES/NO's READSTRING returns **0** with an empty text. INBUF still holds the stale `quit`, so `<1 .INBUF>` = `q`, which is not in `"TtYy"`: the answer is "no". RDCOM prints `>`, and its next READSTRING raises Confusion's `Unexpected EOF`. YES/NO RESETs INCHAN first (`77defs.mud:433`), which is why the first EOF read returns a count instead of failing. |
| `C2c` | `…quit\ny` (no LF) then EOF | READSTRING returns `y` (count 1), which is "yes". RECORD writes ZORK.LOG with 7 moves, then QUIT. stderr is empty and the exit status is 0. |
| `C2d` | `…quit\n\nquit\ny\n` | An empty answer line has count 0, and the stale `q` again means "no". It prints `>` with no text. The second quit shows 8 moves; the empty answer did not count. ZORK.LOG says 8 moves. |
| `C2e` | `quit\nyes please\n` right after boot | Only the first character is tested (`77defs.mud:438`), so this quits. The score line reads `in 1 move.` and ZORK.LOG says `1 moves`: RECORD always prints the plural, `77rooms.mud:770`. |

Mapped onto ADR-0050 D3 (mirror, then strict), C2 is: the first EOF read inside YES/NO
returns 0, the stale INBUF answers "no", `>` is printed, and the next RDCOM READSTRING is
the strict input-exhausted error. The Confusion transcript up to the final `>` is the
reference.

## C3: unknown words and malformed commands (ending with quit/y)

Input: `xyzzy`, `frobozzle`, `blorfintz`, `qqq`, `take`, `open the`, `put leaflet in`, an empty
line, `north west`, `score`, `quit`, `y`. Each response, verbatim on the pipe:

| Input | Response | Counts as a move? |
|---|---|---|
| `xyzzy` | `I don't know the word XYZZY` (`77np.mud:97`, word upper-cased) | yes |
| `frobozzle` | `The FROBOZZ Corporation created, owns, and operates this dungeon.`<br>The lexer keeps 5 characters, and `FROBO` is a known word, so this is **not** an unknown word. | yes |
| `blorfintz` | `I don't know the word BLORF` (truncated to 5 characters) | yes |
| `qqq` | `I don't know the word QQQ` | yes |
| `take` | `Take what?` | yes |
| `open the` | `Opening the mailbox reveals a leaflet.` (the parser picks the mailbox) | yes |
| `put leaflet in` | `I can't make sense out of that.` | yes |
| (empty line) | `Beg pardon?` (`77rooms.mud:641`) | **no** (INPLEN 0) |
| `north west` | the North of House full description (it moves north) | yes |
| `score` | `…in 9 moves.` | yes |
| `quit` | `…in 10 moves.` followed by the prompt | yes |

ZORK.LOG reads `0/500 points, 10 moves, 0 deaths.  In North of House. Quit.` The C3
diagnostic shows RANDOM is called only once, for the seed. Parse failures and unknown words
consume no RANDOM. North of House was not yet seen, so `north west` calls no PROB.

## C4: control path from the `quit` verb to process exit

Every path below is in `.cache/upstream/mdlzork/mdlzork_771212/patched_confusion`. The dynamic
order is confirmed by the C1 and D side logs.

1. `RDCOM` (`77rooms.mud:600`) prints `>` (614) and runs `READSTRING .INBUF ,INCHAN .STR` (616).
   `INPLEN > 0` leads to `SETG MOVES <+ ,MOVES 1>` (620-621). Then EPARSE, and the verb
   function `VFCN` is applied through `APPLY-RANDOM` (631-632; macro at `77defs.mud:440`).
2. The verb `QUIT` is bound to `FINISH` (`77dung.mud:2920`, `<SADD-ACTION "QUIT" FINISH>`),
   applied with no arguments, so `ASK?`=T.
3. `FINISH` (`77rooms.mud:700-712`) is `<UNWIND <PROG () …> <QUIT>>`:
   - `SCORE .ASK?` runs (668), then `TELL "Do you wish to leave the game? (Y is affirmative): "`
     (705-707), then `YES/NO <>` (708).
   - `YES/NO` (`77defs.mud:431-438`) does `RESET .INCHAN`, `READSTRING .INBUF .INCHAN ,READER-STRING`,
     and then `MEMQ <1 .INBUF> "TtYy"`.
   - For "no": the COND fails, the PROG returns, and the UNWIND cleanup does **not** run
     (normal exit). Control returns to RDCOM, which finishes the turn: demons (642-646),
     then the `>` of the next pass.
   - For "yes": `RECORD .SCOR ,MOVES ,DEATHS .ASK? ,HERE` (710), then `<QUIT>` (711).
4. `RECORD` (`77rooms.mud:722-795`) is the same as RECORD in D, with these steps:
   - `OPEN "READB" "ZORK" "LOG" .DEV .SNM` (731). DEV=`"DSK"` and SNM=`"MDL"` were set by
     SAVE-IT, `77rooms.mud:18-21`, because `MUDDLE`=101.
   - Then the busy test (743-747) and `OPEN "PRINT"` (748).
   - The log lines use `PDSKDATE <DSKDATE>` (761; defined at 833) and `PLAY-TIME .CH <>`
     (763; defined at 187, which calls GET-TIME at 174), then `CLOSE` (794).
   - Its own UNWIND cleanup (795) closes CH only if it is a CHANNEL with nonzero CHNUM.
5. `QUIT` is the Confusion SUBR, `exit(0)` with no argument (more than one argument raises
   `Too many arguments to QUIT`). The process ends with status 0, FINISH's UNWIND cleanup
   `<QUIT>` (712) never runs, and nothing more is read.

Other QUIT call sites (not exercised):
- the XUNM gate in SAVE-IT (`77rooms.mud:50`) and START (279);
- the save/restore paths (427, 428, 435);
- JIGS-UP after the third death (`77rooms.mud:951-952`: `RECORD <SCORE <>> …` then `QUIT`);
- `FINISH` from `HANDLE` (231, `CONTROL-G?`; 252, `#FALSE (". Error.")`);
- `FINISH <>` from death paths (338-339, 898, 906).

## Limitations

- **Pipe output buffering.** On the pipe, Confusion's output order relative to input is not
  observable. The pty run supplies the ordering evidence for the prompt's CRLF.
- **Process-specific values.** `MTRZORK`/`""` (XUNAME and USER-NAME) and the `MADADV.SAVE`
  bytes belong to the Confusion process. They are not game semantics.
- **Clock-dependent log fields.** ZORK.LOG's date and `Played for` fields depend on the
  clock. Under the fixed clock they are `December 12 at 12:00 PM` and `0 seconds`.
- **Not exercised:** death, the save/restore verbs and the `HANDLE` paths.
