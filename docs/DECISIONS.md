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
