#!/usr/bin/env python3
"""Record pinned Confusion's OBLIST contents as reference evidence.

``root``      dumps the startup ROOT OBLIST of a fresh interpreter run in a
              new empty directory under $TMPDIR.
``placement`` copies the pinned game directory to a new $TMPDIR directory,
              runs <FLOAD "77loadall.mud"> there, and dumps every atom on
              ROOT, on INITIAL, and on each OBLIST associated (indicator
              OBLIST) with an atom of ROOT or INITIAL.

Both modes run one local process with stdin input ending in <QUIT>, never
inside .cache/upstream, and keep raw stdout/stderr, exit status and the
interpreter SHA-256 next to the parsed entries. The MDL dump code uses only
atoms prefixed DUMP- (filtered from the result), so reading it adds nothing
else to INITIAL.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from scripts.reference_runner import EXE, GAME, canonical_text, sha256

BEGIN, END = "@@BEGIN", "@@END"
TAB = "<PRINC <ASCII 9>>"

ROOT_DUMP = (
    f'<PROG () <PRINC "{BEGIN}"> <TERPRI> '
    '<MAPF <> <FUNCTION (DUMP-B) <MAPF <> <FUNCTION (DUMP-A) '
    '<PRINC <SPNAME .DUMP-A>> <TERPRI>> .DUMP-B>> <ROOT>> '
    f'<PRINC "{END}"> <TERPRI> T>'
)

# Each line: <label> TAB <SPNAME>. Labels: ROOT, INITIAL, or @<SPNAME of
# the atom whose OBLIST association names a further OBLIST>.
PLACEMENT_DUMP = (
    '<DEFINE DUMP-OBL (DUMP-LABEL DUMP-OB) '
    '<MAPF <> <FUNCTION (DUMP-B) <MAPF <> <FUNCTION (DUMP-A) '
    f'<PRINC .DUMP-LABEL> {TAB} <PRINC <SPNAME .DUMP-A>> <TERPRI>> .DUMP-B>> .DUMP-OB>>\n'
    '<DEFINE DUMP-NAMED (DUMP-OB) '
    '<MAPF <> <FUNCTION (DUMP-B) <MAPF <> <FUNCTION (DUMP-A "AUX" (DUMP-O <GET .DUMP-A OBLIST>)) '
    '<COND (<AND <TYPE? .DUMP-O OBLIST> <NOT <==? .DUMP-O <ROOT>>> '
    '<NOT <==? .DUMP-O <GET INITIAL OBLIST>>>> '
    '<DUMP-OBL <STRING "@" <SPNAME .DUMP-A>> .DUMP-O>)>> .DUMP-B>> .DUMP-OB>>\n'
    f'<PROG () <PRINC "{BEGIN}"> <TERPRI> '
    '<DUMP-OBL "ROOT" <ROOT>> <DUMP-OBL "INITIAL" <GET INITIAL OBLIST>> '
    '<DUMP-NAMED <ROOT>> <DUMP-NAMED <GET INITIAL OBLIST>> '
    f'<PRINC "{END}"> <TERPRI> T>'
)


def run(cwd: Path, input_text: str, timeout: float) -> dict:
    result = subprocess.run([str(EXE)], input=input_text, text=True,
                            capture_output=True, cwd=cwd, timeout=timeout)
    stdout = canonical_text(result.stdout)
    body = None
    if BEGIN + "\n" in stdout and "\n" + END + "\n" in stdout:
        body = stdout.split(BEGIN + "\n", 1)[1].split("\n" + END + "\n", 1)[0]
    return {"input": input_text, "exit_code": result.returncode,
            "stdout": stdout, "stderr": canonical_text(result.stderr),
            "body": body}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["root", "placement"])
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--timeout", type=float, default=300)
    args = parser.parse_args()
    if not EXE.is_file():
        parser.error("native Confusion is not built: make reference-build")
    with tempfile.TemporaryDirectory(prefix="confusion-oblist-") as tmp:
        work = Path(tmp)
        if args.mode == "root":
            row = run(work, ROOT_DUMP + "\n<QUIT>\n", args.timeout)
            entries = sorted(set(row["body"].split("\n"))) if row["body"] else None
            cwd_note = "fresh empty directory under $TMPDIR"
        else:
            game = work / "game"
            shutil.copytree(GAME, game, symlinks=True)
            text = '<FLOAD "77loadall.mud">\n' + PLACEMENT_DUMP + "\n<QUIT>\n"
            row = run(game, text, args.timeout)
            entries = None
            if row["body"] is not None:
                pairs = set()
                for line in row["body"].split("\n"):
                    label, _, pname = line.partition("\t")
                    if not pname.startswith("DUMP-"):
                        pairs.add((label, pname))
                entries = [list(p) for p in sorted(pairs)]
            cwd_note = "copy of the pinned game directory under $TMPDIR"
    ok = row["exit_code"] == 0 and entries is not None
    report = {
        "schema_version": 1, "mode": args.mode,
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "interpreter": str(EXE.relative_to(EXE.parents[2])),
        "interpreter_sha256": sha256(EXE), "cwd": cwd_note,
        "protocol": "one local process; stdin input then <QUIT>",
        "ok": ok, "entries": entries, **row,
    }
    del report["body"]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    if not ok:
        print(f"CONFUSION OBLIST DUMP FAILED; evidence: {args.output}", file=sys.stderr)
        return 1
    print(f"Recorded {len(entries)} entries; evidence: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
