#!/usr/bin/env python3
"""Pinned-Confusion reference capture for the M4 S10 scenario help-info
(tests/scenarios/help-info.json; issue #171): `help`, `info` and `?` print the
shipped files MDL/MADADV.HELP and MDL/MADADV.INFO through FILE-TO-TTY
(77rooms.mud:954-985: OPEN "READ", FILE-LENGTH, READSTRING from the file
channel by count and with ,BREAKS, PRINTSTRING with a count, CLOSE).

Read-only reference investigation. Nothing here is runtime code, and the game
sources under .cache/upstream are never written: every run boots a fresh copy
of the game directory under $TMPDIR (protocol of
scripts/probe_session_reference.py, which this script imports; transcript
helpers from scripts/probe_house_cellar_reference.py). Modelled on
scripts/probe_p0prims_scenario_reference.py, with two differences:

  * the prompt split is LINE-INITIAL: the help text holds two '>' characters
    inside a line ('attack <villain> with <weapon>'), so prompt_head counts
    only '>' at the start of a line (the runner's #:prompt-split
    'line-initial);
  * the READSTRING wrapper of the diagnostic runs takes a checkpoint and logs
    READSTRING-COUNT / READSTRING-TEXT only for reads from ,INCHAN (RDCOM's
    command reads); reads from the help/info file channel are logged as
    FILE-READSTRING-COUNT only, FILE-LENGTH and CLOSE as FILE-LENGTH-RESULT
    and CLOSE-RESULT-TYPE. The wrappers apply the original SUBR to the same
    arguments and return its value unchanged.

Usage (sandbox; TMPDIR must be writable):
    python3 -I scripts/probe_help_info_scenario_reference.py OUT.json [--shim-src C]

Runs (all pipe mode, fixed clock epoch 250776000, TZ=UTC, microseconds 0):
  * T1  transcript: <FLOAD "77loadall.mud"> <SAVE-IT> + the scenario commands;
  * T1b repeat of T1 (byte determinism);
  * Pkk transcripts of the first k commands then EOF (k = 0 .. n-1);
  * Dkk DIAGNOSTIC prefix runs (k = 0 .. n-1): the X1 diagnostic input cut
        after k commands; their LAST checkpoint is the end-of-input state of
        prefix k;
  * X1  DIAGNOSTIC (not a transcript): forms typed at LISTEN after FLOAD and
        before SAVE-IT wrap RANDOM, READSTRING, FILE-LENGTH and CLOSE and log
        to DIAG.LOG OUTSIDE the game copy; a read-only state checkpoint is
        logged at every terminal READSTRING entry. The game part of X1's
        stdout must be byte-identical to T1's, or the capture is rejected.

Checkpoint fields: HERE's RID; the winner's AOBJS (OIDs); MOVES, RAW-SCORE,
DEATHS; TELL-FLAG; INBUF as the list of its 100 character codes
(<MAPF ,LIST ,ASCII ,INBUF>), which shows what the file READSTRINGs left in
the shared buffer. No game state is written.

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
import probe_session_reference as psr  # noqa: E402
from probe_house_cellar_reference import (  # noqa: E402
    game_part, split_responses, parse_diag)

TAG = "help-info"
PINNED_SHA256 = "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789"

DIAG_FORMS = r'''<SETG DIAG-CH <OPEN "PRINT" "@LOG@">>
<SETG DIAG <FUNCTION (DIAG-T DIAG-X) <PRINC .DIAG-T ,DIAG-CH> <PRINC " " ,DIAG-CH> <PRIN1 .DIAG-X ,DIAG-CH> <CRLF ,DIAG-CH> T>>
<SETG DIAG-N 0>
<SETG DIAG-STATE <FUNCTION () <DIAG "CP-BEGIN" ,DIAG-N> <DIAG "CP-HERE" <RID ,HERE>> <DIAG "CP-AOBJS" <MAPF ,LIST ,OID <AOBJS ,WINNER>>> <DIAG "CP-MOVES" ,MOVES> <DIAG "CP-RAW-SCORE" ,RAW-SCORE> <DIAG "CP-DEATHS" ,DEATHS> <DIAG "CP-TELL-FLAG" ,TELL-FLAG> <DIAG "CP-INBUF" <MAPF ,LIST ,ASCII ,INBUF>> <DIAG "CP-END" ,DIAG-N> <SETG DIAG-N <+ ,DIAG-N 1>> T>>
<SETG DIAG-ORIG-RANDOM ,RANDOM>
<SETG RANDOM <FUNCTION ("TUPLE" DIAG-A "AUX" DIAG-R) <DIAG "RANDOM-ARGS" <LIST !.DIAG-A>> <SET DIAG-R <APPLY ,DIAG-ORIG-RANDOM !.DIAG-A>> <DIAG "RANDOM-RESULT" .DIAG-R> .DIAG-R>>
<SETG DIAG-ORIG-FILE-LENGTH ,FILE-LENGTH>
<SETG FILE-LENGTH <FUNCTION ("TUPLE" DIAG-A "AUX" DIAG-R) <SET DIAG-R <APPLY ,DIAG-ORIG-FILE-LENGTH !.DIAG-A>> <DIAG "FILE-LENGTH-RESULT" .DIAG-R> .DIAG-R>>
<SETG DIAG-ORIG-CLOSE ,CLOSE>
<SETG CLOSE <FUNCTION ("TUPLE" DIAG-A "AUX" DIAG-R) <SET DIAG-R <APPLY ,DIAG-ORIG-CLOSE !.DIAG-A>> <DIAG "CLOSE-RESULT-TYPE" <TYPE .DIAG-R>> .DIAG-R>>
<SETG DIAG-ORIG-READSTRING ,READSTRING>
<SETG READSTRING <FUNCTION ("TUPLE" DIAG-A "AUX" DIAG-R (DIAG-TTY <==? <2 .DIAG-A> ,INCHAN>)) <AND .DIAG-TTY <DIAG-STATE>> <SET DIAG-R <APPLY ,DIAG-ORIG-READSTRING !.DIAG-A>> <COND (.DIAG-TTY <DIAG "READSTRING-COUNT" .DIAG-R> <DIAG "READSTRING-TEXT" <SUBSTRUC <1 .DIAG-A> 0 .DIAG-R>>) (T <DIAG "FILE-READSTRING-COUNT" .DIAG-R>)> .DIAG-R>>
'''


def prompt_positions(text: str) -> list[int]:
    """Offsets of the line-initial '>' (RDCOM prompts)."""
    return [m.start() for m in re.finditer(r"(?m)^>", text)]


def prompt_head(full_game: str, k: int) -> str:
    """T1's game text through the (k+1)-th line-initial RDCOM prompt."""
    return full_game[:prompt_positions(full_game)[k] + 1]


