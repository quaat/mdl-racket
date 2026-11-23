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

**Fix (revised after independent review, see below).** A boundary
`with-handlers` records the value actually leaving the loop (a raise caught
inside the loop never counts) and re-raises it unchanged. The post thunk then
flushes every distinct terminal output port once (one failing port no longer
leaves another unflushed; ports shared by several PRINT channels are
flushed once) and **runs no host code**:

- if a raised value is leaving: it continues unchanged (same object, `eq?`);
  every flush failure (any raised value, not only `exn:fail`) is recorded as
  a secondary failure of it, readable with
  `(mdl-host-loop-secondary-failures primary)` (exported by `mdl/loader.rkt`;
  a weak `eq?` table keyed by the primary);
- if nothing was raised (a host escape out of ON-EVENT): the first flush
  failure is raised and the rest are recorded as its secondaries — a flush
  failure with no primary is never swallowed.

ON-EVENT is never called after the loop body has been left, so a host
callback that escapes or raises cannot replace the primary or turn a failure
into a normal return. Breaks are not intercepted by the flush collection.
MDL UNWIND behaviour (ADR-0051) is untouched: the boundary is outside every
MDL frame.

**Independent review (2026-11-23, of 8e3d103/c6e8078).** Found that the
first version (a) caught only `exn:fail` from an ON-EVENT `(flush-failed …)`
report, so another raise replaced the primary; (b) let an ON-EVENT escape
during that report turn the failure into a clean return; (c) collected only
`exn:fail` from port flushes; (d) raised only the first of several
no-primary failures and flushed shared ports twice. All four are fixed by
the revision above, each with a regression (reviewer reproductions adapted).
No defect found in: break handling, misattribution of internally caught
raises, object identity, ADR-0051 interaction.

**Regressions** (`tests/host_loop_test.rkt`, 81 tests): reviewer
reproduction (`eq?` original; no event after the body is left; one
secondary failure); D3 input exhaustion preserved when only the final flush
fails; strict runtime error (inert REP) preserved; non-exception flush raise
recorded as secondary (both as its own primary and under a host primary); a
host that escapes on every event still receives the primary; standalone
flush failure on a host escape is raised; successful escape still flushes.
Red on 45c387f: `7/69` failures for the first set. Mutations caught:
`exn:fail`-only collection (3/81), raising the flush failure when a primary
is leaving (8/80).

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
