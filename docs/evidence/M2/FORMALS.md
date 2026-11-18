# M2 local task — OPTIONAL/AUX/TUPLE/ARGS function formals

**Local slice: PASS. M2 milestone: NOT YET PASS.** Base commit (branch
`feat/m2-named-activations`, pending merge of the #28 slice):
`c9f0df9f51fc7a61a34e00fa1c08ec4d763f9bb3`; `main`:
`40cbebb1f6d4cb2fcf708a51e2cd98b85f95b4e8`. This slice is tracked by
[issue #30](https://github.com/quaat/mdl-racket/issues/30) and
[PR #32](https://github.com/quaat/mdl-racket/pull/32) from branch
`feat/m2-function-formals`, stacked on the `feat/m2-named-activations`
branch of PR #29; this file remains the full task record required by
`AGENTS.md` step 3. `sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and patched Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; `scripts/fetch_sources.py`
verified both upstream trees clean before the probes. This slice implements
the plan's "function binding" work item: OPTIONAL/AUX/TUPLE and application
semantics, the prerequisite for DEFMAC and the source loader. The historical
reconstruction uses these forms pervasively: 245 `"AUX"`, 39 `"OPTIONAL"`,
16 `"TUPLE"`, and one `"ARGS"` occurrence across the `patched_confusion`
1977 sources (for example `REMOVE-OBJECT` with bare `"AUX"`, `FLUSH-OBJ` with
`"TUPLE"` before `"AUX"` with an initializer, `ILO` with bare `"OPTIONAL"`,
and `NEWSTRUC` with `"ARGS"`).

## Semantics

Historical formal lists mark sections with **STRINGs**, not atoms: `"OPT"` or
`"OPTIONAL"`, `"ARGS"`, `"TUPLE"`, and `"AUX"` or `"EXTRA"`. An ATOM named
`AUX` is an ordinary required formal (probe `aux-atom-is-plain-formal` returns
`(1 3)` for `(A AUX B)` called with three arguments). Section order follows
the pinned Confusion `mdl_bind_args` state machine: required atoms, then
OPTIONAL, then at most one ARGS or TUPLE binding, then AUX. Two-element LISTs
give an OPTIONAL or AUX binding an initial-value expression; they are rejected
in the required section. Defaults evaluate left to right in the partially
built function frame, so a later default sees earlier formals. An unsupplied
OPTIONAL without a default and a bare AUX local stay **unassigned**: reading
them raises the same unassigned-local error as a PROG auxiliary (Confusion
prints `*ERROR* "UNBOUND-VARIABLE"`). AUX bindings are frame-local and
restore outer locals on return. TUPLE binds the remaining arguments as a
value with TYPE `TUPLE` **and PRIMTYPE `TUPLE`** — its own primitive type, not
LIST; `TYPEPRIM TUPLE` is `TUPLE`, and `REST` of a TUPLE keeps TYPE `TUPLE`.
Two separately made TUPLEs of equal content are `=?` but not `==?`, and a
TUPLE is never `=?` to a LIST. ARGS binds the remaining arguments as a
LIST. Arity failures raise `TOO-FEW-ARGUMENTS-SUPPLIED` and
`TOO-MANY-ARGUMENTS-SUPPLIED`; a repeated formal raises `BAD-ARGUMENT-LIST`.

The manual's function chapters
([9](https://mdl-language.readthedocs.io/en/latest/09-functions/) and
[5](https://mdl-language.readthedocs.io/en/latest/05-simple-functions/))
document optional and auxiliary arguments and the string-marked formal list;
the pinned Confusion source `macros.cpp` `mdl_bind_args` fixes the exact
section order and rest-binding behavior. Confusion was read as a semantic
reference only; no Confusion code was copied.

## Deviations

- Confusion stores the formal list as unevaluated data and validates it at
  **call** time; malformed lists (TUPLE after AUX, two TUPLEs, duplicate
  formals) kill the process with a stderr message such as `TUPLE in wrong
  place in argument string`. This slice rejects every malformed or unsupported
  formal list at **compile** time instead, consistent with the repository's
  existing strict-failure discipline and the named-activation slice's
  treatment of duplicate names. No construct that Confusion accepts is
  rejected, and no construct Confusion rejects is silently accepted.
- The `"NAME"`, `"ACT"`, `"BIND"`, and `"CALL"` activation formal markers fail
  explicitly at compile time; they belong to the later control slice with GO
  and UNWIND.
- `PUT` on a TUPLE follows the LIST-primtype mutation path in the Racket
  runtime; historical TUPLE mutation was not probed and is not claimed.
- Empty TUPLE identity (`==?` of two empty TUPLEs) was not probed in
  Confusion; the Racket runtime gives distinct identities, as for nonempty
  TUPLEs.

## Commands and results

| Command | Exit | Observed result |
|---|---:|---|
| `scripts/fetch_sources.py` | 0 | Two locked commits verified; upstream trees clean |
| `raco pkg install --auto --link` (session setup) | 0 | Package linked; in-sandbox runs use `PLTCOLLECTS` because the sandbox hides `~/.local/share/racket` between commands |
| `make test` before implementation (Racket half) | 0 | 347 Racket checks on the base commit; new `tests/formals_test.rkt` aborted red on `DEFINE optional/AUX/TUPLE arguments not supported in M0` |
| Python tests before implementation | 0 | 13 passed |
| `make test` final (Racket half) | 0 | 403 Racket checks (347 existing + 46 formals + 10 new core invariants); after the Codex review fix below, 408 |
| `raco test` with the PUTREST fix (72ac750) | 0 | 408 Racket checks, 13 Python tests |
| Python tests final | 0 | 13 passed (see environment note below) |
| `scripts/check_1977_sources.py` | 0 | 36 parsed, 0 failed, 4 non-text |
| `scripts.mdl_probe --cases docs/evidence/M2/formals-cases.json` | 0 | 24/24 successful probes, exit 0, empty stderr |
| `scripts.mdl_probe --cases docs/evidence/M2/formals-error-cases.json` | 1, expected | 11 deliberately invalid observations recorded, including `TOO-FEW/TOO-MANY-ARGUMENTS-SUPPLIED`, `BAD-ARGUMENT-LIST`, three `UNBOUND-VARIABLE` unassigned reads, and process-fatal `TUPLE/2-list` formal-list errors |
| `scripts.reference_runner.py capture` | 0 | Five turns, `complete=true`, `error=null` |
| `scripts.mdl_probe --cases tests/scenarios/primitives.json` | 0 | Twelve baseline expressions |
| Saved-suite reproduction script (this report) | 0 | All 69 saved M2 success cases (9 prog, 5 repeat, 11 activation-target, 24 formals) and 20 expected-error cases reproduce exactly |
| Golden comparison (excluding `captured_at`, `engine_sha256`, banner timestamp) | 0 | `M2 formals slice reference and golden comparisons PASS` |
| `git diff --check` | 0 | No whitespace errors |

Environment notes, recorded precisely: the session sandbox hides the host
Python 3.13 interpreter that `.venv` symlinks point at, so the Python tests and
probe scripts ran under system Python 3.9.2 with the pinned pure-Python wheels
(`pytest 8.4.2`, `pexpect 4.9.0`, and their dependencies, resolved for 3.9)
extracted into the untracked `.sandbox-pydeps/` directory; `make test`'s
Racket half ran with `PLTCOLLECTS` pointing at the repository. The pinned
Confusion binary was built in the #28 session and not rebuilt (SHA unchanged
below); Racket is 7.9 [bc], Python 3.9.2 for the harness tests, BDW GC 8.0.4.

Hashes: Confusion binary SHA-256
`2c58ef023d2ac306bdf661ee0afc0123eef94a8608c108a36ddc2e8808ab4d95`;
reconstructed game image SHA-256
`92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6a1b0ffb7a4`;
approved M0 golden SHA-256
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
Focused probe inputs are fixed with no time or randomness; the house scenario
has fixed commands but no controlled RNG seed, and Confusion embeds build time
in its banner (excluded by the comparison contract).

## Supported and unsupported

## Post-review fix

The Codex review of PR #32 (P1) found that PUTREST unwrapped a TUPLE head
or tail through `mdl-list-head`, splicing or exposing tuple storage across
its distinct primitive type. PUTREST now validates both operands through
PRIMTYPE and rejects non-LIST-primtype values explicitly while keeping
LIST, FALSE, and typed LIST heads working; TUPLE access for LENGTH, NTH,
PUT, REST, and equality is unchanged. Fix commit `72ac750` adds five
regression checks (`tests/formals_test.rkt`), bringing the suite to 408
Racket checks.

Supported: required formals; `"OPT"`/`"OPTIONAL"`, `"AUX"`/`"EXTRA"`,
`"ARGS"`, and `"TUPLE"` sections in the reference order with compile-time
shape validation; defaults evaluated in frame order; unassigned optional/aux
bindings; TUPLE-typed rest values (TYPE/PRIMTYPE `TUPLE`, structural equality,
LENGTH/NTH/REST); ARGS as LIST; historical arity error names; frame
restoration on return. Unsupported and failing explicitly: `"NAME"`/`"ACT"`/
`"BIND"`/`"CALL"` markers, quoted formals, activation-name ATOMs before the
formal list, malformed section order, duplicate formals, 2-lists in the
required section, and CHTYPE to or from TUPLE.

No game rule, upstream source, public license, deployed service, or GPLv3
Confusion code changed; no evaluator endpoint was exposed. Next: activation
formals with GO and UNWIND (the later control slice), then DEFMAC and the
source loader with initial original source definitions.
