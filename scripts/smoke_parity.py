#!/usr/bin/env python3
"""M3 SMOKE_PARITY: the single transcript comparator (S10; ADR-0053).

Every SMOKE_PARITY comparison goes through compare_records(): the reference
records captured from pinned Confusion (scripts/boot_reference.py, schema 2
or 3) and the candidate record of this runtime (scripts/m3_house_boot_run.rkt
run through candidate_record()). There is no second comparator.

Allowed presentation differences (and nothing else):

* D1 (ADR-0050 part 5): the reference boot_output contains Confusion's LISTEN
  banner line ``LISTENING-AT-LEVEL 1 PROCESS 1`` and FLOAD's ``"DONE"`` value
  line, which the host loop never prints. Each must occur exactly once in a
  reference boot_output and is removed exactly once. The REP print of
  ``,NULL`` (the blank line after the date line) is KEPT on both sides.
* D2 (ADR-0050, S7 golden-compare.txt): the reference text is
  ``canonical_text`` of PTY output, whose line discipline applies ONLCR; the
  candidate's raw output gets the same treatment, ``canonical_text(ONLCR(raw))``.

No date substitution, no alternative "west" text, no whitespace folding.
Scenario, clock, zone, entry, command order, boot text, every response, the
date line and the score line (points and moves) must match exactly.

Termination (D3, ADR-0050 part 4): the candidate run must end by input
exhaustion: after the last command, exactly one mirrored empty read
(``Beg pardon?`` and ``>``), then ``exn:fail:mdl-input-exhausted`` with the
exact D3 message, all input consumed. That is reported as input exhaustion,
not as a user QUIT. The reference PTY capture stops at the last prompt, so
the D3 tail is checked against its exact expectation, not against the
reference (Confusion's pipe run shows the same tail before ``Error:
Unexpected EOF``; evidence/M3/S7-frontier/golden-compare.txt).

Usage:
  smoke_parity.py run --scenario S --output CAND.json [--raw-output RUN.json]
  smoke_parity.py candidate RUN.json --output CAND.json
  smoke_parity.py compare EXPECTED.json ACTUAL.json [--report R.json]
  smoke_parity.py native --scenario S --reference REF.json --candidate CAND.json
                         --output-dir DIR
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import boot_reference as br  # noqa: E402

CANDIDATE_SCHEMA_VERSION = 1
CANDIDATE_ENGINE = "mdl-racket-host-loop"
REFERENCE_ENGINES = ("confusion-patched-1977-boot",)
RUNNER = ROOT / "scripts/m3_house_boot_run.rkt"

# D1: lines the reference prints and the host loop never does.
D1_LISTEN_LINE = "LISTENING-AT-LEVEL 1 PROCESS 1\n"
D1_DONE_LINE = '"DONE"\n'
# D3: the documented end of the candidate run.
D3_KIND = "input-exhausted"
D3_MESSAGE = ("READSTRING: input exhausted: the session input ended and the "
              "mirrored end-of-input read was already returned "
              "(maintainer decision D3; ADR-0050)")
D3_TAIL = ["Beg pardon?\n", ""]
# Same prompt rule as the reference capture (RDCOM's '>' at line start).
PROMPT = br.PROMPT
DATE_LINE = re.compile(r"(?m)^This version created [^\n]*$")
SCORE_LINE = re.compile(
    r"Your score would be (-?\d+) \[total of (\d+) points\], in (\d+) moves?\.")
LOAD_EXPECTED = {"status": "PASS", "completed_expressions": 1229,
                 "skipped_expressions": 0}


class ParityError(RuntimeError):
    """A record that cannot be compared at all (malformed input)."""


# ---------------------------------------------------------------------------
# Normalisation (D1, D2) — the only allowed presentation differences
# ---------------------------------------------------------------------------

def onlcr(text: str) -> str:
    """Emulate the PTY output line discipline (ONLCR): LF -> CR LF."""
    return text.replace("\n", "\r\n")


def d2(raw: str) -> str:
    """D2: canonical_text(ONLCR(raw)), the reference capture's own rule."""
    return br.canonical_text(onlcr(raw))


