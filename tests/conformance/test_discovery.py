"""Candidate inventory tests use small Racket modules without instantiating them."""

import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SCANNER = ROOT / "scripts/conformance_discovery.rkt"

CORE = """(define builtin-table
  (hash "DECLARE" (lambda () (string-append "NOT-A-KEY" "DECOY"))
        "TYPE" mdl-type))
(define (make-mdl-atom-space)
  (define types (make-hash))
  (for ([entry (in-list '(("TYPE" . "WORD")
                          ("SECOND" . "WORD")))])
    (define type-atom (seed-root! (car entry)))
    (hash-set! types type-atom (cdr entry)))
  (for ([entry (in-list '(("NOT-A-TYPE" . "WORD")))])
    (hash-set! unrelated type-atom (cdr entry))))
(define (mdl-eval-form value)
  (case (string->symbol (mdl-atom-pname op))
    [(QUOTE DEFMAC) 'unevaluated]
    [(NESTED)
     (case host-parameter
       [(NOT-AN-OP) 'false-positive])]
    [else #f]))
"""
COMPILER = """(define (compile-form n locals)
  `(case (string->symbol op) [(NOT-COMPILED) 0])
  (case (string->symbol op)
    [(DEFINE %?!) (void)]
    [else #f]))
"""
LOADER = """(define (make-mdl-session)
  ; (mdl-define-subr! (mdl-root-atom "COMMENT") values)
  '(mdl-define-subr! (mdl-root-atom "QUOTED") values)
  (call-in-session session
    (lambda ()
      (mdl-define-subr! (mdl-root-atom "FLOAD") values))))
(define (custom-session)
  (mdl-define-subr! (mdl-root-atom "NOT-STARTUP") values))
"""

SOURCES = {
    "mdl/runtime/core.rkt": CORE,
    "mdl/compiler.rkt": COMPILER,
    "mdl/loader.rkt": LOADER,
}


def write_sources(root, sources, *, prefix=""):
    for file, body in sources.items():
        path = root / file
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#lang racket/base\n" + prefix + body, encoding="utf-8")


def discover(root):
    return json.loads(
        subprocess.check_output(["racket", str(SCANNER), str(root)], text=True)
    )


def without_lines(candidates):
    return {
        name: [(site["file"], site["kind"]) for site in sites]
        for name, sites in candidates.items()
    }


def test_selects_real_declarations_and_ignores_decoys(tmp_path):
    write_sources(tmp_path, SOURCES)
    found = discover(tmp_path)
    core, compiler, loader = SOURCES
    assert without_lines(found) == {
        "DECLARE": [(core, "runtime operator binding")],
        "TYPE": [(core, "runtime operator binding"), (core, "runtime type registration")],
        "SECOND": [(core, "runtime type registration")],
        "QUOTE": [(core, "interpreted evaluator special form")],
        "DEFMAC": [(core, "interpreted evaluator special form")],
        "NESTED": [(core, "interpreted evaluator special form")],
        "DEFINE": [(compiler, "compiler special form")],
        "%?!": [(compiler, "compiler special form")],
        "FLOAD": [(loader, "loader-only operator binding")],
    }
    for name, sites in found.items():
        for site in sites:
            line = (tmp_path / site["file"]).read_text().splitlines()[site["line"] - 1]
            assert name in line


def test_relocating_declarations_updates_lines_not_semantic_inventory(tmp_path):
    write_sources(tmp_path, SOURCES)
    before = discover(tmp_path)

    # Prepend a commented declaration and enough lines to shift any narrow
    # source interval, then relocate a real top-level definition.
    prefix = (
        '; (define builtin-table (hash "GHOST" values))\n'
        '(define unrelated-register (hash "ANOTHER-GHOST" values))\n'
        + "\n" * 250
    )
    atom_space_start = CORE.index("(define (make-mdl-atom-space)")
    eval_start = CORE.index("(define (mdl-eval-form")
    moved_core = CORE[eval_start:] + CORE[:atom_space_start] + CORE[atom_space_start:eval_start]
    write_sources(tmp_path, {**SOURCES, "mdl/runtime/core.rkt": moved_core}, prefix=prefix)
    after = discover(tmp_path)
    assert without_lines(before) == without_lines(after)
    assert before != after


def test_scans_current_checkout_by_static_declaration():
    found = discover(ROOT)
    assert {site["kind"] for site in found["FUNCTION"]} == {
        "runtime type registration",
        "compiler special form",
        "interpreted evaluator special form",
    }
    assert found["FLOAD"][0]["kind"] == "loader-only operator binding"
    assert found["ABS"][0]["kind"] == "runtime operator binding"
