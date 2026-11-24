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
  tests/chtype_segment_test.rkt \
  tests/chtype_character_test.rkt \
  tests/atom_props_test.rkt tests/neq_test.rkt tests/error_test.rkt \
  tests/memq_test.rkt tests/mapf_test.rkt tests/typeq_test.rkt \
  tests/startup_oblist_assoc_test.rkt tests/indirect_apply_test.rkt \
  tests/emptyq_test.rkt tests/lengthq_test.rkt tests/assignedq_test.rkt \
  tests/root_test.rkt tests/newtype_decl_test.rkt tests/gdecl_test.rkt \
  tests/andq_test.rkt \
  tests/quoted_optional_test.rkt \
  tests/applicable_decl_test.rkt \
  tests/percent_empty_test.rkt \
  tests/pstring_literal_test.rkt \
  tests/function_decl_metadata_test.rkt \
  tests/space_character_test.rkt \
  tests/percent_read_test.rkt \
  tests/nth_decl_test.rkt \
  tests/deferred_decl_type_test.rkt \
  tests/duplicate_decl_test.rkt \
  tests/event_registration_test.rkt \
  tests/interrupt_dispatch_test.rkt \
  tests/logical_gc_test.rkt tests/special_decl_test.rkt \
  tests/lose_literal_test.rkt tests/error_interrupt_test.rkt \
  tests/erret_interrupt_cleanup_test.rkt \
  tests/channel_type_test.rkt tests/numeric_predicate_test.rkt \
  tests/istring_test.rkt \
  tests/structured_type_head_test.rkt tests/block_test.rkt \
  tests/iuvector_chutype_test.rkt tests/ivector_test.rkt tests/mapr_test.rkt \
  tests/chtype_atom_test.rkt tests/min_test.rkt tests/max_test.rkt tests/abs_test.rkt tests/p0prims_test.rkt \
  tests/chtype_string_test.rkt \
  tests/typed_string_literal_test.rkt tests/moblist_association_test.rkt \
  tests/empty_uvector_test.rkt tests/spname_test.rkt \
  tests/gettimedate_test.rkt tests/terminal_channel_test.rkt \
  tests/printstring_channel_test.rkt tests/crlf_test.rkt \
  tests/random36_test.rkt tests/back_test.rkt tests/top_test.rkt \
  tests/function_type_test.rkt \
  tests/unparse_test.rkt \
  tests/memq_string_test.rkt \
  tests/channel_port_test.rkt tests/channel_root_identity_test.rkt \
  tests/constructor_eval_policy_test.rkt tests/string_view_consumers_test.rkt \
  tests/oblist_identity_test.rkt \
  tests/substruc_test.rkt \
  tests/on_save_test.rkt \
  tests/escaped_atom_test.rkt \
  tests/rep_test.rkt \
  tests/reset_test.rkt \
  tests/princ_test.rkt \
  tests/readstring_test.rkt \
  tests/readstring_bang_test.rkt \
  tests/prin1_test.rkt \
  tests/host_loop_test.rkt \
  tests/unwind_raise_test.rkt \
  tests/session_clock_test.rkt \
  tests/replay_clock_test.rkt tests/replay_checkpoint_test.rkt \
  tests/member_test.rkt \
  tests/quit_open_test.rkt \
  tests/session_output_port_test.rkt
