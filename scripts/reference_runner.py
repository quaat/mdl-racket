#!/usr/bin/env python3
"""Capture interactive Confusion transcripts in a normalized JSON envelope.

M0 harness uses a pseudo-terminal via pexpect. The historical program's
READSTRING/READCHR behavior can require adjustments. A timeout is FAILURE,
not a passing reference. No automatic golden updates.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pexpect

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / ".cache/upstream/mdlzork/mdlzork_771212/patched_confusion"
EXE = ROOT / ".cache/build/confusion_patched/mdli"
IMAGE = GAME / "SAVEFILE/ZORK.SAVE"
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
PROMPT = re.compile(r"(?m)^>")


def canonical_text(text: str) -> str:
    """Normalize PTY transport only; never strip semantic whitespace."""
    return ANSI.sub("", text.replace("\r\n", "\n").replace("\r", "\n"))


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def capture(scenario: dict[str, Any], timeout: float) -> dict[str, Any]:
    if not EXE.is_file() or not IMAGE.is_file():
        raise RuntimeError("Confusion binary/game image missing. Run: make reference-build")
    commands = scenario["commands"]
    if not isinstance(commands, list) or not commands or not all(isinstance(x, str) for x in commands):
        raise ValueError("Scenario commands must be a nonempty list of strings")
    # Do not run an interpreter with write access beyond the game tree in CI/production.
    child = pexpect.spawn(str(EXE), ["-r", "SAVEFILE/ZORK.SAVE"],
                          cwd=str(GAME), encoding="utf-8", codec_errors="replace",
                          echo=False, timeout=timeout, dimensions=(40, 100))
    child.delaybeforesend = 0.05
    record: dict[str, Any] = {
        "schema_version": 1,
        "engine": "confusion-patched-1977",
        "scenario": scenario["name"],
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "engine_sha256": sha256(EXE),
        "game_sha256": sha256(IMAGE),
        "commands": [],
        "initial_output": "",
        "complete": False,
        "error": None,
    }
    try:
        # RDCOM writes '>' at the start of a line. The banner contains
        # <WARRANTY> and <COPYING>, which are not prompts.
        child.expect(PROMPT)
        record["initial_output"] = canonical_text(child.before)
        for command in commands:
            child.sendline(command)
            try:
                idx = child.expect([PROMPT, pexpect.EOF, pexpect.TIMEOUT])
            except OSError as exc:
                raise RuntimeError(f"PTY failure after {command!r}: {exc}") from exc
            record["commands"].append({"input": command,
                                       "output": canonical_text(child.before),
                                       "prompt_returned": idx == 0})
            if idx == 2:
                raise RuntimeError(f"Timed out waiting for command response: {command!r}")
            if idx == 1 and command != commands[-1]:
                raise RuntimeError(f"Game exited before last command: {command!r}")
        record["complete"] = True
    except (pexpect.ExceptionPexpect, RuntimeError) as exc:
        record["error"] = str(exc)
    finally:
        if child.isalive():
            child.terminate(force=True)
        child.close()
        record["process_exitstatus"] = child.exitstatus
        record["process_signalstatus"] = child.signalstatus
    return record


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    cap = sub.add_parser("capture", help="Run the pinned native reference and capture results")
    cap.add_argument("--scenario", type=Path, required=True)
    cap.add_argument("--output", type=Path, required=True)
    cap.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args()
    scenario = json.loads(args.scenario.read_text(encoding="utf-8"))
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    record = capture(scenario, args.timeout)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if not record["complete"]:
        print(f"REFERENCE FAILED: {record['error']}\nEvidence: {args.output}", file=sys.stderr)
        return 1
    print(f"Captured {len(record['commands'])} turns: {args.output}")
    print("Review and approve transcripts before turning them into golden fixtures.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, OSError, json.JSONDecodeError) as exc:
        print(f"reference_runner: {exc}", file=sys.stderr)
        raise SystemExit(1)
