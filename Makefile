SHELL := /bin/bash
.PHONY: doctor sources install test test-racket test-python test-historical test-m2-g3 test-m3-andq test-m3-historical-gc test-m3-start-back test-m3-saveit test-m3-interactive test-m3-clock-seed test-m3-session test-m3-launcher test-m4-house-cellar test-m4-mailbox-drop test-m4-orphan-prompt test-m4-top-parser test-m4-sword-glow test-m4-troll-combat test-m4-parser-ambiguity test-m4-replay-persistence test-m4-cyclops-room test-m4-mirror-bat test-m4-strange-passage test-m4-help-info test-m4-grue-resurrection test-m4-grue-refusal test-m4-troll-death test-m4-treasure-deposit test-m4-thief-robbery test-m4-cure-recovery test-m4-lamp-burnout test-m4-match-clock test-m4-boat-river test-m4-dam-sluice test-m4-maint-leak test-m4-coal-machine test-m4-gas-room test-m4-balloon-ledge test-m4-thief-fight m4-decl-sweep m4-scenarios-per-prefix m4-check m4-accept play m2-check m3-source-progress check-source reference-build reference-capture reference-probe compare reference-capture-boot test-boot-reference m3-check m3-native-parity test-m3-bang

PYTHON ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)
RACKET ?= racket
export TMPDIR ?= /tmp

doctor:
	@$(PYTHON) scripts/doctor.py

sources:
	@$(PYTHON) scripts/fetch_sources.py

install:
	@$(PYTHON) -m pip install -r requirements.txt
	@raco pkg install --auto --link || (echo 'If package is already linked, this may be harmless; inspect raco pkg show.'; exit 1)

test: test-racket test-python

test-racket:
	@bash scripts/test_racket.sh

test-python:
	@$(PYTHON) -m pytest -q tests/test_harness.py tests/test_fetch_sources.py tests/test_reference_pty.py tests/test_probe.py tests/test_m3_source_progress.py tests/test_boot_reference.py tests/test_smoke_parity.py tests/test_sweep_operator_heads.py tests/test_m4_check.py tests/test_reference_corpus.py

test-historical: sources
	@racket tests/historical_vfload_test.rkt
	@racket tests/historical_decl_test.rkt
	@racket tests/historical_computed_global_test.rkt
	@racket tests/historical_error_test.rkt
	@racket tests/historical_memq_test.rkt
	@racket tests/historical_oblist_placement_test.rkt
	@racket tests/historical_channel_start_test.rkt
	@MDL_PINNED_SOURCES=1 raco test tests/file_read_test.rkt

test-m2-g3: sources
	@racket tests/historical_g3_test.rkt

test-m3-andq: sources
	@racket tests/historical_andq_test.rkt

test-m3-historical-gc: sources
	@raco test tests/historical_gc_handler_test.rkt

test-m3-start-back: sources
	@raco test tests/historical_start_back_test.rkt

test-m3-saveit: sources
	@raco test tests/historical_saveit_test.rkt

# S7 (ADR-0050): faithful run.mud path played with the six house-boot
# commands through the host top-level loop on the golden's fixed session
# clock (ADR-0052); compared exactly with the approved CANDIDATE golden.
# INITIALIZED/INTERACTIVE evidence, not a SMOKE_PARITY claim.
test-m3-interactive: sources
	@raco test tests/historical_interactive_test.rkt

# S11 (ADR-0054, ADR-0055): a complete local session through the game's own
# FINISH -> RECORD -> QUIT (OPEN denied, no file written), compared with the
# pinned Confusion pipe captures; EOF at the quit prompt, unknown words, and an
# unsupported host operation that must stay a strict failure.
test-m3-session: sources
	@raco test tests/historical_session_quit_test.rkt

# M4 native-parity scenarios (the twenty-five test-m4-* targets below except
# replay-persistence) run through the shared runner tests/m4_scenario_runner.rkt
# (docs/TESTING.md, "M4 scenario runner"). Default single-run mode: one boot
# fed all commands, every turn's output and read-only checkpoints compared at
# READSTRING entry with the pinned Confusion captures (D1 only), the whole
# transcript and end-of-input state compared exactly, and the prefixes whose
# native end-of-input tail is not standard re-run per prefix. On failure a
# report is written to artifacts/scenario-divergence/<name>-<mode>.json.
# `make m4-scenarios-per-prefix` runs all of them in the per-prefix reboot mode.
#
# M4 scenario 1 (enter the house and open the cellar): every turn compared
# with the pinned Confusion captures (D1 only) plus read-only state
# checkpoints; then the known strict frontier next to it (not parity).
test-m4-house-cellar: sources
	@racket tests/historical_house_cellar_test.rkt
	@racket tests/historical_m4_frontier_test.rkt

