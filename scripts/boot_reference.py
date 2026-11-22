#!/usr/bin/env python3
"""Capture a fresh-boot Confusion transcript for the BOOT-REF smoke scenario.

Unlike reference_runner.py (which restores from ZORK.SAVE with -r), this script
starts Confusion without -r and drives the faithful entry sequence:

    <FLOAD "77loadall.mud">
    <SAVE-IT>

After SAVE-IT the game starts immediately (SAVE returns "SAVED" and the COND
in 77rooms.mud continues in the same clause). The first game prompt '>' then
appears. We then send the scenario commands and record the transcript.

Clock control: the LD_PRELOAD shim scripts/reference/fixed_time.c intercepts
gettimeofday/time/clock_gettime so that DSKDATE is deterministic. The shim is
compiled at run time into $TMPDIR (or .cache/build/shim/) and must NOT be
committed as a binary.

Transcript schema is a superset of reference_runner.py's schema (schema_version 1),
adding: run_mud, fixed_epoch, boot_output, engine_sha256, game_files_sha256.

Usage (see also Makefile reference-capture-boot):
    python3 scripts/boot_reference.py capture \\
        --scenario tests/scenarios/house-boot.json \\
        --output artifacts/reference/house-boot.json \\
        --epoch 250776000
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pexpect

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / ".cache/build/confusion_patched/mdli"
UPSTREAM_GAME = ROOT / ".cache/upstream/mdlzork/mdlzork_771212/patched_confusion"
SHIM_SRC = ROOT / "scripts/reference/fixed_time.c"

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
# RDCOM prints '>' at the beginning of a line; don't match MDL type brackets
PROMPT = re.compile(r"(?m)^>")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def canonical_text(text: str) -> str:
    """Normalize PTY transport only; never strip semantic whitespace."""
    return ANSI.sub("", text.replace("\r\n", "\n").replace("\r", "\n"))


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_tree(directory: Path) -> str:
    """Stable SHA-256 of all regular files in a directory (sorted paths)."""
    h = hashlib.sha256()
    for child in sorted(directory.rglob("*")):
        if child.is_file():
            rel = str(child.relative_to(directory))
            h.update(rel.encode())
            h.update(sha256_file(child).encode())
    return h.hexdigest()


def build_shim(output_dir: Path) -> Path:
    """Compile the fixed_time LD_PRELOAD shim and return path to the .so."""
    output_dir.mkdir(parents=True, exist_ok=True)
    so_path = output_dir / "fixed_time.so"
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2",
         "-o", str(so_path), str(SHIM_SRC), "-ldl"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"Failed to compile fixed_time shim:\n{result.stderr}"
        )
    return so_path


# ---------------------------------------------------------------------------
# Core capture
# ---------------------------------------------------------------------------

def capture_boot(scenario: dict[str, Any], epoch: int, timeout: float,
                 shim_so: Path | None = None) -> dict[str, Any]:
    """
    Run a fresh-boot reference capture.

    Copies the upstream game directory to a fresh temp dir so that mdli can
    write MDL/ZORK.SAVE (and MDL/ZORK.LOG if any) without dirtying
    .cache/upstream. The copy is deleted on return.

    Parameters
    ----------
    scenario:
        Parsed scenario dict; must have 'name' and 'commands' keys.
    epoch:
        Unix epoch (seconds since 1970-01-01 UTC) to pass as MDL_FIXED_EPOCH.
        Frozen by the LD_PRELOAD shim.
    timeout:
        Per-interaction timeout for pexpect.
    shim_so:
        Path to the compiled fixed_time.so. If None, the shim is compiled now.
    """
    if not EXE.is_file():
        raise RuntimeError(
            f"Confusion binary missing: {EXE}\n"
            "Build it with: make reference-build"
        )
    if not UPSTREAM_GAME.is_dir():
        raise RuntimeError(
            f"Upstream game directory missing: {UPSTREAM_GAME}\n"
            "Fetch sources with: make sources"
        )

    commands = scenario.get("commands", [])
    if not isinstance(commands, list) or not commands:
        raise ValueError("Scenario 'commands' must be a nonempty list of strings.")

    # Compile shim once if needed
    if shim_so is None:
        shim_dir = ROOT / ".cache/build/shim"
        shim_so = build_shim(shim_dir)

    # Fresh copy of game dir — mdli writes SAVE files here
    tmpdir = Path(tempfile.mkdtemp(prefix="mdl-boot-ref-"))
    game_dir = tmpdir / "game"
    try:
        shutil.copytree(str(UPSTREAM_GAME), str(game_dir))
        game_files_sha256 = sha256_tree(game_dir)

        env = dict(os.environ)
        env["MDL_FIXED_EPOCH"] = str(epoch)
        env["LD_PRELOAD"] = str(shim_so)
        # Ensure no stale ZORK.SAVE interferes
        stale = game_dir / "SAVEFILE" / "ZORK.SAVE"
        if stale.exists():
            stale.unlink()

        record: dict[str, Any] = {
            "schema_version": 1,
            "engine": "confusion-patched-1977-boot",
            "scenario": scenario["name"],
            "run_mud": str(UPSTREAM_GAME / "run.mud"),
            "fixed_epoch": epoch,
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "engine_sha256": sha256_file(EXE),
            "game_files_sha256": game_files_sha256,
            "boot_output": "",
            "commands": [],
            "complete": False,
            "error": None,
        }

        child = pexpect.spawn(
            str(EXE), [],
            cwd=str(game_dir),
            env=env,
            encoding="utf-8", codec_errors="replace",
            echo=False, timeout=timeout, dimensions=(40, 100),
        )
        child.delaybeforesend = 0.1

        try:
            # Phase 1: send the MDL boot expressions.
            # We pipe them quickly; Confusion's LISTEN will read and eval them.
            # <FLOAD "77loadall.mud"> prints "DONE" and returns.
            # <SAVE-IT> writes the save image, then immediately enters the game
            # via the patched COND in 77rooms.mud (the same COND-clause as the
            # SAVE success), printing the Welcome banner and the first '>'.
            #
            # We send both before waiting so we don't have to identify the MDL
            # LISTEN prompt, which Confusion may format differently from the
            # game's RDCOM '>'.
            child.sendline('<FLOAD "77loadall.mud">')
            child.sendline("<SAVE-IT>")

            # Phase 2: wait for the first game prompt '>' that RDCOM emits.
            # This covers the banner, room description, and initial '>'.
            child.expect(PROMPT, timeout=timeout)
            boot_raw = canonical_text(child.before)
            record["boot_output"] = boot_raw

            # Phase 3: send scenario commands, waiting for '>' after each.
            for cmd in commands:
                child.sendline(cmd)
                try:
                    idx = child.expect([PROMPT, pexpect.EOF, pexpect.TIMEOUT],
                                       timeout=timeout)
                except OSError as exc:
                    raise RuntimeError(
                        f"PTY failure after {cmd!r}: {exc}"
                    ) from exc
                record["commands"].append({
                    "input": cmd,
                    "output": canonical_text(child.before),
                    "prompt_returned": idx == 0,
                })
                if idx == 2:
                    raise RuntimeError(
                        f"Timed out waiting for command response: {cmd!r}"
                    )
                if idx == 1 and cmd != commands[-1]:
                    raise RuntimeError(
                        f"Game exited before last command: {cmd!r}"
                    )
            record["complete"] = True

        except (pexpect.ExceptionPexpect, RuntimeError) as exc:
            record["error"] = str(exc)
        finally:
            if child.isalive():
                child.terminate(force=True)
            child.close()
            record["process_exitstatus"] = child.exitstatus
            record["process_signalstatus"] = child.signalstatus

    finally:
        shutil.rmtree(str(tmpdir), ignore_errors=True)

    return record


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)

    cap = sub.add_parser(
        "capture",
        help="Run a fresh-boot Confusion reference and capture results.",
    )
    cap.add_argument("--scenario", type=Path, required=True,
                     help="Scenario JSON (must include 'commands').")
    cap.add_argument("--output", type=Path, required=True,
                     help="Output transcript JSON path.")
    cap.add_argument("--epoch", type=int, default=None,
                     help=(
                         "Unix epoch to freeze (MDL_FIXED_EPOCH). "
                         "If omitted, taken from scenario['fixed_epoch']."
                     ))
    cap.add_argument("--timeout", type=float, default=60,
                     help="Per-interaction PTY timeout in seconds (default 60).")

    args = parser.parse_args()

    if not args.scenario.is_file():
        print(f"boot_reference: scenario not found: {args.scenario}", file=sys.stderr)
        return 1

    scenario = json.loads(args.scenario.read_text(encoding="utf-8"))

    epoch = args.epoch
    if epoch is None:
        epoch = scenario.get("fixed_epoch")
    if epoch is None:
        print(
            "boot_reference: --epoch not provided and scenario has no 'fixed_epoch'.",
            file=sys.stderr,
        )
        return 1

    if args.timeout <= 0:
        print("boot_reference: --timeout must be positive.", file=sys.stderr)
        return 1

    try:
        record = capture_boot(scenario, epoch, args.timeout)
    except (RuntimeError, ValueError, OSError) as exc:
        print(f"boot_reference: {exc}", file=sys.stderr)
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(record, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    if not record["complete"]:
        print(
            f"BOOT REFERENCE FAILED: {record['error']}\nEvidence: {args.output}",
            file=sys.stderr,
        )
        return 1

    print(f"Boot captured {len(record['commands'])} turns: {args.output}")
    print(
        "CANDIDATE — review and approve before turning into a golden fixture.\n"
        "Run twice with the same --epoch; transcripts must be byte-identical."
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, OSError, json.JSONDecodeError) as exc:
        print(f"boot_reference: {exc}", file=sys.stderr)
        raise SystemExit(1)
