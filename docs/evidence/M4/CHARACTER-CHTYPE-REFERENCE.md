# M4 S3 reference: CHTYPE between FIX (WORD) and CHARACTER

Date: 2026-11-23. Read-only reference investigation for frontier F2/F2b
(`S1-HOUSE-CELLAR-FRONTIER.md`, `S2-CHTYPE-SEGMENT.md`). Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before
and after (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; fixed clock 250776000, TZ=UTC
(shim `scripts/reference/fixed_time.c`, sha256 `d1fa8652…b925`).

Command: `python3 -I scripts/probe_character_chtype_reference.py docs/evidence/M4/character-chtype-probe.json`
→ exit 0, 26 cases (one mdli process each, pipe mode; language cases in an
empty `$TMPDIR` directory, game cases in a fresh copy of
`patched_confusion`). Record: `character-chtype-probe.json` (sha256
`62b6028f…f27d`), raw stdout/stderr per case (latin-1).

## The game's use (77np.mud:220-243, 354)

```
ORTELL  <TELL <PRSTR <CHTYPE .PREP ATOM>> 0 " what?">            ; :226
PRSTR   <FOOSTR <SET SP <SPNAME .ATM>> <BACK ,SCRSTR <LENGTH .SP>> <>>   ; :232
FOOSTR  <MAPR <> <FUNCTION (X Y) ... <COND (<AND .1ST <==? .X .NAM>> <PUT .Y 1 <1 .X>>)
            (<PUT .Y 1 <CHTYPE <+ 32 <ASCII <1 .X>>> CHARACTER>>)>> .NAM .STR>   ; :241
SCRSTR  <SETG SCRSTR <REST <ISTRING 5> 5>>                        ; :354
```

PRSTR lower-cases an ATOM's SPNAME into the tail of the shared 5-character
buffer SCRSTR and returns that tail (a STRING sharing SCRSTR's storage).
Values reaching the CHTYPE in the scenario (CHTYPE wrapper in diagnostic X1
of `orphan-prompt-reference.json`): `throw leaflet` → 97, 116 (`at`);
`kill mailbox` → 119, 105, 116, 104 (`with`). No other CHTYPE to CHARACTER
happens in the scenario.

## Findings

| Case | Observation |
|---|---|
| fix-to-character | `<CHTYPE 65 CHARACTER>` `!\A`; TYPE CHARACTER; PRIMTYPE WORD; `<TYPEPRIM CHARACTER>` WORD; PRIN1 writes `!\A`; PRINC writes `A`; UNPARSE `"!\\A"`; `<TYPE? … CHARACTER>` CHARACTER; 119 → `!\w`; 32 → `!\ ` |
| character-identity | `==?` and `=?` with `!\A`: T, T; two CHTYPEs of 97 `==?` T; 97 vs `!\A` FALSE; CHARACTER vs FIX 97: `==?` FALSE, `=?` FALSE; `<==? <CHTYPE 119 CHARACTER> <ASCII 119>>` T; `<CHTYPE !\A CHARACTER>` `==?` `!\A` T |
| character-to-fix | `<CHTYPE !\A FIX>` 65 (TYPE FIX); `!\a` 97; round trip 119; `<==? <CHTYPE !\w FIX> <ASCII !\w>>` T; `<ASCII <CHTYPE 119 CHARACTER>>` 119; space 32 |
| character-word | `<CHTYPE !\A WORD>` `#WORD *0000000000000000000101*`; WORD → CHARACTER `!\A` (`==?` T); `<CHTYPE <CHTYPE 65 WORD> CHARACTER>` `!\A`, → FIX 65; `NEWTYPE CH WORD`: CH ↔ CHARACTER round trip, `<CHTYPE !\A CH>` `#CH *…101*` |
| range-through-ascii | **no range check**: ASCII of `<CHTYPE n CHARACTER>` returns n for 0, 1, 31, 126, 127, 128, 255, 256, -1, 34359738367, -34359738368; CHTYPE back to FIX: 300 → 300, -1 → -1; `<TYPE <CHTYPE 300 CHARACTER>>` CHARACTER |
| ascii-fix-range | `<ASCII 127>` prints `!\` + implementation bytes; `<TYPE <ASCII 0>>` CHARACTER |
| err-ascii-128 / err-ascii-minus-1 | stderr `Value for ASCII out of range` (ASCII FIX → CHARACTER is range-checked, CHTYPE is not) |
| print-code-0 / 127 / 128 / 255 | `!\^@`; 127, 128, 255 print `!\` followed by implementation bytes (recorded only) |
| float-word-bits | `<ASCII <CHTYPE 1.0 CHARACTER>>` 4607182418800017408 (the host double's bits); 0.0 → 0, TYPE CHARACTER; `<CHTYPE !\A FLOAT>` `0.0000000` |
| character-in-strings | PUT into `<ISTRING 3 !\X>` → `"wXX"`; `<STRING <CHTYPE 104 CHARACTER> "i">` `"hi"`; MEMQ finds it in `"abc"` → `"bc"`; MAPF ,STRING over `"WITH"` with FOOSTR's expression → `"with"`; code 200 PUT into a STRING then ASCII → -56 (8-bit byte) |
| foostr-prstr-shape | FOOSTR/PRSTR/SCRSTR copied under other names: buffer `(0 0 0 0 0)` (ISTRING fills with code 0); `"with"`, `"at"`, `"mailb"`, `"troll"`, `<ATOM "#####">` → `"CCCCC"` (35+32), `A-B` → `"aMb"` (45+32); buffer afterwards `(67 67 97 77 98)` (each PRSTR overwrites the tail); FOOSTR with 1ST defaulted to T keeps the first character: `"With"`; element TYPE CHARACTER |
| err-string/list/atom/vector-to-character, err-character-to-atom/list/string | stderr `PRIMTYPES do not match in CHTYPE`, back at LISTENING-AT-LEVEL 1 |
| err-too-many-args / err-too-few-args | `TOO-MANY-ARGUMENTS-SUPPLIED` / `TOO-FEW-ARGUMENTS-SUPPLIED` (ERROR, level 2) |
| game-prstr | after `<FLOAD "77loadall.mud">`: SCRSTR `(0 0 0 0 0)`; `<PRSTR <CHTYPE <FIND-PREP "WITH"> ATOM>>` `"with"`, then AT `"at"`; SCRSTR `(0 119 105 97 116)` (`at` overwrote the last two of `with`); `<TYPE <1 <PRSTR MAILB!-OBJECTS>>>` CHARACTER, `"mailb"`, SCRSTR `(109 97 105 108 98)`; `<FOOSTR "TROLL" <ISTRING 5 !\X>>` `"Troll"`, with `<>` `"troll"` |
| game-word-pname-range | after FLOAD, over every ATOM of the WORDS, OBJECTS, ACTIONS and DIRECTIONS oblists: max PNAME character code 90, 90, 90, 88 (275, 297, 183, 27 atoms), no PNAME character above 95. PRSTR receives only ATOMs found by LOOKUP in these oblists, so FOOSTR's CHTYPE argument is at most 122 |

## Range decision input

The reference treats CHARACTER as a retag of a 36-bit WORD (any value,
printed with implementation bytes outside ASCII). This runtime's CHARACTER
contract is ASCII 0–127 (ASCII FIX → CHARACTER, where the reference itself
refuses 128 and -1; READSTRING input refuses codes above 127). The
game-reachable values are 65–122 at most. ADR-0057 therefore keeps CHTYPE
to CHARACTER strict at 0–127 and records the wider reference behaviour as a
deviation.

Side observation: after FLOAD every top-level result is followed by
`Atom REP has neither LVAL nor GVAL` on stderr (81tell-repl.mud); it is
unrelated to CHARACTER.

Confusion (GPLv3) is executed only as a reference binary; no source copied.
