# M4 S8: ABS and the cyclops (issue #167; scenario `cyclops-room`)

Date: 2026-11-24. Branch `feat/m4-abs-cyclops` at `main` `a755788`. Upstream
mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`, mit_zork
`d94501340842e006791fce0757dc0043b8ec8916` (`sources.lock.json`). Pinned
mdli sha256 `6df359f6…b789` before and after every capture (never rebuilt).
Racket v7.9 [bc], Python 3.9.2.

Result: **ABS implemented; scenario `cyclops-room` PASS (branch evidence,
scoped: this scenario only, transcript plus checkpoints plus RANDOM draws,
D1 only): all 41 command prefixes (k = 0..40) match the pinned native
reference byte for byte and every end checkpoint equals the reference.** No
further divergence was found after ABS on this path, so no frontier entry
was added. Not a PLAYABLE claim and not the M4 gate. `odysseus` / the
Strange Passage (TIME, #170) is deliberately not on this path.

## The failure (#167)

Entering the Cyclops Room, the demon FIGHTING (`78melee.mud:308-309`)
applies the cyclops action CYCLOPS (`77act1.mud:934`) with the FIRST? verb;
CYCLOPS evaluates `<G? <ABS .COUNT> 5>` (`:951`) before its FIRST? clause.
ABS was not a builtin, so the session ended with `mdl-eval: unassigned or
non-applicable MDL operator ABS` after 23 matching responses (failure
inventory case F1). The other game sites are `:949` (WAKE), `:1031`
(CYCLOPS-ROOM, LOOK) and `:1050` (AOS-SOS), all on the FIX anger counter
RVARS.

## Semantics (docs/SEMANTICS.md "M4: ABS (#167)", written before the code)

Manual §3.4, §3.5, Appendix 2: one FIX or FLOAT argument; result of the
same TYPE, |x|. This runtime: FIX in, FIX out (36-bit checked); FLOAT in,
FLOAT out (exact); −2^35 is a strict `mdl-abs: FIX overflow` (36-bit model,
§3.5); zero or two+ arguments `mdl-abs: TOO-FEW-/TOO-MANY-ARGUMENTS-SUPPLIED`;
non-numbers `mdl-abs: expected MDL FIX or FLOAT`. Implementation
`mdl-abs` in `mdl/runtime/core.rkt` (builtin-table `"ABS"`; exported).

## Reference probes

[ABS-REFERENCE.md](ABS-REFERENCE.md), `abs-probe.json` (21 bare-mdli
cases). Native: `<ABS -5>` 5 FIX, `<ABS 0>` 0, `<ABS -2.5>` 2.5 FLOAT,
`<ABS 0.0>` 0.0 FLOAT, large FLOATs exact, errors `FIRST-ARG-WRONG-TYPE` and
`TOO-FEW/TOO-MANY-ARGUMENTS-SUPPLIED`. Manual/Confusion differences, none on
the game path (no adjudication needed): `<ABS -34359738368>` is FIX
34359738368 in Confusion (64-bit FIX), a strict overflow here;
`-34359738369` reads as FLOAT here (M1 #8); `<ABS <MAX>>` follows ADR-0059;
native errors are MDL ERRORs, here strict host failures (as for MAX).

The function-type probe was re-recorded with ABS in `builtin_names`
(`function-type-probe.json` sha256 `da65b478…b446`; 114 names, all SUBR),
so the builtin-set assertion of `tests/function_type_test.rkt` holds. ABS is
already in the ROOT inventory (`mdl/runtime/root-names.rktd`).

## Tests first (red, then green)

`tests/abs_test.rkt` (added to `scripts/test_racket.sh`): FIX/FLOAT values
and TYPEs, large FLOATs (`<* -100000000000.0 1000000000.0>`; this reader
has no exponent FLOAT syntax), 36-bit boundaries and the −2^35 overflow,
host integers outside the range, arity and type refusals, APPLY/MAPF, and
the game's four expression shapes.

* red, before `mdl-abs` existed: `raco test tests/abs_test.rkt` → exit 1,
  `57/58 test failures` (every ABS form: `unassigned or non-applicable MDL
  operator ABS`; the one pass is the literal `-34359738368` reading as FIX);
* green: `59 tests passed` (one check added with the computed large FLOAT).

## Scenario

[CYCLOPS-ROOM-REFERENCE.md](CYCLOPS-ROOM-REFERENCE.md),
`cyclops-room-reference.json` (83 pipe runs, T1 = T1b; X1 42 checkpoints),
`tests/scenarios/cyclops-room.json` (40 commands):

`north`, `east`, `open window`, `west`, `open sack`, `take lunch`,
`take bottle`, `inventory`, `west`, `take sword`, `take lamp`, `move rug`,
`open trap door`, `turn on lamp`, `down`, `east`, `kill troll with sword` ×3,
`south`, `south`, `east`, `up`, `sw`, `east`, `south`, `ne`,
`give lunch to cyclops`, `look`, `take cyclops`, `open bottle`,
`give water to cyclops`, `take cyclops`, `look`, `wake cyclops`, `look`,
`west`, `diagnose`, `inventory`, `score`.

Native highlights: the troll fight is identical to `troll-combat`; the
cyclops eats the hot peppers (RVARS −1), "The cyclops seems somewhat
agitated." (`<ABS -1>`), "… getting more agitated." (`<ABS -2>`), falls
asleep after the water, "You can't be serious.", wakes ("yawns and stares")
with RVARS `<ABS -2>` = 2 and FIGHTBIT, "knocks you silly", "standing in the
corner … getting more agitated." and "almost strangles you"; the hero flees
west, is in perfect health, score 35 in 40 moves. 22 RANDOM draws, pinned.

`tests/historical_cyclops_room_test.rkt` (`make test-m4-cyclops-room`; CI
step "M4 S8 scenario (the cyclops and ABS)" after the WP4 replay step),
modelled on the troll-combat test: reference integrity (mdli sha256,
upstream SHA, stdout sha256 of every transcript case, capture checks, the
reference cyclops state per checkpoint and the RANDOM draws); then for every
prefix k = 0..40 a guarded, watchdogged run that must end by D3 input
exhaustion with raw output equal to the reference after D1 only and the
read-only end checkpoint equal to reference end checkpoint k. Fields: HERE;
winner AOBJS, ASTRENGTH, ASTAGGERED; cyclops OROOM, OCAPAC, SLEEPBIT,
FIGHTBIT, STAGGERED; Cyclops Room RVARS; CYCLOPS-FLAG, MAGIC-FLAG,
TROLL-FLAG; FOOD and WATER OROOM/OCAN; bottle OCONTENTS; `<3 ,OPPV>`;
`<3 ,VILLAIN-PROBS>`; CURIN CFLAG/CTICK; sword OTVAL; RAW-SCORE, ASCORE,
MOVES.

## Commands and results

| Command | Exit | Notes |
|---|---|---|
| `python3 -I scripts/probe_abs_reference.py docs/evidence/M4/abs-probe.json` | 0 | 21 cases; mdli sha256 unchanged |
| `python3 -I scripts/probe_function_type_reference.py docs/evidence/M4/function-type-probe.json` | 0 | 19 cases; ABS added |
| `python3 -I scripts/probe_cyclops_room_reference.py docs/evidence/M4/cyclops-room-reference.json` | 0 | 83 runs; all capture checks true |
| `raco test tests/abs_test.rkt` before `mdl-abs` | 1 | 57/58 failures (red) |
| `raco test tests/abs_test.rkt` | 0 | 59 passed |
| `raco test tests/function_type_test.rkt` | 0 | 335 passed |
| `racket tests/historical_cyclops_room_test.rkt` | 0 | `cyclops-room: all 41 prefix runs match the reference (D1 only)`; 4 min 32 s |
| mutation (a): `mdl-abs` returns its argument unchanged; `raco test tests/abs_test.rkt` | 1 | 22/59 failures |
| mutation (a): `racket tests/historical_cyclops_room_test.rkt` | 1 | prefixes 0–28 pass; prefix 29 (`look` after feeding) fails: `mdl-nth: index out of range` (`<NTH ,CYCLOMAD -1>`, `77act1.mud:1031`); core.rkt restored |
| mutation (b): P28 stdout `hot peppers` → `hot pepperz`, sha256 recomputed; `racket tests/historical_cyclops_room_test.rkt` | 1 | prefixes 0–27 pass; prefix 28 fails at the transcript check (`historical_cyclops_room_test.rkt:330`); JSON restored (sha256 `16202bed…b45c` again) |
| `make PYTHON=/usr/bin/python3 test` (outside the sandbox, `PYTHONPATH=.sandbox-pydeps/lib`) | 0 | 4766 Racket tests passed; pytest 68 passed, 1 deselected |
| `make PYTHON=/usr/bin/python3 test-historical` (outside the sandbox) | 0 | |
| `make PYTHON=/usr/bin/python3 test-m4-troll-combat` | 0 | 23 prefix runs match |
| `make PYTHON=/usr/bin/python3 test-m4-cyclops-room` | 0 | 41 prefix runs match |
| `git diff --check` | 0 | |

## Security and licensing

Reference runs used disposable `$TMPDIR` copies; `.cache/upstream` was not
written; recorded paths are sanitized. No MDL evaluator is exposed; the
test uses the existing host-only introspection API. Confusion (GPLv3) was
used only as a behaviour reference; no Confusion source was copied. The MDL
manual is cited from the public transcription (taradinoc/mdl-docs).

## Limits and next step

Scenario-scoped parity only, one seed. Not compared: the cyclops eating
the player (`<G? <ABS .COUNT> 5>` true, JIGS-UP and the second melee death
in the same turn, seen natively while choosing the commands), the
treasure-room path past the sleeping cyclops (thief fight), killing the
cyclops, and `odysseus` (MAGIC-FLAG; the Strange Passage needs TIME, #170,
a maintainer decision). Next: the TIME decision (#170), then the
`odysseus` scenario.
