# M4 S6 reference capture: fight the troll (scenario `troll-combat`)

Date: 2026-11-23. Read-only reference capture. Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before and
after (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; game directory
`mdlzork_771212/patched_confusion`, copied fresh under `$TMPDIR` for every
run (SAVEFILE/ZORK.SAVE removed; the only file written is SAVE-IT's
`MDL/MADADV.SAVE` in the copy). Fixed clock: shim
`scripts/reference/fixed_time.c` (sha256 `d1fa8652…b925`), LD_PRELOAD,
`MDL_FIXED_EPOCH=250776000`, `TZ=UTC`; RANDOM seeded by START with
10438660480 as in every M4 scenario.

Command: `python3 -I scripts/probe_troll_combat_reference.py docs/evidence/M4/troll-combat-reference.json`
→ exit 0 (47 runs, pipe mode, about 11 s). Record: `troll-combat-reference.json`
(sha256 `7826e240…d608`), T1 stdout sha256 `0f2c16e5…e1d4`. Local paths in
the record (diagnostic DIAG.LOG names) are written as `$TMPDIR` / `<repo>`;
the transcript cases contain none (asserted by the script).

Scenario (`tests/scenarios/troll-combat.json`): `<FLOAD "77loadall.mud">`,
`<SAVE-IT>`, then the 13 sword-glow commands (`north`, `east`,
`open window`, `west`, `west`, `take sword`, `inventory`, `take lamp`,
`move rug`, `open trap door`, `turn on lamp`, `down`, `east`), then
`kill troll with sword` ×3, `diagnose`, `score`, `inventory`, `look`,
`take axe`, `east`, then end of input.

## Choosing the command list

An exploratory native run with 15 `kill troll with sword` after the
sword-glow path showed the fight decided by the third attack (the troll
dies); attacks 4–15 only print `I can't see a troll here.`. A second
exploratory run added the state checks; `take axe` fails because the axe
leaves with the troll's carcass. The committed scenario stops attacking
after the deciding blow. Both exploratory runs and T1/T1b printed the same
fight text.

## Runs and checks

* T1 / T1b: the transcript, byte-identical twice (`t1_equals_t1b_bytes`), so
  the RANDOM-driven fight is deterministic under the fixed clock and seed.
* P00–P21: the first k commands, then EOF; each equals T1 cut after the
  (k+1)-th prompt plus the end-of-input reply (`prefix_runs_consistent_with_t1`).
* X1: diagnostic (not a transcript). Forms typed after FLOAD and before
  SAVE-IT wrap RANDOM and READSTRING (the original SUBR is applied to the
  same arguments and its value returned) and log to `DIAG.LOG` outside the
  game copy; a read-only checkpoint at every READSTRING entry. Game text
  equals T1's byte for byte (`diag_game_part_equals_t1_game_part_bytes`);
  24 checkpoints.
* D00–D21: X1 cut after k commands; their last checkpoint is the state after
  the end-of-input empty command (`Beg pardon?`), which still runs the
  demons: the state a per-prefix candidate run ends in (`end_checkpoints`;
  k = 22 is X1's last). Each game text equals Pkk's.

Checkpoint fields: HERE; winner AOBJS, ASTRENGTH, ASTAGGERED bit; troll
OROOM, OCAPAC, OCONTENTS, FIGHTBIT, STAGGERED bit; axe OROOM and OCAN;
TROLL-FLAG!-FLAG; `<1 ,OPPV>`; `<1 ,VILLAIN-PROBS>`; CURIN CFLAG and CTICK;
sword OTVAL; SWORD-DEMON HACTION; RAW-SCORE, ASCORE, MOVES. Bits are read as
TRNN does (`<N==? <CHTYPE <ANDB flags bit> FIX> 0>`).

## Transcript of the fight (game part from `east`, CRs as printed `<CR>`)

```
>You are in a small room with passages off in all directions. <CR>
Bloodstains and deep scratches (perhaps made by an axe) mar the<CR>
walls.
A nasty-looking troll, brandishing a bloody axe, blocks all passages<CR>
out of the room.
Your sword has begun to glow very brightly.                     (east)
>Your sword pinks the troll on the wrist, but it's not serious.
The troll swings his axe, but it misses.                        (kill 1)
>The troll's weapon is knocked to the floor, leaving him unarmed.
The troll, now worried about this encounter, recovers his bloody<CR>
axe.                                                            (kill 2)
>It's curtains for the troll as your sword removes his head.
Almost as soon as the troll breathes his last breath, a cloud<CR>
of sinister black fog envelops him, and when the fog lifts, the<CR>
carcass has disappeared.
Your sword is no longer glowing.                                (kill 3)
>You are in perfect health.
You can be killed by a serious wound.                           (diagnose)
>
Your score would be 35 [total of 500 points], in 18 moves.
This score gives you the rank of Amateur Adventurer.            (score)
>You are carrying:
A lamp
A sword                                                         (inventory)
>You are in a small room with passages off in all directions. <CR>
Bloodstains and deep scratches (perhaps made by an axe) mar the<CR>
walls.                                                          (look)
>I can't see a axe here.                                        (take axe)
>You are in a north-south crawlway; a passage goes to the east also.<CR>
There is a hole above, but it provides no opportunities for climbing.  (east)
>Beg pardon?
>
```

stderr: `Error: Unexpected EOF`; exit status 0.

## Diagnostic findings

* Troll OCAPAC (strength): 2 through checkpoint 13; 1 after the first
  attack (light wound: `<MAX 0 <- .DEF 1>>`, `78melee.mud:447`), FIGHTBIT
  set, `<1 ,OPPV>` = TROLL (checkpoints 14–15); 0 after the third (killed:
  REMOVE-OBJECT, OROOM FALSE, FIGHTBIT cleared, TROLL-FLAG!-FLAG T, OPPV
  slot FALSE; checkpoints 16–23).
* The axe: OCAN TROLL and OROOM FALSE at every checkpoint (in the second
  attack it is knocked to the floor and recovered by TROLL's FIGHT! branch,
  `77act1.mud:366-372`, within the same turn); it leaves with the troll.
* The hero is never hit: ASTRENGTH 0, ASTAGGERED clear, CURIN CFLAG FALSE,
  CTICK 0 throughout. STAGGERED never set on the troll.
* Sword OTVAL: 1 in the cellar (12), 2 in the troll room (13–15), 0 after
  the troll dies (16 on); SWORD-DEMON HACTION stays the ATOM SWORD-GLOW from
  checkpoint 6.
* RAW-SCORE/ASCORE 35 from checkpoint 12; no points for the troll. MOVES 22
  after `east` into CRAW4.
* RANDOM (12 calls): START's seeding `<RANDOM 10438660480>` →
  16566282405; entering the troll room one draw (-21802663835; by source reading
  FIGHTING's FIRST? `<PROB 33>` via TROLL `77act1.mud:391`, false: FIGHTBIT
  stays clear); attack 1: four draws (12914488375,
  -6577089531, 34210328094, 3437552668); attack 2: three (13814526739,
  -20114144995, 11990399124); attack 3: two (31711279130, 25894896720);
  `look`: one (24534915165; caller not traced, it does not change the
  checkpoints). Draws are logged with the number of
  checkpoints before them (13, 14, 15, 16, 20).

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source was copied.
