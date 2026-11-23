# Manual DrRacket verification (launcher, S12)

Required by the maintainer's M4 review (2026-11-23): the DrRacket behaviour of
`zork/main.rkt` must be verified manually, not inferred from the automated CLI
and break tests.

| Check | Result | Source |
|---|---|---|
| Loading the game in DrRacket (`zork/main.rkt`) | **Works** | Maintainer report, 2026-11-23 |
| `#lang mdl` modules in DrRacket | **Work** | Maintainer report, 2026-11-23 |
| `(run-zork)`, then `quit` / `y` returns control to the DrRacket REPL | **PASS** | Maintainer run, 2026-11-23 (transcript below) |
| Stop interrupts a running game without terminating DrRacket | NOT YET REPORTED | — |

Automated stand-ins that already pass (not a substitute for the open Stop row):
`tests/launcher_test.rkt` (run-zork returns `'quit`; a `break-thread` during
the blocking read ends the game thread with `exn:break` and the test process
continues).

## Maintainer run: quit returns control (2026-11-23)

DrRacket 7.9 [3m], language `racket/base` with debugging, memory limit
128 MB; `(run-zork)` with the defaults (real clock, local zone, notice on).
Observed: the `[launcher]` preview notice; the 12 `… loaded` lines of the
original FLOAD chain; `Welcome to Dungeon.` / `This version created
November 23.` (DSKDATE from the real session clock, as intended for local
play) and the West of House description; `>quit` → `Your score would be 0
[total of 500 points], in 1 move.` / `This score gives you the rank of
Beginner.` / `Do you wish to leave the game? (Y is affirmative): ` → `y`.
`run-zork` then returned `(zork-result 'quit '() #f)` and the DrRacket REPL
prompt came back: the game's own FINISH → RECORD → QUIT path ended the
session without exiting DrRacket and with no MDL error recorded. The quit
prompt, score line and move counting match the native reference
(docs/evidence/M3/SESSION-QUIT-REFERENCE.md).

Still open: pressing Stop during a running game.
