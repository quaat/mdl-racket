# Review F1/F2 fixes on the S7 head (PR #141), 2026-11-23

External review (2026-11-23) of head 45c387f raised two stack-readiness
findings. This record covers both; the specification consolidation (F3) is a
separate documentation branch.

## F2 — the host loop's final flush masked the primary failure

**Defect (reproduced first-hand).** `mdl-run-host-loop` (mdl/runtime/core.rkt)
ran `flush-terminal-output!` as an unconditional `dynamic-wind` post thunk. If
the loop was being left by a raised value and the flush itself raised (closed
or failing output port), the flush exception replaced the original. Red run
with the new regressions in `tests/host_loop_test.rkt` against 45c387f's
core.rkt: `7/69 test failures`; the reviewer's reproduction returns
`flush-output: output port is closed` instead of the preconstructed
`ORIGINAL-STRICT-FAILURE` exception.

**Fix.** A boundary `with-handlers` records the value actually leaving the
loop (a raise caught inside the loop never counts) and re-raises it unchanged.
The post thunk then flushes every terminal output port (one failing port no
longer leaves another unflushed) and:

- if a raised value is leaving: it continues unchanged (same object, `eq?`),
  and each flush failure is reported separately as an ON-EVENT
  `(flush-failed exn)` host observation; a failing ON-EVENT callback in that
  report cannot mask the primary either;
- if nothing was raised (a host escape out of ON-EVENT): the first flush
  failure is raised — a flush failure with no primary is never swallowed.

Breaks are not intercepted by the flush collection. MDL UNWIND behaviour
(ADR-0051) is untouched: the boundary is outside every MDL frame.

**Regressions** (all in `tests/host_loop_test.rkt`): reviewer reproduction
(`eq?` original + one `flush-failed` event); raised non-exception value
preserved; D3 input exhaustion preserved when only the final flush fails;
strict runtime error (inert REP) preserved; standalone flush failure on a host
escape is raised; successful escape still flushes. Green: `71 tests passed`.
A second mutation (never taking the preserve branch) is also caught. The
future QUIT outcome gets its own regression in the QUIT slice.

## F1 — CI did not execute the six-command result

`reference.yml` (the source-enabled workflow) now runs `make test-m3-saveit`
and `make test-m3-interactive` after the existing historical gates, each under
`timeout-minutes: 8` with `set -o pipefail` logs uploaded as
`artifacts/ci-logs/` (the artifact step is `if: always()`). The test itself
has a 300 s watchdog that turns a hang into a failure (mutation-checked in
S7). `max-passes` is not used as a command limit: RDCOM consumes every command
in one pass.

`ci.yml` (offline smoke) now runs the shared `make test-python` target
instead of its own shorter file list, so `tests/test_m3_source_progress.py`
(and any later Python test added to the target) runs in CI.

**Mismatch proof (local, exact CI command).** Changing the approved
`take leaflet` response in `tests/fixtures/house-boot-golden.json`
("Taken." → "Took.") makes `make test-m3-interactive` exit 2 with one
FAILURE; restoring it gives exit 0, `30 tests passed`. The fixture was
restored byte-for-byte; no permissive comparator was added. A CI run of the
same mutation is recorded in the PR #141 comment.
