#!/usr/bin/env python3
"""Pinned-Confusion reference probes for a complete local session (QUIT),
OPEN failure payloads, and the clock -> RANDOM seed chain.

Read-only reference investigation (M3). Nothing here is runtime code.

Usage (sandbox; TMPDIR must be writable):
    python3 -I scripts/probe_session_reference.py session OUT.json [--shim-src C]
    python3 -I scripts/probe_session_reference.py open    OUT.json [--shim-src C]
    python3 -I scripts/probe_session_reference.py seed    OUT.json [--shim-src C]

Protocol (same as scripts/boot_reference.py, PR #131):
  * every case runs one pinned mdli process in a FRESH copy of
    .cache/upstream/mdlzork/mdlzork_771212/patched_confusion under
    $TMPDIR/session-probes/<case>-*/game (never in .cache/upstream);
    SAVEFILE/ZORK.SAVE is removed from the copy before boot (STALE_BOOT_FILES);
  * fixed wall clock: LD_PRELOAD of fixed_time.so compiled from
    scripts/reference/fixed_time.c (BOOT-REF branch) with MDL_FIXED_EPOCH and
    TZ=UTC unless a case says otherwise;
  * entry: <FLOAD "77loadall.mud"> then <SAVE-IT>, then game commands;
  * "pipe" cases feed all stdin bytes at once and record raw stdout/stderr
    (latin-1, so CR is kept); "pty" cases drive pexpect like boot_reference.py
    and record per-step output;
  * file manifests (size, sha256, octal mode) of the game copy before and
    after the run, plus the content of small created text files;
  * "diagnostic" cases add an MDL prelude that wraps SUBRs and logs to a
    side file OUTSIDE the game copy (DIAG.LOG); their stdout is not a
    transcript, and they are labelled diagnostic in the JSON.

Confusion is GPLv3 and is used only as a behaviour reference; no Confusion
source is copied into this script.
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

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / ".cache/build/confusion_patched/mdli"
UPSTREAM_ROOT = ROOT / ".cache/upstream/mdlzork"
GAME = UPSTREAM_ROOT / "mdlzork_771212/patched_confusion"
DEFAULT_SHIM_SRC = ROOT / "scripts/reference/fixed_time.c"
STALE_BOOT_FILES = ("SAVEFILE/ZORK.SAVE",)
ENTRY = '<FLOAD "77loadall.mud">\n<SAVE-IT>\n'
EPOCH = 250776000  # 1977-12-12 12:00:00 UTC (tests/scenarios/house-boot.json)
SIX = ["north", "west", "open mailbox", "take leaflet", "inventory", "score"]
YESNO_TEXT = "Do you wish to leave the game? (Y is affirmative): "


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def sha256_file(p: Path) -> str:
    return sha256_bytes(p.read_bytes())


def manifest(d: Path) -> dict:
    out = {}
    for p in sorted(d.rglob("*")):
        rel = p.relative_to(d).as_posix()
        st = p.lstat()
        mode = oct(stat.S_IMODE(st.st_mode))
        if p.is_dir():
            out[rel + "/"] = {"mode": mode}
        elif p.is_file():
            try:
                h = sha256_file(p)
            except PermissionError:
                h = "UNREADABLE"
            out[rel] = {"size": st.st_size, "sha256": h, "mode": mode}
    return out


def canon(t: str) -> str:
    return t.replace("\r\n", "\n").replace("\r", "\n")


def build_shim(src: Path, out_dir: Path) -> Path:
    so = out_dir / "fixed_time.so"
    r = subprocess.run(["gcc", "-shared", "-fPIC", "-O2", "-o", str(so), str(src), "-ldl"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit("shim build failed:\n" + r.stderr)
    return so


def mstr(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def diag_prelude(log: Path, wrap: list[str], fake_open: str | None = None) -> str:
    """MDL text typed into LISTEN BEFORE <FLOAD>: opens the side log and wraps
    the named SUBRs (RANDOM, GETTIMEDATE, READSTRING, OPEN, CLOSE, QUIT).
    Logging only; every wrapper applies the original SUBR to the same args
    and returns its value unchanged (except OPEN when fake_open is given)."""
    lines = [
        f"<SETG DIAG-CH <OPEN \"PRINT\" {mstr(str(log))}>>",
        "<SETG DIAG-OPENS 0>",
        "<SETG DIAG <FUNCTION (DIAG-T DIAG-X) <PRINC .DIAG-T ,DIAG-CH> "
        "<PRINC \" \" ,DIAG-CH> <PRIN1 .DIAG-X ,DIAG-CH> <CRLF ,DIAG-CH> T>>",
    ]
    for name in wrap:
        orig = f"DIAG-ORIG-{name}"
        lines.append(f"<SETG {orig} ,{name}>")
        if name == "READSTRING":
            body = (f"<SET DIAG-R <APPLY ,{orig} !.DIAG-A>> "
                    f"<DIAG \"READSTRING-COUNT\" .DIAG-R> "
                    f"<DIAG \"READSTRING-TEXT\" <SUBSTRUC <1 .DIAG-A> 0 .DIAG-R>> .DIAG-R")
        elif name == "QUIT":
            body = (f"<DIAG \"QUIT-NARGS\" <LENGTH .DIAG-A>> <CLOSE ,DIAG-CH> "
                    f"<APPLY ,{orig} !.DIAG-A>")
        elif name == "OPEN" and fake_open:
            # fake_open: MDL expression evaluated instead of the real OPEN for
            # ZORK LOG opens (diagnostic of RECORD's control flow only).
            body = (f"<DIAG \"OPEN-ARGS\" <LIST !.DIAG-A>> <SETG DIAG-OPENS <+ ,DIAG-OPENS 1>> "
                    f"<SET DIAG-R <COND (<AND <G? <LENGTH .DIAG-A> 2> <=? <3 .DIAG-A> \"LOG\">> {fake_open}) "
                    f"(T <APPLY ,{orig} !.DIAG-A>)>> "
                    f"<DIAG \"OPEN-RESULT\" .DIAG-R> .DIAG-R")
        elif name == "OPEN":
            body = (f"<DIAG \"OPEN-ARGS\" <LIST !.DIAG-A>> <SET DIAG-R <APPLY ,{orig} !.DIAG-A>> "
                    f"<DIAG \"OPEN-RESULT\" <COND (<TYPE? .DIAG-R CHANNEL> CHANNEL) (T .DIAG-R)>> .DIAG-R")
        elif name == "CLOSE":
            body = (f"<DIAG \"CLOSE-ARG-TYPE\" <TYPE <1 .DIAG-A>>> <APPLY ,{orig} !.DIAG-A>")
        else:
            body = (f"<DIAG \"{name}-ARGS\" <LIST !.DIAG-A>> <SET DIAG-R <APPLY ,{orig} !.DIAG-A>> "
                    f"<DIAG \"{name}-RESULT\" .DIAG-R> .DIAG-R")
        lines.append(f"<SETG {name} <FUNCTION (\"TUPLE\" DIAG-A \"AUX\" DIAG-R) {body}>>")
    return "\n".join(lines) + "\n"


def dskdate_wrap() -> str:
    """Typed after FLOAD, before SAVE-IT: log every DSKDATE result (a WORD)
    and its FIX value."""
    return ("<SETG DIAG-ORIG-DSKDATE ,DSKDATE>\n"
            "<SETG DSKDATE <FUNCTION (\"TUPLE\" DIAG-A \"AUX\" DIAG-R) "
            "<SET DIAG-R <APPLY ,DIAG-ORIG-DSKDATE !.DIAG-A>> "
            "<DIAG \"DSKDATE-RESULT-FIX\" <CHTYPE .DIAG-R FIX>> .DIAG-R>>\n")


def run_case(case: dict, base: Path, shim: Path) -> dict:
    d = Path(tempfile.mkdtemp(prefix=case["name"] + "-", dir=base))
    game = d / "game"
    log = d / "DIAG.LOG"
    if case.get("cwd", "game") == "game":
        shutil.copytree(GAME, game)
        removed = []
        for rel in STALE_BOOT_FILES:
            if (game / rel).exists():
                (game / rel).unlink()
                removed.append(rel)
    else:
        game.mkdir()
        removed = []
    for op in case.get("setup", []):
        kind, rel = op[0], op[1]
        p = game / rel
        if kind == "mkdir":
            p.mkdir(parents=True, exist_ok=True)
        elif kind == "write":
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(op[2].encode("latin-1"))
        elif kind == "chmod":
            os.chmod(p, int(op[2], 8))
        elif kind == "rmtree":
            shutil.rmtree(p)
    before = manifest(game)
    env = dict(os.environ)
    clock = case.get("clock", {"epoch": EPOCH, "tz": "UTC"})
    if clock:
        env.update({"LD_PRELOAD": str(shim), "MDL_FIXED_EPOCH": str(clock["epoch"]),
                    "TZ": clock["tz"]})
    stdin_text = case["input"].replace("@LOG@", str(log)).replace("@GAME@", str(game))
    t0 = time.monotonic()
    row = {"name": case["name"], "kind": case.get("kind", "transcript"),
           "note": case.get("note", ""), "mode": case.get("mode", "pipe"),
           "clock": clock or "real host clock (no shim)",
           "cwd": "$TMPDIR/session-probes/" + d.name + "/game",
           "removed_before_boot": removed, "setup": case.get("setup", [])}
    if case.get("mode", "pipe") == "pipe":
        stdin = stdin_text.encode("latin-1")
        try:
            r = subprocess.run([str(EXE)], input=stdin, capture_output=True, cwd=game,
                               env=env, timeout=case.get("timeout", 120))
            status, out, err = r.returncode, r.stdout, r.stderr
        except subprocess.TimeoutExpired as e:
            status, out, err = "timeout", e.stdout or b"", (e.stderr or b"") + b"\nTIMEOUT"
        row.update({"input": stdin_text, "input_sha256": sha256_bytes(stdin),
                    "exit_status": status,
                    "stdout_raw": out.decode("latin-1"),
                    "stdout_sha256": sha256_bytes(out),
                    "stdout_canonical": canon(out.decode("latin-1")),
                    "stderr_raw": err.decode("latin-1")})
    else:
        row.update(run_pty(case, stdin_text, game, env))
    row["elapsed_seconds"] = round(time.monotonic() - t0, 2)
    # modes as left by the run (before the host restores u+rw so it can hash)
    modes_after_run = {p.relative_to(game).as_posix() + ("/" if p.is_dir() else ""):
                       oct(stat.S_IMODE(p.lstat().st_mode)) for p in sorted(game.rglob("*"))}
    # restore permissions so the manifest and cleanup can read everything
    for p in [game] + list(game.rglob("*")):
        try:
            os.chmod(p, os.stat(p).st_mode | stat.S_IRUSR | stat.S_IWUSR | (stat.S_IXUSR if p.is_dir() else 0))
        except OSError:
            pass
    after = manifest(game)
    for k, v in after.items():
        if k in modes_after_run:
            v["mode"] = modes_after_run[k]
    row["files_before"] = before
    row["files_changed"] = {k: {"before": before.get(k), "after": v}
                            for k, v in after.items() if before.get(k) != v}
    row["files_removed"] = sorted(k for k in before if k not in after)
    texts = {}
    for k in row["files_changed"]:
        p = game / k
        if p.is_file() and p.stat().st_size < 4096 and not k.endswith(".SAVE"):
            texts[k] = p.read_bytes().decode("latin-1")
    row["changed_file_text"] = texts
    if log.exists():
        row["diag_log"] = log.read_bytes().decode("latin-1")
    print(f"{case['name']}: exit={row.get('exit_status')} changed={list(row['files_changed'])} "
          f"t={row['elapsed_seconds']}s", file=sys.stderr)
    return row


def run_pty(case: dict, entry_text: str, game: Path, env: dict) -> dict:
    import pexpect
    prompt = re.compile(r"(?m)^>")
    child = pexpect.spawn(str(EXE), [], cwd=str(game), env=env, encoding="latin-1",
                          echo=False, timeout=case.get("timeout", 60), dimensions=(40, 100))
    child.delaybeforesend = 0.1
    steps = []
    err = None
    try:
        for line in entry_text.splitlines():
            child.sendline(line)
        child.expect(prompt)
        boot = child.before
        for inp, want in case["steps"]:
            if want == "chmod-mdl-555":
                os.chmod(game / "MDL", 0o555)
                steps.append({"action": "chmod MDL 0555 (host, between commands)"})
                continue
            child.send(inp)
            pats = {"prompt": prompt, "yesno": re.escape(YESNO_TEXT), "eof": pexpect.EOF}
            idx = child.expect([pats[want], pexpect.EOF, pexpect.TIMEOUT])
            steps.append({"input_bytes": inp, "expected": want,
                          "matched": ["expected", "EOF", "TIMEOUT"][idx],
                          "output": child.before,
                          "matched_text": child.after if isinstance(child.after, str) else None})
            if idx == 2:
                raise RuntimeError(f"timeout after {inp!r}")
            if idx == 1 and want != "eof":
                break
    except Exception as e:  # recorded, not hidden
        err = repr(e)
        boot = locals().get("boot", child.before)
    finally:
        try:
            child.expect(pexpect.EOF, timeout=5)
            tail = child.before
        except Exception:
            tail = None
        alive = child.isalive()
        if alive:
            child.terminate(force=True)
        child.close()
    return {"entry_lines": entry_text.splitlines(), "boot_output_raw": boot,
            "boot_output_canonical": canon(boot), "steps": steps,
            "post_steps_tail": tail, "still_alive_after_steps": alive, "error": err,
            "exit_status": child.exitstatus, "signal_status": child.signalstatus}


def lines(*xs: str) -> str:
    return "".join(x + "\n" for x in xs)


# ---------------------------------------------------------------------------
# Probe C: complete session ending in QUIT
# ---------------------------------------------------------------------------
def session_cases() -> list[dict]:
    full = SIX + ["quit", "n", "inventory", "quit", "y", "look"]
    wrap = ["RANDOM", "READSTRING", "OPEN", "CLOSE", "QUIT"]
    return [
        {"name": "C1-session-quit-pipe", "input": ENTRY + lines(*full),
         "note": "six house-boot commands, quit, n, inventory, quit, y, then an extra "
                 "'look' that must not be processed"},
        {"name": "C1-session-quit-pty", "mode": "pty", "input": ENTRY,
         "steps": [(c + "\n", "prompt") for c in SIX]
                  + [("quit\n", "yesno"), ("n\n", "prompt"), ("inventory\n", "prompt"),
                     ("quit\n", "yesno"), ("y\nlook\n", "eof")],
         "note": "same session over a pty with boot_reference.py's pexpect settings; "
                 "'y' and 'look' are written in one send"},
        {"name": "C1-session-quit-diag", "kind": "diagnostic",
         "input": diag_prelude(Path("@LOG@"), wrap) + ENTRY + lines(*full),
         "note": "DIAGNOSTIC (not a transcript): RANDOM/READSTRING/OPEN/CLOSE/QUIT logged "
                 "to DIAG.LOG outside the game copy"},
        {"name": "C1b-session-quit-repeat", "input": ENTRY + lines(*full),
         "note": "repeat of C1 pipe to show byte determinism"},
        {"name": "C2-eof-at-yesno", "input": ENTRY + lines(*SIX, "quit"),
         "note": "input ends while the quit confirmation is pending"},
        {"name": "C2b-eof-at-yesno-diag", "kind": "diagnostic",
         "input": diag_prelude(Path("@LOG@"), ["READSTRING", "OPEN", "QUIT"]) + ENTRY
                  + lines(*SIX, "quit"),
         "note": "DIAGNOSTIC of C2: READSTRING counts/texts"},
        {"name": "C2c-yes-without-newline-then-eof", "input": ENTRY + lines(*SIX, "quit") + "y",
         "note": "the answer 'y' is followed by end of input instead of LF"},
        {"name": "C2d-empty-answer-line", "input": ENTRY + lines(*SIX, "quit", "", "quit", "y"),
         "note": "an empty line answers the confirmation; INBUF still holds 'quit'"},
        {"name": "C2e-yes-word-answer", "input": ENTRY + lines("quit", "yes please"),
         "note": "only the first character of the answer is tested"},
        {"name": "C3-unknown-and-malformed", "input": ENTRY + lines(
            "xyzzy", "frobozzle", "blorfintz", "qqq", "take", "open the", "put leaflet in", "", "north west",
            "score", "quit", "y"),
         "note": "XYZZY; FROBOZZLE (lexes to a known 5-letter prefix FROBO); truly unknown BLORFINTZ and QQQ; malformed commands and an empty line, then score/quit"},
        {"name": "C3-unknown-and-malformed-diag", "kind": "diagnostic",
         "input": diag_prelude(Path("@LOG@"), ["RANDOM", "READSTRING"]) + ENTRY + lines(
             "xyzzy", "frobozzle", "blorfintz", "qqq", "take", "open the", "put leaflet in", "", "north west",
             "score", "quit", "y"),
         "note": "DIAGNOSTIC of C3: RANDOM and READSTRING log"},
    ]


# ---------------------------------------------------------------------------
# Probe D: OPEN failure payloads
# ---------------------------------------------------------------------------
OPEN_FORMS = [
    ('READB', '<OPEN "READB" "ZORK" "LOG" "DSK" "MDL">'),
    ('PRINTO', '<OPEN "PRINTO" "ZORK" "LOG" "DSK" "MDL">'),
    ('PRINT', '<OPEN "PRINT" "ZORK" "LOG" "DSK" "MDL">'),
    ('READ', '<OPEN "READ" "ZORK" "LOG" "DSK" "MDL">'),
]


def open_probe_text() -> str:
    out = ["<SETG MUD ,MUDDLE>", "*600130*", "*600117*", "*600123*", "*4000000*"]
    for mode, form in OPEN_FORMS:
        out += [
            f"<SET CH {form}>",
            "<TYPE .CH>",
            "<COND (<TYPE? .CH FALSE> <LENGTH .CH>) (T CHANNEL)>",
            "<COND (<TYPE? .CH FALSE> <MAPF ,LIST ,TYPE .CH>) (T CHANNEL)>",
            "<COND (<TYPE? .CH FALSE> <1 .CH>) (T CHANNEL)>",
            "<COND (<TYPE? .CH FALSE> <2 .CH>) (T CHANNEL)>",
            "<COND (<TYPE? .CH FALSE> <3 .CH>) (T CHANNEL)>",
            "<COND (<TYPE? .CH FALSE> <==? <3 .CH> *600130*>) (T CHANNEL)>",
            "<COND (<TYPE? .CH FALSE> <N==? <3 .CH> *4000000*>) (T CHANNEL)>",
            "<COND (<TYPE? .CH CHANNEL> <CLOSE .CH>) (T NOT-A-CHANNEL)>",
        ]
    out.append("<QUIT>")
    return lines(*out)


def record_game_input(diag: bool, fake: str | None = None) -> str:
    pre = diag_prelude(Path("@LOG@"), ["OPEN", "CLOSE", "QUIT"], fake) if diag else ""
    return pre + ENTRY + lines("north", "quit", "y")


def open_cases() -> list[dict]:
    ptext = open_probe_text()
    plain = {"cwd": "empty"}
    return [
        dict(plain, name="D1-no-MDL-dir", input=ptext,
             note="empty cwd: directory MDL does not exist"),
        dict(plain, name="D2-MDL-dir-readonly", input=ptext,
             setup=[["mkdir", "MDL"], ["chmod", "MDL", "555"]],
             note="MDL exists, mode 0555 (no write); ZORK.LOG absent"),
        dict(plain, name="D3-ZORK-LOG-mode-000", input=ptext,
             setup=[["mkdir", "MDL"], ["write", "MDL/ZORK.LOG", "x\n"],
                    ["chmod", "MDL/ZORK.LOG", "000"]],
             note="MDL/ZORK.LOG exists with mode 0000"),
        dict(plain, name="D4-ZORK-LOG-readable", input=ptext,
             setup=[["mkdir", "MDL"], ["write", "MDL/ZORK.LOG", "x\n"]],
             note="control: MDL/ZORK.LOG exists and is readable/writable"),
        dict(plain, name="D5-MDL-is-a-file", input=ptext,
             setup=[["write", "MDL", "not a directory\n"]],
             note="MDL is a regular file (ENOTDIR)"),
        {"name": "D6-game-quit-log-mode-000", "kind": "diagnostic",
         "input": record_game_input(True),
         "setup": [["write", "MDL/ZORK.LOG", "pre-existing\n"], ["chmod", "MDL/ZORK.LOG", "000"]],
         "note": "DIAGNOSTIC: real game quit; MDL/ZORK.LOG pre-created mode 0000 so both "
                 "RECORD OPENs are denied (EACCES)"},
        {"name": "D7-game-quit-MDL-dir-readonly", "kind": "diagnostic",
         "input": record_game_input(True), "setup": [["chmod", "MDL", "555"]],
         "note": "DIAGNOSTIC: real game quit; MDL dir mode 0555 (MADADV.SAVE exists and is "
                 "writable so SAVE-IT still succeeds); ZORK.LOG cannot be created"},
        {"name": "D7b-game-quit-MDL-dir-readonly-transcript", "input": record_game_input(False),
         "setup": [["chmod", "MDL", "555"]],
         "note": "transcript run of D7 without diagnostic wrappers"},
        {"name": "D8-game-quit-normal", "kind": "diagnostic", "input": record_game_input(True),
         "note": "DIAGNOSTIC control: normal quit, ZORK.LOG created"},
        {"name": "D9-fake-status-600130-then-13", "kind": "diagnostic", "timeout": 60,
         "input": record_game_input(True, fake=(
             "<COND (<L? ,DIAG-OPENS 4> #FALSE (\"FAKE BUSY\" \"MDL/ZORK.LOG\" *600130*)) "
             "(T #FALSE (\"FAKE DENIED\" \"MDL/ZORK.LOG\" 13))>")),
         "note": "DIAGNOSTIC: OPEN of ZORK LOG faked: first 3 calls return status *600130*, "
                 "then status 13; shows RECORD's SLEEP 1/AGAIN loop and its exit"},
        {"name": "D10-fake-status-13", "kind": "diagnostic",
         "input": record_game_input(True, fake="#FALSE (\"FAKE DENIED\" \"MDL/ZORK.LOG\" 13)"),
         "note": "DIAGNOSTIC: OPEN of ZORK LOG always returns #FALSE (reason file 13)"},
        {"name": "D11-fake-false-two-elements", "kind": "diagnostic", "timeout": 30,
         "input": record_game_input(True, fake="#FALSE (\"FAKE DENIED\" \"MDL/ZORK.LOG\")"),
         "note": "DIAGNOSTIC: OPEN returns a FALSE with only 2 elements: <3 .CH> fails"},
        {"name": "D12-fake-empty-false", "kind": "diagnostic", "timeout": 30,
         "input": record_game_input(True, fake="<>"),
         "note": "DIAGNOSTIC: OPEN returns #FALSE () : <3 .CH> fails"},
    ]


# ---------------------------------------------------------------------------
# Probe E: clock -> RANDOM
# ---------------------------------------------------------------------------
WALK = ["north", "west", "north", "west", "north", "west", "north", "west",
        "north", "west", "north", "west"]


def seed_diag_input(cmds: list[str]) -> str:
    pre = diag_prelude(Path("@LOG@"), ["RANDOM", "GETTIMEDATE", "READSTRING"])
    return pre + '<FLOAD "77loadall.mud">\n' + dskdate_wrap() + "<SAVE-IT>\n" + lines(*cmds)


def plain_seq_text(n: int) -> str:
    return '<FLOAD "77loadall.mud">\n' + lines(
        "<GETTIMEDATE>", "<CHTYPE <DSKDATE> FIX>", "<SET S <CHTYPE <DSKDATE> FIX>>",
        "<RANDOM .S>", *(["<RANDOM>"] * n), "<QUIT>")


def seed_cases() -> list[dict]:
    e2 = 251036100  # 1977-12-15 12:15:00 UTC
    return [
        {"name": "E1-seed-diag-epoch-A", "kind": "diagnostic", "input": seed_diag_input(SIX),
         "note": "DIAGNOSTIC: RANDOM wrapped before FLOAD, DSKDATE wrapped after FLOAD; "
                 "six house-boot commands then EOF"},
        {"name": "E1b-seed-diag-epoch-A-repeat", "kind": "diagnostic",
         "input": seed_diag_input(SIX), "note": "repeat of E1"},
        {"name": "E2-seed-diag-epoch-B", "kind": "diagnostic", "input": seed_diag_input(SIX),
         "clock": {"epoch": e2, "tz": "UTC"}, "note": "second distinct epoch"},
        {"name": "E3-seed-diag-epoch-A-TZ-NY", "kind": "diagnostic", "input": seed_diag_input(SIX),
         "clock": {"epoch": EPOCH, "tz": "America/New_York"},
         "note": "same epoch, TZ=America/New_York: localtime reaches the seed"},
        {"name": "E4-walk-diag-epoch-A", "kind": "diagnostic", "input": seed_diag_input(WALK),
         "note": "DIAGNOSTIC: 12 alternating moves; each entry to a seen room calls PROB 80"},
        {"name": "E4b-walk-transcript-epoch-A", "input": ENTRY + lines(*WALK),
         "note": "transcript of E4 without wrappers"},
        {"name": "E5-plain-sequence-epoch-A", "kind": "diagnostic", "input": plain_seq_text(12),
         "note": "DIAGNOSTIC: after FLOAD only (no SAVE-IT): GETTIMEDATE, DSKDATE, "
                 "<RANDOM seed> and 12 further <RANDOM> at LISTEN"},
        {"name": "E5b-plain-sequence-epoch-B", "kind": "diagnostic", "input": plain_seq_text(12),
         "clock": {"epoch": e2, "tz": "UTC"}, "note": "as E5 at epoch B"},
        {"name": "E6-real-clock-gettimedate", "kind": "diagnostic", "clock": None,
         "cwd": "empty", "input": lines("<GETTIMEDATE>", "<GETTIMEDATE>", "<QUIT>"),
         "note": "no shim: element 7 (microseconds) is live on the real clock"},
        {"name": "E8-subsecond-term", "kind": "diagnostic",
         "input": '<FLOAD "77loadall.mud">\n' + lines(
             "<SETG GTD-ORIG ,GETTIMEDATE>", "<SETG USEC 0>",
             "<SETG GETTIMEDATE <FUNCTION (\"TUPLE\" A) <PUT <APPLY ,GTD-ORIG !.A> 7 ,USEC>>>",
             "<CHTYPE <DSKDATE> FIX>",
             "<SETG USEC 499999>", "<CHTYPE <DSKDATE> FIX>",
             "<SETG USEC 500000>", "<CHTYPE <DSKDATE> FIX>",
             "<SETG USEC 999999>", "<CHTYPE <DSKDATE> FIX>", "<QUIT>"),
         "note": "DIAGNOSTIC: GETTIMEDATE element 7 (microseconds) forced to 0, 499999, "
                 "500000, 999999 under the fixed clock; shows the half-second term of DSKDATE"},
        {"name": "E7-west-transcript-epoch-A", "input": ENTRY + lines(*SIX),
         "note": "plain transcript of the six commands under the fixed clock"},
        {"name": "E7b-west-transcript-epoch-A-repeat", "input": ENTRY + lines(*SIX),
         "note": "repeat"},
    ]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("probe", choices=["session", "open", "seed"])
    ap.add_argument("output", type=Path)
    ap.add_argument("--shim-src", type=Path, default=DEFAULT_SHIM_SRC)
    ap.add_argument("--only", default=None, help="regex on case names")
    a = ap.parse_args()
    if not EXE.is_file() or not GAME.is_dir():
        raise SystemExit("missing pinned mdli or game sources (make sources / reference-build)")
    if not a.shim_src.is_file():
        raise SystemExit(f"fixed_time.c not found: {a.shim_src} (BOOT-REF branch, PR #131)")
    base = Path(os.environ.get("TMPDIR", "/tmp")) / "session-probes"
    base.mkdir(parents=True, exist_ok=True)
    shim_dir = Path(tempfile.mkdtemp(prefix="shim-", dir=base))
    shim = build_shim(a.shim_src, shim_dir)
    cases = {"session": session_cases, "open": open_cases, "seed": seed_cases}[a.probe]()
    if a.only:
        cases = [c for c in cases if re.search(a.only, c["name"])]
    head = subprocess.run(["git", "-C", str(UPSTREAM_ROOT), "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    exe_before = sha256_file(EXE)
    rows = [run_case(c, base, shim) for c in cases]
    res = {"schema_version": 1, "probe": a.probe,
           "recorded_at": datetime.now(timezone.utc).isoformat(),
           "interpreter_sha256_before": exe_before,
           "interpreter_sha256_after": sha256_file(EXE),
           "upstream_mdlzork_checked_out": head,
           "game_dir": "mdlzork_771212/patched_confusion",
           "shim_src_sha256": sha256_file(a.shim_src),
           "shim": "fixed_time.c from BOOT-REF (feat/m3-boot-reference e616ac0), compiled "
                   "per run: gcc -shared -fPIC -O2 -o fixed_time.so fixed_time.c -ldl",
           "protocol": "scripts/probe_session_reference.py (see module docstring)",
           "cases": rows}
    a.output.write_text(json.dumps(res, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
