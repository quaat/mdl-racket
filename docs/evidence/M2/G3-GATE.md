# M2 G3 integrated execution gate — branch-level FAIL

**Decision (2026-11-20): FAIL on `feat/m2-memq`; M2 remains open.**
This current-head pre-merge evaluation includes D5 PR #54 and the stacked
`N=?` (#59), computed-global (#61), `ERROR` (#62), and MEMQ correction
after gate commit `d9472a3`. It is not a mainline milestone result. The
exact original `MSETG` from `81prim.mud` succeeds on first/equal calls
and raises `ALREADY-GASSIGNED` on conflict. Original `PSETG` now succeeds
on first/repeat calls with one PURE-LIST membership. The next unmet M2
build path is original `FLAGWORD`, whose empty-TUPLE call reaches
unassigned `MAPF`. A focused correction is [issue #65](https://github.com/quaat/mdl-racket/issues/65);
gate tracking is [issue #56](https://github.com/quaat/mdl-racket/issues/56).
PR #54 remains open pending explicit maintainer merge approval. No M3 work
has started.
The requested external Codex review of D5 final head `e6d295d` was
declined by the review service's usage limit; both PR workflows passed,
and the three earlier review threads are resolved. A final-head external
review is therefore still unavailable.

## Preserved gate contract and checklist

The unchanged `docs/PLAN.md` M2 build lists DEFINE formals, DEFMAC, COND,
PROG, REPEAT, RETURN, AGAIN, MAPF, UNWIND, indirect APPLY/DISPATCH,
declarations, runtime macro expansion, and cross-file loading. Its gate
requires structured tests and original source definitions executing with no
loss of aliasing or continuations. The supplied follow-up adds a coherent
single-session original-source scenario. This report does not waive the
unreached MAPF or indirect application surface.

| Criterion | Result | Evidence |
|---|---|---|
| Source authenticity and no skipped forms | PASS | Three SHA-256 checks before copied-byte execution; full chain report has 24 PASS events, zero skipped, then FAIL. |
| Shared-session original definition loading | PASS for reached prefix | Original `77loadall.mud` invokes VFLOAD; all eight `81prim.mud` forms and `77defs.mud` forms 1–14 execute in one session. |
| VFLOAD return, output, global state | PASS | Same loaded VFLOAD invokes controlled one-form file; returns FALSE, prints `g3-controlled.mud loaded`, assigns `G3-VF=17`. |
| Original MSETG first call and declaration rejection | PASS | Fresh atom/FIX returns T, assigns/manifest global; non-ATOM first argument raises DECL error. |
| Original MSETG equal repeat and conflict | PASS for tested paths | Equal repeat returns T; conflict raises `MSETG G3-TEMP ALREADY-GASSIGNED 3` and preserves the old value. Pinned Confusion agrees on the path and arguments. |
| PSETG installation and invocation | PASS for tested paths | Original definition installs; first/repeat calls return 3/4, update the target, and keep `PURE-LIST` at `(G3-P)`, matching pinned Confusion. |
| FLAGWORD empty-TUPLE call | **FAIL** | Original definition reaches unassigned `MAPF`; pinned Confusion returns 1 for the same call. |
| RAPPLIC property and declaration consultation | PASS | Original 77defs PUT stores `<OR ATOM FALSE NOFFSET>`; GET, TYPE/PRIMTYPE, GASSIGNED?, DECL? hit and diagnostic miss checked in same session. |
| Original DEFMAC expansion | PASS for TRNN | `EXPAND` of original TRNN yields `<N==? <CHTYPE <ANDB 2 <OFLAGS OBJ>> FIX> 0>`, matching pinned Confusion; execution of OFLAGS is outside reached subset. |
| Local binding, nested function/control path | PASS for reached paths | Original VFLOAD uses local X, nested FLOAD/PRINTSTRING/TERPRI; MSETG uses local formals, COND/AND, SETG/MANIFEST. Broad continuation behavior remains NOT RUN. |
| Mutable storage aliasing | PASS | Two globals share one LIST; indexed PUT via one is observed through the other. |
| Failure propagation and diagnostics | PASS for reached barrier | The first FAIL event is followed by no PASS event; failure is `77defs.mud` expression 15, line 37, execute stage, original NEWSTRUC calling unassigned EMPTY?. |
| Session isolation | PASS for tested state | Fresh session has no RAPPLIC association or MSETG definition, while original session retains both; MUDDLE is reseeded. |
| Full M2 build surface | NOT RUN / unsupported | MAPF, indirect APPLY/DISPATCH, broader activation and continuation paths are not established by this scenario. Their absence cannot be silently treated as a gate pass. |

The dedicated test is `tests/historical_g3_test.rkt` via `make test-m2-g3`.
Its 52 assertions verify the reached behavior, including expected unsupported
MAPF, then it **intentionally exits nonzero** with the explicit G3 FAIL.
Checks for expected errors reject unexpected success; source hashes, exact
report status/count/diagnostic, and reference outputs reject changed or
malformed observations. The Racket `mdl-session-atom` helper obtains the same
interned atom as the source reader within a session; `<ATOM "name">` creates
an uninterned atom and would test the wrong association/global identity.

## Provenance and differential evidence

`sources.lock.json`: MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916`; reconstructed
mdlzork/Confusion `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
Source SHA-256: `77loadall.mud`
`389da842abe67e75523afb8e1ff1350f26375f5470b7dab167805f4a611e08aa`;
`81prim.mud`
`8d0e9365109f3583a7d232a60fb893e274bb6a9e225c826178dc38e026c6c571`;
`77defs.mud`
`566ebcc32be9b9226dd7cefd77a517583eebab80a03f452df39e13b85eed734e`.
Current rebuilt Confusion binary SHA-256:
`987471cf0e568ad7f83a10b893484cd3fa99a86a69444c3b7d5554b16829f475`.

The original G3 capture is in `g3-integrated-reference.json` (10 cases,
eight clean; two deliberately invalid 77defs-only loads kept as source
dependency evidence) and `g3-integrated-error-reference.json` (one deliberate
MSETG conflict break). The clean eight are isolated in
`g3-integrated-clean-cases.json`. Rebuilding Confusion and rerunning those
eight yielded zero per-case differences in name, expression, input, exit,
result output, stderr, and `ok`. The deliberate error likewise had zero
differences under those fields. The separate original TRNN expansion is in
`g3-macro-{cases,reference}.json`; one clean case, exact result and empty
stderr. The reference cases each run in a fresh Confusion process; the Racket
integration observations run in one shared session. No RNG or gameplay input
is involved. The approved five-turn M0 capture matched after normalizing
only `captured_at`, engine hash, and the Confusion build-time banner.

## Commands and observed results

**Current MEMQ branch after gate commit `d9472a3`:**
`make test-m2-g3` exited **2**: 52 integrated assertions passed, followed
by explicit `G3 FAIL: original FLAGWORD requires unsupported MAPF`.
`make test` exited 0 (903 Racket checks, 13 Python);
`make test-historical` exited 0 (VFLOAD 23, DECL 21, MSETG equal/conflict,
PSETG first/repeat).
The saved G3 reference cases and source SHA checks are unchanged. The
table below preserves the **initial D5-only gate run** at `ae0984f` and
must not be read as current-head results.

Run from repository root with Racket and Python tools installed:

| Command | Exit | Relevant result |
|---|---:|---|
| `make doctor` | 0 | Python 3.13.0, BDW GC 8.0.4, required tools found. |
| `make sources` | 0 | Two pinned repositories verified. |
| `make test` | 0 | 864 Racket checks; 13 Python tests. |
| `make test-historical` | 0 | VFLOAD 23, DECL 20 assertions. |
| `make test-m2-g3` | **2** | 48 observations pass; explicit `G3 FAIL: original MSETG repeat/conflict requires unsupported N=?`. |
| `make check-source` | 0 | 36 text files parsed, four nontext, zero parse failures. |
| `make reference-build` | 0 | Native Confusion built; upstream checkout unchanged. |
| `make reference-capture` | 0 | Five turns captured; approved golden comparison as above passed. |
| `make reference-probe` | 0 | Twelve baseline expressions probed. |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/g3-integrated-clean-cases.json --output artifacts/m2/g3-integrated-clean-current.json --timeout 300` | 0 | Eight clean reference cases; saved-result comparison zero differences. |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/g3-integrated-error-cases.json --output artifacts/m2/g3-integrated-error-current.json --timeout 300` | 1 expected | Deliberate MSETG error; saved-result comparison zero differences, including nonempty stderr. |
| `.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M2/g3-macro-cases.json --output docs/evidence/M2/g3-macro-reference.json --timeout 300` | 0 | One original TRNN expansion case, clean. |
| `racket scripts/mdl_load.rkt --source-root .cache/upstream/mdlzork/mdlzork_771212/patched_confusion --entry 77loadall.mud --report artifacts/m2/g3-load.json` | 1 expected | 24 expressions; first barrier EMPTY? in original NEWSTRUC. |
| `git diff --check` | 0 | No whitespace errors. |

An initial bare `python3 -m scripts.mdl_probe` attempt exited 1 before running
any probe because that interpreter lacked `pexpect`; the repository virtual
environment command above succeeded. Reference execution is local and
isolated. No upstream source was changed, no GPLv3 code was copied into the
MIT-0 runtime, and no network evaluator was added. Strong association
references, unsupported GETPROP/PUTPROP/locatives, and the D5 declaration
cycle deviation remain as documented in `ATOM-PROPS.md`.

## Blocker and next action

The current root cause is absent `MAPF`, used by the original FLAGWORD.
The previous MSETG and PSETG gaps are corrected on stacked branches.
**Recommended next action:** implement and review reference-backed `MAPF`
in issue #65, then rerun G3 on that head. PR #54 still requires maintainer
authorization before merge.
Do not start M3 `EMPTY?` while this gate fails.
