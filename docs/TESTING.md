# Test strategy, reference capture, and parity contract

## Test layers

1. `make test-racket`: reader, bootstrap compiler, FALSE, atom/OBLIST,
   mutable sequences, type constructors, local/global bindings, and the
   documented 36-bit FIX/WORD subset on the
   explicitly supported subset. The target refreshes the linked `#lang mdl`
   module before tests so changed runtime exports are visible.
2. `python -m pytest -q tests/test_harness.py`: source lock, reference
   interchange format, exact comparator and transcript normalization.
3. `racket scripts/mdl_check.rkt ...`: syntax parse coverage on pinned
   historical source. Record file-by-file results; no unsupported syntax skips.
4. `make reference-build`: native Confusion compile (requires GC/libgc-dev).
5. `make reference-capture`: actual game run on pinned 1977 reconstructed save.
6. `make reference-probe`: run isolated Confusion primitive probes through stdin. The native REPL has no prompt; each case ends with `<QUIT>`. Raw output, stderr, and exit code are captured for review.
7. `python scripts/compare_transcripts.py REF CAND`: strict differential
   transcript comparison (once a candidate game engine is available).
8. Future: state diff, randomized test corpus, complete 500-point game, browser.

## Frozen 1977 baseline

The archived MIT source omits some components required to run the game.
`heasm66/mdlzork` supplies a patched reconstruction and a prebuilt
`SAVEFILE/ZORK.SAVE` image; this is **not** the original archival binary.
A Confusion baseline is independently verified only when its build and
interactive command playback succeed.

Commands:

```bash
make sources
make reference-build
python scripts/reference_runner.py capture \
  --scenario tests/scenarios/house.json \
  --output artifacts/reference/house.json
```

The runner uses a PTY because the original reader expects terminal behavior.
It waits for a `>` prompt. Timeouts, unexpected early exits, and missing
binaries are failures, not passing tests. If the prompt protocol differs on
some platform, fix the PTY bridge with documented, tested input handling.
The M0 baseline was built and captured locally and in CI; see the M0 report.

## Transcript JSON schema v1

```json
{
  "schema_version": 1,
  "engine": "confusion-patched-1977",
  "scenario": "house-smoke",
  "initial_output": "...",
  "complete": true,
  "commands": [
    { "input": "look", "output": "...", "prompt_returned": true }
  ]
}
```

Reference captures additionally record interpreter image SHA256, game image
SHA256, timestamp, exit status, and errors. A Racket candidate must produce
identical `scenario`, command order, initial output, and per-command output
fields, plus `complete=true`; the `engine` and binary hashes may differ.
Future captures can include read-only `state` snapshots for deeper tests.

### Normalization

The current reference runner removes PTY ANSI SGR/control sequences matching
`ESC [ digits/semicolon <letter>` and normalizes CRLF/CR to LF. It does **not**
strip spaces, remove prompt text from responses (beyond the consumed `>`),
reword descriptions, ignore score differences, or normalize random behavior.
Any further normalization must be explicit and reviewed, with a negative test.

### Golden approval and evidence

Do NOT auto-update goldens when assertions fail. Review the output manually,
record the SHA256 and captured source commits, and only then copy a curated
fixture to `docs/evidence/<milestone>/`. Failed capture JSON belongs in
`artifacts/` and must not be treated as truth. Avoid including private data,
credentials, or host paths in published evidence.

M0's locally reviewed and maintainer-approved fixture is
`docs/evidence/M0/house-golden.json`; hashes, exact command sequence, output
review, timestamp limitation, and PTY exit behavior are in
`docs/evidence/M0/REPORT.md`. The second observed capture matched the first
except for `captured_at`. Rebuilding native Confusion changes its banner's
compile timestamp and thus the exact `initial_output` field.
Approval was given in the Codex conversation on 2026-11-17 for the fixture
with SHA256 `ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.

## Cross-engine limitations

Random NPC actions, runtime timing, and historical save/restore features may
produce legitimate nondeterminism. Deal with that through controlled seeds,
instrumentation, or scenario design rather than weakening strict comparisons.
The earliest endgame is incomplete in some variants; the playable December
1977 reconstruction is documented as a 500-point game.
