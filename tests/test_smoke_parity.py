"""Unit tests of the single SMOKE_PARITY comparator (S10; ADR-0053).

Binary-free and Racket-free: they read only committed records.

* reference: docs/evidence/M3/house-boot-candidate.json, the maintainer-approved
  Confusion capture (schema 2, unchanged), and the S10 fresh capture
  docs/evidence/M3/S10-house-boot-reference.json (schema 3).
* candidate: docs/evidence/M3/S10-racket-house-boot-run.json, the raw facts of
  one run of this runtime (scripts/m3_house_boot_run.rkt), turned into a
  candidate record by smoke_parity.candidate_record.

Each negative check mutates the RAW run facts (or a reference record) and
asserts that the comparator fails on the targeted check, so the failure is
the intended one and not a side effect of an inconsistent record.
"""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import scripts.smoke_parity as sp  # noqa: E402

REFERENCE_PATH = ROOT / "docs/evidence/M3/house-boot-candidate.json"
FRESH_PATH = ROOT / "docs/evidence/M3/S10-house-boot-reference.json"
RUN_PATH = ROOT / "docs/evidence/M3/S10-racket-house-boot-run.json"
GOLDEN_PATH = ROOT / "tests/fixtures/house-boot-golden.json"

REFERENCE = json.loads(REFERENCE_PATH.read_text(encoding="utf-8"))
FRESH = json.loads(FRESH_PATH.read_text(encoding="utf-8"))
RUN = json.loads(RUN_PATH.read_text(encoding="utf-8"))

BRIEF_WEST = ">West of House\nThere is a small mailbox here.\n>"
# The full ROOM-INFO description, which <PROB 80> failing would print for "west"
# (the same text as at boot; S7-racket-vs-confusion.txt "FULL-variant").
FULL_WEST = (">You are in an open field west of a big white house, with a boarded\r\n"
             "front door.\nThere is a small mailbox here.\n>")


def run_with(old: str | None = None, new: str | None = None, **changes) -> dict:
    run = copy.deepcopy(RUN)
    if old is not None:
        assert run["raw_output"].count(old) == 1, old
        run["raw_output"] = run["raw_output"].replace(old, new)
    run.update(changes)
    return run


def candidate(run: dict | None = None) -> dict:
    return sp.candidate_record(copy.deepcopy(RUN if run is None else run))


def checks(mismatches: list[dict]) -> list[str]:
    return [m["check"] for m in mismatches]


def details(mismatches: list[dict]) -> str:
    return " | ".join(m.get("detail", "") for m in mismatches)


# ---------------------------------------------------------------------------
# Positive: the committed records agree strictly
# ---------------------------------------------------------------------------

def test_candidate_matches_committed_reference() -> None:
    assert sp.compare_records(REFERENCE, candidate()) == []


def test_fresh_reference_matches_committed_reference() -> None:
    assert FRESH["schema_version"] == 3 and REFERENCE["schema_version"] == 2
    assert sp.compare_records(REFERENCE, FRESH) == []


def test_candidate_matches_fresh_reference() -> None:
    assert sp.compare_records(FRESH, candidate()) == []


def test_candidate_run_ended_by_input_exhaustion_not_quit() -> None:
    term = candidate()["termination"]
    assert term["kind"] == "input-exhausted"
    assert term["message"] == sp.D3_MESSAGE
    assert term["tail"] == ["Beg pardon?\n", ""]
    assert "not a user QUIT" in term["protocol"]


def test_candidate_view_equals_golden_fixture() -> None:
    """The comparator's view of our run equals the S7/S8 golden extract (D1, D2)."""
    golden = json.loads(GOLDEN_PATH.read_text(encoding="utf-8"))
    view = sp.presentation_view(candidate())
    golden_boot = sp.d1_strip(golden["boot_output"])
    assert golden_boot[1] == []
    assert view["boot_output"] == golden_boot[0]
    assert view["outputs"] == [c["output"] for c in golden["commands"]]


def test_d2_is_canonical_text_of_onlcr() -> None:
    # A raw CR LF from PRINC becomes CR CR LF under ONLCR, i.e. a blank line,
    # exactly as on the reference PTY.
    assert sp.d2("a\r\nb\n") == "a\n\nb\n"
    assert sp.d2("a\nb") == "a\nb"


# ---------------------------------------------------------------------------
# Negative checks required by the S10 handoff (each must FAIL)
# ---------------------------------------------------------------------------

def test_changed_date_line_fails() -> None:
    run = run_with("This version created December 12.", "This version created December 13.")
    mm = sp.compare_records(REFERENCE, candidate(run))
    assert "date_line" in checks(mm) and "boot_output" in checks(mm)


def test_wrong_west_description_full_variant_fails() -> None:
    run = run_with(BRIEF_WEST, FULL_WEST)
    mm = sp.compare_records(REFERENCE, candidate(run))
    assert checks(mm) == ["command[1] 'west'"]
    assert mm[0]["first_difference"]["offset"] == 0


