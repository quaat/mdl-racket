#!/usr/bin/env python3
"""Pinned-Confusion reference probes for M4 S8: the ABS SUBR (issue #167;
77act1.mud:949 `<PUT .RM ,RVARS <ABS <RVARS .RM>>>` and :951
`<G? <ABS .COUNT> 5>` (CYCLOPS), :1031 `<NTH ,CYCLOMAD <ABS .VARS>>`
(CYCLOPS-ROOM), :1050 `<NTH ,CYCLOMAD <ABS .FOO>>` (AOS-SOS)).

Read-only reference investigation. Nothing here is runtime code, and the game
sources under .cache/upstream are never written.

Usage (sandbox; TMPDIR must be writable):
    python3 -I scripts/probe_abs_reference.py OUT.json [--shim-src C]

Protocol (run_case of scripts/probe_session_reference.py, as
scripts/probe_max_reference.py):
  * one pinned mdli process per case, pipe mode, fixed clock (LD_PRELOAD of
    scripts/reference/fixed_time.c, MDL_FIXED_EPOCH=250776000, TZ=UTC);
  * every case runs in a fresh empty directory under $TMPDIR/abs-probes
    (bare interpreter; ABS is a primitive, no game load is needed);
  * every case ends with <QUIT>; error cases hold one failing form so that a
    LISTENING-AT-LEVEL 2 never hides a later result;
  * a FLOAT near the host DBL_MAX/DBL_MIN is never printed (R6: printing
    <MIN> segfaults this build); it is observed through ==?, G? and TYPE;
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


CASES = [
    # --- FIX ------------------------------------------------------------------------
    lang("fix", ["<ABS 5>", "<TYPE <ABS 5>>", "<ABS -5>", "<TYPE <ABS -5>>",
                 "<ABS 0>", "<TYPE <ABS 0>>", "<ABS -1>", "<ABS 1>"],
         "positive, negative and zero FIX; TYPE of each result"),
    # --- FLOAT ----------------------------------------------------------------------
    lang("float", ["<ABS 2.5>", "<TYPE <ABS 2.5>>", "<ABS -2.5>", "<TYPE <ABS -2.5>>",
                   "<ABS 0.0>", "<TYPE <ABS 0.0>>", "<ABS -0.5>", "<==? <ABS -2.5> 2.5>"],
         "positive, negative and zero FLOAT; TYPE of each result (no FIX conversion)"),
    lang("float-large", ["<ABS -1.0E20>", "<==? <ABS -1.0E20> 1.0E20>",
                         "<TYPE <ABS -1.0E20>>", "<==? <ABS <- <MIN>>> <MIN>>",
                         "<==? <ABS <MIN>> <MIN>>", "<TYPE <ABS <- <MIN>>>>",
                         "<==? <ABS <MAX>> <MAX>>", "<G? <ABS <MAX>> 0>",
                         "<ABS <* -100000000000.0 1000000000.0>>",
                         "<==? <ABS <* -100000000000.0 1000000000.0>> "
                         "<* 100000000000.0 1000000000.0>>"],
         "large FLOATs; <MIN> is never printed (R6), only compared"),
    # --- 36-bit FIX boundaries ------------------------------------------------------
    lang("fix-36bit-boundaries", ["<ABS 34359738367>", "<ABS -34359738367>",
                                  "<TYPE <ABS -34359738367>>"],
         "2^35-1 and its negation"),
    lang("fix-most-negative", ["<ABS -34359738368>", "<TYPE <ABS -34359738368>>",
                               "<G? <ABS -34359738368> 34359738367>"],
         "-2^35, the most negative 36-bit FIX (a PDP-10 MOVM overflows here); "
         "Confusion FIX is a 64-bit host integer"),
    lang("fix-most-negative-computed", ["<ABS <- 0 34359738368>>",
                                        "<TYPE <- 0 34359738368>>"],
         "the same value formed by subtraction (34359738368 is FIX in Confusion)"),
    lang("fix-beyond-36bit", ["<ABS -34359738369>", "<TYPE <ABS -34359738369>>"],
         "one beyond -2^35 (64-bit in Confusion; FLOAT by our reader rule)"),
    # --- arity ------------------------------------------------------------------------
    lang("err-no-args", ["<ABS>"], "zero arguments"),
    lang("err-two-args", ["<ABS 1 2>"], "two arguments"),
    lang("err-two-args-negative", ["<ABS -1 -2>"], "two negative arguments"),
    # --- non-numeric arguments: one failing form per case ------------------------
    lang("err-string", ['<ABS "A">'], "STRING"),
    lang("err-atom", ["<ABS A>"], "ATOM (an ATOM evaluates to itself)"),
    lang("err-quoted-atom", ["<ABS 'A>"], "quoted ATOM"),
    lang("err-list", ["<ABS '(1 2)>"], "LIST"),
    lang("err-false", ["<ABS <>>"], "FALSE"),
    lang("err-character", ["<ABS !\\A>"], "CHARACTER"),
    lang("err-vector", ["<ABS [-1]>"], "VECTOR"),
    # --- application shapes -----------------------------------------------------------
    lang("applicable", ["<TYPE ,ABS>", "<APPLY ,ABS -7>", "<MAPF ,LIST ,ABS '(-1 2 -3)>"],
         "ABS as a SUBR value (APPLY, MAPF)"),
    # --- the game's own expressions -----------------------------------------------
    lang("game-cyclops-count",
         ["<SET COUNT 0>", "<G? <ABS .COUNT> 5>", "<SET COUNT -6>", "<G? <ABS .COUNT> 5>",
          "<SET COUNT 6>", "<G? <ABS .COUNT> 5>", "<SET COUNT -5>", "<G? <ABS .COUNT> 5>"],
         "77act1.mud:951 `<G? <ABS .COUNT> 5>` (COUNT is DECLed FIX)"),
    lang("game-cyclomad-index",
         ["<SETG CM '[\"a\" \"b\" \"c\" \"d\" \"e\" \"f\"]>", "<NTH ,CM <ABS -1>>",
          "<NTH ,CM <ABS 2>>", "<NTH ,CM <ABS -6>>",
          "<SET FOO -2> <SET FOO <- .FOO 1>>", "<NTH ,CM <ABS .FOO>>"],
         "77act1.mud:1031/1050 `<NTH ,CYCLOMAD <ABS .VARS>>` shape with a 6-element VECTOR"),
    lang("game-rvars-put",
         ["<SETG V [-3]>", "<PUT ,V 1 <ABS <1 ,V>>>", "<1 ,V>", "<TYPE <1 ,V>>"],
         "77act1.mud:949 `<PUT .RM ,RVARS <ABS <RVARS .RM>>>` shape"),
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
    base = Path(os.environ.get("TMPDIR", "/tmp")) / "abs-probes"
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
        "kind": "m4-abs-reference",
        "engine": "confusion-patched-1977",
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "interpreter": ".cache/build/confusion_patched/mdli",
        "interpreter_sha256_before": before,
        "interpreter_sha256_after": psr.sha256_file(psr.EXE),
        "upstream_mdlzork_checked_out": head,
        "fixed_epoch": psr.EPOCH, "tz": "UTC",
        "shim_src_sha256": psr.sha256_file(a.shim_src),
        "protocol": "scripts/probe_abs_reference.py (module docstring)",
        "cases": rows,
    }
    text = json.dumps(res, indent=2, ensure_ascii=False) + "\n"
    tmp = os.environ.get("TMPDIR", "/tmp").rstrip("/")
    text = text.replace(tmp, "$TMPDIR").replace(str(psr.ROOT), "<repo>")
    a.output.write_text(text, encoding="utf-8")
    return 0 if before == res["interpreter_sha256_after"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
