# M3 mainline acceptance record (2026-11-23)

**Result: M3 house-boot SMOKE_PARITY — PASS (mainline, scoped); local quit-session
smoke — PASS (mainline); PLAYABLE — NOT RUN.**

Gate run on `main` = **`2a86d5d05f2e4ab2e114143b20670ab5001c4293`** (merge of #151).
This record is added afterwards by a documentation-only commit; it changes no
code, test, fixture or reference record.

## Integration (maintainer approval, 2026-11-23)

Merged into `main` with merge commits, as individual PRs, in the approved order
(each stacked PR retargeted to `main` after its base landed; every PR's CI green
on its merged head):

| PR | Slice | Merge result on `main` |
|---|---|---|
| #107 | umbrella: load the unchanged 1977 source | `2fd0132` |
| #109 | session-owned 36-bit RANDOM | `54b48bd` |
| #111 | BACK views, original CONTIN | `35d560e` |
| #125 | S1 UNPARSE | `a6f68f2` |
| #128 | S2 MEMQ CHARACTER in STRING | `dea93f9` |
| #130 | S3 SUBSTRUC | `751356a` |
| #136 | S4 ON/IPC; SAVE strict (superseded by S5) | `34d3a39` |
| #137 | S5 SAVE as an in-session record; BLOCKED | `657775b` |
| #138 | S6 inert REP | `0ebcad9` |
| #141 | S7 terminal I/O, host loop; review F1/F2 | `5ac5710` |
| #144 | S8 session clock | `c74b4db` |
| #145 | S9 MEMBER | `2b0f6f3` |
| #147 | S11 QUIT outcome, OPEN no-file denial | `a6f2fbe` |
| #148 | S12 launcher | `7ae0311` |
| #150 | S13 READSTRING `!`, explicit output ports | `c0cced1` |
| #146 | S10 strict SMOKE_PARITY gate (includes #131's tooling) | `8f53c57` |
| #142 | docs reconciliation (#113, review F3), M4 backlog | `9738615` |
| #143 | native reference probe evidence | closed: its only commit `a680596` was already on `main` via merges `2e13f68` (#145) and `a4e72ba` (#146) |
| #151 | integration-only doc carry-over; schema-3 promotion | `2a86d5d` |

#150, #146 and #142 conflicted with `main` after their bases landed; `main` was
merged into each branch and the conflicts were resolved exactly as on the tested
integration record #149 (`adb61d5`): append-only Makefile targets, CI steps and
ADR order (0053 → 0054 → 0055); for #142 the four conflicted documents were
taken from `adb61d5`.

**Tree comparison.** After #142, `main` (`9738615`) differed from `adb61d5` only
in two integration-only documentation edits (docs/PLAN.md, the compatibility
inventory). #151's first commit `2f88d92` carried them over (tree equal to
`adb61d5`); its second commit `468f460` is the schema-3 promotion. The tree of
`2a86d5d` equals the tree of `468f460`, so **`main` = `adb61d5` + the
intentional schema-3 promotion only.**

## Schema-3 promotion (maintainer decision)

`docs/evidence/M3/house-boot-reference.json` is now the committed strict
reference: the S10 fresh capture (schema 3, sha256 `8c64e6da…`) with only
`candidate` (false), `candidate_note` and a `promotion` record changed.
`MDL/MADADV.SAVE` is recorded under `provenance.save_artifacts` (before/after);
the immutable input hashes are unchanged. The schema-2 approved candidate
`house-boot-candidate.json` (sha256 `eb194115…`) is unchanged as the historical
baseline. ADR-0053 amended. Strict comparator (D1/D2 only) at epoch 250776000
UTC: schema-2 baseline == promoted reference; promoted == fresh native capture;
schema-2 baseline == fresh native capture — all PASS. Across native captures
the immutable inputs and the MADADV.SAVE before-hash are identical and the
after-hash differs (never compared).

## Mainline gate on `2a86d5d`

**Local** (clean detached worktree, unsandboxed; **Racket v7.9 [bc]**;
`M3_NATIVE=require`; mdli sha256 `6df359f676862b34…`; sources
mdlzork `bdcd4a671b47…`, mit_zork `d94501340842…`):

| Target | Exit | Notes |
|---|---|---|
| `make sources` | 0 | source lock verified |
| `make test` | 0 | 3622 Racket tests; 68 Python passed, 1 native deselected |
| `make test-historical` | 0 | |
| `make test-m2-g3` | 0 | |
| `make m3-source-progress` | 0 | 1,229 original forms, zero skipped |
| `make test-m3-andq` | 0 | |
| `make test-m3-historical-gc` | 0 | |
| `make test-m3-start-back` | 0 | |
| `make test-m3-saveit` | 0 | |
| `make test-m3-interactive` | 0 | |
| `make test-m3-clock-seed` | 0 | seed 10438660480; RANDOM sequence = native |
| `make test-m3-session` | 0 | local quit session |
| `make test-m3-launcher` | 0 | |
| `make test-m3-bang` | 0 | |
| `M3_NATIVE=require make m3-check` | 0 | 7/7 PASS: sources, test-m3-saveit, test-m3-clock-seed, test-m3-interactive, comparator unit tests, candidate vs committed (promoted) reference, native fresh capture; report `native_mode: require`, commit `2a86d5d` |
| `make m3-native-parity` | 0 | |
| `make m2-check` | 0 | |
| `git diff --check` | 0 | upstream checkouts clean |

**CI on `2a86d5d`** (pinned `racket:8.10-bc` container):
[Native Confusion reference run 45176163020](https://github.com/quaat/mdl-racket/actions/runs/45176163020)
(workflow_dispatch on `main`; every step success, including the six-command
host loop, clock-seed chain, quit session, launcher, typed `!`, the binary-free
M3 SMOKE_PARITY check and, after `make reference-build`, the native
fresh-capture comparison) and
[Harness checks run 45176121779](https://github.com/quaat/mdl-racket/actions/runs/45176121779)
(push smoke) — both success.

## Gate table (mainline)

| M3 stage | State |
|---|---|
| PARSED | PASS (mainline) |
| LOADED | PASS (mainline): 1,229 forms, zero skipped |
| INITIALIZED | PASS (mainline, scoped) |
| INTERACTIVE | PASS (mainline, scoped) |
| SMOKE_PARITY | **PASS (mainline, scoped)**: fresh-boot house-boot scenario at session clock 250776000 / UTC; D1/D2 only; promoted schema-3 reference |
| Local session smoke | **PASS (mainline)**: quit/n, inventory, quit/y through FINISH → RECORD → QUIT, byte-identical to native, no files written |
| PLAYABLE | NOT RUN (M4) |

## Limits that remain

- Not exercised: a manual DrRacket GUI run (quit and Stop); the break test
  stands in for Stop.
- Strict gaps reached by ordinary play: `put X in …` (TOP, `77np.mud:126`;
  CHTYPE conversion), an in-game MDL ERROR stops at unsupported PRINT in
  HANDLE (`77rooms.mud:251`), `info`/`help` (OPEN "READ"), `script`; RESTORE
  unsupported; SAVE is an in-session record only.
- Documented deviations: Confusion writes `MDL/ZORK.LOG` on quit, this runtime
  writes no file (ADR-0055; no visible difference); non-ASCII terminal input
  is refused; D1/D2 presentation differences (ADR-0053).
- Next: M4, first scenario "enter the house and open the cellar"
  ([backlog](../M4/SCENARIO-BACKLOG.md)).
