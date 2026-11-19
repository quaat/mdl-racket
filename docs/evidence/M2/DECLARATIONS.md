# M2 local task — `#DECL` local declarations and `DECL?`

**Local slice: PASS. M2 milestone: NOT YET PASS.** Base commit (branch
`feat/m2-declarations`, created from `main`):
`2267ae9e1bb18d399740067b392d7ba80620b7a5`; `main`:
`2267ae9e1bb18d399740067b392d7ba80620b7a5`. This slice is tracked by
[issue #44](https://github.com/quaat/mdl-racket/issues/44) from branch
`feat/m2-declarations`. `sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and patched Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; `scripts/check_1977_sources.py`
verified both checkouts at the locked commits (it aborts on any mismatch)
during the reader sweep. The target file
`81prim.mud` has SHA-256
`8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`;
the entry `77loadall.mud` has SHA-256
`389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa`.

The session that implemented most of this slice ended mid-task; a later
session recovered the uncommitted work, verified it, added the three
red-to-green items below, and produced this record. The recovery notes are
in `docs/evidence/M2/SESSION-RECOVERY-2026-11-19.md`.

## What this slice implements

`#DECL` parses to a declaration node carrying its source line and column;
`<TYPE #DECL ((X) FIX)>` is the ATOM `DECL`. A declaration is accepted only
immediately after the formal or auxiliary list of `DEFINE`, `DEFMAC`,
`PROG`, and `REPEAT`, in both the compiled and interpreted paths, and also
evaluates to a DECL-typed value in any other expression position. Patterns
support registered type ATOMs (including `NEWTYPE` names), `ANY`,
`<OR ...>`, and `<PRIMTYPE type>`; matching compares MDL `TYPE` and
`PRIMTYPE` respectively. Checking is on: bound arguments, optional and AUX
initializations, each later `SET` in the owning frame, and the normal or
explicit `RETURN`/prog result of the owning activation, including nonlocal
returns through nested calls. The frame association uses a weak table keyed
by frame identity, so nested and stale frames are never confused. `GASSIGNED?`
and `MANIFEST` (returning `T`) were added as the primitives the original
`MSETG` body needs, with `SETG` refusing to change an already assigned
manifest value unless the new value is `==?`-identical or `.REDEFINE` is
true. The explicit chapter-14 predicate `<DECL? value pattern>` returns `T`
or a `#FALSE` carrying the value and pattern, matching pinned Confusion.

The pinned original source contains one doubled `#DECL #DECL ((PRSACT)
VERB)` (`77act1.mud:110`, present in the original, MIT, and
patched_confusion trees). Confusion's reader implements `#` as a generic
typecode prefix, so the outer `#DECL` re-types the inner DECL value — a
no-op — and both `#DECL` tokens collapse into one declaration. The reader
now accepts that exact form and still rejects any other non-parenthesized
payload.

Unknown type names, malformed pairs, duplicate declarations, compound
structure/repetition patterns (`<LIST FIX>`, `[REST ATOM]`), quoted-object
patterns, aliases, and `SPECIAL`/`UNSPECIAL` fail explicitly and are never
treated as `ANY`. `DECL-CHECK` (historically global checking control) is
not implemented; checking is unconditionally on, which is what the original
sources assume.

## Red-to-green evidence

The original `MSETG` definition (`81prim.mud` expression 2) previously
stopped the loader at compile stage with `unsupported compiler construct
#DECL` (recorded in
`docs/evidence/M2/source-load-first-barrier.json` from the source-loader
slice). After this slice, the same unmodified definition installs, and
`<MSETG M2-D1-TEMP 3>` returns `T` leaving the global at `3`
(`tests/declaration_test.rkt` lines 75–86 drive this through the shared
session loader).

Three items were added by the recovering session, each observed red first:

1. `<TYPE #DECL ((X) FIX)>` compiled to `mdl-compiler: unsupported MDL
   construct decl` before the `decl` case was added to
   `compile-expression/body`; it now yields the ATOM `DECL` (also matching
   reference case `decl-object`).
2. `<DECL? 3 FIX>` raised `unassigned or non-applicable MDL operator`
   before `DECL?` was registered; it now returns `T`, `#FALSE`, and the
   reference-observed error behavior for malformed patterns.
3. The doubled `#DECL #DECL` failed the whole-file reader sweep with
   `#DECL requires a parenthesized payload` on `act1.37`, `act1.38`,
   `77act1.mud`, and their MIT counterparts (5 files, observed 2026-11-19);
   after the reader fix, all 36 selected text files parse again.
4. PR #45's first CI run failed the smoke workflow: the declaration test
   asserted the pinned-source load progression, but the smoke container
   does not provision `.cache/upstream/`. The pinned-file acceptance
   (SHA verification, FAIL-at-splice progression, retained `MSETG`) moved to
   `tests/historical_decl_test.rkt` in the `make test-historical` suite,
   which `reference.yml` runs after `make sources`; the smoke-visible
   `tests/declaration_test.rkt` now pins the same original `MSETG` source
   text as a session fixture (file copy, full load PASS, execution and
   wrong-atom rejection) so both gates exercise the D1 acceptance.

## Reference validation

Probe inputs and full stdout/stderr are in `decl-cases.json`,
`decl-reference.json`, `decl-error-cases.json`, and
`decl-error-reference.json` (one local Confusion process per case, stdin
expression then `<QUIT>`; cwd the pinned `patched_confusion` tree). All 13
case observations match the earlier capture from the implementing session
byte-for-byte (exit codes, stdout, stderr), and the regenerated files carry
the same interpreter SHA-256, so the earlier capture was not discarded.

- 11 success cases exit 0 with empty stderr, including `decl-object`
  (`DECL`), `explicit-fix-yes`/`no`, `explicit-or`, `explicit-primtype`
  (`DECL?` matching `T` / `#FALSE ("x" FIX)`), and the original
  `msetg-good`/`msetg-repeat` (`FLOAD "81prim.mud"`, then `T`).
- 2 error cases record `*ERROR* MSETG ... ALREADY-GASSIGNED` (case
  `original-msetg-conflict`, stderr `Atom REP has neither LVAL nor GVAL`)
  and `Type Mismatch, 1st arg to GASSIGNED? must be atom` (case
  `original-msetg-wrong-atom`).

Known deviation, recorded in `docs/SEMANTICS.md`: the pinned Confusion
build does **not** enforce attached declarations (cases
`attached-bad-argument`, `attached-bad-set`, `attached-bad-result` all
succeed there); its `mdl_decl.cpp` labels checking work in progress. This
implementation follows the manual's chapter-14 enforcement semantics and
rejects those cases, rather than copying the reference's missing checks.
A second deviation: the manual's `DECL?` example returns `#FALSE ()`,
while pinned Confusion returns `#FALSE (value pattern)`; this slice
reproduces Confusion because it is the comparison reference. Wrong-atom
`MSETG` errors at the declaration binding boundary here and at
`GASSIGNED?` in Confusion; both fail explicitly.

## Commands and results

| Command | Exit | Observed result |
|---|---:|---|
| `raco test tests/declaration_test.rkt` | 0 | 56 checks including the doubled-`#DECL`, `DECL?`, expression-position, original-`MSETG` fixture, and review-regression cases |
| `bash scripts/test_racket.sh` | 0 | 618 Racket checks passed (loader and historical tests need `/tmp` and were run outside the per-command sandbox; see environment note) |
| `raco test tests/loader_test.rkt` (from repo root) | 0 | 57 checks passed |
| `make test-historical` (from repo root) | 0 | 23 VFLOAD assertions plus 10 declaration assertions, including the pinned `81prim.mud` SHA verification, the FAIL-at-splice load progression, and the retained original `MSETG` execution |
| Python tests (`tests/test_harness.py`, `test_fetch_sources.py`, `test_reference_pty.py`, `test_probe.py`) | 0 | 13 passed |
| `racket scripts/mdl_load.rkt --source-root .../patched_confusion --entry 77loadall.mud --report artifacts/m2/source-load.json` | 0 | `MDL source load FAIL: 3 completed expressions`; new blocker is the `!`-splice construct at `81prim.mud:16:46` (compile stage, `unsupported MDL construct splice`) — the loader stops explicitly by design |
| `scripts.mdl_probe --cases docs/evidence/M2/decl-cases.json` | 0 | 11/11 successful probes |
| `scripts.mdl_probe --cases docs/evidence/M2/decl-error-cases.json` | 1, expected | 2 deliberately invalid observations recorded |
| `scripts/check_1977_sources.py` | 0 | 36 parsed, 0 failed, 4 non-text after the doubled-`#DECL` reader fix; current sweep copied to `docs/evidence/M2/reader-sweep.json`, frozen M0 sweep restored per the M1 protocol |
| `git diff --check` | 0 | No whitespace errors |

Environment notes, recorded precisely: the per-command sandbox mounts `/tmp`
read-only, so `tests/loader_test.rkt` and `tests/historical_vfload_test.rkt`
(which create scratch directories under literal `/tmp` paths) were run
outside it; the same tests pass there. In-sandbox runs use `PLTCOLLECTS`
pointing at the repository because the sandbox hides
`~/.local/share/racket` between commands. Python tests ran under system
Python 3.9.2 with the pinned pure-Python wheels in the untracked
`.sandbox-pydeps/` directory (the `.venv` target is hidden the same way).
Racket is 7.9 [bc]. The pinned Confusion binary was built by
`make reference-build` earlier and not rebuilt; SHA-256
`a29c756df5c973e462a6ad2b318e28ec265934e89e72d825bc7672387317e629`.

## Security and licensing impact

No MDL evaluator or filesystem access is exposed to any network client; all
execution is local. Confusion was read as a semantic reference only
(`mdl_read.cpp`, `mdl_decl.cpp`, `macros.cpp`); no Confusion code was
copied into the MIT-0 runtime. `.cache/upstream/` was not modified.

## Supported and unsupported

Supported: `#DECL` in the declaration position of `DEFINE`, `DEFMAC`,
`PROG`, and `REPEAT` (compiled and interpreted, including macros with a
leading activation name); declaration-position checking of bound formals,
OPTIONAL/AUX initializers, `SET`, and normal/`RETURN` results; `ANY`,
type atoms (including `NEWTYPE`), `<OR ...>`, `<PRIMTYPE type>`; `VALUE`
result patterns; the doubled `#DECL` form; `DECL?`; `GASSIGNED?`; `MANIFEST`
with the `.REDEFINE`-gated `SETG` restriction.

Unsupported (explicit failures, not silent no-ops): compound patterns
(`<LIST FIX>`, `[REST ATOM]`), quoted-object patterns, `SPECIAL`/
`UNSPECIAL`, aliases, `GDECL`/`DECL-CHECK`, RSUBR declaration forms,
non-parenthesized `#DECL` payloads other than the doubled-`#DECL` form.

## Post-review regression additions

The PR #45 review (Codex CLI was unavailable, so the independent pass ran
in-session with fresh context plus targeted inline probes) found no
defects in the slice. Fifteen review probes verified: interpreted AUX
initializer and `SET` enforcement through the loader session, absence of
cross-frame declaration leakage between nested calls, all manifest edges
(identical reassignment allowed, differing reassignment rejected, the
`.REDEFINE` override, `MANIFEST` before assignment leaving `GASSIGNED?`
false), independent `VALUE` declarations of an inner PROG and its
enclosing function (the function's own declaration rejects a result the
PROG accepted, at the function's `#DECL` position), `REPEAT`
declarations, `RETURN` to a named activation checking the function's
result declaration, and a `DEFMAC`'s own declaration checking its bound
formals at expansion. Six behaviors the probes confirmed but the suite
did not yet pin were added as regressions to
`tests/declaration_test.rkt`: the four manifest edges, cross-frame
isolation, macro declaration acceptance/rejection, and the inner-PROG
`VALUE` independence. One permissive corner was noted and deliberately
left: `SETG` after `MANIFEST` on a still-unassigned global is allowed
(the restriction only applies once a value is assigned); no historical
source exercises it, Confusion's `MANIFEST` is a no-op, so no parity is
claimed for it.

## Next action

The loader's next actual blocker, after this slice, is the `!`-splice
(`!.PL` in `PSETG`, `81prim.mud:16:46`, compile stage), followed by the
compound `<LIST [REST ATOM]>` pattern that `PSETG`'s own declaration
requires. Implement the splice read construct first, then the
reference-backed `[REST ...]` pattern slice; both need their own
`DECLARATIONS.md`-style record and issue.
