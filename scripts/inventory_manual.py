#!/usr/bin/env python3
"""Build the L0 manual and implementation inventory from pinned inputs."""

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MANUAL = "https://mdl-language.readthedocs.io/en/latest/"
MANUAL_COMMIT = "89707367b951ea79bedc71f51ab213886e0f62ce"
SOURCE_BASE = f"https://github.com/taradinoc/mdl-docs/blob/{MANUAL_COMMIT}/docs/"
OUTPUT = ROOT / "docs/conformance"
SOURCE_FILES = (
    "mdl/parser.rkt", "mdl/compiler.rkt", "mdl/runtime/core.rkt",
    "mdl/loader.rkt", "mdl/lang/reader.rkt",
)
KNOWN = {
    "SET": [121], "SETG": [121], "GVAL": [121], "LVAL": [121, 134],
    "TYPE": [129], "CHTYPE": [129], "NEWTYPE": [129],
    "STRING": [127], "%": [126], "ILIST": [120], "IVECTOR": [120],
    "IUVECTOR": [120], "ISTRING": [120],
}
DECISIONS = {
    "OPEN": "ADR-0055: virtual no-file policy",
    "SAVE": "ADR-0048: session-owned record",
    "REP": "ADR-0049: inert default binding",
    "UNWIND": "ADR-0051: cleanup only for MDL transfers",
    "RANDOM": "ADR-0045: session-owned 36-bit RNG",
    "MAX": "ADR-0059: zero-argument result",
}
TRACKED = {"PRINT": [173], "PUTPROP": [179], "GETPROP": [179]}


def relative(path):
    return path.relative_to(ROOT).as_posix()


def page_sections(path, lines):
    sections = []
    for number, line in enumerate(lines, 1):
        match = re.fullmatch(r"(#{1,6})\s+(.+)", line)
        if not match:
            continue
        title = match[2].replace("`", "")
        sections.append({
            "title": title, "line": number,
            "source": f"{SOURCE_BASE}{path.name}#L{number}",
        })
    return sections


def normalized_form(source):
    return "\n".join(line.strip() for line in source.splitlines())


def manual_pages(docs, fixtures, outcomes, agreements):
    pages = []
    for path in sorted(docs.glob("*.md")):
        content = path.read_bytes()
        lines = content.decode("utf-8").splitlines()
        sections = page_sections(path, lines)
        chapter = path.stem.split("-", maxsplit=1)[0]
        examples = [f for f in fixtures if f"{f['chapter']:02}" == chapter]
        prompt_lines = []
        for number, line in enumerate(lines, 1):
            if not re.match(r"^(?: {4}|\t)\S", line) or not re.search(r"(?<![!\\])\$\s*$", line):
                continue
            row = {"line": number, "source": f"{SOURCE_BASE}{path.name}#L{number}",
                   "status": "NOT_TESTED"}
            for fixture in examples:
                if fixture["origin"] != "manual":
                    continue
                program = fixture["expression"]
                start = number - len(program.splitlines())
                if normalized_form("\n".join(lines[max(start, 0):number]).rstrip()[:-1]) != normalized_form(program):
                    continue
                name = fixture["id"]
                row["fixture"] = name
                result = outcomes.get(name, {})
                if set(result) != {"loader", "lang"}:
                    break
                if set(result.values()) == {"XFAIL"}:
                    row["status"] = "UNSUPPORTED"
                elif set(result.values()) == {"PASS"}:
                    if fixture.get("manual_expected"):
                        row["status"] = "ACCEPTED_DEVIATION"
                    else:
                        row["status"] = "VERIFIED" if name in agreements else "PARTIAL"
                break
            prompt_lines.append(row)
        pages.append({
            "page": path.stem, "url": MANUAL if path.stem == "index" else f"{MANUAL}{path.stem}/",
            "source": f"{SOURCE_BASE}{path.name}", "sha256": hashlib.sha256(content).hexdigest(),
            "sections": sections, "transcript_prompt_lines": prompt_lines,
            "manual_cases": [f["id"] for f in examples],
        })
    return pages