# M4 S2 (drop the leaflet; frontier F1, CHTYPE to SEGMENT): every command
# turn compared with the pinned Confusion captures (D1 only) plus read-only
# state checkpoints, and the game's INSERT-OBJECT/TAKE-OBJECT tail sharing.
test-m4-mailbox-drop: sources
	@racket tests/historical_mailbox_drop_test.rkt

# M4 S3 (orphan prompts; frontier F2/F2b, CHTYPE FIX -> CHARACTER in FOOSTR):
# every turn compared with the pinned Confusion captures (D1 only)
# plus read-only state checkpoints (ORPHANS, SCRSTR), and the game's own
# PRSTR/FOOSTR after FLOAD.
test-m4-orphan-prompt: sources
	@racket tests/historical_orphan_prompt_test.rkt

# M4 S4 (the TOP SUBR; SPARSE 77np.mud:126 and EVERYTHING 77rooms.mud:1283):
# every turn compared with the pinned Confusion captures (D1 only)
# plus read-only state checkpoints (PRSVEC, PREPVEC, OBJ-UV storage), and the
# game's TOP operands after FLOAD.
test-m4-top-parser: sources
	@racket tests/historical_top_parser_test.rkt

# M4 S5b (TYPE of applicable values; frontier F4, SWORD 77act1.mud:1903
# <TYPE? ,SWORD-GLOW NOFFSET>): take the sword and carry it to the troll room;
# every turn compared with the pinned Confusion captures (D1 only)
# plus read-only state checkpoints (sword glow level, SWORD-DEMON HACTION),
# and the game's applicables typed after FLOAD.
test-m4-sword-glow: sources
	@racket tests/historical_sword_glow_test.rkt

# M4 S6 (troll combat): the sword-glow path, then `kill troll with sword` until
# the troll dies (KILLER 77act1.mud:1699, BLOW 78melee.mud:377, the FIGHTING
# demon 78melee.mud:282, TROLL 77act1.mud:360), then diagnose/score/inventory/
# look/take axe/east; every turn compared with the pinned Confusion
# captures (D1 only) plus read-only state checkpoints (troll strength and
# flags, axe location, hero strength, cure clock, glow level).
test-m4-troll-combat: sources
	@racket tests/historical_troll_combat_test.rkt

# M4 S7 (parser rejection and ambiguity): unknown words, 5-letter truncation,
# empty and blank lines, buzz words, orphan continuations, dangling adjective,
# too many objects, double preposition, quoting, the 10-word LEXV, darkness,
# and `Which door?` (GET-OBJECT 77np.mud:363 -> SPARSE 77np.mud:88) answered
# by an adjective; every turn compared with the pinned Confusion
# captures (D1 only) plus read-only state checkpoints (LEXV, PRSVEC,
# PARSE-WON, ORPHANS, trap door, MOVES).
test-m4-parser-ambiguity: sources
	@racket tests/historical_parser_ambiguity_test.rkt

# M4 WP4 (ADR-0061): host persistence by deterministic replay. The troll-combat
# scenario on a recording clock (fixed source 250776000 UTC): checkpoints at the
# RDCOM prompt, restore in-process and in a fresh process, verification (both
# RNG words, MOVES, state and transcript digests), continuation equal to the
# native transcript, tampering, independence and replay cost. The checkpoint
# format and clock modes also run in `make test` (replay_*_test.rkt).
test-m4-replay-persistence: sources
	@racket tests/persistence_replay_test.rkt
	@racket tests/replay_sleep_time_test.rkt
	@racket tests/help_info_replay_test.rkt

