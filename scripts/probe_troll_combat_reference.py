#!/usr/bin/env python3
"""Pinned-Confusion reference capture for the M4 S6 scenario "fight the troll"
(tests/scenarios/troll-combat.json): the sword-glow path into the troll room,
then `kill troll with sword` until the fight is decided, then state checks.
Game path: RDCOM -> verb KILL -> KILLER (77act1.mud:1699) -> BLOW
(78melee.mud:377) for the hero's attack; the troll's counterattack each turn
through the demon FIGHTING (78melee.mud:282) -> BLOW; the troll's own action
TROLL (77act1.mud:360) for FIGHT!/DEAD! and the axe; MAX in BLOW's wound
arithmetic (78melee.mud:447-448); PRES (78melee.mud:351) picks each remark
with RANDOM; DIAGNOSE (78melee.mud:511) afterwards.

Read-only reference investigation. Nothing here is runtime code, and the game
sources under .cache/upstream are never written: every run boots a fresh copy
of the game directory under $TMPDIR (protocol of scripts/probe_session_reference.py,
which this script imports; transcript helpers from
scripts/probe_house_cellar_reference.py). Modelled on
scripts/probe_sword_glow_reference.py.

Usage (sandbox; TMPDIR must be writable):
    python3 -I scripts/probe_troll_combat_reference.py OUT.json [--shim-src C]

Runs (all pipe mode, fixed clock epoch 250776000, TZ=UTC, microseconds 0):
  * T1  transcript: <FLOAD "77loadall.mud"> <SAVE-IT> + the scenario commands;
  * T1b repeat of T1 (byte determinism, so the RANDOM-driven fight is fixed);
  * Pkk transcripts of the first k commands then EOF (k = 0 .. n-1), for
    per-prefix candidate runs;
  * Dkk DIAGNOSTIC prefix runs (k = 0 .. n-1): the X1 diagnostic input cut
        after k commands. Their LAST checkpoint is taken at the READSTRING
        that meets end of input, after the empty command that end of input
        produces ("Beg pardon?"), which still runs the demons (the troll's
        FIGHTING demon included); it is the state a per-prefix candidate run
        ends in ("end checkpoint k"). For k = n the end checkpoint is X1's
        last checkpoint. The game part of every Dkk stdout must equal Pkk's;
  * X1  DIAGNOSTIC (not a transcript): forms typed at LISTEN after FLOAD and
        before SAVE-IT wrap RANDOM and READSTRING (the original SUBR is
        applied to the same arguments and its value returned unchanged) and
        log to DIAG.LOG OUTSIDE the game copy. At every READSTRING entry a
        read-only state checkpoint is logged. The game part of X1's stdout
        must be byte-identical to T1's, or the capture is rejected.

Checkpoint fields (accessors are NEWSTRUC offsets/DEFMACs of 77defs.mud read
with NTH, or pure predicates; flag bits are tested with ANDB/CHTYPE exactly
as TRNN does): HERE's RID, the winner's AOBJS (OIDs), ASTRENGTH and
ASTAGGERED; the troll's OROOM (RID or FALSE), OCAPAC (its fighting strength;
0 dead, negative unconscious), OCONTENTS (OIDs), FIGHTBIT and STAGGERED; the
axe's OROOM and OCAN (OID or FALSE); TROLL-FLAG!-FLAG; <1 ,OPPV> (OID or
FALSE) and <1 ,VILLAIN-PROBS>; the cure clock CURIN's CFLAG and CTICK; the
sword's OTVAL (glow level) and SWORD-DEMON's HACTION; RAW-SCORE, ASCORE,
MOVES. No game state is written.

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

SCENARIO = psr.ROOT / "tests/scenarios/troll-combat.json"
PINNED_SHA256 = "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789"

DIAG_FORMS = r'''<SETG DIAG-CH <OPEN "PRINT" "@LOG@">>
<SETG DIAG <FUNCTION (DIAG-T DIAG-X) <PRINC .DIAG-T ,DIAG-CH> <PRINC " " ,DIAG-CH> <PRIN1 .DIAG-X ,DIAG-CH> <CRLF ,DIAG-CH> T>>
<SETG DIAG-N 0>
<PROG () <SETG DIAG-SWORD <FIND-OBJ "SWORD">> <SETG DIAG-TROLL <FIND-OBJ "TROLL">> <SETG DIAG-AXE <FIND-OBJ "AXE">> T>
<SETG DIAG-BIT <FUNCTION (DIAG-F DIAG-B) <N==? <CHTYPE <ANDB .DIAG-F .DIAG-B> FIX> 0>>>
<SETG DIAG-STATE <FUNCTION () <DIAG "CP-BEGIN" ,DIAG-N> <DIAG "CP-HERE" <RID ,HERE>> <DIAG "CP-AOBJS" <MAPF ,LIST ,OID <AOBJS ,WINNER>>> <DIAG "CP-WINNER-ASTRENGTH" <ASTRENGTH ,WINNER>> <DIAG "CP-WINNER-STAGGERED" <DIAG-BIT <AFLAGS ,WINNER> ,ASTAGGERED>> <DIAG "CP-TROLL-OROOM" <COND (<OROOM ,DIAG-TROLL> <RID <OROOM ,DIAG-TROLL>>)>> <DIAG "CP-TROLL-OCAPAC" <OCAPAC ,DIAG-TROLL>> <DIAG "CP-TROLL-OCONTENTS" <MAPF ,LIST ,OID <OCONTENTS ,DIAG-TROLL>>> <DIAG "CP-TROLL-FIGHTING" <DIAG-BIT <OFLAGS ,DIAG-TROLL> ,FIGHTBIT>> <DIAG "CP-TROLL-STAGGERED" <DIAG-BIT <OFLAGS ,DIAG-TROLL> ,STAGGERED>> <DIAG "CP-AXE-OROOM" <COND (<OROOM ,DIAG-AXE> <RID <OROOM ,DIAG-AXE>>)>> <DIAG "CP-AXE-OCAN" <COND (<OCAN ,DIAG-AXE> <OID <OCAN ,DIAG-AXE>>)>> <DIAG "CP-TROLL-FLAG" ,TROLL-FLAG!-FLAG> <DIAG "CP-OPPV-1" <COND (<1 ,OPPV> <OID <1 ,OPPV>>)>> <DIAG "CP-VILLAIN-PROBS-1" <1 ,VILLAIN-PROBS>> <DIAG "CP-CURIN-CFLAG" <CFLAG ,CURIN>> <DIAG "CP-CURIN-CTICK" <CTICK ,CURIN>> <DIAG "CP-SWORD-OTVAL" <OTVAL ,DIAG-SWORD>> <DIAG "CP-SWORD-DEMON-HACTION" <HACTION ,SWORD-DEMON>> <DIAG "CP-RAW-SCORE" ,RAW-SCORE> <DIAG "CP-ASCORE" <ASCORE ,WINNER>> <DIAG "CP-MOVES" ,MOVES> <DIAG "CP-END" ,DIAG-N> <SETG DIAG-N <+ ,DIAG-N 1>> T>>
<SETG DIAG-ORIG-RANDOM ,RANDOM>
<SETG RANDOM <FUNCTION ("TUPLE" DIAG-A "AUX" DIAG-R) <DIAG "RANDOM-ARGS" <LIST !.DIAG-A>> <SET DIAG-R <APPLY ,DIAG-ORIG-RANDOM !.DIAG-A>> <DIAG "RANDOM-RESULT" .DIAG-R> .DIAG-R>>
<SETG DIAG-ORIG-READSTRING ,READSTRING>
<SETG READSTRING <FUNCTION ("TUPLE" DIAG-A "AUX" DIAG-R) <DIAG-STATE> <SET DIAG-R <APPLY ,DIAG-ORIG-READSTRING !.DIAG-A>> <DIAG "READSTRING-COUNT" .DIAG-R> <DIAG "READSTRING-TEXT" <SUBSTRUC <1 .DIAG-A> 0 .DIAG-R>> .DIAG-R>>
'''


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
    base = Path(os.environ.get("TMPDIR", "/tmp")) / "troll-combat-probes"
    base.mkdir(parents=True, exist_ok=True)
    shim = psr.build_shim(a.shim_src, Path(tempfile.mkdtemp(prefix="shim-", dir=base)))
    cases = [
        {"name": "T1-troll-combat-pipe", "input": plain_input,
         "note": "transcript: faithful entry + scenario commands, then EOF"},
        {"name": "T1b-troll-combat-pipe-repeat", "input": plain_input,
         "note": "repeat of T1 to show byte determinism"},
        {"name": "X1-troll-combat-diag", "kind": "diagnostic", "input": diag_input,
         "note": "DIAGNOSTIC (not a transcript): RANDOM and READSTRING wrapped after "
                 "FLOAD, before SAVE-IT; read-only state checkpoint at every READSTRING "
                 "entry; log in DIAG.LOG outside the game copy"},
    ]
    for k in range(len(cmds)):
        cases.append({"name": f"P{k:02d}-troll-combat-prefix",
                      "input": psr.ENTRY + psr.lines(*cmds[:k]),
                      "note": f"transcript of the first {k} commands, then EOF (used by "
                              f"per-prefix candidate runs)"})
    for k in range(len(cmds)):
        cases.append({"name": f"D{k:02d}-troll-combat-diag-prefix", "kind": "diagnostic",
                      "input": entry_fload + DIAG_FORMS + "<SAVE-IT>\n" + psr.lines(*cmds[:k]),
                      "note": f"DIAGNOSTIC: X1 cut after {k} commands; its last checkpoint is "
                              f"the end-of-input state of prefix {k} (end checkpoint {k})"})
    rows = [psr.run_case(c, base, shim) for c in cases]
    t1, t1b, x1 = rows[:3]
    prefixes = rows[3:3 + len(cmds)]
    dprefixes = rows[3 + len(cmds):]
    g1 = game_part(t1["stdout_raw"])
    gx = game_part(x1["stdout_raw"])
    log = x1.get("diag_log", "")
    diag = parse_diag(log)
    canonical = psr.canon(g1)
    dparsed = [parse_diag(r.get("diag_log", "")) for r in dprefixes]
    end_checkpoints = [d["checkpoints"][-1] for d in dparsed] + [diag["checkpoints"][-1]]
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
        "prefix_runs_consistent_with_t1": all(
            prefix_expected(g1, k) == game_part(r["stdout_raw"]) for k, r in enumerate(prefixes)),
        "prefix_exit_statuses": sorted({r["exit_status"] for r in prefixes}),
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
        "scenario_file": "tests/scenarios/troll-combat.json",
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
        "protocol": "scripts/probe_troll_combat_reference.py (module docstring); "
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
        "end_checkpoints": end_checkpoints,
        "cases": rows,
    }
    text = json.dumps(res, indent=2, ensure_ascii=False) + "\n"
    # Local paths (diagnostic DIAG.LOG names, a CHANNEL's printed name) are
    # sanitized; transcript cases contain none, so their stdout and recorded
    # sha256 are untouched (checked).
    tmp = os.environ.get("TMPDIR", "/tmp").rstrip("/")
    for c in (t1, t1b, *prefixes):
        assert tmp not in c["stdout_raw"] and str(psr.ROOT) not in c["stdout_raw"], c["name"]
    text = text.replace(tmp, "$TMPDIR").replace(str(psr.ROOT), "<repo>")
    a.output.write_text(text, encoding="utf-8")
    print(json.dumps(checks, indent=2), file=sys.stderr)
    ok = (checks["t1_equals_t1b_bytes"] and checks["diag_game_part_equals_t1_game_part_bytes"]
          and checks["prefix_runs_consistent_with_t1"]
          and checks["diag_prefix_game_parts_equal_prefix_game_parts"]
          and checks["diag_prefix_checkpoint_counts"] == [k + 2 for k in range(len(cmds))]
          and checks["diag_checkpoint_count"] == checks["expected_checkpoint_count"]
          and exe_before == res["interpreter_sha256_after"])
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
