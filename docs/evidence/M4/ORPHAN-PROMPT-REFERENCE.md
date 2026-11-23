# M4 S3 scenario reference: orphan prompts

Date: 2026-11-23. Scenario `tests/scenarios/orphan-prompt.json`: fresh boot
(`<FLOAD "77loadall.mud">`, `<SAVE-IT>`), fixed clock 250776000 / UTC, then
`open mailbox`, `take leaflet`, `throw leaflet`, `mailbox`, `look`,
`take leaflet`, `kill mailbox`, `leaflet`, `inventory`, end of input.

Why these commands: `throw leaflet` and `kill mailbox` are the two orphan
prompts reachable at West of House (THROW wants an indirect object after
AT, KILL one after WITH; SYN-MATCH → ORPHAN → ORTELL `77np.mud:226` → PRSTR
→ FOOSTR `77np.mud:241`, the CHTYPE to CHARACTER). Each prompt is followed
by the player's answer, which SPARSE's orphan branch (`77np.mud:113-122`)
merges into the stored sentence. `kill mailbox` stands in for frontier F2's
`kill troll`, which needs the walk to the troll room; that exact path is
captured separately as case F2 (below). `look` and the second `take`
confirm that the thrown leaflet landed in the room (INSERT-OBJECT, S2).

Command: `python3 -I scripts/probe_orphan_prompt_reference.py docs/evidence/M4/orphan-prompt-reference.json`
→ exit 0. Pinned mdli sha256 `6df359f6…b789` before and after (not rebuilt);
upstream `bdcd4a67…19b3`. Record `orphan-prompt-reference.json` (sha256
`7f8b9118…9443`). Cases: T1, T1b (repeat), X1 (diagnostic), F2 (frontier
transcript), P00–P08 (prefixes). Checks: `t1_equals_t1b_bytes`,
`diag_game_part_equals_t1_game_part_bytes`, `prefix_runs_consistent_with_t1`
all true; 11 checkpoints (n = 0..10); every exit status 0, stderr
`Error: Unexpected EOF`. The only file written is SAVE-IT's
`MDL/MADADV.SAVE`, in the disposable copy. T1 stdout sha256 `3513a55e…d21d`.

Game text (T1, after `"DONE"`):

```
Welcome to Dungeon.
This version created December 12.

You are in an open field west of a big white house, with a boarded
front door.
There is a small mailbox here.
>Opening the mailbox reveals a leaflet.
>Taken.
>at what?
>Thrown.
>You are in an open field west of a big white house, with a boarded
front door.
There is a small leaflet here.
There is a small mailbox here.
>Taken.
>with what?
>Trying to kill a mailbox with a leaflet is suicidal.
>You are carrying:
A leaflet
>Beg pardon?
>
```

Checkpoints (X1, at each READSTRING entry; trailers omitted): HERE is
WHOUS throughout; score 0. The ORPHANS vector is set only while a prompt is
pending: CP 3 (after `throw leaflet`) OFLAG T, OVERB THROW, OSLOT1 ADVER,
OPREP AT, ONAME FALSE; CP 7 (after `kill mailbox`) OFLAG T, OVERB KILL,
OSLOT1 MAILB, OPREP WITH; every other checkpoint has all five slots FALSE
(the answer consumes the orphan). The scratch buffer `<BACK ,SCRSTR 5>`
holds codes `(0 0 0 0 0)` until CP 3, `(0 0 0 97 116)` (`at`) from CP 3,
`(0 119 105 116 104)` (`with`) from CP 7. After `mailbox` (CP 4) the
leaflet is in WHOUS (ROBJS `(ADVER FDOOR MAILB)`, OROOM WHOUS), AOBJS `()`;
`take leaflet` (CP 6) moves it back. MOVES 0..9; CP 9 = CP 10 apart from
n (the end-of-input read changes nothing). RANDOM: START's seed call
`<RANDOM 10438660480>` → 16566282405, then one `<RANDOM>` in the `look`
(−21802663835 before CP 5).

CHTYPE to CHARACTER (X1 wrapper): arguments 97, 116 before CP 3 and 119,
105, 116, 104 before CP 7; nothing else in the scenario.

## Case F2 (frontier transcript, not the scenario)

Input: the S1 house-cellar commands without `score` (`north`, `east`,
`open window`, `west`, `west`, `take lamp`, `move rug`, `open trap door`,
`turn on lamp`, `down`), then `east`, `kill troll`, `lamp`. Stdout sha256
`cfddd111…38a8`. The troll room is followed by `>with what?` and
`>Trying to kill a troll with a lamp is suicidal.`, then `>Beg pardon?`
at end of input. The troll does not attack in these turns.

## Not used (ad hoc, recorded)

Answering a prompt with a prepositional phrase (`kill mailbox`, then
`with leaflet`) raises `ARGUMENT-OUT-OF-RANGE` in the native reference
(ERROR, LISTENING-AT-LEVEL 2). This runtime also fails strictly on that
input, with a different error (`mdl-decl: DECL 26:4: OBJ does not satisfy
declaration`, SPARSE's DECL). Both engines fail; the error kinds differ.
Not part of this slice; a candidate frontier note (see
`S3-CHTYPE-CHARACTER.md`).
