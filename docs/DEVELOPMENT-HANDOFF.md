# Development handoff — MDL on Racket

Durable cross-session state. Update at every meaningful checkpoint; link to
evidence instead of duplicating logs. Last updated 2026-11-21.

**Current checkpoint:** M2 integrated on `main` at `7d34195`, with 59
SHA-verified G3 assertions, 986 Racket checks and 13 Python tests.
`make m2-check` and the final mainline harness workflow passed. See
`docs/evidence/M2/MAINLINE-GATE.md` for all merge commits, command exits,
source hashes, reference comparisons and limits. Issue #73 now separates
the permanent M2 prefix from full-loader progress: M2 G3 passes 58
assertions, `make test` passes 986 Racket and 22 Python checks, and
`make m3-source-progress` reports 24 completed and zero skipped forms at
EMPTY? in `77defs.mud` expression 15. See `docs/evidence/M3/SOURCE-PROGRESS.md`.
**Next:** implement M3 EMPTY? from native evidence and advance the unchanged
source chain. Random/event APIs are M3 issue #71. User untracked files
`.claude/worktrees/` and `tests/fixtures/mytest.mdl` are untouched.

## Earlier checkpoints (retained for provenance)

**Latest correction (issue #60):** `feat/m2-error-primitive` adds a strict
`ERROR` builtin. Four deliberate native error cases are saved in
`docs/evidence/M2/error-*`; the Racket `ERROR` raises a non-resumable
exception. The hash-verified original MSETG conflicting-repeat path now
passes. `make test` passes 888 Racket and 13 Python checks;
`make test-historical` passes all four probes. The integrated G3 branch
still needs a current-head run, so G3 remains FAIL and M3 is not started.
Next: update and rerun G3, then act only on its observed first failure.

**Latest M2 correction (issue #63):** `feat/m2-memq` implements `MEMQ`
for LIST, VECTOR, UVECTOR and list-primitive structured values with
`==?` identity and REST aliasing. Eight clean Confusion cases and three
deliberate error cases (including one reference segfault) are saved in
`docs/evidence/M2/memq-*`. `make test` passes 903 Racket and 13 Python
checks; `make test-historical` passes VFLOAD 23, DECL 21, MSETG, PSETG.
The updated G3 test passes 52 assertions then exits 2: original FLAGWORD
reaches unassigned `MAPF` (issue #65). See `docs/evidence/M2/MEMQ.md`
and `G3-GATE.md`. G3 FAIL; M3 unstarted.

**Current G3 rerun:** `feat/m2-g3-current` carries the saved integration
test onto `3589652`. `make test-m2-g3` exits 2 after 48 passing assertions;
original MSETG first/equal/conflict paths pass, while original PSETG
reaches unassigned `MEMQ` after initial side effects. Issue #63 is the
next focused correction. See `docs/evidence/M2/G3-GATE.md`. G3 FAIL;
do not begin M3.

**Latest correction (issue #58):** `feat/m2-computed-global` reads `,.FOO`
as GVAL of FOO's local value. Three pinned Confusion cases, reader and
binding regressions, and a hash-verified original MSETG equal-repeat probe
pass. `make test`: 884 Racket and 13 Python checks; `make test-historical`:
VFLOAD, DECL, and MSETG equal-repeat pass. The conflicting-repeat path
reaches unassigned `ERROR` (issue #60), so G3 remains FAIL. Evidence:
`docs/evidence/M2/COMPUTED-GLOBAL.md`. Next: focused `ERROR` primitive,
then rerun G3. Do not begin M3; D5 PR #54 remains unmerged.

**Latest correction (issue #57):** `feat/m2-structural-neq` adds the
reference-backed structural `N=?` primitive. Eight clean Confusion cases,
three deliberate arity errors, and two bounded cyclic timeouts are in
`docs/evidence/M2/NEQ.md`. `make test` passes 879 Racket checks and 13
Python tests; 13 focused tests fail before and pass after. The exact
original MSETG advances to a distinct `,.FOO` computed-global reader
failure (issue #58). G3 remains FAIL. D5 PR #54 remains unmerged pending
explicit maintainer approval; do not begin M3 EMPTY?.

**D5 local review update (issue #67):** The native SUBR FIX-indicator
association bug is fixed and documented in
`docs/evidence/M2/D5-FINAL-REVIEW.md`. Its final-head CI and maintainer
approval remain pending.

- **Milestone / gate:** M2. D1 (PR #45), D2 (PR #49), D3 (PR #50), D4
  (PR #52), and the agent definitions (PR #47) are all **merged into
  `main`** (current main `419fc5c`); issues #44/#46/#48/#51 closed.
  Pre-merge G3 FAIL: `N=?` issue #57 is locally corrected, then original
  MSETG reaches the distinct `,.FOO` reader gap (issue #58). M2 NOT PASS.
- **Active issues/PRs:** issue **#53** and [PR #54](https://github.com/quaat/mdl-racket/pull/54)
  (D5 atom-property `PUT`/`GET`) —
  reference evidence, implementation, focused tests, and independent review
  fixes are on `feat/m2-atom-props` (base `419fc5c`, head `e6d295d`).
  Both PR workflows passed on that corrected head; the requested
  final-head Codex review was declined by the service's usage limit.
  Issue
  #11 was closed as completed on 2026-11-20.
- **D5 state (implemented, main-session-verified on
  `feat/m2-atom-props`):** Confusion reference evidence (18 success + 6
  deliberate-error observations; `docs/evidence/M2/ATOM-PROPS.md`) plus
  the implementation (commit `676f488`) and focused tests
  (`tests/atom_props_test.rkt`, commit `a3ce79f`). Independent review found
  the weak `eq?` item-key mismatch, structured two-arg PUT dispatch, and
  DECL alias/precedence gaps; review regressions and pinned Confusion
  evidence are under `atom-props-review-*`. A further final-head review
  found inconsistent CHARACTER extraction from STRING GET versus SEGMENT;
  four clean Confusion probes and two red-to-green tests now cover the fix.
  An independent local final-head review fixed the native-SUBR FIX
  association dispatch (issue #67); see `docs/evidence/M2/D5-FINAL-REVIEW.md`.
  Fresh suites: 868
  Racket checks, 13 Python tests, `make test-historical` green
  (VFLOAD 23 + DECL 20 assertions). The pinned `77loadall.mud` load
  completes **twenty-four expressions** — `81prim.mud` in full plus
  `77defs.mud` 1–14, including the historical
  `<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>` — and stops at
  `77defs.mud` expression 15 (`<NEWSTRUC ROOM VECTOR ...>`, line 37):
  the original source-defined `NEWSTRUC` calls the unassigned `EMPTY?`
  primitive (execute stage). Architect decisions: follow the reference
  over the manual where they conflict (removal returns the item;
  augmented `#FALSE (leaf)` DECL? misses); session-owned strong-reference
  association entries compared with MDL `==?` on both keys; `SETG` does not
  enforce DECL associations; GETPROP/PUTPROP and chapter 13.4 machinery
  explicitly unimplemented. See ADR-0023 and the M2 D5 section of
  `docs/SEMANTICS.md`.
- **Exact next action:** implement issue #65 MAPF against the pinned
  reference, then rerun G3; merge D5
  only after explicit
  maintainer approval and final-head review. M3 `EMPTY?` waits for G3.
- **Active issues/PRs (historical, D2/D3 era — superseded by the header
  above):** [PR #49](https://github.com/quaat/mdl-racket/pull/49)
  (D2 SEGMENT) and
  [PR #47](https://github.com/quaat/mdl-racket/pull/47) (Flash subagent
  definitions) were green awaiting merge; issue #48 (D3) was implemented
  on stacked branches. All have since merged.
- **Latest integrated commit (historical, D1 era):** `f87d160` on `main`
  (merge of PR #45, declarations; post-merge CI green, run 44615298096);
  superseded by `419fc5c` (merge of PR #52).
- **D3 state (implemented, main-session-verified):** Confusion
  reference evidence (22 success + 14 error observations, reproduced
  byte-identically) plus the Flash implementer's tests-first slice,
  merged and freshly verified by the main session: full suite 785 Racket
  checks (declaration-pattern suite 73), loader 57, historical 23 + 20,
  Python 13, `git diff --check` clean. **The pinned `81prim.mud` loads in
  full** (8/8 expressions, `PSETG` installs with its
  `<LIST [REST ATOM]>` declaration); the `77loadall.mud` chain completes
  **10 expressions** and stops at `77defs.mud` expression 1 on the
  unassigned global `MUDDLE` (`<AND <L? ,MUDDLE 100> ...>`, execute
  stage) — the next source dependency, alongside the `MEMQ` primitive
  `PSETG` invokes. Architect decisions: strict `DECL?` arity over
  Confusion's surplus tolerance; multi-pattern REST payload derived from
  Confusion's loop; structured heads restricted to
  LIST/VECTOR/UVECTOR/TUPLE.
- **D2 state (implemented, main-session-verified):** Confusion reference evidence recorded by the
  `glm-5.3-flash:cloud` reference-investigator subagent (18 success + 10
  error observations; independently reproduced byte-for-byte by the main
  session before commit `c015e8a`; see
  `docs/evidence/M2/SEGMENTS.md`). Key semantics: left-to-right element
  evaluation with splice flattening, LIST tail-sharing for final LIST
  segments (observable via PUT), no re-evaluation of FORM-argument splices,
  quoted segments stay data, `ILLEGAL-SEGMENT` errors for standalone and
  non-structured results, `![` is UVECTOR syntax not segment syntax.
  The Flash implementer produced `feat/m2-segment-impl` (tests `81d8286`,
  implementation `006674d`); the main agent reviewed the full diff, merged
  it (`b0af6b8`), and freshly re-ran all suites green: 701 Racket checks,
  loader 57, historical 23 + 14 assertions, reader sweep 36/36. The pinned
  load now completes **three expressions** and fails at the D3 barrier
  (`DECL 11:9: unsupported declaration pattern LIST` in `PSETG`).
  Architect decisions recorded in `docs/SEMANTICS.md`: interpreted
  call-argument splicing follows the manual over the reference's
  non-splicing interpreted path; eager interpreted segment-payload
  evaluation is a recorded, unobserved-case divergence.
- **Flash subagent routing (verified 2026-11-19):** provider accepts
  `glm-5.3-flash:cloud` (added to the Ollama Claude integration model list;
  backup at `~/.ollama/config.json.bak-20261119`); a headless
  `claude -p --model glm-5.3-flash:cloud` launch executed a real tool call
  with its transcript recording `"model":"glm-5.3-flash"`. In-session Agent
  type pickup of the new `.claude/agents` definitions needs a session
  restart, so in-session delegation uses user-approved scoped headless
  launches (allowlist: repo file Read/Write/Glob/Grep +
  `sha256sum`/probe `PYTHONPATH` commands, no permission-mode override).
- **Changed files (uncommitted on `feat/m2-segment`):**
  `docs/evidence/M2/SOURCE-EXECUTION.md` (stale `#DECL`-blocker inventory
  reconciled), `docs/STATUS.md` (header), this file.
- **Tests last executed (2026-11-19, fresh, on `main` `f87d160`):** full
  Racket suite 626 passed; loader 57; `make test-historical` 23 VFLOAD + 10
  declaration assertions; Python 13; `git diff --check` clean; PR #45 CI green
  on all three checks pre-merge and post-merge. Environment notes:
  loader/historical tests need writable `/tmp` (run outside the per-command
  sandbox); in-sandbox Racket needs `PLTCOLLECTS=":$PWD"`; the smoke CI
  container does not provision `.cache/upstream/`, so pinned-source
  assertions live only in `make test-historical` (reference workflow).
- **First failing source construct (historical, D3 era):** the unassigned
  global `MUDDLE` in `77defs.mud` expression 1 (`<AND <L? ,MUDDLE 100>
  ...>`, execute stage) — `81prim.mud` now loads in full; invoking the
  installed `PSETG` stops at `<MEMQ .FOO .PL>` (no MEMQ primitive yet).
- **Known semantic decisions:** see `docs/SEMANTICS.md` (M2 D1 section) and
  `docs/evidence/M2/DECLARATIONS.md`; deviations: attached-declaration
  enforcement follows the manual over non-enforcing pinned Confusion;
  `DECL?` false payload follows Confusion (`#FALSE (value pattern)`).
- **D4 state (merged, historical):** `MUDDLE` seeded as FIX `101` per the
  reference, interned in each session's atom space (PR #52); at D4 close
  the chain completed **twelve** expressions and stopped at
  `77defs.mud` expression 3 (`<PUT RAPPLIC DECL '...>>` — atom-property
  PUT, the next dependency). Fresh suites at that point: 802 Racket
  checks (muddle suite 9), loader 57, historical 23 + 20, Python 13,
  `git diff --check` clean. **The pinned reference loads the entire
  12-file chain to `DONE` — the concrete parity target.**
- **Full evidence:** `docs/evidence/M2/DECLARATIONS.md` (D1 slice),
  `docs/evidence/M2/SESSION-RECOVERY-2026-11-19.md` (recovery),
  `docs/evidence/M2/SOURCE-EXECUTION.md` (live execution inventory),
  `docs/evidence/M2/reader-sweep.json` (current sweep; frozen M0 sweep stays
  at `docs/evidence/M0/reader-sweep.json`).
