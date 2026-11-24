# MDL language conformance

This track extends the existing `#lang mdl` and session loader. The Zork
track owns gameplay acceptance and shared platform policy through
[epic #163](https://github.com/quaat/mdl-racket/issues/163).

| Order | Scope and locations | Dependencies and risks | Acceptance evidence |
| --- | --- | --- | --- |
| L0 | Inventory, manual examples and local test runner in `docs/conformance` and `tests/conformance` | No runtime change. Record uncovered areas and run the existing gates. | Pinned manual, reproducible source/test mapping, isolated loader and frontend results, portable native probes and clean-baseline gates. |
| L1.1 | `PUTPROP` and `GETPROP`, [§13](https://mdl-language.readthedocs.io/en/latest/13-association-properties/), `runtime/core.rkt` association space | L0. High identity and GC risk. Reuse the existing session table and coordinate with #53. Investigate fallback EVAL ordering before choosing slice boundaries. | Numeric selector vs indexing, structured identity, replacement/removal, stored FALSE vs miss, default evaluation, lifetime and sessions. Native probes and independent review. |
| L1.2 | Missing mathematics, [§3.4–3.5](https://mdl-language.readthedocs.io/en/latest/03-built-in-functions/#34-examples--and-fix-arithmetic-1), `runtime/core.rkt` | L0. Low game reach for additive operators. Preserve established FIX/FLOAT representation and ADRs. | Numeric types, order, arity, domain and overflow tests, compared with manual and native. |
| L1.3 | Printing and basic I/O, [§11](https://mdl-language.readthedocs.io/en/latest/11-input-output/), `runtime/core.rkt` and `loader.rkt` | L0. Shared channel and ERROR behavior. [#173](https://github.com/quaat/mdl-racket/issues/173) owns PRINT. | Output bytes, return types, channel ownership, strict failure, no unrestricted files. |
| L2 | Allocation #120, binding arguments #121, nested LVAL #134, type identity #129, STRING identity #127 and reader ordering #126 | Independent PRs in that order, coordinate shared work via #163. #126 and L4 share the executable reader. High mutation and compatibility risk. | Exact failing-before cases, native probes, adversarial identity/aliasing tests and regression gates. #120 validates bounds before allocation. |
| L3 | EVAL, ENVIRONMENT, UNASSIGN, BIND/CALL, application and activation, [§4](https://mdl-language.readthedocs.io/en/latest/04-values-of-atoms/) and [§9](https://mdl-language.readthedocs.io/en/latest/09-functions/), compiler and runtime | L1/L2 foundations. High risk to dynamic scope, ERROR and original source execution. | Raw/evaluated arguments, environment lifetime, binding restoration, nonlocal ownership, compiled/interpreted equivalence. |
| L4 | Locatives, BYTES/OFFSET/GROW, reader and type extensibility, [§7](https://mdl-language.readthedocs.io/en/latest/07-structured-objects/), [§12](https://mdl-language.readthedocs.io/en/latest/12-locatives/), [§17](https://mdl-language.readthedocs.io/en/latest/17-macro-operations/) | L2 identity/order and L3 evaluation/application. High aliasing and source-order risk. | Location aliasing and legality, typed sharing, read-time order, type-specific evaluation/application and print. |
| L5 | Processes, interrupts, files/images, historical machine code and diagnostics, [§19–23](https://mdl-language.readthedocs.io/en/latest/19-compiled-programs/) | Core stable. Shared host policy and licensing review as applicable. | Per-feature feasibility decision, bounded host abstraction where accepted and platform limits documented. |

L0 is in progress. Later rows are pending. Every runtime PR requires
`make test`, `make test-historical`, `make test-manual`, `git diff --check`,
and the current M3/M4 regression targets. Existing approved game fixtures
are the compatibility contract. A name in the runtime registry alone is
candidate implementation evidence.