def d1_strip(boot_output: str) -> tuple[str, list[str]]:
    """Remove the two D1 lines from a reference boot_output, exactly once each."""
    problems = []
    text = boot_output
    if not text.startswith(D1_LISTEN_LINE):
        problems.append(f"reference boot_output does not start with {D1_LISTEN_LINE!r} (D1)")
    for line in (D1_LISTEN_LINE, D1_DONE_LINE):
        n = len(re.findall(r"(?m)^" + re.escape(line), text))
        if n != 1:
            problems.append(f"reference boot_output has {n} occurrences of the D1 line "
                            f"{line!r}; exactly 1 required")
        else:
            text = re.sub(r"(?m)^" + re.escape(line), "", text, count=1)
    return text, problems


# ---------------------------------------------------------------------------
# Candidate record (this runtime) from the raw run facts
# ---------------------------------------------------------------------------

def segment(raw: str, inputs: list[str]) -> dict[str, Any]:
    """D2-normalise the raw output and split it at RDCOM prompts."""
    parts = PROMPT.split(d2(raw))
    outs = parts[1:]
    commands = []
    for i, cmd in enumerate(inputs):
        if i >= len(outs):
            break
        commands.append({"input": cmd, "output": outs[i],
                         "prompt_returned": i < len(outs) - 1})
    return {"boot_output": parts[0], "commands": commands,
            "tail": outs[len(inputs):]}


def candidate_record(run: dict[str, Any]) -> dict[str, Any]:
    """Build the comparable candidate record from m3_house_boot_run.rkt output.

    The raw run facts are kept verbatim under "run"; validate() re-derives
    every compared field from them, so an edited record cannot pass.
    """
    inputs = list(run["command_inputs"])
    seg = segment(run["raw_output"], inputs)
    answered = len(seg["commands"]) == len(inputs)
    return {
        "schema_version": CANDIDATE_SCHEMA_VERSION,
        "engine": CANDIDATE_ENGINE,
        "scenario": run["scenario"],
        "fixed_epoch": run["fixed_epoch"],
        "tz": run["tz"],
        "entry": run["entry"],
        "boot_output": seg["boot_output"],
        "commands": seg["commands"],
        "complete": answered and all(c["prompt_returned"] for c in seg["commands"]),
        "termination": {
            "protocol": "ADR-0050 D3 input exhaustion (not a user QUIT)",
            "kind": run["outcome"]["kind"],
            "message": run["outcome"]["message"],
            "tail": seg["tail"],
        },
        "normalisation": "D2: canonical_text(ONLCR(raw_output)); no other change",
        "run": run,
    }


# ---------------------------------------------------------------------------
# Validation of one record
# ---------------------------------------------------------------------------

def record_kind(record: dict[str, Any]) -> str:
    engine = record.get("engine")
    if engine in REFERENCE_ENGINES:
        return "reference"
    if engine == CANDIDATE_ENGINE:
        return "candidate"
    raise ParityError(f"unknown record engine {engine!r}")


def _texts(record: dict[str, Any]) -> list[str]:
    return [record.get("boot_output") or ""] + [
        c.get("output") or "" for c in record.get("commands") or []]


