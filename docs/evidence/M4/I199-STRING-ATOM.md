# Issue #199: non-ATOM first arguments to the binding primitives (reference observations)

Read-only reference investigation, recorded 2026-11-26 on branch
`fix/199-binding-atom-string` (worktree commit `6a9f0fe`, = main). Nothing
under `mdl/`, `tests/`, `scripts/` or `Makefile` was changed. These are
observations only, not a parity claim and not a fix.

## Question and expected semantics

The [MDL manual, chapter 4](https://mdl-language.readthedocs.io/en/latest/04-values-of-atoms/)
defines `SET`, `SETG`, `LVAL`, `GVAL`, `VALUE`, `UNASSIGN`, `GUNASSIGN`,
`ASSIGNED?`, `GASSIGNED?`, `BOUND?` and `GBOUND?` on an ATOM. Their first
argument is an ATOM, and the manual gives no conversion from a STRING (or
any other type) to an ATOM. A STRING, FIX or FORM in that position should
therefore be an error and should not intern or touch the ATOM whose PNAME
the STRING spells. `MANIFEST` (chapter 14) also takes ATOMs. This
runtime's `binding-atom` (`mdl/runtime/core.rkt:124`) instead interns a
STRING as an ATOM name. The question is what pinned Confusion does for each
primitive, at top level and inside a FUNCTION, and through the original
`MSETG`/`PSETG` from `81prim.mud`.

## Interpreter and sources

| Item | Value |
|---|---|
| Interpreter | `.cache/build/confusion_patched/mdli` |
| Interpreter SHA-256 | `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` (both reference JSONs record it, and so does `sha256sum`) |
| Upstream mdlzork checkout | `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; `git status --short` is empty before and after |
| Working directory | disposable copy `$TMPDIR/i199/game` of `mdlzork_771212/patched_confusion` (18 files). The sorted `sha256sum` list of every file is identical before and after both capture rounds, so no case wrote a file |
| Our runtime | worktree commit `6a9f0fe`; `mdl/runtime/core.rkt` SHA-256 is in `i199-string-atom-ours.json`; Racket v7.9 [bc] |

`make reference-build` was not run.

## Files

- `i199-string-atom-cases.json`: 11 cases expected to exit cleanly (ATOM
  controls and the MANIFEST cases).
- `i199-string-atom-error-cases.json`: 69 cases with deliberate errors.
- `i199-string-atom-reference.json`, `i199-string-atom-error-reference.json`:
  native Confusion output from `scripts.mdl_probe` (full stdout, stderr and
  exit code for each case).
- `i199-string-atom-ours.json`: this runtime's result for every form of the
  same 80 cases.

Each case runs in its own fresh process (Confusion) or fresh
`make-mdl-session` (ours), so a case cannot affect another. Follow-up forms
inside one case (for example `<GASSIGNED? FOO>` after `<SETG "FOO" 3>`) show
the state after the probed call. Confusion keeps reading stdin after both
kinds of error described below, so its follow-ups are evaluated too.

## Commands and exit codes

Confusion, run from the repository's probe tool. The tool is unchanged:
a 6-line wrapper only repoints its module-level `GAME` (the working
directory) to the disposable copy.

```sh
# $TMPDIR/i199/probe_in_copy.py (sha256 b1a5a9aa...785549f):
#   import sys; from pathlib import Path; import scripts.mdl_probe as m
#   m.GAME = Path(sys.argv[1]).resolve()
#   sys.argv = ["scripts.mdl_probe"] + sys.argv[2:]; raise SystemExit(m.main())
cp -a .cache/upstream/mdlzork/mdlzork_771212/patched_confusion $TMPDIR/i199/game
for run in 1 2; do for f in i199-string-atom i199-string-atom-error; do
  PYTHONPATH=$PWD /usr/bin/python3 $TMPDIR/i199/probe_in_copy.py $TMPDIR/i199/game \
    --cases docs/evidence/M4/$f-cases.json --output $TMPDIR/i199/run$run/$f-reference.json
done; done
```

| Run | Cases file | Exit | Result |
|---|---|---:|---|
| 1 and 2 | `i199-string-atom-cases.json` | 0 | 11/11 ok (exit 0, empty stderr) |
| 1 and 2 | `i199-string-atom-error-cases.json` | 1, **expected** | 0/69 "ok": every case has stderr output or an error level, as intended. Every process exited 0 |

Determinism: the `cases` arrays of run 1 and run 2 are identical (Python
`==` on the parsed JSON, which covers every stdout, stderr and exit field)
for both files, and the interpreter SHA-256 is the same. Only
`recorded_at` differs. Run 1 is the committed file.

Our runtime: a read-only harness `$TMPDIR/i199/ours/run_ours.rkt` (sha256
`df73be27...a80b1c91`). It makes one `make-mdl-session` per case, rooted at
another disposable copy, so `FLOAD "81prim.mud"` goes through the real
loader. It parses the case with `parse-mdl`, then compiles and evaluates
each top-level form with `compile-expression` inside the session, and prints
the value with the runtime's `mdl-unparse-value` (`#<TYPE>` when that cannot
print it) or the exception message. It continues with the next form after an
error. It gets the non-exported `call-in-session`, `mdl-unparse-value` and
`mdl-type-name` through `module->namespace`.

