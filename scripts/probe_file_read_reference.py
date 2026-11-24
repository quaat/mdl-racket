#!/usr/bin/env python3
"""Pinned-Confusion reference probes for issue #171 (help / info): OPEN "READ",
FILE-LENGTH, READSTRING from a file CHANNEL (FIX count and STRING stop),
PRINTSTRING with a count, CLOSE, and the game's FILE-TO-TTY.

Game use (77rooms.mud:954-985): HELP / INFO call <FILE-TO-TTY "MADADV" "HELP">
/ "INFO", which does <OPEN "READ" .FILE1 .FILE2 .DEV .SNM> (DEV "DSK", SNM
"MDL", set by SAVE-IT for MUDDLE > 100, :20-21), <FILE-LENGTH .CH>, then
ITER = ceil(LEN / 100) READSTRINGs into ,INBUF (<ISTRING 100>, :1539): every
chunk but the last by count (<READSTRING .BUF .CH .BUFLEN>), the last with
the stop STRING ,BREAKS = <STRING <ASCII 3> <ASCII 0>> (:958); each chunk is
written with <PRINTSTRING .BUF ,OUTCHAN .SLEN>; then CRLF and <CLOSE .CH>.

Read-only reference investigation. Nothing here is runtime code, and the game
sources under .cache/upstream are never written.

Usage (sandbox; TMPDIR must be writable):
    python3 -I scripts/probe_file_read_reference.py OUT.json [--shim-src C]

Protocol (run_case of scripts/probe_session_reference.py, as
scripts/probe_p0prims_reference.py):
  * one pinned mdli process per case, pipe mode, fixed clock (LD_PRELOAD of
    scripts/reference/fixed_time.c, MDL_FIXED_EPOCH=250776000, TZ=UTC);
  * every case runs in a FRESH COPY of the game directory under
    $TMPDIR/file-read-probes/<case>-*/game (never in .cache/upstream); cases
    that need an extra file create it in that copy only ("setup");
  * the bare interpreter (no game load) unless the case FLOADs the game;
  * every case ends with <QUIT>; error cases hold one failing form so that a
    LISTENING-AT-LEVEL 2 never hides a later result;
  * stdout is kept raw (latin-1); the file manifest of the copy before and
    after each run is compared (files_changed must be empty: nothing written);
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

OPEN_HELP = '<SET C <OPEN "READ" "MADADV" "HELP" "DSK" "MDL">>'
OPEN_INFO = '<SET C <OPEN "READ" "MADADV" "INFO" "DSK" "MDL">>'
BREAKS = "<SETG BREAKS <STRING <ASCII 3> <ASCII 0>>>"
BUF = "<SET B <ISTRING 100>>"
# 15 full 100-character chunks of MADADV.INFO (1527 = 15 * 100 + 27)
INFO_15 = "<REPEAT ((I 15)) <READSTRING .B .C 100> <AND <0? <SET I <- .I 1>>> <RETURN .I>>>"

# FILE-TO-TTY exactly as 77rooms.mud:960-985, with its globals
FILE_TO_TTY = [
    '<SETG DEV "DSK">', '<SETG SNM "MDL">', "<SETG INBUF <ISTRING 100>>", BREAKS,
    "<SETG TELL-FLAG <>>",
    '<DEFINE FILE-TO-TTY (FILE1 FILE2 "OPTIONAL" (DEV <VALUE DEV>) (SNM <VALUE SNM>) '
    '"AUX" (CH <OPEN "READ" .FILE1 .FILE2 .DEV .SNM>) LEN (BUF ,INBUF) (BUFLEN <LENGTH .BUF>) ITER) '
    '#DECL ((BUF FILE1 FILE2 DEV SNM) STRING (CH) <OR CHANNEL FALSE> (ITER LEN BUFLEN) FIX) '
    '<COND (.CH <UNWIND <PROG () <SET LEN <FILE-LENGTH .CH>> <SET ITER </ .LEN .BUFLEN>> '
    '<OR <0? <MOD .LEN .BUFLEN>> <SET ITER <+ .ITER 1>>> <CRLF ,OUTCHAN> <SETG TELL-FLAG T> '
    '<REPEAT (SLEN) #DECL ((SLEN) FIX) <COND (<1? .ITER> <SET SLEN <READSTRING .BUF .CH ,BREAKS>>) '
    '(<SET SLEN <READSTRING .BUF .CH .BUFLEN>>)> <PRINTSTRING .BUF ,OUTCHAN .SLEN> '
    '<COND (<0? <SET ITER <- .ITER 1>>> <CRLF ,OUTCHAN> <RETURN <CLOSE .CH>>)>>> <CLOSE .CH>>) '
    '(<TELL "File not found.">)>>',
]


def case(name, forms, note="", setup=None, timeout=60):
    return {"name": name, "cwd": "game", "note": note, "timeout": timeout,
            "setup": setup or [], "forms": forms, "input": "\n".join(forms) + "\n" + Q}


CASES = [
    case("muddle", [",MUDDLE"], "MUDDLE > 100 selects DEV \"DSK\", SNM \"MDL\" in SAVE-IT"),
    # --- OPEN "READ" ----------------------------------------------------------------------
    case("open-help", [OPEN_HELP, "<TYPE .C>", "<LENGTH .C>", "<CLOSE .C>"],
         "the game's 5-argument form; the printed CHANNEL shows its slots"),
    case("open-info", [OPEN_INFO, "<TYPE .C>", "<CLOSE .C>"], "the INFO file"),
    case("open-slots", [OPEN_HELP] + [f"<NTH .C {i}>" for i in range(1, 19)] + ["<CLOSE .C>"],
         "CHANNEL elements 1-18 one by one"),
    case("open-missing", ['<OPEN "READ" "NOSUCH" "FILE" "DSK" "MDL">'],
         "absent file in the game directory: FALSE payload (FILE-TO-TTY's File not found. branch)"),
    case("open-lowercase", ['<OPEN "READ" "madadv" "help" "DSK" "MDL">'],
         "case variant of the names: does Confusion fold case?"),
    case("open-lowercase-dir", ['<OPEN "READ" "MADADV" "HELP" "DSK" "mdl">'],
         "case variant of the directory"),
    case("open-other-device", ['<SET C <OPEN "READ" "MADADV" "HELP" "FOO" "MDL">>', "<TYPE .C>"],
         "another device name: is the device part of the file spec?"),
    case("open-four-args", ['<SET C <OPEN "READ" "MADADV" "HELP" "DSK">>', "<TYPE .C>"],
         "4-argument form (directory omitted)"),
    case("open-three-args", ['<SET C <OPEN "READ" "MADADV" "HELP">>', "<TYPE .C>"],
         "3-argument form"),
    case("open-one-spec", ['<SET C <OPEN "READ" "MDL/MADADV.HELP">>', "<TYPE .C>"],
         "one file-spec STRING form"),
    case("open-dir-as-file", ['<OPEN "READ" "MDL" "" "DSK" "">'], "a directory"),
    case("open-dotdot", ['<SET C <OPEN "READ" "MADADV" "HELP" "DSK" "MDL/../MDL">>', "<TYPE .C>"],
         "a directory with a parent component"),
    case("open-twice", [OPEN_HELP, '<SET D <OPEN "READ" "MADADV" "HELP" "DSK" "MDL">>',
                        "<==? .C .D>", "<FILE-LENGTH .D>", "<CLOSE .C>", "<CLOSE .D>"],
         "two channels on the same file"),
    # --- FILE-LENGTH ----------------------------------------------------------------------
    case("file-length-help", [OPEN_HELP, "<FILE-LENGTH .C>", "<TYPE <FILE-LENGTH .C>>",
                              "<CLOSE .C>"],
         "units: MADADV.HELP is 4274 bytes (855 36-bit words of 5 characters)"),
    case("file-length-info", [OPEN_INFO, "<FILE-LENGTH .C>", "<CLOSE .C>"],
         "units: MADADV.INFO is 1527 bytes"),
    case("file-length-after-read", [OPEN_INFO, BUF, "<READSTRING .B .C 100>",
                                    "<FILE-LENGTH .C>", "<CLOSE .C>"],
         "FILE-LENGTH after reading 100 characters (length, not remaining)"),
    case("err-file-length-inchan", ["<FILE-LENGTH .INCHAN>"], "terminal channel"),
    case("err-file-length-no-args", ["<FILE-LENGTH>"], "zero arguments"),
    case("err-file-length-string", ['<FILE-LENGTH "MDL/MADADV.HELP">'], "non-CHANNEL"),
    case("err-file-length-two-args", [OPEN_HELP, "<FILE-LENGTH .C .C>"], "two arguments"),
    case("err-file-length-closed", [OPEN_HELP, "<CLOSE .C>", "<FILE-LENGTH .C>"],
         "after CLOSE"),
    # --- READSTRING from a file channel ---------------------------------------------------
    case("readstring-count-100", [OPEN_HELP, BUF, "<READSTRING .B .C 100>", ".B",
                                  "<READSTRING .B .C 100>", ".B", "<CLOSE .C>"],
         "the game's count form: two successive 100-character chunks"),
    case("readstring-count-10", [OPEN_HELP, BUF, "<READSTRING .B .C 10>", ".B",
                                 "<READSTRING .B .C 10>", "<SUBSTRUC .B 0 20>", "<CLOSE .C>"],
         "count smaller than the buffer: the rest of the buffer is unchanged?"),
    case("readstring-count-0", [OPEN_HELP, BUF, "<READSTRING .B .C 0>", "<READSTRING .B .C 5>",
                                "<SUBSTRUC .B 0 5>", "<CLOSE .C>"],
         "count 0"),
    case("readstring-count-gt-buffer", [OPEN_HELP, "<SET B <ISTRING 5>>",
                                        "<READSTRING .B .C 10>", ".B", "<CLOSE .C>"],
         "count larger than the buffer"),
    case("readstring-count-negative", [OPEN_HELP, BUF, "<READSTRING .B .C -1>", "<CLOSE .C>"],
         "negative count"),
    case("readstring-two-args", [OPEN_HELP, BUF, "<READSTRING .B .C>", ".B", "<CLOSE .C>"],
         "no stop argument on a file channel"),
    case("readstring-stop-newline", [OPEN_HELP, BUF, "<READSTRING .B .C <STRING <ASCII 10>>>",
                                     "<SUBSTRUC .B 0 15>",
                                     "<READSTRING .B .C <STRING <ASCII 10>>>",
                                     "<READSTRING .B .C <STRING <ASCII 10>>>",
                                     "<SUBSTRUC .B 0 20>", "<CLOSE .C>"],
         "STRING stop: is the stop character consumed and not stored?"),
    case("readstring-breaks-info", [OPEN_INFO, BUF, BREAKS, INFO_15,
                                    "<READSTRING .B .C ,BREAKS>", "<SUBSTRUC .B 0 27>", ".B",
                                    "<CLOSE .C>"],
         "the last chunk: 15 x 100 by count, then ,BREAKS meets end of file after 27"),
    case("readstring-breaks-after-eof", [OPEN_INFO, BUF, BREAKS, INFO_15,
                                         "<READSTRING .B .C ,BREAKS>",
                                         "<READSTRING .B .C ,BREAKS>", "<CLOSE .C>"],
         "a second ,BREAKS read after end of file"),
    case("readstring-count-after-eof", [OPEN_INFO, BUF, BREAKS, INFO_15,
                                        "<READSTRING .B .C ,BREAKS>",
                                        "<READSTRING .B .C 100>", "<CLOSE .C>"],
         "a count read after end of file"),
    case("readstring-count-crosses-eof", [OPEN_INFO, BUF, INFO_15,
                                          "<READSTRING .B .C 100>", "<SUBSTRUC .B 0 27>",
                                          "<CLOSE .C>"],
         "a count read that meets end of file before the count"),
    case("readstring-count-crosses-eof-next", [OPEN_INFO, BUF, INFO_15,
                                               "<READSTRING .B .C 100>",
                                               "<READSTRING .B .C 100>", "<CLOSE .C>"],
         "the count read after one that met end of file"),
    case("readstring-whole-info", [OPEN_INFO, "<SET B <ISTRING 2000>>",
                                   "<READSTRING .B .C 2000>", "<CLOSE .C>"],
         "one count read larger than the file"),
    case("readstring-bang", [
        '<SET C <OPEN "READ" "BANG" "TXT" "DSK" "MDL">>', BUF,
        "<READSTRING .B .C 100>", "<SUBSTRUC .B 0 12>", "<CLOSE .C>"],
        "is ! an escape in a file channel? (file a!b!!c!<LF>de<LF>, 12 bytes, in the copy only)",
        setup=[["write", "MDL/BANG.TXT", "a!b!!c!\nde\n"]]),
    case("readstring-crlf", [
        '<SET C <OPEN "READ" "CRLF" "TXT" "DSK" "MDL">>', BUF, "<FILE-LENGTH .C>",
        "<READSTRING .B .C 100>", "<SUBSTRUC .B 0 6>", "<CLOSE .C>"],
        "CR LF in a file are stored raw? (file ab<CR><LF>cd, 6 bytes, in the copy only)",
        setup=[["write", "MDL/CRLF.TXT", "ab\r\ncd"]]),
    case("err-readstring-closed", [OPEN_HELP, BUF, "<CLOSE .C>", "<READSTRING .B .C 100>"],
         "READSTRING after CLOSE"),
    case("err-readstring-fix-stop-inchan", [BUF, "<READSTRING .B .INCHAN 0>"],
         "FIX stop on the terminal channel (count 0)"),
    # --- output to a READ file channel ----------------------------------------------------
    case("err-princ-read-channel", [OPEN_HELP, '<PRINC "x" .C>'], "PRINC to a READ channel"),
    case("err-printstring-read-channel", [OPEN_HELP, '<PRINTSTRING "x" .C>'],
         "PRINTSTRING to a READ channel"),
    case("err-crlf-read-channel", [OPEN_HELP, "<CRLF .C>"], "CRLF to a READ channel"),
    # --- PRINTSTRING with a count -----------------------------------------------------------
    case("printstring-count", ['<PRINTSTRING "abcdef" ,OUTCHAN 3>',
                               '<PRINTSTRING "abcdef" ,OUTCHAN 0>',
                               '<PRINTSTRING "abcdef" ,OUTCHAN 6>'],
         "PRINTSTRING with a count: output and value"),
    case("err-printstring-count-too-big", ['<PRINTSTRING "abc" ,OUTCHAN 5>'],
         "count larger than the STRING"),
    # --- CLOSE ---------------------------------------------------------------------------
    case("close-value", [OPEN_HELP, "<SET D <CLOSE .C>>", "<==? .D .C>", "<TYPE .D>"],
         "CLOSE's value"),
    case("close-double", [OPEN_HELP, "<CLOSE .C>", "<CLOSE .C>", "<TYPE <CLOSE .C>>"],
         "CLOSE of a closed channel"),
    case("close-after-read", [OPEN_INFO, BUF, "<READSTRING .B .C 100>", "<CLOSE .C>"],
         "CLOSE after a read"),
    case("err-close-no-args", ["<CLOSE>"], "zero arguments"),
    case("err-close-string", ['<CLOSE "x">'], "non-CHANNEL"),
    # --- FILE-TO-TTY (bare interpreter, the game's definition) ----------------------------
    case("file-to-tty-info", FILE_TO_TTY + ['<FILE-TO-TTY "MADADV" "INFO">', ",TELL-FLAG"],
         "FILE-TO-TTY of 77rooms.mud:960 on INFO: output, value, TELL-FLAG"),
    case("file-to-tty-help", FILE_TO_TTY + ['<FILE-TO-TTY "MADADV" "HELP">'],
         "FILE-TO-TTY on HELP"),
    case("file-to-tty-missing", FILE_TO_TTY + ['<SETG TELL <FUNCTION (S) <PRINC .S> <CRLF> T>>',
                                               '<FILE-TO-TTY "NOSUCH" "FILE">'],
         "FILE-TO-TTY on an absent file (TELL stubbed as PRINC + CRLF)"),
    # --- in the game ------------------------------------------------------------------------
    {"name": "game-help-info", "cwd": "game", "note": "faithful boot, then help, info, ?, quit y",
     "timeout": 120, "setup": [], "forms": None,
     "input": psr.ENTRY + "help\ninfo\n?\nquit\ny\n"},
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
    base = Path(os.environ.get("TMPDIR", "/tmp")) / "file-read-probes"
    base.mkdir(parents=True, exist_ok=True)
    shim = psr.build_shim(a.shim_src, Path(tempfile.mkdtemp(prefix="shim-", dir=base)))
    rows = []
    for c in CASES:
        row = psr.run_case(c, base, shim)
        row["forms"] = c["forms"]
        for k in ("files_before", "changed_file_text"):
            row.pop(k, None)
        rows.append(row)
    game = psr.GAME / "MDL"
    head = subprocess.run(["git", "-C", str(psr.UPSTREAM_ROOT), "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    setup_files = {"MDL/BANG.TXT", "MDL/CRLF.TXT"}
    res = {
        "schema_version": 1,
        "kind": "m4-file-read-reference",
        "engine": "confusion-patched-1977",
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "interpreter": ".cache/build/confusion_patched/mdli",
        "interpreter_sha256_before": before,
        "interpreter_sha256_after": psr.sha256_file(psr.EXE),
        "upstream_mdlzork_checked_out": head,
        "game_dir": "mdlzork_771212/patched_confusion",
        "files": {name: {"size": (game / name).stat().st_size,
                         "sha256": psr.sha256_file(game / name)}
                  for name in ("MADADV.HELP", "MADADV.INFO")},
        "fixed_epoch": psr.EPOCH, "tz": "UTC",
        "shim_src_sha256": psr.sha256_file(a.shim_src),
        "protocol": "scripts/probe_file_read_reference.py (module docstring)",
        "checks": {
            # bare-interpreter cases write nothing; the game case's SAVE-IT
            # and QUIT write MADADV.SAVE and ZORK.LOG natively (in the copy)
            "no_primitive_case_changed_a_file": all(
                set(r["files_changed"]) <= setup_files and not r["files_removed"]
                for r in rows if not r["name"].startswith("game-")),
            "game_case_files_changed": sorted(
                next(r for r in rows if r["name"].startswith("game-"))["files_changed"]),
        },
        "cases": rows,
    }
    text = json.dumps(res, indent=2, ensure_ascii=False) + "\n"
    tmp = os.environ.get("TMPDIR", "/tmp").rstrip("/")
    text = text.replace(tmp, "$TMPDIR").replace(str(psr.ROOT), "<repo>")
    a.output.write_text(text, encoding="utf-8")
    ok = before == res["interpreter_sha256_after"] and res["checks"]["no_primitive_case_changed_a_file"]
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
