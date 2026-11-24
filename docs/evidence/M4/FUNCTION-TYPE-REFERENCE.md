# M4 S5b reference: TYPE of applicable values (frontier F4)

Date: 2026-11-23. Read-only reference investigation for frontier F4
(`S1-HOUSE-CELLAR-FRONTIER.md`): SWORD `77act1.mud:1903`
`<TYPE? ,SWORD-GLOW NOFFSET>`. Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before
and after (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; fixed clock 250776000, TZ=UTC
(shim `scripts/reference/fixed_time.c`, sha256 `d1fa8652…b925`).

Command: `python3 -I scripts/probe_function_type_reference.py docs/evidence/M4/function-type-probe.json`
→ exit 0, 19 cases (one mdli process each, pipe mode; language cases in an
empty `$TMPDIR` directory, the game case in a fresh copy of
`patched_confusion`). Record: `function-type-probe.json` (sha256
`da65b478…b446`; re-recorded in M4 S8 to add ABS, earlier records `0dac64dc…861f` (M4 S5a, adding MAX) and `398d250e…489a`), raw stdout/stderr per case (latin-1), the probed name lists
`builtin_names` and `special_names`.

Manual: *The MDL Programming Language* §9.1 (a FUNCTION is a LIST-primtype
object: the formal LIST followed by the body), §9.3 (SUBR/FSUBR), §17.1
(MACRO), §6.4 (TYPE, TYPE?, PRIMTYPE).

## What SWORD-GLOW and NOFFSET are (pinned game source)

* `SWORD-GLOW` is an ordinary DEFINEd FUNCTION, `77act1.mud:1877-1897`
  `<DEFINE SWORD-GLOW (DEM "AUX" (SW <HOBJ .DEM>) (G <OTVAL .SW>) (NG 0)) ...>`:
  the sword demon. While the sword is carried it computes the glow level (2:
  a villain in this room, 1: a villain in an adjacent room, 0 otherwise),
  prints a message when the level changes and stores it in the sword's OTVAL;
  when the sword is not carried it disarms itself with `<PUT .DEM ,HACTION <>>`.
* `SWORD-DEMON` (`77dung.mud:416`) is a HACK
  `<CHTYPE [SWORD-GLOW ,VILLAINS () <1 ,ROOMS> <FIND-OBJ "SWORD"> <>] HACK>`
  whose HACTION (slot 1) is the ATOM SWORD-GLOW; HACTION is declared
  `RAPPLIC` = `<OR ATOM FALSE NOFFSET>` (`77defs.mud:5, 263`). The demon loop
  (`77rooms.mud:645`) applies HACTION with APPLY-RANDOM.
* `NOFFSET` is `<NEWTYPE NOFFSET WORD>` (`77defs.mud:4`): the PDP-10
  compiled-code offset type. The interpreted 1977 source never makes a value
  of TYPE NOFFSET, so every `<TYPE? x NOFFSET>` is FALSE.
* SWORD (`77act1.mud:1899-1906`) runs on `take sword` (TAKE
  `77rooms.mud:1098` → APPLY-OBJECT `77rooms.mud:1129`): `<PUT ,SWORD-DEMON
  ,HACTION <COND (<TYPE? ,SWORD-GLOW NOFFSET> ,SWORD-GLOW) (SWORD-GLOW)>>`
  re-arms the demon with the ATOM SWORD-GLOW (the second clause's value).
  The same shape is in ROBBER (`77act1.mud:1529, 1564`), FUNCTION-PRINT
  (`77defs.mud:503-513`) and CEVENT handling (`77rooms.mud:1642-1649`).

## Findings

| Case | Observation |
|---|---|
| define-function | `<DEFINE F (X) <+ .X 1>>` → `F` (the name ATOM); `<TYPE ,F>` FUNCTION; `<PRIMTYPE ,F>` LIST; `<TYPE? ,F FUNCTION>` FUNCTION; `<TYPE? ,F SUBR FSUBR FUNCTION>` FUNCTION; `<TYPE? ,F SUBR FSUBR>`, `<TYPE? ,F MACRO>` FALSE; after `<NEWTYPE NOFFSET WORD>`, `<TYPE? ,F NOFFSET>` FALSE and SWORD's COND returns the ATOM `F`; `<==? <TYPE ,F> FUNCTION>` T; `<APPLICABLE? ,F>` T; `<DECL? ,F FUNCTION>` T; `<DECL? ,F <OR ATOM FALSE NOFFSET>>` `#FALSE (#FUNCTION ((X) <+ .X 1>) ATOM)`; `<F 4>`, `<APPLY ,F 4>` 5; `<MAPF ,LIST ,F (1 2 3)>` `(2 3 4)` |
| define-shapes | no args, `#DECL`, OPTIONAL/AUX, TUPLE, leading activation ATOM, "NAME", quoted formal: every one TYPE FUNCTION; each DEFINE returns its name |
| function-identity | `<==? ,F ,F>` T; `<SETG F2 ,F>` (prints `#FUNCTION ((X) .X)`), `<==? ,F ,F2>` T, `<=? ,F ,F2>` T, TYPE FUNCTION; `<==? ,F <GVAL F>>` T; a second `<DEFINE G (X) .X>`: `<==? ,F ,G>` FALSE, **`<=? ,F ,G>` T** (structural); an LVAL copy `==?` T |
| function-literal | `<FUNCTION (X) .X>` TYPE FUNCTION, PRIMTYPE LIST; applied through a GVAL: 5 |
| function-structure | `<LENGTH ,F>` 2, `<1 ,F>` `(X)`, `<2 ,F>` `<+ .X 1>`, `<EMPTY? ,F>` FALSE; `<CHTYPE ,F LIST>` `((X) <+ .X 1>)` (TYPE LIST; `<REST>` of two CHTYPEs `==?` T: the same cells); CHTYPE back to FUNCTION applies (5); `<CHTYPE '((Y) <* .Y 2>) FUNCTION>` applies (10) |
| function-printing | `,F` / UNPARSE / PRIN1 / PRINC print `#FUNCTION ((X) <+ .X 1>)` |
| function-uvector | `<UVECTOR ,F ,G>` `![#FUNCTION ((X) .X) #FUNCTION ((X) .X)!]`, UTYPE FUNCTION |
| macro | DEFMAC: TYPE MACRO, PRIMTYPE LIST, `<TYPE? ,M MACRO>` MACRO, `<TYPE? ,M FUNCTION>` FALSE, APPLICABLE? T, `<M>` 3 |
| builtin-subr | `<TYPE ,+>` SUBR, PRIMTYPE WORD, `<TYPE? ,+ SUBR>` SUBR, `<TYPE? ,+ FUNCTION>` FALSE, APPLICABLE? T, `<DECL? ,+ SUBR>` T, `==?` T; `<SETG PLUS ,+>` prints `#SUBR *0000000000000000000117*`, `==?` T, TYPE SUBR, applies; `<TYPEPRIM SUBR>` WORD, `FSUBR` WORD, `FUNCTION` LIST, `MACRO` LIST |
| builtin-subr-types | `<TYPE ,n>` is **SUBR** for every one of the 114 probed names: the 113 names this runtime binds to a host built-in (`builtin-table` of `mdl/runtime/core.rkt` at `adbe410`, plus MAX added by M4 S5a and ABS added by M4 S8) and FLOAD |
| special-form-types | QUOTE, DEFINE, DEFMAC, FUNCTION, PROG, REPEAT, UNWIND, GDECL, COND, AND, OR: **FSUBR**; RETURN, AGAIN, NOT: **SUBR** |
| fsubr | `<TYPE ,COND>` FSUBR, PRIMTYPE WORD, `<TYPE? ,COND SUBR FSUBR>` FSUBR, APPLICABLE? T, `<GASSIGNED? COND>` T |
| applicable-other | `<APPLICABLE? 3>` T; ATOM, LIST, FALSE: FALSE |
| subr-printing | `,+` and UNPARSE: `#SUBR *0000000000000000000117*` (an address) |
| err-chtype-subr-list, err-chtype-vector-function, err-apply-fix-function | `<CHTYPE ,+ LIST>`, `<CHTYPE [1 2] FUNCTION>`, `<CHTYPE 1 FUNCTION>`: stderr `PRIMTYPES do not match in CHTYPE` |
| err-decl-applicable | `<DECL? ,F APPLICABLE>`: ERROR `BAD-TYPE-SPECIFICATION1` (no ATOM APPLICABLE at startup in this build) |
| game-sword-glow | after `<FLOAD "77loadall.mud">`: `<TYPE ,SWORD-GLOW>` FUNCTION, PRIMTYPE LIST, `<TYPE? ,SWORD-GLOW NOFFSET>` FALSE, `<TYPEPRIM NOFFSET>` WORD; SWORD, ROBBER, RDCOM: FUNCTION; `<TYPE? ,ROBBER NOFFSET>` FALSE; SWORD-DEMON TYPE HACK, HACTION the ATOM `SWORD-GLOW`; the sword's OTVAL 0; SWORD's COND → `SWORD-GLOW`; `<TYPE ,FLOAD>` SUBR |

## Summary for the specification

* Every DEFINE (whatever its formals) and every FUNCTION literal is TYPE
  FUNCTION, PRIMTYPE LIST; DEFMAC is MACRO; every built-in this runtime binds
  is SUBR; the compiler-handled special forms are FSUBR (RETURN, AGAIN, NOT:
  SUBR). TYPE? NOFFSET is FALSE for all of them, so SWORD stores the ATOM.
* The reference treats a FUNCTION as its formals+body LIST (LENGTH, NTH,
  CHTYPE to and from LIST, `=?` by structure, printing). This runtime's
  compiled DEFINE keeps no such LIST; see SEMANTICS "M4 S5b" for the strict
  refusals.
* `<DEFINE ...>` returns the name ATOM in the reference.

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source was copied.