def appendix_entries(docs):
    entries = {}
    subr = docs / "appendix-2-predefined-subroutines.md"
    blocks = re.findall(r"^```\n(.*?)^```$", subr.read_text(), re.M | re.S)
    for block in blocks:
        signature, *declarations = re.split(r"\n\s*(?=#DECL\b)", block, maxsplit=1)
        name, syntax = signature.strip().split(maxsplit=1)
        entries.setdefault(name, {})["subroutine"] = {
            "syntax": " ".join(syntax.split()),
            "argument_and_return_declaration": declarations[0].strip() if declarations else None,
        }
    types = docs / "appendix-3-predefined-types.md"
    for line in types.read_text().splitlines():
        if not line.startswith("| `") or line.startswith("| `TYPE`"):
            continue
        name, primtype, structured, evaluated, applicable, reader, _ = (
            cell.strip().replace("`", "") for cell in line[1:-1].split("|")
        )
        entries.setdefault(name, {})["predefined_type"] = {
            "primtype": primtype or name,
            "structured": structured == "S",
            "evaluated": evaluated == "E",
            "applicable": applicable == "A",
            "reader_flags": reader,
        }
    errors = docs / "appendix-4-error-messages.md"
    for number, line in enumerate(errors.read_text().splitlines(), 1):
        match = re.match(r"\| `(.+?)`\s*\|", line)
        if match:
            entries.setdefault(match[1], {})["error_atom"] = f"{SOURCE_BASE}{errors.name}#L{number}"
    name_index = docs / "appendix-8-name-index.md"
    for line in name_index.read_text().splitlines():
        match = re.match(r"\| `(.+?)`\s*\|(.*)", line)
        if not match:
            continue
        entries.setdefault(match[1], {})["sections"] = [
            {"section": label, "url": f"{MANUAL}{page}/#{anchor}"}
            for label, page, anchor in re.findall(r"\[([^\]]+)\]\(([^)]+)\.md#([^)]*)\)", match[2])
        ]
    return entries


def implementation_maps():
    sources = {name: (ROOT / name).read_text().splitlines() for name in SOURCE_FILES}
    implementations = defaultdict(list)

    def add(name, file, number, kind):
        implementations[name].append({"file": file, "line": number, "kind": kind})

    core = SOURCE_FILES[2]
    in_registry = False
    for number, line in enumerate(sources[core], 1):
        if line.startswith("(define "):
            in_registry = line == "(define builtin-table"
        if in_registry and (match := re.match(r'^\s*(?:\(hash )?"([^"]+)" ', line)):
            add(match[1], core, number, "runtime operator binding")
        if "seed-root!" not in line and number in range(1800, 1910):
            for match in re.finditer(r'\("([^"]+)" \. "[^"]+"\)', line):
                add(match[1], core, number, "runtime type registration")
    compiler = SOURCE_FILES[1]
    in_forms = False
    for number, line in enumerate(sources[compiler], 1):
        if line.startswith("(define "):
            in_forms = line.startswith("(define (compile-form n ")
        if in_forms and (match := re.match(r"\s*\[\(([A-Z][A-Z0-9?! -]*)\)", line)):
            for name in match[1].split():
                add(name, compiler, number, "compiler special form")
    loader = SOURCE_FILES[3]
    for number, line in enumerate(sources[loader], 1):
        match = re.search(r'mdl-define-subr! \(mdl-root-atom "([^"]+)"\)', line)
        if match:
            add(match[1], loader, number, "loader-only operator binding")
    return implementations


def lexical_evidence(paths):
    hits = defaultdict(set)
    for path in paths:
        content = path.read_text(errors="replace")
        for name in re.findall(r"<\s*([A-Z0-9?+=!&*/_-]+)(?=[\s>])", content):
            hits[name].add(relative(path))
    return hits


