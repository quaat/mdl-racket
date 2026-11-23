# Status — 2026-11-23 (M2 mainline PASS; M3 source load WIP PASS; S7 INITIALIZED/INTERACTIVE scoped PASS)

## Current state (2026-11-23)

| M3 stage | Current evidence |
|---|---|
| PARSED | PASS: 36 historical text files parsed; 4 non-text files identified |
| LOADED | PASS on WIP branch: loader exit 0 after 1,229 original forms, zero skipped |
| INITIALIZED | PASS (scoped) on S7 branch `feat/m3-interactive-io`: faithful `<FLOAD "77loadall.mud">` + SAVE-IT returns `,NULL` through CONTIN's RESET (ADR-0050); the host loop prints it (D1) and RDCOM reaches its first READSTRING; boot text equals the approved golden after D1/D2 normalisation and date-line normalisation (`make test-m3-interactive`) |
| INTERACTIVE | PASS (scoped) on S7 branch: all six house-boot commands are read by the original RDCOM and answered as in the approved golden (`west` accepted in its two `<PROB 80>` forms, unfixed clock); end of input gives `Beg pardon?`/`>` then the strict host error `exn:fail:mdl-input-exhausted` (D3) |
| SMOKE_PARITY | NOT CLAIMED: date line and RANDOM depend on the unfixed host clock (issue #135); the golden is still a candidate |
| PLAYABLE | NOT RUN: QUIT, OPEN/CLOSE (RECORD), MEMBER (HANDLE) and UNWIND under host errors (#139) are missing |

- **S7 interactive terminal I/O on `feat/m3-interactive-io` (WIP, ADR-0050):**
  RESET (terminal CHANNEL; clears the host end-of-input flag), PRINC (STRING,
  CHARACTER, FIX), PRIN1 (FIX, trailer-free ATOM incl. `,NULL`), READSTRING
  (RDCOM/YES-NO form; stop consumed; overflow kept; no echo; flush first) and
  the local host loop `mdl-session-run-interactive` (explicit ports; entry value
  printed per D1; GVAL REP re-read each pass). End of input follows D3
  "Mirror, then strict". The faithful path plays the six approved commands:
  `make test-m3-interactive` exit 0 (30 checks); 10 raw runs are byte-identical
  to Confusion's pipe output after removing `"DONE"` and the date. The `west`
  response is RNG-dependent (`<PROB 80>`, 77rooms.mud:523) until #135. Strict
  and unsupported: QUIT, OPEN/CLOSE, MEMBER, PRINC line breaking, `!` in input,
  READSTRING default channel/FIX stop/EOF routine. See
  [S7 evidence](evidence/M3/S7-INTERACTIVE.md).

- **S6 inert REP on `feat/m3-startup-rep` (WIP, ADR-0049):** The GVAL of
  ROOT REP is a predefined SUBR in every session (TYPE SUBR, GASSIGNED,
  APPLICABLE; `<SETG SAVEREP ,REP>` keeps the same object), matching pinned
  Confusion (`evidence/M3/S6-rep-reference.json`). Applying the default REP
  by any path is a strict error naming ADR-0049; no raw MDL REPL exists. The
  host top-level loop that applies the current GVAL of REP is specified in
  SEMANTICS but not implemented. The faithful path now passes
  77rooms.mud:301-302 and fails at `<RESET ,INCHAN>` (303):
  `mdl-eval: unassigned or non-applicable MDL operator RESET`. Next
  blockers: RESET, then the host loop, PRINC, READSTRING. Sandboxed checks
  only so far; no INITIALIZED, interactive or parity result is claimed.
  See [S6 evidence](evidence/M3/S6-REP.md).

- **S5 SAVE session record on `feat/m3-startup-save-record` (WIP, ADR-0048):**
  SAVE returns a fresh `"SAVED"`, writes no file, performs no GC or
  interrupt side effect, and records (sequence, file-spec, INT-LEVEL) for
  host inspection; RESTORE stays refused; `"BLOCKED"` registers but never
  fires. Earlier, S4 (ADR-0047, issue #112) added ON with IPC registration
  and stopped at the strict SAVE refusal at 77rooms.mud:26. The faithful
  `<FLOAD "77loadall.mud">` + `<SAVE-IT>` path now records one SAVE of
  `"<MDL>MADADV.SAVE"` at INT-LEVEL 100000, executes `<INT-LEVEL 0>`
  (77rooms.mud:26; no GC/DIVERT-AGC occurrence was pending), STARTER,
  GETSYS, `ON "BLOCKED"` and START (welcome text, INT-LEVEL 0 at 292),
  and fails in CONTIN at 77rooms.mud:301 `<SETG SAVEREP ,REP>`:
  `mdl-gval: unassigned MDL global REP`. Next blockers per the reference
  trace: GVAL REP plus a LISTEN loop that applies it, RESET, PRINC,
  READSTRING. No INITIALIZED, interactive or parity result is claimed.
  See [S5 evidence](evidence/M3/S5-SAVE-RECORD.md) and the
  [reference frontier](evidence/M3/S5-SAVE-FRONTIER.md).

- **Issue #110 BACK follow-up on `feat/m3-back-continuation` (WIP):**
  Manual and pinned Confusion probes establish BACK view behavior and the
  terminal CHANNEL predecessor slot. The unchanged original START now
  passes RANDOM and BACK, then fails at unassigned `TENEX?` in
  `77rooms.mud:298`. Original source wrappers set this platform global
  through GETSYS before START; direct START bypasses that setup. The
  next slice must probe the source's startup prelude and report its next
  real failure. No interactive or smoke-parity result is claimed. See
  [BACK evidence](evidence/M3/BACK-CONTIN.md).

- **Issue #108 RNG follow-up on `feat/m3-session-random` (WIP):** A
  session-owned two-word 36-bit generator passes deterministic reference
  cases, seed-order checks, strict errors, range checks and independent
  session tests. The unchanged START now passes RANDOM and fails at
  unassigned `BACK` in `77rooms.mud:297` after welcome output. The source
  load remains 1,229 forms, zero skips. This is a new executable frontier,
  not an INITIALIZED or M3 pass. See [RANDOM evidence](evidence/M3/RANDOM-START.md).

- **Current WIP `feat/m3-logical-gc` (reviewed checkpoint `c5a6027`):** The complete unchanged
  source chain loads: 1,229 forms, zero skips, loader exit 0. This is a
  scoped LOADED gate result, not M3 acceptance. A direct original `START`
  call fails at unassigned `RANDOM` after CRLF; terminal input, the game loop, approved
  house smoke parity, and state comparisons remain unverified. After CI fixture
  repair and GC/UVECTOR regressions, `make test` passes 1,471 Racket and 23
  Python tests; `make m2-check` exits 0 on the repaired head. The
  logical GC ledger covers LIST, VECTOR and UVECTOR backing allocations,
  with the limits in [WIP evidence](evidence/M3/WIP-SOURCE-LOAD.md). The
  next executable action is a reference-validated session RNG and then
  the original terminal I/O path. M3 status: **FAIL / incomplete**.

- **Previous issue #104 interrupt foundation on `feat/m3-interrupt-dispatcher`:
  scoped Gate A PASS after independent review; Gate B BLOCKED and M3
  incomplete.** Session-owned
  priority dispatch, pending occurrences, `INT-LEVEL`, `ENABLE`, and
  `DISABLE` have focused red-to-green tests. Independent review findings
  were fixed for queued delivery after a handler exception,
  event-order preservation, and strict predefined event registration.
  The verified source frontier remains **433 completed forms, zero
  skipped**, with loader exit 1 at `77rooms.mud` expression 16, line 101:
  `EVENT "GC"` stays guarded until an actual post-collection event source
  and defensible `<GC>` return semantics exist. The blocker is missing
  MDL reclaimed-word accounting and automatic collection scheduling;
  options and the recommended bounded ledger feasibility probe are in
  [ADR-0043](DECISIONS.md). `make m3-source-progress`
  exits 0 only as a partial measurement. M2 remains PASS; source loading,
  initialization, interactive input and parity are unverified. See
  [interrupt evidence](evidence/M3/INTERRUPT-FOUNDATION.md) and
  [issue #104](https://github.com/quaat/mdl-racket/issues/104).

- **Issue #102 user EVENT/HANDLER registration slice PASS on
  `feat/m3-event-handler`; full M3 gate incomplete:** session-owned
  IHEADER and HANDLER objects support registration, identity, removal
  and reattachment for user-defined STRING events. The manual supplies
  these rules; pinned Confusion stubs the related operators as `T`, so
  native output is a documented reference deviation. Automatic events,
  callback dispatch and process-targeted handlers remain unsupported.
  The unchanged loader completes **433 original forms, zero skipped**,
  up from 430, then exits 1 at `77rooms.mud` expression 16, line 101:
  `EVENT "GC"` is explicitly unsupported until real GC callback delivery.
  The blocker is absent automatic GC scheduling; the options are to
  implement verifiable delivery or keep registration unsupported. The
  recommended next action is a GC callback probe and implementation,
  with the source stop retained until verified.
  `make m3-source-progress` exits 0 only as a partial measurement. See
  [evidence](evidence/M3/EVENT-REGISTRATION.md) and next
  [issue #104](https://github.com/quaat/mdl-racket/issues/104) under
  [event issue #71](https://github.com/quaat/mdl-racket/issues/71).
  Full load, initialization, interactive input and parity remain unverified.
- **Issue #100 duplicate ATOM declaration slice PASS on
  `feat/m3-duplicate-decl`; full M3 gate incomplete:** duplicate names
  retain both Patterns and enforce their conjunction in source order.
  Manual precedence is unspecified and the conjunction is documented as
  an inference; pinned Confusion accepts the syntax but does not enforce
  attached declarations. The unchanged loader completes **430 original
  forms, zero skipped**, up from 363, fully loading `77act1.mud`,
  `77act2.mud` and `77act3.mud`. It exits 1 at `77rooms.mud`
  expression 13, line 92: unassigned `HANDLER`. `make m3-source-progress`
  exits 0 as a partial measurement only. See
  [evidence](evidence/M3/DUPLICATE-DECL.md) and next
  [issue #102](https://github.com/quaat/mdl-racket/issues/102) under
  [event issue #71](https://github.com/quaat/mdl-racket/issues/71).
  Full load, initialization, interactive input and parity remain unverified.
- **Issue #98 deferred attached TYPE names PASS on
  `feat/m3-deferred-decl-type`; full M3 gate incomplete:** an unresolved
  TYPE atom remains in an attached declaration and is resolved only when
  checking a value. It raises an error if still unknown; explicit `DECL?`
  remains immediate. Four clean and two error-level pinned Confusion probes
  support the distinction, with attached enforcement retained as a manual
  rule and reference deviation. The unchanged loader completes **363
  original forms, zero skipped**, up from 233, and fully loads
  `77act1.mud`. It exits 1 at `77act2.mud` expression 39, line 424:
  duplicate declaration for `M`. `make m3-source-progress` exits 0 as a
  partial measurement only. See [evidence](evidence/M3/DEFERRED-DECL-TYPE.md)
  and next [issue #100](https://github.com/quaat/mdl-racket/issues/100).
  Full load, initialization, interactive input and parity remain unverified.
- **Issue #96 NTH declaration slice PASS on `feat/m3-nth-declaration`;
  full M3 gate incomplete:** positive-count repeated Pattern sequences
  match lazily and reject short values; NTH also works in NEWTYPE's stored
  Pattern. Thirteen clean and four error-level pinned Confusion observations
  are retained. Its attached `[3 ANY]` accepts a short vector, a documented
  reference deviation from the manual and this runtime. The unchanged
  loader completes **233 original forms, zero skipped**, up from 188,
  and exits 1 at `77act1.mud` expression 55, line 740: unknown
  declaration type `PRSOBJ`. `make m3-source-progress` exits 0 only as a
  partial-progress measurement. The next bounded task is
  [issue #98](https://github.com/quaat/mdl-racket/issues/98). See
  [NTH evidence](evidence/M3/NTH-DECL.md). Full loading, initialization,
  interactive input and game parity remain unverified.
- **Issue #94 session-aware `%` READ slice PASS on
  `feat/m3-read-time-percent`; full M3 gate incomplete:** executable
  reading evaluates `%` before consuming the next sibling, retaining the
  actual substituted object per session. `ASCII` and CHARACTER-capable
  `STRING` satisfy the original `81tell-repl.mud:46` expression. Native
  probes confirm ordering, once-only substitution, identity and errors.
  The unchanged loader completes 188 original forms with zero skips,
  fully loads `81tell-repl.mud`, and exits 1 at `77act1.mud`
  expression 10, line 78: unsupported NTH declaration Pattern
  `[3 ANY]`. `make m3-source-progress` exits 0 as a partial-progress
  measurement. Full load, initialization and gameplay remain unverified.
  See [issue #94 evidence](evidence/M3/PERCENT-READ.md),
  [next issue #96](https://github.com/quaat/mdl-racket/issues/96), and the
  [compatibility inventory](evidence/M3/COMPATIBILITY-INVENTORY.md).
- **Issue #92 `!\` CHARACTER reader slice PASS; full M3 gate
  incomplete:** `!\ ` now reads as a CHARACTER with code 32, distinct
  from SEGMENT syntax. Five native cases corroborate TYPE, primitive
  type, ASCII code and identity. `make test` passes 1,160 Racket and
  22 Python tests; `make m2-check` passes. The unchanged loader still
  completes 157 forms, zero skipped: the first failure moves within
  `81tell-repl.mud` expression 23 from `!\ ` at line 45 to the
  distinct `%<STRING <ASCII 10>>` read macro at line 46. This slice
  has **no completed-form increase**. See
  [evidence](evidence/M3/SPACE-CHARACTER.md) and
  [next issue #94](https://github.com/quaat/mdl-racket/issues/94).
- **Issue #90 positional `#DECL` metadata slice PASS; full M3 gate
  incomplete:** the RSUBR-style `"VALUE"`/`"OPTIONAL"` Pattern list
  is validated and retained on FUNCTION, without ATOM-variable
  enforcement, matching nine pinned Confusion observations. `make
  test` passes 1,148 Racket and 22 Python tests; `make m2-check`
  passes. The unchanged loader completes 157 forms, zero skipped,
  then stops at `!\ ` in `81tell-repl.mud` expression 23, line 45.
  See [evidence](evidence/M3/FUNCTION-DECL.md) and
  [next issue #92](https://github.com/quaat/mdl-racket/issues/92).
- **Issue #88 custom WORD-primtype literal slice PASS; full M3 gate
  incomplete:** the parser reads `#PSTRING 0` as one typed object in
  the original two-element AUX default. Six native cases confirm its
  PSTRING TYPE, WORD primitive, data and binding; a deliberate
  wrong-primitive native observation differs from manual CHTYPE
  safety, which Racket retains. `make test` passes 1,135 Racket and
  22 Python tests; `make m2-check` passes. The unchanged loader
  completes 144 original forms, zero skipped, then stops at a
  function-style `#DECL` in `81tell-repl.mud` expression 10, line 27.
  See [evidence](evidence/M3/PSTRING-LITERAL.md) and
  [next issue #90](https://github.com/quaat/mdl-racket/issues/90).
- **Issue #86 `%<>` reader macro value slice PASS; full M3 gate
  incomplete:** the side-effect-free empty FORM after `%` becomes
  canonical empty FALSE in data or expression position. Six native
  cases corroborate TYPE, truth and identity; other `%`/`%%` forms
  still fail strictly. `make test` passes 1,121 Racket and 22 Python
  tests; `make m2-check` passes. The unchanged loader completes 136
  original forms, zero skipped, fully loading `77makstr.mud` before a
  three-element typed AUX formal in `81tell-repl.mud` expression 2,
  line 3. See [evidence](evidence/M3/PERCENT-EMPTY.md) and
  [next issue #88](https://github.com/quaat/mdl-racket/issues/88).
- **Issue #84 APPLICABLE declaration Pattern slice PASS; full M3 gate
  incomplete:** the manual's compound type name now matches the callable
  values represented by this runtime, including FIX, FUNCTION, MACRO and
  SUBR, in simple, OR and structured Patterns. Six native `APPLICABLE?`
  cases corroborate type applicability; direct Confusion `DECL?`
  APPLICABLE probes instead enter an error, a documented deviation.
  `make test` passes 1,113 Racket and 22 Python tests; `make m2-check`
  passes. The unchanged loader completes 112 original forms, zero
  skipped, fully loading `77defs.mud`. The next failure is `%<>` in
  `77makstr.mud` expression 6, line 73. See
  [evidence](evidence/M3/APPLICABLE-DECL.md) and
  [next issue #86](https://github.com/quaat/mdl-racket/issues/86).
- **Issue #82 quoted OPTIONAL default slice PASS; full M3 gate incomplete:**
  the manual and six pinned Confusion cases establish raw explicit
  arguments and evaluated defaults in the growing frame. Focused tests
  pass; `make test` passes 1,097 Racket checks and 22 Python tests;
  `make m2-check` passes. The unchanged loader now completes 87 forms,
  zero skipped, then stops at `APPLICABLE` in `77defs.mud` expression
  78, line 448. See [evidence](evidence/M3/QUOTED-OPTIONAL.md) and
  [next issue #84](https://github.com/quaat/mdl-racket/issues/84).
- **Issue #80 eager AND? slice PASS; full M3 gate incomplete:**
  seven clean native cases, one deliberate late-error case and a
  SHA-verified original-source regression establish eager argument
  evaluation and all five `MSETG` global side effects in `77defs.mud`
  expression 28. `make test` passes 1,086 Racket checks and 22 Python
  tests. The unchanged loader reaches 70 completed forms, zero skipped;
  the next failure is a quoted OPTIONAL default in `77defs.mud`
  expression 61, line 338. See [evidence](evidence/M3/ANDQ.md) and
  [next issue #82](https://github.com/quaat/mdl-racket/issues/82).
- **Issue #78 GDECL slice PASS; full M3 gate incomplete:** original
  `GDECL` is a source-data FSUBR that installs global value Patterns and
  checks later `SETG`. Pinned Confusion's GDECL is an explicit no-op, so
  this is a documented manual/reference deviation. `make test` passes
  1,077 Racket checks and 22 Python tests; the unchanged loader completes
  37 forms with zero skips and then stopped at `AND?` in `77defs.mud`
  expression 28, line 146. See [evidence](evidence/M3/GDECL.md) and
  [next issue #80](https://github.com/quaat/mdl-racket/issues/80).
- **Issue #76 source-backed slice PASS; full M3 gate incomplete:**
  three-argument `NEWTYPE` stores and enforces a declaration Pattern,
  including `<<PRIMTYPE VECTOR> ...>` structure heads and same-primitive
  redeclaration. The pinned Confusion reference ignores this third
  argument, a documented manual/reference deviation. The unchanged loader
  reached 36 forms with zero skips, then stopped at `GDECL` in
  `77defs.mud` expression 27, line 139. See [evidence](evidence/M3/NEWTYPE-DECL.md)
  and [next issue #78](https://github.com/quaat/mdl-racket/issues/78).
- **First M3 source-backed slice PASS; full M3 gate remains incomplete:**
  issue #75 adds native-backed `EMPTY?`, bounded `LENGTH?`, current-frame
  `ASSIGNED?`, and startup `ROOT`. `make test` passes 1,046 Racket checks
  and 22 Python tests; `make m2-check` passes its G3 58 assertions and
  native probes/capture. `make m3-source-progress` measures 26 completed,
  zero skipped forms, two beyond the accepted prefix. The first remaining
  barrier at that checkpoint was `77defs.mud` expression 17, line 66: three-argument
  `NEWTYPE`, tracked in [issue #76](https://github.com/quaat/mdl-racket/issues/76).
  See [slice evidence](evidence/M3/EMPTYQ.md). The optional
  `ASSIGNED?` ENV form, full loader, initialization, and play are not
  supported or established.

- **M2 gate PASS on integrated `main` code baseline `7d34195`:**
  [mainline report](evidence/M2/MAINLINE-GATE.md) records the eight
  authorized merges, requirements audit, all command exits, source hashes,
  reference comparisons, CI and limits. G0/G1/G2 and G3 pass; G3 executes
  59 same-session exact-source assertions. `make m2-check` exits 0 with
  986 Racket checks and 13 Python tests; the final `main` harness run
  44889721673 succeeds.
- **First M3 source barrier:** the unchanged `77loadall.mud` chain exits 1
  after 24 completed and zero skipped forms at unassigned `EMPTY?` inside
  original `NEWSTRUC`, `77defs.mud` expression 15, line 37 (execute).
  This is not game initialization or a playable session.
- **M3 progress infrastructure:** issue #73 makes the M2 regression suite
  independent of full-loader progress and adds a machine-readable M3
  source-progress target. `make m2-check` now passes with 986 Racket, 22 Python and
  58 original-source G3 assertions; `make m3-source-progress` passes with
  the authentic 24-form EMPTY? report. See [M3 source progress](evidence/M3/SOURCE-PROGRESS.md).
- **Earlier next action:** implement EMPTY? from native evidence. Random/event APIs are tracked in
  [M3 issue #71](https://github.com/quaat/mdl-racket/issues/71), with no
  parity claim. The pinned Confusion reference loads the full 12-file
  chain to `DONE`.

## Earlier branch checkpoints (retained for provenance)

The [branch acceptance report](evidence/M2/BRANCH-ACCEPTANCE.md) records
the last stacked-head result before integration. The independent D5 review
and issue #67 correction are in [D5-FINAL-REVIEW.md](evidence/M2/D5-FINAL-REVIEW.md).
The [G3-GATE-MAPF.md](evidence/M2/G3-GATE-MAPF.md) report records the
first branch-level 59-assertion G3 PASS; the [requirements audit](evidence/M2/REQUIREMENTS-AUDIT.md)
traces the accepted M2 surface. Older FAIL checkpoints below preserve their
original observations and must not be read as current blockers.

## Earlier checkpoints (retained for provenance)
- **Earlier N=? local slice:** `make test` 879 Racket checks and 13 Python tests;
  focused `neq_test.rkt` 13 checks. Original MSETG advanced from `N=?`
  to `,.FOO`; see [evidence](evidence/M2/NEQ.md). The next action is
  issue #58, then repeat G3. M3 `EMPTY?` waits for G3.
- **Earlier issue #58 stacked reader slice:** `,.FOO` parses as GVAL of the local
  value FOO. `make test` passes 884 Racket checks and 13 Python tests;
  `make test-historical` passes exact-source MSETG first/equal-repeat paths
  alongside VFLOAD and DECL. The original conflicting-repeat path now reaches
  unassigned `ERROR`; G3 is still FAIL. See
  [computed-global evidence](evidence/M2/COMPUTED-GLOBAL.md). Next: probe
  and implement `ERROR` as a separate source-backed slice (issue #60), then
  rerun G3.
- **Earlier issue #60 stacked ERROR slice:** `make test` passes 888 Racket checks
  and 13 Python tests; `make test-historical` includes the hash-verified
  original MSETG conflict and passes. Confusion's `ERROR` enters a
  resumable level; this Racket slice raises a non-resumable exception with
  evaluated arguments. See [evidence](evidence/M2/ERROR.md). The integrated
  G3 was rerun and fails at `MEMQ`; no gate PASS claim is possible.
- **Earlier current-head G3 rerun:** `make test-m2-g3` exits 2 after 48 passing
  integrated assertions; original MSETG first/equal/conflict paths pass,
  while original PSETG reaches unassigned `MEMQ` after its initial SETG
  and PURE-LIST side effects. **G3 FAIL**. See
  [gate evidence](evidence/M2/G3-GATE.md); focused correction issue #63.
- **Current MEMQ/G3 rerun:** `make test` passes 903 Racket checks and 13
  Python tests; `make test-historical` passes VFLOAD 23, DECL 21, MSETG,
  and PSETG. `make test-m2-g3` exits 2 after 52 passing assertions because
  original FLAGWORD reaches unassigned `MAPF`. **G3 FAIL**. See
  [MEMQ evidence](evidence/M2/MEMQ.md) and [G3 gate](evidence/M2/G3-GATE.md).
- **Not demonstrated:** full integrated M2 state invariants, game boot,
  parser, puzzle behavior, RNG parity.


## M2 source execution audit (G0)

**G0 PASS; M2 integrated gate NOT RUN.** The baseline on
`36df3cefccfb9e382cef113752dcd16457e1e95c` reproduces 513 local Racket
checks, 13 Python tests, 36 parsed source files, the native build, capture and
probe. The 508 count on Racket 8.10 is a RackUnit nested-check reporting
difference, verified with a deliberately failing nested assertion in a
disposable copy. The first actual source barriers were `FLOAD`, `#DECL`, the
native `MUDDLE` global, and source ordering; `FLOAD` (G1/G2) and `#DECL`
(M2-D1, PR #45) are now cleared, and the current blocker is the `!`-splice in
the original `PSETG` (issue #46). See
[`SOURCE-READINESS.md`](evidence/M2/SOURCE-READINESS.md) and its JSON inventory.
Next: the SEGMENT slice (issue #46). Original source
execution and gameplay have not been demonstrated.

## M2 shared-session source loader (G1)

**G1 PASS locally; M2 integrated gate NOT RUN.** A root-restricted local
loader compiles and executes top-level forms in order, shares MDL state across
files, and routes nested `FLOAD` through the same session. Controlled fixture
tests cover ordering, definitions/macros, fresh-session isolation,
partial failure, missing files, traversal, symlink escape, cycles, repeated
loads and source diagnostics. The original `77loadall.mud` now executes its
`VFLOAD` definition and begins `81prim.mud`; it stops on the genuine
unsupported `#DECL` at line 3:9. See
[`SOURCE-LOADER.md`](evidence/M2/SOURCE-LOADER.md) and the structured
[load report](evidence/M2/source-load-first-barrier.json). G2 must invoke the
unmodified definition with controlled input; no gameplay is claimed.
The PR #41 review follow-up fixes an indirect symlink escape and preserves
completed forms before later reader errors. The first native CI run failed
because the minimal image lacks `raco make`; the conditional precompile fix
passed both the harness and native reference CI workflows on the follow-up
commit. That follow-up reported 561 Racket checks and 13 Python tests. See
the review section of `SOURCE-LOADER.md`.
The second PR #41 review identified link targets containing `..` after a
symlink and interpreted definitions rejected by `mdl-session-call`. Both now
have focused regressions and local fixes; see the same report for validation.
The third review found a consecutive-parent path bug. Its regression failed
with the wrong child file and now passes; the current suite reports 570
Racket checks and 13 Python tests.
Both follow-up workflows passed on `88d7b39`: harness run 44571160830 and
native reference run 44571160806. G1 remains a local slice PASS while the
PR is under review. G2 has a separate stacked PR #43; the integrated M2
gate remains open.

## M2 historical VFLOAD partial-source probe (G2)

**G2 PASS locally; integrated M2 G3 NOT RUN.** The test verifies the pinned
`77loadall.mud` SHA256, copies its bytes unchanged into a disposable
authorized root, executes only its first `DEFINE VFLOAD`, and invokes that
original reconstructed-source definition on a controlled file. The loader
explicitly reports PARTIAL (one completed, 12 unexecuted forms); the call
prints `<fixture-path> loaded`, returns empty FALSE and installs the fixture's
global value. Six focused pinned Confusion cases corroborate the relevant
output and state. See [`HISTORICAL-VFLOAD.md`](evidence/M2/HISTORICAL-VFLOAD.md).
`PRINTSTRING` follows the manual's count return while Confusion returns the
buffer, a recorded deviation that does not affect VFLOAD's final value.
The full source sequence remains blocked at `#DECL`; the next slice must
implement verified declaration semantics. No gameplay is claimed.
The [M2 source execution inventory](evidence/M2/SOURCE-EXECUTION.md) keeps
the integrated G3 gate at NOT RUN.
PR #43's first two native CI runs failed before reference capture because the
minimal Racket image lacked `compatibility-lib` for `racket/mpair`, then
`rackunit-lib` for the runtime's test submodule. The review
also found that a negative-test helper accepted its own assertion exception.
Both have follow-up fixes: the workflow installs both libraries, and a
failing-then-passing helper self-check makes wrong-type tests meaningful.
The dependency correction passed both workflows on `b4b2809`. After merging
the latest G1 path fix, local G2 validation reports 23 historical assertions,
570 Racket checks, 13 Python tests, and matching reference output; the
combined branch's [harness run 44571763597](https://github.com/quaat/mdl-racket/actions/runs/44571763597)
and [native run 44571763652](https://github.com/quaat/mdl-racket/actions/runs/44571763652)
also passed.

| Gate | State | Evidence / limitation |
|---|---|---|
| Source SHA verification | **PASS** | `make sources` verified both locked commits and clean upstream trees; see `artifacts/environment/sources.json` |
| Racket and Python tests | **PASS** | Plain `make test`: 26 Racket and 13 Python tests pass with pinned dependencies in ignored `.venv`; Makefile selects the venv and `/tmp`. Earlier failures on read-only `/var/tmp` and missing `pexpect` are recorded in the report. |
| December 1977 text reader sweep | **PASS for parsing** | `make check-source`: 36/36 selected UTF-8 MDL text files parsed, four non-text files classified separately; per-file offsets, hashes and counts in `docs/evidence/M0/reader-sweep.json` |
| Native Confusion build | **PASS** | `make reference-build` built `mdli` from pinned `mdlzork` without changing checkout |
| Opening scene plus five commands | **PASS** | `make reference-capture`: all prompts returned, no observed reference errors; maintainer approved `docs/evidence/M0/house-golden.json` in the Codex conversation on 2026-11-17 |
| Primitive reference probes | **PASS for reference only** | `make reference-probe`: 12/12 processes exited 0 with empty stderr; `docs/evidence/M0/primitives.json` |
| CI offline job | **PASS** | [Harness checks run 44125722477](https://github.com/quaat/mdl-racket/actions/runs/44125722477) completed successfully on PR #2 |
| CI native reference job | **PASS** | [Run 44125722256](https://github.com/quaat/mdl-racket/actions/runs/44125722256) verified 36 text files, built Confusion, captured five turns, and probed 12 cases. First run failed on missing `<cstdint>`; build-only flag fixed it. |
| Archive/reconstruction deltas | **PASS for inventory** | Explicit source and semantic differences are listed in `docs/PROVENANCE.md`, based on pinned `mdlzork_771212/README.md` |
| Candidate Racket gameplay / parity | **NOT IMPLEMENTED** | M0 compiler is demonstrative only |

**M0 gate: PASS.** The maintainer approved the exact golden fixture in the
Codex conversation on 2026-11-17; its SHA256 is
`ef270218760101039e499e3dd2b47834cd080f432209822db691fd936d70f7fc`.
[GitHub issue #1](https://github.com/quaat/mdl-racket/issues/1) and merged
[PR #2](https://github.com/quaat/mdl-racket/pull/2) track M0. Both PR workflows
passed. **M1 is PASS on `main`; M2 is current.** This status does not claim Racket
game execution or runtime equivalence.

The M1 issue list and dependency graph are in `docs/PLAN.md`. Slice sections
below preserve each feature's status at its PR head; the final combined gate
result is at the end of this file.

See `docs/evidence/M0/REPORT.md` for exact commands, hashes, and limits.

## M1 issue #3: FALSE values (merged)

**Local slice checks: PASS. M1 milestone: NOT YET PASS.** The reader now groups
`#FALSE (items)` as one source-located node. The bootstrap compiler/runtime
represent FALSE separately from `NIL`, preserve literal payloads, and return
MDL values from `NOT`, `AND`, `OR`, `COND`, and supported predicates. `TYPE`
currently recognizes only FALSE and placeholder ATOM values. `make test`
passes 63 Racket checks and 13 Python tests; the source sweep parses 36/36
text files; reference capture matches the approved M0 golden except for its
timestamp. Thirteen focused Confusion processes exited zero with empty stderr.
M1 FALSE evidence and limitations are in `docs/evidence/M1/REPORT.md`; the
slice merged in [PR #10](https://github.com/quaat/mdl-racket/pull/10).

## M1 issue #4: atom identity and OBLIST (merged)

**Local slice checks: PASS. M1 milestone: NOT YET PASS.** Identity-bearing ATOM
and OBLIST values replace the symbol placeholder. Direct reader names and
`!-` trailers intern through an atom space; `ATOM`, `MOBLIST`, `LOOKUP`,
`INSERT`, `REMOVE`, `OBLIST?`, and `PNAME` have focused implementations.
`make test` passes 83 Racket checks and 13 Python tests; seven focused
Confusion processes exited zero with empty stderr. Dynamic `.OBLIST`,
associations, full OBLIST structure, and general binding semantics remain
unsupported. See `docs/evidence/M1/ATOMS.md` for commands and deviations.

## M1 issue #5: mutable sequences and shared views (merged)

**Local slice checks: PASS. M1 milestone: NOT YET PASS.** LIST values now use
mutable shared tails; VECTOR and UVECTOR values use shared storage views.
`REST`, `NTH`, `LENGTH`, `PUT`, `PUTREST`, and `UTYPE` have tested behavior on
the supported sequence types. Direct FALSE payloads and quoted structured
literals retain MDL atoms and mutable structure identity. `make test` passes
125 Racket checks and 13 Python tests. Ten successful Confusion probes exited
zero with empty stderr; one deliberate UVECTOR error case is recorded
separately. The five-turn capture matches the approved M0 golden except for
`captured_at`. See `docs/evidence/M1/SEQUENCES.md` for exact evidence and
limits. Type constructors, full bindings, and 36-bit arithmetic remain open.

## M1 issue #6: type tags and constructors (merged)

**Local slice checks: PASS. M1 milestone: NOT YET PASS.** `PRIMTYPE`,
`TYPEPRIM`, `NEWTYPE`, and structured `CHTYPE` now preserve user type tags
and shared LIST/VECTOR/UVECTOR storage. The implementation rejects mismatched
primitive types and unimplemented built-in and WORD conversions. Nine focused
Confusion cases exited zero with empty stderr; `make test` passes 152 Racket
checks and 13 Python tests. Source sweep remains 36/36 text files, and the
five-turn reference capture matches the approved golden except for timestamp.
See `docs/evidence/M1/TYPES.md` for commands, hashes, and limits. Local/global
binding semantics and 36-bit arithmetic remain open.

## M1 issue #7: local and global bindings (merged)

**Local slice checks: PASS. M1 milestone: NOT YET PASS.** Atom-keyed globals
and dynamic local frames replace the bootstrap string table and lexical-only
parameter lookup. `SET`, `SETG`, `LVAL`, `GVAL`, `VALUE`, and `GUNASSIGN` have
reference-backed behavior on the supported function subset. Nine focused
Confusion cases exited zero with empty stderr; three expected error probes
are preserved separately, including Confusion's missing `UNASSIGN` builtin.
`make test` passes 176 Racket checks and 13 Python tests. The approved house
golden still matches except for timestamp. See `docs/evidence/M1/BINDINGS.md`.
Optional/auxiliary arguments, explicit environments, and 36-bit arithmetic
remain open.

## M1 issue #8: 36-bit FIX and WORD operations (merged)

**Local slice checks: PASS for the documented subset. M1 milestone: NOT YET
PASS.** FIX input and arithmetic now enforce the manual's 36-bit signed
range; WORD values use a 36-bit mask. The slice implements octal and `#WORD`
literals, integer division, MOD, WORD casts, ANDB/ORB/XORB/EQVB, LSH,
BITS/GETBITS/PUTBITS, and type-sensitive numeric identity. `make test`
passes 262 Racket checks and 13 Python tests; the selected historical text
sweep still parses 36/36 files. Nine focused Confusion cases exit zero with
empty stderr, and two deliberate error cases are saved. The house capture
matches the approved golden except for timestamp. Confusion uses 64-bit
WORD output, allows FIX beyond the PDP-10 range, returns zero for `</>`,
and lacks ROT; the Racket target follows the historical manual on 36-bit
limits and `</>` and leaves ROT unsupported. See
`docs/evidence/M1/WORDS.md` for exact evidence and limits.

## M1 integrated gate on main

**PASS on `main` at merge commit
`a68cbb970b7028853fbcf7885c6c7c42f9470fe5`.**
The M1 gate in `docs/PLAN.md` requires independent Confusion-backed primitive
tests, property and mutation-aliasing tests, and explicit failure on
unsupported constructs. All five primitive slices have local and harness/
native CI PASS. The integrated audit adds three Confusion cases for equality
and evaluation order, nine Racket assertions, and three red-to-green strict
compiler checks. `make test` passes 274 Racket checks and 13 Python tests;
`make sources` verifies both pins; the current M1 sweep parses all 36 text
files. A fresh native build changes the binary hash and its embedded banner
timestamp. The five-turn reference capture matches the approved M0 golden
after excluding `captured_at`, `engine_sha256`, and that banner timestamp.
All 60 successful M1 probe results and six expected error observations match
their saved outputs on the rebuilt oracle. Details, exact commands, merge
SHAs, and limitations are in `docs/evidence/M1/GATE.md`. No Racket Zork
execution or gameplay parity is claimed.

## M2 issue #20: scoped PROG and bare RETURN

**Local slice: PASS. M2 milestone: NOT YET PASS.** Unnamed
`PROG` now creates an auxiliary local frame and returns its last body value;
bare `RETURN` exits the closest `PROG` within the current function. Initializers
run in order before their own new binding is installed, so they can read an
outer binding, while later initializers see earlier new bindings. An unassigned
auxiliary can be assigned with `SET`. Nested exits restore local frames, and a
bare `RETURN` in a called function cannot exit its caller's `PROG`.

`make test` passes 294 Racket checks and 13 Python tests. Nine focused pinned
Confusion cases exited zero with empty stderr; three expected error cases are
saved separately. Confusion crashes with signal 11 on `RETURN` in a PROG
auxiliary initializer; Racket follows the manual's activation-on-entry rule
for that case, and the deviation is recorded separately. `make check-source`
still parses 36/36 selected text files.
The five-turn reference capture and baseline probes pass, and the M1 golden
comparison passes with its documented build-metadata exclusions. Named
activations, explicit target `RETURN`, `REPEAT`, `AGAIN`, `GO`, `UNWIND`,
complex function formals, macros, and source loading remain unsupported.
Exact commands, hashes, and observations are in `docs/evidence/M2/PROG.md`.

## M2 issue #22: activation frames and function ownership

**Local hardening slice: PASS. M2 milestone: NOT YET PASS.** The unnamed PROG
subset now has an explicit dynamic stack of activation frames. Each frame
belongs to one function invocation and becomes invalid on normal completion,
RETURN, or an error. Bare RETURN resolves the nearest live frame belonging to
the current function; a called DEFINE cannot consume its caller's frame.
`make test` passes 308 Racket checks and 13 Python tests. Pinned source
verification and the 36/36 text reader sweep pass. A rebuilt Confusion
reproduces the nine saved successful M2 cases and three expected errors; the
five-turn capture, 12 baseline probes, and approved M1 comparison pass under
the documented build-metadata exclusions. Named/explicit activation targets
remain unsupported. Cyclic structural equality is tracked separately in
issue #23. See `docs/evidence/M2/ACTIVATIONS.md` for exact evidence and limits.

## M2 issue #23: cyclic structural equality boundary

**Local hardening slice: PASS. M2 milestone: NOT YET PASS.** `=?` now returns
true for the same cyclic object, false when two cycles differ before a repeated
comparison, and an explicit unsupported error when a pair of distinct
structured objects repeats on the active comparison path. Finite acyclic
values, including shared substructures, retain their structural result.
`==?` identity behavior is unchanged. `make test` passes 319 Racket checks
and 13 Python tests; source sweep remains 36/36 selected text files. Five
focused Confusion cases succeed, while one distinct LIST-cycle probe times out
at two seconds and one distinct VECTOR-cycle probe exits by signal 11. These
are recorded separately, not counted as passing oracle cases. The five-turn
capture, 12 baseline probes, and M1 approved comparison pass with documented
build-metadata exclusions. See `docs/evidence/M2/EQUALITY.md` for exact
commands, hashes, and unresolved semantics.

## M2 issue #26: unnamed REPEAT and bare AGAIN

**Local slice: PASS. M2 milestone: NOT YET PASS.** Unnamed REPEAT binds
auxiliaries once, repeats its body until RETURN, and shares the activation
stack with PROG. Bare AGAIN restarts the nearest PROG or REPEAT within the
current function without rebinding auxiliaries. Bare RETURN exits either.
Named activations and explicit target transfers remain unsupported and fail
at compile time. `make test` passes 331 Racket checks and 13
Python tests; the 36/36 selected historical text files still parse. Five
finite Confusion cases exited zero with empty stderr and match the Racket
assertions. The five-turn capture, 12 baseline probes, and approved M1
reference/golden comparison pass. See `docs/evidence/M2/REPEAT.md` for
commands, hashes, one transient `/var/tmp` test-runner failure, and remaining limits.

## M2 issue #28: named activations and explicit targets

**Local slice: PASS. M2 milestone: NOT YET PASS.** Named PROG/REPEAT now
bind an opaque ACTIVATION before their auxiliaries. Explicit RETURN/AGAIN
can target a live enclosing PROG/REPEAT, including across a called simple
DEFINE; bare transfers still obey current-function ownership. TYPE reports
ACTIVATION and PRIMTYPE reports FRAME. Wrong-type and stale targets fail
explicitly. `make test` passes 347 Racket checks and 13 Python tests; the
source sweep parses 36/36 selected text files. Eleven focused Confusion
processes exited zero with empty stderr. Six separate invalid-target,
duplicate-name, and unbound-LEGAL? observations include one signal-11 crash
and are not counted as successes. Native build, five-turn capture, 12 baseline
probes, and the approved M1 golden comparison pass locally. Function
activation formals, GO, UNWIND, and original game execution remain open.
See `docs/evidence/M2/ACTIVATION-TARGETS.md` for exact commands, hashes,
deviations, and remaining limits.

## M2 local task: OPTIONAL/AUX/TUPLE/ARGS function formals

**Local slice: PASS. M2 milestone: NOT YET PASS.** `DEFINE` now accepts
historical formal-list sections marked by strings: `"OPT"`/`"OPTIONAL"`,
`"AUX"`/`"EXTRA"`, `"ARGS"`, and `"TUPLE"`, in the reference order required
→ OPTIONAL → one ARGS/TUPLE rest binding → AUX. Defaults evaluate left to
right in the growing function frame; unsupplied optionals and bare AUX locals
stay unassigned; AUX restores outer locals on return. TUPLE binds remaining
arguments as a value with TYPE and PRIMTYPE `TUPLE` (its own primitive type;
`TYPEPRIM TUPLE` is `TUPLE`, `REST` keeps the TUPLE type); ARGS binds them as
a LIST. Arity failures use the historical `TOO-FEW/TOO-MANY-ARGUMENTS-SUPPLIED`
and `BAD-ARGUMENT-LIST` error names. An ATOM named AUX is an ordinary formal.
Malformed formal lists fail at compile time; Confusion validates them at call
time, a documented stricter deviation. The slice is tracked by
[issue #30](https://github.com/quaat/mdl-racket/issues/30) and
[PR #32](https://github.com/quaat/mdl-racket/pull/32); the full task record
is `docs/evidence/M2/FORMALS.md`.
`make test` passes 408 Racket checks and 13 Python tests (the sandboxed
session ran the Python half under system Python 3.9 with repo-local pinned
wheels; see the report). The Codex review of PR #32 found PUTREST splicing
TUPLE storage; both PUTREST operands are now validated through PRIMTYPE
and non-LIST-primtype values fail explicitly (fix commit `72ac750`). The 36/36 text reader sweep passes; the five-turn
capture, 12 baseline probes, the approved M1 golden comparison, and all 69
saved M2 success cases plus 20 expected-error observations reproduce exactly
against the pinned binary. Twenty-four focused Confusion formals probes
succeeded; eleven error observations are recorded separately.
`"NAME"`/`"ACT"`/`"BIND"`/`"CALL"` activation formals, quoted formals,
activation-name atoms before the formal list, GO, UNWIND, macros, and source
loading remain unsupported. See `docs/evidence/M2/FORMALS.md` for commands,
hashes, deviations, and remaining limits.

## M2 local task: activation formals, GO, and UNWIND

**Local slice: PASS. M2 milestone: NOT YET PASS.** `DEFINE` now accepts a
function activation name ATOM between the name and the formal list (the form
the 1977 reconstruction uses 14 times, e.g. `SEARCH-LIST SL`) plus the
`"NAME"`/`"ACT"` markers after any formal section. The activation exists
before formal binding, so RETURN during an AUX initializer exits the call;
explicit RETURN/AGAIN target it from any depth, unwinding intervening PROGs;
AGAIN re-runs the body without re-binding; bare transfers never target
function frames. `GO` follows the MDL manual chapter 10: top-level atoms in
PROG/REPEAT bodies are labels skipped in normal flow, and GO resumes at the
following expression in the nearest owned frame; the pinned Confusion has no
GO or TAG, a recorded reference deviation, and TAG values remain
unsupported. `UNWIND` runs its cleanup when a nonlocal transfer crosses
below it and returns the guarded expression's value otherwise. (This slice
originally also ran it on errors; issue #139 / ADR-0051 corrected that: a
raised error runs no cleanup, matching the manual and Confusion; see
[I139 evidence](evidence/M3/I139-UNWIND.md).) `make test` passes 465 Racket checks and 13
Python tests under the documented sandbox environment after both Codex
review fixes (PUTREST TUPLE rejection in PR #32 and octal-token label
exclusion here); the 36/36 reader
sweep passes; the five-turn capture, 12 baseline probes, the approved M1
golden comparison, and all 65 saved M2 success cases plus 27 expected-error
observations reproduce against the pinned binary. Sixteen focused Confusion
control probes succeeded; seven error observations are recorded separately.
`"BIND"`/`"CALL"` markers, TAG, the FSUBR `BIND`, and macros/source loading
remain unsupported. The slice is tracked by
[issue #31](https://github.com/quaat/mdl-racket/issues/31) and
[PR #33](https://github.com/quaat/mdl-racket/pull/33); the full task record
is `docs/evidence/M2/CONTROL.md` with commands, hashes, deviations, and
remaining limits.

## M2 local task: DEFMAC expansion and quoted formals

**Local slice: PASS. M2 milestone: NOT YET PASS.** The macro slice adds
`DEFMAC`, FORM construction and evaluation, one-step `EXPAND`, and quoted
formals in interpreted DEFINE and DEFMAC. Plain supplied arguments and
TUPLE rest arguments evaluate in the caller frame; ARGS keeps raw source
arguments. A macro expansion can define a callable function. Interpreted
function ownership prevents a bare RETURN from escaping the caller's PROG.
`make test` passes 513 Racket checks and 13 Python tests. The selected text
sweep still parses 36/36 files. Twenty-five pinned Confusion success cases
exit zero with empty stderr, and eight separate error observations match
their saved outputs. The five-turn house capture matches the approved M0
golden after the documented capture/build timestamp exclusions. Confusion's
caller-local expansion behavior differs from the manual's top-level wording;
Confusion also evaluates non-macro EXPAND input and prints a debug message,
while Racket keeps the form unchanged. Malformed formal-list error order
also differs. Full details and commands are in
[`docs/evidence/M2/MACROS.md`](evidence/M2/MACROS.md), tracked by
[issue #34](https://github.com/quaat/mdl-racket/issues/34).
Source loading, declarations, general APPLY/DISPATCH, and original game
execution remain open. The first unmet **milestone** gate is still M2.
The PR review follow-up fixes empty auxiliary LISTs in interpreted
PROG/REPEAT and keeps a leading activation name separate from quoted
formals in directly compiled and generated definitions. Ten new pinned
Confusion cases match the Racket regressions; the red-to-green record is in
[`docs/evidence/M2/MACROS.md`](evidence/M2/MACROS.md#review-follow-up).

## M2 infrastructure task: faster CI Racket setup

**CI task: PASS. M2 milestone: NOT YET PASS.** Both workflows passed on the
digest-pinned minimal Racket `8.10-bc` container: [harness run
44353286644](https://github.com/quaat/mdl-racket/actions/runs/44353286644)
and [native run
44353286715](https://github.com/quaat/mdl-racket/actions/runs/44353286715).
The harness log spans about 32 seconds and the native log about 43 seconds,
including image pull, dependencies, and cleanup. The same-day apt baselines
were 40 seconds for the harness and 84 seconds for one native run; a later
native apt run took about 17 minutes due to its dependency install. These
are individual runs, not a controlled benchmark. The full comparison,
commands, and limitations are in
[`docs/evidence/M2/CI-SETUP.md`](evidence/M2/CI-SETUP.md), tracked by
[issue #36](https://github.com/quaat/mdl-racket/issues/36) and
[PR #37](https://github.com/quaat/mdl-racket/pull/37). No MDL semantics or
upstream source changed. Source loading and original game execution remain
the next M2 work.

## M2 issue #44: `#DECL` local declarations

**Local slice: PASS. M2 milestone: NOT YET PASS.** The declaration slice
implements chapter-14 `#DECL` for `DEFINE`, `DEFMAC`, `PROG`, and `REPEAT`
in both compiled and interpreted paths: bound formals, OPTIONAL/AUX
initializers, later `SET`s, and normal or explicit results are checked
against `ANY`, registered type atoms, `<OR ...>`, and `<PRIMTYPE type>`
patterns, with strict explicit rejection of everything else. `DECL?`,
`GASSIGNED?`, and `MANIFEST` are added; `SETG` refuses to change an assigned
manifest except to an `==?`-identical value or when `.REDEFINE` is true.
The reader accepts the doubled `#DECL #DECL` form that the original
`77act1.mud:110` requires (Confusion's generic `#`-typecode reading makes
it a re-typing no-op). The unmodified original `MSETG` now installs and
executes (`<MSETG M2-D1-TEMP 3>` returns `T`, leaving the global at `3`);
the `77loadall.mud` load advances past the `#DECL` barrier and stops
explicitly at the next construct, the `!`-splice in the original `PSETG`
(`81prim.mud:16:46`). `make test` passes 620 Racket checks and 13 Python
tests; the selected text sweep still parses 36/36 files. Thirteen pinned
Confusion observations back the semantics: eleven success cases exit zero
and the two deliberate `MSETG` error cases match their saved outputs.
Pinned Confusion does not enforce attached declarations; this slice
follows the manual instead and records that deviation. Full details,
commands, and hashes are in
[`docs/evidence/M2/DECLARATIONS.md`](evidence/M2/DECLARATIONS.md), tracked
by [issue #44](https://github.com/quaat/mdl-racket/issues/44). The
session recovery record is in
[`docs/evidence/M2/SESSION-RECOVERY-2026-11-19.md`](evidence/M2/SESSION-RECOVERY-2026-11-19.md).
General APPLY/DISPATCH and original game execution remain open. The
first unmet **milestone** gate is still M2.

## M2 issue #51: the interpreter-supplied MUDDLE global

**Local slice: PASS. M2 milestone: NOT YET PASS.** The interpreter bound
its version number as a startup global; the pinned reference binds
`MUDDLE` to the FIX `101`, and every fresh shared-session loader session
now seeds it identically (interned in that session's atom space). With
that value the `77defs.mud:1` guard `<L? ,MUDDLE 100>` is FALSE, the
`<AND ...>` short-circuits, and `USE` — unbound in the reference — stays
an explicit error. The pinned `77loadall.mud` chain completes **twelve**
expressions (up from ten) and now stops at `77defs.mud` expression 3:
`<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>` fails on the missing
atom-property `PUT` — the next source dependency. The reference itself
loads the entire chain to `DONE` (recorded in the D4 reference evidence),
which is the concrete parity target for the remaining M2 work. `make
test` passes 802 Racket checks and 13 Python tests. Full details,
commands, and hashes are in
[`docs/evidence/M2/MUDDLE.md`](evidence/M2/MUDDLE.md), tracked by
[issue #51](https://github.com/quaat/mdl-racket/issues/51). Atom-property
`PUT`, the `MEMQ` primitive, general APPLY/DISPATCH, and original game
execution remain open. The first unmet **milestone** gate is still M2.

## M2 issue #48: structured declaration patterns

**Local slice: PASS. M2 milestone: NOT YET PASS.** The structured
declaration slice implements chapter-14 `<struc [REST ...]>` patterns for
LIST, VECTOR, UVECTOR, and TUPLE: required element prefixes apply
positionally, the trailing `[REST pat ...]` repetition matches zero or
more remaining elements (cyclically for multi-pattern repetitions), and
nested `<OR ...>` works inside structures. `DECL?` gains the reference's
payload distinction (overall-type mismatch returns bare `#FALSE ()`; an
element mismatch carries the offending element and the leaf pattern).
Traversal is bounded (explicit depth limit 200; cyclic chains surface the
reader's explicit cyclic error) and checked values are never copied or
mutated. The unmodified original `PSETG` now installs with its
`<LIST [REST ATOM]>` declaration; **the pinned `81prim.mud` loads in
full** (all eight expressions), the `77loadall.mud` chain completes ten
expressions, and the load now stops at the unassigned global `MUDDLE` in
`77defs.mud` — the historical interpreter-version global and the next
source dependency, alongside the `MEMQ` primitive `PSETG` invokes.
`make test` passes 785 Racket checks and 13 Python tests. Twenty-two
pinned Confusion success cases and fourteen deliberate-error observations
back the semantics, regenerated byte-identically before commit; the
deviations (empty `<struc>` rejected per the manual BNF, strict `DECL?`
arity, structured heads restricted to the four types) are recorded in
`docs/SEMANTICS.md`. Full details, commands, and hashes are in
[`docs/evidence/M2/DECLARATION-PATTERNS.md`](evidence/M2/DECLARATION-PATTERNS.md),
tracked by [issue #48](https://github.com/quaat/mdl-racket/issues/48).
The `MUDDLE` global, the `MEMQ` primitive, general APPLY/DISPATCH, and
original game execution remain open. The first unmet **milestone** gate
is still M2.

## M2 issue #46: SEGMENT (`!` splice) evaluation

**Local slice: PASS. M2 milestone: NOT YET PASS.** The SEGMENT slice
implements chapter-7 `!` notation: `!.ATOM`/`!,ATOM`/`!<FORM...>` segments
splice their value's elements into LIST, VECTOR, UVECTOR, and
FORM-argument construction in strict left-to-right order; a final
LIST-valued segment shares the payload's tail (PUT mutation visible through
both names), non-final segments and array constructions copy; STRING
segments splice as CHARACTER values; quoted structures keep segments as
unevaluated data; standalone and non-structured segment results raise the
reference's ILLEGAL-SEGMENT, and non-uniform UVECTOR construction raises
TYPES-DIFFER-IN-UNIFORM-VECTOR. The original `PSETG` splice now compiles:
the pinned `77loadall.mud` load advances to **three completed expressions**
and stops at the next actual dependency, `PSETG`'s compound
`<LIST [REST ATOM]>` declaration pattern at runtime stage (issue #48).
`make test` passes 701 Racket checks and 13 Python tests; the selected text
sweep still parses 36/36 files. Eighteen pinned Confusion success cases and
ten deliberate-error observations back the semantics, regenerated
byte-identically before commit; the deviations (interpreted call-argument
splicing follows the manual over the reference's interpreted path;
eager interpreted segment-payload evaluation) are recorded in
`docs/SEMANTICS.md`. Full details, commands, and hashes are in
[`docs/evidence/M2/SEGMENTS.md`](evidence/M2/SEGMENTS.md), tracked by
[issue #46](https://github.com/quaat/mdl-racket/issues/46). At this
slice's close the structured declaration patterns (issue #48, recorded
above) were the next dependency; general APPLY/DISPATCH and original game
execution remained open.

## M2 issue #53: atom-property PUT/GET associations (D5)

**Local slice: PASS (branch `feat/m2-atom-props`). M2 milestone: NOT YET
PASS.** The D5 slice implements MDL association space: `PUT` and `GET`
dispatch exactly as the pinned reference classifies (structured item +
FIX indicator is the element store; every other combination — including
FIX indicators on non-structured items — is an association;
two-argument PUT removes and echoes the item; one-argument PUT is
TOO-FEW-ARGUMENTS-SUPPLIED; three-argument GET on a structure errors).
Associations match by `==?` identity via `mdl-identical?` on both item
and indicator in a session-owned entry list — fresh sessions start
property-free. A weak `eq?` table failed review regressions for WORDs and
array REST views; the corrected store retains keys until removal or session
end, a documented GC-lifetime deviation. `DECL?` consults an atom's `DECL` association through
the existing D1/D3 matcher and carries the resolved leaf in the `#FALSE`
payload; `SETG` deliberately does not enforce it. `GETPROP`/`PUTPROP`
and chapter 13.4 machinery remain explicit unimplemented failures.
The historical `77defs.mud` expression 3
`<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>` now executes; the pinned
load advances from twelve to **twenty-four completed expressions** and
stops at `77defs.mud` expression 15 (`EMPTY?` inside the original
`NEWSTRUC`). `make test` passes 864 Racket checks and 13 Python tests.
Eighteen initial and eleven review-derived pinned Confusion success cases,
plus six initial deliberate errors, one review-derived error and one bounded
alias-cycle timeout back the semantics; the two manual-vs-reference conflicts
(removal returns the item, not the previous value; augmented `#FALSE
(leaf)` DECL? misses) are adjudicated toward the reference in
[`docs/evidence/M2/ATOM-PROPS.md`](evidence/M2/ATOM-PROPS.md) and ADR-0023.
Full details in `docs/SEMANTICS.md` (M2 D5 section). The integrated G3
gate and original game execution remain open.
