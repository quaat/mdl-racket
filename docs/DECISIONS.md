# Architecture decision records

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
