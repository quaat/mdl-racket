# M3 original-source progress baseline — 2026-11-21

**Gate result: PASS as a progress measurement; original load INCOMPLETE.**
Issue [#73](https://github.com/quaat/mdl-racket/issues/73) separates the
stable M2 original-definition regression from the moving full-loader
frontier. The accepted M2 code baseline is
`0360292d78e07b79002ee509e3b0a72e373dde2d` on `main`; this M3
work does not implement an MDL primitive. The implementation commit is
`7323fa62f2a866b14bb8e0acdcd09086e9dab6c1`; later documentation
and CI wiring are checked on the PR's final head.
Reproduce with:

```bash
make reference-build
make m2-check
make m3-source-progress
```

The target verifies the source lock, sweeps all historical text, runs the
bounded G3 semantic scenario, executes unchanged `77loadall.mud`, and
writes `artifacts/m3/source-load.json` (raw loader) and
`artifacts/m3/source-progress.json` (validated summary). The accepted
initial observation is preserved as
[`source-progress-initial.json`](source-progress-initial.json). It exits 0 for
a *valid incomplete observation*; it does not claim the loader returned
success. The Racket loader subprocess exits 1 at the actual unsupported
EMPTY? call. The validator exits nonzero for fewer than 24 original
expressions, a changed accepted event prefix, skipped forms, wrong file
order, malformed diagnostics, impossible complete-file counts or a false
completion claim. Its baseline is
[`source-progress-baseline.json`](source-progress-baseline.json).
The native reference CI job runs this target after G3, so regressions in
the accepted original-source prefix fail automated checks too.

| Stage or metric | Current observation | Pinned reference or limit |
|---|---|---|
| PARSED | 36 historical text files; four nontext classified | Reader coverage, not execution |
| LOADED | No complete original chain | Confusion completes 12 nested files to `"DONE"` in [`muddle-reference.json`](../M2/muddle-reference.json), case `fload-chain-completion` |
| EXECUTED | 24 original top-level forms, zero skipped | Accepted M2 prefix retained; no later forms executed |
| Files encountered | `77loadall.mud`, `81prim.mud`, `77defs.mud` | Confusion order begins `81prim.mud`, `77defs.mud` |
| Complete file | `81prim.mud` (8 forms) | Original entry and `77defs.mud` are partial |
| Partial files | `77loadall.mud` (2 forms), `77defs.mud` (14 forms) | No world file beyond `77defs.mud` reached |
| First failure | `77defs.mud` expression 15, line 37, column 1, execute/runtime, original `NEWSTRUC` calls unassigned `EMPTY?` | Confusion completes this and the later files |
| INITIALIZED | No | No game globals/parser initialization proved |
| PLAYABLE | No | No Racket game transcript exists |

The `sources.lock.json` revisions remain MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`. The SHA256 values
verified for encountered files are `77loadall.mud`
`389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa`,
`81prim.mud` `8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`,
and `77defs.mud` `566ebcc32be9b9226dd7cefd77a517583eebab80a03f452df39e13b85eed734e`.
The script hashes every newly encountered file as progress advances.

**Test architecture:** `tests/historical_g3_test.rkt` now loads original
`77loadall.mud` expression 1, all eight `81prim.mud` forms, and the first
14 `77defs.mud` forms in a shared session. It keeps VFLOAD, MSETG,
PSETG, FLAGWORD, RAPPLIC declaration association, macro expansion,
aliasing, control/error and session-isolation assertions, and passes 58
checks. `tests/historical_decl_test.rkt` and the D5 property suite use
the same bounded prefix, removing their stale full-loader failure
requirements. The complete chain is exercised only by this M3 target.

**Red-to-green evidence:** before the validator existed,
`.venv/bin/python -m pytest -q tests/test_m3_source_progress.py`
exited 2 at import with `ModuleNotFoundError: scripts.m3_source_progress`.
After implementation it exits 0 with nine tests, including deliberate
regression and malformed-report cases. `make m3-source-progress` exits 0:
24 completed, delta `+0`, zero skipped, first failure EMPTY?. `make
m2-check` exits 0 with 986 Racket and 22 Python tests, historical DECL
20 assertions and G3 58 assertions; native 12-case probe and five-turn
capture also pass. Direct `racket tests/atom_props_test.rkt` initially
exited 1 because its temporary directory defaulted to read-only
`/var/tmp`; `TMPDIR=/tmp racket tests/atom_props_test.rkt` exited 0,
and Makefile exports TMPDIR for the complete passing suite.

The progress validator uses the recorded clean Confusion full-load case
from `muddle-reference.json`. It checks source order and completion
target but does not infer gameplay parity from that native run. No
upstream bytes were changed, GPLv3 Confusion source was not copied into
the MIT-0 runtime, and no network evaluator was added. The next narrow
M3 task is to document and probe EMPTY? against the pinned native
reference, implement it with red-to-green tests, and rerun this target
to identify the actual next original-source dependency.
