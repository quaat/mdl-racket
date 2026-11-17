# Architecture / source map

## Two versions of the game

- **Historical original**: MITDDC/zork archive at a pinned commit. This is the
  preservation source of record; it is not modified.
- **Playable reconstructed baseline**: heasm66/mdlzork December 1977 patch set
  at a pinned commit. It includes material from later MDL releases and fixes.

Source-by-source mapping will be tracked in a forthcoming
`docs/semantics/source-map.csv` once corpus analysis completes. The original
and patched variant must never be conflated in claims of fidelity.

## Code layout

```text
mdl/parser.rkt           MDL lexical reader -> source-located AST
mdl/compiler.rkt         small bootstrap translation subset (fail closed)
mdl/runtime/core.rkt     small bootstrap runtime (NOT a faithful full MDL VM)
mdl/lang/reader.rkt      #lang mdl custom language reader
mdl/lang/main.rkt        core Racket bindings for generated code
scripts/fetch_sources.py  pinned immutable upstream checkouts
scripts/build_confusion.sh native reference build
scripts/reference_runner.py interactive PTY capture
scripts/compare_transcripts.py strict diff oracle
scripts/mdl_check.rkt   source parser coverage command
sources.lock.json       exact Git commits of both upstream repos
tests/                  offline Python + Racket tests, scenario corpus
artifacts/              local logs/transcripts/checkpoints (gitignored)
docs/evidence/           curated milestone reports committed to Git
```

## Extension policy

`mdl/parser.rkt` and `mdl/compiler.rkt` are intentionally independent from
Confusion. The native reference is an **oracle**, not a linked library. Future
Racket sessions must have independent global state, a stable game-state format,
and explicit I/O boundaries. Bootstrap `current-mdl-globals` is process-local
and not adequate for production player isolation.

`#lang mdl` uses a custom reader to create a Racket module. Parsing a source
file does not imply that the compiler understands all its forms. The M0
subset is exercised with `tests/fixtures/basic.mdl`.

## Runtime architecture, later

```text
                     original/patched MDL source
                               |
                       Reader / AST / linker
                               |
                       MDL semantic runtime
                    (mutable objects, parser,
                     actors, events, RNG, IO)
                               |
            session service: command -> state + output
                               |
                       web transport API
                               |
                      accessible web terminal
```

The browser service must never accept arbitrary MDL source, and all game
processes must be isolated, resource limited, and incapable of reading
unrelated files. WASM is an explicitly optional later track.
