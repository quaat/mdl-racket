#!/usr/bin/env python3
"""Pinned-Confusion reference probes for MEMBER and for `!` in READSTRING input.

Read-only reference investigation (2026-11-23). Confusion (GPLv3) is executed
as a reference only; nothing here is runtime code.

Usage (from the repository root):
    python3 -I docs/evidence/M3/member-bang-probe.py member \
        docs/evidence/M3/member-probe.json
    python3 -I docs/evidence/M3/member-bang-probe.py bang \
        docs/evidence/M3/readstring-bang-probe.json

Protocol
- The interpreter SHA-256 is checked before any case runs; the script aborts
  unless it equals PINNED_SHA256.
- One mdli process per case. cwd is a fresh directory under
  $TMPDIR/mb-probe-work: empty ("cwd": "empty") or a byte copy of the
  patched_confusion game directory ("cwd": "game"). The script never runs
  anything in .cache/upstream.
- "mode": "pipe" (default) feeds the input bytes on a pipe (stdin is not a
  tty) and captures stdout and stderr separately. "mode": "pty" runs mdli on
  a pseudo-terminal through pexpect with ECHO off; stdout and stderr share
  the pty, so they are recorded together in stdout_raw. A pty end of input is
  sent as ^D (0x04, VEOF) at the start of a line.
- "fixed_clock": true LD_PRELOADs the fixed_time shim (built into the work
  directory from the #131 worktree's scripts/reference/fixed_time.c, or
  MDL_FIXED_TIME_C) with MDL_FIXED_EPOCH=250776000, TZ=UTC: the approved
  house-boot settings.
- Raw stdout/stderr are decoded as latin-1 so every byte (CR, ESC, >127) is
  preserved; input bytes are also recorded as hex.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(os.environ.get("MDL_REPO_ROOT", Path(__file__).resolve().parents[3]))
EXE = ROOT / ".cache/build/confusion_patched/mdli"
GAME = ROOT / ".cache/upstream/mdlzork/mdlzork_771212/patched_confusion"
PINNED_SHA256 = "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789"
TMP = Path(os.environ.get("TMPDIR", "/tmp"))
WORK = TMP / "mb-probe-work"
SHIM_C = Path(os.environ.get(
    "MDL_FIXED_TIME_C",
    ROOT / ".claude/worktrees/agent-a64a330470b6b2df4/scripts/reference/fixed_time.c"))
EPOCH = "250776000"
LISTENING = "LISTENING-AT-LEVEL 1 PROCESS 1\n"
Q = "<QUIT>\n"


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def snapshot(d: Path) -> dict:
    return {str(p.relative_to(d)): (p.stat().st_size, sha(p))
            for p in sorted(d.rglob("*")) if p.is_file()}


def canon(t: str) -> str:
    return t.replace("\r\n", "\n").replace("\r", "\n")


# --------------------------------------------------------------------------
# MEMBER cases. Each case is a sequence of top-level forms on stdin followed by
# <QUIT>. Error cases are one form per process so a LISTENING-AT-LEVEL 2 never
# hides a later result.

def m(name, forms, note=""):
    return {"name": name, "note": note, "input": "\n".join(forms) + "\n" + Q}


MEMBER_CASES = [
    # Structural search on LIST / VECTOR / UVECTOR (=? semantics)
    m("list-hit", ["<MEMBER 2 '(1 2 3)>"]),
    m("list-miss", ["<MEMBER 4 '(1 2 3)>"]),
    m("list-first-of-duplicates", ["<MEMBER 2 '(1 2 3 2 5)>", "<LENGTH <MEMBER 2 '(1 2 3 2 5)>>"]),
    m("list-empty", ["<MEMBER 1 ()>"]),
    m("list-nested-equal", ["<MEMBER '(1 2) '(0 (1 2) 3)>"]),
    m("list-nested-kind-differs", ["<MEMBER '[1 2] '(0 (1 2) 3)>"]),
    m("list-deep-nested", ["<MEMBER '(1 [2 \"x\"]) '(0 (1 [2 \"x\"]) 3)>"]),
    m("fix-vs-float", ["<MEMBER 2 '(1 2.0 3)>", "<MEMBER 2.0 '(1 2 2.0)>", "<MEMBER 2.0 '(1 2.0)>"]),
    m("atom-element", ["<MEMBER FOO '(BAR FOO BAZ)>", "<MEMBER FOO '(BAR BAZ)>"]),
    m("character-element", ["<MEMBER !\\b '(!\\a !\\b)>", "<MEMBER !\\B '(!\\a !\\b)>"]),
    m("false-element", ["<MEMBER <> '(1 #FALSE () 2)>", "<MEMBER #FALSE (1) '(#FALSE () #FALSE (1) 2)>"]),
    m("string-element-list", ["<MEMBER \"abc\" '(\"x\" \"abc\" \"y\")>"]),
    m("string-element-distinct-object", ["<MEMBER <STRING \"ab\" \"c\"> '(\"x\" \"abc\")>"]),
    m("memq-contrast-distinct-string", ["<MEMQ <STRING \"ab\" \"c\"> '(\"x\" \"abc\")>"]),
    m("string-needle-vector-no-substring", ["<MEMBER \"a\" [\"abc\" \"xa\"]>", "<MEMBER \"abc\" [\"xabcx\" \"abc\"]>"],
      "STRING needle, non-STRING haystack: element search, not substring"),
    m("string-needle-char-list", ["<MEMBER \"a\" '(!\\a)>"]),
    m("vector-hit", ["<MEMBER \"B\" [\"A\" \"B\" \"C\"]>", "<TYPE <MEMBER \"B\" [\"A\" \"B\" \"C\"]>>"]),
    m("uvector-hit", ["<MEMBER 2 ![1 2 3!]>", "<TYPE <MEMBER 2 ![1 2 3!]>>", "<MEMBER 4 ![1 2 3!]>"]),
    m("winners-vector", [
        "<SETG WINNERS '[\"BKD\" \"TAA\" \"MARC\" \"PDL\" \"MDL\"]>",
        "<MEMBER \"MARC\" ,WINNERS>", "<MEMBER \"MTRZORK\" ,WINNERS>",
        "<MEMBER \"MAR\" ,WINNERS>", "<MEMBER \"marc\" ,WINNERS>",
        "<MEMBER <STRING \"MD\" \"L\"> ,WINNERS>"],
      "77rooms.mud:254 WINNERS shape; HANDLE 77rooms.mud:220, SAVE-IT :33, ILO 77act1.mud:17-18"),
    m("lexv-empty-string-search", [
        "<SETG LEXV <IVECTOR 4 '<REST <ISTRING 5> 5>>>",
        "<MEMBER \"\" ,LEXV>", "<==? <MEMBER \"\" ,LEXV> ,LEXV>",
        "<PUT ,LEXV 1 <STRING \"ROBOT\">>", "<PUT ,LEXV 2 <STRING \"GO\">>",
        "<MEMBER \"\" ,LEXV>", "<LENGTH <MEMBER \"\" ,LEXV>>", "<REST <MEMBER \"\" ,LEXV>>",
        "<MEMBER \"\" [\"A\" \"B\"]>"],
      "COMMAND 77rooms.mud:1745 <REST <MEMBER \"\" ,LEXV>>; LEXV shape 77rooms.mud:1555"),
    m("list-alias", ["<SET L (1 2 3)>", "<PUT <MEMBER 2 .L> 1 99>", ".L",
                     "<==? <MEMBER 99 .L> <REST .L 1>>", "<==? <MEMBER 1 .L> .L>"]),
    m("vector-alias", ["<SET V [1 2 3]>", "<PUT <MEMBER 2 .V> 1 99>", ".V",
                       "<==? <MEMBER 99 .V> <REST .V 1>>", "<==? <MEMBER 1 .V> .V>"]),
    m("uvector-alias", ["<SET U ![1 2 3!]>", "<PUT <MEMBER 2 .U> 1 99>", ".U",
                        "<==? <MEMBER 99 .U> <REST .U 1>>"]),
    m("rest-view-haystack", ["<MEMBER 1 <REST '(1 2 1 3) 1>>", "<MEMBER 1 <REST [1 2 1 3] 1>>",
                             "<MEMBER 1 <REST [1 2 3] 1>>"]),
    m("typed-structure", ["<MEMBER 2 <CHTYPE (1 2 3) FORM>>",
                          "<TYPE <MEMBER 2 <CHTYPE (1 2 3) FORM>>>",
                          "<NEWTYPE MYV VECTOR>", "<MEMBER 2 <CHTYPE [1 2 3] MYV>>",
                          "<TYPE <MEMBER 2 <CHTYPE [1 2 3] MYV>>>"]),
    m("false-haystack", ["<MEMBER 1 <>>", "<MEMBER 1 #FALSE (1 2)>"],
      "FALSE has PRIMTYPE LIST, so it is structured"),
    # STRING needle in STRING haystack (substring search)
    m("str-manual-example", ["<MEMBER \"PART\" \"SUM OF PARTS\">"], "manual 8.2.2 example"),
    m("str-miss", ["<MEMBER \"XYZ\" \"SUM OF PARTS\">"]),
    m("str-match-at-start", ["<MEMBER \"SUM\" \"SUM OF PARTS\">", "<MEMBER \"S\" \"SUM OF PARTS\">"]),
    m("str-match-at-end", ["<MEMBER \"TS\" \"SUM OF PARTS\">", "<MEMBER \"PARTS\" \"SUM OF PARTS\">"]),
    m("str-equal", ["<MEMBER \"abc\" \"abc\">"]),
    m("str-needle-longer", ["<MEMBER \"abcd\" \"abc\">", "<MEMBER \"xabc\" \"abc\">"]),
    m("str-empty-needle", ["<MEMBER \"\" \"abc\">", "<LENGTH <MEMBER \"\" \"abc\">>"]),
    m("str-empty-needle-variants", ["<MEMBER <REST \"xyz\" 3> \"abc\">", "<MEMBER <ISTRING 0> \"abc\">",
                                    "<MEMBER \"\" <REST \"abc\" 3>>", "<MEMBER \"\" \"\">",
                                    "<MEMBER \"\" <ISTRING 3>>", "<LENGTH <MEMBER \"\" <ISTRING 3>>>"]),
    m("str-empty-needle-storage", ["<MEMBER \"\" <STRING \"ab\" \"c\">>", "<MEMBER \"\" <ISTRING 3 !\\a>>",
                                   "<MEMBER \"\" <SUBSTRUC \"abcdef\" 0 3>>",
                                   "<MEMBER <REST <STRING \"x\" \"y\"> 2> \"abc\">",
                                   "<MEMBER \"\" <STRING \"ab\" <ASCII 0> \"cd\">>"],
      "does the empty-needle result depend on the bytes stored after the needle/haystack?"),
    m("str-empty-haystack",["<MEMBER \"a\" \"\">", "<MEMBER \"a\" <REST \"abc\" 3>>"]),
    m("str-nul-needle", ["<MEMBER <STRING <ASCII 0>> \"abc\">", "<MEMBER <STRING <ASCII 0>> <STRING \"ab\" <ASCII 0>>>"],
      "probes for out-of-bounds matching past the haystack end"),
    m("str-case-sensitive", ["<MEMBER \"part\" \"SUM OF PARTS\">"]),
    m("str-first-of-multiple", ["<MEMBER \"AB\" \"xABAB\">", "<LENGTH <MEMBER \"AB\" \"xABAB\">>"]),
    m("str-backtrack", ["<MEMBER \"aab\" \"aaab\">"]),
    m("str-rest-haystack", ["<MEMBER \"b\" <REST \"abcb\" 2>>", "<MEMBER \"ab\" <REST \"abab\" 1>>",
                            "<MEMBER \"a\" <REST \"abc\" 1>>"]),
    m("str-rest-needle", ["<MEMBER <REST \"xLEDG\" 1> \"CLEDG\">"]),
    m("str-result-type", ["<TYPE <MEMBER \"b\" \"abc\">>"]),
    m("str-alias", ["<SET S <STRING \"RIVR3\">>", "<SET M <MEMBER \"VR\" .S>>", "<LENGTH .M>",
                    "<PUT .M 1 !\\Z>", ".S", "<==? .M <REST .S 2>>", "<=? .M <REST .S 2>>"]),
    m("str-identity-offset0", ["<SET B <STRING \"ECHO\">>", "<==? <MEMBER \"ECHO\" .B> .B>",
                               "<==? <MEMBER \"CHO\" .B> .B>", "<SET B2 <STRING \"XECHO\">>",
                               "<==? <MEMBER \"ECHO\" .B2> .B2>",
                               "<SET B3 <ISTRING 10 !\\x>>", "<PUT .B3 1 !\\E>", "<PUT .B3 2 !\\C>",
                               "<PUT .B3 3 !\\H>", "<PUT .B3 4 !\\O>", "<==? <MEMBER \"ECHO\" .B3> .B3>"],
      "ECHO-ROOM 77act1.mud:1096 <==? <MEMBER \"ECHO\" <UPPERCASE .B>> .B>"),
    m("str-spname-haystack", ["<MEMBER \"RIVR\" <SPNAME RIVR4>>", "<MEMBER \"LEDG\" <SPNAME LEDG2>>",
                              "<MEMBER \"VAIR\" <SPNAME VAIR1>>", "<MEMBER \"ALI\" <SPNAME ALICE>>",
                              "<MEMBER \"ALI\" <SPNAME ALITR>>", "<MEMBER \"RIVR\" <SPNAME RAVINE>>",
                              "<TYPE <SPNAME FOO>>"],
      "room-id idiom in 77act2/77act3"),
    m("str-character-needle", ["<MEMBER !\\b \"abc\">", "<MEMBER !\\z \"abc\">", "<MEMBER !\\B \"abc\">",
                               "<MEMQ !\\b \"abc\">"]),
    m("str-fix-needle", ["<MEMBER 98 \"abc\">"]),
    m("str-atom-needle", ["<MEMBER abc \"abc\">"]),
    m("str-list-needle", ["<MEMBER '(1) \"abc\">"]),
    m("str-typed", ["<NEWTYPE MYS STRING>", "<MEMBER \"b\" <CHTYPE \"abc\" MYS>>",
                    "<TYPE <MEMBER \"b\" <CHTYPE \"abc\" MYS>>>", "<MEMBER <CHTYPE \"b\" MYS> \"abc\">",
                    "<MEMBER <CHTYPE \"b\" MYS> <CHTYPE \"abc\" MYS>>",
                    "<MEMBER <CHTYPE \"b\" MYS> '(\"b\")>"]),
    # Errors (one per process)
    m("err-arity-0", ["<MEMBER>"]),
    m("err-arity-1", ["<MEMBER 1>"]),
    m("err-arity-3", ["<MEMBER 1 '(1) 2>"]),
    m("err-nonstructured-fix", ["<MEMBER 1 2>"]),
    m("err-nonstructured-atom", ["<MEMBER 1 FOO>"]),
    m("err-string-needle-fix-haystack", ["<MEMBER \"a\" 5>"]),
    m("err-character-haystack", ["<MEMBER \"a\" !\\a>"]),
]


# --------------------------------------------------------------------------
# `!` in READSTRING input. RS is the game's READER-STRING (77rooms.mud:598).

RS = "<SETG RS <STRING <ASCII 27> <ASCII 13> <ASCII 10>>>\n"
SHOW = "<PRINT <MAPF ,VECTOR ,ASCII .B>>"


def rs_case(name, bufsize, nreads, typed, note="", mode="pipe", quit=True):
    """Buffer filled with '.', nreads READSTRINGs; typed input follows the
    PROG's closing '>' on the same line (the REPL reader does not consume it)."""
    reads = " ".join(f"<PRINT <READSTRING .B ,INCHAN ,RS>> <PRINT .B> {SHOW}"
                     for _ in range(nreads))
    text = (RS + f"<SET B <ISTRING {bufsize} !\\.>>\n<PROG () {reads}>" + typed
            + (Q if quit else ""))
    return {"name": name, "note": note, "mode": mode, "input": text}


