# M4 S6: troll combat (scenario `troll-combat`)

Date: 2026-11-23. Branch `feat/m4-troll-combat` at `main` `18e2047` (MAX,
#159, and function TYPE, #161, merged). Upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`, mit_zork
`d94501340842e006791fce0757dc0043b8ec8916` (`sources.lock.json`). Pinned mdli
sha256 `6df359f6…b789` before and after the capture (never rebuilt). Racket
v7.9 [bc], Python 3.9.2.

Result: **scenario `troll-combat` PASS (scoped: this scenario only,
transcript plus checkpoints, D1 only): all 23 command prefixes (k = 0..22)
match the pinned native reference byte for byte, and every end checkpoint
equals the reference.** No divergence was found, so no frontier entry was
added. Not a PLAYABLE claim and not the M4 gate. No runtime code changed in
this slice (`mdl/` untouched); it is test and evidence only.

## What the scenario exercises

The sword-glow path into the troll room, then `kill troll with sword` until
the fight is decided, then state checks (`tests/scenarios/troll-combat.json`,
22 commands). Under the fixed clock (250776000 UTC) and START's seed the
fight is deterministic (reference T1 = T1b byte for byte):

1. attack 1: `Your sword pinks the troll on the wrist, but it's not
   serious.` / `The troll swings his axe, but it misses.` (light wound:
   troll OCAPAC 2 → 1 through `<MAX 0 <- .DEF 1>>`, `78melee.mud:447`;
   FIGHTBIT set; `<1 ,OPPV>` = TROLL);
2. attack 2: `The troll's weapon is knocked to the floor, leaving him
   unarmed.` / `The troll, now worried about this encounter, recovers his
   bloody axe.` (LOSE-WEAPON: REMOVE-OBJECT + INSERT-OBJECT of the axe in
   BLOW `78melee.mud:452-455`, hero branch; TROLL's FIGHT! branch `77act1.mud:366-372`
   SNARF-OBJECTs it back in the same turn);
3. attack 3 decides it: `It's curtains for the troll as your sword removes
   his head.`, the black-fog carcass text, `Your sword is no longer
   glowing.` (KILLED: OCAPAC 0, REMOVE-OBJECT, TROLL DEAD! sets
   TROLL-FLAG!-FLAG; sword OTVAL 0).

Then `diagnose` (`You are in perfect health.` / `You can be killed by a
serious wound.`, DIAGNOSE `78melee.mud:511`, FIGHT-STRENGTH with FLOAT
arithmetic), `score` (35 in 18 moves, Amateur Adventurer), `inventory`
(lamp, sword), `look` (troll room, no troll), `take axe` (`I can't see a axe
here.`: the axe left with the troll) and `east` (north-south crawlway,
CRAW4). The hero is never wounded (ASTRENGTH 0, CURIN not enabled). The
player-death branch of BLOW / JIGS-UP is not reached on this path.

Call path: RDCOM → verb KILL → KILLER (`77act1.mud:1699`) → `<BLOW ,PLAYER
.PRSO <ORAND .PRSI> T <>>` (`:1711`) → BLOW (`78melee.mud:377`) → PRES
(`78melee.mud:351`, remark picked by `<MOD <RANDOM> .L>`); each turn the
demon FIGHTING (`78melee.mud:282`) → APPLY-RANDOM TROLL (`77act1.mud:360`)
→ BLOW for the troll's counterattack. 12 RANDOM calls in the reference run
(listed in TROLL-COMBAT-REFERENCE.md and asserted by the test).

## Reference

[TROLL-COMBAT-REFERENCE.md](TROLL-COMBAT-REFERENCE.md),
`troll-combat-reference.json` (47 pipe runs): T1/T1b, P00–P21, the
diagnostic X1 (24 checkpoints) and D00–D21 (end-of-input checkpoint of every
prefix). Command:
`python3 -I scripts/probe_troll_combat_reference.py docs/evidence/M4/troll-combat-reference.json`
→ exit 0; all capture checks true.

## Test

`tests/historical_troll_combat_test.rkt` (`make test-m4-troll-combat`; CI
step "M4 S6 scenario (troll combat with the sword)" in
`.github/workflows/reference.yml`, after the S5b step), modelled exactly on
`tests/historical_sword_glow_test.rkt`: reference integrity (pinned mdli
sha256, upstream SHA, stdout sha256 of every transcript case, capture
checks, the reference checkpoint and RANDOM-draw structure of the fight);
then for every prefix k = 0..22 a guarded (no writes, empty cwd, game tree
hashes unchanged, no OPEN records), watchdogged run that must end by D3
input exhaustion, whose raw output must equal the reference stdout after D1
only, and whose read-only end checkpoint must equal reference end checkpoint
k. Checkpoint fields: HERE; winner AOBJS, ASTRENGTH, ASTAGGERED; troll
OROOM, OCAPAC, OCONTENTS, FIGHTBIT, STAGGERED; axe OROOM, OCAN;
TROLL-FLAG!-FLAG; `<1 ,OPPV>`; `<1 ,VILLAIN-PROBS>`; CURIN CFLAG/CTICK;
sword OTVAL; SWORD-DEMON HACTION; RAW-SCORE, ASCORE, MOVES. Flag bits are
read as TRNN does (`ANDB`, `CHTYPE … FIX`).

## Commands and results

| Command | Exit | Notes |
|---|---|---|
| `python3 -I scripts/probe_troll_combat_reference.py docs/evidence/M4/troll-combat-reference.json` | 0 | 47 runs; mdli sha256 unchanged |
| `make PYTHON=/usr/bin/python3 test-m4-troll-combat` | 0 | `troll-combat: all 23 prefix runs match the reference (D1 only)`; about 2.5 min |
| mutation: P15 stdout `recovers his bloody` → `bloodx` (sha256 recomputed) in the reference JSON, then `racket tests/historical_troll_combat_test.rkt` | 1 | fails at prefix 15, transcript check (`historical_troll_combat_test.rkt:296`); JSON restored, `cmp` identical |
| `make PYTHON=/usr/bin/python3 test` (sandbox) | 2 | 3/4374 failures, all sandbox `/tmp` read-only: `tests/loader_test.rkt`, `tests/declaration_test.rkt`, `tests/percent_read_test.rkt` |
| `raco test` of those three files outside the sandbox | 0 each | 59, 56, 40 tests passed |
| `make PYTHON=/usr/bin/python3 test-python` | 0 | 68 passed, 1 deselected (`make test` stops before it on the sandbox failure) |
| `make PYTHON=/usr/bin/python3 test-historical` (outside the sandbox; it writes `/tmp`) | 0 | |
| `make PYTHON=/usr/bin/python3 test-m4-sword-glow` | 0 | 14 prefix runs match |
| `git diff --check` | 0 | |

## Security and licensing

Reference runs used disposable `$TMPDIR` copies; `.cache/upstream` was not
written. No MDL evaluator is exposed; the test uses the existing host-only
introspection API (`mdl-session-call`/`-global`/`-atom`). Confusion (GPLv3)
was used only as a behaviour reference; no Confusion source was copied.

## Limits and next step

Scenario-scoped parity only: one deterministic fight under one seed, troll
death branch. Not compared: the hero being wounded or killed (CURIN, the
ASTRENGTH update, JIGS-UP `77rooms.mud:870`), the troll knocked
unconscious (OUT!/IN! branches, negative OCAPAC), STAGGERED, and attacking
with other weapons. A further scenario would need a different seed or
command timing to reach those branches.
