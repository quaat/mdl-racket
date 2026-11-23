#!/usr/bin/env python3
"""Pinned-Confusion reference capture for M4 scenario 1, "enter the house and
open the cellar" (tests/scenarios/house-cellar.json).

Read-only reference investigation. Nothing here is runtime code, and the game
sources under .cache/upstream are never written: every run boots a fresh copy
of the game directory under $TMPDIR (protocol of scripts/probe_session_reference.py,
which this script imports).

Usage (sandbox; TMPDIR must be writable):
    python3 -I scripts/probe_house_cellar_reference.py OUT.json [--shim-src C]

Runs (all pipe mode, fixed clock epoch 250776000, TZ=UTC, microseconds 0):
  * T1  transcript: <FLOAD "77loadall.mud"> <SAVE-IT> + the scenario commands;
  * T1b repeat of T1 (byte determinism);
  * P00..P10 transcripts of the first k commands then EOF, for per-prefix
    candidate runs (state at end of input = checkpoint k);
  * X1  DIAGNOSTIC (not a transcript): the same input with forms typed at
        LISTEN after FLOAD and before SAVE-IT that wrap RANDOM and READSTRING.
        The wrappers apply the original SUBR to the same arguments and return
        its value unchanged; they only append to DIAG.LOG OUTSIDE the game
        copy. At every READSTRING entry (i.e. after the previous command has
        been fully processed, including demons) a read-only state checkpoint
        is logged. The game part of X1's stdout (from "Welcome to Dungeon.")
        must be byte-identical to T1's, or the capture is rejected.

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source is copied into this script.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import probe_session_reference as psr  # noqa: E402  (same protocol, same pinned paths)

SCENARIO = psr.ROOT / "tests/scenarios/house-cellar.json"
GAME_START = "Welcome to Dungeon."

# Read-only checkpoint. Every accessor below is a NEWSTRUC offset or a
# DEFMAC from 77defs.mud (RID, AOBJS, ASCORE, OID, ORAND, OTOUCH?, OLIGHT?,
# OFLAGS, OVIS? = TRNN OVISON, RSEEN?), or a pure predicate (LIT?, MEMQ).
# Object/room handles are fetched once, before SAVE-IT, with FIND-OBJ /
# FIND-ROOM on names that already exist (a pure lookup in that case,
# 77defs.mud:470-500). They are set inside one PROG that returns T, so LISTEN
# never prints a (circular) ROOM.
DIAG_FORMS = r'''<SETG DIAG-CH <OPEN "PRINT" "@LOG@">>
<SETG DIAG <FUNCTION (DIAG-T DIAG-X) <PRINC .DIAG-T ,DIAG-CH> <PRINC " " ,DIAG-CH> <PRIN1 .DIAG-X ,DIAG-CH> <CRLF ,DIAG-CH> T>>
<SETG DIAG-N 0>
<PROG () <SETG DIAG-RUG <FIND-OBJ "RUG">> <SETG DIAG-DOOR <FIND-OBJ "DOOR">> <SETG DIAG-LAMP <FIND-OBJ "LAMP">> <SETG DIAG-LROOM <FIND-ROOM "LROOM">> T>
<SETG DIAG-STATE <FUNCTION () <DIAG "CP-BEGIN" ,DIAG-N> <DIAG "CP-HERE" <RID ,HERE>> <DIAG "CP-RSEEN" <RSEEN? ,HERE>> <DIAG "CP-AOBJS" <MAPF ,LIST ,OID <AOBJS ,WINNER>>> <DIAG "CP-KITCHEN-WINDOW" ,KITCHEN-WINDOW!-FLAG> <DIAG "CP-RUG-ORAND" <ORAND ,DIAG-RUG>> <DIAG "CP-DOOR-OVISON" <OVIS? ,DIAG-DOOR>> <DIAG "CP-DOOR-OFLAGS" <CHTYPE <OFLAGS ,DIAG-DOOR> FIX>> <DIAG "CP-DOOR-OTOUCH" <OTOUCH? ,DIAG-DOOR>> <DIAG "CP-TRAP-DOOR" ,TRAP-DOOR!-FLAG> <DIAG "CP-LAMP-OLIGHT" <OLIGHT? ,DIAG-LAMP>> <DIAG "CP-LAMP-IN-LROOM" <COND (<MEMQ ,DIAG-LAMP <ROBJS ,DIAG-LROOM>> T)>> <DIAG "CP-LIT" <LIT? ,HERE>> <DIAG "CP-RAW-SCORE" ,RAW-SCORE> <DIAG "CP-ASCORE" <ASCORE ,WINNER>> <DIAG "CP-MOVES" ,MOVES> <DIAG "CP-END" ,DIAG-N> <SETG DIAG-N <+ ,DIAG-N 1>> T>>
<SETG DIAG-ORIG-RANDOM ,RANDOM>
<SETG RANDOM <FUNCTION ("TUPLE" DIAG-A "AUX" DIAG-R) <DIAG "RANDOM-ARGS" <LIST !.DIAG-A>> <SET DIAG-R <APPLY ,DIAG-ORIG-RANDOM !.DIAG-A>> <DIAG "RANDOM-RESULT" .DIAG-R> .DIAG-R>>
<SETG DIAG-ORIG-READSTRING ,READSTRING>
<SETG READSTRING <FUNCTION ("TUPLE" DIAG-A "AUX" DIAG-R) <DIAG-STATE> <SET DIAG-R <APPLY ,DIAG-ORIG-READSTRING !.DIAG-A>> <DIAG "READSTRING-COUNT" .DIAG-R> <DIAG "READSTRING-TEXT" <SUBSTRUC <1 .DIAG-A> 0 .DIAG-R>> .DIAG-R>>
'''


def game_part(stdout: str) -> str:
    i = stdout.find(GAME_START)
    return stdout[i:] if i >= 0 else ""


def prefix_expected(full_game: str, k: int) -> str:
    """T1's game text cut after the (k+1)-th RDCOM prompt, followed by the
    end-of-input reply T1 itself ends with ("Beg pardon?" and a prompt)."""
    segs = full_game.split(">")
    tail = ">".join(segs[len(segs) - 2:])          # "Beg pardon?\n" + ">" + rest
    return ">".join(segs[:k + 1]) + ">" + tail


def split_responses(game: str, commands: list[str]) -> dict:
    """Split the canonical game text at line-initial '>' prompts: chunk 0 is
    the opening text, chunk k (k>=1) is the response to command k."""
    parts = re.split(r"(?m)^>", game)
    opening, rest = parts[0], parts[1:]
    rows = []
    for k, cmd in enumerate(commands):
        rows.append({"input": cmd, "output": rest[k] if k < len(rest) else None})
    return {"opening": opening, "commands": rows, "after_last_command": rest[len(commands):]}


def parse_diag(log: str) -> dict:
    draws, checkpoints, reads, cur = [], [], [], None
    pending_args = None
    for line in log.splitlines():
        tag, _, val = line.partition(" ")
        if tag == "RANDOM-ARGS":
            pending_args = val
        elif tag == "RANDOM-RESULT":
            draws.append({"index": len(draws), "args": pending_args, "result": int(val),
                          "mod100": int(val) % 100, "mod8": int(val) % 8,
                          "before_checkpoint": len(checkpoints)})
            pending_args = None
        elif tag == "CP-BEGIN":
            cur = {"n": int(val)}
        elif tag == "CP-END":
            checkpoints.append(cur)
            cur = None
        elif tag.startswith("CP-") and cur is not None:
            cur[tag[3:].lower().replace("-", "_")] = val
        elif tag in ("READSTRING-COUNT", "READSTRING-TEXT"):
            reads.append({tag: val})
    return {"random_draws": draws, "checkpoints": checkpoints, "readstring": reads}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("output", type=Path)
    ap.add_argument("--shim-src", type=Path, default=psr.DEFAULT_SHIM_SRC)
    a = ap.parse_args()
    if not psr.EXE.is_file() or not psr.GAME.is_dir():
        raise SystemExit("missing pinned mdli or game sources")
    sc = json.loads(SCENARIO.read_text(encoding="utf-8"))
    cmds = sc["commands"]
    assert sc["fixed_epoch"] == psr.EPOCH and sc["tz"] == "UTC"
    entry_fload = '<FLOAD "77loadall.mud">\n'
    plain_input = psr.ENTRY + psr.lines(*cmds)
    diag_input = entry_fload + DIAG_FORMS + "<SAVE-IT>\n" + psr.lines(*cmds)
    base = Path(os.environ.get("TMPDIR", "/tmp")) / "house-cellar-probes"
    base.mkdir(parents=True, exist_ok=True)
    shim = psr.build_shim(a.shim_src, Path(tempfile.mkdtemp(prefix="shim-", dir=base)))
    exe_before = psr.sha256_file(psr.EXE)
    cases = [
        {"name": "T1-house-cellar-pipe", "input": plain_input,
         "note": "transcript: faithful entry + scenario commands, then EOF"},
        {"name": "T1b-house-cellar-pipe-repeat", "input": plain_input,
         "note": "repeat of T1 to show byte determinism"},
        {"name": "X1-house-cellar-diag", "kind": "diagnostic", "input": diag_input,
         "note": "DIAGNOSTIC (not a transcript): RANDOM and READSTRING wrapped after FLOAD, "
                 "before SAVE-IT; read-only state checkpoint at every READSTRING entry; "
                 "log in DIAG.LOG outside the game copy"},
    ]
    for k in range(len(cmds)):
        cases.append({"name": f"P{k:02d}-house-cellar-prefix", "input": psr.ENTRY + psr.lines(*cmds[:k]),
                      "note": f"transcript of the first {k} commands, then EOF (state at "
                              f"end of input = checkpoint {k}; used by per-prefix candidate runs)"})
    rows = [psr.run_case(c, base, shim) for c in cases]
    t1, t1b, x1 = rows[:3]
    prefixes = rows[3:]
    g1 = game_part(t1["stdout_raw"])
    gx = game_part(x1["stdout_raw"])
    diag = parse_diag(x1.get("diag_log", ""))
    canonical = psr.canon(g1)
    checks = {
        "t1_exit_status": t1["exit_status"],
        "t1_equals_t1b_bytes": t1["stdout_raw"] == t1b["stdout_raw"],
        "diag_game_part_equals_t1_game_part_bytes": g1 == gx and g1 != "",
        "diag_checkpoint_count": len(diag["checkpoints"]),
        "expected_checkpoint_count": len(cmds) + 2,
        "prefix_runs_consistent_with_t1": all(
            prefix_expected(g1, k) == game_part(r["stdout_raw"]) for k, r in enumerate(prefixes)),
        "prefix_exit_statuses": sorted({r["exit_status"] for r in prefixes}),
        "t1_files_changed": sorted(t1["files_changed"]),
        "t1_files_removed": t1["files_removed"],
    }
    head = subprocess.run(["git", "-C", str(psr.UPSTREAM_ROOT), "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    res = {
        "schema_version": 1,
        "kind": "m4-scenario-reference",
        "scenario": sc["name"],
        "scenario_file": "tests/scenarios/house-cellar.json",
        "engine": "confusion-patched-1977",
        "fixed_epoch": psr.EPOCH, "tz": "UTC",
        "entry": ['<FLOAD "77loadall.mud">', "<SAVE-IT>"],
        "commands": cmds,
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
        "protocol": "scripts/probe_house_cellar_reference.py (module docstring); "
                    "run_case from scripts/probe_session_reference.py",
        "checks": checks,
        "transcript": {
            "source_case": t1["name"],
            "stdout_sha256": t1["stdout_sha256"],
            "game_output_raw": g1,
            "game_output_canonical": canonical,
            "split": split_responses(canonical, cmds),
        },
        "diagnostic": {"source_case": x1["name"], "diag_forms": DIAG_FORMS, **diag},
        "cases": rows,
    }
    a.output.write_text(json.dumps(res, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(checks, indent=2), file=sys.stderr)
    ok = (checks["t1_equals_t1b_bytes"] and checks["diag_game_part_equals_t1_game_part_bytes"]
          and checks["prefix_runs_consistent_with_t1"]
          and checks["diag_checkpoint_count"] == checks["expected_checkpoint_count"])
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