```sh
PLTCOLLECTS=":$PWD" racket $TMPDIR/i199/ours/run_ours.rkt $TMPDIR/i199/game-ours \
  docs/evidence/M4/<file>-cases.json <out.json>
```

Both files were run twice, and every run exited 0. The two outputs are
byte-identical (`cmp`), and the copy's file hashes are unchanged.

## Side-by-side

Notation. **ABORT(msg)**: Confusion printed `msg` on stderr and abandoned the
evaluation back to `LISTENING-AT-LEVEL 1`, with no `*ERROR*` frame.
**\*ERROR\* ... [L2]**: Confusion called MDL `ERROR` and entered
`LISTENING-AT-LEVEL 2` (stderr also gets `Atom REP has neither LVAL nor
GVAL`, which is omitted here). **ERR**: a Racket exception in our runtime.
Values of successive forms are separated by `;`. `#<FUNCTION>` vs `F` after
a `DEFINE` is the known, already documented difference in DEFINE's value
(SEMANTICS, "Known deviations": a compiled DEFINE yields the FUNCTION, the
reference yields the ATOM). It is not part of this issue.

### STRING argument

| Case | Expression | Confusion | Ours | Same? |
|---|---|---|---|---|
| setg-string-fresh | `<SETG "FOO" 3> <GASSIGNED? FOO> <GBOUND? FOO>` | ABORT(Type Mismatch, 1st arg to SETG must be atom) ; #FALSE () ; #FALSE () | 3 ; T ; ERR GBOUND? unassigned operator | **no**: ours assigns ATOM FOO |
| setg-string-preset | `<SETG FOO 1> <SETG "FOO" 3> ,FOO` | 1 ; ABORT(... SETG must be atom) ; 1 | 1 ; 3 ; 3 | **no**: ours overwrites FOO |
| setg-string-in-function | `<DEFINE F () <SETG "X" 1>> <F> <GASSIGNED? X>` | F ; ABORT(... SETG must be atom) ; #FALSE () | #<FUNCTION> ; 1 ; T | **no** |
| gval-string-fresh | `<GVAL "FOO">` | \*ERROR\* "FIRST-ARG-WRONG-TYPE" "First arg to GVAL must be atom" [L2] | ERR mdl-gval: unassigned MDL global FOO | error in both, different reason |
| gval-string-preset | `<SETG FOO 1> <GVAL "FOO">` | 1 ; \*ERROR\* FIRST-ARG-WRONG-TYPE (GVAL) [L2] | 1 ; 1 | **no** |
| gval-string-in-function | `<SETG X 1> <DEFINE F () <GVAL "X">> <F>` | 1 ; F ; \*ERROR\* FIRST-ARG-WRONG-TYPE (GVAL) [L2] | 1 ; #<FUNCTION> ; 1 | **no** |
| gassigned-string-fresh | `<GASSIGNED? "FOO">` | ABORT(Type Mismatch, 1st arg to GASSIGNED? must be atom) | #FALSE () | **no** |
| gassigned-string-preset | `<SETG FOO 1> <GASSIGNED? "FOO">` | 1 ; ABORT(... GASSIGNED? must be atom) | 1 ; T | **no** |
| gassigned-string-in-function | `<SETG X 1> <DEFINE F () <GASSIGNED? "X">> <F>` | 1 ; F ; ABORT(... GASSIGNED? must be atom) | 1 ; #<FUNCTION> ; T | **no** |
| gbound-string-fresh | `<GBOUND? "FOO">` | ABORT(Type Mismatch, 1st arg to GBOUND? must be atom) | ERR GBOUND? unassigned operator | error in both; GBOUND? absent here |
| gbound-string-preset | `<SETG FOO 1> <GBOUND? "FOO">` | 1 ; ABORT(... GBOUND? must be atom) | 1 ; ERR GBOUND? unassigned operator | as above |
| gbound-string-in-function | `<SETG X 1> <DEFINE F () <GBOUND? "X">> <F>` | 1 ; F ; ABORT(... GBOUND? must be atom) | 1 ; #<FUNCTION> ; ERR GBOUND? unassigned operator | as above |
| set-string-fresh | `<SET "FOO" 3> <ASSIGNED? FOO> <BOUND? FOO>` | ABORT(Type Mismatch, 1st arg to SET must be atom) ; #FALSE () ; #FALSE () | 3 ; T ; ERR BOUND? unassigned operator | **no**: ours assigns local FOO |
| set-string-preset | `<SET FOO 1> <SET "FOO" 3> .FOO` | 1 ; ABORT(... SET must be atom) ; 1 | 1 ; 3 ; 3 | **no** |
| set-string-in-function | `<DEFINE F () <SET "X" 1>> <F> <ASSIGNED? X>` | F ; ABORT(... SET must be atom) ; #FALSE () | #<FUNCTION> ; 1 ; T | **no** |
| set-string-in-function-bound | `<DEFINE F ("AUX" (X 0)) <SET "X" 1> .X> <F>` | F ; ABORT(... SET must be atom) | #<FUNCTION> ; 1 | **no** |
| lval-string-fresh | `<LVAL "FOO">` | \*ERROR\* "Type Mismatch, 1st arg to LVAL must be atom" [L2] | ERR mdl-lval: unassigned MDL local FOO | error in both, different reason |
| lval-string-preset | `<SET FOO 1> <LVAL "FOO">` | 1 ; \*ERROR\* (LVAL must be atom) [L2] | 1 ; 1 | **no** |
| lval-string-in-function | `<DEFINE F ("AUX" (X 1)) <LVAL "X">> <F>` | F ; \*ERROR\* (LVAL must be atom) [L2] | #<FUNCTION> ; 1 | **no** |
| value-string-fresh | `<VALUE "FOO">` | ABORT(Type Mismatch, 1st arg to VALUE must be atom) | ERR mdl-gval: unassigned MDL global FOO | error in both, different reason |
| value-string-preset (local) | `<SET FOO 1> <VALUE "FOO">` | 1 ; ABORT(... VALUE must be atom) | 1 ; 1 | **no** |
| value-string-preset-global | `<SETG FOO 1> <VALUE "FOO">` | 1 ; ABORT(... VALUE must be atom) | 1 ; 1 | **no** |
| value-string-in-function | `<DEFINE F ("AUX" (X 1)) <VALUE "X">> <F>` | F ; ABORT(... VALUE must be atom) | #<FUNCTION> ; 1 | **no** |
| gunassign-string-fresh | `<GUNASSIGN "FOO">` | \*ERROR\* "FIRST-ARG-WRONG-TYPE" ##ATOM 0 UNPRINTABLE [L2] | FOO | **no** |
| gunassign-string-preset | `<SETG FOO 1> <GUNASSIGN "FOO"> ,FOO` | 1 ; \*ERROR\* FIRST-ARG-WRONG-TYPE ... [L2] ; 1 | 1 ; FOO ; ERR mdl-gval: unassigned MDL global FOO | **no**: ours unassigns FOO |
| gunassign-string-in-function | `<SETG X 1> <DEFINE F () <GUNASSIGN "X">> <F> <GASSIGNED? X>` | 1 ; F ; \*ERROR\* FIRST-ARG-WRONG-TYPE ... [L2] ; T | 1 ; #<FUNCTION> ; X ; #FALSE () | **no** |
| manifest-string-fresh | `<MANIFEST "FOO"> <GASSIGNED? FOO> <GBOUND? FOO>` | T ; #FALSE () ; #FALSE () | T ; #FALSE () ; ERR GBOUND? unassigned operator | MANIFEST: same value (both accept) |
| manifest-string-preset | `<SETG FOO 1> <MANIFEST "FOO"> <SETG FOO 2> ,FOO` | 1 ; T ; 2 ; 2 | 1 ; T ; ERR mdl-setg: ATTEMPT-TO-CHANGE-MANIFEST-VARIABLE FOO ; 1 | **no**: ours marks ATOM FOO manifest |
| manifest-string-in-function | `<SETG X 1> <DEFINE F () <MANIFEST "X">> <F> <SETG X 2> ,X` | 1 ; F ; T ; 2 ; 2 | 1 ; #<FUNCTION> ; T ; ERR ...MANIFEST-VARIABLE X ; 1 | **no** |
| assigned-string-fresh | `<ASSIGNED? "FOO">` | ABORT(Type Mismatch, 1st arg to ASSIGNED? must be atom) | ERR mdl-assigned?: First arg to ASSIGNED? must be ATOM | both error (text and mechanism differ) |
| assigned-string-preset | `<SET FOO 1> <ASSIGNED? "FOO">` | 1 ; ABORT(... ASSIGNED? must be atom) | 1 ; ERR (ASSIGNED? must be ATOM) | both error |
| assigned-string-in-function | `<DEFINE F ("AUX" (X 1)) <ASSIGNED? "X">> <F>` | F ; ABORT(... ASSIGNED? must be atom) | #<FUNCTION> ; ERR (ASSIGNED? must be ATOM) | both error |
| bound-string-fresh | `<BOUND? "FOO">` | ABORT(Type Mismatch, 1st arg to BOUND? must be atom) | ERR BOUND? unassigned operator | error in both; BOUND? absent here |
| bound-string-preset | `<SET FOO 1> <BOUND? "FOO">` | 1 ; ABORT(... BOUND? must be atom) | 1 ; ERR BOUND? unassigned operator | as above |
| bound-string-in-function | `<DEFINE F ("AUX" (X 1)) <BOUND? "X">> <F>` | F ; ABORT(... BOUND? must be atom) | #<FUNCTION> ; ERR BOUND? unassigned operator | as above |
| unassign-string-fresh | `<UNASSIGN "FOO">` | \*ERROR\* "UNBOUND-VARIABLE" "In apply of form" UNASSIGN [L2] | ERR mdl-eval: ... operator UNASSIGN | absent in both |
| unassign-string-preset | `<SET FOO 1> <UNASSIGN "FOO"> .FOO` | 1 ; \*ERROR\* UNBOUND-VARIABLE ... UNASSIGN [L2] ; 1 | 1 ; ERR operator UNASSIGN ; 1 | absent in both |
| unassign-string-in-function | `<DEFINE F ("AUX" (X 1)) <UNASSIGN "X">> <F>` | F ; \*ERROR\* UNBOUND-VARIABLE ... UNASSIGN [L2] | #<FUNCTION> ; ERR operator UNASSIGN | absent in both |

