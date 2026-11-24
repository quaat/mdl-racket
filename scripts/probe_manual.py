#!/usr/bin/env python3
"""Capture standalone native observations for the checked-in L0 corpus."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

from scripts.mdl_probe import probe_case
from scripts.reference_runner import EXE, sha256

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/l0/native.json")
    args = parser.parse_args()
    locked = json.loads((ROOT / "sources.lock.json").read_text())["sources"]["mdlzork"]["commit"]
    upstream = ROOT / ".cache/upstream/mdlzork"
    actual = subprocess.check_output(["git", "-C", upstream, "rev-parse", "HEAD"], text=True).strip()
    if not EXE.is_file() or actual != locked:
        parser.error("the locked Confusion build is required (make reference-build)")
    cases = json.loads((ROOT / "tests/conformance/manifest.json").read_text())["cases"]
    observations = []
    os.environ["TZ"] = "UTC"
    for case in cases:
        forms = [*case["setup"], case["expression"]]
        if "effect_expression" in case:
            forms.append(case["effect_expression"])
        source = "\n".join(forms)
        with tempfile.TemporaryDirectory(prefix="mdl-manual-native-") as directory:
            try:
                observation = probe_case(EXE, Path(directory), {
                    "name": case["id"], "expression": source,
                }, timeout=10)
            except subprocess.TimeoutExpired:
                observation = {"name": case["id"], "input": source + "\n<QUIT>\n",
                               "result_output": None, "stderr": "timed out",
                               "exit_code": None, "ok": False}
        observations.append({key: observation[key] for key in
                             ("name", "input", "result_output", "stderr", "exit_code", "ok")})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    data = {"schema_version": 1, "source_commit": locked, "exe_sha256": sha256(EXE),
            "protocol": "Bare Confusion, empty working directory per case, TZ=UTC, default RNG, final QUIT",
            "observations": observations}
    args.output.write_text(json.dumps(data, indent=2) + "\n")
    return int(not all(row["ok"] for row in observations))


if __name__ == "__main__":
    raise SystemExit(main())
