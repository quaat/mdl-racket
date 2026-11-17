# Status — 2026-11-17 (M0 local verification)

| Gate | State | Evidence / limitation |
|---|---|---|
| Source SHA verification | **PASS** | `make sources` verified both locked commits and clean upstream trees; see `artifacts/environment/sources.json` |
| Racket and Python tests | **PASS** | Plain `make test`: 26 Racket and 13 Python tests pass with pinned dependencies in ignored `.venv`; Makefile selects the venv and `/tmp`. Earlier failures on read-only `/var/tmp` and missing `pexpect` are recorded in the report. |
| December 1977 text reader sweep | **PASS for parsing** | `make check-source`: 36/36 selected UTF-8 MDL text files parsed, four non-text files classified separately; per-file offsets, hashes and counts in `docs/evidence/M0/reader-sweep.json` |
| Native Confusion build | **PASS** | `make reference-build` built `mdli` from pinned `mdlzork` without changing checkout |
| Opening scene plus five commands | **PASS for reference capture** | `make reference-capture`: all prompts returned, no observed reference errors; reviewed `docs/evidence/M0/house-golden.json` |
| Primitive reference probes | **PASS for reference only** | `make reference-probe`: 12/12 processes exited 0 with empty stderr; `docs/evidence/M0/primitives.json` |
| CI offline job | **NOT RUN remotely** | GitHub repository now exists; workflow execution must be checked on the M0 PR |
| CI native reference job | **NOT RUN remotely** | `.github/workflows/reference.yml` runs on PRs and manual dispatch; check its run on the M0 PR |
| Candidate Racket gameplay / parity | **NOT IMPLEMENTED** | M0 compiler is demonstrative only |

**M0 gate: BLOCKED** on remote CI execution and written human approval of the
reviewed golden transcript. [GitHub issue #1](https://github.com/quaat/mdl-racket/issues/1)
tracks the work. Local reader, reference build, capture, and tests pass. Do not
start M1 until the M0 gate is reviewed and closed. Next action: check both PR
workflows and review the golden fixture in the PR.

See `docs/evidence/M0/REPORT.md` for exact commands, hashes, and limits.
