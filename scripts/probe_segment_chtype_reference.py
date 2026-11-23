#!/usr/bin/env python3
"""Pinned-Confusion reference probes for M4 S2: CHTYPE to SEGMENT and the
evaluation of runtime-built SEGMENT objects (frontier F1, the INSERT-OBJECT /
TAKE-OBJECT macros of 77defs.mud:332-342).

Read-only reference investigation. Nothing here is runtime code, and the game
sources under .cache/upstream are never written.

Usage (sandbox; TMPDIR must be writable):
    python3 -I scripts/probe_segment_chtype_reference.py OUT.json [--shim-src C]

Protocol (run_case of scripts/probe_session_reference.py):
  * one pinned mdli process per case, pipe mode, fixed clock (LD_PRELOAD of
    scripts/reference/fixed_time.c, MDL_FIXED_EPOCH=250776000, TZ=UTC);
  * language cases ("cwd": "empty") run in a fresh empty directory under
    $TMPDIR/segment-chtype-probes; game cases run in a fresh copy of
    mdlzork_771212/patched_confusion (SAVEFILE/ZORK.SAVE removed);
  * every case ends with <QUIT>; error cases hold one failing form so that a
    LISTENING-AT-LEVEL 2 never hides a later result;
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
    # --- TYPE, PRIMTYPE, TYPEPRIM --------------------------------------------
    lang("type-of-chtype", ["<TYPE <CHTYPE <FORM A B> SEGMENT>>",
                            "<PRIMTYPE <CHTYPE <FORM A B> SEGMENT>>",
                            "<TYPEPRIM SEGMENT>"]),
    lang("reader-segment-is-same-type", ["<TYPE '!.X>", "<PRIMTYPE '!.X>", "<1 '!.X>", "<2 '!.X>",
                                         "<1 '!,X>", "<TYPE '!<A B C>>", "<LENGTH '!<A B C>>",
                                         "<=? '!<A B> <CHTYPE <FORM A B> SEGMENT>>"],
         "the reader's !<...>/!.X objects are SEGMENTs over the FORM's elements"),
    # --- identity and sharing --------------------------------------------------
    lang("identity-sharing", ["<SET F <FORM A B>>", "<SET S <CHTYPE .F SEGMENT>>",
                              "<==? .S .F>", "<=? .S .F>",
                              "<==? <CHTYPE .S FORM> .F>", "<=? <CHTYPE .S FORM> .F>",
                              "<==? <CHTYPE .S LIST> <CHTYPE .F LIST>>",
                              "<==? <CHTYPE .S SEGMENT> .S>",
                              "<==? <CHTYPE .F SEGMENT> .S>",
                              "<PUT .S 2 C>", ".F", "<PUT .F 1 D>", ".S",
                              "<LENGTH .S>", "<TYPE <REST .S>>"],
         "CHTYPE shares the LIST cells: PUT through either view is visible in both"),
    # --- printing (recorded only) ---------------------------------------------
    lang("print-forms", ["<CHTYPE <FORM REST '(1 2 3)> SEGMENT>",
                         "<CHTYPE <FORM LVAL X> SEGMENT>",
                         "<CHTYPE <FORM GVAL X> SEGMENT>",
                         "<CHTYPE () SEGMENT>",
                         "<PRIN1 <CHTYPE <FORM A B> SEGMENT>>",
                         "<UNPARSE <CHTYPE <FORM A B> SEGMENT>>"]),
    # --- other LIST-primtype sources, and back ---------------------------------
    lang("list-primtype-sources", ["<CHTYPE (A B) SEGMENT>", "<TYPE <CHTYPE (A B) SEGMENT>>",
                                   "<CHTYPE <> SEGMENT>", "<TYPE <CHTYPE <> SEGMENT>>",
                                   "<NEWTYPE FOO LIST>", "<CHTYPE <CHTYPE (A) FOO> SEGMENT>",
                                   "<CHTYPE <CHTYPE (A B) SEGMENT> FOO>",
                                   "<CHTYPE <CHTYPE (A B) SEGMENT> FORM>",
                                   "<CHTYPE <CHTYPE (A B) SEGMENT> LIST>",
                                   "<CHTYPE <CHTYPE <FORM A> SEGMENT> FALSE>"]),
    lang("err-vector", ["<CHTYPE [1 2] SEGMENT>"]),
    lang("err-string", ["<CHTYPE \"AB\" SEGMENT>"]),
    lang("err-uvector", ["<CHTYPE ![1 2!] SEGMENT>"]),
    lang("err-fix", ["<CHTYPE 1 SEGMENT>"]),
    lang("err-atom", ["<CHTYPE FOO SEGMENT>"]),
    lang("err-segment-to-vector", ["<CHTYPE <CHTYPE <FORM A> SEGMENT> VECTOR>"]),
    # --- evaluation of a runtime SEGMENT inside structures --------------------
    lang("eval-list-splice", ["<SET L (6 7 8)>", "<SET S <CHTYPE <FORM LVAL L> SEGMENT>>",
                              "<EVAL <LIST 1 .S 2>>",
                              "<SET R <EVAL <LIST 0 .S>>>", "<==? <REST .R> .L>",
                              "<SET R2 <EVAL <LIST .S>>>", "<==? .R2 .L>",
                              "<SET R3 <EVAL <LIST .S 9>>>", "<==? <REST .R3 3> .L>",
                              "<EVAL <LIST .S .S>>"],
         "non-final copies; a final LIST segment shares the payload's cells"),
    lang("eval-list-tail-mutation", ["<SET L (6 7 8)>",
                                     "<SET R <EVAL <LIST 0 <CHTYPE <FORM LVAL L> SEGMENT>>>>",
                                     "<PUT .L 1 60>", ".R",
                                     "<SET R4 <EVAL <LIST <CHTYPE <FORM LVAL L> SEGMENT> 0>>>",
                                     "<PUT .L 2 70>", ".R4"]),
    lang("eval-vector-uvector", ["<SET L (6 7 8)>", "<SET S <CHTYPE <FORM LVAL L> SEGMENT>>",
                                 "<EVAL <VECTOR 0 .S 9>>", "<EVAL <VECTOR .S>>",
                                 "<EVAL <UVECTOR 0 .S>>"]),
    lang("eval-form-args", ["<SET L (6 7 8)>", "<SET S <CHTYPE <FORM LVAL L> SEGMENT>>",
                            "<EVAL <FORM + 1 .S>>", "<EVAL <FORM LIST 1 .S>>",
                            "<==? <REST <EVAL <FORM LIST 1 .S>>> .L>",
                            "<EVAL <FORM LIST .S>>", "<==? <EVAL <FORM LIST .S>> .L>",
                            "<EVAL <FORM PUT <FORM LVAL L> 1 .S>>"],
         "SUBR argument assembly splices; the LIST SUBR copies"),
    lang("eval-function-args", ["<SET L (6 7 8)>", "<SET S <CHTYPE <FORM LVAL L> SEGMENT>>",
                                "<DEFINE FT (\"TUPLE\" TT) .TT>",
                                "<EVAL <FORM FT 1 .S>>",
                                "<DEFINE F3 (A B C) (.A .B .C)>",
                                "<EVAL <FORM F3 .S>>"],
         "interpreted FUNCTION argument binding (recorded M2 D2 deviation area)"),
    lang("eval-chtype-list-source", ["<SET L (1 2)>",
                                     "<EVAL <LIST 0 <CHTYPE (LVAL L) SEGMENT>>>",
                                     "<EVAL <LIST 0 <CHTYPE <FORM LIST> SEGMENT> 3>>",
                                     "<EVAL <LIST 0 <CHTYPE <FORM VECTOR 4 5> SEGMENT>>>",
                                     "<EVAL <LIST 0 <CHTYPE <FORM STRING \"ab\"> SEGMENT>>>"]),
    lang("plain-element-value-stored", ["<SET L (6 7 8)>",
                                        "<SET S <CHTYPE <FORM LVAL L> SEGMENT>>",
                                        "<SET P <LIST 1 .S>>", "<TYPE <2 .P>>", "<==? <2 .P> .S>",
                                        "<SET Q (1 <CHTYPE <FORM LVAL L> SEGMENT>)>",
                                        "<TYPE <2 .Q>>", "<EVAL .Q>"],
         "a SEGMENT that is the VALUE of an element is stored; re-EVAL of that LIST splices"),
    lang("err-standalone-eval", ["<SET L (6 7 8)>", "<EVAL <CHTYPE <FORM LVAL L> SEGMENT>>"]),
    lang("err-nonstructured-payload", ["<EVAL <LIST 0 <CHTYPE <FORM + 1 2> SEGMENT>>>"]),
    # --- an INSERT-OBJECT-shaped DEFMAC, standalone ---------------------------
    lang("defmac-insert-shape", ["<DEFMAC INS ('OBJ 'BOX) <FORM PUT .BOX 1 (.OBJ <CHTYPE <FORM 1 .BOX> SEGMENT>)>>",
                                 "<SET V [(A B)]>", "<SET OLD <1 .V>>",
                                 "<EXPAND '<INS Z .V>>",
                                 "<MAPF ,LIST ,TYPE <4 <EXPAND '<INS Z .V>>>>",
                                 "<INS Z .V>", "<1 .V>", "<==? <REST <1 .V>> .OLD>",
                                 "<DEFINE USE (W) <INS Y .W>>", "<USE .V>", "<1 .V>",
                                 "<==? <REST <1 .V> 2> .OLD>"]),
    # --- the game's own macros (77defs.mud:332-342) ---------------------------
    game("game-insert-take-object", [
        '<FLOAD "77loadall.mud">',
        '<PROG () <SET R <FIND-ROOM "LROOM">> <SET O <FIND-OBJ "ADVER">> <SET W ,PLAYER> T>',
        "<EXPAND '<INSERT-OBJECT .O .R>>",
        "<EXPAND '<TAKE-OBJECT .O .W>>",
        "<MAPF ,LIST ,TYPE <4 <EXPAND '<INSERT-OBJECT .O .R>>>>",
        "<PROG () <SET B <ROBJS .R>> T>", "<MAPF ,LIST ,OID .B>",
        "<PROG () <INSERT-OBJECT .O .R> T>",
        "<MAPF ,LIST ,OID <ROBJS .R>>", "<==? <REST <ROBJS .R>> .B>", "<==? <OROOM .O> .R>",
        "<PROG () <SET A <AOBJS .W>> T>", "<MAPF ,LIST ,OID .A>",
        "<PROG () <TAKE-OBJECT .O .W> T>",
        "<MAPF ,LIST ,OID <AOBJS .W>>", "<==? <REST <AOBJS .W>> .A>", "<OROOM .O>",
        "<PROG () <SET A2 <AOBJS .W>> <TAKE-OBJECT <FIND-OBJ \"LAMP\"> .W> T>",
        "<MAPF ,LIST ,OID <AOBJS .W>>", "<==? <REST <AOBJS .W>> .A2>"],
        "expansions and effects of INSERT-OBJECT/TAKE-OBJECT after FLOAD (no SAVE-IT; "
        "WINNER is unbound before START, so ,PLAYER is passed explicitly)"),
]

# The runtime has no EVAL SUBR (the game reaches EVAL only in the ILO
# anti-tamper path, 77act1.mud:20), but it evaluates macro expansions, which
# is how INSERT-OBJECT's LIST is evaluated. A DEFMAC with an evaluated formal
# returning it, <DEFMAC EV (X) .X>, evaluates its argument and then
# evaluates that value as the expansion: the same two steps as <EVAL x>.
# Each EVAL case gets a "-via-macro" twin so the tests can use EV and still
# compare with a recorded reference.
EV = "<DEFMAC EV (X) .X>"
EVAL_CASES = {"eval-list-splice", "eval-list-tail-mutation", "eval-vector-uvector",
              "eval-form-args", "eval-function-args", "eval-chtype-list-source",
              "plain-element-value-stored", "err-standalone-eval", "err-nonstructured-payload"}
for _c in list(CASES):
    if _c["name"] in EVAL_CASES:
        _forms = [EV] + [f.replace("<EVAL ", "<EV ") for f in _c["forms"]]
        CASES.append(lang(_c["name"] + "-via-macro", _forms,
                          "EVAL replaced by the macro EV (see EV above)"))


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
    base = Path(os.environ.get("TMPDIR", "/tmp")) / "segment-chtype-probes"
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
        "kind": "m4-segment-chtype-reference",
        "engine": "confusion-patched-1977",
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "interpreter": ".cache/build/confusion_patched/mdli",
        "interpreter_sha256_before": before,
        "interpreter_sha256_after": psr.sha256_file(psr.EXE),
        "upstream_mdlzork_checked_out": head,
        "fixed_epoch": psr.EPOCH, "tz": "UTC",
        "shim_src_sha256": psr.sha256_file(a.shim_src),
        "protocol": "scripts/probe_segment_chtype_reference.py (module docstring)",
        "cases": rows,
    }
    a.output.write_text(json.dumps(res, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
