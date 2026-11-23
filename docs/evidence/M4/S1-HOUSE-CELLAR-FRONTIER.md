# M4 S1 frontier: enter the house and open the cellar

Date: 2026-11-23. Branch `feat/m4-house-cellar` at `main` `23b492e`. The
runtime was not changed: no file under `mdl/` was edited. Upstream mdlzork
is `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

Result: **S1 scenario PASS (scoped: this scenario only, transcript plus
checkpoints)**. There is no divergence and no strict failure on the S1 path.
The nearest strict failures just beyond S1 are recorded below as the M4
frontier. This is not a PLAYABLE claim and not the M4 gate.

## Scenario

`tests/scenarios/house-cellar.json`: fresh boot (`<FLOAD "77loadall.mud">`,
`<SAVE-IT>`), session clock fixed at epoch 250776000 with zone UTC, then
`north`, `east`, `open window`, `west`, `west`, `take lamp`, `move rug`,
`open trap door`, `turn on lamp`, `down`, `score`, then end of input.

## Reference capture

See [HOUSE-CELLAR-REFERENCE.md](HOUSE-CELLAR-REFERENCE.md) and
[house-cellar-reference.json](house-cellar-reference.json). Pinned mdli
sha256 `6df359f6…b789` (not rebuilt). The native reference accepted all 11
commands. Score 35 in 11 moves: kitchen 10 + cellar 25. The only RANDOM
call is START's seed call, `<RANDOM 10438660480>` → 16566282405, and no
ROOM-INFO `<PROB 80>` draw occurs. A diagnostic run (X1) recorded 13
read-only checkpoints, and its game text is byte-identical to the plain
transcript. Prefix captures P00–P10 cover every intermediate state. The
only file written is SAVE-IT's `MDL/MADADV.SAVE`, in the disposable copy.

Command: `python3 -I scripts/probe_house_cellar_reference.py $TMPDIR/hc-ref.json`
→ exit 0. Checks: `t1_equals_t1b_bytes`,
`diag_game_part_equals_t1_game_part_bytes` and
`prefix_runs_consistent_with_t1` are all true; 13 checkpoints.

## Our runtime (main `23b492e`, Racket v7.9 BC)

`tests/historical_house_cellar_test.rkt`, run by `make test-m4-house-cellar`.
For every prefix k = 0..11 it does one fresh session:
`make-mdl-session` with explicit ports, `make-fixed-mdl-clock 250776000`,
`#:time-zone 'utc`, `mdl-session-load! "77loadall.mud"`, then
`mdl-session-run-interactive "SAVE-IT"`. Each run has a 300 s watchdog and a
security guard (no write or delete, empty cwd, game tree hashes unchanged,
no OPEN records). The test asserts:

* load PASS with 1,229 expressions; the run ends with
  `exn:fail:mdl-input-exhausted` (D3) after the reference's own
  `Beg pardon?\n>`; events are `(entry-returned pass)`; all input is consumed;
* **transcript**: the raw output equals the reference stdout byte for byte
  after D1 only (the LISTEN banner and the `"DONE"` line). Before the
  comparison the reference text is checked against its recorded sha256.
  Byte equality after D1 is stricter than the ADR-0053 D2 view, so the
  D1/D2 comparator result is implied;
* **checkpoints**: after prefix k, HERE (RID), RSEEN?, the winner's AOBJS
  (OIDs), `KITCHEN-WINDOW!-FLAG`, RUG ORAND, DOOR OVIS?/OFLAGS/OTOUCH?,
  `TRAP-DOOR!-FLAG`, LAMP OLIGHT?, LAMP ∈ ROBJS(LROOM), `LIT? ,HERE`,
  RAW-SCORE, ASCORE and MOVES equal reference checkpoint k. They are read
  through `mdl-session-global` and `mdl-session-call` (NTH, LIT?, MEMQ,
  FIND-OBJ, FIND-ROOM, CHTYPE, TYPE, LENGTH) after the run. The reference
  shows that the end-of-input read changes no field (CP 11 = CP 12).

Commands and results:

