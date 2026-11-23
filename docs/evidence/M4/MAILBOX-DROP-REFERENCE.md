# M4 S2 scenario reference: drop the leaflet

Date: 2026-11-23. Scenario `tests/scenarios/mailbox-drop.json`: fresh boot
(`<FLOAD "77loadall.mud">`, `<SAVE-IT>`), fixed clock 250776000 / UTC, then
`open mailbox`, `take leaflet`, `drop leaflet`, `inventory`, `look`,
`take leaflet`, `drop leaflet`, `look`, end of input.

Command: `python3 -I scripts/probe_mailbox_drop_reference.py docs/evidence/M4/mailbox-drop-reference.json`
→ exit 0. Pinned mdli sha256 `6df359f6…b789` before and after (not rebuilt);
upstream `bdcd4a67…19b3`. Record `mailbox-drop-reference.json` (sha256
`b88e44a2…5615`). Cases: T1, T1b (repeat), X1 (diagnostic), P00–P07
(prefixes). Checks: `t1_equals_t1b_bytes`,
`diag_game_part_equals_t1_game_part_bytes`, `prefix_runs_consistent_with_t1`
all true; 10 checkpoints (n = 0..9); every exit status 0, stderr
`Error: Unexpected EOF`. The only file written is SAVE-IT's
`MDL/MADADV.SAVE`, in the disposable copy. T1 stdout sha256 `edc8feaf…7d75`.

Game text (T1, after `"DONE"`):

```
Welcome to Dungeon.
This version created December 12.

You are in an open field west of a big white house, with a boarded
front door.
There is a small mailbox here.
>Opening the mailbox reveals a leaflet.
>Taken.
>Dropped.
>You are empty handed.
>You are in an open field west of a big white house, with a boarded
front door.
There is a small leaflet here.
There is a small mailbox here.
>Taken.
>Dropped.
>You are in an open field west of a big white house, with a boarded
front door.
There is a small leaflet here.
There is a small mailbox here.
>Beg pardon?
>
```

Checkpoints (X1, at each READSTRING entry; trailers `!-ROOMS`/`!-OBJECTS`
omitted): HERE is WHOUS throughout; score 0. `drop leaflet` (CP 3 and CP 7)
makes WHOUS ROBJS `(ADVER FDOOR MAILB)` with `robjs_tail_shared` T: the
REST of the new list is `==?` the previous list (INSERT-OBJECT's final
SEGMENT shares the tail). `take leaflet` from the room (CP 6) leaves
`(FDOOR MAILB)`. The leaflet's OCAN is MAILB until the first take, its OROOM
WHOUS after each drop. MOVES 0..8; CP 8 = CP 9 (the end-of-input read
changes nothing). RANDOM: START's seed call `<RANDOM 10438660480>` →
16566282405, then one `<RANDOM>` in each `look` (−21802663835 before CP 5,
12914488375 before CP 8); neither changes the visible text.

TAKE-OBJECT is not on this path (only the boat repair and CONS-OBJ use it);
its effect is recorded by the probe case `game-insert-take-object`
(`SEGMENT-CHTYPE-REFERENCE.md`).
