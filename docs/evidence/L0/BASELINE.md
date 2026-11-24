# L0 baseline verification

The audited commit is
`522b56339865ed1226550e00968f330807d74525` of `quaat/mdl-racket`.
`git fetch --prune origin` exited 0, `HEAD` equaled `origin/main`,
and the tree was clean before the work. The L0 branch adds documentation
and tests. No existing runtime, scenario regression or approved golden
was edited. The initial M4 sweep evidence follows [epic #163](https://github.com/quaat/mdl-racket/issues/163).

## Toolchain and inputs

| Item | Version or SHA |
| --- | --- |
| Racket | 8.10 BC for the primary results, 9.3 CS for the first baseline run |
| Python | 3.13.5, pexpect 4.9.0 and pytest 8.4.2 in the checkout's venv |
| Git, make, GCC | 2.47.3, 4.4.1, 14.2.0 |
| Archival MIT Zork | `d94501340842e006791fce0757dc0043b8ec8916` |
| Reconstructed Zork and Confusion | `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3` |
| Built Confusion SHA-256 | `da8472a991a8f2fe109c117cfe00c6207edb5bb8d9033dfe36f1e2d478380f68` |
| Manual transcription | `89707367b951ea79bedc71f51ab213886e0f62ce` |

`make doctor` exited 0. It reported missing pkg-config. The GC headers
and libraries were present. `make sources` exited 0 and verified both
locked checkouts. An initial network-restricted clone exited 2 and was
retried with network access. Both historical working trees were clean
after `make reference-build`, which exited 0, linked `mdli` with the
existing `-include cstdint` compatibility flag, and reported an
`_XOPEN_SOURCE` redefinition warning.

`python3 -m venv .venv` and `PLTUSERHOME="$(mktemp -d)" make install`
installed the Python dependencies and linked this checkout in a private
Racket 9.3 package directory. Linking with a package home nested inside
the checkout initially failed because Racket forbids the overlap.
The Racket 8.10 BC distribution was independently installed in a
private cache. The 8.10 gates used its `racket` and `raco` first on
PATH, a separate PLTUSERHOME, `PLTCOLLECTS="$PWD:"`, and `TMPDIR=/tmp`
(exported by Make for its targets). Use a separate compiled-file cache
or rebuild the checkout when switching Racket versions.

## Baseline gates

| Command | Outcome |
| --- | --- |
| `make test`, 9.3 CS | **FAIL**, exit 2. Six of 4,843 assertions in `tests/host_loop_test.rkt` failed. The empty write was skipped in the tested custom port, shifting flush counts and the primary error in one check. |
| `make test`, 8.10 BC | **PASS**, exit 0. 4,844 Racket assertions, 74 Python tests passed and one deselected. |
| `TMPDIR=/tmp raco test tests/host_loop_test.rkt`, 8.10 BC | **PASS**, exit 0. 81 tests. Earlier direct invocations had stale 9.3 bytecode or a read-only `/var/tmp`. |
| `make test-historical` | **PASS**, exit 0 on both versions. |
| `make m3-source-progress` | **PASS**, exit 0 on 9.3 and on 8.10 after `raco make scripts/mdl_load.rkt scripts/m3_house_boot_run.rkt`. 36 historical files parsed, 1,229 original forms loaded, zero skips. The first 8.10 command exited 2 because an invoked script still had 9.3 bytecode. |
| `M3_NATIVE=require make m3-check` | **PASS**, exit 0 on 9.3 and on 8.10 after recompilation. All seven stages passed, including fresh native parity. The first 8.10 command exited 2 on stale runner bytecode. |
| `make m3-native-parity` | **PASS**, exit 0 on 8.10 BC. Both selected parity stages passed. |
| `make test-m3-andq`, `make test-m3-historical-gc`, `make test-m3-start-back`, `make test-m3-saveit`, `make test-m3-clock-seed`, `make test-m3-interactive`, `make test-m3-session`, `make test-m3-launcher`, `make test-m3-bang`, `make test-boot-reference` | **PASS**, exit 0 on 9.3 CS. |

M3 uses the approved fixed-clock house-boot capture with epoch 250776000
UTC, original game startup and its deterministic RNG derivation.
M4 uses its existing per-prefix transcript and state checkpoint
fixtures with the same clock epoch and documented D1 normalization.
Replay additionally verifies the documented RNG checkpoint contract.
These are scenario-scoped results.

| Racket 8.10 BC M4 target | Outcome |
| --- | --- |
| `make test-m4-house-cellar` | **PASS**, exit 0. 12 prefixes and the expected adjacent strict frontiers. |
| `make test-m4-mailbox-drop` | **PASS**, exit 0. 9 prefixes. |
| `make test-m4-orphan-prompt` | **PASS**, exit 0. 10 prefixes. |
| `make test-m4-top-parser` | **PASS**, exit 0. 11 prefixes. |
| `make test-m4-sword-glow` | **PASS**, exit 0. 14 prefixes. |
| `make test-m4-troll-combat` | **PASS**, exit 0. 23 prefixes. |
| `make test-m4-parser-ambiguity` | **PASS**, exit 0. 35 prefixes. |
| `make test-m4-replay-persistence` | **PASS**, exit 0. WP4.5/WP4.6, including fresh-process restore, RNG and TIME checkpoints. |
| `make test-m4-cyclops-room` | **PASS**, exit 0. 41 prefixes. |
| `make test-m4-mirror-bat` | **PASS**, exit 0. 38 prefixes. |
| `make test-m4-strange-passage` | **PASS**, exit 0. 32 prefixes. |

## L0 artifacts

- `make test-manual` under Racket 8.10 BC exited 0 with 72 PASS and 16
  XFAIL across 44 fixtures. The initial harness conflated module host
  printing with explicit MDL output. Two expectation errors were
  resolved using the manual's UNWIND rule and the existing accepted DECL?
  payload. The [fixture manifest](../../tests/conformance/manifest.json)
  retains both the manual and accepted declaration values. The
  [machine-readable summary](manual-summary.json) includes both paths
  for each fixture. The NTH range check is a positive diagnostic test.
- `.venv/bin/python -m scripts.probe_manual --output artifacts/l0/native.json`
  exited 1. Of 44 observations, 40 completed without diagnostics, three
  hit native limitations and one signaled the expected range error. The complete [probe record](native-examples.json) preserves
  diagnostics for SQRT, SETLOC, %% and the out-of-range NTH. Native inputs were bare local
  programs in fresh empty working directories, with default RNG, UTC
  and final QUIT. These observations are separate from approved game
  transcripts.
- `git clone https://github.com/taradinoc/mdl-docs.git .cache/conformance-manual`,
  followed by checkout of the transcription SHA above, supplies the input
  for `python3 scripts/inventory_manual.py .cache/conformance-manual`.
  Add `--check` to verify that the checked-in inventory regenerates.
- `git diff --check` exited 0 for the candidate. The provided smoke file
  was run after adjusting only its imports in a disposable copy and
  passed all 10 tests.
- Independent review confirmed the fixes to the harness, coverage
  generator and corpus expectations. A successful case marked as a gap
  yielded XPASS on both execution paths. A wrong diagnostic yielded
  FAIL, whereas the original diagnostic yielded XFAIL.

The corpus is trusted local test input. The process limits and disposable
directories do not provide an OS sandbox for untrusted MDL. No new
game capabilities or file policies are introduced. The manual examples
are short excerpts with attribution. The historical dependency remains
separately fetched under its existing provenance and license.

**L0 gate remains open.** Complete the remaining semantic and example
audit in #178 and obtain review. The association removal discrepancy in
[#179](https://github.com/quaat/mdl-racket/issues/179) is a separate
maintainer decision before the L1 implementation.