BOOT = '<FLOAD "77loadall.mud">\n<SAVE-IT>\n'


def boot(name, typed, note="", mode="pipe"):
    return {"name": name, "note": note, "mode": mode, "cwd": "game",
            "fixed_clock": True, "timeout": 120, "input": BOOT + typed}


BANG_CASES = [
    rs_case("bang-mid", 10, 1, "Ab!cD\n", "maintainer example: expect AbcD"),
    rs_case("bang-double", 10, 1, "!!\n"),
    rs_case("bang-double-between", 10, 1, "a!!b\n"),
    rs_case("bang-multiple", 10, 1, "!a!b!c\n", "multiple escapes; count vs stored"),
    rs_case("bang-before-lf", 10, 2, "ab!\nXY\n", "escaped LF: stop or stored?"),
    rs_case("bang-before-cr", 10, 2, "ab!\rXY\n", "escaped CR (stop char)"),
    rs_case("bang-before-crlf", 10, 3, "ab!\r\ncd\n"),
    rs_case("bang-before-esc", 10, 2, "ab!\x1bXY\n", "escaped ESC (altmode, stop char)"),
    rs_case("bang-before-tab", 10, 1, "a!\tb\n", "escaped non-stop control char"),
    rs_case("bang-before-backslash", 10, 1, "a!\\b\n"),
    rs_case("backslash-plain", 10, 1, "a\\b\n", "\\ is not an escape in READSTRING?"),
    rs_case("bang-before-eof", 10, 2, "ab!", "trailing ! immediately before EOF", quit=False),
    rs_case("bang-only-eof", 10, 2, "!", "lone ! then EOF", quit=False),
    rs_case("bang-buffer-boundary-last-slot", 3, 2, "ab!cd\n",
            "!c pair lands in the last buffer slot"),
    rs_case("bang-buffer-boundary-straddle", 2, 2, "ab!cd\n",
            "buffer fills after 'ab'; the next read starts at '!'"),
    rs_case("bang-buffer-boundary-2", 2, 2, "a!bc\n"),
    rs_case("nonascii-latin1", 10, 1, "a\xe9b\n", "single byte 0xE9"),
    rs_case("nonascii-utf8", 10, 1, "a\xc3\xa9b\n", "UTF-8 e-acute (2 bytes)"),
    rs_case("bang-before-nonascii", 10, 1, "a!\xe9b\n"),
    rs_case("nul-and-del", 10, 1, "a\x00b\x7fc\n", "NUL and DEL bytes"),
    {"name": "bang-fix-stop", "note": "FIX stop count with ! (not used by the game)", "mode": "pipe",
     "input": f"<SET B <ISTRING 10 !\\.>>\n<PROG () <PRINT <READSTRING .B ,INCHAN 3>> <PRINT .B> {SHOW}>!abcd\n" + Q},
    # PTY variants (ECHO off; ^D = 0x04 is VEOF in canonical mode)
    rs_case("pty-bang-mid", 10, 1, "Ab!cD\n", mode="pty"),
    rs_case("pty-bang-double", 10, 1, "!!\n", mode="pty"),
    rs_case("pty-bang-before-lf", 10, 2, "ab!\nXY\n", mode="pty"),
    rs_case("pty-bang-before-cr", 10, 2, "ab!\rXY\n", "pty ICRNL maps CR to LF", mode="pty"),
    rs_case("pty-bang-before-esc", 10, 2, "ab!\x1bXY\n", mode="pty"),
    rs_case("pty-bang-before-eof", 10, 2, "ab!\x04\x04",
            "first ^D pushes the partial line 'ab!', the second gives EOF", mode="pty", quit=False),
    rs_case("pty-bang-buffer-boundary", 3, 2, "ab!cd\n", mode="pty"),
    rs_case("pty-nonascii-latin1", 10, 1, "a\xe9b\n", mode="pty"),
    # Game RDCOM (FLOAD 77loadall.mud + SAVE-IT, fixed clock, pipe)
    boot("game-baseline-north", "north\n", "control: unescaped command"),
    boot("game-bang-mid-word", "nor!th\n"),
    boot("game-bang-first", "!north\n"),
    boot("game-mixed-case-bang", "Ab!cD\n"),
    boot("game-bang-double", "!!\n"),
    boot("game-bang-before-lf", "north!\nwest\n"),
    boot("game-bang-before-esc", "north!\x1bwest\n"),
    boot("game-bang-before-eof", "north!"),
    boot("game-buffer-boundary", "x" * 99 + "!yz\nlook\n",
         "INBUF is ISTRING 100 (77rooms.mud); !y lands in slot 100"),
    boot("game-nonascii", "nor\xe9th\nnorth\n"),
    boot("pty-game-bang-mid-word", "nor!th\n\x04", mode="pty"),
]


