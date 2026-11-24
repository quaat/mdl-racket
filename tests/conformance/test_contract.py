import copy

import pytest

from scripts import conformance_evidence as evidence
from scripts import test_manual


@pytest.fixture
def manifest():
    return evidence.load_manifest()


@pytest.fixture
def sample(manifest):
    return next(case for case in manifest["cases"] if case["id"] == "sqrt")


def test_manifest_validates_every_reference_before_running(manifest):
    manifest["cases"][-1]["source"] = "https://example.invalid/fixture"
    with pytest.raises(ValueError, match="manual source"):
        evidence.validate_manifest(manifest)


def test_expected_diagnostic_is_exact_and_requires_loader_location(sample):
    diagnostic = sample["gaps"]["loader"]
    failure = {k: v for k, v in diagnostic.items() if k not in {"output", "issue"}}
    report = {"status": "FAIL", "output": "", "failure": failure}
    assert evidence.classify(sample, "loader", report) == "XFAIL"
    assert evidence.classify(sample, "loader", sample["expected"]) == "XPASS"
    assert test_manual.gate_exit([{"status": "XPASS"}]) == 1
    for key, value in [("line", 999), ("exception", "an unrelated failure")]:
        altered = copy.deepcopy(report)
        altered["failure"][key] = value
        assert evidence.classify(sample, "loader", altered) == "FAIL"


@pytest.mark.parametrize("payload", ['null', '[]', '{}', '{"schema_version": 1}',
                                      '{"schema_version": 1, "schema_version": 1}'])
def test_worker_rejects_malformed_json_records(payload):
    with pytest.raises(ValueError):
        test_manual.read_worker(payload, "loader")


@pytest.mark.parametrize("kind", [
    "timeout", "process", "worker-protocol",
])
def test_harness_failure_is_never_an_xfail(sample, kind):
    report = {"harness_error": {"kind": kind, "message": "a fixture diagnostic"}}
    assert evidence.classify(sample, "loader", report) == "FAIL"


@pytest.fixture
def retained():
    directory = evidence.ROOT / "docs/evidence/L0"
    return {name: evidence.read_json(directory / f"{name}.json")
            for name in ("manual-summary", "native-examples", "native-agreement")}


def test_retained_evidence_validates(manifest, retained):
    evidence.validate_manual(retained["manual-summary"], manifest, historical=True)
    evidence.validate_native(retained["native-examples"], retained["native-agreement"], manifest)


def test_changed_fixture_under_same_id_is_stale(manifest, retained):
    manifest["cases"][0]["expression"] = "777"
    report = retained["manual-summary"]
    report["provenance"].update(evidence.manifest_provenance(manifest))
    with pytest.raises(ValueError, match="stale fixture digest"):
        evidence.validate_manual(report, manifest, historical=True)


@pytest.mark.parametrize(("mutation", "message"), [
    ("missing", "missing fixture/mode"), ("duplicate", "duplicate fixture/mode"),
    ("classification", "invalid classification"), ("mismatch", "inconsistent classification"),
    ("missing-provenance", "invalid manual result record"),
    ("no-toolchain", "invalid runtime or toolchain provenance"),
    ("runtime-hash", "inconsistent runtime digest"),
])
def test_rejects_incomplete_or_inconsistent_manual_evidence(manifest, retained, mutation, message):
    report = retained["manual-summary"]
    row = report["results"][0]
    if mutation == "missing":
        report["results"].pop()
    elif mutation == "duplicate":
        report["results"].append(copy.deepcopy(row))
    elif mutation == "classification":
        row["status"] = "VERIFIED"
    elif mutation == "mismatch":
        row["status"] = "XFAIL"
    elif mutation == "missing-provenance":
        del report["provenance"]
    elif mutation == "no-toolchain":
        report["provenance"]["toolchain"] = {}
    elif mutation == "runtime-hash":
        report["provenance"]["runtime_sha256"] = "0" * 64
    with pytest.raises(ValueError, match=message):
        evidence.validate_manual(report, manifest, historical=True)


