#!/usr/bin/env python3
"""Pinned-Confusion reference probes for M4 S9: the IMAGE, SLEEP and TIME
SUBRs (issues #168, #169, #170).

Game uses: FWEEP (77act2.mud:53-58) `<IMAGE 7>` and `<OR <0? .SLP> <SLEEP
.SLP>>` (reached from the Bat Room, FLY-ME `<FWEEP 4 1>`, and BOOM-ROOM
`<FWEEP 7>`); the ATOM TIME as a do-nothing verb function (C-INT, WALK-IN, ...,
77dung.mud:2902-2916, TURN-TO :2819) and as the Strange Passage's room action
(77dung.mud:1385), applied with no arguments by APPLY-RANDOM.

Read-only reference investigation. Nothing here is runtime code, and the game
sources under .cache/upstream are never written.

Usage (sandbox; TMPDIR must be writable):
    python3 -I scripts/probe_p0prims_reference.py OUT.json [--shim-src C]

Protocol (run_case of scripts/probe_session_reference.py, as
scripts/probe_abs_reference.py):
  * one pinned mdli process per case, pipe mode, fixed clock (LD_PRELOAD of
    scripts/reference/fixed_time.c, MDL_FIXED_EPOCH=250776000, TZ=UTC; the
    shim fixes the wall clock only, so SLEEP and CPU time run normally);
  * every case runs in a fresh empty directory under $TMPDIR/p0prims-probes
    (bare interpreter; no game load is needed);
  * every case ends with <QUIT>; error cases hold one failing form so that a
    LISTENING-AT-LEVEL 2 never hides a later result;
  * each case's wall time (elapsed_seconds, host monotonic clock around the
    whole process) is recorded; SLEEP durations are read against the
    `baseline` case;
  * stdout is kept raw (latin-1), so IMAGE's control bytes are visible in the
    JSON as \\u0007 etc.; `stdout_hex_tail` repeats the last bytes in hex;
  * printed TIME values are CPU time and differ between runs; the checks use
    TYPE, G? and ==? only;
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


def lang(name, forms, note="", timeout=60):
    return {"name": name, "cwd": "empty", "note": note, "timeout": timeout,
            "forms": forms, "input": "\n".join(forms) + "\n" + Q}


FWEEP = ('<DEFINE FWEEP (NUM "OPTIONAL" (SLP 0)) #DECL ((NUM SLP) FIX) '
         '<REPEAT ((N .NUM)) <AND <0? <SET N <- .N 1>>> <RETURN>> <IMAGE 7> '
         '<OR <0? .SLP> <SLEEP .SLP>>>>')

CASES = [
    lang("baseline", ["<+ 1 1>"], "wall-time baseline for the SLEEP cases"),
    # --- IMAGE ------------------------------------------------------------------------
    lang("image-65", ["<IMAGE 65>", "<TYPE <IMAGE 66>>"],
         "printable code: writes the character, returns the FIX"),
    lang("image-7", ["<IMAGE 7>", "<TYPE <IMAGE 7>>"], "BEL (the game's code)"),
    lang("image-controls", ["<IMAGE 0>", "<IMAGE 1>", "<IMAGE 10>", "<IMAGE 13>",
                            "<IMAGE 27>", "<IMAGE 127>"],
         "control codes and DEL: raw, never ^X notation"),
    lang("image-128", ["<IMAGE 128>"], "first code above 7-bit ASCII"),
    lang("image-200", ["<IMAGE 200>"], "8-bit code"),
    lang("image-255", ["<IMAGE 255>"], "8-bit code"),
    lang("image-256", ["<IMAGE 256>"], "beyond a byte"),
    lang("image-321", ["<IMAGE 321>"], "65 + 256"),
    lang("image-negative", ["<IMAGE -1>"], "negative FIX"),
    lang("image-outchan-lval", ["<IMAGE 66 .OUTCHAN>"], "explicit channel, LVAL OUTCHAN"),
    lang("image-outchan-gval", ["<IMAGE 67 ,OUTCHAN>"], "explicit channel, GVAL OUTCHAN"),
    lang("err-image-inchan", ["<IMAGE 65 .INCHAN>"], "input channel"),
    lang("err-image-chan-fix", ["<IMAGE 65 1>"], "non-CHANNEL second argument"),
    lang("err-image-no-args", ["<IMAGE>"], "zero arguments"),
    lang("err-image-three-args", ["<IMAGE 65 .OUTCHAN 1>"], "three arguments"),
    lang("err-image-string", ['<IMAGE "A">'], "STRING"),
    lang("err-image-character", ["<IMAGE !\\A>"], "CHARACTER"),
    lang("err-image-float", ["<IMAGE 65.0>"], "FLOAT"),
    lang("err-image-false", ["<IMAGE <>>"], "FALSE"),
    lang("err-image-atom", ["<IMAGE A>"], "ATOM"),
    lang("image-applicable", ["<TYPE ,IMAGE>", "<APPLY ,IMAGE 68>"], "IMAGE as a SUBR value"),
    lang("image-fweep-no-sleep", [FWEEP, "<FWEEP 7>"],
         "77act2.mud:53 FWEEP with SLP 0 (BOOM-ROOM's <FWEEP 7>): six BELs, no SLEEP"),
    # --- SLEEP ------------------------------------------------------------------------
    lang("sleep-0", ["<SLEEP 0>", "<TYPE <SLEEP 0>>"], "zero seconds"),
    lang("sleep-1", ["<SLEEP 1>"], "one second (compare elapsed with baseline)"),
    lang("sleep-3x1", ["<SLEEP 1>", "<SLEEP 1>", "<SLEEP 1>"], "three one-second sleeps"),
    lang("sleep-float", ["<SLEEP 0.5>", "<TYPE <SLEEP 0.5>>"], "FLOAT seconds"),
    lang("sleep-float-1.5", ["<SLEEP 1.5>"], "FLOAT seconds"),
    lang("sleep-negative", ["<SLEEP -1>"], "negative FIX (manual: time is non-negative)",
         timeout=20),
    lang("sleep-negative-float", ["<SLEEP -0.5>"], "negative FLOAT", timeout=20),
    lang("sleep-pred-true", ["<SLEEP 0 T>"], "optional UNHANG argument, true"),
    lang("sleep-pred-false", ["<SLEEP 1 <>>"], "optional UNHANG argument, FALSE"),
    lang("sleep-gettimedate", ["<GETTIMEDATE>", "<SLEEP 1>", "<GETTIMEDATE>"],
         "under the fixed-clock shim the wall clock does not move across SLEEP"),
    lang("err-sleep-no-args", ["<SLEEP>"], "zero arguments"),
    lang("err-sleep-three-args", ["<SLEEP 0 T T>"], "three arguments"),
    lang("err-sleep-string", ['<SLEEP "1">'], "STRING"),
    lang("err-sleep-atom", ["<SLEEP A>"], "ATOM"),
    lang("err-sleep-false", ["<SLEEP <>>"], "FALSE"),
    lang("err-sleep-character", ["<SLEEP !\\A>"], "CHARACTER"),
    lang("err-sleep-list", ["<SLEEP '(1)>"], "LIST"),
    lang("sleep-applicable", ["<TYPE ,SLEEP>", "<APPLY ,SLEEP 0>"], "SLEEP as a SUBR value"),
    lang("sleep-fweep", [FWEEP, "<FWEEP 4 1>"],
         "77act2.mud:43 FLY-ME's <FWEEP 4 1>: three BELs and three one-second SLEEPs"),
    # --- TIME -------------------------------------------------------------------------
    lang("time-type", ["<TYPE <TIME>>", "<G? <TIME> 0.0>", "<TIME>"],
         "TYPE and sign; the printed value is CPU time (not deterministic)"),
    lang("time-args", ["<TYPE <TIME 1>>", "<TYPE <TIME 1 \"a\" FOO <>>>",
                       "<TIME <SETG X 5>>", ",X"],
         "any number of arguments, evaluated and ignored"),
    lang("time-monotonic", ["<SET A <TIME>>", "<SET B <TIME>>", "<G=? .B .A>",
                            "<==? .A .B>"],
         "two successive calls"),
    lang("time-truthy", ["<COND (<TIME> \"true\") (T \"false\")>",
                         "<COND (<APPLY <GVAL TIME>> \"true\") (T \"false\")>"],
         "the game's use: APPLY of the GVAL with no arguments, tested for truth"),
    lang("time-applicable", ["<TYPE ,TIME>", "<TYPE <APPLY ,TIME>>"], "TIME as a SUBR value"),
    lang("time-sleep", ["<SET A <TIME>>", "<SLEEP 1>", "<SET B <TIME>>",
                        "<L? <- .B .A> 0.5>"],
         "SLEEP does not consume CPU time (manual 21.10.2)"),
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
    base = Path(os.environ.get("TMPDIR", "/tmp")) / "p0prims-probes"
    base.mkdir(parents=True, exist_ok=True)
    shim = psr.build_shim(a.shim_src, Path(tempfile.mkdtemp(prefix="shim-", dir=base)))
    rows = []
    for c in CASES:
        row = psr.run_case(c, base, shim)
        row["forms"] = c["forms"]
        row["cwd_kind"] = c["cwd"]
        raw = row.get("stdout_raw", "").encode("latin-1")
        row["stdout_hex_tail"] = raw[-64:].hex()
        for k in ("files_before", "files_changed", "changed_file_text"):
            row.pop(k, None)
        rows.append(row)
    head = subprocess.run(["git", "-C", str(psr.UPSTREAM_ROOT), "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    res = {
        "schema_version": 1,
        "kind": "m4-p0prims-reference",
        "engine": "confusion-patched-1977",
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "interpreter": ".cache/build/confusion_patched/mdli",
        "interpreter_sha256_before": before,
        "interpreter_sha256_after": psr.sha256_file(psr.EXE),
        "upstream_mdlzork_checked_out": head,
        "fixed_epoch": psr.EPOCH, "tz": "UTC",
        "shim_src_sha256": psr.sha256_file(a.shim_src),
        "protocol": "scripts/probe_p0prims_reference.py (module docstring)",
        "cases": rows,
    }
    text = json.dumps(res, indent=2, ensure_ascii=False) + "\n"
    tmp = os.environ.get("TMPDIR", "/tmp").rstrip("/")
    text = text.replace(tmp, "$TMPDIR").replace(str(psr.ROOT), "<repo>")
    a.output.write_text(text, encoding="utf-8")
    return 0 if before == res["interpreter_sha256_after"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
