#!/usr/bin/env python3
"""Pinned-Confusion reference capture for the M4 Phase 2 death scenarios
(epic #163, death and recovery): grue-resurrection, grue-refusal and
troll-death, and the M4 Phase 3 timer, object and scoring scenarios
(epic #163 Phase 3): treasure-deposit, thief-robbery, cure-recovery and
lamp-burnout (tests/scenarios/<name>.json).

Read-only reference investigation. Nothing here is runtime code, and the game
sources under .cache/upstream are never written: every run boots a fresh copy
of the game directory under $TMPDIR (protocol of
scripts/probe_session_reference.py, which this script imports; transcript
helpers from scripts/probe_house_cellar_reference.py). Natively, a run that
ends in the game's QUIT writes MDL/ZORK.LOG through RECORD, and every run
rewrites MDL/MADADV.SAVE through SAVE-IT: both only in the disposable copy.
Modelled on scripts/probe_help_info_scenario_reference.py, with three
differences:

  * the death question.  JIGS-UP (77rooms.mud:870) asks "Do you want me to
    try to patch you?" with TELL ... 0 (no CRLF) and reads the answer with
    YES/NO (77defs.mud:431): a terminal READSTRING entry whose prompt is that
    question, not RDCOM's `>`.  The scenario declares these entries
    (`entry_prompts`, READSTRING entry index -> prompt text); the diagnostic
    wraps YES/NO and logs YES/NO-ENTRY with the index of the READSTRING entry
    it is about to make, and the capture is rejected unless the logged
    entries are exactly the declared ones.  The prompt split counts `>`
    (any position, as the runner's default) for every other entry;
  * the QUIT ending.  A prefix run can end by the game's own QUIT (FINISH ->
    RECORD -> QUIT) instead of end of input.  The scenario declares these
    prefixes (`quit_prefixes`); the capture records each run's ending from
    its stderr (end of input: "Error: Unexpected EOF\\n"; QUIT: empty) and,
    for diagnostic runs, the QUIT wrapper's QUIT-NARGS line, and is rejected
    unless they agree with the declaration.  The QUIT wrapper takes a last
    checkpoint (the state at QUIT) and closes the diagnostic log before
    applying the original QUIT;
  * the end of input inside YES/NO.  A prefix that ends at the question has
    YES/NO's READSTRING meet end of input: natively it returns 0 and the
    stale first character of INBUF answers (77defs.mud:435-438).

Every wrapper applies the original SUBR or FUNCTION to the same arguments and
returns its value unchanged.  The game part of every diagnostic run's stdout
must equal the matching transcript run's, or the capture is rejected.

Usage (sandbox; TMPDIR must be writable):
    python3 -I scripts/probe_death_scenario_reference.py NAME OUT.json [--shim-src C]

Runs (all pipe mode, fixed clock epoch 250776000, TZ=UTC, microseconds 0):
  * T1  transcript: <FLOAD "77loadall.mud"> <SAVE-IT> + the scenario commands;
  * T1b repeat of T1 (byte determinism);
  * Pkk transcripts of the first k commands then EOF (k = 0 .. n-1);
  * Dkk DIAGNOSTIC prefix runs (k = 0 .. n-1): the X1 diagnostic input cut
        after k commands; their LAST checkpoint is the end state of prefix k
        (end of input: the READSTRING entry that dies; QUIT: the state at
        QUIT);
  * X1  DIAGNOSTIC (not a transcript): forms typed at LISTEN after FLOAD and
        before SAVE-IT wrap RANDOM, READSTRING, YES/NO and QUIT and log to
        DIAG.LOG OUTSIDE the game copy; a read-only state checkpoint is
        logged at every terminal READSTRING entry and at QUIT.

Checkpoint fields: HERE's RID; the winner's AOBJS (OIDs), ASCORE, ASTRENGTH
and ASTAGGERED bit; MOVES, RAW-SCORE, DEATHS; EGYPT-FLAG!-FLAG; the trap
door's OTOUCH?; CURIN's CFLAG and CTICK; the troll's OROOM, OCAPAC and
FIGHTBIT; the lamp's OROOM, OCAN and OLIGHT?; the OROOM of the sword, the
sack and the bottle; INBUF as the list of its 100 character codes.  No game
state is written.

Checkpoint profiles (PROFILES): the death scenarios use exactly the fields
above (DIAG_FORMS, unchanged since their capture).  The Phase 3 scenarios use
the "timers" profile (TIMERS_DIAG_FORMS): the same fields, then the lamp's
LIGHT-INT counter (<1 <ORAND lamp>>), LNTIN's CFLAG and CTICK, every clock
event of the CLOCKER demon in HOBJS order as (CID CFLAG CTICK), the
painting's OROOM, OCAN, OFVAL and OTVAL, the trophy case's OOPEN? and
OCONTENTS (OIDs), the thief's OROOM, and the ROBBER demon's HROOM (RID),
HFLAG and HOBJS (OIDs: the thief's bag).  Pure reads as well.  A timers
capture keeps each Dkk case's log only as diag_log_sha256 and diag_log_bytes
(the logs grow with k; their last checkpoints are end_checkpoints, and X1's
log is kept in full); the reference says so in `diag_logs`.

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
import probe_session_reference as psr  # noqa: E402
from probe_house_cellar_reference import (  # noqa: E402
    game_part, split_responses, parse_diag)

PINNED_SHA256 = "6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789"
EOF_STDERR = "Error: Unexpected EOF\n"
STD_TAIL = "Beg pardon?\n>"

DIAG_FORMS = r'''<SETG DIAG-CH <OPEN "PRINT" "@LOG@">>
<SETG DIAG <FUNCTION (DIAG-T DIAG-X) <PRINC .DIAG-T ,DIAG-CH> <PRINC " " ,DIAG-CH> <PRIN1 .DIAG-X ,DIAG-CH> <CRLF ,DIAG-CH> T>>
<SETG DIAG-N 0>
<PROG () <SETG DIAG-TROLL <FIND-OBJ "TROLL">> <SETG DIAG-LAMP <FIND-OBJ "LAMP">> <SETG DIAG-DOOR <FIND-OBJ "DOOR">> <SETG DIAG-SWORD <FIND-OBJ "SWORD">> <SETG DIAG-SBAG <FIND-OBJ "SBAG">> <SETG DIAG-BOTTL <FIND-OBJ "BOTTL">> T>
<SETG DIAG-BIT <FUNCTION (DIAG-F DIAG-B) <N==? <CHTYPE <ANDB .DIAG-F .DIAG-B> FIX> 0>>>
<SETG DIAG-ROOM <FUNCTION (DIAG-O) <COND (<OROOM .DIAG-O> <RID <OROOM .DIAG-O>>)>>>
<SETG DIAG-STATE <FUNCTION () <DIAG "CP-BEGIN" ,DIAG-N> <DIAG "CP-HERE" <RID ,HERE>> <DIAG "CP-AOBJS" <MAPF ,LIST ,OID <AOBJS ,WINNER>>> <DIAG "CP-MOVES" ,MOVES> <DIAG "CP-RAW-SCORE" ,RAW-SCORE> <DIAG "CP-ASCORE" <ASCORE ,WINNER>> <DIAG "CP-DEATHS" ,DEATHS> <DIAG "CP-EGYPT-FLAG" ,EGYPT-FLAG!-FLAG> <DIAG "CP-DOOR-OTOUCH" <OTOUCH? ,DIAG-DOOR>> <DIAG "CP-WINNER-ASTRENGTH" <ASTRENGTH ,WINNER>> <DIAG "CP-WINNER-STAGGERED" <DIAG-BIT <AFLAGS ,WINNER> ,ASTAGGERED>> <DIAG "CP-CURIN-CFLAG" <CFLAG ,CURIN>> <DIAG "CP-CURIN-CTICK" <CTICK ,CURIN>> <DIAG "CP-TROLL-OROOM" <DIAG-ROOM ,DIAG-TROLL>> <DIAG "CP-TROLL-OCAPAC" <OCAPAC ,DIAG-TROLL>> <DIAG "CP-TROLL-FIGHTING" <DIAG-BIT <OFLAGS ,DIAG-TROLL> ,FIGHTBIT>> <DIAG "CP-LAMP-OROOM" <DIAG-ROOM ,DIAG-LAMP>> <DIAG "CP-LAMP-OCAN" <COND (<OCAN ,DIAG-LAMP> <OID <OCAN ,DIAG-LAMP>>)>> <DIAG "CP-LAMP-OLIGHT" <OLIGHT? ,DIAG-LAMP>> <DIAG "CP-SWORD-OROOM" <DIAG-ROOM ,DIAG-SWORD>> <DIAG "CP-SBAG-OROOM" <DIAG-ROOM ,DIAG-SBAG>> <DIAG "CP-BOTTL-OROOM" <DIAG-ROOM ,DIAG-BOTTL>> <DIAG "CP-INBUF" <MAPF ,LIST ,ASCII ,INBUF>> <DIAG "CP-END" ,DIAG-N> <SETG DIAG-N <+ ,DIAG-N 1>> T>>
<SETG DIAG-ORIG-RANDOM ,RANDOM>
<SETG RANDOM <FUNCTION ("TUPLE" DIAG-A "AUX" DIAG-R) <DIAG "RANDOM-ARGS" <LIST !.DIAG-A>> <SET DIAG-R <APPLY ,DIAG-ORIG-RANDOM !.DIAG-A>> <DIAG "RANDOM-RESULT" .DIAG-R> .DIAG-R>>
<SETG DIAG-ORIG-READSTRING ,READSTRING>
<SETG READSTRING <FUNCTION ("TUPLE" DIAG-A "AUX" DIAG-R (DIAG-TTY <==? <2 .DIAG-A> ,INCHAN>)) <AND .DIAG-TTY <DIAG-STATE>> <SET DIAG-R <APPLY ,DIAG-ORIG-READSTRING !.DIAG-A>> <COND (.DIAG-TTY <DIAG "READSTRING-COUNT" .DIAG-R> <DIAG "READSTRING-TEXT" <SUBSTRUC <1 .DIAG-A> 0 .DIAG-R>>) (T <DIAG "FILE-READSTRING-COUNT" .DIAG-R>)> .DIAG-R>>
<SETG DIAG-ORIG-YES/NO ,YES/NO>
<SETG YES/NO <FUNCTION ("TUPLE" DIAG-A "AUX" DIAG-R) <DIAG "YES/NO-ENTRY" ,DIAG-N> <SET DIAG-R <APPLY ,DIAG-ORIG-YES/NO !.DIAG-A>> <DIAG "YES/NO-RESULT" .DIAG-R> .DIAG-R>>
<SETG DIAG-ORIG-QUIT ,QUIT>
<SETG QUIT <FUNCTION ("TUPLE" DIAG-A) <DIAG "QUIT-NARGS" <LENGTH .DIAG-A>> <DIAG-STATE> <CLOSE ,DIAG-CH> <APPLY ,DIAG-ORIG-QUIT !.DIAG-A>>>
'''

# The Phase 3 "timers" profile: DIAG_FORMS with more objects found once and
# more checkpoint fields before CP-END (each replacement must apply once).
_FIND_OLD = '<SETG DIAG-BOTTL <FIND-OBJ "BOTTL">> T>'
_FIND_NEW = ('<SETG DIAG-BOTTL <FIND-OBJ "BOTTL">> <SETG DIAG-PAINT <FIND-OBJ "PAINT">> '
             '<SETG DIAG-TCASE <FIND-OBJ "TCASE">> <SETG DIAG-THIEF <FIND-OBJ "THIEF">> T>')
_CP_END = '<DIAG "CP-END" ,DIAG-N>'
_TIMERS_FIELDS = (
    '<DIAG "CP-LAMP-CNT" <1 <ORAND ,DIAG-LAMP>>> '
    '<DIAG "CP-LNTIN-CFLAG" <CFLAG ,LNTIN>> '
    '<DIAG "CP-LNTIN-CTICK" <CTICK ,LNTIN>> '
    '<DIAG "CP-CLOCK-EVENTS" <MAPF ,LIST <FUNCTION (DIAG-E) <LIST <CID .DIAG-E> <CFLAG .DIAG-E> '
    '<CTICK .DIAG-E>>> <HOBJS ,CLOCKER>>> '
    '<DIAG "CP-PAINT-OROOM" <DIAG-ROOM ,DIAG-PAINT>> '
    '<DIAG "CP-PAINT-OCAN" <COND (<OCAN ,DIAG-PAINT> <OID <OCAN ,DIAG-PAINT>>)>> '
    '<DIAG "CP-PAINT-OFVAL" <OFVAL ,DIAG-PAINT>> '
    '<DIAG "CP-PAINT-OTVAL" <OTVAL ,DIAG-PAINT>> '
    '<DIAG "CP-TCASE-OOPEN" <OOPEN? ,DIAG-TCASE>> '
    '<DIAG "CP-TCASE-CONTENTS" <MAPF ,LIST ,OID <OCONTENTS ,DIAG-TCASE>>> '
    '<DIAG "CP-THIEF-OROOM" <DIAG-ROOM ,DIAG-THIEF>> '
    '<DIAG "CP-ROBBER-HROOM" <RID <HROOM ,ROBBER-DEMON>>> '
    '<DIAG "CP-ROBBER-HFLAG" <HFLAG ,ROBBER-DEMON>> '
    '<DIAG "CP-ROBBER-HOBJS" <MAPF ,LIST ,OID <HOBJS ,ROBBER-DEMON>>> ')
assert DIAG_FORMS.count(_FIND_OLD) == 1 and DIAG_FORMS.count(_CP_END) == 1
TIMERS_DIAG_FORMS = (DIAG_FORMS.replace(_FIND_OLD, _FIND_NEW)
                     .replace(_CP_END, _TIMERS_FIELDS + _CP_END))

# The Phase 3b "dam" profile: TIMERS_DIAG_FORMS with the Flood Control Dam #3
# objects and room found once and more checkpoint fields before CP-END: the
# gate and tide flags (77act1.mud:677, BOLT-FUNCTION), the Maintenance Room's
# RVARS (MAINT-ROOM's water level) and RMUNGBIT, the leak clock MNTIN's CFLAG
# and CTICK, the wrench's OROOM, the tube's OOPEN?, the putty's OROOM and OCAN,
# the trunk's OROOM and OVISON bit (BOLT-FUNCTION makes it visible), and the
# matchbook's ORAND (matches left), OLIGHT? and FLAMEBIT with the match clock
# MATIN's CFLAG and CTICK (MATCH-FUNCTION, 77act1.mud:1925).
_DAM_FIND_OLD = '<SETG DIAG-THIEF <FIND-OBJ "THIEF">> T>'
_DAM_FIND_NEW = ('<SETG DIAG-THIEF <FIND-OBJ "THIEF">> <SETG DIAG-MAINT <FIND-ROOM "MAINT">> '
                 '<SETG DIAG-WRENC <FIND-OBJ "WRENC">> <SETG DIAG-TUBE <FIND-OBJ "TUBE">> '
                 '<SETG DIAG-PUTTY <FIND-OBJ "PUTTY">> <SETG DIAG-TRUNK <FIND-OBJ "TRUNK">> '
                 '<SETG DIAG-MATCH <FIND-OBJ "MATCH">> T>')
_DAM_FIELDS = (
    '<DIAG "CP-GATE-FLAG" ,GATE-FLAG!-FLAG> '
    '<DIAG "CP-LOW-TIDE" ,LOW-TIDE!-FLAG> '
    '<DIAG "CP-MAINT-RVARS" <RVARS ,DIAG-MAINT>> '
    '<DIAG "CP-MAINT-MUNGED" <DIAG-BIT <RBITS ,DIAG-MAINT> ,RMUNGBIT>> '
    '<DIAG "CP-MNTIN-CFLAG" <CFLAG ,MNTIN>> '
    '<DIAG "CP-MNTIN-CTICK" <CTICK ,MNTIN>> '
    '<DIAG "CP-WRENC-OROOM" <DIAG-ROOM ,DIAG-WRENC>> '
    '<DIAG "CP-TUBE-OOPEN" <OOPEN? ,DIAG-TUBE>> '
    '<DIAG "CP-PUTTY-OROOM" <DIAG-ROOM ,DIAG-PUTTY>> '
    '<DIAG "CP-PUTTY-OCAN" <COND (<OCAN ,DIAG-PUTTY> <OID <OCAN ,DIAG-PUTTY>>)>> '
    '<DIAG "CP-TRUNK-OROOM" <DIAG-ROOM ,DIAG-TRUNK>> '
    '<DIAG "CP-TRUNK-VISIBLE" <DIAG-BIT <OFLAGS ,DIAG-TRUNK> ,OVISON>> '
    '<DIAG "CP-MATCH-ORAND" <ORAND ,DIAG-MATCH>> '
    '<DIAG "CP-MATCH-OLIGHT" <OLIGHT? ,DIAG-MATCH>> '
    '<DIAG "CP-MATCH-FLAMING" <DIAG-BIT <OFLAGS ,DIAG-MATCH> ,FLAMEBIT>> '
    '<DIAG "CP-MATIN-CFLAG" <CFLAG ,MATIN>> '
    '<DIAG "CP-MATIN-CTICK" <CTICK ,MATIN>> ')
assert TIMERS_DIAG_FORMS.count(_DAM_FIND_OLD) == 1 and TIMERS_DIAG_FORMS.count(_CP_END) == 1
DAM_DIAG_FORMS = (TIMERS_DIAG_FORMS.replace(_DAM_FIND_OLD, _DAM_FIND_NEW)
                  .replace(_CP_END, _DAM_FIELDS + _CP_END))

# Scenario name -> its checkpoint profile's diagnostic forms.
PROFILES = {
    "grue-resurrection": DIAG_FORMS,
    "grue-refusal": DIAG_FORMS,
    "troll-death": DIAG_FORMS,
    "treasure-deposit": TIMERS_DIAG_FORMS,
    "thief-robbery": TIMERS_DIAG_FORMS,
    "cure-recovery": TIMERS_DIAG_FORMS,
    "lamp-burnout": TIMERS_DIAG_FORMS,
    "dam-sluice": DAM_DIAG_FORMS,
    "maint-leak": DAM_DIAG_FORMS,
    "match-clock": DAM_DIAG_FORMS,
}
NAMES = tuple(PROFILES)


def prompt_heads(game: str, last_entry: int, entry_prompts: dict[int, str]) -> list[str]:
    """The text through the prompt of each READSTRING entry 0..last_entry:
    the next `>` for an RDCOM entry, the next occurrence of the declared text
    for a YES/NO entry (no `>` may lie before it).  The same rule as the
    runner's prompt-head (tests/m4_scenario_runner.rkt)."""
    heads, pos = [], 0
    for j in range(last_entry + 1):
        lit = entry_prompts.get(j)
        if lit is None:
            i = game.find(">", pos)
            if i < 0:
                raise ValueError(f"no prompt for entry {j}")
            pos = i + 1
        else:
            i = game.find(lit, pos)
            if i < 0 or ">" in game[pos:i]:
                raise ValueError(f"entry {j}: declared prompt not found before the next `>`")
            pos = i + len(lit)
        heads.append(game[:pos])
    return heads


