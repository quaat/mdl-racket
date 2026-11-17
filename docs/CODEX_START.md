# First task to give Codex

Copy the instruction below verbatim into a Codex session with this repository
as its working directory, after creating your GitHub repository.

---

You are the lead developer of a preservation-focused Racket implementation of
historical MDL, with the December 1977 Zork as the first target. Follow
`AGENTS.md` and the milestone gates in `docs/PLAN.md`. Work on the **first unmet
milestone**; do not jump to browser UI or a replacement game engine.

**Immediate tasks:**

1. Inspect the project source and document versions/dependencies (`make doctor`).
   Verify or repair the starter Racket reader/compiler and execute `make test`.
   Record results honestly. The bootstrap code has NOT been Racket-tested by
   its author; treat it as a scaffold, not trusted production code.
2. Run `make sources`; confirm exact pinned SHAs and manifest, never modify
   the upstream checkout. Inspect all historical textual MDL files; run
   `scripts/mdl_check.rkt` and track line/column of unsupported syntax and
   parser failures. Extend the **reader only** to parse all files losslessly
   enough for AST inspection; add regression tests for each new construct.
3. Build native Confusion (`make reference-build`) and run the smoke scenario
   (`make reference-capture`). Fix PTY protocol handling if needed. Establish
   a verified, reviewable, reproducible transcript. Capture versions/hashes,
   exit behavior, and known randomness/time dependencies. Do not change the
   game rules to make the capture succeed.
4. Add a minimally invasive way to probe MDL primitive semantics against
   Confusion, preserving input/output and observed results. Prioritize MDL
   FALSE vs NIL, mutable `REST`/`PUT`, local/global binding, types, and
   nonlocal control flow; record findings in `docs/SEMANTICS.md`.
5. Update `docs/STATUS.md` and `docs/evidence/M0/REPORT.md` with exact commands,
   outputs, tests, deviations, blockers, and proposed M1 tasks. Open issues/
   PRs and write findings in comments when GitHub is available.

**Quality bar:** reproducibility, source fidelity, explicit unsupported
constructs, regression tests, and unambiguous PASS/FAIL/BLOCKED/NOT RUN gates.
Never claim a Zork port exists before the actual MDL game runs in Racket.

After M0 gate passes, propose M1 with an issue list and dependency graph; then
start the smallest approved semantic primitive (do not rewrite the game).

---

## Codex operational advice

- Grant the local Codex session network access if you want it to clone public
  repositories, install dependencies, and communicate with GitHub. The default
  sandbox may restrict these operations; request explicit approval for the
  narrowly scoped operation rather than silently skipping it.
- Use a writable workspace and an authenticated `gh` CLI if Codex is expected
  to create branches, issues, PRs, comments, and commits. Check `gh auth status`.
- Do not run Codex with broad, unsandboxed privileges just to solve a
  permissions issue. Fix directory ownership or use a scoped approval.
- A Codex session running locally has access only to tools, files, and
  permissions actually provided to it; this scaffold does not create remote
  communication automatically.
