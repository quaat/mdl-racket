# M2 issue #23 — cyclic structural equality boundary

**Local hardening slice: PASS. M2 milestone: NOT YET PASS.** Base main commit:
`71600a80ba24fa39b994f47573f567103fd8d386`. The feature commit and CI
result belong in the issue/PR comment after publication. `sources.lock.json`
pins MIT Zork `d94501340842e006791fce0757dc0043b8ec8916` and patched
Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`. Both upstream
checkouts remain unmodified.

The [MDL manual's equality rule](https://mdl-language.readthedocs.io/en/latest/08-truth/)
says `=?` compares same-TYPE structural content while `==?` tests identity.
Its [self-reference examples](https://mdl-language.readthedocs.io/en/latest/07-structured-objects/)
show LIST and VECTOR cycles created by PUT/PUTREST and warn that printing
them may never finish. The manual does not give a finite `=?` result for two
distinct cyclic structures whose content repeats forever. This slice keeps
identity and finite structural results, while explicitly rejecting that
unresolved case instead of inventing a coinductive equality rule.

| Command | Exit | Observed result |
|---|---:|---|
| `make doctor` | 0 | Python 3.13.0, Racket 7.9 [bc], BDW GC 8.0.4, build tools found |
| `raco test tests/equality_cycle_test.rkt` before fix | 1 | `bounded-run: cyclic comparison did not terminate` on first same-cycle `=?` assertion |
| `raco test tests/equality_cycle_test.rkt` after fix | 0 | Eleven boundary assertions passed; one interim run exposed a missing test-source `>` delimiter, then it was repaired |
| `make test` final | 0 | `319 tests passed` in Racket; `13 passed` in Python |
| `make sources` | 0 | Two locked commits verified; upstream trees clean |
| `make reference-build` | 0 | Native Confusion rebuilt with build-only `-include cstdint`; upstream unchanged |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/equality-cases.json --output docs/evidence/M2/equality-reference.json --timeout 2` | 0 | Five children exited 0 with empty stderr |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/equality-timeout-cases.json --output docs/evidence/M2/equality-timeout-reference.json --timeout 2` | 1, expected | Distinct equal-content LIST cycles did not finish within two seconds; timeout row saved |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/equality-crash-cases.json --output docs/evidence/M2/equality-crash-reference.json --timeout 2` | 1, expected | Distinct self-referencing VECTORs exited `-11` (signal 11); raw row saved |
| `make check-source` | 0 | `{'parsed': 36, 'failed': 0, 'non-text': 4}`; frozen M0 sweep restored afterward |
| `make reference-capture` | 0 | Five turns captured at `artifacts/reference/house.json`; `complete=true`, `error=null`, PTY cleanup signal 1 |
| `make reference-probe` | 0 | Twelve baseline expressions probed |
| M1 gate report's reference/golden comparison script | 0 | `M1 mainline reference and golden comparisons PASS` |

The five successful reference results are: `T` for a LIST tail cycle compared
with itself, `T` for a LIST containing itself, `T` for a VECTOR containing
itself, `#FALSE ()` for two cyclic LISTs differing at their first element,
and `T` for an acyclic LIST with shared substructure compared to an equal
one. The distinct equal-content LIST-cycle probe reached the two-second
timeout; this is a bounded observation, not proof that Confusion never
returns. The crash probe returned child exit `-11`, with `M2-EQ` as partial
result output and empty stderr. These two cases are excluded from the
successful reference count. Their raw inputs and observations are in the
`equality-*.json` files beside this report.

The rebuilt Confusion binary SHA-256 is
`a142145428f56dfc0ccde6170d5dbaf5b0ce2f94eff3f55abfdb56fac0f5a3b5`;
the reconstructed game image SHA-256 is
`92fdfa3e7500a91042a57f7d6a46c4e906c9587a4a094b4ca219a6a1b0ffb7a4`;
the approved M0 golden SHA-256 is
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
Focused expressions have no time or randomness. The house scenario has fixed
commands but no controlled RNG seed. Confusion embeds build time in its
banner; the approved comparison excludes capture time, rebuilt binary hash,
and banner timestamp only. The timeout harness does not retain partial child
stdout/stderr; only the timeout, input expression, and binary hash are saved.

Supported: identity equality for the same cyclic object, finite structural
equality with acyclic sharing, and false when a difference is found before
cycle repetition. For distinct LIST, VECTOR/UVECTOR, FALSE payload, or tagged
structured values whose comparison repeats an active pair, Racket raises
`mdl-equal?: unsupported cyclic structural equality`. The test suite covers
LIST tails, self-elements, VECTOR/UVECTOR values, FALSE payloads, and a
user-tagged VECTOR.
General coinductive equivalence of distinct cyclic values remains unsupported.
The M2 integrated gate and original Zork execution remain open. No game rule,
upstream source, public license, deployed service, or GPLv3 Confusion code
changed; no interpreter endpoint was exposed. Next action: after review,
proceed to reference-backed REPEAT/AGAIN and named activation work, keeping
cycle errors explicit unless historical evidence establishes a finite rule.
