# `!` in READSTRING terminal input: pinned Confusion reference observations

Read-only reference investigation, 2026-11-23. This closes the open question
recorded in SEMANTICS ("M3 interactive terminal I/O", READSTRING) and in
ADR-0050 §3. No implementation, test, or upstream file was changed.

| Item | Value |
| --- | --- |
| Repository commit probed from | `45c387f` (branch `evidence/m3-session-probes`) |
| Interpreter | `.cache/build/confusion_patched/mdli`, sha256 `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` (checked before the run and before every case) |
| Upstream | mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`, mit_zork `d94501340842e006791fce0757dc0043b8ec8916` |
| Script | `docs/evidence/M3/member-bang-probe.py` (suite `bang`) |
| Raw evidence | `docs/evidence/M3/readstring-bang-probe.json` (40 cases; every exit status 0) |
| Clock / RNG | game cases: fixed_time shim, `MDL_FIXED_EPOCH=250776000`, `TZ=UTC` (the approved house-boot settings); the banner reads "This version created December 12." |

## Method

```
export MDL_FIXED_TIME_C=<repo>/.claude/worktrees/agent-a64a330470b6b2df4/scripts/reference/fixed_time.c
python3 -I docs/evidence/M3/member-bang-probe.py bang docs/evidence/M3/readstring-bang-probe.json
```

Exit status 0. The run was repeated twice with identical results.
`fixed_time.c` comes from the #131 BOOT-REF worktree. The script compiles it
with gcc into `$TMPDIR/mb-probe-work/`.

- **Direct cases.** One `mdli` per case, in a fresh empty cwd under
  `$TMPDIR/mb-probe-work/`. Each input defines
  `RS = <STRING <ASCII 27> <ASCII 13> <ASCII 10>>`, which is the game's
  READER-STRING (77rooms.mud:598). It then fills a buffer
  `<ISTRING n !\.>` and evaluates
  `<PROG () <PRINT <READSTRING .B ,INCHAN ,RS>> <PRINT .B> <PRINT <MAPF ,VECTOR ,ASCII .B>> …>`.
  The typed bytes follow the PROG's closing `>` on the same line (the REPL
  reader does not consume them; S7-frontier `readstring-bang-and-case`). The
  input ends with `<QUIT>` unless the case tests EOF.
- **Game cases.** The cwd is a fresh byte copy of `patched_confusion/`. The
  input is `<FLOAD "77loadall.mud">\n<SAVE-IT>\n` followed by the typed
  bytes, so RDCOM's own `<READSTRING .INBUF ,INCHAN .STR>` (77rooms.mud:616)
  reads the line. INBUF is `<ISTRING 100>` (77rooms.mud:1539). The only file
  written is `MDL/MADADV.SAVE` inside the temporary copy.
- **pipe vs pty.** The default is a stdin pipe, as the host loop uses.
  `pty-*` cases run the same input on a pexpect pseudo-terminal with ECHO
  off, where stdout and stderr share the pty. EOF is `^D` (0x04, VEOF) at
  the start of a line.

The Confusion source (`mdl_read.cpp`: `mdl_read_1_char`, `mdl_read_string`)
was read to choose the probes and was not copied. Its logic agrees with
every observation: on `!`, the next byte is read and returned tagged as
escaped. READSTRING compares the low byte with the stop string, then
stores that byte.

## Manual

- §11.4.1.2 READSTRING
  (<https://mdl-language.readthedocs.io/en/latest/11-input-output/>):
  "*stop* tells when to stop inputting: if a `FIX`, read this many
  `CHARACTER`s (fill up *buffer* by default); if a `STRING`, stop reading if
  any `CHARACTER` in this `STRING` is read (don't include this `CHARACTER`
  in final `STRING`)."
- §11.1.1, §11.8: terminal input follows ITS conventions (rubout, `^D`,
  `^L`, `^@`, Teco-like CR handling). **The manual says nothing about `!` in
  terminal input.** `!` appears only as reader syntax (`!\c`, `!.X`,
  `!,X`, `!<…>`) and in PRINC's description of `!\`. The `!` escape is a
  Confusion stdio behaviour (every stdin/file channel read goes through it);
  it is not documented MDL semantics.

## Observations: direct READSTRING (pipe)

The count is READSTRING's FIX result. "Stored" lists the buffer's
`<ASCII …>` codes in order; `.` (46) is the untouched fill.

| Case | Typed bytes (hex) | Read 1: count, stored | Read 2 / 3 | Notes |
| --- | --- | --- | --- | --- |
| bang-mid | `41 62 21 63 44 0a` (`Ab!cD⏎`) | 4, `65 98 99 68` "AbcD" | – | `!` removed; case kept |
| bang-double | `21 21 0a` | 1, `33` "!" | – | `!!` gives one `!` |
| bang-double-between | `61 21 21 62 0a` | 3, "a!b" | – | |
| bang-multiple | `21 61 21 62 21 63 0a` | 3, "abc" | – | each `!` is dropped and not counted |
| bang-before-lf | `61 62 21 0a 58 59 0a` | 2, "ab" | 2, "XY" | **escaped LF still stops**; LF consumed, not stored |
| bang-before-cr | `61 62 21 0d 58 59 0a` | 2, "ab" | 2, "XY" | escaped CR stops |
| bang-before-crlf | `61 62 21 0d 0a 63 64 0a` | 2, "ab" | 0 (LF) / 2 "cd" | as unescaped CRLF: an extra empty read |
| bang-before-esc | `61 62 21 1b 58 59 0a` | 2, "ab" | 2, "XY" | escaped ESC (altmode) stops |
| bang-before-tab | `61 21 09 62 0a` | 3, `97 9 98` | – | escaped non-stop control char stored |
| bang-before-backslash | `61 21 5c 62 0a` | 3, `97 92 98` | – | |
| backslash-plain | `61 5c 62 0a` | 3, `97 92 98` | – | `\` is not an escape in READSTRING |
| bang-before-eof | `61 62 21` (EOF) | 3, "ab!" (`97 98 33`) | stderr `Error: Unexpected EOF` | **trailing `!` before EOF is stored literally** |
| bang-only-eof | `21` (EOF) | 1, "!" | stderr `Error: Unexpected EOF` | |
| bang-buffer-boundary-last-slot | buffer 3; `61 62 21 63 64 0a` | 3, "abc" | 1, "d" (buffer "dbc") | the `!c` pair takes one slot; the read stops when the buffer is full and the rest stays unread |
| bang-buffer-boundary-straddle | buffer 2; `61 62 21 63 64 0a` | 2, "ab" | 2, "cd" | the next read starts at `!` and escapes as usual |
| bang-buffer-boundary-2 | buffer 2; `61 21 62 63 0a` | 2, "ab" | 1, "c" (buffer "cb") | |
| bang-fix-stop | `<READSTRING .B ,INCHAN 3>`; `21 61 62 63 64 0a` | 3, "abc" | – (`d` goes back to the REPL, printed `d`) | a FIX stop counts stored chars; `!a` is one |

## Observations: non-ASCII and other bytes (pipe)

| Case | Typed bytes (hex) | Count, stored codes | Notes |
| --- | --- | --- | --- |
| nonascii-latin1 | `61 e9 62 0a` | 3, `97 -23 98` | byte stored raw; `<ASCII>` gives **-23** (signed char) |
| nonascii-utf8 | `61 c3 a9 62 0a` | 4, `97 -61 -87 98` | UTF-8 is not decoded: 2 bytes give 2 CHARACTERs |
| bang-before-nonascii | `61 21 e9 62 0a` | 3, `97 -23 98` | |
| nul-and-del | `61 00 62 7f 63 0a` | 5, `97 0 98 127 99` | NUL and DEL stored raw; PRINT shows `^@`, `^?` (written as `^` + 0xBF in the raw bytes) |

Confusion accepts every byte value without error.

## Observations: pty vs pipe

`pty-bang-mid`, `pty-bang-double`, `pty-bang-before-lf`,
`pty-bang-before-cr`, `pty-bang-before-esc`, `pty-bang-before-eof`
(`61 62 21 04 04`), `pty-bang-buffer-boundary`, and `pty-nonascii-latin1`
give **the same counts and stored codes** as the pipe cases. The only
differences are transport artefacts:
- Output: ONLCR turns the printed RS string `"^[\r\n"` into an extra blank
  line in canonical form. stderr (`Error: Unexpected EOF`) is interleaved in
  the same stream.
- Input: ICRNL maps a typed CR to LF before Confusion sees it. Both are stop
  characters, so the result does not change. In canonical mode, one `^D`
  after `ab!` pushes the partial line and a second `^D` gives EOF; the
  result matches pipe EOF.

Confusion sets no termios mode. The `!` handling is in its stdio read
routine, independent of `isatty` (`isatty` only selects DEVN `"TTY"` or
`"DSK"`).

## Observations: the game's RDCOM (FLOAD + SAVE-IT, fixed clock)

Output after "This version created December 12." and the West of House
description:

| Case | Typed bytes (hex) | Game output |
| --- | --- | --- |
| game-baseline-north | `6e 6f 72 74 68 0a` | `>You are facing the north side of a white house. …` then `>Beg pardon?` `>` + `Error: Unexpected EOF` |
| game-bang-mid-word | `6e 6f 72 21 74 68 0a` (`nor!th`) | identical to the baseline |
| game-bang-first | `21 6e 6f 72 74 68 0a` (`!north`) | identical to the baseline |
| game-mixed-case-bang | `41 62 21 63 44 0a` (`Ab!cD`) | `>I don't know the word ABCD` |
| game-bang-double | `21 21 0a` | `>Huh?` |
| game-bang-before-lf | `…68 21 0a 77 65 73 74 0a` (`north!⏎west⏎`) | north, then `>West of House …`: the escaped LF still ends the command |
| game-bang-before-esc | `…68 21 1b 77 65 73 74 0a` | the same as above: the escaped ESC still ends the command |
| game-bang-before-eof | `6e 6f 72 74 68 21` (EOF) | north executes (INBUF "north!", count 6); then **no** `Beg pardon?`: the next READSTRING raises `Error: Unexpected EOF` at once |
| game-buffer-boundary | 99×`x`, `21 79 7a 0a`, `look⏎` | `>I don't know the word XXXXX` (100 chars, `!y` in slot 100), `>I don't know the word Z`, then `look` |
| game-nonascii | `6e 6f 72 e9 74 68 0a`, `north⏎` | `>I don't know the word NOR\xe9T` (byte kept raw, LEX truncates to 5), then north |
| pty-game-bang-mid-word | `nor!th⏎` then `^D` | same as pipe (north, `Beg pardon?`, `Error: Unexpected EOF`) |