# M4 S8 (the cyclops and ABS, issue #167): lunch and water from the kitchen,
# the troll-combat path, the maze into the Cyclops Room (FIGHTING's FIRST?
# call evaluates <ABS .COUNT>, 77act1.mud:951), then feed, water, wake
# (<ABS <RVARS .RM>>, :949) and flee the cyclops; every turn
# compared with the pinned Confusion captures (D1 only) plus read-only state
# checkpoints (cyclops flags and RVARS, food/water, OPPV, scores, MOVES) and
# the RANDOM draws.
test-m4-cyclops-room: sources
	@racket tests/historical_cyclops_room_test.rkt

# M4 S9 (IMAGE and SLEEP, issues #168/#169): the troll-combat path, the round
# room, `rub mirror`, then the Bat Room: FWEEP's <IMAGE 7> and <SLEEP 1>
# (77act2.mud:57-58) three times, then the bat's RANDOM drop; every
# turn compared with the pinned Confusion captures (D1 only; the three BEL
# bytes included) plus read-only state checkpoints; the fixed (non-live) clock
# must never call the host sleeper.
test-m4-mirror-bat: sources
	@racket tests/historical_mirror_bat_test.rkt

# M4 S9 (TIME, issue #170): the maze into the Cyclops Room, `odysseus`, `north`
# into the Strange Passage (room action TIME), `c-int` (verb function TIME),
# the living room; every turn compared with the pinned Confusion
# captures (D1 only) plus read-only state checkpoints.
test-m4-strange-passage: sources
	@racket tests/historical_strange_passage_test.rkt

# M4 S10 (help and info, issue #171; ADR-0055 amendment "Read-only
# allowlist"): `help`, `info` and `?` print MDL/MADADV.HELP / .INFO through
# FILE-TO-TTY (OPEN "READ" of the two pinned, hash-checked files, FILE-LENGTH,
# file READSTRING, CLOSE); every turn compared with the pinned Confusion
# captures (D1 only; prompts split at line-initial `>`) plus read-only state
# checkpoints including ,INBUF.
test-m4-help-info: sources
	@racket tests/historical_help_info_test.rkt

# M4 Phase 2 death and recovery (epic #163; ADR-0062 amendment: YES/NO entry
# prompts and declared QUIT endings). grue-resurrection (discovery run F12,
# extended): death by grue in the dark attic, `y`, resurrection in the forest,
# the sword, bottle, sack and lamp scattered over RANDOM-LIST; prefix 11 quits.
# grue-refusal (F13): death, `n`, FINISH -> RECORD (both OPENs denied,
# ADR-0055; natively writes MDL/ZORK.LOG) -> QUIT, `look` unread. troll-death:
# unarmed in the troll room, staggered, wounded and killed by the troll, `y`.
# Every turn compared with the pinned Confusion captures (D1 only) plus
# read-only state checkpoints (DEATHS, HERE, scores, possessions' rooms, lamp,
# hero strength/stagger, cure clock, troll, INBUF).
test-m4-grue-resurrection: sources
	@racket tests/historical_grue_resurrection_test.rkt

test-m4-grue-refusal: sources
	@racket tests/historical_grue_refusal_test.rkt

test-m4-troll-death: sources
	@racket tests/historical_troll_death_test.rkt

# M4 Phase 3 timers, objects and scoring (epic #163), the "timers" checkpoint
# profile of scripts/probe_death_scenario_reference.py (lamp and clock events,
# painting, trophy case, thief). treasure-deposit: the painting from the
# Gallery up the chimney into the trophy case (ASCORE 46). thief-robbery: the
# same route one turn earlier, the thief takes the painting from the hero
# (observed under the fixed seed, not chased). cure-recovery: wounded by the
# troll, back to the cellar, the CURE clock heals the wound. lamp-burnout: 118
# `wait`s in the living room, the lamp's LIGHT-INT warnings and burn-out.
test-m4-treasure-deposit: sources
	@racket tests/historical_treasure_deposit_test.rkt

test-m4-thief-robbery: sources
	@racket tests/historical_thief_robbery_test.rkt

test-m4-cure-recovery: sources
	@racket tests/historical_cure_recovery_test.rkt

test-m4-lamp-burnout: sources
	@racket tests/historical_lamp_burnout_test.rkt

