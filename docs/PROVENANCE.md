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

Add future development patches under `patches/` (not implemented in M0), each
with an ADR, tests, changed-file SHA, and provenance. Never edit archival
sources or quietly ship historical data as if newly authored.

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
