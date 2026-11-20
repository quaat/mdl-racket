#!/usr/bin/env bash
set -euo pipefail

raco make mdl/parser.rkt mdl/compiler.rkt mdl/lang/reader.rkt mdl/lang/main.rkt tests/*.rkt
raco test mdl/runtime/core.rkt \
  tests/parser_test.rkt tests/compiler_test.rkt tests/false_test.rkt \
  tests/atom_test.rkt tests/sequence_test.rkt tests/type_test.rkt \
  tests/binding_test.rkt tests/word_test.rkt tests/integration_test.rkt \
  tests/prog_test.rkt tests/equality_cycle_test.rkt tests/repeat_test.rkt \
  tests/activation_target_test.rkt tests/formals_test.rkt \
  tests/control_test.rkt tests/macro_test.rkt tests/loader_test.rkt \
  tests/declaration_test.rkt tests/declaration_pattern_test.rkt tests/segment_test.rkt
