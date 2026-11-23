"""Mutation checks for issue #139. Run from the repository root:
  PLTCOLLECTS=":$PWD" python3 -I docs/evidence/M3/I139-mutations.py
Replaces the body of mdl-unwind's dynamic-wind, recompiles, runs the UNWIND
tests, records exit status and failure counts, and restores core.rkt."""
import re, shutil, subprocess, sys, os
CORE = "mdl/runtime/core.rkt"
ORIG = open(CORE).read()
BODY = """    (lambda ()
      (define value
        (call-with-exception-handler
         (lambda (raised) (set! raised-through? #t) raised)
         std-thunk))
      (set! completed-normally? #t)
      value)
    (lambda ()
      (unless (or completed-normally? raised-through?)
        (erre-thunk)
        (void)))))"""
assert ORIG.count(BODY) == 1
MUT = {
 "M1-plain-dynamic-wind": """    std-thunk
    (lambda () (erre-thunk) (void))))""",
 "M2-old-ADR-0018-cleanup-on-raise": """    (lambda ()
      (define value (std-thunk))
      (set! completed-normally? #t)
      value)
    (lambda ()
      (unless completed-normally? (erre-thunk) (void)))))""",
 "M3-drop-cleanup-on-transfer": """    std-thunk
    void))""",
 "M4-swallow-cleanup-errors": BODY.replace("(erre-thunk)", "(with-handlers ([exn:fail? void]) (erre-thunk))"),
 "M5-only-exn-values-skip": BODY.replace("(set! raised-through? #t)", "(when (exn? raised) (set! raised-through? #t))"),
}
TESTS = ["tests/unwind_raise_test.rkt", "tests/control_test.rkt", "tests/mapf_test.rkt", CORE]
try:
    for name, body in MUT.items():
        open(CORE, "w").write(ORIG.replace(BODY, body))
        subprocess.run(["raco", "make", CORE] + TESTS[:3], check=True)
        print(f"== {name}")
        for t in TESTS:
            r = subprocess.run(["raco", "test", t], capture_output=True, text=True)
            out = r.stdout + r.stderr
            m = re.findall(r"(\d+)/(\d+) test failures", out)
            fails = out.count("FAILURE")
            print(f"   {t}: exit={r.returncode} failures={m[-1] if m else ('0' if r.returncode==0 else '?')} FAILURE-blocks={fails}")
finally:
    open(CORE, "w").write(ORIG)
    subprocess.run(["raco", "make", CORE] + TESTS[:3], check=True)
    print("restored", CORE)
