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
| `PROG` / `REPEAT` / `RETURN` / `AGAIN` | unnamed frames and bare transfers in current function | named activations, explicit targets, GO/UNWIND | M2 issues #20, #26 |
| MDL octal `*777*` | FIX input with 36-bit boundary conversion | full reader radix controls | M1 issue #8 |
| `#ROOM {...}` / typed macros | AST recognition only | macro expansion with original semantics | **NOT IMPLEMENTED** |
| `READSTRING` / `LEX` / `EPARSE` | not supported | original parser and terminal semantics | **NOT IMPLEMENTED** |
| `SAVE` / `RESTORE` | not supported | stable per-player snapshots; validated against reference | **NOT IMPLEMENTED** |
| random/time/events | not supported | determinism and original turn-based scheduling | **NOT IMPLEMENTED** |

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