# --------------------------------------------------------------------------

def build_shim() -> Path:
    so = WORK / "fixed_time.so"
    if not so.exists():
        if not SHIM_C.is_file():
            raise SystemExit(f"fixed_time.c not found at {SHIM_C}")
        subprocess.run(["gcc", "-shared", "-fPIC", "-O2", "-o", str(so), str(SHIM_C), "-ldl"],
                       check=True)
    return so


def run_pipe(d, env, data, timeout):
    try:
        r = subprocess.run([str(EXE)], input=data, capture_output=True, cwd=d,
                           env=env, timeout=timeout)
        return r.returncode, r.stdout.decode("latin-1"), r.stderr.decode("latin-1")
    except subprocess.TimeoutExpired as e:
        return ("timeout", (e.stdout or b"").decode("latin-1"),
                (e.stderr or b"").decode("latin-1") + "\nTIMEOUT")


def run_pty(d, env, data, timeout):
    import pexpect
    child = pexpect.spawn(str(EXE), [], cwd=str(d), env=env, echo=False,
                          timeout=timeout, encoding=None, dimensions=(40, 200))
    child.delaybeforesend = None
    time.sleep(0.3)
    # Send line by line so no canonical line exceeds the pty line buffer.
    for line in data.split(b"\n")[:-1]:
        child.send(line + b"\n")
    tail = data.split(b"\n")[-1]
    if tail:
        for b in tail:
            child.send(bytes([b]))
            time.sleep(0.05)
    status = None
    try:
        child.expect(pexpect.EOF)
        out = child.before
    except pexpect.TIMEOUT:
        out = child.before + b"\nTIMEOUT"
        status = "timeout"
    child.close(force=True)
    if status is None:
        status = child.exitstatus if child.exitstatus is not None else f"signal {child.signalstatus}"
    return status, out.decode("latin-1"), "(pty: stderr is merged into stdout_raw)"


