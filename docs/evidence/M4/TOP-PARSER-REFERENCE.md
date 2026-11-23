# M4 S4 reference capture: scenario "top-parser"

Date: 2026-11-23. Scenario `tests/scenarios/top-parser.json` (issue #157).
Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before
and after (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; fixed clock 250776000, TZ=UTC,
microseconds 0 (shim `scripts/reference/fixed_time.c`). Every run boots a
fresh copy of `patched_confusion` under `$TMPDIR`; the only file written is
SAVE-IT's `MDL/MADADV.SAVE`, in the copy.

Command: `python3 -I scripts/probe_top_parser_reference.py docs/evidence/M4/top-parser-reference.json`
→ exit 0. Record: `top-parser-reference.json` (sha256 `f55cd7a6…eb63`;
T1 stdout sha256 `39ec9dcc…ad2d`, identical across the two captures made
while preparing this slice). Checks: `t1_equals_t1b_bytes`,
`diag_game_part_equals_t1_game_part_bytes` and
`prefix_runs_consistent_with_t1` are true; 12 checkpoints (10 commands + the
start + the end-of-input read); all exit statuses 0.

## Transcript (T1, game part)

| # | Command | Native response | TOP reached |
|---|---|---|---|
| 1 | `open mailbox` | `Opening the mailbox reveals a leaflet.` | — |
| 2 | `take leaflet` | `Taken.` | — |
| 3 | `drop leaflet in` | `I can't make sense out of that.` | SPARSE `77np.mud:126`: `(VECTOR 2 VECTOR 3 T #FALSE ())` |
| 4 | `put all in mailbox` | `leaflet:` / `  Done.` / `door:` / `  Nice try.` | EVERYTHING `77rooms.mud:1284`: `(UVECTOR 0 UVECTOR 20 #FALSE () T)` |
| 5 | `take all` | `Nothing happens.` | EVERYTHING |
| 6 | `take leaflet` | `Taken.` | — |
| 7 | `drop all` | `leaflet:` / `  Dropped.` | EVERYTHING |
| 8 | `take all` | `leaflet:` / `  Taken.` | EVERYTHING |
| 9 | `put leaflet in` | `I can't make sense out of that.` | SPARSE |
| 10 | `inventory` | `You are carrying:` / `A leaflet` | — |

then `Beg pardon?` and `>` at end of input (stderr `Error: Unexpected EOF`).
The TOP log entry is (TYPE and LENGTH of the operand, TYPE and LENGTH of the
result, result `==?` PRSVEC, result `==?` `<BACK ,OBJ-UV 20>`), from the
diagnostic run X1's TOP wrapper: SPARSE's TOP returns PRSVEC itself;
EVERYTHING's TOP of the empty OBJ-UV view returns the whole 20-slot storage.
No other TOP call happens.

RANDOM: START's seeding call `(10438660480)` → 16566282405, and one draw
in `put all in mailbox` (the door's reply) → -21802663835.

## Checkpoints (X1, at every READSTRING entry)

Fields: HERE, AOBJS, WHOUS ROBJS, MAILB OCONTENTS, leaflet OROOM/OCAN,
PRSVEC slots, PREPVEC PHRASEs, OBJ-UV LENGTH, the 20 OBJ-UV storage slots
(OID of a known object, else 0), RAW-SCORE, ASCORE, MOVES. Notable values:

* after `drop leaflet in` (cp 3): PRSVEC `((ACTION DROP) (IN ADVER) #FALSE
  ())` — the dangling preposition's PHRASE was written through `<BACK .PVR>`
  into PRSVEC slot 2 and into PREPVEC slot 1 `(IN ADVER)`; the syntax then
  did not match (the ACTION is still unresolved);
* after `put all in mailbox` (cp 4): OBJ-UV slots 19-20 `ADVER FDOOR`
  (filled downwards from the top by BACK), the leaflet in the mailbox, its
  OROOM still WHOUS;
* after `take all` (cp 5): slots 19-20 `MAILB FDOOR`; after `drop all`
  (cp 7): `MAILB ADVER` (slot 20 only was rewritten); after the second
  `take all` (cp 8): slots 18-20 `MAILB FDOOR ADVER`;
* OBJ-UV's own LENGTH stays 0 throughout (EVERYTHING works on a local copy
  of the view); MOVES 10 at the end, score 0.

## Frontier F4 (not the scenario)

Case `F4-living-room-take-all-pipe`: `north`, `east`, `open window`,
`west`, `west`, `take all`. Native: `sword:` / `  Taken.`, `newspaper:` /
`  Taken.`, `carpet:` / `  The rug is extremely heavy and cannot be
carried.`, `lamp:` / `  Taken.`. This runtime stops after `sword:` (see
`S4-TOP.md`).
