# BOOT-REF — Fresh-boot reference capture for SMOKE_PARITY

**Branch:** `feat/m3-boot-reference`  
**Base commit:** `124f60c` (`origin/feat/m3-logical-gc`)  
**Engine SHA256:** `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789`  
**Game SHA:** `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3` (mdlzork_771212)  
**Candidate artifact:** `docs/evidence/M3/house-boot-candidate.json` (this directory)  
**Approved golden:** NOT YET — awaiting maintainer approval  

---

## Maintainer decision (2026-11-22)

SMOKE_PARITY uses a new fresh-boot scenario. The entry is `<FLOAD "77loadall.mud">` then
`<SAVE-IT>` via stdin (the `run.mud` path). After `<SAVE-IT>`, the game starts immediately
because the patched COND in `77rooms.mud` continues in the same clause as a successful SAVE.
Clock and RNG are fixed via an LD_PRELOAD shim (`scripts/reference/fixed_time.c`).

The existing approved `tests/scenarios/house.json` (ZORK.SAVE restore) is UNCHANGED.

---

## Task 1: Clock control shim

**File:** `scripts/reference/fixed_time.c`  
**Binary:** `.cache/build/shim/fixed_time.so` (gitignored — built at run time by `boot_reference.py`)

Confusion (`macros.cpp` lines 7922, 7965) calls `gettimeofday` directly in
`mdl_builtin_eval_gettimeofday` and `mdl_builtin_eval_gettimedate`. Both are the entry
points for `<GETTIMEDATE>` / `<DSKDATE>`, which determine the version-date line and the
`<RANDOM <CHTYPE <DSKDATE> FIX>>` seed in `START`.

The shim intercepts three POSIX calls:

| Symbol | Used by Confusion | Notes |
|---|---|---|
| `gettimeofday` | Yes (`macros.cpp:7922,7965`) | primary clock source |
| `time` | libc internal | defensive intercept |
| `clock_gettime` | libc internal | defensive intercept |

`localtime_r` is NOT intercepted: Confusion applies it to the `tv_sec` already returned
from gettimeofday, so intercepting gettimeofday is sufficient.

**Determinism evidence (commands, exit 0):**

```
# Epoch 250776000 (1977-12-12 12:00 UTC)
$ MDL_FIXED_EPOCH=250776000 LD_PRELOAD=.cache/build/shim/fixed_time.so ./test_shim_time
250776000

# Epoch 100000000 (1973-03-03)
$ MDL_FIXED_EPOCH=100000000 LD_PRELOAD=.cache/build/shim/fixed_time.so ./test_shim_time
100000000

# Without shim — returns current wall clock (not a fixed value)
$ ./test_shim_time
1795384763
```

Two different epochs return different values deterministically. Without the shim, the
current wall clock is returned.

---

## Task 2: Capture tooling

**File:** `scripts/boot_reference.py`

Extends `reference_runner.py` with a boot-specific capture function:
1. Copies the upstream game directory to a fresh `tempfile.mkdtemp()` dir.
2. Builds (or accepts) the shim `.so` targeting `.cache/build/shim/`.
3. Spawns `mdli` without `-r`, with `LD_PRELOAD` and `MDL_FIXED_EPOCH` set.
4. Sends `<FLOAD "77loadall.mud">` and `<SAVE-IT>` before waiting for the first `>` prompt.
5. Waits for `^>` (RDCOM prompt) which indicates the game is running.
6. Sends scenario commands one at a time, waiting for `^>` after each.
7. Writes a JSON transcript extending schema_version 1 with: `run_mud`, `fixed_epoch`,
   `boot_output`, `engine_sha256`, `game_files_sha256`.
8. Deletes the temp copy on exit.

**Key design note:** Both `<FLOAD "77loadall.mud">` and `<SAVE-IT>` are sent before we
wait for the first `^>`. This is correct because:
- The MDL REPL in Confusion uses prompts that do NOT match `^>`.
- The first standalone `>` in the PTY stream is always the Zork RDCOM game prompt.

---

## Task 3: Scenario

**File:** `tests/scenarios/house-boot.json`

```json
{
  "name": "house-boot",
  "fixed_epoch": 250776000,
  "commands": ["north", "west", "open mailbox", "take leaflet", "inventory", "score"]
}
```

`fixed_epoch` = 250776000 = **1977-12-12 12:00:00 UTC**.

Justification: One day before the `mdlzork_771212` game snapshot (`bdcd4a67`). The epoch
makes DSKDATE → day=12, month=12, year=1977 — matching the archive date. The RANDOM seed
is `<CHTYPE <DSKDATE> FIX>` which uses the GETTIMEDATE UVECTOR; with this epoch the seed
is deterministic across machines and time zones when the shim is active.

---

## Task 4: Candidate output

**Run 1:** `python3 scripts/boot_reference.py capture --scenario tests/scenarios/house-boot.json --output artifacts/reference/house-boot.json --timeout 90`  
**Run 2:** same command  
**Result:** byte-identical (ignoring `captured_at` timestamp field) ✓

