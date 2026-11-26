"""Validate manual fixtures, worker observations, and retained conformance evidence."""

from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests/conformance"
MANUAL_REVISION = "89707367b951ea79bedc71f51ab213886e0f62ce"
MANUAL_URL = "https://mdl-language.readthedocs.io/en/latest/"
MANUAL_SOURCE = f"https://github.com/taradinoc/mdl-docs/blob/{MANUAL_REVISION}/docs/"
MODES = ("loader", "lang")
LOADER_LOCATION = ("classification", "stage", "construct", "expression_index", "line", "column")
STATUSES = ("PASS", "FAIL", "XFAIL", "XPASS")
REPORT_VERSION = 2
RUNNER_FILES = ("scripts/conformance_evidence.py", "scripts/test_manual.py",
                "tests/conformance/manual_test.rkt")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key {key!r}")
        result[key] = value
    return result


def invalid_constant(value):
    raise ValueError(f"invalid JSON constant {value}")


def parse_json(source):
    return json.loads(source, object_pairs_hook=unique_object, parse_constant=invalid_constant)


def read_json(path):
    return parse_json(path.read_text(encoding="utf-8"))


def digest(value):
    data = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False,
                      allow_nan=False).encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def matches(pattern, value):
    return isinstance(value, str) and re.fullmatch(pattern, value) is not None


def has_keys(value, keys):
    return isinstance(value, dict) and value.keys() == set(keys.split())


def nonempty(value):
    return isinstance(value, str) and bool(value.strip())


def typed_value(value):
    if not has_keys(value, "type primtype value") or not all(
        nonempty(value[k]) for k in ("type", "primtype")
    ):
        return False
    data = value["value"]
    match value["type"]:
        case "FIX" | "CHARACTER" | "WORD":
            return type(data) is int
        case "FLOAT":
            return type(data) is float and math.isfinite(data)
        case "ATOM" | "STRING":
            return isinstance(data, str)
        case "FALSE" | "LIST" | "VECTOR" | "UVECTOR":
            return isinstance(data, list) and all(typed_value(item) for item in data)
        case _:
            return False


def typed_observation(value):
    return (has_keys(value, "result effect output") and isinstance(value["output"], str)
            and typed_value(value["result"]) and typed_value(value["effect"]))


def location(value):
    return (all(nonempty(value.get(k)) for k in LOADER_LOCATION[:3])
            and all(type(value.get(k)) is int and value[k] > 0 for k in LOADER_LOCATION[3:]))


def validate_expectation(value, mode, gap, label):
    keys = ["exception", "output", *(LOADER_LOCATION if mode == "loader" else ())]
    if gap:
        keys.append("issue")
    require(has_keys(value, " ".join(keys)) and isinstance(value["output"], str)
            and nonempty(value["exception"]) and ":" in value["exception"],
            f"{label}: invalid diagnostic")
    if mode == "loader":
        require(location(value), f"{label}: invalid loader diagnostic location")
    if gap:
        require(matches(r"#[1-9][0-9]*", value["issue"]) and value["issue"] not in {"#177", "#178"},
                f"{label}: gap requires a semantic tracking issue")


def validate_manifest(data, manual_docs=None):
    require(has_keys(data, "schema_version cases") and type(data["schema_version"]) is int
            and data["schema_version"] == 2 and isinstance(data["cases"], list) and data["cases"],
            "invalid manifest schema")
    seen = set()
    required = set("id chapter section feature specification source origin setup expression".split())
    optional = set("effect_expression expected expected_errors gaps note manual_expected".split())
    for case in data["cases"]:
        require(isinstance(case, dict) and required <= case.keys() <= required | optional,
                "invalid fixture fields")
        label = case["id"]
        require(matches(r"[a-z0-9]+(?:-[a-z0-9]+)*", label) and label not in seen,
                f"invalid or duplicate fixture id {label!r}")
        seen.add(label)
        chapter = case["chapter"]
        require(type(chapter) is int and 1 <= chapter <= 24 and
                matches(rf"{chapter}(?:\.[1-9][0-9]*)+", case["section"]),
                f"{label}: invalid chapter or section")
        require(matches(re.escape(MANUAL_SOURCE) + rf"{chapter:02}-[a-z0-9-]+\.md#L[1-9][0-9]*",
                        case["source"]), f"{label}: invalid manual source")
        page, number = case["source"].removeprefix(MANUAL_SOURCE).split(".md#L")
        anchor_prefix = case["section"].replace(".", "") + "-"
        require(matches(re.escape(f"{MANUAL_URL}{page}/#{anchor_prefix}") + r"[a-z0-9_-]+",
                        case["specification"]), f"{label}: invalid specification reference")
        if manual_docs is not None:
            path = manual_docs / f"{page}.md"
            require(path.is_file(), f"{label}: missing pinned manual page")
            lines = path.read_text(encoding="utf-8").splitlines()
            require(int(number) <= len(lines) and re.match(
                rf"^#+ {re.escape(case['section'])}\.\s", lines[int(number) - 1]
            ), f"{label}: pinned manual section does not match source line")
        require(case["origin"] in ("manual", "adapted", "authored") and nonempty(case["feature"])
                and nonempty(case["expression"]) and isinstance(case["setup"], list)
                and all(nonempty(form) for form in case["setup"])
                and all(nonempty(case[key]) for key in ("effect_expression", "note") if key in case),
                f"{label}: invalid fixture source")
        require(("expected" in case) != ("expected_errors" in case)
                and not ({"gaps", "expected_errors"} <= case.keys()), f"{label}: ambiguous expectation")
        if "expected" in case:
            require(typed_observation(case["expected"]), f"{label}: invalid typed expectation")
        if "manual_expected" in case:
            require(typed_value(case["manual_expected"]) and "note" in case,
                    f"{label}: document the manual expectation")
        for key in ("expected_errors", "gaps"):
            if key not in case:
                continue
            specs = case[key]
            require(isinstance(specs, dict) and bool(specs) and specs.keys() <= set(MODES)
                    and (key == "gaps" or specs.keys() == set(MODES)), f"{label}: invalid {key} modes")
            for mode, diagnostic in specs.items():
                validate_expectation(diagnostic, mode, key == "gaps", f"{label}/{mode}")
    return data


