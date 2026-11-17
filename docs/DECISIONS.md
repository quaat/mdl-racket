# Architecture decision records

## ADR-0001: Racket custom language, not a new adventure engine

**Decision:** Implement a source-located MDL reader plus semantic translator/
compatibility runtime. Preserve original game source and command parser.

**Why:** Lexical resemblance to Lisp is not enough; mutable structure aliasing,
false values, and activation records require documented compatibility work.

**Alternatives:** direct Clojure port; full historical MDL interpreter;
Confusion server as final implementation; remaking puzzles in TypeScript.

**Consequence:** initial prototype is smaller than a playable game. Compiler
must error on unknown constructs; support progresses in verified increments.

## ADR-0002: Confusion as differential oracle

**Decision:** Use pinned `heasm66/mdlzork` patched Confusion as the native
reference. Keep separate from MIT historical original sources.

**Why:** Existing playable reconstruction supplies missing 1977 modules.

**Consequence:** A discrepancy against historical documentation must be
investigated; Confusion is practical but not necessarily definitive.

## ADR-0003: Server-backed browser delivery first

**Decision:** Defer in-browser Racket/WASM until the engine is proven native.

**Why:** Racket browser tooling does not provide a verified drop-in path for
this custom language, and game semantics dominate initial risk.

**Consequence:** Web session service can wrap an isolated Racket engine; a
standalone client is a separately gated feasibility study.

## ADR-0004: M0 reference protocols and reader scope

**Decision:** Treat `;` as a comment on one MDL object; accept both `!]` and
bare `]` for uvector input; retain computed `GVAL` as an AST node and reject
its compilation in M0. Match game prompts only at the start of a line. Probe
the promptless native REPL with one local process per case, ending in `<QUIT>`.

**Why:** The 1977 source and MDL manual show these lexical forms. The Confusion
banner contains `<WARRANTY>` and `<COPYING>`, which caused false PTY prompt
matches. The bare REPL emits no prompt, while `<QUIT>` yields clean exit 0.

**Consequence:** Reader parse coverage is 36/36 selected text files, with
comments' historical associations still omitted from the AST. A parse result
does not imply evaluation support. The golden game capture includes a build
timestamp in the Confusion banner and records SIGHUP cleanup after the fifth
command; future comparisons must account for the documented protocol.

## ADR-0005: Modern compiler compatibility for pinned Confusion

**Decision:** Build the exported Confusion copy with `-include cstdint` in
`CXXFLAGS`. Keep the upstream checkout and exported source bytes unchanged.

**Why:** The Ubuntu 24.04 CI compiler rejects `uint64_t` in `macros.hpp`
because that header does not include `<cstdint>`. The local older compiler
accepted the same pinned source through a transitive include. Explicitly
supplying the standard header fixes the toolchain dependency without editing
GPLv3 source in the MIT-0 harness.

**Consequence:** The native binary hash changes on rebuild because Confusion
embeds compile time in its banner. The golden transcript must be reviewed
against the new build, with toolchain/version differences recorded.

## ADR-0006: First-class FALSE in the bootstrap runtime

**Decision:** Represent MDL FALSE with a dedicated Racket structure carrying
its unevaluated LIST payload. Only this structure is false in MDL truth tests;
empty FALSE values share one canonical instance for MDL `==?` identity;
host booleans reaching those tests raise an error. Preserve values and
evaluation order in `NOT`, `AND`, `OR`, and `COND`. Return MDL atoms or FALSE
from the small set of existing predicate builtins. Recognize `TYPE` only for
FALSE and placeholder ATOM values.

**Why:** The MDL manual's chapter 8 and ten pinned Confusion probes agree on
FALSE payloads, `NIL` truth, return values, and short circuit behavior.

**Consequence:** The M0 fixture now stores an MDL FALSE instead of Racket
`#f`. Display, mutable payload views, general type operations, and atom
identity remain unsupported or approximate. The change does not alter the
reference source or game rules.
