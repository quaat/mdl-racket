# M3 eager AND? and original MSETG side effects — 2026-11-21

**Issue #80 slice PASS; full M3 source-load gate INCOMPLETE.** Branch
`feat/m3-andq` starts from merged main commit
`ee00fa54892af5461583b97b085542e6b86847fc`. The final
implementation commit and CI runs are recorded on its PR.

## Provenance and reference

`sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and
mdlzork/Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
Verified SHA256: `77loadall.mud`
`389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa`,
`81prim.mud` `8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`,
and `77defs.mud` `566ebcc32be9b9226dd7cefd77a517583eebab80a03f452df39e13b85eed734e`.
The local native binary SHA256 is
`cd7bfffe22265b3f63dfd2713330507c53e6182ec9f41ba4aa3d818127252580`.

The [MDL manual §8.2.3](https://mdl-language.readthedocs.io/en/latest/08-truth/)
says AND? is a SUBR: all arguments are evaluated before truth is
tested. Seven clean local Confusion cases in
[`andq-reference.json`](andq-reference.json) cover zero arguments,
last-value return, zero as true, first-FALSE payload, eager SET side
effects and MSETG definitions from unchanged `81prim.mud`. The
separate deliberate late-error case in
[`andq-error-reference.json`](andq-error-reference.json) enters the
native error level even after an earlier FALSE; the probe marks this
`ok=false` by design. Inputs are in the matching `*-cases.json` files.
Each native case used a separate local process with appended `<QUIT>`;
no game input or RNG seed was involved.

The new runtime builtin uses the existing SUBR dispatcher, which
evaluates every argument left to right before invocation. It returns
the first FALSE value with its payload, the final value when all are
true, or session T with no arguments. The short-circuit AND compiler
path is unchanged.

## Exact-source assertion and command evidence

`TMPDIR=/tmp raco test tests/andq_test.rkt` initially exited 1 at
unassigned AND?; after implementation it exits 0 with nine checks.
`make test-m3-andq` verifies the three source SHAs, copies their exact
bytes into a disposable isolated root, loads original `77loadall.mud`
expression 1, complete `81prim.mud`, and `77defs.mud` expressions 1–28
in one session. It asserts all five original MSETG effects:
`OFLAG=1`, `OVERB=2`, `OSLOT1=3`, `OPREP=4`, `ONAME=5`. The bounded
regression deliberately leaves 68 later `77defs.mud` expressions
unexecuted; the unchanged full loader is measured separately and
skips zero. The first test run reported a RackUnit failure despite a
zero process exit because it used `racket`; switching to `raco test`
made failures fatal. Its first raco run exited 2 because raco changed
the working directory; a module-relative source root fixed that. The
final target exits 0 with 21 checks and the five-global assertion.

`make test` exits 0 with 1,086 Racket checks and 22 Python tests.
`make m2-check` exits 0 with original VFLOAD 23, DECL 20,
MSETG/PSETG, G3 58, 12 native primitive probes and five-turn native
capture. `make m3-source-progress` exits 0 after its new exact-source
regression: 36 historical text files parsed, four nontext, 70
completed original forms, 46 beyond the accepted M2 prefix, zero
skipped. The underlying unchanged full loader exits 1 at
`77defs.mud` expression 61, line 338, compile stage: quoted OPTIONAL
formal with a default is unsupported. The report is
[`source-progress-andq.json`](source-progress-andq.json).
`git diff --check` exits 0. Reproduce after `make reference-build`:

```bash
make test
make m2-check
make test-m3-andq
make m3-source-progress
git diff --check
```

Relevant local versions: Racket 7.9 bc, Python 3.13, BDW GC 8.0.4.
The next source-backed task is
[issue #82](https://github.com/quaat/mdl-racket/issues/82), the quoted
OPTIONAL default in original TAKE-OBJECT. Full source load, game
initialization and Racket gameplay parity remain unverified. No
upstream bytes, GPLv3 code, public license or exposed evaluator
changed.