### FIX and quoted FORM arguments

The FIX case (`<P 5 ...>`) and the FORM case (`<P '<FOO> ...>`) gave the
same result as each other for every primitive.

| Primitive | Confusion (FIX and FORM) | Ours (FIX and FORM) | Same? |
|---|---|---|---|
| SETG | ABORT(Type Mismatch, 1st arg to SETG must be atom) | ERR mdl-setg: expected an MDL ATOM | both error |
| GVAL | \*ERROR\* "FIRST-ARG-WRONG-TYPE" "First arg to GVAL must be atom" [L2] | ERR mdl-gval: expected an MDL ATOM | both error |
| GASSIGNED? | ABORT(... GASSIGNED? must be atom) | ERR mdl-gassigned?: expected an MDL ATOM | both error |
| GBOUND? | ABORT(... GBOUND? must be atom) | ERR GBOUND? unassigned operator | both error; absent here |
| SET | ABORT(... SET must be atom) | ERR mdl-set: expected an MDL ATOM | both error |
| LVAL | \*ERROR\* "Type Mismatch, 1st arg to LVAL must be atom" [L2] | ERR mdl-lval: expected an MDL ATOM | both error |
| VALUE | ABORT(... VALUE must be atom) | ERR mdl-value: expected an MDL ATOM | both error |
| GUNASSIGN | \*ERROR\* "FIRST-ARG-WRONG-TYPE" ##ATOM 0 UNPRINTABLE [L2] | ERR mdl-gunassign: expected an MDL ATOM | both error |
| MANIFEST | `T`, clean (no error) | ERR mdl-manifest: expected an MDL ATOM | **no**: Confusion accepts anything |
| ASSIGNED? | ABORT(... ASSIGNED? must be atom) | ERR mdl-assigned?: First arg to ASSIGNED? must be ATOM | both error |
| BOUND? | ABORT(... BOUND? must be atom) | ERR BOUND? unassigned operator | both error; absent here |
| UNASSIGN | \*ERROR\* UNBOUND-VARIABLE "In apply of form" UNASSIGN [L2] | ERR operator UNASSIGN | absent in both |