def coverage(docs):
    fixtures = json.loads((ROOT / "tests/conformance/manifest.json").read_text())["cases"]
    implementations = implementation_maps()
    tests = lexical_evidence((ROOT / "tests").glob("*_test.rkt"))
    native = lexical_evidence(sorted((ROOT / "docs/evidence").rglob("*.json")))
    semantics = json.loads((OUTPUT / "semantics.json").read_text(encoding="utf-8"))
    native_report = ROOT / "docs/evidence/L0/native-examples.json"
    records = json.loads(native_report.read_text())["observations"]
    observations = {item["name"]: item["ok"] for item in records}
    reviewed = json.loads(native_report.with_name("native-agreement.json").read_text())["agreements"]
    agreements = {
        row["name"] for row in records
        if row["ok"] and reviewed.get(row["name"]) == {
            "input": row["input"], "result_output": row["result_output"]
        }
    }
    manual_report = ROOT / "docs/evidence/L0/manual-summary.json"
    outcomes = defaultdict(dict)
    for row in json.loads(manual_report.read_text())["results"]:
        outcomes[row["id"]][row["mode"]] = row["status"]
    sweep = json.loads((ROOT / "docs/evidence/M4/operator-head-sweep.json").read_text())
    reachable = set(sweep["builtin_used"]) | {row["name"] for row in sweep["missing"]}
    entries = []
    for name, entry in sorted(appendix_entries(docs).items()):
        candidates = implementations.get(name, [])
        fixture_matches = [f["id"] for f in fixtures if name in f["feature"].split("/")]
        status = "NOT_TESTED"
        if name in KNOWN:
            status = "KNOWN_DEFECT"
        elif name in {"OPEN", "SAVE", "REP"}:
            status = "ACCEPTED_DEVIATION"
        elif candidates:
            status = "PARTIAL"
        elif name in TRACKED or any(f.get("gaps") and f["feature"] == name for f in fixtures):
            status = "UNSUPPORTED"
        case_info = [f for f in fixtures if f["id"] in fixture_matches]
        entries.append({
            "name": name, **entry, "status": status,
            "required_evaluation_semantics": None,
            "identity_and_mutation": None, "error_behavior": None,
            "implementation_candidates": candidates,
            "test_mentions": sorted(tests[name]),
            "native_mentions": sorted(native[name]),
            "manual_cases": fixture_matches,
            "fixture_reference": [
                {"case": f["id"], "source": f["source"],
                 "native_capture_completed": observations.get(f["id"]),
                 "runtime_results": dict(outcomes[f["id"]])}
                for f in case_info
            ],
            "issues": KNOWN.get(name, TRACKED.get(name, [])),
            "deviation": DECISIONS.get(name),
            "missing_functionality": "operator or reader facility" if status == "UNSUPPORTED" else None,
            "dependencies": None,
            "zork_reachability": "static operator mention" if name in reachable else None,
            **semantics.get(name, {}),
        })
    pages = manual_pages(docs, fixtures, outcomes, agreements)
    return {"schema_version": 1, "manual_commit": MANUAL_COMMIT, "pages": pages,
            "entries": entries}


def matrix(data):
    counts = Counter(row["status"] for row in data["entries"])
    lines = [
        "# MDL coverage inventory", "",
        f"Manual transcription commit `{MANUAL_COMMIT}`.",
        "The [JSON inventory](coverage.json) contains the complete source index.",
        "", "| Classification | Construct count |", "| --- | ---: |",
    ]
    for status in ("VERIFIED", "PARTIAL", "KNOWN_DEFECT", "UNSUPPORTED",
                   "ACCEPTED_DEVIATION", "PLATFORM_EXCLUSION", "NOT_TESTED"):
        lines.append(f"| `{status}` | {counts[status]} |")
    lines += ["", "| Manual page | Sections | Transcript prompt candidates | Executable fixtures |",
              "| --- | ---: | ---: | ---: |"]
    for page in data["pages"]:
        lines.append(f"| [{page['page']}]({page['url']}) | {len(page['sections'])} | "
                     f"{len(page['transcript_prompt_lines'])} | {len(page['manual_cases'])} |")
    lines += ["", "| Construct | Status | Runtime candidates | Fixture IDs |",
              "| --- | --- | --- | --- |"]
    for row in data["entries"]:
        name = row["name"].replace("|", "&#124;").replace("`", "&#96;")
        links = ", ".join(f"[{p['file']}:{p['line']}](../../{p['file']}#L{p['line']})"
                          for p in row["implementation_candidates"])
        cases = ", ".join(row["manual_cases"])
        lines.append(f"| `{name}` | {row['status']} | {links} | {cases} |")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manual_checkout", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    actual = subprocess.check_output(
        ["git", "-C", str(args.manual_checkout), "rev-parse", "HEAD"], text=True
    ).strip()
    if actual != MANUAL_COMMIT:
        parser.error(f"expected manual {MANUAL_COMMIT}, got {actual}")
    if subprocess.check_output(["git", "-C", str(args.manual_checkout), "status",
                                "--porcelain", "--untracked-files=no"], text=True).strip():
        parser.error("manual checkout has modified tracked files")
    data = coverage(args.manual_checkout / "docs")
    outputs = {"coverage.json": json.dumps(data, indent=2) + "\n",
               "MDL-COVERAGE.md": matrix(data)}
    for name, content in outputs.items():
        target = OUTPUT / name
        if args.check:
            if target.read_text() != content:
                parser.error(f"{relative(target)} needs regeneration")
        else:
            target.write_text(content)


if __name__ == "__main__":
    main()
