#!/usr/bin/env python3
"""Pinned-Confusion reference capture for the M4 S3 scenario "orphan
prompts" (tests/scenarios/orphan-prompt.json), the game path of CHTYPE FIX ->
CHARACTER (ORTELL 77np.mud:226 -> PRSTR -> FOOSTR 77np.mud:241).

Read-only reference investigation. Nothing here is runtime code, and the game
sources under .cache/upstream are never written: every run boots a fresh copy
of the game directory under $TMPDIR (protocol of scripts/probe_session_reference.py,
which this script imports; transcript helpers from
scripts/probe_house_cellar_reference.py).

Usage (sandbox; TMPDIR must be writable):
    python3 -I scripts/probe_orphan_prompt_reference.py OUT.json [--shim-src C]

Runs (all pipe mode, fixed clock epoch 250776000, TZ=UTC, microseconds 0):
  * T1  transcript: <FLOAD "77loadall.mud"> <SAVE-IT> + the scenario commands;
  * T1b repeat of T1 (byte determinism);
  * Pkk transcripts of the first k commands then EOF (k = 0 .. n-1), for
    per-prefix candidate runs (state at end of input = checkpoint k);
  * F2  transcript of frontier F2 (not the scenario): the S1 house-cellar
        commands without `score`, then `east`, `kill troll`, `lamp`;
  * X1  DIAGNOSTIC (not a transcript): forms typed at LISTEN after FLOAD and
        before SAVE-IT wrap RANDOM, READSTRING and CHTYPE (the original SUBR
        is applied to the same arguments and its value returned unchanged)
        and log to DIAG.LOG OUTSIDE the game copy. The CHTYPE wrapper logs
        the first argument of every CHTYPE whose second argument is the ATOM
        CHARACTER (the values that reach FOOSTR's conversion). At every
        READSTRING entry a read-only state checkpoint is logged. The game
        part of X1's stdout must be byte-identical to T1's, or the capture is
        rejected.

Checkpoint fields (accessors are NEWSTRUC offsets/MSETG constants of
77defs.mud read with NTH, or pure predicates): HERE's RID, the winner's AOBJS
(OIDs), WHOUS's ROBJS (OIDs), MAILB's OCONTENTS (OIDs), MAILB OOPEN?, the
leaflet's OROOM (RID or FALSE), OCAN (OID or FALSE) and OTOUCH?; the ORPHANS
vector (77np.mud:9, 77defs.mud:146-150): OFLAG, OVERB (the ACTION's VNAME or
FALSE), OSLOT1 (OID or FALSE; any other TYPE is logged by name), OPREP (the
PREP CHTYPEd to ATOM, or FALSE), ONAME; the five codes of the parser's
scratch buffer <BACK ,SCRSTR 5> (77np.mud:354), which PRSTR writes; RAW-SCORE,
ASCORE, MOVES. No game state is written.

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
from probe_house_cellar_reference import (  # noqa: E402
    game_part, prefix_expected, split_responses, parse_diag)

SCENARIO = psr.ROOT / "tests/scenarios/orphan-prompt.json"
PINNED_SHA256 = "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789"
F2_COMMANDS = ["north", "east", "open window", "west", "west", "take lamp", "move rug",
               "open trap door", "turn on lamp", "down", "east", "kill troll", "lamp"]

DIAG_FORMS = r'''<SETG DIAG-CH <OPEN "PRINT" "@LOG@">>
<SETG DIAG <FUNCTION (DIAG-T DIAG-X) <PRINC .DIAG-T ,DIAG-CH> <PRINC " " ,DIAG-CH> <PRIN1 .DIAG-X ,DIAG-CH> <CRLF ,DIAG-CH> T>>
<SETG DIAG-N 0>
<PROG () <SETG DIAG-LEAF <FIND-OBJ "ADVER">> <SETG DIAG-MBOX <FIND-OBJ "MAILB">> <SETG DIAG-WHOUS <FIND-ROOM "WHOUS">> T>
<SETG DIAG-OBJ <FUNCTION (DIAG-O) <COND (<NOT .DIAG-O> .DIAG-O) (<TYPE? .DIAG-O OBJECT> <OID .DIAG-O>) (T <TYPE .DIAG-O>)>>>
<SETG DIAG-STATE <FUNCTION ("AUX" (DIAG-OR ,ORPHANS)) <DIAG "CP-BEGIN" ,DIAG-N> <DIAG "CP-HERE" <RID ,HERE>> <DIAG "CP-AOBJS" <MAPF ,LIST ,OID <AOBJS ,WINNER>>> <DIAG "CP-WHOUS-ROBJS" <MAPF ,LIST ,OID <ROBJS ,DIAG-WHOUS>>> <DIAG "CP-MAILBOX-OCONTENTS" <MAPF ,LIST ,OID <OCONTENTS ,DIAG-MBOX>>> <DIAG "CP-MAILBOX-OOPEN" <OOPEN? ,DIAG-MBOX>> <DIAG "CP-LEAFLET-OROOM" <COND (<OROOM ,DIAG-LEAF> <RID <OROOM ,DIAG-LEAF>>)>> <DIAG "CP-LEAFLET-OCAN" <COND (<OCAN ,DIAG-LEAF> <OID <OCAN ,DIAG-LEAF>>)>> <DIAG "CP-LEAFLET-OTOUCH" <OTOUCH? ,DIAG-LEAF>> <DIAG "CP-ORPHAN-FLAG" <NTH .DIAG-OR ,OFLAG>> <DIAG "CP-ORPHAN-VERB" <COND (<NTH .DIAG-OR ,OVERB> <VNAME <NTH .DIAG-OR ,OVERB>>)>> <DIAG "CP-ORPHAN-SLOT1" <DIAG-OBJ <NTH .DIAG-OR ,OSLOT1>>> <DIAG "CP-ORPHAN-PREP" <COND (<NTH .DIAG-OR ,OPREP> <CHTYPE <NTH .DIAG-OR ,OPREP> ATOM>)>> <DIAG "CP-ORPHAN-NAME" <NTH .DIAG-OR ,ONAME>> <DIAG "CP-SCRSTR-CODES" <MAPF ,LIST ,ASCII <BACK ,SCRSTR 5>>> <DIAG "CP-RAW-SCORE" ,RAW-SCORE> <DIAG "CP-ASCORE" <ASCORE ,WINNER>> <DIAG "CP-MOVES" ,MOVES> <DIAG "CP-END" ,DIAG-N> <SETG DIAG-N <+ ,DIAG-N 1>> T>>
<SETG DIAG-ORIG-RANDOM ,RANDOM>
<SETG RANDOM <FUNCTION ("TUPLE" DIAG-A "AUX" DIAG-R) <DIAG "RANDOM-ARGS" <LIST !.DIAG-A>> <SET DIAG-R <APPLY ,DIAG-ORIG-RANDOM !.DIAG-A>> <DIAG "RANDOM-RESULT" .DIAG-R> .DIAG-R>>
<SETG DIAG-ORIG-CHTYPE ,CHTYPE>
<SETG CHTYPE <FUNCTION (DIAG-A DIAG-B) <COND (<==? .DIAG-B CHARACTER> <DIAG "CHTYPE-CHARACTER" .DIAG-A>)> <APPLY ,DIAG-ORIG-CHTYPE .DIAG-A .DIAG-B>>>
<SETG DIAG-ORIG-READSTRING ,READSTRING>
<SETG READSTRING <FUNCTION ("TUPLE" DIAG-A "AUX" DIAG-R) <DIAG-STATE> <SET DIAG-R <APPLY ,DIAG-ORIG-READSTRING !.DIAG-A>> <DIAG "READSTRING-COUNT" .DIAG-R> <DIAG "READSTRING-TEXT" <SUBSTRUC <1 .DIAG-A> 0 .DIAG-R>> .DIAG-R>>
'''


def chtype_character_log(log: str) -> list[dict]:
    """The CHTYPE ... CHARACTER arguments, each with the number of
    checkpoints logged before it (= the command index that reached it)."""
    out, cps = [], 0
    for line in log.splitlines():
        tag, _, val = line.partition(" ")
        if tag == "CP-END":
            cps += 1
        elif tag == "CHTYPE-CHARACTER":
            out.append({"arg": int(val), "char": chr(int(val)) if 0 <= int(val) < 128 else None,
                        "before_checkpoint": cps})
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("output", type=Path)
    ap.add_argument("--shim-src", type=Path, default=psr.DEFAULT_SHIM_SRC)
    a = ap.parse_args()
    if not psr.EXE.is_file() or not psr.GAME.is_dir():
        raise SystemExit("missing pinned mdli or game sources")
    exe_before = psr.sha256_file(psr.EXE)
    if exe_before != PINNED_SHA256:
        raise SystemExit(f"mdli sha256 {exe_before} != pinned {PINNED_SHA256}")
    sc = json.loads(SCENARIO.read_text(encoding="utf-8"))
    cmds = sc["commands"]
    assert sc["fixed_epoch"] == psr.EPOCH and sc["tz"] == "UTC"
    entry_fload = '<FLOAD "77loadall.mud">\n'
    plain_input = psr.ENTRY + psr.lines(*cmds)
    diag_input = entry_fload + DIAG_FORMS + "<SAVE-IT>\n" + psr.lines(*cmds)
    base = Path(os.environ.get("TMPDIR", "/tmp")) / "orphan-prompt-probes"
    base.mkdir(parents=True, exist_ok=True)
    shim = psr.build_shim(a.shim_src, Path(tempfile.mkdtemp(prefix="shim-", dir=base)))
    cases = [
        {"name": "T1-orphan-prompt-pipe", "input": plain_input,
         "note": "transcript: faithful entry + scenario commands, then EOF"},
        {"name": "T1b-orphan-prompt-pipe-repeat", "input": plain_input,
         "note": "repeat of T1 to show byte determinism"},
        {"name": "X1-orphan-prompt-diag", "kind": "diagnostic", "input": diag_input,
         "note": "DIAGNOSTIC (not a transcript): RANDOM, READSTRING and CHTYPE wrapped after "
                 "FLOAD, before SAVE-IT; read-only state checkpoint at every READSTRING entry; "
                 "CHTYPE ... CHARACTER arguments logged; log in DIAG.LOG outside the game copy"},
    ]
    # Frontier F2 (S1-HOUSE-CELLAR-FRONTIER.md): S1 without `score`, then the
    # troll room, `kill troll` (native `with what?`) and the answer `lamp`.
    # Not part of the scenario; the positive regression of
    # tests/historical_m4_frontier_test.rkt compares against it.
    cases.append({"name": "F2-kill-troll-pipe",
                  "input": psr.ENTRY + psr.lines(*F2_COMMANDS),
                  "note": "frontier F2 transcript (not the scenario): S1 without score, east, "
                          "kill troll, lamp, then EOF"})
    for k in range(len(cmds)):
        cases.append({"name": f"P{k:02d}-orphan-prompt-prefix",
                      "input": psr.ENTRY + psr.lines(*cmds[:k]),
                      "note": f"transcript of the first {k} commands, then EOF (state at "
                              f"end of input = checkpoint {k}; used by per-prefix candidate runs)"})
    rows = [psr.run_case(c, base, shim) for c in cases]
    t1, t1b, x1, f2 = rows[:4]
    prefixes = rows[4:]
    g1 = game_part(t1["stdout_raw"])
    gx = game_part(x1["stdout_raw"])
    log = x1.get("diag_log", "")
    diag = parse_diag(log)
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
        "f2_exit_status": f2["exit_status"],
        "t1_files_changed": sorted(t1["files_changed"]),
        "t1_files_removed": t1["files_removed"],
    }
    for r in rows:
        for k in ("files_before", "changed_file_text"):
            r.pop(k, None)
    head = subprocess.run(["git", "-C", str(psr.UPSTREAM_ROOT), "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    res = {
        "schema_version": 1,
        "kind": "m4-scenario-reference",
        "scenario": sc["name"],
        "scenario_file": "tests/scenarios/orphan-prompt.json",
        "engine": "confusion-patched-1977",
        "fixed_epoch": psr.EPOCH, "tz": "UTC",
        "entry": ['<FLOAD "77loadall.mud">', "<SAVE-IT>"],
        "commands": cmds,
        "f2_commands": F2_COMMANDS,
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
        "protocol": "scripts/probe_orphan_prompt_reference.py (module docstring); "
                    "run_case from scripts/probe_session_reference.py",
        "checks": checks,
        "transcript": {
            "source_case": t1["name"],
            "stdout_sha256": t1["stdout_sha256"],
            "game_output_raw": g1,
            "game_output_canonical": canonical,
            "split": split_responses(canonical, cmds),
        },
        "diagnostic": {"source_case": x1["name"], "diag_forms": DIAG_FORMS,
                       "chtype_character": chtype_character_log(log), **diag},
        "cases": rows,
    }
    a.output.write_text(json.dumps(res, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
