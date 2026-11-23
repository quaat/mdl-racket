#!/usr/bin/env python3
"""Pinned-Confusion reference probes for M4 S3: CHTYPE between FIX (or any
WORD-primtype value) and CHARACTER (frontier F2/F2b, FOOSTR 77np.mud:241,
`<PUT .Y 1 <CHTYPE <+ 32 <ASCII <1 .X>>> CHARACTER>>`).

Read-only reference investigation. Nothing here is runtime code, and the game
sources under .cache/upstream are never written.

Usage (sandbox; TMPDIR must be writable):
    python3 -I scripts/probe_character_chtype_reference.py OUT.json [--shim-src C]

Protocol (run_case of scripts/probe_session_reference.py):
  * one pinned mdli process per case, pipe mode, fixed clock (LD_PRELOAD of
    scripts/reference/fixed_time.c, MDL_FIXED_EPOCH=250776000, TZ=UTC);
  * language cases ("cwd": "empty") run in a fresh empty directory under
    $TMPDIR/character-chtype-probes; game cases run in a fresh copy of
    mdlzork_771212/patched_confusion (SAVEFILE/ZORK.SAVE removed);
  * every case ends with <QUIT>; error cases hold one failing form so that a
    LISTENING-AT-LEVEL 2 never hides a later result;
  * out-of-range CHARACTERs print implementation-specific bytes, so the
    boundary cases observe them through ASCII (a FIX) instead of printing;
    the few printing cases are recorded only (stdout kept as latin-1);
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


# FOOSTR and PRSTR exactly as 77np.mud:230-243 (whitespace normalised), and
# SCRSTR as 77np.mud:354, under other names so a language case can run them.
FOOSTR_DEFS = [
    "<SETG XSCRSTR <REST <ISTRING 5> 5>>",
    "<DEFINE XFOOSTR (NAM STR \"OPTIONAL\" (1ST T)) #DECL ((STR NAM) STRING (1ST) <OR ATOM FALSE>) "
    "<MAPR <> <FUNCTION (X Y) #DECL ((X Y) STRING) <COND (<AND .1ST <==? .X .NAM>> <PUT .Y 1 <1 .X>>) "
    "(<PUT .Y 1 <CHTYPE <+ 32 <ASCII <1 .X>>> CHARACTER>>)>> .NAM .STR> .STR>",
    "<DEFINE XPRSTR (ATM \"AUX\" SP) #DECL ((ATM) ATOM (SP) STRING) "
    "<XFOOSTR <SET SP <SPNAME .ATM>> <BACK ,XSCRSTR <LENGTH .SP>> <>>>",
]

CASES = [
    # --- FIX -> CHARACTER: TYPE, printing, identity ---------------------------
    lang("fix-to-character", ["<CHTYPE 65 CHARACTER>", "<TYPE <CHTYPE 65 CHARACTER>>",
                              "<PRIMTYPE <CHTYPE 65 CHARACTER>>", "<TYPEPRIM CHARACTER>",
                              "<PRIN1 <CHTYPE 65 CHARACTER>>", "<PRINC <CHTYPE 65 CHARACTER>>",
                              "<UNPARSE <CHTYPE 65 CHARACTER>>",
                              "<TYPE? <CHTYPE 98 CHARACTER> CHARACTER>",
                              "<CHTYPE 119 CHARACTER>", "<CHTYPE 32 CHARACTER>"]),
    lang("character-identity", ["<==? <CHTYPE 65 CHARACTER> !\\A>",
                                "<=? <CHTYPE 65 CHARACTER> !\\A>",
                                "<==? <CHTYPE 97 CHARACTER> <CHTYPE 97 CHARACTER>>",
                                "<==? <CHTYPE 97 CHARACTER> !\\A>",
                                "<==? <CHTYPE 97 CHARACTER> 97>",
                                "<=? <CHTYPE 97 CHARACTER> 97>",
                                "<==? <CHTYPE 119 CHARACTER> <ASCII 119>>",
                                "<==? <CHTYPE !\\A CHARACTER> !\\A>"],
         "CHARACTER equality is by code; a CHARACTER is never ==? or =? a FIX"),
    # --- CHARACTER -> FIX, ASCII equivalence ---------------------------------
    lang("character-to-fix", ["<CHTYPE !\\A FIX>", "<TYPE <CHTYPE !\\A FIX>>",
                              "<CHTYPE !\\a FIX>", "<CHTYPE <CHTYPE 119 CHARACTER> FIX>",
                              "<==? <CHTYPE !\\w FIX> <ASCII !\\w>>",
                              "<ASCII <CHTYPE 119 CHARACTER>>",
                              "<CHTYPE !\\  FIX>"]),
    # --- WORD round trips --------------------------------------------------------
    lang("character-word", ["<CHTYPE !\\A WORD>", "<TYPE <CHTYPE !\\A WORD>>",
                            "<CHTYPE <CHTYPE !\\A WORD> CHARACTER>",
                            "<==? <CHTYPE <CHTYPE !\\A WORD> CHARACTER> !\\A>",
                            "<CHTYPE <CHTYPE 65 WORD> CHARACTER>",
                            "<CHTYPE <CHTYPE <CHTYPE 65 WORD> CHARACTER> FIX>",
                            "<NEWTYPE CH WORD>", "<CHTYPE <CHTYPE 65 CH> CHARACTER>",
                            "<CHTYPE !\\A CH>", "<TYPE <CHTYPE !\\A CH>>",
                            "<CHTYPE <CHTYPE !\\A CH> CHARACTER>"]),
    # --- range: observed through ASCII (a FIX), never printed -----------------
    lang("range-through-ascii", ["<ASCII <CHTYPE 0 CHARACTER>>", "<ASCII <CHTYPE 1 CHARACTER>>",
                                 "<ASCII <CHTYPE 31 CHARACTER>>", "<ASCII <CHTYPE 126 CHARACTER>>",
                                 "<ASCII <CHTYPE 127 CHARACTER>>", "<ASCII <CHTYPE 128 CHARACTER>>",
                                 "<ASCII <CHTYPE 255 CHARACTER>>", "<ASCII <CHTYPE 256 CHARACTER>>",
                                 "<ASCII <CHTYPE -1 CHARACTER>>",
                                 "<ASCII <CHTYPE 34359738367 CHARACTER>>",
                                 "<ASCII <CHTYPE -34359738368 CHARACTER>>",
                                 "<CHTYPE <CHTYPE 300 CHARACTER> FIX>",
                                 "<CHTYPE <CHTYPE -1 CHARACTER> FIX>",
                                 "<TYPE <CHTYPE 300 CHARACTER>>"],
         "CHTYPE does not range-check: any WORD value becomes a CHARACTER and comes back unchanged"),
    lang("ascii-fix-range", ["<ASCII 127>", "<TYPE <ASCII 0>>"],
         "ASCII FIX -> CHARACTER within 0..127 (ASCII 128/256/-1 errors: M3 percent-read reference)"),
    lang("err-ascii-128", ["<ASCII 128>"]),
    lang("err-ascii-minus-1", ["<ASCII -1>"]),
    # --- printing out-of-range or control CHARACTERs (recorded only) ----------
    lang("print-code-0", ["<CHTYPE 0 CHARACTER>"]),
    lang("print-code-127", ["<CHTYPE 127 CHARACTER>"]),
    lang("print-code-128", ["<CHTYPE 128 CHARACTER>"]),
    lang("print-code-255", ["<CHTYPE 255 CHARACTER>"]),
    # --- FLOAT is PRIMTYPE WORD too (recorded) ---------------------------------
    lang("float-word-bits", ["<ASCII <CHTYPE 1.0 CHARACTER>>", "<ASCII <CHTYPE 0.0 CHARACTER>>",
                             "<TYPE <CHTYPE 0.0 CHARACTER>>", "<CHTYPE !\\A FLOAT>"],
         "FLOAT -> CHARACTER keeps the 36-bit float pattern; CHARACTER -> FLOAT reinterprets"),
    # --- the CHARACTER in STRING operations -------------------------------------
    lang("character-in-strings", ["<PROG ((S <ISTRING 3 !\\X>)) <PUT .S 1 <CHTYPE 119 CHARACTER>> .S>",
                                  "<STRING <CHTYPE 104 CHARACTER> \"i\">",
                                  "<MEMQ <CHTYPE 98 CHARACTER> \"abc\">",
                                  "<MAPF ,STRING <FUNCTION (C) <CHTYPE <+ 32 <ASCII .C>> CHARACTER>> \"WITH\">",
                                  "<PROG ((S <ISTRING 2 !\\X>)) <PUT .S 1 <CHTYPE 200 CHARACTER>> <ASCII <1 .S>>>"],
         "the last form stores code 200 in a STRING (an 8-bit byte; ASCII then reads -56)"),
    lang("foostr-prstr-shape", FOOSTR_DEFS + [
        "<MAPF ,LIST ,ASCII <BACK ,XSCRSTR 5>>",
        "<XPRSTR WITH>", "<XPRSTR AT>", "<XPRSTR MAILB>", "<XPRSTR TROLL>",
        "<XPRSTR <ATOM \"#####\">>", "<XPRSTR A-B>",
        "<MAPF ,LIST ,ASCII <BACK ,XSCRSTR 5>>",
        "<XFOOSTR \"WITH\" <ISTRING 4 !\\X>>",
        "<TYPE <1 <XPRSTR AT>>>"],
        "FOOSTR/PRSTR copied from 77np.mud:230-243 under other names; +32 maps A-Z to a-z and "
        "other ASCII 33..95 by the same offset"),
    # --- refusals -----------------------------------------------------------------
    lang("err-string-to-character", ["<CHTYPE \"A\" CHARACTER>"]),
    lang("err-list-to-character", ["<CHTYPE (65) CHARACTER>"]),
    lang("err-atom-to-character", ["<CHTYPE FOO CHARACTER>"]),
    lang("err-vector-to-character", ["<CHTYPE [65] CHARACTER>"]),
    lang("err-character-to-atom", ["<CHTYPE !\\A ATOM>"]),
    lang("err-character-to-list", ["<CHTYPE !\\A LIST>"]),
    lang("err-character-to-string", ["<CHTYPE !\\A STRING>"]),
    lang("err-too-many-args", ["<CHTYPE 65 CHARACTER FOO>"]),
    lang("err-too-few-args", ["<CHTYPE 65>"]),
    # --- the game's own PRSTR / FOOSTR after FLOAD ------------------------------
    game("game-prstr", [
        '<FLOAD "77loadall.mud">',
        "<MAPF ,LIST ,ASCII <BACK ,SCRSTR 5>>",
        '<PRSTR <CHTYPE <FIND-PREP "WITH"> ATOM>>',
        '<PRSTR <CHTYPE <FIND-PREP "AT"> ATOM>>',
        "<MAPF ,LIST ,ASCII <BACK ,SCRSTR 5>>",
        "<TYPE <1 <PRSTR MAILB!-OBJECTS>>>",
        "<PRSTR MAILB!-OBJECTS>",
        "<MAPF ,LIST ,ASCII <BACK ,SCRSTR 5>>",
        '<FOOSTR "TROLL" <ISTRING 5 !\\X>>',
        '<FOOSTR "TROLL" <ISTRING 5 !\\X> <>>'],
        "the game's PRSTR/FOOSTR/SCRSTR (77np.mud:230-243, 354) after FLOAD (no SAVE-IT)"),
    game("game-word-pname-range", [
        '<FLOAD "77loadall.mud">',
        "<DEFINE MAXC (OBL \"AUX\" (M 0) (N 0) (W ())) <MAPF <> <FUNCTION (BUCKET) "
        "<MAPF <> <FUNCTION (A) <SET N <+ .N 1>> <MAPF <> <FUNCTION (C) "
        "<COND (<G? <ASCII .C> .M> <SET M <ASCII .C>>)> "
        "<COND (<G? <ASCII .C> 95> <SET W (.A !.W)>)>> <SPNAME .A>>> .BUCKET>> .OBL> (.M .N .W)>",
        "<MAXC ,WORDS>", "<MAXC ,OBJECT-OBL>", "<MAXC ,ACTIONS>", "<MAXC ,DIRECTIONS>"],
        "PRSTR only receives ATOMs found by LOOKUP in these oblists (77np.mud:43-86, 226): "
        "(max pname character code, atom count, atoms with a code above 95). With +32 the "
        "largest FOOSTR CHTYPE argument is max + 32"),
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
    base = Path(os.environ.get("TMPDIR", "/tmp")) / "character-chtype-probes"
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
        "kind": "m4-character-chtype-reference",
        "engine": "confusion-patched-1977",
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "interpreter": ".cache/build/confusion_patched/mdli",
        "interpreter_sha256_before": before,
        "interpreter_sha256_after": psr.sha256_file(psr.EXE),
        "upstream_mdlzork_checked_out": head,
        "fixed_epoch": psr.EPOCH, "tz": "UTC",
        "shim_src_sha256": psr.sha256_file(a.shim_src),
        "protocol": "scripts/probe_character_chtype_reference.py (module docstring)",
        "cases": rows,
    }
    a.output.write_text(json.dumps(res, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
