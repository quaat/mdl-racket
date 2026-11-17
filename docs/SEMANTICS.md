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
  of computed references remains unsupported by the M0 compiler. Reference:
  *The MDL Programming Language*,
  [§4.2.2](https://mdl-language.readthedocs.io/en/latest/04-values-of-atoms/).
  Tests: `tests/parser_test.rkt`.
- Backslash in a string quotes the following character. In particular,
  `\n` in source represents `n`, not a newline escape. Reference:
  *The MDL Programming Language*,
  [§7.2.4](https://mdl-language.readthedocs.io/en/latest/07-structured-objects/)
  and pinned Confusion `mdl_read.cpp` (`READSTATE_INSTRING_LIT_BS`). Test:
  `tests/parser_test.rkt`.

| Construct | M0 behavior | Required target behavior | Evidence |
|---|---|---|---|
| `<DEFINE>` | simple fixed arity only | MDL parameters incl `OPTIONAL`, `AUX`, `TUPLE`, callable globals | bootstrap tests only |
| `<SETG>`/`,GLOB` | hash-backed process-local environment | original MDL global binding/lookup semantics | bootstrap tests only |
| `.LOCAL` | lexical variable with limited SET | dynamic and named activation semantics as applicable | bootstrap tests only |
| `<>` / `#FALSE` | M0 maps `<>` to Racket `#f` | distinct MDL FALSE value with payload; literal payload is data | M1 issue #3 in progress |
| `<COND>` | simplified test + value branches | MDL predicate truth and branch return value, evaluation order | bootstrap tests only |
| `AND`/`OR` | approximated with Racket logic | MDL short-circuit and false-value semantics | **NOT VERIFIED** |
| MDL lists | mcons/mutable pair construction | aliasing, nested views, REST/PUTREST/PUT and identity | **NOT IMPLEMENTED** |
| MDL vectors | Racket vectors (bootstrap) | original vector and UVECTOR/structure distinctions | **NOT VERIFIED** |
| `OBLIST` / `ATOM` | M1 identity-bearing values and direct lookup/insertion | dynamic reader lookup, associations, and complete OBLIST structure | issue #4 slice in progress |
| `NEWTYPE` / `CHTYPE` / `NEWSTRUC` | not supported | original type tags and accessors | **NOT IMPLEMENTED** |
| `RETURN` / `AGAIN` / `UNWIND` | not supported | MDL activation record semantics | **NOT IMPLEMENTED** |
| MDL octal `*777*` | basic scalar parsing | 36-bit signed/unsigned bit semantics | **NOT VERIFIED** |
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
