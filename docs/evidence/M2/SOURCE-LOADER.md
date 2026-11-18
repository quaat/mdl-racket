# M2 G1 source loader (2026-11-18)

**G1 PASS; M2 integrated gate NOT RUN.** The loader is a local library and
command-line diagnostic tool. It does not expose an evaluator over a network.
The initial source execution report is
[`source-load-first-barrier.json`](source-load-first-barrier.json).

## Scope and provenance

Base audit commit: `3658dd8f2bf61d82b2a0132f62c8c527ef808cab`
(G0 PR #39). This slice changes no pinned source or game rule. The source lock
still pins MITDDC/zork at `d94501340842e006791fce0757dc0043b8ec8916`
and reconstructed mdlzork/Confusion at
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
The executed `77loadall.mud` SHA256 is
`389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa`;
the nested `81prim.mud` SHA256 is
`8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`.

`mdl/loader.rkt` owns one MDL session's globals, local root frame, atom/type
space and execution records. Each top-level node is read, compiled and
evaluated before the next. `FLOAD` calls the same loader in the active session. The
source root is explicit; traversal, symlink escapes, cycles and excessive
depth fail. The first failure is a structured record with file, exact node
line/column, expression index, load chain, stage, classification and original
exception. Earlier side effects remain after failure; no transaction or
rollback is claimed. A new session starts with fresh mutable MDL state.

## Red-to-green and validation

The new `tests/loader_test.rkt` first failed with exit 1 because
`mdl/loader.rkt` did not exist. After implementation, its first execution
found a symlink-containment gap: `simplify-path` did not resolve the final
link. The loader now resolves every path component before containment checks;
the symlink and directory-link regressions pass. The initial `make test`
failed with nine stale compiled test modules after parser exports changed.
`scripts/test_racket.sh` now compiles the reader, compiler, language modules
and tests before running them; the full suite then passed. No test was
disabled or excluded.

| Command | Exit | Observation |
|---|---:|---|
| `raco test tests/loader_test.rkt` before loader | 1 | Missing loader module (expected red) |
| `raco test tests/loader_test.rkt` after review fixes | 0 | 48 checks pass |
| `make test` before stale-bytecode fix | 2 | Nine module instantiation mismatches, unrelated to MDL evaluation |
| `make test` after review fixes | 0 | 561 Racket checks, 13 Python tests |
| `racket scripts/mdl_load.rkt --source-root /tmp/mdl-loader-cli-fixture --entry ok.mud --report /tmp/mdl-loader-cli-success.json` | 0 | Two expressions completed; status PASS |
| `racket scripts/mdl_load.rkt --source-root .cache/upstream/mdlzork/mdlzork_771212/patched_confusion --entry 77loadall.mud --report artifacts/m2/source-load.json` | 1 | Two expressions completed; status FAIL at unmodified `81prim.mud` form 2, line 3:9 `#DECL` |
| `make sources` | 0 | Both locked upstream commits verified, without source edits |
| `make check-source` (first run) | 2 | Stale compiled `mdl_check.rkt` import after parser exports changed; generated M0 sweep was restored |
| `make check-source` (after conditional `raco make` in target) | 0 | 36 text files parsed, four non-text files excluded, zero failures; generated M0 sweep was restored |
| `make reference-build` | 0 | Native pinned Confusion rebuilt; `_XOPEN_SOURCE` redefinition warning |
| `make reference-capture` | 0 | Five game turns captured locally |
| `make reference-probe` | 0 | Twelve existing primitive cases captured |
| Approved M0 golden comparison | 0 | All stable fields match across five turns; excluded only `captured_at`, `engine_sha256`, and generated Confusion build-date text |
| `git diff --check` | 0 | No whitespace errors |

Toolchain: Racket 7.9 [bc], Python 3.13.0, GCC with BDW GC 8.0.4.
CI uses the existing digest-pinned Racket 8.10 [bc] container; its result
belongs to the review PR and is not claimed here before it runs. The approved
M0 golden was not updated. No RNG seed was set for the fixed five-turn game
capture; input was `west`, `open mailbox`, `take leaflet`, `inventory`, `score`.

### PR #41 review follow-up

The independent review found two valid bugs. A final symlink could point to
a path with another symlink in an intermediate component, permitting a file
outside the root to be opened. A file-wide parse also caused a later malformed
form to prevent earlier valid forms from executing. New regressions first
reproduced each problem. The path resolver now replays every symlink target
component before checking containment. The parser exposes a one-node reader,
and the loader reads, compiles and evaluates each node before reading the next.
Tests verify that an indirect escape is rejected without executing the
outside file, that a valid prefix survives a later reader error, and that an
earlier runtime error wins over a later parse error.

The initial native CI run failed before the reference build because the
minimal Racket image lacks `raco make`; G1's unconditional precompile step in
`make check-source` was wrong for that image. The target now precompiles only
when the command exists, while the fresh CI checkout can interpret the
reader sweep directly. The harness CI job passed on the initial PR commit;
the native job and both review fixes require a new CI run on the follow-up
commit. No gate is claimed from the failed native job.

The fixture for the successful CLI run was two unmodified test commands,
`<SETG CLI-VALUE 7>` followed by `<+ ,CLI-VALUE 3>`. The pinned source run
completed the original `VFLOAD` definition and the first STRING expression
of `81prim.mud`. It then stopped on unsupported `#DECL`. This is genuine
partial source execution, **not** an integrated M2 or game boot result.

### Pinned Confusion FLOAD probes

With the locally built pinned Confusion REPL and disposable `/tmp` files,
`<FLOAD "/tmp/mdl-fload-probe.mud">` returned `"DONE"` (exit 0, empty
stderr). A separate repeat file incremented `REPEAT-COUNT`. The exact REPL
input `<SETG REPEAT-COUNT 0>`, two successive
`<FLOAD "/tmp/mdl-fload-repeat.mud">` calls, then `,REPEAT-COUNT` produced
`0`, `"DONE"`, `"DONE"`, `2` (exit 0, empty stderr), confirming re-execution.
A missing file printed `Couldn't open file in
FLOAD` to stderr and entered another REPL error level despite process exit 0.
A file that set a global to 23 before an unknown operator left that global at
23 after the error. `<FLOAD 5>` produced `NAME1 arg to OPEN/CHANNEL must be
string` on stderr. The local loader reports errors structurally and exits
nonzero from its CLI; it does not reproduce Confusion's interactive error
level. Confusion resolved a relative nested file against its process working
directory in a focused probe. The loader deliberately uses the containing
source directory and enforces the authorized root. The
[semantic ledger](../../SEMANTICS.md) records this path-policy deviation.

## Capability boundary and next task

Supported: sequential compilation/evaluation of the existing MDL subset,
shared session state across files, nested/repeated `FLOAD`, source-relative
resolution, local `FLOAD` STRING result, and structured partial failures.
Unsupported: `#DECL`, full historical filesystem/channel behavior,
game-specific native globals such as `MUDDLE`, later historical primitives,
game initialization and gameplay. No archive or GPLv3 Confusion source was
copied into the MIT-0 runtime. No mixed-license binary was distributed.

The next slice is G2: execute and invoke the unmodified `VFLOAD` definition
from `77loadall.mud` with controlled source input. It requires focused
`PRINTSTRING`, `STRING` and `TERPRI` behavior plus reference comparison.
Keep the integrated G3 M2 gate open until a coherent original-definition
sequence is exercised and verified.
