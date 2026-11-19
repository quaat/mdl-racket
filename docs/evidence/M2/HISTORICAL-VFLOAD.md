# M2 G2: pinned historical VFLOAD definition

**G2 PASS locally as a partial-source probe; integrated M2 G3 NOT RUN.**
This executes an unmodified definition from the pinned *playable
reconstruction* source. It is not evidence of archival-exact game behavior.

## Source and invocation

The locked reconstructed source is heasm66/mdlzork commit
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; the separate archival
MITDDC/zork commit remains
`d94501340842e006791fce0757dc0043b8ec8916`. `77loadall.mud` SHA256 is
`389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa`.
`tests/historical_vfload_test.rkt` invokes `sha256sum` on the pinned file and
requires that exact hash. It copies all original bytes unchanged into a
disposable authorized source root, checks byte equality, and asks the loader
to execute exactly the first top-level form. The loader reports **PARTIAL**:
one expression completed and 12 deliberately unexecuted. The form is:

```mdl
<DEFINE VFLOAD (X) <FLOAD .X> <PRINTSTRING <STRING .X " loaded">> <TERPRI>>
```

This installs the historical `VFLOAD` definition in a real MDL session.
The test invokes it with the absolute path of a controlled `controlled.mud`
file inside the temporary root. That file contains
`<SETG HISTORICAL-RESULT 27>`. The invocation:

- loads the file through `FLOAD` in the same session;
- leaves `HISTORICAL-RESULT` at 27;
- emits exactly `<fixture-path> loaded\n` to the active output port;
- returns empty MDL FALSE through `TERPRI`.

Invalid `VFLOAD` calls with a FIX path or a missing file raise explicit
errors. The test also checks STRING concatenation and zero arguments,
PRINTSTRING output and return, TERPRI output and return, and wrong-type
rejection. The controlled source file is fabricated and clearly separate
from the pinned historical definition. No historical source bytes are edited.

## Confusion comparison

[`vfload-reference.json`](vfload-reference.json) records six isolated local
Confusion REPL processes. The script
`python -m scripts.probe_vfload_reference` reads the pinned first line at
runtime, creates a temporary one-form source file, and replaces only its
temporary directory spelling with `<TEMP_ROOT>` in the saved evidence. Each
process receives its recorded expression and `<QUIT>`; no RNG input or game
state is involved. The successful original definition call prints:

```text
VFLOAD
<TEMP_ROOT>/controlled.mud loaded
#FALSE ()
27
```

The first line is the REPL's echo of the definition, absent from the Racket
loader API. The following lines agree with the Racket output, return type,
and global state after path normalization. Confusion's missing-file and
wrong-type cases print errors to stderr and enter a new interactive error
level; their process exit code 0 is not a success result. The local loader
raises structured errors instead.

The [MDL manual's `PRINTSTRING` entry](https://mdl-language.readthedocs.io/en/latest/11-input-output/)
specifies a count return; pinned Confusion outputs the string but returns
the original STRING. The Racket subset follows the manual and records this
runtime-equivalence deviation. `VFLOAD` ignores that intermediate return, so
its observed final result agrees. STRING CHARACTER arguments, explicit
output CHANNEL/count arguments, and historical terminal CRLF behavior remain
unsupported. The [semantic ledger](../../SEMANTICS.md) specifies the slice.

## Validation and boundary

Base loader review-fix commit: `88d7b393f9a98ec740e027b2dc331273164a18b4`
(G1 PR #41). Racket 7.9 [bc], Python 3.13.0, pinned native Confusion and
BDW GC 8.0.4 were used locally.

| Command | Exit | Result |
|---|---:|---|
| `racket tests/historical_vfload_test.rkt` before prefix and I/O implementation | 1 | Loader rejected `#:max-expressions` (expected red) |
| `make test-historical` after review fixes | 0 | Source SHAs verified; 23 historical probe assertions pass |
| `make test` | 0 | 570 Racket checks, 13 Python tests after latest G1 merge |
| `.venv/bin/python -m scripts.probe_vfload_reference` | 0 | Six focused Confusion observations saved |
| `make check-source` | 0 | 36 text files parsed, four non-text files excluded, zero failures; generated M0 sweep restored |
| `make reference-build` | 0 | Pinned native build, with `_XOPEN_SOURCE` redefinition warning |
| `make reference-capture` | 0 | Five fixed-input turns captured |
| `make reference-probe` | 0 | Twelve prior primitive cases captured |
| Approved M0 golden comparison | 0 | Five-turn stable fields match after excluding only capture/build metadata and the generated Confusion build-date line |
| `git diff --check` | 0 | No whitespace errors |

The native five-turn input was `west`, `open mailbox`, `take leaflet`,
`inventory`, `score`; no RNG seed was set. The approved golden was not changed.
The digest-pinned Racket 8.10 CI container results are recorded below;
local results alone do not imply CI PASS.

### PR #43 review follow-up (2026-11-19)

The first native CI run on `b9d165e` failed at `make test-historical` because
the minimal Racket image did not have `compatibility-lib`, which provides
`racket/mpair` for the runtime. The next native run on `4291b1d` installed
that library and reached a second missing module: `rackunit` from the
runtime's test submodule at `mdl/runtime/core.rkt:1411:11`. The workflow now
installs both `compatibility-lib` and `rackunit-lib` before the historical
probe. The first code review also found that the local
`raises` helper accepted its own `expected failure` exception as a valid
failure. A new self-check first exited 1 with `expected #t, got #f`; the
helper now records only exceptions thrown by the tested call and raises its
own assertion afterward. The FIX-path, missing-file, STRING and PRINTSTRING
negative cases therefore detect unexpected success.

After bringing in the corrected G1 loader, `make test-historical` exits 0
with 23 assertions, `make test` exits 0 with 570 Racket checks and 13 Python
tests, `make check-source` exits 0 with 36 parsed text files, and the native
build, five-turn capture, 12 primitive probes and six focused VFLOAD probes
all exit 0. The full-load diagnostic still exits 1 at `81prim.mud` form 2
`#DECL` after two completed expressions, as expected. The approved M0
golden's stable fields still match after the documented capture/build
metadata exclusions. The rebuilt local Confusion binary has SHA256
`9d8a07bd0bb88ff89cceb6b257e4752174a1a5831540a531db514e6880a4c305`;
the six-case reference JSON records that binary and unchanged observations.
No RNG seed was set for the fixed five-turn input sequence. The dependency
correction passed [harness CI run 44570235523](https://github.com/quaat/mdl-racket/actions/runs/44570235523)
and [native CI run 44570235452](https://github.com/quaat/mdl-racket/actions/runs/44570235452)
on `b4b28099b59697dce7dc1cfb31f68a2016953a1d`. The latest G1
consecutive-parent correction is merged into this branch and passes locally;
the combined branch's
[harness run 44571763597](https://github.com/quaat/mdl-racket/actions/runs/44571763597)
and [native run 44571763652](https://github.com/quaat/mdl-racket/actions/runs/44571763652)
both passed on `3fd25cbc8202ad62549062e0dfc20425331d7999`.

The reference result is a partial source-execution slice. The full
`77loadall.mud` still reaches `81prim.mud` and stops on its unsupported
`#DECL` at line 3:9. No larger definition sequence, game initialization,
random behavior, or gameplay has been verified. No GPLv3 Confusion code was
copied, mixed-license binary distributed, public license changed, or
network-facing evaluator introduced. G3 must implement declaration semantics
and subsequent source dependencies in separate focused slices before the
integrated M2 gate can be considered. The next action is a `#DECL` semantics
and source-backed validation slice, followed by a fresh full-load attempt.
