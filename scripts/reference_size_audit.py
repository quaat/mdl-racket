#!/usr/bin/env python3
"""Audit the tracked reference corpus against ADR-0065 (reference size policy).

Counts git-tracked files under the policy roots (docs/evidence/reference-corpus-policy.json),
reports the total and the largest files, and lists violations: a total over the soft
budget, or a single file over the per-file limit, without a recorded justification.
Exit 0 when there is no violation, 1 otherwise. Read-only.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "docs/evidence/reference-corpus-policy.json"


def tracked_sizes(roots: list[str]) -> dict[str, int]:
    """Sizes of the files under ROOTS: git-tracked files when the checkout has
    git metadata, otherwise every file present (a CI checkout made without git
    contains only tracked files). SOURCE records which one was used."""
    global SOURCE
    try:
        out = subprocess.run(["git", "-c", f"safe.directory={ROOT}", "ls-files", "-z",
                              "--", *roots], cwd=ROOT, capture_output=True,
                             check=True).stdout
        names = [n for n in out.decode("utf-8").split("\0") if n]
        SOURCE = "git ls-files"
    except (OSError, subprocess.CalledProcessError):
        names = [p.relative_to(ROOT).as_posix() for r in roots
                 for p in (ROOT / r).rglob("*") if p.is_file()]
        SOURCE = "filesystem walk (no git metadata)"
    return {n: (ROOT / n).stat().st_size for n in names if (ROOT / n).is_file()}


SOURCE = "not run"


def violations(policy: dict, sizes: dict[str, int]) -> list[str]:
    allowed = {j["path"]: int(j["bytes_allowed"]) for j in policy.get("justifications", [])}
    problems = []
    total = sum(sizes.values())
    if total > policy["soft_total_budget_bytes"] and total > allowed.get("TOTAL", -1):
        problems.append(f"total {total} bytes exceeds the soft budget "
                        f"{policy['soft_total_budget_bytes']} without a TOTAL justification")
    for path, size in sizes.items():
        if size > policy["single_file_limit_bytes"] and size > allowed.get(path, -1):
            problems.append(f"{path}: {size} bytes exceeds the single-file limit "
                            f"{policy['single_file_limit_bytes']} without a justification")
    return problems


def main() -> int:
    policy = json.loads(POLICY.read_text(encoding="utf-8"))
    sizes = tracked_sizes(policy["roots"])
    total = sum(sizes.values())
    print(f"reference corpus: {total / 1048576:.2f} MiB in {len(sizes)} tracked files "
          f"(soft budget {policy['soft_total_budget_bytes'] / 1048576:.0f} MiB, "
          f"single-file limit {policy['single_file_limit_bytes'] / 1048576:.0f} MiB; "
          f"{SOURCE})")
    for root in policy["roots"]:
        part = [s for p, s in sizes.items() if p.startswith(root + "/")]
        print(f"  {root:20} {sum(part) / 1048576:7.2f} MiB {len(part):4d} files")
    for path, size in sorted(sizes.items(), key=lambda kv: -kv[1])[:10]:
        print(f"  {size / 1048576:7.2f} MiB  {path}")
    problems = violations(policy, sizes)
    for p in problems:
        print(f"VIOLATION: {p}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
