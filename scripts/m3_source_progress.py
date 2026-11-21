#!/usr/bin/env python3
"""Validate and summarize unchanged original-source loader progress.

An incomplete load is a successful *measurement* only when it preserves the
accepted M2 prefix, has no skipped forms, and reports its real next failure.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOT = ROOT / ".cache/upstream/mdlzork/mdlzork_771212/patched_confusion"
BASELINE = ROOT / "docs/evidence/M3/source-progress-baseline.json"
REFERENCE = ROOT / "docs/evidence/M2/muddle-reference.json"
LOCK = ROOT / "sources.lock.json"
SWEEP = ROOT / "artifacts/m3/reader-sweep.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def natural_count(value: object) -> bool:
    return type(value) is int and value >= 0


def signature(event: dict) -> dict:
    return {key: event.get(key) for key in ("file", "expression_index", "construct")}


def validate_report(report: dict, baseline: dict) -> dict:
    """Reject stale barriers, skipped forms, false completion and bad reports."""
    require(isinstance(report, dict), "loader report must be an object")
    require(report.get("entry") == baseline["entry"], "wrong source entry")
    status = report.get("status")
    require(status in ("PASS", "FAIL"), "loader status must be PASS or FAIL")
    completed = report.get("completed_expressions")
    require(natural_count(completed), "invalid completed expression count")
    require(natural_count(report.get("skipped_expressions")), "invalid skipped count")
    require(report["skipped_expressions"] == 0, "loader skipped expressions")
    events = report.get("events")
    require(isinstance(events, list) and events, "missing loader events")
    require(all(isinstance(event, dict) for event in events), "malformed loader event")
    require(all(event.get("status") in ("PASS", "FAIL") for event in events),
            "unknown loader event status")
    passes = [event for event in events if event["status"] == "PASS"]
    failures = [event for event in events if event["status"] == "FAIL"]
    require(len(passes) == completed, "completed count disagrees with PASS events")
    accepted = baseline["accepted_prefix"]
    require(completed >= baseline["minimum_completed_expressions"],
            "source execution regressed below accepted M2 baseline")
    require([signature(e) for e in passes[:len(accepted)]] == accepted,
            "accepted original-source execution prefix changed")
    if failures:
        first_failure = next(i for i, e in enumerate(events) if e["status"] == "FAIL")
        require(all(e["status"] == "FAIL" for e in events[first_failure:]),
                "PASS event follows a failure")
    encountered = list(dict.fromkeys(event.get("file") for event in events))
    require(all(isinstance(name, str) and name and not Path(name).is_absolute()
                and ".." not in Path(name).parts for name in encountered),
            "invalid source path in events")
    require(encountered[0] == baseline["entry"], "source entry is not first")
    reference_files = baseline["reference_files"]
    require(encountered[1:] == reference_files[:len(encountered)-1],
            "source file loading order differs from pinned Confusion")

    failure = report.get("failure")
    if status == "PASS":
        require(failure is None and not failures, "false completion with a failure")
        require(encountered[1:] == reference_files,
                "false completion before all reference files loaded")
        partial = []
    else:
        require(isinstance(failure, dict) and failures, "FAIL missing diagnostic")
        require(failure.get("file") in encountered, "failure file was not encountered")
        require(type(failure.get("expression_index")) is int
                and failure["expression_index"] > 0, "invalid failure expression")
        require(type(failure.get("line")) is int and failure["line"] > 0,
                "invalid failure line")
        require(type(failure.get("column")) is int and failure["column"] > 0,
                "invalid failure column")
        require(failure.get("stage") in ("parse", "compile", "execute"),
                "invalid failure stage")
        require(isinstance(failure.get("classification"), str)
                and failure["classification"], "missing failure classification")
        require(isinstance(failure.get("exception"), str)
                and failure["exception"], "missing failure diagnostic")
        partial = failure.get("load_chain")
        require(isinstance(partial, list) and partial
                and partial[0] == baseline["entry"]
                and partial[-1] == failure["file"], "invalid failure load chain")
        require(any(e.get("file") == failure["file"]
                    and e.get("expression_index") == failure["expression_index"]
                    for e in failures), "failure diagnostic disagrees with events")

    per_file = dict(Counter(e["file"] for e in passes))
    form_counts = baseline.get("source_form_counts", {})
    require(all(per_file.get(name, 0) <= form_counts.get(name, -1)
                for name in encountered), "executed count exceeds source form count")
    complete_files = [name for name in encountered if name not in partial]
    require(all(per_file.get(name, 0) == form_counts.get(name)
                for name in complete_files), "false claim of a completely loaded file")
    return {
        "stage": "LOADED" if status == "PASS" else "EXECUTED_PARTIAL",
        "completed_expressions": completed,
        "skipped_expressions": 0,
        "progress_delta": completed - baseline["minimum_completed_expressions"],
        "files_encountered": encountered,
        "files_completely_loaded": complete_files,
        "files_partially_executed": partial,
        "completed_per_file": per_file,
        "definition_forms_completed": sum(e.get("construct") in ("DEFINE", "DEFMAC")
                                          for e in passes),
        "failure": failure,
        "reference": {"status": "LOADED", "files": reference_files},
    }


def checked_sources(baseline: dict, encountered: list[str]) -> dict:
    lock = json.loads(LOCK.read_text())
    commits = {name: item["commit"] for name, item in lock["sources"].items()}
    require(commits == baseline["source_commits"], "source lock changed")
    sweep = json.loads(SWEEP.read_text())
    require(sweep.get("source_commits") == commits, "reader sweep uses different sources")
    require(sweep.get("summary") == {"parsed": 36, "failed": 0, "non-text": 4},
            "historical reader sweep regressed")
    hashes = {}
    for name in encountered:
        path = (SOURCE_ROOT / name).resolve()
        require(path.is_relative_to(SOURCE_ROOT.resolve()), "source path escapes root")
        hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        expected = baseline["source_sha256"].get(name)
        if expected:
            require(hashes[name] == expected, f"source SHA changed: {name}")
    return {"source_commits": commits, "source_sha256": hashes,
            "historical_text_files_parsed": 36, "historical_nontext_files": 4}


def checked_reference(baseline: dict) -> None:
    reference = json.loads(REFERENCE.read_text())
    case = next((c for c in reference.get("cases", [])
                 if c.get("name") == "fload-chain-completion"), None)
    require(isinstance(case, dict) and case.get("ok") is True
            and case.get("exit_code") == 0 and case.get("stderr") == "",
            "pinned Confusion full-loader reference is not clean")
    output = case.get("result_output", "")
    require(output.endswith('"DONE"\n'), "reference did not reach DONE")
    files = [line.removesuffix(" loaded") for line in output.splitlines()
             if line.endswith(" loaded")]
    require(files == baseline["reference_files"], "reference file inventory changed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/m3/source-progress.json")
    parser.add_argument("--raw-output", type=Path, default=ROOT / "artifacts/m3/source-load.json")
    args = parser.parse_args()
    baseline = json.loads(BASELINE.read_text())
    checked_reference(baseline)
    args.raw_output.parent.mkdir(parents=True, exist_ok=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    command = ["racket", "scripts/mdl_load.rkt", "--source-root",
               str(SOURCE_ROOT), "--entry", baseline["entry"],
               "--report", str(args.raw_output)]
    run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    report = json.loads(args.raw_output.read_text())
    summary = validate_report(report, baseline)
    require(run.returncode == (0 if report["status"] == "PASS" else 1),
            "loader process exit disagrees with report status")
    summary.update(checked_sources(baseline, summary["files_encountered"]))
    summary.update({"schema_version": 1, "entry": baseline["entry"],
                    "baseline_completed_expressions": baseline["minimum_completed_expressions"],
                    "loader_exit": run.returncode, "loader_stdout": run.stdout,
                    "loader_stderr": run.stderr,
                    "raw_report": str(args.raw_output.relative_to(ROOT))
                    if args.raw_output.is_relative_to(ROOT) else str(args.raw_output),
                    "reference_evidence": baseline["reference_evidence"]})
    summary["milestones"] = {
        "PARSED": True,
        "LOADED": summary["stage"] == "LOADED",
        "EXECUTED": summary["completed_expressions"] > 0,
        "INITIALIZED": False,
        "PLAYABLE": False,
    }
    args.output.write_text(json.dumps(summary, indent=2) + "\n")
    print(f"M3 source progress {summary['stage']}: {summary['completed_expressions']} "
          f"completed, delta {summary['progress_delta']:+}, 0 skipped; "
          f"report: {args.output}")
    if summary["failure"]:
        f = summary["failure"]
        print(f"First failure: {f['file']} expression {f['expression_index']} "
              f"{f['stage']}: {f['exception']}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as exc:
        print(f"M3 source progress FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
