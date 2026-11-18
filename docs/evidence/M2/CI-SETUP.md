# M2 infrastructure task — CI Racket setup

**CI task: PASS. M2 milestone: NOT YET PASS.** Tracked by
[issue #36](https://github.com/quaat/mdl-racket/issues/36) and
[PR #37](https://github.com/quaat/mdl-racket/pull/37). Implementation commits
`4625665c591ed80e9c94fa5391cd96271e57d353` and
`ee0779e127ee46aaba28910b751909f98d72cdfb`, based on macro slice
`d828f3aeeacd75abdded10cc5f495a7294e0b21f`. `sources.lock.json` pins
MIT Zork `d94501340842e006791fce0757dc0043b8ec8916` and reconstructed
Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

## Choice and alternatives

The workflows use the [Racket project's Docker
image](https://github.com/racket/docker), in its minimal `racket/racket:8.10-bc`
variant, at
`sha256:8c527e0cca4650a6bdd73f3f73fe203ede6317c82f3f3f33bc861cec981e8b2d`.
The image supplies Racket before the job starts. The harness adds Git and
`compiler-lib`, `rackunit-lib`, and `compatibility-lib`; the native job adds
Git, G++, Make, Perl, and `libgc-dev`. Both still fetch Python packages. The
minimal image manifest is about 64 MB compressed for amd64; the full 8.10 BC
distribution image is about 184 MB compressed. These figures are layer sums,
not measured network bytes. The minimal image requires explicit libraries:
`raco make` needs `compiler-lib`, and the suite needs RackUnit and
`racket/mpair`. The image is maintained by the Racket project; it is not a
Docker Library Official Image.

Other options examined:

| Option | Assessment |
|---|---|
| Ubuntu apt with `--no-install-recommends` | Avoids the recommended [`racket-doc` package](https://packages.ubuntu.com/noble/racket) (36.4 MB in the observed install) but still installs the 104 MB `racket` package and leaves apt/network delay on every run. |
| `setup-racket` plus Actions cache | Could reuse a downloaded distribution across runs, but adds a third-party action and cache invalidation/restore work. No measured pilot here. |
| Full Racket distribution image | Includes more libraries, but its compressed payload is roughly 120 MB larger than the minimal image in the inspected manifests. No CI pilot here. |
| Custom prebuilt GHCR image | Could include test libraries and native tools and save further setup, but requires a build, publication, update, and trust process. Consider only if future run data show the remaining setup costs matter. |

## Measured runs

All times below are wall-clock spans from GitHub Actions job logs, rounded
to the nearest second. They include runner/container setup and cleanup. One
run per configuration is insufficient to estimate a stable speedup.

| Configuration | Run | Outcome | Job span | Setup step |
|---|---|---|---:|---:|
| Ubuntu apt harness | [44349589805](https://github.com/quaat/mdl-racket/actions/runs/44349589805) | PASS | 40 s | Racket apt install 19 s |
| Ubuntu apt native | [44125722256](https://github.com/quaat/mdl-racket/actions/runs/44125722256) | PASS | 84 s | Dependency apt install 45 s |
| Ubuntu apt native, later run | [44349590755](https://github.com/quaat/mdl-racket/actions/runs/44349590755) | PASS | 1006 s | Dependency apt install 971 s |
| Minimal image native pilot | [44353014062](https://github.com/quaat/mdl-racket/actions/runs/44353014062) | PASS | 44 s | Image startup 3 s, native tools 11 s |
| Minimal image harness first pilot | [44353014159](https://github.com/quaat/mdl-racket/actions/runs/44353014159) | FAIL | 28 s | Git absent; source-lock Python test could not launch `git` |
| Minimal image harness final | [44353286644](https://github.com/quaat/mdl-racket/actions/runs/44353286644) | PASS | about 32 s | Image startup 3 s, Git 5 s, Racket libraries 9 s |
| Minimal image native final | [44353286715](https://github.com/quaat/mdl-racket/actions/runs/44353286715) | PASS | about 43 s | Image startup 5 s, native tools 8 s |

The final harness ran `bash scripts/test_racket.sh` successfully (497
RackUnit checks under Racket 8.10 BC), followed by the four-file Python
suite (13 passed). The final native job ran `make sources`,
`make check-source`, `make reference-build`, `make reference-capture`, and
`make reference-probe` successfully and uploaded its evidence artifact.
Its source check used the pinned commits above; the reader result is a parse
sweep, not runtime game execution. Reference capture uses the existing
five-command `house` scenario, with no RNG seed set by this CI change. No new
golden was approved or differential gameplay comparison
performed by this CI change.

## Reproduction and limits

From a checkout with Racket installed and the local package linked:

```bash
make test
make sources
make check-source
make reference-build
make reference-capture
make reference-probe
```

The workflow definitions in `.github/workflows/ci.yml` and
`.github/workflows/reference.yml` are the exact container reproduction
recipes. Locally, `make test` passed with 502 Racket checks under Racket 7.9
BC and 13 Python tests; `bash -n scripts/test_racket.sh` and YAML parsing
also passed. The Racket check count differed between these two versions; its
cause was not investigated, and all selected test files passed in both. The project
continues to support only the documented reader, M1 primitives, and M2
control/formals/macro slices. Original source loading, declarations, general
APPLY/DISPATCH, gameplay, and parity remain unsupported. Unknown MDL forms
continue to fail explicitly.

The image digest prevents the base image from drifting, but apt, Racket
package catalog, Python package index, and action major tags still supply
dependencies at job time. The container runs the native reference only on
the isolated GitHub runner; no evaluator or filesystem access is exposed to
a web client. No upstream checkout was modified, and no GPLv3 Confusion
source entered the MIT-0 runtime. The next M2 task remains original source
loading and initial-definition execution.
