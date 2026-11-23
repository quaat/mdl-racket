#!/usr/bin/env python3
"""Probe driver for the S5 SAVE-frontier evidence (copied from the scratch run).

Usage (from the repository root, after `make reference-build`):
  python3 -I docs/evidence/M3/s5_sf_probe.py CASES.json OUT.json

Each case runs the pinned Confusion mdli in its own fresh directory under
$TMPDIR: either empty ("cwd": "empty") or a byte copy of the 1977 game dir
("cwd": "game"). Never runs in .cache/upstream. Records stdin, stdout,
stderr, exit status, and the files created/changed in that directory.
Optional "argv" (e.g. ["-r", "MDL/MADADV.SAVE"]) and "reuse" (name of an
earlier case whose directory is reused, to restore an image it wrote).
"""
import hashlib, json, os, shutil, subprocess, sys, tempfile
from datetime import datetime, timezone
from pathlib import Path

# Repository root = three levels above docs/evidence/M3/.
ROOT = Path(__file__).resolve().parents[3]
EXE = ROOT / ".cache/build/confusion_patched/mdli"
GAME = ROOT / ".cache/upstream/mdlzork/mdlzork_771212/patched_confusion"
WORK = Path(os.environ.get("TMPDIR", "/tmp")) / "sf-work"


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
    dirs, rows = {}, []
    for c in data["cases"]:
        if c.get("reuse"):
            d = dirs[c["reuse"]]
        else:
            d = Path(tempfile.mkdtemp(prefix=c["name"] + "-", dir=WORK))
            if c.get("cwd") == "game":
                shutil.copytree(GAME, d, dirs_exist_ok=True)
                if c.get("pre_remove"):  # only ever inside the fresh copy
                    shutil.rmtree(d / c["pre_remove"])
        dirs[c["name"]] = d
        before = snapshot(d)
        stdin = c["input"]
        try:
            r = subprocess.run([str(EXE)] + c.get("argv", []), input=stdin, text=True,
                               capture_output=True, cwd=d, timeout=c.get("timeout", 60),
                               errors="replace")
            status, out, err = r.returncode, canon(r.stdout), canon(r.stderr)
        except subprocess.TimeoutExpired as e:
            status, out, err = "timeout", canon((e.stdout or b"").decode("utf-8", "replace") if isinstance(e.stdout, bytes) else (e.stdout or "")), "TIMEOUT"
        after = snapshot(d)
        changed = {k: {"before": before.get(k), "after": v} for k, v in after.items() if before.get(k) != v}
        rows.append({"name": c["name"], "note": c.get("note", ""), "cwd_kind": c.get("cwd", "empty"),
                     "argv": c.get("argv", []), "input": stdin, "exit_status": status,
                     "stdout": out, "stderr": err, "files_created_or_changed": changed,
                     "workdir": "$TMPDIR/sf-work/" + d.name})
        print(f"{c['name']}: exit={status} changed={list(changed)}")
    res = {"schema_version": 1, "name": data["name"],
           "recorded_at": datetime.now(timezone.utc).isoformat(),
           "interpreter_sha256": sha(EXE),
           "protocol": "scratch driver sf_probe.py; one mdli process per case, cwd = fresh $TMPDIR dir (empty or copy of patched_confusion game dir); never .cache/upstream",
           "cases": rows}
    out_path.write_text(json.dumps(res, indent=2) + "\n")


if __name__ == "__main__":
    main()
