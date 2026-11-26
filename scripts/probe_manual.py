#!/usr/bin/env python3
"""Capture standalone native observations for the checked-in L0 corpus."""

import argparse
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile

from scripts.mdl_probe import probe_case
from scripts.reference_runner import EXE, sha256
from scripts import conformance_evidence as evidence

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/l0/native.json")
    args = parser.parse_args()
    data = evidence.load_manifest()
    locked = evidence.read_json(ROOT / "sources.lock.json")["sources"]["mdlzork"]["commit"]
    upstream = ROOT / ".cache/upstream/mdlzork"
    actual = subprocess.check_output(["git", "-C", upstream, "rev-parse", "HEAD"], text=True).strip()
    if not EXE.is_file() or actual != locked or evidence.git(
        "status", "--porcelain", "--untracked-files=no", root=upstream
    ):
        parser.error("the locked Confusion build is required (make reference-build)")
    executable_digest = sha256(EXE)
    observations = []
    os.environ["TZ"] = "UTC"
    for case in data["cases"]:
        input_text = evidence.native_input(case)
        source = input_text.removesuffix("\n<QUIT>\n")
        with tempfile.TemporaryDirectory(prefix="mdl-manual-native-") as directory:
            try:
                observation = probe_case(EXE, Path(directory), {
                    "name": case["id"], "expression": source,
                }, timeout=10)
            except subprocess.TimeoutExpired:
                observation = {"input": input_text,
                               "result_output": None, "stderr": "timed out",
                               "exit_code": None, "ok": False}
        observations.append({
            "id": case["id"], "fixture_sha256": evidence.digest(case),
            **{key: observation[key] for key in
               ("input", "result_output", "stderr", "exit_code", "ok")},
        })
    if sha256(EXE) != executable_digest:
        parser.error("Confusion executable changed during capture")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    provenance = {
        **evidence.manifest_provenance(data), "reference_revision": locked,
        "exe_sha256": executable_digest,
        "toolchain": {"python": platform.python_version(), "machine": platform.machine()},
    }
    report = {"schema_version": evidence.REPORT_VERSION, "provenance": provenance,
              "protocol": "Bare Confusion, empty working directory per case, TZ=UTC, default RNG, final QUIT",
              "observations": observations}
    evidence.validate_native(report, {
        "schema_version": evidence.REPORT_VERSION, "provenance": provenance, "agreements": {},
    }, data)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return int(not all(row["ok"] for row in observations))


if __name__ == "__main__":
    raise SystemExit(main())
