# Development handoff — MDL on Racket

Durable cross-session state. Update at every meaningful checkpoint; link to
evidence instead of duplicating logs. Last updated 2026-11-19 (post-D1 merge,
D2 in progress).

- **Milestone / gate:** M2. G0/G1/G2 PASS and **M2-D1 merged**; integrated
  M3-style gate NOT RUN. M2 milestone NOT YET PASS.
- **Active issues/PRs:** [PR #49](https://github.com/quaat/mdl-racket/pull/49)
  (D2 SEGMENT) — review findings fixed, CI green on head `c4a1d63`,
  **awaiting maintainer merge decision**;
  [PR #47](https://github.com/quaat/mdl-racket/pull/47) (Flash subagent
  definitions) green, **awaiting maintainer merge decision**; issue #44
  closed (D1 merged); issue #46 implemented (PR #49); issue #48 (D3
  structured declaration patterns) **implemented and main-session-verified**
  on stacked branch `feat/m2-decl-patterns` (Flash subagent branch
  `feat/m2-decl-patterns-impl` merged; reference evidence `325bc09`,
  implementation merge on top) — D3 PR to open next.
- **Latest integrated commit:** `f87d160` on `main` (merge of PR #45,
  declarations; post-merge CI green, run 44615298096). Local `main` is
  up to date.
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
- **First failing source construct:** the unassigned global `MUDDLE` in
  `77defs.mud` expression 1 (`<AND <L? ,MUDDLE 100> ...>`, execute stage)
  — `81prim.mud` now loads in full; invoking the installed `PSETG` stops
  at `<MEMQ .FOO .PL>` (no MEMQ primitive yet).
- **Known semantic decisions:** see `docs/SEMANTICS.md` (M2 D1 section) and
  `docs/evidence/M2/DECLARATIONS.md`; deviations: attached-declaration
  enforcement follows the manual over non-enforcing pinned Confusion;
  `DECL?` false payload follows Confusion (`#FALSE (value pattern)`).
- **D4 state (reference evidence recorded, verified, committed `9cdb8e3`
  on stacked branch `feat/m2-muddle`):** `MUDDLE` is the FIX `101`,
  interpreter-supplied — the 77defs.mud:1 guard `<L? ,MUDDLE 100>` is
  false, `AND` short-circuits, and `USE` (unbound in the reference) never
  runs; `RAPPLIC` stays unassigned through the whole chain (77defs.mud:3
  PUTs the DECL *property* on the atom — the next-next dependency is
  atom-property PUT); `MEMQ` returns the tail sublist on identity match,
  `#FALSE ()` on miss. **The pinned reference loads the entire 12-file
  `77loadall.mud` chain to completion with zero errors — that full-chain
  transcript is the concrete parity target for the M2 gate.** Current
  parity gap: 10 completed expressions vs the reference's full DONE.
- **Exact next action:** land D3 (PR #50: CI + independent review +
  maintainer approval), then the D4 implementation on `feat/m2-muddle`
  (bind `MUDDLE := 101` as a reference-backed session default, advance
  the chain, record the next blocker — likely atom-property PUT at
  77defs.mud:3, then `MEMQ` for PSETG execution). Obtain maintainer
  merge decisions for PR #47 and PR #49 when ready.
- **Full evidence:** `docs/evidence/M2/DECLARATIONS.md` (D1 slice),
  `docs/evidence/M2/SESSION-RECOVERY-2026-11-19.md` (recovery),
  `docs/evidence/M2/SOURCE-EXECUTION.md` (live execution inventory),
  `docs/evidence/M2/reader-sweep.json` (current sweep; frozen M0 sweep stays
  at `docs/evidence/M0/reader-sweep.json`).
