# M4 #173 B2: OBLIST trailers and the game's ERROR handler path (INV-07)

Maintainer direction (#173, 2026-11-26; ADR-0064): implement PRINT according
to the manual, keep MDL-language errors and host failures distinct, and
cover the game's error-handler path as a regression. B1 (PR #207) added
PRINT. This slice adds what HANDLE still needed and the regression itself.

- Base: `main` da973a7 (B1 merged). Upstream `mdlzork` `bdcd4a67`
  (sources.lock.json); pinned Confusion sha256 `6df359f6…b789`. Racket v7.9 [bc].
- Contract: SEMANTICS "M4 #173 B2: OBLIST trailers in PRIN1, PRINT and
  UNPARSE" (spec and tests committed first, 9685483).

## Why trailers

A static trace of HANDLE (77rooms.mud:215-251) in this runtime showed that
every primitive of its general branch is supported except the PRINT of the
ERROR arguments when they are ATOMs off the current OBLIST path. The game's
own ERROR sites outside load-time code are:
`<ERROR UNASSIGNED-VARIABLE!-ERRORS .FN DA>` (DA, 77defs.mud:458; nothing
calls DA) and `<ERROR NO-PREP!-ERRORS>` (FIND-PREP, 77makstr.mud:129; only
at load), both with ERRORS-OBLIST ATOMs, and two defensive branches:
`<ERROR MELEE "CHOMPS" .RES>` (78melee.mud:462, an unknown blow result, a
FIX) and `<ERROR "Wrong dispatch type" <TYPE .NO> .NO>` (DISPATCH,
81tell-repl.mud:133; DISPATCH is reached in play, e.g. 77rooms.mud:1643).
PRIN1 refused trailer notation ("trailer notation not implemented"). After
this slice HANDLE prints all these arguments except a DISPATCH object of a
TYPE PRINT does not print here (VECTOR, FORM, ...).

## Manual

Chapter 15 (https://mdl-language.readthedocs.io/en/latest/15-lexical-blocking/):
§15.4 "it outputs as little of the trailer as is necessary to specify the
ATOM uniquely to READ … if the ATOM is the first ATOM of that PNAME which
READ would find in its normal look-up in the current .OBLIST, no trailer is
output. Otherwise, `!-` is output and the name of the OBLIST is recursively
PRIN1ed", and some trailers do not terminate; §15.2.1 the name of an OBLIST
is the ATOM associated with it under the indicator OBLIST, and ATOMs of an
OBLIST whose name was removed print "as if they were in no OBLIST"; §15.5
the separator `!-` alone refers to ROOT; §15.7.4 an ATOM on no OBLIST
prints with the trailer `!-#FALSE ()`.

## Native reference

21 cases ([`i173-trailer-cases.json`](i173-trailer-cases.json)), the same
tools and protocol as [I173-PRINT.md](I173-PRINT.md) (probe tool through a
3-line wrapper repointing GAME/EXE; a raw-bytes helper), a fresh disposable
copy of `patched_confusion` under the session scratchpad, two runs.

| Run | Tool | Exit | Result |
|---|---|---:|---|
| 1 and 2 | probe tool | 0 | 21 ok |
| 1 and 2 | raw helper | 0 | 21 rows |

Run 1 == run 2 for both tools; the upstream tree hash `3041a19b…40c8` was
the same before and after. (The first capture had 19 cases;
`prin1-root-shadowed` and `unparse-uninterned` were added after the
independent review, recaptured twice the same way; the first 19 rows of
both files are identical to the first capture.) Committed: [`i173-trailer-reference.json`](i173-trailer-reference.json),
[`i173-trailer-reference-raw.json`](i173-trailer-reference-raw.json).

| Case | Native | Ours after |
|---|---|---|
| `<PRIN1 UNASSIGNED-VARIABLE!-ERRORS>` | `UNASSIGNED-VARIABLE!-ERRORS` | same |
| `<PRINT FOO!-ERRORS>`, `<UNPARSE FOO!-ERRORS>` | `\nFOO!-ERRORS `, `"FOO!-ERRORS"` | same |
| ATOM on a MOBLIST OB1 | `BAR!-OB1` | same |
| `T` on OB1 (shadowed by ROOT's T) | `T!-OB1` | same |
| ROOT ATOM, ROOT off the path | `FOO!-` | same |
| ROOT ATOM shadowed by an INITIAL ATOM, ROOT on the path | `ZQROOT!-` | same |
| `<UNPARSE <ATOM "QQ">>`, in a LIST | `"QQ!-#FALSE ()"`, `"(1 QQ!-#FALSE ())"` | same |
| INITIAL ATOM, path `(OB3 ROOT)` | `ZZZ!-INITIAL` | same |
| OBLIST named by an ATOM on another OBLIST | `LEAF!-INNER!-OBA` | same |
| nothing reachable | `LEAF2!-HIDDEN!-OBB!-INITIAL!-` | same |
| `<ATOM "QQ">`, a REMOVEd ATOM | `QQ!-#FALSE ()`, `RMV!-#FALSE ()` | same |
| `<PUT ,OBR OBLIST NEWNAME>` | `RX!-NEWNAME` | same |
| name association removed | `QX!-!-#FALSE ()` | same (recorded disposition, ADR-0064 amendment) |
| HANDLE's MAPF PRINT over `(UNASSIGNED-VARIABLE!-ERRORS FOO DA)` | `\nUNASSIGNED-VARIABLE!-ERRORS \nFOO \nDA ` | same |
| width 10 after 6 columns, `FOO!-ERRORS` | break before it (one token) | same |
| width 12, `QQ!-#FALSE ()` | `QQ!-#FALSE` and `()` break separately | same |

All 21 are byte-identical (`tests/print_trailer_test.rkt`). In the LISTEN
echo, an OBLIST value is replaced by the placeholder `<OBLIST>` on both
sides, because printing OBLISTs is outside this slice (PRIN1 of an OBLIST
stays strict). Nothing else is normalised. Not captured natively: a
non-terminating trailer (manual: "death"); refused here.

## Failing before, passing after

| Command | Before (9685483: tests only) | After |
|---|---|---|
| `raco test tests/print_trailer_test.rkt` | raises `PRIN1: UNPARSE ATOM: trailer notation not implemented; atom "UNASSIGNED-VARIABLE" …` | 82 passed |
| `raco test tests/historical_handle_test.rkt` with `main`'s core.rkt (da973a7) | 6/30 failures: H1 stops at PRINT with the same refusal after HANDLE's TELLs; no FINISH, no QUIT | 32 passed |
| `raco test tests/error_interrupt_test.rkt` (new cross-session check) | — (regression guard) | 15 passed |

Tests that asserted the old refusal now assert the native text
(`unparse_test`: `FOO!-#FALSE ()`, `FOO!-INITIAL`; `prin1_test` and
`print_test`: `BAR!-#FALSE ()`).

## The HANDLE regression

`tests/historical_handle_test.rkt`, run by `make test-historical` (so also
by the reference CI job). No ordinary command reaches an ERROR in the pinned
sources: DA is never called (and needs APPLICABLE?, unimplemented here: a
dead-code finding, not on any game path), and FIND-PREP's ERROR runs only at
load. The ERROR is therefore injected, test-only, without changing the
sources: at the first READSTRING the session's input observer (ADR-0061)
makes the GVAL of the verb JARGON (typed as its synonym `foo`; `jargon`
itself is "I don't know the word JARGO", natively too) a host SUBR that
calls ERROR with DA's arguments. Pinned Confusion stubs HANDLER/EVENT
(case `error-handler-native`), so the expected text is built from the source
and the manual, anchored to native captures where possible.

| Run | Input | Checks |
|---|---|---|
| H1 | `north`, `foo`, `look` | outcome `'quit-after-mdl-error`, one MDL error; the output equals the native C1 capture through the second prompt (D1 applied), then HANDLE's TELL text read from 77rooms.mud, `,VERS`, `\nUNASSIGNED-VARIABLE!-ERRORS \nHANDLE-TEST-UNASSIGNED \nDA ` (the native shape), SCORE's CRLF and "Your score is 0 [total of 500 points], in 2 moves." and the rank; no "Do you wish to leave", no ". Error."; `look` unread; `<13 ,OUTCHAN>` = 80; RECORD's two OPENs denied; no write, empty cwd, game tree unchanged |
| H2 | same, the SUBR first sets INT-LEVEL 8 | the ERROR is not delivered: a strict failure, output ends at the second prompt, no HANDLE text |
| H3 | same, ERROR with a VECTOR argument | HANDLE's TELLs and the first PRINT run, then `PRINT: unsupported TYPE VECTOR` ends the session (Confusion would print `[1 2]`; recorded deviation) |

ADR-0064's required regressions and where they are:
explicit ERROR delivery, handler arguments and FRAME TYPE, ERRET, fall-through,
interrupt-level suppression (`error_interrupt_test.rkt`); nested errors,
ERRET from a nested handler, cleanup and host failures bypassing the handler
(`erret_interrupt_cleanup_test.rkt`); UNWIND (`unwind_raise_test.rkt`);
stale FRAME (`error_interrupt_test.rkt`); **new:** cross-session FRAME
refused (`error_interrupt_test.rkt`, mutation: removing ERRET's owner check
gives 2/14 failures); **new:** the game's own handler during play, at level
8 suppressed, and a strict failure inside it (H1-H3); no M4 scenario
regression (gate below). H3 shows a strict failure inside the handler,
not that host failures bypass it (that is `erret_interrupt_cleanup_test`).

## Gate

Run sequentially on branch head 0d601d0 (`gate.sh`, `make
PYTHON=/usr/bin/python3 <target>`), before the review follow-up:

| Target | Exit | Seconds |
|---|---:|---:|
| `test` (raco 5629 passed, now including print_test; pytest 136 passed, 1 deselected) | 0 | 133 |
| `test-historical` (historical_handle_test: 32 passed) | 0 | 35 |
| `test-m2-g3` | 0 | 1 |
| `m3-source-progress` | 0 | 17 |
| `test-m3-interactive` | 0 | 7 |
| `test-m3-session` | 0 | 23 |
| `test-m3-launcher` | 0 | 45 |
| `test-m3-bang` | 0 | 53 |
| `m3-check` | 0 | 27 |
| `m4-check` | 0 | 761 |

`m4-check`: SCENARIO_PARITY PASS (26); GAMEPLAY_RELIABILITY NOT YET (20 of
23, baseline v1 APPROVED; open blocking item INV-06 only); PLAYABLE NOT
RUN; FULL_COMPLETION NOT RUN; M4_ACCEPTED NOT YET. `m4-scenarios-per-prefix`
not run: the runtime change only replaces a strict refusal that no
scenario reached (all 26 passed before, single-run unchanged after).

## Mutation checks

| Mutation | Result |
|---|---|
| ROOT's trailer printed as `!-ROOT` | print_trailer_test: failures (9 report lines) |
| unnamed OBLIST printed as `!-#FALSE ()` instead of `!-!-#FALSE ()` | print_trailer_test: failures (6 report lines) |
| ERRET without its session-owner check | error_interrupt_test: 2/14 failures |

Each restored and re-run green.

## Also fixed

`tests/print_test.rkt` (B1) was not in `scripts/test_racket.sh`'s explicit
list, so `make test` and CI never ran it (it was run directly during B1).
It is added now, with `tests/print_trailer_test.rkt`.

## Deviations and limitations

- Strict where Confusion prints: non-terminating trailers (Confusion does
  not terminate), an OBLIST name that is not an ATOM, an unreachable ATOM
  with an empty PNAME, PNAMEs that need `\` escapes; PRINT of VECTOR, FORM,
  FLOAT and NEWTYPE values (B1, unchanged), including as ERROR arguments.
- Reference-specific, followed: `!-!-#FALSE ()` for an unnamed OBLIST; the
  token split of a trailer.
- Not changed: class B of ADR-0064 (no host exception becomes an MDL ERROR);
  APPLICABLE? stays unimplemented (only DA uses it).
