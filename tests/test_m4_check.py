"""`make m4-check` term logic (scripts/m4_check.py) and manifest completeness.

No Racket, no game run: the term computation is tested on fake check results,
and the completeness test reads the real Makefile, tests/scenarios/*.json and
the two declared manifests.
"""
from copy import deepcopy

import pytest

from scripts import m4_check as m
from scripts.m4_check import FAIL, NOT_RUN, NOT_YET, PASS, UNCOVERED


MANIFEST = {
    "clock": {"fixed_epoch": 250776000, "tz": "UTC"},
    "scenarios": [
        {"name": "a", "target": "test-m4-a", "scenario_file": "tests/scenarios/a.json",
         "runner_test": "tests/a_test.rkt"},
        {"name": "b", "target": "test-m4-b", "scenario_file": "tests/scenarios/b.json",
         "runner_test": "tests/b_test.rkt"},
    ],
    "persistence": [{"name": "p", "target": "test-m4-p"}],
    "playable_subchecks": [{"name": "s", "target": "test-m3-s"}],
    "playable_missing": ["a PLAYABLE gate"],
    "full_completion": {"check": None, "reason": "Phase 6"},
    "m4_plan_requirements": [
        {"id": "R1", "text": "scenarios", "satisfied_by_term": "SCENARIO_PARITY"},
        {"id": "R4", "text": "completion", "satisfied_by_term": "FULL_COMPLETION"},
    ],
    "excluded_scenario_files": [{"file": "tests/scenarios/x.json", "reason": "M3"}],
}

BRANCHES = {
    "list_status": "APPROVED test list",
    "baseline_version": 1,
    "categories": [
        {"name": "combat", "branches": [
            {"id": "combat.one", "required": True, "checks": ["test-m4-a"]},
            {"id": "combat.two", "required": True, "checks": ["test-m4-b", "test-m4-p"]},
        ]},
    ],
    "blocking_inventory": [],
}

MAKEFILE = """\
.PHONY: test-m4-a test-m4-b
test-m4-a: sources
\t@racket tests/a_test.rkt
test-m4-b: sources
\t@racket tests/b_test.rkt
test-m4-p: sources
\t@racket tests/p_test.rkt
test-m3-s: sources
\t@raco test tests/s_test.rkt
M4_SCENARIO_TESTS := tests/a_test.rkt \\
\ttests/b_test.rkt
"""
FILES = ["tests/scenarios/a.json", "tests/scenarios/b.json", "tests/scenarios/x.json"]


def res(**statuses):
    return {t.replace("_", "-"): {"status": s} for t, s in statuses.items()}


ALL_PASS = res(test_m4_a=PASS, test_m4_b=PASS, test_m4_p=PASS, test_m3_s=PASS)


# -- SCENARIO_PARITY ---------------------------------------------------------

def test_scenario_parity_pass_only_when_every_scenario_passes():
    t = m.scenario_parity_term(MANIFEST, ALL_PASS, [])
    assert t["status"] == PASS
    assert "2 scenarios, each under one fixed clock and seed" in t["scope"]


@pytest.mark.parametrize("failing", ["test-m4-a", "test-m4-b"])
def test_any_scenario_failure_fails_scenario_parity(failing):
    results = deepcopy(ALL_PASS)
    results[failing]["status"] = FAIL
    t = m.scenario_parity_term(MANIFEST, results, [])
    assert t["status"] == FAIL


def test_unrun_scenario_is_not_run_never_pass():
    results = res(test_m4_a=PASS)
    assert m.scenario_parity_term(MANIFEST, results, [])["status"] == NOT_RUN
    results["test-m4-b"] = {"status": NOT_RUN}
    assert m.scenario_parity_term(MANIFEST, results, [])["status"] == NOT_RUN


def test_incomplete_manifest_fails_scenario_parity_even_if_all_pass():
    t = m.scenario_parity_term(MANIFEST, ALL_PASS, ["target test-m4-c missing"])
    assert t["status"] == FAIL


def test_per_prefix_failure_fails_scenario_parity():
    t = m.scenario_parity_term(MANIFEST, ALL_PASS, [], per_prefix={"status": FAIL})
    assert t["status"] == FAIL


