#!/usr/bin/env python3
"""Sweep every selected December 1977 source file with the Racket reader."""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT / ".cache/upstream"
OUTPUT = ROOT / "docs/evidence/M0/reader-sweep.json"
ROOTS = (
    UPSTREAM / "mit_zork/zork",
    UPSTREAM / "mdlzork/mdlzork_771212/original_source/zork",
    UPSTREAM / "mdlzork/mdlzork_771212/patched_confusion",
)


def main() -> int:
    lock = json.loads((ROOT / "sources.lock.json").read_text())
    commits = {}
    for name, item in lock["sources"].items():
        checkout = UPSTREAM / name
        actual = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=checkout, capture_output=True,
            text=True, check=True,
        ).stdout.strip()
        if actual != item["commit"]:
            raise RuntimeError(f"{name}: checkout {actual} differs from lock {item['commit']}")
        commits[name] = actual

    files = sorted(
        path for base in ROOTS for path in base.rglob("*")
        if path.is_file() and (path.suffix == ".mud" or path.suffix[1:].isdigit())
    )
    rows = []
    for path in files:
        raw = path.read_bytes()
        row = {"path": str(path.relative_to(ROOT)),
               "sha256": hashlib.sha256(raw).hexdigest()}
        try:
            raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            row.update(status="non-text", reason=f"UTF-8 decode failed at byte {exc.start}")
        else:
            env = {**os.environ, "TMPDIR": "/tmp"}
            result = subprocess.run(
                ["racket", "scripts/mdl_check.rkt", row["path"]],
                cwd=ROOT, env=env, capture_output=True, text=True,
            )
            row.update(status="parsed" if result.returncode == 0 else "failed",
                       exit_code=result.returncode,
                       output=(result.stdout or result.stderr).strip())
        rows.append(row)
        print(row["output"] if "output" in row else
              f"NON-TEXT {row['path']}: {row['reason']}")

    summary = {status: sum(row["status"] == status for row in rows)
               for status in ("parsed", "failed", "non-text")}
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps({
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "source_commits": commits,
        "summary": summary,
        "files": rows,
    }, indent=2) + "\n")
    print(f"Summary: {summary}; evidence: {OUTPUT.relative_to(ROOT)}")
    return 0 if summary["failed"] == 0 and summary["parsed"] > 0 else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.CalledProcessError, RuntimeError) as exc:
        print(f"source sweep: {exc}", file=sys.stderr)
        raise SystemExit(1)
