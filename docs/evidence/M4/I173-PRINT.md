# M4 #173 (INV-07): PRINT, PRIN1 of structures, CHANNEL line width

Maintainer decision (#173, 2026-11-26): implement PRINT as the manual
specifies (chapter 11, §11.1.2.1), extend PRIN1 to the TYPEs UNPARSE already
prints, and remove the silent "no line breaking" divergence. Contract:
SEMANTICS "M4 #173: PRINT, PRIN1 of structures, and CHANNEL line width"
(written and committed before the implementation).

- Base: `main` 5b27177. Upstream `mdlzork` `bdcd4a67` (sources.lock.json);
  pinned Confusion binary sha256 `6df359f6…b789`. Racket v7.9 [bc].
- Scope: `mdl/runtime/core.rkt` only (no game-specific logic; the game's
  HANDLE path is the next slice).

## Native reference: commands and exit codes

The probe tool is unchanged; a 7-line wrapper only repoints its module-level
`GAME` (working directory) to a disposable copy and `EXE` to the built
interpreter of the main checkout (this worktree has no `.cache`). A second
helper records the exact stdout bytes (the probe tool canonicalises CR to
LF). `make reference-build` was not run.

```sh
# $TMPDIR/i173/probe_in_copy.py (sha256 ad9fbf69…0e26):
#   import sys; from pathlib import Path; import scripts.mdl_probe as m
#   m.GAME = Path(sys.argv[1]).resolve(); m.EXE = Path(sys.argv[2]).resolve()
#   sys.argv = ["scripts.mdl_probe"] + sys.argv[3:]; raise SystemExit(m.main())
# $TMPDIR/i173/raw_all.py (sha256 1a64a093…3b53): same protocol (stdin
#   expression + <QUIT>, cwd = the copy), stores stdout bytes after the
#   LISTENING marker, latin-1 decoded, no canonicalisation.
cp -a .cache/upstream/mdlzork/mdlzork_771212/patched_confusion $TMPDIR/i173/game
for run in 1 2; do
  PYTHONPATH=$PWD python3 $TMPDIR/i173/probe_in_copy.py $TMPDIR/i173/game $EXE \
    --cases docs/evidence/M4/i173-print-cases.json \
    --output $TMPDIR/i173/run$run/i173-print-reference.json
  python3 -I $TMPDIR/i173/raw_all.py $EXE $TMPDIR/i173/game \
    docs/evidence/M4/i173-print-cases.json $TMPDIR/i173/run$run/raw.json
done
```

| Run | Tool | Exit | Result |
|---|---|---:|---|
| 1 and 2 | probe tool, 44 cases | 1, **expected** | 39 ok; 5 not "ok" by design (stderr): `print-arity-0`, `print-arity-3`, `print-non-channel`, `print-input-channel`, `error-handler-native`. Every process exited 0 |
| 1 and 2 | raw helper, 44 cases | 0 | 44 rows |

- Determinism: run 1 and run 2 `cases` are identical (Python `==`) for both
  tools; same interpreter sha256. Run 1 is committed
  ([`i173-print-reference.json`](i173-print-reference.json),
  [`i173-print-reference-raw.json`](i173-print-reference-raw.json)).
- The first capture had 43 cases; `print-type-subr` was added afterwards
  (function_type_test needs native evidence for every new built-in). The
  first 43 raw rows of the recapture are byte-identical to the first capture.
- Canonical and raw stdout differ only for `width-princ-cr-resets` (a CR).
- Upstream integrity: `git -C .cache/upstream/mdlzork status` could not be
  run from this isolated worktree (the agent sandbox refuses git outside
  it). Instead a sha256 over every file of `.cache/upstream/mdlzork`
  (`find . -type f | sort | sha256sum`) was taken before and after all
  captures: `3041a19b…40c8` both times. Nothing under `.cache/upstream` was
  used as a writable working directory.

Our side: `$TMPDIR/i173/run_ours.rkt` (sha256 `26f4b670…474e`, read-only)
runs every case in a fresh `make-mdl-context`, emulating LISTEN with this
runtime's own PRIN1 and TERPRI after each top-level form;
[`i173-print-ours.json`](i173-print-ours.json).

## Native vs ours

35 of 44 cases are byte-identical (LISTEN echo included). Selected rows
(`\n` is LF; `·` marks the trailing space PRINT writes):

| Case | Native (pinned Confusion) | Ours |
|---|---|---|
| `<PRINT 42>` | `\n42·` | same |
| `<PRINT -17>` | `\n-17·` | same |
| `<PRINT FOO>` | `\nFOO·` | same |
| `<PRINT ,NULL>` (empty PNAME) | `\n·` | same |
| `<PRINT "a\"b\\c">` | `\n"a\"b\\c"·` | same |
| `<PRINT !\A>`, `<PRINT !\">` | `\n!\A·`, `\n!\"·` | same |
| `<PRINT (1 FOO "x" !\c)>` | `\n(1 FOO "x" !\c)·` | same |
| `<PRINT (1 (2 (3 ())) ())>` | `\n(1 (2 (3 ())) ())·` | same |
| `<PRINT <>>`, `<PRINT #FALSE (1 "x")>` | `\n#FALSE ()·`, `\n#FALSE (1 "x")·` | same |
| return value `==?` argument | `T` | same |
| `<PRINT <SET X <+ .X 1>>>` then `.X` | `\n2·`, `2` (once) | same |
| `<PRINT 1 .OUTCHAN>` / `,OUTCHAN` | `\n1·` | same |
| `<TYPE ,PRINT>` | `SUBR` | same |
| width 10, `<PRINT (A B C D E F G H I J K)>` | `\n(A B C D E\nF G H I J\nK)·` | same |
| width 10, `<PRINT (A B C D E)>` | `\n(A B C D E\n)·` | same |
| width 10, `<PRINC "abcdefgh">` `<PRINT "abcdefghijkl">` `<PRINC "xyz">` | `abcdefgh\n"abcdefghijkl"·\nxyz` | same |
| width 5, PRINT of long ATOM/FIX/STRING | no break (column 0) | same |
| width 80, `<PRINT FOO>` then `<14 .OUTCHAN>` | `4` | same |
| width 10, PRINC 8 chars, `<PRIN1 "abc">` | break before `"abc"` | same |
| width 10, PRINC 8 chars, `<PRIN1 12>` `<PRIN1 3>` | `abcdefgh12\n3` (exact fit, no break) | same |
| width 0, 94 columns of PRINC | no break, `<14 .OUTCHAN>` = 0 | same |
| width 10, `<PRINTSTRING "abcdefg<LF>xy">` then `<14 .OUTCHAN>` | `10` (LF counted), next PRIN1 breaks | same |
| width 10, PRINC text ending in CR | column 0, no break | same |
| TERPRI / CRLF then `<14 .OUTCHAN>` | `0`, `0` | same |
| width 8, FALSE at a positive column | `\n#FALSE\n()`, `\n#FALSE (\n1 2)` | same |
| width 8, `()` / `(())` at column 7 | `\n()`, `(\n())` | same |
| `<PRINT (A ,NULL B)>` | `\n(A  B)·` | same |
| width 80, HANDLE-like list of STRINGs | break before `"Send mail…"` | same |
| fresh `<13 .OUTCHAN>`, `<14 .OUTCHAN>` | `0`, `0` | same (was 80, 0) |
| `<PRINT '<FOO 1>>` | `\n<FOO 1>·` | strict `PRINT: unsupported TYPE FORM (ADR-0050)`, nothing written |
| `<PRINT [1 2]>` | `\n[1 2]·` | strict `… unsupported TYPE VECTOR …` |
| NEWTYPE ZZ of LIST / ZS of STRING | `\n#ZZ (1 2)·`, `\n#ZS "ab"·` | strict `… unsupported TYPE ZZ` / `ZS` |
| `<PRINT>` / 3 args | stderr `Too few/many arguments to PRINT` | strict `PRINT: PRINT takes an object and an optional CHANNEL (ADR-0050)` |
| `<PRINT 1 2>` | stderr `Error: Attempt to write to non-channel` | strict `PRINT: attempt to write to non-channel` |
| `<PRINT 1 .INCHAN>` | stderr `Channel for PRINT must be output channel` | strict `PRINT: PRINT requires an output channel` |
| `error-handler-native` | HANDLER is a stub (`T`); `<ERROR FOO "BAR">` prints `\n *ERROR* \n FOO \n "BAR" ` and enters level 2 | not comparable (our HANDLER value is not printable; ERROR semantics differ, ADR-0025) |

## Line-width decision

Implemented faithfully (not the strict-error fallback). Cost: one token
layout (`write-tokens!`), one column model (`write-text!`,
`write-newline!`, `channel-output!`) shared by PRINTSTRING, TERPRI, CRLF,
PRINC, PRIN1 and PRINT, and the PRIN1 tokeniser (`prin1-tokens`). A strict
error would have needed the same per-channel column tracking to know when a
break is required, so it was not cheaper. Every rule is checked against a
native case (table above). The column lives in CHANNEL element 14, as in
the manual (§11.2.8.1) and Confusion, so `<PUT .OUTCHAN 14 n>` works.

Decision flagged for review: a terminal PRINT CHANNEL now starts with width
0 (native `default-width-and-column`; M3 `channel-slots`), not 80. With 80,
fresh sessions and the game's startup (before RDCOM's `<PUT .OUTCHAN 13
1000>`) would break lines that Confusion does not. RDCOM-path output is
unchanged: at width 1000 a break needs more than 1000 columns since the last
newline, which no recorded transcript shows.

