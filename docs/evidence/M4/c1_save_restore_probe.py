#!/usr/bin/env python3
"""C1 (#172) native save/restore probes against the pinned Confusion mdli.

Read-only reference investigation; not runtime code. Reuses the protocol of
scripts/probe_failure_inventory_reference.py / probe_session_reference.py
(fresh game copy under $TMPDIR, pipe mode, LD_PRELOAD fixed_time.so,
MDL_FIXED_EPOCH, TZ=UTC), extended to several SEQUENTIAL processes per copy
(process B sees the files process A left) and a per-process epoch.

Usage:
    python3 -I c1_save_restore_probe.py CASES.json OUT.json \
        --cache <dir containing build/ and upstream/> --shim-src fixed_time.c

Never writes under --cache. Only one mdli process runs at a time.
Confusion is GPLv3 and is used only as a behaviour reference.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

PINNED_SHA256 = "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789"
GAME_START = "Welcome to Dungeon."
MARK = re.compile(r"\{\{.*?\}\}", re.S)

DIAG_FORMS = r'''<PROG () <SETG DIAG-TROLL <FIND-OBJ "TROLL">> <SETG DIAG-LAMP <FIND-OBJ "LAMP">> T>
<SETG DIAG-P <FUNCTION (N V) <PRINC " "> <PRINC .N> <PRINC "="> <PRIN1 .V> T>>
<SETG DIAG-G <FUNCTION (N A) <DIAG-P .N <COND (<GASSIGNED? .A> ,.A) (T UNASSIGNED)>>>>
<SETG DIAG-STATE <FUNCTION () <PRINC "{{CP"> <DIAG-G "MOVES" MOVES> <DIAG-P "HERE" <RID ,HERE>> <DIAG-P "LIT" <COND (<LIT? ,HERE> T)>> <DIAG-G "RAW" RAW-SCORE> <DIAG-P "ASTR" <ASTRENGTH ,WINNER>> <DIAG-G "DEATHS" DEATHS> <DIAG-P "LN" <CTICK ,LNTIN>> <DIAG-P "LNF" <CFLAG ,LNTIN>> <DIAG-P "CU" <CTICK ,CURIN>> <DIAG-P "CUF" <CFLAG ,CURIN>> <DIAG-P "TROLL" <OCAPAC ,DIAG-TROLL>> <DIAG-P "TFIGHT" <COND (<TRNN ,DIAG-TROLL ,FIGHTBIT> T)>> <DIAG-P "LAMPL" <OLIGHT? ,DIAG-LAMP>> <DIAG-G "BR" BRIEF!-FLAG> <DIAG-G "SB" SUPER-BRIEF!-FLAG> <DIAG-P "VEH" <COND (<AVEHICLE ,WINNER> <OID <AVEHICLE ,WINNER>>)>> <DIAG-P "INTIME" <CHTYPE ,INTIME FIX>> <DIAG-G "PLAYED" PLAYED-TIME> <DIAG-G "PW" PARSE-WON> <DIAG-P "PRSO" <TYPE <2 ,PRSVEC>>> <PRINC "}}"> T>>
<SETG DIAG-ORIG-RANDOM ,RANDOM>
<SETG RANDOM <FUNCTION ("TUPLE" DIAG-A "AUX" DIAG-R) <SET DIAG-R <APPLY ,DIAG-ORIG-RANDOM !.DIAG-A>> <PRINC "{{R"> <MAPF <> <FUNCTION (X) <PRINC " "> <PRIN1 .X>> .DIAG-A> <PRINC "=>"> <PRIN1 .DIAG-R> <PRINC "}}"> .DIAG-R>>
<SETG DIAG-ORIG-READSTRING ,READSTRING>
<SETG READSTRING <FUNCTION ("TUPLE" DIAG-A "AUX" DIAG-R) <DIAG-STATE> <SET DIAG-R <APPLY ,DIAG-ORIG-READSTRING !.DIAG-A>> <PRINC "{{IN "> <PRIN1 <SUBSTRUC <1 .DIAG-A> 0 .DIAG-R>> <PRINC "}}"> .DIAG-R>>
'''


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def sha256_file(p: Path) -> str:
    return sha256_bytes(p.read_bytes())


def tree_hash(root: Path) -> dict:
    h = hashlib.sha256()
    n = 0
    for p in sorted(root.rglob("*")):
        if p.is_file() and not p.is_symlink():
            rel = p.relative_to(root).as_posix()
            h.update(rel.encode() + b"\0" + sha256_file(p).encode() + b"\n")
            n += 1
    return {"files": n, "sha256": h.hexdigest()}


def manifest(d: Path) -> dict:
    out = {}
    for p in sorted(d.rglob("*")):
        rel = p.relative_to(d).as_posix()
        if p.is_dir():
            out[rel + "/"] = {"mode": oct(stat.S_IMODE(p.lstat().st_mode))}
        elif p.is_file():
            out[rel] = {"size": p.stat().st_size, "sha256": sha256_file(p)}
    return out


def savefile_state(game: Path) -> dict:
    p = game / "SAVEFILE/ZORK.SAVE"
    if not p.is_file():
        return {"exists": False, "savefile_dir_exists": (game / "SAVEFILE").is_dir()}
    return {"exists": True, "size": p.stat().st_size, "sha256": sha256_file(p)}


def build_input(proc: dict, diag: bool) -> str:
    if proc["entry"] == "bare":
        head = ""
    elif diag:
        head = '<FLOAD "77loadall.mud">\n' + DIAG_FORMS + "<SAVE-IT>\n"
    else:
        head = '<FLOAD "77loadall.mud">\n<SAVE-IT>\n'
    return head + "".join(c + "\n" for c in proc["commands"])


def host_op(game: Path, op: str) -> dict:
    parts = op.split()
    if parts[0] == "truncate":
        p = game / parts[1]
        before = savefile_state(game)
        data = p.read_bytes() if p.is_file() else b""
        n = len(data) // 2 if parts[2] == "half" else int(parts[2])
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data[:n])
        return {"op": op, "before": before, "after": savefile_state(game)}
    raise SystemExit(f"unknown host op {op}")


def run_proc(exe: Path, shim: Path, game: Path, proc: dict, diag: bool) -> dict:
    ops = [host_op(game, o) for o in proc.get("host_before", [])]
    before = manifest(game)
    stdin_text = build_input(proc, diag)
    stdin = stdin_text.encode("latin-1")
    env = dict(os.environ)
    env.update({"LD_PRELOAD": str(shim), "MDL_FIXED_EPOCH": str(proc["epoch"]),
                "TZ": proc["tz"]})
    t0 = time.monotonic()
    try:
        r = subprocess.run([str(exe)], input=stdin, capture_output=True, cwd=game, env=env,
                           timeout=120)
        status, out, err = r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired as e:
        status, out, err = "timeout", e.stdout or b"", (e.stderr or b"") + b"\nTIMEOUT"
    el = round(time.monotonic() - t0, 2)
    after = manifest(game)
    so = out.decode("latin-1")
    row = {"label": proc["label"], "entry": proc["entry"],
           "clock": {"epoch": proc["epoch"], "tz": proc["tz"], "microseconds": 0},
           "host_before": ops, "commands": proc["commands"],
           "stdin": stdin_text, "stdin_sha256": sha256_bytes(stdin),
           "exit_status": status, "elapsed_seconds": el,
           "stdout_raw": so, "stdout_sha256": sha256_bytes(out),
           "stderr_raw": err.decode("latin-1"),
           "savefile_after": savefile_state(game),
           "files_changed": {k: {"before": before.get(k), "after": v}
                             for k, v in after.items() if before.get(k) != v},
           "files_removed": sorted(k for k in before if k not in after)}
    if proc["entry"] != "bare":
        i = so.find(GAME_START)
        gp = so[i:] if i >= 0 else ""
        row["game_part_raw"] = gp
        row["game_part_sha256"] = sha256_bytes(gp.encode("latin-1"))
        if diag:
            stripped = MARK.sub("", gp)
            row["game_part_stripped_sha256"] = sha256_bytes(stripped.encode("latin-1"))
            row["diag_markers"] = MARK.findall(gp)
    print(f"  {proc['label']}: exit={status} t={el}s save={row['savefile_after']}",
          file=sys.stderr)
    return row


def run_variant(case: dict, rep: int, diag: bool, base: Path, upstream_game: Path,
                exe: Path, shim: Path) -> dict:
    d = Path(tempfile.mkdtemp(prefix=f"{case['name']}-{'diag' if diag else 'tx'}-r{rep}-",
                              dir=base))
    game = d / "game"
    shutil.copytree(upstream_game, game)
    setup_done = []
    for s in case["setup"]:
        if s == "remove SAVEFILE/ZORK.SAVE":
            p = game / "SAVEFILE/ZORK.SAVE"
            if p.exists():
                p.unlink()
                setup_done.append(s)
        elif s == "remove directory SAVEFILE":
            shutil.rmtree(game / "SAVEFILE")
            setup_done.append(s)
        elif s == "keep shipped SAVEFILE/ZORK.SAVE":
            setup_done.append(s)
        else:
            raise SystemExit(f"unknown setup {s}")
    print(f"{case['name']} {'diag' if diag else 'transcript'} rep{rep}", file=sys.stderr)
    procs = [run_proc(exe, shim, game, p, diag) for p in case["processes"]]
    return {"variant": "diagnostic" if diag else "transcript", "rep": rep,
            "workdir": str(game), "setup_done": setup_done,
            "processes": procs}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("cases", type=Path)
    ap.add_argument("output", type=Path)
    ap.add_argument("--cache", type=Path, required=True)
    ap.add_argument("--shim-src", type=Path, required=True)
    ap.add_argument("--only", default=None)
    a = ap.parse_args()
    exe = a.cache / "build/confusion_patched/mdli"
    upstream = a.cache / "upstream/mdlzork"
    game_src = upstream / "mdlzork_771212/patched_confusion"
    exe_before = sha256_file(exe)
    if exe_before != PINNED_SHA256:
        raise SystemExit(f"mdli sha256 {exe_before} != pinned {PINNED_SHA256}")
    up_before = tree_hash(upstream)
    head = (upstream / ".git/HEAD").read_text().strip()
    spec = json.loads(a.cases.read_text())
    base = Path(os.environ["TMPDIR"]) / "c1-save-restore"
    base.mkdir(parents=True, exist_ok=True)
    sd = Path(tempfile.mkdtemp(prefix="shim-", dir=base))
    so = sd / "fixed_time.so"
    r = subprocess.run(["gcc", "-shared", "-fPIC", "-O2", "-o", str(so), str(a.shim_src), "-ldl"],
                       capture_output=True, text=True)
    if r.returncode:
        raise SystemExit("shim build failed\n" + r.stderr)
    rows = []
    for c in spec["cases"]:
        if a.only and not re.search(a.only, c["name"]):
            continue
        runs = []
        for diag in ([False, True] if c.get("diagnostic_twin") else [False]):
            for rep in range(1, spec["repetitions"] + 1):
                runs.append(run_variant(c, rep, diag, base, game_src, exe, so))
        # determinism + twin checks
        det = {}
        for var in {r["variant"] for r in runs}:
            rs = [r for r in runs if r["variant"] == var]
            per = {}
            for i, p in enumerate(rs[0]["processes"]):
                others = [r["processes"][i] for r in rs[1:]]
                per[p["label"]] = {
                    "stdout_identical": all(o["stdout_sha256"] == p["stdout_sha256"] for o in others),
                    "stderr_identical": all(o["stderr_raw"] == p["stderr_raw"] for o in others),
                    "exit_identical": all(o["exit_status"] == p["exit_status"] for o in others),
                    "savefile_identical": all(o["savefile_after"] == p["savefile_after"] for o in others),
                }
            det[var] = per
        twin = None
        if c.get("diagnostic_twin"):
            twin = {}
            tx = [r for r in runs if r["variant"] == "transcript"][0]
            dg = [r for r in runs if r["variant"] == "diagnostic"][0]
            for pt, pd in zip(tx["processes"], dg["processes"]):
                twin[pt["label"]] = pd.get("game_part_stripped_sha256") == pt.get("game_part_sha256")
        rows.append({**c, "runs": runs, "determinism": det,
                     "diagnostic_stripped_equals_transcript": twin})
    res = {
        "schema_version": 1,
        "kind": "c1-save-restore-native-reference",
        "cases_file": "docs/evidence/M4/c1-save-restore-cases.json",
        "driver": "docs/evidence/M4/c1_save_restore_probe.py",
        "engine": "confusion-patched-1977",
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "interpreter": ".cache/build/confusion_patched/mdli",
        "interpreter_sha256_before": exe_before,
        "interpreter_sha256_after": sha256_file(exe),
        "upstream_mdlzork_head": head,
        "upstream_mdlzork_tree_before": up_before,
        "upstream_mdlzork_tree_after": tree_hash(upstream),
        "tree_hash_method": "sha256 over sorted 'relpath NUL sha256(file) LF' of every regular "
                            "file under .cache/upstream/mdlzork (including .git)",
        "game_dir": "mdlzork_771212/patched_confusion",
        "shim_src_sha256": sha256_file(a.shim_src),
        "shim": "scripts/reference/fixed_time.c compiled once per capture: gcc -shared -fPIC "
                "-O2 -o fixed_time.so fixed_time.c -ldl; LD_PRELOAD, MDL_FIXED_EPOCH=<process "
                "epoch>, TZ=UTC",
        "protocol": spec["protocol"],
        "diag_forms": DIAG_FORMS,
        "cases": rows,
    }
    text = json.dumps(res, indent=1, ensure_ascii=False) + "\n"
    tmp = os.environ["TMPDIR"].rstrip("/")
    text = text.replace(tmp, "$TMPDIR")
    a.output.write_text(text, encoding="utf-8")
    ok = exe_before == res["interpreter_sha256_after"] and up_before == res["upstream_mdlzork_tree_after"]
    print("interpreter/upstream unchanged:", ok, file=sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