# M4 Phase 3b (epic #163): beyond the house, the "dam" and "boat" checkpoint
# profiles of scripts/probe_death_scenario_reference.py (dam flags, the
# Maintenance Room, the leak and match clocks; the boats and the pump).
# match-clock: the matchbook in the Dam Lobby, the clock event MATIN lit four
# times (gone out at a tick, at a `wait`, turned off, out of matches).
# boat-river: the pump from Reservoir North (by the Atlantis Room), down the
# slide, the boat at the Dam Base inflated, boarded, launched onto the river,
# landed, deflated.
test-m4-match-clock: sources
	@racket tests/historical_match_clock_test.rkt

test-m4-boat-river: sources
	@racket tests/historical_boat_river_test.rkt

# M4 S14 (issue #193, INV-11 fixed; the #98 ADR amendment: an attached
# declaration's TYPE name still undefined when checked is not enforced, as in
# pinned Confusion). Both routes enter the Maintenance Room (MAINT-ROOM's
# #DECL names the undefined type PRSOBJ). dam-sluice: the wrench, the bolt
# refused, the yellow button, the sluice gates opened, the trunk from the
# drained reservoir. maint-leak: the blue button's leak, the clock event
# MNTIN (CTICK -1) raising the water level, plugged with the putty.
test-m4-dam-sluice: sources
	@racket tests/historical_dam_sluice_test.rkt

test-m4-maint-leak: sources
	@racket tests/historical_maint_leak_test.rkt

# M4 Phase 3c (epic #163): the puzzles beyond the house, the "puzzles"
# checkpoint profile of scripts/probe_death_scenario_reference.py (the
# balloon, the coal-mine basket and machine, the candles, the gas room).
# coal-machine: the screwdriver and the drained reservoir, the candles from
# the Altar, the coal through the mine, the basket lowered with the coal, the
# screwdriver and the burning candles, the empty-handed passage, the machine
# turning the coal into a diamond, the basket raised. gas-room: the Gas Room
# entered with the lamp only (nothing happens) and with the burning candles
# (the explosion; patched). balloon-ledge (gated since M4 #196, INV-12
# resolved: attached #DECLs are not enforced, the attached-declaration ADR
# amendment): the guidebook burned in the receptacle, the balloon risen to the
# Narrow Ledge, the wire tied to the hook and untied, the balloon landed again
# (BALLOON's attached #DECL (PRSO) <OR OBJECT DIRECTION> meets the #FALSE ()
# CLOCK-DEMON leaves in PRSVEC, unchecked natively and now here too). It
# replaces the retired xfail-m4-balloon-frontier.
test-m4-coal-machine: sources
	@racket tests/historical_coal_machine_test.rkt

test-m4-gas-room: sources
	@racket tests/historical_gas_room_test.rkt

test-m4-balloon-ledge: sources
	@racket tests/historical_balloon_ledge_test.rkt

# M4 combat.thief (epic #163): the "thief" checkpoint profile of
# scripts/probe_death_scenario_reference.py (the timers fields plus the
# thief's strength and fight bits, the stiletto, the chalice, HACTION).
# thief-fight: strange-passage's way to the Cyclops Room and `odysseus`, `up`
# into the Treasure Room (TREASURE-ROOM brings the thief, who attacks at
# once), two `kill thief with sword`: the thief is wounded twice, then knocks
# the hero out and kills him; patched in the forest.
test-m4-thief-fight: sources
	@racket tests/historical_thief_fight_test.rkt

# M4 #196 (maintainer decision 2026-11-26, "sweep first"): DIAGNOSTIC ONLY,
# not part of `make test`, `make m4-check` or any scenario target. Runs every
# gated M4 scenario (balloon-ledge included since #196) and the targeted
# probes of tests/decl_sweep_probes.json with the host-only, test-only
# decl-violation recorder on (attached #DECL violations are recorded and the
# run proceeds), and again without it (production: since the #196 amendment no
# attached #DECL is enforced), and writes docs/evidence/M4/decl-violation-sweep.json
# (unit results and logs in artifacts/decl-sweep/). See docs/TESTING.md and
# docs/evidence/M4/DECL-VIOLATION-SWEEP.md. Options:
# M4_DECL_SWEEP_ARGS="--units a,b --reuse --out P --work D".
m4-decl-sweep: sources
	@racket tests/decl_violation_sweep.rkt $(M4_DECL_SWEEP_ARGS)

