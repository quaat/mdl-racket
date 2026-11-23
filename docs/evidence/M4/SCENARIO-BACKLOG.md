# M4 scenario backlog (plan, 2026-11-23)

Status (updated 2026-11-23): scenario 1 is **executed and PASS on `main`**
(#153, `make test-m4-house-cellar`); two further scenarios grew out of its
frontier and also PASS on `main`: **mailbox-drop** (S2, #154) and
**orphan-prompt** (S3, #155) — see the [M4 baseline](M4-MAINLINE-BASELINE.md).
Row 4 (troll combat, S6, #162) is on `main`; row 2 (parser rejection and
ambiguity, S7) PASSes on its branch.
Rows 3 and 5 remain planned (row 4 has further branches, see its row). Original status when drafted: plan only; no
scenario had been run in either engine. This orders the first M4
slices after M3 acceptance (deterministic house smoke) and the local session
smoke (PLAN WP4). It is not a PLAYABLE claim.

All scenarios start from the faithful entry (`<FLOAD "77loadall.mud">`,
`<SAVE-IT>`) with the session-owned fixed clock (epoch 250776000, TZ UTC,
microseconds 0), which seeds RANDOM with 10438660480
([clock seed reference](../M3/CLOCK-SEED-REFERENCE.md)). A scenario whose
text depends on RANDOM records which draws it consumes. Reference captures
use a disposable `$TMPDIR` copy of the game directory. Comparison is a strict
transcript match plus read-only state checkpoints taken in both engines
(e.g. `,HERE`, the winner's AOBJS, `,RAW-SCORE`, `,MOVES`, object flags read
after the run). Matching opening text alone is never state equivalence.

Source paths below are relative to
`.cache/upstream/mdlzork/mdlzork_771212/patched_confusion/`.

| # | Scenario | Exercises | Source | Clock/RNG | Known unsupported risk |
|---|---|---|---|---|---|
| 1 | **Enter the house and open the cellar** (first scenario) | object transfer, containment, a puzzle transition, darkness | WINDOW-FUNCTION / OPEN-CLOSE `77act1.mud:39-60`, KITCHEN `:62`, LIVING-ROOM `:178`, RUG `:303`, TRAP-DOOR `:211`, CELLAR `:270`, TAKE `77rooms.mud:1098`, LIT? `77rooms.mud:1026` | fixed clock; ROOM-INFO `<PROB 80>` draws on each new room | first construct past the six-command path is unknown until probed; MEMBER (WP3) is on the parser path |
| 2 | Parser rejection and ambiguity | unknown words, 5-letter truncation, "which X?", empty line | SPARSE `77np.mud:19`, EPARSE `77np.mud:347`, TAKE-IT-OR-LEAVE-IT `77np.mud:182` | none expected; one YUKS draw (`take` of the mailbox) and two in `down` from the dark attic | reference: unknown words count as moves, an empty line does not ([quit probe](../M3/SESSION-QUIT-REFERENCE.md)). **S7 PASS (branch evidence)**: 35 prefixes + checkpoints match native, no runtime change ([S7](S7-PARSER-AMBIGUITY.md)); `Which door?` in the living room answered by `trap` / `wooden`; not covered: a carried-vs-room ambiguity, a PHRASE orphan, the vehicle message |
| 3 | Lamp and time events | LANTERN on/off, LIGHT-INT countdown, CLOCK-INT queue | LANTERN `77act1.mud:1859`, LIGHT-INT `77act1.mud:2006`, CLOCK-INT `77rooms.mud:1657` | needs many moves; RNG draws from room descriptions | interrupt/clock-event delivery path not yet exercised |
| 4 | Troll combat and death | FIGHTING, BLOW, strength, JIGS-UP | TROLL `77act1.mud:360`, FIGHTING `78melee.mud:282`, BLOW `78melee.mud:377`, JIGS-UP `77rooms.mud:870` | RNG-heavy: every blow draws | MAX resolved (#159). **S6 PASS** for the branch where the troll dies on the third blow ([S6](S6-TROLL-COMBAT.md)); hero wounds, JIGS-UP, unconsciousness and staggering not yet reached (need another seed or timing); MIN at `77act1.mud:963` |
| 5 | Scoring | SCORE-OBJ / SCORE-ROOM / SCORE-UPD | `77rooms.mud:654-668` | fixed | none known |

## First concrete scenario: enter the house and open the cellar

Commands as drafted (the executed sequence, confirmed natively, is in
`tests/scenarios/house-cellar.json`: `north`, `east`, `open window`, `west`,
`west`, `take lamp`, `move rug`, `open trap door`, `turn on lamp`, `down`,
`score`):
`north`, `east`, `open window`, `enter` (or `west`), `west`, `take lamp`,
`move rug`, `open trap door`, `turn on lamp`, `down`, `score`.

Checkpoints to record in both engines:

1. after `open window`: KITCHEN-WINDOW!-FLAG true;
2. after entering: `,HERE` is the kitchen, and the room-score change if any;
3. after `take lamp`: the lamp is in the winner's AOBJS and not in the room;
4. after `move rug`: the rug's ORAND is T and the trap door has OVISON set;
5. after `down` with the lamp on: `,HERE` is the cellar, LIT? true, and the
   trap door closes behind the player (TRAP-DOOR/CELLAR behaviour);
6. final `score` text and `,MOVES`.

Deliverables for the slice: a reference capture (fixed clock, disposable
copy), the candidate run through `mdl-session-run-interactive`, a strict
comparator over text plus checkpoints, and the first unsupported construct
reached (stop and implement it as its own slice if one is hit).

## Correctness debt to schedule against these scenarios

- **#127** (STRING literal identity/mutation): audit mutation reachability
  before scenarios 1–5 make broad play claims.
- **#121** (STRING accepted as a binding ATOM): focused strict-typing patch.
- **#122** (MAX): needed by scenario 4 and by RECORD's PRINTO branch
  (`77rooms.mud:741`, not reached under the no-file OPEN policy).
- **#126 / #129 / #134**: keep tracked with limited-scope evidence; not on
  these paths per current audits.
- **#120** (unbounded host allocation): a blocker before any shared or
  exposed execution; not needed for local scenarios.
- SAVE/RESTORE parity and complete-game verification are separate later
  slices; SAVE is an in-session record only (ADR-0048).
