# S9-MEMBER — the MEMBER SUBR

**RID**: S9-MEMBER (local task record; the orchestrator owns the issue/PR)
**Branch**: feat/m3-member, base commit `2e13f68`. Changes are uncommitted when this
record was written; the orchestrator reviews and commits.
**Upstream SHAs (sources.lock.json)**: mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`;
MITDDC/zork `d94501340842e006791fce0757dc0043b8ec8916`
**Toolchain**: Racket v7.9 [bc]
**Reference**: [MEMBER-REFERENCE.md](MEMBER-REFERENCE.md), `member-probe.json` (58 native
Confusion cases; sha256 prefix `df7c4ef47906a1c1`). No new reference run was made for this slice.
**Specification**: SEMANTICS "M3 primitive: `MEMBER` (S9; issue #139 frontier, HANDLE)",
written before the tests and the code.

## Design

- `mdl-member` in `mdl/runtime/core.rkt`, registered as the ROOT SUBR `MEMBER` with the
  same arity wrapper as MEMQ (`TOO-FEW-ARGUMENTS-SUPPLIED` / `TOO-MANY-ARGUMENTS-SUPPLIED`).
- Element comparison is the existing `mdl-equal?` (`=?`), so the issue #23 cycle boundary is
  inherited unchanged. Results come from `mdl-rest` (STRING views, array views, LIST tails),
  so they share storage, are `==?` to `<REST s i>`, and have the PRIMTYPE type.
- Dispatch on the haystack's base value:
  - STRING (native, view, typed) + STRING-base needle: substring search over the visible
    characters; empty needle is a deliberate refusal.
  - STRING + any other needle: `=?` against each CHARACTER element.
  - VECTOR/UVECTOR arrays: `=?` element search. Any other array kind is refused.
  - LIST-primtype (LIST, FORM, other typed LISTs, FALSE payload): pair walk with a seen set;
    revisiting a pair without a hit raises `MEMBER: cyclic LIST haystack without a match`.
  - TUPLE: refused (modelled, but not probed for MEMBER).
  - Anything else: `Second arg to MEMBER must be structured` (host error, same style as MEMQ;
    Confusion prints the same text as an internal error with no ERROR frame).

## Disagreements and deliberate deviations

- Empty STRING needle on a STRING haystack: refused (reference = out-of-bounds read).
- TUPLE haystack: refused; the reference recommendation allows it if modelled, but there is
  no observation of the result TYPE. Needs a probe before support.
- Cyclic LIST haystack with no match: explicit error instead of a hang (unprobed).
- Test input deviation: the probe built a FORM with `<CHTYPE (1 2 3) FORM>`. This runtime
  refuses CHTYPE to FORM (`mdl-chtype: unsupported built-in TYPE conversion`, pre-existing),
  so the test uses `<FORM 1 2 3>`, which yields the same FORM value. Result `(2 3)`, TYPE LIST
  as in the reference.
- One manual-backed (not probed) assertion: an offset-0 hit on a NEWTYPE'd VECTOR returns
  TYPE VECTOR (manual: the result is `<REST structured i>`).
- No disagreement with any observed reference output was found.

## Commands and results

All from the worktree with `export PLTCOLLECTS=":$PWD"`.

| Step | Command | Exit | Result |
| --- | --- | --- | --- |
| Red | `raco make tests/member_test.rkt && raco test tests/member_test.rkt` | 1 | 15/15 test cases fail, each with `mdl-eval: unassigned or non-applicable MDL operator MEMBER` |
| Green | `raco make mdl/runtime/core.rkt tests/member_test.rkt && raco test tests/member_test.rkt` | 0 | `15 tests passed` (132 check forms; 143 assertions counting loop bodies) |
| Updated test | `raco test tests/oblist_identity_test.rkt` | 0 | `22 tests passed` (the "unassigned ROOT global" example moved from MEMBER to STRCOMP) |
| Smoke suite | `bash scripts/test_racket.sh` | 1 | `3/3259 test failures`: only `tests/loader_test.rkt`, `tests/declaration_test.rkt`, `tests/percent_read_test.rkt`, each `make-directory: ... /tmp/mdl-...: Read-only file system` (sandbox-only, hardcoded `/tmp`, not changed) |
| Interactive | `make test-m3-interactive` | 0 | `31 tests passed` |
| Clock seed | `make test-m3-clock-seed` | 0 | `17 tests passed` |

`make test-m3-*` ran `sources` first: "Verified 2 source repositories".

## Mutation checks

Each mutant was applied to a copy-restored `core.rkt`, rebuilt and run against
`tests/member_test.rkt`; the original was restored and re-verified green (byte-identical).

| Mutant | Exit | Killed by |
| --- | --- | --- |
| MEMQ alias (MEMBER calls `mdl-memq`) | 1 | 9/15 cases (MEMBER is not MEMQ, LIST `=?`, substring, WINNERS, SPNAME, typed STRING, cycles, refusals, sharing) |
| Copy instead of share (fresh STRING/array/LIST results) | 1 | 6/15 cases (aliasing, `==?` to REST, LEXV identity, REST'd offsets, STRING sharing/BACK, cycles) |
| Substring on VECTOR (STRING needle matches STRING elements by substring) | 1 | 2/15 cases (element-not-substring, WINNERS `"MAR"`) |
| Empty needle accepted | 1 | 1/15 cases (strict refusals) |

## Call-site coverage (20 sites, MEMBER-REFERENCE.md inventory)

| Sites | Shape | Covered by |
| --- | --- | --- |
| 77act1.mud:16 (`"<FLUSH-ME>"`), 77rooms.mud:349, 380 (`"GUEST"`) | non-empty literal STRING in STRING | substring search tests |
| 77act1.mud:19 (`,FF` in `.BODY`) | STRING in STRING | substring search, **provided `,FF` is non-empty**; no `SETG FF` exists in the pinned sources, ILO is only reached by an IPC interrupt, so an empty or unassigned FF is not exercised. An empty FF would hit the strict refusal. |
| 77act1.mud:1096 (ECHO-ROOM) | substring, `==?` at offset 0 | str-identity-offset0 tests (needs `UPPERCASE`, a game DEFINE) |
| 77act2.mud:269, 497, 511, 532, 550, 562, 757; 77act3.mud:112, 131 | literal STRING in SPNAME | SPNAME tests; kept result is a STRING view |
| 77act1.mud:17, 18; 77rooms.mud:33, 220, 414 | STRING in WINNERS VECTOR | winners-vector tests |
| 77rooms.mud:1745 (COMMAND) | `""` in LEXV VECTOR (element search) | lexv-empty-string-search tests |

All 20 sites fall in the supported subset; none uses LIST/UVECTOR/TUPLE haystacks,
non-STRING needles or an empty needle on a STRING haystack.

## Files changed

- `docs/SEMANTICS.md` (new section), `mdl/runtime/core.rkt` (`mdl-member`, SUBR entry),
  `tests/member_test.rkt` (new), `scripts/test_racket.sh` (registers it),
  `tests/oblist_identity_test.rkt` (unassigned-ROOT example now STRCOMP),
  `docs/evidence/M3/S9-MEMBER.md` (this record).

## Limitations and risks

- No game-level parity is claimed: this slice does not run HANDLE or any MEMBER call site
  in the historical harness. STATUS/README gate claims are unchanged by this record.
- BYTES, TEMPLATE, TUPLE haystacks are refused; BYTES/TEMPLATE are not modelled.
- `=?` between two distinct equal-content cycles raises the existing explicit error.
- Security/licensing: no reference code was copied; no new execution surface.
