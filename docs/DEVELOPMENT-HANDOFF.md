# Development handoff — MDL on Racket

Durable cross-session state. Update at every meaningful checkpoint; link to
evidence instead of duplicating logs. Last updated 2026-11-19 (post-D1 merge,
D2 in progress).

- **Milestone / gate:** M2. G0/G1/G2 PASS and **M2-D1 merged**; integrated
  M3-style gate NOT RUN. M2 milestone NOT YET PASS.
- **Active issues/PRs:** [PR #49](https://github.com/quaat/mdl-racket/pull/49)
  (D2 SEGMENT, branch `feat/m2-segment`, head `e26f3a8`) — independent
  review returned REQUEST_CHANGES (two verified semantic defects + a
  coverage gap); all findings fixed with regression tests and pushed;
  716 Racket checks green locally; CI re-running on the fix head; merge
  gated on green CI + maintainer approval;
  [issue #48](https://github.com/quaat/mdl-racket/issues/48) (D3 structured
  declaration patterns, the current load blocker) — reference evidence
  recorded, verified, and committed on stacked branch
  `feat/m2-decl-patterns` (`325bc09`), implementation held until the D2
  review lands (shared `mdl/runtime/core.rkt` ownership);
  [PR #47](https://github.com/quaat/mdl-racket/pull/47) (Flash subagent
  definitions) green, **pending maintainer merge decision**; issue #44
  **closed** (D1 merged).
- **Latest integrated commit:** `f87d160` on `main` (merge of PR #45,
  declarations; post-merge CI green, run 44615298096). Local `main` is
  up to date.
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
- **First failing source construct:** the compound declaration pattern
  `<LIST [REST ATOM]>` in `PSETG` (`81prim.mud:11:9`, runtime stage,
  expression 3) — the `!`-splice at 16:46 now compiles (D2).
- **Known semantic decisions:** see `docs/SEMANTICS.md` (M2 D1 section) and
  `docs/evidence/M2/DECLARATIONS.md`; deviations: attached-declaration
  enforcement follows the manual over non-enforcing pinned Confusion;
  `DECL?` false payload follows Confusion (`#FALSE (value pattern)`).
- **Exact next action:** confirm CI green on PR #49 head `e26f3a8`, then
  merge with maintainer approval; then launch the D3 Flash implementer on
  `feat/m2-decl-patterns` (the `[REST ...]` structured-pattern slice,
  issue #48 — Confusion's DECL? implements the subset, so the reference
  backing is direct), then retry the full `77loadall.mud` load and record
  the next blocker. Key D3 reference facts: the PSETG pattern accepts (),
  (A), (A B) and rejects (A 1) with #FALSE (1 ATOM); overall-type
  mismatches return bare #FALSE () while element mismatches carry
  (value pattern) — see docs/evidence/M2/DECLARATION-PATTERNS.md.
- **Full evidence:** `docs/evidence/M2/DECLARATIONS.md` (D1 slice),
  `docs/evidence/M2/SESSION-RECOVERY-2026-11-19.md` (recovery),
  `docs/evidence/M2/SOURCE-EXECUTION.md` (live execution inventory),
  `docs/evidence/M2/reader-sweep.json` (current sweep; frozen M0 sweep stays
  at `docs/evidence/M0/reader-sweep.json`).