def main() -> int:
    suite, out_path = sys.argv[1], Path(sys.argv[2])
    cases = {"member": MEMBER_CASES, "bang": BANG_CASES}[suite]
    got = sha(EXE)
    if got != PINNED_SHA256:
        raise SystemExit(f"interpreter sha256 {got} != pinned {PINNED_SHA256}")
    lock = json.loads((ROOT / "sources.lock.json").read_text())
    WORK.mkdir(parents=True, exist_ok=True)
    shim = build_shim() if any(c.get("fixed_clock") for c in cases) else None
    rows = []
    for c in cases:
        d = Path(tempfile.mkdtemp(prefix=c["name"] + "-", dir=WORK))
        if c.get("cwd") == "game":
            shutil.copytree(GAME, d, dirs_exist_ok=True)
        before = snapshot(d)
        env = dict(os.environ)
        if c.get("fixed_clock"):
            env.update({"LD_PRELOAD": str(shim), "MDL_FIXED_EPOCH": EPOCH, "TZ": "UTC"})
        data = c["input"].encode("latin-1")
        mode = c.get("mode", "pipe")
        pre_sha = sha(EXE)
        runner = run_pty if mode == "pty" else run_pipe
        status, out, err = runner(d, env, data, c.get("timeout", 30))
        after = snapshot(d)
        changed = {k: {"before": before.get(k), "after": v}
                   for k, v in after.items() if before.get(k) != v}
        co = canon(out)
        _, marker, result = co.partition(LISTENING)
        rows.append({
            "name": c["name"], "note": c.get("note", ""), "mode": mode,
            "cwd_kind": c.get("cwd", "empty"), "fixed_clock": bool(c.get("fixed_clock")),
            "interpreter_sha256_checked": pre_sha,
            "command": f"<repo>/{EXE.relative_to(ROOT)} (no args), cwd=$TMPDIR/mb-probe-work/{d.name}, stdin={mode}",
            "input": c["input"], "input_hex": data.hex(),
            "exit_status": status, "stdout_raw": out, "stdout_canonical": co,
            "result_after_listening": result if marker else None,
            "stderr_raw": err, "files_created_or_changed": changed,
        })
        print(f"{c['name']}: exit={status} changed={list(changed)}")
    res = {
        "schema_version": 1, "name": f"m3-{suite}-reference",
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "interpreter": str(EXE.relative_to(ROOT)), "interpreter_sha256": got,
        "upstream_mdlzork_commit": lock["sources"]["mdlzork"]["commit"],
        "upstream_mit_zork_commit": lock["sources"]["mit_zork"]["commit"],
        "protocol": ("member-bang-probe.py; one mdli process per case; cwd fresh "
                     "$TMPDIR/mb-probe-work dir (game cases: byte copy of patched_confusion); "
                     "never .cache/upstream; pipe stdin unless mode=pty"),
        "cases": rows,
    }
    out_path.write_text(json.dumps(res, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