def test_empty_scenario_list_is_never_pass():
    t = m.scenario_parity_term({**MANIFEST, "scenarios": []}, ALL_PASS, [])
    assert t["status"] == NOT_RUN


def test_persistence_is_not_a_scenario():
    results = deepcopy(ALL_PASS)
    results["test-m4-p"]["status"] = FAIL
    assert m.scenario_parity_term(MANIFEST, results, [])["status"] == PASS
    assert "p" not in m.scenario_parity_term(MANIFEST, results, [])["scenarios"]


# -- GAMEPLAY_RELIABILITY ------------------------------------------------------

def test_gameplay_reliability_pass_only_with_full_coverage_and_no_blockers():
    assert m.gameplay_reliability_term(BRANCHES, ALL_PASS)["status"] == PASS


def test_uncovered_branch_is_never_pass():
    b = deepcopy(BRANCHES)
    b["categories"][0]["branches"].append({"id": "combat.three", "required": True,
                                           "checks": []})
    t = m.gameplay_reliability_term(b, ALL_PASS)
    assert t["status"] == NOT_YET
    assert t["branches"]["combat.three"]["status"] == UNCOVERED


@pytest.mark.parametrize("status", ["PROVISIONAL (draft)", "", None])
def test_unapproved_branch_list_is_never_pass(status):
    b = deepcopy(BRANCHES)
    if status is None:
        del b["list_status"]
    else:
        b["list_status"] = status
    t = m.gameplay_reliability_term(b, ALL_PASS)
    assert t["status"] == NOT_YET
    assert any("not maintainer-approved" in r for r in t["reasons"])


def test_approved_branch_list_scope_names_the_baseline():
    t = m.gameplay_reliability_term(BRANCHES, ALL_PASS)
    assert "branch list APPROVED (baseline v1)" in t["scope"]


def test_open_blocking_item_is_never_pass():
    b = deepcopy(BRANCHES)
    b["blocking_inventory"] = [{"id": "INV-06", "status": "open"}]
    t = m.gameplay_reliability_term(b, ALL_PASS)
    assert t["status"] == NOT_YET
    assert t["blocking_open"] == ["INV-06"]
    b["blocking_inventory"][0]["status"] = "closed"
    assert m.gameplay_reliability_term(b, ALL_PASS)["status"] == PASS


def test_partly_run_branch_is_not_pass():
    results = res(test_m4_a=PASS, test_m4_b=PASS)  # test-m4-p never ran
    t = m.gameplay_reliability_term(BRANCHES, results)
    assert t["status"] == NOT_RUN
    assert t["branches"]["combat.two"]["status"] == NOT_RUN


def test_failing_covering_check_fails_gameplay_reliability():
    results = deepcopy(ALL_PASS)
    results["test-m4-p"]["status"] = FAIL
    assert m.gameplay_reliability_term(BRANCHES, results)["status"] == FAIL


def test_no_declared_branches_is_never_pass():
    t = m.gameplay_reliability_term({"categories": []}, ALL_PASS)
    assert t["status"] == NOT_YET


# -- PLAYABLE, FULL_COMPLETION ---------------------------------------------------

def test_playable_is_never_pass_without_a_gate():
    t = m.playable_term(MANIFEST, ALL_PASS)
    assert t["status"] == NOT_RUN
    assert any("PLAYABLE gate" in r for r in t["reasons"])


def test_failing_playable_subcheck_fails_playable():
    results = deepcopy(ALL_PASS)
    results["test-m3-s"]["status"] = FAIL
    assert m.playable_term(MANIFEST, results)["status"] == FAIL


def test_full_completion_not_run_without_a_check():
    t = m.full_completion_term(MANIFEST, ALL_PASS)
    assert t["status"] == NOT_RUN and t["reasons"] == ["Phase 6"]


# -- M4_ACCEPTED and exit policy ------------------------------------------------

def _terms(**over):
    base = {n: {"status": PASS, "scope": "", "reasons": []} for n in m.TERMS[:-1]}
    for k, v in over.items():
        base[k]["status"] = v
    return base


def test_m4_accepted_pass_only_when_all_four_terms_pass():
    assert m.m4_accepted_term(_terms(), MANIFEST)["status"] == PASS
    for name in m.TERMS[:-1]:
        for s in (FAIL, NOT_RUN, NOT_YET):
            t = m.m4_accepted_term(_terms(**{name: s}), MANIFEST)
            assert t["status"] == NOT_YET, (name, s)
            assert any(name in r for r in t["reasons"])


