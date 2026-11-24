# Architecture decision records

## ADR-0043: Session-owned interrupt scheduling before GC integration

**Decision (2026-11-22, issue #104, before implementation):** Extend each
MDL atom-space with a scheduler state containing interrupt level and pending
occurrences. Event sources report already evaluated arguments at explicit
safe points; the dispatcher calls the existing evaluated-argument function
application path. Eligible occurrences dispatch immediately; others queue
in order. Dynamic cleanup restores the prior level on normal return and
exceptions. A deterministic test-only event source verifies scheduling
independently of host GC. `INT-LEVEL`, `ENABLE`, and `DISABLE` expose the
source-independent manual behavior.

**GC investigation:** Installed Racket is v7.9 [bc]. `collect-garbage`,
`current-gc-milliseconds`, and `current-memory-use` exist. Host collection
is real, but its return value does not provide historical MDL reclaimed
words. Its timing and allocation triggers differ from MDL's. Arbitrary MDL
callbacks must run after collection at a safe boundary. The original
`77rooms.mud:78–104` installs and removes DIVERT/GC handlers;
`DIVERT-FCN` reattaches `GC-HAND`, and `GC-FCN` removes it. The manual
classifies GC and DIVERT-AGC as internal interrupts. GC delivers FLOAT
seconds, FIX cause (explicit `<GC>` is 1), and ATOM initiator. DIVERT-AGC
delivers FIX requested words and ATOM initiator before a deferrable
automatic collection.
The [Racket GC reference](https://docs.racket-lang.org/reference/garbagecollection.html)
says `collect-garbage` returns void and host memory use is estimated in bytes.
Its [timing API](https://docs.racket-lang.org/reference/time.html) reports
collector processor milliseconds. Racket's
[will executors](https://docs.racket-lang.org/reference/willexecutor.html)
report object finalization, not every collection, and must be polled or run
by a thread. Its [unsafe collector callbacks](https://docs.racket-lang.org/foreign/Garbage_Collection_Callbacks.html)
cannot allocate managed memory, so they cannot directly execute MDL code.
Pinned Confusion source itself marks `GC` only partially implemented:
`mdl_builtin_eval_gc` calls Boehm `GC_gcollect()` and returns `T`, whereas
the manual requires reclaimed MDL words. Its `BLOAT` implementation calls
its values bogus and returns the requested FIX or 65536. Those routines
are useful evidence of the reference limitation, not code or semantics to
copy into the Racket runtime. This project has not changed either upstream
source tree.

**Rejected:** Equating every Racket GC to historical MDL GC invents event
timing and cause codes. Accepting `EVENT "GC"` without delivery silently
loses callbacks. Fabricated reclaimed-word counts for `<GC>` or `BLOAT`
would corrupt observable MDL values.

**Boundary:** This first slice proves the dispatcher. GC registration stays
guarded pending a defensible explicit collection operation and a separate
decision on automatic MDL allocation pressure. Pinned Confusion stubs
interrupt registration and offers no usable delivery oracle; manual
semantics and focused assertions supply the evidence here.

**Gate B options after foundation:** (1) Use host `collect-garbage` and
estimate reclaimed MDL words from Racket bytes. This is measurable host
behavior but does not count MDL words or reproduce the historical return
contract, so it cannot be presented as runtime equivalence. (2) Add a
bounded session-owned ledger for MDL allocation sizes and reachable roots,
then use a real host collection at an explicit `<GC>` safe point while
reporting an honest MDL-ledger reclaimed count. This needs a separate
prototype and tests for object identity, sharing, cycles, and roots before
it can be accepted. (3) Copy Confusion's `T`/bogus-value stubs; rejected as
false semantics. The recommended next action is a small ledger feasibility
probe on the original `77rooms.mud` GC/BLOAT call paths. Keep `EVENT "GC"`
guarded until that probe demonstrates executable post-collection delivery
and a defensible return value.

## ADR: Represent user event registrations without dispatch (M3 issue #102)

**Decision:** Implement session-owned IHEADER and HANDLER objects and the
manual's user event registration/removal operations. Reject external
event registration and interrupt dispatch until callback scheduling is
implemented. In particular, `EVENT "GC"` must not install a handler
that would silently fail to run on garbage collection.

**Why:** Pinned Confusion stubs EVENT, HANDLER, OFF and ON as `T` even on
bad arguments, and has no usable INTERRUPT. Copying that behavior would
advance source loading while abandoning event semantics. The manual
provides a real object model and identity/removal rules.

**Consequence:** This registration slice advances only to the first
external event dependency. M3 remains incomplete, and no game or
interrupt parity is claimed.

## ADR: Conjoin duplicate ATOM Patterns in one attached DECL (M3 issue #100)

**Decision:** If an ATOM appears in more than one pair of the same attached
`#DECL`, retain each normalized Pattern and check all of them in source
order. Continue rejecting duplicate VALUE declarations in this slice.

**Why:** The unchanged original `BALLOON` source declares `M` twice. The
manual does not state a duplicate precedence rule, and pinned Confusion
does not enforce attached checks. Conjunction preserves both written
constraints. The later `M` Pattern is narrower than the earlier one.

**Consequence:** This is a documented inference, pending a stronger
historical oracle. It permits the original function definition without
weakening later checks or editing upstream source.

## ADR: Defer unresolved TYPE atoms in attached declarations (M3 issue #98)

**Decision:** Retain an unresolved TYPE atom in an attached declaration's
normalized Pattern. Resolve it at each actual declaration check. Keep
explicit `DECL?` and positional declaration validation immediate.

**Why:** The original `77act1.mud` defines a function with `PRSOBJ` in
`#DECL` before any registered type or DECL association of that name exists.
Pinned Confusion accepts the definition and invocation but rejects explicit
`DECL? PRSOBJ`; its attached checks are absent. Retaining the unresolved
name lets source definitions load while the Racket runtime still enforces
the manual's declaration checks when the function runs.

**Consequence:** Unknown names remain strict at use time, and a later NEWTYPE
or DECL association can make a previously defined Pattern valid. The source
frontier can advance without changing upstream bytes.

## ADR: Lazy NTH declaration matching for M3 issue #96

**Decision:** Normalize `[n pattern ...]` as a counted sequence in the
required prefix. Unfold one pattern while consuming each actual element,
without constructing `n` copies. Require a positive FIX count and at least
one pattern. Keep the manual's required-length rule for attached declarations.

**Why:** The original source uses `[3 ANY]`; a large valid count must reject a
short value without large allocation. Pinned Confusion's attached declaration
accepts a short vector, although its explicit `DECL?` and the manual reject
short repeated prefixes. That discrepancy is recorded in SEMANTICS.md.

**Consequence:** The runtime deliberately differs from that one attached
Confusion observation. NTH remains strict for malformed syntax and is matched
incrementally for LIST and array values.

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

## ADR-0012: Scoped PROG activation and sequential auxiliary bindings

**Decision:** Compile unnamed `PROG` to a Racket escape continuation and a
separate dynamic auxiliary frame. Evaluate each auxiliary initializer before
installing that variable's new binding; install an explicit unassigned marker
for bare auxiliary atoms. Bind the escape continuation for the PROG body and
initializers. A plain `DEFINE` call clears the implicit RETURN target before
its body, so bare `RETURN` inside a helper cannot exit a caller's PROG. Reject
named activations and explicit target RETURN at compilation.

**Why:** The MDL manual's chapters 9–10 and nine pinned Confusion probes show
normal value, sequential initialization, shadowing, frame restoration, and
early/default/nested returns. Three expected-error probes distinguish
unassigned auxiliaries and RETURN across a function boundary. Confusion
crashes with signal 11 when RETURN occurs in an auxiliary initializer, while
the manual specifies an activation before auxiliary binding; the Racket
slice follows the manual on that case and records the discrepancy.

**Consequence:** This models one activation boundary without claiming general
MDL continuation semantics. REPEAT, AGAIN, GO, UNWIND, named activations,
complex function formals, and source linking remain separate M2 work. The
reference's error printer and Racket error messages differ. No original game
source, rule, public license, or GPLv3 code changed.

## ADR-0013: Owned activation frames before broader control flow

**Decision:** Represent each unnamed PROG entry with an opaque activation
frame carrying a function-invocation owner, escape destination, and live
state. Keep active frames on a dynamic stack. A bare RETURN selects the nearest
frame owned by the current function invocation. A plain DEFINE call creates a
new owner. Normal exit, RETURN, and exception unwinding invalidate the frame.
The compiler uses runtime scope helpers instead of a single dynamically
scoped continuation parameter.

**Why:** The manual treats an ACTIVATION as one particular evaluation and says
bare RETURN targets a PROG in the current function. Existing pinned Confusion
cases distinguish nested PROGs and called-function boundaries. New Racket
tests verify frame identity, stale-frame rejection, and cleanup after normal,
RETURN, and error exits.

**Consequence:** This hardens the representation of the existing unnamed
PROG subset. Named activations, explicit target RETURN, REPEAT, AGAIN, GO,
and UNWIND remain unsupported; no new semantic parity is claimed. Cyclic
equality is tracked separately as issue #23. No upstream source, game rule,
public license, or GPLv3 reference code changed.

## ADR-0014: Bounded structural equality for cyclic values

**Decision:** Keep `=?` identical-object fast paths and finite structural
comparison, including repeated but acyclic shared substructures. Track pairs
of distinct structured objects only while their comparison is active. If a
pair recurs on that path, raise an explicit unsupported-cyclic-comparison
error. Preserve FALSE when structure differs before repetition; leave `==?`
identity behavior unchanged.

**Why:** The manual defines structural equality and permits cyclic LIST and
VECTOR objects, but gives no finite result for two distinct repeated cycles.
Pinned Confusion returns T for self-comparison, FALSE for cycles with an
immediate difference, times out on distinct equal-content LIST cycles, and
exits by signal 11 on distinct self-referencing VECTORs. A guessed general
coinductive equality rule would be an unverified semantic addition.

**Consequence:** `=?` now terminates deterministically on tested cyclic
values, but deliberately reports a limitation for unresolved distinct cycles.
This does not establish full cyclic equality parity. No upstream source,
game rule, public license, deployed service, or GPLv3 code changed.

## ADR-0015: Restart an activation body without rebinding auxiliaries

**Decision:** Use the existing owned activation frame for unnamed PROG and
REPEAT. Bind auxiliaries once inside the frame; expose an internal restart
escape around each body evaluation. Bare AGAIN invokes that escape for the
nearest frame owned by the current function. PROG returns its final body
value; REPEAT iterates after normal body completion until RETURN exits.

**Why:** The manual defines REPEAT as PROG with implicit final AGAIN and says
AGAIN does not repeat auxiliary binding. Five finite pinned Confusion probes
confirm the core loop, initializer retention, PROG restart, explicit bare
AGAIN in REPEAT, and nested RETURN.

**Consequence:** Restart uses tail iteration and preserves mutable local
bindings. Named activations, explicit target transfer, GO, UNWIND, and
AGAIN from auxiliary initializers remain outside this slice. No
upstream source, game rule, public license, deployed service, or GPLv3 code
changed.

## ADR-0016: Opaque named activations and explicit transfer validation

**Decision:** Bind an opaque ACTIVATION value around a named PROG or REPEAT
before auxiliary initialization. Keep the frame on the dynamic stack while
the body is active and mark it inactive when the evaluation ends. Explicit
RETURN/AGAIN targets may select a live enclosing PROG/REPEAT frame across a
called function boundary; validate both type and membership in the current
dynamic stack before invoking its escape or restart continuation. Bare
transfers retain current-function ownership rules.

**Why:** The manual defines ACTIVATION identity and lifetime, named binding,
and explicit target transfers. Eleven finite pinned Confusion probes confirm
type, primitive FRAME type, binding order, shadowing, nested and cross-function
transfer. Confusion crashes or reports frame errors on malformed and stale
targets, so copying its failure mode is not a semantic requirement.

**Consequence:** Named PROG/REPEAT and explicit targets are now available in
the tested subset. Function activation formals, GO, UNWIND, `LEGAL?`, and
general FRAME operations remain unsupported. No upstream source, game rule,
public license, deployed service, or GPLv3 code changed.

## ADR-0017: String-marked formal sections and a TUPLE primitive type

**Decision:** Parse `DEFINE` formal lists by the pinned Confusion section
state machine: required atoms, then `"OPT"`/`"OPTIONAL"`, then one
`"ARGS"` or `"TUPLE"` rest binding, then `"AUX"`/`"EXTRA"` locals. Markers
are STRINGs only; an ATOM named AUX is an ordinary formal. Two-element
`(ATOM expression)` defaults evaluate left to right in the growing function
frame. Unsupplied optionals and bare AUX locals carry the PROG-style
unassigned marker. TUPLE binds remaining arguments as a value with TYPE and
PRIMTYPE TUPLE — its own primitive type — while ARGS binds a LIST; REST of a
TUPLE stays a TUPLE. Compile every compiled function as one variadic Racket
lambda whose arguments flow through a runtime binder that raises the
historical `TOO-FEW/TOO-MANY-ARGUMENTS-SUPPLIED` and `BAD-ARGUMENT-LIST`
error names. Reject malformed and unsupported formal lists at compile time.

**Why:** Confusion's `mdl_bind_args` (GPLv3, read as reference only) fixes
the section order, rest-binding behavior, and error names, and 24 focused
Confusion probes corroborate defaults, unassigned reads, frame restoration,
TUPLE typing, equality, and ARGS-vs-TUPLE. The 1977 reconstruction sources
use these sections pervasively, including `"TUPLE"` before `"AUX"` with
initializers.

**Consequence:** Formal-list shape errors surface earlier than in Confusion,
which validates at call time and kills the process; this is a documented
stricter deviation, as is the earlier duplicate-name rejection. TUPLE
becomes a registered built-in type whose CHTYPE conversions fail
explicitly. Activation formals (`"NAME"`, `"ACT"`, `"BIND"`, `"CALL"`),
quoted formals, GO, and UNWIND remain unsupported. No upstream source, game
rule, public license, deployed service, or GPLv3 reference code changed.

## ADR-0018: Function activations, manual-based GO, and flagged-wind UNWIND

> **Superseded in part by ADR-0051 (issue #139):** UNWIND cleanups no longer
> run for raised errors. The "or an error" clause and the error paragraph
> under **Why** below are historical. Their probe was misread, as ADR-0051
> explains.

**Decision:** Give every activation frame a kind. PROG/REPEAT frames are
eligible bare targets as before; function activations created for a leading
activation ATOM or `"NAME"`/`"ACT"` marker are only reachable by explicit
RETURN/AGAIN, matching the reference's LASTPROG lookup. A function
activation exists before formal binding, and explicit AGAIN to it re-runs
the body without re-binding. Compile PROG/REPEAT bodies as ordered items
where top-level non-numeric atom nodes are labels skipped in normal flow;
GO resolves the nearest owned frame and jumps to the item after a label
through a per-item escape. Implement UNWIND as a flagged dynamic-wind whose
cleanup runs only when a transfer or an error crosses below it.

**Why:** Sixteen pinned Confusion probes corroborate activation formals,
AGAIN-without-rebinding, return-from-aux-initializer, and UNWIND transfer
semantics. Confusion has no GO and marks TAG unimplemented, so GO follows
the MDL manual chapter 10, the same manual-over-reference precedent as ROT.
Confusion's `mdl_error` bypasses UNWIND frames, so its observed error path
skips cleanups; the manual's FLOAD example documents cleanup on nonlocal
error unwinding, and the runtime follows the manual.

**Consequence:** GO has no differential reference; its tests are
manual-derived only. TAG values, `"BIND"`/`"CALL"` markers, and the FSUBR
`BIND` remain unsupported and fail explicitly. Bare atom nodes that carry
number or `#` reader tokens cannot be labels. No upstream source, game rule,
public license, deployed service, or GPLv3 reference code changed.

## ADR-0019: Runtime FORM data and caller-frame macro arguments

**Decision:** Compile raw call operands as MDL data alongside evaluation
thunks. Ordinary compiled procedures consume the thunks in order; MACRO
and interpreted quoted-formal FUNCTION values bind the data themselves.
Represent FORM as a LIST-primtype tagged value and evaluate macro expansion
results at the call site. Supplied plain formals and TUPLE rest arguments
evaluate in the saved caller locals and function owner; ARGS and quoted
formals retain raw operands. Give each interpreted invocation its own
function owner. Keep `EXPAND` to one top-level macro expansion.

**Why:** The MDL manual chapter 17 specifies two-stage macro evaluation,
while pinned Confusion probes confirm raw quoted operands, caller-frame
argument evaluation, TUPLE versus ARGS, nested expansion, and function
definitions produced by expansion. The new caller-frame and bare-RETURN
tests failed against the unfinished runtime draft before the fixes.

**Consequence:** Macro code can construct and evaluate FORM data on the
documented subset. Confusion observes caller locals during expansion even
though the manual says top-level; the runtime follows the observed reference
for this slice. Confusion's debug build evaluates a non-macro EXPAND input;
the runtime follows the manual's one-step behavior instead. Full formal-list
validation can report a malformed-list error before Confusion's arity error.
Compile-time expansion, declarations, source loading, and general APPLY
remain separate tasks. No upstream source, game rule, public license,
deployed service, or GPLv3 reference code changed.

**PR #35 review follow-up:** Keep a leading activation ATOM as its own field
on an interpreted FUNCTION or MACRO, bind it before parsed formals, and
reject a duplicate formal name. Encoding it as a prepended `"NAME"` marker
closed the required-formal section and rejected quoted arguments. The
runtime evaluator now accepts the empty MDL LIST (`'()`) as a PROG/REPEAT
auxiliary list, including named activations. Ten pinned Confusion probes
confirm these cases; see `docs/evidence/M2/MACROS.md#review-follow-up`.

## ADR-0020: Run CI in a digest-pinned minimal Racket image

**Decision:** Use the Racket project's `racket/racket:8.10-bc` minimal image
by immutable digest for both GitHub Actions jobs. Install only the Racket
libraries needed by the harness tests and the native tools needed by the
Confusion reference job. Share the Racket test command list between Make and
CI through `scripts/test_racket.sh`.

**Why:** The existing Ubuntu apt step repeatedly downloaded and installed
Racket and recommended documentation. One native apt run spent over 16
minutes in the dependency step. The minimal image pulls quickly in the
measured pilot and both workflows pass, including the source-lock check,
reader sweep, native build, and reference capture. `--no-install-recommends`
would remove the 36 MB documentation package but still download and install
the Racket package. A full Racket distribution image has a larger compressed
payload, and a custom prebuilt image would add a publication process.

**Consequence:** CI uses Racket 8.10 BC; local development may use another
version, so the full suite remains the compatibility check. The container
still fetches Git/native packages and Racket test libraries per run. The
image digest is fixed, while package repositories and action major tags can
change. Reference execution remains local to the CI runner and no raw
interpreter service is exposed. No upstream source, runtime semantics, game
rule, public license, or GPLv3 code was changed or copied.

## ADR-0021: Shared local MDL session and constrained FLOAD

**Decision:** Keep the existing parameterized runtime and create an explicit
local session object for globals, root local frame, atom/type space, namespace
and diagnostic records. Read, compile and evaluate one top-level node at a
time so later reader errors preserve earlier effects. Route `FLOAD` through
that loader in the same session;
return `"DONE"` on success. Resolve nested paths from the containing file and
require their canonical target to stay within the authorized source root.
Reject traversal, symlink escapes, cycles and excessive depth. Report partial
execution and the first failure through structured errors. Add source
positions to reader and compiler exceptions without changing their fail-closed
behavior.

**Why:** The unmodified `77loadall.mud` defines `VFLOAD` then calls it on
`81prim.mud`. Whole-program precompilation would block this valid ordering.
Pinned Confusion probes support successful `FLOAD` returning `"DONE"`,
repeated execution, and side effects surviving later failure. The existing
atom and type registry already lives in a parameterized atom space, so this
small session wrapper preserves the established semantics. The local source
root prevents historical file operations from reading arbitrary host files.

**Consequence:** Controlled multi-file fixtures load and the original
`77loadall.mud` reaches `81prim.mud`'s unsupported `#DECL` at line 3:9.
Confusion resolved a relative nested file from process cwd in the observed
probe; source-relative lookup is a documented local policy deviation. The
loader does not roll back side effects, emulate Confusion's interactive error
levels, expose a network evaluator, or implement full MDL filesystem semantics.
No upstream source or GPLv3 code was copied or modified.

**Review refinement (2026-11-19):** Resolve link-target components in lookup
order, including `..` after a resolved symlink, so the authorized-root check
uses the file that the filesystem will open. Dispatch local session calls to
interpreted functions and macros through the existing runtime application
path; compiled procedures continue through `mdl-apply`. These changes are
covered by controlled loader fixtures and do not expand the filesystem root
or add an evaluator service.
Each consecutive parent component is applied to the already resolved path;
the third PR #41 review found that `path-only` retained a trailing separator
and failed to ascend on the second parent component. The resolver now
simplifies one parent step at a time after preceding symlinks are resolved.

## ADR-0022: Explicit partial-source historical probe and narrow text output

**Decision:** Permit the loader to execute a positive number of initial
top-level expressions only when explicitly requested with
`#:max-expressions`; report `PARTIAL` and the exact skipped count. Use this
to install the first byte-for-byte original `VFLOAD` definition from the
pinned reconstructed `77loadall.mud` in a disposable authorized root.
Implement only STRING concatenation of STRING values, one-buffer/default-port
PRINTSTRING, and no-argument/default-port TERPRI. Follow the manual's
PRINTSTRING count return and empty-FALSE TERPRI return.

**Why:** Full `77loadall.mud` immediately enters `81prim.mud` and stops on
unsupported `#DECL`, so a clearly labeled prefix probe is necessary to
exercise an authentic definition now. The MDL manual and six pinned Confusion
probes support the required text behavior. Confusion returns the STRING from
PRINTSTRING, contrary to the manual's count; `VFLOAD` discards that result.

**Consequence:** G2 can verify original reconstructed-source function
invocation, output, return value and state changes without pretending that
the remaining 12 expressions ran. CHARACTER values, explicit CHANNEL/count
I/O, historical CRLF terminal behavior, declarations and game bootstrap
remain unsupported. No upstream or game source changed, and no GPLv3 code
was copied into the runtime.

## ADR-0023: Session-owned ==?-identity association space

**Decision:** Implement MDL atom-property associations (D5, issue #53) as
a session-owned entry list. Both item and indicator are matched by
`mdl-identical?` (`==?`), preserving the stored value's exact identity.
An independent review found that the initial weak `eq?` table missed
equal WORD values and separately constructed VECTOR/UVECTOR REST views;
five Confusion-backed identity regressions now cover these keys. `PUT`
and `GET` dispatch by the pinned
reference's classification: structured item + FIX indicator keeps the
existing element store; every other combination is an association
(including FIX indicators on non-structured items); two-argument PUT
removes an association and echoes the item, but a structured item with a
FIX selector raises TOO-FEW-ARGUMENTS-SUPPLIED. `DECL?` consults an atom's
`DECL` association through the existing D1/D3 declaration matcher,
carrying the resolved leaf in the `#FALSE` payload. `GETPROP`/`PUTPROP`
and chapter 13.4 machinery stay explicit unimplemented failures.

**Why:** `77defs.mud` expression 3
(`<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>`) and the object/OBLIST
property forms throughout the 1977 sources require association space
with `==?` identity (the manual's chapter 13 warning: READ-generated
structures do not match). Eighteen success and six deliberate-error
pinned Confusion observations (evidence: `evidence/M2/ATOM-PROPS.md`)
fix the dispatch, return values, and error behavior. Two manual passages
conflict with the reference — removal returns the item (not the previous
value) and `DECL?` misses print `#FALSE (leaf)` — and the reference wins
both adjudications because it is the executable parity target.

**Consequence:** The chain advances past the historical `RAPPLIC` barrier
to twenty-four completed expressions; the new first barrier is `EMPTY?`
inside the original `NEWSTRUC` (`77defs.mud` expression 15). Associations
hold strong references to item, indicator, and value until removal or
session termination. This is a recorded deviation from historical
association garbage collection; a weak table honoring the full MDL
`==?` equivalence needs separate design and testing. Registered type atoms
take precedence over DECL associations, aliases can chain, and a cycle
raises an explicit error (the pinned reference loops on the tested cycle).
Indexed STRING GET returns CHARACTER and mutable STRING PUT accepts one.
Final-head review established that STRING GET and SEGMENT extraction must
produce `==?` CHARACTER values; both now share the typed CHARACTER
representation, and PUT accepts it. Four pinned Confusion cases are in
`evidence/M2/character-review-*`.
`SETG` intentionally does not enforce DECL associations. Reader behavior
and printing remain unchanged; each fresh session starts property-free.

**Final-head local review (#67):** A native SUBR is represented here as a
Racket procedure but is an unstructured MDL association item. A FIX
indicator on that item must use association storage without asking for
the host procedure's unsupported MDL primtype. Pinned Confusion returns
`9` from `<PUT ,+ 7 9> <GET ,+ 7>` and returns FALSE after two-argument
removal. The narrow dispatch guard and red-to-green tests are recorded in
`evidence/M2/D5-FINAL-REVIEW.md`; structured FIX indexing is unchanged.

## ADR-0024: Complement the existing bounded structural comparator for N=?

**Decision:** Implement M2 `N=?` as the Boolean complement of the
existing `mdl-equal?` relation with exactly two evaluated arguments. Use
the reference's TOO-FEW and TOO-MANY diagnostics for wrong arity. Preserve
the existing explicit failure for comparisons of distinct equal-content
cycles. Keep `,.FOO` parsing as a separate reader correction (issue #58)
after the `N=?` primitive PR, because the original MSETG repeat path
exposed both dependencies in sequence.

**Why:** The manual defines `N=?` as the complement of structural `=?`;
eight clean pinned Confusion cases and three deliberate arity errors
confirm finite-value behavior. The two cyclic `N=?` probes timed out, so
they provide no finite reference result. The existing Racket comparator
already has a documented bounded cyclic policy, and this small primitive
must not invent a new equivalence rule or hang.

**Consequence:** Thirteen focused tests pass, including the explicit
cyclic boundary. The original MSETG advances from unassigned `N=?` to
the independent computed-global reader failure at `,.FOO`; G3 remains
FAIL. Evidence and exact commands are in `evidence/M2/NEQ.md`.

## ADR-0024: Read `,.FOO` as GVAL of FOO's local value

**Decision (2026-11-20, issue #58):** When comma is immediately followed
by period, the reader creates a global node whose operand is the local
node. This follows the MDL manual chapter 4 and three pinned Confusion
cases. Existing `,ATOM` and `,<FORM>` paths retain their behavior.

**Consequence:** The hash-verified original `MSETG` first and equal-repeat
calls return `T` without source edits. A conflicting repeat reaches the
separate missing `ERROR` primitive (issue #60), so integrated G3 remains
FAIL. Evidence: `evidence/M2/COMPUTED-GLOBAL.md`. No source provenance,
license, network exposure, or gameplay claim changes.

## ADR-0025: Preserve ERROR as an explicit interruption

**Decision (2026-11-20, issue #60):** A call to `ERROR` evaluates its
arguments and raises a Racket exception with readable values; zero
arguments also raises. The pinned Confusion reference enters a resumable
error level, but this runtime has no compatible error frames or `ERRET`.

**Consequence:** The exact original MSETG conflicting-repeat path reports
`ALREADY-GASSIGNED` and keeps the old global value. Error handlers,
resumption, and structured-argument printing remain documented gaps.
Evidence: `evidence/M2/ERROR.md`. No source provenance, licensing, or
service exposure changes.

## ADR-0026: Keep M2 G3 failed at original PSETG's MEMQ dependency

**Decision (2026-11-20, issue #56):** The current-head integrated probe
must require original MSETG first/equal/conflict paths and an original
PSETG invocation in the same loaded session. The 48 reached assertions
pass, but PSETG stops at unassigned `MEMQ` after SETG and PURE-LIST
initialization. G3 remains FAIL; partial side effects do not count as a
completed function call.

**Consequence:** Issue #63 is the next focused M2 correction. M3 `EMPTY?`
waits for a new G3 decision. Evidence: `evidence/M2/G3-GATE.md`.

## ADR-0027: Use MDL identity and REST views for MEMQ

**Decision (2026-11-20, issue #63):** MEMQ searches supported structured
values left-to-right with `mdl-identical?` (`==?`) and returns the
`mdl-rest` view from the first hit. A miss returns FALSE. This preserves
LIST tail aliasing and VECTOR/UVECTOR kind in the pinned reference cases.
One-argument MEMQ raises an explicit arity error locally; pinned Confusion
crashes with signal 11 on that probe. STRING MEMQ remains an explicit
unsupported error until mutable STRING REST semantics are established.

**Consequence:** Original PSETG first/repeat calls pass and keep one
PURE-LIST entry. The current G3 run fails next at original FLAGWORD's
unassigned MAPF (issue #65), after 52 passing assertions. Evidence:
`evidence/M2/MEMQ.md` and `evidence/M2/G3-GATE.md`. No upstream,
license, or service boundary changes.

## ADR-0028: Invoke evaluated MAPF elements directly and preserve map control

**Decision (2026-11-20, issue #65):** MAPF traverses supported MDL
structures by index until the first is exhausted. An internal application
path passes already evaluated element values directly to native procedures
or interpreted FUNCTIONs, including LIST/VECTOR values, without evaluating
their contents again. Inline `<FUNCTION ...>` creates an interpreted
FUNCTION value. MAPRET, MAPSTOP, and MAPLEAVE use scoped escape
continuations; dynamic parameter restoration and existing activation
cleanup remove map context on exits and exceptions. Pinned Confusion's
FALSE-final MAPRET/MAPSTOP result is the current first input, as recorded
in `evidence/M2/mapf-control-reference.json`, even when explicit control
values differ. An integer applicable selects that index from its one
structured argument.

**G3 follow-ons:** Add the observed TYPE? predicate and seed the native
reference's four reciprocal INITIAL/ROOT OBLIST associations in each fresh
atom space. These are required by the original FLAGWORD path and are
covered by separate red-to-green tests. The previous D5 association
dispatch is unchanged for ordinary items.

**Consequence:** The branch-level G3 original-definition scenario passes
59 assertions, including FLAGWORD no-arg, FALSE, ATOM, mixed, and
deliberate error paths. The complete source loader still stops at EMPTY?
after 24 forms. M2 mainline acceptance remains gated by the requirements
audit, CI/review, and authorized integration. No upstream, license, or
network service boundary changes.

## ADR-0029: Share evaluated application for APPLY, MAPF and computed heads

**Decision (2026-11-20, issue #69):** A computed FORM head is compiled as
an expression before its arguments. The shared runtime dispatcher keeps
raw arguments for interpreted FUNCTIONs and MACROs, but passes evaluated
values to native SUBRs and FIX applicables. APPLY always receives already
evaluated arguments and rejects MACRO, quoted-formal and ARGS-formal
targets; compiled DEFINE procedures retain formal-kind metadata for this
check. Host `mdl-apply` and `mdl-session-call` now also pass interpreted
FUNCTION arguments as values, preserving embedded FORM/LIST identity.
FIX application with two arguments performs indexed PUT only on a
structured target, following pinned Confusion rather than general PUT
association dispatch.

**Consequence:** Fifteen clean native indirect-application cases and
nine deliberate error observations are recorded; focused tests and the
existing binding regression pass. The branch G3 gate remains 59/59.
FSUBR values, CALL formals and broader applicable types remain explicit
unsupported cases. No upstream, licensing, or service boundary changes.

## ADR-0030: Assign random and event APIs to source-backed M3 work

**Decision (2026-11-21, M2 mainline gate):** The original M2 plan's task
list included “#16 random/event APIs,” but its stated M2 Build and Gate
require initial original definitions and execution semantics, not game
events or random behavior. The hash-verified G3 scenario invokes no
random/event API, while the M3 Build and Gate explicitly include the game
loop and event seed handling. Resolve the mismatch by tracking random and
event APIs as [M3 issue #71](https://github.com/quaat/mdl-racket/issues/71).
Implement them from actual unchanged-source calls and pinned Confusion
observations, with controlled seeds and scheduler state. This is a scope
decision, not evidence that those APIs work today.

**Consequence:** M2 PASS covers its listed Build and Gate plus the audited
APPLY/DISPATCH surface. It does not imply random/event parity, game boot,
or parser operation. The first M3 barrier remains original NEWSTRUC's
EMPTY? call, and source-progress reporting must identify later dependencies.

## ADR-0031: Separate stable M2 semantics from moving M3 source progress

**Decision (2026-11-21, issue #73):** The M2 G3, historical DECL and D5
property regressions load an explicit, SHA-verified source prefix in one
session: `77loadall.mud` expression 1, complete `81prim.mud`, and
`77defs.mud` expressions 1–14. They assert original definitions and state,
not the full chain's first failure. `make m3-source-progress` separately
executes unchanged `77loadall.mud` and validates a machine-readable report
against the accepted 24-form prefix and the pinned Confusion file order.
A legitimate later failure may advance the count without making M2 fail;
skips, lost prefix events, backward progress or false completion fail.

**Consequence:** Implementing EMPTY? can advance the loader without
invalidating M2's semantic regression. The progress target itself is an
incomplete-execution measurement, not a game-boot or parity claim. The
first observed M3 dependency is still EMPTY? until a tested correction
changes it. No upstream, licensing or network service boundary changes.

## ADR-0032: Advance original NEWSTRUC through native-backed predicates

**Decision (2026-11-21, issue #75):** Implement `EMPTY?`, bounded
`LENGTH?`, current-frame `ASSIGNED?`, and zero-argument `ROOT` as four
small, native-backed dependencies of original NEWSTRUC. `EMPTY?` checks
the first LIST cell so a circular LIST terminates. `LENGTH?` stops at the
given bound and preserves Confusion's empty-LIST/negative-MAX result of
FIX 0, a recorded manual deviation. `ASSIGNED?` accepts only the
one-argument source form; a supplied ENV fails explicitly pending frame
semantics. `ROOT` returns the already seeded session OBLIST by identity.

**Consequence:** The unchanged source loader advances from 24 to 26
completed forms with zero skips. It then fails at three-argument NEWTYPE
in `77defs.mud` expression 17. This is partial source execution, with no
game boot or parity claim. The original sources, GPLv3 interpreter,
license, and service exposure are unchanged.

## ADR-0033: Preserve NEWTYPE's declaration Pattern despite reference omission

**Decision (2026-11-21, issue #76):** Follow the MDL manual §14.6 for
the optional third `NEWTYPE` argument: validate its supported syntax,
store it under the type's `DECL` association, and check it when casting
into the type, including same-type casts. Permit same-primitive
redefinition to replace the Pattern. Accept the original
`<<PRIMTYPE VECTOR> ...>` structure head, resolving forward type atoms
when the cast occurs. Pinned Confusion reads but discards the third
argument; its `GET` returns FALSE and an invalid cast succeeds. This is
an explicit manual/reference divergence, not a silent no-op.

**Consequence:** The unchanged original loader advances from 26 to 36
completed forms with zero skips, then stops at `GDECL` in `77defs.mud`
expression 27. Full source loading and game boot remain unproved.
`GDECL` is tracked in issue #78. No upstream, licensing, or service
boundary changes.

## ADR-0034: Implement global declarations despite Confusion's no-op

**Decision (2026-11-21, issue #78):** Implement manual §14.5.1 GDECL
as an FSUBR consuming unevaluated source data. Validate nonempty ATOM
lists and supported declaration Pattern shapes, install each Pattern
on the session's global value slot, and check existing and later SETG
values. Preserve old global values on failed assignments. Store Patterns
until assignment so names of later-defined types can be resolved then.
Pinned Confusion's GDECL routine returns T without using its form or
arguments; copying that no-op would silently discard original source
meaning.

**Consequence:** Original source execution advances from 36 to 37
completed forms with zero skips, then stops at `AND?` in
`77defs.mud` expression 28. This is partial source progress, not a
game boot or parity result. No upstream, license, or service boundary
changes.

## ADR-0035: Keep AND? eager while preserving all original assignments

**Decision (2026-11-21, issue #80):** Implement `AND?` as a normal SUBR,
using the existing dispatcher to evaluate every argument left to right
before testing truth. Return the first FALSE value and its payload, or
the last value if all are true; zero arguments return T. Keep the
short-circuit `AND` compiler path separate. A SHA-verified bounded
source regression runs `77defs.mud` expression 28 and asserts all five
original MSETG globals. The complete loader still reports zero skipped
forms independently of that bounded test.

**Consequence:** Original source execution advances from 37 to 70
completed forms with zero skips, then reaches the quoted OPTIONAL
default in `77defs.mud` expression 61. Full load and game boot remain
unproved. No upstream, license or service boundary changes.

## ADR-0036: Bind quoted OPTIONAL defaults in the interpreted frame

**Decision (2026-11-21, issue #82):** Permit a two-element OPTIONAL
formal whose first element is a quoted ATOM. An explicit call argument
binds raw without evaluating the default; an omitted argument evaluates
the default once in the growing function frame. Reject the shape in AUX
or required sections, and keep duplicate-name validation. `DEFINE` with
quoted formals already uses the interpreted binder, so this extends its
existing quoted OPTIONAL path rather than adding a separate evaluator.
Six pinned Confusion cases corroborate timing, raw forms and the original
`',WINNER` default shape.

**Consequence:** The unchanged original loader advances from 70 to 87
completed forms with zero skips, then stops at a separate `APPLICABLE`
declaration in `77defs.mud` expression 78. Full load, initialization
and gameplay remain unproved. No upstream, license or service boundary
changes.

## ADR-0037: Match APPLICABLE declarations against runtime callables

**Decision (2026-11-21, issue #84):** Recognize `APPLICABLE` as the
manual's compound declaration type name. It matches values this runtime
can apply as a FORM operator: FIX, FUNCTION, MACRO and built-in SUBR
representations. It participates in simple, OR, structured and attached
declaration Patterns. Unknown type names remain errors. The native
`APPLICABLE?` SUBR confirms the type partition, while direct pinned
Confusion `DECL?` APPLICABLE probes enter `BAD-TYPE-SPECIFICATION1`;
this is an explicit manual/reference deviation. This slice does not add
the `APPLICABLE?` SUBR or unsupported custom application types.

**Consequence:** The unchanged loader advances from 87 to 112 forms,
zero skipped, and fully executes `77defs.mud`; it next stops on `%<>`
in `77makstr.mud` expression 6. Full source load and game boot remain
unproved. No upstream, license or service boundary changes.

## ADR-0038: Substitute the side-effect-free `%<>` reader value

**Decision (2026-11-21, issue #86):** Implement the `%` read macro
only when its payload is the empty FORM. Evaluating `<>` produces the
canonical empty FALSE with no side effects, so the compiler retains
that value once per loaded expression and shares it across uses of a
compiled definition. Six pinned Confusion cases confirm TYPE, truth
and identity. Other `%` payloads and `%%` remain explicit errors until
the general read-time evaluator is designed and tested.

**Consequence:** The unchanged loader advances from 112 to 136 forms,
zero skipped, and fully executes `77makstr.mud`; it next stops at a
typed AUX formal in `81tell-repl.mud` expression 2. Full source load
and game boot remain unproved. No upstream, license or service boundary
changes.

## ADR-0039: Read custom WORD-primtype `#type` literals

**Decision (2026-11-21, issue #88):** Parse `#PSTRING 0` as one typed
literal and, after `NEWTYPE PSTRING WORD`, construct a 36-bit WORD
representation and CHTYPE it to PSTRING. The reader accepts numeric
`#type` forms generically; the compiler supports integer WORD
representations and leaves other primitive representations as strict
errors. Retain custom typed literals once per compiled source
expression. Six pinned Confusion cases confirm the source behavior.
The Racket runtime keeps the manual's primitive-type safety check;
pinned Confusion accepts a deliberately mismatched LIST type case.

**Consequence:** The unchanged loader advances from 136 to 144 forms,
zero skipped, then stops on function-style `#DECL` in
`81tell-repl.mud` expression 10. Full load and game boot remain
unproved. No upstream, license or service boundary changes.

## ADR-0040: Preserve positional #DECL metadata on FUNCTION

**Decision (2026-11-21, issue #90):** Parse `#DECL ("VALUE" Pattern
...)` as positional RSUBR-style declaration data, distinct from ATOM
declaration pairs. Validate its supported `"VALUE"` and `"OPTIONAL"`
grammar and Patterns, and retain it on the definition. The MDL manual
places positional declarations on RSUBRs; pinned Confusion accepts
them on FUNCTION without enforcing their argument or result Patterns.
The Racket FUNCTION path follows that observed placement behavior.
Unsupported positional markers and malformed Patterns still fail.

**Consequence:** The unchanged loader advances from 144 to 157 forms,
zero skipped, then stops at `!\ ` in `81tell-repl.mud` expression 23.
Full source load and game boot remain unproved. No upstream, license
or service boundary changes.

## ADR-0041: Distinguish `!\` CHARACTER from SEGMENT notation

**Decision (2026-11-21, issue #92):** Read `!\` followed by one
character, including a separator such as space, as a CHARACTER node.
Compile it to the runtime's existing CHARACTER value. Keep `!<...>`,
`!.X` and other SEGMENT paths separate. Five pinned Confusion cases
confirm TYPE CHARACTER, PRIMTYPE WORD, code 32 and identity for
`!\ `. The runtime `ASCII` SUBR is not added by this reader slice.

**Consequence:** The original loader still completes 157 forms with
zero skipped. The first failure moves within `81tell-repl.mud`
expression 23 from `!\ ` to `%<STRING <ASCII 10>>`. This is a
scoped reader PASS, not an increase in completed source forms or a
full M3 gate PASS. No upstream, license or service boundary changes.

## ADR-0042: Evaluate `%` during executable reading in the active session

**Decision (2026-11-21, issue #94, before implementation):** Keep
`parse-mdl` and the source inventory syntax-only. Give the incremental
reader an optional callback used only by the executable loader. On `%`,
read its payload recursively, invoke the callback immediately, then put
an object reference into the source-located node. The callback compiles
and evaluates the payload in the current MDL session. A session-owned
registry holds the actual result object; compiled forms retrieve that
object rather than recreating it from syntax. Syntax-sensitive compiler
paths may inspect a one-level type/content projection whose children
still refer to the original registry objects. Ordinary expression
positions evaluate the substituted object; data positions retain it.
Substituted SEGMENT values enter the existing splice path in structured
or call-argument positions and raise ILLEGAL-SEGMENT when standalone.
Nested FLOAD inherits the same session and registry. Each new session
owns a separate registry. Reader evaluation errors retain the percent
location and stop
the loader; no fallback value is inserted.

**Rejected:** Compilation-time evaluation occurs after an entire top-level
form is read, so a preceding `%` could miss reader-visible state changes.
Rebuilding the substitution from an AST would lose mutable object identity
and could evaluate again on function calls. Enabling evaluation in the
syntax-only source sweep would introduce side effects into diagnostics.

**Boundary:** This implements `%` with currently supported MDL expressions,
plus the source-required `ASCII` and CHARACTER-capable `STRING` slice.
`%%`, mutable read tables, channel controls, and unsupported payload forms
remain strict errors. The source-progress report must distinguish
read-time failure from parse, compile and execute failures.

## ADR-0044: Track bounded logical MDL storage with weak references

**Decision (2026-11-22, WIP branch `feat/m3-logical-gc`):** Maintain a
session-owned ledger of allocation counts for LIST cells and VECTOR/UVECTOR
backing arrays, using manual word formulas and weak boxes. An explicit GC
triggers Racket major collection, sweeps dead ledger entries, returns the
reclaimed logical words, and dispatches the MDL event only after collection.
BLOAT requests free logical movable words. Allocation pressure invokes the
existing safe DIVERT-AGC/GC event path at tracked allocation boundaries.
The original handler lifecycle has a focused source-level regression.

**Limits:** The ledger deliberately omits atoms, OBLIST entries, strings,
closures, locals and frames; it is a bounded logical model, not a complete
PDP-10 storage simulator. Racket collection timing is not historical MDL
collection timing, and Confusion's GC/BLOAT stubs are not reference oracles.
The real host collector runs locally, outside any MDL callback. No public
REPL or evaluator service was added. The scope can be widened only with
separate word-accounting evidence and tests. The source LOADED gate passes;
M3 initialization and gameplay remain incomplete.

## ADR-0045: Model RANDOM as session-owned 36-bit state

**Decision (2026-11-22, issue #108):** Keep two 36-bit words in each MDL
session's atom space. Implement the bit recurrence independently with Racket
integer operations, using the historical manual's signed FIX contract and
pinned Confusion output fixtures as behavioral checks. No process-global
Racket PRNG or bounded integer random API participates. A one-seed call
replaces the first word; a two-seed call replaces both before one advance.

**Reference limit:** Pinned Confusion emits a value outside the signed
36-bit range for negative seeds. Normalize state at every step and report
that difference rather than treating an out-of-range host value as MDL FIX.
The separate GPLv3 source remains a local reference dependency; no source
code is copied into the MIT-0 runtime. A reviewer should inspect this
independent recurrence and the fixture provenance before integration.

## ADR-0046: Preserve the terminal CHANNEL predecessor for BACK

**Decision (2026-11-22, issue #110):** Represent the default terminal
CHANNEL as a view beginning after one host-managed element in its backing
VECTOR. BACK can expose that predecessor without inventing a game object
or changing source. Pinned Confusion reports a 20-element CHANNEL after
BACK of the 19-element INCHAN, with FIX 0 at its first position. Generic
VECTOR, UVECTOR and STRING BACK shares storage and enforces the manual's
positive, in-range offset rule. The terminal CHANNEL retains its TYPE
in the reference, so the runtime preserves it for that host value.

**Boundary:** This does not define a full CHANNEL control block or RESET
behavior. The original CONTIN then fails at TENEX?, a global initialized
by source wrappers before START. Probe that prelude before adding host
platform state. No GPLv3 implementation was copied.

## ADR-0047: Register IPC without a source; refuse SAVE strictly

**Superseded in part (2026-11-23):** part (2), strict SAVE refusal, is
superseded by ADR-0048 (SAVE session record). Part (1), IPC registration,
still applies, and RESTORE remains refused.

**Decision (maintainer, 2026-11-22, issue #112):** (1) `ON` is EVENT plus
HANDLER per manual chapter 21 and returns the new HANDLER. The predefined
`"IPC"` may be registered and observed, and OFF removes it, but an isolated
session has no inter-process message source, so any attempt to emit or
deliver an IPC occurrence is a strict error. All other refused predefined
names (CHAR, READ, BLOCKED, ...) stay refused. (2) `SAVE` raises an explicit
unsupported error naming this decision; it does not return `"SAVED"` and
writes no file. `RESTORE` is refused the same way.

**Consequence:** the faithful `run.mud` path stops at `<SAVE .FN>`
(77rooms.mud:26) after ON IPC, HANDLER DIVERT, ISTRING, DEV/SNM and
`INT-LEVEL 100000`; INITIALIZED is BLOCKED at SAVE. Confusion stubs ON and
really saves an image; both differences are documented reference deviations.
A session-owned snapshot (option b) remains a later, separately approved slice.
No GPLv3 implementation was copied.

**INT-LEVEL after the SAVE error (review note).** SAVE-IT raises the level
with an ordinary `<INT-LEVEL 100000>` call (77rooms.mud:25) before `<SAVE
.FN>`, and nothing unwinds it, so after the strict SAVE error the session's
INT-LEVEL stays 100000, with GC and DIVERT-AGC occurrences masked (queued,
not delivered). That is faithful to MDL, which would sit in an error loop at
that level, and SAVE deliberately does not reset it. It is harmless today
because every test builds a fresh session; any later slice that continues
the same session past SAVE (for example by calling START) must account for
it explicitly, after probing what Confusion's RESTORE does to the level,
instead of letting queued DIVERT-AGC occurrences silently change the GC
schedule.

## ADR-0048: SAVE as an in-session save record; BLOCKED registers without a source

**Decision (maintainer, 2026-11-23; supersedes ADR-0047 part 2, keeps ADR-0047
part 1 for IPC):**

1. **SAVE = session record.** `<SAVE file-spec>` evaluates its arguments as
   any SUBR, then returns a *fresh* mutable STRING `"SAVED"` (two calls never
   return `==?` objects; mutating one result never affects a later SAVE). It
   writes no file, opens no channel, performs no garbage collection, and has no
   interrupt side effect: it neither changes INT-LEVEL nor emits, queues or
   drains any occurrence. It appends one immutable record to the current
   session: a 1-based per-session sequence number, an immutable snapshot of
   the file-spec STRING's visible characters, and the INT-LEVEL at the call.
   The records are visible only to host Racket code
   (`mdl-save-records` in `mdl/runtime/core.rkt`,
   `mdl-session-save-records` in `mdl/loader.rkt`); no MDL primitive exposes
   them.
2. **Strict arguments.** Exactly the forms the game and manual 11.6.1
   (`<SAVE file-spec:string gc?:false-or-any>`) need: one STRING file-spec
   (a native STRING or a REST view), optionally followed by a FALSE `gc?`.
   A FALSE `gc?` asks the manual's SAVE *not* to collect, which is exactly
   what this SAVE does, so it is accepted and has no further effect. Strict
   errors: `<SAVE>` (Confusion writes `MUDDLE.SAVE`), a non-STRING file-spec
   (`<SAVE 1>` crashes pinned Confusion with SIGSEGV), a non-FALSE `gc?`
   (the manual would collect; this SAVE never does), and more than two
   arguments. The manual's multi-name form (`<SAVE name1 name2 device dir
   gc?>`) is therefore refused too (its second STRING is a non-FALSE
   `gc?` position here). Validation happens before any record is appended.
   The one-argument form is accepted, although under the manual an omitted
   `gc?` also means "collect"; this asymmetry is intended. `<SAVE .FN>` is
   the only form the game uses, an explicit non-FALSE `gc?` is refused
   rather than silently ignored, and the missing GC is a recorded deviation.
3. **RESTORE stays strictly refused** with an explicit error naming this
   decision. Neither Confusion's behavior (RESTORE swaps the heap and
   re-enters the LISTEN loop, so SAVE never returns again) nor the manual's
   (SAVE returns a second time with `"RESTORED"`) is modeled. The two
   references disagree; that disagreement is recorded in
   `evidence/M3/S5-SAVE-FRONTIER.md` and must be resolved before any future
   RESTORE slice.
4. **"BLOCKED" registers, never fires** (same treatment as IPC). It moves from
   the refused predefined names to the sourceless ones: EVENT, HANDLER, ON
   and OFF work; emitting or delivering a BLOCKED occurrence is a strict
   error naming this decision, because the session has no blocked-input
   source. Every other refused predefined name (CHAR, READ, WRITE,
   UNBLOCKED, CLOCK, ...) stays refused.

**Deviations recorded:** pinned Confusion writes an image file and returns
`"SAVED"` (or `#FALSE ()` if the file cannot be opened), and ignores `gc?`;
the manual collects garbage unless `gc?` is FALSE. This SAVE writes nothing,
never returns FALSE, and never collects. Confusion stubs `ON "BLOCKED"` as
`T`; this runtime returns a real HANDLER.

**Consequence:** the patched `SAVE-IT` takes its single COND clause
(`<=? <SAVE .FN> "SAVED">`), runs `<INT-LEVEL 0>` at 77rooms.mud:26 in the
same session and continues into the startup code. At that `<INT-LEVEL 0>`
this runtime would deliver any GC or DIVERT-AGC occurrence queued while the
level was 100000 (Confusion has no such occurrences); this is faithful MDL
behavior and is not suppressed. On the observed faithful path none was
pending (DIVERT-CNT stayed 0). The run then stops in CONTIN at
77rooms.mud:301 on the unassigned GVAL of REP; see
`evidence/M3/S5-SAVE-RECORD.md`. INITIALIZED remains FAIL. No GPLv3
implementation was copied.

## ADR-0049: Inert REP and a host top-level loop

**Decision (maintainer, 2026-11-23, "Inert REP + host loop"):**

1. **REP is a real predefined SUBR in every session.** The GVAL of ROOT `REP`
   is a SUBR value: `<GASSIGNED? REP>` is T, `<TYPE ,REP>` is SUBR, it matches
   the APPLICABLE declaration Pattern, and `<SETG SAVEREP ,REP>` stores that
   same object (`<==? ,REP ,SAVEREP>` is T). This is what CONTIN needs at
   77rooms.mud:301 and what BLO tests at 77act1.mud:3
   (`<TYPE? ,REP SUBR FSUBR>`). Pinned Confusion agrees on all four
   observations (`evidence/M3/S6-rep-reference.json`).
2. **Applying the default REP is a strict error.** Applying it directly
   (`<REP>`), through `<APPLY ,REP>`, as a HANDLER action, or by any later
   path that restores it (for example `<SETG REP ,SAVEREP>`, 77rooms.mud:222)
   evaluates the arguments as for any SUBR and then raises
   `REP: the default REP SUBR is inert; this runtime never provides a raw MDL
   read-eval-print loop (maintainer decision 2026-11-23; ADR-0049)`.
   The runtime never provides a raw MDL REPL.
3. **A host top-level loop applies the current GVAL of REP.** Its contract is
   specified in SEMANTICS ("M3 startup: inert REP and the host top-level
   loop"). It is *not implemented* in this slice: it cannot be exercised before
   RESET, PRINC and READSTRING exist. In summary, it starts only after the
   session's entry form returns normally, re-reads GVAL REP on every pass,
   applies it with no arguments, never applies the default REP (that is the
   strict error above), ends when the applied code QUITs, fails strictly when
   terminal input is exhausted or anything raises, and is local-only: no
   server or web client may reach it or any MDL evaluator.

**Scope limits.** Only REP is represented as a SUBR value. Other built-in
SUBRs are still host procedures whose TYPE is an explicit unsupported-type
error, as before. TYPEPRIM SUBR and PRIMTYPE of REP stay strict errors
(Confusion: WORD); SUBR is not registered in the TYPE table, so CHTYPE,
DECL patterns naming SUBR and UNPARSE of REP fail strictly.

**Deviations recorded.** In Confusion `<REP>` performs one real
read-eval-print step on the terminal (`<REP>` followed by `<+ 1 2>` prints
3, then LISTEN prints REP's value 3), and its LISTEN loop applies the new
GVAL of REP on the very next pass (`listen-applies-new-rep`). This runtime
refuses the default REP by decision. Paths in the game that restore
`SAVEREP` (only 77rooms.mud:222, in the ERROR handler HANDLE, for an
unassigned XUNM or an XUNM in WINNERS) will therefore fail loudly when the
loop next applies REP, instead of dropping into an implementor REPL.

**Consequence.** The faithful SAVE-IT path passes 77rooms.mud:301-302
(SAVEREP holds the REP SUBR; REP becomes RDCOM) and stops at the next
missing primitive; see `evidence/M3/S6-REP.md`. INITIALIZED remains FAIL.
No GPLv3 implementation was copied.

## ADR-0050: Terminal RESET, PRINC, PRIN1, READSTRING and the host top-level loop

**Decision (maintainer, 2026-11-23; implements ADR-0049 part 3).** Evidence:
`evidence/M3/S7-frontier/` (pinned Confusion `6df359f6…`, upstream
`bdcd4a67`), implementation record `evidence/M3/S7-INTERACTIVE.md`,
contracts in SEMANTICS ("M3 interactive terminal I/O and the host top-level
loop").

1. **RESET** of an open terminal CHANNEL of this session returns the same
   CHANNEL. For the READ channel it clears the host-side end-of-input flag;
   it never discards queued unread input (no lookahead is ever held, because
   READSTRING never peeks). It changes no CHANNEL slot, predecessor slot or
   association. Every other argument (non-CHANNEL, forged or foreign
   CHANNEL, shifted view, wrong arity) is a strict error.
2. **PRINC** writes a STRING, CHARACTER or FIX to an open PRINT CHANNEL
   (default: the LVAL of OUTCHAN) and returns its argument. **PRIN1** writes
   a FIX, or an ATOM printable without trailers, the same way. Control
   characters other than CR and LF, and every other TYPE, are strict errors.
   **No line breaking** is performed (deviation: manual and Confusion break
   lines at the CHANNEL width; RDCOM sets the width to 1000).
3. **READSTRING** `<READSTRING buffer channel [stop-string]>` reads the
   session input port into a mutable STRING view exactly as RDCOM and YES/NO
   use it: count returned, stop character consumed and not stored, full
   buffer leaves the rest of the line unread, no echo, output flushed first.
   The manual's default channel, a FIX stop and the EOF-routine argument are
   strict errors. A non-ASCII character in the input is a strict error.
   ~~A `!` in the input is a strict error (open question: Confusion drops
   `!` as a reader escape; the manual is silent).~~ **Amended 2026-11-23
   (S13 part A, maintainer decision "follow pinned Confusion"):** `!c` is an
   escape pair that stores `c` in one slot; the `!` is never stored or
   counted; an escaped stop character still stops the read and is consumed;
   `!` immediately before end of input is stored literally and sets the
   end-of-input flag; escape pairing resumes on the next READSTRING after a
   full buffer; the character after `!` must still be ASCII. Evidence:
   `evidence/M3/READSTRING-BANG-REFERENCE.md`; contract: SEMANTICS
   READSTRING; record: `evidence/M3/S13-BANG-OUTPUT.md`.
4. **End of input, maintainer decision D3 "Mirror, then strict".** A read
   that meets end of input returns the characters read so far (often 0) and
   sets the channel's end-of-input flag, as Confusion does, so the game
   prints `Beg pardon?` and `>` once. A READSTRING entered with the flag set
   raises the host-level `exn:fail:mdl-input-exhausted` ("input exhausted").
   It is not an MDL ERROR, so no MDL ERROR handler (the game's HANDLE) runs,
   and a host must report it as a failure, never as success. RESET clears
   the flag (mirrors Confusion's `eof-sequence-then-reset`).
5. **Host top-level loop** (`mdl-session-run-interactive`, local only). It
   requires a session made with explicit input and output ports, applies
   the entry FUNCTION (for `run.mud`, SAVE-IT) with no arguments, then
   prints the entry value with PRIN1 and TERPRI to the LVAL of OUTCHAN.
   **Maintainer decision D1:** that print is kept, because it is the REP
   print the game's own `,NULL` (an empty-PNAME ATOM) exists for; it yields
   the golden transcript's blank line. The host never prints the
   `LISTENING-AT-LEVEL` banner or FLOAD's `"DONE"` value line; a transcript
   comparator strips those two lines from the Confusion golden. Then each
   pass re-reads the GVAL of ROOT REP and applies it with no arguments; the
   default REP SUBR stays the ADR-0049 strict error. The loop exposes no
   MDL evaluator and is never reachable from a network service.

**Deviations recorded.** Confusion's RESET sets STATUS (slot 11) to 0 and
rewrites DEVN (slot 9), and drops one lookahead character; our slots are
untouched (ADR-0046/D8 slot layout) and no lookahead exists. Confusion's
default EOF action is `Error: Unexpected EOF` and the manual's is an MDL
ERROR; ours is a host-level strict error. PRINC/PRIN1 do not break lines.
The ADR-0049 sentence "the loop itself reads and prints nothing" is amended
by D1: the loop prints the entry value once.

**Host input port only (independent review follow-up).** Terminal input
uses only a host-supplied port. READSTRING on a session input CHANNEL with no
port is a strict error (`... has no host-supplied port ...`); the runtime
never reads the process's own stdin. ~~Output keeps its pre-S7 behaviour:
with no session port, OUTCHAN writes to the host's `current-output-port`
parameter. That parameter is host-controlled and existing tests capture
output through it. Making output strict as well would change a
runtime-wide contract that predates S7 (PRINTSTRING, CRLF, VFLOAD tests),
so it is left for a separate decision.~~ (Superseded below.)
`mdl-session-run-interactive` requires both ports to be explicit.

**Explicit output port (amended 2026-11-23, S13 part B, maintainer
decision "explicit output for game sessions").** Terminal output now uses
only a host-supplied port as well. A PRINT CHANNEL made by `make-mdl-session`
or `make-mdl-context` without `#:output-port` has no port, and every
operation that resolves it is a strict error naming ADR-0050 (`... PRINT
CHANNEL has no host-supplied output port; the runtime never falls back to the
host's current-output-port (ADR-0050)`): PRINC, PRIN1, PRINTSTRING, TERPRI,
CRLF, READSTRING's pre-read flush, the host loop's entry-value print and its
final flush. Nothing is written to a parameterized host port. The only
exception is an explicit opt-in that `make-mdl-session` and `make-mdl-context`
do not accept: `mdl-ensure-terminal-channels! #:follow-current-output-port?
#t`, used by exactly two non-session callers, the process-wide default
context (end of `core.rkt`, used by core unit tests and host code that never
creates a context) and `#lang mdl` modules (`mdl/lang/reader.rkt`), which run
in that ambient context. Their PRINT CHANNEL follows the host's
`current-output-port` at each operation, as before. F2 is unchanged: a
strict error from the final flush is a secondary failure when a primary is
leaving the loop, and is raised only when nothing else was. Record:
`evidence/M3/S13-BANG-OUTPUT.md`.

**Out of scope (decisions pending):** QUIT, OPEN/CLOSE (D5), UNWIND under
host errors (issue #139), MEMBER, a fixed clock (#135). No GPLv3
implementation was copied. (2026-11-23: #139 was since decided by ADR-0051
and merged into this branch; the others remain pending, see PLAN "Active
iteration" WP2/WP3.)

## ADR-0051: UNWIND cleanups run only for MDL transfers, never for raised errors

**Status:** Accepted (maintainer decision 2026-11-23, issue #139, option a).
Supersedes the error clause of ADR-0018 ("cleanup runs only when a
transfer or an error crosses below it"). The rest of ADR-0018 stands.

**Decision:** An UNWIND cleanup runs only when an MDL transfer of control
leaves the guarded expression through the UNWIND frame. In this runtime
those transfers are RETURN, AGAIN, GO and MAPLEAVE/MAPRET/MAPSTOP,
including transfers made by an ERROR or other interrupt handler. ERRET to
an ERROR frame lies above the UNWIND and crosses none. Anything that
leaves by a Racket `raise` propagates unchanged and runs no cleanup. That
covers an MDL ERROR no handler resolves, host strict errors for
unsupported constructs, nested-load failures, and any future QUIT, which
must be a raised non-`exn:fail` signal. `mdl-unwind` marks a raise passing
through its body with `call-with-exception-handler`, which returns the
value so the raise continues to the next handler, and its `dynamic-wind`
post skips the cleanup when the mark is set. Host bookkeeping (activation
liveness, bindings, OBLIST path and interrupt level) is still restored on
a raise. An error inside a cleanup during a transfer propagates unchanged.
It abandons the pending transfer and any outer cleanups on that path.
"Unchanged" refers to UNWIND: it neither catches nor rewraps the raise. A
raise out of a nested FLOAD still reaches its caller as the loader's
`exn:fail:mdl-load` wrapper, which is a loader behaviour, not UNWIND's.

**Why:** The MDL manual §16.2 makes ERROR a nested LISTEN on the intact
stack. In §16.4/§16.5 only ERRET and RETRY strip the stack. The §16.6
FLOAD cleanup runs "if the user attempts to ERRET", and in §23.3 QUIT
stops MDL. Pinned Confusion (`6df359f6…`) runs no cleanup on entering an
error level, at EOF from that level, on QUIT, or for C-level internal
errors. It runs the cleanup only on ERRET or a RETURN typed at the error
level that crosses the UNWIND (`docs/evidence/M3/I139-UNWIND.md`). ADR-0018
misread its probe `unwind-cleanup-on-error`. The probe read `,M2-C` while
still at error level 2, where the manual also runs no cleanup, so the
manual and Confusion never disagreed. The old rule also broke strict
failure. A cleanup error replaced the body's error, and a cleanup that
RETURNed past the UNWIND turned a strict error into a normal value. If QUIT
had followed that rule, the game's FLUSH-ME/JIGS-UP/FINISH cleanups would
have run FINISH and RECORD a second time.

**Consequence:** Raised errors are terminal and keep their original
message. This runtime has no interactive error level, so it cannot model
ERRET with no arguments, ERRET to a frame below the UNWIND, RETRY, or a
RETURN typed at level 2. These are documented deviations, never emulated.
Confusion keeps a transfer pending when its cleanup errors and completes it
after ERRET. Here that error is terminal, unless an ERROR handler resolves
it with ERRET, in which case the transfer completes. Skipped cleanups are
not reported as diagnostics. The original exception is the only report.
No game source, upstream provenance, license, deployed service or GPLv3
code changed. The source LOADED gate is unchanged at 1229 expressions.

## ADR-0052: The wall clock and local time zone are session-owned host dependencies

**Status:** Proposed (issue #135 part 1).

**Decision:** Each MDL session owns a clock and a time zone, stored in its
atom space next to its RANDOM state. `make-mdl-session` accepts `#:clock`
(an `mdl-clock`; default `real-mdl-clock`, the host wall clock) and
`#:time-zone` (`'local`, default, or `'utc`). `make-fixed-mdl-clock seconds
#:micros m` returns a constant instant that never advances. Only the
no-argument "now" read of GETTIMEDATE uses the clock. The zone replaces the
process local zone for GETTIMEDATE's non-UTC decomposition. Explicit
timestamps keep their values. A truthy UTC argument still selects UTC.
`mdl-session-random-snapshot` is a host-only, detached copy of the RANDOM
state for observation.

**Why:** DSKDATE feeds both the "This version created" line and START's
RANDOM seed, so a deterministic run needs a deterministic clock. A
process-global parameter or a changed process `TZ` would couple two
sessions in one process. A fixed clock that does not advance matches the
reference capture (`scripts/reference/fixed_time.c`, PR #131): its
`gettimeofday`, `time` and `CLOCK_REALTIME` return the constant
`MDL_FIXED_EPOCH` with zero microseconds on every call, while monotonic and
CPU clocks run normally. The reference child runs with `TZ=UTC`, so the
golden's zone is UTC. Normal local play keeps the real clock and the host
zone.

**Consequence:** Under a fixed clock, every DSKDATE in a run is equal, so
GET-TIME reports zero played time, as in the reference capture. The
supported zone set is minimal: no named or offset zones. Invalid clocks,
invalid clock reads and unknown zones fail strictly. No game source, game
global, DSKDATE/START/RANDOM call site, upstream provenance, license or
GPLv3 code changed.

**Known wall-time input outside the clock (independent review,
2026-11-23):** the GC interrupt's elapsed-time argument
(`mdl/runtime/memory.rkt`, `mdl-memory-collect!`) is still measured with
Racket wall time and is not controlled by the session clock. It does not
reach this game's output: the only GC handler, `GC-FCN`
(`77rooms.mud:97-102`), takes its arguments as an unused `"TUPLE" T`, and
the handler is turned `OFF` at load (`77rooms.mud:104`). A determinism
claim for another program that reads that argument must not rely on this
ADR.

**Amendment (M4 S9, maintainer decisions on #169/#170, 2026-11-24).** (1)
SLEEP waits for real only when the session clock is *live*: the real clock,
the resumed clock (ADR-0061), a recording clock over a live source, or a
custom clock made with `make-mdl-clock thunk #:live? #t`. Fixed, replaying,
recording-over-fixed and (by default) custom clocks are non-live and SLEEP
returns at once. The new query `mdl-clock-live?` reads no time. (2) SLEEP and
TIME never read the session clock: GETTIMEDATE's "now" stays its only
reader. TIME returns a session-derived FLOAT (the count of TIME calls in the
session), a documented deviation from Confusion's CPU time. (3) The live
wait goes through the host-only parameter `current-mdl-sleeper` (default
Racket `sleep`, interruptible by a break); tests replace it. Details:
SEMANTICS "M4: IMAGE, SLEEP, TIME (#168–#170)".

## ADR-0053: One strict SMOKE_PARITY comparator; D1 and D2 are the only allowed differences

**Status:** Proposed (S10, issues #131/#135). Builds on ADR-0050 (D1, D2,
D3) and ADR-0052 (fixed session clock). Evidence:
`evidence/M3/S10-SMOKE-PARITY.md`.

**Decision:**

1. **One comparator.** Every fresh-boot SMOKE_PARITY comparison goes through
   `compare_records` in `scripts/smoke_parity.py`: this runtime's candidate
   against a Confusion reference record, and a fresh Confusion capture
   against the committed one. `boot_reference.py compare` delegates to it.
   There is no second comparator.
2. **Records.** A reference record is a Confusion PTY capture from
   `scripts/boot_reference.py` (schema 2 or 3; same strict-field layout). A
   candidate record is built by `candidate_record` from the raw facts of
   `scripts/m3_house_boot_run.rkt`. That script runs the faithful `run.mud`
   path through `mdl-session-run-interactive` on the scenario's fixed clock
   (`fixed_epoch`, zone UTC) and keeps the raw output verbatim. The
   comparator re-derives every compared candidate field from that raw output,
   so an edited record fails.
3. **Allowed presentation differences, and nothing else:**
   - **D1** (ADR-0050 part 5): the reference `boot_output` must contain
     `LISTENING-AT-LEVEL 1 PROCESS 1` as its first line and FLOAD's
     `"DONE"` line exactly once each. Those two lines are removed exactly once,
     from the reference only. The host's REP print of `,NULL` (the blank line
     after the date line) is compared, not removed.
   - **D2** (ADR-0050; `evidence/M3/S7-frontier/golden-compare.txt`): the
     reference text is `canonical_text` of PTY output, whose line discipline
     applies ONLCR. The candidate's raw output becomes
     `canonical_text(ONLCR(raw))`, then splits at RDCOM prompts with the
     reference's own rule (`^>`). After D2, no CR or ESC may remain in any
     compared text.
4. **Exact checks.** These must be equal: scenario name, `fixed_epoch`,
   `tz`, the entry forms, and the command inputs (order, missing and extra
   commands). These must be byte-identical after D1/D2: the boot text and
   every response. Named checks repeat these for the date line (exactly one,
   identical) and the score line (points, total, moves). The final move count
   must equal the number of commands. The candidate's `MOVES` global must
   equal the move count on its score line. There is no date substitution,
   no alternative `west` text and no whitespace folding.
5. **Termination (D3).** The candidate run must end by input exhaustion:
   - exactly one mirrored empty read after the last command (output
     `Beg pardon?` then `>`);
   - then `exn:fail:mdl-input-exhausted` with the exact D3 message;
   - all input consumed, load PASS (1229/0), host-loop events
     `entry-returned`, `pass`, and the game directory unchanged.

   This is reported as input exhaustion, never as a user QUIT or as success
   on its own. A run that stops early, times out, errors or returns is a
   FAIL. The reference PTY capture stops at the last prompt, so the D3 tail
   is checked against its exact expectation, not against the reference.
6. **Provenance (reference schema 3).** `provenance.immutable_inputs` holds
   what is fixed before the boot:
   - the game files, minus the removed stale `SAVEFILE/ZORK.SAVE` and minus
     SAVE artifacts;
   - the hashes of mdli, `fixed_time.c` and the scenario file;
   - the commands and the entry forms.

   `provenance.save_artifacts` lists the files the run writes
   (`MDL/MADADV.SAVE`, `77rooms.mud:8-9`) with before and after hashes. The
   after hash changes between identical Confusion runs, so it is never
   compared. A capture fails if the run writes any other file. The
   approved schema-2 record stays unchanged. Its `boot_input_state` still
   lists `MDL/MADADV.SAVE`, a documented flaw. Its gameplay fields remain
   comparable.
7. **`make m3-check`** runs these stages in order, each PASS, FAIL or NOT
   RUN:
   - `sources`;
   - `test-m3-saveit`;
   - `test-m3-clock-seed`;
   - `test-m3-interactive`;
   - the comparator unit tests;
   - the binary-free strict comparison of this runtime against the
     committed reference;
   - optionally, a fresh native capture compared with both. Without mdli or
     gcc this stage is NOT RUN, never PASS; `M3_NATIVE=require` makes that a
     FAIL.

   The target exits nonzero on any FAIL and writes
   `artifacts/m3/m3-check.json`.

**Why:** S7 compared with date normalisation and allowed two `west` texts,
because the clock was not fixed. ADR-0052 made the clock a session
dependency, so every tolerance except the two approved presentation
differences can now go. One comparator keeps the contract in one place.
Each kind of drift (date, RNG branch, text, command list, score/moves,
early stop) fails a named negative test.

**Consequence:** A PASS is technical evidence for one scenario: six
commands, fixed clock 250776000, UTC. It does not cover play under the real
wall clock, other inputs, save/restore, QUIT or death paths. The gate state
stays the maintainer's decision in `STATUS.md`. No runtime file, game
source, upstream provenance, license or GPLv3 code changed.

**Amendment (2026-11-23, maintainer decision — schema-3 promotion):** the
committed reference compared by `make m3-check` is
`docs/evidence/M3/house-boot-reference.json`, the schema-3 S10 capture with
only `candidate`, `candidate_note` and a `promotion` record changed. The
schema-2 approved candidate `house-boot-candidate.json` (sha256 `eb194115…`)
is kept unchanged as the historical baseline. The comparison contract, the
six-command transcript and D1/D2 are unchanged; baseline, promoted reference
and a fresh native capture at epoch 250776000 UTC compare strictly equal.

## ADR-0054: QUIT is a session-termination signal; the host loop returns a session outcome

**Status:** Proposed (S11). Implements the "ends when the applied code QUITs"
clause of ADR-0049 part 3 and the QUIT rule anticipated by ADR-0051.
Contract: SEMANTICS "M3 session end: `QUIT` and the host-loop outcome".
Evidence: `evidence/M3/SESSION-QUIT-REFERENCE.md` (pinned Confusion
`6df359f6…`, upstream `bdcd4a67`), implementation record
`evidence/M3/S11-QUIT-OPEN.md`.

**Decision:**
1. `<QUIT>` takes exactly zero arguments (every game call site, including
   FINISH 77rooms.mud:711-712). One argument is a strict unsupported error,
   two or more `TOO-MANY-ARGUMENTS-SUPPLIED`. It never calls Racket `exit`.
   It raises `mdl-quit-signal`, a dedicated host struct that is neither an
   `exn:fail` nor an `exn:break`, so no `exn:fail?` handler of the runtime or
   loader intercepts it.
2. QUIT is not an MDL ERROR: no ERROR interrupt is signalled and no MDL ERROR
   handler (the game's HANDLE) runs. It is a raise, not an MDL transfer, so
   per ADR-0051 every UNWIND it crosses skips its cleanup (FINISH's cleanup
   `<QUIT>` and any FLUSH-ME/JIGS-UP cleanup never run, RECORD never runs
   twice). Host bookkeeping restored by `dynamic-wind`/`parameterize` is
   still restored.
3. `mdl-run-host-loop` / `mdl-session-run-interactive` catch exactly that
   signal at the session boundary and **return** an `mdl-session-outcome`
   (`kind`, `mdl-errors`). Kind is `'quit`, or `'quit-after-mdl-error` when
   any MDL ERROR was signalled while the loop ran (resolved by a handler or
   not); `mdl-errors` lists their messages oldest first. The runtime records
   each application of the ERROR SUBR in the session for this purpose. An
   acceptance run must require `'quit`.
4. Every other ending still raises, unchanged: input exhaustion
   (`exn:fail:mdl-input-exhausted`, D3), strict host/runtime failures and
   unresolved MDL ERRORs (their `exn:fail`), the pass bound, host
   cancellation (`exn:break`).
5. F2 final flush: after a QUIT there is no primary failure, so a failed final
   flush is raised (first failure; the rest are its secondaries) and the quit
   outcome is dropped. A quit whose transcript may be incomplete is never
   reported as success.
6. QUIT outside the host loop: during `mdl-session-load!` the loader records
   a `"QUIT"` event (file, expression, line, column, construct, load chain)
   and the load report's status is `"QUIT"` (never `"PASS"`; the
   `scripts/mdl_load.rkt` driver exits 3); during `mdl-session-call` the
   signal propagates to the host caller unchanged. (Amended after the S11
   independent review, 2026-11-23.)
7. An MDL ERROR's outcome record is the message formatted at signal time;
   the message of an unresolved ERROR's host failure is formatted after
   handler delivery, as before S11, so a handler that mutates an argument
   is reflected in it (S11 review).

**Why:** The manual (§23.3) makes QUIT end MDL; Confusion's QUIT is `exit(0)`
and runs no cleanup (C1, D11). A host process must not exit from inside a
library call, and a game session needs a structured result that cannot be
confused with failure. HANDLE (77rooms.mud:213-252) turns an MDL ERROR into
`FINISH #FALSE (". Error.")` → RECORD → QUIT, an exit status 0 in Confusion;
the outcome kind makes that path visible instead of letting it look like a
clean user quit.

**Consequences:** In this runtime HANDLE's ERROR path currently stops before
FINISH: it applies `PRINT` (77rooms.mud:251), which is unsupported, so that
path is a strict failure today; the outcome kind covers it once PRINT exists.
No game source, upstream provenance, license or GPLv3 code changed.

## ADR-0055: OPEN under a virtual no-file policy

**Status:** Proposed (S11). Implements the maintainer-approved policy "OPEN
returns FALSE, no file" (ADR-0050 D5). Contract: SEMANTICS "M3 file system:
`OPEN` denial". Evidence: `evidence/M3/OPEN-FAILURE-REFERENCE.md`
(`open-failure-probe.json`).

**Decision:**
1. Only RECORD's form is supported: `<OPEN mode name1 name2 device
   directory>`, five STRING arguments, mode `"READB"`, `"PRINT"` or
   `"PRINTO"` (77rooms.mud:731, 736, 748). Every other arity (the
   one-file-spec forms at 316, 392, 412), every other mode (`"READ"` at 350,
   352, 381, 384, 961; `"PRINTB"` at 392) and every non-STRING argument is a
   strict error.
2. OPEN never touches the host file system. It returns the three-element
   FALSE `#FALSE (reason file-spec status)` with fresh STRINGs and a FIX
   status, following manual §11.2.1 and Confusion's shape. The file spec is
   built as Confusion builds it: `directory "/" name1 "." name2`.
3. **Virtual-file-system policy, not OS equivalence:** the session's virtual
   directory is empty and read-only. READB → `"No such file or directory"`,
   2; PRINT and PRINTO → `"Permission denied"`, 13 (the values pinned
   Confusion returns for an absent log in a read-only directory, D2/D7). The
   status is never `*600130*` (196696), the only value that sends RECORD
   (MUDDLE 101) into its SLEEP/AGAIN busy loop. The PRINTO value is fixed by
   this policy; it is unreachable, because PRINTO follows only a successful
   READB (Confusion D2 reports ENOENT for PRINTO on an absent file).
4. Each denied call is recorded host-side (`mdl-session-open-records`); no MDL
   primitive exposes it.
5. CLOSE, FILE-LENGTH, ACCESS, SLEEP and file READSTRING stay unsupported.
   Under the policy RECORD returns T through `<RETURN T .RECORD>` and its
   UNWIND cleanup stops at the FALSE `.CH`, so CLOSE is never reached. No
   success-shaped CLOSE exists.

**Deviations recorded:** Confusion creates or appends to `MDL/ZORK.LOG` when
the game QUITs; this runtime writes nothing. The log is not console output,
so the C1 transcript is byte-identical. DO-SCRIPT's PRINT
(77rooms.mud:354) is the same form and would be denied, so `script` would
print `I can't open the script channel.` where Confusion creates
`ZORK.SCRIPT` (not exercised). HELP/INFO (FILE-TO-TTY) fail strictly.

**Security:** no file is opened, created, truncated or deleted by any OPEN
call; the S11 tests run under a security guard that records every write or
delete attempt and assert there are none. No server or web client can reach
OPEN or the host loop.

## ADR-0056: One SEGMENT representation, a LIST-primtype typed value

Status: accepted (M4 S2, 2026-11-23).

Context: frontier F1 (`drop`) needs `<CHTYPE <FORM ...> SEGMENT>`. The
runtime's reader built SEGMENTs as a separate host struct with no MDL TYPE,
so CHTYPE could not produce one and TYPE/NTH of a reader segment failed.
The pinned reference shows a single TYPE SEGMENT, PRIMTYPE LIST, for reader
and CHTYPE'd segments, with CHTYPE sharing the LIST cells
(`docs/evidence/M4/SEGMENT-CHTYPE-REFERENCE.md`).

Decision: SEGMENT is a built-in TYPE (PRIMTYPE LIST) represented like FORM:
a TYPE tag over the element cells. The reader constructor
(`mdl-make-segment`) and CHTYPE both produce it; `mdl-segment?` and
`mdl-segment-payload` (a FORM view over the same cells) are the only
accessors the evaluator uses, so the M2 D2 splice rules apply unchanged to
every SEGMENT. `mdl-segment?` tests the type atom's identity against the
ROOT SEGMENT atoms of all atom spaces (a weak registry filled by
`make-mdl-atom-space`), so the answer does not depend on which space is
current. CHTYPE gains SEGMENT as a LIST-primtype target that shares cells;
CHTYPE to FORM stays unsupported (not needed by the game).

Consequences: no game-specific path; source line/column of reader segments
is dropped (unused). Printing SEGMENTs stays strict. Alternatives rejected:
a second CHTYPE-only segment struct (two representations of one MDL TYPE,
diverging TYPE/NTH/`==?` behaviour); copying the cells on CHTYPE (the
reference shares, and INSERT-OBJECT relies on the shared tail).

**Amendment (independent review, 2026-11-23):** SEGMENT identity is tested
against the current atom space's ROOT SEGMENT atom, exactly as FORM is
(`mdl-form?`): a SEGMENT value from another session is not spliced here, and
a user TYPE atom merely named SEGMENT (or LIST/FALSE) never takes a built-in
CHTYPE branch — CHTYPE dispatches on the target being a ROOT built-in TYPE,
not on its PNAME. Hosts that inspect session values check TYPE inside the
session (e.g. `mdl-session-call session "TYPE" v`).

## ADR-0057: CHTYPE to CHARACTER keeps the 0–127 CHARACTER range

Status: accepted (M4 S3, 2026-11-23).

Context: frontier F2/F2b (every `<prep> what?` orphan prompt and every
PRSTR use) needs `<CHTYPE fix CHARACTER>` (FOOSTR, `77np.mud:241`). The
pinned reference treats CHARACTER as a raw retag of a 36-bit WORD: any
value is accepted and comes back unchanged through ASCII, and out-of-range
CHARACTERs print implementation bytes
(`docs/evidence/M4/CHARACTER-CHTYPE-REFERENCE.md`). This runtime's
documented CHARACTER contract is ASCII 0–127: `ASCII` FIX → CHARACTER is
0–127 (the reference agrees there), READSTRING refuses input codes above
127, and UNPARSE/PRINC are specified only for that range.

Decision: CHTYPE to the ROOT CHARACTER TYPE accepts a WORD-primtype value
(FIX, WORD, CHARACTER, NEWTYPE of WORD; not FLOAT) whose signed value is
0–127 and returns the runtime's one CHARACTER representation (the typed
WORD value made by `mdl-character`), so `==?`, STRING PUT and MEMQ treat it
exactly like `!\c`. Other codes are a strict error. CHARACTER → FIX/WORD
was already supported and is unchanged.

Consequences: the game-reachable values (at most 122: PNAME characters ≤ 90
plus 32, recorded by the reference probe `game-word-pname-range`) behave as
in the reference; out-of-range CHTYPEs, which the reference accepts, fail
loudly instead of producing an unprintable value. Following the reference
would have required widening CHARACTER to a 36-bit code everywhere (STRING
storage, printing, input) — a larger change with no game use. Alternatives
rejected: accept any code (conflicts with the ASCII and input contract and
the host string representation); refuse WORD/NEWTYPE sources (the reference
accepts them and they cost nothing).

**Amendment (independent review, 2026-11-23).** (1) A second game use: the
balloon's room names `VAIRn` step their digit with `<PUT .S 5 <CHTYPE <+|-
<CHTYPE <5 .M> FIX> 1> CHARACTER>>` (`77act2.mud:526` rising, `:578`
falling); the codes are digits ±1 (48–53), inside the range, and a unit case
covers both directions. (2) FLOAT is refused only as a direct source: a FLOAT
first CHTYPE'd to WORD or to a NEWTYPE of FLOAT reaches the WORD branch and
is then governed by the 0–127 range check alone (its bits use this runtime's
existing FLOAT word encoding); not game-reachable. (3) The 0–127 range binds
CHTYPE, ASCII and READSTRING; the reader and STRING literals can still carry
a CHARACTER above 127 (e.g. `!\é`, `<1 "é">`), so `<CHTYPE <CHTYPE !\é FIX>
CHARACTER>` is refused although the original CHARACTER existed; not
game-reachable, a candidate for a separate reader slice. (4) Pre-existing:
a host Racket `char` passed through the embedding API (`mdl-session-call`)
is typed CHARACTER but CHTYPE of it to FIX/WORD fails in `word-bits-of`; MDL
code cannot produce host chars.

## ADR-0058: TOP is a shared-storage view keeping the TYPE; CHANNEL storage refused

Status: accepted (M4 S4, issue #157, 2026-11-23).

Context: frontier item 3 (`77np.mud:126`, SPARSE's dangling preposition)
and `take all`/`drop all`/`put all in ...` (EVERYTHING, `77rooms.mud:1284`)
need the TOP SUBR. The pinned reference
(`docs/evidence/M4/TOP-REFERENCE.md`) returns the same storage from its first
element, keeps the argument's TYPE, refuses LIST-primtype values and TUPLEs,
and shows two hidden slots before a terminal CHANNEL's element 1, of which
this runtime models one (M3 BACK, issue #110).

Decision: TOP reuses the existing view representation. For an `mdl-array`
the result is a new view record over the same Racket vector and the same
UTYPE cell, start 0, length the vector's length; for a STRING it is a view
over the same backing string from 0 to its end. A TYPE tag
over the array is re-applied to the result. No element is copied. Everything
else is a strict `Bad type for TOP` error. Storage that backs a CHANNEL
(registered when the runtime makes the channel, independent of atom space)
is refused, because a TOP of it here would yield a 20-element value whose
slot 1 is the reference's slot 2.

Consequences: SPARSE's TOP returns PRSVEC itself (`==?`), EVERYTHING's
`<==? .SUV .TUV>` ends its fill loop as in the reference, the balloon's
`<TOP ,SCRSTR>` writes into SCRSTR's storage. The script commands are
unaffected (they fail earlier at OPEN). Alternatives rejected: copying
(breaks `==?` and the SCRSTR/OBJ-UV aliasing the game relies on); returning
the PRIMTYPE instead of the argument's TYPE (the reference keeps FOO and
CHANNEL; the manual's general PRIMTYPE remark is not what Confusion does);
adding the reference's first CHANNEL slot now (it is the echo/script LIST,
whose effect this runtime does not implement, so a PUT there would be a
silent no-op; revisit when scripting is supported).

**Amendment (maintainer decision, 2026-11-23): BACK keeps the TYPE too.**
`mdl-back` preserves the argument's exact MDL TYPE — the TYPE atom itself,
never its PNAME — for every array-backed value: the terminal CHANNEL (as
before) and any NEWTYPE of VECTOR, UVECTOR or STRING. Shared storage, the
UVECTOR UTYPE cell, mutation visibility and the bounds checks are unchanged.
The resulting policy: REST drops a custom TYPE tag; BACK and TOP keep the
argument's TYPE, matching pinned Confusion. This departs from the manual's
general statement (§7.6.2) that BACK yields the array PRIMTYPE; the
discrepancy is acknowledged and the reference is followed. It revises the M3
BACK rule (CHANNEL-only), which was the source of the TOP/BACK `==?`
inconsistency found in the S4 review.

## ADR-0059: Zero-argument MAX is the negation of `<MIN>`

Status: accepted (maintainer decision, 2026-11-23; M4 S5a, issue #122,
PR #159).

Acceptance scope: the maintainer approved keeping this zero-argument
`<MAX>` behaviour and its recorded deviation from pinned Confusion. The
approval covers only the zero-argument `<MAX>` discrepancy. It does not
authorize other deviations from Confusion or any relaxation of strict
unsupported behaviour. The pinned reference and the parity tests are
unchanged. Regression coverage for both identities stays explicit:
`tests/min_test.rkt` and `tests/max_test.rkt` pin the exact value, TYPE
FLOAT, PRIMTYPE WORD, the CHTYPE FIX/WORD images and the comparison
boundaries. "Least FLOAT" here means the least FLOAT this runtime
represents and converts (the negation of `<MIN>`); the wording note below
still applies.

Context: the manual (§3.5) gives "the least FLOAT" as MAX's zero-argument
identity, symmetric to MIN's "greatest FLOAT". R6 decided `<MIN>` is the
ordinary FLOAT (2^27−1)·2^100, the greatest PDP-10 single-precision value
(SEMANTICS "M3 MIN"). Pinned Confusion's `<MAX>` is the host `DBL_MIN`, the
smallest *positive* double (`docs/evidence/M4/MAX-REFERENCE.md`, case
`zero`): it is greater than every negative number, so it is not an identity
for MAX, and the same seed makes the reference return `0.0000000` for
`<MAX -1.5 -2.5>` (case `float-negative`). No source form calls MAX with
zero arguments; the game's uses are two-argument FIX (`78melee.mud:447-448`,
`77rooms.mud:741`).

Decision: `<MAX>` returns `pdp10-least-float` = −(2^27−1)·2^100, the exact
negation of `<MIN>`, an ordinary host flonum like every other FLOAT. Its
PDP-10 word image (CHTYPE to FIX/WORD) is 400000000001₈ (FIX −34359738367).
Non-empty MAX folds from its first argument (never from a seed), so negative
FLOAT arguments give the largest argument.
Wording note (independent review): this is described as the negation of
`<MIN>`, not as "the least PDP-10 FLOAT". PDP-10 negative FLOATs are two's
complement, so the word 400000000000₈ (−2^127) is very likely also a valid
normalized negative below 400000000001₈; it is a rejected candidate here
because this runtime's checked word-image conversion (`float-word-bits`,
R6) refuses exponent field 256, and the symmetry with the decided `<MIN>`
is the stated rationale. This could not be verified against MUDDLE's ARITH
source (not in the pinned sources).

Consequences: MIN and MAX are symmetric; `<MAX <MAX> x>` is x (as FLOAT)
for every x in the PDP-10 FLOAT range (the reader can produce FLOATs below
it, for which the result is the sentinel, as for R6's `<MIN>`), and the value takes part in arithmetic, comparison and CHTYPE
like `<MIN>`. Recorded deviation from the reference for `<MAX>` itself and
for all-negative FLOAT MAX with a FLOAT first argument; no game expression
reaches either. Alternatives rejected: copying the reference's DBL_MIN
(not the 36-bit target, not an identity, and the cause of the reference's
negative-FLOAT results; the PDP-10 analogue, the smallest positive FLOAT
0.5·2^-128, has the same defect); a strict error for `<MAX>` (consistent
with "do not invent", but asymmetric with the decided `<MIN>` although the
manual defines both identities in the same sentence).

## ADR-0060: TYPE of compiled DEFINEs and host built-ins by representation registry

Status: accepted (M4 S5b, frontier F4, 2026-11-23). (ADR-0059 is reserved by
the separate MAX branch.)

Context: SWORD (`77act1.mud:1903`) evaluates `<TYPE? ,SWORD-GLOW NOFFSET>` on
every `take sword`. The GVAL of a DEFINE without quoted formals is a Racket
closure made by the compiler, and `mdl-type-name` had no TYPE for it, so the
game stopped with `mdl-type: unsupported MDL type #<procedure>`. The pinned
reference (`docs/evidence/M4/FUNCTION-TYPE-REFERENCE.md`) gives FUNCTION for
every DEFINE shape and SUBR for every built-in this runtime binds (and FLOAD).
ADR-0049 established `mdl-subr`, a struct with `prop:procedure`, for REP.

Decision: the TYPE of a host applicable is decided by membership in a
runtime-owned `eq?` registry, never by a PNAME or GVAL name:

- `mdl-define!` (only the compiler's DEFINE path calls it) already records
  every compiled DEFINE closure in the weak `compiled-function-formals`
  table; membership in that table now means TYPE FUNCTION. The closure
  itself is unchanged, so application, GVAL/SETG identity and `==?` and the
  call fast path are untouched (no wrapper, no extra indirection);
- the values of `builtin-table` form a fixed `eq?` set whose TYPE is SUBR;
- the loader's FLOAD, the only other caller of `mdl-define!`, becomes an
  `mdl-subr` (TYPE SUBR, as REP; reference `<TYPE ,FLOAD>` = SUBR) through a
  new `mdl-define-subr!`, so it no longer counts as a FUNCTION.

Every other host procedure keeps the strict unsupported-type error. Values
that need the MDL body LIST (CHTYPE to LIST, LENGTH/NTH/REST, printing) stay
strict errors because a compiled closure has no such LIST.

Consequences: `take sword`, `take all` and the sword demon run as in the
reference; ROBBER, FUNCTION-PRINT and CEVENT's NOFFSET tests become
reachable with the reference answer. TYPE of RDCOM (REP after CONTIN) is
FUNCTION, so BLO's `<TYPE? ,REP SUBR FSUBR>` is FALSE as in the reference.
Alternatives rejected: wrapping compiled closures in a struct like
`mdl-subr` (changes the representation every call site sees, adds an
application indirection, changes Racket object names in diagnostics);
deciding by the DEFINE's name or by `object-name` (PNAME dispatch,
ADR-0056); giving SUBR a PRIMTYPE (would open CHTYPE of a SUBR to WORD
conversions that the runtime cannot honour); keeping the MDL body LIST of
every compiled DEFINE to support CHTYPE/LENGTH/printing (a larger change
not needed by the game; recorded as a deviation).

## ADR-0061: Game persistence by deterministic replay first (hybrid strategy)

Status: accepted direction (maintainer, 2026-11-23): hybrid persistence, deterministic replay first. Decisions taken: the resumed clock, any runtime with the same game sources, saves at the command prompt only. The implementation is validated by the WP4.5 proof of concept. ADR-0048 and ADR-0055 stay in force; this ADR does not amend them. Epic #163, WP4.

### Context

Today SAVE is an in-session record (ADR-0048). OPEN is limited to RECORD's denied form (ADR-0055). RESTORE is a strict error, and `run-zork` never writes files. Players need saves that survive a process exit.

The facts below come from the pinned 1977 source and the current runtime.

**1. Host inputs to the game.** The game reads only two kinds of host input:

- **The session clock.** GETTIMEDATE is the clock's only reader (`mdl/runtime/clock.rkt`, ADR-0052). The game calls it through DSKDATE (`81tell-repl.mud:57`), which packs the time of day in *half-seconds* and so uses the microsecond field. DSKDATE has these callers:
  - START, for INTIME (`77rooms.mud:277`) and to seed RANDOM (`:291`);
  - GET-TIME / PLAY-TIME (`:174`);
  - the VERSION text (`:158`);
  - DO-SAVE and DO-RESTORE (`:389`, `:414`).
- **Terminal input.** READSTRING on INCHAN. (READCHR appears only inside comment strings of the patched source, `77rooms.mud:617-618`, `77act1.mud:1075-1076`, and is not implemented by this runtime.)

The user name is the constant `"MTRZORK"` (GXUNAME, `81tell-repl.mud:93`). GETSYS runs only when MUDDLE > 100. RANDOM is the session-owned 36-bit two-word generator (`mdl/runtime/random36.rkt`). The GC interrupt source is the logical allocation ledger, not the host GC (#113 R2).

**2. RNG state.** It is two unsigned 36-bit words. An explicit `<RANDOM s1 s2>` overwrites one or both words before stepping. `mdl-session-random-snapshot` (`mdl/loader.rkt`) returns a detached copy.

**3. Native save semantics (for reference only).**
- DO-SAVE banks PLAYED-TIME and stamps THEN.
- DO-RESTORE resets INTIME to the restore time. It also refuses with "It's too soon." and then QUITs if fewer than 2400 half-seconds (20 minutes) have passed since the save, unless the player is in WINNERS (`77rooms.mud:404-436`).
- The manual (§11.6) says RESTORE resumes execution at the earlier SAVE; it does not return to RESTORE's caller.

None of this is in scope here.

### Decision

Host-managed persistence first uses **deterministic replay**.

A checkpoint is a versioned record of:
- the initial conditions;
- every host input the session consumed, in order;
- the verification state at the save point.

Restore boots a fresh session from the unchanged sources and replays those inputs. It then **verifies** that the reconstructed state equals the recorded verification state. A mismatch is a restore failure, and nothing is overwritten.

**Option A, direct snapshots** (serializing runtime state), stays open as a later optimisation. It must be validated against replay. It is not used first, because:
- compiled closures, ports, continuations and shared or cyclic MDL structure cannot be serialized safely without custom, reviewed encoders;
- replay reuses the exact code path that the native parity tests already certify.

#### 1. RNG contract (`rng/v1`)

The checkpoint records:
- the algorithm id `mdl-random36/v1`;
- the initial-seed provenance: the START DSKDATE word and the clock observation it came from;
- both current state words, first then second, as unsigned 36-bit values.

A draw count goes in **only if** it can be counted outside the generator without changing any MDL-visible result; otherwise it is left out.

On restore, the RNG state comes from replay alone and is then compared with the recorded words. The state words are never written into a session. RANDOM is never reseeded from the wall clock. No second generator is introduced.

#### 2. Clock modes

Four `mdl-clock` constructors exist; ADR-0052's interface is unchanged.

- **real** — existing.
- **fixed** — existing.
- **recording** — wraps a source clock. It appends each `(seconds, micros)` read, in order, to a session-owned observation log. The time zone and the epoch base are recorded once.
- **replaying** — serves the logged observations in order. These are strict errors:
  - a read after the log is exhausted (an extra read);
  - observations left unread when replay ends (a missing read);
  - a read whose call position does not match the log (an ordering divergence). Each observation carries its input-turn index, so the check is "observation *i* belongs to turn *t*".

**Replay-to-live transition — decided: the resumed clock.** After replay, the session switches to a **resumed clock**:

    live = last recorded observation + (wall time elapsed since the restore)

The reasoning:
- The original game excludes non-running time from "played time" (DO-SAVE banks PLAYED-TIME; DO-RESTORE resets INTIME).
- The host must not change game globals to imitate that.
- A clock that continues from the save keeps GET-TIME and PLAY-TIME continuous without touching game state.

The cost is that DSKDATE's date and time of day no longer match the host's. Its only other visible use is the VERSION text.

The rejected alternative is a raw wall clock after restore: GET-TIME would then count the downtime, which the original never does.

Turn-based events (CLOCK-INT, `77rooms.mud:1657`) advance only per game turn. Downtime never advances them.

#### 3. Input log and save boundary

The checkpoint records every input unit the session consumed: the raw characters of each completed READSTRING call (escape `!` and stop character included) and why it ended (stop character, full buffer, end of input), observed host-side inside READSTRING. Interrupts are handled as follows:
- interrupts the host delivers (the DrRacket break) are not replayable, and any session in which one was delivered cannot be saved;
- the logical GC interrupts are internal and must reproduce on replay; the proof checks this.

A save can be taken **only at the RDCOM command prompt**: the READSTRING in RDCOM, `77rooms.mud:616`, with no pending orphan question and no unread input. After the S7 parser evidence the rule is concrete (SEMANTICS "M4 WP4"): the READSTRING must be RDCOM's own (its frame shape, `IVEC` FALSE, INBUF/INCHAN/READER-STRING, `,REP` = `,RDCOM`), `<1 ,ORPHANS>` must be FALSE, and the previous READSTRING must have ended at its stop character. Saves are refused:
- inside a parser follow-up (`Which door?`, an orphan prompt);
- during YES-NO prompts;
- after a strict runtime error;
- after QUIT or FINISH.

The startup SAVE-IT record (ADR-0048) is separate. It is never a player save, and a player save never replaces it.

#### 4. Format and boundary

A checkpoint is a bounded, versioned JSON document. It contains no closures, ports, continuations or executable data, and is read with a schema-checked parser only. Its fields:
- `format` (`mdl-zork-replay/v1`);
- `rng` (`rng/v1`);
- source provenance: the upstream SHAs and a manifest hash of the game files. A mismatch is a hard reject;
- runtime provenance: the runtime commit and the Racket version class. Recorded for diagnosis only; it does not by itself reject a checkpoint;
- the time zone and the boot clock mode;
- the observation log;
- the input log;
- the verification block: both RNG words, MOVES, a canonical digest of selected game state, and a transcript digest;
- an integrity checksum over the canonical encoding.

Limits: a maximum input and observation count and a maximum byte size. A checkpoint that fails any check is rejected with a specific error before any session is created:
- wrong format or RNG version;
- source provenance mismatch;
- checksum mismatch;
- oversized.

In the proof of concept, the checkpoint is a detached value that tests write under `$TMPDIR`. `run-zork` and MDL code gain **no** file access. A later player-facing slice adds a host-only save directory (atomic writes, confined slot names, no player-controlled paths), and that needs its own accepted amendment of ADR-0055's no-file policy for the launcher.

#### 5. Replay side effects

Replay runs with:
- output written to a capture port that is discarded after its digest is compared;
- no file writes, given ADR-0055;
- the replaying clock.

Visible output is shown only after verification succeeds. A failed restore never touches an existing live session; it uses a fresh session that is then dropped.

### Consequences

- Restore cost grows linearly with the number of commands replayed. It must be measured; the proof reports seconds per 100 commands. Option A, or replay from intermediate verified snapshots, is the mitigation if it proves too slow.
- Compatibility (decided): a checkpoint is accepted by **any runtime whose game-source manifest hash matches**. The runtime commit and Racket version are recorded for diagnosis only.
  - Replay verification is the safety net: both RNG words, MOVES, the state digest and the transcript digest must match at the save point. If they don't, the restore fails with a "this runtime does not reproduce the saved game" error, and no session is created.
  - A runtime change that alters game behaviour therefore surfaces as a verification failure, never as silently different state.
- Native SAVE/RESTORE (DO-SAVE, DO-RESTORE, SAVE-GAME and RESTORE-GAME with OPEN "PRINTB"/"READB") stays unsupported and strict. It needs a separate decision, which must cover continuation semantics, the 20-minute rule, and file channels.

### Decisions recorded (maintainer, 2026-11-23)

1. Replay-to-live: the **resumed clock**.
2. Compatibility: the **same game sources, any runtime**, with replay verification as the gate.
3. Save boundary: the **command prompt only**.

### Implementation (feat/m4-replay-persistence, WP4.1–WP4.5)

Verified while implementing; the decisions above are unchanged.

- Module placement: the generic replay machinery (canonical checkpoint
  encoding and strict parser, recording and restoring runs, verification)
  is `mdl/replay.rkt`, a host module beside `mdl/loader.rkt`; it is not an
  MDL primitive and is not reachable from MDL. The Zork rules (the RDCOM
  save boundary, the selected game state, the seed provenance) are the
  profile in `zork/persistence.rkt`. Neither writes files; `run-zork` is
  unchanged. Clock modes are in `mdl/runtime/clock.rkt`.
- Input is observed inside READSTRING by a session-owned, host-only
  observer (`make-mdl-session #:input-observer`), so the log is exactly
  what MDL consumed. The draw count is counted in the generator state; it
  never changes a RANDOM result and is not visible to MDL.
- Semantics, limits and error stages: SEMANTICS "M4 WP4: session clock
  modes and deterministic replay checkpoints". Evidence:
  `docs/evidence/M4/WP4-REPLAY-PERSISTENCE.md`.
- Trust model (review L4): the checkpoint checksum is integrity only, not
  authentication. A player can edit and reseal the input or clock log,
  including the clock observations that choose START's RANDOM seed.
  Verification guarantees only that the restored state is what the real
  game produces from the recorded inputs; it does not prove the inputs were
  played. A player-facing slice that needs tamper resistance must add
  authentication (for example a host-held key) as a separate decision.
- Selected verification state (review L5): the verification block holds a
  selected state (34 fields in the Zork profile). Object positions beyond
  those fields, room flags and most globals are covered only by the
  transcript digest and by the reconstruction itself. Replay is the
  reconstruction; verification guards against a runtime that diverges.

**Note (M4 S9, 2026-11-24).** SLEEP and TIME add no clock observation and no
checkpoint field: SLEEP's wait depends only on the clock's liveness
(non-live while replaying, live once the clock resumes), and the TIME
counter is reproduced by replaying the same inputs from a fresh boot. A
checkpoint taken after a SLEEP or TIME restores exactly and its replay never
waits (`tests/replay_sleep_time_test.rkt`). The format `mdl-zork-replay/v1`
is unchanged.

## ADR-0062: M4 scenarios run once per scenario, checked at every READSTRING entry

Status: proposed (2026-11-24, branch `feat/m4-single-run-runner`; Phase 1 of
epic #163). Evidence: `docs/evidence/M4/SINGLE-RUN-RUNNER.md`.

- The ten M4 native-parity scenario tests share one driver,
  `tests/m4_scenario_runner.rkt`. Its default single-run mode boots once,
  feeds all commands, and at each READSTRING entry k compares the output so
  far with the native prefix-k stdout up to its prompt (the probe's
  `prompt_head` split, strict on the prompt count) and the read-only
  checkpoint with the reference diagnostic checkpoint k; at end of input it
  compares the whole transcript with T1 and the end checkpoint n. The
  per-prefix reboot protocol stays available (`M4_SCENARIO_MODE=per-prefix`,
  `make m4-scenarios-per-prefix`) and is the only way native end-of-input
  tails of every prefix are re-executed.
- End-of-input tails: prefixes whose native tail is not exactly
  `Beg pardon?\n>` or whose end checkpoint differs from the (declared,
  reference-verified) transform of the entry checkpoint are re-run per
  prefix automatically. The coverage the single-run mode does not keep is
  stated in TESTING ("M4 scenario runner").
- Snapshots are taken by the host-only READSTRING observer (ADR-0061); no
  runtime hook was added. A snapshot must not change the RANDOM state or the
  logical storage ledger (game-visible, ADR-0044); a checkpoint field whose
  read evaluates allocating game code (`LIT?` reaches LFCN, which evaluates a
  FUNCTION form) is read only after end of input (`#:end-only-keys`), never
  mid-run.
- Comparison stays ADR-0053 D1 only, byte for byte. Failures write a
  divergence report `artifacts/scenario-divergence/<scenario>-<mode>.json`
  and still fail the test.
