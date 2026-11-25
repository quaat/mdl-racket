# M4 Phase 3b reference: the boat and the river; scenario `boat-river`

Date: 2026-11-25. Read-only reference investigation for epic #163 Phase 3b
(objects beyond the house); slice record [DAM-CLOCKS.md](DAM-CLOCKS.md).
Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before and
after every capture (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; game directory
`mdlzork_771212/patched_confusion`, unmodified, copied fresh under `$TMPDIR`
for every run. Fixed clock: shim `scripts/reference/fixed_time.c` (sha256
`d1fa8652…b925`), LD_PRELOAD, `MDL_FIXED_EPOCH=250776000`, `TZ=UTC`; seed
10438660480, never overridden; no seed search.

## Route choice (no seed search)

The pump is in Reservoir North. With the reservoir full (the dam's sluice
gates closed; when this was captured the runtime could not open them,
INV-11, since fixed by S14 / #193) the only way in is
the Atlantis Room, below the Cave east of Mirror Room 1. mirror-bat's first
thirty-one commands reach Mirror Room 1 (the round room's RANDOM exits under
this clock and seed, then `rub mirror`); they are reused unchanged. Four
native exploration runs:

1. `west` from the Cave: "There is no way to go in that direction." (the Cave
   leads north and down only); rejected.
2. `north` from the Cave, the slide, the troll room, the reservoir, the Dam,
   the Dam Base, `inflate boat with pump`, `board boat`, `launch`, `look`,
   `wait`, `look`: works.
3. The same, then `down` the river, `land` (no landing at the second river
   room) and `disembark`: "Unfortunately, that leaves you in the water, where
   you drown." Rejected: a death, not this branch.
4. The same as 2 with `land` at the first river room, `disembark`, `look`,
   `deflate boat`, `take boat`, `inventory`, `score`: the scenario.

The routes draw RANDOM at different turns; the seed itself never changed.

## Captures

Checkpoint profile "boat" of `scripts/probe_death_scenario_reference.py`
(BOAT_DIAG_FORMS; the reference's `diag_forms` equals the probe's profile at
the final commit): the "dam" fields ([MATCH-CLOCK-REFERENCE.md](MATCH-CLOCK-REFERENCE.md))
plus the winner's AVEHICLE (OID) and the OROOM of the folded boat IBOAT, the
inflated boat RBOAT and the pump. The Dkk cases keep their log's sha256 and
size instead of the log.

| Command | Exit | Record |
|---|---|---|
| `python3 -I scripts/probe_death_scenario_reference.py boat-river docs/evidence/M4/boat-river-reference.json` (copied from the first `$TMPDIR` capture) | 0 (`CAPTURE OK`) | 119 runs (T1, T1b, X1, Pkk, Dkk); sha256 `23d83eb6…06ca`; T1 stdout sha256 `36b9adbe…3dc1`; scenario file sha256 `c9798913…` |
| same, second capture to `$TMPDIR` (not committed) | 0 (`CAPTURE OK`) | all 60 transcript cases' stdout byte-identical; every diagnostic log (or its sha256), X1 checkpoints, RANDOM draws and end checkpoints identical |

## Findings (pinned Confusion)

Commands (58): mirror-bat's first thirty-one; `east` `down` `se` (Cave,
Atlantis Room, Reservoir North); `take pump`; `north` `up` `north` `west`
`west` (Mirror Room 1, the corridor, the Slide Room); `down` (the slide:
Cellar); `east` `north` `north` `down` `up` `east` `down` (Troll Room,
East-West Passage, Deep Ravine, Reservoir South, Deep Canyon, Dam, Dam
Base); `inflate boat with pump`; `board boat`; `launch`; `land`;
`disembark`; `look`; `deflate boat`; `take boat`; `inventory`; `score`.

- Entry 35 (`take pump`): the pump carried.
- Entry 48 (`down` to the Dam Base): "There is a folded pile of plastic here
  which has a small valve attached." and the stick; "Your sword is glowing
  with a faint blue glow." (the thief is in the Dam, HROOM DAM).
- Command 49 `inflate boat with pump` (IBOAT-FUNCTION 77act2.mud:285, the
  pump carried): "The boat inflates and appears seaworthy."; IBOAT removed,
  RBOAT in the Dam Base.
- Command 50 `board boat`: "You are in the magic boat."; AVEHICLE RBOAT.
- Command 51 `launch`: the River Frigid near the Dam (RIVR1), the boat
  moved with the hero: "You are on the River Frigid in the vicinity of the
  Dam.  The river flows quietly here.  There is a landing on the west
  shore." and the boat's contents (the tan label).
- Command 52 `land`: back to the Dam Base, still in the boat.
- Command 53 `disembark`: "You are on your own feet again."; AVEHICLE
  cleared.
- Command 55 `deflate boat` (RBOAT-FUNCTION): "The boat deflates."; RBOAT
  replaced by IBOAT. Command 56 `take boat`: carried. `inventory`: the boat,
  the pump, the lamp, the sword. `score`: 40 in 58 moves.
- RANDOM: 33 draws (mirror-bat's through command 31, then the thief).
- The thief: takes the grail from the Grail Room (HOBJS (GRAIL) from entry
  35; the end-of-input turn of prefix 34 already shows it) and the trident
  from the Atlantis Room (entry 54); never in the hero's room at a
  READSTRING entry. During prefix 47's end-of-input turn (the hero in the
  Dam) he appears: "Someone carrying a large bag is casually leaning against
  one of the walls here. …" and the sword glows; prefix 48's end-of-input
  turn prints "Your sword is no longer glowing." Every other shorter prefix
  differs from the next entry only in HROOM.
- Endings: every prefix ends by end of input. No run writes MDL/ZORK.LOG;
  every run rewrites MDL/MADADV.SAVE.

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source was copied.
