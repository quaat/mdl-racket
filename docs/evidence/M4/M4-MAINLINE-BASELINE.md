# M4 mainline baseline (2026-11-23)

**Result:** M4 scenarios S1, S2, S3 — **PASS (mainline, scenario-scoped)**.
The M4 comprehensive-equivalence gate is **NOT YET PASSED**; **PLAYABLE: NOT
RUN** (no separately defined playability gate has been executed).

Gate run on `main` = **`c8964bfc2d556e0d3f5d7968dcc2695de81fa64f`** (merge of #155). This record
is added by a documentation-only commit afterwards.

## Integration (maintainer approval, 2026-11-23)

| PR | Slice | Reviewed head | Merge on `main` |
|---|---|---|---|
| #153 | M4 S1: enter the house and open the cellar (reference, checkpoints, frontier) | `e48532d` | `c439026` |
| #55 | AGENTS.md: provider-neutral agent roles (reconciled with main first) | `ce4aad2` | `3d67497` |
| #154 | M4 S2: CHTYPE to SEGMENT; drop matches native | `241e124` | `3a41e87` |
| #155 | M4 S3: CHTYPE to/from CHARACTER; orphan prompts match native | `d12b50e` | `c8964bf` |

All merges are regular merge commits. #155 was retargeted from the S2 branch
to `main` after #154 landed; its effective diff was the two S3 commits
(`8f0d06d`, `d12b50e`) only. The tree of `main` after #154 equals the tree of
#154's head, and the tree of `c8964bf` equals the tree of the CI-tested #155
head `d12b50e`. Before merging #154: head unchanged since review, CI green,
no review threads, runtime diff limited to `mdl/runtime/core.rkt`, ROOT TYPE
identity (not PNAME) for built-in dispatch confirmed, PR text updated with the
completed DrRacket record.

## Gate on `c8964bf`

**Local** (clean detached worktree, unsandboxed; **Racket v7.9 [bc]**;
`M3_NATIVE=require`; mdli sha256 `6df359f6…`; upstream mdlzork `bdcd4a67…`,
mit_zork `d9450134…`):

| Command | Exit | Result |
|---|---|---|
| `make sources` | 0 | source lock verified |
| `make test` | 0 | 3814 Racket tests; 68 Python passed, 1 native deselected; SEGMENT and CHARACTER unit suites pass |
| `make test-historical` | 0 | |
| `make m3-source-progress` | 0 | LOADED: 1229 original forms completed, 0 skipped |
| `make test-m3-interactive` | 0 | |
| `make test-m3-session` | 0 | |
| `make test-m3-launcher` | 0 | |
| `make test-m3-bang` | 0 | |
| `make test-m4-house-cellar` | 0 | all 12 prefixes = native, checkpoints equal; frontier: F1, F2, F2b resolved; F3 `help`/`info` strict as recorded |
| `make test-m4-mailbox-drop` | 0 | all 9 prefixes = native, 11 checkpoints each |
| `make test-m4-orphan-prompt` | 0 | all 10 prefixes = native, checkpoints equal |
| `M3_NATIVE=require make m3-check` | 0 | 7/7 PASS incl. native fresh capture (`native_mode: require`) |
| `git diff --check` | 0 | upstream checkout clean; no source modified |

**CI on `c8964bf`** (racket:8.10-bc):
[native reference run 45230824479](https://github.com/quaat/mdl-racket/actions/runs/45230824479)
(workflow_dispatch; every step success) and
[harness run 45230779719](https://github.com/quaat/mdl-racket/actions/runs/45230779719)
(push) — success.

## Scenario coverage on `main`

| Scenario | Commands | Native comparison |
|---|---|---|
| M3 house-boot smoke | north, west, open mailbox, take leaflet, inventory, score | strict, D1/D2 (ADR-0053) |
| M3 local quit session | + quit, n, inventory, quit, y | byte-identical, D1 |
| S1 house-cellar | north, east, open window, west, west, take lamp, move rug, open trap door, turn on lamp, down, score | 12 prefixes + 13 checkpoints |
| S2 mailbox-drop | open mailbox, take leaflet, drop leaflet, inventory, look, take leaflet, drop leaflet, look | 9 prefixes + 11 checkpoints |
| S3 orphan-prompt | open mailbox, take leaflet, throw leaflet, mailbox, look, take leaflet, kill mailbox, leaflet, inventory | 10 prefixes + checkpoints; plus `kill troll` → `lamp` from the cellar (frontier) |

All runs use the session clock fixed at 250776000 UTC and write no files.

## Manual DrRacket checks

Both **PASS** (maintainer runs, DrRacket 7.9 [3m]): quit returns control
(`(zork-result 'quit '() #f)`), and Stop interrupts the game with "user break"
while the REPL keeps answering — [record](DRRACKET-MANUAL-CHECK.md).

## Deviations and strict behaviour that remain

- Recorded deviations: CHTYPE to CHARACTER accepts codes 0–127 only
  (ADR-0057; Confusion does no range check; game reach ≤ 122); printing a
  SEGMENT is strict; CHTYPE to FORM stays refused; interpreted required
  formals splice where Confusion raises ILLEGAL-SEGMENT (ADR-0056); D1/D2
  presentation differences (ADR-0053); no ZORK.LOG on quit (ADR-0055).
- Strict by decision: `help`/`info` (OPEN "READ", `77rooms.mud:961`), RESTORE,
  other file operations.
- Known strict gaps ahead: TOP (`put X in …`, `77np.mud:126`), MAX in combat
  (`78melee.mud:447-448`, #122).
- Seen, not fixed: answering an orphan prompt with `with leaflet` errors in
  both engines with different messages.

## Next development targets

1. M4 S4: TOP and the parser path through `77np.mud:126` (new issue).
2. M4 S5: MAX (#122) and a weapon-based troll-combat path.
3. Scenario-corpus expansion (parser ambiguity / "Which X?", death and
   recovery, scoring and inventory, lamp countdown and clock events).
