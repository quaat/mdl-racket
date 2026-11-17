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

## ADR-0009: Type registry and shared structured casts

**Decision:** Store type registration in the parameterized atom space, keyed
by ATOM identity. Built-in types record their primitive storage type;
`NEWTYPE` registers a new tag with a pre-existing primitive type. `CHTYPE`
for LIST/VECTOR/UVECTOR storage wraps that storage with a new type tag,
preserving mutation and identity after a round trip. FALSE-to-LIST casts
share the payload chain. `REST` drops a user type tag to the primitive type.
Reject primitive mismatches, dangerous built-in targets, and WORD bit
reinterpretation explicitly.

**Why:** Chapter 6 of the MDL manual and nine pinned Confusion probes
corroborate TYPE/PRIMTYPE/TYPEPRIM distinction, NEWTYPE registration,
shared data, and type-sensitive identity. Confusion reports OBLIST's
primitive type as UVECTOR. Tests cover aliasing and negative conversion
boundaries.

**Consequence:** General type declarations, `#NAME` reader notation,
PRINTTYPE/EVALTYPE/APPLYTYPE, and numeric WORD reinterprets remain open.
The Racket type registry contains only types proven for this subset; it is
not a complete historical table. No upstream or game rules changed.

## ADR-0010: Atom-keyed local and global binding frames

**Decision:** Store global values under ATOM identity. A separate dynamic
stack of local frames binds simple function parameters for the duration of
each call. `SET` updates the nearest active binding, or the persistent root
local frame when no parameter binds the ATOM. Explicit `GVAL` and `LVAL`
report unassigned errors; `VALUE` checks local before global. FORM operator
resolution checks global before local, including replaceable builtins.
`GUNASSIGN` installs an unassigned marker. Computed GVAL and computed
SET/SETG operands now evaluate to an ATOM.

**Why:** Chapters 4 and 5 of the MDL manual specify separate values and
dynamic parameter binding. Nine pinned Confusion cases corroborate local
shadowing/restoration, free assignments, atom identity, VALUE precedence,
and GUNASSIGN. Racket tests check the same behavior and errors.

**Consequence:** `UNASSIGN` is still unsupported because this pinned
Confusion build reports its own operator as unbound, despite the manual
documenting it. Explicit ENVIRONMENT arguments, complex formal parameters,
PROCESS-specific local stacks, and compiled UNSPECIAL behavior remain open.
The Makefile refreshes the linked `#lang mdl` module to avoid stale compiled
exports during local tests. No upstream or game rules changed.

## ADR-0011: Historical 36-bit FIX/WORD over native Confusion width

**Decision:** Use the manual's signed 36-bit FIX range and 36-bit WORD mask.
Out-of-range FIX literals become FLOAT when representable; FIX arithmetic
checks every intermediate result for overflow. WORD casts reinterpret the
36-bit pattern, and bit/field operations mask results to 36 bits. Recognize
`#WORD` with a numeric payload as one source-located reader node. Keep ROT
unsupported until a reference implementation can corroborate it.

**Why:** Chapters 2, 3, and 18 of the MDL manual specify these rules.
Nine pinned Confusion probes corroborate in-range arithmetic and low-bit
operations, but reveal Confusion's native 64-bit WORD output, out-of-range
FIX values, a zero result for zero-argument division (the manual says one),
and no ROT global binding. These are explicit reference deviations, not
reasons to change the preservation target.

**Consequence:** The numeric slice is not byte-for-byte equivalent to
Confusion at the documented width/identity boundaries. PDP-10 FLOAT
precision and bit layout, machine overflow switches, ROT, and the complete
arithmetic library remain unsupported. No upstream source or game rule
changed; no GPLv3 reference code was copied.
