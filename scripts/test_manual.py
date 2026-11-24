#!/usr/bin/env python3
"""Execute reviewed MDL fixtures in isolated, resource-limited Racket processes."""

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import resource
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests/conformance"
MODES = ("loader", "lang")
TIMEOUT = 20
MIB = 1024 * 1024


def limit_worker():
    resource.setrlimit(resource.RLIMIT_AS, (768 * MIB, 768 * MIB))
    resource.setrlimit(resource.RLIMIT_CPU, (15, 15))
    resource.setrlimit(resource.RLIMIT_FSIZE, (MIB, MIB))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def run_fixture(case, mode, racket):
    with tempfile.TemporaryDirectory(prefix="mdl-manual-") as directory:
        root = Path(directory)
        source = root / f"{case['id']}.mud"
        prefix = "#lang mdl\n" if mode == "lang" else ""
        setup = "".join(f"{form}\n" for form in case["setup"])
        source.write_text(
            f"{prefix}{setup}<SETG CONFORMANCE-RESULT {case['expression']}>\n"
            f"<SETG CONFORMANCE-EFFECT {case.get('effect_expression', '0')}>\n",
            encoding="utf-8",
        )
        with (root / "stdout").open("w+b") as stdout, (root / "stderr").open("w+b") as stderr:
            try:
                completed = subprocess.run(
                    [racket, str(CORPUS / "manual_test.rkt"), mode, str(source)],
                    cwd=root, stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr,
                    timeout=TIMEOUT, preexec_fn=limit_worker,
                    env={**os.environ, "TZ": "UTC"},
                )
            except subprocess.TimeoutExpired:
                return "FAIL", {"diagnostic": f"exceeded {TIMEOUT}s wall limit"}
            stdout.seek(0)
            stderr.seek(0)
            errors = stderr.read().decode("utf-8", errors="replace")
            if completed.returncode or errors:
                return "FAIL", {"exit": completed.returncode, "stderr": errors[:8192]}
            try:
                report = json.load(stdout)
            except (UnicodeError, ValueError) as exc:
                return "FAIL", {"diagnostic": f"invalid worker report: {exc}"}

    return classify(case, mode, report), report


def classify(case, mode, report):
    gap = case.get("gaps", {}).get(mode)
    expected_error = case.get("expected_errors", {}).get(mode)
    if expected_error:
        return "PASS" if matches_diagnostic(report, mode, expected_error) else "FAIL"
    if report == case.get("expected"):
        return "XPASS" if gap else "PASS"
    return "XFAIL" if gap and matches_diagnostic(report, mode, gap) else "FAIL"


def matches_diagnostic(report, mode, expected):
    if report.get("status") != "FAIL" or report.get("output") != expected["output"]:
        return False
    failure = report.get("failure") or {}
    if not re.fullmatch(expected["exception"], failure.get("exception", "")):
        return False
    return mode != "loader" or all(
        failure.get(key) == expected[key]
        for key in ("classification", "stage", "construct", "expression_index", "line", "column")
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--racket", default="racket")
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/l0/manual.json")
    args = parser.parse_args()
    racket = shutil.which(args.racket)
    if not racket:
        parser.error(f"Racket executable not found: {args.racket}")
    racket = str(Path(racket).resolve())
    data = json.loads((CORPUS / "manifest.json").read_text(encoding="utf-8"))
    if data["schema_version"] != 1:
        parser.error("unsupported fixture schema")
    cases = data["cases"]
    ids = [case["id"] for case in cases]
    if not ids or len(ids) != len(set(ids)) or any(
        not re.fullmatch(r"[a-z0-9-]+", case_id) for case_id in ids
    ):
        parser.error("fixture IDs must be nonempty, unique lowercase slugs")
    rows = []
    by_chapter = {}
    by_feature = {}
    for case in cases:
        for mode in MODES:
            gap = case.get("gaps", {}).get(mode)
            if gap and not re.fullmatch(r"#[1-9][0-9]*", gap["issue"]):
                parser.error(f"{case['id']} {mode}: gap requires an issue number")
            status, actual = run_fixture(case, mode, racket)
            row = {
                "id": case["id"], "chapter": case["chapter"], "feature": case["feature"],
                "specification": case["specification"], "source": case["source"],
                "mode": mode, "status": status,
                "actual": actual, "expected": case.get("expected"),
                "expected_error": case.get("expected_errors", {}).get(mode), "gap": gap,
            }
            rows.append(row)
            by_chapter.setdefault(str(case["chapter"]), Counter())[status] += 1
            by_feature.setdefault(case["feature"], Counter())[status] += 1
            print(f"{status:5} {case['chapter']:02} {case['feature']} / {case['id']} [{mode}]")
            if status in {"FAIL", "XPASS"}:
                print(f"  {case['specification']}: {json.dumps(actual)}")
    counts = dict(Counter(row["status"] for row in rows))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps({"schema_version": 1, "summary": counts, "chapters": by_chapter,
                    "features": by_feature, "results": rows}, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"{counts} ({args.output})")
    return 1 if counts.get("FAIL") or counts.get("XPASS") else 0


if __name__ == "__main__":
    raise SystemExit(main())
