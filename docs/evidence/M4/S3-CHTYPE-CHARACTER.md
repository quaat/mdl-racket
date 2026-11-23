# M4 S3: CHTYPE between FIX and CHARACTER (frontier F2/F2b, orphan prompts)

Date: 2026-11-23. Branch `feat/m4-chtype-character`, stacked on the S2
SEGMENT branch at `241e124` (PR #154); uncommitted working tree (the
orchestrator commits). Upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`. Racket v7.9 [bc]. Pinned mdli
sha256 `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789`
before and after every capture (never rebuilt). Native runs: disposable
`$TMPDIR` copies, fixed clock 250776000, TZ=UTC.

Result: **S3 scenario PASS (scoped: the orphan-prompt scenario, transcript
plus checkpoints, and the game's own PRSTR/FOOSTR)**. F2 and F2b are
resolved; no new strict failure on either path. Not a PLAYABLE claim and
not the M4 gate.

## Reference

* [CHARACTER-CHTYPE-REFERENCE.md](CHARACTER-CHTYPE-REFERENCE.md),
  `character-chtype-probe.json` (26 cases), script
  `scripts/probe_character_chtype_reference.py`. Key results: CHTYPE FIX →
  CHARACTER yields the same CHARACTER as `!\c`/ASCII (`==?` by code, never
  `==?`/`=?` to the FIX); CHARACTER → FIX/WORD and back round-trip; non-WORD
  PRIMTYPEs are refused (`PRIMTYPES do not match in CHTYPE`). **Range: the
  reference does not range-check** (128, 255, 256, -1, ±2^35 come back
  unchanged through ASCII; such characters print implementation bytes),
  while ASCII FIX → CHARACTER refuses 128 and -1. Game reach: PNAME
  characters of every ATOM in the WORDS/OBJECTS/ACTIONS/DIRECTIONS oblists
  are at most 90, so FOOSTR's argument is at most 122.
* [ORPHAN-PROMPT-REFERENCE.md](ORPHAN-PROMPT-REFERENCE.md),
  `orphan-prompt-reference.json`, script
  `scripts/probe_orphan_prompt_reference.py`, scenario
  `tests/scenarios/orphan-prompt.json`: `open mailbox`, `take leaflet`,
  `throw leaflet` (→ `at what?`), `mailbox` (→ `Thrown.`), `look`,
  `take leaflet`, `kill mailbox` (→ `with what?`), `leaflet` (→ `Trying to
  kill a mailbox with a leaflet is suicidal.`), `inventory`. T1 = T1b bytes,
  X1 game text = T1, prefixes consistent, 11 checkpoints including the
  ORPHANS vector and the SCRSTR buffer; the X1 CHTYPE wrapper shows the only
  CHTYPE-to-CHARACTER arguments: 97 116 (`at`), 119 105 116 104 (`with`).
  `kill mailbox` is the start-area stand-in for `kill troll` (same KILL
  syntax, same ORTELL/PRSTR/FOOSTR path, no walk to the troll room); the
  exact F2 path is captured as case `F2-kill-troll-pipe` (S1 commands
  without `score`, `east`, `kill troll`, `lamp`).

## Semantics implemented (SEMANTICS "M4 S3"; ADR-0057)

* `<CHTYPE x CHARACTER>` for x of PRIMTYPE WORD (FIX, WORD, CHARACTER, a
  NEWTYPE of WORD) returns the runtime's one CHARACTER value
  (`mdl-character`), so `==?`, `=?`, STRING PUT/STRING/MEMQ and PRINC treat
  it exactly like `!\c`. CHARACTER → FIX/WORD (already supported) unchanged.
* Range: codes 0–127 only (the runtime's documented CHARACTER/ASCII/input
  range); other codes are a strict error `CHARACTER code out of supported
  range 0..127`. **Deviation**: the reference accepts any WORD value.
* Strict refusals: non-WORD PRIMTYPE sources and CHARACTER → ATOM/LIST/
  STRING (`primitive type mismatch`); FLOAT → CHARACTER and CHARACTER →
  FLOAT (`unsupported …`; the reference reinterprets the bits); wrong
  argument counts (host arity error; reference TOO-MANY/TOO-FEW).
* Dispatch only for the ROOT CHARACTER TYPE atom (ADR-0056): a user TYPE
  atom named CHARACTER stays an ordinary WORD NEWTYPE (tested).

Code: `mdl/runtime/core.rkt` only (CHARACTER added to the built-in CHTYPE
targets, one branch in the WORD conversion). No compiler change, no
game-specific path, no game source change.

## Tests

* `tests/chtype_character_test.rkt` (new; in `scripts/test_racket.sh`): one
  assertion per supported probe observation, the refusals and the recorded
  deviations (out-of-range codes, FLOAT), the FOOSTR/PRSTR copy compiled and
  interpreted through the shared-session loader, and the ADR-0056 dispatch
  check.
* `tests/historical_orphan_prompt_test.rkt` (new; `make test-m4-orphan-prompt`;
  CI step in `.github/workflows/reference.yml`): prefixes k = 0..9 equal the
  reference byte for byte after D1; checkpoints HERE, AOBJS, WHOUS ROBJS,
  MAILB OCONTENTS/OOPEN?, leaflet OROOM/OCAN/OTOUCH?, ORPHANS
  (OFLAG/OVERB/OSLOT1/OPREP/ONAME), the codes of `<BACK ,SCRSTR 5>`,
  RAW-SCORE, ASCORE, MOVES equal reference checkpoint k; the reference's
  CHTYPE log and RANDOM draws are asserted; after a fresh FLOAD the game's
  own PRSTR/FOOSTR give the `game-prstr` results (including the shared
  SCRSTR buffer).
* `tests/historical_m4_frontier_test.rkt`: the F2 and F2b failure
  assertions are **replaced** by positive regressions (output equals
  reference `F2-kill-troll-pipe` and orphan-prompt `P03`, D1 only, input
  exhaustion). No unresolved frontier case remains in that file.

### Red → green

| Command | Before (runtime at `241e124`) | After |
|---|---|---|
| `racket tests/chtype_character_test.rkt` | exit 1, `mdl-chtype: unsupported built-in TYPE conversion` (first case, `<CHTYPE 65 CHARACTER>`) | exit 0, `interpreted CHTYPE CHARACTER twins passed`, `chtype character tests passed` |
| `racket tests/historical_orphan_prompt_test.rkt` | exit 1: prefixes 0–2 equal the reference, prefix 3 (`throw leaflet`) fails the input-exhaustion check (line 270; strict CHTYPE error) | exit 0, `orphan-prompt: all 10 prefix runs match the reference (D1 only)` (60 s) |
| `racket tests/historical_m4_frontier_test.rkt` | exit 1 at the F2 positive regression (line 109) | exit 0: F1, F2, F2b `resolved; output equals reference …` (17 s) |

The "before" runs used the working tree before the core change (unit and
scenario tests) and a `$TMPDIR` copy with `git show HEAD:mdl/runtime/core.rkt`
(frontier test).

### Mutations (each in a `$TMPDIR` copy of the final tree)

| Mutation | Test | Result |
|---|---|---|
| (a) CHTYPE FIX → CHARACTER returns the FIX unchanged | `chtype_character_test.rkt`; `historical_orphan_prompt_test.rkt` | exit 1 at line 70 (`<CHTYPE 65 CHARACTER>`: actual `65`); exit 1 at prefix 3 (line 270, strict failure at `throw leaflet`) |
| (b) wrong TYPE: result tagged WORD instead of CHARACTER | `chtype_character_test.rkt`; `historical_orphan_prompt_test.rkt` | exit 1 (first case: value is not a CHARACTER); exit 1 at prefix 3 (line 270) |
| (c) range check widened to any Unicode code | `chtype_character_test.rkt` | exit 1 at the out-of-range refusal loop (`<CHTYPE 128 CHARACTER>` accepted) |
| (c′) PRIMTYPE check skipped for target CHARACTER | `chtype_character_test.rkt` | exit 1 at the refusal loop (`<CHTYPE "A" CHARACTER>` not refused with `primitive type mismatch`) |
| (d) CHARACTER → FIX returns the CHARACTER | `chtype_character_test.rkt` | exit 1 at line 91 (`<CHTYPE !\A FIX>`: actual `!\A`) |

The reference rejects no WORD value, so (c) checks this runtime's documented
range; (c′) checks the reference's own refusal (`PRIMTYPES do not match`).

### Regression runs (final tree, `export PLTCOLLECTS=":$PWD"`)

| Command | Exit | Output excerpt |
|---|---|---|
| `racket tests/chtype_character_test.rkt` | 0 | `interpreted CHTYPE CHARACTER twins passed`, `chtype character tests passed` |
| `bash scripts/test_racket.sh` | 1 | `3/3660 test failures`: only `loader_test`, `declaration_test`, `percent_read_test`, each `make-directory: /tmp/…: Read-only file system` (they hardcode `/tmp`; sandbox only). No other FAILURE line in the full log. The same three files with `/tmp/mdl-` replaced by `$TMPDIR/mdl-` in a scratch copy of the final tree: `raco test` exit 0, 155 tests passed |
| `make test-m4-house-cellar` | 0 | S1 all prefixes match; frontier `F1 drop`, `F2 orphan prompt`, `F2b throw`: `resolved; output equals reference …` (80 s) |
| `make test-m4-mailbox-drop` | 0 | `mailbox-drop: all 9 prefix runs match the reference (D1 only)` (52 s) |
| `make test-m4-orphan-prompt` | 0 | `prstr: the game's PRSTR/FOOSTR and SCRSTR equal the reference (game-prstr)`, `orphan-prompt: all 10 prefix runs match the reference (D1 only)` (55 s) |
| `make test-m3-interactive` | 0 | `31 tests passed` (6 s) |
| `make test-m3-session` | 0 | `85 tests passed` (20 s) |