# The twenty-six M4 native-parity scenarios in the per-prefix reboot mode (one boot
# per command prefix; the pre-runner protocol, slower). Not on CI's default
# path; the equivalence evidence is docs/evidence/M4/SINGLE-RUN-RUNNER.md.
M4_SCENARIO_TESTS := tests/historical_house_cellar_test.rkt \
	tests/historical_mailbox_drop_test.rkt tests/historical_orphan_prompt_test.rkt \
	tests/historical_top_parser_test.rkt tests/historical_sword_glow_test.rkt \
	tests/historical_troll_combat_test.rkt tests/historical_parser_ambiguity_test.rkt \
	tests/historical_cyclops_room_test.rkt tests/historical_mirror_bat_test.rkt \
	tests/historical_strange_passage_test.rkt tests/historical_help_info_test.rkt \
	tests/historical_grue_resurrection_test.rkt tests/historical_grue_refusal_test.rkt \
	tests/historical_troll_death_test.rkt tests/historical_treasure_deposit_test.rkt \
	tests/historical_thief_robbery_test.rkt tests/historical_cure_recovery_test.rkt \
	tests/historical_lamp_burnout_test.rkt tests/historical_match_clock_test.rkt \
	tests/historical_boat_river_test.rkt tests/historical_dam_sluice_test.rkt \
	tests/historical_maint_leak_test.rkt tests/historical_coal_machine_test.rkt \
	tests/historical_gas_room_test.rkt tests/historical_balloon_ledge_test.rkt \
	tests/historical_thief_fight_test.rkt
m4-scenarios-per-prefix: sources
	@for t in $(M4_SCENARIO_TESTS); do \
	  echo "== M4_SCENARIO_MODE=per-prefix racket $$t"; \
	  M4_SCENARIO_MODE=per-prefix racket $$t || exit 1; \
	done

# M4 acceptance-term report (epic #163 Phase 7; scripts/m4_check.py). Runs
# every check declared in tests/scenarios/m4-manifest.json, sequentially:
# `make sources`, the twenty-five M4 scenario targets (SCENARIO_PARITY), the WP4
# persistence check and the PLAYABLE evidence sub-checks, then reports the five
# terms SCENARIO_PARITY, GAMEPLAY_RELIABILITY (branches declared in
# docs/evidence/M4/gameplay-branches.json), PLAYABLE, FULL_COMPLETION and
# M4_ACCEPTED separately. Exit 0 when nothing FAILs (NOT RUN / NOT YET allowed),
# 1 on any FAIL; pass M4_CHECK_ARGS="--require-accepted" to exit 3 unless
# M4_ACCEPTED is PASS, "--scenarios-only" for the scenario part only, or
# "--per-prefix" to add `make m4-scenarios-per-prefix`. Report:
# artifacts/m4-check/m4-check.json; logs: artifacts/m4-check/logs/.
m4-check:
	@$(PYTHON) scripts/m4_check.py $(M4_CHECK_ARGS)

# The final M4 milestone-acceptance gate (ADR-0063 amendment, 2026-11-26): the
# same declared checks plus the per-prefix protocol, with --require-accepted,
# so it exits 3 unless M4_ACCEPTED is PASS (all four technical terms PASS and
# the maintainer's committed R5 record exists with its required fields). It is
# not an ordinary PR gate; `make m4-check` (exit 0 = no executed check failed)
# is. Report: artifacts/m4-accept/m4-check.json.
m4-accept:
	@$(PYTHON) scripts/m4_check.py --require-accepted --per-prefix \
		--report artifacts/m4-accept/m4-check.json $(M4_CHECK_ARGS)

# S12 (WP4): the local launcher zork/main.rkt (run-zork) and its command line
# zork/cli.rkt: the S11 house-quit transcript through run-zork, EOF, notice,
# fresh state per run, missing sources, CLI exit codes, break propagation.
test-m3-launcher: sources
	@raco test tests/launcher_test.rkt

# Play the unchanged 1977 Zork locally on this terminal (real clock, local
# zone). Exit codes are documented in zork/cli.rkt and README "Play locally".
play: sources
	@$(RACKET) zork/cli.rkt