| Command | Exit | Output excerpt |
|---|---|---|
| `PLTCOLLECTS=":$PWD" racket tests/historical_house_cellar_test.rkt` | 0 | `prefix 0..11: transcript and checkpoint k equal the reference`; `house-cellar: all 12 prefix runs match the reference (D1 only)` (65 s) |
| `PLTCOLLECTS=":$PWD" make test-m4-house-cellar` | 0 | as above plus the two frontier lines below (76 s) |
| Mutation: a reference checkpoint 0 `rug_orand` set to `T` | 1 | check failure at `tests/historical_house_cellar_test.rkt:235` (reference file restored; sha256 `fce5ff53…462b`) |

**First divergence on S1: none. First strict failure on S1: none.**

## Frontier just beyond S1 (strict failures, recorded)

These were found by running a few commands past the S1 path in both
engines. They were ad-hoc runs: only the S1 captures are committed
reference JSON. `tests/historical_m4_frontier_test.rkt` asserts the exact
text printed before each failure and the exact error, so the test fails if
the frontier moves. It is not a parity test.

### F1 (rank 1): `<CHTYPE <FORM ...> SEGMENT>`, TYPE SEGMENT unknown

* Reproduction: `open mailbox`, `take leaflet`, `drop leaflet`. Native
  prints `Dropped.`. We print `>Taken.\n>` and then raise
  `mdl-typeprim: unknown MDL TYPE SEGMENT`.
* MDL being executed: DROPPER `77rooms.mud:1239` `(<INSERT-OBJECT .OBJ .RM>)`.
  Expanding the DEFMAC INSERT-OBJECT (`77defs.mud:332-336`) evaluates the
  LIST `(<FORM PUT .OBJ ,OROOM .ROOM> <CHTYPE <FORM ROBJS .ROOM> SEGMENT>)`.
  TAKE-OBJECT (`77defs.mud:338-342`) has the same shape.
* Call path: RDCOM → verb DROP → DROPPER → INSERT-OBJECT macro expansion →
  CHTYPE. In Racket: `mdl-chtype` (`mdl/runtime/core.rkt:3641`) →
  `mdl-typeprim`, under `build-eval-list` (`core.rkt:1007`).
* Root cause: the runtime has SEGMENT objects from the reader (`!<...>`,
  `!.X`; SEMANTICS "M2 D2 SEGMENT"), but the TYPE SEGMENT is not in the
  type table, so CHTYPE cannot make one from a FORM.
* Reach: about 40 INSERT-OBJECT/TAKE-OBJECT call sites (77act1 11, 77act2
  15, 77act3 6, 77rooms 5, 78melee 2, 77makstr 1). These include every
  `drop`, death (JIGS-UP `77rooms.mud:931,945`), throwing the lamp
  (`77act1.mud:1867`) and a melee weapon loss (`78melee.mud:455,458`). Also
  checked: after S1, `turn off lamp`, `look`, `west`, `south` (grue death,
  JIGS-UP) is byte-identical to native up to `You can't have everything.`,
  then fails with the same error.
* Preliminary native observations (ad-hoc, before the slice's own probe
  file): `<CHTYPE <FORM REST '(1 2 3)> SEGMENT>` prints `!<REST (1 2 3)!>`,
  TYPE SEGMENT, PRIMTYPE LIST, `<TYPEPRIM SEGMENT>` LIST;
  `<EVAL <LIST 0 .S>>` → `(0 2 3)`; a DEFMAC
  `(.X <CHTYPE <FORM LVAL .Y> SEGMENT>)` yields `(6 7 8)` whose REST is
  `==?` the old list, so the final segment shares the tail; a non-final
  segment splices (`(1 6 7 8 9)`); `<CHTYPE [1 2] SEGMENT>` →
  `PRIMTYPES do not match in CHTYPE`.

### F2 (rank 2): `<CHTYPE fix CHARACTER>`, FIX → CHARACTER

* Reproduction: S1 without `score`, then `east`, `kill troll`. Native
  prints `with what?` (orphan prompt). We print the troll room and `>`,
  then raise `mdl-chtype: unsupported built-in TYPE conversion`.
