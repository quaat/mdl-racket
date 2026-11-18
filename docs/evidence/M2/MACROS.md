# M2 local task — DEFMAC expansion and quoted formals

**Local slice: PASS. M2 milestone: NOT YET PASS.** Tracked by
[issue #34](https://github.com/quaat/mdl-racket/issues/34) on
`feat/m2-macros`, based on `a74ed4d` (the merged control slice). The final
slice commit is recorded in the PR; this report describes the tested worktree.
`sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and patched Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`. `make sources` verified
both checkouts clean at those commits.

## Semantics and limits

`DEFMAC` stores a MACRO with PRIMTYPE LIST and returns its name. A macro
call binds raw source arguments, evaluates its body to an expansion, then
evaluates the expansion at the call site. A quoted formal receives the raw
argument; an ordinary formal evaluates in the **caller** frame at binding
time. `"ARGS"` preserves raw remaining arguments and `"TUPLE"` evaluates
them in the caller frame. `FORM` constructs a first-class FORM from evaluated
operands. `EXPAND` performs one macro expansion without evaluating its
result. Interpreted definitions have their own function owner, so bare
RETURN cannot escape a caller's PROG. FORM evaluation also supports an
expansion that defines a later-callable FUNCTION.

The [MDL manual's macro chapter](https://mdl-language.readthedocs.io/en/latest/17-macro-operations/)
says expansion runs in a top-level environment; pinned Confusion observes
caller locals in `macro-sees-caller-local`, which this slice follows. For a
non-macro form, the manual's one-step `EXPAND` contract leaves the form
unchanged; this pinned Confusion build instead evaluates it and prints
`eval top-level form`, a debug-output deviation. Racket validates the full
formal list before application; Confusion reports too few arguments first
for malformed `('X 3)`, an error-order deviation. Compile-time macro
expansion, `APPLY` with quoted formals, declarations, splice/segment
semantics, full environments, cross-file loading, and original game
execution remain unsupported. Unsupported operators and forms fail
explicitly.

## Evidence

| Command | Exit | Result |
|---|---:|---|
| `make sources` | 0 | Both locked commits and clean upstream trees verified |
| `raco test tests/macro_test.rkt` before compiler integration | 1 | `DEFMAC` unassigned; first macro assertion red |
| `raco test tests/macro_test.rkt` before frame fix | 1 | Bare RETURN escaped a caller PROG; new assertion red |
| `raco test tests/macro_test.rkt` before TUPLE fix | 1 | TUPLE argument side effect absent; expected 4, got 0 |
| `raco test tests/macro_test.rkt` before caller-frame fix | 1 | Second argument saw callee formal; expected 3, got 8 |
| `raco test tests/macro_test.rkt` final | 0 | 37 checks pass |
| `make test` final | 0 | 502 Racket checks and 13 Python tests pass |
| `make check-source` | 0 | 36/36 selected text files parse, four non-text files classified separately; generated M0 sweep restored to its committed bytes |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/macro-cases.json --output artifacts/reference/macro.json` | 0 | 25/25 reference cases exit zero with empty stderr |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/macro-error-cases.json --output artifacts/reference/macro-error.json` | 1, expected | Eight deliberate error observations; all saved fields reproduced |
| `make reference-capture` | 0 | Five-turn `house` capture complete; all prompts returned |
| `git diff --check` | 0 | No whitespace errors |

The 21 original success cases matched their saved result and stderr fields
when four new cases were added. All eight saved error observations matched
their saved result, stderr, exit, and success fields. The final 25-case
reference file is `macro-reference.json`; the inputs are in
`macro-cases.json`. Errors are in `macro-error-reference.json` and
`macro-error-cases.json`. Each probe starts a fresh local Confusion process,
sends its fixed input, then `<QUIT>`; no random seed, gameplay input, or
clock-dependent expression is used. The new cases specifically verify
caller-frame evaluation, TUPLE versus ARGS, and a macro-generated DEFINE.

The fresh house capture matches the approved M0 golden for every stable
field, including the five commands and outputs. `initial_output` matches
after replacing only the embedded Confusion build timestamp; `captured_at`
and `engine_sha256` differ as expected. The approved golden SHA-256 is
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
The native interpreter SHA-256 is
`2c58ef023d2ac306bdf661ee0afc0123eef94a8608c108a36ddc2e8808ab4d95`;
game image SHA-256 is
`92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6a1b0ffb7a4`.
Tools: Racket 7.9 [bc], Python 3.13.0. An initial `python3` probe attempt
exited 1 because system Python lacks `pexpect`; rerunning with the pinned
`.venv/bin/python` succeeded. No upstream file or GPLv3 Confusion source
was modified, copied into the runtime, or exposed to a web client.

## Next action

Review the macro slice and then implement the source loader as a separate
M2 task, with a source-order test and a Confusion-backed initial-definition
probe. The M2 integrated gate still requires original definitions to execute
without lost aliasing or continuations.