def load_manifest():
    return validate_manifest(read_json(CORPUS / "manifest.json"))


def validate_observation(report, mode):
    if typed_observation(report):
        return
    require(has_keys(report, "status failure output") and report["status"] == "FAIL"
            and isinstance(report["output"], str) and isinstance(report["failure"], dict)
            and nonempty(report["failure"].get("exception")), "invalid worker observation")
    if mode == "loader":
        require(location(report["failure"]), "invalid loader observation location")
    else:
        require(has_keys(report["failure"], "exception"), "invalid frontend diagnostic")


def expected_for(case, mode):
    return {"value": case.get("expected"), "gap": case.get("gaps", {}).get(mode),
            "error": case.get("expected_errors", {}).get(mode)}


def classify(case, mode, report):
    if "harness_error" in report:
        return "FAIL"
    expected = expected_for(case, mode)
    if expected["value"] is not None and expected["value"] == report:
        return "XPASS" if expected["gap"] else "PASS"
    diagnostic = expected["error"] or expected["gap"]
    if diagnostic and report.get("status") == "FAIL" and report["output"] == diagnostic["output"]:
        keys = ("exception", *(LOADER_LOCATION if mode == "loader" else ()))
        if all(report["failure"].get(key) == diagnostic[key] for key in keys):
            return "PASS" if expected["error"] else "XFAIL"
    return "FAIL"


def git(*args, root=ROOT):
    return subprocess.check_output(["git", "-C", str(root), *args])


def runtime_digest(revision=None):
    if revision:
        names = git("ls-tree", "-rz", "--name-only", revision, "--", "mdl", "info.rkt")
    else:
        names = git("ls-files", "-z", "--cached", "--others", "--exclude-standard", "--",
                    "mdl", "info.rkt")
    paths = {name.decode() for name in names.split(b"\0") if name}
    hashes = {}
    for name in sorted(paths):
        content = git("show", f"{revision}:{name}") if revision else (ROOT / name).read_bytes()
        hashes[name] = hashlib.sha256(content).hexdigest()
    require(bool(hashes), "runtime source tree is empty")
    return digest(hashes)


def manifest_provenance(data):
    return {"manifest_version": data["schema_version"], "manifest_sha256": digest(data),
            "manual_revision": MANUAL_REVISION}


def check_provenance(report, data, keys):
    require(report.get("schema_version") == REPORT_VERSION, "invalid evidence schema")
    provenance = report.get("provenance")
    common = manifest_provenance(data)
    require(has_keys(provenance, " ".join([*common, *keys])),
            "missing or invalid evidence provenance")
    require(all(provenance[k] == v for k, v in common.items()), "stale manifest or manual provenance")
    return provenance


