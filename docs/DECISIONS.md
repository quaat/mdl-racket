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

The compiler binds each direct FALSE literal once per compiled top-level
expression. A function closure thus reuses its source literal across calls,
while separately written nonempty literals keep distinct identities.

**Why:** The MDL manual's chapter 8 and ten pinned Confusion probes agree on
FALSE payloads, `NIL` truth, return values, and short circuit behavior.

**Consequence:** The M0 fixture now stores an MDL FALSE instead of Racket
`#f`. At this decision's point, display, mutable payload views, general type
operations, and atom identity remained unsupported or approximate. ADR-0007
addresses the first atom identity slice. The change does not alter the
reference source or game rules.

## ADR-0007: Identity-bearing atom and OBLIST values

**Decision:** Give each MDL ATOM its own identity, PNAME, and optional OBLIST
membership. Ordinary reader names intern in the current default atom space;
`!-` trailers select a named OBLIST. `MOBLIST` reuses an OBLIST by name atom.
`ATOM` creates an uninterned value; `LOOKUP`, `INSERT`, and `REMOVE` manage
membership explicitly. Keep the atom space parameterizable for session
isolation. Quoted atom literals compile through the same interning operation.

**Why:** The MDL manual's chapter 15 and seven pinned Confusion probes agree
on identity, membership, trailer, and lookup behavior. Racket symbols alone
cannot represent two atoms with the same PNAME in different OBLISTs.

**Consequence:** The new atom and OBLIST structures are opaque so `==?` and
`=?` both compare atom identity. Printing still uses Racket debug notation,
and full OBLIST bucket geometry, dynamic `.OBLIST`, and associations remain
outside this slice. Confusion prints 17 default buckets while the manual says
13; no bucket count behavior is claimed. No upstream or game source changed.

## ADR-0008: Mutable LIST tails and array views

**Decision:** Represent LIST-primtype values as mutable Racket pair chains and
VECTOR/UVECTOR values as a typed view over shared vector storage. `REST`
advances a LIST tail pointer or array view offset; `PUT` mutates through the
view and returns its input; `PUTREST` rewires a nonempty LIST head. A FALSE
payload is a LIST chain, and `REST` of FALSE returns a LIST view. Bind quoted
structured literals once per compiled source expression so function calls
retain their identity. Nested literal atoms use the atom space.

**Why:** Chapter 7 of the MDL manual and ten successful pinned Confusion
probes show shared tails, shared array storage, and identity-preserving
mutation. A separate Confusion UVECTOR type violation probe exits with an
error. Tests include 1-based access, boundary errors, aliasing, and a
deterministic property sweep over LIST lengths 2 through 10.

**Consequence:** This is a narrow sequence subset. Dynamic type tags,
GROW/BACK/TOP, segments, STRING/BYTES views, and general printing remain
unsupported. `GET` is not treated as `NTH`; it needs its own semantics.
Cycles made by `PUTREST` raise on `LENGTH` in this implementation. No game
rules, upstream sources, or GPLv3 code were changed.
