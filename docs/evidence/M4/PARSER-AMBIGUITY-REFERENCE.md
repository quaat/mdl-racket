# M4 S7 reference capture: parser rejection and ambiguity (scenario `parser-ambiguity`)

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

Command: `python3 -I scripts/probe_parser_ambiguity_reference.py docs/evidence/M4/parser-ambiguity-reference.json`
→ exit 0 (71 runs, pipe mode, about 16 s). Record:
`parser-ambiguity-reference.json` (sha256 `ca8ed4e9…389a`), T1 stdout
sha256 `39f43238…98c0`. Local paths in the record (diagnostic DIAG.LOG
names) are written as `$TMPDIR` / `<repo>`; the transcript cases contain
none (asserted by the script).

Scenario (`tests/scenarios/parser-ambiguity.json`): `<FLOAD "77loadall.mud">`,
`<SAVE-IT>`, then 34 lines: `xyzzy`, `frobozz`, an empty line, a line of
three blanks, `inven`, `inventoryxyz`, `INVENTORY`, `the`, `mailbox`,
`take`, `take it`, `open brass`, `take wooden mailbox`,
`open mailbox door mailbox`, `open with with mailbox`, `take "leaflet"`,
`take the the the the the the the the the leaflet`, `northeast`, `east`,
`open window`, `west`, `up`, `take knife`, `down`, `west`, `move rug`,
`open door`, `trap`, `open door`, `xyzzy`, `wooden`, `Take BRASS Lantern`,
`take all`, `score`, then end of input.

## Choosing the command list

Source reading of the parser (`77np.mud`, LEX/RDCOM in `77rooms.mud`)
listed the rejection messages and which object names are shared. The only
start-area ambiguity reachable without new puzzles is `door` in the living
room: WDOOR (names `DOOR`, adjective `WOODE`, `77dung.mud:1660`) is always
visible, and the trap door (OID `DOOR`, adjective `TRAP`, `77dung.mud:1654`)
becomes visible after `move rug`. THIS-IT? (`77rooms.mud:1549`) matches an
object by OID or ONAMES, so both match `door`, SEARCH-LIST returns NEFALS,
and SPARSE prints `Which door?` (`77np.mud:88`) and records the orphan
(`ORPHAN T <verb> <2 .PV> .PREP .ATM`). Two exploratory native runs (the
first ended with `look` instead of `take all`/`score`) confirmed every
response. Commands already covered by other scenarios were left out:
`throw leaflet`/`kill mailbox` with an orphan answer (orphan-prompt), the
dangling preposition and `put all in`/`take all`/`drop all` at West of House
(top-parser). `help`, `info` and a leading `?` (LEX turns it into HELP) are
strict by maintainer decision (OPEN "READ", frontier F3) and are not used.

## Runs and checks

* T1 / T1b: the transcript, byte-identical twice (`t1_equals_t1b_bytes`).
* P00–P33: the first k commands, then EOF; each equals T1 cut after the
  (k+1)-th prompt plus the end-of-input reply (`prefix_runs_consistent_with_t1`).
* X1: diagnostic (not a transcript). Forms typed after FLOAD and before
  SAVE-IT wrap RANDOM and READSTRING (the original SUBR is applied to the
  same arguments and its value returned) and log to `DIAG.LOG` outside the
  game copy; a read-only checkpoint at every READSTRING entry. Game text
  equals T1's byte for byte (`diag_game_part_equals_t1_game_part_bytes`);
  36 checkpoints.
