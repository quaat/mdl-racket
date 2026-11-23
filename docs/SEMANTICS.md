# MDL semantic compatibility ledger

This is a living ledger. A reader parsing a token is **not** a verified
implementation. Every entry must ultimately reference the MDL documentation,
a minimal Confusion probe (source + output), and a Racket regression test.

## M0 reader lexical rules under test

- A semicolon comments out the following **single MDL object**, including a
  multiline string or nested form; it does not end at newline. The reader
  currently discards comments and their associations, so the AST does not
  preserve that historical metadata. Reference: *The MDL Programming
  Language*, [§5.5](https://mdl-language.readthedocs.io/en/latest/05-simple-functions/)
  and pinned Confusion `mdl_read.cpp` (`MDL_C_SEMI`). Tests:
  `tests/parser_test.rkt`.
- Uniform vectors use `![` and `!]`; the closing `!` is optional in source
  input. Both forms occur in the selected 1977 files. Reference:
  *The MDL Programming Language*,
  [§7.2.3](https://mdl-language.readthedocs.io/en/latest/07-structured-objects/).
  The pinned Confusion reader has a separate `MDL_C_CLOSEUVECTOR` branch;
  acceptance of a bare `]` in Confusion remains unprobed. Tests:
  `tests/parser_test.rkt`.
- `,` is read syntax for `GVAL` of the following object. The AST stores a
  plain atom name for `,NAME` and a child node for `,<FORM ...>`. Evaluation
  of computed references is supported in the M1 binding subset. Reference:
  *The MDL Programming Language*,
  [§4.2.2](https://mdl-language.readthedocs.io/en/latest/04-values-of-atoms/).
  Tests: `tests/parser_test.rkt`.
- `#WORD` followed by a decimal or octal numeric literal is read as one
  source-located typed node. Unsupported typed literal names remain AST
  data and fail explicitly at compilation. Reference: the manual's
  [machine-word chapter](https://mdl-language.readthedocs.io/en/latest/18-machine-words-and-bits/).
  Tests: `tests/parser_test.rkt` and `tests/word_test.rkt`.
- Backslash in a string quotes the following character. In particular,
  `\n` in source represents `n`, not a newline escape. Reference:
  *The MDL Programming Language*,
  [§7.2.4](https://mdl-language.readthedocs.io/en/latest/07-structured-objects/)
  and pinned Confusion `mdl_read.cpp` (`READSTATE_INSTRING_LIT_BS`). Test:
  `tests/parser_test.rkt`.

| Construct | Current supported subset | Remaining target behavior | Evidence |
|---|---|---|---|
| `<DEFINE>` | simple fixed arity, dynamic parameter bindings | OPTIONAL/AUX/TUPLE, activation records | M1 issue #7 |
| `<SETG>`/`,GLOB` | atom-identity global table; computed atom operand | PROCESS behavior and full source loader | M1 issue #7 |
| `.LOCAL` | atom-keyed dynamic frames for simple functions | explicit ENVIRONMENT and UNSPECIAL rules | M1 issue #7 |
| `<>` / `#FALSE` | distinct FALSE with mutable LIST payload | full type-directed print/eval | M1 issues #3/#5 |
| `<COND>` | value-preserving branches and single test evaluation | later control forms | M1 issue #3 |
| `AND`/`OR` | short circuit with MDL FALSE values | full expression compiler | M1 issue #3 |
| MDL lists | mutable shared tails, REST/PUT/PUTREST | GROW/BACK/TOP and segments | M1 issue #5 |
| MDL vectors | VECTOR/UVECTOR shared REST views | full STRING/BYTES and growth | M1 issue #5 |
| `OBLIST` / `ATOM` | identity-bearing values and direct lookup/insertion | dynamic reader lookup, associations, bucket geometry | M1 issue #4 |
| `NEWTYPE` / `CHTYPE` / `NEWSTRUC` | NEWTYPE and structured CHTYPE subset; NEWSTRUC unsupported | declarations, print/eval hooks, NEWSTRUC | M1 issue #6 |
| `PROG` / `REPEAT` / `RETURN` / `AGAIN` | named and unnamed frames; bare and explicit transfers to PROG/REPEAT | GO/TAG cross-function transfer is partial | M2 issues #20, #26, #28 |
| `DEFINE` formals | required, OPTIONAL/AUX/TUPLE/ARGS sections with in-frame defaults; leading activation ATOM and `"NAME"`/`"ACT"` markers | `"BIND"`/`"CALL"` markers, quoted formals | M2 formals and control slices |
| `GO` / `UNWIND` | GO to labels in the current function's PROG/REPEAT; UNWIND cleanup on MDL transfers only, never on raised errors (ADR-0051) | TAG values, GO across function boundaries | M2 control slice |
| MDL octal `*777*` | FIX input with 36-bit boundary conversion | full reader radix controls | M1 issue #8 |
| `#ROOM {...}` / typed macros | AST recognition only | macro expansion with original semantics | **NOT IMPLEMENTED** |
| `READSTRING` / `LEX` / `EPARSE` | branch stack #141 only: READSTRING `<READSTRING buffer channel [stop-string]>` from a host-supplied port (ADR-0050); the original LEX/parser runs for the six house-boot commands (scoped INTERACTIVE PASS); not on `main` | default channel, FIX stop, EOF routine, `!` in input (open: pinned Confusion treats it as an escape), parser coverage beyond the six commands | ADR-0050, `evidence/M3/S7-INTERACTIVE.md` |
| `SAVE` / `RESTORE` | branch only: SAVE is an in-session record returning `"SAVED"`, no file (ADR-0048); RESTORE strict error | stable per-player snapshots; validated against reference | ADR-0048 |
| random/time/events | branch only: session-owned 36-bit RANDOM; GETTIMEDATE reads the host clock; user EVENT/HANDLER, dispatcher, logical GC events (dispatcher and registration also on `main`) | fixed session clock (#135), determinism proof, original turn-based scheduling | `evidence/M3/RANDOM-START.md` |

## Priority Confusion probes

1. FALSE: `<>`, `#FALSE (1)`, `NOT`, `COND`, `OR` return behavior.
2. Mutable LIST: `REST` aliases, `PUT`, `PUTREST`, `SPLICE-OUT`, nested views.
3. ATOM/OBLIST: creating same name under two oblists, GVAL/LVAL binding.
4. Control transfer: `PROG`, `RETURN` from helper, `AGAIN`, `UNWIND`.
5. Arithmetic: PDP-10 36-bit operations, signed values, octal parsing.
6. Parser: first-five-letter word resolution; prepositions and ambiguous objects.
7. Game events: turn counting, NPC/demon scheduling, RNG seed discipline.

### Probe protocol

For each semantic question, save:

- `probe-name.mud` (the actual input), `probe-name.reference.txt`, and
  `probe-name.expected.json` or an explicit unsupported state;
- source path, source commit, Confusion commit, interpreter hash;
- input commands/expressions, stdout/stderr, exit code;
- equivalent Racket test, result and discrepancy adjudication.

The reference interpreter is not necessarily an exact PDP-10 interpreter.
When its semantics and the original manual differ, record the discrepancy
before deciding how the new runtime should behave.

## M1 issue #3 specification: FALSE values and truth operators

The [MDL manual, chapter 8](https://mdl-language.readthedocs.io/en/latest/08-truth/)
specifies `FALSE` as a structured type with `LIST` primtype. `<>` produces
`#FALSE ()`; `#FALSE (items)` is direct representation, so its items are data,
not evaluated expressions. Every non-`FALSE` MDL object is true, including the
atom `NIL`, zero, and empty lists. `T` is an atom, not a host Boolean.

`NOT` returns `T` for any FALSE and empty FALSE otherwise. `AND` evaluates
left to right, stops at and returns the first FALSE, or returns its last value;
zero arguments return `T`. `OR` stops at and returns the first non-FALSE, or
returns its last FALSE; zero arguments return empty FALSE. `COND` evaluates
each test once, returns the selected clause's last value (or test for a
test-only clause), and returns the last FALSE if no clause succeeds. Its
documented minimum is one clause. These operators must preserve payloads and
skip unselected side effects.
The manual's equality rule for empty LIST primtype values means two empty
FALSE values of the same type are `==?`. Distinct nonempty FALSE payloads are
not `==?`, though equal payloads are `=?`.
The same manual says evaluating a FALSE neither copies it nor evaluates its
elements. A nonempty FALSE literal in a function must therefore retain its
identity across calls. Separately written nonempty literals must retain
distinct identities, even when their payloads compare structurally equal.

Pinned Confusion probe inputs and raw output are in
`docs/evidence/M1/false-cases.json` and `false-reference.json`; the latter
records interpreter SHA-256 and exit codes. All thirteen cases exited zero with
empty stderr. Observed: `NIL` is an `ATOM` and `<NOT NIL>` gives empty FALSE;
`AND` returns `#FALSE (1)`, `OR` and `COND` return their last `#FALSE (2)`;
empty `AND` gives `T`, empty `OR` gives `#FALSE ()`; a test-only `COND` gives
`7`; short-circuited `SETG` forms do not execute.
Confusion also gives `T`, empty FALSE, and `T` for `==?` on two empty FALSEs,
`==?` on two independently read payload FALSEs, and `=?` on those payloads.
The review follow-up cases give `T` for two calls returning one literal and
empty FALSE for two distinct literals in one function; both processes exited
zero with empty stderr.

Implementation tests for this slice belong in `tests/false_test.rkt` and
`tests/parser_test.rkt`. The payload is retained as reader data; mutable LIST
view operations, general type introspection, and full atom/OBLIST semantics
remain separate M1 issues. Unsupported payload syntax must fail explicitly.
`TYPE` is supported here only for FALSE and placeholder ATOM values, returning
their MDL type atoms; other types still raise an explicit unsupported error.

## M1 issue #4 specification: ATOM and OBLIST identity

The [MDL manual, chapter 15](https://mdl-language.readthedocs.io/en/latest/15-lexical-blocking/)
defines an OBLIST as a table of atoms keyed by PNAME. Reading the same name in
the same OBLIST returns the same ATOM; the same PNAME in different OBLISTs
denotes distinct ATOMs. `<ATOM string>` creates a fresh uninterned atom.
`<MOBLIST name>` returns the existing named OBLIST or creates one. `<LOOKUP
string oblist>` does not insert; `<INSERT string-or-uninterned-atom oblist>`
inserts and errors on duplicate PNAME or an already interned atom. `REMOVE`
returns the removed atom and leaves it uninterned; `OBLIST?` returns its
current OBLIST or empty FALSE. `PNAME` returns a new string. Reader trailer
syntax `A!-OB` selects the OBLIST named `OB` and creates it if needed.

The exact inputs and raw outputs in `docs/evidence/M1/atoms-cases.json` and
`atoms-reference.json` corroborate seven cases in pinned Confusion (all exit
zero, empty stderr): ordinary quoted names intern identically; two calls to
`ATOM` differ; named `MOBLIST` calls return one object; `LOOKUP` finds an
inserted atom; same PNAME in two OBLISTs is neither `==?` nor `=?`; removal
clears membership and reinsertion preserves identity; trailer notation
interns within its named OBLIST. Confusion prints 17 buckets for a default
MOBLIST, while the manual says 13. Bucket geometry is not part of this slice;
the discrepancy remains explicit rather than treated as historical parity.

Tests for this slice belong in `tests/atom_test.rkt` and the existing compiler
tests. The implementation will use identity-bearing ATOM/OBLIST values;
ordinary quoted atom literals and reader trailers will resolve through an
atom space. Dynamic `.OBLIST` lookup, `BLOCK`/`ENDBLOCK`, associations, and
full structured OBLIST access remain separate work; unsupported calls must
error rather than silently return a placeholder.

## M1 issue #5 specification: mutable sequence views

The [MDL manual, chapter 7](https://mdl-language.readthedocs.io/en/latest/07-structured-objects/)
specifies 1-based `NTH`/`PUT`, `REST` with default offset 1, and `PUTREST`
that rewires the tail of a LIST-primtype head. `PUT` returns the original
structure. LIST tails are shared pointer chains; VECTOR and UVECTOR `REST`
values share backing storage. `REST` retypes its result to the source's
PRIMTYPE, so `REST` of FALSE returns LIST. UVECTOR elements must have one TYPE.
Quoted structured literals retain identity across function calls; separate
source literals remain distinct. Empty LIST values are canonical for `==?`.

Pinned Confusion inputs and raw output are in
`docs/evidence/M1/sequences-cases.json` and `sequences-reference.json`:
ten processes exited zero with empty stderr. Mutation through LIST, VECTOR,
and UVECTOR REST views was visible from each original structure. `PUTREST`
through a LIST tail changed the original `(1 2 3)` to `(1 2 8)`; `PUT` returned
its input by identity. `REST 0` and repeated `REST` of the same structure
were `==?`. `TYPE <REST #FALSE (1 2)>` returned LIST, and PUT on the FALSE
changed its payload. `UTYPE ![1 2!]` returned FIX. A separate deliberate
`<PUT ![1 2!] 1 "bad">` probe is retained in
`sequences-error-reference.json`: Confusion printed
`UVECTOR-PUT-TYPE-VIOLATION` and wrote an error to stderr, so the probe command
correctly exited 1 rather than treating the case as a passing transcript.

Tests for LIST/REST/PUT/PUTREST, VECTOR/UVECTOR aliasing, type restrictions,
boundary errors, and quoted literal identity belong in
`tests/sequence_test.rkt`. Dynamic type tags, GROW, BACK/TOP, segment syntax,
and full STRING/BYTES view semantics remain outside this slice and must fail
explicitly rather than being approximated.

## M1 issue #6 specification: type tags and constructors

The [MDL manual, chapter 6](https://mdl-language.readthedocs.io/en/latest/06-data-types/)
distinguishes `TYPE` from `PRIMTYPE`: FIX and FLOAT both have primitive
type WORD; FALSE has primitive type LIST. `TYPEPRIM` maps a type atom to its
primitive type. `NEWTYPE name base-type` registers a fresh type atom with
the base type's primitive storage and returns the name atom. `CHTYPE` returns
an object with the new TYPE and the same data part, and errors on primitive
type mismatch or dangerous conversion. The manual says `REST` of a new
structured type returns its primitive type. This slice supports changing
structured LIST, VECTOR, and UVECTOR types only, including FALSE/LIST casts.
Numeric word bit reinterpretation and `NEWTYPE` declaration patterns require
their own verified implementation and must error here.
The later issue #8 slice adds FIX/WORD reinterpretation; the declaration
pattern limit remains.

Pinned Confusion input and output are in `docs/evidence/M1/types-cases.json`
and `types-reference.json`: nine isolated processes exited zero with empty
stderr. `PRIMTYPE` and `TYPEPRIM` observations agree with the manual;
Confusion reports OBLIST's primitive type as UVECTOR.
`NEWTYPE M1-BOX VECTOR` returns `M1-BOX`; its tagged vector's TYPE is
M1-BOX, PRIMTYPE is VECTOR, and NTH remains available. A tagged LIST shares
mutable storage with its REST view, which has TYPE LIST. Casting FALSE to
LIST shares its payload: PUT on the resulting LIST changes the original
FALSE. A tagged UVECTOR retains UTYPE FIX, while REST has TYPE UVECTOR.
`CHTYPE` of a value to its current TYPE returns an identical value in the
observed case. Changing a VECTOR to a new TYPE changes `==?` and `=?` to
false against the original, while changing it back to VECTOR restores
identity. A FALSE-to-LIST-to-FALSE round trip also restores identity.
Tests for type registration, data sharing, primitive mismatch,
and unsupported conversions belong in `tests/type_test.rkt`.

The full MDL type table, declaration patterns, `PRINTTYPE`/`EVALTYPE`/
`APPLYTYPE`, general `#NAME` reader notation, dynamic atom blocking, and
WORD bit reinterprets remain outside this slice. They must raise explicit
errors if encountered by the compiler/runtime.

## M1 issue #7 specification: local and global atom values

The [MDL manual, chapter 4](https://mdl-language.readthedocs.io/en/latest/04-values-of-atoms/)
specifies separate local and global values on an ATOM. `SET`/`SETG` return
the assigned value; `LVAL`/`GVAL` and their `.`/`,` reader abbreviations
retrieve only the respective binding, with an error if unassigned. `VALUE`
prefers an assigned local and falls back to a global. `GUNASSIGN` removes the
global value. A FORM resolves an operator's global value before its local
value. Binding is by ATOM identity, not PNAME text.

The [manual, chapter 5](https://mdl-language.readthedocs.io/en/latest/05-simple-functions/)
specifies dynamic function parameter binding: a call temporarily binds its
parameter ATOMs, restores their prior local values on return, and leaves
other ATOMs' values intact. A `SET` of a free atom with no active parameter
binding therefore persists after the function returns. This slice models
those rules for simple required parameters with a stack of atom-keyed local
frames and a separate atom-keyed global table. The runtime will reject
unassigned reads and non-ATOM binding operands.

Nine pinned Confusion cases in `docs/evidence/M1/bindings-cases.json` and
`bindings-reference.json` exited zero with empty stderr. They confirm
local/global separation, VALUE precedence and fallback, parameter shadowing,
free assignment persistence, dynamic free reads, same-PNAME atoms in different
OBLISTs, computed uninterned global operands, and GUNASSIGN leaving local
values intact. A separate error suite in `bindings-error-reference.json`
records unassigned LVAL/GVAL failures and a reference discrepancy:
`UNASSIGN` is documented by the manual but has no global binding in this
Confusion build, so its attempted call reports `UNBOUND-VARIABLE`.
`UNASSIGN`, explicit ENVIRONMENT arguments, OPTIONAL/AUX/TUPLE formals,
PROCESS isolation, and compiled UNSPECIAL optimization remain unsupported.

## M1 issue #8 specification: 36-bit FIX and WORD operations

The [MDL manual, chapter 2](https://mdl-language.readthedocs.io/en/latest/02-read-evaluate-print/)
states that PDP-10 FIX ranges from `-34359738368` to `34359738367`.
Out-of-range decimal or octal FIX input becomes FLOAT; arithmetic that
produces an out-of-range FIX raises overflow. Asterisks around digits specify
an octal FIX literal. The [arithmetic chapter](https://mdl-language.readthedocs.io/en/latest/03-built-in-functions/)
specifies left-to-right arithmetic, FIX division truncated toward zero,
FLOAT contagion, and zero-argument identities `+`/`-` = 0 and `*`/`/` = 1.
The [machine-word chapter](https://mdl-language.readthedocs.io/en/latest/18-machine-words-and-bits/)
specifies 36-bit WORD storage, bitwise ANDB/ORB/XORB/EQVB, LSH, BITS,
GETBITS, and PUTBITS. CHTYPE between FIX and WORD reinterprets a word's
bits; WORD is not directly accepted by arithmetic. Numeric `==?` compares
type and data bits, not Racket object allocation.

Pinned Confusion observations are in `docs/evidence/M1/word-cases.json` and
`word-reference.json`: nine isolated successful processes, all exit 0 with
empty stderr. A separate deliberate error suite records missing `ROT` and
division by zero. Confusion agrees on in-range FIX arithmetic and low-bit
operations, but its native WORD output has 22 octal digits (64-bit storage),
`*777777777777*` remains a positive FIX 68719476735, and `</>` returns 0.
The historical manual requires a 36-bit WORD, an out-of-range octal literal
to become FLOAT, and zero-argument division to return 1. These deltas are
explicit; the Racket target follows the manual for them. `ROT` is documented
by the manual but unbound in this Confusion build. This slice implements only
the word operations used or independently corroborated in the selected
source; `ROT` remains unsupported pending another reference.

Racket tests in `tests/word_test.rkt` will cover reader octal and #WORD
literals, FIX range and overflow, left-to-right arithmetic, truncating
division, type-sensitive numeric identity, 36-bit masking, bitwise identities,
shift direction, BITS extraction/insertion, and negative inputs. FLOAT
precision and PDP-10 36-bit FLOAT bit reinterpretation, ROT, machine-specific
overflow-control switches, and random-number behavior remain unsupported.

## M1 integrated equality and evaluation order audit

Three isolated pinned Confusion cases in
`docs/evidence/M1/integration-cases.json` and `integration-reference.json`
all exited zero with empty stderr. FIX and FLOAT values with the same
mathematical magnitude are neither structurally nor identically equal;
two separately read large FIX values compare equal by both predicates.
Separate LIST and VECTOR values compare structurally equal but not
identical. Function arguments evaluate left to right: the second argument
observes the global mutation made by the first. Matching assertions are in
`tests/integration_test.rkt`. The compiler also rejects an unknown `#`
reader token, scientific numeric notation outside the supported compiler
subset, and malformed octal input explicitly; these checks fail before
runtime evaluation rather than creating ordinary atoms.

## M2 issue #20 specification: scoped PROG and bare RETURN

The [MDL manual, chapter 10](https://mdl-language.readthedocs.io/en/latest/10-looping/)
requires a `PROG` auxiliary LIST, followed by at least one body expression.
An optional activation name precedes the list, but this first slice supports
only the unnamed form. On entry, `PROG` creates an activation and binds each
auxiliary variable in order. A bare auxiliary ATOM is bound but unassigned;
an `(ATOM expression)` initializer evaluates in the environment being built,
then assigns the new binding. Thus a later initializer sees earlier new
bindings, while a variable's own initializer can still see an outer binding
of the same name. The last body value is returned on normal completion.

`RETURN` evaluates its value once, then exits the closest surrounding `PROG`
within the current function, skipping later expressions and unwinding local
bindings. With no value argument it returns the ATOM `T`. The
[manual's activation rules](https://mdl-language.readthedocs.io/en/latest/09-functions/)
say a plain function does not itself create an activation; a bare `RETURN`
inside a helper does not target a caller's `PROG`. Named activations, explicit
target `RETURN`, `REPEAT`, `AGAIN`, `GO`, and `UNWIND` remain unsupported and
must fail explicitly. This slice implements only current-function, unnamed
`PROG` activation behavior; it does not claim full MDL continuation parity.

The manual says the activation is generated before auxiliary binding. The
Racket slice therefore permits `RETURN` in an auxiliary initializer and
returns its value. Pinned Confusion instead exits by signal 11 on
`<PROG ((M2-X <RETURN 6>)) 99>`. This is a documented reference deviation,
not a passing differential case; see `prog-crash-cases.json` and
`prog-crash-reference.json`.

Pinned Confusion cases are saved in `docs/evidence/M2/prog-cases.json` and
`prog-reference.json`; expected errors are in `prog-error-cases.json` and
`prog-error-reference.json`. They test normal completion, left-to-right aux
initialization and shadowing, unassigned aux followed by SET, restoration of
outer locals, early/default/nested RETURN, mutation before escape, and errors
outside a PROG or across a function boundary. Matching Racket assertions
belong in `tests/prog_test.rkt`. The reference process ends each case with
`<QUIT>` and does not use time or randomness.

## M2 issue #22 specification: activation frame invariants

The [MDL function-activation chapter](https://mdl-language.readthedocs.io/en/latest/09-functions/)
defines an activation as a particular evaluation of a Function, invalid once
that evaluation finishes. The
[looping chapter](https://mdl-language.readthedocs.io/en/latest/10-looping/)
says a bare `RETURN` targets the nearest surrounding PROG or REPEAT within the
*current function*. This slice keeps only unnamed PROG and bare RETURN, but
represents each entry with a distinct runtime frame: an owner token for its
function invocation, an escape destination, and a live state. Active frames
form a dynamic stack. The nearest live frame owned by the current function is
the implicit target; a called function has its own owner and cannot consume
its caller's bare target. Normal completion, RETURN, and exception unwinding
remove the frame and invalidate it. Existing M2 reference cases test nested
PROGs and function boundaries; additional Racket tests cover frame identity,
lifetime, and cleanup. Named and explicit-target activations remain unsupported.

## M2 issue #23 specification: cyclic structural equality boundary

The [MDL manual's equality section](https://mdl-language.readthedocs.io/en/latest/08-truth/)
defines `=?` by same TYPE and structural content, and `==?` by identity. Its
[self-reference section](https://mdl-language.readthedocs.io/en/latest/07-structured-objects/)
shows that PUT and PUTREST can make LIST and VECTOR values cyclic, and says
printing them may never terminate. It gives no finite `=?` result for two
distinct cyclic structures with the same repeated content. The pinned
Confusion oracle returns `T` for a cyclic object compared with itself,
`#FALSE ()` when two cycles differ at their first element, but did not finish
the comparison of two distinct equal-content LIST cycles within two seconds;
comparing two distinct self-referencing VECTORs exited by signal 11. These
observations are not evidence for a general cyclic equivalence rule.

This slice preserves the identity result for the same cyclic object and
ordinary structural comparison for finite, acyclic values, including shared
substructure. It returns FALSE for cycles that differ before any repeated
comparison pair. If comparison revisits an active pair of distinct structured
objects, it raises an explicit unsupported-cyclic-comparison error rather
than looping, crashing, or inventing a coinductive equivalence rule. `==?`
continues to use identity. The boundary applies to LIST, VECTOR/UVECTOR,
FALSE payloads, and user-tagged structured values through the same recursive
comparison. Tests belong in `tests/equality_cycle_test.rkt`; focused reference
observations are under `docs/evidence/M2/equality-*`.

## M2 issue #26 specification: unnamed REPEAT and bare AGAIN

The [MDL looping chapter](https://mdl-language.readthedocs.io/en/latest/10-looping/)
defines REPEAT as a PROG with an implicit final `<AGAIN>`. Its auxiliaries are
bound once on entry; body restarts retain their assignments. A bare AGAIN
restarts the nearest surrounding PROG or REPEAT in the current function,
starting at its body without rebinding auxiliaries. A bare RETURN exits that
same nearest frame. The optional activation name and explicit target forms
are outside this slice and remain compile-time errors. A bare AGAIN outside
an eligible frame, or in a called function that has only a caller's frame,
raises an explicit runtime error. The implementation must use iteration
without accumulating Racket stack frames across repetitions, and must unwind
nested scopes on a transfer. Tests belong in `tests/repeat_test.rkt`; finite
reference observations belong under `docs/evidence/M2/repeat-*`.

## M2 issue #28 specification: named activations and explicit targets

The [MDL function chapter](https://mdl-language.readthedocs.io/en/latest/09-functions/)
defines an ACTIVATION as one evaluation of a Function, invalid after that
evaluation ends. The [looping chapter](https://mdl-language.readthedocs.io/en/latest/10-looping/)
binds an optional name to a PROG or REPEAT activation before auxiliary
bindings. `<RETURN value activation>` exits the specified live enclosing
Function, and `<AGAIN activation>` restarts its body without rebinding
auxiliaries. An explicit target may cross a called function's boundary;
bare transfers remain limited to the current function. Transfer unwinds
intervening scopes. The value expression of RETURN is evaluated once before
its target expression, following MDL argument order.

This slice supports named PROG/REPEAT frames and explicit targets to a live
enclosing PROG/REPEAT only. A named frame is an opaque identity-bearing
ACTIVATION value, with PRIMTYPE FRAME. Wrong-type, stale, and non-enclosing
targets raise explicit errors. Function activation formals (`DEFINE` with a
name or `"NAME"`/`"ACT"`), GO, UNWIND, and general FRAME operations remain
unsupported. The pinned Confusion success probes are saved in
`docs/evidence/M2/activation-target-reference.json`: eleven isolated child
processes exited 0. Error probes are separate: wrong-type RETURN crashed
Confusion with signal 11; wrong-type AGAIN and stale targets produced a frame
error. Confusion has no `LEGAL?` binding in this build, so that manual
operation is not added by this slice. Tests belong in
`tests/activation_target_test.rkt` and must cover cross-function transfer,
shadowing, identity, type, and stale-frame rejection.

## M2 function formals specification: OPTIONAL, AUX, TUPLE, and ARGS

Historical `DEFINE` formal lists mark sections with STRINGs: `"OPT"` or
`"OPTIONAL"`, `"ARGS"`, `"TUPLE"`, and `"AUX"` or `"EXTRA"`. An ATOM named
`AUX` is an ordinary required formal; only strings are markers. The section
order is required atoms, then OPTIONAL, then at most one ARGS or TUPLE
binding, then AUX, following the pinned Confusion `mdl_bind_args` state
machine. A two-element `(ATOM expression)` LIST supplies an OPTIONAL or AUX
binding's initial value; it is rejected in the required section. Defaults
evaluate left to right in the partially built function frame, so a later
default sees earlier formals. An unsupplied OPTIONAL without a default and a
bare AUX local remain unassigned, like a PROG auxiliary; reading them errors,
and `SET` assigns them. AUX bindings restore outer locals on return.

`"TUPLE" X` binds the remaining arguments to a value with TYPE `TUPLE` and
PRIMTYPE `TUPLE` — a distinct primitive type, not LIST. `TYPEPRIM TUPLE` is
`TUPLE`, `REST` of a TUPLE keeps TYPE `TUPLE`, two separately made equal
TUPLEs are `=?` but not `==?`, and a TUPLE never `=?`-equals a LIST of the
same content. `"ARGS" X` binds the remaining arguments as a LIST. Extra
arguments without a rest binding raise `TOO-MANY-ARGUMENTS-SUPPLIED`; a
missing required argument raises `TOO-FEW-ARGUMENTS-SUPPLIED`; a repeated
formal raises `BAD-ARGUMENT-LIST`.

Pinned Confusion observations are in `docs/evidence/M2/formals-cases.json`
and `formals-reference.json` (24 successful isolated processes) plus
`formals-error-cases.json` and `formals-error-reference.json` (11 error
observations). Confusion stores the formal list as data and validates it at
call time, killing the process on malformed lists; the Racket compiler
rejects the same shapes at compile time, a documented stricter deviation.
`"NAME"`/`"ACT"`/`"BIND"`/`"CALL"` activation formals and quoted formals
remain unsupported and fail explicitly. Racket tests are in
`tests/formals_test.rkt` plus binder invariants in `mdl/runtime/core.rkt`;
commands, hashes, and limits are in `docs/evidence/M2/FORMALS.md`.

## M2 control slice specification: activation formals, GO, and UNWIND

The [MDL manual, chapter 9](https://mdl-language.readthedocs.io/en/latest/09-functions/)
and the pinned Confusion `mdl_apply_function` bind a function's own
ACTIVATION when `DEFINE` carries an activation name ATOM between the function
name and the formal list (`<DEFINE F SELF (formals) body>`, used 14 times in
the 1977 reconstruction) or a `"NAME"`/`"ACT"` string marker after any formal
section, with nothing permitted after the bound atom. The activation exists
before formal binding, so RETURN during an AUX initializer exits the whole
call. Explicit RETURN to it terminates the call from any depth, unwinding
intervening PROGs; explicit AGAIN re-runs the body without re-binding
formals or AUX locals. Bare RETURN/AGAIN never target function activations
(the reference's LASTPROG lookup only sees PROG/REPEAT frames).

The [manual, chapter 10](https://mdl-language.readthedocs.io/en/latest/10-looping/)
defines `<GO atom>`: top-level ATOMs in a PROG or REPEAT body are labels,
skipped in normal flow, and GO resumes at the expression following the label
in the immediately surrounding PROG or REPEAT of the current function; a
missing label errors. The pinned Confusion has no GO and marks TAG
unimplemented, so GO follows the manual like the ROT precedent, and TAG
values remain unsupported. Bare atom nodes also carry number and `#` reader
tokens in this reader; only non-numeric atom names become labels.

The [manual, chapter 16](https://mdl-language.readthedocs.io/en/latest/16-errors-frames-etc/)
defines `<UNWIND stdexpr errexpr>`: evaluate stdexpr and return its value;
if a nonlocal return crosses below the UNWIND frame, evaluate errexpr in the
UNWIND's environment, ignore its value, and complete the transfer. Normal
completion never runs the cleanup. Pinned Confusion probes are in
`docs/evidence/M2/control-*` (16 successful and 7 error observations).
This slice originally also ran the cleanup on errors and called
Confusion's behaviour a deviation. Issue #139 (ADR-0051) found that the
probe was read at error level 2, where the manual runs no cleanup either.
Raised errors now skip the cleanup; see "M3 UNWIND cleanup only on MDL
transfers" below. Tests are in `tests/control_test.rkt` plus
runtime invariants in `mdl/runtime/core.rkt`; commands, hashes, and
deviations are in `docs/evidence/M2/CONTROL.md`.

## M2 macro slice specification: DEFMAC, FORM, EXPAND, quoted formals

The [MDL manual, chapter 17](https://mdl-language.readthedocs.io/en/latest/17-macro-operations/)
defines `DEFMAC` with `DEFINE` syntax. Its value has TYPE `MACRO` and
PRIMTYPE `LIST`. Calling it first applies its function to the **unevaluated**
call form, then evaluates the expansion at the call site; `EXPAND` performs
only the first step. The manual says expansion occurs in a top-level
environment, but the pinned Confusion probe `macro-sees-caller-local` observes
the caller's local binding. This slice follows that tested reference behavior
and records the manual difference. `FORM` constructs a first-class FORM from
evaluated operands; evaluating a FORM resolves its operator and evaluates its
arguments according to that operator. A quoted formal (`'X`) receives the
raw argument, while an unquoted formal evaluates it once during binding.
`"TUPLE"` collects evaluated remaining arguments and `"ARGS"` retains raw
remaining arguments, matching the pinned `macro-tuple-evaluates` and
`macro-args-stays-raw` probes. An expansion may itself define a function;
`macro-defines-function` confirms the resulting definition is callable.

The pinned success and error observations are in `docs/evidence/M2/macro-*`.
They cover definition return/type, FORM construction, nested expansion,
quoted and ordinary formals in DEFINE/DEFMAC, tuple collection, optional
unassigned reads, and explicit `EXPAND`. Confusion evaluates a non-macro
argument to `EXPAND` and prints a debug message; the manual's one-step
contract is used here, so the Racket runtime returns that FORM unchanged.
`APPLY` of a quoted-formal function remains unsupported and must fail
explicitly. Source loading, declarations, splice/segment semantics, full
environment control, and compilation-time macro expansion remain outside
this slice. Tests are in `tests/macro_test.rkt` and the focused reference
inputs use no random or time-dependent behavior.
The Racket binder validates the full formal list before applying a macro;
Confusion reaches a too-few-arguments error first for the malformed
`('X 3)` list in the saved error probe. This is an error-order deviation.

### Review regressions: interpreted empty auxiliaries and leading activations

The runtime evaluator must accept an empty LIST as the auxiliary list of
`PROG` or `REPEAT`, including their named forms. The MDL manual's looping
forms permit zero auxiliary bindings; the compiled path already accepts the
same source syntax. The historical leading activation ATOM in a `DEFINE` or
`DEFMAC` is separate from the parenthesized formal list. It binds the
function's activation before argument binding and does not end the required
or OPTIONAL formal section. A `"NAME"` or `"ACT"` marker *inside* the
formal list still has to occur after ordinary formals. Duplicate binding
names are errors. These rules apply to directly compiled definitions,
runtime-generated definitions, and macro expansion; regression cases are in
`tests/macro_test.rkt` and pinned local Confusion observations are recorded
in `docs/evidence/M2/macro-review-*`.

## M2 G1 source loading and FLOAD specification

The local `mdl-session-call` API accepts MDL argument objects as call-site
expressions. For an interpreted FUNCTION, ordinary formals evaluate those
objects in the session and quoted formals bind them unchanged; a MACRO expands
and evaluates its result. A compiled procedure still receives already
evaluated values. This API follows the existing interpreted application
behavior and is a local harness interface, not a claim about a historical MDL
host API. Regression cases load both compiled and interpreted definitions and
invoke them through the same session.

The loader's authorized root applies to the file actually opened after
filesystem link resolution. A link target containing a parent component is
resolved component by component, after preceding links, matching filesystem
lookup order. A raw requested path containing `..` remains rejected by local
policy. Regression cases cover an in-root link target of the form
`alias/../child.mud` where `alias` itself is a link.
Consecutive parent components in a link target must each ascend one directory;
the regression `sub/deep/../../child.mud` distinguishes the root child from
`sub/child.mud`.

The [MDL manual, chapter 1](https://mdl-language.readthedocs.io/en/latest/01-basic-introduction/)
and [chapter 11](https://mdl-language.readthedocs.io/en/latest/11-input-output/)
describe `FLOAD` as reading and evaluating a file's MDL expressions. It
does not print each expression value. The pinned Confusion REPL, run locally
with a disposable `/tmp` source file, returned `"DONE"` from a successful
absolute-path `FLOAD`, executed the same file again on a second call, and
preserved an earlier `SETG` when a later form failed. A missing file printed
`Couldn't open file in FLOAD` to stderr; that reference process entered a new
error level, so process exit code 0 was **not** evidence of success. A
non-STRING argument printed `NAME1 arg to OPEN/CHANNEL must be string`.

For the local loader slice, `FLOAD` accepts a STRING path, executes forms in
source order in the active MDL session, and returns the STRING `"DONE"` after
success. Repeated loads execute again. A failed load retains earlier completed
side effects and reports them. The local API rejects failures with structured
diagnostics; it does not emulate Confusion's interactive error level. Paths
are resolved relative to the containing file for nested loads and the
authorized root for entry loads. A Confusion probe with an absolute outer
file and relative inner file failed to find the inner file when the process
working directory differed; source-relative resolution is therefore a
documented deliberate security/usability deviation. All resolved files must
remain under one explicit root; symlink escapes, traversal and cycles fail.
This restricted path policy is a local harness boundary, not a historical MDL
filesystem claim. No network endpoint is provided.

## M2 G2 STRING, PRINTSTRING, and TERPRI specification

The [MDL manual, chapter 7](https://mdl-language.readthedocs.io/en/latest/07-structured-objects/)
defines `STRING` as concatenating evaluated STRING or CHARACTER arguments;
zero arguments yield an empty STRING. This slice supports STRING arguments
only, because CHARACTER values are not implemented. It rejects any other
type explicitly. The unmodified `VFLOAD` definition needs two STRING
arguments: the file name and `" loaded"`.

The [manual, chapter 11](https://mdl-language.readthedocs.io/en/latest/11-input-output/)
states that `PRINTSTRING` outputs the supplied STRING and returns the number
of characters written; `TERPRI` emits a newline and returns empty FALSE.
This slice supports only the default output destination and the full STRING;
explicit CHANNEL and count arguments remain unsupported. Pinned Confusion
returned the original STRING from `<PRINTSTRING "abc">` after outputting
`abc`, contrary to the manual's count. The Racket implementation follows
the manual's return value; this deviation is observable but does not affect
`VFLOAD`, which discards the `PRINTSTRING` result. Pinned Confusion returned
empty FALSE from `<TERPRI>` and emitted a line feed on the local Unix build.
The Racket default output port likewise emits a line feed; MDL's documented
terminal carriage-return/line-feed convention remains unmodeled.

## M0 native Confusion observations (2026-11-17)

The exact inputs and complete stdout/stderr for these observations are in
`docs/evidence/M0/probes/` and `docs/evidence/M0/primitives.json`. Each case ran
in a new pinned Confusion process and exited via `<QUIT>` with code 0 and empty
stderr. They corroborate reference behavior only; no corresponding M1 Racket
semantic implementation has been made.

| Question | Confusion result | M0 runtime status |
|---|---|---|
| `<>` and `#FALSE (1)` | `#FALSE ()` and `#FALSE (1)` | Payload FALSE unsupported |
| `NOT` and `OR` with payload FALSE | `T` and `7` | Bootstrap uses Racket booleans; not equivalent |
| FALSE versus quoted `NIL` | `TYPE` gives `FALSE` versus `ATOM`; identity test gives `#FALSE ()` | Distinction unsupported |
| `REST` view, then `PUT` on its first slot | Original `(1 2 3)` becomes `(1 9 3)` | Shared mutable view unsupported |
| `PUTREST` through a `REST` view | Original becomes `(1 2 8)` | Unsupported |
| Local versus global binding | Global `12`, local `3`, global remains `12` | Bootstrap binding is incomplete |
| `TYPE` of quoted uvector | `UVECTOR` | Type model unsupported |
| `RETURN` from `PROG` | `42`, skipping `99` | Nonlocal control unsupported |

The MDL manual sections on
[atom values](https://mdl-language.readthedocs.io/en/latest/04-values-of-atoms/),
[structured objects](https://mdl-language.readthedocs.io/en/latest/07-structured-objects/),
and [looping](https://mdl-language.readthedocs.io/en/latest/10-looping/)
provide the historical interpretation for future M1 tests. Confusion results
are not by themselves proof of exact original MDL semantics.
## M2 D1 specification: local `#DECL` checking

Chapter 14 of *The MDL Programming Language* defines `#DECL` as a DECL-typed
value whose atom/pattern pairs may occur immediately after the formal or
auxiliary list of `FUNCTION`, `PROG`, or `REPEAT`. `DEFINE` and `DEFMAC` use
the same function body position. `VALUE` denotes the result. Checking is on
initially: bound arguments, initialized locals, each later `SET`, and normal
or explicit results must satisfy the associated pattern. An unassigned
optional or auxiliary slot remains unassigned until set. A failed check must
not change the slot. Checks belong to the owning local frame, including
nested calls and nonlocal returns.

This slice supports type atoms registered in the current MDL type space,
`ANY`, `<OR ...>`, and `<PRIMTYPE type>`. Type matching compares MDL `TYPE`;
primitive matching compares `PRIMTYPE`. The required names include ATOM,
FIX, FLOAT, STRING, FALSE, LIST, VECTOR, UVECTOR, WORD, and registered
`NEWTYPE` names. A `#DECL` payload must have alternating nonempty atom lists
and patterns. A declaration may appear only in the first body position.
Unknown type names, malformed pairs, compound structure/repetition patterns,
quoted-object patterns, aliases, and SPECIAL/UNSPECIAL modifiers fail
explicitly pending separate reference-backed slices. They are never treated
as `ANY`. The reader retains the declaration's line and column; the runtime
uses that position in declaration errors.

`#DECL` also evaluates to a DECL-typed value in any expression position
(`<TYPE #DECL ((X) FIX)>` is `DECL`), and the explicit `<DECL? value
pattern>` predicate checks one value against one pattern with the same
normalization as attached declarations. Pinned Confusion returns `T` on a
match and `#FALSE` carrying the value and pattern otherwise; this
implementation reproduces both. `DECL?` reports malformed or unknown
patterns as explicit errors prefixed `DECL?` rather than as `#FALSE`.

The pinned Confusion build accepts a DECL object and its explicit `DECL?`
predicate checks simple patterns, but it does not enforce attached function
declarations: wrong arguments, `SET`, and results all pass in observed probes.
Its `mdl_decl.cpp` labels checking work in progress, and the only call to
`mdl_check_decl` is its explicit `DECL?` operation. We follow the manual's
enforcement semantics and record this as a reference deviation rather than
copying the reference's missing checks. Reference success, errors, and
source hashes belong in `docs/evidence/M2/DECLARATIONS.md`.

The original `MSETG` first tests `GASSIGNED?`, then `SETG`s and `MANIFEST`s
an atom on the first assignment. The manual says `GASSIGNED?` is true only
when a global value is assigned. `MANIFEST` marks global slots as constants
and returns `T`; with declaration checking enabled, a later `SETG` may change
an assigned manifest value only to an identical (`==?`) value or when
`.REDEFINE` is true. This slice needs first-assignment success and preserves
the manifest restriction. Confusion's pinned source accepts `FLOAD
"81prim.mud"` and the first `<MSETG M2-TEMP 3>` returns `T`, leaving the
global at `3`. A second equivalent call returns `T`; conflicting reassignment
enters its explicit `ERROR MSETG ... ALREADY-GASSIGNED` branch. Confusion
does not have active local declaration checking, so its wrong-FOO error comes
from `GASSIGNED?`, while the Racket implementation rejects at the declaration
binding boundary.

## M2 D2 specification: SEGMENT (`!` splice) evaluation

Chapter 7 of *The MDL Programming Language* defines SEGMENT objects, read
with `!`: `!.ATOM` denotes a segment of `<LVAL ATOM>`, `!,ATOM` of
`<GVAL ATOM>`, and `!<FORM...>` (the trailing `!` optional immediately
before the closing `>`, read as the `!>` digraph) of the FORM's value.
Evaluating a structure — LIST, VECTOR, UVECTOR, or a FORM's argument list —
inserts the *elements* of each segment's value at its position, evaluating
every element in strict left-to-right order. A segment's value must be a
structured object: LIST, FALSE, FORM, and TUPLE payloads contribute their
elements, VECTOR and UVECTOR payloads their element sequence, and STRING
payloads its characters as CHARACTER values. A segment evaluating to a
non-structured value, or standing alone outside a structure evaluation, is
the reference's `ILLEGAL-SEGMENT` error; spliced values are never
re-evaluated. A UVECTOR construction enforces uniform element types
(`TYPES-DIFFER-IN-UNIFORM-VECTOR`).

A LIST-valued segment in the **final** position of a LIST construction
shares the payload's tail cells instead of copying them, so mutation
(`PUT`) through either name is visible in both; non-final segments, and
all VECTOR/UVECTOR constructions, copy. FALSE and TUPLE payloads and
NEWTYPE-wrapped (typed) structured values splice their elements like the
reference's structure walker. Segments in quoted structures stay
unevaluated SEGMENT data that prints back in its original notation, and a
plain element whose value happens to be a SEGMENT object is stored as a
value, not re-spliced. MACRO call arguments are never segment-expanded:
a segment in a macro call binds as the SEGMENT object, exactly like the
pinned reference's raw-argument MACRO branch. `![`/`!]` remain UVECTOR
delimiters, not segment notation. The pinned interpreter's own
`#UVECTOR [...]` input crashes it; that syntax stays an explicit
unsupported construct here. Two reader consequences of the `!>` close
match the reference: a trailing `!>` inside an ordinary (non-segment)
form such as `<FOO A!>` is now a reader error, and a quoted UVECTOR
containing a segment placeholder (`'![1 !.X]`) evaluates to a
uniformity-unchecked data object whose `PUT` raises a type error even at
non-segment slots — the reference instead rejects such reads outright
(`TYPES-DIFFER-IN-UNIFORM-VECTOR`), which is acceptable only because no
historical source constructs one.

Recorded deviations from the pinned reference (evidence in
`docs/evidence/M2/SEGMENTS.md`): the reference's interpreted FUNCTION
application does **not** splice segments in call arguments (its argument
binder consumes raw items), while its SUBR path does. This implementation
follows the manual's general rule — segments splice into FORM argument
assembly — in both the compiled and interpreted paths, per the repository's
compiled/interpreted agreement requirement, and records the reference's
interpreted path as the deviation. Second, interpreted call assembly
evaluates segment payloads eagerly, before bind-time evaluation of plain
formals, where the compiled path interleaves; this is observable only when
a segment payload and a later plain argument of the same interpreted call
both have side effects. No reference observation pins that case, and no
historical source exercises it; it stays a recorded divergence pending a
source-backed need.

## M2 D3 specification: structured declaration patterns

Chapter 14's `<struc elts>` construction extends the M2 D1 pattern
language: a pattern `<LIST elts...>`, `<VECTOR elts...>`,
`<UVECTOR elts...>`, or `<TUPLE elts...>` matches a value whose MDL TYPE
is that structure type (a STRING is LIST-primtype but is **not** matched
by `<LIST ...>`), whose leading elements satisfy the declared element
patterns positionally, and whose remaining elements all satisfy the
trailing `[REST pat ... pat]` repetition — zero or more, last position
only, one repetition only. Multi-pattern `[REST p1 p2]` sequences repeat
cyclically over the remaining elements (recorded reference case
`rest-multi-pattern`); an empty repetition bracket, a misplaced
repetition, `[OPT ...]`, and NTH `[fix pat ...]` repetitions are explicit
normalization errors in this slice. Element patterns nest, including the
existing `<OR ...>` (the last failing alternative is the reported leaf
pattern, mirroring the reference's returned FALSE).

`DECL?` gains the reference's payload distinction: an overall TYPE
mismatch — and likewise a failing `<PRIMTYPE ...>` check, which the
reference returns as its plain FALSE — yields bare `#FALSE ()`, while a
structured element mismatch returns `#FALSE (element pattern)` carrying
the offending element and the simple type-atom leaf; simple-pattern
failures keep the D1 `#FALSE (value pattern)` payload. Attached
declarations and `DECL?` share one matcher, so they agree by
construction.

Traversal is bounded and in place: one nesting-budget unit per
structured pattern level and per `<OR ...>` alternative
(`decl-match-max-depth` 200), with an explicit error naming the limit.
The required prefix of a LIST-primtype value is walked cell by cell
(arrays are read by indexed reference), so nothing is duplicated or
mutated — and a prefix-only pattern matches the prefix of a cyclic LIST
like the reference's incremental walk. Only the `[REST ...]` tail
materializes through the cycle-checked conversion, whose explicit
cyclic error is a recorded safety deviation: the reference's REST loop
would not terminate on a cyclic value at all.

Recorded deviations from the pinned reference (evidence in
`docs/evidence/M2/DECLARATION-PATTERNS.md`): the empty `<LIST>` pattern is
rejected here because the manual's BNF requires at least one element
pattern, while Confusion accepts it and matches any value of the TYPE;
`DECL?` keeps a strict two-operand arity where Confusion silently
ignores surplus operands spliced into its call; structured pattern heads
initially supported only LIST/VECTOR/UVECTOR/TUPLE, later extended in
issue #76 to `<<PRIMTYPE ...> ...>` for original NEWTYPE declarations.
Confusion accepts any NEWTYPE with a structured PRIMTYPE but rejects the
explicit PRIMTYPE-headed DECL? composition in the pinned probe; this
extension follows the manual. Confusion's broken `ANY`/`STRUCTURED` compound names
are not reproduced; `ANY` as a simple pattern keeps its manual semantics
from D1.

## M2 D4 specification: the interpreter-supplied MUDDLE global

The historical interpreter bound its version number as a startup global.
The pinned reference binds `MUDDLE` to the FIX `101` (issue #51 evidence
`muddle-reference.json`, interpreter SHA
`a29c756df5c973e462a6ad2b318e28ec265934e89e72d825bc7672387317e629`), and
every fresh shared-session loader session seeds it identically, interned
in that session's atom space. With that value the `77defs.mud:1` guard
`<L? ,MUDDLE 100>` is FALSE and its `<AND ...>` short-circuits without
evaluating `USE` — which is unbound in the reference and stays an
explicit error here. Changing the value requires new reference evidence,
not a source edit; the reference's own environment is the reproducible
baseline for the original 1977 version number.

## M2 D5 specification: atom-property PUT/GET associations

MDL association storage pairs an arbitrary *item* with an arbitrary
*indicator* and a value, matched by `==?` identity — never structural
`=?`. The runtime dispatch mirrors the pinned reference (evidence:
[`evidence/M2/ATOM-PROPS.md`](evidence/M2/ATOM-PROPS.md), 18 success and 6
deliberate-error Confusion observations):

- `PUT` — structured item (LIST/VECTOR/UVECTOR/STRING via primtype) with a
  FIX indicator keeps the existing index-based element store (with the
  reference's `PUT index too large` and CHARACTER-type stderr diagnostics);
  every other indicator on a structured item, and every indicator on a
  non-structured item (including FIX indicators on non-structured items,
  e.g. `<PUT 5 DECL 'FIX>`), is an association. A two-argument
  `<PUT item indicator>` removes the association and echoes the item;
  one-argument PUT raises TOO-FEW-ARGUMENTS-SUPPLIED. Property PUT returns
  the item.
- `GET` — structured item with a FIX indicator returns the element
  (three-argument GET on a structure is the reference's error `No EXP
  allowed for GET on structure`); an association selector returns the
  stored value, the evaluated optional exp on a miss, or `#FALSE ()`.
  Retrieval preserves the stored object's exact identity (a quoted FORM
  comes back as the same FORM, `<OR ATOM FALSE NOFFSET>`).
  A structured item without an indicator selects its first element, as
  pinned Confusion does. Indexed STRING retrieval returns a CHARACTER
  (`TYPE` CHARACTER, `PRIMTYPE` WORD); a mutable STRING accepts that
  CHARACTER through indexed PUT. Immutable host string literals remain an
  explicit mutation limit.
  Final-head review probes show that a STRING element retrieved by GET and
  the same element produced by STRING SEGMENT expansion are `==?` in pinned
  Confusion; indexed PUT accepts either. Both paths must use one CHARACTER
  value representation, with WORD primtype and code-point identity. The
  cases and red-to-green test are in `evidence/M2/character-review-*` and
  `tests/atom_props_test.rkt`.
- Associations live in a session-owned list searched with `mdl-identical?`
  for **both** item and indicator. A weak `eq?` table was rejected after
  reference-backed regressions showed misses for separately constructed
  equal WORD values and VECTOR/UVECTOR REST views of the same storage.
  Entries hold strong references to item, indicator, and value until
  removed or the session ends. This differs from the manual's association
  garbage collection when keys become unreachable; key lifetime remains
  unsupported until a weak store with MDL `==?` equivalence is proven.
- `DECL?` consults an atom's `DECL` association when the atom names a type
  (the `77defs.mud:5` `<PUT RAPPLIC DECL ...>` NEWTYPE-annotation
  mechanism): the stored pattern is normalized by the existing D1/D3
  matcher, a matching leaf carries the resolved pattern's leaf in the
  `#FALSE` payload (reference: `#FALSE (3 NOFFSET)`), and recursion
  through association-derived declarations is cycle-bounded. `SETG` does
  NOT enforce an atom's DECL association; the property only feeds `DECL?`.
  PUTting a property never assigns the atom as a global and never changes
  its TYPE or PRIMTYPE.
  Registered TYPE atoms retain their intrinsic meaning even if they carry
  a `DECL` association. Unregistered alias atoms follow successive `DECL`
  associations until a pattern is reached; cycles raise a bounded explicit
  error (pinned Confusion loops on an A-to-B-to-A cycle in a timed probe).
  The same normalization applies to attached `#DECL` patterns.
  Two-argument PUT on a structured item with a FIX indicator is a
  TOO-FEW-ARGUMENTS-SUPPLIED error, not association removal.
- `GETPROP`/`PUTPROP` and the chapter 13.4 examination machinery
  (`ASSOCIATIONS`, `NEXT`, `ITEM`, `INDICATOR`, `AVALUE`, `#ASOC`
  printing) remain explicit unimplemented failures — the pinned load set
  never uses them.

Final-head review of issue #53 (issue #67) adds a FIX-indicator dispatch
case: a native SUBR is an unstructured MDL item even though the Racket
runtime represents it as a host procedure. Pinned Confusion accepts
`<PUT ,+ 7 9> <GET ,+ 7>` and returns `9`; a two-argument PUT removes
that association and GET returns `#FALSE ()`. A FIX selector on this
unstructured item must reach association storage without querying an
unsupported host procedure's MDL primtype. Indexed FIX selectors on
LIST/VECTOR/UVECTOR/STRING retain element dispatch. Tests must fail on
the current D5 head and pass after the narrow dispatch correction.

Deviations from the manual are adjudicated in
[`evidence/M2/ATOM-PROPS.md`](evidence/M2/ATOM-PROPS.md): the reference's
augmented `#FALSE (leaf)` DECL? miss is followed over the manual's plain
`#FALSE ()` (it carries useful diagnostic information and the pinned
source flags it as deliberate); the two-argument PUT removal echoes the
item as the reference does (the manual's "returns the previous value"
wording was checked — the reference returns the item; we follow the
reference); and GET's exp is honored only on the association branch.

## M2 G3 corrective slice: structural `N=?` (issue #57)

The [MDL manual chapter 8](https://mdl-language.readthedocs.io/en/latest/08-truth/)
defines `N=?` as the Boolean complement of structural `=?` (not the
identity complement `N==?`). On finite values it returns MDL `T` when
the two arguments differ structurally and `#FALSE ()` when equal. The
reference rejects fewer than two arguments with
`TOO-FEW-ARGUMENTS-SUPPLIED` and more than two with
`TOO-MANY-ARGUMENTS-SUPPLIED`.

The original `81prim.mud` MSETG guard calls `<N=? .BAR ,.FOO>` on a
reassignment. Pinned Confusion returns `T` from MSETG on an equal repeat,
and raises the source's ALREADY-GASSIGNED error on a conflicting repeat.
Racket must use its existing `mdl-equal?` relation and MDL truth values;
the first G3 integration probe failed before implementation because `N=?`
was unassigned. The focused tests must cover scalar, atom, separately
allocated equal/unequal LIST and STRING, and typed values, plus these two
original-source MSETG paths and arity errors.

Two bounded cyclic Confusion `N=?` probes (self and distinct equal-content
LIST cycles) timed out after three seconds. The existing Racket `=?`
boundary already returns T for a cycle compared with itself and raises an
explicit unsupported-cyclic-equality error for two distinct equal cycles.
`N=?` follows the documented complement of that bounded relation: FALSE
for self and the same explicit error for unsupported distinct equal cycles.
This differs from the tested pinned Confusion timeout but prevents a hang;
it is not evidence of general cyclic parity. Reference inputs, outputs,
source hashes, and commands are in `evidence/M2/NEQ.md`.

## M2 G3 corrective reader slice: computed global `,.FOO` (issue #58)

The [MDL manual chapter 4](https://mdl-language.readthedocs.io/en/latest/04-values-of-atoms/)
says comma abbreviates GVAL of the following expression, and explicitly
shows `,.FOO` reading the GVAL of the ATOM held in FOO's local value.
Pinned Confusion confirms this: after `<SETG G3-FOO 3>` and
`<SET FOO 'G3-FOO>`, `,.FOO` returns 3 and `<+ 1 ,.FOO>` returns 4.
The exact original `81prim.mud` MSETG uses `,.FOO` in its N=? guard and
ALREADY-GASSIGNED error path. With N=? available, the current reader's
literal-name parse of `.FOO` causes a false unassigned-global error.

Parse immediate comma-period as a `global` node containing a `local` node;
the existing compiler/runtime paths then evaluate local FOO to an ATOM
and retrieve that ATOM's global value. Preserve plain `,FOO` and computed
`,<FORM>` behavior. Unknown/unassigned names continue to raise explicit
errors. Tests must cover reader AST shape, compiled expression behavior,
and the source-defined MSETG equal-repeat path. Its conflicting-repeat
path reaches a separate unsupported `ERROR` primitive (issue #60); it is
not part of this reader slice. Reference inputs
and outputs are in `evidence/M2/computed-global-*` and the G3 reference
files; final validation belongs in `evidence/M2/COMPUTED-GLOBAL.md`.

## M2 G3 corrective primitive: `ERROR` (issue #60)

The [MDL manual chapter 1](https://mdl-language.readthedocs.io/en/latest/01-basic-introduction/)
describes an error as interrupting evaluation and entering an error state;
chapter 21 describes interrupt handlers and `ERRET` recovery. The pinned
Confusion probe accepts zero or more evaluated arguments to `ERROR`, prints
each one in order, and enters `LISTENING-AT-LEVEL 2`. The exact original
MSETG conflict in `81prim.mud` prints `MSETG`, the target atom,
`ALREADY-GASSIGNED`, and the old value `3`. See `evidence/M2/error-*`.

This initial slice must evaluate arguments in order and raise a host
exception carrying those values in readable form, so the source-defined
error is observable and cannot silently return. A zero-argument call
must also fail. Racket does not yet reproduce MDL's resumable error
level, interrupt handlers, or `ERRET`; those are explicit deviations.
Tests must first fail for unassigned `ERROR`, then pass for zero and
multiple arguments, evaluation side effects, and the exact source-defined
MSETG conflicting-repeat path. No error branch may be converted into a
FALSE or ignored form.

## M2 G3 corrective primitive: `MEMQ` (issue #63)

The [MDL manual chapter 8](https://mdl-language.readthedocs.io/en/latest/08-truth/)
defines `MEMQ` as `MEMBER` using `==?` identity. It returns the `REST`
view beginning at the first identical element, or `#FALSE ()` on a miss.
Pinned Confusion confirms LIST hit `(B C)`, miss `#FALSE ()`, structurally
equal but distinct LIST miss, mutable LIST tail aliasing, VECTOR `[2 3]`,
UVECTOR `![2 3!]`, and original `PSETG` returning `3` with `PURE-LIST`
`(G3-P)`. Reference data: `evidence/M2/memq-*`.

For this corrective slice, scan LIST/VECTOR/UVECTOR left-to-right using
`mdl-identical?`; return `mdl-rest` at the matching zero-based offset to
preserve aliasing and primitive structure kind. Reject non-structured
second arguments explicitly. The one-argument reference crashes with
signal 11, so the Racket runtime must raise a deliberate arity error
rather than reproducing that crash. A three-argument call reports too many
arguments in Confusion. STRING/other structured MEMQ requires a separate
reference-backed representation decision if reached; never return a false
miss merely because that representation is unsupported. Tests must cover
the first match, miss, identity versus structural equality, aliasing,
sequence kinds, arity/type boundaries, and exact-source PSETG.
The implemented slice passes these tests and the exact-source PSETG
first/repeat paths. At M2, `MEMQ` on STRING raised an explicit unsupported
error; see `evidence/M2/MEMQ.md` (2026-11-23: implemented on the M3 branch
stack, see "M3 startup: UNPARSE, MEMQ on STRING and SUBSTRUC"). G3 now fails at original FLAGWORD's
unassigned `MAPF`, rather than at PSETG.
## M2 MAPF, FUNCTION literals, and map control (issue #65)

The [MDL manual, chapter 10.2–10.3](https://mdl-language.readthedocs.io/en/latest/10-looping/)
defines `<MAPF finalf loopf s1 ... sN>` as a simultaneous left-to-right
walk over structured arguments, ending when the first input is exhausted.
Each step applies the already evaluated `loopf` to the current first
elements. A true applicable `finalf` receives the recorded results as
already evaluated arguments; a FALSE `finalf` discards them and returns
the last loop value, or `#FALSE ()` if the loop never ran. With no input
structures, the loop continues until explicit map control exits it.

The pinned Confusion results in `evidence/M2/mapf-reference.json` confirm
LIST, VECTOR, UVECTOR, differing lengths, empty inputs, scalar and
structured final values, interpreted FUNCTION literals and values,
outer local access, nested MAPF, indexed applicable `1`, and preservation
of LIST/VECTOR elements passed to interpreted loop functions. A FUNCTION
literal has formal bindings, optional AUX/defaults and a body; its #DECL
is checked at the same boundaries as an interpreted DEFINE. MAPF must
invoke an already evaluated applicable with already evaluated elements;
evaluating those elements again changes structure contents and is wrong.

`MAPRET` ends the current loop-function invocation and adds zero or more
arguments to the final argument stream. `MAPSTOP` does the same and then
invokes `finalf` immediately. `MAPLEAVE` exits the MAPF directly, discards
the collected values, and returns its argument (or T if omitted). The
reference shows nested map control targets the current map; outside a
live map these operations error (`evidence/M2/mapf-error-reference.json`).
The runtime must discard map control state on ordinary and abnormal exits.
The additional bounded control corpus (`evidence/M2/mapf-control-reference.json`)
shows a pinned Confusion quirk: with FALSE `finalf`, a MAPRET or MAPSTOP
transfer returns the current first input element, even if control supplied
another value. The runtime follows that observed behavior. It also confirms
left-to-right steps, interpreted final functions, declaration checking,
MAPLEAVE default T, and UNWIND cleanup on nonlocal exit. A FUNCTION value
used after its defining PROG has returned does not capture the expired
local binding in Confusion (`mapf-function-context-reference.json`), so
the Racket runtime does not claim implicit lexical closure capture.

The original `81prim.mud` `FLAGWORD` initializes `TOT=1`, `CNT=1`, then
uses `MAPF <>` over tuple `FS` with an inline FUNCTION. On an ATOM it may
call the original MSETG, doubles TOT, increments CNT, and checks for
overflow. The function result is discarded by FALSE finalf. The return
is CNT: no arguments give 1, one FALSE or ATOM gives 2, and FALSE plus
ATOM gives 3 in the recorded native cases. No source substitution is used.

### G3 follow-on: TYPE?

The original FLAGWORD inline FUNCTION calls `<TYPE? .F ATOM>`. The MDL
Primer section 7.3 describes the predicate as returning the object's TYPE
on a candidate hit and FALSE otherwise. Pinned Confusion evidence in
`evidence/M2/typeq-reference.json` confirms ATOM/FIX/FALSE and user-defined
TYPE hits, misses, a late candidate hit, and a no-candidate miss. It also
returns FALSE for numeric or unregistered candidate values; the only
observed deliberate error is a missing value argument
(`evidence/M2/typeq-error-reference.json`). Implement this as evaluated
argument comparison with the actual TYPE atom, without coercing candidate
values or treating a non-hit as an exception.

### G3 follow-on: startup OBLIST associations

After TYPE?, original FLAGWORD calls `<LOOKUP "GROUP-GLUE" <GET INITIAL OBLIST>>`.
Pinned Confusion initializes the reciprocal `OBLIST` associations for
INITIAL/ROOT and their OBLIST values before source execution
(`macros.cpp`, `mdl_interp_init`; observed in
`evidence/M2/get-initial-oblist-reference.json`). Thus GET on INITIAL
with indicator OBLIST yields the initial OBLIST, and GROUP-GLUE lookup
there returns FALSE. An ordinary ATOM has no such association. Seed these
specific associations in each fresh Racket session's atom space so the
original source can observe the same startup state; leave general GET
dispatch and user associations intact.

## M2 indirect APPLY and computed FORM heads (issue #69)

The [MDL manual section 9.10](https://mdl-language.readthedocs.io/en/latest/09-functions/)
defines `<APPLY object arg-1 ...>` as evaluating the applicable object
and every argument, then applying it. It rejects FSUBR/MACRO and
FUNCTION formals that require raw arguments, notably quoted formals and
`"ARGS"`/`"CALL"`. A computed FORM head evaluates to an applicable
object before argument dispatch; unlike APPLY, it may invoke an
interpreted FUNCTION with quoted formals because the original raw
argument forms remain available. The operator and each evaluated
argument are visited left to right exactly once.

Pinned Confusion `evidence/M2/indirect-apply-reference.json` records
native SUBR, interpreted FUNCTION, MAPF and numeric indexed applicable
calls; a structured LIST argument remains a value rather than being
re-evaluated. A FIX head with one argument reads that index; with two
arguments it writes the indexed element and returns the structure.
The computed-head cases include local/global FUNCTION values, quoted
formals, and a RETURN to an outer activation. The separate
`indirect-apply-error-reference.json` records missing APPLY target,
non-applicable target, quoted/ARGS/MACRO restrictions, and FIX excess
arity as deliberate failures. Unknown applicable kinds must continue
to fail explicitly.

The implemented dispatcher shares evaluated-value application between
MAPF, APPLY, computed FORM heads and the host `mdl-apply` API. A compiled
DEFINE keeps its formal-kind metadata so APPLY also rejects its ARGS
formal; TUPLE remains allowed. The shared-session call API now passes
already evaluated values to interpreted FUNCTIONs without rebuilding
structured contents. A FIX head with two arguments invokes indexed PUT
on a structured target directly; it cannot fall through to a PUT
association on a non-structured item. Red-to-green observations and
remaining limits are in `evidence/M2/INDIRECT-APPLY.md`.

## M3 EMPTY? predicate (issue #75; specification before implementation)

The [MDL manual predefined SUBR entry](https://mdl-language.readthedocs.io/en/latest/appendix-2-predefined-subroutines/)
declares `EMPTY? (OBJECT)` with a STRUCTURED argument and a result of
`T` or empty FALSE. It is true exactly when the structure has zero
elements. The exact original `81prim.mud` SHA256
`8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`
defines NEWSTRUC at line 35. Its line-43 `<EMPTY? .ELEM>` checks the
remaining ARGS LIST while `77defs.mud` expression 15 constructs ROOM.

The pinned Confusion clean corpus in
`evidence/M3/emptyq-reference.json` has 16/16 exit-0 cases. Empty
LIST, VECTOR, UVECTOR, STRING, FALSE, REST-end LIST, TUPLE and a typed
LIST return `T`; their nonempty counterparts return `#FALSE ()`.
The circular LIST case returns FALSE promptly; EMPTY? must inspect only
whether a first cell exists, without traversing the whole LIST.
The original source-defined NEWSTRUC succeeds on a controlled VECTOR
definition after FLOAD of the unchanged 81prim file. Deliberate invalid
cases are separate in `emptyq-error-reference.json`: no argument writes
`Not enough arguments to EMPTY?` to stderr; two arguments write
`Too many args to EMPTY?`; ATOM, FIX and WORD enter an error level with
`FIRST-ARG-WRONG_TYPE` and a structured-argument diagnostic. Those
error-level captures have `ok=false` by design, even when the native
process exits 0 after `<QUIT>`.

Implementation tests must cover each supported structured representation,
including typed wrappers and TUPLE, and require explicit errors for wrong
arity or unstructured values. Return the session's canonical `T` atom or
an empty MDL FALSE; do not coerce host truth values. The unchanged full
loader must advance beyond 24 completed forms with zero skipped forms.
This predicate alone does not imply NEWSTRUC, world, or game parity.

## M3 LENGTH? bounded structured length (issue #75 follow-on)

The [MDL manual predefined SUBR entry](https://mdl-language.readthedocs.io/en/latest/appendix-2-predefined-subroutines/)
declares `LENGTH? (OBJECT MAX)` with STRUCTURED and FIX arguments. It
returns the actual length as FIX when that length is at most MAX, and
empty FALSE otherwise. Unlike a full LENGTH traversal, it must stop
after finding more than MAX elements; the manual explicitly discusses
using it on circular LISTs. Original NEWSTRUC in pinned `81prim.mud`
calls `<LENGTH? .ELEM 1>` after the EMPTY? check to reject a one-slot
remainder. The first post-EMPTY? loader run reaches this unassigned
operator in `77defs.mud` expression 15, still after 24 completed forms.

The 16 clean pinned Confusion cases in
`evidence/M3/lengthq-reference.json` cover LIST, VECTOR, UVECTOR,
STRING, FALSE, TUPLE, typed LIST, REST view, and a circular LIST. A
length of two with MAX 1 returns `#FALSE ()`; with MAX 2 or 3 it
returns FIX `2`. A circular LIST with MAX 3 returns empty FALSE in a
bounded process. The five separate deliberate-error cases in
`lengthq-error-reference.json` record missing/extra argument messages,
the structured first-argument requirement, and FIX second-argument
requirement. Native stderr carries those diagnostics while its process
may still exit 0 after `<QUIT>`; the probe marks them `ok=false`.

**Observed reference/manual edge:** Confusion returns FIX `0` for an
empty LIST with negative MAX, although the manual's mathematical
less-than-or-equal rule would imply FALSE. It returns FALSE for a
nonempty LIST with negative MAX. This runtime follows that pinned
observable behavior for the reconstructed target and records the
deviation; NEWSTRUC passes positive MAX 1. Implement a bounded walk
over LIST-like values, checking for emptiness before the bound, so
cyclic lists terminate and the empty/negative case matches the reference.
Do not call the general `LENGTH` path on an unbounded cyclic LIST.

## M3 ASSIGNED? local binding predicate (issue #75 follow-on)

The [MDL manual's function chapter](https://mdl-language.readthedocs.io/en/latest/09-functions/)
and predefined SUBR entry specify `ASSIGNED? (ATOM "OPTIONAL" ENV)`.
Without an ENV, it tests whether the ATOM has an assigned local binding
in the current environment, returning `T` or empty FALSE. A global-only
binding does not count. A nearer unassigned local shadows an assigned
outer local. The original `NEWSTRUC` in SHA-verified `81prim.mud` uses
`<ASSIGNED? RR>` for its initially unassigned AUX local. The first
loader run after EMPTY? and LENGTH? reaches this expression.

The nine clean pinned Confusion cases in
`evidence/M3/assignedq-reference.json` establish unbound, top-level SET,
global-only SETG, PROG local assignment and shadowing, and function AUX
behavior. Four separate deliberate-error cases in
`assignedq-error-reference.json` show the missing-argument error and
that the first argument must be ATOM; a supplied second FIX is rejected
because the optional argument must be a frame. These native error-level
captures are marked `ok=false` even where the process exits zero after
QUIT. The initial implementation supports the one-argument form used by
original source; a supplied ENV fails explicitly until frame semantics
are separately specified and tested. Tests must assert the local/global
distinction, unassigned shadow, wrong type, and arity before runtime code.

## M3 ROOT startup OBLIST (issue #75 NEWSTRUC dependency)

The manual's OBLIST chapter describes ROOT as the system's root OBLIST.
The original `NEWSTRUC` calls `<LOOKUP "COMPILE" <ROOT>>` to select a
compiled or interpreted type definition. On a clean pinned Confusion
session, the five cases in `evidence/M3/root-reference.json` establish
that zero-argument ROOT has type OBLIST, is identical to both
`<MOBLIST 'ROOT>` and `<GET ROOT OBLIST>`, contains the ROOT atom, and
does not contain COMPILE. The deliberate extra-argument case in
`root-error-reference.json` writes `Too many arguments to ROOT`.
Implementation returns the existing session root OBLIST and rejects any
argument. It must preserve identity, not construct another OBLIST.

## M3 three-argument NEWTYPE declaration (issue #76; specification before implementation)

The [MDL manual, §14.6](https://mdl-language.readthedocs.io/en/latest/14-data-type-declarations/)
says the optional third argument is a quoted declaration Pattern. It is
stored as the type atom's `DECL` association and checked on every
`CHTYPE` into that type, including a cast into the value's current type.
Calling `NEWTYPE` again for the same type and primitive type may replace
the Pattern. The original `77defs.mud` expression 17, line 66, uses
`<NEWTYPE EXIT VECTOR '<<PRIMTYPE VECTOR> [REST ATOM <OR ROOM CEXIT NEXIT>]>>`.
The pattern's referenced types are defined later, so storage precedes
full validation; check its shape on NEWTYPE and resolve names when a
value is cast. A `<<PRIMTYPE VECTOR> ...>` structure head matches a
value by primitive type while its element patterns use the existing
declaration matcher. A bad pattern must fail explicitly.

**Pinned Confusion/manual deviation:** the seven clean cases in
`evidence/M3/newtype-decl-reference.json` show Confusion accepts the
third argument and same-primitive redefinition, but `<GET M3N DECL>`
still returns empty FALSE and a cast violating a FIX-only pattern
succeeds. The pinned `confusion_patched/macros.cpp` function
`mdl_builtin_eval_newtype` reads `desc` but calls `mdl_internal_newtype`
with only name and primitive type. Six deliberate-error cases in
`newtype-decl-error-reference.json` establish missing/extra arguments,
unknown primitive, incompatible redefinition, and non-atom type-name
errors. This Racket slice preserves the manual's declaration association
and enforces it; it therefore intentionally differs from this incomplete
Confusion implementation. Do not silently discard the third argument
to match that reference defect. Tests must cover storage, valid and
invalid casts, same-type recheck, redefinition, malformed patterns,
wrong arity and primitive type, and the unchanged original-source load.

## M3 GDECL global value declarations (issue #78; specification before implementation)

The [MDL manual §14.5.1](https://mdl-language.readthedocs.io/en/latest/14-data-type-declarations/)
defines `GDECL` as an FSUBR with alternating nonempty ATOM lists and
declaration Patterns. It installs Patterns on global value slots; a
later `SETG` must satisfy the Pattern when declaration checking is on.
Declaring an unassigned name creates its global slot without assigning a
value. A wrong current value must be rejected before installation, and
a failed later `SETG` must preserve the previous value. `GDECL` consumes
source forms as data: it must not evaluate the ATOM list or Pattern. The
first unchanged source call is `77defs.mud` expression 27, line 139,
for `ORPHANS` with a five-element VECTOR Pattern. A later original
GDECL declares three score globals as FIX. This initial slice supports
the existing declaration matcher (simple type, OR, PRIMTYPE,
LIST/VECTOR/UVECTOR/TUPLE with required and REST patterns); unsupported
pattern shapes fail explicitly. `GET-DECL`/`PUT-DECL`, dynamic
declaration-check switching, and global locatives are separate work.

**Pinned Confusion/manual deviation:** the ten clean local cases in
`evidence/M3/gdecl-reference.json` show pinned Confusion's GDECL always
returns `T`, including empty or malformed inputs and a later SETG
violating a FIX declaration. Its implementation in
`confusion_patched/macros.cpp` explicitly marks GDECL unimplemented and
returns `T` without inspecting the unevaluated form. The Racket runtime
implements the manual operation rather than making a silent no-op. Tests
must cover strict input shape, slot creation versus assignment,
multiple names and patterns, existing value validation, SETG
enforcement, and source-loader advance with zero skipped forms.

## M3 eager AND? (issue #80; specification before implementation)

The [MDL manual §8.2.3](https://mdl-language.readthedocs.io/en/latest/08-truth/)
defines `AND?` as the SUBR counterpart of short-circuit FSUBR `AND`:
every argument is evaluated, left to right, before truth is tested.
With no arguments it returns the session's `T` atom. Otherwise it
returns the first FALSE argument, preserving its payload and identity,
or the final argument if all are true; FIX zero is true. The unchanged
`77defs.mud` expression 28, line 146, wraps five `<MSETG ...>` calls
in AND? so every global assignment must occur, even if an earlier
argument is FALSE. A later error must still propagate after an earlier
FALSE because argument evaluation is eager.

Seven clean pinned Confusion cases in `evidence/M3/andq-reference.json`
cover zero arguments, last-value return, zero truth, first-FALSE
payload, eager SET side effects, and original MSETG definitions loaded
from the unchanged `81prim.mud`. The separate deliberate-error capture
in `andq-error-reference.json` shows `<AND? <> <ERROR ANDQ-LATE>>`
enters the native error level; the probe marks that case `ok=false` by
design. The existing runtime dispatcher evaluates all arguments before
calling a SUBR. `AND?` must use that path, not compile as short-circuit
`AND`. Tests must pin both side effects and returned MDL values before
the runtime addition, then rerun the unchanged loader.

## M3 quoted OPTIONAL defaults (issue #82; specification before implementation)

The [MDL manual §9.9](https://mdl-language.readthedocs.io/en/latest/09-functions/)
permits a two-element OPTIONAL formal whose first element is a quoted
ATOM, for example `('X 'A)`. If a call supplies that argument, `X`
receives the raw, unevaluated call form and its default is not evaluated.
If omitted, the default expression is evaluated once in the new function
frame, after earlier formals have been bound, and the resulting value
is bound to `X`. A default can therefore read an earlier local or perform
a side effect. The quoted form is legal only in OPTIONAL, while an
unquoted two-element form remains legal in OPTIONAL and AUX. Malformed
quoted names, duplicate names, and incorrect sections remain errors.

The unchanged `77defs.mud` expression 61, line 338, defines `TAKE-OBJECT`
with `('WINNER ',WINNER)` and is the first source barrier. The pinned
Confusion reference confirms six focused cases: omitted atom default,
raw explicit FORM without invoking `ERROR`, default side effect, skipped
default on explicit argument, default reading an earlier local, and the
original `',WINNER` shape returning a FORM. Save those inputs and outputs
under `evidence/M3/`, add failing focused tests before implementation,
then verify exact-source loader progress with zero skipped forms. This
slice does not change quoted required formals or ordinary OPTIONAL/AUX
binding.

## M3 APPLICABLE declaration Pattern (issue #84; specification before implementation)

The [MDL manual §14.1](https://mdl-language.readthedocs.io/en/latest/14-data-type-declarations/)
defines `APPLICABLE` as a compound type name in a declaration Pattern:
it accepts values whose TYPE can legally be called as the operator of a
FORM. This includes FIX (position application), FUNCTION, MACRO and SUBR;
ordinary ATOM and LIST values do not match. An `APPLICABLE` alternative
inside `<OR ...>` must obey normal OR matching and preserve strict
declaration checking at function binding. The first unchanged source
use is `77defs.mud` expression 78, line 448, the `FN` parameter of
`DA`, with `<OR APPLICABLE ATOM FIX>`. This slice only adds the
declaration Pattern; it does not claim `APPLICABLE?` as a runtime SUBR,
custom APPLYTYPE, CLOSURE, OFFSET or RSUBR support.

The pinned Confusion `APPLICABLE?` predicate returns T for FIX,
FUNCTION, MACRO and SUBR, and FALSE for ATOM and LIST in six isolated
cases (`evidence/M3/applicable-predicate-reference.json`). Direct
`DECL?` probes of `APPLICABLE`, including the original OR shape,
instead enter `BAD-TYPE-SPECIFICATION1` with an `Atom REP has neither
LVAL nor GVAL` diagnostic (`applicable-decl-reference.json`), an
explicit reference defect or unsupported path. The Racket declaration
matcher follows the manual and the reference's type-applicability
observations. Tests must fail first at unknown declaration type, then
cover positive and negative values, OR, attached declaration checking,
and unchanged source progress with zero skipped forms.

## M3 `%<>` reader macro value (issue #86; specification before implementation)

The [MDL manual §17.1.1](https://mdl-language.readthedocs.io/en/latest/17-macro-operations/)
states that a single `%` immediately evaluates the following object
during READ and substitutes the resulting object. In particular, `%<>`
substitutes the canonical empty FALSE object, because evaluating the
empty FORM `<>` yields empty FALSE. Every occurrence denotes that
canonical value; it can be used in data or expression positions, and a
function definition containing it retains the same value on each call.
Six pinned Confusion cases in `evidence/M3/percent-empty-reference.json`
confirm TYPE FALSE, false truth, identity across occurrences and calls,
and use inside a source-shaped argument list. The first unchanged
source use is `77makstr.mud` expression 6, line 73, in `SOBJECT`.

This vertical slice recognizes only a `%` whose payload is the empty
FORM. It substitutes the canonical empty FALSE value at compilation
of each loaded source expression, which has the same observable result
for this side-effect-free form. Other `%` payloads and `%%` remain
explicitly unsupported; the broader read-time evaluation mechanism
must be designed and tested before later source uses such as
`%<STRING <ASCII 10>>` or `%,OVISON` are admitted. Tests must fail
first at the unsupported percent node, then cover data and expression
positions, identity, and rejection of other percent forms.

## M3 custom WORD-primtype `#type` literal (issue #88; specification before implementation)

The [MDL manual §6.2–6.3.4](https://mdl-language.readthedocs.io/en/latest/06-data-types/)
defines `#type representation` as reading a value in the TYPE's
primitive representation and changing its TYPE to `type`. The
unchanged `81tell-repl.mud` expression 1 registers `PSTRING` with
`NEWTYPE PSTRING WORD`; expression 2 uses `(OBJ #PSTRING 0)` as an
ordinary two-element AUX formal with a typed WORD default. The parser
must read `#PSTRING 0` as one typed-literal node, and evaluation must
produce a PSTRING value with PRIMTYPE WORD and 36-bit zero data.
Decimal and octal integer WORD representations use the existing
36-bit range checks. An unregistered type or a type with another
primitive storage class must fail explicitly. This slice does not
support custom STRING/LIST/VECTOR typed representations or FLOAT bit
reinterpretation.

Six clean pinned Confusion probes in
`evidence/M3/pstring-literal-reference.json` confirm TYPE PSTRING,
PRIMTYPE WORD, equality to a CHTYPEd #WORD value, and binding through
an AUX default. Its unknown-type case enters an error. Confusion also
accepts a PSTRING declared with LIST primitive and a FLOAT-shaped
representation in the retained deliberate cases; the Racket slice
keeps the manual's primitive-type safety check and integer-only WORD
representation. Tests must demonstrate the existing split-token
failure first, then verify reader shape, source evaluation, 36-bit
data, AUX binding, and strict rejection of unsupported typed forms.

## M3 positional `#DECL` metadata on FUNCTION (issue #90; specification before implementation)

The [MDL manual §14.9](https://mdl-language.readthedocs.io/en/latest/14-data-type-declarations/)
defines an RSUBR-style `#DECL` as positional metadata beginning with
the STRING `"VALUE"`, followed by a result Pattern, required argument
Patterns, and optionally the STRING `"OPTIONAL"` before optional
argument Patterns. It is distinct from the ATOM declaration's
alternating `(ATOM ...) Pattern` pairs. The manual says this positional
form is useful on RSUBR/RSUBR-ENTRY, not on an interpreted FUNCTION.
The unchanged `81tell-repl.mud` expression 10 attaches this form to
`DEFINE TELL`; the loader must parse it as typed declaration data
rather than misinterpret the leading STRING as an ATOM-list.

Pinned Confusion accepts the positional form on a FUNCTION but does
not enforce its argument or result Patterns there: four clean cases
and five deliberately mismatched cases all complete without errors
(`evidence/M3/function-decl-*-reference.json`). The Racket runtime
will validate the supported `"VALUE"`/`"OPTIONAL"` grammar and
Patterns, preserve the positional declaration as metadata, and apply
no ATOM-variable checks when it is attached to a FUNCTION. This is an
observed placement rule, not a general no-op for unsupported syntax.
`"QUOTE"`, `"TUPLE"`, `"ARGS"` and `"CALL"` positional markers,
and actual RSUBR application, remain separate work and must fail
explicitly if encountered in this slice. Tests must fail first at
the current atom-list/pattern error, then cover valid metadata,
non-enforcement on FUNCTION, malformed markers and strict Pattern
validation before measuring unchanged source progress.

## M3 `!\` CHARACTER reader notation (issue #92; specification before implementation)

The [MDL manual §7](https://mdl-language.readthedocs.io/en/latest/07-structured-objects/)
defines `!\` followed by one ASCII character as a CHARACTER value of
PRIMTYPE WORD. The following character is consumed even when it is a
separator such as space. The unchanged `81tell-repl.mud` expression 23,
line 45, uses `<PRINC !\ >` to output one space. This is distinct
from `!<...>` and `!.X` SEGMENT notation, which must retain their
existing behavior. An `!\` at end of input is a reader error.

Five isolated pinned Confusion cases in
`evidence/M3/space-character-reference.json` show `!\ ` has TYPE
CHARACTER, PRIMTYPE WORD, ASCII code 32, value identity across
occurrences, and remains a CHARACTER returned from a function.
The Racket reader must produce a dedicated CHARACTER node, and the
compiler must construct the existing runtime CHARACTER value in data
and expression positions. Tests must fail first at unsupported SEGMENT
notation, then check reader shape, space and ordinary characters,
value operations, incomplete input and SEGMENT non-regression before
unchanged source validation.

# M3 issue #94 specification: session-aware `%` READ evaluation

The [MDL manual §17.1.1](https://mdl-language.readthedocs.io/en/latest/17-macro-operations/)
requires a single `%` to evaluate the following object immediately during
READ at any nesting depth, substituting the resulting MDL object. The
syntax-only parser continues to record a percent node; the executable
reader invokes a session callback as soon as its payload has been read.
The callback must finish before the reader consumes the next sibling. It
must preserve the resulting object, including identity, for the lifetime
of the loaded definition. Errors in that evaluation stop reading at the
percent source position. `%%` is separate and remains unsupported.
After substitution, the enclosing expression treats the object exactly
like any object read there: a substituted FORM or structured object in
expression position undergoes ordinary MDL evaluation, while quoted
data retains the object. Syntax-sensitive constructs such as DEFINE
must inspect the substituted object's actual type and contents; an
opaque reference cannot be treated as an unknown formal/name token.
If `%` yields a SEGMENT object in an evaluated structure or call-argument
position, its payload is evaluated and spliced by the existing SEGMENT
rules. The same object in a standalone expression is an explicit
ILLEGAL-SEGMENT error. A read-time substitute must keep this positional
distinction rather than always calling ordinary `mdl-eval` on SEGMENT.

The original `81tell-repl.mud:46` needs `%<STRING <ASCII 10>>`. The manual's
`ASCII` conversion is bidirectional: a FIX ASCII code becomes a CHARACTER;
a CHARACTER becomes its FIX code. The supported code range is 0–127, as
confirmed by pinned Confusion (128, 256 and -1 report out of range).
`STRING` concatenates STRING and CHARACTER arguments after normal left to
right evaluation; zero arguments yield the empty STRING. Unsupported types
raise an error. Existing STRING data is represented by Racket strings and
CHARACTER by the existing typed WORD value.

Native cases in `evidence/M3/percent-read-reference.json` verify type,
conversion, newline length, read-before-evaluation, adjacent order,
once-only function substitution, quoted LIST identity, nested LIST, and
the prior `%<>` behavior. Deliberate errors are retained in
`evidence/M3/percent-read-errors-reference.json`; their probe command
exits 1 because the tool treats native stderr as a failed clean case.
The regression test must first fail on the original percent construct,
then pass for these cases and prove that syntax-only parsing has no MDL
side effects. Arbitrary reader table changes, `%%`, and READ-time channel
control remain outside this slice and must fail explicitly.

## M3 NTH declaration repetition (issue #96; specification before implementation)

The [MDL manual §14.1](https://mdl-language.readthedocs.io/en/latest/14-data-type-declarations/)
defines `[number:fix Pattern ...]` inside a structured declaration as
the Pattern sequence repeated that positive number of times. Each
repeated position is required; a following ordinary Pattern applies
after the repeats, and `[REST ...]` may constrain the remaining tail.
Additional undeclared elements are allowed. Zero/negative counts and
an empty Pattern sequence are errors. A large count must not require
allocating that many pattern copies merely to reject a short value.

Thirteen clean pinned Confusion observations in
`evidence/M3/nth-decl-reference.json` confirm positive count,
multi-Pattern order, prefix/suffix placement, trailing REST, short
values, mismatched elements and extra undeclared elements. Four
deliberate error-level cases in `evidence/M3/nth-decl-errors-reference.json`
confirm invalid count and empty sequence diagnostics. Confusion's
explicit `DECL?` rejects `ANY` as BAD-TYPE-SPECIFICATION1, while its
attached `#DECL` accepts `[3 ANY]` but does not reject a two-element
argument. The manual and this runtime's existing `ANY` Pattern and
attached-declaration enforcement require a three-element minimum.
This is an explicit manual/reference deviation, not silent parity.

Focused tests must first fail on NTH normalization, then cover the
manual rule in DECL?, attached FUNCTION declarations, zero/negative
counts, malformed brackets, large counts, and the existing REST rule.
The unchanged original source is the final progression check.

## M3 deferred attached declaration type names (issue #98; specification before implementation)

An attached `#DECL` is a data value that may name a TYPE atom declared
later. Preserve such an unresolved ATOM Pattern at definition time and
resolve it when checking a bound argument, assignment, or result. If it is
still neither a registered TYPE nor an atom with a `DECL` association,
checking raises `unknown declaration type`; it must never match as `ANY`.
The same rule applies inside OR and structured Patterns. Explicit `DECL?`
continues to normalize and validate its Pattern immediately. Malformed
structure, unsupported Pattern forms, aliases with cycles, and positional
metadata retain their existing strict behavior.

Pinned Confusion accepts a FUNCTION definition with `#DECL ((X) PRSOBJ)`
and a call with `1`, but its explicit `DECL?` on `PRSOBJ` enters
`BAD-TYPE-SPECIFICATION1`. It does not enforce attached declarations,
while this runtime follows the manual's attached-check rule. Delaying only
the TYPE name resolution lets the original source definition load without
discarding the declaration or changing later checking. Tests must first
show the original strict-definition error, then verify definition,
late registration, strict call-time failure, explicit `DECL?` failure,
and the unchanged source progression.

## M3 duplicate attached ATOM declarations (issue #100; specification before implementation)

The original `77act2.mud:424` `BALLOON` function declares `M` twice in one
`#DECL`, first as `<OR FALSE <PRIMTYPE VECTOR>>`, then as a narrower
`<OR FALSE <<PRIMTYPE VECTOR> ANY ROOM>>`. The MDL manual §14 describes
an ATOM declaration as repeated `(atoms:list Pattern)` pairs and does not
specify a duplicate-name rule. Pinned Confusion accepts a duplicate
declaration value and function definition, but omits attached checking,
so it cannot distinguish precedence during a call. Conservatively retain
both Patterns and require a value to satisfy each, in source order. This
does not silently discard either original constraint. The special VALUE
duplicate rule stays unchanged in this bounded slice. Malformed and
unsupported Patterns remain strict errors.

Tests must first fail at the existing duplicate-name error, then verify
both constraints, source-order failure, acceptance of the original
`BALLOON` declaration, and source-load progression. This conjunction is
an explicit inference from the manual's pairing semantics, not a claim of
verified historical precedence.

## M3 EVENT/HANDLER registration (issue #102; specification before implementation)

The [MDL manual chapter 21](https://mdl-language.readthedocs.io/en/latest/21-interrupts/)
defines `EVENT name priority` as creating or retrieving an enabled IHEADER,
`HANDLER iheader applicable` as prepending a HANDLER, and `OFF` on a HANDLER
or IHEADER as removing it from the active list or name association while
returning the same object. EVENT on an IHEADER re-associates it; HANDLER on
an existing detached HANDLER reattaches it. Both types have VECTOR primitive
type and object identity. The event registry belongs to one MDL session.

This bounded slice supports registration and removal for user-defined
STRING-named events, a positive FIX priority, and FUNCTION/SUBR-like
callables in the current PROCESS. Other APPLICABLE types are explicitly
unsupported. It rejects unimplemented predefined events such as `"GC"`,
`"CHAR"`, `"READ"`, `"WRITE"`, `"IPC"` and `"BLOCKED"` explicitly until
their event sources and scheduling can be implemented. Handler dispatch,
process-targeted handlers, and `INTERRUPT` remain unsupported and must not
silently become no-ops. This allows the original `"DIVERT-AGC"` setup to
be represented faithfully while making the next missing internal event
explicit. Native Confusion's EVENT/HANDLER/OFF/ON return `T` for even invalid
arguments, and its INTERRUPT is unbound; those are reference limitations,
not the manual semantics implemented here. The `INTERRUPTS` OBLIST,
name-to-IHEADER `GET` association and structural indexing/mutation of
IHEADER/HANDLER values remain unimplemented; only STRING name lookup through
EVENT is supported. Tests must establish identity,
removal, reattachment, session isolation, strict unsupported
paths, and source progression before claiming the slice.

## M3 interrupt dispatcher (issue #104; specification before implementation)

The [MDL manual chapter 21](https://mdl-language.readthedocs.io/en/latest/21-interrupts/)
sets normal interrupt level to zero. An enabled event occurrence dispatches
at a safe interpreter point when its IHEADER priority exceeds the current
level; otherwise it is queued. Pending occurrences retain already evaluated
arguments and occurrence order. Lowering `INT-LEVEL`, or finishing a handler,
delivers eligible pending occurrences before normal execution resumes.
Handlers run newest first at the IHEADER priority; the previous level is
restored even on an error. `OFF` during dispatch prevents a removed, pending
handler from running. A disabled or disassociated header does not dispatch;
if disabled before queued delivery, its pending occurrence is suppressed.
Each MDL session owns its interrupt level and queue.
If a handler raises, its queued events remain pending while that exception
propagates. A later `INT-LEVEL` call is a safe delivery point even when it
sets the level to its current value, so eligible events cannot remain stuck.
A later event-source call also drains older eligible occurrences before
dispatching the new occurrence, preserving occurrence order after recovery.
The new occurrence enters the queue before draining; if an older callback
raises, the new occurrence remains pending for another safe point.

`INT-LEVEL` with no arguments returns the current FIX level; with one FIX
it sets the level and returns the old one. `ENABLE` and `DISABLE` require a
session-owned IHEADER and return it. Focused tests call the host-only
event-source API deterministically. Callback arguments go
through the ordinary evaluated-argument application path. This slice keeps
`"GC"` guarded until real collection and after-collection dispatch exist.
The manual classifies `"GC"` and `"DIVERT-AGC"` as internal interrupts.
All other named predefined interrupts in manual chapter 21 remain guarded
until their sources exist. The earlier source-loading slice permits
`"DIVERT-AGC"` registration because the original handler is immediately
removed; its automatic event source remains unimplemented and unclaimed.
Process-targeted handlers, `DISMISS`, and automatic sources remain unsupported.

## M3 logical movable storage and explicit GC (issue #104; specification before implementation)

The manual's chapters 21–22 specify that `GC` returns reclaimed MDL words,
while `BLOAT` returns free movable-storage words. An explicit collection
reports `GC` after collection with `(FLOAT seconds, FIX 1, ATOM GC)`.
`DIVERT-AGC` runs before a deferrable collection with `(FIX requested-words,
ATOM initiator)`. The original `77rooms.mud:78–104` installs these handlers,
removes both initially, and reattaches `GC-HAND` on first diversion.

The bounded Racket model tracks each newly constructed LIST pair as two
logical words and each VECTOR/UVECTOR backing block as `2*n+2`/`n+2` words,
respectively, following manual appendix 1. REST views share their backing
allocation. An entry holds only a weak reference, so a host major collection
can establish that an allocation is no longer reachable; a subsequent ledger
sweep releases its logical words once. This is a logical subset, not a claim
about host bytes or exact PDP-10 accounting for every object class. In
particular reader-created strings, atoms, closures, frames, deferred list
elements and other structures are not yet charged. Any GC result is the
reclaimed words **within this tracked subset**. An explicit GC calls the host
collector, sweeps the ledger, and only then delivers its event. Repeated GC
with no newly dead tracked object returns zero. A live shared or cyclic
structure remains charged until the entire allocation becomes unreachable.
Every session has an independent ledger and capacity.

`BLOAT` supports the original one-argument movable-free-space request; it
validates a nonnegative FIX and expands logical capacity enough to satisfy
the requested free space, returning current free words. Other argument
positions are rejected until their storage classes are modeled. At a
tracked allocation boundary, exhaustion signals `DIVERT-AGC` once; if
the handler's `BLOAT` makes room, allocation proceeds without collection.
Otherwise the runtime performs a host collection and emits `GC` with reason
2 and the allocating operation. Pressure handlers run at a safe interpreter
boundary, not from a host GC callback. Pressure recursion is suppressed.
The chosen initial capacity is an implementation parameter, not a claim of
historical GC timing. Host-initiated automatic collections alone do not
create MDL events. `GC` arguments beyond the no-argument form remain
unsupported until the manual's parameter changes can be modeled.

**Capacity growth policy (review R2/R10, PR #123; consolidated 2026-11-23
from `evidence/M3/review/R2.md`).** When a tracked allocation of `words`
would exceed logical capacity: (1) `DIVERT-AGC` is emitted; if its handler's
`BLOAT` makes room, the allocation proceeds with no sweep and gc-min does
not apply. (2) Otherwise a host major collection and ledger sweep run and
`GC` is emitted. (3) Only after such a sweep, if free words are below
`max(words, gc-min)` (gc-min = 8192, manual §22.5), capacity grows to
`min(fix-max, max(used + max(words, gc-min), ceil(capacity × 3/2)))`;
geometric growth keeps a steadily growing live set from triggering a
quadratic number of sweeps. If `used + max(words, gc-min)` exceeds the FIX
maximum, a strict host error (`storage overflow`) is raised, not an MDL
ERROR. Explicit `<GC>` sweeps without growing capacity; `BLOAT` sets an
explicit free-word floor and is independent of this policy. Reported
`used`/`free`/capacity values are an approximation of PDP-10 accounting, not
equivalent to it. Not checked: a handler's `BLOAT` that would push capacity
past the FIX maximum. Tests must not assert exact host-collection counts
that depend on BC/CS liveness (R10). Code: `mdl/runtime/core.rkt`
(`current-mdl-gc-min`, allocation pressure path); tests
`tests/logical_gc_test.rkt`.

## M3 SPECIAL and UNSPECIAL declaration wrappers (source `77rooms.mud:189`)

Manual chapter 14 permits `<SPECIAL Pattern>` and `<UNSPECIAL Pattern>` at
the top level of an ATOM declaration. The marker describes local-binding
specialty for compiled code; interpreted bindings are inherently SPECIAL
while `SPECIAL-CHECK` is off initially. The wrapped Pattern still constrains
the value under this runtime's attached-declaration checking. Preserve the
marker in normalized metadata so a future compiler can inspect it, and
delegate value matching to the nested Pattern. A wrapper needs exactly one
Pattern and is rejected inside OR, a structure, a positional RSUBR-style
declaration, or an explicit `DECL?` Pattern. This bounded slice does not
implement `SPECIAL-CHECK` or change binding representation.

Pinned Confusion accepts valid SPECIAL and UNSPECIAL wrappers. Its attached
declaration check also accepts a mismatched STRING for `<SPECIAL FIX>`;
that observation reflects its previously documented lack of attached
checking, not a rule to drop the nested Pattern in Racket. The original
source uses `<SPECIAL CHANNEL>` and `<SPECIAL STRING>` in attached
declarations. Focused tests must fail first at unsupported SPECIAL, then
cover valid wrappers, nested-pattern enforcement and malformed placement.

## M3 built-in LOSE WORD literal (source `77rooms.mud:218`)

Manual appendix 3 lists `LOSE` as a built-in WORD-primitive placeholder.
The original error handler stores `#LOSE 27` and octal `#LOSE` values in
channel control slots. Read the numeric payload with the existing 36-bit
WORD literal rules, then tag it as LOSE. TYPE and PRIMTYPE report LOSE and
WORD. A LOSE value may be stored and inspected; its meaning as a placeholder
does not make arbitrary arithmetic legal. Preserve the established strict
numeric parsing and overflow errors. This source-loading slice registers
the built-in TYPE and permits only its WORD retyping path. It does not
implement CHANNEL or the source error handler's I/O operations.

## M3 ERROR interrupt and resumable ERROR frame (source `77rooms.mud:261`)

Manual chapter 21 says an `"ERROR"` interrupt occurs when `ERROR` is called.
Handlers receive the FRAME of that ERROR call, followed by its evaluated
arguments (which a TUPLE formal can collect). An eligible handler runs at
the registered priority. Unlike ordinary events, ERROR occurrences cannot
be queued: at an interrupt level at least as high as its priority, normal
ERROR handling runs. A handler may use `<ERRET value frame>` to resume the
interrupted ERROR call with `value`; a normal handler return falls through
to the original error. The frame must belong to the current session and
remain live during handler execution. Invalid, stale and foreign frames
raise strict errors. Existing error value reporting remains the fallback.

This slice covers explicit `ERROR` calls and their registered handlers.
It does not convert arbitrary host exceptions into MDL ERROR interrupts,
implement error-level REPLs, or supply the original host's CHANNEL/FINISH
operations. Tests must demonstrate failing registration first, then verify
argument types and order, normal fallthrough, ERRET, interrupt-level
suppression, session isolation, and stale-frame rejection. Pinned Confusion
stubs EVENT/HANDLER so it cannot certify callback delivery; the manual is
the behavioral specification.

**Delivery and ERRET level (review R8, PR #116; consolidated 2026-11-23
from `evidence/M3/review/R8.md`).** ERROR occurrences are delivered
synchronously by the ERROR call and never enter the session pending queue,
so an older pending occurrence cannot capture one and no occurrence can
outlive its FRAME. ERRET resumes the ERROR call at the interrupt level that
is current when ERRET runs (following manual 21.8.11, where a resolving
handler does `<INT-LEVEL 0>` first); it does not restore the pre-interrupt
level. Returning from ERROR is a safe point: pending occurrences eligible at
the resumed level are delivered exactly once, lower ones stay queued. A
normal handler return, or a host exception leaving a handler, still restores
the previous level; FRAME liveness ends when the ERROR call is left in every
case. Nested errors follow the same rule literally. "ERRET keeps the current
level" is a documented **inference** (§21.8.11, §21.7.3), not an explicit
manual rule, and Confusion cannot confirm it (EVENT/HANDLER are stubs).
RETURN, AGAIN or GO from a handler to an outer activation still restore the
previous level through delivery cleanup; that asymmetry is a documented
deviation risk. `DISMISS`, error-level LISTEN, FRAME/FFRAME traversal, ERRET
without a FRAME and FINISH are unsupported. SUBR failures, unassigned
variables and arity errors remain strict host failures that do not raise the
"ERROR" interrupt; this affects the source's ^G/TTY recovery and crash-report
paths in HANDLE. Tests: `tests/erret_interrupt_cleanup_test.rkt`,
`tests/error_interrupt_test.rkt`.

## M3 built-in CHANNEL type declaration (source `77rooms.mud:270`)

Manual chapter 11 defines CHANNEL as a built-in VECTOR-primitive type.
The original GDECL for `SCRIPT-CHANNEL` names it before any channel is
constructed in the Racket loader. Registering this TYPE makes TYPEPRIM and
declaration normalization recognize it; ordinary GDECL checks still reject
values of other types. This slice does not fabricate a CHANNEL value, open
files, or provide input/output behavior. CHANNEL construction and operations
remain explicit later dependencies. The regression first fails on the
original unknown-TYPE error and then verifies TYPEPRIM and strict GDECL
matching.

## M3 numeric 0? and 1? predicates (original `DIVERT-FCN`)

Manual chapter 8 defines `0?` and `1?` for one FIX or FLOAT argument.
Each returns the session's T atom if its numeric value is zero or one,
otherwise empty FALSE. Wrong types and arity raise errors. The original
`DIVERT-FCN` uses `1?` to attach `GC-HAND` only at its first diversion.
This runtime must use the predicate's ordinary MDL truth values, including
for 0.0 and 1.0; the numeric comparison does not coerce other types.

## M3 ISTRING and shared STRING REST views (`77rooms.mud:559`)

Manual chapter 7 defines `ISTRING length [expression]` as a STRING of
length FIX characters. Omitted expression produces ASCII NUL characters;
when present, its result must be a CHARACTER and is re-evaluated per slot.
`REST` on STRING returns a view into the same character storage, including
the zero-length view at its end. Mutating a view with PUT changes the
original STRING. Pinned Confusion confirms a three-character NUL fill,
character fill, an empty STRING at REST length, and a PUT through a REST
view changing `"XXX"` to `"XYX"`.

The runtime represents a REST view by backing STRING plus start and
length, keeping value TYPE STRING. `LENGTH`, NTH, PUT, EMPTY?, LENGTH?,
STRING concatenation and text output read the view's visible range.
Identity compares backing storage and range; structural equality compares
visible characters. A valid offset is from zero through length; wrong
length or fill types raise errors. The source-loading form uses omitted
fill. ISTRING is an ordinary SUBR: its arguments are evaluated once on
every call path, and the fill value is then EVALed once per character (see
"M3 constructor evaluation policy (review R5)" below). No raw FORM is
needed at any call boundary. (Corrected 2026-11-23: an earlier version of
this section required the raw FORM at the compiled boundary; R5, PR #114,
removed that special path.)

**STRING views as primitive arguments and PNAME snapshots (review R7, PR
#114; consolidated 2026-11-23 from `evidence/M3/review/R5R7.md`).** Any
primitive that takes a STRING accepts a native STRING or a shared REST view;
other TYPEs, including CHTYPEd STRING-primtype values, fail explicitly
unless a section below says otherwise. A primitive that retains a name takes
an immutable snapshot of the visible characters at the call
(`mdl-string-snapshot`): INSERT and ATOM (the PNAME), LOOKUP and REMOVE (the
OBLIST key), EVENT and ON (the event name), FLOAD (the host path) and SAVE (the
recorded file-spec, ADR-0048). A PNAME therefore never aliases user
storage; a later PUT on the original STRING or any view of it changes
neither the atom's name nor OBLIST lookup. The parent STRING and its views
keep sharing storage with each other. Evidence:
`evidence/M3/review/r7-string-view-reference.json`; tests
`tests/string_view_consumers_test.rkt`.

## M3 registered structured TYPE heads in declarations (`77rooms.mud:725`)

Manual chapter 14 permits a structured declaration headed by a registered
structured TYPE. The original `<CHANNEL FIX>` names built-in CHANNEL, whose
primitive representation is VECTOR. Normalization must accept any current
registered TYPE whose primitive is LIST, VECTOR, UVECTOR, or TUPLE, retain
that TYPE atom, and validate the same positional element Patterns as the
existing LIST/VECTOR rules. Matching checks the actual TYPE, not merely
the primitive representation. Thus a plain VECTOR must fail `<CHANNEL FIX>`.
Unsupported storage classes such as BYTES and STRING remain explicit errors
for this slice. Tests should first reproduce the unsupported CHANNEL head,
then cover a custom VECTOR-primitive NEWTYPE's matching and strict failure.

## M3 BLOCK/ENDBLOCK OBLIST search state (`77rooms.mud:804`)

Manual chapter 15 defines `.OBLIST` as the READ search list. Unqualified
ATOMs are looked up in its OBLISTs in order and inserted into the first
OBLIST on a miss. `BLOCK` takes an evaluated nonempty LIST of OBLISTs,
pushes the current search list independent of function application, installs
the argument as the current `.OBLIST`, and returns it. `ENDBLOCK` restores
and returns the previous list. An unmatched ENDBLOCK and malformed search
list fail. State belongs to one session. Explicit `!-` trailers still
select their named OBLIST independently of the current search list.

The original block in `77rooms.mud` prepends the FLAG OBLIST while
defining `FLAG-NAMES`; the following `PSETG` must resolve FLAG-NAMES in
INITIAL but intern new flag atoms in FLAG. ENDBLOCK restores the prior
lookup for the later VAL-NAMES definitions. The source reader compiles one
expression at a time, so runtime atom resolution can follow the active
search list. This slice does not implement DEFAULT insertion redirection,
READ's explicit lookup argument, or print-time minimal trailer selection.

## M3 authoritative OBLIST path, ROOT identity and read-time atoms (review R3/R4)

Consolidated 2026-11-23 from `evidence/M3/review/R3R4.md` (PR #118); it
refines the BLOCK/ENDBLOCK section above.

**One search path.** The manual (15.3) says READ resolves PNAMEs through
the LVAL of OBLIST. That LVAL is the only search path: the innermost binding
of the session's ROOT `OBLIST` atom, including the session top-level frame;
with no binding, the startup list `(INITIAL ROOT)` applies. There is no
separate cached copy. PROG/AUX/formal bindings, SET, BLOCK and ENDBLOCK all
act on the ordinary LVAL, so normal exit, RETURN/AGAIN, ERROR unwinding and
host exceptions restore resolution together with the binding. A
bound-but-unassigned OBLIST is unassigned. BLOCK pushes the current path and
SETs; ENDBLOCK pops and SETs; both are independent of function frames
(15.6). SET of OBLIST requires a nonempty LIST of OBLISTs (stricter than
Confusion, which defers the failure to the next read); atom resolution fails
explicitly when the current LVAL is unassigned or not such a LIST.

**Read-time atoms.** Atoms are identified when their top-level expression is
read: compiled code resolves every user-text ATOM of an expression once,
before it runs, so function bodies keep their read-time atoms when OBLIST is
rebound later. FLOAD inside a binding of OBLIST reads the file under that
binding. Reader-macro heads (LVAL, GVAL, QUOTE) are ROOT atoms. `A!-` (empty
trailer) names ROOT and inserts into ROOT on a miss; `A!-B` looks up B
through the current path.

**ROOT identity.** Following 15.5 and pinned Confusion, each session seeds
ROOT at creation with the complete startup ROOT inventory of pinned
Confusion (`mdl/runtime/root-names.rktd`, 240 names), whether or not the
primitive is implemented; INITIAL starts empty. An unimplemented name is a
ROOT atom without a GVAL and fails strictly when applied. Runtime-internal
names (T, type names, DECL/OBLIST indicators, REDEFINE, QUOTE, GC
initiators, interpreter globals, INCHAN/OUTCHAN, REP) are always the cached
ROOT atoms (`mdl-root-atom`): never looked up through `.OBLIST`, never
interned into a user OBLIST, unaffected by later REMOVE/INSERT on ROOT. A
built-in SUBR is the GVAL of its ROOT atom only; a same-named atom on another
OBLIST, or an uninterned one, is unbound, and GVAL queries never intern.
After the full source load, OBLIST placement matches pinned Confusion
(`tests/historical_oblist_placement_test.rkt`) except two allowlisted,
separately tracked differences: `;` comment objects are not READ by this
reader, and Confusion's startup INTERRUPTS OBLIST contents are not modelled.
(The former allowlist entries for backslash-escaped trailers and `.5` were
removed when #119 and #124 were fixed on the umbrella branch.)

**Deviations and gaps.** Compiler special forms and the interpreted FSUBR
dispatch are recognised by PNAME, not ROOT identity (under a BLOCK that omits
ROOT, `<DEFINE ...>` still compiles as DEFINE). `%` read-eval runs mid-form,
before the enclosing form's atoms are hoisted. The compiler's compile-time
check for substituted ATOM names may intern a stray atom before raising its
unsupported error. Not implemented: OBLIST's GVAL, DEFAULT insertion
redirection, READ's look-up argument, `PARSE`/`READ` SUBRs and print-time
trailer selection. Evidence: `evidence/M3/review/R3R4-oblist-reference.json`,
`R3R4-oblist-error-reference.json`, `confusion-root-names.json`; tests
`tests/oblist_identity_test.rkt`.

## M3 IUVECTOR and CHUTYPE (`77rooms.mud:1249`)

Manual chapter 7 defines `IUVECTOR length [expression]` as a UVECTOR with
the expression evaluated once for each element. Without the expression,
the UVECTOR has UTYPE LOSE and zero-word placeholders. The length is a
nonnegative FIX. Filled UVECTOR elements must have one legal uniform TYPE.
The zero-length REST view retains UTYPE, so the original source can allocate
20 empty slots, take REST at 20, then change that empty view to OBJECT.

`CHUTYPE uv type` changes the UVECTOR's uniform TYPE in place and returns the
same UVECTOR. The type header is shared by REST views of the same backing
storage: changing a tail's UTYPE changes the base's UTYPE too. The pinned
Confusion probe in `evidence/M3/chutype-alias-reference.json` observes WORD
from both base and tail, including an element outside the visible tail,
after changing the tail. Focused regressions first failed with base UTYPE
and first-element TYPE FIX on 2026-11-22. Each existing element in the
shared storage is reinterpreted at the new TYPE only if
old and new element PRIMTYPE agree. LOSE is a special case that can become
any type legal in a UVECTOR. Wrong arity, non-UVECTOR, invalid TYPE, and
incompatible primitive storage fail explicitly. This slice tests mutation
through a shared UVECTOR view and a zero-length LOSE-to-OBJECT cast; the
runtime shares the UTYPE header across views of the same storage.

## M3 IVECTOR (`77rooms.mud:1545`)

Manual chapter 7 defines `IVECTOR length [expression]` as a VECTOR of
nonnegative FIX length. The optional expression evaluates once per slot;
omission fills each slot with the zero-word LOSE value. The source's LEXV
allocation passes a quoted REST expression whose evaluation must create
ten distinct empty STRING views. Wrong arity or length fails explicitly.

## M3 constructor evaluation policy (review R5)

Consolidated 2026-11-23 from `evidence/M3/review/R5R7.md` (PR #114). Manual
§7.5.4 defines ILIST, IVECTOR, IUVECTOR and ISTRING as SUBRs; ILIST is not
implemented (when added it must reuse `constructor-fill-thunk`). Every call
path (compiled call, interpreted FORM or FUNCTION body, APPLY, MAPF)
evaluates the arguments once, including `!` SEGMENT splicing, before the
procedure runs. The optional second argument's **value** is then EVALed
once per generated element, in element order: `<IVECTOR 3 '<SET A <+ .A
1>>>` yields `[1 2 3]`, while `<IVECTOR 3 <SET A <+ .A 1>>>` evaluates its
argument once and yields `[1 1 1]`. A VECTOR fill is rebuilt per element
(`=?` but not `==?`). ISTRING requires each per-element result to be a
CHARACTER. IUVECTOR validates each value as it is produced: the first value
fixes the UTYPE, STRING is never permitted, and a mismatched value fails at
once, so later fills are not evaluated. No dispatcher special-cases these
constructors (`mdl/runtime/core.rkt` `constructor-fill-thunk`).

Pinned Confusion agrees for IVECTOR and ISTRING on all paths and for the
IUVECTOR failure counts. **Recorded deviation:** on success, Confusion's
IUVECTOR evaluates the fill once extra to fix the type (`<IUVECTOR 3 '<SET A
<+ .A 1>>>` gives `![2 3 4!]`, A=4), contradicting the manual's own example;
the runtime follows the manual (`![1 2 3!]`, A=3). No original-source call
is affected. Evidence: `evidence/M3/review/r5-constructor-eval-reference.json`,
`r5-iuvector-uniform-reference.json`; tests
`tests/constructor_eval_policy_test.rkt`.

## M3 MAPR (`77rooms.mud`)

Manual chapter 10 defines MAPR with MAPF's final function, loop function,
multiple structured inputs, and map control operators. At each position,
the loop function receives each input's `REST` at offset zero, one, etc.,
so its PUT at index one mutates the underlying source. Iteration stops at
the shortest input. MAPRET, MAPSTOP, and MAPLEAVE use the same control
semantics as MAPF. The existing MAPF collection and control flow is shared;
only the loop arguments differ. A bounded regression covers LIST and VECTOR
mutation and map termination.

## M3 CHTYPE for ATOM-primitive NEWTYPE (`77np.mud:10`)

Manual chapter 6 permits NEWTYPE with primitive ATOM, including the game's
PREP and ADJECTIVE types. CHTYPE of an ATOM to such a registered type keeps
the same underlying ATOM while changing the visible TYPE; casting back to
ATOM returns the underlying ATOM. A different PRIMTYPE remains an error.

## M3 MIN (`77dung.mud:57`)

Replaced 2026-11-23 with the contract implemented by review R6 (PR #115;
evidence `evidence/M3/review/R6.md`). The earlier FLOAT-typed WORD
sentinel and its "other arithmetic not implemented" limitation no longer
exist.

Manual chapter 3 defines MIN over any number of FIX/FLOAT arguments, with
FLOAT contagion; zero arguments return the greatest FLOAT. The runtime models
the 36-bit target: `<MIN>` is the ordinary FLOAT (2^27−1)·2^100, the greatest
PDP-10 single-precision value, held exactly as a host flonum. It takes part
in arithmetic, comparison, `==?`/`=?` and MIN like any FLOAT.

CHTYPE from FLOAT to a WORD-primtype TYPE (FIX, WORD, user WORD NEWTYPEs)
reinterprets the FLOAT's PDP-10 single-precision word image: sign bit,
excess-128 exponent in bits 1–8, normalized 27-bit fraction, negative values
as the two's complement of the whole word. `<CHTYPE 1.0 FIX>` is
201400000000₈ and `<CHTYPE <MIN> FIX>` is 377777777777₈ = 34359738367, so
the source's BIGFIX (77dung.mud:57) is 17179869183. A host flonum with no
exact 36-bit image (more than 27 fraction bits, e.g. `0.1`, or an exponent
outside the excess-128 range, or NaN/infinity) makes CHTYPE fail with
"FLOAT has no exact PDP-10 FLOAT word image"; it is never rounded. CHUTYPE
of a FLOAT UVECTOR converts every element this way and changes nothing if
any element fails. The format is checked against the MIT PDP-10 Info file
"Floating-Point". `FLOAT` requires a FIX argument (manual 3.4; Confusion
"Arg to FLOAT must be FIX").

Pinned Confusion reinterprets the 64-bit host double instead: `<MIN>` is
`DBL_MAX` and the cast gives 9218868437227405311. This magnitude difference
is a documented reference deviation. Not supported: CHTYPE from FIX/WORD to
FLOAT, bit operations (ANDB etc.) on FLOAT, a PDP-10 overflow range in FLOAT
arithmetic (host doubles overflow only at IEEE limits, so `<* <MIN> 2>`
succeeds here), PDP-10 27-bit rounding of computed FLOATs, FLOAT printing
(UNPARSE/PRIN1 refuse FLOAT), and negative zero (encodes as the zero word;
separate open issue). Code: `mdl/runtime/core.rkt` (`float-word-bits`,
`mdl-min`); evidence `evidence/M3/review/r6-min-float-reference.json`; tests
`tests/min_test.rkt`.

## M3 CHTYPE for STRING-primitive NEWTYPE (`77dung.mud:69`)

The original ADD-BUZZ macro creates BUZZ values by changing a STRING's
TYPE. CHTYPE must preserve the same STRING contents and backing storage
when moving between STRING and a registered STRING-primitive type. The
primitive must match; other built-in STRING conversions remain strict.

## M3 custom STRING `#TYPE` literal (`77dung.mud:148`)

Manual chapter 6 defines `#TYPE representation` as a read-time type change.
For a registered STRING-primitive type such as NEXIT, `#NEXIT "text"`
must read as one typed value with the same string payload. The compiler
retains the literal and resolves TYPE when the expression executes. An
unknown TYPE or primitive mismatch fails, preserving the reader's strict
behavior for unsupported `#` tokens.

## M3 MOBLIST name association (`77dung.mud:184`)

Manual chapter 15 and pinned Confusion's `mdl_create_oblist` associate a
new named OBLIST with its name ATOM under indicator OBLIST, and the reverse
association with the OBLIST. A later `<GET FLAG OBLIST>` must retrieve the
OBLIST created by `<MOBLIST FLAG>`. Repeated MOBLIST of the same ATOM returns
that same OBLIST. These associations are session local.

## M3 empty UVECTOR UTYPE (`77dung.mud:213`)

The manual's UVECTOR rules and pinned Confusion's empty UVECTOR constructor
give an empty UVECTOR UTYPE LOSE. This applies to `UVECTOR` with zero
arguments, literal `![]`, and a MAPF final call to UVECTOR with no collected
elements. CHUTYPE can then change the empty object to ADJECTIVE in place.

## M3 SPNAME (`77dung.mud:2463`)

Manual chapter 15 defines SPNAME as the ATOM's printed-name STRING with
shared, immutable storage. The runtime returns an immutable STRING with
the same contents; this prevents PUT from changing the ATOM name. Racket
may copy when freezing a mutable host string, so physical sharing is not
claimed. PNAME continues to return a mutable copy. Wrong operand types fail.

## M3 GETTIMEDATE host clock bridge (`81tell-repl.mud:57`)

GETTIMEDATE is a Confusion host extension used by the source-defined
DSKDATE. It returns a FIX UVECTOR with seconds, minutes, hours, day,
month, full year, and microseconds. With no time argument or a FALSE first
argument, it reads the host wall clock; a FIX or two-FIX UVECTOR supplies
explicit Unix seconds and microseconds. A truthy second argument selects
UTC; otherwise host local time is used. Each call captures one timestamp
before decomposing it. Invalid types and arity fail. This is an explicit
host compatibility bridge; deterministic cross-engine RNG parity still
requires a seed strategy and is not implied by matching this API shape.
Since issue #135 the "now" read and the local-time zone come from the
session (next section).

## M3 session-owned host clock and time zone (issue #135; ADR-0052)

The original game reads the clock only through GETTIMEDATE: DSKDATE
(`81tell-repl.mud:57`) packs its result, SAVE-IT builds the "This version
created" line from it (`77rooms.mud:158`), and START seeds RANDOM with
`<CHTYPE <DSKDATE> FIX>` (`77rooms.mud:291`). The wall clock is therefore a
host dependency, owned by each session like its RANDOM state.

- `make-mdl-session` takes `#:clock` (default `real-mdl-clock`, the host wall
  clock, as before) and `#:time-zone` (`'local`, the default, or `'utc`).
  Both are stored in the session's atom space; no process-global parameter
  is involved, so two sessions in one process never share a clock or zone.
  Any other `#:clock` value (a number, a bare procedure) or zone symbol is
  rejected at construction.
- A clock is an `mdl-clock` value wrapping a host thunk that returns
  `(values epoch-seconds microseconds)`. `make-mdl-clock` wraps a thunk;
  `make-fixed-mdl-clock seconds #:micros m` (default 0) returns a constant
  instant: every read yields the same values and it never advances. This
  matches the reference capture shim (`scripts/reference/fixed_time.c`,
  PR #131), whose `gettimeofday` returns `MDL_FIXED_EPOCH` with
  `tv_usec = 0` on every call. Each read is validated: seconds an exact
  integer in the signed 36-bit FIX range, microseconds 0..999999; anything
  else is a strict error, never a fallback to real time.
- Only GETTIMEDATE with no time argument (or a FALSE first argument) reads
  the session clock, once per call. Explicit FIX or two-FIX UVECTOR
  timestamps keep their values exactly. Racket monotonic time, timeouts,
  thread scheduling and CPU time are untouched.
- Decomposition: a truthy second argument selects UTC, as before. Otherwise
  the session zone replaces "host local time" for both "now" and explicit
  timestamps, as `localtime_r` does under the reference process's `TZ`.
  With the default `'local` zone every result is identical to the previous
  behaviour. The process `TZ` is never changed. The supported zones are
  exactly `'local` and `'utc`; named or offset zones are not supported.
- The zone is independent of the clock: a fixed clock does not imply UTC.
  The reference golden (`fixed_epoch` 250776000, `tz` UTC) is reproduced
  with `#:clock (make-fixed-mdl-clock 250776000) #:time-zone 'utc`.
- Host-only observation: `mdl-session-random-snapshot` returns a detached
  copy of the session's RANDOM state, so a test can compute later outputs
  without consuming the game's sequence. No MDL primitive exposes it.

Tests: `tests/session_clock_test.rkt` (no upstream source) and
`tests/historical_clock_seed_test.rkt` (DSKDATE → START seed → RANDOM state).

## M3 default terminal CHANNEL bindings (startup)

Confusion initializes root ATOMs INCHAN and OUTCHAN with session-local
CHANNEL values and both LVAL and GVAL bindings. Each CHANNEL is a VECTOR
primitive with the documented channel slots. The default read and print
channels provide mode, terminal device name, empty file names, and basic
position and radix fields. Each Racket execution context creates analogous
values on construction (see "M3 execution contexts and session-owned CHANNEL
ports (review R1)" below); this is host environment state, not a change to
the historical game source. Terminal I/O operations are specified in the R1
section and in "M3 interactive terminal I/O and the host top-level loop".

## M3 PRINTSTRING terminal CHANNEL and count (`77rooms.mud:286`)

Manual chapter 11 allows `PRINTSTRING string [channel [count]]`. It writes
at most `count` visible characters, or the entire STRING when omitted.
The CHANNEL must be an output CHANNEL. This local runner maps its terminal
channel to the session's host-supplied output port (S13 part B: a session
without one refuses PRINTSTRING; only the ambient opt-in context follows the
current Racket output port; see "Host ports" below). The runtime retains the manual's
character-count return value; pinned Confusion returns the source STRING,
a recorded deviation already present for one-argument PRINTSTRING. Invalid
CHANNEL, count, or arity fails. Typed STRING values are accepted after
CHTYPE to STRING, as used by the original TELL definition.

## M3 CRLF and terminal newline (`77rooms.mud:286`)

Manual chapter 11 defines CRLF as emitting a terminal newline and returning
T. It accepts an optional output CHANNEL, like TERPRI, which instead returns
empty FALSE. The local runner writes a line feed to the CHANNEL's host output
port (S13 part B: strict error when the session has none) and requires a
PRINT-mode CHANNEL. This follows the existing documented
Unix terminal normalization; an actual carriage-return byte is not emitted.

## M3 execution contexts and session-owned CHANNEL ports (review R1)

Consolidated 2026-11-23 from `evidence/M3/review/R1.md` (PR #117), updated
for the S7 terminal input slice (ADR-0050).

**Manual and Confusion.** Manual §11.2.7 makes the default channel of the
output SUBRs the **local** value of OUTCHAN; INCHAN and OUTCHAN also have
global values, initially the same terminal CHANNELs. Pinned Confusion puts
both ATOMs on ROOT; its PRINT-family SUBRs read only the LVAL, so SETG does
not change the default and a PROG binding does
(`evidence/M3/review/r1-channel-reference.json`).

**Execution contexts.** An execution context is one globals table, one local
frame stack and one atom space. INCHAN and OUTCHAN are the seeded ROOT atoms
(`mdl-root-atom`), never resolved through `.OBLIST`; a user OUTCHAN that
shadows ROOT in a BLOCK is a different, unbound atom and does not redirect
the default. Each context starts with both ATOMs bound, as top-level LVAL and
GVAL, to one READ/PRINT pair of terminal CHANNELs owned by that context. The
bindings are created by `make-mdl-context` (also used by `make-mdl-session`),
for the process-wide default context when the runtime loads, and by the
idempotent `mdl-ensure-terminal-channels!` that begins every `#lang mdl`
module (it binds only an ATOM that has neither binding). GDECL, MANIFEST,
SETG, `ASSIGNED?` and `GASSIGNED?` treat them like any other binding.
`#lang mdl` modules share the ambient context's channels as they share all
globals; separate contexts never share channels. A context assembled by hand
without the constructor has no INCHAN/OUTCHAN (no hidden fallback).

**Host channels.** Each CHANNEL's backing VECTOR storage is registered in its
owning atom space with a host record: direction, an optional Racket port and,
for READ channels, the end-of-input flag (ADR-0050).
`make-mdl-session`/`make-mdl-context` accept `#:output-port`/`#:input-port`.
Output never falls back either (S13 part B): a session or context made
without `#:output-port` refuses every terminal write and flush with a strict
ADR-0050 error; only the process default context and `#lang mdl` modules
opt in to following `current-output-port` (see "Host ports"). Input never
falls back: READSTRING on a READ channel without
a host-supplied port is a strict error, so the runtime never reads the
process's own stdin (ADR-0050 "Host input port only"). CHTYPE may retype a
VECTOR as CHANNEL, as in Confusion, but only storage registered in the
current session acts as an open channel; REST of a CHANNEL is a VECTOR.

**PRINTSTRING, TERPRI and CRLF** take an optional channel defaulting to
`.OUTCHAN` (ROOT atom, LVAL only) and write only to that channel's port. The
channel is checked first, in Confusion's order: a non-CHANNEL fails ("attempt
to write to non-channel"), then a CHANNEL not registered in this session
("not open"), then a direction or mode slot (NTH 2) other than PRINT
("requires an output channel"); PRINTSTRING then checks its STRING and count.
PRINTSTRING returns the count written (recorded deviation: Confusion returns
the STRING); TERPRI returns `#FALSE ()`; CRLF returns `T`; both emit LF only.

**Deviations and unmodelled behaviour.** This runtime's GDECL checks an
existing value and its SETG refuses to change an assigned MANIFEST
(Confusion does neither). Binding OUTCHAN for the duration of output
(§11.2.7 "PRINT binds OUTCHAN") is not modelled. Output is flushed only
before each READSTRING and when the host loop exits, not after every SUBR.
Line-width and other slots (e.g. `<PUT ,OUTCHAN 13 80>`) are stored but not
interpreted (no PRINC/PRIN1 line breaking, ADR-0050). Tests:
`tests/channel_port_test.rkt`, `tests/channel_root_identity_test.rkt`,
`tests/printstring_channel_test.rkt`, `tests/terminal_channel_test.rkt`.

## M3 session-owned 36-bit RANDOM (`77rooms.mud:291`; issue #108)

[The MDL Programming Language, chapter 3.5](https://mdl-language.readthedocs.io/en/latest/03-built-in-functions/)
defines RANDOM as returning a FIX over the machine's full signed FIX range.
With no explicit seeds, each fresh interpreter follows the same sequence.
Two FIX arguments initialize a new sequence. The original START passes one
FIX derived from DSKDATE, so the pinned Confusion reference's one-seed
behavior is also required for progression. The generator state consists of
two 36-bit words per session; a one-seed call replaces only the first word,
and a two-seed call replaces both before advancing. Each call returns the
new first word interpreted as a signed 36-bit FIX. A 36-bit logical shift
of the second word and rotation of the first word's low bit determine the
next first word; the previous first word becomes the second. This recurrence
is expressed independently in Racket and checked against observed native
outputs, without copying GPLv3 Confusion source into the MIT-0 runtime.

The pinned observations in `evidence/M3/random-reference.json` cover the
default first three outputs, one/two-seed replay and order, zero seeds,
boundary seeds, and error text. Confusion accepts no, one, or two arguments;
wrong types and more than two arguments report errors. Its negative-seed
case returns `-68719476736`, outside signed 36-bit FIX, because its native
host arithmetic does not normalize that intermediate. The Racket runtime
normalizes every state transition to 36 bits and therefore intentionally
differs for that case. Tests require range safety, deterministic replay,
separate session state, valid seeding, strict errors, and original START
advancement to its next actual dependency.

## M3 BACK and terminal CHANNEL predecessor (`77rooms.mud:297`; issue #110)

[The MDL Programming Language, chapter 7.6.2](https://mdl-language.readthedocs.io/en/latest/07-structured-objects/)
defines BACK on VECTOR, UVECTOR and STRING arrays as the inverse of REST:
it exposes one or more previously removed elements from the same storage.
The default offset is one. A nonpositive offset, a value that is not an
array, or an offset beyond the view's start fails. BACK shares the backing
storage and UVECTOR UTYPE header with the input view; mutation through
either view remains visible to the other. The pinned native probes in
`evidence/M3/back-reference.json` confirm vector, uvector and string
content, zero-offset and beyond-start errors, and the host terminal
CHANNEL's one preceding slot. Confusion retains the argument's TYPE on BACK
— CHANNEL for INCHAN, and any NEWTYPE of VECTOR, UVECTOR or STRING — despite
the manual's general statement that BACK changes to the array PRIMTYPE.
*Amended 2026-11-23 (maintainer decision; ADR-0058 amendment):* BACK keeps
the argument's exact TYPE (by TYPE atom, never PNAME) for every array-backed
value, as TOP does; REST drops it. Previously only CHANNEL was kept. The
manual discrepancy is acknowledged and the reference is followed. Its preceding slot reads as FIX 0 in the pinned bare
interpreter; the original source's PUT on that FIX uses the existing
association dispatch. This host representation is not a puzzle-rule change.

Tests must first fail on unassigned BACK, then assert shared view mutation,
strict bounds and types, terminal CHANNEL metadata, and the next actual
original START failure. TOP and RESET are separate source dependencies.

## M3 startup: UNPARSE, MEMQ on STRING and SUBSTRUC (issue #112 S1–S3)

Consolidated 2026-11-23 from `evidence/M3/S1-UNPARSE.md` (PR #125),
`evidence/M3/S1-MEMQ-STRING.md` (PR #128) and `evidence/M3/S3-SUBSTRUC.md`
(PR #130); branch-only, not on `main`.

**UNPARSE** (manual 7.6.6.4) `<UNPARSE any [radix]>` returns a fresh mutable
STRING with the characters PRINT would output, without line-width breaks.
Exact against pinned Confusion for: FIX in decimal (including the 36-bit
extremes); STRING, quoted with `\"` and `\\`; CHARACTER as `!\c`; FALSE;
LIST (recursive); and a plain ATOM whose PNAME is non-empty ASCII
`[A-Za-z0-9-]`, does not parse as a number, and is found as the same atom
on the current OBLIST path (LVAL of ROOT OBLIST, R3/R4). Strict errors: a
radix other than 10 (Confusion ignores the radix; deviation, not copied);
ATOMs needing escapes or a trailer; control characters in STRING/CHARACTER
(Confusion prints `^X`); FLOAT, VECTOR, UVECTOR, WORD, FORM and other types.
Source use: 77rooms.mud:164 only (a day-of-month FIX). Tests:
`tests/unparse_test.rkt`.

**MEMQ on STRING** (manual ch. 13; amends the M2 MEMQ section above). With a
CHARACTER needle, MEMQ compares each element by `==?` (character code). On a
hit at position i it returns the STRING REST'd to i, a view sharing storage
with the original, so BACK and PUT alias it; on a miss it returns `#FALSE
()`. A non-CHARACTER needle (FIX, STRING, ...) can never be `==?` to a
CHARACTER element and returns `#FALSE ()`, as pinned Confusion does; the
manual does not address the type mismatch. MEMBER is not implemented.
Evidence: `evidence/M3/memq-string-reference.json`; tests
`tests/memq_string_test.rkt`.

**SUBSTRUC** (manual 7.1.7) `<SUBSTRUC from [rest] [amount] [to]>` copies
elements. `rest` (FIX, default 0) must be in [0, length]; `amount` (FIX,
default the remainder) in [0, length − rest]. Without `to` it returns a fresh
structure of `from`'s PRIMTYPE that never shares storage with `from`. With
`to` (which must have the primitive TYPE itself, not a NEWTYPE; Confusion
"Last arg to SUBSTRUC must be same type as primtype"), the elements are
written to positions [0, amount) and `to` is returned; the destination length
is checked before any write, a UVECTOR `to` must have the source's element
type, and a STRING copy snapshots all source characters first, so overlapping
views copy atomically. Supported: STRING, VECTOR, UVECTOR, LIST without `to`.
Strict errors: LIST with `to`, BYTES, TUPLE, wrong argument TYPEs and the
Confusion-confirmed range errors (`SUBSTRUC rest cannot be negative`, `rest
too large`, `amount cannot be negative`, `amount too big for source`).
Recorded deviation: `<SUBSTRUC "abc" 0 2 [0 0 0]>` reports the type mismatch
first where Confusion reports "destination too short"; the game never mixes
PRIMTYPEs. Evidence: `evidence/M3/substruc-reference.json`; tests
`tests/substruc_test.rkt`.

## M3 startup: ON (IPC) and SAVE

[Manual chapter 21.6](https://mdl-language.readthedocs.io/en/latest/21-interrupts/)
defines `<ON name applicable priority>` as `<HANDLER <EVENT name priority>
applicable>`: it finds or creates the IHEADER, associates and enables it,
puts a new HANDLER at the front of its action list and returns that HANDLER;
`OFF` removes it. The runtime validates arity (exactly three; the optional
process/which arguments are unsupported), a STRING name, a FUNCTION/SUBR
applicable and a positive FIX priority before registering anything. By
maintainer decision (2026-11-22, issue #112, ADR-0047) the predefined
`"IPC"` may be registered through ON or EVENT, but the session has no
inter-process message source: emitting or delivering an IPC occurrence is a
strict error. By maintainer decision (2026-11-23, ADR-0048) `"BLOCKED"`
receives the same treatment: registration through ON/EVENT/HANDLER and OFF
work, but the session has no blocked-input source, so emitting or delivering
a BLOCKED occurrence is a strict error naming ADR-0048. Every other refused
predefined name (CHAR, READ, WRITE, UNBLOCKED, CLOCK, ...) stays refused.

**SAVE (ADR-0048, supersedes ADR-0047 part 2).** Manual 11.6.1 defines
`<SAVE file-spec:string gc?:false-or-any>` and the multi-name form `<SAVE
name1 name2 device dir gc?>` (all STRINGs optional, defaulting to "MUDDLE",
"SAVE", "DSK" and the SNM value); a FALSE `gc?` "causes no garbage
collection to occur before SAVEing", and SAVE returns `"SAVED"`. Manual
11.6.2 defines RESTORE. The multi-name and zero-argument forms are not
needed by the game and are strict errors here. Arguments are evaluated as for
any SUBR. The runtime accepts exactly one STRING file-spec (native or REST
view), optionally followed by a FALSE `gc?` (an explicit request not to
collect, which is what this SAVE always does). `<SAVE>`, a non-STRING
file-spec, a non-FALSE `gc?` and more than two arguments are strict errors,
raised before anything is recorded. A valid call:

- returns a **fresh** mutable STRING `"SAVED"` (`<==? <SAVE "X"> <SAVE "X">>`
  is false, `=?` is true; mutating a result does not affect later results);
- writes, opens or deletes no file and creates no channel;
- performs no garbage collection and has no interrupt side effect (INT-LEVEL
  unchanged; nothing emitted, queued or drained);
- appends a record `(sequence file-spec int-level)` to the current session:
  a 1-based per-session counter, an immutable snapshot of the file-spec's
  visible characters (later mutation of the argument does not change it),
  and the INT-LEVEL at the call. Host code reads the records, oldest first,
  with `mdl-save-records` (core) or `mdl-session-save-records` (loader);
  no MDL primitive exposes them.

`RESTORE` stays a strict, intentional unsupported SUBR: after evaluating its
arguments it raises `RESTORE: restoring a saved image is not supported
(maintainer decision 2026-11-23; ADR-0048)` and never touches files.

**Reference behavior and deviations.** Pinned Confusion stubs ON, EVENT and
HANDLER (`T`, TYPE ATOM, even for invalid arguments; `<ON "BLOCKED" ,TYPE
100>` is `T`). Its SAVE writes an image file, ignores `gc?`, returns
`"SAVED"`, returns `#FALSE ()` when the file cannot be opened, writes
`MUDDLE.SAVE` for `<SAVE>` and crashes (SIGSEGV) on `<SAVE 1>`; see
`evidence/M3/on-save-reference.json` and
`evidence/M3/S5-SAVE-FRONTIER.md`. On RESTORE Confusion swaps the heap and
re-enters LISTEN applying `,REP`, so the original SAVE never returns again;
the manual instead says SAVE returns a second time with `"RESTORED"`. The
runtime models neither; the disagreement is recorded for a future RESTORE
slice. The manual's GC on SAVE is not performed.

**Faithful SAVE-IT path.** The patched 77rooms.mud SAVE-IT has one COND
clause, `(<=? <SAVE .FN> "SAVED"> <INT-LEVEL 0> ...)`, so a session-record
SAVE continues in the same session: SAVE is recorded with file-spec
`"<MDL>MADADV.SAVE"` and INT-LEVEL 100000, then `<INT-LEVEL 0>` at
77rooms.mud:26 lowers the level. Lowering the level is an ordinary MDL safe
point: any GC or DIVERT-AGC occurrence queued while the level was 100000 is
delivered there (Confusion has no such occurrences). This is not
suppressed. On the observed faithful path no occurrence was pending there
(DIVERT-CNT stayed 0); the run continues through START and stops in CONTIN
at 77rooms.mud:301 on the unassigned GVAL of REP. See
`evidence/M3/S5-SAVE-RECORD.md`.

## M3 startup: inert REP and the host top-level loop (ADR-0049)

**Reference.** In pinned Confusion (`evidence/M3/S6-rep-reference.json`,
binary `6df359f6…`, upstream `bdcd4a67`) a fresh session has
`<GASSIGNED? REP>` = T, `<TYPE ,REP>` = SUBR, REP on ROOT, `<TYPE? ,REP
SUBR FSUBR>` = SUBR, `<PRIMTYPE ,REP>` = WORD; after `<SETG SAVEREP ,REP>`
(which prints `#SUBR *…227*`) `<TYPE ,SAVEREP>` = SUBR and `<==? ,REP
,SAVEREP>` = T. `<REP>` and `<APPLY ,REP>` each perform one real
read-eval-print step on the terminal and return the value. Confusion's
LISTEN loop re-reads the GVAL of REP on every pass: after `<SETG REP ,F>`
the next pass applies F (the following `<+ 5 6>` is never read).

**REP value (implemented).** Every session's GVAL of ROOT `REP` is one
predefined SUBR value until the program SETGs or GUNASSIGNs REP:

- `<GASSIGNED? REP>` → T; `<TYPE ,REP>` → SUBR (the ROOT atom);
  `<TYPE? ,REP SUBR FSUBR>` → SUBR; it matches the `APPLICABLE` Pattern;
- `<SETG SAVEREP ,REP>` stores the same object: `<==? ,REP ,SAVEREP>` → T;
- SETG of REP in one session never affects another session; each fresh
  session starts with the default REP.
- **Applying it is a strict error** (decision, not reference): `<REP ...>`,
  `<APPLY ,REP ...>`, a HANDLER/ON action that is the default REP, a host
  `mdl-apply`, and any path that restores it into REP and applies it. Arguments
  are evaluated first as for any SUBR; then the call raises
  `REP: the default REP SUBR is inert; this runtime never provides a raw MDL
  read-eval-print loop (maintainer decision 2026-11-23; ADR-0049)`.
  It never reads a channel, evaluates input, prints or returns a value.
- Not supported (strict errors, unchanged): `<PRIMTYPE ,REP>`,
  `<TYPEPRIM SUBR>` (Confusion: WORD), CHTYPE of REP, DECL Patterns naming
  SUBR or FSUBR, UNPARSE/PRINT of REP. Other built-in SUBRs remain host
  procedures whose TYPE is still an unsupported-type error.

**Host top-level loop (specified in S6; implemented in S7, ADR-0050).** The loop
replaces Confusion's LISTEN for a game session. Contract for the slice that
implements it (after RESET, PRINC and READSTRING exist):

1. *Start.* It starts only after the session's entry form returns normally
   (for `run.mud`, after `<SAVE-IT>` returns from the faithful path, at which
   point CONTIN has set REP to `,RDCOM`). If the entry form raises, the loop
   never starts and the failure is reported.
2. *Each pass.* It re-reads the session's current GVAL of ROOT `REP` (never a
   cached value) and applies it with no arguments, exactly like an MDL
   `<APPLY ,REP>`. An unassigned or non-applicable GVAL is a strict error. The
   default REP SUBR is never applied by the loop: meeting it is the ADR-0049
   strict error. The pass's value is discarded; the loop itself reads and
   prints nothing. (Amended by ADR-0050, maintainer decision D1: before the
   first pass the loop prints the entry form's value once with PRIN1 and
   TERPRI; see "M3 interactive terminal I/O and the host top-level loop".)
3. *End.* The loop ends normally only when the applied code QUITs (the game's
   QUIT/FINISH path). Exhausted terminal input (for example READSTRING at EOF,
   which Confusion reports as `Unexpected EOF`) is a strict error, never a
   silent success. Any other error raised during a pass propagates; there is
   no LISTEN error level, retry or recovery. A host test may bound the number
   of passes; exceeding the bound is a strict error.
4. *Isolation.* The loop runs locally in the host process against the
   session's own channels. It is never exposed to a network server or web
   client, and it provides no MDL evaluator: whatever input it sees reaches
   MDL only through the program's own READSTRING/RDCOM code.

**Source paths that restore SAVEREP.** Only 77rooms.mud:222, in the ERROR
handler HANDLE: `<AND <GASSIGNED? SAVEREP> <SETG REP ,SAVEREP>>`, taken when
XUNM is unassigned or in WINNERS and `<PC>` (T) holds. On that path the next
loop pass meets the default REP and fails loudly (ADR-0049), where Confusion
drops into its REPL. BLO (77act1.mud:3) acts only while REP is a SUBR or FSUBR;
after CONTIN REP is RDCOM (a FUNCTION), and BLOCKED never fires (ADR-0048).

## M3 interactive terminal I/O and the host top-level loop (ADR-0050)

Specification written before implementation. References: manual chapter 11
(§11.1.2.3 PRINC/PRIN1, §11.2.8 channel slots, §11.3 end of file, §11.4.1.2
READSTRING, §11.7.7 RESET, §11.8 terminals) and 16.1 (LISTEN); pinned
Confusion `6df359f6…` probes in `evidence/M3/S7-frontier/`
(`primitives-reference.json`, `extra2-reference.json`, `boot-reference.json`).
Game uses: CONTIN `<RESET ,INCHAN>` (77rooms.mud:303), YES/NO (77defs.mud:433),
RDCOM `<PRINC ">">` and `<READSTRING .INBUF ,INCHAN .STR>` with READER-STRING
= ESC CR LF (77rooms.mud:598-616), PRINC `!\.` (77rooms.mud:1398), PRINC of a
FIX (78melee.mud:524), SCORE's PRIN1 of FIX (77rooms.mud:675-680).

**Host ports (ADR-0050 "Host input port only" and, from 2026-11-23, S13 part
B "Explicit output port").** A terminal CHANNEL reads or writes only the
Racket port its host supplied. A session or context made without
`#:input-port` refuses READSTRING; one made without `#:output-port` refuses
every operation that resolves its PRINT CHANNEL: PRINC, PRIN1, PRINTSTRING,
TERPRI, CRLF, the pre-read flush of READSTRING, and the host loop's entry
print and final flush. The message is `<who>: this session's PRINT CHANNEL
has no host-supplied output port; the runtime never falls back to the host's
current-output-port (ADR-0050)`, and nothing reaches a parameterized
`current-output-port`. Explicit opt-in, never a default:
`mdl-ensure-terminal-channels! #:follow-current-output-port? #t` creates a
PRINT CHANNEL that writes to the host's `current-output-port` at each
operation. It is used only by the process-wide default context and by
`#lang mdl` modules (which run in it); `make-mdl-session` and
`make-mdl-context` do not accept it. Tests: `tests/session_output_port_test.rkt`.

**Terminal CHANNEL host state.** Each terminal CHANNEL's host record (keyed
by its backing storage, ADR-0046/#117) gains one mutable end-of-input flag,
initially clear. It is host state only: no CHANNEL slot shows it (deviation:
Confusion keeps it in STATUS, slot 11). "Open CHANNEL" below means: TYPE
CHANNEL (the ROOT atom), registered in the current session, and the view's
mode slot (element 2) equal to the host direction (`"READ"`/`"PRINT"`), so a
forged, foreign or shifted (BACK/REST) view is refused.

**RESET** `<RESET channel>`.
- Exactly one argument; zero or more than one is a strict error
  (Confusion: `Not enough args to RESET` / `Too many args to RESET`).
- A non-CHANNEL is a strict error (Confusion: `Argument to RESET must be of
  type CHANNEL`); a CHANNEL that is not open in this session is refused.
- READ terminal channel: clears the end-of-input flag. Unread input queued on
  the port is **not** discarded (Confusion keeps its stdio buffer too). There
  is no lookahead to drop: READSTRING never peeks (Confusion drops one
  lookahead character, which only LISTEN's reader sets).
- PRINT terminal channel: no host state to reset.
- Returns the same object (`==?` the argument). No slot changes, the BACK
  predecessor slot and its associations (CONTIN's `<PUT <1 <BACK ,INCHAN>> 6
  …>`) are untouched. Deviation: Confusion sets STATUS to 0 and rewrites
  DEVN; the manual's "like OPENing afresh" re-acquisition is not modelled.

**PRINC** `<PRINC object [channel]>` and **PRIN1** `<PRIN1 object [channel]>`.
- One or two arguments, otherwise a strict error. The channel defaults to
  the LVAL of OUTCHAN (as PRINTSTRING); it must be an open PRINT CHANNEL
  (Confusion: `Channel for PRINC must be output channel`, `Attempt to write
  to non-channel`).
- Both return the object itself.
- PRINC writes: a STRING (native or REST view) as its characters, without
  quotes; a CHARACTER as the bare character; a FIX in decimal (Confusion
  `<PRINC 42>` → `42`). CR (13) and LF (10) are written raw. Any other
  control character (0-31, 127) is a strict error (Confusion prints `^X`
  notation, e.g. ESC as `^[`; not modelled).
- PRIN1 writes: a FIX in decimal; an ATOM whose PNAME is empty and which is
  found by its PNAME on the current OBLIST path prints nothing (Confusion
  `rep-value-printing-null-atom`: the game's `,NULL`); any other ATOM follows
  the existing UNPARSE ATOM rules (safe PNAME characters, reachable, no
  trailer), else a strict error.
- Every other TYPE (ATOM for PRINC, STRING/CHARACTER/LIST/FALSE for PRIN1,
  typed values, …) is a strict error.
- **No line breaking.** The manual and Confusion insert a newline when the
  column is positive and column + length exceeds the CHANNEL line width
  (slot 13, 0 = unlimited). This runtime ignores slot 13 and inserts
  nothing; RDCOM sets the width to 1000 (`<PUT .OUTCHAN 13 1000>`), which
  makes breaking unreachable on the tested path. Tests assert the absence.
  HANDLE sets width 80; that path is out of scope.

**READSTRING** `<READSTRING buffer channel [stop]>`.
- Exactly two or three arguments. Fewer is a strict error (the manual's
  default `.INCHAN` channel is not modelled); a fourth argument (EOF routine)
  is a strict unsupported error; more is a strict error.
- buffer: a mutable STRING or REST view of one; anything else (including an
  immutable literal or a CHTYPE'd STRING) is a strict error (Confusion:
  `UVECTOR for readstring must be of type STRING`).
- channel: an open READ CHANNEL (Confusion: `Channel for READSTRING must be
  input channel`).
- stop: a STRING (native or view) of stop characters. A FIX stop (count
  limit) is a strict unsupported error; any other TYPE is a strict error.
- Arguments are validated first. Then every open terminal output port of the
  session is flushed (the prompt is visible before a blocking read). Then, if
  the channel's end-of-input flag is set, `exn:fail:mdl-input-exhausted` is
  raised (see below). Otherwise characters are read one at a time from the
  channel's port until (a) the buffer view is full, (b) a stop character is
  read (consumed, not stored), or (c) end of input, which sets the flag.
  Characters are stored from position 1 of the given view; the rest of the
  buffer is unchanged (stale characters stay, as YES/NO relies on). Returns
  the FIX count stored. Case is preserved, nothing is echoed or written.
- Overflow: when the buffer fills, the rest of the line stays unread and the
  next READSTRING continues from it (Confusion `readstring-overflow`).
- A character with code above 127 in the input is a strict error.
- *(Superseded 2026-11-23, S13 part A: this bullet said "a `!` in the input
  is a strict error".)* **`!` escape (maintainer decision 2026-11-23: follow
  pinned Confusion; evidence `evidence/M3/READSTRING-BANG-REFERENCE.md`,
  `readstring-bang-probe.json`).** The manual is silent on `!` in terminal
  input; this is Confusion's stdio behaviour, adopted by decision, not a
  manual-backed fact. Reading proceeds one *unit* at a time while the
  buffer view has room:
  1. A unit is one character `c`, or `!` followed by one character `c` (the
     escape pair). Every character can be escaped, including `!` itself,
     control characters and `\` (`\` is never an escape).
  2. An escape pair yields `c`: the `!` is never stored or counted, and the
     pair uses one buffer slot (`Ab!cD` → 4 `"AbcD"`; `!!` → 1 `"!"`;
     `a!!b` → 3 `"a!b"`; `!a!b!c` → 3 `"abc"`; `a!<TAB>b` stores TAB).
  3. The stop test uses `c` whether or not it was escaped: an escaped CR, LF
     or ESC still ends the read, is consumed and is not stored (`ab!<LF>XY<LF>`
     → 2 `"ab"`, then 2 `"XY"`; `ab!<CR><LF>cd<LF>` → 2, 0, 2).
  4. `!` immediately followed by end of input is stored as a literal `!` and
     counted; the read returns there and sets the end-of-input flag, so the
     next READSTRING raises the D3 exhausted error (`ab!` → 3 `"ab!"`).
     Unprobed (S13 review): whether that trailing `!` would instead stop the
     read when the stop STRING itself contains `!`; the game's READER-STRING
     (ESC CR LF) never does, so the runtime stores it as above.
  5. A unit begins only when the buffer has room; when the buffer is full the
     rest stays unread, and escape pairing resumes on the next READSTRING
     (3 slots, `ab!cd<LF>` → 3 `"abc"`, then 1 `"d"`; 2 slots → `"ab"`, then
     `"cd"`). Because a pair always fits in the one slot that is left, a `!`
     is never the last character read before the buffer fills.
  6. The count is the number of characters stored.
  The character after `!` passes the same check as any other input: code
  above 127 is a strict error (`a!é` is refused). Known deviation, unchanged:
  Confusion stores bytes above 127 raw (`ASCII` gives negative codes) with or
  without a `!`. Not modelled: a FIX stop (strict here, so `bang-fix-stop`
  cannot be exercised).
- CR is a stop character in READER-STRING, so CRLF input yields an extra empty
  read (Confusion `boot-six-crlf`); the host therefore feeds LF-terminated
  lines.

**End of input (maintainer decision D3, "Mirror, then strict").** The first
read that meets end of input behaves as Confusion's: it returns the count
read so far (0 for an empty read, so RDCOM prints `Beg pardon?` and a new
`>`) and sets the flag. A READSTRING entered with the flag set raises
`exn:fail:mdl-input-exhausted` with the message `READSTRING: input exhausted:
the session input ended and the mirrored end-of-input read was already
returned (maintainer decision D3; ADR-0050)`. This is a host-level Racket
exception, **not** an MDL ERROR: no MDL ERROR handler runs (the game's HANDLE
would otherwise run FINISH/RECORD/QUIT, which Confusion never shows), and the
host loop reports it as a failure. RESET clears the flag (Confusion: after
RESET one more 0-count read, then the error). Deviation: Confusion raises
`Error: Unexpected EOF` and closes the channel; the manual calls ERROR.

**Host top-level loop** (`mdl-session-run-interactive session entry
#:max-passes #:on-event`, `mdl/loader.rkt`). Implements ADR-0049 part 3 with
the maintainer's D1 amendment.
1. The session must have been made with explicit `#:input-port` and
   `#:output-port`; otherwise the call fails before running anything (the
   loop never reads the process's own standard input by accident).
2. *Entry.* Apply the GVAL named `entry` (for `run.mud`: `SAVE-IT`, after
   the caller's `mdl-session-load!` of `77loadall.mud`) with no arguments.
   If it raises, the failure propagates and the loop never starts.
3. *Entry value print (D1).* PRIN1 the entry value to the LVAL of OUTCHAN,
   then TERPRI. For SAVE-IT this is `,NULL` (empty PNAME), i.e. one empty
   line, as LISTEN's REP prints it in Confusion. The banner
   `LISTENING-AT-LEVEL 1 PROCESS 1` and the `"DONE"` line (REP printing
   FLOAD's value) are never printed; the comparator strips them from the
   Confusion golden.
4. *Each pass.* Re-read the session's GVAL of ROOT REP (never cached);
   unassigned or non-applicable is a strict error; the default REP is the
   ADR-0049 strict error. Apply it with no arguments; discard the value.
   RDCOM never returns on the tested path, so the loop makes one pass.
   `#:max-passes` bounds the passes (exceeding it is a strict error).
5. *End.* Only by an exception in this slice: input exhausted, a strict
   error, or any other failure. QUIT is not implemented (out of scope). The
   output port is flushed on every exit. *Amended by S11 (ADR-0054):* a QUIT
   now ends the loop with a returned session outcome; see "M3 session end".
6. *Isolation.* Local host API only; no network or web entry point; input
   reaches MDL only through the program's own READSTRING.

**Transcript comparison (D2).** The approved golden is PTY-rendered. A
Racket transcript is compared as `canonical_text(ONLCR(raw))`: every LF in
the raw output becomes CR LF (termios ONLCR), then CR LF → LF and CR → LF
(`scripts/boot_reference.py` `canonical_text`). The golden's
`LISTENING-AT-LEVEL 1 PROCESS 1` and `"DONE"` lines are removed (D1), and the
`This version created <Month> <day>.` line is normalised in both texts,
because DSKDATE reads the host clock until issue #135 fixes it. Full
SMOKE_PARITY needs that fixed clock.

## M3 reader: backslash escapes in atom names (issue #119)

**Contract** (MDL manual chapter 15, confirmed by pinned Confusion binary
`6df359f6…`, probed 2026-11-22):

- `\X` within an atom PNAME quotes the next character: the backslash is
  **dropped** and the following character `X` is retained verbatim in the PNAME.
- The `!-` OBLIST-trailer split (`mdl-atom`) operates on the processed
  (backslash-stripped) string, so `DEAD\!!-WORDS` → pname `"DEAD!"`, oblist
  `WORDS` (not pname `"DEAD\!"` on oblist `WORDS`).
- A token that began with a `\`-prefixed character is classified as ATOM
  regardless of its PNAME text.  `\5` has PNAME `"5"` but TYPE ATOM, not FIX.
  `\-5` → ATOM, `\1.5` → ATOM, `\*7*` → ATOM, `\#FOO` → ATOM.
  Confusion confirms all five via `<TYPE \5>` → ATOM, etc.
- `\X` as a PROG/REPEAT label is legal: `\1ST` has PNAME `"1ST"` and is a
  valid label.

**Implementation** (`mdl/parser.rkt`, `mdl/compiler.rkt`):

The parser's `read-atom!` returns `(values pname escaped?)`.  When `escaped?`
is `#t` the caller emits an `'escaped-atom` node instead of `'atom`.  The
compiler's `mdl-constant/plain` returns `(atom-ref val)` immediately for
`'escaped-atom` nodes, skipping all numeric and `#` classification.
`atom-node-constant-token?` accepts a node (not a string) and returns `#f`
for `'escaped-atom`, so `prog-label-name` treats such nodes as valid labels.
All other compiler predicates that previously checked `is-kind? n 'atom` now
use the `is-atom-node?` helper which accepts both kinds.

**Tests**: `tests/escaped_atom_test.rkt` — covers PNAME stripping, `!-`
trailer splitting, intern identity, and the five escaped-numeric/`#` cases.

## M3 reader: leading-dot FLOAT vs LVAL (issue #124)

MDL allows FLOAT literals that begin with a decimal point.  The reader
identifies a leading-dot FLOAT by this rule:

1. Consume the `.`.
2. Read the atom-name characters until the next delimiter → `name`.
3. If the raw character right after the first `.` is a literal (unescaped)
   `.`, raise a strict reader error (`..X` is not supported; Confusion
   evaluates `..5` as LVAL of FLOAT 0.5 → type mismatch). `.\.5` is the
   LVAL of ATOM ".5" (the second `.` is escaped).
4. If `name` contained no `\` escape (#119) and matches `^[0-9]+([Ee][+-]?[0-9]+)?$` (all float-numeral chars,
   no embedded decimal), the token is a FLOAT: value = `"." + name`.
   - `.5` → FLOAT 0.5; `.05` → FLOAT 0.05; `.5E1` unsupported (see below).
5. Otherwise the token is an LVAL reference to atom `name`.
   - `.\5` → LVAL "5" (escaped, never numeric; #119);
   - `.A` → LVAL "A"; `.5A` → LVAL "5A"; `.5.` → LVAL "5."; `.5.5` → LVAL "5.5".

The `(\.[0-9]*)?` group is intentionally absent from step 4: `.5.` and `.5.5`
contain an embedded decimal in the suffix and are NOT FLOATs — Confusion yields
UNBOUND-VARIABLE for LVAL "5." and "5.5" respectively.

`-.5` is an ATOM named `"-.5"`, not a negative FLOAT.  Confusion confirms: the
`-` prefix only introduces a signed number when followed immediately by a digit.

**Deviation: `.5E1`** — Confusion returns FLOAT 5.0.  This reader produces an
`unsupported numeric token` error, consistent with the existing strict-failure
policy for scientific notation (`1E2` is also unsupported).  `.5E1` does not
appear in the pinned 1977 game source.

**Deviation: `. 5` (space between `.` and digit)** — Confusion evaluates this
as LVAL of the FIX 5 (a type mismatch when evaluated).  This reader raises
"empty local reference", a strict reader error.  Not present in the game source.

Evidence: `docs/evidence/M3/I124-LEADING-DOT.md`, Confusion probe I124.

## M3 UNWIND cleanup only on MDL transfers (issue #139; ADR-0051, supersedes ADR-0018's error rule)

`<UNWIND stdexpr errexpr>` evaluates stdexpr and returns its value. The
cleanup errexpr runs, in the UNWIND's environment and with its value
ignored, **only** when an MDL transfer of control leaves stdexpr through
the UNWIND frame. The transfer then completes. In this runtime the MDL
transfers are the escape continuations:

- `RETURN` and `AGAIN`, bare or to an explicit PROG/REPEAT/function
  ACTIVATION below the UNWIND;
- `GO` to a label of a PROG/REPEAT below the UNWIND;
- `MAPLEAVE`, `MAPRET` and `MAPSTOP` from a MAPF/MAPR loop function whose
  body contains the UNWIND;
- the same transfers performed by an ERROR or other interrupt handler.
  `<ERRET value frame>` returns to the ERROR frame, which is above every
  UNWIND that was active when ERROR was called, so it crosses none.

A raised error never runs the cleanup. This covers an MDL `ERROR` that no
handler resolves (it reaches the host as a Racket exception), host strict
errors for unsupported constructs and unassigned operators, nested-load
failures, and any other Racket `raise`, including a non-`exn` value.
The original exception propagates unchanged. A cleanup therefore cannot
mask the error or turn it into a normal value by escaping, for example
`<PROG P () <UNWIND <OPEN-NOT-DEFINED "X"> <RETURN 7 .P>>>` raises the
unassigned-operator error and never returns 7. A future `QUIT` must be
implemented as a raised signal that is not an `exn:fail`, so it skips
cleanups by the same rule. Host bookkeeping still unwinds on a raise:
activation liveness, local bindings, OBLIST paths and the interrupt level
are restored by Racket `dynamic-wind`/`parameterize`. Only the MDL
errexpr is skipped.

Manual basis
([chapter 16](https://mdl-language.readthedocs.io/en/latest/16-errors-frames-etc/),
[chapter 23](https://mdl-language.readthedocs.io/en/latest/23-mdl-as-a-system-process/)):

- §16.2: ERROR is a call that behaves like LISTEN on top of the intact
  stack. Entering the error level unwinds nothing.
- §16.4/§16.5: only ERRET and RETRY strip the control stack.
- §16.6: the cleanup runs when a non-local return crosses the UNWIND,
  for example the FLOAD channel close "if the user attempts to ERRET".
- §23.3: QUIT stops MDL. Nothing is unwound.

Pinned Confusion agrees (`docs/evidence/M3/I139-UNWIND.md`): entering an
error level, stdin EOF at the error level, QUIT and C-level internal errors
run no cleanup. ERRET with no arguments, ERRET to a frame below, and a
RETURN typed at the error level to an activation below all run it.

A runtime-level error that is not resolved is terminal: this runtime has no
interactive error level. That matches the outcome of a Confusion error
level that is never left by ERRET or RETRY. The error-level transfers that
need an operator at a REPL cannot be modelled. These are ERRET with no
arguments, ERRET to a frame below the UNWIND, RETRY, and a RETURN typed
at level 2. They are documented deviations, never guessed.

An error raised inside a cleanup while an MDL transfer is in progress
propagates unchanged and is terminal. The pending transfer is abandoned,
and no outer UNWIND cleanup on the abandoned path runs. Confusion instead
suspends the transfer at a new error level and completes it after an ERRET
from that level. When an ERROR handler resolves the cleanup's ERROR with
`<ERRET value frame>`, the cleanup continues and the original transfer
completes, as in Confusion's `error-inside-cleanup-erret-value` probe.

Tests (`tests/unwind_raise_test.rkt`, `tests/control_test.rkt`,
`tests/mapf_test.rkt`, core invariants in `mdl/runtime/core.rkt`) must
show the following. Strict and MDL errors inside the body, including the
FINISH-shaped case whose cleanup would call an unassigned QUIT, surface
the body's original error with the cleanup counter at 0. A cleanup that
would RETURN past the error never swallows it. RETURN, AGAIN, GO,
MAPLEAVE, MAPRET and MAPSTOP run the cleanup exactly once. Nested UNWINDs
run inner then outer on a transfer and neither on a raise. An error in a
cleanup during a transfer surfaces unchanged and skips outer cleanups. A
handler-resolved error inside the body does not disable a later
transfer's cleanup. A raised non-`exn` value skips cleanups.

## M3 primitive: `MEMBER` (S9; issue #139 frontier, HANDLE)

Authority: [MDL manual §8.2.2](https://mdl-language.readthedocs.io/en/latest/08-truth/)
and the pinned Confusion observations in `docs/evidence/M3/MEMBER-REFERENCE.md`
(`member-probe.json`, 58 cases). Implementation record:
`docs/evidence/M3/S9-MEMBER.md`.

`<MEMBER object structured>` takes exactly two arguments. It is not an alias
of `MEMQ`: the comparison is structural `=?` (the runtime's `mdl-equal?`,
including its cycle boundary from issue #23), never `==?`, and the result is
never a host Boolean.

Supported subset:

- **Element search.** The haystack is PRIMTYPE LIST (LIST, FORM, any other
  LIST-primtype TYPE, and a FALSE's payload), VECTOR or UVECTOR, native or a
  REST view, CHTYPE'd/NEWTYPE'd included. Elements are scanned first to last
  and compared with `=?`; the first hit wins. The result is the shared
  `<REST structured i>` view (`mdl-rest`): a PUT through it is visible in the
  haystack, it is `==?` to `<REST s i>`, and at offset 0 it is `==?` to the
  haystack itself. Its TYPE is the haystack's PRIMTYPE type (FORM gives LIST,
  a NEWTYPE of VECTOR gives VECTOR, `#FALSE (1 2)` gives LIST). A miss
  returns `#FALSE ()`. A STRING needle against a LIST or VECTOR is an element
  search (`<MEMBER "a" ["abc"]>` misses); `<MEMBER "" ,LEXV>` (77rooms.mud
  COMMAND) finds the first empty STRING view.
- **Substring search.** When both arguments are PRIMTYPE STRING (native
  STRING, REST view, typed STRING), MEMBER returns the shared STRING tail view
  at the first case-sensitive occurrence of the needle's characters, offset
  relative to the (possibly REST'd) haystack, TYPE STRING. A needle longer than
  the haystack, or an empty haystack, returns `#FALSE ()`.
- **Element search in a STRING.** Any other needle against a STRING haystack
  is an element search with `=?` against each CHARACTER element: a CHARACTER
  finds its position (same result as MEMQ); FIX, ATOM, LIST, etc. miss.
- **Cycles.** Comparison inherits the `=?` cycle boundary: identical cyclic
  objects match, distinct equal-content cycles raise the explicit
  unsupported-cyclic-equality error. That error ends the whole search, even
  if a later element is `==?` to the needle (e.g. `<MEMBER .A (.B .A)>` with
  `.A` and `.B` distinct one-element cycles): strict, never a silent miss. A LIST haystack is walked pair by pair;
  a hit before the cycle closes is returned, and revisiting a pair raises an
  explicit "cyclic LIST" error instead of looping (deviation: unprobed; the
  reference would not terminate on a miss).

Strict refusals (never a silent FALSE):

- Arity other than two: `TOO-FEW-ARGUMENTS-SUPPLIED` /
  `TOO-MANY-ARGUMENTS-SUPPLIED` (Confusion raises these MDL ERRORs).
- A non-structured second argument (FIX, ATOM, CHARACTER, ...): error
  `Second arg to MEMBER must be structured`, the same host-error style as
  MEMQ. Confusion prints this text as an internal error without an ERROR frame.
- An **empty STRING needle with a STRING haystack**. Confusion's result is an
  out-of-bounds read (it matches at the first NUL in or after the haystack),
  which differs from the manual's substring definition and is not MDL
  semantics. The runtime raises a deliberate unsupported error and returns
  neither the haystack nor `""`. The game never does this.
- TUPLE haystacks (modelled by the runtime, but MEMBER on them was not probed)
  and structured kinds the runtime does not model (BYTES, TEMPLATE, ...).
  These raise an explicit unsupported error until a reference probe exists.

Tests: `tests/member_test.rkt` (smoke suite), one assertion per supported
reference case plus aliasing, first-match, REST'd offsets, typed values,
cycles and every refusal.

## M3 session end: `QUIT` and the host-loop outcome (S11; ADR-0054)

Specification written before implementation. Authority: MDL manual §23.3
(QUIT stops MDL) and §16.2/§16.6; ADR-0051 (UNWIND cleanups only for MDL
transfers); pinned Confusion observations in
`docs/evidence/M3/SESSION-QUIT-REFERENCE.md` (`session-quit-probe.json`).
Implementation record: `docs/evidence/M3/S11-QUIT-OPEN.md`.

**Game call sites.** Every `QUIT` in the game takes no arguments:
77rooms.mud:50 (SAVE-IT XUNM gate), 279 (START, MUDDLE < 100 only), 427, 428,
435 (DO-RESTORE), 711 (FINISH after RECORD), 712 (FINISH's UNWIND cleanup),
952 (JIGS-UP after the third death). FINISH is reached from the `QUIT` verb
(77dung.mud:2920), from HANDLE (77rooms.mud:231 CONTROL-G, 252 after an MDL
ERROR), from death paths (338-339, 898, 906) and from DO-SAVE (398).

**`<QUIT>`.**
- Exactly zero arguments. One argument (Confusion: an exit status) is a strict
  unsupported error; two or more is `TOO-MANY-ARGUMENTS-SUPPLIED`. Arguments
  are evaluated first, as for any SUBR.
- It never calls Racket `exit` and never returns. It raises a dedicated host
  value, `mdl-quit-signal`, which is **not** an `exn:fail` (nor `exn:break`),
  so no `exn:fail?` handler of the runtime or loader intercepts it.
- It is **not** an MDL ERROR: no ERROR interrupt is signalled and no MDL ERROR
  handler (the game's HANDLE) runs.
- As a raise it is not an MDL transfer (ADR-0051): every UNWIND it crosses
  skips its cleanup. FINISH's `<UNWIND <PROG () … <QUIT>> <QUIT>>` therefore
  never runs its cleanup QUIT, RECORD's own UNWIND cleanup does not run on the
  QUIT that follows it (RECORD has already returned), and FLUSH-ME/JIGS-UP
  cleanups never run FINISH/RECORD a second time. Pinned Confusion agrees:
  its QUIT is `exit(0)` and runs no cleanup.
- Host bookkeeping restored by `dynamic-wind`/`parameterize` (bindings,
  activation liveness, ERROR frame liveness, OBLIST path, interrupt level) is
  still restored while the signal propagates.
- Outside the host loop (for example during `mdl-session-load!` or
  `mdl-session-call`) the signal propagates to the host caller unchanged; the
  host recognises it with `mdl-quit-signal?`.

**Session outcome.** `mdl-run-host-loop` / `mdl-session-run-interactive`
catch exactly `mdl-quit-signal` at the session boundary and **return** an
`mdl-session-outcome`; every other ending still raises. The taxonomy:

| Ending | Host sees |
|---|---|
| The game QUITs, no MDL ERROR was signalled during the run | returns outcome, kind `'quit` |
| The game QUITs after at least one MDL ERROR was signalled during the run (e.g. HANDLE → FINISH → QUIT, or a handler that ERRETs and play continues) | returns outcome, kind `'quit-after-mdl-error`; `mdl-session-outcome-mdl-errors` lists each ERROR's message, oldest first |
| Terminal input exhausted (D3) | raises `exn:fail:mdl-input-exhausted` |
| Host cancellation (break) | raises the `exn:break` |
| Strict host/runtime failure, unresolved MDL ERROR, pass bound | raises that `exn:fail` (unchanged object) |
| QUIT, but the final flush of terminal output fails | raises the first flush failure; the others are its secondary failures (`mdl-host-loop-secondary-failures`). There is no primary failure, and a quit whose transcript may be incomplete is never reported as success. |

"Signalled" means any application of the ERROR SUBR in the session while the
loop runs, whether or not a handler resolved it. Host strict errors are not
MDL ERRORs (they never run HANDLE) and always end the run as raised failures.
An acceptance run must require kind `'quit`.

## M3 file system: `OPEN` denial (virtual no-file policy; S11; ADR-0055)

Specification written before implementation. Authority: MDL manual §11.2.1
(a failed OPEN returns a FALSE of reason, file specification and status);
maintainer policy "OPEN returns FALSE, no file"; pinned Confusion observations
in `docs/evidence/M3/OPEN-FAILURE-REFERENCE.md` (`open-failure-probe.json`).

**Game call sites** (77rooms.mud unless stated):

| Line | Function | Form | This slice |
|---|---|---|---|
| 731 | RECORD | `<OPEN "READB" "ZORK" "LOG" .DEV .SNM>` | denied FALSE |
| 736 | RECORD | `<OPEN "PRINTO" "ZORK" "LOG" .DEV .SNM>` (only after a successful READB) | denied FALSE (unreachable under this policy) |
| 748 | RECORD | `<OPEN "PRINT" "ZORK" "LOG" .DEV .SNM>` | denied FALSE |
| 316 | MAKE-SCRIPT | `<OPEN "PRINT" <STRING "MARC;%Z" ,XUNM " >">>` (one file-spec STRING) | strict unsupported |
| 350, 352, 381, 384 | DO-SCRIPT, DO-SAVE (MUDDLE < 100 only) | `<OPEN "READ" … "DSK" .UNM>` | strict unsupported |
| 354 | DO-SCRIPT | `<OPEN "PRINT" "ZORK" "SCRIPT" "DSK" .UNM>` | denied FALSE (same 5-STRING PRINT form; not exercised). Visible policy deviation: the game prints `I can't open the script channel.` where Confusion creates `ZORK.SCRIPT` |
| 392 | DO-SAVE | `<OPEN "PRINTB" <STRING …>>` | strict unsupported |
| 412 | DO-RESTORE | `<OPEN "READB" .STR>` (one file-spec STRING) | strict unsupported |
| 961 | FILE-TO-TTY (HELP, INFO, …) | `<OPEN "READ" .FILE1 .FILE2 .DEV .SNM>` | strict unsupported |

**`<OPEN mode name1 name2 device directory>`** (the RECORD form).
- Exactly five arguments, each a STRING (native or REST view). Mode must be
  `"READB"`, `"PRINT"` or `"PRINTO"`. Any other arity (including the
  one-file-spec form), any other mode (`"READ"`, `"PRINTB"`, …) and any
  non-STRING argument is a strict error. No default arguments.
- It never touches the host file system: it opens, creates, truncates, stats
  or deletes nothing, in any directory.
- It returns a three-element FALSE `#FALSE (reason file-spec status)`:
  - `reason`: a fresh STRING; `file-spec`: a fresh STRING built as
    Confusion builds it, `directory "/" name1 "." name2` (the device is not
    part of it), e.g. `"MDL/ZORK.LOG"`; `status`: a FIX.
  - **Virtual-file-system policy** (not a claim of OS equivalence): the
    session's virtual directory is empty and read-only. READB: `"No such file
    or directory"`, status 2. PRINT and PRINTO: `"Permission denied"`, status
    13. These are the values pinned Confusion returns for an absent log in a
    read-only directory (Probe D2/D7), used as fixed constants.
  - The status is never `*600130*` (196696), the only value that sends RECORD
    (MUDDLE = 101) into its SLEEP/AGAIN busy loop, and never `*600117*` or
    `*600123*`.
- Each call is recorded host-side (mode, file-spec, status), readable with
  `mdl-session-open-records`; no MDL primitive exposes the record.

**RECORD under this policy.** READB is denied, the busy test `<==? <3 .CH>
*600130*>` is false, PRINT is denied, the `*600117*` test is false, and the
last clause `<RETURN T .RECORD>` returns. That RETURN crosses RECORD's UNWIND,
so its cleanup runs: `<AND .CH …>` stops at the FALSE `.CH`, and **CLOSE is not
reached**. FINISH then QUITs. Deviation: Confusion writes (or appends to)
`MDL/ZORK.LOG` here; this runtime writes nothing. The log is not part of the
console transcript, so no visible output differs.

**CLOSE** and the rest of the file API (FILE-LENGTH, ACCESS, READSTRING from a
file, SLEEP) stay unsupported (strict). No success-shaped CLOSE exists.

## M4 S2: CHTYPE to SEGMENT and runtime-built SEGMENTs (frontier F1; ADR-0056)

Specification written before implementation. Authority: MDL manual chapter
7 (segments) and chapter 6 (TYPE/PRIMTYPE/CHTYPE); pinned Confusion
observations in `docs/evidence/M4/SEGMENT-CHTYPE-REFERENCE.md`
(`segment-chtype-probe.json`, script `scripts/probe_segment_chtype_reference.py`).
Game use: the DEFMACs INSERT-OBJECT and TAKE-OBJECT (`77defs.mud:332-342`)
build `(<FORM PUT …> <CHTYPE <FORM ROBJS .ROOM> SEGMENT>)`; their expansion
is `<PUT .R 7 (<PUT .O 19 .R> !<ROBJS .R!>)>`, whose LIST, when evaluated,
prepends the object and **shares** the old ROBJS chain as its tail.

**One SEGMENT type.** SEGMENT is a built-in TYPE whose PRIMTYPE is LIST
(`<TYPEPRIM SEGMENT>` is LIST). The reader's `!<...>`, `!.X`, `!,X` and a
CHTYPE'd FORM are the same kind of object: in the reference `<TYPE '!.X>` is
SEGMENT and `<1 '!.X>` is LVAL. A SEGMENT is therefore represented exactly
like a FORM: a TYPE tag over the LIST cells of its elements. NTH, LENGTH,
REST (which returns a LIST), PUT, `=?` and `==?` behave as for any
LIST-primtype typed value.

**CHTYPE.** `<CHTYPE x SEGMENT>` accepts any value of PRIMTYPE LIST (LIST,
FORM, FALSE, SEGMENT, a NEWTYPE of LIST) and returns a SEGMENT over the
**same cells** (no copy): PUT through the SEGMENT is visible in the FORM and
vice versa. `<==? seg form>` and `<=? seg form>` are false (the TYPEs
differ); `==?` between two CHTYPEs of the same cells to SEGMENT is true, and
so is `==?` between their LIST views (`<CHTYPE seg LIST>`). CHTYPE of a
SEGMENT back to LIST, FALSE or a LIST NEWTYPE likewise shares the cells.
CHTYPE to SEGMENT from any other PRIMTYPE (VECTOR, UVECTOR, STRING,
WORD/FIX, ATOM) is a strict error, and so is SEGMENT to VECTOR (reference:
`PRIMTYPES do not match in CHTYPE`). The SEGMENT test is by identity with
the ROOT atom SEGMENT of a session's atom space, never by PNAME.

**Evaluation.** Unchanged M2 D2 rules, now applied to every SEGMENT object,
whatever produced it:

* a SEGMENT that is a *raw element* of a LIST, VECTOR or UVECTOR being
  evaluated (for example by EVAL of a runtime-built LIST, or by evaluating a
  macro expansion) evaluates its elements as a FORM and splices the value's
  elements; a final LIST-valued segment of a LIST construction shares the
  payload's cells (reference: `<==? <REST <EVAL <LIST 0 .S>>> .L>` is T,
  `<==? <EVAL <LIST .S>> .L>` is T, and a later PUT on `.L` is visible);
  non-final segments copy (`<EVAL <LIST .S 9>>` does not share);
* in a FORM's argument list it splices into the call's arguments; the LIST
  SUBR copies (`<==? <EVAL <FORM LIST .S>> .L>` is false);
* a SEGMENT that is the *value* of an evaluated element is stored as is
  (`<LIST 1 .S>` → a LIST whose second element has TYPE SEGMENT); EVAL of
  that LIST then splices it;
* EVAL of a SEGMENT outside a structure is `ILLEGAL-SEGMENT: Attempt to
  evaluate segment outside structured type`; a payload that evaluates to a
  non-structured value is `ILLEGAL-SEGMENT: Segment evaluated to
  nonstructured type`.

**Not supported / deviations (recorded).**

* CHTYPE to FORM stays an unsupported built-in conversion (existing strict
  refusal, `tests/type_test.rkt`; not on the game path). The reference
  accepts it and shares the cells (`<==? <CHTYPE seg FORM> form>` is T,
  `<CHTYPE <CHTYPE (A B) SEGMENT> FORM>` is `<A B>`).
* Printing a SEGMENT (PRIN1, UNPARSE, the REPL print) stays a strict error.
  The reference prints `!<A B!>`, `!.X`, `!,X`, `!<!>`; this runtime does not
  print FORMs or LISTs either.
* The CHTYPE mismatch text stays the runtime's `primitive type mismatch`.
  The reference writes `PRIMTYPES do not match in CHTYPE` to stderr and
  returns to LISTEN without an ERROR frame.
* Interpreted FUNCTION application: the reference binds a required formal
  from a raw SEGMENT argument by evaluating it standalone
  (`ILLEGAL-SEGMENT`), while a `"TUPLE"` formal splices; this runtime splices
  in both (the existing M2 D2 deviation, now also for runtime SEGMENTs).
* Reader SEGMENTs no longer carry a source line/column (never shown in any
  message).

## M4 S3: CHTYPE between FIX (WORD) and CHARACTER (frontier F2/F2b; ADR-0057)

Specification written before implementation. Authority: MDL manual chapter
6 (TYPE/PRIMTYPE/CHTYPE: CHTYPE changes only the TYPE of an object whose
PRIMTYPE equals the target's) and chapter 7 (CHARACTER is PRIMTYPE WORD);
pinned Confusion observations in
`docs/evidence/M4/CHARACTER-CHTYPE-REFERENCE.md`
(`character-chtype-probe.json`, script
`scripts/probe_character_chtype_reference.py`). Game use: FOOSTR
(`77np.mud:241`) lower-cases a word for PRSTR with
`<PUT .Y 1 <CHTYPE <+ 32 <ASCII <1 .X>>> CHARACTER>>`; PRSTR is called by
ORTELL (the `<prep> what?` orphan prompts, `77np.mud:226`), by SPARSE's
`Which <noun>?` (`77np.mud:88`) and `I can't see a <adj> <noun> here.`
(`77np.mud:79-80`).

**Conversion.** `<CHTYPE x CHARACTER>` accepts any x of PRIMTYPE WORD whose
value is a FIX code (FIX, WORD, CHARACTER, a NEWTYPE of WORD) and returns
the CHARACTER with that code, the same runtime value that `ASCII`, a STRING
element and the reader's `!\c` produce. Equality is by code: the result is
`==?` and `=?` to `!\c` and to `<ASCII code>`; it is never `==?` or `=?` to
the FIX (reference `character-identity`). It can be stored in a STRING by
PUT, concatenated by STRING, found by MEMQ in a STRING, and PRINC writes it
as the bare character. `<CHTYPE char FIX>` returns the code (`<CHTYPE !\A
FIX>` is 65, equal to `<ASCII !\A>`); `<CHTYPE char WORD>` returns the WORD
with that code and `<CHTYPE word CHARACTER>` returns the CHARACTER again;
a NEWTYPE of WORD round-trips the same way. `<CHTYPE char CHARACTER>`
returns the character unchanged.

**Range (deviation, ADR-0057).** The reference does not range-check: any
36-bit value becomes a CHARACTER and comes back unchanged through ASCII or
CHTYPE to FIX (128, 255, 256, -1, 2^35-1, -2^35 all observed), and such
CHARACTERs print implementation bytes. This runtime keeps its documented
CHARACTER range: `<CHTYPE x CHARACTER>` is supported for codes **0–127**
only, the range of `ASCII` FIX → CHARACTER (whose 128 and -1 the reference
itself refuses with `Value for ASCII out of range`) and of terminal input
(a code above 127 in READSTRING input is a strict error). Any other code is
a strict error `mdl-chtype: CHARACTER code out of supported range 0..127`.
Game reach is inside the range: PRSTR only receives ATOMs found by LOOKUP
in the WORDS, OBJECTS, ACTIONS and DIRECTIONS oblists, whose PNAME
characters are at most 90 (`Z`) in the reference (`game-word-pname-range`),
so FOOSTR's argument is at most 122; the scenario log shows 97, 116, 119,
105, 116, 104 (`at`, `with`).

**Strict refusals.** CHTYPE to CHARACTER from a non-WORD PRIMTYPE (STRING,
LIST, ATOM, VECTOR) and from CHARACTER to ATOM, LIST or STRING:
`primitive type mismatch` (reference `PRIMTYPES do not match in CHTYPE`).
FLOAT to CHARACTER and CHARACTER to FLOAT stay unsupported (the reference
reinterprets the float bits; not on the game path). Wrong argument counts
stay host arity errors (reference `TOO-MANY-/TOO-FEW-ARGUMENTS-SUPPLIED`).
Printing a CHARACTER outside 32–126 through UNPARSE/PRIN1 is unchanged
(control characters strict; PRIN1 of CHARACTER strict, M3 S7).

**Dispatch.** As ADR-0056: the CHARACTER branch is taken only when the
target is the session's ROOT built-in TYPE atom CHARACTER; a user TYPE atom
merely named CHARACTER is an ordinary NEWTYPE.

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

## M4 S4: TOP of arrays (issue #157; frontier item 3; ADR-0058)

Specification written before implementation. Authority: MDL manual §7.6.2.2
(`<TOP array>` puts back every element that REST removed: the inverse of
all RESTs) and the BACK section above ("M3 BACK and terminal CHANNEL
predecessor"); pinned Confusion observations in
`docs/evidence/M4/TOP-REFERENCE.md` (`top-probe.json`, script
`scripts/probe_top_reference.py`). Game uses: SPARSE's dangling preposition
(`77np.mud:126`, `<TOP <PUT <BACK .PVR> 1 ...>>`, the whole PRSVEC);
EVERYTHING/VALUABLES (`77rooms.mud:1284, 1330`, `(TUV <TOP .SUV>)` on the
20-slot OBJECT UVECTOR OBJ-UV, filled downwards with BACK until
`<==? .SUV .TUV>`); the balloon (`77act2.mud:505, 557`, `(S <TOP ,SCRSTR>)`);
the script channels (`77rooms.mud:317-369`, `<PUT <TOP ,INCHAN> 1 (.CH)>`,
only after OPEN "PRINT" succeeds, which ADR-0055 denies).

**Result.** `<TOP x>` takes exactly one argument. For x of PRIMTYPE VECTOR,
UVECTOR or STRING (a plain array, a REST or BACK view, or a TYPE over one)
it returns a view of the **same storage** from the storage's first element
to its end. It is never a copy: a PUT through the result, through x or
through any other view of the storage is visible in all of them, whether it
happened before or after TOP. A UVECTOR result shares the element-type
(UTYPE) cell. x itself is unchanged (a REST view keeps its length).

**TYPE.** The result has x's TYPE: TOP of a NEWTYPE-tagged array (`#FOO
[...]`, a NEWTYPE of STRING or UVECTOR) is of that NEWTYPE (reference
`newtype-vector`, `newtype-string-uvector`). REST (including REST 0) of a
typed array already returns the PRIMTYPE, so `<TOP <REST x>>` is a VECTOR,
UVECTOR or STRING. The type dispatch is on the value's representation
(array or STRING storage under at most one TYPE tag), never on a TYPE
atom's PNAME (ADR-0056/0057).

**Identity.** `==?` on arrays is the same storage, start and length, so the
TOP result is `==?` to the unrested original, to every other TOP of the
same storage, and to a BACK that reaches the first element; it is `==?` to
a NEWTYPE-tagged original only if the TYPEs agree (`<==? <TOP <CHTYPE <REST
.V 2> FOO>> .V>` is FALSE, the CHTYPE back to VECTOR is T). An equal
separate array is `=?` but not `==?`. EVERYTHING's `<==? .SUV .TUV>` is T
exactly when the BACK steps have reached the first slot.

**BACK of a NEWTYPE'd array (resolved 2026-11-23).** The independent S4
review found that BACK dropped a NEWTYPE tag while TOP kept it (native keeps
it for both: `<TYPE <BACK .F 2>>` = FOO, `<==? <TOP .F> <BACK .F 2>>` = T,
`BS` for a NEWTYPE of STRING; mdli 6df359f6). By maintainer decision BACK now
keeps the argument's TYPE too, so TOP and BACK views of the same extent of a
typed array are `==?` (tests/back_test.rkt, tests/top_test.rkt).

**Refusals (strict errors).** Any other argument: LIST-primtype values
(LIST, a REST of a LIST, FORM, FALSE, SEGMENT), TUPLEs (this runtime's TUPLE
is a LIST; the reference refuses them too), FIX, ATOM, CHARACTER and other
non-structured values, and the struct-backed builtins whose PRIMTYPE is
UVECTOR or VECTOR but which are not arrays here — OBLIST, IHEADER, HANDLER
(recorded deviation: the reference's TOP would accept an OBLIST; refusing is
strict and not game-reachable): `mdl-top: Bad type for TOP` (reference text `Bad type
for TOP`, written to stderr; this runtime raises the error like every other
refusal). TOP never invents LIST semantics. Arity: `<TOP>` raises
`TOO-FEW-ARGUMENTS-SUPPLIED`, two or more arguments
`TOO-MANY-ARGUMENTS-SUPPLIED` (reference: ERROR frames with those names).

**CHANNEL storage (deviation, ADR-0058).** The reference's terminal
CHANNELs have two slots before element 1; TOP exposes both: slot 1 is the
LIST of script/echo channels (`()`), slot 2 the FIX 0 that `<1 <BACK
,INCHAN>>` reads (`<TOP ,INCHAN>` is a CHANNEL of 21 elements, `==?` to
`<BACK ,INCHAN 2>`). This runtime models only the second (M3, issue #110)
and implements no echo channels. TOP of any view of a CHANNEL's storage (a
CHANNEL, or a VECTOR obtained by REST of one) is therefore a strict error
`mdl-top: TOP of CHANNEL storage is not supported (ADR-0058)` rather than a
20-element result whose slot 1 would be the wrong slot. The game reaches it
only in the script code after a successful OPEN "PRINT".

**Not supported / recorded.** GROW is not a SUBR of the pinned reference
(UNBOUND-VARIABLE) nor of this runtime, so TOP after GROW is not defined.
