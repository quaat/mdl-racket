# BOOT-REF — Fresh-boot reference capture for SMOKE_PARITY

> **Promotion (2026-11-23, maintainer decision).** The committed strict reference is now
> `docs/evidence/M3/house-boot-reference.json`: the schema-3 S10 capture with only `candidate`,
> `candidate_note` and a `promotion` record changed. The schema-2 candidate below stays unchanged
> as the historical baseline; baseline, promoted reference and fresh native capture are strictly
> equal under ADR-0053 (D1/D2 only). See [M3 mainline acceptance](M3-MAINLINE-ACCEPTANCE.md).


**Branch:** `feat/m3-boot-reference` (PR #131, base `feat/m3-logical-gc`)
**Upstream source (pinned, `sources.lock.json`):** mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`
**Boot-input state (post-cleanup manifest hash):** `7f8589c80882da1ed6ed2db5104a9e6cad891fe6e617baa1af32247b6fb21260`
**Engine SHA256 (build-specific, informational):** `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789`
**Candidate artifact:** `docs/evidence/M3/house-boot-candidate.json` (schema_version 2)
**Status:** gameplay APPROVED by maintainer (2026-11-22); full JSON is a CANDIDATE,
NOT a strict golden fixture. Only the gameplay view (`STRICT_FIELDS`) is compared.

---

## S10 corrections (2026-11-23; see [S10-SMOKE-PARITY.md](S10-SMOKE-PARITY.md), ADR-0053)

1. **RNG-visible output (risk 4 below was wrong).** The scenario *does* show RNG-dependent
   text. `west` re-enters West of House, and ROOM-INFO (`77rooms.mud:521-525`) prints the brief
   text only if `<OR ,BRIEF!-FLAG <PROB 80>>` holds; `PROB` draws `RANDOM`, which `START` seeds
   from `<DSKDATE>` (the clock). Without a fixed clock the response alternates between the brief
   text and the full West of House description (S7: 15 brief / 6 full in 21 unfixed-clock runs).
   Under the fixed clock (250776000, UTC) the reference and this runtime both print the brief
   text; the draw is proven in `historical_clock_seed_test.rkt` and
   [CLOCK-SEED-REFERENCE.md](CLOCK-SEED-REFERENCE.md).
2. **Provenance split (schema 3).** `MDL/MADADV.SAVE` is not a boot input: `SAVE-IT`
   (`77rooms.mud:8-9`, `MUDDLE` > 100) writes `<MDL>MADADV.SAVE`. Schema 3 records it under
   `provenance.save_artifacts` with before/after hashes and keeps it out of
   `provenance.immutable_inputs` (game files, interpreter, clock shim, scenario, entry). The
   approved schema-2 capture `house-boot-candidate.json` is kept unchanged (sha256 `eb194115…`);
   its `boot_input_state` still lists `MDL/MADADV.SAVE`, a known schema-2 flaw. The schema-3
   fresh capture is [S10-house-boot-reference.json](S10-house-boot-reference.json).
3. **Comparison.** `boot_reference.py compare` now delegates to the single comparator
   `scripts/smoke_parity.py` (ADR-0053); `compare_gameplay` was removed.
4. **Risk 1 below is obsolete:** the Racket runtime runs this boot since S7/S8
   (`make test-m3-interactive`, `make m3-check`).

---

## Maintainer decision (2026-11-22)

SMOKE_PARITY uses a fresh-boot scenario. The entry is `<FLOAD "77loadall.mud">` then
`<SAVE-IT>` via stdin (the `run.mud` path). After `<SAVE-IT>` the game starts immediately
because the patched COND in `77rooms.mud` continues in the same clause as a successful SAVE.
Approved behaviour: fixed reference clock, commands
`north / west / open mailbox / take leaflet / inventory / score`, expected
`0 points ... in 6 moves`. `tests/scenarios/house.json` (ZORK.SAVE restore) is UNCHANGED.

---

## PR #131 review findings — resolution

| # | Finding | Resolution |
|---|---|---|
| 1 | `test_house_boot_candidate_exists` required gitignored `artifacts/reference/house-boot.json` | Replaced by `test_committed_house_boot_candidate`, which validates the committed `docs/evidence/M3/house-boot-candidate.json` (portability, provenance, approved gameplay). No test in the normal gate reads `artifacts/`. |
| 2 | `run_mud` was an absolute path; Confusion banner (compile timestamp) was in `boot_output` | `run_mud` = `mdlzork_771212/patched_confusion/run.mud` (relative to the upstream checkout root `.cache/upstream/mdlzork`). `boot_output` now starts at `LISTENING-AT-LEVEL`; the banner is moved to `informational.interpreter_banner`. If a Confusion banner appears without that terminator the capture fails (no silent leak). Strict parity uses `gameplay_view()` = `scenario, fixed_epoch, tz, entry, boot_output, commands, complete`. `captured_at`, banner, exit status and `engine_sha256` are excluded. |
| 3 | Timezone not fixed | Child env sets `TZ=UTC`; recorded as `"tz": "UTC"` (a strict field). Verified by a fake-interpreter test that echoes `TZ`, and by a native capture with parent `TZ=Pacific/Kiritimati` (UTC+14, which would otherwise render December 13): gameplay identical. |
| 4 | `@pytest.mark.native` did not exclude anything (the native test ran in the normal gate) | `pytest.ini`: `addopts = -m "not native"`. New opt-in `make test-boot-reference` (capture -> `compare` against committed candidate -> `pytest -m native`). Evidence of the original bug: before the fix, `pytest tests/test_boot_reference.py` executed `test_boot_reference_determinism`. |
| 5 | Shim froze `CLOCK_MONOTONIC` | `clock_gettime` is frozen only for `CLOCK_REALTIME` / `CLOCK_REALTIME_COARSE`; all other clock ids fall through. `gettimeofday` and `time` stay frozen. `localtime_r` is not intercepted (deterministic under `TZ=UTC`). Test `test_shim_freezes_wall_clock_only` proves monotonic advances across a 50 ms sleep while wall clock equals the epoch. Game transcript identical. |
| 6 | Tree hash taken before stale save deletion; provenance kinds mixed | Stale `SAVEFILE/ZORK.SAVE` is removed first, then a per-file manifest (`provenance.boot_input_state.files`, relative paths) and its aggregate `sha256` are recorded, with `removed_before_boot`. `provenance.upstream_source` separately records the pinned commit from `sources.lock.json` and the `git rev-parse HEAD` of the checkout; capture aborts if they differ. |

Other changes: the shim is compiled into the per-capture temp dir (nothing written under
the shared `.cache/build`); new `scripts/boot_reference.py compare EXPECTED ACTUAL` exits
non-zero naming differing strict fields; `schema_version` bumped 1 -> 2 (layout changed).
`MDL/MADADV.SAVE` (upstream file, overwritten by `SAVE-IT`) is still present in the
boot-input state; it is not read during the boot.

---

## Commands and results (2026-11-22, Racket 7.9 BC, Python 3.9.2, gcc 10.2.1)

Environment: `export PYTHONPATH="$PWD/.sandbox-pydeps/lib" PLTCOLLECTS=":$PWD"`,
`PYTHON=/usr/bin/python3`, run inside the Claude Code sandbox.

1. Tests written first (red):
   `pytest -q tests/test_boot_reference.py` -> `3 failed, 3 passed, 3 errors`
   (missing `compare_gameplay` / `UPSTREAM_ROOT`; the native test was collected and run).
2. Capture regenerated:
   `python3 scripts/boot_reference.py capture --scenario tests/scenarios/house-boot.json --output artifacts/reference/house-boot.json --timeout 90`
   -> exit 0. `boot_output` equals the previously approved `boot_output` minus the banner;
   all six command outputs byte-identical to the approved candidate. Copied to
   `docs/evidence/M3/house-boot-candidate.json`.
3. Acceptance (a), clean gate without the artifact:
   `rm -f artifacts/reference/house-boot.json && make test-python PYTHON=/usr/bin/python3`
   -> exit 0, `31 passed, 1 deselected` (the deselected test is the native one).
4. Acceptance (b), opt-in native gate: `make test-boot-reference PYTHON=/usr/bin/python3`
   -> exit 0: capture OK; `Boot gameplay identical (scenario, fixed_epoch, tz, entry,
   boot_output, commands, complete)`; `1 passed, 8 deselected`. The new capture has
   `tz=UTC`, `take leaflet` -> `Taken.\n`, score `... in 6 moves.`, no `You already have it.`;
   every non-`informational` field equals the committed candidate.
5. TZ robustness: `TZ=Pacific/Kiritimati python3 scripts/boot_reference.py capture ... --output $TMPDIR/kiri.json`
   then `compare` against the committed candidate -> both exit 0, identical.
6. Acceptance (c): `grep -c '/home\|/tmp' docs/evidence/M3/house-boot-candidate.json` -> `0`;
   `This Confusion created` appears only in `informational.interpreter_banner`
   (asserted by `test_committed_house_boot_candidate`).
7. Acceptance (d): `make test PYTHON=/usr/bin/python3` inside the sandbox -> **exit 2**:
   `test-racket` reports `3/2040 test failures`, all `make-directory: ... Read-only file
   system; errno=30` from pre-existing tests that hardcode `/tmp`
   (`tests/loader_test.rkt`, `tests/declaration_test.rkt`, `tests/percent_read_test.rkt`);
   the sandbox mounts `/tmp` read-only. This change touches no `.rkt` file. A retry outside
   the sandbox was not permitted in this session, so **`make test` = BLOCKED (environment)**
   here; it must be re-run on an unsandboxed checkout. `test-python` passes (step 3).

---

## Clock control shim

**File:** `scripts/reference/fixed_time.c`. Confusion (`macros.cpp` 7922, 7965) calls
`gettimeofday` in `mdl_builtin_eval_gettimeofday` / `mdl_builtin_eval_gettimedate`, then
`localtime_r` (7997) for local broken-down time. These feed `<DSKDATE>`, the version-date line
and `<RANDOM <CHTYPE <DSKDATE> FIX>>` in `START`.

| Symbol | Frozen | Notes |
|---|---|---|
| `gettimeofday` | yes | primary clock source |
| `time` | yes | defensive |
| `clock_gettime(CLOCK_REALTIME[_COARSE])` | yes | defensive |
| `clock_gettime(other ids, incl. CLOCK_MONOTONIC)` | **no** | falls through to libc |
| `localtime_r` | not intercepted | deterministic because child `TZ=UTC` |
| `getrusage` (MDL `<TIME>`) | not intercepted | CPU time, not a wall clock |

## Scenario

`tests/scenarios/house-boot.json`: `fixed_epoch` 250776000 = 1977-12-12 12:00:00 UTC, giving
`This version created December 12.` under `TZ=UTC`.

## Approved gameplay transcript (strict fields)

```
boot_output: LISTENING-AT-LEVEL 1 PROCESS 1 / 81prim.mud loaded ... 77dung.mud loaded /
  "DONE" / Welcome to Dungeon. / This version created December 12. /
  You are in an open field west of a big white house, with a boarded front door.
  There is a small mailbox here.
north        -> You are facing the north side of a white house. ...
west         -> West of House / There is a small mailbox here.
open mailbox -> Opening the mailbox reveals a leaflet.
take leaflet -> Taken.
inventory    -> You are carrying: / A leaflet
score        -> Your score would be 0 [total of 500 points], in 6 moves. /
                This score gives you the rank of Beginner.
```

## Remaining risks

1. The Racket runtime cannot yet run this boot (blocked before `SAVE-IT`; see
   STARTUP-CALLGRAPH.md); the capture records reference behaviour only.
2. `make test` exit status in this session is environment-blocked (see step 7).
3. Fresh boot starts at MOVES=0 (6 moves); the restore scenario `house.json` starts at
   MOVES=2. Expected.
4. ~~The scenario shows no RNG-visible text; epoch control of RANDOM is not yet exercised by
   a gameplay assertion.~~ **Wrong** (S10 correction 1): `west` depends on `<PROB 80>`; the
   fixed clock makes it deterministic and the comparator checks it exactly.
5. Promotion of the full JSON to a strict golden fixture still needs maintainer approval.
