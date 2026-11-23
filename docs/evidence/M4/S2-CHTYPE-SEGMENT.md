# M4 S2: CHTYPE to SEGMENT (frontier F1, `drop`)

Date: 2026-11-23. Branch `feat/m4-chtype-segment` at `main` `c439026`
(uncommitted working tree; the orchestrator commits). Upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`. Racket v7.9 [bc]. Pinned mdli
sha256 `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789`
before and after every capture (never rebuilt). Native runs: disposable
`$TMPDIR` copies, fixed clock 250776000, TZ=UTC.

Result: **S2 scenario PASS (scoped: the mailbox-drop scenario, transcript
plus checkpoints, and the game's INSERT-OBJECT/TAKE-OBJECT effects)**. F1 is
resolved; no new strict failure on the drop path. Not a PLAYABLE claim and
not the M4 gate.

## Reference

* [SEGMENT-CHTYPE-REFERENCE.md](SEGMENT-CHTYPE-REFERENCE.md),
  `segment-chtype-probe.json` (31 cases), script
  `scripts/probe_segment_chtype_reference.py`. Key identity result: the
  reader's `!<...>`/`!.X` and `<CHTYPE form SEGMENT>` are **the same TYPE**
  (SEGMENT, PRIMTYPE LIST, `<1 '!.X>` is LVAL), and CHTYPE **shares** the
  cells (PUT through either view is visible in the other). A final segment
  in an evaluated LIST shares the payload list's cells.
* [MAILBOX-DROP-REFERENCE.md](MAILBOX-DROP-REFERENCE.md),
  `mailbox-drop-reference.json`, script `scripts/probe_mailbox_drop_reference.py`,
  scenario `tests/scenarios/mailbox-drop.json`: `open mailbox`,
  `take leaflet`, `drop leaflet`, `inventory`, `look`, `take leaflet`,
  `drop leaflet`, `look`. T1 = T1b bytes, X1 game text = T1, prefixes
  consistent, 10 checkpoints. Why this extension: the second take/drop pair
  removes the leaflet from, and re-inserts it into, the ROBJS chain that the
  first INSERT-OBJECT built with a shared tail, and both `look`s list the
  room in ROBJS order and make one RANDOM draw each. TAKE-OBJECT is not
  reachable from a short scenario (boat repair, CONS-OBJ only); its native
  effect is the probe case `game-insert-take-object` and is checked on the
  game's own macro in the scenario test.

## Semantics implemented (SEMANTICS "M4 S2"; ADR-0056)

* SEGMENT is a built-in TYPE, PRIMTYPE LIST, one representation for reader
  and CHTYPE segments: a TYPE tag over the LIST cells (like FORM).
  `mdl-segment?` tests identity with the ROOT SEGMENT atom (weak registry of
  all atom spaces), never the PNAME.
* `<CHTYPE x SEGMENT>` for any LIST-primtype x (LIST, FORM, FALSE, SEGMENT,
  LIST NEWTYPE) shares the cells; SEGMENT → LIST/FALSE/NEWTYPE shares too.
* The M2 D2 splice rules now apply to every SEGMENT, including runtime-built
  ones: splice as a raw element of an evaluated LIST/VECTOR/UVECTOR (final
  LIST segment shares the tail) or FORM argument list; stored when it is an
  element's value; ILLEGAL-SEGMENT standalone or for a non-structured value.
* Strict refusals: CHTYPE to SEGMENT from VECTOR, UVECTOR, STRING, FIX,
  ATOM and SEGMENT → VECTOR (`primitive type mismatch`); CHTYPE to FORM
  (unchanged `unsupported built-in TYPE conversion`); printing a SEGMENT.
* Deviations (recorded): print notation not implemented; mismatch message
  text differs; interpreted FUNCTION required formals splice where the
  reference raises ILLEGAL-SEGMENT (existing M2 D2 deviation); CHTYPE to
  FORM refused where the reference accepts it; reader segments drop their
  unused line/column.

Code: `mdl/runtime/core.rkt` only (type table entry, `mdl-segment?`,
`mdl-segment-payload`, `mdl-make-segment`, one CHTYPE branch). No compiler
change, no game-specific path, no game source change.

## Tests

* `tests/chtype_segment_test.rkt` (new; in `scripts/test_racket.sh`): one
  assertion per probe observation that is supported, plus the refusals and
  the recorded deviations; compiled path and interpreted loader twins. The
  runtime has no EVAL SUBR (EVAL is reached only by the ILO anti-tamper path,
  `77act1.mud:20`), so the EVAL cases use the macro `<DEFMAC EV (X) .X>`;
  their recorded `-via-macro` reference twins print the same results.
* `tests/historical_mailbox_drop_test.rkt` (new; `make test-m4-mailbox-drop`;
  CI step in `.github/workflows/reference.yml`): prefixes k = 0..8 equal the
  reference byte for byte after D1; checkpoints HERE, AOBJS, WHOUS ROBJS,
  MAILB OCONTENTS/OOPEN?, leaflet OROOM/OCAN/OTOUCH?, RAW-SCORE, ASCORE,
  MOVES equal reference checkpoint k; then, after a fresh FLOAD, the game's
  INSERT-OBJECT and TAKE-OBJECT prepend and the REST is `==?` the old list.
