#!/usr/bin/env python3
"""Pinned-Confusion transcript capture for the targeted probe routes of the
attached-declaration violation sweep (M4 issue #196; tests/decl_sweep_probes.json,
tests/decl_violation_sweep.rkt, docs/evidence/M4/DECL-VIOLATION-SWEEP.md).

Read-only reference investigation; nothing here is runtime code. The game
sources under .cache/upstream are never written: every run boots a fresh copy
of the game directory under $TMPDIR (scripts/probe_session_reference.py's
run_case: pipe mode, the LD_PRELOAD fixed-time shim, epoch 250776000, TZ=UTC,
microseconds 0; START seeds RANDOM from DSKDATE, no RANDOM override, no seed
search).

Transcript-only: for each probe, T1 (<FLOAD "77loadall.mud"> <SAVE-IT> and the
probe's commands, then end of input) and its repeat T1b; the capture is
rejected unless T1 and T1b are byte-identical, both exit 0 with Confusion's
"Error: Unexpected EOF" on stderr, and the interpreter's sha256 is the pinned
one before and after. No per-prefix runs, no diagnostic checkpoints: the sweep
compares only the whole transcript (D1 only), and says so.

Usage (sandbox; TMPDIR must be writable):
    python3 -I scripts/probe_decl_sweep_reference.py OUT.json [--shim-src C]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import probe_session_reference as psr  # noqa: E402

PINNED_SHA256 = "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789"
PINNED_UPSTREAM = "bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3"
EOF_STDERR = "Error: Unexpected EOF\n"
PROBES = psr.ROOT / "tests/decl_sweep_probes.json"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("output", type=Path)
    ap.add_argument("--shim-src", type=Path, default=psr.DEFAULT_SHIM_SRC)
    a = ap.parse_args()
    if not psr.EXE.is_file() or not psr.GAME.is_dir():
        raise SystemExit("pinned interpreter or game directory missing")
    exe_before = psr.sha256_file(psr.EXE)
    if exe_before != PINNED_SHA256:
        raise SystemExit(f"interpreter sha256 {exe_before} is not the pinned {PINNED_SHA256}")
    upstream = subprocess.run(["git", "-C", str(psr.UPSTREAM_ROOT), "rev-parse", "HEAD"],
                              capture_output=True, text=True, check=True).stdout.strip()
    if upstream != PINNED_UPSTREAM:
        raise SystemExit(f"upstream mdlzork {upstream} is not the pinned {PINNED_UPSTREAM}")
    spec = json.loads(PROBES.read_text())
    assert spec["fixed_epoch"] == psr.EPOCH and spec["tz"] == "UTC"
    base = Path(tempfile.mkdtemp(prefix="decl-sweep-probes-"))
    shim = psr.build_shim(a.shim_src, Path(tempfile.mkdtemp(prefix="shim-", dir=base)))
    probes = []
    for p in spec["probes"]:
        name, cmds = p["name"], p["commands"]
        base_cmds = json.loads((psr.ROOT / f"tests/scenarios/{p['base']}.json").read_text())["commands"]
        if cmds != base_cmds[:p["base_prefix"]] + p["extra"]:
            raise SystemExit(f"{name}: commands are not base[:{p['base_prefix']}] + extra")
        text = psr.ENTRY + psr.lines(*cmds)
        rows = [psr.run_case({"name": f"T1-{name}-pipe", "input": text}, base, shim),
                psr.run_case({"name": f"T1b-{name}-pipe", "input": text,
                              "note": "repeat of T1 (byte determinism)"}, base, shim)]
        for r in rows:
            if r["exit_status"] != 0 or r["stderr_raw"] != EOF_STDERR:
                raise SystemExit(f"{r['name']}: exit {r['exit_status']}, stderr {r['stderr_raw']!r}")
            for k in ("cwd", "files_before"):
                r.pop(k, None)
        if rows[0]["stdout_raw"] != rows[1]["stdout_raw"]:
            raise SystemExit(f"{name}: T1 and T1b differ")
        probes.append({"name": name, "commands": cmds, "cases": rows,
                       "checks": {"t1_equals_t1b_bytes": True}})
    exe_after = psr.sha256_file(psr.EXE)
    if exe_after != PINNED_SHA256:
        raise SystemExit("interpreter changed during the capture")
    doc = {
        "schema_version": 1,
        "kind": "decl-sweep-probes-reference",
        "captured_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "interpreter": ".cache/build/confusion_patched/mdli",
        "interpreter_sha256_before": exe_before,
        "interpreter_sha256_after": exe_after,
        "upstream_mdlzork_checked_out": upstream,
        "game_dir": "mdlzork_771212/patched_confusion (fresh copy under $TMPDIR per run)",
        "clock": {"epoch": psr.EPOCH, "tz": "UTC", "microseconds": 0},
        "rng": "START seeds RANDOM from DSKDATE (seed 10438660480 on this clock); never overridden",
        "probes_file": "tests/decl_sweep_probes.json",
        "probes_file_sha256": psr.sha256_file(PROBES),
        "protocol": "transcript only: T1 and its repeat T1b per probe; no prefix runs, no checkpoints",
        "probes": probes,
    }
    raw = json.dumps(doc, indent=1, sort_keys=True)
    raw = raw.replace(str(base), "$TMPDIR/decl-sweep-probes").replace(str(psr.ROOT), "<repo>")
    a.output.write_text(raw + "\n")
    print("CAPTURE OK", a.output, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
