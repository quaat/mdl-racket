# Explicit association preflight

Scope is [#179](https://github.com/quaat/mdl-racket/issues/179) and
[manual §13](https://mdl-language.readthedocs.io/en/latest/13-association-properties/).
Five bare native Confusion probes exited zero using the locked
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3` source and the build recorded
in [L0](../L0/BASELINE.md). Each used a fresh empty working directory,
with the probe forms on standard input followed by `<QUIT>`.
The probes have no clock, random or game dependency. [Exact inputs and observations](native-preflight.json)

- A FIX indicator of 3 stores a UVECTOR in association space, and
  integer structure lookup at 3 still returns the third element. The
  out-of-range association at 99 also succeeds.
- A structured indicator matches itself and an alias. A fresh structurally
  equal LIST misses. PUT and GET interoperate with the explicit operators.
- The fallback argument's eager side effect runs for both miss and hit.
  The returned FORM is then evaluated only on a miss, even when the value
  stored on the hit is MDL FALSE.
- Replacing 9 with 12 works. On deletion of the entry holding 12, Confusion
  returns the item `ITEM`. Deleting again also returns `ITEM`. §13.1.3
  instead defines `12` and then `#FALSE ()`. ADR-0023 already selects the
  native return on the existing PUT removal path, whose behavior is part
  of the compatibility contract.

Recommend using the manual's deletion return for new PUTPROP calls and
retaining the existing PUT policy. This favors the documented general
language contract for a new binding. Matching native for PUTPROP would
give both operator families the same removal return, at the cost of a
new documented deviation. Record the maintainer's decision in #179 before
implementation. Lifetime and session-isolation evidence are still needed.
