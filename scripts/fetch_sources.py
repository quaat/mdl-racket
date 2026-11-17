#!/usr/bin/env python3
"""Fetch immutable upstream checkouts. Never edit or commit the historical trees."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".cache" / "upstream"
LOCK = ROOT / "sources.lock.json"


def run(*args: str, cwd: Path | None = None) -> str:
    cp = subprocess.run(args, cwd=cwd, check=True, text=True, capture_output=True)
    return cp.stdout.strip()


def acquire(name: str, source: dict[str, str], *, update: bool) -> dict[str, str]:
    dest = CACHE / name
    expected = source["commit"]
    just_cloned = not dest.exists()
    if just_cloned:
        CACHE.mkdir(parents=True, exist_ok=True)
        print(f"Cloning {name} from {source['url']} ...", flush=True)
        run("git", "clone", "--quiet", "--no-checkout", source["url"], str(dest))
    if not (dest / ".git").is_dir():
        raise RuntimeError(f"{dest} exists but is not a Git repository")
    actual_url = run("git", "remote", "get-url", "origin", cwd=dest)
    if actual_url != source["url"]:
        raise RuntimeError(f"Remote URL mismatch for {name}: {actual_url}")
    if update:
        run("git", "fetch", "--quiet", "origin", expected, cwd=dest)
    if not run("git", "cat-file", "-t", expected, cwd=dest) == "commit":
        raise RuntimeError(f"Missing pinned commit {expected}; retry with --fetch")
    # A freshly cloned --no-checkout tree appears dirty (tracked files absent)
    # until checkout; that is not a user modification.
    if not just_cloned:
        before = run("git", "status", "--porcelain", cwd=dest)
        if before:
            raise RuntimeError(f"Refusing to replace locally modified upstream checkout: {dest}")
    run("git", "-c", "advice.detachedHead=false", "checkout", "--quiet", "--detach", expected, cwd=dest)
    actual = run("git", "rev-parse", "HEAD", cwd=dest)
    if actual != expected:
        raise RuntimeError(f"Commit mismatch for {name}: {actual} != {expected}")
    return {"name": name, "url": actual_url, "commit": actual, "directory": str(dest)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", action="store_true", help="Fetch missing commits for existing checkouts")
    args = parser.parse_args()
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    records = []
    for name, source in lock["sources"].items():
        records.append(acquire(name, source, update=args.fetch))
    target = ROOT / "artifacts" / "environment" / "sources.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({"recorded_at": datetime.now(timezone.utc).isoformat(),
                                   "sources": records}, indent=2) + "\n", encoding="utf-8")
    print(f"Verified {len(records)} source repositories; evidence: {target.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.CalledProcessError, OSError) as exc:
        print(f"fetch_sources: {exc}", file=sys.stderr)
        sys.exit(1)
