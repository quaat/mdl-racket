#!/usr/bin/env python3
"""Build the L0 manual and implementation inventory from pinned inputs."""

import argparse
from collections import Counter, defaultdict
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile

if __package__:
    from . import conformance_evidence as evidence
else:
    import conformance_evidence as evidence

ROOT = Path(__file__).resolve().parents[1]
MANUAL = evidence.MANUAL_URL
MANUAL_COMMIT = evidence.MANUAL_REVISION
SOURCE_BASE = evidence.MANUAL_SOURCE
OUTPUT = ROOT / "docs/conformance"
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
TRACKED = {"PRINT": [173], "PUTPROP": [179], "GETPROP": [179],
           "SQRT": [182], "%%": [183], "EVAL": [184], "SETLOC": [185]}


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
            heading = next((item["source"] for item in reversed(sections)
                            if item["line"] <= number), None)
            for fixture in examples:
                if fixture["origin"] != "manual" or fixture["source"] != heading:
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


def implementation_maps(root, racket):
    return evidence.parse_json(subprocess.check_output(
        [racket, str(ROOT / "scripts/conformance_discovery.rkt"), str(root)], text=True,
    ))


def snapshot(checkout, revision, destination, *paths):
    # Scan committed blobs only. A modified or untracked worktree file cannot
    # become a manual page or implementation candidate.
    archive = evidence.git("archive", "--format=tar", revision, "--", *paths, root=checkout)
    with tarfile.open(fileobj=io.BytesIO(archive)) as source:
        source.extractall(destination, filter="data")


def lexical_evidence(root, paths):
    hits = defaultdict(set)
    for path in paths:
        content = path.read_text(errors="replace")
        for name in re.findall(r"<\s*([A-Z0-9?+=!&*/_-]+)(?=[\s>])", content):
            hits[name].add(path.relative_to(root).as_posix())
    return hits


def coverage(docs, runtime_root, data, manual_report, native_report, native, agreement, racket):
    fixtures = data["cases"]
    implementations = implementation_maps(runtime_root, racket)
    tests = lexical_evidence(runtime_root, (runtime_root / "tests").glob("*_test.rkt"))
    native_mentions = lexical_evidence(runtime_root, (runtime_root / "docs/evidence").rglob("*.json"))
    semantics = evidence.read_json(OUTPUT / "semantics.json")
    outcomes = defaultdict(dict)
    for row in manual_report["results"]:
        outcomes[row["id"]][row["mode"]] = row["status"]
    sweep = evidence.read_json(runtime_root / "docs/evidence/M4/operator-head-sweep.json")
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
            "native_mentions": sorted(native_mentions[name]),
            "manual_cases": fixture_matches,
            "fixture_reference": [
                {"case": f["id"], "source": f["source"],
                 "native_capture_completed": native[f["id"]]["ok"],
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
    pages = manual_pages(docs, fixtures, outcomes, agreement["agreements"])
    return {
        "schema_version": 2, "manual_commit": MANUAL_COMMIT,
        "historical_runtime": manual_report["provenance"],
        "native_reference": native_report["provenance"],
        "pages": pages, "entries": entries,
    }


def matrix(data):
    counts = Counter(row["status"] for row in data["entries"])
    revision = data["historical_runtime"]["runtime_revision"]
    lines = [
        "# MDL coverage inventory", "",
        f"Manual transcription commit `{MANUAL_COMMIT}`.",
        f"Historical runtime snapshot `{revision}`.",
        "The [JSON inventory](coverage.json) contains source candidates and retained evidence.",
        "Current runtime regressions are checked separately by `make test-manual`.",
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
        github = f"https://github.com/quaat/mdl-racket/blob/{revision}/"
        links = ", ".join(f"[{p['file']}:{p['line']}]({github}{p['file']}#L{p['line']})"
                          for p in row["implementation_candidates"])
        cases = ", ".join(row["manual_cases"])
        lines.append(f"| `{name}` | {row['status']} | {links} | {cases} |")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manual_checkout", type=Path)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--racket", default="racket")
    args = parser.parse_args()
    try:
        if evidence.git("rev-parse", "HEAD", root=args.manual_checkout).decode().strip() != MANUAL_COMMIT:
            parser.error(f"expected manual checkout revision {MANUAL_COMMIT}")
        reports = ROOT / "docs/evidence/L0"
        data = evidence.load_manifest()
        manual = evidence.validate_manual(evidence.read_json(reports / "manual-summary.json"),
                                          data, historical=True)
        native_report = evidence.read_json(reports / "native-examples.json")
        agreement = evidence.read_json(reports / "native-agreement.json")
        native = evidence.validate_native(native_report, agreement, data)
        revision = manual["provenance"]["runtime_revision"]
        with tempfile.TemporaryDirectory(prefix="mdl-inventory-") as temp:
            manual_root = Path(temp) / "manual"
            runtime_root = Path(temp) / "runtime"
            manual_root.mkdir()
            runtime_root.mkdir()
            snapshot(args.manual_checkout, MANUAL_COMMIT, manual_root, "docs")
            evidence.validate_manifest(data, manual_root / "docs")
            snapshot(ROOT, revision, runtime_root, "mdl", "tests", "docs/evidence")
            data = coverage(manual_root / "docs", runtime_root, data, manual, native_report,
                            native, agreement, args.racket)
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        parser.error(str(exc))
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
