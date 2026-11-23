# M3 BACK follow-up: original CONTIN reaches TENEX?

Date: 2026-11-22. Issue #110, branch `feat/m3-back-continuation`, stacked on
draft RNG PR #109 (head `e3cc6dc0f29882ebcc7dd3490f528224124e3d39`).
The formal M3 gate remains **FAIL / incomplete**.

`sources.lock.json` pins MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916` and mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`. No upstream source was
modified. [`back-reference.json`](back-reference.json) retains the pinned
Confusion executable SHA256, expression inputs and raw output/error for
eight isolated probes. [The manual's array section](https://mdl-language.readthedocs.io/en/latest/07-structured-objects/)
specifies BACK as the inverse of REST. The reference confirms vector,
uvector, STRING and terminal CHANNEL cases; its zero-offset and out-of-range
calls report errors. The bare terminal CHANNEL has one predecessor slot,
FIX 0, and BACK retains CHANNEL TYPE in Confusion. The runtime mirrors that
host-channel case while sharing array and string backing storage across
views. Other custom array types follow the manual's primitive-type rule.

The focused `tests/back_test.rkt` failed before implementation with
`mdl-eval: unassigned or non-applicable MDL operator BACK`, then passed
afterward. It covers mutation through BACK views, UTYPE sharing, bounds,
wrong types, and terminal metadata. The source-dependent
`tests/historical_start_back_test.rkt` runs after `make sources` and checks
all 1,229 successful forms, zero skips, then invokes the unchanged original
START with `"WHOUS"` and `""`. START emits
`"Welcome to Dungeon.\r\n\n"` and raises
`mdl-gval: unassigned MDL global TENEX?` in `CONTIN` at `77rooms.mud:298`.
The wrapper catches that known XFAIL, so its shell exit 0 is not a startup
pass. Source order and loader exit remain validated by
`make m3-source-progress` and `make test-m3-historical-gc`.

| Stage | Result |
|---|---|
| PARSED | PASS: 36 text files, 4 identified nontext files |
| LOADED | PASS on branch: 1,229 forms, zero skips, 13 files in order, loader exit 0 |
| INITIALIZED | FAIL: direct START reaches unassigned TENEX? after BACK |
| INTERACTIVE | NOT RUN |
| SMOKE_PARITY | NOT RUN |
| PLAYABLE | NOT RUN |

| Command | Exit | Observation |
|---|---:|---|
| `TMPDIR=/tmp raco test tests/back_test.rkt` before implementation | 1 | unassigned BACK |
| `TMPDIR=/tmp raco test tests/back_test.rkt tests/terminal_channel_test.rkt` | 0 | 19 focused checks |
| `TMPDIR=/tmp make test-m3-start-back` | 0 | source verified; 6 assertions including TENEX? XFAIL |
| `TMPDIR=/tmp make m2-check` | 0 | 2,009 Racket checks, 23 Python tests, M2 probes and five-turn native capture |
| `TMPDIR=/tmp make m3-source-progress` | 0 | LOADED, 1,229 forms, zero skips, loader exit 0 |

The next source-backed decision concerns the original startup prelude.
`77rooms.mud:56` and `77patch.mud:38` set TENEX? through GETSYS before
calling START; direct START bypasses that initialization. Probe GETSYS and
the original START-ZORK wrapper before adding platform state. Do not silently
assign TENEX? or claim that BACK alone initializes the game.

Security and licensing: the source remains unchanged, all reference probes
run locally, and no web evaluator or filesystem access was exposed to a
client. The runtime's BACK logic uses manual semantics and observed outputs,
without GPLv3 source code. Independent semantic review, final-head CI,
clock/input injection, and house smoke comparison remain open.
