# Source provenance, patch discipline, and rights

## Immutable upstream inputs

Exact references are in `sources.lock.json`, verified as upstream GitHub commit
SHAs at starter creation. The installer checks out precisely these commits
under `.cache/upstream/` and refuses to overwrite local edits.

- `MITDDC/zork` — recovered archival 1977 MDL source, README, and historical
  binary artifacts. MIT license text grants rights **to the extent MIT holds
  them**. It should not be construed as an absolute chain-of-title guarantee.
- `heasm66/mdlzork` — reconstructed 1977 playable variant. Uses some material
  from 1978/1981 and a patched `Confusion` MDL interpreter.
- Confusion source is marked GPLv3. Do not copy Confusion code into the
  harness's permissively licensed modules without independent review.

## Reconstructed-vs-archival differences

See upstream `mdlzork_771212/README.md` for its change-by-change notes,
including missing combat code filled by a later source, MDL compatibility
changes, and a parser defect that otherwise impedes completion.

For the pinned December 1977 target, the following inventory separates the
archival source from the playable Confusion reconstruction. It summarizes the
upstream notes at commit `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`;
individual edits have not been independently re-adjudicated against a PDP-10
runtime.

| Area | Archive → playable reconstruction | Classification |
|---|---|---|
| Missing modules | `81prim.mud` comes from 1981, `78melee.mud` from 1978, and `81tell-repl.mud` replaces TELL | Later-source substitution; not archival exactness |
| MDL syntax and Confusion compatibility | `OFFSET` becomes `NOFFSET`; `#ROOM`, `#OBJECT`, `#EXIT` and related typed-brace forms become callable forms; escaped control characters become `<ASCII ...>` | Interpreter compatibility changes, not proof of identical evaluation |
| World flags and additions | `77defs.mud` adds flag testers; `77patch.mud` adds new definitions; `77dung.mud` adds `IN!` and `OUT!` actions | Playable reconstruction with possible behavioral effects |
| Parser rule | `77np.mud` changes an `OR` to `AND` in the `CAN-TAKE?`/`NO-TAKE` check; upstream notes this avoids an unwinnable boat case | Deliberate puzzle-rule correction; behavioral delta |
| Action and room code | `77act1.mud` changes an orphan-object `PUT` target; `77rooms.mud` adjusts save/error handling and input reads | Potential behavioral deltas requiring scenario validation |
| Source formatting | CRLF conversion and removal of form-feed/NUL padding in several reconstructed files | Transport/reader delta; presumed nonsemantic, not independently proved |
| Startup image | `SAVEFILE/ZORK.SAVE` is the reconstructed Confusion game image | Playable reference, not the archival binary |

The M0 golden transcript establishes the reconstructed reference's observed
opening behavior only. Runtime equivalence between archive, Confusion, and
Racket remains a later milestone.

Add future development patches under `patches/` (not implemented in M0), each
with an ADR, tests, changed-file SHA, and provenance. Never edit archival
sources or quietly ship historical data as if newly authored.

### M0 compiler compatibility flag

The native reference build uses `-include cstdint` in `CXXFLAGS` when compiling
the exported copy of pinned Confusion. The unmodified `macros.hpp` uses
`uint64_t` without including its defining header; Ubuntu 24.04's compiler
reports that omission. The flag supplies only a standard declaration and
does not modify `.cache/upstream/`, game data, or Confusion semantics. The
exact flag set is printed by `scripts/build_confusion.sh` and recorded in the
M0 report. No source patch is applied.

## Licensing and redistribution

The new scaffold code in this repository is under MIT-0 (see `LICENSE`).
This license does not extend to source checkouts, their assets, game names,
or any later Infocom releases. Confusion is GPLv3 and, if distributed or
incorporated into other software, may impose additional obligations.
A legal review is recommended before publishing a combined binary/client,
distributing later-version content, or marketing a commercial web app.

A server-side Confusion process and a client-distributed WASM interpreter have
different GPL implications. Avoid making legal claims beyond the actual license
text; record deployment choices before release.
