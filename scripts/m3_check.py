#!/usr/bin/env python3
"""`make m3-check`: the M3 SMOKE_PARITY technical check (S10; ADR-0053).

Runs, in order, each stage with its own status, log and time limit:

  1. sources                          make sources (pinned checkouts verified)
  2. test-m3-saveit                   faithful FLOAD + SAVE-IT startup
  3. test-m3-clock-seed               fixed clock -> DSKDATE -> RANDOM seed chain
  4. test-m3-interactive              six commands through the host loop
  5. comparator-unit-tests            tests/test_smoke_parity.py (negative checks)
  6. candidate-vs-committed-reference this runtime's run vs the committed
                                      Confusion record, strict (no mdli needed)
  7. native-fresh-capture-parity      OPTIONAL: fresh pinned-Confusion capture
                                      (disposable copy) vs the committed record
                                      and vs stage 6's candidate. NOT RUN (never
                                      PASS) when mdli or gcc is absent, unless
                                      --native require, which makes that a FAIL.

Every stage runs even after a failure (so the report is complete); the exit
status is nonzero if any stage FAILs. The machine-readable report is written
to artifacts/m3/m3-check.json (per-stage PASS/FAIL/NOT RUN, limitations).
A PASS here is technical evidence only; the SMOKE_PARITY gate claim is the
maintainer's (docs/STATUS.md).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/m3"
LOGS = OUT / "logs"
SCENARIO = "tests/scenarios/house-boot.json"
COMMITTED_REFERENCE = "docs/evidence/M3/house-boot-candidate.json"
CANDIDATE = "artifacts/m3/house-boot-racket-candidate.json"
MDLI = ROOT / ".cache/build/confusion_patched/mdli"
NOT_RUN_EXIT = 3          # smoke_parity.py native: prerequisites absent

LIMITATIONS = [
    "Single scenario: the six house-boot commands of tests/scenarios/house-boot.json "
    "under the fixed clock fixed_epoch=250776000, TZ=UTC; no other input, clock or zone "
    "is compared.",
    "The reference is a Confusion PTY capture compared after D1 (LISTEN banner and "
    "\"DONE\" lines) and D2 (canonical_text(ONLCR(raw))) only; Confusion's own "
    "end-of-input behaviour is not compared (the candidate's D3 tail is checked against "
    "its exact expectation).",
    "Stage 6 needs no native binary; the fresh native capture (stage 7) is NOT RUN "
    "where mdli or gcc is absent.",
    "test-m3-* stages read the pinned upstream checkout; make sources does not fetch "
    "unless the checkout is missing.",
    "Not claimed: PLAYABLE, other scenarios, save/restore, QUIT, death paths, or "
    "parity under the real wall clock.",
]


def sha256_file(path: Path) -> str | None:
    if not path.is_file():
        return None
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def rel(path: Path) -> str:
    """Repository-relative display path; never fails."""
    try:
        return Path(os.path.abspath(path)).relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def git(*args: str) -> str | None:
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def run_commands(name: str, commands: list[list[str]], timeout: float) -> dict:
    """Run commands in sequence (stop at the first nonzero) into one log."""
    LOGS.mkdir(parents=True, exist_ok=True)
    log = LOGS / f"{name}.log"
    start = time.monotonic()
    exit_code = 0
    with log.open("w", encoding="utf-8") as fh:
        for cmd in commands:
            fh.write(f"$ {' '.join(cmd)}\n")
            fh.flush()
            remaining = timeout - (time.monotonic() - start)
            try:
                r = subprocess.run(cmd, cwd=ROOT, stdout=fh, stderr=subprocess.STDOUT,
                                   timeout=max(remaining, 1))
                exit_code = r.returncode
            except subprocess.TimeoutExpired:
                fh.write(f"\nTIMEOUT after {timeout} s\n")
                exit_code = None
            fh.write(f"[exit {exit_code}]\n")
            if exit_code != 0:
                break
    return {"exit_code": exit_code, "duration_s": round(time.monotonic() - start, 1),
            "log": rel(log),
            "commands": [" ".join(c) for c in commands]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--native", choices=("auto", "require", "skip"),
                        default=os.environ.get("M3_NATIVE", "auto"))
    parser.add_argument("--stages", default=None,
                        help="comma-separated subset of stage names (default: all)")
    parser.add_argument("--report", type=Path, default=OUT / "m3-check.json")
    parser.add_argument("--stage-timeout", type=float,
                        default=float(os.environ.get("M3_STAGE_TIMEOUT", "900")))
    args = parser.parse_args()

    py = sys.executable
    make = [os.environ.get("MAKE", "make"), "--no-print-directory", f"PYTHON={py}"]
    have_native = MDLI.is_file() and shutil.which("gcc") is not None
    stages = [
        ("sources", [make + ["sources"]]),
        ("test-m3-saveit", [make + ["test-m3-saveit"]]),
        ("test-m3-clock-seed", [make + ["test-m3-clock-seed"]]),
        ("test-m3-interactive", [make + ["test-m3-interactive"]]),
        ("comparator-unit-tests", [[py, "-m", "pytest", "-q", "tests/test_smoke_parity.py"]]),
        ("candidate-vs-committed-reference", [
            [py, "scripts/smoke_parity.py", "run", "--scenario", SCENARIO,
             "--output", CANDIDATE],
            [py, "scripts/smoke_parity.py", "compare", COMMITTED_REFERENCE, CANDIDATE,
             "--report", "artifacts/m3/candidate-vs-committed-reference.json"]]),
        ("native-fresh-capture-parity", [
            [py, "scripts/smoke_parity.py", "native", "--scenario", SCENARIO,
             "--reference", COMMITTED_REFERENCE, "--candidate", CANDIDATE,
             "--output-dir", "artifacts/m3"]]),
    ]
    wanted = set(args.stages.split(",")) if args.stages else None
    if wanted and not wanted <= {n for n, _ in stages}:
        parser.error(f"unknown stage(s): {sorted(wanted - {n for n, _ in stages})}")

    results = []
    for name, commands in stages:
        if wanted and name not in wanted:
            continue
        entry: dict = {"name": name}
        if name == "native-fresh-capture-parity" and (args.native == "skip" or not have_native):
            missing = "skipped by --native skip" if args.native == "skip" else (
                f"native prerequisites absent (mdli at "
                f"{rel(MDLI)}: {MDLI.is_file()}, "
                f"gcc: {shutil.which('gcc') is not None})")
            entry.update(status="FAIL" if args.native == "require" else "NOT RUN",
                         exit_code=None, reason=missing)
        else:
            entry.update(run_commands(name, commands, args.stage_timeout))
            if name == "native-fresh-capture-parity" and entry["exit_code"] == NOT_RUN_EXIT:
                entry["status"] = "FAIL" if args.native == "require" else "NOT RUN"
            else:
                entry["status"] = "PASS" if entry["exit_code"] == 0 else "FAIL"
        results.append(entry)
        print(f"m3-check: {name:34} {entry['status']:8} "
              f"exit={entry.get('exit_code')} {entry.get('duration_s', '')}"
              f"{'s' if 'duration_s' in entry else entry.get('reason', '')}", flush=True)

    failed = [r["name"] for r in results if r["status"] == "FAIL"]
    lock = json.loads((ROOT / "sources.lock.json").read_text(encoding="utf-8"))
    dirty = git("status", "--porcelain", "--untracked-files=no")
    report = {
        "schema_version": 1,
        "target": "make m3-check",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "git_commit": git("rev-parse", "HEAD"),
        "git_worktree_dirty": bool(dirty) if dirty is not None else None,
        "sources_lock": {k: v["commit"] for k, v in lock["sources"].items()},
        "mdli_sha256": sha256_file(MDLI),
        "native_mode": args.native,
        "comparison_contract": "ADR-0053 (scripts/smoke_parity.py): D1 and D2 only; "
                               "candidate must end by D3 input exhaustion",
        "stages": results,
        "overall": "FAIL" if failed else "PASS",
        "failed_stages": failed,
        "not_run_stages": [r["name"] for r in results if r["status"] == "NOT RUN"],
        "limitations": LIMITATIONS,
        "claim": "technical check only; the SMOKE_PARITY gate state is decided by the "
                 "maintainer in docs/STATUS.md",
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    not_run = report["not_run_stages"]
    print(f"m3-check: overall {report['overall']}"
          f"{' (NOT RUN: ' + ', '.join(not_run) + ')' if not_run else ''}"
          f"; report {rel(args.report)}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
