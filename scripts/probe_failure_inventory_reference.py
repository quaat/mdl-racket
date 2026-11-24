#!/usr/bin/env python3
"""Pinned-Confusion reference runs for the M4 gameplay failure inventory
(docs/evidence/M4/GAMEPLAY-FAILURE-INVENTORY.md).

Read-only reference investigation. Nothing here is runtime code, and the game
sources under .cache/upstream are never written: every run boots a fresh copy
of the game directory under $TMPDIR (protocol and helpers of
scripts/probe_session_reference.py, which this script imports). The pinned
mdli sha256 is checked before and after.

Usage (sandbox; TMPDIR must be writable):
    python3 -I scripts/probe_failure_inventory_reference.py OUT.json [--shim-src C]

All runs: pipe mode, fixed clock epoch 250776000, TZ=UTC, microseconds 0,
entry <FLOAD "77loadall.mud"> <SAVE-IT>, then the case's commands, then EOF.
Cases: every entry of tests/scenarios/failure-inventory-cases.json (F1-F13;
each has a note naming the source location it reaches). The same command
lists are run in this runtime by scripts/m4_inventory_candidate.rkt. A
`fault_skip` case (F11) is captured natively as the full battery. Plus:
  * X1  DIAGNOSTIC (not a transcript): after FLOAD (no SAVE-IT), prints
        ,MUDDLE and every action reference the game applies by name through
        APPLY-RANDOM / APPLY-OBJECT / DISPATCH (RACTION of every room,
        CXACTION of every CEXIT, OACTION of every object, AACTION of every
        actor, HACTION of every demon, VFCN of every VERB on the WORDS and
        ACTIONS OBLISTs, reached through ACTION syntaxes), with its GVAL's
        TYPE, to a log OUTSIDE the game copy. Read-only.

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source is copied into this script.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import probe_session_reference as psr  # noqa: E402
from probe_house_cellar_reference import game_part, split_responses  # noqa: E402

PINNED_SHA256 = "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789"
CASES_FILE = psr.ROOT / "tests/scenarios/failure-inventory-cases.json"

DIAG_FORMS = r'''<SETG DIAG-CH <OPEN "PRINT" "@LOG@">>
<SETG DIAG-RA <FUNCTION (DIAG-W DIAG-X) <PRINC .DIAG-W ,DIAG-CH> <PRINC " " ,DIAG-CH> <COND (<TYPE? .DIAG-X ATOM> <PRIN1 .DIAG-X ,DIAG-CH> <PRINC " " ,DIAG-CH> <PRIN1 <COND (<GASSIGNED? .DIAG-X> <TYPE ,.DIAG-X>) (T UNASSIGNED)> ,DIAG-CH>) (<NOT .DIAG-X> <PRINC "FALSE" ,DIAG-CH>) (T <PRINC "VALUE " ,DIAG-CH> <PRIN1 <TYPE .DIAG-X> ,DIAG-CH>)> <CRLF ,DIAG-CH> T>>
<PROG () <PRINC "MUDDLE " ,DIAG-CH> <PRIN1 ,MUDDLE ,DIAG-CH> <CRLF ,DIAG-CH> T>
<PROG () <MAPF <> <FUNCTION (DIAG-R) <DIAG-RA "RACTION" <RACTION .DIAG-R>> <MAPF <> <FUNCTION (DIAG-E) <COND (<TYPE? .DIAG-E CEXIT> <DIAG-RA "CXACTION" <CXACTION .DIAG-E>>)>> <REXITS .DIAG-R>>> ,ROOMS> T>
<PROG () <MAPF <> <FUNCTION (DIAG-O) <DIAG-RA "OACTION" <OACTION .DIAG-O>>> ,OBJECTS> T>
<PROG () <MAPF <> <FUNCTION (DIAG-A) <DIAG-RA "AACTION" <AACTION .DIAG-A>>> ,ACTORS> T>
<PROG () <MAPF <> <FUNCTION (DIAG-H) <DIAG-RA "HACTION" <HACTION .DIAG-H>>> ,DEMONS> T>
<PROG () <MAPF <> <FUNCTION (DIAG-B) <MAPF <> <FUNCTION (DIAG-V) <COND (<AND <GASSIGNED? .DIAG-V> <TYPE? ,.DIAG-V VERB>> <DIAG-RA "VFCN" <VFCN ,.DIAG-V>>)>> .DIAG-B>> ,WORDS> T>
<PROG () <MAPF <> <FUNCTION (DIAG-B) <MAPF <> <FUNCTION (DIAG-V) <COND (<AND <GASSIGNED? .DIAG-V> <TYPE? ,.DIAG-V ACTION>> <MAPF <> <FUNCTION (DIAG-S) <DIAG-RA "SFCN-VFCN" <VFCN <SFCN .DIAG-S>>>> <VDECL ,.DIAG-V>>)>> .DIAG-B>> ,ACTIONS> T>
<PROG () <PRINC "DONE" ,DIAG-CH> <CRLF ,DIAG-CH> T>
'''


def parse_rapplic(log: str) -> dict:
    rows, muddle, done = [], None, False
    for line in log.splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "MUDDLE":
            muddle = int(parts[1])
        elif parts[0] == "DONE":
            done = True
        else:
            rows.append(parts)
    atoms = sorted({(p[1], p[2]) for p in rows if len(p) == 3})
    values = sorted({(p[0], " ".join(p[1:])) for p in rows if len(p) != 3})
    return {"muddle": muddle, "complete": done, "references": len(rows),
            "distinct_atoms": [{"atom": a, "gval_type": t} for a, t in atoms],
            "non_atom_values": [{"slot": s, "value": v} for s, v in values]}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("output", type=Path)
    ap.add_argument("--shim-src", type=Path, default=psr.DEFAULT_SHIM_SRC)
    ap.add_argument("--only", action="append", default=[],
                    help="run only the named case ids (exploration; repeatable)")
    a = ap.parse_args()
    if not psr.EXE.is_file() or not psr.GAME.is_dir():
        raise SystemExit("missing pinned mdli or game sources")
    exe_before = psr.sha256_file(psr.EXE)
    if exe_before != PINNED_SHA256:
        raise SystemExit(f"mdli sha256 {exe_before} != pinned {PINNED_SHA256}")
    spec = json.loads(CASES_FILE.read_text(encoding="utf-8"))
    assert spec["fixed_epoch"] == psr.EPOCH and spec["tz"] == "UTC"
    base = Path(os.environ.get("TMPDIR", "/tmp")) / "failure-inventory-probes"
    base.mkdir(parents=True, exist_ok=True)
    shim = psr.build_shim(a.shim_src, Path(tempfile.mkdtemp(prefix="shim-", dir=base)))
    cases = []
    for c in spec["cases"]:
        if a.only and c["id"] not in a.only:
            continue
        cases.append({"name": c["id"], "input": psr.ENTRY + psr.lines(*c["commands"]),
                      "note": c["note"], "commands": c["commands"]})
    if not a.only or "X1" in a.only:
        cases.append({"name": "X1", "kind": "diagnostic",
                      "input": '<FLOAD "77loadall.mud">\n' + DIAG_FORMS,
                      "note": "DIAGNOSTIC (not a transcript): MUDDLE and every applied "
                              "action reference with its GVAL TYPE; log outside the game copy"})
    rows = []
    for c in cases:
        r = psr.run_case(c, base, shim)
        if r.get("kind") == "transcript":
            g = game_part(r["stdout_raw"])
            r["game_output_canonical"] = psr.canon(g)
            r["split"] = split_responses(psr.canon(g), c["commands"])
        else:
            r["rapplic"] = parse_rapplic(r.get("diag_log", ""))
        for k in ("files_before",):
            r.pop(k, None)
        rows.append(r)
    head = subprocess.run(["git", "-C", str(psr.UPSTREAM_ROOT), "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    res = {
        "schema_version": 1,
        "kind": "m4-failure-inventory-reference",
        "cases_file": "tests/scenarios/failure-inventory-cases.json",
        "engine": "confusion-patched-1977",
        "fixed_epoch": psr.EPOCH, "tz": "UTC",
        "entry": ['<FLOAD "77loadall.mud">', "<SAVE-IT>"],
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "interpreter": ".cache/build/confusion_patched/mdli",
        "interpreter_sha256_before": exe_before,
        "interpreter_sha256_after": psr.sha256_file(psr.EXE),
        "upstream_mdlzork_checked_out": head,
        "game_dir": "mdlzork_771212/patched_confusion",
        "shim_src_sha256": psr.sha256_file(a.shim_src),
        "shim": "scripts/reference/fixed_time.c compiled per capture: "
                "gcc -shared -fPIC -O2 -o fixed_time.so fixed_time.c -ldl; "
                "LD_PRELOAD, MDL_FIXED_EPOCH=250776000, TZ=UTC",
        "protocol": "scripts/probe_failure_inventory_reference.py (module docstring); "
                    "run_case from scripts/probe_session_reference.py",
        "diag_forms": DIAG_FORMS,
        "cases": rows,
    }
    text = json.dumps(res, indent=1, ensure_ascii=False) + "\n"
    tmp = os.environ.get("TMPDIR", "/tmp").rstrip("/")
    text = text.replace(tmp, "$TMPDIR").replace(str(psr.ROOT), "<repo>")
    a.output.write_text(text, encoding="utf-8")
    ok = exe_before == res["interpreter_sha256_after"]
    for r in rows:
        print(f'{r["name"]}: exit={r.get("exit_status")} changed={sorted(r["files_changed"])}',
              file=sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
