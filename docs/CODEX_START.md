# Current Codex starting point — M2 source execution

Read `AGENTS.md`, `docs/PLAN.md`, `docs/STATUS.md`, `docs/SEMANTICS.md`,
`docs/TESTING.md`, `docs/PROVENANCE.md`, and `docs/DECISIONS.md` before
development. Inspect the relevant source and tests. The first unmet milestone
is M2; M0 and M1 passed. The prior M2 macro and CI slices are merged.

The [G0 source-readiness report](evidence/M2/SOURCE-READINESS.md) identifies
the actual historical load barriers. [G1](evidence/M2/SOURCE-LOADER.md) adds
the local source loader and shared MDL session. Begin G2 by invoking an
unmodified pinned historical definition through that loader; the `VFLOAD`
definition in `77loadall.mud` is the first candidate. `#DECL` requires
researched semantics
and must not be silently ignored. The integrated M2 gate remains open until
coherent original definitions are executed and verified.

Use small issues and PRs, maintain reference and golden evidence, and follow
the gate discipline in `AGENTS.md`. Do not edit `.cache/upstream/`, substitute
game rules, expose a network REPL, or claim gameplay from reader coverage.
