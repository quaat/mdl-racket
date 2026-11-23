# M4 S1 reference capture: enter the house and open the cellar

Status: **reference captured** (pinned native Confusion, 2026-11-23). This is a
reference record for M4 scenario 1. It makes no PLAYABLE or M4-gate claim.
Data: [`house-cellar-reference.json`](house-cellar-reference.json). Scenario:
[`tests/scenarios/house-cellar.json`](../../../tests/scenarios/house-cellar.json).
Capture tool: `scripts/probe_house_cellar_reference.py`, which uses the
`run_case` protocol of `scripts/probe_session_reference.py`.

## Inputs

| Item | Value |
|---|---|
| Interpreter | `.cache/build/confusion_patched/mdli`, sha256 `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` (same hash before and after the capture; not rebuilt) |
| Upstream | mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3` (= `sources.lock.json`), game dir `mdlzork_771212/patched_confusion` |
| Clock | `scripts/reference/fixed_time.c` (sha256 `d1fa8652…ab925`) compiled for each capture and loaded with LD_PRELOAD, `MDL_FIXED_EPOCH=250776000`, `TZ=UTC`, microseconds 0 |
| Working copy | a new `$TMPDIR/house-cellar-probes/<case>-*/game` copy for each run, with `SAVEFILE/ZORK.SAVE` removed before boot. Nothing ran inside `.cache/upstream` |
| Entry | `<FLOAD "77loadall.mud">`, `<SAVE-IT>`; the commands go to stdin in pipe mode, followed by EOF |

## Commands

From West of House (WHOUS):

| # | Command | Why (source) |
|---|---|---|
| 1 | `north` | WHOUS → NHOUS (`77dung.mud:158-172`) |
| 2 | `east` | NHOUS → EHOUS (`77dung.mud:172`) |
| 3 | `open window` | WIND1 → WINDOW-FUNCTION → OPEN-CLOSE sets `KITCHEN-WINDOW!-FLAG` (`77act1.mud:39-60`) |
| 4 | `west` | EHOUS `WEST` CEXIT KITCHEN-WINDOW → KITCH, RVAL 10 (`77dung.mud:189,194-200`) |
| 5 | `west` | KITCH → LROOM (`77dung.mud:198`) |
| 6 | `take lamp` | LAMP is TAKEBIT, light -1 (off) (`77dung.mud:343-348`) |
| 7 | `move rug` | RUG MOVE: ORAND ← T, TRO DOOR OVISON (`77act1.mud:303-318`) |
| 8 | `open trap door` | adjective TRAP + noun DOOR → object DOOR → TRAP-DOOR, COND-OPEN (`77act1.mud:211-231`, `77dung.mud:1654`) |
| 9 | `turn on lamp` | TURN `ON` syntax → TURN-ON / LAMP-ON; LANTERN enables the lamp clock (`77dung.mud:2807-2814`, `77act1.mud:1859-1872`) |
| 10 | `down` | LROOM `DOWN` CEXIT TRAP-DOOR → CELLA, RVAL 25; CELLAR closes and bars the door (`77dung.mud:326,374-386`, `77act1.mud:270-283`) |
| 11 | `score` | SCORE |

The reference accepted every command at the first attempt, so no command
had to be adjusted. `west` (4) was chosen over `enter`: both name the same
CEXIT, and `west` is the backlog's first option. No shorter route exists:
the window is the only entry, and the lamp, rug and trap door are all in
LROOM.

## Transcript (T1; T1b byte-identical)

stdout sha256 `ef0753277d267d55f9bf199b21ae74c5b5bac5ff05f1625f346e3ca79227fda6`,
exit 0. stderr is `Error: Unexpected EOF\n`, from the EOF after `score`.
The game text in canonical form (CR removed), one prompt `>` per command:

```
Welcome to Dungeon.
This version created December 12.