# S13 part A (ADR-0050 §3 amended): the `!` escape in terminal input read by
# the game's own RDCOM (`nor!th` behaves like `north`), compared with the
# pinned Confusion game cases in docs/evidence/M3/readstring-bang-probe.json.
test-m3-bang: sources
	@raco test tests/historical_bang_input_test.rkt

# Issue #135 part 1 (ADR-0052): fixed session clock -> DSKDATE -> START's
# RANDOM seed -> RANDOM state, observed host-only.
test-m3-clock-seed: sources
	@raco test tests/historical_clock_seed_test.rkt

# M3 SMOKE_PARITY technical check (S10, ADR-0053). Stages, in order, each with
# PASS/FAIL/NOT RUN: sources, test-m3-saveit, test-m3-clock-seed,
# test-m3-interactive, comparator unit tests, this runtime's run vs the
# committed Confusion record through the single strict comparator (no native
# binary needed), and the optional fresh native capture (NOT RUN without
# mdli/gcc; M3_NATIVE=require makes that a failure). Nonzero exit on any FAIL;
# report in artifacts/m3/m3-check.json, logs in artifacts/m3/logs/.
m3-check:
	@$(PYTHON) scripts/m3_check.py

# Native part only (after `make reference-build`): our candidate run plus a
# fresh capture of pinned Confusion in a disposable copy, both compared strictly.
m3-native-parity:
	@$(PYTHON) scripts/m3_check.py --native require \
		--stages candidate-vs-committed-reference,native-fresh-capture-parity \
		--report artifacts/m3/m3-native-parity.json

# Complete local M2 technical check. Build the native reference once with
# `make reference-build` before using this target. Milestone acceptance also
# requires review, authorized integration, and verification on main.
m2-check:
	@$(MAKE) doctor
	@$(MAKE) sources
	@MDL_SWEEP_OUTPUT=artifacts/m2/reader-sweep.json $(MAKE) check-source
	@$(MAKE) test
	@$(MAKE) test-historical
	@$(MAKE) test-m2-g3
	@$(MAKE) reference-probe
	@$(MAKE) reference-capture
	@git diff --check

# A valid incomplete load is progress evidence, not a successful game boot.
# The validator rejects regressions, skips, malformed reports and false DONE.
m3-source-progress: sources
	@MDL_SWEEP_OUTPUT=artifacts/m3/reader-sweep.json $(MAKE) check-source
	@$(MAKE) test-m2-g3
	@$(MAKE) test-m3-andq
	@$(PYTHON) scripts/m3_source_progress.py

check-source:
	@if raco help make >/dev/null 2>&1; then raco make scripts/mdl_check.rkt; fi
	@$(PYTHON) scripts/check_1977_sources.py

reference-build: sources
	@bash scripts/build_confusion.sh

reference-capture:
	@$(PYTHON) scripts/reference_runner.py capture --scenario tests/scenarios/house.json --output artifacts/reference/house.json

# Fresh-boot scenario capture (BOOT-REF). Requires the native mdli binary and gcc.
# The wall-clock LD_PRELOAD shim is compiled per capture into a temp dir; the
# child runs with TZ=UTC and MDL_FIXED_EPOCH from tests/scenarios/house-boot.json.
# Output is a CANDIDATE — compare its gameplay view, not the whole JSON.
reference-capture-boot:
	@$(PYTHON) scripts/boot_reference.py capture \
		--scenario tests/scenarios/house-boot.json \
		--output artifacts/reference/house-boot.json

# Opt-in native BOOT-REF gate (not part of `make test`): regenerate the capture,
# compare its gameplay view with the committed (promoted schema-3) reference,
# then run the native pytest tests (two more captures; determinism + equality).
test-boot-reference: reference-capture-boot
	@$(PYTHON) scripts/boot_reference.py compare \
		docs/evidence/M3/house-boot-reference.json artifacts/reference/house-boot.json
	@$(PYTHON) -m pytest -q -m native tests/test_boot_reference.py

compare:
	@test -n "$(CANDIDATE)" || (echo 'Usage: make compare CANDIDATE=artifacts/candidate/house.json' >&2; exit 2)
	@$(PYTHON) scripts/compare_transcripts.py artifacts/reference/house.json "$(CANDIDATE)"

reference-probe:
	@$(PYTHON) -m scripts.mdl_probe --cases tests/scenarios/primitives.json --output artifacts/reference/primitives.json
