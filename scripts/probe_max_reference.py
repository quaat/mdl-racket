#!/usr/bin/env python3
"""Pinned-Confusion reference probes for M4 S5a: the MAX SUBR (issue #122;
78melee.mud:447-448 `<SET DEF <MAX 0 <- .DEF 1>>>` / `<MAX 0 <- .DEF 2>>`
(BLOW, combat wound recovery), 77rooms.mud:741 `<ACCESS .CH <MAX 0 <- .FL 1>>>`
(RECORD's PRINTO branch, unreachable under ADR-0055)).

Read-only reference investigation. Nothing here is runtime code, and the game
sources under .cache/upstream are never written.

Usage (sandbox; TMPDIR must be writable):
    python3 -I scripts/probe_max_reference.py OUT.json [--shim-src C]

Protocol (run_case of scripts/probe_session_reference.py):
  * one pinned mdli process per case, pipe mode, fixed clock (LD_PRELOAD of
    scripts/reference/fixed_time.c, MDL_FIXED_EPOCH=250776000, TZ=UTC);
  * every case runs in a fresh empty directory under $TMPDIR/max-probes
    (bare interpreter; MAX is a primitive, no game load is needed);
  * every case ends with <QUIT>; error cases hold one failing form so that a
    LISTENING-AT-LEVEL 2 never hides a later result;
  * a FLOAT near the host DBL_MAX/DBL_MIN is never printed (R6: printing
    <MIN> segfaults this build); its TYPE, comparisons and CHTYPE are
    observed instead;
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


def melee(n):
    return lang(f"melee-def-{n}".replace("-" + "-", "-neg"),
                [f"<SET DEF {n}>", "<MAX 0 <- .DEF 1>>", "<MAX 0 <- .DEF 2>>",
                 "<TYPE <MAX 0 <- .DEF 1>>>", "<SET DEF <MAX 0 <- .DEF 1>>>", ".DEF",
                 f"<SET DEF {n}>", "<SET DEF <MAX 0 <- .DEF 2>>>", ".DEF"],
                f"78melee.mud:447-448 with DEF = {n} (DEF is DECLed FIX, 78melee.mud:381)")


CASES = [
    # --- two FIX arguments -------------------------------------------------------
    lang("fix-two", ["<MAX 1 2>", "<MAX 2 1>", "<TYPE <MAX 1 2>>", "<MAX 3 3>",
                     "<TYPE <MAX 3 3>>", "<MAX 0 0>"],
         "two FIX in both orders and equal operands"),
    lang("fix-negative", ["<MAX -1 -2>", "<MAX -2 -1>", "<MAX -5 0>", "<MAX 0 -5>",
                          "<MAX -7 -7>", "<MAX -1 1>"],
         "negative FIX operands"),
    lang("fix-many", ["<MAX 1 5 3>", "<MAX 5 1 3>", "<MAX 1 3 5>", "<MAX 4 4 4 4>",
                      "<MAX -3 -9 -1 -4>", "<MAX 1 2 3 4 5 6 7 8 9 10>"],
         "three or more FIX arguments"),
    lang("single", ["<MAX 7>", "<TYPE <MAX 7>>", "<MAX -7>", "<MAX 2.5>",
                    "<TYPE <MAX 2.5>>", "<MAX 0>"],
         "a single argument is returned unchanged in TYPE"),
    # --- FIX/FLOAT contagion ----------------------------------------------------------
    lang("mixed", ["<MAX 1 2.0>", "<TYPE <MAX 1 2.0>>", "<MAX 2.0 1>",
                   "<TYPE <MAX 2.0 1>>", "<MAX 3 2.0>", "<TYPE <MAX 3 2.0>>",
                   "<MAX 2.0 3>", "<TYPE <MAX 2.0 3>>", "<MAX 2 2.0>",
                   "<TYPE <MAX 2 2.0>>", "<MAX 2.0 2>", "<TYPE <MAX 2.0 2>>"],
         "one FLOAT makes the result FLOAT, whichever operand is larger"),
    lang("mixed-many", ["<MAX 1 2 3.0>", "<MAX 5 1.0 3>", "<TYPE <MAX 5 1.0 3>>",
                        "<MAX 1.0 5 3>", "<TYPE <MAX 1.0 5 3>>", "<MAX -1 -2.5>",
                        "<TYPE <MAX -1 -2.5>>"],
         "contagion with three arguments and negatives"),
    lang("float-float", ["<MAX 1.5 2.5>", "<MAX 2.5 1.5>", "<TYPE <MAX 1.5 2.5>>",
                         "<MAX -1.5 -2.5>", "<MAX 0.5 0.5>", "<MAX 1.0 2.0 0.5>"],
         "FLOAT operands only"),
    lang("float-negative", ["<TYPE <MAX -1.5 -2.5>>", "<CHTYPE <MAX -1.5 -2.5> FIX>",
                            "<G? <MAX -1.5 -2.5> 0>", "<==? <MAX -1.5 -2.5> <MAX>>",
                            "<MAX -2.5 -1.5>", "<MAX -1.5>", "<MAX -1.5 -2>",
                            "<MAX -2 -1.5>", "<CHTYPE <MAX 0.0 -1.0> FIX>",
                            "<CHTYPE 0.0 FIX>", "<MAX -1.0 0.5>", "<MAX 0.5 -1.0>"],
         "all-FLOAT negative operands: the zero-argument DBL_MIN seed leaks into the result"),
    lang("min-float-positive", ["<MIN 1.5 2.5>", "<MIN 2.5 1.5>", "<MIN -1.5 -2.5>",
                                "<MIN 1.5>"],
         "MIN with all-FLOAT operands, for comparison with float-negative"),
    lang("min-mixed-compare", ["<MIN 1 2.0>", "<TYPE <MIN 1 2.0>>", "<MIN 3 2.0>",
                               "<MIN 2 2.0>", "<TYPE <MIN 2 2.0>>"],
         "MIN on the same operands, for the symmetric contract"),
    # --- 36-bit boundaries --------------------------------------------------------
    lang("fix-36bit-boundaries", ["<MAX 34359738367 0>", "<MAX 0 34359738367>",
                                  "<MAX -34359738368 0>", "<MAX -34359738368 -34359738367>",
                                  "<MAX 34359738367 -34359738368>",
                                  "<MAX 34359738367 34359738367>",
                                  "<MAX 34359738368 0>", "<MAX -34359738369 0>"],
         "+-2^35, 2^35-1 and one beyond (Confusion FIX is a 64-bit host integer)"),
    # --- zero arguments ---------------------------------------------------------------
    lang("zero", ["<TYPE <MAX>>", "<CHTYPE <MAX> FIX>", "<G? <MAX> 0>",
                  "<L? <MAX> 0>", "<0? <MAX>>", "<==? <MAX> 0.0>",
                  "<MAX <MAX> -1>", "<MAX <MAX> 1>", "<L? <MAX> <MIN>>",
                  "<CHTYPE <MIN> FIX>"],
         "the zero-argument identity, not printed (it is the host DBL_MIN per R6)"),
    lang("zero-print", ["<MAX>"], "printing <MAX> itself (R6 recorded 0.0000000)"),
    # --- non-numeric arguments: one failing form per case ------------------------
    lang("err-string", ['<MAX 1 "A">'], "FIX vs STRING"),
    lang("err-string-first", ['<MAX "A" 1>'], "STRING first"),
    lang("err-atom", ["<MAX 1 A>"], "FIX vs ATOM (an ATOM evaluates to itself)"),
    lang("err-quoted-atom", ["<MAX 1 'A>"], "FIX vs quoted ATOM"),
    lang("err-list", ["<MAX 1 '(1 2)>"], "FIX vs LIST"),
    lang("err-false", ["<MAX 1 <>>"], "FIX vs FALSE"),
    lang("err-character", ["<MAX 1 !\\A>"], "FIX vs CHARACTER"),
    lang("err-single-atom", ["<MAX 'A>"], "a single non-number"),
    lang("err-min-string", ['<MIN 1 "A">'], "MIN's error for comparison"),
    # --- the game's own expressions -----------------------------------------------
    melee(-3), melee(0), melee(1), melee(2), melee(3), melee(5),
    lang("record-access-shape", ["<SET FL 0>", "<MAX 0 <- .FL 1>>",
                                 "<SET FL 1>", "<MAX 0 <- .FL 1>>",
                                 "<SET FL 100>", "<MAX 0 <- .FL 1>>"],
         "77rooms.mud:741 argument shape (the OPEN PRINTO branch itself is not run)"),
]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("output", type=Path)
    ap.add_argument("--shim-src", type=Path, default=psr.DEFAULT_SHIM_SRC)
    a = ap.parse_args()
    if not psr.EXE.is_file():
        raise SystemExit("missing pinned mdli")
    before = psr.sha256_file(psr.EXE)
    if before != PINNED_SHA256:
        raise SystemExit(f"mdli sha256 {before} != pinned {PINNED_SHA256}")
    base = Path(os.environ.get("TMPDIR", "/tmp")) / "max-probes"
    base.mkdir(parents=True, exist_ok=True)
    shim = psr.build_shim(a.shim_src, Path(tempfile.mkdtemp(prefix="shim-", dir=base)))
    rows = []
    for c in CASES:
        row = psr.run_case(c, base, shim)
        row["forms"] = c["forms"]
        row["cwd_kind"] = c["cwd"]
        for k in ("files_before", "files_changed", "changed_file_text"):
            row.pop(k, None)
        rows.append(row)
    head = subprocess.run(["git", "-C", str(psr.UPSTREAM_ROOT), "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    res = {
        "schema_version": 1,
        "kind": "m4-max-reference",
        "engine": "confusion-patched-1977",
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "interpreter": ".cache/build/confusion_patched/mdli",
        "interpreter_sha256_before": before,
        "interpreter_sha256_after": psr.sha256_file(psr.EXE),
        "upstream_mdlzork_checked_out": head,
        "fixed_epoch": psr.EPOCH, "tz": "UTC",
        "shim_src_sha256": psr.sha256_file(a.shim_src),
        "protocol": "scripts/probe_max_reference.py (module docstring)",
        "cases": rows,
    }
    a.output.write_text(json.dumps(res, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