## Failing before, passing after

Tests-first commit 42163c2 (implementation absent):

| Command | Exit | Result |
|---|---:|---|
| `PLTCOLLECTS=":$PWD" raco test tests/print_test.rkt` | 1 | `mdl-eval: unassigned or non-applicable MDL operator PRINT` |
| `… raco test tests/prin1_test.rkt` | 1 | 2/25 failures (`"1234567890"` vs `"12345\n67890"`, no break) and `PRIN1: unsupported TYPE STRING (ADR-0050)` |
| `… raco test tests/princ_test.rkt` | 1 | 2/38 failures (no line breaking) |

After 4008a65:

| Command | Exit | Result |
|---|---:|---|
| `… raco test tests/print_test.rkt` | 0 | 193 tests passed |
| `… raco test tests/prin1_test.rkt` | 0 | 32 tests passed |
| `… raco test tests/princ_test.rkt` | 0 | 38 tests passed |
| `… function_type_test.rkt`, `host_loop_test.rkt`, `oblist_identity_test.rkt` | 0 | 344, 81, 22 passed (adapted, see below) |
| `channel_port`, `channel_root_identity`, `crlf`, `printstring_channel`, `session_output_port`, `readstring`, `terminal_channel`, `reset`, `unparse`, `string_view_consumers`, `space_character`, `quit_open`, `p0prims`, `chtype_character`, `chtype_segment`, `top`, `file_read` | 0 each | all passed |
| `pytest tests/test_sweep_operator_heads.py` (local `.sandbox-pydeps`, `.cache` linked read-only for the run) | 0 | 6 passed |