def test_altered_response_text_fails() -> None:
    run = run_with(">Taken.\n>", ">Taken!\n>")
    mm = sp.compare_records(REFERENCE, candidate(run))
    assert checks(mm) == ["command[3] 'take leaflet'"]
    fd = mm[0]["first_difference"]
    assert fd["offset"] == 5 and fd["expected_bytes"].startswith("54 61 6b 65 6e 2e")


def test_missing_command_fails() -> None:
    inputs = [c for c in RUN["command_inputs"] if c != "inventory"]
    run = run_with(">You are carrying:\nA leaflet\n>", ">", command_inputs=inputs)
    mm = sp.compare_records(REFERENCE, candidate(run))
    assert "command_inputs" in checks(mm)


def test_extra_command_fails() -> None:
    inputs = RUN["command_inputs"] + ["look"]
    run = run_with(">Beg pardon?\n>", BRIEF_WEST + "Beg pardon?\n>", command_inputs=inputs)
    mm = sp.compare_records(REFERENCE, candidate(run))
    assert "command_inputs" in checks(mm)


def test_reordered_commands_fail() -> None:
    inputs = list(RUN["command_inputs"])
    inputs[2], inputs[3] = inputs[3], inputs[2]
    mm = sp.compare_records(REFERENCE, candidate(run_with(command_inputs=inputs)))
    assert "command_inputs" in checks(mm)


def test_score_move_count_mismatch_fails() -> None:
    run = run_with("in 6 moves.", "in 7 moves.")
    mm = sp.compare_records(REFERENCE, candidate(run))
    assert "score_line" in checks(mm) and "command[5] 'score'" in checks(mm)
    # The MOVES global (6) no longer agrees with the printed score line either.
    assert "MOVES global 6 differs" in details(mm)


def test_moves_global_mismatch_fails() -> None:
    mm = sp.compare_records(REFERENCE, candidate(run_with(moves=7)))
    assert checks(mm) == ["actual-record"] and "MOVES global 7" in details(mm)


def test_score_points_mismatch_fails() -> None:
    run = run_with("would be 0 [total", "would be 10 [total")
    assert "score_line" in checks(sp.compare_records(REFERENCE, candidate(run)))


def test_incomplete_run_stopped_early_fails() -> None:
    raw = RUN["raw_output"]
    cut = raw.index(">You are carrying:") + 1
    run = run_with(raw_output=raw[:cut],
                   outcome={"kind": "timed-out", "message": "no outcome within 300 s"},
                   moves=4)
    mm = sp.compare_records(REFERENCE, candidate(run))
    assert "actual-record" in checks(mm)
    assert "not by D3 input exhaustion" in details(mm)
    assert "incomplete run" in details(mm)
    assert "command[4] 'inventory'" in checks(mm) and "complete" in checks(mm)


def test_run_ended_by_error_or_quit_fails() -> None:
    for kind in ("error", "returned"):
        run = run_with(outcome={"kind": kind, "message": "QUIT"})
        mm = sp.compare_records(REFERENCE, candidate(run))
        assert checks(mm) == ["actual-record"], kind
        assert "not by D3 input exhaustion" in details(mm)


def test_missing_input_exhausted_tail_fails() -> None:
    # Input exhausted reported, but the mirrored "Beg pardon?" read is missing.
    run = run_with(">Beg pardon?\n>", ">")
    mm = sp.compare_records(REFERENCE, candidate(run))
    assert checks(mm) == ["actual-record"] and "D3 tail" in details(mm)


def test_unconsumed_input_fails() -> None:
    mm = sp.compare_records(REFERENCE, candidate(run_with(input_remaining="look\n")))
    assert checks(mm) == ["actual-record"] and "not fully consumed" in details(mm)


# ---------------------------------------------------------------------------
# The allowed differences are not widened
# ---------------------------------------------------------------------------

def test_d1_null_print_is_not_normalised() -> None:
    """The blank line from the REP print of ,NULL must be present (D1 keeps it)."""
    run = run_with("December 12.\n\nYou are", "December 12.\nYou are")
    assert checks(sp.compare_records(REFERENCE, candidate(run))) == ["boot_output"]


def test_d1_lines_in_candidate_are_not_stripped() -> None:
    run = run_with("77dung.mud loaded\n", '77dung.mud loaded\n"DONE"\n')
    assert checks(sp.compare_records(REFERENCE, candidate(run))) == ["boot_output"]


def test_reference_without_d1_lines_fails() -> None:
    ref = copy.deepcopy(REFERENCE)
    ref["boot_output"] = ref["boot_output"].replace('"DONE"\n', "")
    mm = sp.compare_records(ref, candidate())
    assert "expected-record" in checks(mm) and "exactly 1 required" in details(mm)


def test_d2_cr_fidelity_matters() -> None:
    """Dropping a raw CR (no doubled line under ONLCR) is a mismatch."""
    run = run_with("boarded\r\nfront door.", "boarded\nfront door.")
    assert checks(sp.compare_records(REFERENCE, candidate(run))) == ["boot_output"]


def test_whitespace_is_not_folded() -> None:
    run = run_with(">Opening the mailbox reveals a leaflet.\n>",
                   ">Opening the mailbox reveals a leaflet. \n>")
    assert checks(sp.compare_records(REFERENCE, candidate(run))) == [
        "command[2] 'open mailbox'"]


