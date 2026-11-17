# M2 issue #22 — activation frame hardening

**Local slice: PASS. M2 milestone: NOT YET PASS.** Base main commit:
`c637c9cdb46ebc1403243264eb0d23d5b4960181`. Record the feature commit
and CI result in the issue/PR comment. `sources.lock.json` pins MIT Zork at
`d94501340842e006791fce0757dc0043b8ec8916` and patched Confusion at
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

The [MDL function chapter](https://mdl-language.readthedocs.io/en/latest/09-functions/)
defines an ACTIVATION as one evaluation of a Function and says it becomes
invalid afterward. The [looping chapter](https://mdl-language.readthedocs.io/en/latest/10-looping/)
limits bare RETURN to the nearest PROG/REPEAT in the current function. This
slice gives each unnamed PROG entry a distinct opaque frame with an owner,
escape destination, and live state. A dynamic stack carries active frames;
each DEFINE invocation has a fresh owner. Bare RETURN searches that stack for
the nearest frame owned by its current function. Dynamic unwinding invalidates
the frame on normal return, RETURN, or error. The compiler still rejects named
activations and explicit-target RETURN.

| Command | Exit | Observed result |
|---|---:|---|
| `make doctor` | 0 | Python 3.13.0, Racket 7.9 [bc], BDW GC 8.0.4, and required build tools found |
| `raco test mdl/runtime/core.rkt` after adding frame tests, before refactor | 1 | `mdl-with-prog-activation: unbound identifier` at the first new assertion |
| `raco test mdl/runtime/core.rkt` after refactor | 0 | `14 tests passed` for frame identity, ownership, stale rejection, and cleanup |
| `make test` during refactor | 2 | Compiler parenthesis error at `mdl/compiler.rkt:121`; repaired before final validation |
| `make test` final | 0 | `308 tests passed` in Racket; `13 passed` in Python |
| `make sources` | 0 | Two pinned repositories verified; upstream trees clean |
| `make check-source` | 0 | `{'parsed': 36, 'failed': 0, 'non-text': 4}`; regenerated frozen M0 sweep restored |
| `make reference-build` | 0 | Native Confusion rebuilt with build-only `-include cstdint`; upstream checkout unchanged |
| `make reference-capture` | 0 | Five turns captured at `artifacts/reference/house.json`; `complete=true`, `error=null`, PTY cleanup signal 1 |
| `make reference-probe` | 0 | Twelve baseline expressions probed |
| Fresh `probe_case` comparison against M2 `prog-*` saved reference rows | 0 | Nine successful cases and three expected error observations matched input, result output, stderr, and child exit status |
| M1 gate report's reference/golden comparison script | 0 | `M1 mainline reference and golden comparisons PASS` |

To repeat the focused M2 check after `make reference-build`, run:

```bash
.venv/bin/python - <<'PY'
import json
from pathlib import Path
from scripts.mdl_probe import probe_case
from scripts.reference_runner import EXE, GAME
root = Path('docs/evidence/M2')
for stem in ('prog', 'prog-error'):
    cases = json.loads((root / (stem + '-cases.json')).read_text())['cases']
    saved = json.loads((root / (stem + '-reference.json')).read_text())['cases']
    assert len(cases) == len(saved)
    for case, old in zip(cases, saved):
        new = probe_case(EXE, GAME, case, 20)
        assert (new['input'], new['exit_code'], new['stderr'], new['result_output']) == (
            old['input'], old['exit_code'], old['stderr'], old['result_output'])
    print(stem, len(cases), 'matched')
PY
```

The script in
`docs/evidence/M1/GATE.md` reproduces the approved house and M1 comparison.
The reference cases use fixed expressions with no time or randomness. The
house scenario has fixed commands but no controlled RNG seed; Confusion embeds
build time in its banner. The approved comparison excludes only capture time,
binary hash, and embedded banner time.

The rebuilt Confusion binary SHA-256 is
`480b93b805ce02ffa20ca671b1b91554a0d2d88ec19d58a63850d44bb8095b3e`;
the reconstructed game image SHA-256 is
`92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6a1b0ffb7a4`;
the approved M0 golden SHA-256 is
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
The observed Confusion crash on RETURN during PROG auxiliary initialization
from issue #20 remains a documented deviation; this slice does not alter it.

This refactor adds no MDL surface form. The supported subset remains unnamed
PROG and bare RETURN; nested and called-function behavior is preserved. Named
activations, explicit-target RETURN, REPEAT, AGAIN, GO, UNWIND, complex
function formals, macros, and original-source loading remain unsupported.
Structural equality on cyclic values is a separate issue (#23); it is not
claimed safe here. The M2 integrated gate and original Zork execution remain
open. No game rule, upstream source, public license, deployed service, or
GPLv3 reference code changed. The runtime helpers remain local to Racket and
do not expose evaluator access to a client.
