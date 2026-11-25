# M4 Phase 3b reference: the match clock MATIN; scenario `match-clock`

Date: 2026-11-25. Read-only reference investigation for epic #163 Phase 3b
(objects beyond the house, other clock events); slice record
[DAM-CLOCKS.md](DAM-CLOCKS.md). Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before and
after every capture (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; game directory
`mdlzork_771212/patched_confusion`, unmodified, copied fresh under `$TMPDIR`
for every run. Fixed clock: shim `scripts/reference/fixed_time.c` (sha256
`d1fa8652…b925`), LD_PRELOAD, `MDL_FIXED_EPOCH=250776000`, `TZ=UTC`; seed
10438660480, never overridden; no seed search. One exploration run of the
same route (troll-combat's sixteen commands, the reservoir and the Dam, the
Dam Lobby, the match lit three times) showed MATIN firing; the scenario adds
the last two matches.

## Captures

Checkpoint profile "dam" of `scripts/probe_death_scenario_reference.py`
(DAM_DIAG_FORMS; the reference's `diag_forms` equals the probe's profile at
the final commit): the timers fields plus GATE-FLAG, LOW-TIDE, the
Maintenance Room's RVARS and RMUNGBIT, MNTIN, the wrench, the tube, the
putty, the trunk, the matchbook's ORAND, OLIGHT? and FLAMEBIT, and MATIN's
CFLAG and CTICK. The Dkk cases keep their log's sha256 and size instead of
the log (their last checkpoints are `end_checkpoints`; X1's log is kept).

| Command | Exit | Record |
|---|---|---|
| `python3 -I scripts/probe_death_scenario_reference.py match-clock docs/evidence/M4/match-clock-reference.json` (copied from the first `$TMPDIR` capture) | 0 (`CAPTURE OK`) | 71 runs (T1, T1b, X1, Pkk, Dkk); sha256 `1cda7415…04bc`; T1 stdout sha256 `25457de2…5c33`; scenario file sha256 `c1944515…` |
| same, second capture to `$TMPDIR` (not committed) | 0 (`CAPTURE OK`) | all 36 transcript cases' stdout byte-identical; every diagnostic log (or its sha256), X1 checkpoints, RANDOM draws and end checkpoints identical |

## Findings (pinned Confusion)

Commands (34): troll-combat's first sixteen; `north` `north` `down` `up`
`east` `north` (East-West Passage, Deep Ravine, Reservoir South, Deep Canyon,
Dam, Dam Lobby); `take match`; `light match`; `look`; `look`; `light match`;
`wait`; `light match`; `turn off match`; `light match`; `light match`;
`inventory`; `score`.

- Entry 23 (`take match`): the matchbook carried, ORAND 5 (77dung.mud:2392),
  MATIN not queued (CTICK 0). The CLOCKER holds (CURIN #FALSE () 0) (queued
  by the troll fight, disabled) and LNTIN.
- MATCH-FUNCTION (77act1.mud:1925) at each `light match`: ORAND decremented,
  FLAMEBIT set, OLIGHT? 1, `<CLOCK-INT ,MATIN 2>` (CLOCK-INT conses MATIN in
  front of the CLOCKER's list the first time), "One of the matches starts
  to burn." The same turn's clock tick leaves CTICK 1 (entries 24, 27, 29,
  31: `(MATIN T 1)`).
- Command 25 `look`: the room text, then at its clock tick MATIN fires
  (C-INT): "The match has gone out.", FLAMEBIT cleared, OLIGHT? 0, CTICK 0.
- Command 28 `wait`: "Time passes...", then MATIN fires at WAIT's first
  extra CLOCK-DEMON pass and WAIT stops (77rooms.mud:1619); LNTIN 333 ->
  331 (two ticks: the extra pass and the turn's own).
- Command 30 `turn off match`: "The match is out.", `<CLOCK-INT ,MATIN 0>`;
  MATIN stays queued with CFLAG T and CTICK 0.
- Command 32, the fifth `light match`: ORAND 1 -> 0, "I'm afraid that you
  have run out of matches.", then the fourth match (lit at 31) goes out at
  this turn's tick: "The match has gone out."
- `inventory`: matchbook, lamp, sword; `score`: 40 in 34 moves.
- RANDOM: 13 draws (START's seed and troll-combat's fight); none after the
  troll dies.
- The thief never meets the hero and takes nothing; his HROOM moves on
  every shorter prefix's end-of-input turn except prefix 0, nothing else
  changes. Every prefix ends by end of input. No run writes MDL/ZORK.LOG;
  every run rewrites MDL/MADADV.SAVE.

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source was copied.
