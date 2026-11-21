SHELL := /bin/bash
.PHONY: doctor sources install test test-racket test-python test-historical test-m2-g3 check-source reference-build reference-capture reference-probe compare

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
	@$(PYTHON) -m pytest -q tests/test_harness.py tests/test_fetch_sources.py tests/test_reference_pty.py tests/test_probe.py

test-historical: sources
	@racket tests/historical_vfload_test.rkt
	@racket tests/historical_decl_test.rkt
	@racket tests/historical_computed_global_test.rkt
	@racket tests/historical_error_test.rkt
	@racket tests/historical_memq_test.rkt

test-m2-g3: sources
	@racket tests/historical_g3_test.rkt

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
