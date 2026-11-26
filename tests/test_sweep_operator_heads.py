"""Guard the M4 operator-head sweep (scripts/sweep_operator_heads.py): the
reader rules it relies on, and that the committed sweep JSON still equals a
fresh run over the pinned source (skipped when the source is not fetched)."""

import json
from pathlib import Path

import pytest

from scripts import sweep_operator_heads as sweep

ROOT = Path(__file__).resolve().parents[1]
COMMITTED = ROOT / "docs/evidence/M4/operator-head-sweep.json"


def read(text):
    nodes, comments = sweep.Reader(text, "t.mud").read_all()
    return nodes, comments


def walk(text):
    sw = sweep.Sweep()
    nodes, comments = read(text)
    for n in nodes:
        sw.walk(n, "t.mud", set(), None, set())
    for c in comments:
        sw.walk(c, "t.mud", {"comment"}, None, set())
    return sw


def test_comment_skips_exactly_one_object():
    nodes, comments = read('; <FOO 1> <BAR 2>')
    assert [n.value[0].value for n in nodes] == ["BAR"]
    assert [c.value[0].value for c in comments] == ["FOO"]


def test_character_and_escape_and_strings_are_not_code():
    nodes, _ = read(r'<MEMQ !\< "a <B> \" c"> <X\ Y>')
    assert nodes[0].value[1].kind == "char" and nodes[0].value[1].value == "<"
    assert nodes[0].value[2].kind == "string"
    assert nodes[1].value[0].value == "X Y"


def test_heads_contexts_and_generated_heads():
    sw = walk("<DEFINE F (A) #DECL ((A) <OR ATOM FALSE>) <ABS .A> '<Q> %<+ 1 2> "
              "<FORM GEN .A> <APPLY ,APP> <MAPF ,MAPPED <FUNCTION (X) <.A>> ()>>")
    by = {(s["name"], s["kind"]): s for s in sw.sites}
    assert by[("ABS", "head")]["function"] == "F"
    assert by[("OR", "head")]["context"] == ["decl"]
    assert by[("Q", "head")]["context"] == ["quoted"]
    assert by[("+", "head")]["context"] == ["readeval"]
    assert ("GEN", "generated-head") in by
    assert ("APP", "applied-gval") in by and ("MAPPED", "applied-gval") in by
    assert "F" in sw.defs


def test_newstruc_fields_rest_marker_and_flagword_are_game_defined():
    sw = walk('<NEWSTRUC HACK VECTOR HACTION RAPPLIC "REST" HROOMS <LIST [REST ROOM]> '
              'HFLAG ANY> <FLAGWORD BIT1 BIT2> <MSETG K 1>')
    for name in ("HACTION", "HROOMS", "HFLAG", "BIT1", "BIT2", "K"):
        assert name in sw.defs, name
    assert "RAPPLIC" not in sw.defs and "LIST" not in sw.defs


def test_trailers():
    assert sweep.base_name("CLOSE!-WORDS") == "CLOSE"
    assert sweep.other_oblist("CLOSE!-WORDS")
    assert not sweep.other_oblist("TOPLEVEL!-")
    assert not sweep.other_oblist("ABS")


@pytest.mark.skipif(not sweep.GAME.is_dir(), reason="pinned game source not fetched")
def test_committed_sweep_matches_fresh_run():
    fresh = json.dumps(sweep.run_sweep(sweep.GAME), indent=1) + "\n"
    assert COMMITTED.read_text(encoding="utf-8") == fresh
    data = json.loads(fresh)
    live = {m["name"] for m in data["missing"] if m["class"] == "missing"}
    # The inventory's static candidates still unimplemented
    # (GAMEPLAY-FAILURE-INVENTORY.md); fixed ones move to builtins.
    assert {"ACCESS", "EVAL", "PARSE"} <= live
    # INV-07 PRINT implemented by M4 #173 (HANDLE's MAPF of PRINT).
    assert "PRINT" not in live
    assert "PRINT" in data["runtime_name_sources"]["builtin_table"]
    assert "PRINT" in data["builtin_used"]
    # INV-05 fixed by M4 S10 (#171): FILE-LENGTH and CLOSE are builtins now
    # (read-only file CHANNELs of the allowlist only, ADR-0055 amendment).
    for name in ("FILE-LENGTH", "CLOSE"):
        assert name not in live, name
        assert name in data["runtime_name_sources"]["builtin_table"], name
        assert name in data["builtin_used"], name
    # INV-01 fixed by M4 S8 (#167); INV-02/03/04 fixed by M4 S9 (#168-#170):
    # ABS, IMAGE, SLEEP and TIME are runtime builtins now.
    for name in ("ABS", "IMAGE", "SLEEP", "TIME"):
        assert name not in live, name
        assert name in data["runtime_name_sources"]["builtin_table"], name
    for name in ("ABS", "IMAGE", "SLEEP"):
        assert name in data["builtin_used"], name
    # TIME is applied by name only (a data ATOM, never a head); it is no
    # longer a ROOT-SUBR data reference this runtime lacks.
    assert "TIME" not in {r["name"] for r in data["root_name_data_refs"]}
