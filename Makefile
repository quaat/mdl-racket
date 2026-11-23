SHELL := /bin/bash
.PHONY: doctor sources install test test-racket test-python test-historical test-m2-g3 test-m3-andq test-m3-historical-gc test-m3-start-back test-m3-saveit test-m3-interactive test-m3-clock-seed test-m3-session test-m3-bang m2-check m3-source-progress check-source reference-build reference-capture reference-probe compare test-m3-launcher play

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
	@$(PYTHON) -m pytest -q tests/test_harness.py tests/test_fetch_sources.py tests/test_reference_pty.py tests/test_probe.py tests/test_m3_source_progress.py

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

# S13 part A (ADR-0050 §3 amended): the `!` escape in terminal input read by
# the game's own RDCOM (`nor!th` behaves like `north`), compared with the
# pinned Confusion game cases in docs/evidence/M3/readstring-bang-probe.json.
test-m3-bang: sources
	@raco test tests/historical_bang_input_test.rkt

# S12 (WP4): the local launcher zork/main.rkt (run-zork) and its command line
# zork/cli.rkt: the S11 house-quit transcript through run-zork, EOF, notice,
# fresh state per run, missing sources, CLI exit codes, break propagation.
test-m3-launcher: sources
	@raco test tests/launcher_test.rkt

# Play the unchanged 1977 Zork locally on this terminal (real clock, local
# zone). Exit codes are documented in zork/cli.rkt and README "Play locally".
play: sources
	@$(RACKET) zork/cli.rkt

# Issue #135 part 1 (ADR-0052): fixed session clock -> DSKDATE -> START's
# RANDOM seed -> RANDOM state, observed host-only.
test-m3-clock-seed: sources
	@raco test tests/historical_clock_seed_test.rkt

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

compare:
	@test -n "$(CANDIDATE)" || (echo 'Usage: make compare CANDIDATE=artifacts/candidate/house.json' >&2; exit 2)
	@$(PYTHON) scripts/compare_transcripts.py artifacts/reference/house.json "$(CANDIDATE)"

reference-probe:
	@$(PYTHON) -m scripts.mdl_probe --cases tests/scenarios/primitives.json --output artifacts/reference/primitives.json