def validate(record: dict[str, Any]) -> list[str]:
    """Problems that make a record unfit for a PASS, independent of the other side."""
    kind = record_kind(record)
    problems: list[str] = []
    if any(not isinstance(t, str) for t in _texts(record)):
        problems.append("non-string transcript text")
        return problems
    if any("\r" in t or "\x1b" in t for t in _texts(record)):
        problems.append("CR or ESC left in compared text (D2 not applied)")
    if kind == "reference":
        if record.get("schema_version") not in br.COMPARABLE_SCHEMA_VERSIONS:
            problems.append(f"reference schema_version {record.get('schema_version')!r} "
                            f"not in {br.COMPARABLE_SCHEMA_VERSIONS}")
        if record.get("complete") is not True or record.get("error") is not None:
            problems.append(f"reference capture incomplete: complete="
                            f"{record.get('complete')!r} error={record.get('error')!r}")
        if not all(c.get("prompt_returned") for c in record.get("commands") or []):
            problems.append("reference: a command did not return to the prompt")
        problems.extend(d1_strip(record.get("boot_output") or "")[1])
        return problems

    # Candidate: every compared field must be re-derivable from the raw run.
    run = record.get("run")
    if not isinstance(run, dict) or not isinstance(run.get("raw_output"), str):
        return problems + ["candidate record has no raw run facts"]
    if "\x1b" in run["raw_output"]:
        problems.append("candidate raw output contains ESC")
    derived = candidate_record(run)
    for key in br.STRICT_FIELDS + ("termination",):
        if record.get(key) != derived[key]:
            problems.append(f"candidate field {key!r} differs from its raw run (edited record)")
    term = derived["termination"]
    if term["kind"] != D3_KIND:
        problems.append(f"candidate run ended by {term['kind']!r} ({term['message']}), "
                        f"not by D3 input exhaustion")
    elif term["message"] != D3_MESSAGE:
        problems.append(f"candidate D3 message differs: {term['message']!r}")
    if term["tail"] != D3_TAIL:
        problems.append(f"candidate output after the last command is {term['tail']!r}, "
                        f"expected exactly the D3 tail {D3_TAIL!r}")
    if not derived["complete"]:
        problems.append(f"candidate answered {len(derived['commands'])} of "
                        f"{len(run['command_inputs'])} commands with a prompt (incomplete run)")
    if run.get("input_remaining") != "":
        problems.append(f"candidate input not fully consumed: {run.get('input_remaining')!r}")
    load = run.get("load") or {}
    for key, value in LOAD_EXPECTED.items():
        if load.get(key) != value:
            problems.append(f"candidate load {key}={load.get(key)!r}, expected {value!r}")
    if run.get("source_listing_unchanged") is not True:
        problems.append("candidate run changed the game directory listing")
    if run.get("events") != ["entry-returned", "pass"]:
        problems.append(f"candidate host-loop events {run.get('events')!r}, "
                        "expected ['entry-returned', 'pass']")
    scores = [SCORE_LINE.search(c["output"]) for c in derived["commands"]]
    scores = [m for m in scores if m]
    if scores and run.get("moves") != int(scores[-1].group(3)):
        problems.append(f"candidate MOVES global {run.get('moves')!r} differs from the "
                        f"score line's {scores[-1].group(3)} moves")
    return problems


# ---------------------------------------------------------------------------
# The comparator
# ---------------------------------------------------------------------------

def first_difference(expected: str, actual: str) -> dict[str, Any]:
    """Exact location of the first differing character, with context."""
    n = min(len(expected), len(actual))
    i = next((k for k in range(n) if expected[k] != actual[k]), n)
    lo = max(0, i - 20)
    return {"offset": i,
            "expected_len": len(expected), "actual_len": len(actual),
            "expected_bytes": expected[lo:i + 20].encode("utf-8").hex(" "),
            "actual_bytes": actual[lo:i + 20].encode("utf-8").hex(" "),
            "expected_context": expected[lo:i + 20],
            "actual_context": actual[lo:i + 20]}


def presentation_view(record: dict[str, Any]) -> dict[str, Any]:
    """The compared view of one record: D1 applied to references only."""
    boot = record.get("boot_output") or ""
    if record_kind(record) == "reference":
        boot = d1_strip(boot)[0]
    return {
        "scenario": record.get("scenario"),
        "fixed_epoch": record.get("fixed_epoch"),
        "tz": record.get("tz"),
        "entry": record.get("entry"),
        "boot_output": boot,
        "inputs": [c.get("input") for c in record.get("commands") or []],
        "outputs": [c.get("output") for c in record.get("commands") or []],
        "complete": record.get("complete"),
    }


