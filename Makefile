SHELL := /bin/bash
.PHONY: doctor sources install test test-racket test-python check-source reference-build reference-capture reference-probe compare

PYTHON ?= python3
RACKET ?= racket

doctor:
	@$(PYTHON) scripts/doctor.py

sources:
	@$(PYTHON) scripts/fetch_sources.py

install:
	@$(PYTHON) -m pip install -r requirements.txt
	@raco pkg install --auto --link || (echo 'If package is already linked, this may be harmless; inspect raco pkg show.'; exit 1)

test: test-racket test-python

test-racket:
	@raco test tests/parser_test.rkt tests/compiler_test.rkt

test-python:
	@$(PYTHON) -m pytest -q tests/test_harness.py tests/test_fetch_sources.py tests/test_reference_pty.py

check-source:
	@$(RACKET) scripts/mdl_check.rkt .cache/upstream/mit_zork/zork/lcf/defs.63

reference-build: sources
	@bash scripts/build_confusion.sh

reference-capture:
	@$(PYTHON) scripts/reference_runner.py capture --scenario tests/scenarios/house.json --output artifacts/reference/house.json

compare:
	@test -n "$(CANDIDATE)" || (echo 'Usage: make compare CANDIDATE=artifacts/candidate/house.json' >&2; exit 2)
	@$(PYTHON) scripts/compare_transcripts.py artifacts/reference/house.json "$(CANDIDATE)"

reference-probe:
	@test -n "$(PROMPT)" || (echo 'Usage: make reference-probe PROMPT=<observed-Confusion-REPL-prompt>' >&2; exit 2)
	@$(PYTHON) -m scripts.mdl_probe --cases tests/scenarios/primitives.json --output artifacts/reference/primitives.json --prompt "$(PROMPT)"