* D00–D33: X1 cut after k commands; their last checkpoint is the state after
  the end-of-input empty command (`Beg pardon?`): the state a per-prefix
  candidate run ends in (`end_checkpoints`; k = 34 is X1's last). Each game
  text equals Pkk's.

Checkpoint fields: HERE; `<LIT? ,HERE>` (T or FALSE); winner AOBJS; the 10
LEXV strings; PRSVEC (OID, `(PREP OID)` for a PHRASE, `(TYPE VNAME)` for a
VERB/ACTION, else the TYPE); PARSE-WON (`UNASSIGNED` before the first
command); ORPHANS flag, verb VNAME, OSLOT1, OPREP (as ATOM), ONAME;
TRAP-DOOR!-FLAG; the trap door's OVISON bit (TRNN-style); RAW-SCORE, ASCORE,
MOVES.

## Transcript (game part, CRs as printed `<CR>`)

```
Welcome to Dungeon.<CR>
This version created December 12.

You are in an open field west of a big white house, with a boarded<CR>
front door.
There is a small mailbox here.
>I don't know the word XYZZY                                    (xyzzy)
>The FROBOZZ Corporation created, owns, and operates this dungeon.  (frobozz)
>Beg pardon?                                                    (empty line)
>Huh?                                                           (three blanks)
>You are empty handed.                                          (inven)
>You are empty handed.                                          (inventoryxyz)
>You are empty handed.                                          (INVENTORY)
>Huh?                                                           (the)
>What should I do with the mailbox?                             (mailbox)
>Nice try.                                                      (take)
>Take what?                                                     (take it)
>Dangling adjective?                                            (open brass)
>I can't see a woode mailb here.                                (take wooden mailbox)
>Too many objects specified?                                    (open mailbox door mailbox)
>Double preposition?                                            (open with with mailbox)
>Take what?                                                     (take "leaflet")
>Take what?                                                     (take the ×9 leaflet)
>You are facing the north side of a white house.  There is no door here,<CR>
and all the windows are barred.                                 (northeast)
>You are behind the white house.  In one corner of the house there<CR>
is a small window which is slightly ajar.                       (east)
>With great effort, you open the window far enough to allow entry.
>You are in the kitchen of the white house.  [...]              (west)
>It is pitch black.  You are likely to be eaten by a grue.      (up)
>It is too dark in here to see.                                 (take knife)
>Kitchen
On the table is an elongated brown sack, smelling of hot peppers.
A bottle is sitting on the table.
The glass bottle contains:
 A quantity of water                                            (down)
>You are in the living room.  [...]                             (west)
>With a great effort, the rug is moved to one side of the room.<CR>
With the rug moved, the dusty cover of a closed trap-door appears.
>Which door?                                                    (open door)
>The door reluctantly opens to reveal a rickety staircase descending<CR>
into darkness.                                                  (trap)
>Which door?                                                    (open door)
>I don't know the word XYZZY                                    (xyzzy)
>The door cannot be opened.                                     (wooden)
>Taken.                                                         (Take BRASS Lantern)
>sword:<CR>
  Taken.
newspaper:<CR>
  Taken.
carpet:<CR>
  The rug is extremely heavy and cannot be carried.             (take all)
>
Your score would be 10 [total of 500 points], in 33 moves.
This score gives you the rank of Beginner.                      (score)
>Beg pardon?
>
```

The full text (kitchen and living-room descriptions) is in the record.
stderr: `Error: Unexpected EOF`; exit status 0.

## Diagnostic findings

* MOVES: every non-empty line counts, including unknown words, the line of
  blanks and every rejected sentence; the empty line does not (RDCOM
  increments MOVES only when READSTRING returned a length > 0,
  `77rooms.mud:620-621`; `Beg pardon?` at `:641`). 34 lines, 33 moves.
* LEX (`77rooms.mud:1559`): each word upper-cased and cut to 5 letters
  (`inven`, `inventoryxyz`, `INVENTORY` all give `"INVEN"`; `northeast`
  gives `"NORTH"`, a direction, so the player walks north). A `"` starts
  quoting and skips one LEXV slot, which SPARSE reads as an empty word and
  stops (`take "leaflet"` lexes to `("TAKE" "" "LEAFL" …)` and parses as
  `take`). LEXV has 10 slots; the 11th word (`leaflet`) is dropped silently
  (RDCOM calls LEX with SILENT? T, so `I'm too simple-minded for that.`,
  `:1584`, is not printed). The blank line lexes to ten empty strings;
  SPARSE then has no verb and no object: `Huh?` (`77np.mud:108`).
* Buzz words (`77dung.mud:69`, incl. `THE`, `IT`) are skipped: `the` alone
  is `Huh?`; `take it` is `take` with no object, ORTELL `Take what?`.
* ORPHANS: `the` sets the flag only; `mailbox` (no verb) prints
  `What should I do with the mailbox?` and records OSLOT1 = MAILB
  (checkpoint 9); the next `take` has no object, SYN-MATCH's ORFEO
  (`77np.mud:212`) supplies the mailbox, TAKE finds it not takeable and
  prints a YUKS remark (`Nice try.`, one RANDOM draw); EPARSE clears the
  orphan on success. `open door` sets flag T, verb OPEN, ONAME DOOR
  (checkpoints 27, 29); the unknown word `xyzzy` leaves it in place
  (checkpoint 30); the adjective answers `trap` / `wooden` take SPARSE's
  ADJECTIVE branch, which replaces the word by the orphan's noun
  (`<SET X <SPNAME .ATM>>`, `77np.mud:51-55`), so the sentence becomes
  `open trap door` / `open wooden door`. TRAP-DOOR!-FLAG becomes T after
  `trap` (checkpoint 28 on).
* `I can't see a woode mailb here.`: PRSTR (`77np.mud:230`) prints the
  5-letter PNAMEs of the adjective and noun atoms in lower case.
* `open mailbox door mailbox`: the first two objects fill PRSVEC (MAILB,
  FDOOR, checkpoint 14), the third finds PVR empty: `Too many objects
  specified?` (`77np.mud:61`).
* The attic (`up`) is dark: `<LIT? ,HERE>` false at checkpoints 22–23 and
  SPARSE's branch for a FALSE from GET-OBJECT prints `It is too dark in
  here to see.` instead of `I can't see a …` (`77np.mud:74-81`).
* RANDOM (4 calls): START's seeding call → 16566282405; `take` (YUKS remark,
  PICK-ONE) → -21802663835; `down` out of the dark attic: two draws
  (12914488375, -6577089531; by source reading WALK's `<PROB 75>`,
  `77rooms.mud:1063`, and ROOM-INFO's `<PROB 80>` for the revisited
  kitchen, `:523`). Logged with the number of checkpoints before them
  (0, 10, 24, 24).
* After a verb has run, PRSVEC slot 2 reads FALSE at the next READSTRING
  (e.g. checkpoints 10 and 28); caller not traced (both engines are
  compared on it).
* End checkpoints equal the READSTRING-entry checkpoints except LEXV (all
  empty after the end-of-input empty line) and PARSE-WON (FALSE).

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source was copied.
