#!/usr/bin/env python3
"""Capture a focused pinned Confusion probe of historical VFLOAD and I/O."""
from __future__ import annotations

import json
import tempfile
from pathlib import Path

from scripts.mdl_probe import probe_case
from scripts.reference_runner import EXE, GAME, sha256

SOURCE = GAME / "77loadall.mud"
OUTPUT = Path("docs/evidence/M2/vfload-reference.json")


def main() -> int:
    if not EXE.is_file() or not SOURCE.is_file():
        raise SystemExit("run make sources and make reference-build first")
    original_line = SOURCE.read_text(encoding="utf-8").splitlines()[0]
    if not original_line.startswith("<DEFINE VFLOAD "):
        raise SystemExit("pinned source no longer starts with VFLOAD")
    with tempfile.TemporaryDirectory(prefix="mdl-vfload-") as name:
        root = Path(name)
        controlled = root / "controlled.mud"
        controlled.write_text("<SETG HISTORICAL-RESULT 27>\n", encoding="utf-8")
        cases = [
            ("string_concat", '<STRING "ab" "cd">'),
            ("printstring", '<PRINTSTRING "abc">'),
            ("terpri", "<TERPRI>"),
            ("vfload_success", original_line +
             f'\n<VFLOAD "{controlled}">\n,HISTORICAL-RESULT'),
            ("vfload_invalid_type", original_line + "\n<VFLOAD 5>"),
            ("vfload_missing_file", original_line +
             f'\n<VFLOAD "{root / "missing.mud"}">'),
        ]
        results = []
        for case_name, expression in cases:
            row = probe_case(EXE, GAME, {"name": case_name,
                                         "expression": expression}, 10)
            results.append({
                key: value.replace(name, "<TEMP_ROOT>")
                if isinstance(value, str) else value
                for key, value in row.items()
                if key in ("name", "expression", "input", "result_output",
                           "stderr", "exit_code", "ok", "error")
            })
    report = {
        "schema_version": 1,
        "source_file": "77loadall.mud",
        "source_sha256": sha256(SOURCE),
        "interpreter_sha256": sha256(EXE),
        "protocol": "one local Confusion REPL process per case; each input ends with <QUIT>; TEMP_ROOT denotes a disposable source directory",
        "fixture_source": "<SETG HISTORICAL-RESULT 27>\n",
        "cases": results,
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Captured {len(results)} focused cases: {OUTPUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