### Original MSETG / PSETG (`<FLOAD "81prim.mud">` first; FLOAD prints `"DONE"` in both)

| Case | Expression after FLOAD | Confusion | Ours | Same? |
|---|---|---|---|---|
| msetg-string-x-original | `<MSETG "x" 3>` | ABORT(Type Mismatch, 1st arg to GASSIGNED? must be atom) | T | **no** (the case from #199 / M2 decl-error) |
| msetg-string-fresh | `<MSETG "FOO" 3> <GASSIGNED? FOO>` | ABORT(... GASSIGNED? must be atom) ; #FALSE () | T ; T | **no** |
| msetg-string-preset | `<SETG FOO 1> <MSETG "FOO" 3> ,FOO` | 1 ; ABORT(... GASSIGNED? must be atom) ; 1 | 1 ; ERR mdl-error: MSETG "FOO" ALREADY-GASSIGNED 1 ; 1 | **no** (ours reaches MSETG's own ERROR branch) |
| msetg-fix / msetg-form | `<MSETG 5 3>` / `<MSETG '<FOO> 3>` | ABORT(... GASSIGNED? must be atom) | ERR mdl-gassigned?: expected an MDL ATOM | both error at GASSIGNED? |
| msetg-string-in-function | `<DEFINE G () <MSETG "X" 3>> <G> <GASSIGNED? X>` | G ; ABORT(... GASSIGNED? must be atom) ; #FALSE () | #<FUNCTION> ; T ; T | **no** |
| psetg-string-x-original | `<PSETG "x" 3>` | ABORT(Type Mismatch, 1st arg to SETG must be atom) | 3 | **no** |
| psetg-string-fresh | `<PSETG "FOO" 3> <GASSIGNED? FOO> <GASSIGNED? PURE-LIST>` | ABORT(... SETG must be atom) ; #FALSE () ; #FALSE () | 3 ; T ; T | **no** |
| psetg-string-preset | `<SETG FOO 1> <PSETG "FOO" 3> ,FOO` | 1 ; ABORT(... SETG must be atom) ; 1 | 1 ; 3 ; 3 | **no** |
| psetg-fix / psetg-form | `<PSETG 5 3>` / `<PSETG '<FOO> 3>` | ABORT(... SETG must be atom) | ERR mdl-setg: expected an MDL ATOM | both error at SETG |
| psetg-string-in-function | `<DEFINE G () <PSETG "X" 3>> <G> <GASSIGNED? X>` | G ; ABORT(... SETG must be atom) ; #FALSE () | #<FUNCTION> ; 3 ; T | **no** |

### ATOM controls (clean in Confusion)

| Case | Confusion | Ours |
|---|---|---|
| control-setg-gval-gassigned-atom `<SETG FOO 3> ,FOO <GVAL FOO> <GASSIGNED? FOO> <GBOUND? FOO>` | 3 ; 3 ; 3 ; T ; T | 3 ; 3 ; 3 ; T ; ERR GBOUND? unassigned operator |
| control-set-lval-value-atom `<SET FOO 3> .FOO <LVAL FOO> <VALUE FOO> <ASSIGNED? FOO> <BOUND? FOO>` | 3 ; 3 ; 3 ; 3 ; T ; T | 3 ; 3 ; 3 ; 3 ; T ; ERR BOUND? unassigned operator |
| control-gunassign-atom `<SETG FOO 3> <GUNASSIGN FOO> <GASSIGNED? FOO>` | 3 ; FOO ; #FALSE () | same |
| control-manifest-atom `<SETG FOO 1> <MANIFEST FOO> <SETG FOO 2> ,FOO` | 1 ; T ; 2 ; 2 | 1 ; T ; ERR ATTEMPT-TO-CHANGE-MANIFEST-VARIABLE FOO ; 1 |
| control-msetg-atom `<FLOAD "81prim.mud"> <MSETG FOO 3> ,FOO` | "DONE" ; T ; 3 | same |
| control-psetg-atom `<FLOAD "81prim.mud"> <PSETG FOO 3> ,FOO ,PURE-LIST` | "DONE" ; 3 ; 3 ; (FOO) | same |

## Observed semantics (Confusion)

1. **No primitive accepts a STRING as an ATOM, except MANIFEST.** SETG,
   GVAL, GASSIGNED?, GBOUND?, SET, LVAL, VALUE, GUNASSIGN, ASSIGNED? and
   BOUND? reject STRING, FIX and FORM first arguments. This holds whether or
   not FOO already has a value, and at top level or inside a FUNCTION. After
   a rejected `SETG`/`SET`/`GUNASSIGN`/`MSETG`/`PSETG` on `"FOO"`, the ATOM
   `FOO` is unchanged: still unassigned when it started fresh, still `1` when
   preset.
2. **MANIFEST accepts anything** (`T` for `"FOO"`, `5` and `'<FOO>`) and has
   no effect: a later `SETG` to a different value succeeds, even for an ATOM
   argument. The source labels it "No compiler, so no MANIFEST".
3. **UNASSIGN** has no global value in this build. Every call is
   `*ERROR* UNBOUND-VARIABLE "In apply of form" UNASSIGN`, raised before any
   argument check (matches the M1 bindings-error evidence).
4. **The original MSETG** fails at its first `GASSIGNED? .FOO` for all three
   non-ATOM types. **PSETG** fails at its first `SETG .FOO .BAR`, before
   `PURE-LIST` is created.
5. **Two error mechanisms (the check is not uniform).**
   - SETG, SET, VALUE, GASSIGNED?, GBOUND?, ASSIGNED? and BOUND? use the
     internal `mdl_error` path. It prints `Type Mismatch, 1st arg to <P> must
     be atom` on stderr, abandons the whole evaluation and returns to
     `LISTENING-AT-LEVEL 1`. No `*ERROR*` frame appears on stdout.
   - GVAL, LVAL and GUNASSIGN call MDL `ERROR` instead. That prints a
     `*ERROR*` block on stdout and enters `LISTENING-AT-LEVEL 2`. Their
     arguments differ:
     - GVAL: `"FIRST-ARG-WRONG-TYPE" "First arg to GVAL must be atom"`.
     - LVAL: one string, `"Type Mismatch, 1st arg to LVAL must be atom"`.
     - GUNASSIGN: `"FIRST-ARG-WRONG-TYPE" ##ATOM 0 UNPRINTABLE` (see the
       source summary).

These probes did not test whether an MDL-level handler (ERRET, an ERROR
interrupt) can intercept the `mdl_error` path.

## Confusion source summary (GPLv3; summarised, not copied)

`confusion_patched/macros.cpp`, around lines 3796-4009. All of SETG, SET,
GVAL, LVAL, VALUE, BOUND?, ASSIGNED?, GBOUND?, GASSIGNED? and GUNASSIGN test
whether the first argument's primitive type is ATOM. None of them converts a
STRING. They differ only in how they fail:

- The SETG, SET, VALUE, BOUND?, ASSIGNED?, GBOUND? and GASSIGNED? SUBRs call
  `mdl_error` with a "Type Mismatch, 1st arg to ... must be atom" text.
  `mdl_error` (macros.cpp around 1545) writes the text to stderr, resets to
  the initial frame and longjmps there. This is the observed ABORT back to
  level 1.
- LVAL returns `mdl_call_error` with the "Type Mismatch" text as the only
  ERROR argument.
- GVAL calls `mdl_call_error_ext("FIRST-ARG-WRONG-TYPE", ...)`, but does
  **not** return its result. If that ERROR ever returned (for example via
  ERRET), the SUBR would go on to a global lookup with a non-ATOM. Not
  probed.
- GUNASSIGN passes `"FIRST-ARG-WRONG-TYPE"` as the message string and its
  descriptive text as an *extra argument*. That argument travels through the
  variadic list as if it were an MDL value. This explains the
  `##ATOM 0 UNPRINTABLE` second ERROR argument. It was identical in both
  capture rounds, but it is an artefact of the call and should not be
  treated as semantics.
- MANIFEST (around line 8026, under a "No compiler, so no MANIFEST" comment)
  ignores its arguments and returns T. GDECL next to it also just returns T.
- The generated builtin table (`.cache/build/confusion_patched/mdl_builtins.cpp`)
  registers LVAL, GVAL, VALUE, BOUND?, ASSIGNED?, GBOUND?, GASSIGNED?,
  GUNASSIGN, SETG, SET and MANIFEST. It has no UNASSIGN.

So the ATOM check is uniform in what it accepts (only PRIMTYPE ATOM, in all
ten SUBRs that check). MANIFEST is the one primitive with no check. The
error reporting is not uniform (three variants, described above).

## Mismatches with this runtime (observations, not a fix)

1. **STRING accepted here, rejected by Confusion:** SETG, GVAL, GASSIGNED?,
   SET, LVAL, VALUE and GUNASSIGN, at top level and inside a FUNCTION. Here
   the STRING resolves to the ATOM `FOO`/`X`, so the call has the full side
   effect on that ATOM:
   - `<SETG "FOO" 3>` assigns `,FOO`.
   - `<SET "X" 1>` in a FUNCTION assigns the free/top-level `X`
     (`<ASSIGNED? X>` = T afterwards), or the AUX-bound `X` when there is
     one.
   - `<GUNASSIGN "FOO">` unassigns `FOO`.

   When FOO is fresh, GVAL/LVAL/VALUE of `"FOO"` do fail here, but with
   "unassigned MDL global/local FOO", a different reason from Confusion's
   type error.
2. **Consequences in the original 81prim.mud code:**
   - `<MSETG "x" 3>` returns `T` here. Confusion stops at GASSIGNED?.
   - `<MSETG "FOO" 3>` with FOO preset reaches MSETG's own
     `ERROR MSETG "FOO" ALREADY-GASSIGNED 1` branch here.
   - `<PSETG "FOO" 3>` assigns `FOO` and creates `PURE-LIST` here; Confusion
     stops at SETG. (The contents of `PURE-LIST` here were not printed.)
3. **MANIFEST is the reverse case.** Confusion accepts every argument type
   and does nothing. Here it accepts a STRING (marking the ATOM manifest) but
   rejects FIX and FORM. It also enforces the manifest restriction on a
   later SETG, for an ATOM argument too (control-manifest-atom). The
   restriction itself is the documented M2 D1 choice (SEMANTICS, "The
   original `MSETG` ..."). The FIX/FORM rejection and the STRING acceptance
   are not recorded there.
4. **FIX and FORM:** both implementations reject them for every primitive
   that exists in both, except MANIFEST. The error texts differ
   (`mdl-<p>: expected an MDL ATOM` vs the texts above). So do the
   mechanisms: Confusion either aborts to level 1 or opens an `*ERROR*`
   level, while here a Racket exception is raised.
5. **ASSIGNED?** agrees: both reject STRING, FIX and FORM. Here it checks
   `mdl-atom?` directly and does not go through `binding-atom`.
6. **Not present here:** `BOUND?` and `GBOUND?` (Confusion has both; here
   they fail as an unassigned operator even with an ATOM argument). This is
   outside #199 but visible in the controls. **UNASSIGN** is absent in both.
7. Unrelated, already documented: a compiled `DEFINE` yields the FUNCTION
   here and the ATOM in Confusion.

## Limitations

- Each primitive was probed with one representative of each non-ATOM type
  (`"FOO"`/`"X"`/`"x"`, `5`, `'<FOO>`). Other types (LIST, VECTOR, an ADECL
  or LVAL-typed value) were not probed.
- No probe used the optional ENVIRONMENT/frame arguments of SET, LVAL,
  VALUE, ASSIGNED? or BOUND?.
- Our-runtime results come from a read-only harness that evaluates each form
  through `compile-expression` inside a session. That is the same compile
  and eval path the loader uses for each expression, but it is not the
  loader's own per-file loop, and it continues after errors, which the
  loader does not.

## Fix (branch `fix/199-binding-atom-string`, 2026-11-26)

Commits: `f2ffee6` (tests first), `5af5d14` (runtime, host boundary, test
adaptations), then the documentation commit. Upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3` and mit_zork
`d94501340842e006791fce0757dc0043b8ec8916` (`sources.lock.json`); the
mdlzork checkout's `git status --short` is empty. Racket v7.9 [bc], Python
3.9.2. `make reference-build` was not run; no new Confusion capture was
needed (the observations above are the reference).

**What changed.** `binding-atom` accepts ATOMs only, so SETG, GVAL,
GASSIGNED?, SET, LVAL, VALUE, GUNASSIGN and MANIFEST raise `mdl-<p>: expected
an MDL ATOM` for a STRING, as they did for FIX and FORM; MANIFEST checks all
arguments before marking any. The host API (`mdl/loader.rkt`) converts its
string names with the new non-interning `mdl-find-atom`. Rules: SEMANTICS
"M4 #199"; decision: DECISIONS "Binding primitives take ATOMs only".

After the fix, every STRING row of the side-by-side tables above that was
marked **no** for SETG, GVAL, GASSIGNED?, SET, LVAL, VALUE, GUNASSIGN and
the original MSETG/PSETG now errors here, with the ATOM unchanged, as in
Confusion (error text and mechanism still differ: the existing
error-reporting difference). MANIFEST now errors for a STRING here, while
Confusion returns T (the existing MANIFEST deviation). Not changed: BOUND?,
GBOUND?, UNASSIGN; the compiled DEFINE value.

**MANIFEST source check.** `grep -rni manifest .cache/upstream --include=*.mud`
finds, for the 1977 game (`mdlzork_771212/patched_confusion`), only
`81prim.mud:8 <MANIFEST .FOO>` inside MSETG, reached after `<GASSIGNED?
.FOO>` (which requires an ATOM). Every MSETG/PSETG call site in the 771212
`.mud` files passes a literal ATOM, except `81prim.mud:28` (`.F`, guarded by
`<TYPE? .F ATOM>`), `:69` (`.OFFS`, guarded by `<TYPE? .OFFS ATOM>`) and
`:71` (elements of an OFFS LIST; the `"REST"` STRING is handled before).
Later versions (780124, 791211, 810722) add only ATOM arguments
(`<MANIFEST PUSHJ ADDI BASE-INST>`, `<MANIFEST LEXSIZE>`). `mit_zork` has no
MANIFEST. No pinned source passes a non-ATOM to MANIFEST.

**Failing before.** The MDL-level part of `tests/binding_atom_string_test.rkt`
(everything before its "runtime value API" section, copied unchanged to a
scratch file because the rest needs functions this fix adds) run against
`a9626da`: exit 0 (rackunit prints failures without failing the process),
**53 failing checks**: the 16 STRING cases (8 primitives, top level and in a
FUNCTION), the 16 "no ATOM interned" cases, 19 unchanged-ATOM and in-FUNCTION
cases, and the two MANIFEST check-all-first cases (`<MANIFEST FOO "BAR">`,
`<MANIFEST FOO 5>`). Every FIX and FORM case already passed. The host-API
part could not compile there (`mdl-find-atom`, `mdl-session-find-atom`
unbound). Note: at `f2ffee6` the module's value-API check also named four
non-exported runtime functions; `5af5d14` restricts it to the exported ones.

**Passing after** (`5af5d14`, documentation uncommitted at the time of the
gate runs; commands outside the sandbox with
`PLTCOLLECTS=":$PWD" TMPDIR=/tmp PYTHONPATH=$PWD/.sandbox-pydeps/lib make PYTHON=/usr/bin/python3 <target>`):

| Command | Exit | Result |
|---|---:|---|
| `racket tests/binding_atom_string_test.rkt` | 0 | 0 failures |
| `racket tests/declaration_test.rkt`, `tests/muddle_test.rkt` | 0 | 0 failures |
| `make test` (first run, before two test fixes below) | 2 | 4/5307 raco failures: `channel_port_test.rkt` (a host string applied directly to the GASSIGNED? SUBR) and `oblist_identity_test.rkt` (3: host `mdl-with-bindings` with a string name); both fixed by passing `(mdl-atom NAME)` |
| `make test` | 0 | raco 5307 tests passed; pytest 104 passed, 1 deselected |
| `make test-historical` | 0 | all historical probes passed (MSETG computed-global, MSETG ERROR, PSETG MEMQ, OBLIST placement 2350 entries, ...) |
| `make test-m2-g3` | 0 | G3 integrated gate passed: 58 assertions |
| `make test-m3-session` | 0 | 85 tests passed |
| `make test-m3-launcher` | 0 | 57 tests passed |
| `make m3-check` | 0 | candidate-vs-committed-reference PASS; native-fresh-capture-parity PASS; overall PASS |
| `make m4-check` | 0 | 28 checks PASS (sources, 26 scenarios, persistence); SCENARIO_PARITY PASS (26), GAMEPLAY_RELIABILITY NOT YET 20 of 23 (the three save branches; open INV-06, INV-07), PLAYABLE NOT RUN, FULL_COMPLETION NOT RUN, M4_ACCEPTED NOT YET (unchanged from `6d6e5b1`) |
| `git diff --check origin/main HEAD` | 0 | no whitespace errors |

The first passing `make test` ran before the `on_save_test.rkt` fix and the
`zork/persistence.rkt` helper move (both in `5af5d14`); `make test` re-run at
`5af5d14`: exit 0, raco 5307 passed, pytest 104 passed, 1 deselected.

**Changed test assertions and inputs.**

- `tests/declaration_test.rkt`: the tracked XFAIL `(MSETG "M2-D1-STRING" 3)
  → T` is now `raises ^mdl-gassigned\?: expected an MDL ATOM$`; added PSETG
  (verbatim 81prim.mud:10-18) with a STRING and a FIX (`raises
  ^mdl-setg: expected an MDL ATOM$`), checks that neither STRING's ATOM was
  interned and that no PURE-LIST was created, and a PSETG control with an
  ATOM (→ 4).
- `tests/muddle_test.rkt`: three host calls passed the string `"MUDDLE"` as
  the MDL argument of GVAL/GASSIGNED?; they now pass
  `(mdl-session-atom session "MUDDLE")`. Assertions unchanged.
- `tests/on_save_test.rkt:105`: `(apply mdl-apply "ON" bad)` inside
  `check-exn exn:fail?` would have passed for the wrong reason (the name
  check); it now passes `(mdl-atom "ON")`.
- `tests/channel_port_test.rkt:340`, `tests/oblist_identity_test.rkt`
  (3 `mdl-with-bindings` calls): string names → `(mdl-atom NAME)`.
- 18 test files and `scripts/bench/gc_growth_bench.rkt`: every direct host
  call `(mdl-gval "X")`, `(mdl-setg! "X" v)`, `(mdl-lval "X")`,
  `(mdl-set! "X" v)`, `(mdl-apply "X" ...)` and so on became
  `(... (mdl-atom "X") ...)` (mechanical; `mdl-atom` is what `binding-atom`
  called before, so the ATOM is the same). No expected value changed.
- `tests/historical_parser_ambiguity_test.rkt`: its PARSE-WON checkpoint read
  uses the runner's non-interning `existing-atom`.

**Security and licensing.** No new MDL-reachable capability: `mdl-find-atom`
and `mdl-session-find-atom` are host-only (not in the builtin table) and only
read. No GPLv3 code copied (the Confusion behaviour is summarised above). No
upstream bytes changed.

## Independent review (2026-11-26)

An independent reviewer (a separate subagent given the diff, not this
summary) read the fix and its invariants and ran seven mutations against
`make test`. Six were caught. It reported no blocking defect. The seventh
mutation showed an untested property, and three smaller points followed.
All were addressed on this branch:

- **Untested property (should fix).** Non-interning lookup of
  `NAME!-OWNER`, where the OWNER ATOM exists but has no OBLIST, must not
  create that OBLIST. The mutation `(mdl-moblist owner)` in the
  non-interning branch of `resolve-pname` went undetected.
  `tests/binding_atom_string_test.rkt` now reads `M199-X!-M199-G` (`M199-G`
  exists and has no OBLIST). It checks that the read fails as an unassigned
  global, that `mdl-session-find-atom` returns false, and that
  `<GET M199-G OBLIST>` is still FALSE afterwards. The positive control is
  `<GET M199-OBL OBLIST>`, which is not FALSE. Re-run of the mutation: the
  test fails at line 211, which is the FALSE check after the read. Without
  the mutation the test passes.
- **Temp directory.** The tests made their temporary directories under a
  hard-coded `/tmp`. They now use the system temp directory
  (`make-temporary-file "mdl-i199-test~a"`, and likewise in
  `declaration_test.rkt`).
- **Error message wording.** The message now says "no such ATOM on the
  session's .OBLIST path". The `unassigned MDL global` prefix is unchanged.
- **Checkpoint purity by construction.** Six remaining checkpoint ATOM
  reads used the interning `mdl-session-atom`: house-cellar,
  top-parser, parser-ambiguity (two), orphan-prompt (two) and sword-glow.
  They now use the runner's non-interning `existing-atom`, which fails if
  the ATOM is missing.
- **Left as is (pre-existing, outside #199).** `mdl/compiler.rkt:70-73`
  interns ATOMs at compile time, as the reader does.
- **Process note.** `docs/SEMANTICS.md` was updated in the docs commit
  (dcc19be), after the fix commit (5af5d14). AGENTS.md asks for the
  SEMANTICS entry before the implementation. The probe evidence (a9626da)
  and the failing tests (f2ffee6) did come first, but the SEMANTICS text
  did not.

**Gate on `dcc19be`, run before the review fixes.** Each target ran
sequentially, outside the sandbox, and exited 0: test, test-historical,
test-m2-g3, m3-source-progress, test-m3-interactive, test-m3-session,
test-m3-launcher, test-m3-bang, m3-check, m4-check, m4-decl-sweep and
m4-scenarios-per-prefix (6150 s). `git diff --check` was clean. In the
sweep JSON only `repository_commit` and the timings changed, so it was not
committed.

**Re-run after the review fixes.** `make test` exited 0: raco reported
5312 tests passed, and pytest 104 passed with 1 deselected. `make m4-check`
exited 0. It runs the five changed checkpoint tests (house-cellar,
orphan-prompt, top-parser, sword-glow, parser-ambiguity), and each one
passed. Its summary was SCENARIO_PARITY PASS (26) and GAMEPLAY_RELIABILITY
NOT YET (20 of 23; open INV-06 and INV-07), unchanged from the gate run.
