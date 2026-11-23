# M4 S2 reference: CHTYPE to SEGMENT and runtime-built SEGMENTs

Date: 2026-11-23. Read-only reference investigation for frontier F1
(`S1-HOUSE-CELLAR-FRONTIER.md`). Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before
and after (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; fixed clock 250776000, TZ=UTC
(shim `scripts/reference/fixed_time.c`, sha256 `d1fa8652…b925`).

Command: `python3 -I scripts/probe_segment_chtype_reference.py docs/evidence/M4/segment-chtype-probe.json`
→ exit 0, 31 cases (one mdli process each, pipe mode; language cases in an
empty `$TMPDIR` directory, the game case in a fresh copy of
`patched_confusion`). Record: `segment-chtype-probe.json` (sha256
`88b79f9d…8d08`), raw stdout/stderr per case.

## Findings

| Case | Observation |
|---|---|
| type-of-chtype | `<TYPE <CHTYPE <FORM A B> SEGMENT>>` SEGMENT; PRIMTYPE LIST; `<TYPEPRIM SEGMENT>` LIST |
| reader-segment-is-same-type | `<TYPE '!.X>` SEGMENT, PRIMTYPE LIST, `<1 '!.X>` LVAL, `<2 '!.X>` X, `<1 '!,X>` GVAL, `<LENGTH '!<A B C>>` 3, `<=? '!<A B> <CHTYPE <FORM A B> SEGMENT>>` T: **the reader's segment and the CHTYPE'd one are one object type** over the FORM's elements |
| identity-sharing | `==?`/`=?` SEGMENT vs its FORM: FALSE/FALSE; `<==? <CHTYPE .S FORM> .F>` T; `=?` T; LIST views `==?` T; `<CHTYPE .S SEGMENT>` and `<CHTYPE .F SEGMENT>` are `==?` to `.S`; `<PUT .S 2 C>` → `.F` is `<A C>`; `<PUT .F 1 D>` → `.S` is `!<D C!>`: **CHTYPE shares the cells**. LENGTH 2, `<TYPE <REST .S>>` LIST |
| print-forms | `!<REST (1 2 3)!>`, `!.X`, `!,X`, `!<!>`; PRIN1 `!<A B!>`; UNPARSE `"!<A B!>"` (recorded only; printing stays strict here) |
| list-primtype-sources | from LIST `!<A B!>`, from FALSE `!<!>`, from a LIST NEWTYPE `!<A!>`; SEGMENT → FOO `#FOO (A B)`, → FORM `<A B>`, → LIST `(A B)`, → FALSE `#FALSE (A)` |
| err-vector / err-string / err-uvector / err-fix / err-atom / err-segment-to-vector | stderr `PRIMTYPES do not match in CHTYPE`, back at LISTENING-AT-LEVEL 1 (no ERROR frame) |
| eval-list-splice | `<EVAL <LIST 1 .S 2>>` `(1 6 7 8 2)`; final segment shares: `<==? <REST <EVAL <LIST 0 .S>>> .L>` T, `<==? <EVAL <LIST .S>> .L>` T; non-final copies: `<EVAL <LIST .S 9>>` REST 3 not `==?`; `<EVAL <LIST .S .S>>` `(6 7 8 6 7 8)` |
| eval-list-tail-mutation | PUT on `.L` after a final splice is visible (`(0 60 7 8)`); after a non-final splice it is not (`(60 7 8 0)`) |
| eval-vector-uvector | `[0 6 7 8 9]`, `[6 7 8]`; `<UVECTOR 0 .S>` itself fails `TYPES-DIFFER-IN-UNIFORM-VECTOR` (FIX and SEGMENT values) |
| eval-form-args | SUBR splice `<EVAL <FORM + 1 .S>>` 22; `<FORM LIST 1 .S>` `(1 6 7 8)`, LIST SUBR copies (not `==?`); `<FORM PUT .L 1 .S>` → TOO-MANY-ARGUMENTS-SUPPLIED |
| eval-function-args | interpreted FUNCTION: a `"TUPLE"` formal gets `?[1 6 7 8?]` (spliced); required formals `(A B C)` with `.S` → ILLEGAL-SEGMENT (recorded M2 D2 deviation area) |
| eval-chtype-list-source | `<CHTYPE (LVAL L) SEGMENT>` splices `(0 1 2)`; empty `(0 3)`; VECTOR value `(0 4 5)`; STRING value `(0 !\a !\b)` |
| plain-element-value-stored | `<LIST 1 .S>` → `(1 !.L)`, element TYPE SEGMENT, `==?` `.S`; EVAL of that LIST → `(1 6 7 8)` |
| err-standalone-eval | `ILLEGAL-SEGMENT` "Attempt to evaluate segment outside structured type" |
| err-nonstructured-payload | `ILLEGAL-SEGMENT` "Segment evaluated to nonstructured type" `!<+ 1 2!>` |
| defmac-insert-shape | `<DEFMAC INS ('OBJ 'BOX) <FORM PUT .BOX 1 (.OBJ <CHTYPE <FORM 1 .BOX> SEGMENT>)>>`: EXPAND `<PUT .V 1 (Z !<1 .V!>)>`, element TYPEs `(ATOM SEGMENT)`; after `<INS Z .V>` `[(Z A B)]` and the REST is `==?` the old list; from inside a FUNCTION `[(Y Z A B)]`, REST 2 `==?` old |
| game-insert-take-object | after `<FLOAD "77loadall.mud">` (no SAVE-IT; R = LROOM, O = ADVER, W = ,PLAYER): EXPAND `<INSERT-OBJECT .O .R>` = `<PUT .R 7 (<PUT .O 19 .R> !<ROBJS .R!>)>`, `<TAKE-OBJECT .O .W>` = `<PUT .W 2 (<PUT .O 19 #FALSE ()> !<AOBJS .W!>)>`; LIST element TYPEs `(FORM SEGMENT)`. INSERT-OBJECT: ROBJS becomes `(ADVER WDOOR DOOR TCASE LAMP RUG PAPER SWORD)`, its REST `==?` the old list, OROOM = LROOM. TAKE-OBJECT: AOBJS `(ADVER)` (REST `==?` old `()`), OROOM FALSE; then LAMP: `(LAMP ADVER)`, REST `==?` old |

Every EVAL case also has a `-via-macro` twin (`<DEFMAC EV (X) .X>`, then
`<EV x>` in place of `<EVAL x>`); all nine twins print exactly the same
results as their EVAL case. The runtime has no EVAL SUBR (the game reaches
EVAL only in the ILO anti-tamper path, `77act1.mud:20`), so the unit tests
use EV; a macro expansion is how INSERT-OBJECT's LIST is evaluated in the
game.

Side observation: after FLOAD every top-level result is followed by
`Atom REP has neither LVAL nor GVAL` on stderr (81tell-repl.mud); it is
unrelated to SEGMENT.

Confusion (GPLv3) is executed only as a reference binary; no source copied.