`make test`, `make m4-check`, the `historical_*` tests and the M4 scenario
checkpoints were **not run** (orchestrator gate; memory-constrained host).

Adapted existing tests (contract changed by the decision, not weakened):
`prin1_test` and `princ_test` now assert native breaking and PRIN1 of
STRING/CHARACTER/LIST/FALSE instead of the superseded ADR-0050 deviation;
`host_loop_test` refuses a VECTOR entry value instead of a STRING;
`oblist_identity_test` uses FLATSIZE as its unimplemented ROOT SUBR;
`function_type_test` accepts a built-in added after its probe when it has
its own native `<TYPE ,name>` line (PRINT, from `print-type-subr`);
`test_sweep_operator_heads.py` moves PRINT from "missing" to the builtins
(`operator-head-sweep.json` regenerated from the same disposable copy;
diff: PRINT moves, builtin 122→123, missing 19→18).

## Mutation checks

| Mutation | Result |
|---|---|
| `write-tokens!` never breaks (`(and #f …)`) | print_test exit 1, 17 failures (`width-print-list-breaks`, `width-print-close-paren-break`, …) |
| PRINT omits its trailing space | print_test exit 1, 45 failures |

Both restored (`cmp` against the saved copy); suites re-run green.

## Deviations and limitations

See the SEMANTICS classification. In short: strict errors (with nothing
written) for FORM, VECTOR, UVECTOR, TUPLE, FLOAT, NEWTYPE/CHTYPE values,
SUBR/FUNCTION, control and non-ASCII characters, escaped or trailer ATOMs,
and self-referencing LIST/FALSE; different error texts; non-FIX or negative
elements 13/14 are strict errors; PRINT does not bind OUTCHAN for the call;
the break points before a top-level object and before `)` and the LF column
count follow Confusion (manual silent; unresolved for ITS).

## For the HANDLE slice (not done here)

- HANDLE natively is unreachable by an MDL ERROR in the pinned build:
  Confusion's HANDLER/EVENT are stubs returning `T`, and `<ERROR FOO "BAR">`
  prints `\n *ERROR* \n FOO \n "BAR" ` itself (PRINT-style), then
  `LISTENING-AT-LEVEL 2` (case `error-handler-native`; stderr also shows
  `Atom REP has neither LVAL nor GVAL` twice in the bare interpreter). A
  native transcript of HANDLE's own output needs another approach.
- HANDLE's `<PUT ,OUTCHAN 13 80>` now takes effect; its PRINTs start at
  column 0, so only structured arguments longer than 80 columns break.
- The ERROR tuple's elements must be PRIN1-printable here (ATOM, STRING,
  FIX, LIST, FALSE, CHARACTER); a FORM, VECTOR or FRAME element is a strict
  error in PRINT. What the tuple contains in our runtime (ADR-0025) was not
  examined.
