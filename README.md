# MDL on Racket — original Zork preservation harness

> **Status: M0 gate PASS; M1 semantic runtime work is in progress. NOT a
> playable game.** This repository is a starting point for developing an
> MDL-compatible `#lang mdl` in Racket and validating it
> against the reconstructed December 1977 Zork running in Confusion.
>
> The historical game sources and interpreter are **not bundled**. The included
> fetcher retrieves two immutable upstream GitHub commits after network access is
> available. All verification below is local and reproducible, modulo toolchain
> versions and original input/time/randomness.

## Goals

1. Execute original MDL game code, not a newly designed text-adventure engine.
2. Keep the MIT 1977 source unchanged; track reconstructive patches separately.
3. Establish a working Confusion oracle and differential tests before translating
   complex semantics.
4. Build a source-located MDL parser and a `#lang mdl` implementation in Racket.
5. Eventually offer a browser UI; choose a server-backed Racket runtime first,
   and only commit to client-side WASM after feasibility experiments.
6. Keep research evidence in the repository: sources, tests, deviations, decisions,
   and reproducibility details.

## Prerequisites (Linux)

- Racket (the harness targets modern Racket; compatibility must be confirmed on
  your installed release)
- Python 3.11+ and `venv`/`pip`
- Git, GCC/G++, GNU Make, Perl, and `libgc-dev` for the patched Confusion interpreter
- Internet access to fetch source checkouts and Python packages

Ubuntu/Debian example:

```bash
sudo apt-get update
sudo apt-get install -y racket git build-essential make perl libgc-dev python3-venv
```

## Installation

```bash
unzip mdl-racket-zork-harness.zip
cd mdl-racket-zork-harness
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
raco pkg install --auto --link
make doctor
make test
```

`make doctor` reports detected tools and fails only if required commands are
missing. Successful detection does not mean the Racket tests or Confusion
gameplay have passed; run the validation targets explicitly.

`make test` requires Racket and the locally linked Racket package. It tests
**the bootstrap reader/compiler and implemented M1 primitives**, not the original Zork
game. If `raco` reports that the package is already installed, inspect
`raco pkg show` rather than blindly reinstalling it.

### Source checkout and historical reference

```bash
make sources               # downloads/locks original upstream checkouts
make reference-build       # builds native Confusion (may need toolchain fixes)
make reference-capture     # saves a JSON capture in artifacts/reference/house.json
make check-source          # sweeps selected 1977 text files with the Racket reader
make reference-probe       # captures isolated Confusion primitive observations
```

Reference source paths are:

- `.cache/upstream/mit_zork/zork/` — original MIT 1977 release
- `.cache/upstream/mdlzork/mdlzork_771212/patched_confusion/` — playable reconstruction
- `.cache/upstream/mdlzork/confusion_patched/` — patched C++ MDL interpreter

All `.cache` paths are excluded from Git. `sources.lock.json` pins the commits.
The `fetch_sources.py` script refuses to replace modified upstream checkouts.

Once a candidate game implementation exists, it must emit a JSON transcript
in the [documented interchange format](docs/TESTING.md):

```bash
python scripts/compare_transcripts.py \
  artifacts/reference/house.json artifacts/candidate/house.json
```

**No candidate Zork runtime exists yet.** Differential testing is a planned
acceptance gate, not a capability claimed for M0.

## Current implementation and milestone evidence

M0 passed its source, reader, native Confusion, test, and approved golden
transcript gates. The first M1 slice,
[FALSE values and truth operators](https://github.com/quaat/mdl-racket/pull/10),
has merged with passing local and CI checks. The atom/OBLIST slice is under
review; mutable sequence, type constructor, binding, and 36-bit WORD tests
pass locally. The M1 milestone remains open. Reproduce the checks with
`make test`, `make sources`, `make check-source`,
`make reference-build`, `make reference-capture`, and `make reference-probe`.
See the [M0 report](docs/evidence/M0/REPORT.md),
[M1 FALSE report](docs/evidence/M1/REPORT.md),
[M1 atom report](docs/evidence/M1/ATOMS.md),
[M1 sequence report](docs/evidence/M1/SEQUENCES.md),
[M1 type report](docs/evidence/M1/TYPES.md),
[M1 binding report](docs/evidence/M1/BINDINGS.md),
[M1 word report](docs/evidence/M1/WORDS.md), and
[current gate status](docs/STATUS.md) for hashes, outputs, and limits.

- A custom `#lang mdl` reader for a small subset of angle-bracket MDL syntax.
- Source-located AST nodes and a conservative compiler.
- Basic `DEFINE` with simple parameters, `SETG`, `GVAL`, local/global references,
  arithmetic, comparisons, and a few collection forms.
- First-class MDL FALSE literals with mutable payloads, distinct from the `NIL` atom;
  stable literal identity across function calls; value-preserving `NOT`, `AND`,
  `OR`, and `COND` truth behavior; and limited `TYPE` recognition for FALSE and
  ATOM and OBLIST values.
- Identity-bearing ATOM values, named OBLISTs, lookup/insertion/removal, and
  explicit `!-` OBLIST trailers on reader atom literals.
- Mutable LIST, VECTOR, and UVECTOR values with shared `REST` views,
  1-based `NTH`/`PUT`, LIST `PUTREST`, and uniform UVECTOR element checks.
- Type tags and structured `CHTYPE`, with `PRIMTYPE`, `TYPEPRIM`, and `NEWTYPE`
  for the documented subset.
- Atom-keyed local/global values with dynamic parameter frames, `VALUE`
  lookup, and global unassignment on the supported subset.
- Historical 36-bit FIX and WORD behavior for the documented arithmetic,
  octal, bitwise, shift, and bit field subset.
- An intentionally incomplete compatibility runtime.
- Parser smoke tests, compile tests, native Confusion reference scripts,
  transcript comparison, and offline Python harness tests.

**Not supported yet:** complete original MDL syntax, macros, dynamic `.OBLIST`
and full type declarations, actor/room types, GROW/BACK/TOP and STRING/BYTES views,
explicit environments and complex function parameters, general nonlocal
control flow, ROT, PDP-10 FLOAT bit layout, event scheduling,
original parser, gameplay, and client-side web execution.
Unsupported compile constructs fail with errors; the reader's acceptance of a
construct does not imply implemented semantics.

## Working with Codex

Start at [`AGENTS.md`](AGENTS.md), then [`docs/CODEX_START.md`](docs/CODEX_START.md).
The plan and precise gates are in [`docs/PLAN.md`](docs/PLAN.md). Treat
[`docs/STATUS.md`](docs/STATUS.md) as the current source of truth: never label
any untested target as passing.

For each milestone, follow the first unmet gate in `docs/STATUS.md`, record
the evidence, and update this README when the gate result changes.

## Sources, provenance, licensing

- [MITDDC/zork](https://github.com/MITDDC/zork) — original historical sources;
  MIT-0 **to the extent MIT holds rights**.
- [heasm66/mdlzork](https://github.com/heasm66/mdlzork) — reconstructed
  December 1977 game and patched Confusion.
- Confusion is **GPLv3**; the reconstructed gameplay imports later Zork
  material. Review rights before redistributing binaries, sources, or hosted
  commercial variants. The harness MIT-0 license does **not** override upstream
  licenses. See [`docs/PROVENANCE.md`](docs/PROVENANCE.md).

This repository is an independent development scaffold. Local Racket and
Confusion checks, remote CI, and golden review completed on 2026-11-17.
See [`docs/STATUS.md`](docs/STATUS.md) for explicit M0 evidence and M1 limits.
