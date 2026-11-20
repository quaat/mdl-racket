# Development handoff — MDL on Racket

Durable cross-session state. Update at every meaningful checkpoint; link to
evidence instead of duplicating logs. Last updated 2026-11-20 (D4 merged,
D5 reviewed locally on branch, G3 open).

- **Milestone / gate:** M2. D1 (PR #45), D2 (PR #49), D3 (PR #50), D4
  (PR #52), and the agent definitions (PR #47) are all **merged into
  `main`** (current main `419fc5c`); issues #44/#46/#48/#51 closed.
  Integrated G3 gate NOT RUN. M2 milestone NOT YET PASS.
- **Active issues/PRs:** issue **#53** (D5 atom-property `PUT`/`GET`) —
  reference evidence, implementation, focused tests, and independent review
  fixes are on `feat/m2-atom-props` (base `419fc5c`, prior D5 head
  `32a462d`). PR to open; no open PRs at the last GitHub check. Issue
  #11 was closed as completed on 2026-11-20.
- **D5 state (implemented, main-session-verified on
  `feat/m2-atom-props`):** Confusion reference evidence (18 success + 6
  deliberate-error observations; `docs/evidence/M2/ATOM-PROPS.md`) plus
  the implementation (commit `676f488`) and focused tests
  (`tests/atom_props_test.rkt`, commit `a3ce79f`). Independent review found
  the weak `eq?` item-key mismatch, structured two-arg PUT dispatch, and
  DECL alias/precedence gaps; review regressions and pinned Confusion
  evidence are under `atom-props-review-*`. Fresh suites: 864
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
- **Exact next action:** commit and push the D5 review fixes, open the D5 PR
  referencing issue #53, and run CI; then evaluate
  the integrated M2 G3 gate; then the `EMPTY?` slice for the original
  `NEWSTRUC` (create the issue from the recorded barrier at
  `77defs.mud` expression 15, delegate to the Flash implementer).
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
