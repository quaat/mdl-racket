# Status — 2026-11-17 (starter archive)

| Gate | State | Evidence / limitation |
|---|---|---|
| Source SHAs captured | PASS (metadata only) | `sources.lock.json` pins verified GitHub commit metadata |
| Upstream clones installed locally | NOT RUN | Network required; `make sources` |
| Reader/compiler files created | PASS (files exist) | `mdl/` source; no Racket runtime was available in packaging environment |
| Racket syntax and unit tests | NOT RUN | **Racket not installed in packaging environment**; `make test-racket` |
| Offline Python harness tests | **PASS** | `python3 -m pytest -q tests/test_harness.py tests/test_fetch_sources.py tests/test_reference_pty.py`: 9 passed, 1 benign PTY deprecation warning (packaging environment) |
| Confusion C++ build | NOT RUN | `make reference-build` requires internet, compiler, and libgc |
| Confusion startup / gameplay capture | NOT RUN | `make reference-capture` |
| 1977 textual source parse coverage | NOT RUN | `racket scripts/mdl_check.rkt ...` |
| Candidate MDL Zork gameplay | NOT IMPLEMENTED | Bootstrap compiler does not execute source game |
| Differential game parity | NOT IMPLEMENTED | Requires running candidate engine |
| Browser gameplay | NOT IMPLEMENTED | Deferred until core game semantics pass |

First priority: run and repair the M0 scaffold on a machine with Racket,
then verify native Confusion reference behavior. Any failure is a useful
finding; record exact reproduction evidence rather than changing the status
without tests.

## Packaging correction — 2026-11-17

Corrected local package install instructions in README, Makefile, and GitHub CI:
`raco pkg install --auto --link` (without a final `.`). The previous
`--link .` failed because `.` is not a valid inferred package name.
Added an offline regression test; native Racket execution remains unverified.
