#!/usr/bin/env python3
"""Probe native Confusion primitives in isolated, local MDL processes.

Confusion's bare REPL prints no prompt. Each case therefore runs on stdin and
ends with <QUIT>, which exits cleanly without an EOF diagnostic. Raw output,
stderr, input, and process status are retained alongside the extracted result.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from scripts.reference_runner import EXE, GAME, canonical_text, sha256

LISTENING = "LISTENING-AT-LEVEL 1 PROCESS 1\n"


def probe_case(executable: Path, cwd: Path, item: dict, timeout: float) -> dict:
    expression = item["expression"]
    input_text = expression.rstrip("\n") + "\n<QUIT>\n"
    result = subprocess.run(
        [str(executable)], input=input_text, text=True,
        capture_output=True, cwd=cwd, timeout=timeout,
    )
    stdout = canonical_text(result.stdout)
    stderr = canonical_text(result.stderr)
    prefix, marker, output = stdout.partition(LISTENING)
    ok = result.returncode == 0 and not stderr and bool(marker)
    return {
        "name": item["name"], "expression": expression, "input": input_text,
        "exit_code": result.returncode, "stdout": stdout, "stderr": stderr,
        "startup_output": prefix, "result_output": output if marker else None,
        "ok": ok,
        "error": None if ok else "nonzero exit, stderr, or missing LISTENING marker",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--timeout", type=float, default=20)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    if not EXE.is_file():
        parser.error("native Confusion is not built: make reference-build")
    data = json.loads(args.cases.read_text(encoding="utf-8"))
    cases = data["cases"]
    if not cases or any(not isinstance(c.get("expression"), str) or
                        not isinstance(c.get("name"), str) for c in cases):
        parser.error("cases must contain names and expression strings")
    result = {
        "schema_version": 1, "name": data["name"],
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "interpreter_sha256": sha256(EXE),
        "protocol": "one local process per case; stdin expression then <QUIT>",
        "cases": [], "complete": False,
    }
    for item in cases:
        try:
            row = probe_case(EXE, GAME, item, args.timeout)
        except subprocess.TimeoutExpired as exc:
            row = {"name": item["name"], "expression": item["expression"],
                   "ok": False, "error": f"timeout after {exc.timeout} seconds"}
        result["cases"].append(row)
    result["complete"] = all(row["ok"] for row in result["cases"])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    if not result["complete"]:
        print(f"MDL PROBE FAILED; evidence: {args.output}", file=sys.stderr)
        return 1
    print(f"Probed {len(result['cases'])} expressions; review: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
