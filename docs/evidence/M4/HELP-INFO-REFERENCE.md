# M4 S10 reference: OPEN "READ", FILE-LENGTH, file READSTRING, CLOSE; scenario `help-info`

Date: 2026-11-24. Read-only reference investigation for issue #171
(maintainer decision 2026-11-24, "Read-only allowlist"). Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before and
after every capture (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; game directory
`mdlzork_771212/patched_confusion`, copied fresh under `$TMPDIR` for every run
(never the upstream checkout as the writable cwd). Fixed clock: shim
`scripts/reference/fixed_time.c` (sha256 `d1fa8652…b925`), LD_PRELOAD,
`MDL_FIXED_EPOCH=250776000`, `TZ=UTC`.

The two pinned files (in `patched_confusion/MDL/`):

| File | Bytes | sha256 | Content |
|---|---|---|---|
| `MADADV.HELP` | 4274 | `00fc24d63869f94d9715ca43d53018c5019ef051d9d6074e113cc5bdafbf2ae1` | 96 LF-terminated lines, ASCII 10 and 32–126 only, no `!`, no NUL/^C; line 88 holds two `>` (`'attack <villain> with <weapon>'`) |
| `MADADV.INFO` | 1527 | `36e6eead79f88df939fbe15ef23856f6ba7e594753b994440c38ed1fb2434aa2` | 23 lines, same character set, no `>` |

## Captures

| Command | Exit | Record |
|---|---|---|
| `python3 -I scripts/probe_file_read_reference.py docs/evidence/M4/file-read-probe.json` | 0 | 53 cases, `file-read-probe.json` (sha256 `693a16e5…5436`); script sha256 `03d3f9c1…b5fd` |
| `python3 -I scripts/probe_help_info_scenario_reference.py docs/evidence/M4/help-info-reference.json` | 0 | 19 runs (T1, T1b, X1, P00–P07, D00–D07), `help-info-reference.json` (sha256 `24fbe2b1…6942`); T1 stdout sha256 `90e5ebfc…941f`; script sha256 `cb7c202c…a0b9`; scenario file sha256 `d3f000d7…183b` |
| same, second capture to `$TMPDIR/help-info-reference-2.json` (not committed) | 0 | transcripts, every case's stdout sha256, diagnostic checkpoints and end checkpoints identical to the committed capture |

Primitive cases run the bare interpreter in a fresh game copy (no game
load); none changed a file in its copy (`no_primitive_case_changed_a_file`).
Two cases create a small extra file in their copy only (`MDL/BANG.TXT`,
`MDL/CRLF.TXT`). The game case and every scenario run write only what SAVE-IT
and QUIT write natively (`MDL/MADADV.SAVE`, `MDL/ZORK.LOG`), in the copy.

## Findings (pinned Confusion)

**MUDDLE** is 101, so SAVE-IT sets `DEV` "DSK" and `SNM` "MDL"
(77rooms.mud:20-21) and FILE-TO-TTY's OPEN is
`<OPEN "READ" "MADADV" "HELP" "DSK" "MDL">` (and "INFO").

**OPEN "READ"** (`open-*`):
- The 5-STRING form on an existing file returns a CHANNEL of 19 elements:
  `#CHANNEL [3 "READ" "MADADV" "HELP" "DSK" "MDL" "MADADV" "HELP" "DSK"
  "<absolute host path of the game copy>/MDL" 0 0 #LOSE *0000000000000000000000*
  0 0 0 0 10 0]`: element 1 a channel number (3 for the first open file, 4
  for a second one open at the same time), 2 the mode, 3–6 the requested
  names, 7–10 the "real" names (element 10 is the **absolute host directory**),
  11 a status (0; 1 after end of file), 12 0, 13 a LOSE word, 14–17 0, 18
  10, 19 0.
- File spec = `directory "/" name1 "." name2`, relative to the process cwd;
  **the device is not part of it** (`"FOO"` opens the same file).
- **No case folding**: `"madadv" "help"` and directory `"mdl"` return
  `#FALSE ("No such file or directory" "MDL/madadv.help" 2)` (resp.
  `"mdl/MADADV.HELP"`).
- An absent file: `#FALSE ("No such file or directory" "MDL/NOSUCH.FILE" 2)`
  (FILE-TO-TTY prints `File not found.`).
- 4- and 3-argument forms default the directory to the absolute cwd
  (FALSE here); the one-file-spec form `"MDL/MADADV.HELP"` and a directory
  `"MDL/../MDL"` open the file natively; a directory name as file: FALSE.
- Two OPENs of the same file give two distinct channels (`==?` FALSE), each
  readable.

**FILE-LENGTH** (`file-length-*`, `err-file-length-*`): the length in
**characters (= bytes)**: 4274 for HELP, 1527 for INFO (not 36-bit words:
855 / 306 would be words). TYPE FIX. Unchanged after reading (1527 after a
100-character read). Errors: `<FILE-LENGTH .INCHAN>` MDL ERROR
`FILE-LENGTH-UNAVAILABLE`; no argument `TOO-FEW-ARGUMENTS-SUPPLIED`; two
arguments `TOO-MANY-ARGUMENTS-SUPPLIED`; after CLOSE `CHANNEL-CLOSED`; a
STRING argument **crashes the interpreter** (exit −11, SIGSEGV).

**READSTRING from a file channel** (`readstring-*`):
- FIX third argument = a count: exactly that many characters are read and
  stored from position 1; the rest of the buffer is unchanged (`10` stores
  "Useful com", the remaining 90 stay NUL); the next read continues after
  them. Count 0 returns 0 and reads nothing. Count larger than the buffer
  (`<ISTRING 5>`, count 10) returns **10** and writes past the buffer (the
  printed buffer shows 5); a negative count **crashes** (SIGSEGV).
- Two arguments: reads until the buffer is full (100).
- STRING stop: reads until the buffer is full, a stop character is read
  (consumed, not stored: `Useful commands` 15, then the blank line 0, then
  69), or end of file.
- The game's last chunk: after 15 × 100 by count, `<READSTRING .B .C ,BREAKS>`
  (`,BREAKS` = `<STRING <ASCII 3> <ASCII 0>>`, neither occurs in the files)
  returns **27** at end of file, stores those 27 characters and leaves the
  other 73 characters of the buffer from the previous chunk; the CHANNEL's
  status element 11 becomes 1.
- A count read that meets end of file returns the partial count (27) and also
  sets status 1. **Any READSTRING after end of file** (count or stop) prints
  `Error: Unexpected EOF` on stderr and drops to LISTENING-AT-LEVEL 1 (a host
  error, not an MDL ERROR); the channel can still be CLOSEd.
- One count read larger than the file (2000 on INFO) returns 1527.
- `!` **is an escape in file input too** (file `a!b!!c!<LF>de<LF>`, 12
  bytes → 8 `ab!c<LF>de<LF>`), exactly as on the terminal (S13 part A); the
  pinned files contain no `!`.
- CR LF are stored raw (`ab<CR><LF>cd` → 6); FILE-LENGTH 6.
- After CLOSE: `Attempt to read from closed channel` (host error).

**Output to a READ channel**: `<PRINC "x" .C>`, `<PRINTSTRING "x" .C>`,
`<CRLF .C>` fail (`Channel for PRINC must be output channel`, …).

**PRINTSTRING with a count** (`printstring-count`): `<PRINTSTRING "abcdef"
,OUTCHAN 3>` writes `abc` and returns the STRING `"abcdef"`; 0 writes
nothing; a count larger than the STRING (5 on `"abc"`) writes the whole
STRING, no error.

**CLOSE**: returns the same CHANNEL (`==?` T, TYPE CHANNEL); the CHANNEL then
prints `#CHANNEL [0 "READ" "MADADV" "HELP" "DSK" "MDL" "" "" "" "" 0 …]`
(element 1 → 0, elements 7–10 → `""`, status kept). **A second CLOSE returns
the channel again**, no error. `<CLOSE>` → `Not enough args to CLOSE`; a
non-CHANNEL → `Argument to close must be of type CHANNEL` (host errors).

**FILE-TO-TTY** (the game's definition typed into the bare interpreter):
writes CRLF, the whole file, CRLF; returns CLOSE's value (the CHANNEL); sets
TELL-FLAG T. On an absent file it TELLs `File not found.`.

## Scenario `help-info`

`<FLOAD "77loadall.mud">`, `<SAVE-IT>`, then `north`, `help`, `east`,
`info`, `open window`, `?`, `west`, `score`.

| # | Command | Native response |
|---|---|---|
| 2 | `help` | `\n` + the 4274 bytes of MADADV.HELP + `\n` (4276 characters) |
| 4 | `info` | `\n` + the 1527 bytes of MADADV.INFO + `\n` |
| 6 | `?` | identical to `help` (LEX maps `?` to HELP; the file is opened, read and closed again) |
| 8 | `score` | 10 points in 8 moves (help, info and `?` each count as a move) |

- Prompts: T1 holds 14 `>` characters but exactly 10 line-initial ones
  (n + 2); every Pkk holds k + 2 line-initial prompts, so the runner splits
  prompts at line-initial `>` for this scenario (`prompt_split`
  `line-initial`).
- Every prefix's end-of-input tail is exactly `Beg pardon?\n>`
  (`prefix_runs_with_non_standard_eof_tail` empty).
- X1's file events: FILE-LENGTH 4274, 1527, 4274; 102 file READSTRINGs (99 ×
  100, 74, 27, 74); three CLOSEs, each returning a CHANNEL. RANDOM: one draw
  (START).
- Checkpoints (HERE, AOBJS, MOVES, RAW-SCORE, DEATHS, TELL-FLAG and the 100
  character codes of `,INBUF`) at every terminal READSTRING entry. After
  `help` the shared `,INBUF` holds the last 74 characters of the help file
  followed by 26 characters of the previous chunk; RDCOM's next command read
  overwrites only its own characters (e.g. `east` + the rest of that text).
  TELL-FLAG is FALSE at every entry.

Confusion is GPLv3 and used only as a behaviour reference; no Confusion
source was copied.
