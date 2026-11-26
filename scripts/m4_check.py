#!/usr/bin/env python3
"""`make m4-check`: the M4 acceptance-term report (epic #163, Phase 7).

Reports the five M4 acceptance terms of docs/STATUS.md SEPARATELY, never
collapsed into one PASS:

  SCENARIO_PARITY       every declared M4 native-parity scenario target exits 0
                        (scoped: N scenarios, each under one fixed clock and seed)
  GAMEPLAY_RELIABILITY  every declared required gameplay branch is covered by a
                        check that ran and passed, no blocking inventory item
                        is open, and the branch list is maintainer-APPROVED
                        (docs/evidence/M4/gameplay-branches.json)
  PLAYABLE              NOT RUN: no verified PLAYABLE gate exists; the available
                        evidence sub-checks are run and reported, a failing one
                        makes the term FAIL, passing ones never make it PASS
  FULL_COMPLETION       NOT RUN: no complete-game run exists (Phase 6)
  M4_ACCEPTED           PASS only if all four terms PASS and every M4 PLAN
                        requirement is met (R5: a committed maintainer record
                        with the required fields); otherwise NOT YET

Every check is declared in tests/scenarios/m4-manifest.json; nothing is
discovered implicitly at run time, and tests/test_m4_check.py fails when a
`test-m4-*` target or a scenario JSON file is missing from that manifest.

Statuses: PASS, FAIL, NOT RUN (not executed: skipped, prerequisite failed, or
no check exists), NOT YET (executed what exists, requirements unmet).

Exit policy: 0 when no term and no executed check is FAIL (NOT RUN and NOT YET
are allowed); 1 on any FAIL (including an incomplete manifest or a failed
`make sources`); with --require-accepted, 3 when M4_ACCEPTED is not PASS and
nothing FAILed. Ordinary PR CI runs without --require-accepted (regression
result); the final milestone gate is `make m4-accept` (--require-accepted
--per-prefix). The report is written to artifacts/m4-check/m4-check.json,
per-check logs to artifacts/m4-check/logs/. A PASS here is a technical result
of the commit it ran on; a local branch result is never mainline acceptance.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/m4-check"
MANIFEST = ROOT / "tests/scenarios/m4-manifest.json"
BRANCHES = ROOT / "docs/evidence/M4/gameplay-branches.json"
MAKEFILE = ROOT / "Makefile"
SCENARIO_DIR = ROOT / "tests/scenarios"
MDLI = ROOT / ".cache/build/confusion_patched/mdli"

PASS, FAIL, NOT_RUN, NOT_YET = "PASS", "FAIL", "NOT RUN", "NOT YET"
UNCOVERED = "UNCOVERED"
TERMS = ("SCENARIO_PARITY", "GAMEPLAY_RELIABILITY", "PLAYABLE",
         "FULL_COMPLETION", "M4_ACCEPTED")
PER_PREFIX_TARGET = "m4-scenarios-per-prefix"
EXIT_OK, EXIT_FAIL, EXIT_NOT_ACCEPTED = 0, 1, 3


# --------------------------------------------------------------------------
# Manifest reading and completeness (pure; unit-tested)

def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def makefile_targets(text: str) -> set[str]:
    """Rule targets defined in a Makefile (`name:` at line start, not `:=`)."""
    return set(re.findall(r"^([A-Za-z0-9][A-Za-z0-9_.-]*)\s*:(?!=)", text, re.M))


def makefile_list_var(text: str, name: str) -> list[str]:
    """Words of a `NAME := a b \\ c` variable, continuation lines included."""
    m = re.search(rf"^{re.escape(name)}\s*:?=((?:.*\\\n)*.*)$", text, re.M)
    if not m:
        return []
    return m.group(1).replace("\\\n", " ").split()


def makefile_recipe(text: str, target: str) -> str:
    """The recipe lines (tab-indented) following `target:`."""
    m = re.search(rf"^{re.escape(target)}\s*:(?!=).*\n((?:\t.*\n?)*)", text, re.M)
    return m.group(1) if m else ""


def manifest_targets(manifest: dict) -> dict[str, str]:
    """target -> kind ('scenario', 'persistence', 'playable')."""
    out: dict[str, str] = {}
    for kind, key in (("scenario", "scenarios"), ("persistence", "persistence"),
                      ("playable", "playable_subchecks")):
        for entry in manifest.get(key, []):
            out[entry["target"]] = kind
    return out


def completeness_problems(manifest: dict, makefile_text: str,
                          scenario_files: list[str], branches: dict) -> list[str]:
    """Every way the declared lists can drift from the repository.

    scenario_files are repository-relative paths of tests/scenarios/*.json.
    An empty list means the manifest is complete."""
    problems: list[str] = []
    targets = makefile_targets(makefile_text)
    scenarios = manifest.get("scenarios", [])
    if not scenarios:
        problems.append("manifest declares no scenarios")
    declared = manifest_targets(manifest)
    seen: set[str] = set()
    for kind, key in (("scenario", "scenarios"), ("persistence", "persistence"),
                      ("playable", "playable_subchecks")):
        for entry in manifest.get(key, []):
            t = entry.get("target")
            if not t:
                problems.append(f"{key} entry without a target: {entry}")
                continue
            if t in seen:
                problems.append(f"target {t} declared twice")
            seen.add(t)
            if t not in targets:
                problems.append(f"{kind} target {t} is not a Makefile target")
    for t in sorted(targets):
        if t.startswith("test-m4-") and t not in declared:
            problems.append(f"Makefile target {t} is not in tests/scenarios/m4-manifest.json")
    for t, kind in declared.items():
        if t.startswith("test-m4-") and kind not in ("scenario", "persistence"):
            problems.append(f"{t} must be a scenario or persistence entry, not {kind}")
    listed_files = {e.get("scenario_file") for e in scenarios}
    excluded = {e.get("file") for e in manifest.get("excluded_scenario_files", [])}
    for e in manifest.get("excluded_scenario_files", []):
        if not e.get("reason"):
            problems.append(f"excluded scenario file {e.get('file')} has no reason")
    for f in scenario_files:
        if f not in listed_files and f not in excluded:
            problems.append(f"scenario file {f} is neither an M4 scenario nor excluded "
                            "with a reason in tests/scenarios/m4-manifest.json")
    for f in sorted((listed_files | excluded) - set(scenario_files) - {None}):
        problems.append(f"manifest names {f}, which does not exist")
    per_prefix = makefile_list_var(makefile_text, "M4_SCENARIO_TESTS")
    runners = [e.get("runner_test") for e in scenarios]
    if sorted(per_prefix) != sorted(r for r in runners if r):
        problems.append("Makefile M4_SCENARIO_TESTS (m4-scenarios-per-prefix) differs from "
                        f"the manifest's runner_test list: {sorted(per_prefix)} vs "
                        f"{sorted(r for r in runners if r)}")
    for e in scenarios:
        rt = e.get("runner_test")
        if rt and rt not in makefile_recipe(makefile_text, e.get("target", "")):
            problems.append(f"target {e.get('target')} does not run its runner_test {rt}")
    for cat in branches.get("categories", []):
        for b in cat.get("branches", []):
            for c in b.get("checks", []):
                if c not in declared:
                    problems.append(f"branch {b.get('id')} cites {c}, which m4-check "
                                    "does not run (not in the manifest)")
    for item in branches.get("blocking_inventory", []):
        if item.get("status") not in ("open", "closed"):
            problems.append(f"blocking item {item.get('id')} has status "
                            f"{item.get('status')!r}; expected open or closed")
    return problems


# --------------------------------------------------------------------------
# Term computation (pure; unit-tested). `results` maps a make target to a
# check record with at least {"status": PASS|FAIL|NOT RUN}.

def _status(results: dict, target: str) -> str:
    return results.get(target, {}).get("status", NOT_RUN)


def scenario_parity_term(manifest: dict, results: dict, problems: list[str],
                         per_prefix: dict | None = None) -> dict:
    names = [(e["name"], e["target"]) for e in manifest.get("scenarios", [])]
    per = {name: _status(results, t) for name, t in names}
    failed = [n for n, s in per.items() if s == FAIL]
    not_run = [n for n, s in per.items() if s != PASS and s != FAIL]
    reasons: list[str] = []
    if problems:
        reasons.append(f"manifest incomplete ({len(problems)} problem(s))")
    if failed:
        reasons.append("failed: " + ", ".join(failed))
    if per_prefix is not None and per_prefix.get("status") == FAIL:
        reasons.append(f"{PER_PREFIX_TARGET} failed")
    if problems or failed or (per_prefix is not None and per_prefix.get("status") == FAIL):
        status = FAIL
    elif not names or not_run:
        status = NOT_RUN
        reasons.append("not run: " + (", ".join(not_run) if not_run else "no scenarios"))
    else:
        status = PASS
    scope = (f"{len(names)} scenarios, each under one fixed clock and seed "
             f"(fixed_epoch {manifest.get('clock', {}).get('fixed_epoch')}, "
             f"{manifest.get('clock', {}).get('tz')}); per scenario, not gameplay coverage")
    if per_prefix is not None:
        scope += f"; per-prefix protocol: {per_prefix.get('status')}"
    return {"status": status, "scope": scope, "reasons": reasons, "scenarios": per,
            "per_prefix": None if per_prefix is None else per_prefix.get("status")}


def branch_status(branch: dict, results: dict) -> str:
    checks = branch.get("checks", [])
    if not checks:
        return UNCOVERED
    states = [_status(results, c) for c in checks]
    if FAIL in states:
        return FAIL
    if any(s != PASS for s in states):
        return NOT_RUN
    return PASS


def list_status_word(branches: dict) -> str:
    return (branches.get("list_status") or "").split(" ")[0] or "UNSPECIFIED"


def list_approved(branches: dict) -> bool:
    """The maintainer approved the required-branch list (ADR-0063 amendment,
    2026-11-26). A PROVISIONAL or unspecified list can never give PASS."""
    return list_status_word(branches) == "APPROVED"


def gameplay_reliability_term(branches: dict, results: dict) -> dict:
    per: dict[str, dict] = {}
    for cat in branches.get("categories", []):
        for b in cat.get("branches", []):
            if not b.get("required", True):
                continue
            per[b["id"]] = {"category": cat["name"], "status": branch_status(b, results),
                            "checks": b.get("checks", [])}
    open_items = [i["id"] for i in branches.get("blocking_inventory", [])
                  if i.get("status") != "closed"]
    by = lambda s: [k for k, v in per.items() if v["status"] == s]  # noqa: E731
    failed, uncovered, not_run = by(FAIL), by(UNCOVERED), by(NOT_RUN)
    reasons: list[str] = []
    if failed:
        reasons.append("covering check failed: " + ", ".join(failed))
    if uncovered:
        reasons.append(f"{len(uncovered)} of {len(per)} required branches have no "
                       "covering check: " + ", ".join(uncovered))
    if open_items:
        reasons.append("open blocking inventory items: " + ", ".join(open_items))
    if not_run:
        reasons.append("covering check not run: " + ", ".join(not_run))
    if not per:
        reasons.append("no required branches declared")
    approved = list_approved(branches)
    if not approved:
        reasons.append("the required-branch list is not maintainer-approved "
                       f"(list_status {list_status_word(branches)})")
    if failed:
        status = FAIL
    elif uncovered or open_items or not per or not approved:
        status = NOT_YET
    elif not_run:
        status = NOT_RUN
    else:
        status = PASS
    covered = len(per) - len(uncovered)
    return {"status": status,
            "scope": f"{covered} of {len(per)} required branches have a covering check; "
                     f"branch list {list_status_word(branches)}"
                     + (f" (baseline v{branches['baseline_version']})"
                        if approved and branches.get("baseline_version") else ""),
            "reasons": reasons, "branches": per, "blocking_open": open_items}


def playable_term(manifest: dict, results: dict) -> dict:
    subs = {e["name"]: _status(results, e["target"])
            for e in manifest.get("playable_subchecks", [])}
    failed = [n for n, s in subs.items() if s == FAIL]
    missing = list(manifest.get("playable_missing", [])) or ["no PLAYABLE gate declared"]
    reasons = ["sub-check failed: " + ", ".join(failed)] if failed else []
    reasons += [f"missing: {m}" for m in missing]
    # Passing sub-checks are evidence, never a PLAYABLE PASS: no gate exists.
    return {"status": FAIL if failed else NOT_RUN,
            "scope": "evidence sub-checks only; no verified PLAYABLE session gate",
            "reasons": reasons, "subchecks": subs}


def full_completion_term(manifest: dict, results: dict) -> dict:
    fc = manifest.get("full_completion", {})
    check = fc.get("check")
    if not check:
        return {"status": NOT_RUN, "scope": "no complete-game check exists",
                "reasons": [fc.get("reason", "no complete-game check declared")]}
    s = _status(results, check)
    return {"status": s, "scope": f"complete-game check {check}",
            "reasons": [] if s == PASS else [f"{check}: {s}"]}


# The committed R5 maintainer record (ADR-0063 amendment, 2026-11-26). Claude
# may prepare a draft elsewhere, but only the maintainer writes this record;
# the check verifies its form, never its truth.
MAINTAINER_RECORD_FIELDS = (
    ("Maintainer acceptance", re.compile(r"^Maintainer acceptance:\s*ACCEPTED\s*$", re.M)),
    ("Accepted by", re.compile(r"^Accepted by:\s*\S.*$", re.M)),
    ("Date", re.compile(r"^Date:\s*\d{4}-\d{2}-\d{2}\s*$", re.M)),
    ("Reviewed commit", re.compile(r"^Reviewed commit:\s*[0-9a-f]{40}\s*$", re.M)),
    ("Source pins", re.compile(r"^Source pins:\s*\S.*$", re.M)),
)
MAINTAINER_RECORD_SECTIONS = ("Accepted semantic deviations", "Evidence", "Scope and consequences",
                              "Remaining limitations")


def maintainer_record_problems(path: Path) -> list[str]:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as e:
        return [f"unreadable ({e.strerror})"]
    problems = [f"missing field '{name}:'" for name, rx in MAINTAINER_RECORD_FIELDS
                if not rx.search(text)]
    problems += [f"missing section '## {sec}'" for sec in MAINTAINER_RECORD_SECTIONS
                 if not re.search(rf"^##\s+{re.escape(sec)}\s*$", text, re.M)]
    return problems


def m4_accepted_term(terms: dict, manifest: dict) -> dict:
    unmet: list[str] = []
    reqs = manifest.get("m4_plan_requirements", [])
    cited = {r.get("satisfied_by_term") for r in reqs}
    for name in TERMS[:-1]:   # all four terms are required, cited by a requirement or not
        if name not in cited and terms.get(name, {}).get("status") != PASS:
            unmet.append(f"{name} is {terms.get(name, {}).get('status', NOT_RUN)}")
    for req in reqs:
        term = req.get("satisfied_by_term")
        if term:
            if terms.get(term, {}).get("status") != PASS:
                unmet.append(f"{req['id']}: {term} is "
                             f"{terms.get(term, {}).get('status', NOT_RUN)} ({req['text']})")
        elif not req.get("maintainer_record"):
            unmet.append(f"{req['id']}: {req['text']} (no maintainer record)")
        elif not (ROOT / req["maintainer_record"]).is_file():
            unmet.append(f"{req['id']}: maintainer record {req['maintainer_record']} missing")
        else:
            unmet += [f"{req['id']}: maintainer record {req['maintainer_record']}: {p}"
                      for p in maintainer_record_problems(ROOT / req["maintainer_record"])]
    if not reqs:
        unmet.append("no M4 PLAN requirements declared")
    return {"status": NOT_YET if unmet else PASS,
            "scope": "technical result of this run; mainline acceptance is recorded by "
                     "the maintainer in docs/STATUS.md",
            "reasons": unmet}


def compute_terms(manifest: dict, branches: dict, results: dict, problems: list[str],
                  per_prefix: dict | None = None) -> dict:
    terms = {
        "SCENARIO_PARITY": scenario_parity_term(manifest, results, problems, per_prefix),
        "GAMEPLAY_RELIABILITY": gameplay_reliability_term(branches, results),
        "PLAYABLE": playable_term(manifest, results),
        "FULL_COMPLETION": full_completion_term(manifest, results),
    }
    terms["M4_ACCEPTED"] = m4_accepted_term(terms, manifest)
    return terms


def exit_code(terms: dict, checks: list[dict], problems: list[str],
              require_accepted: bool = False) -> int:
    if problems or any(c.get("status") == FAIL for c in checks) or \
            any(t["status"] == FAIL for t in terms.values()):
        return EXIT_FAIL
    if require_accepted and terms["M4_ACCEPTED"]["status"] != PASS:
        return EXIT_NOT_ACCEPTED
    return EXIT_OK


# --------------------------------------------------------------------------
# Execution and provenance

def rel(path: Path) -> str:
    try:
        return Path(os.path.abspath(path)).relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def sha256_file(path: Path) -> str | None:
    if not path.is_file():
        return None
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def git(*args: str) -> str | None:
    # safe.directory: CI containers check the repository out as another user,
    # and git then refuses to read it ("dubious ownership"), which left the
    # report without a commit. Trusting exactly this checkout for this one
    # read-only call changes nothing else.
    r = subprocess.run(["git", "-c", f"safe.directory={ROOT}", *args], cwd=ROOT,
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def git_commit() -> tuple[str | None, str]:
    """The checked-out commit and where it came from. GITHUB_SHA (on a
    pull_request event, GitHub's merge commit) only when git cannot answer."""
    sha = git("rev-parse", "HEAD")
    if sha:
        return sha, "git rev-parse HEAD"
    env = os.environ.get("GITHUB_SHA")
    if env:
        return env, "GITHUB_SHA (git unavailable)"
    return None, "unavailable"


def tool_version(cmd: list[str]) -> str | None:
    try:
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return (r.stdout or r.stderr).strip() if r.returncode == 0 else None


def run_target(name: str, command: list[str], timeout: float, logs: Path) -> dict:
    logs.mkdir(parents=True, exist_ok=True)
    log = logs / f"{name}.log"
    start = time.monotonic()
    with log.open("w", encoding="utf-8") as fh:
        fh.write(f"$ {' '.join(command)}\n")
        fh.flush()
        try:
            r = subprocess.run(command, cwd=ROOT, stdout=fh, stderr=subprocess.STDOUT,
                               timeout=timeout)
            code: int | None = r.returncode
        except subprocess.TimeoutExpired:
            fh.write(f"\nTIMEOUT after {timeout} s\n")
            code = None
        fh.write(f"[exit {code}]\n")
    return {"name": name, "command": " ".join(command), "exit_code": code,
            "status": PASS if code == 0 else FAIL,
            "duration_s": round(time.monotonic() - start, 1), "log": rel(log)}


def log_tail(path: str, lines: int = 40) -> str:
    try:
        text = (ROOT / path).read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return ""
    return "\n".join(text[-lines:])


def print_table(terms: dict) -> None:
    print("\nm4-check: acceptance terms (separate; never collapsed)")
    print(f"  {'TERM':22} {'STATUS':8}  SCOPE / REASONS")
    for name in TERMS:
        t = terms[name]
        print(f"  {name:22} {t['status']:8}  {t['scope']}")
        for r in t["reasons"]:
            print(f"  {'':22} {'':8}  - {r}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--scenarios-only", action="store_true",
                        help="run only `make sources` and the scenario targets; the "
                             "persistence and PLAYABLE sub-checks are reported NOT RUN")
    parser.add_argument("--per-prefix", action="store_true",
                        help=f"also run `make {PER_PREFIX_TARGET}` (slow; not default)")
    parser.add_argument("--skip", action="append", default=[], metavar="TARGET",
                        help="do not run this declared target (reported NOT RUN); repeatable")
    parser.add_argument("--require-accepted", action="store_true",
                        help=f"exit {EXIT_NOT_ACCEPTED} unless M4_ACCEPTED is PASS")
    parser.add_argument("--report", type=Path, default=OUT / "m4-check.json")
    parser.add_argument("--target-timeout", type=float,
                        default=float(os.environ.get("M4_TARGET_TIMEOUT", "1800")))
    args = parser.parse_args(argv)

    manifest, branches = load_json(MANIFEST), load_json(BRANCHES)
    declared = manifest_targets(manifest)
    unknown = [s for s in args.skip if s not in declared]
    if unknown:
        parser.error(f"--skip names undeclared target(s): {unknown}")
    makefile_text = MAKEFILE.read_text(encoding="utf-8")
    scenario_files = sorted(rel(p) for p in SCENARIO_DIR.glob("*.json"))
    problems = completeness_problems(manifest, makefile_text, scenario_files, branches)
    print(f"m4-check: manifest completeness "
          f"{'PASS' if not problems else 'FAIL'} ({rel(MANIFEST)}, {rel(BRANCHES)})", flush=True)
    for p in problems:
        print(f"m4-check:   - {p}", flush=True)

    py = sys.executable
    make = [os.environ.get("MAKE", "make"), "--no-print-directory", f"PYTHON={py}"]
    logs = args.report.parent / "logs"
    checks: list[dict] = []
    results: dict[str, dict] = {}

    def run(name: str, kind: str, why_not: str | None) -> dict:
        if why_not:
            entry = {"name": name, "command": " ".join(make + [name]), "exit_code": None,
                     "status": NOT_RUN, "reason": why_not}
        else:
            entry = run_target(name, make + [name], args.target_timeout, logs)
        entry["kind"] = kind
        checks.append(entry)
        results[name] = entry
        extra = entry.get("reason") or f"{entry['duration_s']}s {entry['log']}"
        print(f"m4-check: {kind:11} {name:30} {entry['status']:8} "
              f"exit={entry['exit_code']} {extra}", flush=True)
        if entry["status"] == FAIL:
            print(f"m4-check: last lines of {entry['log']}:\n{log_tail(entry['log'])}",
                  flush=True)
        return entry

    src = run("sources", "prerequisite", None)
    blocked = None if src["status"] == PASS else "make sources failed"
    for e in manifest["scenarios"]:
        run(e["target"], "scenario",
            blocked or ("skipped by --skip" if e["target"] in args.skip else None))
    per_prefix = None
    if args.per_prefix:
        per_prefix = run(PER_PREFIX_TARGET, "per-prefix", blocked)
    for key, kind in (("persistence", "persistence"), ("playable_subchecks", "playable")):
        for e in manifest.get(key, []):
            why = blocked or ("not run: --scenarios-only" if args.scenarios_only else None) \
                or ("skipped by --skip" if e["target"] in args.skip else None)
            run(e["target"], kind, why)

    terms = compute_terms(manifest, branches, results, problems, per_prefix)
    code = exit_code(terms, checks, problems, args.require_accepted)
    lock = load_json(ROOT / "sources.lock.json")
    dirty = git("status", "--porcelain", "--untracked-files=no")
    scen_counts = {}
    for e in manifest["scenarios"]:
        try:
            scen_counts[e["name"]] = len(load_json(ROOT / e["scenario_file"])["commands"])
        except (OSError, KeyError, ValueError):
            scen_counts[e["name"]] = None
    commit, commit_source = git_commit()
    report = {
        "schema_version": 1,
        "target": "make m4-check",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "mode": {"scenarios_only": args.scenarios_only, "per_prefix": args.per_prefix,
                 "skip": args.skip, "require_accepted": args.require_accepted,
                 "target_timeout_s": args.target_timeout},
        "git_commit": commit,
        "git_commit_source": commit_source,
        "git_branch": git("rev-parse", "--abbrev-ref", "HEAD"),
        "git_worktree_dirty": bool(dirty) if dirty is not None else None,
        "sources_lock": {k: v["commit"] for k, v in lock["sources"].items()},
        "racket_version": tool_version([os.environ.get("RACKET", "racket"), "--version"]),
        "python": sys.version.split()[0],
        "mdli_sha256": sha256_file(MDLI),
        "mdli_note": "the scenario targets compare with committed native captures and "
                     "do not run mdli; recorded for provenance only",
        "manifests": {rel(MANIFEST): sha256_file(MANIFEST), rel(BRANCHES): sha256_file(BRANCHES)},
        "clock": manifest.get("clock"),
        "scenario_command_counts": scen_counts,
        "manifest_completeness": {"status": FAIL if problems else PASS, "problems": problems},
        "checks": checks,
        "terms": terms,
        "exit_policy": f"{EXIT_OK}: no FAIL (NOT RUN / NOT YET allowed); {EXIT_FAIL}: any "
                       f"FAIL; {EXIT_NOT_ACCEPTED}: --require-accepted and M4_ACCEPTED "
                       "not PASS",
        "exit_code": code,
        "regression_result": "FAIL" if code == EXIT_FAIL else "OK",
        "milestone_acceptance": terms["M4_ACCEPTED"]["status"],
        "result_meaning": "regression_result OK means every executed check passed (the "
                          "ordinary PR gate); it is not milestone acceptance. Milestone "
                          "acceptance is M4_ACCEPTED PASS under `make m4-accept` "
                          "(--require-accepted), plus the maintainer's committed record.",
        "claim": "technical result of this commit only; a local branch result is not "
                 "mainline acceptance, and no term is decided here beyond what ran",
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print_table(terms)
    print(f"\nm4-check: regression result "
          f"{'FAIL' if code == EXIT_FAIL else 'OK (no executed check failed)'}; "
          f"milestone acceptance M4_ACCEPTED {terms['M4_ACCEPTED']['status']}"
          f"{'' if args.require_accepted else ' (not required in this mode)'}")
    print(f"m4-check: exit {code}; report {rel(args.report)}; commit "
          f"{(report['git_commit'] or '?')[:7]}{' (dirty)' if report['git_worktree_dirty'] else ''}")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
