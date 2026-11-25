# M4 Phase 2: death and recovery scenarios (grue-resurrection, grue-refusal, troll-death)

Date: 2026-11-25. Branch `feat/m4-death-branches` from `main` `ab4fdfa`.
Epic #163 Phase 2 (death and recovery). Gate label: **scenario evidence on a
local branch** (three more native-parity scenarios, each under one fixed
clock and seed). Not a PLAYABLE, GAMEPLAY_RELIABILITY or M4 claim.

## Provenance

| Item | Value |
|---|---|
| Upstream game | `mdlzork` bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3 (`sources.lock.json`), `mdlzork_771212/patched_confusion`, unmodified |
| Pinned reference | `.cache/build/confusion_patched/mdli`, sha256 `6df359f6…b789`, unchanged before and after every capture (checked by the probe and with `sha256sum`); `make reference-build` not run |
| Clock / RNG | fixed epoch 250776000 (1977-12-12 12:00 UTC), TZ UTC; START seeds RANDOM from DSKDATE (seed 10438660480); no RANDOM override, no seed search |
| Native protocol | `scripts/probe_death_scenario_reference.py NAME OUT.json`: a fresh copy of the game directory under `$TMPDIR` for every run, pipe mode (quitting runs write MDL/ZORK.LOG there, never in `.cache/upstream`) |
| Ours | Racket v7.9 [bc]; the shared runner `tests/m4_scenario_runner.rkt`, guarded (no write or delete, empty cwd, game-directory hashes unchanged) and watchdogged |

## What "patched" meant (F12)

The inventory's run F12 is labelled "grue death, patched". That is the
game's own word: JIGS-UP (77rooms.mud:870) asks "Do you want me to try to
patch you?" and `y` accepts (resurrection). Nothing was patched: F12 ran on
the unmodified pinned sources under the standard fixed clock and seed, and
so do these scenarios. Nothing non-standard was needed.

## Scenarios

