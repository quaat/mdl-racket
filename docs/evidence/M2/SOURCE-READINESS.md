# M2 source readiness — G0 audit (2026-11-18)

**G0 PASS; M2 integrated gate NOT RUN.** This is a read-only audit. No original
source definition was loaded through a reusable loader or exercised as a game.
The machine-readable first-barrier inventory is
[`source-readiness.json`](source-readiness.json). Its compile pass checks each
top-level expression independently; its execution pass starts a fresh MDL
environment for each file and stops on the first failure. These are diagnostic
probes, not a simulation of the complete historical load sequence.

## Provenance and baseline

Repository base: `36df3cefccfb9e382cef113752dcd16457e1e95c`.
`sources.lock.json` pins archival MITDDC/zork at
`d94501340842e006791fce0757dc0043b8ec8916` and reconstructed
heasm66/mdlzork plus GPLv3 Confusion at
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
Local toolchain: Racket 7.9 [bc], Python 3.13.0, GCC and BDW GC 8.0.4.
The CI image pins Racket 8.10 [bc]. `gh auth status` exited 1: the local CLI
token is invalid; GitHub app integration remains usable.

| Command | Exit | Result |
|---|---:|---|
| `git status --short` | 0 | Clean before audit branch |
| `git rev-parse HEAD` | 0 | Base SHA above |
| `gh auth status` | 1 | Invalid CLI token |
| `make doctor` | 0 | Toolchain present |
| `make sources` | 0 | Both pinned source SHAs verified; upstream unmodified |
| `make test` | 0 | 513 Racket checks, 13 Python tests |
| `make check-source` | 0 | 36 selected text files parsed, four non-text excluded, zero failures |
| `make reference-build` | 0 | Confusion built from exported pinned source; `_XOPEN_SOURCE` redefinition warning |
| `make reference-capture` | 0 | Five game turns captured |
| `make reference-probe` | 0 | Twelve reference processes captured |
| Approved golden comparison | 0 | Five turns match after excluding capture/build metadata and generated Confusion build date |
| `racket scripts/audit_source_readiness.rkt` | 0 | Five source files audited; execution failures are recorded in JSON |

The approved golden was **not** changed. The comparison excluded only
`captured_at`, `engine_sha256`, and the generated `This Confusion created ...`
banner line. The native reference is the playable reconstruction, not proof
of archival equivalence. Its transcript is under `docs/evidence/M0/`.

### Racket check-count difference

Per-file `raco test` counts in a disposable copy showed identical counts for
all 16 selected `tests/*.rkt` files. Only `mdl/runtime/core.rkt` differed:
38 on Racket 7.9 versus 33 on Racket 8.10; total 513 versus 508. Five checks
are nested inside outer RackUnit checks. Racket 8.10 reports the outer checks
only. In a disposable `/tmp` copy, reversing one nested assertion caused
Racket 8.10 `raco test mdl/runtime/core.rkt` to exit 1 with `1/33 test
failures`, at its enclosing outer check. Thus the five assertions still run;
the difference is reporting, not missing test discovery or coverage. The
repository and upstream copies were not changed for this experiment.

## First source barriers

Pinned files are in `mdlzork_771212/patched_confusion/` at the reconstructed
source SHA above. Positions below are the original unmodified file positions.
The `77loadall.mud` order is `81prim`, `77defs`, `77makstr`, `81tell-repl`,
`77act1`, `77act2`, `77act3`, `77rooms`, `77patch`, `77np`, `78melee`, `77dung`.

| File (SHA256 prefix) | First barrier | Class and dependency | Smallest next action |
|---|---|---|---|
| `77loadall.mud` (`389da842`) | Form 2, line 2:1, `VFLOAD` call; form 1 `DEFINE VFLOAD` completed | Missing `FLOAD` primitive; nested loads need a shared session | Build controlled loader and route `FLOAD` through it |
| `81prim.mud` (`8d0e9365`) | Form 2, line 2:1 `DEFINE MSETG`, body line 3:9 `#DECL` | Unsupported declaration in compiled function | Research and implement declaration semantics explicitly |
| `77defs.mud` (`566ebcc3`) | Form 1, line 1:1 `AND` reads missing global `MUDDLE`; independent compile pass reaches form 54, line 300:1 `DEFMAC COND-OPEN`, body line 302:9 `#DECL` | Native environment version dependency, then declaration | Determine authentic `MUDDLE` value and implement needed declaration behavior |
| `77makstr.mud` (`49ef04ce`) | Form 1, line 1:1 `DEFINE CEVENT`, body line 2:9 `#DECL` | Unsupported declaration | Same declaration slice |
| `77patch.mud` (`c13c86c8`) | Form 9, line 21:1 `MSETG`; first eight forms execute independently | `MSETG` should come from `81prim`; standalone file lacks its dependency | Load in original order after `81prim` works |

Each SHA256 prefix identifies a full hash in the audit command output:

```text
77loadall.mud 389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa
81prim.mud    8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571
77defs.mud    566ebcc32be9b9226dd7cefd77a517583eebab80a03f452df39e13b85eed734e
77makstr.mud  49ef04ce6c4c22c33c8e98b4ac5803f5ea5efb09d8a42050fb735d4722c004b5
77patch.mud   c13c86c87d59f6e18adb21ced26580ea6520a3af8f7121cd2ad703fb1879a924
```

All five files parse. The earliest failures here are missing primitive,
unsupported declaration, missing native global, and source ordering. Reader
failure and unsupported native functionality are **not yet observed** at
these positions. No form was skipped or made into an implicit false value.

## Source-execution boundary

`compile-program` compiles the whole input before evaluation, so later
unsupported syntax can block earlier top-level side effects. The loader must
compile and evaluate forms sequentially. `mdl-node` has line and column but
no filename; the loader should carry file, expression index and load chain
around each node and exception. The parameterized globals, local frames and
atom space can scope one session; a fresh session needs fresh instances of
all three. Definition values and mutable objects live in those bindings.
Nested `FLOAD` must use the same session, root and load stack. A failed load
can leave completed side effects, so diagnostics must report partial progress.

The [MDL manual's data declaration chapter](https://mdl-language.readthedocs.io/en/latest/14-data-type-declarations/)
describes `#DECL` as a declaration object used with functions and checked by
the interpreter. It cannot be treated as an ignorable reader token. The
[input/output chapter](https://mdl-language.readthedocs.io/en/latest/11-input-output/)
describes `FLOAD` as evaluating a file's expressions. Precise relative-path,
return-value and error behavior still require focused Confusion probes.

## Gate and next action

**G0 PASS:** baseline reproducible, check-count difference explained, and
source-backed first barriers identified. This audit changes no MDL semantics,
game rules, upstream source, license or service exposure. **G1 NOT RUN:** next
implement a local session and root-restricted sequential loader with nested
`FLOAD`, structured partial-failure diagnostics and deterministic fixtures.
Then exercise the unmodified `VFLOAD` definition as the first G2 target.
