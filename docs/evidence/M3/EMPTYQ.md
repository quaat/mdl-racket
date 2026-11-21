# M3 first original-source correction — 2026-11-21

**Slice PASS; full M3 source-load gate INCOMPLETE.** Issue #75 implements
four reference-backed dependencies of the original `NEWSTRUC` definition:
`EMPTY?`, bounded `LENGTH?`, one-argument `ASSIGNED?`, and zero-argument
`ROOT`. The implementation starts from integrated main commit
`31bf8c323d8d479b3d6420cd86ab598986eec4c7`. The PR's final commit
and CI results are recorded on its issue/PR after publication.

## Source and reference

`sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and reconstructed
mdlzork/Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
Verified SHA256: `77loadall.mud`
`389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa`,
`81prim.mud` `8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`,
`77defs.mud` `566ebcc32be9b9226dd7cefd77a517583eebab80a03f452df39e13b85eed734e`.
The rebuilt local reference binary SHA256 is
`cd7bfffe22265b3f63dfd2713330507c53e6182ec9f41ba4aa3d818127252580`.
Confusion is executed locally, one clean process per case, with an
appended `<QUIT>` and no game input or RNG seed. Error-level captures
are deliberately marked unsuccessful by the probe.

| Native corpus | Clean cases | Deliberate errors | Key result |
|---|---:|---:|---|
| `emptyq-{cases,reference}.json` and `emptyq-error-*` | 16/16 | 5/5 observed | Empty and nonempty structures, REST view, typed LIST, TUPLE, circular LIST |
| `lengthq-{cases,reference}.json` and `lengthq-error-*` | 16/16 | 5/5 observed | Bounded circular LIST; negative MAX edge |
| `assignedq-{cases,reference}.json` and `assignedq-error-*` | 9/9 | 4/4 observed | Local versus global, unassigned shadow, AUX |
| `root-{cases,reference}.json` and `root-error-*` | 5/5 | 1/1 observed | Identity of seeded root OBLIST and COMPILE miss |

The native corpus files are all in this directory. Semantics and the
Confusion/manual negative-MAX deviation are documented in
[`docs/SEMANTICS.md`](../../SEMANTICS.md). Optional `ASSIGNED?` ENV is
explicitly unsupported, not silently ignored.

## Red to green and commands

Before each implementation, `TMPDIR=/tmp raco test` on the focused file
exited 1 at an unassigned operator (`EMPTY?`, `LENGTH?`, `ASSIGNED?`,
`ROOT`). After the first EMPTY? implementation, the circular LIST case
exited 1 with `mdl-list: cyclic LIST`; checking the first cell fixed that
case. Final focused files pass 60 checks. Run from the repository root:

```bash
make reference-build
make test
make m2-check
make m3-source-progress
git diff --check
```

`make reference-build` exited 0 on the integrated baseline. `make test`
exits 0: 1,046 Racket checks and 22 Python tests. `make m2-check` exits
0 with the same offline suite, historical VFLOAD 23 and DECL 20,
original MSETG/PSETG paths, G3 58 assertions, 12 native primitive
probes and five-turn native capture. `make m3-source-progress` exits 0
as a validated partial observation: 36 historical text files parsed,
four classified nontext, 26 original top-level forms completed, two
beyond the accepted M2 prefix, and zero skipped. The raw full loader
subprocess exits 1 at `77defs.mud` expression 17, line 66, execute
stage: current `NEWTYPE` expects two arguments but receives three. The
machine-readable snapshot is
[`source-progress-emptyq.json`](source-progress-emptyq.json). `git diff
--check` exits 0. Racket is 7.9 bc, Python 3.13, BDW GC 8.0.4.

This is source execution progress, not a complete original load,
initialization or Racket gameplay comparison. The approved M0 native
golden is not used as a Racket game parity assertion. Confusion's
GPLv3 code remains an isolated reference; no upstream bytes, public
license, or exposed evaluator were changed. The next focused task is
the reference-backed three-argument `NEWTYPE` signature in original
`77defs.mud` ([issue #76](https://github.com/quaat/mdl-racket/issues/76)),
then another unchanged-loader measurement.
