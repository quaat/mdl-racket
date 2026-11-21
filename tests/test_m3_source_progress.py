"""Guard the M3 loader report against false progress and stale M2 barriers."""

from copy import deepcopy

import pytest

from scripts.m3_source_progress import validate_report


BASELINE = {
    "entry": "a.mud",
    "minimum_completed_expressions": 2,
    "accepted_prefix": [
        {"file": "a.mud", "expression_index": 1, "construct": "DEFINE"},
        {"file": "b.mud", "expression_index": 1, "construct": "SETG"},
    ],
    "reference_files": ["b.mud", "c.mud"],
    "source_form_counts": {"a.mud": 2, "b.mud": 3, "c.mud": 1},
}


def incomplete_report():
    return {
        "entry": "a.mud",
        "status": "FAIL",
        "completed_expressions": 2,
        "skipped_expressions": 0,
        "events": [
            {"status": "PASS", "file": "a.mud", "expression_index": 1,
             "construct": "DEFINE", "load_chain": ["a.mud"]},
            {"status": "PASS", "file": "b.mud", "expression_index": 1,
             "construct": "SETG", "load_chain": ["a.mud", "b.mud"]},
            {"status": "FAIL", "file": "b.mud", "expression_index": 2,
             "construct": "UNKNOWN", "load_chain": ["a.mud", "b.mud"]},
        ],
        "failure": {"file": "b.mud", "expression_index": 2,
                    "line": 4, "column": 1, "stage": "execute",
                    "classification": "runtime", "construct": "UNKNOWN",
                    "exception": "unassigned UNKNOWN",
                    "load_chain": ["a.mud", "b.mud"]},
    }


def test_incomplete_baseline_is_a_valid_progress_observation():
    summary = validate_report(incomplete_report(), BASELINE)
    assert summary["stage"] == "EXECUTED_PARTIAL"
    assert summary["progress_delta"] == 0
    assert summary["completed_per_file"] == {"a.mud": 1, "b.mud": 1}
    assert summary["files_partially_executed"] == ["a.mud", "b.mud"]


def test_new_dependency_after_forward_progress_is_accepted():
    report = incomplete_report()
    report["events"].insert(2, {"status": "PASS", "file": "b.mud",
                                 "expression_index": 2, "construct": "DEFINE",
                                 "load_chain": ["a.mud", "b.mud"]})
    report["completed_expressions"] = 3
    report["failure"]["expression_index"] = 3
    report["events"][-1]["expression_index"] = 3
    assert validate_report(report, BASELINE)["progress_delta"] == 1


@pytest.mark.parametrize("mutation", [
    lambda r: r.update(skipped_expressions=1),
    lambda r: r.update(completed_expressions=1),
    lambda r: r["events"].append({"status": "PASS", "file": "a.mud",
                                  "expression_index": 3, "construct": "SETG"}),
    lambda r: r["events"][0].update(construct="FALSE"),
    lambda r: r["failure"].update(exception=""),
])
def test_regressions_and_malformed_reports_fail(mutation):
    report = deepcopy(incomplete_report())
    mutation(report)
    with pytest.raises(ValueError):
        validate_report(report, BASELINE)


def test_false_completion_without_reference_files_fails():
    report = incomplete_report()
    report["status"] = "PASS"
    report["failure"] = None
    report["events"] = report["events"][:-1]
    with pytest.raises(ValueError, match="reference"):
        validate_report(report, BASELINE)


def test_false_completion_with_all_files_but_missing_forms_fails():
    report = incomplete_report()
    report["status"] = "PASS"
    report["failure"] = None
    report["events"] = report["events"][:-1] + [
        {"status": "PASS", "file": "c.mud", "expression_index": 1,
         "construct": "SETG", "load_chain": ["a.mud", "c.mud"]}]
    report["completed_expressions"] = 3
    with pytest.raises(ValueError, match="completely loaded"):
        validate_report(report, BASELINE)
