"""Tests for the boot_reference capture tooling (BOOT-REF).

Layers, in increasing dependency:

1. Shim build: compiles fixed_time.c into tmp_path and proves that only the
   wall-clock sources are frozen (gettimeofday, time, CLOCK_REALTIME) while
   CLOCK_MONOTONIC keeps running.  Requires gcc; skips without it.

2. Capture plumbing: drives a fake interpreter so that the pexpect/JSON
   plumbing, banner split, TZ=UTC child environment, relative paths and the
   post-cleanup boot-input hash are exercised without the native mdli binary.

3. Scenario schema, the COMMITTED approved candidate
   (docs/evidence/M3/house-boot-candidate.json, schema 2, unchanged) and the
   S10 fresh capture (docs/evidence/M3/S10-house-boot-reference.json,
   schema 3 provenance split).  These run on a clean checkout; nothing under
   artifacts/ is required.  Gameplay comparison always goes through the
   single comparator scripts/smoke_parity.py (ADR-0053).

4. NATIVE tests (``@pytest.mark.native``) need the real mdli binary.  They are
   excluded from the normal gate by ``addopts = -m "not native"`` in
   pytest.ini and run only through ``make test-boot-reference``.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SHIM_SRC = ROOT / "scripts/reference/fixed_time.c"
SCENARIO_PATH = ROOT / "tests/scenarios/house-boot.json"
CANDIDATE_PATH = ROOT / "docs/evidence/M3/house-boot-candidate.json"
FRESH_PATH = ROOT / "docs/evidence/M3/S10-house-boot-reference.json"
LOCK_PATH = ROOT / "sources.lock.json"

sys.path.insert(0, str(ROOT))
import scripts.boot_reference as br  # noqa: E402
import scripts.smoke_parity as sp  # noqa: E402


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def has_gcc() -> bool:
    return shutil.which("gcc") is not None


def build_shim(tmp_path: Path) -> Path:
    """Compile fixed_time.c into tmp_path and return path to .so."""
    so = tmp_path / "fixed_time.so"
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2",
         "-o", str(so), str(SHIM_SRC), "-ldl"],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, f"gcc failed:\n{result.stderr}"
    return so


def iter_strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for k, v in value.items():
            yield k
            yield from iter_strings(v)
    elif isinstance(value, list):
        for v in value:
            yield from iter_strings(v)


# ---------------------------------------------------------------------------
# 1. Shim build and clock selection
# ---------------------------------------------------------------------------

@pytest.mark.skipif(not has_gcc(), reason="gcc not available")
def test_shim_builds_and_exports_symbols(tmp_path: Path) -> None:
    so = build_shim(tmp_path)
    assert so.is_file(), "fixed_time.so not created"
    nm = subprocess.run(["nm", "-D", str(so)], capture_output=True, text=True)
    assert "gettimeofday" in nm.stdout, "gettimeofday not exported"
    assert " time" in nm.stdout, "time not exported"
    assert "clock_gettime" in nm.stdout, "clock_gettime not exported"


PROBE_C = r"""
#include <stdio.h>
#include <time.h>
#include <sys/time.h>
int main(void){
  struct timeval tv; struct timespec rt, m1, m2;
  struct timespec pause = {0, 50000000};
  gettimeofday(&tv, NULL);
  clock_gettime(CLOCK_REALTIME, &rt);
  clock_gettime(CLOCK_MONOTONIC, &m1);
  nanosleep(&pause, NULL);
  clock_gettime(CLOCK_MONOTONIC, &m2);
  long long dm = (m2.tv_sec - m1.tv_sec) * 1000000000LL + (m2.tv_nsec - m1.tv_nsec);
  printf("%ld %ld %ld %ld %lld\n", (long)tv.tv_sec, (long)time(NULL),
         (long)rt.tv_sec, (long)m1.tv_sec, dm);
  return 0;
}
"""


@pytest.mark.skipif(not has_gcc(), reason="gcc not available")
def test_shim_freezes_wall_clock_only(tmp_path: Path) -> None:
    """gettimeofday/time/CLOCK_REALTIME are frozen; CLOCK_MONOTONIC advances."""
    so = build_shim(tmp_path)
    src = tmp_path / "probe.c"
    src.write_text(PROBE_C, encoding="ascii")
    probe = tmp_path / "probe"
    result = subprocess.run(["gcc", "-o", str(probe), str(src)],
                            capture_output=True, text=True)
    assert result.returncode == 0, f"probe compile failed:\n{result.stderr}"

    base = {k: v for k, v in os.environ.items()
            if k not in ("LD_PRELOAD", "MDL_FIXED_EPOCH")}

    def run(epoch: str | None) -> list[int]:
        env = dict(base)
        if epoch is not None:
            env.update(LD_PRELOAD=str(so), MDL_FIXED_EPOCH=epoch)
        out = subprocess.run([str(probe)], env=env, capture_output=True,
                             text=True, check=True).stdout.split()
        return [int(x) for x in out]

    for epoch in ("250776000", "100000000"):
        gtod, t, rt, mono, dmono = run(epoch)
        assert gtod == t == rt == int(epoch), (gtod, t, rt)
        assert mono != int(epoch), "CLOCK_MONOTONIC must not be frozen"
        assert dmono >= 40_000_000, f"CLOCK_MONOTONIC did not advance: {dmono} ns"

    gtod, t, rt, _mono, _d = run(None)
    assert gtod not in (250776000, 100000000), "inactive shim froze the clock"


# ---------------------------------------------------------------------------
# 2. Capture plumbing (fake interpreter, no native mdli)
# ---------------------------------------------------------------------------

FAKE_MDLI = r"""#!/usr/bin/env python3
import os, sys
sys.stdout.write("Welcome to 'Confusion', a MDL interpreter.\n"
                 "This Confusion created Jan  1 2000 @ 00:00:00\n\n"
                 "LISTENING-AT-LEVEL 1 PROCESS 1\n")
