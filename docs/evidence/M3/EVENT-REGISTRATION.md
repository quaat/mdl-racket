# M3 user EVENT/HANDLER registration — issue #102

**Scoped registration slice: PASS on `feat/m3-event-handler`; formal M3
gate: INCOMPLETE.** Base main commit
`8bcb90f3bd5349b2f38db26feb04382c6ff751b5`. Source locks:
MIT Zork `d94501340842e006791fce0757dc0043b8ec8916`,
mdlzork/Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

The [MDL manual chapter 21](https://mdl-language.readthedocs.io/en/latest/21-interrupts/)
defines real IHEADER and HANDLER objects, both VECTOR primitive type.
EVENT associates an enabled IHEADER with a name, HANDLER prepends an
applicable action, and OFF removes a handler or header association while
returning the same object. The runtime now supports these registration
and removal operations for user-defined STRING event names, including
reattachment. The registry is scoped to the MDL session. A cross-session
IHEADER is rejected. Automatic external events, callback dispatch,
process-targeted handlers, and structure mutation of interrupt objects
and `INTERRUPTS` OBLIST associations are unsupported. In particular
`EVENT "GC"` raises an explicit error:
the runtime has no garbage-collection callback source and must not
silently register a handler that never runs.

Twelve [clean native observations](event-registration-reference.json)
show pinned Confusion returns `T` or TYPE ATOM for EVENT, HANDLER, OFF
and ON, including bad priority/header/callable arguments. Two
[error-level observations](event-registration-errors-reference.json)
show its INTERRUPT is unbound. The clean probe command
`.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M3/event-registration-cases.json --output docs/evidence/M3/event-registration-reference.json`
exited **0**; the analogous command with the
`event-registration-errors-*` files exited **1 as expected** because
native stderr is nonempty. Each probe ran one local process with fixed
input and `<QUIT>`, no RNG or game input. Native binary SHA256:
`bd70657059954cbb706fe93e8aceb14c64a58f51f227cfa4e69841d7df9ef340`.
The native build is a stub oracle for interrupts; the implementation
follows the manual and documents this reference deviation rather than
copying the `T` placeholders.

`TMPDIR=/tmp raco test tests/event_registration_test.rkt` exited **1
before implementation** at unassigned EVENT. After the registration
change, it passed 16 checks. A cross-session regression then failed **1**
because an IHEADER could be imported into another session; after owner
checks, focused testing exited **0** with 17 checks. The tests cover
TYPE/PRIMTYPE, event identity, OFF and reattachment, session isolation,
bad arguments, external-event rejection and strict missing INTERRUPT.
`TMPDIR=/tmp make test` exited **0**, **1,252 Racket checks and 23 Python
tests**. `TMPDIR=/tmp make m2-check` exited **0**, including historical
G3 58 assertions, native 12-expression primitive probe and five-turn
reference capture. `TMPDIR=/tmp make m3-source-progress` exited **0 as a
partial-progress measurement** after locked-source verification and
36 historical text files parsed. Its underlying loader exited **1**
after **433 original forms, zero skipped**, up three from 430. It stops
at `77rooms.mud` expression 16, line 101, `EVENT "GC"`, rather than
installing a nonfiring external handler. See
[source summary](source-progress-event-registration.json) and
[raw report](source-load-event-registration.json), including
`77rooms.mud` SHA256
`e89337af98565292f84cfb10e9239924e99918325c9e1ac39b6bce692f5aff94`.

No upstream source, GPLv3 reference code, public license, or network
service changed. No arbitrary MDL evaluator was exposed. The runtime
remains incomplete; full source load, automatic event delivery,
initialization, interactive input, smoke parity and gameplay are
unverified. Next: [issue #104](https://github.com/quaat/mdl-racket/issues/104)
must supply faithful GC event generation and scheduling before allowing
the external registration; this is part of
[event issue #71](https://github.com/quaat/mdl-racket/issues/71).

Reproduce after `make reference-build`:

```bash
TMPDIR=/tmp raco test tests/event_registration_test.rkt
TMPDIR=/tmp make test
TMPDIR=/tmp make m2-check
TMPDIR=/tmp make m3-source-progress
git diff --check
```
