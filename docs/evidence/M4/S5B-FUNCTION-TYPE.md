# M4 S5b: TYPE of applicable values (frontier F4)

Date: 2026-11-23. Branch `feat/m4-function-type` at `main` `adbe410`
(uncommitted working tree; the orchestrator commits). Upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`, mit_zork
`d94501340842e006791fce0757dc0043b8ec8916` (`sources.lock.json`). Pinned mdli
sha256 `6df359f6…b789` before and after every capture (never rebuilt). Racket
v7.9 [bc], Python 3.9.2.

Result: **F4 RESOLVED; scenario `sword-glow` PASS (scoped: this scenario
only, transcript plus checkpoints, D1 only)**. Not a PLAYABLE claim and not
the M4 gate.

## The construct

SWORD (`77act1.mud:1899-1906`) runs on every `take sword` (TAKE
`77rooms.mud:1098` → APPLY-OBJECT `:1129`) and evaluates
`<PUT ,SWORD-DEMON ,HACTION <COND (<TYPE? ,SWORD-GLOW NOFFSET> ,SWORD-GLOW)
(SWORD-GLOW)>>` (`:1903`). SWORD-GLOW is an ordinary DEFINEd FUNCTION, the
sword demon (`77act1.mud:1877-1897`); NOFFSET is `<NEWTYPE NOFFSET WORD>`
(`77defs.mud:4`), the PDP-10 compiled-code offset type, which the
interpreted 1977 game never instantiates. So the TYPE? is FALSE and SWORD
re-arms the demon with the ATOM SWORD-GLOW. This runtime stores a compiled
DEFINE as a Racket closure and `mdl-type-name` had no TYPE for it:
`mdl-type: unsupported MDL type #<procedure>`.

## Reference

* [FUNCTION-TYPE-REFERENCE.md](FUNCTION-TYPE-REFERENCE.md),
  `function-type-probe.json` (19 cases): every DEFINE shape and FUNCTION
  literal is FUNCTION (PRIMTYPE LIST), DEFMAC is MACRO, all 111 host
  built-ins of this runtime plus FLOAD are SUBR, compiler-handled special
  forms are FSUBR (RETURN, AGAIN, NOT: SUBR); in the loaded game SWORD-GLOW,
  SWORD, ROBBER and RDCOM are FUNCTION, `<TYPE? ,SWORD-GLOW NOFFSET>` FALSE.
* [SWORD-GLOW-REFERENCE.md](SWORD-GLOW-REFERENCE.md),
  `sword-glow-reference.json` (29 runs): the scenario transcript, 13
  prefixes, a diagnostic run with 15 checkpoints and the one TYPE? NOFFSET
  call (on a FUNCTION, FALSE), and 13 diagnostic prefix runs giving the
  end-of-input state of every prefix.

## Semantics and decision

`docs/SEMANTICS.md` "M4 S5b: TYPE of applicable values" and ADR-0060
(`docs/DECISIONS.md`; ADR-0059 is reserved by the MAX branch). TYPE is
decided by representation registries, never by a name:

* a closure stored by a compiled DEFINE (`mdl-define!`, already recorded in
  the weak `compiled-function-formals` table) → FUNCTION; the closure is not
  wrapped, so application paths, `==?` and GVAL/SETG identity are unchanged;
* a value of `builtin-table` (fixed `eq?` set) → SUBR;
* FLOAD, the loader's other `mdl-define!` caller, is now an `mdl-subr`
  (new `mdl-define-subr!`) → SUBR, no longer a FUNCTION;
* `mdl-function` records (interpreted DEFINE, FUNCTION literal) → FUNCTION
  and DEFMAC → MACRO, as before; any other host procedure → strict error.

Strict refusals kept (recorded deviations, reference differs): CHTYPE of a
FUNCTION to LIST and of a LIST to FUNCTION; LENGTH/NTH/REST/EMPTY?/MAPF/
PUTREST on a FUNCTION; PRIN1/PRINC/UNPARSE of a FUNCTION or SUBR;
`<PRIMTYPE ,+>` / `<TYPEPRIM SUBR>` and DECL patterns naming SUBR.
Pre-existing deviations recorded, not changed: no GVAL for COND and the
other compiler-handled names; no APPLICABLE? SUBR; `=?` of two separately
DEFINEd equal functions is FALSE (reference T); a compiled DEFINE form
returns the FUNCTION (reference: the name ATOM); `<DECL? f APPLICABLE>` T
(reference BAD-TYPE-SPECIFICATION1).

## Code

* `mdl/runtime/core.rkt`: `compiled-function?`, `builtin-subr?` (set built
  from `builtin-table`), two `mdl-type-name` clauses, `mdl-define-subr!`
  (exported).
* `mdl/loader.rkt`: FLOAD bound with `mdl-define-subr!`.

## Tests (written first, failing before the change)

| Test | Before the change | After |
|---|---|---|
| `tests/function_type_test.rkt` (new; registered in `scripts/test_racket.sh`) | exit 1: `replay: define-function: <DEFINE F (X) <+ .X 1>> ... raised mdl-type: unsupported MDL type #<procedure>` | exit 0 |
| `tests/historical_sword_glow_test.rkt` (new; `make test-m4-sword-glow`, CI step in `.github/workflows/reference.yml`) | exit 2: prefixes 0–5 equal the reference, prefix 6 (`take sword`) stops with `mdl-type: unsupported MDL type #<procedure>` | exit 0, all 14 prefixes and the game-sword-glow section (90 s) |
| `tests/historical_m4_frontier_test.rkt` (F4 now a positive regression) | exit 1 at the F4 case (not input exhaustion) | exit 0 |
| `tests/historical_saveit_test.rkt` (RDCOM TYPE now FUNCTION) | asserted the old unsupported-type error | updated |