def file_events(log: str) -> list[dict]:
    out = []
    for line in log.splitlines():
        tag, _, val = line.partition(" ")
        if tag in ("FILE-READSTRING-COUNT", "FILE-LENGTH-RESULT", "CLOSE-RESULT-TYPE"):
            out.append({tag: val})
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("output", type=Path)
    ap.add_argument("--shim-src", type=Path, default=psr.DEFAULT_SHIM_SRC)
    a = ap.parse_args()
    scenario_file = psr.ROOT / f"tests/scenarios/{TAG}.json"
    if not psr.EXE.is_file() or not psr.GAME.is_dir():
        raise SystemExit("missing pinned mdli or game sources")
    exe_before = psr.sha256_file(psr.EXE)
    if exe_before != PINNED_SHA256:
        raise SystemExit(f"mdli sha256 {exe_before} != pinned {PINNED_SHA256}")
    sc = json.loads(scenario_file.read_text(encoding="utf-8"))
    cmds = sc["commands"]
    assert sc["fixed_epoch"] == psr.EPOCH and sc["tz"] == "UTC"
    entry_fload = '<FLOAD "77loadall.mud">\n'
    plain_input = psr.ENTRY + psr.lines(*cmds)
    diag_input = entry_fload + DIAG_FORMS + "<SAVE-IT>\n" + psr.lines(*cmds)
    base = Path(os.environ.get("TMPDIR", "/tmp")) / f"{TAG}-probes"
    base.mkdir(parents=True, exist_ok=True)
    shim = psr.build_shim(a.shim_src, Path(tempfile.mkdtemp(prefix="shim-", dir=base)))
    cases = [
        {"name": f"T1-{TAG}-pipe", "input": plain_input,
         "note": "transcript: faithful entry + scenario commands, then EOF"},
        {"name": f"T1b-{TAG}-pipe-repeat", "input": plain_input,
         "note": "repeat of T1 to show byte determinism"},
        {"name": f"X1-{TAG}-diag", "kind": "diagnostic", "input": diag_input,
         "note": "DIAGNOSTIC (not a transcript): RANDOM, READSTRING, FILE-LENGTH and CLOSE "
                 "wrapped after FLOAD, before SAVE-IT; read-only state checkpoint at every "
                 "terminal READSTRING entry; log in DIAG.LOG outside the game copy"},
    ]
    for k in range(len(cmds)):
        cases.append({"name": f"P{k:02d}-{TAG}-prefix",
                      "input": psr.ENTRY + psr.lines(*cmds[:k]),
                      "note": f"transcript of the first {k} commands, then EOF (used by "
                              f"per-prefix candidate runs)"})
    for k in range(len(cmds)):
        cases.append({"name": f"D{k:02d}-{TAG}-diag-prefix", "kind": "diagnostic",
                      "input": entry_fload + DIAG_FORMS + "<SAVE-IT>\n" + psr.lines(*cmds[:k]),
                      "note": f"DIAGNOSTIC: X1 cut after {k} commands; its last checkpoint is "
                              f"the end-of-input state of prefix {k} (end checkpoint {k})"})
    rows = [psr.run_case(c, base, shim) for c in cases]
    t1, t1b, x1 = rows[:3]
    prefixes = rows[3:3 + len(cmds)]
    dprefixes = rows[3 + len(cmds):]
    g1 = game_part(t1["stdout_raw"])
    gx = game_part(x1["stdout_raw"])
    diag = parse_diag(x1.get("diag_log", ""))
    canonical = psr.canon(g1)
    dparsed = [parse_diag(r.get("diag_log", "")) for r in dprefixes]
    end_checkpoints = [d["checkpoints"][-1] for d in dparsed] + [diag["checkpoints"][-1]]
    std_tail = "Beg pardon?\n>"
    checks = {
        "diag_prefix_game_parts_equal_prefix_game_parts": all(
            game_part(d["stdout_raw"]) == game_part(p["stdout_raw"])
            for d, p in zip(dprefixes, prefixes)),
        "diag_prefix_checkpoint_counts": [len(d["checkpoints"]) for d in dparsed],
        "t1_exit_status": t1["exit_status"],
        "t1_equals_t1b_bytes": t1["stdout_raw"] == t1b["stdout_raw"],
        "diag_game_part_equals_t1_game_part_bytes": g1 == gx and g1 != "",
        "diag_checkpoint_count": len(diag["checkpoints"]),
        "expected_checkpoint_count": len(cmds) + 2,
        "t1_line_initial_prompts": len(prompt_positions(g1)),
        "t1_all_gt_characters": g1.count(">"),
        "prefix_line_initial_prompts": [len(prompt_positions(game_part(r["stdout_raw"])))
                                        for r in prefixes],
        "prefix_runs_consistent_with_t1": all(
            game_part(r["stdout_raw"]).startswith(prompt_head(g1, k))
            for k, r in enumerate(prefixes)),
        "prefix_runs_with_non_standard_eof_tail": [
            k for k, r in enumerate(prefixes)
            if game_part(r["stdout_raw"])[len(prompt_head(g1, k)):] != std_tail],
        "prefix_exit_statuses": sorted({r["exit_status"] for r in prefixes}),
        "t1_files_changed": sorted(t1["files_changed"]),
        "t1_files_removed": t1["files_removed"],
        "x1_file_events": file_events(x1.get("diag_log", "")),
        "t1_elapsed_seconds": t1["elapsed_seconds"],
        "t1b_elapsed_seconds": t1b["elapsed_seconds"],
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
        "scenario_file": f"tests/scenarios/{TAG}.json",
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
        "protocol": "scripts/probe_help_info_scenario_reference.py (module docstring); "
                    "run_case from scripts/probe_session_reference.py",
        "prompt_split": "line-initial",
        "checks": checks,
        "transcript": {
            "source_case": t1["name"],
            "stdout_sha256": t1["stdout_sha256"],
            "game_output_raw": g1,
            "game_output_canonical": canonical,
            "split": split_responses(canonical, cmds),
        },
        "diagnostic": {"source_case": x1["name"], "diag_forms": DIAG_FORMS, **diag},
        "end_checkpoints": end_checkpoints,
        "cases": rows,
    }
    text = json.dumps(res, indent=2, ensure_ascii=False) + "\n"
    tmp = os.environ.get("TMPDIR", "/tmp").rstrip("/")
    for c in (t1, t1b, *prefixes):
        assert tmp not in c["stdout_raw"] and str(psr.ROOT) not in c["stdout_raw"], c["name"]
    text = text.replace(tmp, "$TMPDIR").replace(str(psr.ROOT), "<repo>")
    a.output.write_text(text, encoding="utf-8")
    print(json.dumps({k: v for k, v in checks.items() if k != "x1_file_events"}, indent=2),
          file=sys.stderr)
    ok = (checks["t1_equals_t1b_bytes"] and checks["diag_game_part_equals_t1_game_part_bytes"]
          and checks["prefix_runs_consistent_with_t1"]
          and checks["diag_prefix_game_parts_equal_prefix_game_parts"]
          and checks["diag_prefix_checkpoint_counts"] == [k + 2 for k in range(len(cmds))]
          and checks["diag_checkpoint_count"] == checks["expected_checkpoint_count"]
          and checks["t1_line_initial_prompts"] == len(cmds) + 2
          and checks["prefix_line_initial_prompts"] == [k + 2 for k in range(len(cmds))]
          and exe_before == res["interpreter_sha256_after"])
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
