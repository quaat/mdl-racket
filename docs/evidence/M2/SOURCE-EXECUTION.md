# M2 source execution inventory — pre-merge G3 FAIL

**Pre-merge G3 FAIL.** Stacked corrections for `N=?`, `,.FOO`, and
`ERROR` let original MSETG first/equal/conflict paths execute; the MEMQ
correction lets original PSETG first/repeat paths execute. The current-head
gate run reaches unassigned `MAPF` inside original FLAGWORD
([issue #65](https://github.com/quaat/mdl-racket/issues/65)). Current
state (2026-11-20,
D5 PR #54 head `e6d295d`,
`main` `419fc5c`): slices D1–D4 are merged (`#DECL`
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
| Pinned reconstructed `77loadall.mud` SHA256 `389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa` | `VFLOAD` from byte-exact first form in an explicit PARTIAL probe; the full chain executes its first two top-level forms | `VFLOAD` on a one-form controlled file; output, empty FALSE return and global value verified against pinned Confusion; full chain loads `81prim.mud` before entering `77defs.mud` | The G2 probe deliberately left 12 forms unexecuted; the current full-chain failure is downstream at `77defs.mud` expression 15 |
| Pinned reconstructed `81prim.mud` SHA256 `8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571` | **All eight forms load** (D2+D3): `MSETG` and `PSETG` install with their original declarations | `MSETG` first/equal/conflict paths and `PSETG` first/repeat paths execute with the expected global and PURE-LIST state | `FLAGWORD` invocation reaches unassigned `MAPF`; the chain's separate next loader blocker is downstream in `77defs.mud` |
| Pinned reconstructed `77defs.mud` | Expressions 1–14 execute in the shared session (D5): `<NEWTYPE NOFFSET WORD>`, the `<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>` declaration property (stored without global assignment; `DECL?` consults it), and DEFMAC forms `TRNN`/`RTRNN`/`RTRZ`/`TRC`/`TRZ`/`TRO`/`RTRO` | The `RAPPLIC` `DECL` association is installed and read back byte-exactly; `TYPE`/`PRIMTYPE` of the atom are unchanged | Expression 15 `<NEWSTRUC ROOM VECTOR ...>` (line 37) fails in `execute` at `EMPTY?` inside the original `NEWSTRUC` bootstrap; expressions 16+ untested |
| `77makstr.mud`, `77patch.mud`, later files | None in a coherent session | None | Independent first barriers are listed in [`SOURCE-READINESS.md`](SOURCE-READINESS.md); full load has not reached them |
| Later reconstructed source files and archival originals | None | None | Not tested for execution through this loader |

The source lock is MITDDC/zork
`d94501340842e006791fce0757dc0043b8ec8916` and heasm66/mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`. The archive, playable
reconstruction, and Racket runtime remain distinct. No game boot, parser
command, puzzle behavior, RNG parity, or the full integrated M2 state
contract has been demonstrated from original source execution. The
pre-merge G3 subset has 52 checked observations, but its gate is FAIL.

The next M2 action is the focused `MAPF` correction and a G3 rerun. After
the M2 gate is settled, the next sequential loader dependency is `EMPTY?`
(called by the original `NEWSTRUC`/`MAPF` bootstraps at the current
barrier, `77defs.mud` expression 15), followed by whatever construct
actual source execution surfaces next. `MAPF` is now the confirmed barrier
for executing the installed `FLAGWORD`. G3 can pass only when a coherent
ordered sequence of original definitions is installed and exercised with
shared state, atom identity, mutation and control behavior verified.