The scenario test compares, for each prefix k = 0..13, our raw output with
the reference stdout byte for byte after D1, and our end-of-input state
(HERE, AOBJS, the sword's OROOM/OTOUCH?/OTVAL, SWORD-DEMON HACTION/HROOM,
LAMP OLIGHT?, TRAP-DOOR!-FLAG, RAW-SCORE, ASCORE, MOVES) with the reference
end checkpoint k. It also asserts the reference's TYPE? NOFFSET log and
RANDOM draws, and types the game's applicables after a fresh FLOAD.

## Runs

All with `export PLTCOLLECTS=":$PWD"` in the worktree.

| Command | Exit | Output excerpt |
|---|---|---|
| `python3 -I scripts/probe_function_type_reference.py docs/evidence/M4/function-type-probe.json` | 0 | 19 cases; mdli sha256 equal before/after |
| `python3 -I scripts/probe_sword_glow_reference.py docs/evidence/M4/sword-glow-reference.json` | 0 | all checks true; 15 checkpoints; D-prefix checkpoint counts 2..14 |
| `racket tests/function_type_test.rkt` | 0 | `reference cases replayed`; `every host built-in is SUBR (and FLOAD)` |
| `make test-m4-sword-glow` | 0 | `sword-glow: all 14 prefix runs match the reference (D1 only)` (90 s) |
| `racket tests/historical_m4_frontier_test.rkt` | 0 | `F4 take all (living room): resolved; output equals reference F4-living-room-take-all-pipe (D1 only)`; F3 help/info strict as recorded |
| `bash scripts/test_racket.sh` | 1 | `3/4254 test failures`: only `loader_test.rkt`, `declaration_test.rkt`, `percent_read_test.rkt`, each `make-directory: cannot make directory /tmp/... Read-only file system` (hard-coded /tmp, sandbox only); `function_type_test.rkt` passes |
| `make test-m4-house-cellar` | 0 | 12 prefixes + frontier (113 s) |
| `make test-m4-mailbox-drop` | 0 | `all 9 prefix runs match` |
| `make test-m4-orphan-prompt` | 0 | `all 10 prefix runs match` |
| `make test-m4-top-parser` | 0 | `all 11 prefix runs match` (73 s) |
| `make test-m3-interactive` | 0 | 31 tests passed |
| `make test-m3-session` | 0 | 85 tests passed |
| `make test-m3-saveit` | 0 | 32 tests passed (RDCOM TYPE FUNCTION) |

Note: running several `make` targets concurrently made their `sources`
prerequisites collide on the shared `.cache` git checkout (`git checkout`
exit 128); the targets were rerun sequentially (results above). The
upstream checkouts were verified clean at the pinned SHAs afterwards.

## Mutation checks

Each mutant was applied to the working tree, compiled and run, then the
file was restored and its sha256 verified (`mdl/runtime/core.rkt`,
`mdl/loader.rkt` OK).

| Mutant | Test | Exit | Caught by |
|---|---|---|---|
| M1 compiled FUNCTION reported as SUBR | `tests/function_type_test.rkt` | 1 | `define-function`: DEFINE's value / `<TYPE ,F>` |
| M1 (same) | `tests/historical_sword_glow_test.rkt` | 1 | all 14 prefixes still pass (TYPE? NOFFSET is FALSE either way); the game-sword-glow section fails on `<TYPE ,SWORD-GLOW>` |
| M2 TYPE? FALSE for compiled DEFINEs | `tests/function_type_test.rkt` | 1 | `<TYPE? ,F FUNCTION>` (reference FUNCTION) |
| M3 applying a compiled FUNCTION broken (`mdl-apply-evaluated`) | `tests/function_type_test.rkt` | 1 | `<F 4>` raised `mutant: apply broken` |
| M4 built-ins reported as FSUBR | `tests/function_type_test.rkt` | 1 | `builtin-subr: <TYPE ,+>` (reference SUBR) |
| M5 FLOAD bound with `mdl-define!` (FUNCTION) | `tests/function_type_test.rkt` | 1 | FLOAD TYPE check: actual FUNCTION, expected SUBR |

## Next strict failure on the sword path (recorded, not stubbed)

After the scenario, `kill troll with sword`: native prints `Your sword pinks
the troll on the wrist, but it's not serious.` and `The troll swings his
axe, but it misses.`. This runtime prints the first line identically and
then stops with `mdl-eval: unassigned or non-applicable MDL operator MAX`.
MDL: BLOW `78melee.mud:447`, `(<==? .RES ,LIGHT-WOUND> <SET DEF <MAX 0 <-
.DEF 1>>>)` (the hero's light wound on the troll). Call path: RDCOM → verb
KILL → KILLER (`77act1.mud:1699`) → `<BLOW ,PLAYER .PRSO <ORAND .PRSI> T
<>>` (`:1711`) → BLOW (`78melee.mud:377`) → MAX. This is frontier item 4
(MAX, #122), which the separate MAX branch implements (ADR-0059); it is not
asserted in the frontier test here so the two branches do not conflict.
After MAX, the troll's counterattack goes through FIGHTING
(`78melee.mud:282`) → BLOW `:341` with RANDOM-driven results; that
combat path has not been compared yet.

Security and licensing: local runs only, no network or exposed evaluator;
reference runs in disposable `$TMPDIR` copies; Confusion (GPLv3) used only
as a reference binary, no source copied. README/STATUS not updated
(orchestrator). The change touches TYPE dispatch used by DECL matching and
UVECTOR uniformity; an independent review is recommended (AGENTS.md).