def expected_gt_count(k_last_entry: int, ending: str, entry_prompts: dict[int, str]) -> int:
    """`>` in a prefix stdout: one per RDCOM entry 0..e (the declared YES/NO
    entries excluded), plus, at end of input, the prompt of the RDCOM entry
    that dies (it follows the empty command of entry e, so it is always
    RDCOM's `>`, whatever index it has in T1)."""
    return (sum(1 for j in range(k_last_entry + 1) if j not in entry_prompts)
            + (1 if ending == "eof" else 0))


def ending_of(row: dict) -> str:
    if row["exit_status"] != 0:
        return f"exit {row['exit_status']}"
    if row["stderr_raw"] == EOF_STDERR:
        return "eof"
    if row["stderr_raw"] == "":
        return "quit"
    return "stderr " + repr(row["stderr_raw"])


def diag_events(log: str) -> dict:
    yes_no, quits, yes_no_results = [], [], []
    for line in log.splitlines():
        tag, _, val = line.partition(" ")
        if tag == "YES/NO-ENTRY":
            yes_no.append(int(val))
        elif tag == "YES/NO-RESULT":
            yes_no_results.append(val)
        elif tag == "QUIT-NARGS":
            quits.append(int(val))
    return {"yes_no_entries": yes_no, "yes_no_results": yes_no_results, "quit_nargs": quits}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("name", choices=NAMES)
    ap.add_argument("output", type=Path)
    ap.add_argument("--shim-src", type=Path, default=psr.DEFAULT_SHIM_SRC)
    a = ap.parse_args()
    tag = a.name
    diag_forms = PROFILES[tag]
    scenario_file = psr.ROOT / f"tests/scenarios/{tag}.json"
    if not psr.EXE.is_file() or not psr.GAME.is_dir():
        raise SystemExit("missing pinned mdli or game sources")
    exe_before = psr.sha256_file(psr.EXE)
    if exe_before != PINNED_SHA256:
        raise SystemExit(f"mdli sha256 {exe_before} != pinned {PINNED_SHA256}")
    sc = json.loads(scenario_file.read_text(encoding="utf-8"))
    cmds = sc["commands"]
    n = len(cmds)
    assert sc["fixed_epoch"] == psr.EPOCH and sc["tz"] == "UTC"
    entry_prompts = {int(k): v for k, v in sc["entry_prompts"].items()}
    quit_prefixes = sorted(sc["quit_prefixes"])
    declared_endings = ["quit" if k in quit_prefixes else "eof" for k in range(n + 1)]
    entry_fload = '<FLOAD "77loadall.mud">\n'
    plain_input = psr.ENTRY + psr.lines(*cmds)
    diag_input = entry_fload + diag_forms + "<SAVE-IT>\n" + psr.lines(*cmds)
    base = Path(os.environ.get("TMPDIR", "/tmp")) / f"{tag}-probes"
    base.mkdir(parents=True, exist_ok=True)
    shim = psr.build_shim(a.shim_src, Path(tempfile.mkdtemp(prefix="shim-", dir=base)))
    cases = [
        {"name": f"T1-{tag}-pipe", "input": plain_input,
         "note": "transcript: faithful entry + scenario commands, then EOF"},
        {"name": f"T1b-{tag}-pipe-repeat", "input": plain_input,
         "note": "repeat of T1 to show byte determinism"},
        {"name": f"X1-{tag}-diag", "kind": "diagnostic", "input": diag_input,
         "note": "DIAGNOSTIC (not a transcript): RANDOM, READSTRING, YES/NO and QUIT wrapped "
                 "after FLOAD, before SAVE-IT; read-only state checkpoint at every terminal "
                 "READSTRING entry and at QUIT; log in DIAG.LOG outside the game copy"},
    ]
    for k in range(n):
        cases.append({"name": f"P{k:02d}-{tag}-prefix",
                      "input": psr.ENTRY + psr.lines(*cmds[:k]),
                      "note": f"transcript of the first {k} commands, then EOF (used by "
                              f"per-prefix candidate runs)"})
    for k in range(n):
        cases.append({"name": f"D{k:02d}-{tag}-diag-prefix", "kind": "diagnostic",
                      "input": entry_fload + diag_forms + "<SAVE-IT>\n" + psr.lines(*cmds[:k]),
                      "note": f"DIAGNOSTIC: X1 cut after {k} commands; its last checkpoint is "
                              f"the end state of prefix {k} (end checkpoint {k})"})
    rows = [psr.run_case(c, base, shim) for c in cases]
    t1, t1b, x1 = rows[:3]
    prefixes = rows[3:3 + n] + [t1]            # P_0 .. P_{n-1}, P_n = T1
    dprefixes = rows[3 + n:] + [x1]            # D_0 .. D_{n-1}, D_n = X1
    games = [game_part(r["stdout_raw"]) for r in prefixes]
    g1 = games[n]
    gx = game_part(x1["stdout_raw"])
    diag = parse_diag(x1.get("diag_log", ""))
    dparsed = [parse_diag(r.get("diag_log", "")) for r in dprefixes]
    devents = [diag_events(r.get("diag_log", "")) for r in dprefixes]
    endings = [ending_of(r) for r in prefixes]
    dendings = [ending_of(r) for r in dprefixes]
    # The last READSTRING entry of each prefix: end of input, k; QUIT, the
    # entry whose answer quit (or k when the answer met end of input).
    q = len(diag["checkpoints"]) - 2
    last_entries = [k if declared_endings[k] == "eof" else min(k, q) for k in range(n + 1)]
    heads = {}
    head_errors = {}
    for k in range(min(q, n) + 1):
        try:
            heads[k] = prompt_heads(games[k], k, entry_prompts)[k]
        except ValueError as e:
            head_errors[k] = str(e)
    end_checkpoints = [d["checkpoints"][-1] for d in dparsed]
    canonical = psr.canon(g1)
    checks = {
        "t1_equals_t1b_bytes": t1["stdout_raw"] == t1b["stdout_raw"],
        "diag_game_part_equals_t1_game_part_bytes": g1 == gx and g1 != "",
        "diag_prefix_game_parts_equal_prefix_game_parts": all(
            game_part(d["stdout_raw"]) == g for d, g in zip(dprefixes, games)),
        "declared_endings": declared_endings,
        "prefix_endings": endings,
        "diag_prefix_endings": dendings,
        "diag_prefix_quit_nargs": [e["quit_nargs"] for e in devents],
        "t1_last_entry": q,
        "last_entries": last_entries,
        "diag_prefix_checkpoint_counts": [len(d["checkpoints"]) for d in dparsed],
        "expected_diag_prefix_checkpoint_counts": [e + 2 for e in last_entries],
        "declared_entry_prompts": {str(k): v for k, v in sorted(entry_prompts.items())},
        "diag_yes_no_entries": devents[n]["yes_no_entries"],
        "diag_yes_no_results": devents[n]["yes_no_results"],
        "prefix_gt_counts": [g.count(">") for g in games],
        "expected_prefix_gt_counts": [expected_gt_count(last_entries[k], declared_endings[k],
                                                        entry_prompts) for k in range(n + 1)],
        "prompt_head_errors": head_errors,
        "prefix_runs_consistent_with_t1": all(
            (games[k].startswith(heads[k]) and g1.startswith(heads[k])) if k in heads
            else games[k] == g1
            for k in range(n + 1)),
        "prefix_runs_with_non_standard_end": [
            k for k in range(n) if k not in heads or declared_endings[k] != "eof"
            or games[k][len(heads[k]):] != STD_TAIL
            or {x: y for x, y in end_checkpoints[k].items() if x != "n"}
            != {x: y for x, y in dparsed[n]["checkpoints"][k].items() if x != "n"}],
        "prefix_exit_statuses": sorted({r["exit_status"] for r in prefixes}),
        "prefix_files_changed": [sorted(r["files_changed"]) for r in prefixes],
        "t1_files_changed": sorted(t1["files_changed"]),
        "t1_files_removed": t1["files_removed"],
        "t1_elapsed_seconds": t1["elapsed_seconds"],
        "t1b_elapsed_seconds": t1b["elapsed_seconds"],
    }
    zork_logs = {r["name"]: r.get("changed_file_text", {}).get("MDL/ZORK.LOG")
                 for r in prefixes if "MDL/ZORK.LOG" in r["files_changed"]}
    for r in rows:
        for key in ("files_before", "changed_file_text"):
            r.pop(key, None)
    # Timers profile: the Dkk logs grow with k (one checkpoint per entry), so
    # a long scenario's reference would hold O(n^2) log text.  Each is replaced
    # by its sha256 and size; what the runner uses from it, its last
    # checkpoint, is kept in end_checkpoints, and X1's log is kept in full.
    compact = diag_forms is TIMERS_DIAG_FORMS or diag_forms is DAM_DIAG_FORMS
    if compact:
        for r in rows[3 + n:]:
            log = r.pop("diag_log", "").encode("latin-1")
            r["diag_log_sha256"] = psr.sha256_bytes(log)
            r["diag_log_bytes"] = len(log)
    head = subprocess.run(["git", "-C", str(psr.UPSTREAM_ROOT), "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    res = {
        "schema_version": 1,
        "kind": "m4-scenario-reference",
        "scenario": sc["name"],
        "scenario_file": f"tests/scenarios/{tag}.json",
        "engine": "confusion-patched-1977",
        "fixed_epoch": psr.EPOCH, "tz": "UTC",
        "entry": ['<FLOAD "77loadall.mud">', "<SAVE-IT>"],
        "commands": cmds,
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "interpreter": ".cache/build/confusion_patched/mdli",
        "interpreter_sha256_before": exe_before,
        "interpreter_sha256_after": psr.sha256_file(psr.EXE),
        "upstream_mdlzork_checked_out": head,
        "game_dir": "mdlzork_771212/patched_confusion",
        "shim_src_sha256": psr.sha256_file(a.shim_src),
        "shim": "scripts/reference/fixed_time.c compiled per capture: "
                "gcc -shared -fPIC -O2 -o fixed_time.so fixed_time.c -ldl; "
                "LD_PRELOAD, MDL_FIXED_EPOCH=250776000, TZ=UTC",
        "protocol": "scripts/probe_death_scenario_reference.py (module docstring); "
                    "run_case from scripts/probe_session_reference.py",
        "prompt_split": "any",
        "entry_prompts": {str(k): v for k, v in sorted(entry_prompts.items())},
        "endings": endings,
        "native_zork_log": zork_logs,
        "checks": checks,
        "transcript": {
            "source_case": t1["name"],
            "stdout_sha256": t1["stdout_sha256"],
            "game_output_raw": g1,
            "game_output_canonical": canonical,
            "split": split_responses(canonical, cmds),
            "split_note": "split at line-initial `>` only: the YES/NO answer has no `>`, so "
                          "from the death question on each row holds the NEXT command's "
                          "response (informational; the runner uses entry_prompts)",
        },
        "diagnostic": {"source_case": x1["name"], "diag_forms": diag_forms, **diag,
                       **devents[n]},
        "end_checkpoints": end_checkpoints,
        "diag_logs": ("Dkk cases: diag_log replaced by diag_log_sha256 and diag_log_bytes; "
                      "their last checkpoints are end_checkpoints; X1's diag_log kept in full")
        if compact else "every diagnostic case keeps its diag_log",
        "cases": rows,
    }
    text = json.dumps(res, indent=2, ensure_ascii=False) + "\n"
    tmp = os.environ.get("TMPDIR", "/tmp").rstrip("/")
    for c in prefixes + [t1b]:
        assert tmp not in c["stdout_raw"] and str(psr.ROOT) not in c["stdout_raw"], c["name"]
    text = text.replace(tmp, "$TMPDIR").replace(str(psr.ROOT), "<repo>")
    a.output.write_text(text, encoding="utf-8")
    print(json.dumps({k: v for k, v in checks.items()
                      if k not in ("prefix_files_changed",)}, indent=1), file=sys.stderr)
    ok = (checks["t1_equals_t1b_bytes"] and checks["diag_game_part_equals_t1_game_part_bytes"]
          and checks["diag_prefix_game_parts_equal_prefix_game_parts"]
          and endings == declared_endings and dendings == declared_endings
          and all((e["quit_nargs"] == [0]) == (d == "quit")
                  and len(e["quit_nargs"]) <= 1
                  for e, d in zip(devents, declared_endings))
          and checks["diag_prefix_checkpoint_counts"]
          == checks["expected_diag_prefix_checkpoint_counts"]
          and sorted(devents[n]["yes_no_entries"]) == sorted(entry_prompts)
          and checks["prefix_gt_counts"] == checks["expected_prefix_gt_counts"]
          and not head_errors
          and checks["prefix_runs_consistent_with_t1"]
          and exe_before == res["interpreter_sha256_after"])
    print("CAPTURE", "OK" if ok else "REJECTED", file=sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
