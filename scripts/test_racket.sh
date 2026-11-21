#!/usr/bin/env bash
set -euo pipefail

raco make mdl/parser.rkt mdl/compiler.rkt mdl/lang/reader.rkt mdl/lang/main.rkt tests/*.rkt
raco test mdl/runtime/core.rkt \
  tests/parser_test.rkt tests/compiler_test.rkt tests/false_test.rkt \
  tests/atom_test.rkt tests/sequence_test.rkt tests/type_test.rkt \
  tests/binding_test.rkt tests/word_test.rkt tests/integration_test.rkt \
  tests/prog_test.rkt tests/equality_cycle_test.rkt tests/repeat_test.rkt \
  tests/activation_target_test.rkt tests/formals_test.rkt \
  tests/control_test.rkt tests/macro_test.rkt tests/loader_test.rkt tests/muddle_test.rkt \
  tests/declaration_test.rkt tests/declaration_pattern_test.rkt tests/segment_test.rkt \
  tests/atom_props_test.rkt tests/neq_test.rkt tests/error_test.rkt \
  tests/memq_test.rkt tests/mapf_test.rkt tests/typeq_test.rkt \
  tests/startup_oblist_assoc_test.rkt tests/indirect_apply_test.rkt \
  tests/emptyq_test.rkt tests/lengthq_test.rkt tests/assignedq_test.rkt \
  tests/root_test.rkt tests/newtype_decl_test.rkt tests/gdecl_test.rkt \
  tests/andq_test.rkt \
  tests/quoted_optional_test.rkt \
  tests/applicable_decl_test.rkt