def test_m4_accepted_needs_maintainer_record_for_manual_requirement():
    man = deepcopy(MANIFEST)
    man["m4_plan_requirements"].append({"id": "R5", "text": "exceptions justified",
                                        "satisfied_by_term": None,
                                        "maintainer_record": None})
    t = m.m4_accepted_term(_terms(), man)
    assert t["status"] == NOT_YET
    man["m4_plan_requirements"][-1]["maintainer_record"] = "docs/does-not-exist.md"
    assert m.m4_accepted_term(_terms(), man)["status"] == NOT_YET


GOOD_RECORD = """# M4 maintainer acceptance (R5)

Maintainer acceptance: ACCEPTED
Accepted by: the maintainer
Date: 2027-01-31
Reviewed commit: 0123456789abcdef0123456789abcdef01234567
Source pins: mit_zork d945013, mdlzork bdcd4a6

## Accepted semantic deviations
## Evidence
## Scope and consequences
## Remaining limitations
"""


def test_maintainer_record_must_have_every_field(tmp_path, monkeypatch):
    monkeypatch.setattr(m, "ROOT", tmp_path)
    man = deepcopy(MANIFEST)
    man["m4_plan_requirements"].append({"id": "R5", "text": "exceptions justified",
                                        "satisfied_by_term": None,
                                        "maintainer_record": "r5.md"})
    (tmp_path / "r5.md").write_text(GOOD_RECORD, encoding="utf-8")
    assert m.m4_accepted_term(_terms(), man)["status"] == PASS
    for broken in ("Maintainer acceptance: ACCEPTED", "Date: 2027-01-31",
                   "Reviewed commit: 0123456789abcdef0123456789abcdef01234567",
                   "## Remaining limitations"):
        (tmp_path / "r5.md").write_text(GOOD_RECORD.replace(broken, ""), encoding="utf-8")
        t = m.m4_accepted_term(_terms(), man)
        assert t["status"] == NOT_YET, broken
        assert any("maintainer record r5.md" in r for r in t["reasons"])
    # A draft or pending record never counts.
    (tmp_path / "r5.md").write_text(
        GOOD_RECORD.replace("ACCEPTED\n", "PENDING\n", 1), encoding="utf-8")
    assert m.m4_accepted_term(_terms(), man)["status"] == NOT_YET


def test_m4_accepted_without_requirements_is_not_pass():
    man = {**MANIFEST, "m4_plan_requirements": []}
    assert m.m4_accepted_term(_terms(), man)["status"] == NOT_YET


def test_compute_terms_on_real_shape_never_accepts_today():
    terms = m.compute_terms(MANIFEST, BRANCHES, ALL_PASS, [])
    assert list(terms) == list(m.TERMS)
    assert terms["SCENARIO_PARITY"]["status"] == PASS
    assert terms["PLAYABLE"]["status"] == NOT_RUN
    assert terms["FULL_COMPLETION"]["status"] == NOT_RUN
    assert terms["M4_ACCEPTED"]["status"] == NOT_YET


def test_exit_policy():
    terms = m.compute_terms(MANIFEST, BRANCHES, ALL_PASS, [])
    checks = [{"status": PASS}]
    assert m.exit_code(terms, checks, []) == m.EXIT_OK
    assert m.exit_code(terms, checks, [], require_accepted=True) == m.EXIT_NOT_ACCEPTED
    assert m.exit_code(terms, [{"status": FAIL}], []) == m.EXIT_FAIL
    assert m.exit_code(terms, checks, ["problem"]) == m.EXIT_FAIL
    failing = deepcopy(ALL_PASS)
    failing["test-m4-a"]["status"] = FAIL
    t2 = m.compute_terms(MANIFEST, BRANCHES, failing, [])
    assert m.exit_code(t2, checks, [], require_accepted=True) == m.EXIT_FAIL


# -- completeness (fake repository) ---------------------------------------------

def test_completeness_clean_fake_repo():
    assert m.completeness_problems(MANIFEST, MAKEFILE, FILES, BRANCHES) == []