| Scenario | Target | Commands | Native finding (details: reference records) |
|---|---|---|---|
| grue-resurrection | `test-m4-grue-resurrection` | 20 | F12 extended with carried possessions. Death by grue in the dark attic (WALK's PROB 75), `y`: forest, empty handed; lamp -> living room, sword -> kitchen, bottle -> clearing, sack -> forest (RANDOM-LIST); the walk back sees them. Prefix 11 (end of input at the question) quits: stale `n` of `north` in INBUF. [Reference](GRUE-RESURRECTION-REFERENCE.md) |
| grue-refusal | `test-m4-grue-refusal` | 8 | F13 unchanged (T1 sha256 equals F13's). Death, `n`, FINISH <> (score, rank), RECORD, QUIT; `look` unread. Prefixes 6, 7, 8 quit; natively each writes MDL/ZORK.LOG. [Reference](GRUE-REFUSAL-REFERENCE.md) |
| troll-death | `test-m4-troll-death` | 24 | Unarmed in the troll room, eight `wait`: staggered (6th), light wound (7th: ASTRENGTH -1, CURIN on), killed (8th); `y`: forest, the lit lamp to the living room, wound and cure clock kept. Prefix 19 (end of input at the question) resurrects: stale `w`. [Reference](TROLL-DEATH-REFERENCE.md) |

Checkpoint fields (`tests/m4_death_checkpoint.rkt`, the reference's
DIAG-STATE): HERE, AOBJS, MOVES, RAW-SCORE, ASCORE, DEATHS, EGYPT-FLAG, the
trap door's OTOUCH?, ASTRENGTH, ASTAGGERED, CURIN CFLAG/CTICK, the troll's
OROOM/OCAPAC/FIGHTBIT, the lamp's OROOM/OCAN/OLIGHT?, the OROOM of the
sword, sack and bottle, and INBUF's 100 character codes (which show the
stale answer character). All are pure reads (GVALs, NTH, ANDB/CHTYPE,
FIND-OBJ on existing IDs, a snapshot of INBUF).

## Runner change (ADR-0062 amendment; opt-in, defaults unchanged)

The death scenarios needed two things the runner did not have:

1. **The death question is a READSTRING entry without `>`.** YES/NO's
   READSTRING follows `Do you want me to try to patch you?` (no CRLF, no
   prompt). `#:entry-prompts` declares these entries; the head of such an
   entry ends after its text, with no counted `>` before it. The `>` count
   stays strict: one per undeclared entry reached, plus the RDCOM prompt of
   the READSTRING that dies at end of input (`prompt-count`). The reference
   records `entry_prompts`, verified by its capture against a YES/NO
   wrapper (`yes_no_entries`), and the scenario must declare the same.
2. **A run can end by the game's QUIT.** `#:quit-prefixes` (with
   `#:quit-open-records`) declares the prefixes that end by FINISH ->
   RECORD -> QUIT; this is per prefix, not per scenario, because an end of
   input at the question answers with INBUF's stale first character (a
   refusal for both grue scenarios' prefix at the question). The reference
   records every prefix's native ending from its stderr (`endings`) and the
   declaration must equal it. A declared quit run must end with the host
   loop's `'quit` outcome and no MDL ERROR (never D3, never a strict
   failure), leave exactly the input after the quitting answer unread
   (grue-refusal T1: `look\n`), and have recorded exactly RECORD's two denied
   OPENs `("READB" "MDL/ZORK.LOG" 2)` and `("PRINT" "MDL/ZORK.LOG" 13)`
   (ADR-0055; as M3 S11). Every other run still ends by D3 with no OPEN
   recorded. The no-write guard is unchanged for all runs. The end checkpoint
   of a quit run is the native state at QUIT (the probe's QUIT wrapper
   checkpoint). Single-run mode observes entries 0..q (q = the entry whose
   answer quit, else n) and re-runs every declared quit prefix below n per
   prefix; a prefix beyond q that is not a declared quit is a strict error.

**Documented differences, not normalised:** natively a quitting run appends
one line to MDL/ZORK.LOG in its game copy (`native_zork_log` in the
reference, e.g. `0/500 points, 6 moves, 1 death.  In Attic. Died.`), and
every run rewrites MDL/MADADV.SAVE through SAVE-IT. This runtime writes
neither (ADR-0055 OPEN denial, ADR-0048 in-session SAVE); RECORD prints
nothing to the console, so the transcripts are byte-identical. The tests
assert the native file effects from the reference and our absence of writes
(the guard) separately.

## Results

| Command | Exit | Result |
|---|---|---|
| `raco test tests/m4_scenario_runner.rkt` | 0 | 57 unit tests (new: prompt-count, entry-prompt heads, strict failures, `#:ks`) |
| `racket tests/historical_grue_refusal_test.rkt` (single-run) | 0 | 9 turns; 3 boots (the run, reboots of quit prefixes 6 and 7); 17.4 s |
| `racket tests/historical_grue_resurrection_test.rkt` (single-run) | 0 | 21 turns; 2 boots (reboot of quit prefix 11); 11.4 s |
| `racket tests/historical_troll_death_test.rkt` (single-run) | 0 | 25 turns; 2 boots (reboot of prefix 19, non-standard tail); 11.5 s |
| `M4_SCENARIO_MODE=per-prefix racket tests/historical_grue_refusal_test.rkt` | 0 | 9 boots, 50.7 s; prefixes 6–8 "ended by the game's QUIT" |
| `M4_SCENARIO_MODE=per-prefix racket tests/historical_grue_resurrection_test.rkt` | 0 | 21 boots, 125.5 s |
| `M4_SCENARIO_MODE=per-prefix racket tests/historical_troll_death_test.rkt` | 0 | 25 boots, 154.7 s |
| `make test` | 0 | 4927 Racket tests passed; Python 104 passed, 1 deselected |
| `make m4-check` | 0 | SCENARIO_PARITY PASS (14 scenarios); GAMEPLAY_RELIABILITY NOT YET (14 of 23); see [below](#make-m4-check) |

Run with `PLTCOLLECTS=":$PWD"`; `make test` and `make m4-check` outside the
tool sandbox with `TMPDIR=/tmp` (inside it, tests that create directories
under `/tmp` fail with "Read-only file system").

## Mutation checks (each reverted; `git status` clean afterwards)

| # | Mutation | Result |
|---|---|---|
| M1 | grue-refusal: one native byte at the death turn (`slavering` -> `slaverinG` in P06, P07, T1; sha256 updated so the integrity check passes) | exit 1: earliest failing k = 6, kind transcript (single-run head 6) |
| M2 | grue-resurrection: the resurrection room in diagnostic checkpoint 12 FORE1 -> FORE2 | exit 1 at the test's own reference check; with that check removed (M2b): earliest failing k = 12, kind checkpoint, field `here` |
| M3 | runtime: QUIT raises input exhaustion instead of quitting (identical output: only the ending check can see it) | exit 1: earliest failing k = 6, kind run-guard, "the run did not end by the game's QUIT (declared quit ending)" |
| M4 | runner treats every prefix as D3 (`ending-of` -> `'eof`, the endings and stderr checks disabled) | exit 1: reference preparation (X1 holds 8 checkpoints, not n + 2 = 10) |
| M5 | grue-refusal declares `#:quit-prefixes '(7 8)` (6 omitted) | exit 1: declared endings differ from the reference's `endings` |
| M6 | grue-refusal declares only the READB denial | exit 1: earliest failing k = 6, kind run-guard, "RECORD OPENs (... READB ... PRINT ...), expected ((READB ...))" |
| M7 | troll-death declares the question at entry 18 | exit 1: declared `entry_prompts` differ from the reference's; with the reference changed too (M7b): strict prompt-count error "P18: expected 19 prompts, found 20" |
| M8 | troll-death: the scattered lamp in diagnostic checkpoint 20 LROOM -> KITCH | exit 1 at the test's reference check; with it removed (M8b): earliest failing k = 20, kind checkpoint, field `lamp_oroom` |

## Gameplay branches newly covered (`gameplay-branches.json`)

| Branch | Covering checks | Precision |
|---|---|---|
| `death.resurrection-accepted` | grue-resurrection, troll-death | non-valuable possessions and the lamp scattered; ROB-ADV's valuables branch, more possessions than RANDOM-LIST rooms, a vehicle and the third death are not exercised |
| `death.resurrection-refused-quit` | grue-refusal, grue-resurrection | `n`, and an end-of-input answer (stale `n`) |
| `death.killed-in-combat` | troll-death | the troll only |
| `combat.hero-wounded` | troll-death | a light wound; the sword-armed hero (S6) is still never hit |
| `combat.hero-staggered-or-unconscious` | troll-death | staggered only; unconsciousness not reached |
| `scoring.final-score-on-quit` | + grue-refusal (beside test-m3-session) | FINISH <> after death |

`timers.cure-clock-recovery` stays UNCOVERED: troll-death enables the CURIN
clock and checkpoints its tick (re-armed at the death turn, 29 -> 30, then
counting down), but recovery is not reached.

## make m4-check

`PLTCOLLECTS=":$PWD" TMPDIR=/tmp PYTHONPATH=.sandbox-pydeps/lib make m4-check
PYTHON=/usr/bin/python3`, exit 0, at commit `908c952` with only
`README.md` and this record uncommitted (reported `dirty`; no code differs).
Manifest completeness PASS; `sources` and all fourteen scenario targets PASS
(the three new ones 12.2 s, 17.1 s, 12.2 s), `test-m4-replay-persistence`
PASS, `test-m3-session` and `test-m3-launcher` PASS.

| Term | Status | Scope / reasons |
|---|---|---|
| SCENARIO_PARITY | PASS | 14 scenarios, each under one fixed clock and seed (250776000, UTC); per scenario, not gameplay coverage |
| GAMEPLAY_RELIABILITY | NOT YET | 14 of 23 required branches covered (was 9; PROVISIONAL list); uncovered: combat.thief, timers.lamp-burnout, timers.cure-clock-recovery, timers.other-clock-events, objects.puzzles-beyond-the-house, scoring.treasure-deposit, save.game-save-command, save.game-restore-command, save.player-facing-resume; open blockers INV-06, INV-07 |
| PLAYABLE | NOT RUN | sub-checks only; no PLAYABLE gate |
| FULL_COMPLETION | NOT RUN | no complete-game check |
| M4_ACCEPTED | NOT YET | R2–R5 unmet |

A local branch result, not a mainline acceptance.

## Security and licensing

No runtime code changed (the runner and tests are test infrastructure). No
new file access: quitting runs reach RECORD's OPENs, which stay denied
(ADR-0055), and the guard shows no write or delete attempt. Native runs used
disposable `$TMPDIR` copies only; `.cache/upstream` was not written; mdli was
not rebuilt. Confusion (GPLv3) was used only as a behaviour reference; no
Confusion code was copied. New scripts and tests are original MIT-0 code.

## Open risks and limits

- Each scenario is one fixed clock and seed; other seeds can take other
  branches (e.g. the grue's PROB 75 failing, the troll missing).
- `#:entry-prompts` matches the first occurrence of the declared text after
  the previous head; a game text that repeats the question before the
  prompt would be caught by the strict `>` count only if a `>` intervenes.
- The quit ending accepts only `'quit` with no MDL ERROR;
  `'quit-after-mdl-error` (INV-07) is not a declarable ending.
- The diagnostic wraps the game FUNCTION YES/NO and the SUBR QUIT
  natively; the capture rejects any change of the game text, but a wrapper
  that changed state without output would not be seen (as for the existing
  RANDOM/READSTRING wrappers).

## Next actionable task

Phase 2 continues with the uncovered combat/timer branches (unconsciousness,
cure-clock recovery, the thief) and Phase 3 objects; a scenario that walks
long enough after troll-death's wound would cover `timers.cure-clock-recovery`.

## Independent review (2026-11-25)

A read-only independent review of `origin/main...HEAD` checked:

* that the default path is unchanged for scenarios declaring neither option
  (prompt count k+2, EOF tails, D3 ending, reboot selection, guards);
* whether the new options could cause a false pass;
* the probe, the checkpoint purity, the branch claims, the wiring and the
  docs.

It found no defect. Verdict: approve with nits. Changes made in response:

* **Quit scenarios require `end_checkpoints`.** Without them, a quit
  prefix's end state would fall back to the entry checkpoint.
* **Declarations are cross-checked against the scenario file.** The runner
  compares the test's `#:entry-prompts` and `#:quit-prefixes` with the
  scenario JSON. Mutation check: removing 8 from grue-refusal's
  `quit_prefixes` fails at that check (exit 1).
* **Wording.** The cure-clock wording now says the tick is re-armed at the
  death turn (29 → 30), then counts down. The CI comment no longer says
  "eleven".
* **TESTING note.** It explains why the diagnostic runs' `stdout_sha256`
  values do not match their path-normalised `stdout_raw`. This predates
  this slice, and the runner does not use those runs.
