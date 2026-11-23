#!/usr/bin/env python3
"""Interactive-frontier probe driver (read-only investigation, 2026-11-23).

Usage: python3 -I if_probe.py CASES.json OUT.json

One pinned-Confusion mdli process per case. cwd is a fresh directory under
$TMPDIR/if-work: empty ("cwd": "empty") or a byte copy of the patched_confusion
game dir ("cwd": "game"). Never runs in .cache/upstream. stdin is a pipe
(not a pty) unless noted. Records raw stdout/stderr bytes (latin-1 decoded,
so \r is preserved), a canonical form (\r\n -> \n, \r -> \n, as
scripts/boot_reference.py canonical_text), exit status and changed files.
Optional per case: "fixed_clock": true -> LD_PRELOAD the fixed_time shim with
MDL_FIXED_EPOCH=250776000 and TZ=UTC (the approved house-boot settings).
"""
import hashlib, json, os, shutil, subprocess, sys, tempfile
from datetime import datetime, timezone
from pathlib import Path

# Repository root: this file lives in docs/evidence/M3/S7-frontier/.
ROOT = Path(os.environ.get("MDL_REPO_ROOT", Path(__file__).resolve().parents[4]))
EXE = ROOT / ".cache/build/confusion_patched/mdli"
GAME = ROOT / ".cache/upstream/mdlzork/mdlzork_771212/patched_confusion"
HERE = Path(__file__).resolve().parent
# Build with: gcc -shared -fPIC -O2 -o $TMPDIR/fixed_time.so scripts/reference/fixed_time.c -ldl
# (fixed_time.c is on the BOOT-REF branch, PR #131); override with MDL_FIXED_TIME_SO.
SHIM = Path(os.environ.get("MDL_FIXED_TIME_SO", Path(os.environ.get("TMPDIR", "/tmp")) / "fixed_time.so"))
WORK = Path(os.environ.get("TMPDIR", "/tmp")) / "if-work"
EPOCH = "250776000"


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def snapshot(d):
    return {str(p.relative_to(d)): (p.stat().st_size, sha(p))
            for p in sorted(d.rglob("*")) if p.is_file()}


def canon(t):
    return t.replace("\r\n", "\n").replace("\r", "\n")


def main():
    cases_path, out_path = Path(sys.argv[1]), Path(sys.argv[2])
    data = json.loads(cases_path.read_text())
    WORK.mkdir(parents=True, exist_ok=True)
    rows = []
    for c in data["cases"]:
        d = Path(tempfile.mkdtemp(prefix=c["name"] + "-", dir=WORK))
        if c.get("cwd") == "game":
            shutil.copytree(GAME, d, dirs_exist_ok=True)
        before = snapshot(d)
        env = dict(os.environ)
        if c.get("fixed_clock"):
            env.update({"LD_PRELOAD": str(SHIM), "MDL_FIXED_EPOCH": EPOCH, "TZ": "UTC"})
        stdin = c["input"].encode("latin-1")
        try:
            r = subprocess.run([str(EXE)], input=stdin, capture_output=True, cwd=d,
                               env=env, timeout=c.get("timeout", 60))
            status, out, err = r.returncode, r.stdout.decode("latin-1"), r.stderr.decode("latin-1")
        except subprocess.TimeoutExpired as e:
            status = "timeout"
            out = (e.stdout or b"").decode("latin-1")
            err = (e.stderr or b"").decode("latin-1") + "\nTIMEOUT"
        after = snapshot(d)
        changed = {k: {"before": before.get(k), "after": v}
                   for k, v in after.items() if before.get(k) != v}
        rows.append({"name": c["name"], "note": c.get("note", ""),
                     "cwd_kind": c.get("cwd", "empty"),
                     "fixed_clock": bool(c.get("fixed_clock")),
                     "input": c["input"], "exit_status": status,
                     "stdout_raw": out, "stdout_canonical": canon(out),
                     "stderr_raw": err,
                     "files_created_or_changed": changed,
                     "workdir": "$TMPDIR/if-work/" + d.name})
        print(f"{c['name']}: exit={status} changed={list(changed)}")
    res = {"schema_version": 1, "name": data["name"],
           "recorded_at": datetime.now(timezone.utc).isoformat(),
           "interpreter_sha256": sha(EXE),
           "protocol": "if_probe.py; one mdli process per case; stdin pipe; cwd fresh $TMPDIR/if-work dir; never .cache/upstream",
           "cases": rows}
    out_path.write_text(json.dumps(res, indent=2) + "\n")


if __name__ == "__main__":
    main()