def validate_manual(report, data, *, historical):
    require(has_keys(report, "schema_version provenance summary chapters features results"),
            "invalid manual result record")
    provenance = check_provenance(report, data, (
        "runtime_revision", "runtime_sha256", "runner_revision", "runner_sha256", "toolchain",
        "worker_version",
    ))
    require(has_keys(provenance["toolchain"], "racket python")
            and matches(r"Welcome to Racket v[0-9.]+.*", provenance["toolchain"]["racket"])
            and matches(r"[0-9]+(?:\.[0-9]+)+", provenance["toolchain"]["python"])
            and all(matches(r"[0-9a-f]{64}", provenance[k]) for k in ("runtime_sha256", "runner_sha256"))
            and type(provenance["worker_version"]) is int and provenance["worker_version"] == 1,
            "invalid runtime or toolchain provenance")
    revision = provenance["runtime_revision"]
    if revision is not None or historical:
        require(matches(r"[0-9a-f]{40}", revision), "missing full runtime revision")
        require(runtime_digest(revision) == provenance["runtime_sha256"], "inconsistent runtime digest")
    runner = provenance["runner_revision"]
    if runner is not None or historical:
        require(matches(r"[0-9a-f]{40}", runner), "missing full runner revision")
        require(runner_digest(runner) == provenance["runner_sha256"], "inconsistent runner digest")
    if not historical:
        require(runtime_digest() == provenance["runtime_sha256"] and
                runner_digest() == provenance["runner_sha256"], "stale runtime or runner provenance")

    cases = {case["id"]: case for case in data["cases"]}
    seen = set()
    chapters, features = {}, {}
    require(isinstance(report["results"], list), "invalid results")
    for row in report["results"]:
        require(has_keys(row, "id fixture_sha256 mode status expected actual"), "invalid result row")
        key = (row["id"], row["mode"])
        require(nonempty(key[0]) and key[0] in cases and key[1] in MODES and key not in seen,
                f"unknown or duplicate fixture/mode: {key}")
        seen.add(key)
        case = cases[row["id"]]
        require(row["fixture_sha256"] == digest(case), f"{key}: stale fixture digest")
        require(digest(row["expected"]) == digest(expected_for(case, row["mode"])),
                f"{key}: stale expectation")
        require(row["status"] in STATUSES, f"{key}: invalid classification")
        actual = row["actual"]
        if has_keys(actual, "harness_error"):
            error = actual["harness_error"]
            require(has_keys(error, "kind message") and error["kind"] in (
                "timeout", "process", "worker-protocol",
            ) and nonempty(error["message"]), f"{key}: malformed process failure")
        else:
            validate_observation(actual, row["mode"])
        require(row["status"] == classify(case, row["mode"], actual), f"{key}: inconsistent classification")
        chapters.setdefault(str(case["chapter"]), Counter())[row["status"]] += 1
        features.setdefault(case["feature"], Counter())[row["status"]] += 1
    require(seen == {(name, mode) for name in cases for mode in MODES}, "missing fixture/mode results")
    require(digest((report["summary"], report["chapters"], report["features"])) == digest((
        Counter(row["status"] for row in report["results"]), chapters, features,
    )), "invalid result totals")
    if historical:
        require(not any(row["status"] in {"FAIL", "XPASS"} for row in report["results"]),
                "historical verification snapshot contains an unsuccessful check")
    return report


def runner_digest(revision=None):
    if revision and len(git("ls-tree", "-r", "--name-only", revision, "--",
                            *RUNNER_FILES).splitlines()) != len(RUNNER_FILES):
        return None
    return digest({
        name: hashlib.sha256(git("show", f"{revision}:{name}") if revision else
                             (ROOT / name).read_bytes()).hexdigest()
        for name in RUNNER_FILES
    })


def native_input(case):
    forms = [*case["setup"], case["expression"]]
    if "effect_expression" in case:
        forms.append(case["effect_expression"])
    return "\n".join(forms).rstrip("\n") + "\n<QUIT>\n"


def validate_native(report, agreement, data):
    require(has_keys(report, "schema_version provenance protocol observations")
            and nonempty(report["protocol"]), "invalid native evidence schema")
    provenance = check_provenance(report, data, ("reference_revision", "exe_sha256", "toolchain"))
    locked = read_json(ROOT / "sources.lock.json")["sources"]["mdlzork"]["commit"]
    require(provenance["reference_revision"] == locked
            and matches(r"[0-9a-f]{64}", provenance["exe_sha256"])
            and has_keys(provenance["toolchain"], "python machine")
            and all(nonempty(v) for v in provenance["toolchain"].values()), "invalid native provenance")
    cases = {case["id"]: case for case in data["cases"]}
    observations = {}
    require(isinstance(report["observations"], list), "invalid native observations")
    for row in report["observations"]:
        require(has_keys(row, "id fixture_sha256 input result_output stderr exit_code ok"),
                "invalid native observation")
        name = row["id"]
        require(nonempty(name) and name in cases and name not in observations,
                f"unknown or duplicate native fixture {name!r}")
        case = cases[name]
        require(row["fixture_sha256"] == digest(case) and row["input"] == native_input(case),
                f"{name}: stale native fixture")
        require(isinstance(row["stderr"], str) and (row["result_output"] is None or
                isinstance(row["result_output"], str)) and (row["exit_code"] is None or
                type(row["exit_code"]) is int) and type(row["ok"]) is bool and row["ok"] == (
                    row["exit_code"] == 0 and not row["stderr"] and row["result_output"] is not None
                ), f"{name}: inconsistent native outcome")
        observations[name] = row
    require(observations.keys() == cases.keys(), "missing native fixtures")
    require(has_keys(agreement, "schema_version provenance agreements"),
            "invalid native agreement record")
    reviewed = check_provenance(agreement, data, ("reference_revision", "exe_sha256", "toolchain"))
    require(reviewed == provenance and isinstance(agreement["agreements"], dict), "stale native agreement provenance")
    for name, row_digest in agreement["agreements"].items():
        require(name in observations and observations[name]["ok"]
                and row_digest == digest(observations[name]), f"{name}: stale native agreement")
    return observations
