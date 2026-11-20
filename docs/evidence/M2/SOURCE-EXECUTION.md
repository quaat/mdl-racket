# M2 source execution inventory — integrated G3 still open

**G3 NOT RUN.** Current state (2026-11-20, D5 branch `feat/m2-atom-props`
at `a3ce79f`, `main` `419fc5c`): slices D1–D4 are merged (`#DECL`
declarations, SEGMENT evaluation, structured declaration patterns, the
`MUDDLE` interpreter global) and D5 atom-property `PUT`/`GET`
associations are implemented on this branch ([issue
#53](https://github.com/quaat/mdl-racket/issues/53), evidence in
[`ATOM-PROPS.md`](ATOM-PROPS.md)). With D5, the full pinned
`77loadall.mud` load exits 1 after **twenty-four completed
expressions** — `81prim.mud` loads in full *and* `77defs.mud`
expressions 1–14 execute, including `<NEWTYPE NOFFSET WORD>` and the
historical `<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>` — and stops at
`77defs.mud` expression 15, the `<NEWSTRUC ROOM VECTOR ...>` at line 37,
whose *original source-defined* `NEWSTRUC` (an `81prim.mud` bootstrapped
function) calls `EMPTY?`, an unimplemented MDL primitive (stage `execute`,
diagnostic `mdl-eval: unassigned or non-applicable MDL operator EMPTY?`).
The pinned Confusion reference loads the entire chain to `DONE` — that
full-chain transcript is the concrete parity target. The G2
[`VFLOAD` partial-source probe](HISTORICAL-VFLOAD.md) remains the D1-era
record. The current barrier is reproduced with
`racket scripts/mdl_load.rkt --source-root .cache/upstream/mdlzork/mdlzork_771212/patched_confusion --entry 77loadall.mud --report artifacts/m2/source-load.json`.

| Source | Definitions loaded | Invoked and verified | Blocked or untested |
|---|---|---|---|
| Pinned reconstructed `77loadall.mud` SHA256 `389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa` | `VFLOAD` from byte-exact first form in an explicit PARTIAL probe | `VFLOAD` on a one-form controlled file; output, empty FALSE return and global value verified against pinned Confusion | Remaining 12 forms deliberately unexecuted in the probe; full load enters `81prim.mud` and stops at form 3 |
| Pinned reconstructed `81prim.mud` SHA256 `8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571` | **All eight forms load** (D2+D3): `MSETG` and `PSETG` install with their original declarations | `MSETG` invoked with a fresh ATOM and FIX `3`: returns `T`, leaves the global at `3`, sets its manifest, and rejects a non-ATOM first argument at the declaration boundary; `PSETG` invoked with a valid ATOM advances through its `SETG` and `PURE-LIST` initialization and stops explicitly at `<MEMQ .FOO .PL>` (no `MEMQ` primitive yet) | None within this file; the chain's next blocker is downstream in `77defs.mud` |
| Pinned reconstructed `77defs.mud` | Expressions 1–14 execute in the shared session (D5): `<NEWTYPE NOFFSET WORD>`, the `<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>` declaration property (stored without global assignment; `DECL?` consults it), and DEFMAC forms `TRNN`/`RTRNN`/`RTRZ`/`TRC`/`TRZ`/`TRO`/`RTRO` | The `RAPPLIC` `DECL` association is installed and read back byte-exactly; `TYPE`/`PRIMTYPE` of the atom are unchanged | Expression 15 `<NEWSTRUC ROOM VECTOR ...>` (line 37) fails in `execute` at `EMPTY?` inside the original `NEWSTRUC` bootstrap; expressions 16+ untested |
| `77makstr.mud`, `77patch.mud`, later files | None in a coherent session | None | Independent first barriers are listed in [`SOURCE-READINESS.md`](SOURCE-READINESS.md); full load has not reached them |
| Later reconstructed source files and archival originals | None | None | Not tested for execution through this loader |

The source lock is MITDDC/zork
`d94501340842e006791fce0757dc0043b8ec8916` and heasm66/mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`. The archive, playable
reconstruction, and Racket runtime remain distinct. No game boot, parser
command, puzzle behavior, RNG parity, or integrated M2 state invariant has
been demonstrated from original source execution.

The first required action after D5 merges is the `EMPTY?` primitive
(called by the original `NEWSTRUC`/`MAPF` bootstraps at the current
barrier, `77defs.mud` expression 15), followed by whatever construct
actual source execution surfaces next. `MEMQ` remains a known candidate
for executing the installed `PSETG`. G3 can pass only when a coherent
ordered sequence of original definitions is installed and exercised with
shared state, atom identity, mutation and control behavior verified.