You are in an open field west of a big white house, with a boarded
front door.
There is a small mailbox here.
>You are facing the north side of a white house.  There is no door here,
and all the windows are barred.
>You are behind the white house.  In one corner of the house there
is a small window which is slightly ajar.
>With great effort, you open the window far enough to allow entry.
>You are in the kitchen of the white house.  A table seems to have
... (kitchen description, sack, bottle, "The glass bottle contains:" / " A quantity of water")
>You are in the living room.  There is a door to the east, a wooden
... (rug, trophy case, lantern, "US NEWS & DUNGEON REPORT dated 12/12/77", sword)
>Taken.
>With a great effort, the rug is moved to one side of the room.
With the rug moved, the dusty cover of a closed trap-door appears.
>The door reluctantly opens to reveal a rickety staircase descending
into darkness.
>The lamp is now on.
>You are in a dark and damp cellar with a narrow passageway leading
east, and a crawlway to the south.  On the west is the bottom of a
steep metal ramp which is unclimbable.
The trap door crashes shut, and you hear someone barring it.
>
Your score would be 35 [total of 500 points], in 11 moves.
This score gives you the rank of Amateur Adventurer.
>Beg pardon?
>
```

The raw bytes are in the JSON (`cases[T1].stdout_raw`; also
`transcript.game_output_raw`, which keeps the CRs). The game sources have
CRLF line ends, so multi-line string literals print a CR before their inner
LF. The newspaper date `12/12/77` comes from the fixed clock.
`transcript.split` holds the response to each command.

Prefix runs P00–P10 hold the first k commands followed by EOF. Each one's
game text equals T1 cut after prompt k+1, followed by T1's own
end-of-input reply `Beg pardon?\n>` (check `prefix_runs_consistent_with_t1`).

## RANDOM draws (diagnostic run X1)

X1 wraps RANDOM and READSTRING with typed forms after FLOAD and before
SAVE-IT. Both wrappers pass through to the original SUBR and only log to
`DIAG.LOG`, outside the game copy. The game text of X1 (from
`Welcome to Dungeon.`) is **byte-identical** to T1's
(`diag_game_part_equals_t1_game_part_bytes: true`).

| Draw | Call | Result | When |
|---|---|---|---|
| 0 | `<RANDOM 10438660480>` (START seed = DSKDATE, `77rooms.mud:291`) | 16566282405 | before the first prompt |

There are **no other RANDOM calls** on the whole path. Every room the
scenario enters is entered for the first time, so ROOM-INFO's `<PROB 80>`
re-entry draw (`77rooms.mud:446,523`) never runs. No demon, PICK-ONE or
thief draw happens either. So the scenario's text and state depend on the
clock only through the seed and the newspaper date.

## State checkpoints (X1, read-only, at each READSTRING entry)

A checkpoint is logged at every READSTRING entry, that is, after the
previous command has been processed completely, including the clock
demons. It reads ROOM/ADV/OBJECT fields through their NEWSTRUC offsets and
DEFMACs, plus `LIT?` and `MEMQ`, all of them pure. The object and room
handles come from FIND-OBJ/FIND-ROOM on existing names before SAVE-IT,
which is a pure lookup in that case (`77defs.mud:470-500`).

| CP (after cmd) | HERE | AOBJS | K-WINDOW | RUG ORAND | DOOR OVIS? / OFLAGS / OTOUCH? | TRAP-DOOR | LAMP OLIGHT? | LAMP in LROOM | LIT? | RAW-SCORE / ASCORE | MOVES |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 (boot) | WHOUS | () | F | F | F / 72 / F | F | -1 | T | T | 0 / 0 | 0 |
| 1 north | NHOUS | () | F | F | F / 72 / F | F | -1 | T | T | 0 / 0 | 1 |
| 2 east | EHOUS | () | F | F | F / 72 / F | F | -1 | T | T | 0 / 0 | 2 |
| 3 open window | EHOUS | () | **T** | F | F / 72 / F | F | -1 | T | T | 0 / 0 | 3 |
| 4 west | **KITCH** | () | T | F | F / 72 / F | F | -1 | T | T | **10 / 10** | 4 |
| 5 west | **LROOM** | () | T | F | F / 72 / F | F | -1 | T | T | 10 / 10 | 5 |
| 6 take lamp | LROOM | **(LAMP)** | T | F | F / 72 / F | F | -1 | **F** | T | 10 / 10 | 6 |
| 7 move rug | LROOM | (LAMP) | T | **T** | **T / 73** / F | F | -1 | F | T | 10 / 10 | 7 |
| 8 open trap door | LROOM | (LAMP) | T | T | T / 73 / F | **T** | -1 | F | T | 10 / 10 | 8 |
| 9 turn on lamp | LROOM | (LAMP) | T | T | T / 73 / F | T | **1** | F | T | 10 / 10 | 9 |
| 10 down | **CELLA** | (LAMP) | T | T | T / 73 / **T** | **F** | 1 | F | **T** | **35 / 35** | 10 |
| 11 score | CELLA | (LAMP) | T | T | T / 73 / T | F | 1 | F | T | 35 / 35 | 11 |
| 12 (EOF read) | = CP 11 | | | | | | | | | | 11 |

(F = `#FALSE ()`; `RSEEN?` of HERE is T at every checkpoint.) Every room on
the path except CELLA has RLIGHT? set. In the cellar, LIT? is true only
because the lamp is lit (OLIGHT? 1). CELLAR resets `TRAP-DOOR!-FLAG` and
sets the door's OTOUCH?. The EOF read (`Beg pardon?`) does not count a move
or change any recorded field (CP 12 = CP 11).

## File-system effects

In every run the only file changed in the disposable game copy is
`MDL/MADADV.SAVE`, written by SAVE-IT (`77rooms.mud:8-9`; the same SAVE
artifact as house-boot). Its post-run hash differs on every run, so the
save image is not byte-deterministic. It is an output and is never
compared. No `MDL/ZORK.LOG` or other file is written: the scenario never
quits, so RECORD does not run. X1 also writes its `DIAG.LOG`, outside the
game copy. Our runtime writes nothing (ADR-0048 in-session SAVE record;
checked by the S1 test's security guard).

## Reproduce

```
python3 -I scripts/probe_house_cellar_reference.py $TMPDIR/house-cellar-reference.json
```

Exit 0 requires T1 == T1b (bytes), X1's game text == T1's, 13 checkpoints,
and every prefix run consistent with T1. `recorded_at`, the `$TMPDIR` paths,
`elapsed_seconds` and the MADADV.SAVE hashes vary between captures. The
transcripts, draws and checkpoints do not.
