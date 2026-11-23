SHELL := /bin/bash
.PHONY: doctor sources install test test-racket test-python test-historical test-m2-g3 test-m3-andq test-m3-historical-gc test-m3-start-back test-m3-saveit test-m3-interactive test-m3-clock-seed test-m3-session test-m3-launcher test-m4-house-cellar test-m4-mailbox-drop play m2-check m3-source-progress check-source reference-build reference-capture reference-probe compare reference-capture-boot test-boot-reference m3-check m3-native-parity test-m3-bang

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
	@$(PYTHON) -m pytest -q tests/test_harness.py tests/test_fetch_sources.py tests/test_reference_pty.py tests/test_probe.py tests/test_m3_source_progress.py tests/test_boot_reference.py tests/test_smoke_parity.py

test-historical: sources
	@racket tests/historical_vfload_test.rkt
	@racket tests/historical_decl_test.rkt
	@racket tests/historical_computed_global_test.rkt
	@racket tests/historical_error_test.rkt
	@racket tests/historical_memq_test.rkt
	@racket tests/historical_oblist_placement_test.rkt
	@racket tests/historical_channel_start_test.rkt

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

# M4 scenario 1 (enter the house and open the cellar): every command prefix
# compared with the pinned Confusion captures (D1 only) plus read-only state
# checkpoints; then the known strict frontier next to it (not parity).
test-m4-house-cellar: sources
	@racket tests/historical_house_cellar_test.rkt
	@racket tests/historical_m4_frontier_test.rkt

# M4 S2 (drop the leaflet; frontier F1, CHTYPE to SEGMENT): every command
# prefix compared with the pinned Confusion captures (D1 only) plus read-only
# state checkpoints, and the game's INSERT-OBJECT/TAKE-OBJECT tail sharing.
test-m4-mailbox-drop: sources
	@racket tests/historical_mailbox_drop_test.rkt

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
