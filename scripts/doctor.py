#!/usr/bin/env python3
"""Report local toolchain availability without claiming unrun tests passed."""
from __future__ import annotations

import shutil
import subprocess
import sys

TOOLS = ("git", "racket", "raco", "make", "gcc", "g++", "perl", "pkg-config", "python3")
# pkg-config aids diagnosis but is not strictly required to compile Confusion.
REQUIRED = frozenset(TOOLS) - {"pkg-config"}


def main() -> int:
    print("MDL/Zork development environment check")
    print(f"Python: {sys.version.split()[0]}")
    found = {command: shutil.which(command) for command in TOOLS}
    for command, path in found.items():
        print(f"{command:12} {'FOUND ' + path if path else 'MISSING'}")

    if found["pkg-config"]:
        result = subprocess.run(
            ["pkg-config", "--modversion", "bdw-gc"],
            capture_output=True, text=True, check=False,
        )
        if result.returncode == 0:
            print("BDW GC:      ", result.stdout.strip())
        else:
            print("BDW GC:       not found via pkg-config (check libgc-dev before building Confusion)")
    else:
        print("BDW GC:       cannot detect without pkg-config (check libgc-dev manually)")

    missing = sorted(command for command in REQUIRED if not found[command])
    if missing:
        print(f"Missing required tools: {', '.join(missing)}")
        if "racket" in missing or "raco" in missing:
            print("Install Racket before running language tests (make test-racket).")
        return 1

    print("Required tools detected. Next: make test; make sources; make reference-build.")
    print("Note: tool discovery alone does not verify Racket tests or Confusion gameplay.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