* `tests/historical_m4_frontier_test.rkt`: the F1 failure assertion is
  replaced by a positive regression (output equals reference P03, input
  exhaustion). F2 is unchanged. New F2b: `throw leaflet` (DROPPER's sibling
  verb) reaches the same F2 construct (FOOSTR CHARACTER CHTYPE); native
  prints `at what?` (ad-hoc native run, not committed JSON).
* Test-harness note: none of the existing assertions were changed.
  `tests/type_test.rkt` keeps `<CHTYPE (1 2) FORM>` as a strict refusal.

### Red → green

| Command | Before (runtime at `c439026`) | After |
|---|---|---|
| `racket tests/chtype_segment_test.rkt` | exit 1, `mdl-typeprim: unknown MDL TYPE SEGMENT` | exit 0, `chtype segment tests passed` |
| `racket tests/historical_mailbox_drop_test.rkt` | exit 1: prefixes 0–2 equal the reference, prefix 3 fails (strict error at `drop leaflet`, check at line 231) | exit 0, `mailbox-drop: all 9 prefix runs match the reference (D1 only)` (≈50 s) |
| `racket tests/historical_m4_frontier_test.rkt` | exit 1 at the F1 positive regression (line 102) | exit 0 (F1 resolved, F2, F2b as recorded) |

The "before" runs used a copy of the tree under `$TMPDIR` with
`git show HEAD:mdl/runtime/core.rkt` (the working tree was not reverted).

### Mutations (each in a `$TMPDIR` copy of the final tree)

| Mutation | Test | Result |
|---|---|---|
| (a) CHTYPE to SEGMENT copies the cells | `chtype_segment_test.rkt` | exit 1 at line 97 (`<==? <CHTYPE .S LIST> <CHTYPE .F LIST>>`) |
| (b) no splicing in evaluated LIST/VECTOR (`build-eval-*` ignore SEGMENTs) | `chtype_segment_test.rkt`; `historical_mailbox_drop_test.rkt` | exit 1 (ILLEGAL-SEGMENT at the first splice case); exit 1 at prefix 3 |
| (c) any PRIMTYPE accepted for SEGMENT (VECTOR → SEGMENT) | `chtype_segment_test.rkt` | exit 1 at line 125 (refusal loop) |
| (d) CHTYPE to SEGMENT yields TYPE FORM | `chtype_segment_test.rkt`; `historical_mailbox_drop_test.rkt` | exit 1 at line 73; exit 1 at checkpoint 3 (`render: unexpected checkpoint value of type OBJECT`: ROBJS nested) |

### Regression runs (final tree, `export PLTCOLLECTS=":$PWD"`)

| Command | Exit | Output excerpt |
|---|---|---|
| `racket tests/chtype_segment_test.rkt` | 0 | `interpreted CHTYPE SEGMENT twins passed`, `chtype segment tests passed` (`raco test`: 86 tests passed) |
| `bash scripts/test_racket.sh` | 1 | `3/3556 test failures`: only `loader_test`, `declaration_test`, `percent_read_test`, each `make-directory: /tmp/…: Read-only file system` (they hardcode `/tmp`; sandbox only). The same three files with `/tmp` replaced by `$TMPDIR` in a scratch copy of the final tree: exit 0 (59, 56, 40 tests passed) |
| `make test-m4-house-cellar` | 0 | S1 `all 12 prefix runs match the reference (D1 only)`; frontier `F1 drop: resolved; output equals reference P03`, F2 and F2b `strict failure as recorded` (84 s) |
| `make test-m4-mailbox-drop` | 0 | `prefix 0..8 … equal the reference`, `macros: INSERT-OBJECT and TAKE-OBJECT prepend and share the old list`, `all 9 prefix runs match the reference (D1 only)` (56 s) |
| `make test-m3-interactive` | 0 | `31 tests passed` (7 s) |
| `make test-m3-session` | 0 | (23 s) |

Python suite (`make test-python`) not run: no Python file under test changed
(two new probe scripts only; `python3 -m py_compile` on both: OK).

## Next frontier

The drop path has no further strict failure. Next to it, `throw leaflet`
(and every `<prep> what?` orphan prompt) stops at F2, `<CHTYPE fix
CHARACTER>` in FOOSTR (`77np.mud:241`), which is the recommended next slice.
Ad-hoc only (not committed reference): after S1, `turn off lamp`, `look`,
`west`, `south` (grue death, JIGS-UP with INSERT-OBJECT) now matches native
up to `Beg pardon?`.

## Risks and limits

* SEGMENT printing is still strict; a game path that prints one would fail
  loudly (none known).
* Only the mailbox-drop scenario is parity-checked; other INSERT-OBJECT
  sites (death, troll, boat) are covered only by the shared mechanism.
* README/STATUS are not updated by this slice (orchestrator); the full
  `make test` (Python suite) was not run.
* Security/licensing: local only, no exposed evaluator; Confusion (GPLv3)
  is run only as a reference binary, no source copied.
