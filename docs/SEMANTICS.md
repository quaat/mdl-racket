# MDL semantic compatibility ledger

This is a living ledger. A reader parsing a token is **not** a verified
implementation. Every entry must ultimately reference the MDL documentation,
a minimal Confusion probe (source + output), and a Racket regression test.

| Construct | M0 behavior | Required target behavior | Evidence |
|---|---|---|---|
| `<DEFINE>` | simple fixed arity only | MDL parameters incl `OPTIONAL`, `AUX`, `TUPLE`, callable globals | bootstrap tests only |
| `<SETG>`/`,GLOB` | hash-backed process-local environment | original MDL global binding/lookup semantics | bootstrap tests only |
| `.LOCAL` | lexical variable with limited SET | dynamic and named activation semantics as applicable | bootstrap tests only |
| `<>` / `#FALSE` | `<>` maps to Racket `#f` | full MDL FALSE type, truth, value payload | **NOT IMPLEMENTED** |
| `<COND>` | simplified test + value branches | MDL predicate truth and branch return value, evaluation order | bootstrap tests only |
| `AND`/`OR` | approximated with Racket logic | MDL short-circuit and false-value semantics | **NOT VERIFIED** |
| MDL lists | mcons/mutable pair construction | aliasing, nested views, REST/PUTREST/PUT and identity | **NOT IMPLEMENTED** |
| MDL vectors | Racket vectors (bootstrap) | original vector and UVECTOR/structure distinctions | **NOT VERIFIED** |
| `OBLIST` / `ATOM` | interned symbol placeholder | atom identity, lookup/insertion, multi-oblist namespaces | **NOT IMPLEMENTED** |
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
