# M4 S4 reference: the TOP SUBR

Date: 2026-11-23. Read-only reference investigation for issue #157 (frontier
item 3 of `S1-HOUSE-CELLAR-FRONTIER.md`). Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before
and after (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; fixed clock 250776000, TZ=UTC
(shim `scripts/reference/fixed_time.c`, sha256 `d1fa8652…b925`).

Command: `python3 -I scripts/probe_top_reference.py docs/evidence/M4/top-probe.json`
→ exit 0, 28 cases (one mdli process each, pipe mode; language cases in an
empty `$TMPDIR` directory, the game case in a fresh copy of
`patched_confusion`). Record: `top-probe.json` (sha256 `169c5ec2…ee0b`),
raw stdout/stderr per case (latin-1).

Manual: *The MDL Programming Language* §7.6.2.2 (`<TOP array>` returns the
array with all elements put back that REST removed: "the inverse of all
RESTs"); the manual describes TOP and BACK for VECTOR, UVECTOR and STRING
(arrays), not LISTs.

## The game's TOP calls (grep of the pinned `.mud` files)

| Site | Form | Operand |
|---|---|---|
| `77np.mud:126` SPARSE | `<TOP <PUT <BACK .PVR> 1 <PUT <PUT <1 .PRV> 1 .PREP> 2 .LOBJ>>>` | a REST view of PRSVEC (VECTOR, 3 slots) |
| `77rooms.mud:1284` EVERYTHING, `:1330` VALUABLES | AUX `(SUV ,OBJ-UV) (TUV <TOP .SUV>)` | `OBJ-UV = <CHUTYPE <REST <IUVECTOR 20> 20> OBJECT>` (`:1249`), an empty UVECTOR view |
| `77act2.mud:505, 557` balloon | AUX `(S <TOP ,SCRSTR>)` | `SCRSTR = <REST <ISTRING 5> 5>` (`77np.mud:354`) |
| `77rooms.mud:317-318, 355-356, 368-369` MAKE-SCRIPT, DO-SCRIPT, DO-UNSCRIPT | `<PUT <TOP ,INCHAN> 1 (.CH)>` | the terminal CHANNELs; only after an OPEN "PRINT" succeeded (denied here, ADR-0055) |

## Findings

| Case | Observation |
|---|---|
| vector-top | `R = <REST [1 2 3 4] 2>`: `<TOP .R>` `[1 2 3 4]`, TYPE VECTOR, LENGTH 4, `==?` V T, `=?` V T; `<TOP .V>` `==?` V T; TOP of the empty end view `<REST .V 4>` `[1 2 3 4]`, `==?` V T; `<==? <TOP .R> .R>` FALSE; R still LENGTH 2 |
| vector-identity | `<==? <TOP .R> <TOP <REST .V 1>>>` T; `<==? <TOP .R> <BACK .R 2>>` T; `<BACK .R 1>` FALSE; TOP of TOP `==?` V T; an equal fresh `[1 2 3 4]`: `==?` FALSE, `=?` T; TOP of a REST of another literal `==?` V FALSE |
| vector-aliasing | PUT through `<TOP .R>` changes V (`[X 2 3 4]`); PUT through R shows in TOP (`[X 2 Y 4]`); PUT on V before TOP shows (`[X Z Y 4]`); `<PUT <TOP .R> 4 W>` shows in R (`[Y W]`); a TOP result saved before a later PUT on V shows it (`[Q Z Y W]`) |
| vector-back-view | `B = <BACK <REST [1 2 3 4 5] 4> 2>` `[3 4 5]`; `<TOP .B>` `[1 2 3 4 5]`, `==?` V T; `<TOP <BACK <REST .V 1> 1>>` the whole vector |
| empty-arrays | `<TOP []>` `[]`; `<TOP <REST [] 0>>` `[]`; `<TOP <REST [1] 1>>` `[1]`; `<TOP "">` `""`; `<LENGTH <TOP <REST "ab" 2>>>` 2; `<TOP <IUVECTOR 0>>` `![!]`; `<==? <TOP .E> .E>` T |
| uvector-top | `U = <IUVECTOR 4 7>`: `<TOP <REST .U 4>>` `![7 7 7 7!]`, `==?` U T; UTYPE FIX, TYPE UVECTOR, LENGTH 4; PUT through `<REST .U 3>` shows in TOP (`![7 7 7 9!]`); PUT through TOP shows in U (`![8 7 7 9!]`) |
| uvector-objuv-shape | `W = <CHUTYPE <REST <IUVECTOR 3> 3> FIX>`: UTYPE FIX, LENGTH 0; `<TOP .W>` UTYPE FIX, LENGTH 3, `![0 0 0!]`; with `T = <TOP .W>` and `S = .W`: `<==? .S .T>` FALSE after 0, 1, 2 `<SET S <BACK .S>> <PUT .S 1 n>` steps and **T after the third** (EVERYTHING's "ran out of room" test); `<TOP .W>` `![7 6 5!]`; W still LENGTH 0 |
| string-top | `R = <REST "abcdef" 3>`: `<TOP .R>` `"abcdef"`, `==?` S T, `=?` S T, TYPE STRING, LENGTH 6; `<TOP .S>` `==?` S T; `<TOP <MEMQ !\c "abcd">>` `"abcd"`; TOP of a BACK view `"abcdef"`; an equal separate literal: `==?` FALSE |
| string-scrstr-shape | `SS = <REST <ISTRING 5> 5>`: LENGTH 0, `<LENGTH <TOP ,SS>>` 5, codes `(0 0 0 0 0)`; `<PUT <TOP ,SS> 5 !\x>` then `<BACK ,SS 1>` `"x"`; `<PUT <BACK ,SS 2> 1 !\y>` shows in the saved TOP (codes `(0 0 0 121 120)`); `<==? <TOP ,SS> <BACK ,SS 5>>` T |
| string-aliasing | `S = <ISTRING 4 !\a>`, `R = <REST .S 2>`: PUT through TOP → S `"baaa"`; PUT through R → TOP `"baca"`; PUT on S → TOP `"bacd"` |
| newtype-vector | `<NEWTYPE FOO VECTOR>`, `F = #FOO [1 2 3]`: `<TYPE <TOP .F>>` **FOO**, `==?` F T; `<TYPE <REST .F>>` VECTOR, so `<TOP <REST .F>>` is the VECTOR `[1 2 3]`; `<TOP <CHTYPE <REST .V 2> FOO>>` `#FOO [1 2 3 4]` (TYPE FOO), `==?` V FALSE, `=?` V FALSE (TYPEs differ), CHTYPE back to VECTOR `==?` V T; PUT through it changes V |
| newtype-string-uvector | `<NEWTYPE BAR STRING>`: `<TOP <CHTYPE <REST "hello" 2> BAR>>` TYPE BAR, LENGTH 5, CHTYPE back to STRING `==?` the STRING T; `<NEWTYPE BAZ UVECTOR>`: TYPE BAZ, LENGTH 3, UTYPE FIX (printing a CHTYPE'd STRING is avoided: in an ad-hoc run it printed `#BAR "hello"` and then upset the REP) |
| channel-top | `<TOP ,INCHAN>` TYPE **CHANNEL**, LENGTH **21** (INCHAN 19): `#CHANNEL [() 0 1 "READ" "" … ]`; slot 1 `()` (the LIST the script code PUTs channels into), slot 2 `0`, slot 3 `1` = `<1 ,INCHAN>`; `<TYPE <BACK ,INCHAN 2>>` CHANNEL and `<==? <TOP ,INCHAN> <BACK ,INCHAN 2>>` T; `<TOP <REST ,INCHAN 3>>` TYPE VECTOR (REST dropped CHANNEL), LENGTH 21; OUTCHAN the same (CHANNEL, 21, `()`, `0`) |
| err-channel-back-3 | `<BACK ,INCHAN 3>`: stderr `Offset to BACK too large` (two slots before element 1) |
| err-list, err-rested-list, err-form, err-false, err-segment, err-fix, err-atom, err-character | stderr `Bad type for TOP`, back at LISTENING-AT-LEVEL 1 (no ERROR frame; same style as `PRIMTYPES do not match in CHTYPE`) |
| err-tuple, err-rested-tuple | `<TOP .T>` and `<TOP <REST .T 2>>` on a `"TUPLE"` argument: `Bad type for TOP` |
| err-too-few-args / err-too-many-args | `<TOP>`: `TOO-FEW-ARGUMENTS-SUPPLIED`; `<TOP [1] 2>`: `TOO-MANY-ARGUMENTS-SUPPLIED` (ERROR, level 2) |
| grow-unbound | `<GROW [1 2] 1 2>`: `UNBOUND-VARIABLE … GROW`: GROW is not a SUBR of this build, so "TOP after GROW" is not observable (and GROW is not implemented in this runtime) |
| game-top-operands | after `<FLOAD "77loadall.mud">`: OBJ-UV LENGTH 0, UTYPE OBJECT; `<TOP ,OBJ-UV>` LENGTH 20, UTYPE OBJECT, TYPE UVECTOR, `==?` `<BACK ,OBJ-UV 20>` T; SCRSTR LENGTH 0, TOP LENGTH 5, TYPE STRING, `==?` `<BACK ,SCRSTR 5>` T; PRSVEC VECTOR of 3, `<TOP <REST ,PRSVEC>>` and `<TOP <REST ,PRSVEC 2>>` `==?` PRSVEC T; `<TOP ,INCHAN>` CHANNEL, 21, slot 1 `()` |

## Summary for the specification

* TOP is defined on the array PRIMTYPEs (VECTOR, UVECTOR, STRING) only. It
  returns a view of the **same storage** from its first element to its end:
  no copy; mutations before and after are visible through every view; the
  result is `==?` to the unrested original, to every other TOP of that
  storage and to a BACK reaching the start.
* TOP keeps the **argument's TYPE** (a NEWTYPE, CHANNEL); REST and REST-0
  drop it first, so `<TOP <REST x>>` has the PRIMTYPE. UVECTOR element type
  is shared.
* LIST-primtype values (LIST, FORM, FALSE, SEGMENT), TUPLEs and non-structured
  values are refused (`Bad type for TOP`); the reference never invents LIST
  semantics for TOP.
* The terminal CHANNELs have **two** slots before element 1; TOP exposes both
  (slot 1 is the script/echo channel LIST).
