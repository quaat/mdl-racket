# M0 local verification report — 2026-11-17

**Gate: FAIL on first native CI run; fix pending rerun.** Local source, reader,
test, native build, capture, and probe checks pass with the documented compiler
compatibility flag. Human approval of the golden fixture remains open.
GitHub issue [#1](https://github.com/quaat/mdl-racket/issues/1) tracks M0;
PR [#2](https://github.com/quaat/mdl-racket/pull/2) carries the work on
`feat/m0-reader-reference-validation`. The `gh` CLI token is
invalid, but the connected GitHub app can create issues and PRs.

## Provenance and environment

- Local base commit SHA: `862feacc4158855f8d32052bafa92f72e408a96d`
  (`initial version`). M0 implementation commit:
  `0c71aa2a74bf423cf2edfd9c07186f8a243d828e`. The compatibility follow-up
  commit SHA will be recorded in the PR comment after commit.
- Archival `MITDDC/zork`: `d94501340842e006791fce0757dc0043b8ec8916`.
- Reconstructed `heasm66/mdlzork` and Confusion: `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
- Both pinned worktrees had empty `git status --porcelain` after building.
- Linux 5.10.0-46-amd64 x86_64; Racket 7.9 [bc]; Python 3.13.0;
  pexpect 4.9.0; pytest 8.4.2; g++ 10.2.1; BDW GC 8.0.4.
- Native `mdli` SHA256 after compatibility rebuild: `99728037f046ee68fdbb6ef69f44155e3c03f9c0b2b0840fbc218c75024c21e3`.
- Reconstructed game image SHA256: `92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6b0ffb7a4`.
- Source manifest: `artifacts/environment/sources.json` (local generated artifact).

## Exact command results

| Command | Exit | Observed result |
|---|---:|---|
| `make doctor` | 0 | Racket, raco, make, C/C++, Perl, pkg-config found; BDW GC 8.0.4 |
| `make test` (initial) | 2 | Racket runner could not write `/var/tmp` (`Read-only file system`) |
| `TMPDIR=/tmp make test` (initial) | 2 | Racket: 14 passed; Python collection failed: `No module named 'pexpect'` |
| `python3 -m pip install --target /tmp/mdl-m0-pydeps -r requirements.txt` (sandbox attempt) | 1 | DNS blocked for PyPI; retried with scoped network approval |
| Same `pip install` with scoped network access | 0 | Installed pinned pexpect 4.9.0 and pytest 8.4.2 in `/tmp` |
| `make sources` | 0 | Verified both exact locked SHAs; wrote source manifest |
| `TMPDIR=/tmp raco test tests/parser_test.rkt` (new lexical tests before fix) | 1 | `![1 2!]` was read as `("1" "2!")`; `![!]` raised unexpected delimiter |
| `TMPDIR=/tmp PYTHONPATH=/tmp/mdl-m0-pydeps python3 -m pytest -q tests/test_reference_pty.py` (before fix) | 1 | Banner `<WARRANTY>` was mistaken for prompt; initial output truncated |
| `TMPDIR=/tmp raco test tests/parser_test.rkt` (string escape test before fix) | 1 | `\n` was decoded as newline instead of quoted `n` |
| `TMPDIR=/tmp PYTHONPATH=/tmp/mdl-m0-pydeps python3 -m pytest -q tests/test_probe.py` (before probe rewrite) | 2 | Missing `probe_case` import, then implemented |
| `TMPDIR=/tmp PYTHONPATH=/tmp/mdl-m0-pydeps make test` (final) | 0 | **26 Racket tests; 13 Python tests passed** |
| `python3 -m venv .venv` | 0 | Local ignored Python environment available |
| `python3 -m pip install --target .venv/lib/python3.13t/site-packages -r requirements.txt` | 0 | Pinned versions installed; pip noted pre-existing target files |
| `make test` (plain, after Makefile environment fix) | 0 | **26 Racket tests; 13 Python tests passed** |
| `make check-source` | 0 | **36/36 UTF-8 text files parsed; 4 non-text binary artifacts excluded** |
| `make reference-build` | 0 | Native `mdli` compiled from copied pinned source; upstream checkout untouched |
| `PYTHONPATH=/tmp/mdl-m0-pydeps make reference-capture` | 0 | Opening scene plus five commands; all prompts returned |
| `PYTHONPATH=/tmp/mdl-m0-pydeps make reference-probe` | 0 | 12/12 isolated primitive cases, exit 0, empty stderr |
| `PYTHONPATH=/tmp/mdl-m0-pydeps make reference-capture` (second run) | 0 | All response fields equal to first run except `captured_at` |
| `make reference-capture` and `make reference-probe` (plain, after venv setup) | 0 each | Both outputs match reviewed evidence apart from timestamps |
| `gh auth status` | 1 | Active account token invalid |
| `git switch -c feat/m0-reader-reference-validation` | 0 after scoped `.git` write approval | M0 worktree carried onto a review branch |
| [GitHub Harness checks run 44124806506](https://github.com/quaat/mdl-racket/actions/runs/44124806506) | 0 | Offline Racket and Python jobs succeeded on PR #2 |
| [GitHub native run 44124806654](https://github.com/quaat/mdl-racket/actions/runs/44124806654) | 2 | `macros.hpp:125:9: error: ‘uint64_t’ does not name a type`; compiler suggests `<cstdint>`; source sweep step passed |
| `make reference-build` with `-include cstdint` | 0 | Exported Confusion copy builds locally; upstream source unchanged; `_XOPEN_SOURCE` redefinition warning in `mdl_assoc.cpp` |
| `make reference-capture`; `make reference-probe`; `make test` after rebuild | 0 each | Five prompts and 12 primitive exits clean; 26 Racket and 13 Python tests pass |

During the final rerun, `make test` temporarily exited 2 because
`mdl/runtime/core.rkt` had appeared at `mdl/lang/runtime/core.rkt`; the
imports still required the former path. The file was restored to its original
location and the exact command then passed 26/13. The cause of that local
move is unknown; it was not part of the planned reader edits.

The first reader sweep parsed 21/40 files and failed at source locations listed
in the tool output. New comment, uvector, computed comma-reference, and string
escape tests failed first, then passed. The final per-file inventory, hashes,
parse counts, and four UTF-8 decoding failures are in `reader-sweep.json`
(SHA256 `1412e0b42338156c8d3a64bd70955f211046d8e233e563837047ecd107a23017`).
The four non-text entries are two copies each of `act2z.27` and `dungz.56`.
Other `.nbin` and saved-game artifacts were not treated as textual MDL source.

## Reference review and golden

The reviewed capture is `house-golden.json`, SHA256
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
Input is `west`, `open mailbox`, `take leaflet`, `inventory`, `score`, starting
from the pinned save's north side of the house. The output reaches West of
House, reveals and takes the leaflet, shows it in inventory, and reports 0/500
in seven moves. `take leaflet` prints both `Taken.` and `You already have it.`;
this is recorded verbatim, not rewritten. No error text appears in the five
responses. This is an agent review; **human golden approval remains pending**.

The PTY uses 40 rows by 100 columns, echo disabled, a 30-second response
timeout, and line-start `>` prompts. After the fifth prompt, the runner
terminates the still-running game: `process_exitstatus=null`,
`process_signalstatus=1` (SIGHUP). Confusion's banner includes a C++ build
timestamp, so rebuilding changes `initial_output`. No RNG seed was set; the
two matching runs establish stability only for this five-command scenario.
After the compiler compatibility rebuild, all five command outputs and the
opening scene after the banner matched the earlier reviewed capture exactly;
the engine hash and embedded compile timestamp changed. The fixture was
manually reviewed and refreshed for the new local binary.
The archival binary is not the reconstructed save image. Archive versus
playable reconstruction patches remain documented in `docs/PROVENANCE.md` and
upstream `mdlzork_771212/README.md`; no local patch was applied.

Primitive reference evidence is `primitives.json`, SHA256
`76271e83e6440f4b017a44732a721ae56e9765275039e63179689a6e8da6ee0e`,
with exact per-case `.mud` input and `.reference.txt` raw stdout in `probes/`.
The native REPL has no prompt. Each process received its expression sequence
and `<QUIT>`, exited 0, and wrote no stderr. Findings for FALSE versus `NIL`,
`REST`/`PUT`/`PUTREST`, bindings, types, and `RETURN` are in
`docs/SEMANTICS.md`. These are Confusion observations, not Racket parity.

## Support, deviations, and impact

- Reader AST: forms, lists, vectors, uvectors, strings, quotes, global/local
  references, splice/percent prefixes, typed-brace forms, and source locations.
  Semicolon comments skip one full object; `![...!]` and `![...]` both parse.
  Historical comment associations and raw source spelling are not retained.
- M0 compiler: only fixed-arity simple `DEFINE`, a small `SETG`/`GVAL`/`SET` and
  expression subset. Computed `GVAL`, payload FALSE, mutable shared views,
  full types, activation control, macros, and game loading remain unsupported
  or approximated as listed in `docs/SEMANTICS.md`. It still raises on
  unsupported constructs; no original game execution is claimed.
- Security: all reference execution remained local. No evaluator or REPL was
  exposed to a web client. Licensing: Confusion GPLv3 source stayed in the
  upstream checkout/build area; no C++ code was copied into the MIT-0 runtime
  and no mixed binary was distributed.
- CI workflow files exist locally. The native workflow only uploads JSON
  evidence. Offline CI passed. Native CI failed on an omitted standard C++
  header in pinned Confusion; a build-only `-include cstdint` workaround is
  prepared and must pass remotely before M0 can pass. See `docs/PROVENANCE.md`.

## Blocker and next action

Root cause: Ubuntu 24.04 native CI rejected `uint64_t` because pinned Confusion
omits `<cstdint>`; the build flag fixes local compilation without changing
upstream bytes. **Recommended next action:** push the compatibility fix and
confirm the native PR workflow passes, then obtain human approval of the
golden transcript. Until then, M0 is FAIL and M1 work does not start.

When M0 closes, proposed M1 issue order is: values/FALSE/atoms → mutable
LIST/VECTOR/UVECTOR views and identity → types/constructors → local/global
binding → 36-bit arithmetic. Each slice needs a documented Confusion probe,
failing-then-passing Racket tests, and differential validation before the next.
