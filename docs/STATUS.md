# Status — 2026-11-25 (`main` = `513272f`: M3 accepted; M4 S1–S10 merged (11 native-parity scenarios); SCENARIO_PARITY PASS for those 11 in a local `make m4-check` run on branch `feat/m4-check` (main + check scaffold, no runtime change; scenario-scoped, one fixed clock and seed); WP4 replay persistence proof of concept; GAMEPLAY_RELIABILITY NOT YET; PLAYABLE NOT RUN; FULL_COMPLETION NOT RUN; M4_ACCEPTED NOT YET)

## Current state (2026-11-23)

States used below: **PASS (mainline)** = verified on `main`; **PASS (branch
evidence)** = verified on an unmerged branch only; **FAIL**; **BLOCKED**;
**NOT RUN**. A branch PASS is not a mainline result.

### Mainline: `main` = `2a86d5d` (M3 mainline acceptance, 2026-11-23)

M0, M1 and M2 gates: **PASS (mainline)**. The M3 stack (#107 → … → #150,
#146, #142; #151) was integrated with the maintainer's approval and the full
gate rerun on `main` with `M3_NATIVE=require`
([acceptance record](evidence/M3/M3-MAINLINE-ACCEPTANCE.md)). Local runs:
Racket v7.9 BC; CI: racket:8.10-bc (runs 45176163020, 45176121779).

| M3 stage | State | Evidence |
|---|---|---|
| PARSED | PASS (mainline) | 36 historical text files parsed; 4 non-text files identified |
| LOADED | PASS (mainline) | loader exit 0 after 1,229 original forms, zero skipped (`make m3-source-progress`) |
| INITIALIZED | PASS (mainline, scoped) | faithful `<FLOAD "77loadall.mud">` + `<SAVE-IT>` (`make test-m3-saveit`) |
| INTERACTIVE | PASS (mainline, scoped) | six house-boot commands through the host loop (`make test-m3-interactive`) |
| SMOKE_PARITY | **PASS (mainline, scoped)** | house-boot at the session clock 250776000/UTC; one strict comparator, D1/D2 only (ADR-0053); promoted schema-3 reference `house-boot-reference.json`; `M3_NATIVE=require make m3-check` 7/7 incl. native fresh capture |
| Local session smoke | **PASS (mainline)** | quit/n, inventory, quit/y through the game's FINISH → RECORD → QUIT, byte-identical to native, no files written (`make test-m3-session`, `make test-m3-launcher`) |
| PLAYABLE | NOT RUN | M4 ([backlog](evidence/M4/SCENARIO-BACKLOG.md)) |

### M4 on `main` (`b6b86d0` 2026-11-23; S8–S10 and the runner merged up to `513272f`, 2026-11-25)

M4 scenarios run on `main` with the session clock fixed at 250776000 UTC,
compared prefix by prefix with pinned native Confusion and read-only state
checkpoints ([M4 baseline record](evidence/M4/M4-MAINLINE-BASELINE.md)):

| M4 item | State | Evidence |
|---|---|---|
| S1 enter the house and open the cellar | **PASS (mainline, scenario-scoped)** | #153; `make test-m4-house-cellar` (12 prefixes, 13 checkpoints) |
| S2 CHTYPE to SEGMENT; drop | **PASS (mainline, scenario-scoped)** | #154; `make test-m4-mailbox-drop` (9 prefixes); ADR-0056 |
| S3 CHTYPE to/from CHARACTER; orphan prompts | **PASS (mainline, scenario-scoped)** | #155; `make test-m4-orphan-prompt` (10 prefixes); ADR-0057 |
| S4 TOP; parser and EVERYTHING paths | **PASS (mainline, scenario-scoped)** | #158; `make test-m4-top-parser`; ADR-0058 |
| BACK keeps the argument's TYPE (maintainer decision) | **PASS (mainline)** | #160; ADR-0058 amendment; `tests/back_test.rkt`, `tests/top_test.rkt` |
| S5a MAX | **PASS (mainline)** | #159 (#122 closed); ADR-0059 accepted (zero-argument `<MAX>` only); `tests/max_test.rkt` |
| S5b TYPE of DEFINEd functions (FUNCTION) and built-ins (SUBR); take sword | **PASS (mainline, scenario-scoped)** | #161; `make test-m4-sword-glow` (14 prefixes); ADR-0060 |
| S6 troll combat with the sword | **PASS (mainline, scenario-scoped)** | #162; `make test-m4-troll-combat` (23 prefixes + checkpoints; troll dies on the third blow); [S6 record](evidence/M4/S6-TROLL-COMBAT.md) |
| S7 parser rejection and ambiguity (`Which door?`) | **PASS (mainline, scenario-scoped)** | #164; `make test-m4-parser-ambiguity` (35 prefixes + checkpoints: LEXV, PRSVEC, PARSE-WON, ORPHANS, MOVES); no runtime change; [S7 record](evidence/M4/S7-PARSER-AMBIGUITY.md) |
| S8 ABS; the cyclops (#167) | **PASS (mainline: PR #175, main 9f16d47, post-merge CI success; scenario-scoped)** | `tests/abs_test.rkt` (ABS on FIX/FLOAT, −2^35 strict overflow, arity/type refusals); `make test-m4-cyclops-room` (41 prefixes + checkpoints: cyclops RVARS −1/−2/2, SLEEPBIT, FIGHTBIT, CYCLOPS-FLAG, 22 RANDOM draws); [S8 record](evidence/M4/S8-ABS-CYCLOPS.md) |
| S9 IMAGE, SLEEP, TIME; the bat and the Strange Passage (#168–#170) | **PASS (mainline: PR #176, main 522b563, post-merge CI success; scenario-scoped)** | `tests/p0prims_test.rkt` (IMAGE exact byte 0–127; SLEEP waits only on a live clock, `mdl-clock-live?`, no clock read; TIME session-derived FLOAT, documented deviation); `make test-m4-mirror-bat` (38 prefixes + checkpoints, three BEL bytes, no wait under the fixed clock); `make test-m4-strange-passage` (32 prefixes + checkpoints: `odysseus`, BLROO, `c-int`); `tests/replay_sleep_time_test.rkt`; ADR-0052 amendment, ADR-0061 note; [S9 record](evidence/M4/S9-IMAGE-SLEEP-TIME.md) |
| S10 help and info under a read-only allowlist (#171; maintainer decision 2026-11-24) | **PASS (mainline: PR #189, main 513272f, post-merge CI success; scenario-scoped)** | ADR-0055 amendment: OPEN "READ" only for MDL/MADADV.HELP and MDL/MADADV.INFO, hash-checked, read-only, served from memory; FILE-LENGTH (characters), file READSTRING (count / stop, EOF partial count, never the input observer), CLOSE; every other OPEN "READ" strict before any file access; `tests/file_read_test.rkt` (17); `make test-m4-help-info` (9 turns single run + 9 prefixes per prefix, `,INBUF` checkpoints; ADR-0062 `#:prompt-split 'line-initial`); `tests/help_info_replay_test.rkt` (replay across help/info exact; tampered file strict); F3 resolved; INV-05 fixed, INV-08 partly; 11 mutations detected; [S10 record](evidence/M4/S10-HELP-INFO.md) |
| Phase 2 death and recovery: grue-resurrection, grue-refusal, troll-death (epic #163) | **PASS (local branch `feat/m4-death-branches`, not merged; scenario-scoped)** | F12 ("patched" = the game's resurrection question; unmodified sources) extended with carried possessions, F13 unchanged, and a new troll death (unarmed hero staggered, wounded, killed; no seed search); native references captured twice identically (`scripts/probe_death_scenario_reference.py`); ADR-0062 amendment: opt-in `#:entry-prompts` (YES/NO's question as an entry prompt) and `#:quit-prefixes` (runs ending by the game's QUIT, exactly RECORD's two denied OPENs, ADR-0055; native ZORK.LOG append documented, not normalised); `make test-m4-grue-resurrection` / `-grue-refusal` / `-troll-death` exit 0 in single-run and per-prefix modes; 8 mutations detected; `make m4-check` exit 0: SCENARIO_PARITY PASS (14), GAMEPLAY_RELIABILITY NOT YET with 14 of 23 branches covered (new: death.resurrection-accepted, death.resurrection-refused-quit, death.killed-in-combat, combat.hero-wounded, combat.hero-staggered-or-unconscious (staggered only)); [record](evidence/M4/DEATH-BRANCHES.md) |
| Phase 3 timers, objects and scoring: treasure-deposit, thief-robbery, cure-recovery, lamp-burnout (epic #163) | **PASS (local branch `feat/m4-timers-scoring`, not merged; scenario-scoped)** | No seed search; one opt-in runner option (ADR-0062 amendment: `#:eof-classification-ignore-keys`, fields left out only of the end-of-input classification); the probe gains a "timers" checkpoint profile (lamp and clock events, painting, trophy case, thief; `tests/m4_timers_checkpoint.rkt`); native references captured twice identically; the painting put in the trophy case (ASCORE 46), the thief taking it on the direct route (observed, kept as a scenario), the CURE clock healing a troll wound, the lamp's four warnings and burn-out after 118 `wait`s; robber_hroom compared everywhere, used to classify end-of-input tails only in thief-robbery; `make test-m4-treasure-deposit` / `-thief-robbery` / `-cure-recovery` / `-lamp-burnout` exit 0 in single-run and per-prefix modes; 14 mutations detected; `make m4-check` exit 0: SCENARIO_PARITY PASS (18), GAMEPLAY_RELIABILITY NOT YET with 17 of 23 branches covered (new: scoring.treasure-deposit, timers.cure-clock-recovery, timers.lamp-burnout; combat.thief stays uncovered: stealing only); [record](evidence/M4/TIMERS-SCORING.md) |
| Phase 3b beyond the house: match-clock, boat-river; dam frontier INV-11 (epic #163) | **PASS (local branch `feat/m4-dam`, not merged; scenario-scoped) for match-clock and boat-river; dam BLOCKED (INV-11) at the time; fixed by S14 (next row)** | No runtime change, no seed search; the probe gains "dam" and "boat" checkpoint profiles (dam flags, Maintenance Room, leak and match clocks, boats, pump, AVEHICLE; `tests/m4_dam_checkpoint.rkt`, `tests/m4_boat_checkpoint.rkt`; earlier profiles byte-identical); native references captured twice identically. match-clock: the match clock MATIN fired at a tick and at a `wait`, turned off, out of matches; boat-river: the pump by the Atlantis Room, the boat inflated, boarded, launched, landed, deflated. **Frontier:** the dam puzzle and its leak clock MNTIN (native references dam-sluice, maint-leak) stop this runtime at command 23, entering the Maintenance Room: MAINT-ROOM's attached #DECL names the undefined type PRSOBJ (strict by ADR #98; unchecked natively) — INV-11, P1, maintainer decision pending, tracked by `make xfail-m4-dam-frontier`. `make test-m4-match-clock` / `-boat-river` exit 0 in single-run and per-prefix modes; 7 mutations detected; `make xfail-m4-dam-frontier` exit 0 (XFAIL as recorded); `make test` exit 0; `make m4-check` exit 0: SCENARIO_PARITY PASS (20), GAMEPLAY_RELIABILITY NOT YET with 18 of 23 branches covered (new: timers.other-clock-events by the match clock; objects.puzzles-beyond-the-house left uncovered, the boat being one of five listed puzzles) and open blockers INV-06, INV-07, INV-11; [record](evidence/M4/DAM-CLOCKS.md) |
| S14 still-undefined attached TYPE names (#193, INV-11 fixed); dam-sluice, maint-leak | **PASS (local branch `feat/m4-prsobj-decl`, not merged; scenario-scoped)** | Maintainer decision 2026-11-25: the #98 ADR amendment (DECISIONS.md): an attached declaration's TYPE name still undefined when checked (no TYPE, no DECL association) matches any value at that position; a name defined later is strict; DECL?, positional, GDECL and known types stay strict; recorded deviation from the manual, alignment with pinned Confusion for undefined names only (Confusion checks no attached declaration). No source change. `tests/deferred_decl_type_test.rkt` 25/49 failing before, 49/49 after; `make test-m4-dam-sluice` (42 turns) and `make test-m4-maint-leak` (36 turns, the leak clock MNTIN) exit 0 in single-run and per-prefix modes against the committed references; `make xfail-m4-dam-frontier` retired; 3 mutations detected; `make test`, `test-historical`, `m3-check` exit 0; `make m4-check` exit 0: SCENARIO_PARITY PASS (22), GAMEPLAY_RELIABILITY NOT YET with 18 of 23 branches (timers.other-clock-events now also by MNTIN; objects.puzzles-beyond-the-house still uncovered, 2 of 5 puzzles) and open blockers INV-06, INV-07 (INV-11 resolved); [record](evidence/M4/S14-PRSOBJ-DECL.md) |
| Phase 3c the puzzles beyond the house: coal-machine, gas-room; balloon frontier INV-12 (epic #163) | **PASS (local branch `feat/m4-puzzles`, not merged; scenario-scoped) for coal-machine and gas-room; balloon BLOCKED (INV-12)** | No runtime change, no seed search; the probe gains the "puzzles" checkpoint profile (balloon, receptacle, BINT/BRNIN, rope, torch, glacier, coal-mine basket, coal, machine, diamond, LIGHT-SHAFT, EMPTY-HANDED, candles and CNDIN, bracelet; `tests/m4_puzzles_checkpoint.rkt`; all eleven earlier references byte-identical in their profiles); native references captured twice identically. coal-machine (94 commands): the screwdriver and the drained reservoir, the Altar's candles through the mirror, the coal up from the Dead End, coal, screwdriver and candles lowered in the basket, the empty-handed passage to the candle-lit Lower Shaft, the machine turning the coal into the diamond, the basket raised. gas-room (62): the Gas Room with the lamp only (nothing happens) and with the burning candles (the explosion, death question at entry 58, patched). **Frontier:** the balloon (native reference balloon-ledge: burned guidebook, rise, Narrow Ledge, wire tied and untied, landing) stops this runtime at command 57, `board basket`: BALLOON's attached #DECL `(PRSO) <OR OBJECT DIRECTION>` (77act2.mud:424) receives the `#FALSE ()` CLOCK-DEMON leaves in PRSVEC at the vehicle's READ-OUT call (known type, strict here; unchecked natively) — INV-12, P1, maintainer decision pending, tracked by `make xfail-m4-balloon-frontier`. `make test-m4-coal-machine` / `-gas-room` exit 0 in single-run and per-prefix modes; 7 mutations detected; `make xfail-m4-balloon-frontier` exit 0 (XFAIL as recorded); `make test` exit 0; `make m4-check` exit 0: SCENARIO_PARITY PASS (24), GAMEPLAY_RELIABILITY NOT YET with 18 of 23 branches (objects.puzzles-beyond-the-house still uncovered: 4 of 5 puzzles, the balloon blocked) and open blockers INV-06, INV-07, INV-12; [record](evidence/M4/PUZZLES.md) |
| #196 attached-declaration violation sweep (diagnostic only; INV-12 data) | **DONE (local branch `feat/m4-decl-sweep`, not merged; no semantic change)** | Maintainer decision 2026-11-26 "sweep first". Host-only, test-only `make-mdl-session #:decl-violation-recorder` (SEMANTICS; one read site; production hosts never pass it; `tests/decl_violation_recorder_test.rkt` in `make test`). `make m4-decl-sweep` (not in `make test`/m4-check): 24 gated scenarios 0 violations, all still PASS; balloon-ledge 2 sites (BALLOON PRSO, BINF) and, allowed to proceed, matches native at all 82 entries; MSWITCH IMP confirmed by a native-compared probe; SPHERE PV by a direct call. 4 distinct sites, all AUX; static PRSVEC upper bound 51 bindings in 45 #DECLs. Production stays strict (`make xfail-m4-balloon-frontier` XFAIL). Recommendation: option 2a; maintainer decision pending; [record](evidence/M4/DECL-VIOLATION-SWEEP.md) |
| S16 attached declarations not enforced (#196, INV-12 fixed); balloon-ledge gated | **PASS (local branch `feat/m4-attached-decl-unenforced`, not merged; scenario-scoped)** | Maintainer decision 2026-11-26 (after the sweep): attached `#DECL`s are not enforced at all in production, matching pinned Confusion; recorded deviation from the manual (DECISIONS: the attached-declaration ADR amendment; SEMANTICS). Definition-time validation unchanged; DECL?, GDECL/SETG, positional and CHTYPE strict with unchanged messages; the test-only recorder still evaluates every attached check. `tests/attached_decl_unenforced_test.rkt` new; 12 test modules failing before (raco 32/4707, `make test-racket` exit 2), all passing after (`make test` exit 0: raco 5165 passed, pytest 104 passed). `make test-m4-balloon-ledge` (81 commands, 82 entries) exit 0 single-run and per-prefix; `make xfail-m4-balloon-frontier` retired. `make test-historical`, `test-m2-g3`, `m3-check` exit 0; `make m4-check` exit 0: SCENARIO_PARITY PASS (25), GAMEPLAY_RELIABILITY NOT YET 19 of 23 (objects.puzzles-beyond-the-house covered by 5 gated checks), open blockers INV-06, INV-07 (INV-12 resolved). `make m4-decl-sweep`: exit 0, the same 4 sites with the recorder (BALLOON PRSO/BINF, MSWITCH IMP, SPHERE PV) and every one of the 27 units matching without it. New finding: the ATOM-taking binding primitives (SETG, GVAL, GASSIGNED?, SET, LVAL, VALUE, GUNASSIGN, MANIFEST) accept a STRING as an ATOM name (Confusion errors at least for GASSIGNED?), formerly hidden by MSETG's declaration; #199, tracked XFAIL; independent review: no blocking defects, comment/doc fixes applied; [record](evidence/M4/S16-ATTACHED-DECL.md) |
| combat.thief: thief-fight (epic #163) | **PASS (local branch `feat/m4-thief-fight`, not merged; scenario-scoped)** | No runtime change, no seed search; the probe gains the "thief" checkpoint profile (the timers fields plus the thief's OCAPAC, FIGHTBIT, STAGGERED, the stiletto, the chalice, HACTION; `tests/m4_thief_checkpoint.rkt`; the 14 earlier references' profiles unchanged); native reference captured twice, transcripts byte-identical. Route: strange-passage's first 25 commands, `up` into the Treasure Room (TREASURE-ROOM brings the thief whatever the seed; he attacks at once), `kill thief with sword` twice (the thief wounded twice, OCAPAC 4 -> 3 -> 2; the hero wounded, knocked out and killed), `y`, look, inventory, diagnose, score. `make test-m4-thief-fight` exit 0 (34 turns, 3 boots, 17.5 s); per-prefix exit 0 (34 boots, 197.0 s); 5 reference mutations each fail at the expected check or k; `combat.thief` covered by thief-robbery (steals) and thief-fight (fights, is fought) together; not exercised: his chance appearance elsewhere, his retreat, his death or knock-out. @@M4CHECK@@ [record](evidence/M4/THIEF-FIGHT.md) |
| Manual DrRacket checks (quit, Stop) | **PASS** | [record](evidence/M4/DRRACKET-MANUAL-CHECK.md) |
| WP4 host persistence by deterministic replay (ADR-0061; WP4.1–4.5 + WP4.6 regressions) | **PASS (mainline, proof of concept, scenario-scoped)** | #165 (independent review: no blocking defects; findings fixed); `make test-m4-replay-persistence` (troll combat saved at the RDCOM prompt before the first kill, restored in-process and in a fresh process: both RNG words, MOVES, 34-field state and transcript digests verified; pre-save + post-restore output = native T1; save after combat; pending lamp event; resumed clock; tampering; independence; 0.85 s replay per 100 commands + 6 s boot); `replay_clock_test`, `replay_checkpoint_test` in `make test`; player-facing SAVE/LOAD not implemented (needs an ADR-0055 amendment); [WP4 record](evidence/M4/WP4-REPLAY-PERSISTENCE.md) |
| Phase 1 single-run per-turn scenario runner (ADR-0062, proposed) | **PASS (mainline: PR #188, main 6b826d5, post-merge CI success; test infrastructure, no runtime change)** | `tests/m4_scenario_runner.rkt` drives all ten scenario tests: one boot per scenario, output and READSTRING-entry checkpoints compared at every turn, whole transcript and end state at end of input, non-standard end-of-input tails re-run per prefix (sword-glow 0, troll-combat 0, mirror-bat 33); both modes pass on all ten; 9 mutations give the same earliest failing k in both modes; divergence JSON and watchdog; `make test-m4-*` 1608.9 s → 292.3 s locally; lost coverage stated (212 standard EOF tails, `lit` read only at end); `make m4-scenarios-per-prefix` keeps the old protocol; [record](evidence/M4/SINGLE-RUN-RUNNER.md) |
| M4 comprehensive-equivalence gate | NOT YET PASSED | scenario, state, save/restore and completion criteria not met |
| PLAYABLE | NOT RUN | no playability gate executed |

#### Acceptance terms (epic [#163](https://github.com/quaat/mdl-racket/issues/163))

These are tracked separately and never collapsed into one PASS. Since
2026-11-25 they are computed by `make m4-check` (`scripts/m4_check.py`,
ADR-0063 proposed; rules in [TESTING](TESTING.md)) from the declared
[scenario manifest](../tests/scenarios/m4-manifest.json) and the declared
[gameplay branches](evidence/M4/gameplay-branches.json). The column below is
**a local branch result** (`feat/m4-check` at `013af37` = `main` `513272f`
plus the check scaffold, no runtime change; Racket v7.9 BC; `make m4-check`
exit 0; [record](evidence/M4/M4-CHECK.md)). It is not a mainline acceptance.

| Term | Meaning | State (local `make m4-check`, branch `feat/m4-check`, 2026-11-25) |
|---|---|---|
| SCENARIO_PARITY | each specified scenario matches pinned Confusion in text and in state checkpoints | **PASS for the 11 declared scenarios** (S1–S10: house-cellar, mailbox-drop, orphan-prompt, top-parser, sword-glow, troll-combat, parser-ambiguity, cyclops-room, mirror-bat, strange-passage, help-info), each under one fixed clock (250776000 UTC) and seed; per scenario, not gameplay coverage |
| GAMEPLAY_RELIABILITY | every declared required gameplay branch runs without an unexpected runtime failure | **NOT YET**: 9 of 23 declared required branches (PROVISIONAL list, epic categories combat, death and recovery, timers, objects, scoring, save/load) have a covering check, all passing; 14 have none (hero wounded/staggered/killed, the thief, both death branches, lamp burn-out, cure recovery, other clock events, puzzles beyond the house, treasure scoring, the game's save, restore, player-facing resume); open blockers INV-06 RESTORE (#172) and INV-07 PRINT in HANDLE (#173) |
| PLAYABLE | a user can start, interact, progress, quit and resume through a verified session | NOT RUN: no PLAYABLE gate exists. Sub-checks run as evidence and passed (`test-m3-session`, `test-m3-launcher`); missing: player-facing resume (WP4.7), the full playthrough (Phase 6) |
| FULL_COMPLETION | the game's real completion condition is reached and verified | NOT RUN: no complete-game check (#163 Phase 6) |
| M4_ACCEPTED | every M4 requirement in [PLAN](PLAN.md) is met (`make m4-check`) | **NOT YET**: GAMEPLAY_RELIABILITY, PLAYABLE and FULL_COMPLETION are not PASS, and "accepted exceptions are source-justified" has no maintainer record |

WP4 persistence (`test-m4-replay-persistence`) also passed in that run; it is
reported as its own check and as coverage of the branch
`save.host-replay-persistence`, never as a scenario.

Gates: `c8964bf` (S1–S3) every target exit 0 locally (Racket v7.9 BC,
`M3_NATIVE=require`) and in CI (racket:8.10-bc, runs 45230824479,
45230779719); each later slice was gated per PR (all M4 scenario targets plus
the M3 targets, run sequentially, exit 0) and CI green before merge. Strict by
decision: RESTORE and file operations (`help`/`info` read their two
allowlisted files since S10, branch evidence). S6 covers one
combat branch only (the troll dies; the hero is never hit): hero wounds,
death (JIGS-UP), unconsciousness and staggering are not reached under this
seed and timing. (Phase 2 branch evidence: troll-death reaches the hero's stagger, wound
and death unarmed under the same seed; unconsciousness is still not reached.) S7 covers the parser's rejection messages, the 5-letter
truncation, empty versus blank lines (only a non-empty line is a move) and
one `Which door?` question answered by adjectives; it needed no runtime
change. WP4 proves deterministic replay persistence. It is not a player-facing
save yet, and native SAVE/RESTORE stays strict. Next, in the order of epic
[#163](https://github.com/quaat/mdl-racket/issues/163):
1. the gameplay failure inventory and a single-run checkpoint runner;
2. combat branches found by searching clocks and seeds in the native game;
3. lamp and clock events, objects, scoring;
4. player-facing saves (WP4.7, after an ADR-0055 amendment).

The sections below describe the branch stack as it was integrated; they are
kept as the integration history.

### Integration history: umbrella #107 and the stack (now on `main`)

Runtime stack (merge order): #107 (umbrella `feat/m3-logical-gc`) → #109 →
#111 → #125 → #128 → #130 → #136 → #137 → #138 → #141 (S7 host loop + review
F1/F2) → #144 (S8 session clock) → #145 (S9 MEMBER) → #147 (S11 QUIT/OPEN) →
#148 (S12 launcher) and #150 (S13 READSTRING `!` and explicit output ports;
both on #147). Side branches on that stack: #146 (S10 strict
SMOKE_PARITY gate, on #144), #142 (docs reconciliation, on #141), #143
(native reference probe evidence, on #141). The integration branch
`integration/m3-acceptance` merges all of them; #131's capture tooling is
merged into #146. All of it is on `main` since 2026-11-23 (#151 / `2a86d5d`).

| M3 stage | State | Evidence |
|---|---|---|
| PARSED | PASS (branch evidence) | as on `main` |
| LOADED | PASS (branch evidence) | loader exit 0 after 1,229 original forms, zero skipped (`make m3-source-progress`) |
| INITIALIZED | PASS (branch evidence, scoped) | faithful `<FLOAD "77loadall.mud">` + `<SAVE-IT>`; SAVE is an in-session record (ADR-0048); host loop per ADR-0050; `make test-m3-saveit`, `make test-m3-interactive` |
| INTERACTIVE | PASS (branch evidence, scoped) | the six house-boot commands read by the original RDCOM and answered exactly (`make test-m3-interactive`) |
| SMOKE_PARITY | **PASS (branch evidence, scoped)** — #146 | fresh-boot house-boot scenario at the session clock fixed to epoch 250776000, UTC (ADR-0052). One strict comparator (ADR-0053): only D1 (LISTEN banner, `"DONE"`) and D2 (`canonical_text(ONLCR(raw))`) differ; date line, `west` (PROB 80 draw 65), every response, score line and move count exact; the candidate ends by D3 input exhaustion. Fresh native Confusion capture == committed candidate record == this runtime (`make m3-check` 7/7; CI run 45155753586 incl. native comparison). Clock→seed chain: DSKDATE = START seed 10438660480 and the RANDOM sequence equal native ([CLOCK-SEED-REFERENCE](evidence/M3/CLOCK-SEED-REFERENCE.md), `make test-m3-clock-seed`). Gameplay approval of the candidate reused; no new golden content |
| Local session smoke | **PASS (branch evidence)** — #147/#148 | boot, six commands, `quit`/`n`, `inventory`, `quit`/`y` through the game's own FINISH → RECORD → QUIT; transcript byte-identical to native (D1 only); outcome `'quit`; extra input unread; no file written (OPEN denied per ADR-0055; Confusion writes `MDL/ZORK.LOG` — documented deviation, no visible difference). `make test-m3-session`, `make test-m3-launcher` (CI run 45158909816) |
| PLAYABLE | NOT RUN | M4 scope ([backlog](evidence/M4/SCENARIO-BACKLOG.md)); known strict gaps below |

Known strict gaps on the branch (each fails with an error, never stubbed):
`put X in …` (unsupported TOP at `77np.mud:126` / CHTYPE conversion);
`info`/`help` (OPEN "READ"); `script` reports it cannot open the channel; an
in-game MDL ERROR stops at unsupported PRINT in HANDLE (`77rooms.mud:251`)
before reaching QUIT; RESTORE unsupported. Local runs used Racket v7.9 BC;
CI uses the pinned racket:8.10-bc container.

### Fixed by the integration (now on `main`)

These fixes reached `main` with the umbrella #107 (2026-11-23); their issues
can now be closed against `main`.

| Item | Fix | Record |
|---|---|---|
| #119 backslash-escaped atom names | PR #132 | [I119](evidence/M3/I119-ESCAPED-TRAILER.md) |
| #124 leading-dot FLOAT | PR #133 | [I124](evidence/M3/I124-LEADING-DOT.md) |
| #139 UNWIND cleanups masking raised errors | PR #140, ADR-0051 | [I139](evidence/M3/I139-UNWIND.md) |
| #113 R1 session-owned CHANNEL ports | PR #117 | [R1](evidence/M3/review/R1.md) |
| #113 R2/R10 GC growth, robust GC tests | PR #123 | [R2](evidence/M3/review/R2.md) |
| #113 R3/R4 OBLIST authority, ROOT identity | PR #118 | [R3R4](evidence/M3/review/R3R4.md) |
| #113 R5/R7 constructor evaluation, STRING views | PR #114 | [R5R7](evidence/M3/review/R5R7.md) |
| #113 R6 MIN as an ordinary PDP-10 FLOAT | PR #115 | [R6](evidence/M3/review/R6.md) |
| #113 R8 ERROR delivery, ERRET level | PR #116 | [R8](evidence/M3/review/R8.md) |
| #113 R9 reference probe evidence | unknown: the branch `evidence/m3-107-reference-probes` named in #113 is not on `origin`; per-finding probes are in each R record | — |

The issue #113 body still lists R2-R4 as "review running" and R6/R8 nits
as open; the merges above supersede that table. The contracts are
consolidated into [SEMANTICS](SEMANTICS.md).

### Next

Active iteration (PLAN "Active iteration (2026-11-23)"): WP1 stack
readiness done on branch (F1 CI coverage, F2 flush, F3 docs, #55); WP2
SMOKE_PARITY PASS on branch; WP3 MEMBER, QUIT, OPEN, READSTRING `!` and
explicit output ports done on branch (#145, #147, #150); WP4 local session smoke and launcher PASS
on branch; WP5 [M4 backlog](evidence/M4/SCENARIO-BACKLOG.md) drafted.

M3 is accepted on `main` (scoped as above). Issues #119, #124, #135 (part 1)
and #139 are fixed on `main`. Next: M4, first scenario "enter the house and
open the cellar"; a manual DrRacket run (quit and Stop) would close the
remaining GUI verification gap.

## Slice history (newest first; each entry as recorded at the time)

- **S7 interactive terminal I/O on `feat/m3-interactive-io` (WIP, ADR-0050):**
  RESET (terminal CHANNEL; clears the host end-of-input flag), PRINC (STRING,
  CHARACTER, FIX), PRIN1 (FIX, trailer-free ATOM incl. `,NULL`), READSTRING
  (RDCOM/YES-NO form; stop consumed; overflow kept; no echo; flush first) and
  the local host loop `mdl-session-run-interactive` (explicit ports; entry value
  printed per D1; GVAL REP re-read each pass). End of input follows D3
  "Mirror, then strict". The faithful path plays the six approved commands:
  `make test-m3-interactive` exit 0 (30 checks); 10 raw runs are byte-identical
  to Confusion's pipe output after removing `"DONE"` and the date. The `west`
  response is RNG-dependent (`<PROB 80>`, 77rooms.mud:523) until #135. Strict
  and unsupported: QUIT, OPEN/CLOSE, MEMBER, PRINC line breaking, `!` in input,
  READSTRING default channel/FIX stop/EOF routine. See
  [S7 evidence](evidence/M3/S7-INTERACTIVE.md).

- **S6 inert REP on `feat/m3-startup-rep` (WIP, ADR-0049):** The GVAL of
  ROOT REP is a predefined SUBR in every session (TYPE SUBR, GASSIGNED,
  APPLICABLE; `<SETG SAVEREP ,REP>` keeps the same object), matching pinned
  Confusion (`evidence/M3/S6-rep-reference.json`). Applying the default REP
  by any path is a strict error naming ADR-0049; no raw MDL REPL exists. The
  host top-level loop that applies the current GVAL of REP is specified in
  SEMANTICS but not implemented. The faithful path now passes
  77rooms.mud:301-302 and fails at `<RESET ,INCHAN>` (303):
  `mdl-eval: unassigned or non-applicable MDL operator RESET`. Next
  blockers: RESET, then the host loop, PRINC, READSTRING. Sandboxed checks
  only so far; no INITIALIZED, interactive or parity result is claimed.
  See [S6 evidence](evidence/M3/S6-REP.md).

- **S5 SAVE session record on `feat/m3-startup-save-record` (WIP, ADR-0048):**
  SAVE returns a fresh `"SAVED"`, writes no file, performs no GC or
  interrupt side effect, and records (sequence, file-spec, INT-LEVEL) for
  host inspection; RESTORE stays refused; `"BLOCKED"` registers but never
  fires. Earlier, S4 (ADR-0047, issue #112) added ON with IPC registration
  and stopped at the strict SAVE refusal at 77rooms.mud:26. The faithful
  `<FLOAD "77loadall.mud">` + `<SAVE-IT>` path now records one SAVE of
  `"<MDL>MADADV.SAVE"` at INT-LEVEL 100000, executes `<INT-LEVEL 0>`
  (77rooms.mud:26; no GC/DIVERT-AGC occurrence was pending), STARTER,
  GETSYS, `ON "BLOCKED"` and START (welcome text, INT-LEVEL 0 at 292),
  and fails in CONTIN at 77rooms.mud:301 `<SETG SAVEREP ,REP>`:
  `mdl-gval: unassigned MDL global REP`. Next blockers per the reference
  trace: GVAL REP plus a LISTEN loop that applies it, RESET, PRINC,
  READSTRING. No INITIALIZED, interactive or parity result is claimed.
  See [S5 evidence](evidence/M3/S5-SAVE-RECORD.md) and the
  [reference frontier](evidence/M3/S5-SAVE-FRONTIER.md).

- **Issue #110 BACK follow-up on `feat/m3-back-continuation` (WIP):**
  Manual and pinned Confusion probes establish BACK view behavior and the
  terminal CHANNEL predecessor slot. The unchanged original START now
  passes RANDOM and BACK, then fails at unassigned `TENEX?` in
  `77rooms.mud:298`. Original source wrappers set this platform global
  through GETSYS before START; direct START bypasses that setup. The
  next slice must probe the source's startup prelude and report its next
  real failure. No interactive or smoke-parity result is claimed. See
  [BACK evidence](evidence/M3/BACK-CONTIN.md).

- **Issue #108 RNG follow-up on `feat/m3-session-random` (WIP):** A
  session-owned two-word 36-bit generator passes deterministic reference
  cases, seed-order checks, strict errors, range checks and independent
  session tests. The unchanged START now passes RANDOM and fails at
  unassigned `BACK` in `77rooms.mud:297` after welcome output. The source
  load remains 1,229 forms, zero skips. This is a new executable frontier,
  not an INITIALIZED or M3 pass. See [RANDOM evidence](evidence/M3/RANDOM-START.md).

- **Current WIP `feat/m3-logical-gc` (reviewed checkpoint `c5a6027`):** The complete unchanged
  source chain loads: 1,229 forms, zero skips, loader exit 0. This is a
  scoped LOADED gate result, not M3 acceptance. A direct original `START`
  call fails at unassigned `RANDOM` after CRLF; terminal input, the game loop, approved
  house smoke parity, and state comparisons remain unverified. After CI fixture
  repair and GC/UVECTOR regressions, `make test` passes 1,471 Racket and 23
  Python tests; `make m2-check` exits 0 on the repaired head. The
  logical GC ledger covers LIST, VECTOR and UVECTOR backing allocations,
  with the limits in [WIP evidence](evidence/M3/WIP-SOURCE-LOAD.md). The
  next executable action is a reference-validated session RNG and then
  the original terminal I/O path. M3 status: **FAIL / incomplete**.

- **Previous issue #104 interrupt foundation on `feat/m3-interrupt-dispatcher`:
  scoped Gate A PASS after independent review; Gate B BLOCKED and M3
  incomplete.** Session-owned
  priority dispatch, pending occurrences, `INT-LEVEL`, `ENABLE`, and
  `DISABLE` have focused red-to-green tests. Independent review findings
  were fixed for queued delivery after a handler exception,
  event-order preservation, and strict predefined event registration.
  The verified source frontier remains **433 completed forms, zero
  skipped**, with loader exit 1 at `77rooms.mud` expression 16, line 101:
  `EVENT "GC"` stays guarded until an actual post-collection event source
  and defensible `<GC>` return semantics exist. The blocker is missing
  MDL reclaimed-word accounting and automatic collection scheduling;
  options and the recommended bounded ledger feasibility probe are in
  [ADR-0043](DECISIONS.md). `make m3-source-progress`
  exits 0 only as a partial measurement. M2 remains PASS; source loading,
  initialization, interactive input and parity are unverified. See
  [interrupt evidence](evidence/M3/INTERRUPT-FOUNDATION.md) and
  [issue #104](https://github.com/quaat/mdl-racket/issues/104).

- **Issue #102 user EVENT/HANDLER registration slice PASS on
  `feat/m3-event-handler`; full M3 gate incomplete:** session-owned
  IHEADER and HANDLER objects support registration, identity, removal
  and reattachment for user-defined STRING events. The manual supplies
  these rules; pinned Confusion stubs the related operators as `T`, so
  native output is a documented reference deviation. Automatic events,
  callback dispatch and process-targeted handlers remain unsupported.
  The unchanged loader completes **433 original forms, zero skipped**,
  up from 430, then exits 1 at `77rooms.mud` expression 16, line 101:
  `EVENT "GC"` is explicitly unsupported until real GC callback delivery.
  The blocker is absent automatic GC scheduling; the options are to
  implement verifiable delivery or keep registration unsupported. The
  recommended next action is a GC callback probe and implementation,
  with the source stop retained until verified.
  `make m3-source-progress` exits 0 only as a partial measurement. See
  [evidence](evidence/M3/EVENT-REGISTRATION.md) and next
  [issue #104](https://github.com/quaat/mdl-racket/issues/104) under
  [event issue #71](https://github.com/quaat/mdl-racket/issues/71).
  Full load, initialization, interactive input and parity remain unverified.
- **Issue #100 duplicate ATOM declaration slice PASS on
  `feat/m3-duplicate-decl`; full M3 gate incomplete:** duplicate names
  retain both Patterns and enforce their conjunction in source order.
  Manual precedence is unspecified and the conjunction is documented as
  an inference; pinned Confusion accepts the syntax but does not enforce
  attached declarations. The unchanged loader completes **430 original
  forms, zero skipped**, up from 363, fully loading `77act1.mud`,
  `77act2.mud` and `77act3.mud`. It exits 1 at `77rooms.mud`
  expression 13, line 92: unassigned `HANDLER`. `make m3-source-progress`
  exits 0 as a partial measurement only. See
  [evidence](evidence/M3/DUPLICATE-DECL.md) and next
  [issue #102](https://github.com/quaat/mdl-racket/issues/102) under
  [event issue #71](https://github.com/quaat/mdl-racket/issues/71).
  Full load, initialization, interactive input and parity remain unverified.
- **Issue #98 deferred attached TYPE names PASS on
  `feat/m3-deferred-decl-type`; full M3 gate incomplete:** an unresolved
  TYPE atom remains in an attached declaration and is resolved only when
  checking a value. It raises an error if still unknown; explicit `DECL?`
  remains immediate. Four clean and two error-level pinned Confusion probes
  support the distinction, with attached enforcement retained as a manual
  rule and reference deviation. The unchanged loader completes **363
  original forms, zero skipped**, up from 233, and fully loads
  `77act1.mud`. It exits 1 at `77act2.mud` expression 39, line 424:
  duplicate declaration for `M`. `make m3-source-progress` exits 0 as a
  partial measurement only. See [evidence](evidence/M3/DEFERRED-DECL-TYPE.md)
  and next [issue #100](https://github.com/quaat/mdl-racket/issues/100).
  Full load, initialization, interactive input and parity remain unverified.
- **Issue #96 NTH declaration slice PASS on `feat/m3-nth-declaration`;
  full M3 gate incomplete:** positive-count repeated Pattern sequences
  match lazily and reject short values; NTH also works in NEWTYPE's stored
  Pattern. Thirteen clean and four error-level pinned Confusion observations
  are retained. Its attached `[3 ANY]` accepts a short vector, a documented
  reference deviation from the manual and this runtime. The unchanged
  loader completes **233 original forms, zero skipped**, up from 188,
  and exits 1 at `77act1.mud` expression 55, line 740: unknown
  declaration type `PRSOBJ`. `make m3-source-progress` exits 0 only as a
  partial-progress measurement. The next bounded task is
  [issue #98](https://github.com/quaat/mdl-racket/issues/98). See
  [NTH evidence](evidence/M3/NTH-DECL.md). Full loading, initialization,
  interactive input and game parity remain unverified.
- **Issue #94 session-aware `%` READ slice PASS on
  `feat/m3-read-time-percent`; full M3 gate incomplete:** executable
  reading evaluates `%` before consuming the next sibling, retaining the
  actual substituted object per session. `ASCII` and CHARACTER-capable
  `STRING` satisfy the original `81tell-repl.mud:46` expression. Native
  probes confirm ordering, once-only substitution, identity and errors.
  The unchanged loader completes 188 original forms with zero skips,
  fully loads `81tell-repl.mud`, and exits 1 at `77act1.mud`
  expression 10, line 78: unsupported NTH declaration Pattern
  `[3 ANY]`. `make m3-source-progress` exits 0 as a partial-progress
  measurement. Full load, initialization and gameplay remain unverified.
  See [issue #94 evidence](evidence/M3/PERCENT-READ.md),
  [next issue #96](https://github.com/quaat/mdl-racket/issues/96), and the
  [compatibility inventory](evidence/M3/COMPATIBILITY-INVENTORY.md).
- **Issue #92 `!\` CHARACTER reader slice PASS; full M3 gate
  incomplete:** `!\ ` now reads as a CHARACTER with code 32, distinct
  from SEGMENT syntax. Five native cases corroborate TYPE, primitive
  type, ASCII code and identity. `make test` passes 1,160 Racket and
  22 Python tests; `make m2-check` passes. The unchanged loader still
  completes 157 forms, zero skipped: the first failure moves within
  `81tell-repl.mud` expression 23 from `!\ ` at line 45 to the
  distinct `%<STRING <ASCII 10>>` read macro at line 46. This slice
  has **no completed-form increase**. See
  [evidence](evidence/M3/SPACE-CHARACTER.md) and
  [next issue #94](https://github.com/quaat/mdl-racket/issues/94).
- **Issue #90 positional `#DECL` metadata slice PASS; full M3 gate
  incomplete:** the RSUBR-style `"VALUE"`/`"OPTIONAL"` Pattern list
  is validated and retained on FUNCTION, without ATOM-variable
  enforcement, matching nine pinned Confusion observations. `make
  test` passes 1,148 Racket and 22 Python tests; `make m2-check`
  passes. The unchanged loader completes 157 forms, zero skipped,
  then stops at `!\ ` in `81tell-repl.mud` expression 23, line 45.
  See [evidence](evidence/M3/FUNCTION-DECL.md) and
  [next issue #92](https://github.com/quaat/mdl-racket/issues/92).
- **Issue #88 custom WORD-primtype literal slice PASS; full M3 gate
  incomplete:** the parser reads `#PSTRING 0` as one typed object in
  the original two-element AUX default. Six native cases confirm its
  PSTRING TYPE, WORD primitive, data and binding; a deliberate
  wrong-primitive native observation differs from manual CHTYPE
  safety, which Racket retains. `make test` passes 1,135 Racket and
  22 Python tests; `make m2-check` passes. The unchanged loader
  completes 144 original forms, zero skipped, then stops at a
  function-style `#DECL` in `81tell-repl.mud` expression 10, line 27.
  See [evidence](evidence/M3/PSTRING-LITERAL.md) and
  [next issue #90](https://github.com/quaat/mdl-racket/issues/90).
- **Issue #86 `%<>` reader macro value slice PASS; full M3 gate
  incomplete:** the side-effect-free empty FORM after `%` becomes
  canonical empty FALSE in data or expression position. Six native
  cases corroborate TYPE, truth and identity; other `%`/`%%` forms
  still fail strictly. `make test` passes 1,121 Racket and 22 Python
  tests; `make m2-check` passes. The unchanged loader completes 136
  original forms, zero skipped, fully loading `77makstr.mud` before a
  three-element typed AUX formal in `81tell-repl.mud` expression 2,
  line 3. See [evidence](evidence/M3/PERCENT-EMPTY.md) and
  [next issue #88](https://github.com/quaat/mdl-racket/issues/88).
- **Issue #84 APPLICABLE declaration Pattern slice PASS; full M3 gate
  incomplete:** the manual's compound type name now matches the callable
  values represented by this runtime, including FIX, FUNCTION, MACRO and
  SUBR, in simple, OR and structured Patterns. Six native `APPLICABLE?`
  cases corroborate type applicability; direct Confusion `DECL?`
  APPLICABLE probes instead enter an error, a documented deviation.
  `make test` passes 1,113 Racket and 22 Python tests; `make m2-check`
  passes. The unchanged loader completes 112 original forms, zero
  skipped, fully loading `77defs.mud`. The next failure is `%<>` in
  `77makstr.mud` expression 6, line 73. See
  [evidence](evidence/M3/APPLICABLE-DECL.md) and
  [next issue #86](https://github.com/quaat/mdl-racket/issues/86).
- **Issue #82 quoted OPTIONAL default slice PASS; full M3 gate incomplete:**
  the manual and six pinned Confusion cases establish raw explicit
  arguments and evaluated defaults in the growing frame. Focused tests
  pass; `make test` passes 1,097 Racket checks and 22 Python tests;
  `make m2-check` passes. The unchanged loader now completes 87 forms,
  zero skipped, then stops at `APPLICABLE` in `77defs.mud` expression
  78, line 448. See [evidence](evidence/M3/QUOTED-OPTIONAL.md) and
  [next issue #84](https://github.com/quaat/mdl-racket/issues/84).
- **Issue #80 eager AND? slice PASS; full M3 gate incomplete:**
  seven clean native cases, one deliberate late-error case and a
  SHA-verified original-source regression establish eager argument
  evaluation and all five `MSETG` global side effects in `77defs.mud`
  expression 28. `make test` passes 1,086 Racket checks and 22 Python
  tests. The unchanged loader reaches 70 completed forms, zero skipped;
  the next failure is a quoted OPTIONAL default in `77defs.mud`
  expression 61, line 338. See [evidence](evidence/M3/ANDQ.md) and
  [next issue #82](https://github.com/quaat/mdl-racket/issues/82).
- **Issue #78 GDECL slice PASS; full M3 gate incomplete:** original
  `GDECL` is a source-data FSUBR that installs global value Patterns and
  checks later `SETG`. Pinned Confusion's GDECL is an explicit no-op, so
  this is a documented manual/reference deviation. `make test` passes
  1,077 Racket checks and 22 Python tests; the unchanged loader completes
  37 forms with zero skips and then stopped at `AND?` in `77defs.mud`
  expression 28, line 146. See [evidence](evidence/M3/GDECL.md) and
  [next issue #80](https://github.com/quaat/mdl-racket/issues/80).
- **Issue #76 source-backed slice PASS; full M3 gate incomplete:**
  three-argument `NEWTYPE` stores and enforces a declaration Pattern,
  including `<<PRIMTYPE VECTOR> ...>` structure heads and same-primitive
  redeclaration. The pinned Confusion reference ignores this third
  argument, a documented manual/reference deviation. The unchanged loader
  reached 36 forms with zero skips, then stopped at `GDECL` in
  `77defs.mud` expression 27, line 139. See [evidence](evidence/M3/NEWTYPE-DECL.md)
  and [next issue #78](https://github.com/quaat/mdl-racket/issues/78).
- **First M3 source-backed slice PASS; full M3 gate remains incomplete:**
  issue #75 adds native-backed `EMPTY?`, bounded `LENGTH?`, current-frame
  `ASSIGNED?`, and startup `ROOT`. `make test` passes 1,046 Racket checks
  and 22 Python tests; `make m2-check` passes its G3 58 assertions and
  native probes/capture. `make m3-source-progress` measures 26 completed,
  zero skipped forms, two beyond the accepted prefix. The first remaining
  barrier at that checkpoint was `77defs.mud` expression 17, line 66: three-argument
  `NEWTYPE`, tracked in [issue #76](https://github.com/quaat/mdl-racket/issues/76).
  See [slice evidence](evidence/M3/EMPTYQ.md). The optional
  `ASSIGNED?` ENV form, full loader, initialization, and play are not
  supported or established.

- **M2 gate PASS on integrated `main` code baseline `7d34195`:**
  [mainline report](evidence/M2/MAINLINE-GATE.md) records the eight
  authorized merges, requirements audit, all command exits, source hashes,
  reference comparisons, CI and limits. G0/G1/G2 and G3 pass; G3 executes
  59 same-session exact-source assertions. `make m2-check` exits 0 with
  986 Racket checks and 13 Python tests; the final `main` harness run
  44889721673 succeeds.
- **First M3 source barrier:** the unchanged `77loadall.mud` chain exits 1
  after 24 completed and zero skipped forms at unassigned `EMPTY?` inside
  original `NEWSTRUC`, `77defs.mud` expression 15, line 37 (execute).
  This is not game initialization or a playable session.
- **M3 progress infrastructure:** issue #73 makes the M2 regression suite
  independent of full-loader progress and adds a machine-readable M3
  source-progress target. `make m2-check` now passes with 986 Racket, 22 Python and
  58 original-source G3 assertions; `make m3-source-progress` passes with
  the authentic 24-form EMPTY? report. See [M3 source progress](evidence/M3/SOURCE-PROGRESS.md).
- **Earlier next action:** implement EMPTY? from native evidence. Random/event APIs are tracked in
  [M3 issue #71](https://github.com/quaat/mdl-racket/issues/71), with no
  parity claim. The pinned Confusion reference loads the full 12-file
  chain to `DONE`.

## Earlier branch checkpoints (retained for provenance)

The [branch acceptance report](evidence/M2/BRANCH-ACCEPTANCE.md) records
the last stacked-head result before integration. The independent D5 review
and issue #67 correction are in [D5-FINAL-REVIEW.md](evidence/M2/D5-FINAL-REVIEW.md).
The [G3-GATE-MAPF.md](evidence/M2/G3-GATE-MAPF.md) report records the
first branch-level 59-assertion G3 PASS; the [requirements audit](evidence/M2/REQUIREMENTS-AUDIT.md)
traces the accepted M2 surface. Older FAIL checkpoints below preserve their
original observations and must not be read as current blockers.

## Earlier checkpoints (retained for provenance)
- **Earlier N=? local slice:** `make test` 879 Racket checks and 13 Python tests;
  focused `neq_test.rkt` 13 checks. Original MSETG advanced from `N=?`
  to `,.FOO`; see [evidence](evidence/M2/NEQ.md). The next action is
  issue #58, then repeat G3. M3 `EMPTY?` waits for G3.
- **Earlier issue #58 stacked reader slice:** `,.FOO` parses as GVAL of the local
  value FOO. `make test` passes 884 Racket checks and 13 Python tests;
  `make test-historical` passes exact-source MSETG first/equal-repeat paths
  alongside VFLOAD and DECL. The original conflicting-repeat path now reaches
  unassigned `ERROR`; G3 is still FAIL. See
  [computed-global evidence](evidence/M2/COMPUTED-GLOBAL.md). Next: probe
  and implement `ERROR` as a separate source-backed slice (issue #60), then
  rerun G3.
- **Earlier issue #60 stacked ERROR slice:** `make test` passes 888 Racket checks
  and 13 Python tests; `make test-historical` includes the hash-verified
  original MSETG conflict and passes. Confusion's `ERROR` enters a
  resumable level; this Racket slice raises a non-resumable exception with
  evaluated arguments. See [evidence](evidence/M2/ERROR.md). The integrated
  G3 was rerun and fails at `MEMQ`; no gate PASS claim is possible.
- **Earlier current-head G3 rerun:** `make test-m2-g3` exits 2 after 48 passing
  integrated assertions; original MSETG first/equal/conflict paths pass,
  while original PSETG reaches unassigned `MEMQ` after its initial SETG
  and PURE-LIST side effects. **G3 FAIL**. See
  [gate evidence](evidence/M2/G3-GATE.md); focused correction issue #63.
- **Current MEMQ/G3 rerun:** `make test` passes 903 Racket checks and 13
  Python tests; `make test-historical` passes VFLOAD 23, DECL 21, MSETG,
  and PSETG. `make test-m2-g3` exits 2 after 52 passing assertions because
  original FLAGWORD reaches unassigned `MAPF`. **G3 FAIL**. See
  [MEMQ evidence](evidence/M2/MEMQ.md) and [G3 gate](evidence/M2/G3-GATE.md).
- **Not demonstrated:** full integrated M2 state invariants, game boot,
  parser, puzzle behavior, RNG parity.


## M2 source execution audit (G0)

**G0 PASS; M2 integrated gate NOT RUN.** The baseline on
`36df3cefccfb9e382cef113752dcd16457e1e95c` reproduces 513 local Racket
checks, 13 Python tests, 36 parsed source files, the native build, capture and
probe. The 508 count on Racket 8.10 is a RackUnit nested-check reporting
difference, verified with a deliberately failing nested assertion in a
disposable copy. The first actual source barriers were `FLOAD`, `#DECL`, the
native `MUDDLE` global, and source ordering; `FLOAD` (G1/G2) and `#DECL`
(M2-D1, PR #45) are now cleared, and the current blocker is the `!`-splice in
the original `PSETG` (issue #46). See
[`SOURCE-READINESS.md`](evidence/M2/SOURCE-READINESS.md) and its JSON inventory.
Next: the SEGMENT slice (issue #46). Original source
execution and gameplay have not been demonstrated.

## M2 shared-session source loader (G1)

**G1 PASS locally; M2 integrated gate NOT RUN.** A root-restricted local
loader compiles and executes top-level forms in order, shares MDL state across
files, and routes nested `FLOAD` through the same session. Controlled fixture
tests cover ordering, definitions/macros, fresh-session isolation,
partial failure, missing files, traversal, symlink escape, cycles, repeated
loads and source diagnostics. The original `77loadall.mud` now executes its
`VFLOAD` definition and begins `81prim.mud`; it stops on the genuine
unsupported `#DECL` at line 3:9. See
[`SOURCE-LOADER.md`](evidence/M2/SOURCE-LOADER.md) and the structured
[load report](evidence/M2/source-load-first-barrier.json). G2 must invoke the
unmodified definition with controlled input; no gameplay is claimed.
The PR #41 review follow-up fixes an indirect symlink escape and preserves
completed forms before later reader errors. The first native CI run failed
because the minimal image lacks `raco make`; the conditional precompile fix
passed both the harness and native reference CI workflows on the follow-up
commit. That follow-up reported 561 Racket checks and 13 Python tests. See
the review section of `SOURCE-LOADER.md`.
The second PR #41 review identified link targets containing `..` after a
symlink and interpreted definitions rejected by `mdl-session-call`. Both now
have focused regressions and local fixes; see the same report for validation.
The third review found a consecutive-parent path bug. Its regression failed
with the wrong child file and now passes; the current suite reports 570
Racket checks and 13 Python tests.
Both follow-up workflows passed on `88d7b39`: harness run 44571160830 and
native reference run 44571160806. G1 remains a local slice PASS while the
PR is under review. G2 has a separate stacked PR #43; the integrated M2
gate remains open.

## M2 historical VFLOAD partial-source probe (G2)

**G2 PASS locally; integrated M2 G3 NOT RUN.** The test verifies the pinned
`77loadall.mud` SHA256, copies its bytes unchanged into a disposable
authorized root, executes only its first `DEFINE VFLOAD`, and invokes that
original reconstructed-source definition on a controlled file. The loader
explicitly reports PARTIAL (one completed, 12 unexecuted forms); the call
prints `<fixture-path> loaded`, returns empty FALSE and installs the fixture's
global value. Six focused pinned Confusion cases corroborate the relevant
output and state. See [`HISTORICAL-VFLOAD.md`](evidence/M2/HISTORICAL-VFLOAD.md).
`PRINTSTRING` follows the manual's count return while Confusion returns the
buffer, a recorded deviation that does not affect VFLOAD's final value.
The full source sequence remains blocked at `#DECL`; the next slice must
implement verified declaration semantics. No gameplay is claimed.
The [M2 source execution inventory](evidence/M2/SOURCE-EXECUTION.md) keeps
the integrated G3 gate at NOT RUN.
PR #43's first two native CI runs failed before reference capture because the
minimal Racket image lacked `compatibility-lib` for `racket/mpair`, then
`rackunit-lib` for the runtime's test submodule. The review
also found that a negative-test helper accepted its own assertion exception.
Both have follow-up fixes: the workflow installs both libraries, and a
failing-then-passing helper self-check makes wrong-type tests meaningful.
The dependency correction passed both workflows on `b4b2809`. After merging
the latest G1 path fix, local G2 validation reports 23 historical assertions,
570 Racket checks, 13 Python tests, and matching reference output; the
combined branch's [harness run 44571763597](https://github.com/quaat/mdl-racket/actions/runs/44571763597)
and [native run 44571763652](https://github.com/quaat/mdl-racket/actions/runs/44571763652)
also passed.

| Gate | State | Evidence / limitation |
|---|---|---|
| Source SHA verification | **PASS** | `make sources` verified both locked commits and clean upstream trees; see `artifacts/environment/sources.json` |
| Racket and Python tests | **PASS** | Plain `make test`: 26 Racket and 13 Python tests pass with pinned dependencies in ignored `.venv`; Makefile selects the venv and `/tmp`. Earlier failures on read-only `/var/tmp` and missing `pexpect` are recorded in the report. |
| December 1977 text reader sweep | **PASS for parsing** | `make check-source`: 36/36 selected UTF-8 MDL text files parsed, four non-text files classified separately; per-file offsets, hashes and counts in `docs/evidence/M0/reader-sweep.json` |
| Native Confusion build | **PASS** | `make reference-build` built `mdli` from pinned `mdlzork` without changing checkout |
| Opening scene plus five commands | **PASS** | `make reference-capture`: all prompts returned, no observed reference errors; maintainer approved `docs/evidence/M0/house-golden.json` in the Codex conversation on 2026-11-17 |
| Primitive reference probes | **PASS for reference only** | `make reference-probe`: 12/12 processes exited 0 with empty stderr; `docs/evidence/M0/primitives.json` |
| CI offline job | **PASS** | [Harness checks run 44125722477](https://github.com/quaat/mdl-racket/actions/runs/44125722477) completed successfully on PR #2 |
| CI native reference job | **PASS** | [Run 44125722256](https://github.com/quaat/mdl-racket/actions/runs/44125722256) verified 36 text files, built Confusion, captured five turns, and probed 12 cases. First run failed on missing `<cstdint>`; build-only flag fixed it. |
| Archive/reconstruction deltas | **PASS for inventory** | Explicit source and semantic differences are listed in `docs/PROVENANCE.md`, based on pinned `mdlzork_771212/README.md` |
| Candidate Racket gameplay / parity | **NOT IMPLEMENTED** | M0 compiler is demonstrative only |

**M0 gate: PASS.** The maintainer approved the exact golden fixture in the
Codex conversation on 2026-11-17; its SHA256 is
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
[GitHub issue #1](https://github.com/quaat/mdl-racket/issues/1) and merged
[PR #2](https://github.com/quaat/mdl-racket/pull/2) track M0. Both PR workflows
passed. **M1 is PASS on `main`; M2 is current.** This status does not claim Racket
game execution or runtime equivalence.

The M1 issue list and dependency graph are in `docs/PLAN.md`. Slice sections
below preserve each feature's status at its PR head; the final combined gate
result is at the end of this file.

See `docs/evidence/M0/REPORT.md` for exact commands, hashes, and limits.

## M1 issue #3: FALSE values (merged)

**Local slice checks: PASS. M1 milestone: NOT YET PASS.** The reader now groups
`#FALSE (items)` as one source-located node. The bootstrap compiler/runtime
represent FALSE separately from `NIL`, preserve literal payloads, and return
MDL values from `NOT`, `AND`, `OR`, `COND`, and supported predicates. `TYPE`
currently recognizes only FALSE and placeholder ATOM values. `make test`
passes 63 Racket checks and 13 Python tests; the source sweep parses 36/36
text files; reference capture matches the approved M0 golden except for its
timestamp. Thirteen focused Confusion processes exited zero with empty stderr.
M1 FALSE evidence and limitations are in `docs/evidence/M1/REPORT.md`; the
slice merged in [PR #10](https://github.com/quaat/mdl-racket/pull/10).

## M1 issue #4: atom identity and OBLIST (merged)

**Local slice checks: PASS. M1 milestone: NOT YET PASS.** Identity-bearing ATOM
and OBLIST values replace the symbol placeholder. Direct reader names and
`!-` trailers intern through an atom space; `ATOM`, `MOBLIST`, `LOOKUP`,
`INSERT`, `REMOVE`, `OBLIST?`, and `PNAME` have focused implementations.
`make test` passes 83 Racket checks and 13 Python tests; seven focused
Confusion processes exited zero with empty stderr. Dynamic `.OBLIST`,
associations, full OBLIST structure, and general binding semantics remain
unsupported. See `docs/evidence/M1/ATOMS.md` for commands and deviations.

## M1 issue #5: mutable sequences and shared views (merged)

**Local slice checks: PASS. M1 milestone: NOT YET PASS.** LIST values now use
mutable shared tails; VECTOR and UVECTOR values use shared storage views.
`REST`, `NTH`, `LENGTH`, `PUT`, `PUTREST`, and `UTYPE` have tested behavior on
the supported sequence types. Direct FALSE payloads and quoted structured
literals retain MDL atoms and mutable structure identity. `make test` passes
125 Racket checks and 13 Python tests. Ten successful Confusion probes exited
zero with empty stderr; one deliberate UVECTOR error case is recorded
separately. The five-turn capture matches the approved M0 golden except for
`captured_at`. See `docs/evidence/M1/SEQUENCES.md` for exact evidence and
limits. Type constructors, full bindings, and 36-bit arithmetic remain open.

## M1 issue #6: type tags and constructors (merged)

**Local slice checks: PASS. M1 milestone: NOT YET PASS.** `PRIMTYPE`,
`TYPEPRIM`, `NEWTYPE`, and structured `CHTYPE` now preserve user type tags
and shared LIST/VECTOR/UVECTOR storage. The implementation rejects mismatched
primitive types and unimplemented built-in and WORD conversions. Nine focused
Confusion cases exited zero with empty stderr; `make test` passes 152 Racket
checks and 13 Python tests. Source sweep remains 36/36 text files, and the
five-turn reference capture matches the approved golden except for timestamp.
See `docs/evidence/M1/TYPES.md` for commands, hashes, and limits. Local/global
binding semantics and 36-bit arithmetic remain open.

## M1 issue #7: local and global bindings (merged)

**Local slice checks: PASS. M1 milestone: NOT YET PASS.** Atom-keyed globals
and dynamic local frames replace the bootstrap string table and lexical-only
parameter lookup. `SET`, `SETG`, `LVAL`, `GVAL`, `VALUE`, and `GUNASSIGN` have
reference-backed behavior on the supported function subset. Nine focused
Confusion cases exited zero with empty stderr; three expected error probes
are preserved separately, including Confusion's missing `UNASSIGN` builtin.
`make test` passes 176 Racket checks and 13 Python tests. The approved house
golden still matches except for timestamp. See `docs/evidence/M1/BINDINGS.md`.
Optional/auxiliary arguments, explicit environments, and 36-bit arithmetic
remain open.

## M1 issue #8: 36-bit FIX and WORD operations (merged)

**Local slice checks: PASS for the documented subset. M1 milestone: NOT YET
PASS.** FIX input and arithmetic now enforce the manual's 36-bit signed
range; WORD values use a 36-bit mask. The slice implements octal and `#WORD`
literals, integer division, MOD, WORD casts, ANDB/ORB/XORB/EQVB, LSH,
BITS/GETBITS/PUTBITS, and type-sensitive numeric identity. `make test`
passes 262 Racket checks and 13 Python tests; the selected historical text
sweep still parses 36/36 files. Nine focused Confusion cases exit zero with
empty stderr, and two deliberate error cases are saved. The house capture
matches the approved golden except for timestamp. Confusion uses 64-bit
WORD output, allows FIX beyond the PDP-10 range, returns zero for `</>`,
and lacks ROT; the Racket target follows the historical manual on 36-bit
limits and `</>` and leaves ROT unsupported. See
`docs/evidence/M1/WORDS.md` for exact evidence and limits.

## M1 integrated gate on main

**PASS on `main` at merge commit
`a68cbb970b7028853fbcf7885c6c7c42f9470fe5`.**
The M1 gate in `docs/PLAN.md` requires independent Confusion-backed primitive
tests, property and mutation-aliasing tests, and explicit failure on
unsupported constructs. All five primitive slices have local and harness/
native CI PASS. The integrated audit adds three Confusion cases for equality
and evaluation order, nine Racket assertions, and three red-to-green strict
compiler checks. `make test` passes 274 Racket checks and 13 Python tests;
`make sources` verifies both pins; the current M1 sweep parses all 36 text
files. A fresh native build changes the binary hash and its embedded banner
timestamp. The five-turn reference capture matches the approved M0 golden
after excluding `captured_at`, `engine_sha256`, and that banner timestamp.
All 60 successful M1 probe results and six expected error observations match
their saved outputs on the rebuilt oracle. Details, exact commands, merge
SHAs, and limitations are in `docs/evidence/M1/GATE.md`. No Racket Zork
execution or gameplay parity is claimed.

## M2 issue #20: scoped PROG and bare RETURN

**Local slice: PASS. M2 milestone: NOT YET PASS.** Unnamed
`PROG` now creates an auxiliary local frame and returns its last body value;
bare `RETURN` exits the closest `PROG` within the current function. Initializers
run in order before their own new binding is installed, so they can read an
outer binding, while later initializers see earlier new bindings. An unassigned
auxiliary can be assigned with `SET`. Nested exits restore local frames, and a
bare `RETURN` in a called function cannot exit its caller's `PROG`.

`make test` passes 294 Racket checks and 13 Python tests. Nine focused pinned
Confusion cases exited zero with empty stderr; three expected error cases are
saved separately. Confusion crashes with signal 11 on `RETURN` in a PROG
auxiliary initializer; Racket follows the manual's activation-on-entry rule
for that case, and the deviation is recorded separately. `make check-source`
still parses 36/36 selected text files.
The five-turn reference capture and baseline probes pass, and the M1 golden
comparison passes with its documented build-metadata exclusions. Named
activations, explicit target `RETURN`, `REPEAT`, `AGAIN`, `GO`, `UNWIND`,
complex function formals, macros, and source loading remain unsupported.
Exact commands, hashes, and observations are in `docs/evidence/M2/PROG.md`.

## M2 issue #22: activation frames and function ownership

**Local hardening slice: PASS. M2 milestone: NOT YET PASS.** The unnamed PROG
subset now has an explicit dynamic stack of activation frames. Each frame
belongs to one function invocation and becomes invalid on normal completion,
RETURN, or an error. Bare RETURN resolves the nearest live frame belonging to
the current function; a called DEFINE cannot consume its caller's frame.
`make test` passes 308 Racket checks and 13 Python tests. Pinned source
verification and the 36/36 text reader sweep pass. A rebuilt Confusion
reproduces the nine saved successful M2 cases and three expected errors; the
five-turn capture, 12 baseline probes, and approved M1 comparison pass under
the documented build-metadata exclusions. Named/explicit activation targets
remain unsupported. Cyclic structural equality is tracked separately in
issue #23. See `docs/evidence/M2/ACTIVATIONS.md` for exact evidence and limits.

## M2 issue #23: cyclic structural equality boundary

**Local hardening slice: PASS. M2 milestone: NOT YET PASS.** `=?` now returns
true for the same cyclic object, false when two cycles differ before a repeated
comparison, and an explicit unsupported error when a pair of distinct
structured objects repeats on the active comparison path. Finite acyclic
values, including shared substructures, retain their structural result.
`==?` identity behavior is unchanged. `make test` passes 319 Racket checks
and 13 Python tests; source sweep remains 36/36 selected text files. Five
focused Confusion cases succeed, while one distinct LIST-cycle probe times out
at two seconds and one distinct VECTOR-cycle probe exits by signal 11. These
are recorded separately, not counted as passing oracle cases. The five-turn
capture, 12 baseline probes, and M1 approved comparison pass with documented
build-metadata exclusions. See `docs/evidence/M2/EQUALITY.md` for exact
commands, hashes, and unresolved semantics.

## M2 issue #26: unnamed REPEAT and bare AGAIN

**Local slice: PASS. M2 milestone: NOT YET PASS.** Unnamed REPEAT binds
auxiliaries once, repeats its body until RETURN, and shares the activation
stack with PROG. Bare AGAIN restarts the nearest PROG or REPEAT within the
current function without rebinding auxiliaries. Bare RETURN exits either.
Named activations and explicit target transfers remain unsupported and fail
at compile time. `make test` passes 331 Racket checks and 13
Python tests; the 36/36 selected historical text files still parse. Five
finite Confusion cases exited zero with empty stderr and match the Racket
assertions. The five-turn capture, 12 baseline probes, and approved M1
reference/golden comparison pass. See `docs/evidence/M2/REPEAT.md` for
commands, hashes, one transient `/var/tmp` test-runner failure, and remaining limits.

## M2 issue #28: named activations and explicit targets

**Local slice: PASS. M2 milestone: NOT YET PASS.** Named PROG/REPEAT now
bind an opaque ACTIVATION before their auxiliaries. Explicit RETURN/AGAIN
can target a live enclosing PROG/REPEAT, including across a called simple
DEFINE; bare transfers still obey current-function ownership. TYPE reports
ACTIVATION and PRIMTYPE reports FRAME. Wrong-type and stale targets fail
explicitly. `make test` passes 347 Racket checks and 13 Python tests; the
source sweep parses 36/36 selected text files. Eleven focused Confusion
processes exited zero with empty stderr. Six separate invalid-target,
duplicate-name, and unbound-LEGAL? observations include one signal-11 crash
and are not counted as successes. Native build, five-turn capture, 12 baseline
probes, and the approved M1 golden comparison pass locally. Function
activation formals, GO, UNWIND, and original game execution remain open.
See `docs/evidence/M2/ACTIVATION-TARGETS.md` for exact commands, hashes,
deviations, and remaining limits.

## M2 local task: OPTIONAL/AUX/TUPLE/ARGS function formals

**Local slice: PASS. M2 milestone: NOT YET PASS.** `DEFINE` now accepts
historical formal-list sections marked by strings: `"OPT"`/`"OPTIONAL"`,
`"AUX"`/`"EXTRA"`, `"ARGS"`, and `"TUPLE"`, in the reference order required
→ OPTIONAL → one ARGS/TUPLE rest binding → AUX. Defaults evaluate left to
right in the growing function frame; unsupplied optionals and bare AUX locals
stay unassigned; AUX restores outer locals on return. TUPLE binds remaining
arguments as a value with TYPE and PRIMTYPE `TUPLE` (its own primitive type;
`TYPEPRIM TUPLE` is `TUPLE`, `REST` keeps the TUPLE type); ARGS binds them as
a LIST. Arity failures use the historical `TOO-FEW/TOO-MANY-ARGUMENTS-SUPPLIED`
and `BAD-ARGUMENT-LIST` error names. An ATOM named AUX is an ordinary formal.
Malformed formal lists fail at compile time; Confusion validates them at call
time, a documented stricter deviation. The slice is tracked by
[issue #30](https://github.com/quaat/mdl-racket/issues/30) and
[PR #32](https://github.com/quaat/mdl-racket/pull/32); the full task record
is `docs/evidence/M2/FORMALS.md`.
`make test` passes 408 Racket checks and 13 Python tests (the sandboxed
session ran the Python half under system Python 3.9 with repo-local pinned
wheels; see the report). The Codex review of PR #32 found PUTREST splicing
TUPLE storage; both PUTREST operands are now validated through PRIMTYPE
and non-LIST-primtype values fail explicitly (fix commit `72ac750`). The 36/36 text reader sweep passes; the five-turn
capture, 12 baseline probes, the approved M1 golden comparison, and all 69
saved M2 success cases plus 20 expected-error observations reproduce exactly
against the pinned binary. Twenty-four focused Confusion formals probes
succeeded; eleven error observations are recorded separately.
`"NAME"`/`"ACT"`/`"BIND"`/`"CALL"` activation formals, quoted formals,
activation-name atoms before the formal list, GO, UNWIND, macros, and source
loading remain unsupported. See `docs/evidence/M2/FORMALS.md` for commands,
hashes, deviations, and remaining limits.

## M2 local task: activation formals, GO, and UNWIND

**Local slice: PASS. M2 milestone: NOT YET PASS.** `DEFINE` now accepts a
function activation name ATOM between the name and the formal list (the form
the 1977 reconstruction uses 14 times, e.g. `SEARCH-LIST SL`) plus the
`"NAME"`/`"ACT"` markers after any formal section. The activation exists
before formal binding, so RETURN during an AUX initializer exits the call;
explicit RETURN/AGAIN target it from any depth, unwinding intervening PROGs;
AGAIN re-runs the body without re-binding; bare transfers never target
function frames. `GO` follows the MDL manual chapter 10: top-level atoms in
PROG/REPEAT bodies are labels skipped in normal flow, and GO resumes at the
following expression in the nearest owned frame; the pinned Confusion has no
GO or TAG, a recorded reference deviation, and TAG values remain
unsupported. `UNWIND` runs its cleanup when a nonlocal transfer crosses
below it and returns the guarded expression's value otherwise. (This slice
originally also ran it on errors; issue #139 / ADR-0051 corrected that: a
raised error runs no cleanup, matching the manual and Confusion; see
[I139 evidence](evidence/M3/I139-UNWIND.md).) `make test` passes 465 Racket checks and 13
Python tests under the documented sandbox environment after both Codex
review fixes (PUTREST TUPLE rejection in PR #32 and octal-token label
exclusion here); the 36/36 reader
sweep passes; the five-turn capture, 12 baseline probes, the approved M1
golden comparison, and all 65 saved M2 success cases plus 27 expected-error
observations reproduce against the pinned binary. Sixteen focused Confusion
control probes succeeded; seven error observations are recorded separately.
`"BIND"`/`"CALL"` markers, TAG, the FSUBR `BIND`, and macros/source loading
remain unsupported. The slice is tracked by
[issue #31](https://github.com/quaat/mdl-racket/issues/31) and
[PR #33](https://github.com/quaat/mdl-racket/pull/33); the full task record
is `docs/evidence/M2/CONTROL.md` with commands, hashes, deviations, and
remaining limits.

## M2 local task: DEFMAC expansion and quoted formals

**Local slice: PASS. M2 milestone: NOT YET PASS.** The macro slice adds
`DEFMAC`, FORM construction and evaluation, one-step `EXPAND`, and quoted
formals in interpreted DEFINE and DEFMAC. Plain supplied arguments and
TUPLE rest arguments evaluate in the caller frame; ARGS keeps raw source
arguments. A macro expansion can define a callable function. Interpreted
function ownership prevents a bare RETURN from escaping the caller's PROG.
`make test` passes 513 Racket checks and 13 Python tests. The selected text
sweep still parses 36/36 files. Twenty-five pinned Confusion success cases
exit zero with empty stderr, and eight separate error observations match
their saved outputs. The five-turn house capture matches the approved M0
golden after the documented capture/build timestamp exclusions. Confusion's
caller-local expansion behavior differs from the manual's top-level wording;
Confusion also evaluates non-macro EXPAND input and prints a debug message,
while Racket keeps the form unchanged. Malformed formal-list error order
also differs. Full details and commands are in
[`docs/evidence/M2/MACROS.md`](evidence/M2/MACROS.md), tracked by
[issue #34](https://github.com/quaat/mdl-racket/issues/34).
Source loading, declarations, general APPLY/DISPATCH, and original game
execution remain open. The first unmet **milestone** gate is still M2.
The PR review follow-up fixes empty auxiliary LISTs in interpreted
PROG/REPEAT and keeps a leading activation name separate from quoted
formals in directly compiled and generated definitions. Ten new pinned
Confusion cases match the Racket regressions; the red-to-green record is in
[`docs/evidence/M2/MACROS.md`](evidence/M2/MACROS.md#review-follow-up).

## M2 infrastructure task: faster CI Racket setup

**CI task: PASS. M2 milestone: NOT YET PASS.** Both workflows passed on the
digest-pinned minimal Racket `8.10-bc` container: [harness run
44353286644](https://github.com/quaat/mdl-racket/actions/runs/44353286644)
and [native run
44353286715](https://github.com/quaat/mdl-racket/actions/runs/44353286715).
The harness log spans about 32 seconds and the native log about 43 seconds,
including image pull, dependencies, and cleanup. The same-day apt baselines
were 40 seconds for the harness and 84 seconds for one native run; a later
native apt run took about 17 minutes due to its dependency install. These
are individual runs, not a controlled benchmark. The full comparison,
commands, and limitations are in
[`docs/evidence/M2/CI-SETUP.md`](evidence/M2/CI-SETUP.md), tracked by
[issue #36](https://github.com/quaat/mdl-racket/issues/36) and
[PR #37](https://github.com/quaat/mdl-racket/pull/37). No MDL semantics or
upstream source changed. Source loading and original game execution remain
the next M2 work.

## M2 issue #44: `#DECL` local declarations

**Local slice: PASS. M2 milestone: NOT YET PASS.** The declaration slice
implements chapter-14 `#DECL` for `DEFINE`, `DEFMAC`, `PROG`, and `REPEAT`
in both compiled and interpreted paths: bound formals, OPTIONAL/AUX
initializers, later `SET`s, and normal or explicit results are checked
against `ANY`, registered type atoms, `<OR ...>`, and `<PRIMTYPE type>`
patterns, with strict explicit rejection of everything else. `DECL?`,
`GASSIGNED?`, and `MANIFEST` are added; `SETG` refuses to change an assigned
manifest except to an `==?`-identical value or when `.REDEFINE` is true.
The reader accepts the doubled `#DECL #DECL` form that the original
`77act1.mud:110` requires (Confusion's generic `#`-typecode reading makes
it a re-typing no-op). The unmodified original `MSETG` now installs and
executes (`<MSETG M2-D1-TEMP 3>` returns `T`, leaving the global at `3`);
the `77loadall.mud` load advances past the `#DECL` barrier and stops
explicitly at the next construct, the `!`-splice in the original `PSETG`
(`81prim.mud:16:46`). `make test` passes 620 Racket checks and 13 Python
tests; the selected text sweep still parses 36/36 files. Thirteen pinned
Confusion observations back the semantics: eleven success cases exit zero
and the two deliberate `MSETG` error cases match their saved outputs.
Pinned Confusion does not enforce attached declarations; this slice
follows the manual instead and records that deviation. Full details,
commands, and hashes are in
[`docs/evidence/M2/DECLARATIONS.md`](evidence/M2/DECLARATIONS.md), tracked
by [issue #44](https://github.com/quaat/mdl-racket/issues/44). The
session recovery record is in
[`docs/evidence/M2/SESSION-RECOVERY-2026-11-19.md`](evidence/M2/SESSION-RECOVERY-2026-11-19.md).
General APPLY/DISPATCH and original game execution remain open. The
first unmet **milestone** gate is still M2.

## M2 issue #51: the interpreter-supplied MUDDLE global

**Local slice: PASS. M2 milestone: NOT YET PASS.** The interpreter bound
its version number as a startup global; the pinned reference binds
`MUDDLE` to the FIX `101`, and every fresh shared-session loader session
now seeds it identically (interned in that session's atom space). With
that value the `77defs.mud:1` guard `<L? ,MUDDLE 100>` is FALSE, the
`<AND ...>` short-circuits, and `USE` — unbound in the reference — stays
an explicit error. The pinned `77loadall.mud` chain completes **twelve**
expressions (up from ten) and now stops at `77defs.mud` expression 3:
`<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>` fails on the missing
atom-property `PUT` — the next source dependency. The reference itself
loads the entire chain to `DONE` (recorded in the D4 reference evidence),
which is the concrete parity target for the remaining M2 work. `make
test` passes 802 Racket checks and 13 Python tests. Full details,
commands, and hashes are in
[`docs/evidence/M2/MUDDLE.md`](evidence/M2/MUDDLE.md), tracked by
[issue #51](https://github.com/quaat/mdl-racket/issues/51). Atom-property
`PUT`, the `MEMQ` primitive, general APPLY/DISPATCH, and original game
execution remain open. The first unmet **milestone** gate is still M2.

## M2 issue #48: structured declaration patterns

**Local slice: PASS. M2 milestone: NOT YET PASS.** The structured
declaration slice implements chapter-14 `<struc [REST ...]>` patterns for
LIST, VECTOR, UVECTOR, and TUPLE: required element prefixes apply
positionally, the trailing `[REST pat ...]` repetition matches zero or
more remaining elements (cyclically for multi-pattern repetitions), and
nested `<OR ...>` works inside structures. `DECL?` gains the reference's
payload distinction (overall-type mismatch returns bare `#FALSE ()`; an
element mismatch carries the offending element and the leaf pattern).
Traversal is bounded (explicit depth limit 200; cyclic chains surface the
reader's explicit cyclic error) and checked values are never copied or
mutated. The unmodified original `PSETG` now installs with its
`<LIST [REST ATOM]>` declaration; **the pinned `81prim.mud` loads in
full** (all eight expressions), the `77loadall.mud` chain completes ten
expressions, and the load now stops at the unassigned global `MUDDLE` in
`77defs.mud` — the historical interpreter-version global and the next
source dependency, alongside the `MEMQ` primitive `PSETG` invokes.
`make test` passes 785 Racket checks and 13 Python tests. Twenty-two
pinned Confusion success cases and fourteen deliberate-error observations
back the semantics, regenerated byte-identically before commit; the
deviations (empty `<struc>` rejected per the manual BNF, strict `DECL?`
arity, structured heads restricted to the four types) are recorded in
`docs/SEMANTICS.md`. Full details, commands, and hashes are in
[`docs/evidence/M2/DECLARATION-PATTERNS.md`](evidence/M2/DECLARATION-PATTERNS.md),
tracked by [issue #48](https://github.com/quaat/mdl-racket/issues/48).
The `MUDDLE` global, the `MEMQ` primitive, general APPLY/DISPATCH, and
original game execution remain open. The first unmet **milestone** gate
is still M2.

## M2 issue #46: SEGMENT (`!` splice) evaluation

**Local slice: PASS. M2 milestone: NOT YET PASS.** The SEGMENT slice
implements chapter-7 `!` notation: `!.ATOM`/`!,ATOM`/`!<FORM...>` segments
splice their value's elements into LIST, VECTOR, UVECTOR, and
FORM-argument construction in strict left-to-right order; a final
LIST-valued segment shares the payload's tail (PUT mutation visible through
both names), non-final segments and array constructions copy; STRING
segments splice as CHARACTER values; quoted structures keep segments as
unevaluated data; standalone and non-structured segment results raise the
reference's ILLEGAL-SEGMENT, and non-uniform UVECTOR construction raises
TYPES-DIFFER-IN-UNIFORM-VECTOR. The original `PSETG` splice now compiles:
the pinned `77loadall.mud` load advances to **three completed expressions**
and stops at the next actual dependency, `PSETG`'s compound
`<LIST [REST ATOM]>` declaration pattern at runtime stage (issue #48).
`make test` passes 701 Racket checks and 13 Python tests; the selected text
sweep still parses 36/36 files. Eighteen pinned Confusion success cases and
ten deliberate-error observations back the semantics, regenerated
byte-identically before commit; the deviations (interpreted call-argument
splicing follows the manual over the reference's interpreted path;
eager interpreted segment-payload evaluation) are recorded in
`docs/SEMANTICS.md`. Full details, commands, and hashes are in
[`docs/evidence/M2/SEGMENTS.md`](evidence/M2/SEGMENTS.md), tracked by
[issue #46](https://github.com/quaat/mdl-racket/issues/46). At this
slice's close the structured declaration patterns (issue #48, recorded
above) were the next dependency; general APPLY/DISPATCH and original game
execution remained open.

## M2 issue #53: atom-property PUT/GET associations (D5)

**Local slice: PASS (branch `feat/m2-atom-props`). M2 milestone: NOT YET
PASS.** The D5 slice implements MDL association space: `PUT` and `GET`
dispatch exactly as the pinned reference classifies (structured item +
FIX indicator is the element store; every other combination — including
FIX indicators on non-structured items — is an association;
two-argument PUT removes and echoes the item; one-argument PUT is
TOO-FEW-ARGUMENTS-SUPPLIED; three-argument GET on a structure errors).
Associations match by `==?` identity via `mdl-identical?` on both item
and indicator in a session-owned entry list — fresh sessions start
property-free. A weak `eq?` table failed review regressions for WORDs and
array REST views; the corrected store retains keys until removal or session
end, a documented GC-lifetime deviation. `DECL?` consults an atom's `DECL` association through
the existing D1/D3 matcher and carries the resolved leaf in the `#FALSE`
payload; `SETG` deliberately does not enforce it. `GETPROP`/`PUTPROP`
and chapter 13.4 machinery remain explicit unimplemented failures.
The historical `77defs.mud` expression 3
`<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>` now executes; the pinned
load advances from twelve to **twenty-four completed expressions** and
stops at `77defs.mud` expression 15 (`EMPTY?` inside the original
`NEWSTRUC`). `make test` passes 864 Racket checks and 13 Python tests.
Eighteen initial and eleven review-derived pinned Confusion success cases,
plus six initial deliberate errors, one review-derived error and one bounded
alias-cycle timeout back the semantics; the two manual-vs-reference conflicts
(removal returns the item, not the previous value; augmented `#FALSE
(leaf)` DECL? misses) are adjudicated toward the reference in
[`docs/evidence/M2/ATOM-PROPS.md`](evidence/M2/ATOM-PROPS.md) and ADR-0023.
Full details in `docs/SEMANTICS.md` (M2 D5 section). The integrated G3
gate and original game execution remain open.
