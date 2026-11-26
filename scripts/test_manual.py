#!/usr/bin/env python3
"""Execute reviewed MDL fixtures in isolated, resource-limited Racket processes."""

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import platform
import resource
import shutil
import subprocess
import tempfile

if __package__:
    from . import conformance_evidence as evidence
else:
    import conformance_evidence as evidence

TIMEOUT = 20
MIB = 1024 * 1024


def limit_worker():
    resource.setrlimit(resource.RLIMIT_AS, (768 * MIB, 768 * MIB))
    resource.setrlimit(resource.RLIMIT_CPU, (15, 15))
    resource.setrlimit(resource.RLIMIT_FSIZE, (MIB, MIB))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def read_worker(payload, mode, source=None):
    message = evidence.parse_json(payload)
    evidence.require(evidence.has_keys(message, "schema_version observation")
                     and type(message["schema_version"]) is int and message["schema_version"] == 1,
                     "invalid worker protocol")
    report = message["observation"]
    evidence.validate_observation(report, mode)
    if source is not None and report.get("status") == "FAIL":
        report["failure"]["exception"] = report["failure"]["exception"].replace(str(source), source.name)
    return report


def harness_error(kind, message):
    return {"harness_error": {"kind": kind, "message": message}}


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
                    [racket, str(evidence.CORPUS / "manual_test.rkt"), mode, str(source)],
                    cwd=root, stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr,
                    timeout=TIMEOUT, preexec_fn=limit_worker,
                    env={**os.environ, "TZ": "UTC"},
                )
            except subprocess.TimeoutExpired:
                return harness_error("timeout", f"exceeded {TIMEOUT}s wall limit")
            except (OSError, subprocess.SubprocessError) as exc:
                return harness_error("process", str(exc))
            stdout.seek(0)
            stderr.seek(0)
            errors = stderr.read(8192).decode("utf-8", errors="replace")
            if completed.returncode or errors:
                return harness_error("process", f"worker exit {completed.returncode}: {errors}")
            try:
                return read_worker(stdout.read().decode("utf-8"), mode, source)
            except (ValueError, RecursionError) as exc:
                return harness_error("worker-protocol", str(exc))


def gate_exit(rows):
    return int(any(row["status"] in {"FAIL", "XPASS"} for row in rows))


def run_manifest(data, racket, output):
    runtime = evidence.runtime_digest()
    runner = evidence.runner_digest()
    head = evidence.git("rev-parse", "HEAD").decode().strip()
    provenance = {
        **evidence.manifest_provenance(data),
        "runtime_revision": head if evidence.runtime_digest(head) == runtime else None,
        "runtime_sha256": runtime,
        "runner_revision": head if evidence.runner_digest(head) == runner else None,
        "runner_sha256": runner,
        "toolchain": {"racket": subprocess.check_output([racket, "--version"], text=True).strip(),
                      "python": platform.python_version()},
        "worker_version": 1,
    }
    rows = []
    chapters = {}
    features = {}
    for case in data["cases"]:
        for mode in evidence.MODES:
            actual = run_fixture(case, mode, racket)
            status = evidence.classify(case, mode, actual)
            row = {
                "id": case["id"], "fixture_sha256": evidence.digest(case), "mode": mode, "status": status,
                "actual": actual, "expected": evidence.expected_for(case, mode),
            }
            rows.append(row)
            chapters.setdefault(str(case["chapter"]), Counter())[status] += 1
            features.setdefault(case["feature"], Counter())[status] += 1
            print(f"{status:5} {case['chapter']:02} {case['feature']} / {case['id']} [{mode}]")
            if status in {"FAIL", "XPASS"}:
                print(f"  {case['specification']} {case['source']}: {json.dumps(actual)}")
    counts = dict(Counter(row["status"] for row in rows))
    report = {"schema_version": evidence.REPORT_VERSION, "provenance": provenance,
              "summary": counts, "chapters": chapters, "features": features, "results": rows}
    evidence.validate_manual(report, data, historical=False)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"{counts} ({output})")
    return gate_exit(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--racket", default="racket")
    parser.add_argument("--output", type=Path, default=evidence.ROOT / "artifacts/l0/manual.json")
    args = parser.parse_args()
    try:
        data = evidence.load_manifest()  # No fixture executes before the whole manifest passes.
        racket = shutil.which(args.racket)
        if not racket:
            parser.error(f"Racket executable not found: {args.racket}")
        return run_manifest(data, str(Path(racket).resolve()), args.output)
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    raise SystemExit(main())