def compare_records(expected: dict[str, Any], actual: dict[str, Any]) -> list[dict[str, Any]]:
    """All mismatches between two records; an empty list is a strict PASS."""
    mismatches: list[dict[str, Any]] = []

    def add(check: str, exp: Any = None, act: Any = None, detail: str | None = None) -> None:
        item: dict[str, Any] = {"check": check}
        if detail is not None:
            item["detail"] = detail
        if exp is not None or act is not None:
            item["expected"], item["actual"] = exp, act
            if isinstance(exp, str) and isinstance(act, str):
                item["first_difference"] = first_difference(exp, act)
        mismatches.append(item)

    for side, record in (("expected", expected), ("actual", actual)):
        for problem in validate(record):
            add(f"{side}-record", detail=problem)

    ve, va = presentation_view(expected), presentation_view(actual)
    for key in ("scenario", "fixed_epoch", "tz", "entry"):
        if ve[key] != va[key]:
            add(key, ve[key], va[key])
    if ve["inputs"] != va["inputs"]:
        add("command_inputs", ve["inputs"], va["inputs"],
            "command order, missing or extra command")
    if ve["boot_output"] != va["boot_output"]:
        add("boot_output", ve["boot_output"], va["boot_output"])
    dates_e = DATE_LINE.findall(ve["boot_output"])
    dates_a = DATE_LINE.findall(va["boot_output"])
    if len(dates_e) != 1 or dates_e != dates_a:
        add("date_line", dates_e, dates_a, "exactly one identical date line required")
    for i in range(max(len(ve["outputs"]), len(va["outputs"]))):
        exp = ve["outputs"][i] if i < len(ve["outputs"]) else None
        act = va["outputs"][i] if i < len(va["outputs"]) else None
        if exp != act:
            name = (ve["inputs"][i] if i < len(ve["inputs"])
                    else va["inputs"][i] if i < len(va["inputs"]) else None)
            add(f"command[{i}] {name!r}", exp, act)
    score_e = [m.groups() for o in ve["outputs"] if o for m in [SCORE_LINE.search(o)] if m]
    score_a = [m.groups() for o in va["outputs"] if o for m in [SCORE_LINE.search(o)] if m]
    if not score_e or score_e != score_a:
        add("score_line", score_e, score_a,
            "(points, total, moves) from every score response must be identical")
    elif int(score_e[-1][2]) != len(ve["inputs"]):
        add("score_moves", score_e[-1][2], len(ve["inputs"]),
            "final move count must equal the number of commands")
    if ve["complete"] is not True or va["complete"] is not True:
        add("complete", ve["complete"], va["complete"])
    return mismatches


def report(expected_label: str, actual_label: str,
           mismatches: list[dict[str, Any]]) -> dict[str, Any]:
    return {"comparator": "scripts/smoke_parity.py compare_records (ADR-0053)",
            "expected": expected_label, "actual": actual_label,
            "allowed_differences": ["D1 (reference LISTEN banner and \"DONE\" lines; "
                                    "REP print of ,NULL kept)",
                                    "D2 (canonical_text(ONLCR(raw)))"],
            "result": "PASS" if not mismatches else "FAIL",
            "mismatches": mismatches}


def load(path: Path) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def describe(mismatches: list[dict[str, Any]]) -> str:
    lines = []
    for m in mismatches:
        line = f"  - {m['check']}"
        if "detail" in m:
            line += f": {m['detail']}"
        if "first_difference" in m:
            fd = m["first_difference"]
            line += (f" at offset {fd['offset']}: expected {fd['expected_context']!r} "
                     f"[{fd['expected_bytes']}] actual {fd['actual_context']!r} "
                     f"[{fd['actual_bytes']}]")
        elif "expected" in m:
            line += f": expected {m['expected']!r} actual {m['actual']!r}"
        lines.append(line)
    return "\n".join(lines)


