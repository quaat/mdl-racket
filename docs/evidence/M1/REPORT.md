# M1 issue #3 — FALSE values, local evidence

**Slice gate: PASS locally; PR/CI review pending. M1 milestone: NOT YET PASS.**
M0 closure commit: `690540f233e9ee1c906dcb80b3a41c5c2712024e`
(merged as `d32d35f019682187106cc6f25322a6b6b9a58aa9` in PR #9); M0
implementation merge commit: `899159cd2ebf63b2de53a26317d919413d3e55c9`.
The first M1 implementation commit is
`831f26df45377ea5d4bac739f6e35f6b327736b5`; record the review-fix head
SHA in the PR conversation after push. Locked upstream commits: MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916`, patched Confusion/mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

## Commands and results (2026-11-17)

| Command | Exit | Result |
|---|---:|---|
| `make doctor` | 0 | Python 3.13.0, Racket/raco, gcc/g++, git, make, Perl, pkg-config, BDW GC 8.0.4 found |
| `python3 -m scripts.mdl_probe --cases docs/evidence/M1/false-cases.json --output docs/evidence/M1/false-reference.json` | 1 | Initial system Python lacked `pexpect`; no probe ran |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M1/false-cases.json --output docs/evidence/M1/false-reference.json` | 0 | 13 independent pinned Confusion processes; all exited 0, empty stderr; repeated calls returned `T` for one literal and FALSE for two literals |
| `make test-racket` before implementation | 2 | Reader expected `false` but got `atom`; `mdl-false?` unbound |
| `raco test tests/false_test.rkt` before narrow `TYPE` support | 1 | `TYPE` was unassigned in bootstrap runtime |
| `raco test tests/false_test.rkt` before canonical empty FALSE | 1 | `==? <> <>` returned FALSE, but reference returns `T` |
| `make test-racket` before review fix | 2 | 3/63 failures: the `#lang mdl` fixture and function-return tests reported FALSE for repeated calls to one literal |
| `make test` after review fix | 0 | 63 Racket checks, 13 Python tests |
| `make sources` | 0 | Both locked upstream SHAs verified; working trees clean |
| `make check-source` | 0 | 36 selected text files parsed, 0 parser failures; 4 binary/nontext exclusions. M1 counts in `reader-sweep.json` |
| `make reference-capture` | 0 | Five turns captured at `artifacts/reference/house.json`; complete, process ended with SIGHUP cleanup |
| `make reference-probe` | 0 | Existing 12 primitive cases passed |
| `git diff --check` | 0 | No whitespace errors |

The fresh house capture differs from approved
`docs/evidence/M0/house-golden.json` only in `captured_at`; every other JSON
field matched. Approved M0 golden SHA-256:
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
Confusion executable SHA-256:
`99728037f046ee68fdbb6ef69f44155e3c03f9c0b2b0840fbc218c75024c21e3`;
game file SHA-256:
`92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6a1b0ffb7a4`.
The native game capture's SIGHUP is the existing PTY cleanup behavior, not an
interpreter crash; focused bare REPL probes use `<QUIT>` and exit 0.

## Supported behavior and limits

`<>` and direct `#FALSE (items)` literals produce a dedicated FALSE value.
The direct payload is preserved as data without evaluating it. `NIL` and `T`
remain distinct atom placeholders and are true. `NOT`, `AND`, `OR`, and
`COND` preserve MDL return values and short circuit order. Empty FALSE is
canonical for `==?`; each nonempty source literal retains its identity across
function calls, while separate literals remain distinct. Existing numeric
and equality predicates now return MDL `T` or empty FALSE. `TYPE` handles
FALSE and placeholder ATOM values; other types raise an error.

The reader still omits historical comment associations. FALSE payloads with
forms and other unsupported quoted constructs fail explicitly. Payloads are
not yet mutable MDL LIST views; atom identity/OBLIST, full type system,
36-bit arithmetic, control flow, and game evaluation remain unimplemented.
Existing equality/atom behavior is still bootstrap approximation. The M1
reader sweep has lower node counts in files containing `#FALSE (items)` because
that direct representation is now one AST node; no source bytes changed.

All reference execution remained local. No upstream checkout or game rule was
modified. No GPLv3 source or binary is included in the MIT-0 runtime. Next
action after review is the atom identity/OBLIST slice (issue #4), then mutable
LIST/REST semantics (issue #5) according to `docs/PLAN.md` dependencies.
