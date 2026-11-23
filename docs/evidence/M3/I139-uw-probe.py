#!/usr/bin/env python3
"""UNWIND-frontier probe driver (read-only investigation, issue #139, 2026-11-23).

Usage (from the repository root):
  python3 -I docs/evidence/M3/I139-uw-probe.py CASES.json OUT.json

One pinned-Confusion mdli process per case, stdin is a pipe, cwd is a fresh
empty directory under $TMPDIR/uw-work (never .cache/upstream, never under
.cache). Records stdout/stderr (latin-1), canonical stdout (\r\n,\r -> \n)
with the 5-line startup banner removed, exit status. Inputs are fed exactly as
given: a case that omits <QUIT> deliberately ends at stdin EOF.
"""
import hashlib, json, os, subprocess, sys, tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]  # repository root
EXE = ROOT / ".cache/build/confusion_patched/mdli"
WORK = Path(os.environ.get("TMPDIR") or tempfile.gettempdir()) / "uw-work"


def canon(t):
    t = t.replace("\r\n", "\n").replace("\r", "\n")
    lines = t.split("\n")
    # drop banner (Welcome/Copyright/created/WARRANTY/COPYING lines)
    while lines and (lines[0].startswith(("Welcome to", "Copyright", "This Confusion",
                                         "This program", "This is free")) or lines[0] == ""):
        lines.pop(0)
    return "\n".join(lines)


def main():
    cases_path, out_path = Path(sys.argv[1]), Path(sys.argv[2])
    data = json.loads(cases_path.read_text())
    WORK.mkdir(parents=True, exist_ok=True)
    rows = []
    for c in data["cases"]:
        d = Path(tempfile.mkdtemp(prefix=c["name"] + "-", dir=WORK))
        try:
            r = subprocess.run([str(EXE)], input=c["input"].encode("latin-1"),
                               capture_output=True, cwd=d, timeout=c.get("timeout", 30))
            status, out, err = r.returncode, r.stdout.decode("latin-1"), r.stderr.decode("latin-1")
        except subprocess.TimeoutExpired as e:
            status = "timeout"
            out = (e.stdout or b"").decode("latin-1")
            err = (e.stderr or b"").decode("latin-1") + "\nTIMEOUT"
        rows.append({"name": c["name"], "note": c.get("note", ""), "input": c["input"],
                     "exit_status": status, "stdout_after_banner": canon(out),
                     "stdout_raw": out, "stderr_raw": err,
                     "files_left": sorted(p.name for p in d.iterdir())})
        print(f"--- {c['name']}: exit={status}")
        print(canon(out).rstrip())
        if err.strip():
            print("[stderr] " + err.strip().replace("\n", " | "))
    res = {"schema_version": 1, "name": data["name"],
           "recorded_at": datetime.now(timezone.utc).isoformat(),
           "interpreter_sha256": hashlib.sha256(EXE.read_bytes()).hexdigest(),
           "protocol": "uw_probe.py; one mdli process per case; stdin pipe; cwd fresh empty $TMPDIR/uw-work dir",
           "cases": rows}
    out_path.write_text(json.dumps(res, indent=2) + "\n")


if __name__ == "__main__":
    main()