Python suite (`make test-python`) not run: no Python file under test changed
(two new probe scripts only; `python3 -m py_compile` on both: OK).

## Next frontier

No strict failure remains on the F2 (`kill troll`, answer `lamp`) or F2b
(`throw leaflet`, answer `mailbox`) paths, nor on two further PRSTR uses
checked ad hoc against native (`take sword` → `I can't see a sword here.`,
`take brown bottle` → `I can't see a brown bottl here.`; byte-identical up
to end of input). Recorded, not fixed (ad hoc, both engines fail):
answering an orphan prompt with a prepositional phrase (`kill mailbox`,
then `with leaflet`) is `ARGUMENT-OUT-OF-RANGE` natively and
`mdl-decl: DECL 26:4: OBJ does not satisfy declaration` here (SPARSE). The
next recommended slice stays on the S1 frontier list: TOP (`77np.mud:126`)
or MAX in troll combat (`78melee.mud:447-448`).

## Risks and limits

* CHTYPE to CHARACTER outside 0–127 fails where the reference succeeds
  (ADR-0057); no game path reaches it (max 122).
* Only the orphan-prompt scenario and the F2 transcript are parity-checked;
  `Which <noun>?` (`77np.mud:88`) has no committed reference.
* README/STATUS are not updated by this slice (orchestrator); the full
  `make test` (Python suite) was not run.
* Security/licensing: local only, no exposed evaluator; Confusion (GPLv3)
  is run only as a reference binary, no source copied.
