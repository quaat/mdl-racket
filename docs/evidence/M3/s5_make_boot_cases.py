#!/usr/bin/env python3
"""Generate s5-save-frontier-boot-cases.json (whole-game boots in fresh $TMPDIR game copies)."""
import json
from pathlib import Path

# Tracing prelude: defined AFTER 77loadall.mud loads and BEFORE <SAVE-IT>,
# exactly the two forms of run.mud. It only rebinds GVALs to wrappers that
# print "{n NAME il=<INT-LEVEL> args}" then call the original; no source file
# is edited. Empty TUPLE splices are avoided (Confusion raised
# TOO-MANY-ARGUMENTS-SUPPLIED for <F !.A> with A empty on a 0-arg FUNCTION).
TRACE = r'''
<SETG SF-N 0>
<SETG O-INT-LEVEL ,INT-LEVEL>
<DEFINE SF-ARG (X) <COND (<TYPE? .X CHANNEL> <PRINC " #CHANNEL">) (<TYPE? .X STRING> <PRINC " "> <PRIN1 .X>) (<TYPE? .X FIX ATOM FALSE> <PRINC " "> <PRIN1 .X>) (T <PRINC " #"> <PRINC <TYPE .X>>)>>
<DEFINE SF-TRC (NAME "TUPLE" A) <SETG SF-N <+ ,SF-N 1>> <PRINC "{"> <PRIN1 ,SF-N> <PRINC " "> <PRINC .NAME> <PRINC " il="> <PRIN1 <O-INT-LEVEL>> <MAPF <> ,SF-ARG .A> <PRINC "}"> T>
<DEFINE SF-RET (NAME R) <PRINC "{=> "> <PRINC .NAME> <SF-ARG .R> <PRINC "}"> .R>
'''
WRAP = ["SAVE", "INT-LEVEL", "ON", "OFF", "HANDLER", "EVENT", "DSKDATE", "GETTIMEDATE",
        "RANDOM", "RESET", "READSTRING", "QUIT", "GETSYS", "STARTER", "XUNAME", "GET-NAME",
        "START", "CONTIN", "ROOM-INFO", "RDCOM", "ISTRING", "SNAME", "FINISH"]
ZERO = {"DSKDATE", "GETTIMEDATE", "GETSYS", "STARTER", "XUNAME", "CONTIN"}
OPT1 = {"GET-NAME", "ROOM-INFO", "RDCOM", "FINISH"}
# A "TUPLE" wrapper invoked during another FUNCTION's AUX binding raised
# ILLEGAL-SEGMENT in Confusion (segment splice into a FUNCTION, not a SUBR),
# so wrappers of FUNCTIONs use fixed arity; TUPLE+splice only for SUBRs.
for n in WRAP:
    TRACE += f'<SETG O-{n} ,{n}>\n'
    if n == "START":  # segment-splicing into a FUNCTION raised ILLEGAL-SEGMENT
        TRACE += '<SETG START <FUNCTION (RM ST) <SF-TRC "START" .RM .ST> <SF-RET "START" <O-START .RM .ST>>>>\n'
    elif n in ZERO:
        TRACE += f'<SETG {n} <FUNCTION () <SF-TRC "{n}"> <SF-RET "{n}" <O-{n}>>>>\n'
    elif n in OPT1:
        TRACE += (f'<SETG {n} <FUNCTION ("OPTIONAL" X) <COND (<ASSIGNED? X> <SF-TRC "{n}" .X> <SF-RET "{n}" <O-{n} .X>>)'
                  f' (T <SF-TRC "{n}"> <SF-RET "{n}" <O-{n}>>)>>>\n')
    else:
        TRACE += (f'<SETG {n} <FUNCTION ("TUPLE" A) <SF-TRC "{n}" !.A> '
                  f'<SF-RET "{n}" <COND (<EMPTY? .A> <O-{n}>) (T <O-{n} !.A>)>>>>\n')

cases = [
    {"name": "boot-plain", "cwd": "game",
     "note": "faithful entry: <FLOAD \"run.mud\"> then one game command on stdin",
     "input": '<FLOAD "run.mud">\nlook\n', "timeout": 120},
    {"name": "restore-madadv-from-boot", "reuse": "boot-plain", "argv": ["-r", "MDL/MADADV.SAVE"],
     "note": "restore the image SAVE-IT just wrote: where does execution continue?",
     "input": '<PRIN1 <INT-LEVEL>>\n<PRIN1 <GVAL REP>>\n<PRIN1 ,VERS>\n<QUIT>\n', "timeout": 60},
    {"name": "boot-traced", "cwd": "game",
     "note": "run.mud's two forms with a GVAL-wrapper tracing prelude in between",
     "input": '<FLOAD "77loadall.mud">\n' + TRACE + '<SAVE-IT>\nlook\n', "timeout": 120},
    {"name": "boot-no-mdl-dir", "cwd": "game", "pre_remove": "MDL",
     "note": "SAVE fails (#FALSE) if <MDL> directory is missing: what does patched SAVE-IT do?",
     "input": '<FLOAD "77loadall.mud">\n' + TRACE + '<SAVE-IT>\nlook\n', "timeout": 120},
    {"name": "restore-zork-save", "cwd": "game", "argv": ["-r", "SAVEFILE/ZORK.SAVE"],
     "note": "reference_runner boot image: initial output before first READSTRING",
     "input": 'look\n', "timeout": 60},
]
Path(__file__).with_name("s5-save-frontier-boot-cases.json").write_text(json.dumps({"name": "save-frontier-boot", "cases": cases}, indent=2) + "\n")
