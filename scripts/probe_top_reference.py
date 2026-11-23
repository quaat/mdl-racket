#!/usr/bin/env python3
"""Pinned-Confusion reference probes for M4 S4: the TOP SUBR (issue #157;
SPARSE 77np.mud:126 `<TOP <PUT <BACK .PVR> 1 ...>>`, EVERYTHING/VALUABLES
77rooms.mud:1284,1330 `<TOP .SUV>` on the OBJECT UVECTOR OBJ-UV, the balloon
77act2.mud:505,557 `<TOP ,SCRSTR>`, the script channels 77rooms.mud:317-369
`<PUT <TOP ,INCHAN> 1 ...>`).

Read-only reference investigation. Nothing here is runtime code, and the game
sources under .cache/upstream are never written.

Usage (sandbox; TMPDIR must be writable):
    python3 -I scripts/probe_top_reference.py OUT.json [--shim-src C]

Protocol (run_case of scripts/probe_session_reference.py):
  * one pinned mdli process per case, pipe mode, fixed clock (LD_PRELOAD of
    scripts/reference/fixed_time.c, MDL_FIXED_EPOCH=250776000, TZ=UTC);
  * language cases ("cwd": "empty") run in a fresh empty directory under
    $TMPDIR/top-probes; game cases run in a fresh copy of
    mdlzork_771212/patched_confusion (SAVEFILE/ZORK.SAVE removed);
  * every case ends with <QUIT>; error cases hold one failing form so that a
    LISTENING-AT-LEVEL 2 never hides a later result;
  * a CHTYPE'd STRING is never printed (printing one upsets this build's
    REP); its TYPE and LENGTH are observed instead;
  * the interpreter sha256 is recorded before and after and must equal
    PINNED_SHA256.

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
import probe_session_reference as psr  # noqa: E402  (same protocol, same pinned paths)

PINNED_SHA256 = "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789"
Q = "<QUIT>\n"


def lang(name, forms, note=""):
    return {"name": name, "cwd": "empty", "note": note,
            "forms": forms, "input": "\n".join(forms) + "\n" + Q}


def game(name, forms, note=""):
    return {"name": name, "cwd": "game", "note": note,
            "forms": forms, "input": "\n".join(forms) + "\n" + Q}


CASES = [
    # --- VECTOR: REST views and unrested arrays -----------------------------------
    lang("vector-top", ["<SET V [1 2 3 4]>", "<SET R <REST .V 2>>", "<TOP .R>",
                        "<TYPE <TOP .R>>", "<LENGTH <TOP .R>>",
                        "<==? <TOP .R> .V>", "<=? <TOP .R> .V>",
                        "<TOP .V>", "<==? <TOP .V> .V>",
                        "<TOP <REST .V 4>>", "<==? <TOP <REST .V 4>> .V>",
                        "<==? <TOP .R> .R>", "<LENGTH .R>"],
         "TOP of a REST view is the whole array, ==? the original; the view is unchanged"),
    lang("vector-identity", ["<SET V [1 2 3 4]>", "<SET R <REST .V 2>>",
                             "<==? <TOP .R> <TOP <REST .V 1>>>",
                             "<==? <TOP .R> <BACK .R 2>>",
                             "<==? <TOP .R> <BACK .R 1>>",
                             "<==? <TOP <TOP .R>> .V>",
                             "<==? <TOP .R> [1 2 3 4]>", "<=? <TOP .R> [1 2 3 4]>",
                             "<==? <TOP <REST [1 2 3 4] 2>> .V>"],
         "identity is the same storage, start and length; an equal copy is =? only"),
    lang("vector-aliasing", ["<SET V [1 2 3 4]>", "<SET R <REST .V 2>>",
                             "<PUT <TOP .R> 1 X>", ".V", "<PUT .R 1 Y>", "<TOP .R>",
                             "<PUT .V 2 Z>", "<TOP .R>", "<PUT <TOP .R> 4 W>", ".R",
                             "<SET T <TOP .R>>", "<PUT .V 1 Q>", ".T"],
         "TOP shares storage: mutation before and after TOP, through any view, is visible"),
    lang("vector-back-view", ["<SET V [1 2 3 4 5]>", "<SET B <BACK <REST .V 4> 2>>", ".B",
                              "<TOP .B>", "<==? <TOP .B> .V>",
                              "<TOP <BACK <REST .V 1> 1>>"],
         "TOP of a BACK view"),
    lang("empty-arrays", ["<TOP []>", "<TOP <REST [] 0>>", "<TOP <REST [1] 1>>",
                          "<TOP \"\">", "<LENGTH <TOP <REST \"ab\" 2>>>",
                          "<TOP <IUVECTOR 0>>", "<SET E []>", "<==? <TOP .E> .E>"]),
    # --- UVECTOR ------------------------------------------------------------------------
    lang("uvector-top", ["<SET U <IUVECTOR 4 7>>", "<TOP <REST .U 4>>",
                         "<==? <TOP <REST .U 4>> .U>", "<UTYPE <TOP <REST .U 2>>>",
                         "<TYPE <TOP <REST .U 2>>>", "<LENGTH <TOP <REST .U 3>>>",
                         "<PUT <REST .U 3> 1 9>", "<TOP <REST .U 1>>",
                         "<PUT <TOP <REST .U 2>> 1 8>", ".U"]),
    lang("uvector-objuv-shape", ["<SET W <CHUTYPE <REST <IUVECTOR 3> 3> FIX>>",
                                 "<UTYPE .W>", "<LENGTH .W>", "<UTYPE <TOP .W>>",
                                 "<LENGTH <TOP .W>>", "<SET T <TOP .W>>",
                                 "<SET S .W>", "<==? .S .T>",
                                 "<SET S <BACK .S>>", "<PUT .S 1 5>", "<==? .S .T>",
                                 "<SET S <BACK .S>>", "<PUT .S 1 6>", "<==? .S .T>",
                                 "<SET S <BACK .S>>", "<PUT .S 1 7>", "<==? .S .T>",
                                 "<TOP .W>", ".S", "<LENGTH .W>"],
         "EVERYTHING's shape (77rooms.mud:1249, 1283-1300): TUV = <TOP .SUV>, fill with "
         "BACK/PUT until <==? .SUV .TUV>"),
    # --- STRING -------------------------------------------------------------------------
    lang("string-top", ["<SET S \"abcdef\">", "<SET R <REST .S 3>>", "<TOP .R>",
                        "<==? <TOP .R> .S>", "<=? <TOP .R> .S>", "<TYPE <TOP .R>>",
                        "<LENGTH <TOP .R>>", "<TOP .S>", "<==? <TOP .S> .S>",
                        "<TOP <MEMQ !\\c \"abcd\">>", "<TOP <BACK <REST .S 4> 2>>",
                        "<==? <TOP .R> \"abcdef\">"]),
    lang("string-scrstr-shape", ["<SETG SS <REST <ISTRING 5> 5>>", "<LENGTH ,SS>",
                                 "<LENGTH <TOP ,SS>>", "<MAPF ,LIST ,ASCII <TOP ,SS>>",
                                 "<SET T <TOP ,SS>>", "<PUT .T 5 !\\x>", "<BACK ,SS 1>",
                                 "<PUT <BACK ,SS 2> 1 !\\y>", "<MAPF ,LIST ,ASCII .T>",
                                 "<==? <TOP ,SS> <BACK ,SS 5>>"],
         "the balloon's shape (77np.mud:354, 77act2.mud:505,557): (S <TOP ,SCRSTR>) then PUT"),
    lang("string-aliasing", ["<SET S <ISTRING 4 !\\a>>", "<SET R <REST .S 2>>",
                             "<PUT <TOP .R> 1 !\\b>", ".S", "<PUT .R 1 !\\c>", "<TOP .R>",
                             "<PUT .S 4 !\\d>", "<TOP .R>"]),
    # --- NEWTYPE-tagged arrays ----------------------------------------------------------
    lang("newtype-vector", ["<NEWTYPE FOO VECTOR>", "<SET V [1 2 3 4]>",
                            "<SET F <CHTYPE [1 2 3] FOO>>", "<TYPE <TOP .F>>", "<TOP .F>",
                            "<==? <TOP .F> .F>", "<TYPE <REST .F>>", "<TYPE <TOP <REST .F>>>",
                            "<TOP <REST .F>>",
                            "<TOP <CHTYPE <REST .V 2> FOO>>",
                            "<TYPE <TOP <CHTYPE <REST .V 2> FOO>>>",
                            "<==? <TOP <CHTYPE <REST .V 2> FOO>> .V>",
                            "<=? <TOP <CHTYPE <REST .V 2> FOO>> .V>",
                            "<==? <CHTYPE <TOP <CHTYPE <REST .V 2> FOO>> VECTOR> .V>",
                            "<PUT <TOP <CHTYPE <REST .V 2> FOO>> 1 X>", ".V"],
         "TOP keeps the argument's TYPE (a NEWTYPE survives TOP; REST drops it first)"),
    lang("newtype-string-uvector", ["<NEWTYPE BAR STRING>", "<NEWTYPE BAZ UVECTOR>",
                                    "<SET S \"hello\">",
                                    "<TYPE <TOP <CHTYPE <REST .S 2> BAR>>>",
                                    "<LENGTH <TOP <CHTYPE <REST .S 2> BAR>>>",
                                    "<==? <CHTYPE <TOP <CHTYPE <REST .S 2> BAR>> STRING> .S>",
                                    "<SET U ![1 2 3!]>",
                                    "<TYPE <TOP <CHTYPE <REST .U 2> BAZ>>>",
                                    "<LENGTH <TOP <CHTYPE <REST .U 2> BAZ>>>",
                                    "<UTYPE <TOP <CHTYPE <REST .U 2> BAZ>>>"],
         "a CHTYPE'd STRING is not printed (see the module docstring)"),
    # --- CHANNEL storage ----------------------------------------------------------------
    lang("channel-top", ["<TYPE <TOP ,INCHAN>>", "<LENGTH <TOP ,INCHAN>>", "<LENGTH ,INCHAN>",
                         "<TOP ,INCHAN>", "<1 <TOP ,INCHAN>>", "<2 <TOP ,INCHAN>>",
                         "<3 <TOP ,INCHAN>>", "<1 ,INCHAN>", "<2 ,INCHAN>",
                         "<TYPE <BACK ,INCHAN 2>>",
                         "<==? <TOP ,INCHAN> <BACK ,INCHAN 2>>",
                         "<==? <TOP ,INCHAN> ,INCHAN>",
                         "<TYPE <TOP <REST ,INCHAN 3>>>", "<LENGTH <TOP <REST ,INCHAN 3>>>",
                         "<TYPE <TOP ,OUTCHAN>>", "<LENGTH <TOP ,OUTCHAN>>",
                         "<1 <TOP ,OUTCHAN>>", "<2 <TOP ,OUTCHAN>>"],
         "the terminal CHANNELs have two slots before element 1; TOP's slot 1 is the LIST "
         "the script code (77rooms.mud:317-369) PUTs channels into"),
    lang("err-channel-back-3", ["<BACK ,INCHAN 3>"]),
    # --- refusals -------------------------------------------------------------------------
    lang("err-list", ["<TOP (1 2)>"]),
    lang("err-rested-list", ["<TOP <REST (1 2 3)>>"]),
    lang("err-form", ["<TOP '<A B>>"]),
    lang("err-false", ["<TOP <>>"]),
    lang("err-segment", ["<TOP <CHTYPE '<A B> SEGMENT>>"]),
    lang("err-fix", ["<TOP 5>"]),
    lang("err-atom", ["<TOP FOO>"]),
    lang("err-character", ["<TOP !\\a>"]),
    lang("err-tuple", ["<DEFINE G (\"TUPLE\" T) <TOP .T>>", "<G 1 2 3>"]),
    lang("err-rested-tuple", ["<DEFINE F (\"TUPLE\" T) <TOP <REST .T 2>>>", "<F 1 2 3>"]),
    lang("err-too-few-args", ["<TOP>"]),
    lang("err-too-many-args", ["<TOP [1] 2>"]),
    lang("grow-unbound", ["<GROW [1 2] 1 2>"],
         "GROW is not a SUBR of this Confusion build, so TOP after GROW is not observable"),
    # --- the game's own TOP operands after FLOAD -------------------------------------------
    game("game-top-operands", [
        '<FLOAD "77loadall.mud">',
        "<LENGTH ,OBJ-UV>", "<UTYPE ,OBJ-UV>",
        "<LENGTH <TOP ,OBJ-UV>>", "<UTYPE <TOP ,OBJ-UV>>", "<TYPE <TOP ,OBJ-UV>>",
        "<==? <TOP ,OBJ-UV> <BACK ,OBJ-UV 20>>",
        "<LENGTH ,SCRSTR>", "<LENGTH <TOP ,SCRSTR>>", "<TYPE <TOP ,SCRSTR>>",
        "<==? <TOP ,SCRSTR> <BACK ,SCRSTR 5>>",
        "<TYPE ,PRSVEC>", "<LENGTH ,PRSVEC>",
        "<==? <TOP <REST ,PRSVEC>> ,PRSVEC>", "<==? <TOP <REST ,PRSVEC 2>> ,PRSVEC>",
        "<TYPE <TOP ,INCHAN>>", "<LENGTH <TOP ,INCHAN>>", "<1 <TOP ,INCHAN>>"],
        "the game's TOP operands (77rooms.mud:1249, 77np.mud:354, 77rooms.mud:1545) after "
        "FLOAD (no SAVE-IT)"),
]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("output", type=Path)
    ap.add_argument("--shim-src", type=Path, default=psr.DEFAULT_SHIM_SRC)
    a = ap.parse_args()
    if not psr.EXE.is_file() or not psr.GAME.is_dir():
        raise SystemExit("missing pinned mdli or game sources")
    before = psr.sha256_file(psr.EXE)
    if before != PINNED_SHA256:
        raise SystemExit(f"mdli sha256 {before} != pinned {PINNED_SHA256}")
    base = Path(os.environ.get("TMPDIR", "/tmp")) / "top-probes"
    base.mkdir(parents=True, exist_ok=True)
    shim = psr.build_shim(a.shim_src, Path(tempfile.mkdtemp(prefix="shim-", dir=base)))
    rows = []
    for c in CASES:
        row = psr.run_case(c, base, shim)
        row["forms"] = c["forms"]
        row["cwd_kind"] = c["cwd"]
        for k in ("files_before", "files_changed", "changed_file_text"):
            row.pop(k, None)   # game-copy manifests are large and not under test here
        rows.append(row)
    head = subprocess.run(["git", "-C", str(psr.UPSTREAM_ROOT), "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    res = {
        "schema_version": 1,
        "kind": "m4-top-reference",
        "engine": "confusion-patched-1977",
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "interpreter": ".cache/build/confusion_patched/mdli",
        "interpreter_sha256_before": before,
        "interpreter_sha256_after": psr.sha256_file(psr.EXE),
        "upstream_mdlzork_checked_out": head,
        "fixed_epoch": psr.EPOCH, "tz": "UTC",
        "shim_src_sha256": psr.sha256_file(a.shim_src),
        "protocol": "scripts/probe_top_reference.py (module docstring)",
        "cases": rows,
    }
    a.output.write_text(json.dumps(res, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
