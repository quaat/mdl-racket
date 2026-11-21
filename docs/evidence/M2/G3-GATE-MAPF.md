# M2 G3 original-definition execution — branch PASS, 2026-11-20

**Decision:** G3 **PASS on `feat/m2-mapf`**, exit 0 with 59 assertions.
This supersedes the earlier [branch FAIL report](G3-GATE.md) for this
stacked head. It is not a mainline M2 PASS. Required M2 language-surface
audit, CI, review, authorization, and `main` verification remain.

## Contract and observed result

`make test-m2-g3` invokes `tests/historical_g3_test.rkt`. Before executing
it checks SHA-256 for `77loadall.mud`
`389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa`,
`81prim.mud`
`8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`,
and `77defs.mud`
`566ebcc32be9b9226dd7cefd77a517583eebab80a03f452df39e13b85eed734e`.
The test copies the exact bytes to an isolated temporary root, loads the
original `77loadall.mud` chain in one MDL session, and checks 24 PASS events,
zero skipped forms, then the expected first failure at `EMPTY?` in
`77defs.mud` expression 15. The failure is propagated and no later forms
are reported as executed.

In the same surviving session the test verifies:

| Original definition or invariant | Observation |
|---|---|
| VFLOAD | Controlled file returns FALSE, prints the original loaded message, and assigns `G3-VF=17`. |
| MSETG | First/equal calls return T; conflict reports `ALREADY-GASSIGNED` and keeps the old value; declaration rejects a non-ATOM. |
| PSETG | First/repeated calls return 3/4 and leave one `PURE-LIST` member. |
| FLAGWORD | No arguments returns 1; FALSE and ATOM return 2; FALSE+ATOM returns 3 and assigns that ATOM bit value 2; repeated ATOM produces original MSETG conflict and preserves the first bit. |
| RAPPLIC association and DECL? | Original PUT/GET and DECL? hit/miss are observed in the same session. |
| Original TRNN DEFMAC | EXPAND yields the reference's FORM without executing later OFLAGS. |
| Mutable aliasing | Indexed PUT through one global LIST is visible through another. |
| Session isolation | Fresh session has no RAPPLIC association or MSETG definition and has a fresh interpreter MUDDLE value; original session state persists. |

Expected-error checks fail if a negative path unexpectedly succeeds.
The focused [MAPF report](MAPF.md) gives the native comparison for
FLAGWORD and the MAPF/TYPE?/OBLIST dependencies. `sources.lock.json` pins
MIT Zork `d94501340842e006791fce0757dc0043b8ec8916` and
mdlzork/Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
The locally rebuilt native Confusion SHA-256 is
`1d540d2df348479d4740290d4190533b71d94a8308193811b96e52898798b886`.
No RNG or gameplay input is involved.

Local acceptance commands on this branch: `make test` exit 0 (958 Racket,
13 Python), `make test-historical` exit 0 (VFLOAD 23, DECL 21, MSETG and
PSETG), `make test-m2-g3` exit 0 (59 assertions), and `git diff --check`
exit 0. The required native reference CI job now also runs G3 after
provisioning pinned sources. CI and final review remain pending at this
report's preparation time.

## Separate full-loader result and limits

The full loader command in [MAPF.md](MAPF.md) exits 1 after 24 completed
forms at unassigned EMPTY? inside original NEWSTRUC. This is the first M3
source dependency and does not make the tested original-definition G3
scenario pass or fail by itself. G3 does not establish full parser, game
boot, puzzle, RNG, or transcript parity. The broader indirect application
and continuation requirements still need audit and mainline acceptance.

The native reference executes only in local isolated processes. Pinned
upstream source was not edited; no GPLv3 interpreter code was copied and
no raw MDL evaluator was exposed over a network.
