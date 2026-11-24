#!/usr/bin/env python3
"""Pinned-Confusion reference probes for M4 S5b: the TYPE of applicable
values (frontier F4, SWORD 77act1.mud:1899-1906,
`<TYPE? ,SWORD-GLOW NOFFSET>`; the same shape for ROBBER at 77act1.mud:1529,
1564; FUNCTION-PRINT 77defs.mud:503-513 and the CEVENT code
77rooms.mud:1642-1649 test NOFFSET the same way).

Read-only reference investigation. Nothing here is runtime code, and the game
sources under .cache/upstream are never written.

Usage (sandbox; TMPDIR must be writable):
    python3 -I scripts/probe_function_type_reference.py OUT.json [--shim-src C]

Protocol (run_case of scripts/probe_session_reference.py):
  * one pinned mdli process per case, pipe mode, fixed clock (LD_PRELOAD of
    scripts/reference/fixed_time.c, MDL_FIXED_EPOCH=250776000, TZ=UTC);
  * language cases ("cwd": "empty") run in a fresh empty directory under
    $TMPDIR/function-type-probes; game cases run in a fresh copy of
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

# The ROOT names this runtime binds to a host builtin (builtin-table of
# mdl/runtime/core.rkt at main adbe410, plus MAX from M4 S5a, ABS from
# M4 S8 and IMAGE, SLEEP, TIME from M4 S9) plus FLOAD
# (bound by the loader).
BUILTIN_NAMES = (
    "TYPE TYPE? AND? EMPTY? LENGTH? LVAL GVAL VALUE SET SETG GASSIGNED? ASSIGNED? "
    "MANIFEST DECL? GUNASSIGN PRIMTYPE TYPEPRIM NEWTYPE CHTYPE CHUTYPE FIX FLOAT BITS "
    "GETBITS PUTBITS ANDB ORB XORB EQVB LSH UTYPE LIST VECTOR IVECTOR UVECTOR IUVECTOR "
    "STRING ISTRING GC BLOAT ASCII UNPARSE PRINTSTRING SUBSTRUC TERPRI CRLF RESET PRINC "
    "PRIN1 READSTRING ERROR ERRET EVENT HANDLER OFF ON SAVE RESTORE QUIT OPEN REP "
    "INT-LEVEL ENABLE DISABLE MAPF MAPR MAPRET MAPSTOP MAPLEAVE APPLY LENGTH REST BACK "
    "TOP NTH PUT GET MEMQ MEMBER PUTREST FORM EXPAND ATOM MOBLIST BLOCK ENDBLOCK ROOT "
    "LOOKUP INSERT REMOVE OBLIST? PNAME SPNAME + - * / MIN MAX ABS IMAGE SLEEP TIME RANDOM GETTIMEDATE MOD 0? 1? "
    "L? L=? G? G=? =? N=? ==? N==? FLOAD").split()
# The FSUBR-like names the compiler handles by PNAME (root-internal-names).
SPECIAL_NAMES = ("QUOTE DEFINE DEFMAC FUNCTION PROG REPEAT RETURN AGAIN UNWIND GDECL "
                 "COND AND OR NOT").split()


def lang(name, forms, note=""):
    return {"name": name, "cwd": "empty", "note": note,
            "forms": forms, "input": "\n".join(forms) + "\n" + Q}


def game(name, forms, note=""):
    return {"name": name, "cwd": "game", "note": note,
            "forms": forms, "input": "\n".join(forms) + "\n" + Q}


CASES = [
    # --- DEFINEd FUNCTIONs -------------------------------------------------------
    lang("define-function",
         ["<DEFINE F (X) <+ .X 1>>", "<TYPE ,F>", "<PRIMTYPE ,F>", "<TYPE? ,F FUNCTION>",
          "<TYPE? ,F SUBR FSUBR FUNCTION>", "<TYPE? ,F SUBR FSUBR>", "<TYPE? ,F MACRO>",
          "<NEWTYPE NOFFSET WORD>", "<TYPE? ,F NOFFSET>",
          "<COND (<TYPE? ,F NOFFSET> ,F) (F)>",
          "<==? <TYPE ,F> FUNCTION>", "<APPLICABLE? ,F>",
          "<DECL? ,F FUNCTION>", "<DECL? ,F <OR ATOM FALSE NOFFSET>>", "<F 4>",
          "<APPLY ,F 4>", "<MAPF ,LIST ,F (1 2 3)>"],
         "SWORD's test: a DEFINEd FUNCTION is TYPE FUNCTION, never NOFFSET"),
    lang("define-shapes",
         ["<DEFINE G () 1>", "<TYPE ,G>",
          "<DEFINE H (X) #DECL ((X) FIX) <+ .X 1>>", "<TYPE ,H>",
          "<DEFINE K (X \"OPTIONAL\" (Y 2) \"AUX\" (Z 3)) <+ .X .Y .Z>>", "<TYPE ,K>", "<K 1>",
          "<DEFINE T1 (\"TUPLE\" A) .A>", "<TYPE ,T1>",
          "<DEFINE A1 ACT (X) <RETURN .X .ACT>>", "<TYPE ,A1>", "<A1 7>",
          "<DEFINE N1 (X \"NAME\" ACT) <RETURN .X .ACT>>", "<TYPE ,N1>",
          "<DEFINE Q1 ('X) .X>", "<TYPE ,Q1>", "<Q1 <+ 1 2>>"],
         "every DEFINE shape (no args, DECL, OPTIONAL/AUX, TUPLE, activation, quoted) is FUNCTION"),
    lang("function-identity",
         ["<DEFINE F (X) .X>", "<==? ,F ,F>", "<SETG F2 ,F>", "<==? ,F ,F2>", "<=? ,F ,F2>",
          "<TYPE ,F2>", "<==? ,F <GVAL F>>", "<DEFINE G (X) .X>", "<==? ,F ,G>", "<=? ,F ,G>",
          "<SET L ,F>", "<==? .L ,F>"],
         "GVAL/SETG keep the same object; two equal bodies are =? but not ==?"),
    lang("function-literal",
         ["<TYPE <FUNCTION (X) .X>>", "<PRIMTYPE <FUNCTION (X) .X>>",
          "<SETG FL <FUNCTION (X) .X>>", "<TYPE ,FL>", "<FL 5>"]),
    lang("function-structure",
         ["<DEFINE F (X) <+ .X 1>>", "<LENGTH ,F>", "<1 ,F>", "<2 ,F>", "<EMPTY? ,F>",
          "<SET L <CHTYPE ,F LIST>>", "<TYPE .L>", ".L", "<==? <REST .L> <REST <CHTYPE ,F LIST>>>",
          "<SET F3 <CHTYPE .L FUNCTION>>", "<TYPE .F3>", "<APPLY .F3 4>",
          "<CHTYPE '((Y) <* .Y 2>) FUNCTION>", "<APPLY <CHTYPE '((Y) <* .Y 2>) FUNCTION> 5>"],
         "FUNCTION is PRIMTYPE LIST: its storage is the formals+body LIST"),
    lang("function-printing",
         ["<DEFINE F (X) <+ .X 1>>", ",F", "<UNPARSE ,F>", "<PRIN1 ,F>", "<PRINC ,F>"]),
    lang("function-uvector",
         ["<DEFINE F (X) .X>", "<DEFINE G (X) .X>", "<SET U <UVECTOR ,F ,G>>", "<UTYPE .U>",
          "<TYPE <1 .U>>"]),
    # --- MACRO -----------------------------------------------------------------------
    lang("macro",
         ["<DEFMAC M () <FORM + 1 2>>", "<TYPE ,M>", "<PRIMTYPE ,M>", "<TYPE? ,M MACRO>",
          "<TYPE? ,M FUNCTION>", "<APPLICABLE? ,M>", "<M>"]),
    # --- built-in SUBRs and FSUBRs --------------------------------------------------------
    lang("builtin-subr",
         ["<TYPE ,+>", "<PRIMTYPE ,+>", "<TYPE? ,+ SUBR>", "<TYPE? ,+ FUNCTION>",
          "<APPLICABLE? ,+>", "<DECL? ,+ SUBR>", "<==? ,+ ,+>", "<SETG PLUS ,+>",
          "<==? ,PLUS ,+>", "<TYPE ,PLUS>", "<PLUS 1 2>", "<TYPEPRIM SUBR>",
          "<TYPEPRIM FSUBR>", "<TYPEPRIM FUNCTION>", "<TYPEPRIM MACRO>"]),
    lang("builtin-subr-types", [f"<TYPE ,{n}>" for n in BUILTIN_NAMES],
         "TYPE of every ROOT name bound to a host builtin in this runtime (and FLOAD)"),
    lang("special-form-types", [f"<TYPE ,{n}>" for n in SPECIAL_NAMES],
         "TYPE of the names this runtime's compiler handles by PNAME"),
    lang("fsubr", ["<TYPE ,COND>", "<PRIMTYPE ,COND>", "<TYPE? ,COND SUBR FSUBR>",
                   "<APPLICABLE? ,COND>", "<GASSIGNED? COND>"]),
    lang("applicable-other",
         ["<APPLICABLE? 3>", "<APPLICABLE? FOO>", "<APPLICABLE? (1 2)>", "<APPLICABLE? <>>"]),
    lang("subr-printing", [",+", "<UNPARSE ,+>"]),
    # --- refusals (one failing form each) ----------------------------------------------
    lang("err-chtype-subr-list", ["<CHTYPE ,+ LIST>"]),
    lang("err-decl-applicable", ["<DEFINE F (X) .X>", "<DECL? ,F APPLICABLE>"],
         "APPLICABLE is not a ROOT atom at startup here (SEMANTICS: root inventory)"),
    lang("err-chtype-vector-function", ["<CHTYPE [1 2] FUNCTION>"]),
    lang("err-apply-fix-function", ["<CHTYPE 1 FUNCTION>"]),
    # --- the game, after FLOAD (no SAVE-IT) ---------------------------------------------
    game("game-sword-glow", [
        '<FLOAD "77loadall.mud">',
        "<TYPE ,SWORD-GLOW>", "<PRIMTYPE ,SWORD-GLOW>", "<TYPE? ,SWORD-GLOW NOFFSET>",
        "<TYPEPRIM NOFFSET>", "<TYPE ,SWORD>", "<TYPE ,ROBBER>", "<TYPE? ,ROBBER NOFFSET>",
        "<TYPE ,RDCOM>", "<TYPE ,SWORD-DEMON>", "<HACTION ,SWORD-DEMON>",
        "<TYPE <HACTION ,SWORD-DEMON>>", "<OTVAL <FIND-OBJ \"SWORD\">>",
        "<COND (<TYPE? ,SWORD-GLOW NOFFSET> ,SWORD-GLOW) (SWORD-GLOW)>",
        "<==? ,SWORD-GLOW ,SWORD-GLOW>", "<TYPE ,FLOAD>"],
        "SWORD-GLOW is a DEFINEd FUNCTION; NOFFSET is <NEWTYPE NOFFSET WORD> (77defs.mud:4)"),
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
    base = Path(os.environ.get("TMPDIR", "/tmp")) / "function-type-probes"
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
        "kind": "m4-function-type-reference",
        "engine": "confusion-patched-1977",
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "interpreter": ".cache/build/confusion_patched/mdli",
        "interpreter_sha256_before": before,
        "interpreter_sha256_after": psr.sha256_file(psr.EXE),
        "upstream_mdlzork_checked_out": head,
        "fixed_epoch": psr.EPOCH, "tz": "UTC",
        "shim_src_sha256": psr.sha256_file(a.shim_src),
        "protocol": "scripts/probe_function_type_reference.py (module docstring)",
        "builtin_names": BUILTIN_NAMES,
        "special_names": SPECIAL_NAMES,
        "cases": rows,
    }
    a.output.write_text(json.dumps(res, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
