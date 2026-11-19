# Development handoff — MDL on Racket

Durable cross-session state. Update at every meaningful checkpoint; link to
evidence instead of duplicating logs. Last updated 2026-11-19 (M2-D1).

- **Milestone / gate:** M2. G0/G1/G2 PASS; integrated M3-style gate NOT RUN.
  M2 milestone NOT YET PASS.
- **Active issue/PR:** [issue #44](https://github.com/quaat/mdl-racket/issues/44)
  (`#DECL` semantics) on branch `feat/m2-declarations`.
- **Latest integrated commit:** `2267ae9` (merge of PR #43, historical VFLOAD).
- **Implementation status (D1, uncommitted on the branch):** `#DECL` parses,
  compiles, and is enforced in `DEFINE`/`DEFMAC`/`PROG`/`REPEAT` (compiled and
  interpreted); `DECL?`, `GASSIGNED?`, `MANIFEST`, manifest-gated `SETG`; the
  doubled `#DECL #DECL` source form; expression-position `#DECL`.
- **Changed files:** `mdl/parser.rkt`, `mdl/compiler.rkt`,
  `mdl/runtime/core.rkt`, `tests/declaration_test.rkt` (new),
  `tests/historical_decl_test.rkt` (new, `make test-historical`),
  `tests/loader_test.rkt`, `scripts/test_racket.sh`, `Makefile`,
  `docs/SEMANTICS.md`.
- **Tests last executed (2026-11-19, fresh):** full Racket suite 618 passed;
  loader 57; `make test-historical` 23 VFLOAD + 10 declaration assertions;
  Python 13; `git diff --check` clean.
  Loader/historical tests need writable `/tmp` (run outside the per-command
  sandbox); in-sandbox Racket needs `PLTCOLLECTS=":$PWD"`. The smoke CI
  container does not provision `.cache/upstream/`, so pinned-source
  assertions live only in `make test-historical` (reference workflow).
- **First failing source construct:** `!`-splice, `81prim.mud:16:46`
  (`!.PL` in the original `PSETG`), compile stage — then `PSETG`'s compound
  `<LIST [REST ATOM]>` pattern.
- **Known semantic decisions:** attached-declaration enforcement follows the
  manual, not pinned Confusion (Confusion does not enforce); `DECL?` false
  payload follows Confusion (`#FALSE (value pattern)`) over the manual's
  `#FALSE ()`; checking is unconditionally on (`DECL-CHECK` not implemented).
  See `docs/SEMANTICS.md` (M2 D1 section) and
  `docs/evidence/M2/DECLARATIONS.md`.
- **Exact next action:** implement the `!`-splice read construct with
  reference-backed tests, then the `[REST ...]` pattern slice; record each in
  `docs/evidence/M2/`; after `81prim.mud` loads fully, drive several original
  helpers (`MSETG`, `PSETG`) and re-run `77loadall.mud` for the next blocker.
- **Full evidence:** `docs/evidence/M2/DECLARATIONS.md` (slice),
  `docs/evidence/M2/SESSION-RECOVERY-2026-11-19.md` (recovery),
  `docs/evidence/M2/reader-sweep.json` (current sweep; frozen M0 sweep stays
  at `docs/evidence/M0/reader-sweep.json`).
