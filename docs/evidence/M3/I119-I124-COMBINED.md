# I119 + I124 combined reader reconciliation

Merge `cb2e3d6` (umbrella with #119, merged into #124). Pinned Confusion is binary `6df359f6…`, recorded 2026-11-22.
- Cases: `I119-I124-combined-cases.json`
- Reference: `I119-I124-combined-reference.json`

`mdl_probe` reports `complete: false` because the `..5` case is a deliberate error case. That is expected.

| Expression | Confusion | Runtime (`cb2e3d6`) | Status |
|---|---|---|---|
| `<SET \5 3> .\5` | 3 | 3 | exact |
| `<SET \.5 7> .\.5` | 7 | 7 | exact |
| `<SPNAME \.5>` / `<TYPE \.5>` | `".5"` / ATOM | ATOM, PNAME `.5` | exact |
| `.5` / `<TYPE .5>` | 0.5000000 / FLOAT | 0.5 / FLOAT | exact |
| `..5` | `*ERROR* Type Mismatch, 1st arg to LVAL must be atom` | strict reader error | error in both; different stage |
| `<SET B 4> <SET A B> ..A` | 4 (`<LVAL .A>`) | strict reader error | **deviation**: fails loudly, not silently. `..` is unused in the game source. Follow-up: #134. |

Regression tests are the four "combined" cases in `tests/escaped_atom_test.rkt`.

Mutation check: reverting only the `esc?` FLOAT guard fails 2 checks, and reverting only the raw-character `..` check fails 1.