def test_new_m4_target_not_in_manifest_is_reported():
    mk = MAKEFILE + "test-m4-new: sources\n\t@racket tests/new_test.rkt\n"
    probs = m.completeness_problems(MANIFEST, mk, FILES, BRANCHES)
    assert any("test-m4-new" in p for p in probs)


def test_new_scenario_file_not_in_manifest_is_reported():
    probs = m.completeness_problems(MANIFEST, MAKEFILE, FILES + ["tests/scenarios/new.json"],
                                    BRANCHES)
    assert any("new.json" in p for p in probs)


def test_branch_citing_undeclared_check_is_reported():
    b = deepcopy(BRANCHES)
    b["categories"][0]["branches"][0]["checks"] = ["test-m4-ghost"]
    probs = m.completeness_problems(MANIFEST, MAKEFILE, FILES, b)
    assert any("test-m4-ghost" in p for p in probs)


def test_runner_list_drift_is_reported():
    mk = MAKEFILE.replace("\\\n\ttests/b_test.rkt", "")
    probs = m.completeness_problems(MANIFEST, mk, FILES, BRANCHES)
    assert any("M4_SCENARIO_TESTS" in p for p in probs)


def test_makefile_parsing_helpers():
    assert {"test-m4-a", "test-m4-b", "test-m4-p", "test-m3-s"} <= m.makefile_targets(MAKEFILE)
    assert "M4_SCENARIO_TESTS" not in m.makefile_targets(MAKEFILE)
    assert m.makefile_list_var(MAKEFILE, "M4_SCENARIO_TESTS") == ["tests/a_test.rkt",
                                                                 "tests/b_test.rkt"]
    assert "tests/b_test.rkt" in m.makefile_recipe(MAKEFILE, "test-m4-b")
    assert "tests/a_test.rkt" not in m.makefile_recipe(MAKEFILE, "test-m4-b")


# -- completeness (the real repository) -------------------------------------------

def test_real_manifest_is_complete():
    """Every test-m4-* target and every tests/scenarios/*.json file is declared."""
    manifest, branches = m.load_json(m.MANIFEST), m.load_json(m.BRANCHES)
    files = sorted(m.rel(p) for p in m.SCENARIO_DIR.glob("*.json"))
    makefile = m.MAKEFILE.read_text(encoding="utf-8")
    assert m.completeness_problems(manifest, makefile, files, branches) == []
    targets = m.makefile_targets(makefile)
    declared = m.manifest_targets(manifest)
    assert {t for t in targets if t.startswith("test-m4-")} <= set(declared)
    assert declared["test-m4-replay-persistence"] == "persistence"


def test_real_branch_list_cannot_pass_today():
    """Conservative: the declared branch list has uncovered branches and open
    blockers, so GAMEPLAY_RELIABILITY cannot be PASS even if every check passes."""
    manifest, branches = m.load_json(m.MANIFEST), m.load_json(m.BRANCHES)
    every_pass = {t: {"status": PASS} for t in m.manifest_targets(manifest)}
    terms = m.compute_terms(manifest, branches, every_pass, [])
    assert terms["SCENARIO_PARITY"]["status"] == PASS
    assert terms["GAMEPLAY_RELIABILITY"]["status"] == NOT_YET
    assert {"INV-06", "INV-07"} <= set(terms["GAMEPLAY_RELIABILITY"]["blocking_open"])
    assert terms["PLAYABLE"]["status"] == NOT_RUN
    assert terms["FULL_COMPLETION"]["status"] == NOT_RUN
    assert terms["M4_ACCEPTED"]["status"] == NOT_YET
    # The 23-branch baseline is maintainer-approved (2026-11-26); R5 has no
    # maintainer record yet, so M4_ACCEPTED cannot be PASS whatever passes.
    assert m.list_approved(branches)
    assert branches["baseline_version"] == 1
    required = [b for c in branches["categories"] for b in c["branches"]
                if b.get("required", True)]
    assert len(required) == 23
    r5 = [r for r in manifest["m4_plan_requirements"] if r["id"].startswith("R5")]
    assert r5 and r5[0]["maintainer_record"] is None
    assert any("R5" in r for r in terms["M4_ACCEPTED"]["reasons"])
    for name in ("combat", "death-and-recovery", "timers", "objects", "scoring",
                 "save-load"):
        assert name in {c["name"] for c in branches["categories"]}
