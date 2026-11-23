# M2 local task — activation formals, GO, and UNWIND

**Local slice: PASS. M2 milestone: NOT YET PASS.** Base commit (branch
`feat/m2-function-formals`, itself pending merge on top of the pending #28
branch): `4764c17` after the PR #32 review fix (originally developed on
`931545c594b932f03a4a924b031ad260d89535da`). This slice is tracked
by [issue #31](https://github.com/quaat/mdl-racket/issues/31) and
[PR #33](https://github.com/quaat/mdl-racket/pull/33) from branch
`feat/m2-control-flow`; this file remains the full task record. This slice
implements the plan's "later control" work item: function activation
formals, GO, and UNWIND. `sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and patched Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; `scripts/fetch_sources.py`
verified both upstream trees clean before the probes.

## Semantics

**Function activation formals.** Historical `DEFINE` admits an activation
name ATOM between the function name and the formal list:
`<DEFINE F SELF (formals) body>`. The 1977 reconstruction uses this form 14
times (`ROBBER`, `BALLOON`, `SPARSE`, `GET-OBJECT`, `SEARCH-LIST`, ...). The
`"NAME"` and `"ACT"` string markers bind the same activation from inside the
formal list, after any section, with nothing permitted after the bound atom.
The activation exists before formal binding, so RETURN during an AUX
initializer exits the whole call (probe `return-from-aux-init` gives 5).
Explicit `RETURN` to it terminates the call from any depth, including called
functions, and unwinds intervening PROGs; explicit `AGAIN` re-runs the body
without re-binding formals or AUX locals. Bare `RETURN`/`AGAIN` never target
function activations — Confusion's LASTPROG lookup only sees PROG/REPEAT
frames, so a bare RETURN in a self-activation function with no PROG errors
("No activation in RETURN"). The Racket runtime marks frames with a kind and
the bare-transfer resolution skips function frames.

**GO.** The MDL manual's
[chapter 10](https://mdl-language.readthedocs.io/en/latest/10-looping/)
defines `<GO atom>`: top-level ATOMs in a PROG or REPEAT body are labels,
skipped in normal flow, and GO resumes at the expression following the label
in the immediately surrounding PROG or REPEAT of the current function; a
missing label errors. **The pinned Confusion has no GO and no TAG at all**
(probes `go-unbound` and `tag-unbound` return `UNBOUND-VARIABLE` in apply of
form; Confusion's `macros.hpp` marks `MDL_TYPE_TAG` unimplemented), so this
slice follows the manual like the ROT precedent in ADR-0011. TAG values,
which the manual documents for cross-function GO, remain unsupported and
fail explicitly. Bare atom nodes also carry number and `#` reader tokens in
this reader, so only non-numeric atom names become labels.

**UNWIND.** The manual's
[chapter 16](https://mdl-language.readthedocs.io/en/latest/16-errors-frames-etc/)
defines `<UNWIND stdexpr errexpr>`: evaluate stdexpr and return its value;
if a nonlocal return crosses below the UNWIND frame, evaluate errexpr in the
UNWIND's environment, ignore its value, and complete the transfer. Normal
completion never runs the cleanup, and a transfer to a frame inside the
guarded expression does not trigger it (probe `unwind-inner-prog-normal`).
The Racket runtime implements this with a flagged dynamic-wind, so cleanup
runs for RETURN/AGAIN transfers and errors alike.

## Deviations

- GO has no reference implementation; its semantics are manual-based and its
  cases have no Confusion differential. TAG is unsupported in both.
- Confusion validates malformed formal lists at call time and kills the
  process; this runtime rejects the same shapes at compile time (carried
  over from the formals slice). `atom-after-name` in Confusion reports
  "Unexpected ATOM in formal argument list" at call time.
- **Superseded by ADR-0051 (issue #139, 2026-11-23).** The bullet below
  misread the probe: at error level 2 the manual also runs no cleanup, and
  Confusion runs it after ERRET. The runtime now skips cleanups for raised
  errors; see `docs/evidence/M3/I139-UNWIND.md`. Historical text follows.
- **Confusion does not run UNWIND cleanup on errors**: the
  `unwind-cleanup-on-error` probe shows `,M2-C` still 0 after the error
  REPL, because Confusion's `mdl_error` jumps directly to the initial frame
  instead of unwinding through UNWIND frames. The manual's FLOAD example
  documents cleanup on ERRET-below-UNWIND, and errors in MDL-10 are nonlocal
  returns, so the Racket runtime follows the manual and runs the cleanup on
  errors too. This is a recorded reference deviation.
- The `"BIND"` and `"CALL"` formal markers remain unsupported and fail at
  compile time; the FSUBR `BIND` is a separate Confusion PROG variant that
  is out of scope for this slice.

## Commands and results

| Command | Exit | Observed result |
|---|---:|---|
| `scripts/fetch_sources.py` | 0 | Two locked commits verified; upstream trees clean |
| `make test` before implementation (Racket half) | 0 | 403 Racket checks on the base commit; new `tests/control_test.rkt` aborted red on `DEFINE requires a parenthesized formal list` |
| Python tests before implementation | 0 | 13 passed |
| `make test` final (Racket half) | 0 | 455 Racket checks at `a74b6c6` (403 existing + 39 control + 13 new core invariants); three pre-existing checks that asserted NAME/ACT were unsupported were updated to BIND/CALL, which remain unsupported |
| `make test-racket` after both review fixes (rebased branch) | 0 | 465 Racket checks (408 from PR #32 with its PUTREST fix + 39 control + 13 core + 5 octal-label checks) |
| Python tests final | 0 | 13 passed (same sandbox environment note as FORMALS.md) |
| `scripts/check_1977_sources.py` | 0 | 36 parsed, 0 failed, 4 non-text; frozen M0 sweep restored afterward |
| `scripts.mdl_probe --cases docs/evidence/M2/control-cases.json` | 0 | 16/16 successful probes, exit 0, empty stderr |
| `scripts.mdl_probe --cases docs/evidence/M2/control-error-cases.json` | 1, expected | 7 error observations: bare-RETURN without PROG ("No activation in RETURN"), stale self-return ("Tried to jump to frame not on stack!"), GO and TAG unbound, atom-after-name, duplicate formal, and the UNWIND-on-error case showing Confusion skipping the cleanup |
| `scripts.reference_runner.py capture` | 0 | Five turns, `complete=true`, `error=null` |
| `scripts.mdl_probe --cases tests/scenarios/primitives.json` | 0 | Twelve baseline expressions |
| Saved-suite reproduction script (this report) | 0 | All 65 saved M2 success cases (9 prog, 5 repeat, 11 activation-target, 24 formals, 16 control) and 27 expected-error cases reproduce exactly |
| Golden comparison (excluding `captured_at`, `engine_sha256`, banner timestamp) | 0 | `M2 control slice reference and golden comparisons PASS` |
| `git diff --check` | 0 | No whitespace errors |

Environment notes: identical to FORMALS.md — the sandbox hides the host
Python 3.13 and Racket user-directory, so the Racket half ran with
`PLTCOLLECTS` and the Python half under system Python 3.9.2 with the
repo-local pinned wheels in untracked `.sandbox-pydeps/`. The pinned
Confusion binary was not rebuilt (SHA unchanged). Racket 7.9 [bc].

Hashes: Confusion binary SHA-256
`2c58ef023d2ac306bdf661ee0afc0123eef94a8608c108a36ddc2e8808ab4d95`;
reconstructed game image SHA-256
`92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6a1b0ffb7a4`;
approved M0 golden SHA-256
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
Focused probe inputs are fixed with no time or randomness.

## Supported and unsupported

## Post-review fix

The Codex review of PR #33 (P1) found that the PROG/REPEAT label predicate
excluded only decimal-prefixed and `#` tokens, so an octal literal like
`*10*` was classified as a label — `<PROG () 1 *10*>` returned 1 instead
of 8, and a malformed token like `*89*` was silently skipped instead of
reaching `mdl-constant`'s explicit invalid-octal error. Label detection now
shares one atom-token classification with constant compilation covering
decimal, FLOAT, scientific, octal (including malformed), and `#` reader
tokens. Fix commit `fbc2ddb` adds five regression checks
(`tests/control_test.rkt`).

Supported: the leading activation ATOM and `"NAME"`/`"ACT"` markers; explicit
RETURN/AGAIN to a function activation from any depth; AGAIN re-running the
body without re-binding; the activation existing during auxiliary
initialization; bare transfers skipping function frames; GO to top-level
labels in PROG/REPEAT of the current function, with labels skipped in normal
flow; UNWIND cleanup on transfers and errors with normal completion
untouched; TUPLE/ARGS/OPTIONAL/AUX combinations with activation formals.
Unsupported and failing explicitly: TAG values, `"BIND"`/`"CALL"` markers,
the FSUBR `BIND`, quoted formals, GO across a function boundary, GO label
search from an AUX initializer (no active position), malformed formal-list
ordering at compile time, and GO with a non-ATOM label.

No game rule, upstream source, public license, deployed service, or GPLv3
Confusion code changed; no evaluator endpoint was exposed. Next: the macro
and loader slices (DEFMAC expansion and cross-file loading with initial
original source definitions), then the M2 integrated gate.
