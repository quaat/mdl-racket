# M3 interrupt foundation — issue #104

**Scoped Gate A: PASS locally after independent review; Gate B and full M3:
INCOMPLETE.**
Branch `feat/m3-interrupt-dispatcher` starts from main
`5cabf3714074b927881d16142c214e69283e2810`. Source locks are
MIT Zork `d94501340842e006791fce0757dc0043b8ec8916` and
mdlzork/Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
`77rooms.mud` SHA256 is
`e89337af98565292f84cfb10e9239924e99918325c9e1ac39b6bce692f5aff94`.
The candidate commit SHA and CI status belong in the PR and final issue
comment after publishing; this file describes the code being reviewed.

The [MDL manual chapter 21](https://mdl-language.readthedocs.io/en/latest/21-interrupts/)
defines priority dispatch, pending occurrences, interrupt levels, handler
ordering and removal. The implementation adds these to a session-owned
interrupt state. Event sources supply already evaluated arguments through
the same function application path as the rest of the interpreter. Tests
call a host-only event-source API deterministically; this is **not**
evidence of GC event generation. `INT-LEVEL`, `ENABLE`, and `DISABLE` are
available for session-owned headers. Invalid FIXs, foreign headers and
unregistered test events fail explicitly. Unsupported process-targeted
handlers, `DISMISS`, predefined automatic event sources, and `INTERRUPT`
remain explicit limits. No arbitrary evaluator is exposed to clients.

Red-to-green evidence:

- `TMPDIR=/tmp raco test tests/interrupt_dispatch_test.rkt` exited **1**
  before implementation because the test event-source interface did not
  exist. After implementation, the combined interrupt and registration
  focused command exited **0**, **69 checks passed**.
- Independent read-only review found that a handler exception left an
  eligible queued event stuck. The focused regression failed **1/34**
  before an `INT-LEVEL` safe-point fix, then passed. The reviewer found a
  second ordering flaw: after that exception, a new event could run
  before the older queued event. Its regression failed **1/36** with
  actual `(new old)` versus expected `(old new)`, then passed after event
  emission began draining older eligible occurrences first.
- The reviewer also found ten predefined event names that could register
  without sources. Ten strict-error tests failed **10/46** before the guard
  was extended and passed afterward. `"DIVERT-AGC"` remains the documented
  loader-registration exception; its automatic source is unsupported.
- A further retention test failed **1/50**: an older queued callback raised
  while a new occurrence was being reported, causing the new occurrence to
  vanish. Enqueuing before draining preserved the occurrence; the focused
  command then passed all 69 checks. An interpreted handler also retains an
  already evaluated FORM argument without executing its embedded SETG.
- `TMPDIR=/tmp make test` exited **0** with **1,304 Racket checks and 23
  Python tests** after the final focused fix. An earlier full run exited
  **2** due to a two-second timeout in the unrelated fake-reference PTY
  test; the identical 23-test Python suite then exited **0** in 0.98 s,
  and the later full `make test` exited 0. Independent final read-only
  review found no remaining material Gate A issue after the queue-first fix.
- `TMPDIR=/tmp make m2-check` exited **0** on the final files, including
  **1,304 Racket checks, 23 Python tests**, the historical G3 **58**
  assertions, the native **12-expression** primitive probe and the
  **five-turn** reference capture. This preserves the M2 gate; it does not
  establish Racket gameplay parity.
- `TMPDIR=/tmp make m3-source-progress` exited **0** as a partial-progress
  measurement. Its [summary](source-progress-interrupt-foundation.json)
  records `loader_exit: 1`, **433 original forms completed, zero skipped**,
  and first failure `77rooms.mud` expression 16, line 101,
  `mdl-event: unsupported predefined EVENT GC`. `81prim`, `77defs`,
  `77makstr`, `81tell-repl`, `77act1`, `77act2`, and `77act3` complete;
  `77rooms` is partial. Full loading is not verified.

Pinned Confusion's EVENT/HANDLER/OFF/ON stubs return `T`; its INTERRUPT
is unbound. The 12 clean and 2 error-level reference observations remain
in [event registration evidence](EVENT-REGISTRATION.md). Thus the manual
and direct scheduler assertions, rather than these stub outputs, establish
this slice. No RNG or game input was used in the focused checks. There is
no golden game comparison at this stage.
Pinned Confusion's own `mdl_builtin_eval_gc` collects via Boehm GC and
returns `T`; its `BLOAT` implementation labels its values bogus. Neither
matches the manual's reclaimed-word and free-storage return contracts.

The [Racket GC reference](https://docs.racket-lang.org/reference/garbagecollection.html)
documents that `collect-garbage` returns void and memory use is estimated
in bytes. The [MDL storage chapter](https://mdl-language.readthedocs.io/en/latest/22-storage-management/)
requires `<GC>` to return reclaimed MDL words. Racket automatic GC does
not give MDL collection causes or historical allocation timing. This
foundation deliberately retains the `EVENT "GC"` guard. To pass Gate B,
issue #104 needs a verifiable explicit collection path, a defensible return
value, and safe post-collection callback delivery. Automatic collection
parity needs a separate allocation-accounting decision. The current Gate B
is **BLOCKED** by the missing MDL reclaimed-word accounting and automatic
event source; `docs/DECISIONS.md` records three options and recommends a
bounded ledger feasibility probe. Do not treat host
GC alone or deterministic test injection as an MDL GC oracle.

No `.cache/upstream/` source, GPLv3 Confusion code, public license or
network service changed. M0/M1/M2 regressions remain required. The next
action is to design and test an explicit MDL `<GC>` operation with honest
reclaimed-word semantics before allowing `EVENT "GC"` registration.
