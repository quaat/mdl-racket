"""ADR-0065: the tracked reference corpus stays within its size policy."""
import json

from scripts import reference_size_audit as audit

MiB = 1048576
POLICY = {"soft_total_budget_bytes": 64 * MiB, "single_file_limit_bytes": 8 * MiB,
          "justifications": []}


def test_real_corpus_within_policy():
    policy = json.loads(audit.POLICY.read_text(encoding="utf-8"))
    assert policy["soft_total_budget_bytes"] == 64 * MiB
    sizes = audit.tracked_sizes(policy["roots"])
    assert sizes, "no tracked reference files found"
    assert audit.violations(policy, sizes) == []


def test_oversized_file_needs_justification():
    sizes = {"docs/evidence/M4/big.json": 9 * MiB}
    assert len(audit.violations(POLICY, sizes)) == 1
    ok = {**POLICY, "justifications": [{"path": "docs/evidence/M4/big.json",
                                        "bytes_allowed": 10 * MiB}]}
    assert audit.violations(ok, sizes) == []


def test_total_over_budget_needs_justification():
    sizes = {f"docs/evidence/f{i}.json": 7 * MiB for i in range(10)}
    problems = audit.violations(POLICY, sizes)
    assert len(problems) == 1 and "soft budget" in problems[0]
    ok = {**POLICY, "justifications": [{"path": "TOTAL", "bytes_allowed": 80 * MiB}]}
    assert audit.violations(ok, sizes) == []