sys.stdout.flush()
lines = iter(sys.stdin)
try:
    next(lines)  # <FLOAD ...>
    next(lines)  # <SAVE-IT>
except StopIteration:
    sys.exit(1)
with open("MDL/MADADV.SAVE", "wb") as fh:   # SAVE-IT's image (cwd = game copy)
    fh.write(b"new image")
EXTRA_WRITE = None
if EXTRA_WRITE:
    with open(EXTRA_WRITE, "a") as fh:
        fh.write("written during the run\n")
sys.stdout.write('"DONE"\nTZ=' + os.environ.get("TZ", "<unset>") + "\n"
                 "Welcome to Dungeon.\nThis version created December 12.\n>")
sys.stdout.flush()
for line in lines:
    sys.stdout.write("CMD:" + line.strip() + "\n>")
    sys.stdout.flush()
"""


@pytest.fixture
def fake_env(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    fake_exe = tmp_path / "fake-mdli"
    fake_exe.write_text(FAKE_MDLI, encoding="utf-8")
    fake_exe.chmod(0o755)
    upstream_root = tmp_path / "upstream"
    game = upstream_root / "mdlzork_771212" / "patched_confusion"
    (game / "SAVEFILE").mkdir(parents=True)
    (game / "SAVEFILE" / "ZORK.SAVE").write_bytes(b"stale image")
    (game / "MDL").mkdir()
    (game / "MDL" / "MADADV.SAVE").write_bytes(b"old image")
    (game / "run.mud").write_text('<FLOAD "77loadall.mud">\n<SAVE-IT>\n')
    monkeypatch.setattr(br, "EXE", fake_exe)
    monkeypatch.setattr(br, "UPSTREAM_ROOT", upstream_root)
    monkeypatch.setattr(br, "UPSTREAM_GAME", game)
    dummy_so = tmp_path / "noop.so"
    dummy_so.write_bytes(b"")
    return dummy_so


def test_capture_boot_with_fake_interpreter(fake_env: Path) -> None:
    scenario = {"name": "boot-pty-test", "fixed_epoch": 250776000,
                "commands": ["north", "score"]}
    result = br.capture_boot(scenario, epoch=250776000, timeout=5, shim_so=fake_env)

    assert result["complete"], f"Capture failed: {result['error']}"
    assert result["engine"] == "confusion-patched-1977-boot"
    assert result["fixed_epoch"] == 250776000
    assert result["tz"] == "UTC"
    # Child really ran with TZ=UTC.
    assert "TZ=UTC" in result["boot_output"]
    # Interpreter banner (with compile timestamp) is informational only.
    banner = result["informational"]["interpreter_banner"]
    assert "This Confusion created" in banner
    assert "This Confusion created" not in result["boot_output"]
    assert result["boot_output"].startswith("LISTENING-AT-LEVEL 1 PROCESS 1\n")
    assert "Welcome to Dungeon" in result["boot_output"]
    assert result["commands"][0]["input"] == "north"
    assert "CMD:north" in result["commands"][0]["output"]
    assert result["commands"][1]["input"] == "score"
    # Paths are relative; no absolute path anywhere in the record.
    assert result["run_mud"] == "mdlzork_771212/patched_confusion/run.mud"
    for s in iter_strings(result):
        assert not s.startswith("/"), f"absolute path in record: {s!r}"
    # Schema 3 provenance split (S10): immutable pre-boot inputs, hashed
    # AFTER the stale save image is removed, never include SAVE artifacts.
    assert result["schema_version"] == 3
    inputs = result["provenance"]["immutable_inputs"]
    assert inputs["removed_before_boot"] == ["SAVEFILE/ZORK.SAVE"]
    assert set(inputs["game_files"]) == {"run.mud"}
    assert "MDL/MADADV.SAVE" not in inputs["game_files"]
    assert inputs["game_files_sha256"] == br.sha256_manifest(inputs["game_files"])
    assert inputs["entry"] == list(br.ENTRY)
    assert inputs["scenario"]["commands"] == ["north", "score"]
    assert inputs["clock_shim"] == {"path": "scripts/reference/fixed_time.c",
                                    "sha256": br.sha256_file(SHIM_SRC)}
    assert inputs["interpreter"]["sha256"] == br.sha256_file(br.EXE)
    # SAVE-created/overwritten artifacts: before/after hashes, not inputs.
    saved = result["provenance"]["save_artifacts"]["files"]
    assert set(saved) == {"MDL/MADADV.SAVE"}
    assert saved["MDL/MADADV.SAVE"] == {
        "before": hashlib.sha256(b"old image").hexdigest(),
        "after": hashlib.sha256(b"new image").hexdigest()}
    # Gameplay view excludes informational metadata.
    view = br.gameplay_view(result)
    assert set(view) == set(br.STRICT_FIELDS)
    assert "informational" not in view and "provenance" not in view


def test_capture_boot_rejects_missing_banner_terminator(
        fake_env: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """A Confusion banner without LISTENING-AT-LEVEL must fail, not leak."""
    exe = tmp_path / "bad-mdli"
    exe.write_text(FAKE_MDLI.replace("LISTENING-AT-LEVEL 1 PROCESS 1\\n", ""),
                   encoding="utf-8")
    exe.chmod(0o755)
    monkeypatch.setattr(br, "EXE", exe)
    result = br.capture_boot({"name": "x", "commands": ["look"]},
                             epoch=1, timeout=5, shim_so=fake_env)
    assert not result["complete"]
    assert "banner" in result["error"]


@pytest.mark.parametrize("target, message", [
    ("run.mud", "immutable input changed during run: run.mud"),
    ("NEW.FILE", "undeclared file written during run: NEW.FILE"),
])
def test_capture_boot_fails_on_write_outside_save_artifacts(
        fake_env: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
        target: str, message: str) -> None:
    """Only SAVE_ARTIFACTS may be written; anything else fails the capture."""
    exe = tmp_path / "writing-mdli"
    exe.write_text(FAKE_MDLI.replace("EXTRA_WRITE = None", f"EXTRA_WRITE = {target!r}"),
                   encoding="utf-8")
    exe.chmod(0o755)
    monkeypatch.setattr(br, "EXE", exe)
    result = br.capture_boot({"name": "x", "commands": ["look"]},
                             epoch=1, timeout=5, shim_so=fake_env)
    assert not result["complete"]
    assert message in result["error"]


def test_capture_boot_requires_commands(fake_env: Path) -> None:
    with pytest.raises(ValueError, match="nonempty"):
        br.capture_boot({"name": "x", "commands": []}, epoch=0, timeout=5,
                        shim_so=fake_env)


def test_comparator_ignores_informational_and_provenance() -> None:
    a = json.loads(CANDIDATE_PATH.read_text(encoding="utf-8"))
    b = json.loads(json.dumps(a))
    b["informational"]["captured_at"] = "1999-01-01T00:00:00+00:00"
    b["informational"]["interpreter_banner"] = "This Confusion created X\n"
    b["provenance"]["engine_sha256"] = "0" * 64
    assert sp.compare_records(a, b) == []
    b["commands"][3]["output"] = "You already have it.\n"
    assert [m["check"] for m in sp.compare_records(a, b)] == ["command[3] 'take leaflet'"]


# ---------------------------------------------------------------------------
# 3. Scenario schema and committed candidate (clean checkout, no artifacts/)
# ---------------------------------------------------------------------------

EXPECTED_COMMANDS = ["north", "west", "open mailbox", "take leaflet",
                     "inventory", "score"]


def test_house_boot_scenario_schema() -> None:
    assert SCENARIO_PATH.is_file(), f"Missing scenario: {SCENARIO_PATH}"
    data = json.loads(SCENARIO_PATH.read_text(encoding="utf-8"))
    assert data.get("name") == "house-boot"
    cmds = data.get("commands")
    assert cmds == EXPECTED_COMMANDS
    assert isinstance(data.get("fixed_epoch"), int) and data["fixed_epoch"] > 0


def test_committed_house_boot_candidate() -> None:
    """The committed candidate is portable and holds the approved transcript."""
    assert CANDIDATE_PATH.is_file(), f"Missing committed candidate: {CANDIDATE_PATH}"
    text = CANDIDATE_PATH.read_text(encoding="utf-8")
    data = json.loads(text)
    scenario = json.loads(SCENARIO_PATH.read_text(encoding="utf-8"))
    lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))

    assert data["candidate"] is True
    # The approved capture is kept unchanged at schema 2 (never regenerated);
    # its gameplay fields have the same layout as schema 3.
    assert data["schema_version"] == 2
    assert data["schema_version"] in br.COMPARABLE_SCHEMA_VERSIONS
    assert data["complete"] is True and data["error"] is None
    assert data["scenario"] == scenario["name"]
    assert data["fixed_epoch"] == scenario["fixed_epoch"]
    assert data["tz"] == "UTC"
    assert data["entry"] == list(br.ENTRY)

    # No absolute developer-machine paths anywhere.
    assert "/home" not in text and "/tmp" not in text
    for s in iter_strings(data):
        assert not s.startswith("/"), f"absolute path: {s!r}"
    assert data["run_mud"] == "mdlzork_771212/patched_confusion/run.mud"

    # Banner (compile timestamp) is not in any compared field.
    compared = json.dumps(br.gameplay_view(data))
    assert "This Confusion created" not in compared
    assert "This Confusion created" in data["informational"]["interpreter_banner"]

    # Provenance: pinned upstream source vs. post-cleanup boot-input state.
    up = data["provenance"]["upstream_source"]
    assert up["commit"] == lock["sources"]["mdlzork"]["commit"]
    assert up["checked_out_commit"] == up["commit"]
    state = data["provenance"]["boot_input_state"]
    assert state["removed_before_boot"] == ["SAVEFILE/ZORK.SAVE"]
    assert "SAVEFILE/ZORK.SAVE" not in state["files"]
    assert state["sha256"] == br.sha256_manifest(state["files"])

    # Known schema-2 flaw (corrected by schema 3): boot_input_state lists the
    # SAVE-overwritten MDL/MADADV.SAVE as if it were a boot input.
    assert "MDL/MADADV.SAVE" in state["files"]

    # Approved gameplay (maintainer decision 2026-11-22).
    assert [c["input"] for c in data["commands"]] == EXPECTED_COMMANDS
    assert all(c["prompt_returned"] for c in data["commands"])
    outputs = {c["input"]: c["output"] for c in data["commands"]}
    assert outputs["take leaflet"] == "Taken.\n"
    assert "You already have it." not in compared
    assert "in 6 moves." in outputs["score"]
    assert "This version created December 12." in data["boot_output"]


def test_committed_fresh_reference_provenance_split() -> None:
    """S10 fresh capture (schema 3): immutable inputs vs SAVE artifacts."""
    text = FRESH_PATH.read_text(encoding="utf-8")
    fresh = json.loads(text)
    legacy = json.loads(CANDIDATE_PATH.read_text(encoding="utf-8"))
    lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    assert fresh["schema_version"] == br.SCHEMA_VERSION == 3
    assert fresh["complete"] is True and fresh["error"] is None
    assert "/home" not in text and "/tmp" not in text
    for s in iter_strings(fresh):
        assert not s.startswith("/"), f"absolute path: {s!r}"
    assert "boot_input_state" not in fresh["provenance"]
    assert fresh["provenance"]["upstream_source"] == legacy["provenance"]["upstream_source"]
    assert fresh["provenance"]["upstream_source"]["commit"] == lock["sources"]["mdlzork"]["commit"]

    inputs = fresh["provenance"]["immutable_inputs"]
    saved = fresh["provenance"]["save_artifacts"]["files"]
    assert "MDL/MADADV.SAVE" not in inputs["game_files"]
    assert set(saved) == {"MDL/MADADV.SAVE"}
    # The immutable game files are exactly the approved capture's boot inputs
    # minus the SAVE artifact, byte for byte (same hashes).
    legacy_files = dict(legacy["provenance"]["boot_input_state"]["files"])
    legacy_save = legacy_files.pop("MDL/MADADV.SAVE")
    assert inputs["game_files"] == legacy_files
    assert inputs["game_files_sha256"] == br.sha256_manifest(inputs["game_files"])
    assert saved["MDL/MADADV.SAVE"]["before"] == legacy_save
    assert saved["MDL/MADADV.SAVE"]["after"] not in (None, legacy_save)
    assert inputs["removed_before_boot"] == ["SAVEFILE/ZORK.SAVE"]
    assert inputs["entry"] == list(br.ENTRY)
    assert inputs["interpreter"]["path"] == ".cache/build/confusion_patched/mdli"
    assert inputs["interpreter"]["sha256"] == legacy["provenance"]["engine_sha256"]
    assert inputs["clock_shim"] == {"path": "scripts/reference/fixed_time.c",
                                    "sha256": br.sha256_file(SHIM_SRC)}
    assert inputs["scenario"]["path"] == "tests/scenarios/house-boot.json"
    assert inputs["scenario"]["sha256"] == br.sha256_file(SCENARIO_PATH)
    assert inputs["scenario"]["commands"] == EXPECTED_COMMANDS
    # Gameplay identical to the approved capture through the one comparator.
    assert sp.compare_records(legacy, fresh) == []


# ---------------------------------------------------------------------------
# 4. NATIVE tests — real mdli binary; run via `make test-boot-reference`
# ---------------------------------------------------------------------------

MDLI = ROOT / ".cache/build/confusion_patched/mdli"


@pytest.mark.native
@pytest.mark.skipif(not MDLI.is_file(), reason="native mdli binary not built")
@pytest.mark.skipif(not has_gcc(), reason="gcc not available (shim build)")
def test_boot_reference_matches_committed_candidate(tmp_path: Path) -> None:
    """Two fresh captures agree with each other and with the committed candidate."""
    shim_so = build_shim(tmp_path)
    scenario = json.loads(SCENARIO_PATH.read_text(encoding="utf-8"))
    epoch = scenario["fixed_epoch"]
    committed = json.loads(CANDIDATE_PATH.read_text(encoding="utf-8"))

    r1 = br.capture_boot(scenario, epoch=epoch, timeout=90, shim_so=shim_so,
                         scenario_path=SCENARIO_PATH)
    r2 = br.capture_boot(scenario, epoch=epoch, timeout=90, shim_so=shim_so,
                         scenario_path=SCENARIO_PATH)
    assert r1["complete"], f"Run 1 failed: {r1['error']}"
    assert r2["complete"], f"Run 2 failed: {r2['error']}"
    assert sp.compare_records(r1, r2) == []
    assert sp.compare_records(committed, r1) == []
    # Immutable inputs are identical; SAVE artifacts agree before the run
    # (their after-hash is Confusion's heap image and is never compared).
    assert r1["provenance"]["immutable_inputs"] == r2["provenance"]["immutable_inputs"]
    p1, p2 = (r["provenance"]["save_artifacts"]["files"] for r in (r1, r2))
    assert {k: v["before"] for k, v in p1.items()} == {k: v["before"] for k, v in p2.items()}
    legacy_files = dict(committed["provenance"]["boot_input_state"]["files"])
    assert p1["MDL/MADADV.SAVE"]["before"] == legacy_files.pop("MDL/MADADV.SAVE")
    assert r1["provenance"]["immutable_inputs"]["game_files"] == legacy_files
    assert (r1["provenance"]["upstream_source"]
            == committed["provenance"]["upstream_source"])
