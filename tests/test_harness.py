"""Offline tests; do not require GitHub, Confusion, or Racket."""
import json
from pathlib import Path

from scripts.compare_transcripts import differences
from scripts.reference_runner import canonical_text

ROOT = Path(__file__).resolve().parents[1]


def test_lock_has_pinned_full_commits():
    data = json.loads((ROOT / "sources.lock.json").read_text())
    assert set(data["sources"]) == {"mit_zork", "mdlzork"}
    for source in data["sources"].values():
        assert len(source["commit"]) == 40
        assert source["url"].startswith("https://github.com/")


def test_reference_scenario_shape():
    data = json.loads((ROOT / "tests/scenarios/house.json").read_text())
    assert data["name"] == "house-smoke"
    assert all(isinstance(x, str) and x.strip() for x in data["commands"])


def test_primitive_probe_fixture():
    data = json.loads((ROOT / "tests/scenarios/primitives.json").read_text())
    assert data["name"] == "primitive-smoke"
    assert all(x["expression"].strip() for x in data["cases"])


def test_transcript_passes_identical():
    capture = {"complete": True, "scenario": "s", "initial_output": "Welcome\n",
               "commands": [{"input": "look", "output": "West of House\n", "prompt_returned": True}]}
    assert not differences(capture, capture)


def test_transcript_rejects_semantic_difference():
    ref = {"complete": True, "scenario": "s", "initial_output": "x\n", "commands": []}
    candidate = {"complete": True, "scenario": "s", "initial_output": "y\n", "commands": []}
    assert "initial output differs" in differences(ref, candidate)[0]


def test_incomplete_capture_cannot_pass():
    record = {"complete": False, "scenario": "s", "initial_output": "", "commands": []}
    assert differences(record, record)


def test_canonical_text_preserves_meaningful_whitespace():
    assert canonical_text("one\r\ntwo\x1b[1m\r") == "one\ntwo\n"
    assert canonical_text("two  spaces") == "two  spaces"


def test_racket_local_install_command_has_no_dot_source():
    """Racket infers the package name when no source arg is given, not from `.`."""
    for path in ["README.md", "Makefile", ".github/workflows/ci.yml"]:
        content = (ROOT / path).read_text()
        assert "raco pkg install --auto --link ." not in content
        assert "raco pkg install --auto --link" in content


def test_doctor_reports_success_when_racket_and_tools_present(monkeypatch, capsys):
    from scripts import doctor

    class GcVersion:
        returncode = 0
        stdout = "8.0.4\n"

    monkeypatch.setattr(doctor.shutil, "which", lambda command: f"/usr/bin/{command}")
    monkeypatch.setattr(doctor.subprocess, "run", lambda *args, **kwargs: GcVersion())
    assert doctor.main() == 0
    message = capsys.readouterr().out
    assert "Required tools detected" in message
    assert "BDW GC:       8.0.4" in message
    assert "Missing Racket prevents" not in message


def test_doctor_requires_racket(monkeypatch, capsys):
    from scripts import doctor

    class GcVersion:
        returncode = 0
        stdout = "8.0.4\n"

    monkeypatch.setattr(
        doctor.shutil, "which",
        lambda command: None if command == "racket" else f"/usr/bin/{command}",
    )
    monkeypatch.setattr(doctor.subprocess, "run", lambda *args, **kwargs: GcVersion())
    assert doctor.main() == 1
    message = capsys.readouterr().out
    assert "Missing required tools: racket" in message
    assert "Install Racket" in message
