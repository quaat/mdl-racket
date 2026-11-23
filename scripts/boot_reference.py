#!/usr/bin/env python3
"""Capture a fresh-boot Confusion transcript for the BOOT-REF smoke scenario.

Unlike reference_runner.py (which restores from ZORK.SAVE with -r), this script
starts Confusion without -r and drives the faithful entry sequence (run.mud):

    <FLOAD "77loadall.mud">
    <SAVE-IT>

After SAVE-IT the game starts immediately (SAVE returns "SAVED" and the COND
in 77rooms.mud continues in the same clause). The first game prompt '>' then
appears. We then send the scenario commands and record the transcript.

Clock control: the LD_PRELOAD shim scripts/reference/fixed_time.c freezes the
wall clock only (gettimeofday, time, clock_gettime for CLOCK_REALTIME*);
CLOCK_MONOTONIC and CPU clocks are untouched. The child runs with TZ=UTC so
GETTIMEDATE's localtime_r is a deterministic function of the frozen epoch.
The shim is compiled per capture into the capture's temp dir and is never
committed as a binary.

Record layout (schema_version 2):
  * STRICT_FIELDS — the gameplay view compared for parity (see gameplay_view):
    scenario, fixed_epoch, tz, entry, boot_output, commands, complete.
    boot_output starts at "LISTENING-AT-LEVEL"; the Confusion banner (which
    contains the binary's compile timestamp) is moved to
    informational.interpreter_banner and never compared.
  * provenance.upstream_source — pinned mdlzork commit from sources.lock.json
    plus the commit actually checked out, and the game dir RELATIVE to the
    upstream checkout root.
  * provenance.boot_input_state — per-file SHA-256 manifest (relative paths)
    of the game directory AFTER the stale save image is removed, i.e. the
    effective boot inputs, plus its aggregate hash.
  * provenance.engine_sha256 — build-specific (Confusion embeds __DATE__);
    informational, not part of gameplay parity.
  * informational — captured_at, interpreter_banner, process exit status.

Usage (see also Makefile reference-capture-boot / test-boot-reference):
    python3 scripts/boot_reference.py capture \\
        --scenario tests/scenarios/house-boot.json \\
        --output artifacts/reference/house-boot.json
    python3 scripts/boot_reference.py compare \\
        docs/evidence/M3/house-boot-candidate.json artifacts/reference/house-boot.json
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
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
UPSTREAM_NAME = "mdlzork"
UPSTREAM_ROOT = ROOT / ".cache/upstream" / UPSTREAM_NAME
UPSTREAM_GAME = UPSTREAM_ROOT / "mdlzork_771212/patched_confusion"
SHIM_SRC = ROOT / "scripts/reference/fixed_time.c"
LOCK_FILE = ROOT / "sources.lock.json"

SCHEMA_VERSION = 2
CHILD_TZ = "UTC"
ENTRY = ('<FLOAD "77loadall.mud">', "<SAVE-IT>")
# Files removed from the per-capture game copy before boot (relative paths).
STALE_BOOT_FILES = ("SAVEFILE/ZORK.SAVE",)
# Fields that make up the gameplay view used for strict parity.
STRICT_FIELDS = ("scenario", "fixed_epoch", "tz", "entry", "boot_output",
                 "commands", "complete")
CONFUSION_BANNER_START = "Welcome to 'Confusion'"
BANNER_END = "LISTENING-AT-LEVEL"
CANDIDATE_NOTE = ("CANDIDATE: gameplay approved by maintainer 2026-11-22; NOT yet "
                  "a strict golden fixture. Compare only STRICT_FIELDS "
                  "(scripts/boot_reference.py compare).")

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


def file_manifest(directory: Path) -> dict[str, str]:
    """Map POSIX-relative path -> SHA-256 for every regular file under directory."""
    return {
        child.relative_to(directory).as_posix(): sha256_file(child)
        for child in sorted(directory.rglob("*"))
        if child.is_file()
    }


def sha256_manifest(manifest: dict[str, str]) -> str:
    """Aggregate hash of a file manifest (sorted 'path\\0sha\\n' lines)."""
    h = hashlib.sha256()
    for rel in sorted(manifest):
        h.update(f"{rel}\0{manifest[rel]}\n".encode())
    return h.hexdigest()


def relative_posix(path: Path, base: Path) -> str:
    """Path relative to base as POSIX text; refuse to emit an absolute path."""
    try:
        rel = path.resolve().relative_to(base.resolve()).as_posix()
    except ValueError as exc:
        raise RuntimeError(f"{path} is not under {base}") from exc
    return rel


def pinned_commit(name: str) -> str | None:
    try:
        lock = json.loads(LOCK_FILE.read_text(encoding="utf-8"))
        return lock["sources"][name]["commit"]
    except (OSError, KeyError, json.JSONDecodeError):
        return None


def checked_out_commit(repo: Path) -> str | None:
    if not (repo / ".git").exists():
        return None
    result = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"],
                            capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def split_banner(text: str) -> tuple[str, str]:
    """Split the Confusion start-up banner from the MDL/game output.

    The banner carries the binary's compile timestamp and is therefore not
    gameplay. Fail loudly if a Confusion banner is present but its terminator
    is not, rather than leaking the timestamp into the compared text.
    """
    if CONFUSION_BANNER_START not in text:
        return "", text
    idx = text.find(BANNER_END)
    if idx < 0:
        raise RuntimeError(
            f"Confusion banner found but no {BANNER_END!r} terminator; "
            "refusing to record banner text as gameplay"
        )
    return text[:idx], text[idx:]


def gameplay_view(record: dict[str, Any]) -> dict[str, Any]:
    """Return only the fields that participate in strict gameplay parity."""
    return {key: record.get(key) for key in STRICT_FIELDS}


def compare_gameplay(a: dict[str, Any], b: dict[str, Any]) -> list[str]:
    """Return the STRICT_FIELDS whose values differ between two records."""
    va, vb = gameplay_view(a), gameplay_view(b)
    return [key for key in STRICT_FIELDS if va[key] != vb[key]]


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
    write its save image without dirtying .cache/upstream, removes the stale
    STALE_BOOT_FILES, hashes the resulting boot inputs, and runs mdli there
    with TZ=UTC and the wall-clock shim. The temp dir is deleted on return.

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
        Path to the compiled fixed_time.so. If None, the shim is compiled into
        the capture's temp dir (nothing is written under .cache/build).
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

    upstream_commit = pinned_commit(UPSTREAM_NAME)
    head_commit = checked_out_commit(UPSTREAM_ROOT)
    if upstream_commit and head_commit and upstream_commit != head_commit:
        raise RuntimeError(
            f"{UPSTREAM_ROOT.name} checkout is at {head_commit}, but "
            f"sources.lock.json pins {upstream_commit}; run make sources"
        )
    game_rel = relative_posix(UPSTREAM_GAME, UPSTREAM_ROOT)

    # Fresh copy of game dir — mdli writes SAVE files here
    tmpdir = Path(tempfile.mkdtemp(prefix="mdl-boot-ref-"))
    game_dir = tmpdir / "game"
    try:
        if shim_so is None:
            shim_so = build_shim(tmpdir / "shim")
        shutil.copytree(str(UPSTREAM_GAME), str(game_dir))

        # Remove stale save images, THEN hash the effective boot inputs.
        removed = []
        for rel in STALE_BOOT_FILES:
            stale = game_dir / rel
            if stale.exists():
                stale.unlink()
                removed.append(rel)
        boot_files = file_manifest(game_dir)

        env = dict(os.environ)
        env["MDL_FIXED_EPOCH"] = str(epoch)
        env["LD_PRELOAD"] = str(shim_so)
        env["TZ"] = CHILD_TZ

        record: dict[str, Any] = {
            "schema_version": SCHEMA_VERSION,
            "engine": "confusion-patched-1977-boot",
            "scenario": scenario["name"],
            "fixed_epoch": epoch,
            "tz": CHILD_TZ,
            "entry": list(ENTRY),
            "run_mud": f"{game_rel}/run.mud",
            "provenance": {
                "upstream_source": {
                    "name": UPSTREAM_NAME,
                    "commit": upstream_commit,
                    "checked_out_commit": head_commit,
                    "checkout_root": f".cache/upstream/{UPSTREAM_NAME}",
                    "game_dir": game_rel,
                },
                "boot_input_state": {
                    "description": (
                        "game_dir copy after removing removed_before_boot; "
                        "sha256 = sha256_manifest(files)"
                    ),
                    "removed_before_boot": removed,
                    "sha256": sha256_manifest(boot_files),
                    "files": boot_files,
                },
                "engine_sha256": sha256_file(EXE),
            },
            "strict_fields": list(STRICT_FIELDS),
            "boot_output": "",
            "commands": [],
            "complete": False,
            "error": None,
            "informational": {
                "captured_at": datetime.now(timezone.utc).isoformat(),
                "interpreter_banner": "",
            },
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
            for expr in ENTRY:
                child.sendline(expr)

            # Phase 2: wait for the first game prompt '>' that RDCOM emits.
            # This covers the banner, room description, and initial '>'.
            child.expect(PROMPT, timeout=timeout)
            banner, boot_text = split_banner(canonical_text(child.before))
            record["informational"]["interpreter_banner"] = banner
            record["boot_output"] = boot_text

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
            record["informational"]["process_exitstatus"] = child.exitstatus
            record["informational"]["process_signalstatus"] = child.signalstatus

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

    cmp_ = sub.add_parser(
        "compare",
        help="Compare the gameplay view (STRICT_FIELDS) of two boot captures.",
    )
    cmp_.add_argument("expected", type=Path)
    cmp_.add_argument("actual", type=Path)

    args = parser.parse_args()

    if args.action == "compare":
        expected = json.loads(args.expected.read_text(encoding="utf-8"))
        actual = json.loads(args.actual.read_text(encoding="utf-8"))
        diffs = compare_gameplay(expected, actual)
        if diffs:
            print(f"BOOT GAMEPLAY MISMATCH in fields: {', '.join(diffs)}",
                  file=sys.stderr)
            return 1
        print(f"Boot gameplay identical ({', '.join(STRICT_FIELDS)}): "
              f"{args.expected} == {args.actual}")
        return 0

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
        record["candidate"] = True
        record["candidate_note"] = CANDIDATE_NOTE
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
        "CANDIDATE — compare gameplay with: "
        "scripts/boot_reference.py compare <expected> <actual>"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, OSError, json.JSONDecodeError) as exc:
        print(f"boot_reference: {exc}", file=sys.stderr)
        raise SystemExit(1)
