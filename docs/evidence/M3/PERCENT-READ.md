# M3 session-aware `%` READ evaluation — issue #94

**Scoped gate: PASS on `feat/m3-read-time-percent`; formal M3 gate:
INCOMPLETE.** Base main commit:
`74effec5744a44f43ae9c6a308b2ab37013ec7b0`. Locked source commits
in `sources.lock.json`: MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916`, mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

The MDL manual §17.1.1 requires `%` evaluation immediately during READ.
Thirteen isolated [pinned Confusion cases](percent-read-reference.json)
confirm ASCII 10 is a CHARACTER, STRING of it is a one-character newline
STRING, read-before-eval ordering, adjacent left-to-right substitutions,
once-only function substitution, quoted LIST identity, nested structure
substitution, and `%<>`. The command
`.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M3/percent-read-cases.json --output docs/evidence/M3/percent-read-reference.json`
exits **0**. Six [deliberate error observations](percent-read-errors-reference.json)
show ASCII out-of-range/type errors, STRING argument errors and an unbound
read-time form. Their same probe command using `percent-read-errors-cases.json`
exits **1 as expected** because the probe tool requires clean stderr.
Both runs use one local process per case, deterministic input followed by
`<QUIT>`, no RNG or game input. Rebuilt native binary SHA256:
`bd70657059954cbb706fe93e8aceb14c64a58f51f227cfa4e69841d7df9ef340`.

The executable reader calls back into the active session immediately after
reading a `%` payload. A session-owned registry retains the resulting MDL
object; the compiler references that object from definitions without
re-evaluating the payload. The syntax-only parser performs no MDL
evaluation. Nested FLOAD uses the same session. Unsupported `%%` fails
strictly; reader-evaluation errors stop with the percent source location.
ADR-0042 records rejected designs and limitations.

`TMPDIR=/tmp raco test tests/percent_read_test.rkt` initially exited **1**:
the first percent-bearing file load returned FAIL and NEWLINE was unbound.
After implementation it exits **0**, 27 focused checks. The new validator
case verifies distinct `read-eval` failure staging. `make test` exits **0**
with **1,187 Racket and 23 Python** tests; `make m2-check` exits **0**
with G3 58, native 12-case primitives, and a five-turn reference capture.
`make reference-build` exits **0** and reports no upstream modification.
`git diff --check` exits **0**. Local versions: Racket 7.9 bc,
Python 3.13.0, BDW GC 8.0.4.

`make m3-source-progress` exits **0** as a validated incomplete-load
measurement. The unchanged Racket loader exits **1** after **188 completed
original forms, zero skipped**, 31 beyond the prior 157-form checkpoint.
It fully loads `81tell-repl.mud`; [summary](source-progress-percent-read.json)
and [raw report](source-load-percent-read.json) include the SHA256 of every
encountered source file. The next failure is `77act1.mud` expression 10,
line 78: unsupported NTH declaration Pattern `[3 ANY]`. PARSED is true;
LOADED, INITIALIZED, INTERACTIVE and SMOKE-PARITY remain false. The
read-time `READSTRING` terminator is constructed, but calling READSTRING,
game initialization and gameplay were not tested as working features.

The requested fresh HTTPS clone exited **128**, `Could not resolve host:
github.com`; the existing checkout and connected GitHub integration both
verified main at the same commit. `gh auth status` exited **1** due an
invalid local token; the connected GitHub integration remained available.
The existing virtual environment and Racket package were used, so
`make install` was not rerun. Source locks passed `make sources` through
the regression targets.

No bytes under `.cache/upstream/`, GPLv3 source, public license, or
network service were changed. The runtime remains an incomplete local
interpreter; it has no exposed REPL service. Remaining risks include
reader table and channel-control semantics, `%%`, Unicode CHARACTER
limits, and later runtime use of READSTRING. The next action is to
review/integrate this slice, then probe NTH declaration repetition in
[issue #96](https://github.com/quaat/mdl-racket/issues/96). Reproduce with:

```bash
make reference-build
TMPDIR=/tmp raco test tests/percent_read_test.rkt
make test
make m2-check
make m3-source-progress
git diff --check
```
