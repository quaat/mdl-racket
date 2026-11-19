# M2 source execution inventory — integrated G3 still open

**G3 NOT RUN.** The available source-backed results are the G2
[`VFLOAD` partial-source probe](HISTORICAL-VFLOAD.md) and the M2-D1
declaration slice's `81prim.mud` load probe, not yet a coherent
bootstrap sequence. The full pinned `77loadall.mud` load has been
attempted through the G1 CLI and exits 1 at `81prim.mud` form 3,
line 16:46 — the `!`-splice in the original `PSETG` (the earlier
`#DECL` barrier at form 2 is cleared; `MSETG` now installs and
executes). The [structured report](source-load-first-barrier.json)
records the original `#DECL` barrier; the current barrier is
reproduced with
`racket scripts/mdl_load.rkt --source-root .cache/upstream/mdlzork/mdlzork_771212/patched_confusion --entry 77loadall.mud --report artifacts/m2/source-load.json`.

| Source | Definitions loaded | Invoked and verified | Blocked or untested |
|---|---|---|---|
| Pinned reconstructed `77loadall.mud` SHA256 `389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa` | `VFLOAD` from byte-exact first form in an explicit PARTIAL probe | `VFLOAD` on a one-form controlled file; output, empty FALSE return and global value verified against pinned Confusion | Remaining 12 forms deliberately unexecuted in the probe; full load enters `81prim.mud` and stops at form 3 |
| Pinned reconstructed `81prim.mud` SHA256 `8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571` | The original `MSETG` (form 2) installs through the shared-session loader with its unmodified `#DECL` | `MSETG` invoked with a fresh ATOM and FIX `3`: returns `T`, leaves the global at `3`, sets its manifest, and rejects a non-ATOM first argument at the declaration boundary (see [`DECLARATIONS.md`](DECLARATIONS.md)) | Form 3 `DEFINE PSETG` blocked at compile stage: `!`-splice (`!.PL`) at 16:46, then its compound `<LIST [REST ATOM]>` declaration pattern; forms 4–8 untested |
| `77defs.mud`, `77makstr.mud`, `77patch.mud` | None in a coherent session | None | Independent first barriers are listed in [`SOURCE-READINESS.md`](SOURCE-READINESS.md); full load has not reached them |
| Later reconstructed source files and archival originals | None | None | Not tested for execution through this loader |

The source lock is MITDDC/zork
`d94501340842e006791fce0757dc0043b8ec8916` and heasm66/mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`. The archive, playable
reconstruction, and Racket runtime remain distinct. No game boot, parser
command, puzzle behavior, RNG parity, or integrated M2 state invariant has
been demonstrated from original source execution.

The first required action is the reference-backed SEGMENT slice for the
`!`-splice in `PSETG` (tracked in
[issue #46](https://github.com/quaat/mdl-racket/issues/46)), followed by
the compound `<LIST [REST ATOM]>` declaration pattern that `PSETG` itself
declares. After those slices, retry the pinned full load and inventory the
next actual barrier. G3 can pass only when a coherent ordered sequence of
original definitions is installed and exercised with shared state, atom
identity, mutation and control behavior verified.