The game's stop string is READER-STRING = ESC CR LF (77rooms.mud:598). RDCOM
(77rooms.mud:616) and ECHO-ROOM (77act1.mud:1068-1072) use it.

## Precise rule (as observed)

Reading proceeds one input unit at a time until the buffer view is full, a
stop character is read, or EOF:
1. A unit is either one byte `c`, or `!` followed by a byte `c` (the escape
   pair). Escaping applies to every byte, including `!` itself, control
   characters, and bytes above 127.
2. An escape pair yields `c`. The `!` is never stored or counted, and the
   pair uses one buffer slot.
3. The stop-character test uses `c` **whether or not it was escaped**. An
   escaped CR, LF, or ESC still stops the read, is consumed, and is not
   stored. `!` cannot protect a stop character.
4. A `!` immediately followed by EOF is stored as a literal `!` and counted.
   That read then returns at EOF and sets the EOF state, so the next
   READSTRING meets end of input. This is the D3 "mirror, then strict" path.
5. If the buffer is full before a unit begins, that unit stays unread.
   Escape pairing resumes on the next READSTRING.
6. The count returned equals the characters stored.
7. pipe and pty give the same results.

## Recommendation for the implementing slice

Mirror rules 1-6 for ASCII input on the session input port, replacing ADR-0050
§3's "`!` is a strict error". Required tests (from this evidence):
`Ab!cD` gives 4 "AbcD"; `!!` gives 1 "!"; `a!!b` gives 3 "a!b"; `!a!b!c`
gives 3 "abc"; `ab!⏎XY⏎` gives 2 "ab" then 2 "XY"; the same for escaped CR
and ESC; `ab!⏎` with a CRLF tail gives 2 / 0 / 2; `ab!` at EOF gives 3
"ab!" and then the D3 exhausted error; buffer 3 with `ab!cd⏎` gives 3 "abc"
then 1 "d"; buffer 2 with `ab!cd⏎` gives "ab" then "cd"; `a!\tb` stores TAB;
and `\` is not an escape.

Keep these as they are now (no loosening):
- **Bytes above 127** (with or without a preceding `!`). Confusion stores
  them as raw bytes and its `ASCII` gives negative values (-23 for 0xE9).
  UTF-8 is split into bytes. Mirroring this would need a byte-level CHARACTER
  model the runtime does not have; record it as a known deviation.
- Control characters. Confusion stores NUL, DEL, and TAB raw. The runtime
  at `45c387f` (`mdl/runtime/core.rkt`, READSTRING loop) already stores
  codes 0-127 other than `!` and stop characters, so it already matches
  here. An escaped control character must then store the character, as
  Confusion does (`a!\tb` gives `97 9 98`).
- Implementation note: the runtime reads with Racket `read-char` (UTF-8
  decoding). A lone 0xE9 byte decodes to U+FFFD and a UTF-8 é to U+00E9;
  both are > 127 and refused. The character after a `!` must pass the same
  > 127 check. A `!` followed by EOF must store `!`, count it, and set the
  EOF flag (rule 4).
- An escaped byte above 127 (`!é`) stays a strict error. The escape does not
  make an invalid byte valid.

Open or not determined:
- Whether the historical ITS MDL interpreted `!` in terminal input at all.
  The manual is silent, so this behaviour is Confusion's. Following it is the
  maintainer's decision, not a manual-backed fact.
- Console line editing (rubout, `^D`, `^L`, `^@` as in §11.1.1) was not
  probed. Confusion implements none of it in READSTRING beyond the kernel
  pty line discipline.

Security and licensing: probes ran locally on temporary copies, with no
network and no evaluator exposure. No GPLv3 code was copied; only outputs
are recorded.