**Full candidate transcript (boot_output + 6 commands):**

```
boot_output:
  Welcome to 'Confusion', a MDL interpreter.
  Copyright 2009 Matthew T. Russotto
  This Confusion created Nov 22 2026 @ 20:58:42
  ...
  LISTENING-AT-LEVEL 1 PROCESS 1
  81prim.mud loaded
  ...
  77dung.mud loaded
  "DONE"
  Welcome to Dungeon.

  This version created December 12.

  You are in an open field west of a big white house, with a boarded
  front door.
  There is a small mailbox here.

> north
  You are facing the north side of a white house.  There is no door here,
  and all the windows are barred.

> west
  West of House
  There is a small mailbox here.

> open mailbox
  Opening the mailbox reveals a leaflet.

> take leaflet
  Taken.

> inventory
  You are carrying:
  A leaflet

> score

  Your score would be 0 [total of 500 points], in 6 moves.
  This score gives you the rank of Beginner.
```

**Epoch comparison:** With epoch 244598400 (1977-10-02 UTC), only the version line changes:
`"This version created October 2."`. All six command outputs are identical across epochs —
no RNG-visible text in this scenario (commands avoid combat areas).

**Surprise:** "This Confusion created Nov 22 2026 @ 20:58:42" in the banner is the binary's
compile-time timestamp (from the `__DATE__`/`__TIME__` macros in the Confusion source), NOT
from DSKDATE. The shim correctly intercepts only the game's DSKDATE calls; the Confusion
banner compile timestamp is unaffected.

---

## Task 5: Make target and pytest

**Makefile target:** `reference-capture-boot` (runs `scripts/boot_reference.py capture`)  
**Pytest file:** `tests/test_boot_reference.py`  
**Added to:** `Makefile test-python` target  

Test coverage (all without the native binary; native test skips cleanly):
- `test_shim_builds_and_exports_symbols` — gcc required, skips if absent
- `test_shim_freezes_gettimeofday` — gcc required; proves epoch control end-to-end
- `test_capture_boot_with_fake_interpreter` — fake mdli, no binary needed
- `test_capture_boot_requires_commands` — error path
- `test_house_boot_scenario_schema` — JSON schema validation
- `test_house_boot_candidate_exists` — artifact presence check
- `test_boot_reference_determinism` — `@pytest.mark.native`, skips without mdli/gcc

**make test-python result:**

```
30 passed in 8.11s
```

Exit 0, `git diff --check` clean.

---

## Changed files

| File | Status |
|---|---|
| `Makefile` | modified — added `reference-capture-boot` target; added `tests/test_boot_reference.py` to `test-python` |
| `pytest.ini` | new — registers `native` mark |
| `scripts/boot_reference.py` | new |
| `scripts/reference/fixed_time.c` | new |
| `tests/scenarios/house-boot.json` | new |
| `tests/test_boot_reference.py` | new |
| `docs/evidence/M3/house-boot-candidate.json` | new — CANDIDATE transcript |

NOT changed: `mdl/` runtime, `tests/scenarios/house.json`, any upstream source.

---

## Remaining risks and open items

1. **SAVE semantics:** `<SAVE-IT>` requires real Confusion image save/restore semantics.
   The current harness cannot re-enter from ZORK.SAVE via `mdli -r` from a boot-fresh image
   because Confusion's binary image format is not implemented. This capture is therefore
   read-only: it records what the reference does, not what the Racket runtime does.

2. **SAVE-IT → BLOCKED:** The Racket harness will error on `<ON "IPC" ,ILO 1>` before
   reaching SAVE (see STARTUP-CALLGRAPH.md step 3). This capture proves what the reference
   output should look like for a future implementation.

3. **Score discrepancy:** Fresh boot starts with MOVES=0; the approved `house.json`
   (ZORK.SAVE restore) starts at MOVES=2. After `north` + 5 commands = 6 moves total in
   the fresh-boot scenario; the restore scenario has 7 moves. This is correct and expected.

4. **Timezone sensitivity:** DSKDATE uses `localtime_r` after the shim freezes `tv_sec`.
   If the host machine is not UTC, `December 12` might render as `December 11` (for UTC-13
   or similar). The candidate was captured on a UTC+1 host (December 12 output confirmed).
   Future golden approval should note the expected local date string.

---

## Proposed docs/SEMANTICS.md section

```markdown
### Boot-reference entry sequence (run.mud)

The faithful game entry is `run.mud`:
  <FLOAD "77loadall.mud">
  <SAVE-IT>

After FLOAD loads all source, SAVE-IT calls SAVE with FN="<MDL>MADADV.SAVE". In the
patched Confusion build (mdlzork_771212), the patched COND continues in the same clause
as the SAVE success, so the game starts immediately without returning to the MDL REPL.
DSKDATE (via GETTIMEDATE → gettimeofday) determines both the version-date banner and the
RANDOM seed. Clock must be frozen for reproducible captures.

The MDL REPL in Confusion does NOT use '>' as its prompt. The first standalone '>' in the
PTY stream is always the Zork RDCOM game prompt.
```