@pytest.mark.parametrize("kind", ["native-input", "native-output", "native-executable"])
def test_stale_native_agreement_is_rejected(manifest, retained, kind):
    report = retained["native-examples"]
    agreement = retained["native-agreement"]
    row = next(item for item in report["observations"] if item["id"] in agreement["agreements"])
    if kind == "native-input":
        row["input"] += "\n"
    elif kind == "native-output":
        row["result_output"] += "changed\n"
    else:
        report["provenance"]["exe_sha256"] = "0" * 64
    with pytest.raises(ValueError, match="stale native"):
        evidence.validate_native(report, agreement, manifest)


def test_git_snapshot_excludes_untracked_and_modified_manual_pages(tmp_path):
    import subprocess

    from scripts.inventory_manual import snapshot

    checkout = tmp_path / "checkout"
    checkout.mkdir()
    docs = checkout / "docs"
    docs.mkdir()
    page = docs / "01-original.md"
    page.write_text("committed\n")
    subprocess.run(["git", "init", "-q", checkout], check=True)
    evidence.git("add", "docs", root=checkout)
    evidence.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "-qm", "manual", root=checkout)
    page.write_text("modified\n")
    (docs / "02-extra.md").write_text("untracked\n")
    out = tmp_path / "out"
    out.mkdir()
    snapshot(checkout, "HEAD", out, "docs")
    assert list((out / "docs").iterdir()) == [out / "docs/01-original.md"]
    assert (out / "docs/01-original.md").read_text() == "committed\n"


def test_observation_failure_stays_outside_semantic_diagnostic(sample):
    import shutil

    racket = shutil.which("racket")
    assert racket
    case = copy.deepcopy(sample)
    case["expression"] = "<BITS 1>"
    report = test_manual.run_fixture(case, "lang", racket)
    assert report["harness_error"]["kind"] == "process"
    assert "no observation for MDL TYPE BITS" in report["harness_error"]["message"]
    assert evidence.classify(case, "lang", report) == "FAIL"


@pytest.mark.parametrize(("exit_code", "kind"), [(-24, "process"), (None, "timeout"), (0, "worker-protocol")])
def test_worker_process_lifecycle_is_never_a_semantic_failure(monkeypatch, sample, exit_code, kind):
    import subprocess

    def fake_run(cmd, **kwargs):
        if exit_code is None:
            raise subprocess.TimeoutExpired(cmd, kwargs["timeout"])
        kwargs["stdout"].write(b"[]")
        return subprocess.CompletedProcess(cmd, exit_code)
    monkeypatch.setattr(test_manual.subprocess, "run", fake_run)
    actual = test_manual.run_fixture(sample, "loader", "/unused")
    assert actual["harness_error"]["kind"] == kind
    assert evidence.classify(sample, "loader", actual) == "FAIL"


def test_worker_rejects_nonfinite_numeric_observation(sample):
    import json

    report = copy.deepcopy(sample["expected"])
    encoded = json.dumps({"schema_version": 1, "observation": report}).replace("5.0", "1e999")
    with pytest.raises(ValueError, match="invalid worker observation"):
        test_manual.read_worker(encoded, "lang")


def test_worker_selects_this_checkout_over_ambient_collection(monkeypatch, tmp_path, manifest):
    import os
    import shutil

    foreign = tmp_path / "mdl/lang"
    foreign.mkdir(parents=True)
    (foreign / "reader.rkt").write_text('#lang racket/base\n(error "foreign MDL reader")\n')
    default = os.environ.get("PLTCOLLECTS", "")
    monkeypatch.setenv("PLTCOLLECTS", f"{tmp_path}:{default}")
    case = next(case for case in manifest["cases"] if case["id"] == "fix-literal")
    racket = shutil.which("racket")
    assert racket
    assert test_manual.run_fixture(case, "lang", racket) == case["expected"]
