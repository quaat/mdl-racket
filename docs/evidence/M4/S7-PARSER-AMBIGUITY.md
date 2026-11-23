# M4 S7: parser rejection and ambiguity (scenario `parser-ambiguity`)

Date: 2026-11-23. Branch `feat/m4-parser-ambiguity` at `main` `b6b86d0`
(S6 troll combat, #162, merged). Upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`, mit_zork
`d94501340842e006791fce0757dc0043b8ec8916` (`sources.lock.json`). Pinned mdli
sha256 `6df359f6…b789` before and after the capture (never rebuilt). Racket
v7.9 [bc], Python 3.9.2.

Result: **scenario `parser-ambiguity` PASS (scoped: this scenario only,
transcript plus checkpoints, D1 only): all 35 command prefixes (k = 0..34)
match the pinned native reference byte for byte, and every end checkpoint
equals the reference.** No divergence was found, so no frontier entry was
added. Not a PLAYABLE claim and not the M4 gate. No runtime code changed in
this slice (`mdl/` untouched); it is test and evidence only.

## What the scenario exercises

`tests/scenarios/parser-ambiguity.json`, 34 input lines, through RDCOM
(`77rooms.mud:600`) → LEX (`77rooms.mud:1559`) → EPARSE (`77np.mud:347`) →
SPARSE (`77np.mud:19`) → SYN-MATCH (`77np.mud:144`). Native responses (full
transcript in [PARSER-AMBIGUITY-REFERENCE.md](PARSER-AMBIGUITY-REFERENCE.md)):

| Input | Native response | Parser path |
|---|---|---|
| `xyzzy` (also later, inside an orphan) | `I don't know the word XYZZY` | SPARSE `77np.mud:97` |
| `frobozz` | `The FROBOZZ Corporation created, owns, and operates this dungeon.` | a real verb (`FROBO`) |
| empty line | `Beg pardon?` (no move) | RDCOM `77rooms.mud:620`, `:641` |
| three blanks | `Huh?` (a move) | LEXV empty, no verb, no object: `77np.mud:108` |
| `inven`, `inventoryxyz`, `INVENTORY` | `You are empty handed.` ×3 | LEX upper-cases and cuts to 5 letters |
| `the` | `Huh?` | buzz word skipped (`77dung.mud:69`) |
| `mailbox` | `What should I do with the mailbox?` | orphan, OSLOT1 = MAILB |
| `take` | `Nice try.` | ORFEO (`77np.mud:212`) supplies the mailbox; TAKE's YUKS remark (RANDOM) |
| `take it` | `Take what?` | IT is a buzz word; ORTELL (`77np.mud:219`) |
| `open brass` | `Dangling adjective?` | `77np.mud:112` |
| `take wooden mailbox` | `I can't see a woode mailb here.` | PRSTR prints 5-letter PNAMEs |
| `open mailbox door mailbox` | `Too many objects specified?` | `77np.mud:61` |
| `open with with mailbox` | `Double preposition?` | `77np.mud:48` |
| `take "leaflet"` | `Take what?` | LEX's quote skips a slot; SPARSE stops at the empty word |
| `take` + 9× `the` + `leaflet` | `Take what?` | LEXV has 10 slots; the 11th word is dropped silently |
| `northeast` | north of the house | truncated to `NORTH`, a direction |
| `up`, `take knife` | `It is pitch black. …` / `It is too dark in here to see.` | dark attic, `77np.mud:74-81` |
| `move rug`, `open door` | `Which door?` | WDOOR and the trap door both match `door`; GET-OBJECT (`77np.mud:363`) returns NEFALS; `77np.mud:88` |
| `trap` | `The door reluctantly opens to reveal a rickety staircase descending into darkness.` | adjective answer: SPARSE substitutes the orphan's noun (`77np.mud:51-55`) |
| `open door`, `xyzzy`, `wooden` | `Which door?`, `I don't know the word XYZZY`, `The door cannot be opened.` | the orphan survives a failed parse |
| `Take BRASS Lantern` | `Taken.` | mixed case, adjective + noun |
| `take all` | `sword:` `Taken.` / `newspaper:` `Taken.` / `carpet:` `The rug is extremely heavy and cannot be carried.` | EVERYTHING over several room objects |
| `score` | `Your score would be 10 [total of 500 points], in 33 moves.` | 34 lines, 33 moves |

RANDOM: 4 calls (START's seed; the YUKS remark for `take`; two in `down` out
of the dark attic), listed in the reference record and asserted by the test.

## Reference

[PARSER-AMBIGUITY-REFERENCE.md](PARSER-AMBIGUITY-REFERENCE.md),
`parser-ambiguity-reference.json` (71 pipe runs): T1/T1b (byte-identical),
P00–P33, the diagnostic X1 (36 checkpoints) and D00–D33 (end-of-input
checkpoint of every prefix). Command:
`python3 -I scripts/probe_parser_ambiguity_reference.py docs/evidence/M4/parser-ambiguity-reference.json`
→ exit 0; all capture checks true; mdli sha256 unchanged.

## Test

`tests/historical_parser_ambiguity_test.rkt` (`make test-m4-parser-ambiguity`;
CI step "M4 S7 scenario (parser rejection and ambiguity)" in
`.github/workflows/reference.yml`, after the S6 step), modelled exactly on
`tests/historical_troll_combat_test.rkt`: reference integrity (pinned mdli
sha256, upstream SHA, stdout sha256 of every transcript case, capture
checks, and the reference's MOVES sequence, LEXV contents, ORPHANS states,
TRAP-DOOR!-FLAG sequence and RANDOM draws); then for every prefix
k = 0..34 a guarded (no writes, empty cwd, game tree hashes unchanged, no
OPEN records), watchdogged run that must end by D3 input exhaustion, whose
raw output must equal the reference stdout after D1 only, and whose
read-only end checkpoint must equal reference end checkpoint k. Checkpoint
fields: HERE, `<LIT? ,HERE>`, winner AOBJS, the 10 LEXV strings, PRSVEC,
PARSE-WON, the five ORPHANS slots, TRAP-DOOR!-FLAG, the trap door's OVISON
bit, RAW-SCORE, ASCORE, MOVES.

## Commands and results

| Command | Exit | Notes |
|---|---|---|
| `python3 -I scripts/probe_parser_ambiguity_reference.py docs/evidence/M4/parser-ambiguity-reference.json` | 0 | 71 runs, about 16 s; mdli sha256 unchanged |
| `make PYTHON=/usr/bin/python3 test-m4-parser-ambiguity` | 0 | `parser-ambiguity: all 35 prefix runs match the reference (D1 only)`; about 3.7 min (222 s); run twice (before and after the mutation check) |
| mutation: P27 stdout `>Which door?` → `>Which doox?` (sha256 recomputed) in the reference JSON, then `racket tests/historical_parser_ambiguity_test.rkt` | 1 | prefixes 0–26 pass, fails at prefix 27, transcript check (`historical_parser_ambiguity_test.rkt:318`); JSON restored from a copy, `cmp` identical |
| `make PYTHON=/usr/bin/python3 test` (sandbox) | 2 | 3/4374 failures, all sandbox `/tmp` read-only (`make-directory: … Read-only file system`): `tests/loader_test.rkt`, `tests/declaration_test.rkt`, `tests/percent_read_test.rkt` |
| `raco test` of those three files outside the sandbox | 0 each | 59, 56, 40 tests passed |
| `make PYTHON=/usr/bin/python3 test-historical` (outside the sandbox; it writes `/tmp`) | 0 | |
| `PYTHONPATH=.sandbox-pydeps/lib make PYTHON=/usr/bin/python3 test-python` | 0 | 68 passed, 1 deselected (`make test` stops before it on the sandbox failure) |
| `git diff --check` | 0 | |

## Security and licensing

Reference runs used disposable `$TMPDIR` copies; `.cache/upstream` was not
written. No MDL evaluator is exposed; the test uses the existing host-only
introspection API (`mdl-session-call`/`-global`/`-atom`). Confusion (GPLv3)
was used only as a behaviour reference; no Confusion source was copied.

## Limits and next step

Scenario-scoped parity only. Not compared: `help`/`info`/a leading `?`
(strict by decision, frontier F3); `I'm too simple-minded for that.` (only
printed when LEX is not silent, which RDCOM never asks for); `I can't reach
that from inside the …` (needs a vehicle); a prepositional phrase as a bare
orphan (`with mailbox`, which would put a PHRASE in OSLOT1); answering
`Which door?` with a full noun phrase; ambiguity between a carried and a
room object. Next backlog rows: lamp and time events, death and recovery,
scoring.
