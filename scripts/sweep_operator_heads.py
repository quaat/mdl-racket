#!/usr/bin/env python3
"""Static sweep of operator heads in the loaded 1977 Zork source (M4 Phase 1).

Reads the twelve files 77loadall.mud loads (plus 77loadall.mud and run.mud)
with a small standalone MDL reader and lists every operator the game can
call that is neither a runtime built-in nor defined by the game itself.
It is a discovery tool for docs/evidence/M4/GAMEPLAY-FAILURE-INVENTORY.md,
not a reachability proof: reachability is classified by hand from the
call sites it reports.

Usage:
    python3 -I scripts/sweep_operator_heads.py OUT.json
    python3 -I scripts/sweep_operator_heads.py --check docs/evidence/M4/operator-head-sweep.json

What counts as an operator use ("site"):
  * head: the first element of a FORM `<X ...>` when it is an ATOM;
  * generated head: the first argument of `<FORM X ...>` (DEFMAC bodies
    build code this way, e.g. DISPATCH in APPLY-RANDOM);
  * applied GVAL: `,X` passed to APPLY, MAPF or MAPR in function position.
Sites are tagged with their context: `comment` (inside a `;` comment, never
read), `readeval` (inside `%<...>`, run once at read time), `quoted`
(inside `'...`), `decl` (a type specification: #DECL, GDECL, NEWSTRUC and
NEWTYPE declarations; never evaluated), `string`-free code otherwise.
STRING contents are not code to the reader; strings that the game turns
into code (PARSE/EVAL) are reported separately under `strings_as_code`.

Name classes (first match wins):
  * builtin: a builtin-table key, a root-internal name, a compiler special
    form (mdl/compiler.rkt compile-form) or a loader SUBR (FLOAD), read
    from the runtime source so the sweep follows the runtime;
  * game: DEFINE/DEFMAC, SETG/PSETG/MSETG of a literal ATOM, NEWSTRUC field
    names (offsets: `<ODESC2 .O>` applies a FIX, i.e. NTH), FLAGWORD bit
    names and MAKE-SLOT accessors;
  * local: an ATOM bound as a formal of an enclosing FUNCTION/DEFINE (MDL
    applies its LVAL when it has no GVAL);
  * missing: everything else. `in_confusion_root` says whether pinned
    Confusion has the name in its startup ROOT (mdl/runtime/root-names.rktd);
    a missing name that is not in ROOT fails natively as well.

Sites inside a function body that a later DEFINE of the same name replaces
(77patch.mud redefines DO-SAVE and DO-RESTORE) are tagged `superseded` and,
like comments and declarations, are not "live".

`root_name_data_refs` lists ATOMs and `,ATOM`s outside head position that
name something pinned Confusion has in its startup ROOT but this runtime
does not provide (and the game does not define). The game applies some
ATOMs by name through APPLY-RANDOM (<APPLY <GVAL atom>>); this is how the
verb table and the room BLROO reach the ROOT SUBR TIME, which no head-only
sweep can see. Most hits are inert data (TYPE names, OBLIST names, local
variables); the inventory classifies each by hand. The complete list of
applied action ATOMs is a dynamic check (native diagnostic case X1 of
scripts/probe_failure_inventory_reference.py).

The game also SETGs atoms it computes (`<SETG .ATM ...>`: rooms, objects,
verbs, flags, CEVENTs). Those are never heads, so they cannot hide a missing
operator; they are reported as a count only.

Line numbers are physical lines of the source files (as `grep -n` prints).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME_REL = ".cache/upstream/mdlzork/mdlzork_771212/patched_confusion"
GAME = ROOT / GAME_REL
LOADED = ["81prim.mud", "77defs.mud", "77makstr.mud", "81tell-repl.mud", "77act1.mud",
          "77act2.mud", "77act3.mud", "77rooms.mud", "77patch.mud", "77np.mud",
          "78melee.mud", "77dung.mud"]
ENTRY_FILES = ["77loadall.mud", "run.mud"]
CORE = ROOT / "mdl/runtime/core.rkt"
COMPILER = ROOT / "mdl/compiler.rkt"
LOADER = ROOT / "mdl/loader.rkt"
ROOT_NAMES = ROOT / "mdl/runtime/root-names.rktd"


class ReadError(Exception):
    pass


class Node:
    __slots__ = ("kind", "value", "line", "col", "prefix")

    def __init__(self, kind, value, line, col, prefix=None):
        self.kind, self.value, self.line, self.col, self.prefix = kind, value, line, col, prefix

    def __repr__(self):  # pragma: no cover - debugging aid
        return f"Node({self.kind!r}, {self.value!r}, {self.line})"


DELIMS = set("<>()[]{}\";,'") | {"\0"}


class Reader:
    """Enough MDL syntax for the 1977 sources: FORM/LIST/VECTOR/UVECTOR,
    strings, `;` comments (the next object), `!\\c` characters, `\\` atom
    escapes, `'` `.` `,` `%` `%%` `#TYPE obj` prefixes, `!.` `!,` `!<`
    segments and `!>` / `!]` closes. Atoms keep their `!-` trailers."""

    def __init__(self, text: str, name: str):
        self.t, self.n, self.i, self.line, self.col, self.name = text, len(text), 0, 1, 1, name

    def peek(self, k=0):
        j = self.i + k
        return self.t[j] if j < self.n else None

    def adv(self):
        ch = self.t[self.i]
        self.i += 1
        if ch == "\n":
            self.line, self.col = self.line + 1, 1
        else:
            self.col += 1
        return ch

    def err(self, msg):
        raise ReadError(f"{self.name}:{self.line}:{self.col}: {msg}")

    def skip_ws(self, comments):
        while True:
            ch = self.peek()
            if ch is None:
                return
            if ch.isspace() or ch == "\0" or ch == "\x0c":
                self.adv()
            elif ch == ";":
                self.adv()
                self.skip_ws(comments)
                if self.peek() is None:
                    self.err("comment without an object")
                comments.append(self.read(comments))
            else:
                return

    def read_all(self):
        out, comments = [], []
        while True:
            self.skip_ws(comments)
            if self.peek() is None:
                return out, comments
            out.append(self.read(comments))

    def read_seq(self, close, kind, line, col, comments, bang_close=None):
        items = []
        while True:
            self.skip_ws(comments)
            ch = self.peek()
            if ch is None:
                self.err(f"unterminated {kind} from line {line}")
            if ch == close:
                self.adv()
                return Node(kind, items, line, col)
            if bang_close and ch == "!" and self.peek(1) == bang_close:
                self.adv(); self.adv()
                return Node(kind, items, line, col)
            if ch in ")]>}" :
                self.err(f"unexpected {ch!r} in {kind} from line {line}")
            items.append(self.read(comments))

    def read(self, comments):
        self.skip_ws(comments)
        line, col = self.line, self.col
        ch = self.peek()
        if ch is None:
            self.err("unexpected end of input")
        if ch == "<":
            self.adv()
            return self.read_seq(">", "form", line, col, comments, bang_close=">")
        if ch == "(":
            self.adv()
            return self.read_seq(")", "list", line, col, comments)
        if ch == "[":
            self.adv()
            return self.read_seq("]", "vector", line, col, comments, bang_close="]")
        if ch == "{":
            self.adv()
            return self.read_seq("}", "template", line, col, comments)
        if ch == '"':
            self.adv()
            buf = []
            while True:
                c = self.peek()
                if c is None:
                    self.err(f"unterminated string from line {line}")
                self.adv()
                if c == "\\":
                    if self.peek() is None:
                        self.err("string escape at end of input")
                    buf.append(self.adv())
                elif c == '"':
                    return Node("string", "".join(buf), line, col)
                else:
                    buf.append(c)
        if ch == "'":
            self.adv()
            return Node("quote", self.read(comments), line, col)
        if ch == ",":
            self.adv()
            return Node("gval", self.read(comments), line, col)
        if ch == "%":
            self.adv()
            if self.peek() == "%":
                self.adv()
                return Node("readeval-discard", self.read(comments), line, col)
            return Node("readeval", self.read(comments), line, col)
        if ch == "#":
            self.adv()
            tname = self.read_token()
            return Node("hash", (tname, self.read(comments)), line, col)
        if ch == "!":
            nxt = self.peek(1)
            if nxt == "\\":
                self.adv(); self.adv()
                return Node("char", self.adv(), line, col)
            if nxt == "[":
                self.adv(); self.adv()
                n = self.read_seq("]", "uvector", line, col, comments, bang_close="]")
                return n
            if nxt in ("<", ".", ",", "'"):
                self.adv()
                return Node("segment", self.read(comments), line, col)
        if ch == "." and self.peek(1) is not None and self.peek(1) not in DELIMS \
                and not self.peek(1).isspace() and not self.peek(1).isdigit():
            self.adv()
            return Node("lval", self.read(comments), line, col)
        tok = self.read_token()
        if tok == "":
            self.err(f"unexpected character {ch!r}")
        if re.fullmatch(r"-?\d+\.?", tok) or re.fullmatch(r"\*[0-7]+\*", tok) \
                or re.fullmatch(r"-?\d*\.\d+(E-?\d+)?", tok):
            return Node("number", tok, line, col)
        return Node("atom", tok, line, col)

    def read_token(self):
        buf = []
        while True:
            c = self.peek()
            if c is None or c in DELIMS or c.isspace():
                break
            if c == "!" and self.peek(1) in ("]", ">"):
                break
            if c == "\\":
                self.adv()
                if self.peek() is None:
                    self.err("atom escape at end of input")
                buf.append(self.adv())
                continue
            buf.append(self.adv())
        return "".join(buf)


def base_name(atom: str) -> str:
    """PNAME without an `!-OBLIST` trailer (`FOO!-BAR` -> FOO, `FOO!-` -> FOO)."""
    i = atom.find("!-")
    return atom[:i] if i > 0 else atom


def other_oblist(atom: str) -> bool:
    """True for `FOO!-BAR` (an ATOM on OBLIST BAR, e.g. CLOSE!-WORDS)."""
    i = atom.find("!-")
    return i > 0 and i + 2 < len(atom)


def atom_of(node):
    return base_name(node.value) if node is not None and node.kind == "atom" else None


# --- runtime name sets -----------------------------------------------------------

def runtime_names() -> dict:
    core = CORE.read_text(encoding="utf-8")
    m = re.search(r"\(define builtin-table\s*\(hash(.*?)\n;; ADR-0060", core, re.S)
    if not m:
        raise SystemExit("builtin-table not found in core.rkt")
    builtin = set(re.findall(r'^\s*"([^"]+)"\s', m.group(1), re.M))
    m = re.search(r"\(define root-internal-names\s*'\((.*?)\)\)", core, re.S)
    if not m:
        raise SystemExit("root-internal-names not found in core.rkt")
    internal = set(re.findall(r'"([^"]+)"', m.group(1)))
    comp = COMPILER.read_text(encoding="utf-8")
    m = re.search(r"\(define \(compile-form n locals\)(.*?)\n\(define \(compile-expression ",
                  comp, re.S)
    if not m:
        raise SystemExit("compile-form not found in compiler.rkt")
    special = set(re.findall(r"\[\(([A-Z][A-Z0-9?!-]*)\)", m.group(1)))
    loader = set(re.findall(r'mdl-define-subr! \(mdl-root-atom "([^"]+)"\)',
                            LOADER.read_text(encoding="utf-8")))
    root = set(re.findall(r'"([^"]+)"', ROOT_NAMES.read_text(encoding="utf-8")))
    return {"builtin_table": builtin, "root_internal": internal,
            "compiler_special": special, "loader_subrs": loader, "confusion_root": root}


# --- walking -------------------------------------------------------------------

DEF_HEADS = {"DEFINE", "DEFMAC"}
# Sites never executed as written: comments, type declarations, and bodies
# replaced by a later DEFINE of the same name.
NONLIVE = {"comment", "decl", "superseded"}
SETG_HEADS = {"SETG", "PSETG", "MSETG"}


def formals_of(fl):
    out = set()
    if fl is None or fl.kind != "list":
        return out
    for x in fl.value:
        if x.kind == "atom":
            out.add(base_name(x.value))
        elif x.kind == "quote" and x.value.kind == "atom":
            out.add(base_name(x.value.value))
        elif x.kind == "list" and x.value:
            h = x.value[0]
            if h.kind == "atom":
                out.add(base_name(h.value))
            elif h.kind == "quote" and h.value.kind == "atom":
                out.add(base_name(h.value.value))
    return out


class Sweep:
    def __init__(self):
        self.sites = []            # every operator site
        self.defs = defaultdict(list)   # name -> [(kind, file, line)]
        self.computed_setg = 0
        self.computed_heads = []
        self.data_refs = []        # non-head ATOMs and GVALs (see root_name_data_refs)
        self.strings_as_code = []
        self.current_def = None    # (file, line) of the enclosing top-level DEFINE/DEFMAC

    def define(self, name, kind, f, line):
        self.defs[name].append({"kind": kind, "file": f, "line": line})

    def walk(self, node, f, ctx, fn, formals):
        k = node.kind
        if k == "form":
            self.walk_form(node, f, ctx, fn, formals)
        elif k in ("list", "vector", "uvector", "template"):
            for x in node.value:
                self.walk(x, f, ctx, fn, formals)
        elif k == "quote":
            self.walk(node.value, f, ctx | {"quoted"}, fn, formals)
        elif k == "readeval" or k == "readeval-discard":
            self.walk(node.value, f, ctx | {"readeval"}, fn, formals)
        elif k == "hash":
            tname, obj = node.value
            extra = {"decl"} if tname.upper() == "DECL" else {"hash-" + tname}
            self.walk(obj, f, ctx | extra, fn, formals)
        elif k == "gval" and node.value.kind == "atom" and not other_oblist(node.value.value):
            self.data_refs.append({"name": base_name(node.value.value), "kind": "gval",
                                   "file": f, "line": node.line, "function": fn,
                                   "context": sorted(ctx)})
        elif k in ("gval", "lval", "segment") and node.value.kind != "atom":
            self.walk(node.value, f, ctx, fn, formals)
        elif k == "atom" and not other_oblist(node.value):
            self.data_refs.append({"name": base_name(node.value), "kind": "atom",
                                   "file": f, "line": node.line, "function": fn,
                                   "context": sorted(ctx)})

    def site(self, name, kind, node, f, ctx, fn, formals):
        self.sites.append({"name": name, "kind": kind, "file": f, "line": node.line,
                           "col": node.col, "function": fn, "function_def": self.current_def,
                           "context": sorted(ctx), "local_formal": name in formals})

    def walk_form(self, node, f, ctx, fn, formals):
        items = node.value
        if not items:
            return
        head = items[0]
        hname = atom_of(head)
        args = items[1:]
        if hname is None:
            if head.kind != "number":
                self.computed_heads.append({"file": f, "line": node.line, "head_kind": head.kind,
                                            "function": fn, "context": sorted(ctx)})
            for x in items:
                self.walk(x, f, ctx, fn, formals)
            return
        self.site(hname, "head", head, f, ctx, fn, formals)
        code = not (ctx & {"quoted", "decl", "comment"})
        # definitions (only where the form is evaluated code or a load-time form)
        if hname in DEF_HEADS and args and args[0].kind == "atom":
            name = base_name(args[0].value)
            if code:
                self.define(name, hname, f, head.line)
            rest = args[1:]
            if hname == "DEFMAC" and rest and rest[0].kind == "atom" and len(rest) > 1:
                rest = rest[1:]
            elif hname == "DEFINE" and rest and rest[0].kind == "atom" and len(rest) > 1 \
                    and rest[1].kind == "list":
                rest = rest[1:]
            fl = rest[0] if rest else None
            inner = formals | formals_of(fl)
            outer_def = self.current_def
            if outer_def is None:
                self.current_def = (f, head.line)
            for x in rest:
                self.walk(x, f, ctx, name, inner)
            self.current_def = outer_def
            return
        if hname == "FUNCTION" and args:
            fl = args[0] if args[0].kind == "list" else (args[1] if len(args) > 1 else None)
            inner = formals | formals_of(fl)
            for x in args:
                self.walk(x, f, ctx, fn, inner)
            return
        if hname in ("PROG", "REPEAT") and args:
            fl = args[0] if args[0].kind == "list" else (args[1] if len(args) > 1 else None)
            inner = formals | formals_of(fl)
            for x in args:
                self.walk(x, f, ctx, fn, inner)
            return
        if hname in SETG_HEADS and len(args) >= 1:
            if args[0].kind == "atom":
                if code:
                    self.define(base_name(args[0].value), hname, f, head.line)
            else:
                self.computed_setg += 1
        if hname == "NEWSTRUC" and len(args) >= 2:
            # NEWSTRUC (81prim.mud:34): a "REST" STRING, a FALSE or a FORM
            # offset takes one element; a name (ATOM or LIST of ATOMs) and
            # its declaration take two.
            fields, j = args[2:], 0
            while j < len(fields):
                off = fields[j]
                if off.kind in ("string", "form"):
                    j += 1
                    continue
                if off.kind == "hash" and off.value[0].upper() == "FALSE":
                    j += 1
                    continue
                if off.kind == "atom" and code:
                    self.define(base_name(off.value), "NEWSTRUC-field", f, off.line)
                elif off.kind == "list" and code:
                    for a in off.value:
                        if a.kind == "atom":
                            self.define(base_name(a.value), "NEWSTRUC-field", f, a.line)
                if j + 1 < len(fields):
                    self.walk(fields[j + 1], f, ctx | {"decl"}, fn, formals)
                j += 2
            return
        if hname == "FLAGWORD":
            for a in args:
                if a.kind == "atom" and code:
                    self.define(base_name(a.value), "FLAGWORD-bit", f, a.line)
            return
        if hname == "MAKE-SLOT" and args and args[0].kind == "atom" and code:
            self.define(base_name(args[0].value), "MAKE-SLOT", f, head.line)
        if hname == "GDECL":
            for x in args:
                self.walk(x, f, ctx | {"decl"}, fn, formals)
            return
        if hname == "NEWTYPE":
            for j, x in enumerate(args):
                self.walk(x, f, ctx | ({"decl"} if j >= 2 else set()), fn, formals)
            return
        if hname == "FORM" and args and args[0].kind == "atom":
            self.site(base_name(args[0].value), "generated-head", args[0], f, ctx, fn, formals)
        if hname in ("APPLY", "MAPF", "MAPR") and args:
            fpos = args[0] if hname == "APPLY" else (args[1] if len(args) > 1 else None)
            if fpos is not None and fpos.kind == "gval" and fpos.value.kind == "atom":
                self.site(base_name(fpos.value.value), "applied-gval", fpos.value, f, ctx, fn,
                          formals)
            if hname != "APPLY" and args[0].kind == "gval" and args[0].value.kind == "atom":
                self.site(base_name(args[0].value.value), "applied-gval", args[0].value, f,
                          ctx, fn, formals)
        if hname in ("PARSE", "EVAL", "LPARSE", "READ", "READCHR") and code:
            self.strings_as_code.append({"name": hname, "file": f, "line": head.line,
                                         "function": fn,
                                         "argument": (args[0].kind if args else None)})
        for x in args:
            self.walk(x, f, ctx, fn, formals)


def run_sweep(game: Path) -> dict:
    names = runtime_names()
    builtin = (names["builtin_table"] | names["root_internal"] | names["compiler_special"]
               | names["loader_subrs"])
    sw = Sweep()
    comment_nodes = []
    file_stats = {}
    for f in ENTRY_FILES + LOADED:
        text = (game / f).read_text(encoding="latin-1")
        nodes, comments = Reader(text, f).read_all()
        file_stats[f] = {"top_level_objects": len(nodes), "comments": len(comments)}
        for n in nodes:
            sw.walk(n, f, set(), None, set())
        for c in comments:
            comment_nodes.append((f, c))
    for f, c in comment_nodes:
        sw.walk(c, f, {"comment"}, None, set())
    # A function DEFINEd again later in load order (77patch.mud redefines
    # DO-SAVE and DO-RESTORE under REDEFINE) supersedes the earlier body:
    # sites inside an earlier body are tagged `superseded`.
    order = {f: i for i, f in enumerate(ENTRY_FILES + LOADED)}
    last_def = {}
    for name, ds in sw.defs.items():
        fdefs = [d for d in ds if d["kind"] in DEF_HEADS]
        if fdefs:
            last = max(fdefs, key=lambda d: (order[d["file"]] if d["file"] in LOADED else -1,
                                             d["line"]))
            last_def[name] = (last["file"], last["line"])
    superseded = []
    for name, ds in sorted(sw.defs.items()):
        for d in ds:
            if d["kind"] in DEF_HEADS and last_def.get(name) != (d["file"], d["line"]):
                superseded.append({"name": name, "file": d["file"], "line": d["line"],
                                   "superseded_by": "%s:%d" % last_def[name]})
    sup_keys = {(d["file"], d["line"]) for d in superseded}
    for s in sw.sites:
        fd = s.pop("function_def")
        if fd is not None and tuple(fd) in sup_keys:
            s["context"] = sorted(set(s["context"]) | {"superseded"})
    # Group sites by name.
    by_name = defaultdict(list)
    for s in sw.sites:
        by_name[s["name"]].append(s)

    def classify(name, sites):
        if name in builtin:
            return "builtin"
        if name in sw.defs:
            return "game"
        if sites and all(s["local_formal"] for s in sites):
            return "local"
        return "missing"

    missing, summary = [], {"builtin": 0, "game": 0, "local": 0, "missing": 0}
    for name in sorted(by_name):
        sites = by_name[name]
        cls = classify(name, sites)
        live = [s for s in sites if not set(s["context"]) & NONLIVE]
        if cls == "missing" and not live:
            cls = "missing-not-live"
        summary[cls] = summary.get(cls, 0) + 1
        if cls.startswith("missing"):
            missing.append({
                "name": name,
                "class": cls,
                "in_confusion_root": name in names["confusion_root"],
                "live_site_count": len(live),
                "sites": [{k: s[k] for k in ("file", "line", "col", "kind", "function",
                                              "context", "local_formal")} for s in sites],
            })
    game_defined = {n: d for n, d in sorted(sw.defs.items())}
    # Data references (an ATOM or `,ATOM` outside head position, outside
    # comments, declarations and superseded bodies) to names pinned
    # Confusion has in its startup ROOT but this runtime does not provide
    # and the game does not define. Such an ATOM can still be applied by
    # name (APPLY-RANDOM <GVAL atom>): the verb table binds internal verbs
    # to the ROOT SUBR TIME this way. Most hits are inert data (type names,
    # words); each is classified by hand in the inventory.
    refs = defaultdict(list)
    for r in sw.data_refs:
        n = r["name"]
        if n in names["confusion_root"] and n not in builtin and n not in sw.defs \
                and not set(r["context"]) & NONLIVE:
            refs[n].append({k: r[k] for k in ("kind", "file", "line", "function", "context")})
    root_refs = [{"name": n, "count": len(v), "sites": v} for n, v in sorted(refs.items())]
    return {
        "schema_version": 1,
        "kind": "m4-operator-head-sweep",
        "generator": "scripts/sweep_operator_heads.py",
        "game_dir": GAME_REL,
        "files": ENTRY_FILES + LOADED,
        "file_stats": file_stats,
        "runtime_name_sources": {
            "builtin_table": sorted(names["builtin_table"]),
            "root_internal": sorted(names["root_internal"]),
            "compiler_special": sorted(names["compiler_special"]),
            "loader_subrs": sorted(names["loader_subrs"]),
            "confusion_root_count": len(names["confusion_root"]),
        },
        "summary": {"distinct_operator_names": len(by_name), "by_class": summary,
                    "sites": len(sw.sites), "game_defined_names": len(sw.defs),
                    "computed_setg_sites": sw.computed_setg,
                    "computed_head_sites": len(sw.computed_heads)},
        "missing": missing,
        "superseded_definitions": superseded,
        "computed_heads": sw.computed_heads,
        "strings_as_code": sw.strings_as_code,
        "game_defined_kinds": {n: sorted({d["kind"] for d in v})
                               for n, v in game_defined.items()},
        "root_name_data_refs": root_refs,
        "builtin_used": sorted(n for n in by_name if n in builtin),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("output", type=Path, nargs="?")
    ap.add_argument("--check", type=Path,
                    help="regenerate and compare with this committed JSON (exit 1 on drift)")
    a = ap.parse_args()
    if not GAME.is_dir():
        raise SystemExit(f"missing pinned game sources: {GAME_REL}")
    res = run_sweep(GAME)
    text = json.dumps(res, indent=1, sort_keys=False) + "\n"
    if a.check:
        old = a.check.read_text(encoding="utf-8")
        if old != text:
            print(f"operator sweep drift: {a.check} differs from a fresh run", file=sys.stderr)
            return 1
        print("operator sweep: committed JSON matches a fresh run", file=sys.stderr)
        return 0
    if a.output:
        a.output.write_text(text, encoding="utf-8")
    for m in res["missing"]:
        live = [s for s in m["sites"] if not set(s["context"]) & NONLIVE]
        locs = ", ".join(f'{s["file"]}:{s["line"]}' for s in live[:4]) or "(no live site)"
        print(f'{m["name"]:16} {m["class"]:22} root={str(m["in_confusion_root"])[0]} '
              f'live={m["live_site_count"]:2} {locs}')
    print(json.dumps(res["summary"]), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