def compare_files(expected: Path, actual: Path, report_path: Path | None = None) -> int:
    mismatches = compare_records(load(expected), load(actual))
    if report_path:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report(str(expected), str(actual), mismatches),
                                          ensure_ascii=False, indent=2) + "\n",
                               encoding="utf-8")
    if mismatches:
        print(f"SMOKE PARITY MISMATCH: {expected} vs {actual}\n{describe(mismatches)}",
              file=sys.stderr)
        return 1
    print(f"SMOKE PARITY strict PASS (D1, D2 only): {expected} == {actual}")
    return 0


# ---------------------------------------------------------------------------
# Producing records
# ---------------------------------------------------------------------------

def run_candidate(scenario: Path, raw_output: Path, racket: str = "racket",
                  timeout: float = 600) -> dict[str, Any]:
    """Run this runtime on the scenario (scripts/m3_house_boot_run.rkt)."""
    raw_output.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run([racket, str(RUNNER), str(scenario), str(raw_output)],
                            cwd=str(ROOT), capture_output=True, text=True,
                            timeout=timeout)
    if result.returncode != 0:
        raise ParityError(f"candidate runner exit {result.returncode}:\n{result.stderr}")
    return load(raw_output)


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def native(args: argparse.Namespace) -> int:
    """Fresh native capture (disposable copy) compared with the committed
    reference and with this runtime's candidate record."""
    if not br.EXE.is_file():
        print(f"NOT RUN: native interpreter missing ({br.repo_relative(br.EXE)})",
              file=sys.stderr)
        return 3
    if shutil.which("gcc") is None:
        print("NOT RUN: gcc missing (clock shim)", file=sys.stderr)
        return 3
    scenario = load(args.scenario)
    fresh = br.capture_boot(scenario, scenario["fixed_epoch"], args.timeout,
                            scenario_path=args.scenario)
    out = args.output_dir
    write_json(out / "house-boot-fresh-reference.json", fresh)
    status = 0
    for exp, act, label in ((args.reference, out / "house-boot-fresh-reference.json",
                             "fresh-vs-committed-reference"),
                            (out / "house-boot-fresh-reference.json", args.candidate,
                             "candidate-vs-fresh-reference")):
        rc = compare_files(exp, act, out / f"{label}.json")
        status = status or rc
    return status


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="action", required=True)
    p = sub.add_parser("run", help="run this runtime and write its candidate record")
    p.add_argument("--scenario", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--raw-output", type=Path, default=None)
    p.add_argument("--racket", default=os.environ.get("RACKET", "racket"))
    p = sub.add_parser("candidate", help="candidate record from saved raw run facts")
    p.add_argument("run", type=Path)
    p.add_argument("--output", type=Path, required=True)
    p = sub.add_parser("compare", help="strict comparison of two records")
    p.add_argument("expected", type=Path)
    p.add_argument("actual", type=Path)
    p.add_argument("--report", type=Path, default=None)
    p = sub.add_parser("native", help="fresh native capture + comparisons")
    p.add_argument("--scenario", type=Path, required=True)
    p.add_argument("--reference", type=Path, required=True)
    p.add_argument("--candidate", type=Path, required=True)
    p.add_argument("--output-dir", type=Path, required=True)
    p.add_argument("--timeout", type=float, default=90)
    args = parser.parse_args()

    if args.action == "run":
        raw = args.raw_output or args.output.with_name(args.output.stem + "-run.json")
        record = candidate_record(run_candidate(args.scenario, raw, args.racket))
        write_json(args.output, record)
        term = record["termination"]
        print(f"candidate: {len(record['commands'])} commands answered; run ended by "
              f"{term['kind']} ({'D3 input exhaustion, not a QUIT' if term['kind'] == D3_KIND else term['message']}): {args.output}")
        return 0
    if args.action == "candidate":
        write_json(args.output, candidate_record(load(args.run)))
        return 0
    if args.action == "compare":
        return compare_files(args.expected, args.actual, args.report)
    return native(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ParityError, ValueError, RuntimeError, OSError, KeyError,
            json.JSONDecodeError, subprocess.TimeoutExpired) as exc:
        print(f"smoke_parity: {exc}", file=sys.stderr)
        raise SystemExit(1)
