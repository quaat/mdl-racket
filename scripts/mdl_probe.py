#!/usr/bin/env python3
"""Experimental MDL REPL probe runner, used to corroborate individual semantics.

The native Confusion REPL prompt is intentionally configurable until its
actual behavior is verified on the target platform. A missing prompt is a
hard failure. Do not substitute guessed results for observed outputs.
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import pexpect

from scripts.reference_runner import EXE, GAME, canonical_text, sha256


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--prompt", required=True,
                        help="Exact verified Confusion REPL prompt (no guessing)")
    parser.add_argument("--timeout", type=float, default=20)
    args = parser.parse_args()
    if not EXE.is_file():
        parser.error("native Confusion is not built: make reference-build")
    data = json.loads(args.cases.read_text(encoding="utf-8"))
    cases = data["cases"]
    if not cases or any(not isinstance(c.get("expression"), str) for c in cases):
        parser.error("cases must contain one or more expression strings")
    result = {"schema_version": 1, "name": data["name"],
              "recorded_at": datetime.now(timezone.utc).isoformat(),
              "interpreter_sha256": sha256(EXE), "prompt": args.prompt,
              "cases": [], "complete": False, "error": None}
    child = pexpect.spawn(str(EXE), [], cwd=str(GAME), encoding="utf-8",
                          codec_errors="replace", echo=False, timeout=args.timeout)
    try:
        child.expect_exact(args.prompt)
        result["initial_output"] = canonical_text(child.before)
        for item in cases:
            child.sendline(item["expression"])
            child.expect_exact(args.prompt)
            result["cases"].append({"name": item["name"],
                                    "expression": item["expression"],
                                    "output": canonical_text(child.before)})
        result["complete"] = True
    except pexpect.ExceptionPexpect as exc:
        result["error"] = str(exc)
    finally:
        if child.isalive():
            child.terminate(force=True)
        child.close()
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    if not result["complete"]:
        print(f"MDL PROBE FAILED: {result['error']}", file=sys.stderr)
        return 1
    print(f"Probed {len(result['cases'])} expressions; review: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
