# Manual DrRacket verification (launcher, S12)

Required by the maintainer's M4 review (2026-11-23): the DrRacket behaviour of
`zork/main.rkt` must be verified manually, not inferred from the automated CLI
and break tests.

| Check | Result | Source |
|---|---|---|
| Loading the game in DrRacket (`zork/main.rkt`) | **Works** | Maintainer report, 2026-11-23 |
| `#lang mdl` modules in DrRacket | **Work** | Maintainer report, 2026-11-23 |
| `(run-zork)`, then `quit` / `y` returns control to the DrRacket REPL | NOT YET REPORTED | — |
| Stop interrupts a running game without terminating DrRacket | NOT YET REPORTED | — |

Automated stand-ins that already pass (not a substitute for the two open rows):
`tests/launcher_test.rkt` (run-zork returns `'quit`; a `break-thread` during
the blocking read ends the game thread with `exn:break` and the test process
continues).
