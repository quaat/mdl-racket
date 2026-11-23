# INTERACTIVE frontier: RESET, host loop, PRINC, READSTRING, EOF/QUIT (reference investigation)

> **Copy note (S7, 2026-11-23).** This is the read-only S7 reference
> investigation, copied into the repository as evidence for ADR-0050. The probe
> cases and Confusion outputs are unchanged. Only the drivers' absolute paths
> were made repo-relative (`if_probe.py`: `MDL_REPO_ROOT`, `MDL_FIXED_TIME_SO`;
> `make_trace_case.py`: repo-relative `mdl_builtins.cpp`). The `racket_*.rkt`
> scratch walks (throwaway host stubs, absolute paths) and the `shim/` binary
> were **not** copied; only their recorded outputs (`racket-*.txt`) were. The
> implementation is described in [`../S7-INTERACTIVE.md`](../S7-INTERACTIVE.md).

Date 2026-11-23. This was a read-only investigation: no repository file was changed, nothing was written under `.cache/`, and mdli was never run in `.cache/upstream`. The mdlzork checkout was clean at `bdcd4a67` afterwards (`git status --porcelain` printed nothing).

- Pinned Confusion `mdli` sha256: `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789`
- Upstream sources (sources.lock.json):
  - mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`
  - MITDDC/zork `d94501340842e006791fce0757dc0043b8ec8916`
- Runtime inspected: worktree `s6-rep` at `aea622a`, branch `feat/m3-startup-rep`. Racket v7.9 [bc], Python 3.9.2.
- Game sources cited (read-only): `.cache/upstream/mdlzork/mdlzork_771212/patched_confusion/*.mud`.
- Confusion C++ is cited by file:line as behaviour evidence only. No Confusion source text is copied here.
- Manual: mdl-language.readthedocs.io, chapters 11 (§11.1.2.3 PRINC, §11.2.8 channel slots, §11.3 EOF, §11.4.1.2 READSTRING, §11.7.7 RESET, §11.8 terminals) and 16.1 (LISTEN), fetched 2026-11-23.

All relative file names below are in this directory.

## Files

| File | What it is |
|---|---|
| `if_probe.py` | Probe driver.<br>Runs one mdli process per case, with the cwd set to a fresh `$TMPDIR/if-work/<case>-*` directory: either empty, or a byte copy of `patched_confusion/`.<br>stdin is a **pipe**, not a pty.<br>Records raw stdout as latin-1 (so `\r` is kept), a canonical form, stderr, the exit status, and the files changed.<br>`fixed_clock` loads the house-boot `fixed_time.c` shim (built into `shim/`) with `MDL_FIXED_EPOCH=250776000` and `TZ=UTC`. |
| `make_cases.py` | Generates the inputs:<br>`primitives-cases.json` → `primitives-reference.json` (30 cases: RESET, READSTRING, PRINC, QUIT, EOF, LISTEN)<br>`boot-cases.json` → `boot-reference.json` (7 whole-game cases) |
| `extra-cases.json` → `extra-reference.json` | The NULL-marker boot case, and the TYPEs of game functions |
| `extra2-cases.json` → `extra2-reference.json` | EOF/RESET interplay, the EOF routine, and quit followed by EOF |
| `make_trace_case.py` → `trace-cases.json` → `trace-reference.json`, `trace-summary.txt` | First-hit trace of every Confusion SUBR over boot + six commands + `quit`/`y`. |
| `golden-compare.txt` | Pipe output compared with the approved `house-boot-candidate.json` |
| `racket_inventory.rkt` → `racket-inventory.txt` | Which Confusion builtin names are GASSIGNED in an s6-rep session, before and after loading |
| `racket_errh.rkt` → `racket-errh.txt` | Is the game's ERROR handler HANDLE live in our runtime? |
| `racket_frontier_walk.rkt` → `racket-frontier-walk-{1..4}.txt`, `racket-frontier-walk-six-raw.txt`, `racket-vs-confusion.txt` | **Scratch** walk of the s6-rep runtime, with throwaway host stubs for RESET/PRINC/PRIN1/READSTRING/QUIT (and optionally OPEN/CLOSE), applying `,REP` once. It is an experiment, not an implementation. |

## Commands and exit statuses (all sandboxed)

| Command | Exit | Result |
|---|---|---|
| `gcc -shared -fPIC -O2 -o shim/fixed_time.so <a64a worktree>/scripts/reference/fixed_time.c -ldl` | 0 | |
| `python3 -I make_cases.py` | 0 | 30 primitive and 7 boot cases |
| `python3 -I if_probe.py primitives-cases.json primitives-reference.json` | 0 | every mdli exit status was 0 |
| `python3 -I if_probe.py boot-cases.json boot-reference.json` | 0 | every mdli exit status was 0; `MDL/MADADV.SAVE` is rewritten in each copy; quit+y also writes `MDL/ZORK.LOG` |
| `python3 -I if_probe.py extra-cases.json extra-reference.json` | 0 | |
| `python3 -I if_probe.py extra2-cases.json extra2-reference.json` | 0 | |
| `python3 -I make_trace_case.py && python3 -I if_probe.py trace-cases.json trace-reference.json` | 0 | 145 SUBRs wrapped |
| `racket racket_inventory.rkt "<180 builtin names>"` | 0 | load PASS, 1229 forms |
| `racket racket_errh.rkt` | 0 | `<ERROR ...>` ran HANDLE, which then failed at MEMBER |
| `racket racket_frontier_walk.rkt "<six commands>"` | 0 | first run: PRINC stub lacked CHARACTER; second run: ran to the EOF stub error |
| `racket racket_frontier_walk.rkt "north\nquit\ny\nlook\n" [OPEN CLOSE]` | 0 | ended by QUIT (see D4) |

Confusion's mdli exits 0 even on `Error: Unexpected EOF` and on errors. The real signal is the stderr text.

## 1. RESET of INCHAN

**Manual §11.7.7 / §11.8**
- RESET "returns *channel*, after resetting it… like OPENing it afresh, with only the file-name slots preserved".
- For input it means "emptying all input buffers".
- For a terminal it re-acquires the terminal and updates device parameters.

**Confusion** (`macros.cpp:6777-6787` arity and type checks; `macros.cpp:1334-1377` `mdl_internal_reset_channel`):
- A stdin/stdout channel keeps its `FILE*`. It is never reopened, and stdio-buffered input is *not* discarded.
- It sets STATUS (slot 11) to 0. That clears both `ICHANNEL_AT_EOF` and `ICHANNEL_HAS_LOOKAHEAD`, so **the one pending lookahead character is dropped**.
- It rewrites DEVN (slot 9) to `"TTY"` on a tty, or to DEVNARG (`""`) on a pipe.
- It returns the same object.
- A channel whose CHNUM (slot 1) is 0 instead takes the OPEN path (`macros.cpp:1342-1343`).

**Probes** (`primitives-reference.json`, `extra2-reference.json`):

| Case | Observation |
|---|---|
| `reset-inchan-return` | `<TYPE <RESET ,INCHAN>>` → `CHANNEL`; `==?` the argument → `T`; LENGTH 19 |
| `reset-outchan-return` | same for OUTCHAN |
| `reset-arg-errors` | `Not enough args to RESET`, `Argument to RESET must be of type CHANNEL`, `Too many args to RESET` |
| `channel-slots` | INCHAN before: `[1 "READ" "" "" "" "" "" "" "DSK" "" 2 0 #LOSE *0* 10 0 0 0 10 0]`: CHNUM 1, STATUS 2 (lookahead), slot 13 = EOF object `#LOSE 0`, slot 14 = lookahead char 10 (LF).<br>After RESET: DEVN `""`, STATUS 0.<br>OUTCHAN: `[2 "PRINT" … "DSK" "" 0 0 0 0 0 0 0 10 0]`, so line width (slot 13) defaults to **0** (unlimited). After `<PUT ,OUTCHAN 13 1000>` and RESET, slot 13 stays 1000; slot 14 (column) is live. |
| `contin-put-then-reset` | `<1 <BACK ,INCHAN>>` is FIX 0. The CONTIN PUT (index 6) is an association on it, which survives RESET. RESET does not touch the predecessor slot. |
| `reset-buffer-discard` vs `noreset-buffer-compare` | Without RESET, the `\n` left after the typed form is read as an empty line (count 0). With RESET, `abc` is read (count 3). **RESET drops exactly the lookahead.** |
| `boot-same-line` | `<SAVE-IT>north` → `I don't know the word ORTH`. CONTIN's RESET ate the `n` that LISTEN's reader had peeked. |
| `eof-sequence-then-reset` | After a READSTRING hit EOF (flag set), `<RESET ,INCHAN>` clears the flag. The next READSTRING returns 0, *not* an error; the one after that raises `Error: Unexpected EOF`. |

**Why RESET matters in the game.** Three sites call it:
- CONTIN (`77rooms.mud:303`)
- YES/NO (`77defs.mud:433`)
- JIGS-UP (`77rooms.mud:888`)

READSTRING never sets a lookahead, so in the game RESET only:
- discards LISTEN's peeked character after `<SAVE-IT>` (this is why the golden transcript has no spurious `Beg pardon?`), and
- clears a pending EOF.

Under our host loop, terminal input contains only the commands, so the lookahead effect is moot unless we model a lookahead.

**Our terminal CHANNEL state that RESET could touch** (`core.rkt:2778-2795`):
- Backing VECTOR of 20: `[0 | 0 mode "" "" "" "" "" "" "TTY" "" 0 0 80 0 24 0 0 10 0]`.
- The visible view is `REST 1`. GET-NAME reads slots 10/7/8; CONTIN PUTs on `<1 <BACK ,INCHAN>>`.

Differences from Confusion that an implementer will meet:
- CHNUM is 0 here, where Confusion has 1 or 2. A literal port of Confusion's "CHNUM 0 → open" rule would be wrong.
- INCHAN slot 13 here is 80; Confusion puts the EOF object there.
- INCHAN slot 14 here is 0; Confusion puts the lookahead there.
- OUTCHAN slots 13 and 15 here are 80 and 24; Confusion has 0 and 0.
- DEVN here is "TTY"; Confusion has "DSK" on a pipe and "TTY" on a pty.

**What is needed:** RESET of a host terminal channel returns the same CHANNEL and clears the host EOF flag (and the lookahead, if one is ever modelled). It must leave slots 13/14, the predecessor slot and associations untouched. The strict errors are arity and non-CHANNEL.

## 2. Top-level loop: how Confusion reaches RDCOM, and how it ends

**Manual 16.1.** LISTEN does `<APPLY <VALUE REP>>` (the LVAL first, then the GVAL) if that value is applicable; otherwise it applies the SUBR REP, which loops forever.

**Confusion** (`macros.cpp:3686-3705`):
- LISTEN loops forever. On each pass it re-reads REP (`mdl_both_symbol_lookup`) and applies it to no arguments.
- The default REP (`macros.cpp:7628-7672`) does one READ / EVAL / PRIN1 / TERPRI and returns.
- At the top level, at EOF, `mdl_toplevel` stops (`macros.cpp:3740`).

**Order of events on the run.mud path:**
1. LISTEN applies the default REP, which reads `<SAVE-IT>`.
2. SAVE-IT → START → CONTIN sets `REP` to `,RDCOM` and returns `,NULL`.
3. SAVE-IT returns `,NULL` (`77rooms.mud:304-306`).
4. The *same* default REP now PRIN1s that value and does a TERPRI.
5. The next LISTEN pass applies RDCOM with no arguments.

**The blank line in the golden.** It comes from step 4:
- NULL is an ATOM with an empty PNAME (`81tell-repl.mud:137`; "a single rubout in real MDL").
- PRIN1 prints nothing for it, then TERPRI prints `\n`.
- Proof (`boot-null-marker`): with `<SETG NULL NULLMARK>` before `<SAVE-IT>`, the line between `This version created December 12.` and `You are in an open field…` reads `NULLMARK`.
- `"DONE"` in the golden is the same REP printing FLOAD's value.

**RDCOM never returns on this path** (`77rooms.mud:600-655`):
- It is called with IVEC `<>`, so it runs `<PUT .OUTCHAN 13 1000>` and `<ROOM-INFO T>`.
- It then enters an unconditional `REPEAT`, whose only exit is `<AND .IVEC <RETURN>>`.
- So LISTEN's "re-apply REP each pass" is never exercised after CONTIN; the host loop effectively makes one pass.
- `listen-rep-function-returns` confirms the re-application for a REP that does return.

**Ending the game.** QUIT is `exit(0)` (`macros.cpp:7898-7906`): immediate, with no UNWIND cleanup. `<QUIT 1>` gives `Too many arguments to QUIT`.

Game paths that reach QUIT:
- FINISH (`77rooms.mud:700-712`), from the `quit` verb, JIGS-UP after a third death, and HANDLE. It runs SCORE, asks via YES/NO, then RECORD (writes `<MDL>ZORK.LOG`), then QUIT.
- Inside an `UNWIND` whose cleanup is also `<QUIT>`.
- `boot-quit-yes`: the output stops after `Do you wish to leave the game? (Y is affirmative): \n`. Exit 0, a 131-byte `MDL/ZORK.LOG` is created, and the remaining input is unread.
- `boot-quit-no`: the game continues.
- `boot-quit-then-eof`: YES/NO RESETs (clearing EOF), READSTRING returns 0, and stale INBUF `"quit"` → `q` is read as "no". The game shows `>` again, then `Error: Unexpected EOF`.

**End of stdin.** The exact transcript (`boot-six`) is `…This score gives you the rank of Beginner.\n>Beg pardon?\n>`, then stderr `Error: Unexpected EOF\n`, exit status **0**.
- The first READSTRING at EOF returns 0, so RDCOM prints `Beg pardon?` and MOVES is not incremented.
- The second raises (`mdl_read.cpp:1293-1296` → `mdl_exec_chan_eof_object` → `Error: Unexpected EOF`, `mdl_read.cpp:274-282`).
- At EOF in mid-line (`boot-eof-midline`), the partial `west` is executed and then the error follows.
- An explicit EOF routine (4th argument) is evaluated after the channel is closed, and its value is returned (`eof-routine-proper`).

**Our runtime differs here.** The game's ERROR handler HANDLE (77rooms.mud:262-264) is **live** in our runtime. Confusion stubs HANDLER, so `<GASSIGNED? ERRH>`/`<TYPE ,ERRH>` there is ATOM T.
- `racket-errh.txt`: after load, `<ERROR PROBE-ERROR>` runs HANDLE, which fails at the unregistered MEMBER (`77rooms.mud:219`).
- INT-LEVEL during RDCOM is 0 and the handler priority is 8, so any MDL-level ERROR during play enters HANDLE.
- With MEMBER present, HANDLE would continue: XUNM `"MTRZORK"` is not in WINNERS → TELL "I'm sorry, you seem to have encountered an error…" → FINISH `#FALSE (". Error.")` → RECORD → QUIT.

## 3. Operations RDCOM and its callees need (six-command scenario, then quit/y), in first-hit order

**Method.** Every Confusion SUBR except 23 control/infrastructure ones was replaced with a counting FUNCTION wrapper; tracing starts just before `<SAVE-IT>` (`trace-reference.json`, `trace-summary.txt`).
- Phase = the number of READSTRING calls made before the first hit: 0 = boot up to the first `>`; 1-6 = north … score; 7 = quit; 8 = `y` plus RECORD and QUIT.
- Hits ordered 1-39 run in SAVE-IT/START/CONTIN before RESET, and our runtime already passes them.
- "Registered" means present in `builtin-table` or a compiler/eval special form (`racket-inventory.txt`). It does not prove the semantics match.

| Order | Operation | First phase | Calls | s6-rep |
|---|---|---|---|---|
| 40 | **RESET** | 0 (CONTIN 303) | 2 | **missing** |
| 41 | N==? | 0 | 188 | registered |
| 42 | FORM (runtime DEFMAC expansion in Confusion) | 0 | 1112 | registered |
| — | PUT on a CHANNEL (`<PUT .OUTCHAN 13 1000>`) | 0 | — | works (scratch walk) |
| 43 | **PRINC** (STRING `">"`, later CHARACTER `!\.` in "open mailbox") | 0 | 49 | **missing** |
| 44 | **READSTRING** | 0 | 8 | **missing** |
| 45-48 | MAPR, MIN, L=?, XORB | 1 (north) | | registered |
| 49 | FIX | 4 (take leaflet) | | registered |
| 50 | **PRIN1** (FIX, in SCORE) | 6 (score) | 14 | **missing** |
| 51-52 | 1?, FLOAT (FLOAT compare in SCORE) | 6 | | registered |
| — | **QUIT** (not wrapped; hit) | 8 | 1 | **missing** |
| 53, 55, 56 | VALUE, N=?, G=? | 8 (RECORD) | | registered |
| 54 | **OPEN** (`"READB"`/`"PRINT" "ZORK" "LOG" "DSK" "MDL"`) | 8 | 2 | **missing** |
| 57 | **CLOSE** | 8 | 1 | **missing** |
| — | **MEMBER** | only via HANDLE (our live ERRH) | 0 in Confusion | **missing** |

Not wrapped in the trace, but all registered or special in s6-rep: APPLY, PUT, NTH, +, 0?, SETG, GVAL, LVAL, RETURN, AGAIN, MAPRET, MAPSTOP, MAPLEAVE, ERRET. The FSUBRs on the path are REPEAT, PROG, COND, AND, OR, UNWIND (FINISH, RECORD, JIGS-UP) and QUOTE. BIND is never used.

**Scratch walk (decisive evidence).** In a throwaway s6-rep session, host stubs were SETG'd for only RESET (returns its argument), PRINC (STRING/ATOM/FIX/CHARACTER), PRIN1 (FIX), READSTRING (Confusion rules) and QUIT. Then SAVE-IT was called and `,REP` applied once.
- The run plays all six commands.
- `racket-vs-confusion.txt`: the s6-rep output from `81prim.mud loaded` onward is **byte-identical** to Confusion's pipe output, with the date line normalised (s6-rep's clock was not fixed). That includes the `\r\n` inside game strings and the trailing `Beg pardon?\n>`.
- The only differences are the two LISTEN artifacts: the `"DONE"` line, and the blank line from PRIN1 of `,NULL`.
- No other missing primitive, TYPE-of-compiled-DEFINE problem, or BLOCKED interrupt was hit.
- The quit/y walk (D4) also needs OPEN and CLOSE, or else hits the UNWIND hazard.

## 4. READSTRING and PRINC semantics needed

**READSTRING** (`macros.cpp:7097-7116`, `mdl_read.cpp:1284-1322`; manual §11.4.1.2).
- Arguments: `buffer channel [stop] [eof]`. The channel defaults to `.INCHAN` and is bound as INCHAN in the frame.
- If AT_EOF is already set on entry, the EOF object is evaluated (default: `Error: Unexpected EOF`) and the channel is closed. Otherwise it reads characters until one of these:
  - the buffer is full: the default, or a FIX `stop`;
  - a character in the STRING `stop`: that character is **consumed and not stored**;
  - EOF: AT_EOF is set and the partial count is returned.
- It returns a FIX count. It writes from position 1 of the given view (`<REST .B 2>` writes into the backing string) and never clears the rest of the buffer, so stale bytes stay (YES/NO relies on `<1 .INBUF>`).
- Case is preserved (LEX upper-cases later). There is no echo, and nothing is written to OUTCHAN.
- In overflow (`readstring-overflow`, INBUF is 100), the rest of the line stays for the next call. `boot-edge-lines`: a 150-character line gives two `I don't know the word XXXXX` responses.
- READER-STRING is ESC CR LF.
  - CRLF input yields an extra empty read, so a `Beg pardon?` follows every command (`boot-six-crlf`).
  - ESC ends a command (`west<ESC>inventory` = two commands).
- `!x` in input is read through the reader's bang handling (`mdl_read_1_char`; `Ab!cD` → `AbcD`, count 4).
- Errors: `Not enough arguments to READSTRING`; a non-STRING buffer gives `UVECTOR for readstring must be of type STRING`; an output channel gives `Channel for READSTRING must be input channel`; 5 args gives `Too many args`.
- ALT-FLAG is never read by the patched path: the `READCHR` that consumed the LF after CR is commented out at 77rooms.mud:617-618.

**PRINC** (`macros.cpp:6971-6991`, `mdl_output.cpp:335-397, 966-986`; manual §11.1.2.3).
- Arguments: `obj [channel]`. The channel defaults to the LVAL of OUTCHAN. It **returns obj**.
- It prints a STRING without quotes, a CHARACTER as the bare character, an ATOM without trailers, and a LIST with its elements PRINC'd.
- Non-whitespace control characters are printed as `^X`: ESC prints as `^[`. CR and LF are written raw.
- Errors: `Too few arguments to PRINC`, `Channel for PRINC must be output channel`, `Error: Attempt to write to non-channel`, `Too many arguments to PRINC`.
- PRIN1 has the same shape and flushes stdout.

**Line breaking.** PRINC/PRIN1/PRINT (but **not** PRINTSTRING) insert a newline when column > 0 and `column + len > linewidth`.
- linewidth is slot 13 (0 = never); the column is slot 14 and resets at a `\r` character or a newline.
- `princ-linewidth` shows this with width 10.
- RDCOM sets the width to 1000, so it is unreachable in the scenario. HANDLE sets 80.

**Transcript format** (`golden-compare.txt`):
- The prompt is a bare `>` with no newline after it. The response text follows it directly, and input is not echoed.
- Game strings contain the source's CRLF bytes (`\r\n`), and our reader keeps them, as the walk shows.
- **The approved golden is PTY-rendered.** Emulating termios ONLCR (`\n`→`\r\n`) on the raw pipe bytes and then applying `boot_reference.canonical_text` reproduces `boot_output` and all six command outputs **exactly**. Plain `\r\n`→`\n` canonicalisation does not: the golden's `boarded\n\nfront door` comes from `\r\r\n`.
- Confusion's stdout is fully buffered on a pipe; on a pty the prompt is flushed before the read.

## 5. Decision points (tradeoffs → recommendation)

**D1. LISTEN artifacts in the boot transcript.** The golden `boot_output` contains three things a host loop does not produce: `LISTENING-AT-LEVEL 1 PROCESS 1`, `"DONE"` (REP printing FLOAD's value), and one empty line (REP doing PRIN1 of `,NULL` + TERPRI).
- (a) The host prints them: it PRIN1s and TERPRIs the values of the two fixed entry forms, plus the banner. This is faithful to the original design: NULL's rubout exists for exactly this print. But it fakes interpreter output and needs PRIN1 of STRING and ATOM.
- (b) The parity comparator removes exactly these three lines, a documented "LISTEN view".
- **Recommendation:** (b) for the banner and `"DONE"`.
- For the `,NULL` line, PRIN1+TERPRI of SAVE-IT's value by the host loop is defensible, because it is the REP print the game's own code relies on. Have the maintainer choose explicitly and record the choice in an ADR.

**D2. Golden comparison canonicalisation.**
- **Recommendation:** compare as `canonical_text(ONLCR(raw))`, which is proven exact on Confusion's pipe output. Never "fix" the double newlines in the runtime.

**D3. Exhausted input.** Confusion's sequence is: the first EOF read returns its count (so `Beg pardon?` and `>` are printed); the next READSTRING raises `Unexpected EOF`; exit 0. The manual says the default EOF action calls ERROR, and in our runtime that would enter the live HANDLE → FINISH → RECORD → QUIT, whose output Confusion never shows.
- **Recommendation:** model AT_EOF exactly as Confusion does: the first EOF returns the count, and a READSTRING entered with the flag set fails. Raise a **host-level strict error** (not an MDL ERROR, so HANDLE is not run) with a distinct `input exhausted` message. Record the deviation from the manual's ERROR call.
- Tests assert the transcript up to the final `>` and then that exact error.

**D4. QUIT vs UNWIND.** Confusion's QUIT is `exit(0)` and never runs UNWIND cleanups. `mdl-unwind` (`core.rkt:885-894`) runs the cleanup on *any* non-local exit, including Racket exceptions.
- The scratch walk showed the consequence: a strict error inside FINISH's UNWIND body (RECORD's unimplemented OPEN) ran the cleanup `<QUIT>`. That replaced the strict error with a clean QUIT (`racket-frontier-walk-3.txt`), and QUIT ran twice in walk 4.
- **Recommendation:** QUIT ends the session through an escape that `mdl-unwind` does not treat as unwinding (no cleanup), and returns a terminal "quit" outcome to the host loop.
- Separately, decide whether strict host errors should run UNWIND cleanups at all. MDL errors do not unwind; they enter a nested LISTEN. **Recommendation:** they should not, or the strict-failure rule is violated.

**D5. RECORD's file I/O** (OPEN/CLOSE `<MDL>ZORK.LOG`; ACCESS, FILE-LENGTH and READSTRING on a file when the log exists).
- (a) OPEN returns a FALSE `("reason" "file" status)`. RECORD then tries `"PRINT"`, gets FALSE again, and does `RETURN T`, so the game ends cleanly with no file.
- (b) A session-owned in-memory file.
- (c) Real host files. This conflicts with AGENTS.md isolation.
- **Recommendation:** (a), documented as a deviation from Confusion, which does write the log. Make the status value differ from `*600130*` (the "busy, retry" code) or RECORD loops forever.

**D6. Live ERROR handler (ERRH/HANDLE).** Confusion stubs HANDLER; ours delivers it. Any MDL ERROR during play runs the game's crash path: MEMBER, then TELL "I'm sorry…" and FINISH.
- **Recommendation:** keep the real delivery, because it is the original semantics. Then add MEMBER before any slice whose tests can raise an MDL ERROR. Make sure host-level strict errors (D3, unsupported constructs) are not routed through it.

**D7. Input line endings and echo.**
- **Recommendation:** the host feeds LF-terminated lines (a pty's ICRNL does the same) and never echoes. CRLF input would produce an extra `Beg pardon?` per line, as Confusion does. Flush OUTCHAN before every blocking terminal READSTRING.

**D8. Terminal CHANNEL slots.** Our slots differ from Confusion: CHNUM 0, widths 80/24, no EOF-object or lookahead slots.
- **Recommendation:** keep them; nothing on the path reads them except `PUT .OUTCHAN 13`.
- Store RESET/EOF state host-side, not in slot 11.
- Do not implement PRINC line breaking now (width 1000 makes it unreachable); document it as a deviation and test that it is absent.

**D9. Not hit on this path** (verified by the walk):
- BLOCKED delivery: never fires.
- TYPE of RDCOM: still unsupported, but only BLO and DISPATCH would ask, and neither ran.
- The ADR-0049 default-REP error: only reached via HANDLE line 222 when XUNM is in WINNERS; XUNM is `"MTRZORK"`.
- LISTEN reading `<VALUE REP>` (LVAL first, per manual and Confusion) versus ADR-0049's GVAL: no LVAL of REP exists on the path. Note it in the ADR.

## Limits

- Pipe-mode probes. The golden is pty-mode; D2 reconciles the two.
- The trace wrapper changes SUBR values into FUNCTIONs. The game output was unchanged, but frame-sensitive SUBRs were deliberately not wrapped.
- The scratch walk's stubs are minimal and are not a specification. Its clock was not fixed, so RANDOM differs, although no RNG-visible text appears in the scenario.
- Only the six-command, quit/y and edge scenarios were exercised. Death (JIGS-UP RESET) and SCRIPT/SAVE/RESTORE verbs were not.
- Sandbox side note: the sandbox shows char-device stub entries under `s6-rep/.claude/` (dated Oct 13, untracked). This investigation did not create or modify them.
