#!/usr/bin/env python3
"""Differential oracle: compare one candidate transcript to one Confusion capture."""
from __future__ import annotations

import argparse
import difflib
import json
import sys
from pathlib import Path
from typing import Any


def differences(reference: dict[str, Any], candidate: dict[str, Any]) -> list[str]:
    problems = []
    if not reference.get("complete") or not candidate.get("complete"):
        problems.append("both captures must be marked complete")
    if reference.get("scenario") != candidate.get("scenario"):
        problems.append("scenario names differ")
    if reference.get("initial_output") != candidate.get("initial_output"):
        problems.append("initial output differs:\n" + "".join(difflib.unified_diff(
            reference.get("initial_output", "").splitlines(keepends=True),
            candidate.get("initial_output", "").splitlines(keepends=True),
            fromfile="reference/initial", tofile="candidate/initial")))
    rturns, cturns = reference.get("commands", []), candidate.get("commands", [])
    if len(rturns) != len(cturns):
        problems.append(f"turn count differs: reference={len(rturns)}, candidate={len(cturns)}")
    for i, (r, c) in enumerate(zip(rturns, cturns), 1):
        if r.get("input") != c.get("input"):
            problems.append(f"turn {i}: input differs")
        if r.get("output") != c.get("output"):
            problems.append(f"turn {i}: output differs:\n" + "".join(difflib.unified_diff(
                r.get("output", "").splitlines(keepends=True),
                c.get("output", "").splitlines(keepends=True),
                fromfile=f"reference/turn-{i}", tofile=f"candidate/turn-{i}")))
        if r.get("prompt_returned") != c.get("prompt_returned"):
            problems.append(f"turn {i}: prompt/exit behavior differs")
        if "state" in r and "state" in c and r["state"] != c["state"]:
            problems.append(f"turn {i}: state snapshot differs")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path)
    parser.add_argument("candidate", type=Path)
    args = parser.parse_args()
    r = json.loads(args.reference.read_text(encoding="utf-8"))
    c = json.loads(args.candidate.read_text(encoding="utf-8"))
    issues = differences(r, c)
    if issues:
        print(f"FAIL: {len(issues)} differential mismatches", file=sys.stderr)
        for issue in issues:
            print(issue, file=sys.stderr)
        return 1
    print(f"PASS: {len(r['commands'])} turns identical under the explicitly documented normalization")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