def test_edited_candidate_record_fails() -> None:
    """Compared fields are re-derived from the raw run; editing them is caught."""
    rec = candidate()
    rec["commands"][1]["output"] = "edited\n"
    mm = sp.compare_records(REFERENCE, rec)
    assert "edited record" in details(mm)


def test_reference_vs_reference_mutation_fails() -> None:
    fresh = copy.deepcopy(FRESH)
    fresh["commands"][1]["output"] = FULL_WEST[1:-1].replace("\r\n", "\n\n")
    assert checks(sp.compare_records(REFERENCE, fresh)) == ["command[1] 'west'"]


def test_clock_mismatch_fails() -> None:
    for key, value in (("fixed_epoch", 250862400), ("tz", "CET")):
        mm = sp.compare_records(REFERENCE, candidate(run_with(**{key: value})))
        assert key in checks(mm)


def test_compare_files_exit_status(tmp_path: Path) -> None:
    good = tmp_path / "good.json"
    bad = tmp_path / "bad.json"
    good.write_text(json.dumps(candidate()), encoding="utf-8")
    bad.write_text(json.dumps(candidate(run_with(">Taken.\n>", ">Taken!\n>"))),
                   encoding="utf-8")
    report = tmp_path / "r.json"
    assert sp.compare_files(REFERENCE_PATH, good, report) == 0
    assert json.loads(report.read_text())["result"] == "PASS"
    assert sp.compare_files(REFERENCE_PATH, bad, report) == 1
    assert json.loads(report.read_text())["result"] == "FAIL"


def test_unknown_engine_is_refused() -> None:
    rec = candidate()
    rec["engine"] = "something-else"
    with pytest.raises(sp.ParityError):
        sp.compare_records(REFERENCE, rec)


# ---------------------------------------------------------------------------
# make m3-check: the native stage is NOT RUN (never PASS) without mdli
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("mode, status, exit_code", [
    ("auto", "NOT RUN", 0), ("require", "FAIL", 1)])
def test_m3_check_native_stage_without_mdli(tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
                                           mode: str, status: str, exit_code: int) -> None:
    import scripts.m3_check as m3
    monkeypatch.setattr(m3, "MDLI", tmp_path / "absent-mdli")
    report = tmp_path / "m3-check.json"
    monkeypatch.setattr(sys, "argv", ["m3_check.py", "--native", mode, "--stages",
                                      "native-fresh-capture-parity", "--report", str(report)])
    assert m3.main() == exit_code
    data = json.loads(report.read_text(encoding="utf-8"))
    (stage,) = data["stages"]
    assert stage["status"] == status and stage["exit_code"] is None
    assert "native prerequisites absent" in stage["reason"]
    assert data["overall"] == ("PASS" if mode == "auto" else "FAIL")
    assert data["mdli_sha256"] is None


# ---------------------------------------------------------------------------
# Schema-3 promotion (maintainer decision 2026-11-23)
# ---------------------------------------------------------------------------
PROMOTED_PATH = ROOT / "docs/evidence/M3/house-boot-reference.json"


def _sha256(path: Path) -> str:
    import hashlib
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_promoted_reference_is_the_schema3_capture_marked_approved() -> None:
    promoted = json.loads(PROMOTED_PATH.read_text(encoding="utf-8"))
    assert promoted["schema_version"] == 3 and promoted["candidate"] is False
    promo = promoted["promotion"]
    assert promo["changed_fields"] == ["candidate", "candidate_note", "promotion"]
    assert promo["promoted_from"]["file"] == "docs/evidence/M3/S10-house-boot-reference.json"
    assert promo["promoted_from"]["sha256"] == _sha256(FRESH_PATH)
    assert promo["supersedes_as_committed_reference"]["sha256"] == _sha256(REFERENCE_PATH)
    # Every other field, provenance included, is the S10 capture byte for byte.
    rest = {k: v for k, v in promoted.items() if k not in promo["changed_fields"]}
    assert rest == {k: v for k, v in FRESH.items() if k not in promo["changed_fields"]}
    inputs = promoted["provenance"]["immutable_inputs"]["game_files"]
    assert "MDL/MADADV.SAVE" not in inputs
    assert set(promoted["provenance"]["save_artifacts"]["files"]) == {"MDL/MADADV.SAVE"}


def test_three_way_strict_parity_baseline_promoted_capture(tmp_path: Path) -> None:
    # schema-2 baseline == promoted schema-3 reference == S10 fresh capture,
    # through the single strict comparator (D1/D2 only), in both directions.
    for exp, act in ((REFERENCE_PATH, PROMOTED_PATH), (PROMOTED_PATH, FRESH_PATH),
                     (PROMOTED_PATH, REFERENCE_PATH)):
        assert sp.compare_files(exp, act, tmp_path / "r.json") == 0, (exp, act)


def test_m3_check_compares_against_the_promoted_reference() -> None:
    import importlib.util
    spec = importlib.util.spec_from_file_location("m3_check", ROOT / "scripts/m3_check.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    assert mod.COMMITTED_REFERENCE == "docs/evidence/M3/house-boot-reference.json"
