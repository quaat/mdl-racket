# M2 source execution inventory — integrated G3 still open

**G3 NOT RUN.** The available source-backed result is the G2
[`VFLOAD` partial-source probe](HISTORICAL-VFLOAD.md), not a coherent
bootstrap sequence. The full pinned `77loadall.mud` load has been attempted
through the G1 CLI and exits 1 at `81prim.mud` form 2, line 3:9 `#DECL`.
The [structured report](source-load-first-barrier.json) records both
completed expressions and the loading chain.

| Source | Definitions loaded | Invoked and verified | Blocked or untested |
|---|---|---|---|
| Pinned reconstructed `77loadall.mud` SHA256 `389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa` | `VFLOAD` from byte-exact first form in an explicit PARTIAL probe | `VFLOAD` on a one-form controlled file; output, empty FALSE return and global value verified against pinned Confusion | Remaining 12 forms deliberately unexecuted in the probe; full load enters `81prim.mud` and fails |
| Pinned reconstructed `81prim.mud` SHA256 `8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571` | None verified | None | First STRING expression completes in full-load diagnostic; `DEFINE MSETG` body contains unsupported `#DECL` at 3:9 |
| `77defs.mud`, `77makstr.mud`, `77patch.mud` | None in a coherent session | None | Independent first barriers are listed in [`SOURCE-READINESS.md`](SOURCE-READINESS.md); full load has not reached them |
| Later reconstructed source files and archival originals | None | None | Not tested for execution through this loader |

The source lock is MITDDC/zork
`d94501340842e006791fce0757dc0043b8ec8916` and heasm66/mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`. The archive, playable
reconstruction, and Racket runtime remain distinct. No game boot, parser
command, puzzle behavior, RNG parity, or integrated M2 state invariant has
been demonstrated from original source execution.

The first required action is a focused, reference-backed declaration slice
for `#DECL` in `81prim.mud` and `77makstr.mud`. The MDL manual describes
declarations as checked type constraints, so accepting them without
enforcement would require an explicit compatibility decision and still could
not establish fidelity. After that slice, retry the pinned full load and
inventory the next actual barrier. G3 can pass only when a coherent ordered
sequence of original definitions is installed and exercised with shared
state, atom identity, mutation and control behavior verified.
