"""Tests for the boot_reference capture tooling (BOOT-REF).

Three test layers, in increasing dependency:

1. Shim build: compiles fixed_time.c into $TMPDIR and verifies the .so exports
   gettimeofday / time / clock_gettime, plus demonstrates that a small test
   program returns the fixed epoch value.  Requires gcc.

2. Capture parser: drives a fake interpreter (like test_reference_pty.py) so
   that the pexpect/JSON plumbing is exercised without the native mdli binary.

3. Scenario schema: validates that tests/scenarios/house-boot.json is well-formed
   (has name, commands, fixed_epoch).

Tests that need gcc skip gracefully with pytest.importorskip / skipif.
Tests that need the real mdli binary are separately labelled NATIVE and NOT
added to make test-python; they are opt-in via pytest -m native.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SHIM_SRC = ROOT / "scripts/reference/fixed_time.c"
BOOT_REFERENCE = ROOT / "scripts/boot_reference"  # module path unused; import below
SCENARIO_PATH = ROOT / "tests/scenarios/house-boot.json"


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


# ---------------------------------------------------------------------------
# 1. Shim build and symbol export
# ---------------------------------------------------------------------------

@pytest.mark.skipif(not has_gcc(), reason="gcc not available")
def test_shim_builds_and_exports_symbols(tmp_path: Path) -> None:
    so = build_shim(tmp_path)
    assert so.is_file(), "fixed_time.so not created"
    nm = subprocess.run(["nm", "-D", str(so)], capture_output=True, text=True)
    assert "gettimeofday" in nm.stdout, "gettimeofday not exported"
    assert "time" in nm.stdout, "time not exported"
    assert "clock_gettime" in nm.stdout, "clock_gettime not exported"


@pytest.mark.skipif(not has_gcc(), reason="gcc not available")
def test_shim_freezes_gettimeofday(tmp_path: Path) -> None:
    """With MDL_FIXED_EPOCH set, a program's gettimeofday returns the fixed value."""
    so = build_shim(tmp_path)
    # Compile a tiny test program that prints tv_sec from gettimeofday
    test_src = tmp_path / "probe.c"
    test_src.write_text(
        "#include <stdio.h>\n#include <sys/time.h>\n"
        "int main(void){\n"
        "  struct timeval tv;\n"
        "  gettimeofday(&tv, NULL);\n"
        "  printf(\"%ld\\n\", (long)tv.tv_sec);\n"
        "  return 0;\n"
        "}\n",
        encoding="ascii",
    )
    probe_bin = tmp_path / "probe"
    result = subprocess.run(
        ["gcc", "-o", str(probe_bin), str(test_src)],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, f"probe compile failed:\n{result.stderr}"

    env1 = {**os.environ, "LD_PRELOAD": str(so), "MDL_FIXED_EPOCH": "250776000"}
    env2 = {**os.environ, "LD_PRELOAD": str(so), "MDL_FIXED_EPOCH": "100000000"}
    env3 = {k: v for k, v in os.environ.items()
            if k not in ("LD_PRELOAD", "MDL_FIXED_EPOCH")}

    r1 = subprocess.run([str(probe_bin)], env=env1, capture_output=True, text=True)
    r2 = subprocess.run([str(probe_bin)], env=env2, capture_output=True, text=True)
    r3 = subprocess.run([str(probe_bin)], env=env3, capture_output=True, text=True)

    assert r1.stdout.strip() == "250776000", f"Expected 250776000, got {r1.stdout!r}"
    assert r2.stdout.strip() == "100000000", f"Expected 100000000, got {r2.stdout!r}"
    # Without shim, current time should NOT match fixed epoch
    assert r3.stdout.strip() not in ("250776000", "100000000"), (
        f"Without shim, got a fixed epoch value: {r3.stdout!r}"
    )


# ---------------------------------------------------------------------------
# 2. Capture plumbing (fake interpreter, no native mdli)
# ---------------------------------------------------------------------------

def test_capture_boot_with_fake_interpreter(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """boot_reference.capture_boot works with a fake mdli that echoes '>'."""
    # Fake mdli simulates the real boot sequence:
    # 1. The first two lines from stdin are FLOAD and SAVE-IT (MDL REPL expressions).
    #    Real Confusion's MDL REPL does NOT use '>' as its prompt, so these are
    #    consumed silently (we emit MDL-style noise without any standalone '>').
    # 2. After SAVE-IT, the game banner is printed ending with the first '>' (RDCOM).
    # 3. Subsequent lines are game commands; each produces output ending with '>'.
    fake_exe = tmp_path / "fake-mdli"
    fake_exe.write_text(
        "#!/usr/bin/env python3\n"
        "import sys\n"
        "lines = iter(sys.stdin)\n"
        "# consume FLOAD and SAVE-IT without emitting '>'\n"
        "try:\n"
        "    _ = next(lines)  # <FLOAD ...>\n"
        "    _ = next(lines)  # <SAVE-IT>\n"
        "except StopIteration:\n"
        "    sys.exit(1)\n"
        "# emit banner ending with the first game '>'\n"
        "sys.stdout.write(\n"
        "    '\"DONE\"\\n'\n"
        "    'Welcome to Dungeon.\\n'\n"
        "    'This version created December 12.\\n'\n"
        "    'You are in an open field west of a big white house.\\n'\n"
        "    '>'\n"
        ")\n"
        "sys.stdout.flush()\n"
        "for line in lines:\n"
        "    cmd = line.strip()\n"
        "    sys.stdout.write('CMD:' + cmd + '\\n>')\n"
        "    sys.stdout.flush()\n",
        encoding="utf-8",
    )
    fake_exe.chmod(0o755)

    # Minimal upstream-game-like directory
    fake_game = tmp_path / "game"
    fake_game.mkdir()

    sys.path.insert(0, str(ROOT))
    import scripts.boot_reference as br

    monkeypatch.setattr(br, "EXE", fake_exe)
    monkeypatch.setattr(br, "UPSTREAM_GAME", fake_game)
    monkeypatch.setattr(br, "SHIM_SRC", SHIM_SRC)

    # Patch build_shim to return a dummy .so so we don't need gcc
    dummy_so = tmp_path / "noop.so"
    dummy_so.write_bytes(b"")
    monkeypatch.setattr(br, "build_shim", lambda d: dummy_so)

    scenario = {
        "name": "boot-pty-test",
        "fixed_epoch": 250776000,
        "commands": ["north", "score"],
    }
    result = br.capture_boot(scenario, epoch=250776000, timeout=5, shim_so=dummy_so)

    assert result["complete"], f"Capture failed: {result['error']}"
    assert "Welcome to Dungeon" in result["boot_output"]
    assert result["commands"][0]["input"] == "north"
    assert "CMD:north" in result["commands"][0]["output"]
    assert result["commands"][1]["input"] == "score"
    assert result["fixed_epoch"] == 250776000
    assert result["engine"] == "confusion-patched-1977-boot"


def test_capture_boot_requires_commands(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """capture_boot raises ValueError for missing or empty commands."""
    sys.path.insert(0, str(ROOT))
    import scripts.boot_reference as br

    fake_exe = tmp_path / "fake-mdli"
    fake_exe.write_bytes(b"")
    fake_exe.chmod(0o755)
    fake_game = tmp_path / "game"
    fake_game.mkdir()
    dummy_so = tmp_path / "noop.so"
    dummy_so.write_bytes(b"")

    monkeypatch.setattr(br, "EXE", fake_exe)
    monkeypatch.setattr(br, "UPSTREAM_GAME", fake_game)

    with pytest.raises(ValueError, match="nonempty"):
        br.capture_boot({"name": "x", "commands": []}, epoch=0, timeout=5, shim_so=dummy_so)


# ---------------------------------------------------------------------------
# 3. Scenario schema
# ---------------------------------------------------------------------------

def test_house_boot_scenario_schema() -> None:
    """tests/scenarios/house-boot.json is well-formed."""
    assert SCENARIO_PATH.is_file(), f"Missing scenario: {SCENARIO_PATH}"
    data = json.loads(SCENARIO_PATH.read_text(encoding="utf-8"))
    assert data.get("name") == "house-boot", "Scenario name must be 'house-boot'"
    cmds = data.get("commands")
    assert isinstance(cmds, list) and cmds, "commands must be a nonempty list"
    assert all(isinstance(c, str) for c in cmds), "all commands must be strings"
    assert "fixed_epoch" in data, "Scenario must have fixed_epoch"
    assert isinstance(data["fixed_epoch"], int), "fixed_epoch must be an int"
    assert data["fixed_epoch"] > 0, "fixed_epoch must be positive"
    expected_commands = ["north", "west", "open mailbox", "take leaflet", "inventory", "score"]
    assert cmds == expected_commands, (
        f"Expected SMOKE_PARITY commands {expected_commands}, got {cmds}"
    )


def test_house_boot_candidate_exists() -> None:
    """artifacts/reference/house-boot.json exists and is a CANDIDATE."""
    p = ROOT / "artifacts/reference/house-boot.json"
    assert p.is_file(), f"Missing candidate artifact: {p}"
    data = json.loads(p.read_text(encoding="utf-8"))
    assert data.get("candidate") is True, "Must be marked candidate=True"
    assert data.get("schema_version") == 1
    assert "boot_output" in data
    assert "fixed_epoch" in data


# ---------------------------------------------------------------------------
# NATIVE tests — require the real mdli binary (opt-in: pytest -m native)
# ---------------------------------------------------------------------------

MDLI = ROOT / ".cache/build/confusion_patched/mdli"


@pytest.mark.native
@pytest.mark.skipif(not MDLI.is_file(), reason="native mdli binary not built")
@pytest.mark.skipif(not has_gcc(), reason="gcc not available (shim build)")
def test_boot_reference_determinism(tmp_path: Path) -> None:
    """Two runs with the same epoch produce byte-identical transcripts."""
    sys.path.insert(0, str(ROOT))
    import scripts.boot_reference as br

    shim_so = build_shim(tmp_path)
    scenario = json.loads(SCENARIO_PATH.read_text(encoding="utf-8"))
    epoch = scenario["fixed_epoch"]

    r1 = br.capture_boot(scenario, epoch=epoch, timeout=90, shim_so=shim_so)
    r2 = br.capture_boot(scenario, epoch=epoch, timeout=90, shim_so=shim_so)

    assert r1["complete"], f"Run 1 failed: {r1['error']}"
    assert r2["complete"], f"Run 2 failed: {r2['error']}"

    # Strip captured_at before comparison
    for key in ("captured_at",):
        r1.pop(key, None)
        r2.pop(key, None)

    assert r1 == r2, "Two runs with same epoch are not byte-identical"
