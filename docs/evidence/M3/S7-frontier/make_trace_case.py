#!/usr/bin/env python3
"""Generate trace-cases.json: boot + six commands + quit/y with every
Confusion SUBR (minus an exclusion list) wrapped by a counting FUNCTION.

Only builtin NAMES and their SUBR/FSUBR kind are read from the pinned
Confusion mdl_builtins.cpp registration lines; no code is copied.
The prelude is typed into LISTEN after <FLOAD "77loadall.mud"> and before
<SAVE-IT>. Tracing is off during setup (TR-ON false) and is switched on
just before <SAVE-IT>. QUIT is replaced by TR-DUMP, which prints one
'@@TRACE name count first-phase first-order' line per wrapped SUBR and then
applies the original QUIT. Phase = number of READSTRING calls made before
the first hit (0 = boot up to the first prompt; 1..6 = the six scenario
commands; 7 = 'quit'; 8 = the 'y' answer read by YES/NO).
"""
import json, re
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE.parents[3] / ".cache/build/confusion_patched/mdl_builtins.cpp"  # repo-relative
pairs = re.findall(r"MDL_BUILTIN\(([^,]+),\s*[^,]+,\s*([A-Z]+)", SRC.read_text())
subrs = [n.strip() for n, k in pairs if k == "SUBR"]
fsubrs = [n.strip() for n, k in pairs if k == "FSUBR"]
EXCLUDE = {"APPLY", "PUT", "NTH", "+", "0?", "SETG", "GVAL", "LVAL",
           "RETURN", "AGAIN", "MAPRET", "MAPSTOP", "MAPLEAVE", "ERRET", "RETRY",
           "FRAME", "FFRAME", "TFFRAME", "ARGS", "FUNCT", "LISTEN", "REP", "QUIT"}
names = ["READSTRING"] + [n for n in subrs if n not in EXCLUDE and n != "READSTRING"]

def mstr(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

prelude = f"""<SETG TR-NAMES [{' '.join(mstr(n) for n in names)}]>
<SETG TR-N <LENGTH ,TR-NAMES>>
<SETG TR-CNT <IVECTOR ,TR-N 0>>
<SETG TR-FIRST <IVECTOR ,TR-N -1>>
<SETG TR-ORD <IVECTOR ,TR-N 0>>
<SETG TR-SEQ 0>
<SETG TR-ON <>>
<DEFINE TR-HIT (I) <COND (,TR-ON <COND (<0? <NTH ,TR-CNT .I>> <PUT ,TR-FIRST .I <NTH ,TR-CNT 1>> <SETG TR-SEQ <+ ,TR-SEQ 1>> <PUT ,TR-ORD .I ,TR-SEQ>)> <PUT ,TR-CNT .I <+ <NTH ,TR-CNT .I> 1>>)> T>
<DEFINE TR-MK (I ORIG) <CHTYPE <LIST '("TUPLE" TRARGS) <FORM TR-HIT .I> <FORM APPLY <FORM QUOTE .ORIG> <CHTYPE <FORM LVAL TRARGS> SEGMENT>>> FUNCTION>>
<SETG TR-W <IVECTOR ,TR-N <>>>
<SETG TR-A <IVECTOR ,TR-N <>>>
<PROG ((I 1) A) <REPEAT () <COND (<G? .I ,TR-N> <RETURN T>)> <SET A <LOOKUP <NTH ,TR-NAMES .I> <ROOT>>> <COND (<AND .A <GASSIGNED? .A> <TYPE? ,.A SUBR>> <PUT ,TR-A .I .A> <PUT ,TR-W .I <TR-MK .I ,.A>>)> <SET I <+ .I 1>>>>
<SETG TR-QUIT ,QUIT>
<DEFINE TR-DUMP ("TUPLE" X) <SETG TR-ON <>> <PROG ((I 1)) <REPEAT () <COND (<G? .I ,TR-N> <RETURN T>)> <COND (<NTH ,TR-A .I> <PRINC "@@TRACE "> <PRINC <NTH ,TR-NAMES .I>> <PRINC " "> <PRIN1 <NTH ,TR-CNT .I>> <PRINC " "> <PRIN1 <NTH ,TR-FIRST .I>> <PRINC " "> <PRIN1 <NTH ,TR-ORD .I>> <CRLF>)> <SET I <+ .I 1>>>> <APPLY ,TR-QUIT>>
<PROG ((I 1)) <REPEAT () <COND (<G? .I ,TR-N> <RETURN T>)> <COND (<NTH ,TR-A .I> <SETG <NTH ,TR-A .I> <NTH ,TR-W .I>>)> <SET I <+ .I 1>>>>
<SETG QUIT ,TR-DUMP>
<SETG TR-ON T>
"""

inp = ('<FLOAD "77loadall.mud">\n' + prelude + '<SAVE-IT>\n'
       + 'north\nwest\nopen mailbox\ntake leaflet\ninventory\nscore\nquit\ny\n')
cases = {"name": "interactive-subr-trace", "excluded_from_wrapping": sorted(EXCLUDE),
         "fsubrs_not_wrappable": fsubrs,
         "cases": [{"name": "trace-six-quit", "cwd": "game", "fixed_clock": True,
                    "timeout": 300, "input": inp,
                    "note": "SUBR first-hit trace; see make_trace_case.py docstring"}]}
(HERE / "trace-cases.json").write_text(json.dumps(cases, indent=2) + "\n")
print(len(names), "wrapped candidates")