* MDL being executed: ORTELL `77np.mud:226`
  `<TELL <PRSTR <CHTYPE .PREP ATOM>> 0 " what?">` (PREP→ATOM succeeds) →
  PRSTR `77np.mud:230-232` → FOOSTR `77np.mud:234-243`, where line 241,
  `<PUT .Y 1 <CHTYPE <+ 32 <ASCII <1 .X>>> CHARACTER>>`, lower-cases the
  word.
* Root cause: `mdl-chtype` allows only a fixed list of built-in targets
  (ATOM, LIST, FALSE, VECTOR, UVECTOR, STRING, FIX, WORD, LOSE, CHANNEL), and
  CHARACTER is not on it. Confirmed directly: `(mdl-session-call s "CHTYPE"
  119 CHARACTER)` raises that message.
* Reach: every PRSTR use. That covers the orphan `<prep> what?` prompts,
  `Which <noun>?` ambiguity (`77np.mud:88`) and the adjective echo
  (`77np.mud:79`), which makes this the head of backlog scenario 2.
* Preliminary native observations: `<CHTYPE 119 CHARACTER>` is `!\w`,
  TYPE CHARACTER, `==?` to `!\w`; `<CHTYPE !\a FIX>` is 97. Out of range,
  300 prints garbage bytes and -1 prints `!\^?`. These are implementation
  artefacts: a slice should accept 0–127, the existing ASCII range policy,
  and fail strictly otherwise.

### Further constructs visible nearby (static grep, not yet reached)

3. TOP at `77np.mud:126` (`put X in …`; a known gap in STATUS).
4. MAX (#122) at `78melee.mud:447-448`, reached by actual troll combat with
   a weapon (backlog scenario 4). `kill troll with lamp` currently matches
   native (`Trying to kill a troll with a lamp is suicidal.`).
5. JIGS-UP past F1: ROB-ADV / RANDOM-LIST scattering, then RECORD/QUIT on
   the third death (OPEN policy ADR-0055).

## Smallest faithful next slice (recommended)

**TYPE SEGMENT for CHTYPE (F1).** Specify the following in SEMANTICS first:

* SEGMENT is a built-in TYPE with PRIMTYPE LIST;
* `<CHTYPE form SEGMENT>` returns the runtime's existing SEGMENT object for
  that FORM payload, the same object the reader builds for `!<...>`;
* the object splices when it is a raw element of an evaluated LIST (macro
  expansion), and in final position it shares the payload's tail;
* CHTYPE of a non-LIST primtype raises `PRIMTYPES do not match`.

Reference probes to add (pinned mdli, a disposable copy, one probe file):

* TYPE, PRIMTYPE and TYPEPRIM, and the printed form;
* CHTYPE from FORM, from LIST and from a NEWTYPE of LIST;
* EVAL of LIST, VECTOR and FORM-argument constructions holding a
  CHTYPE'd segment, in non-final and final position (tail `==?`);
* an INSERT-OBJECT-shaped DEFMAC;
* a standalone segment evaluation (ILLEGAL-SEGMENT);
* CHTYPE back to FORM;
* VECTOR → SEGMENT (error).

Then add a reference-captured scenario that drops an object (for example
S1 + `drop lamp`, or `open mailbox`, `take leaflet`, `drop leaflet`) and
replace F1 in the frontier test with it. F2 (CHARACTER) is the next slice
after that.

## Files

* `tests/scenarios/house-cellar.json`: commands and fixed clock.
* `scripts/probe_house_cellar_reference.py`: the native capture.
* `docs/evidence/M4/house-cellar-reference.json`,
  `docs/evidence/M4/HOUSE-CELLAR-REFERENCE.md`: the reference.
* `tests/historical_house_cellar_test.rkt`: S1 transcript and checkpoint
  comparison.
* `tests/historical_m4_frontier_test.rkt`: the recorded frontier F1 and F2
  (strict, not parity).
* `Makefile`: the target `test-m4-house-cellar`.

Security and licensing: the work is local only, with no network or exposed
evaluator. Confusion (GPLv3) is run only as a reference binary, and none of
its source is copied. Unresolved: README/STATUS were not updated in this
slice (that is for the orchestrator), and the full `make test` was not run.
