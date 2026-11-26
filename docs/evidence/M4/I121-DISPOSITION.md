# Issue #121: disposition after #199 / PR #202 (2026-11-26)

#121 (found in the review of PR #114, part of #113) reported that
`binding-atom` accepted a native string, so that `<SET "FOO" 3>`,
`<SETG "BAR" 4>`, GVAL, LVAL, VALUE, MANIFEST, GUNASSIGN, GASSIGNED? and
APPLY "with a string argument" succeeded, and that a REST view of the same
string was rejected. It asked to separate the host API (which may name a
ROOT atom by a Racket string) from the MDL-callable SUBRs (strict).

## Superseded by #199 (PR #202, main `5b27177`)

#199 made `binding-atom` ATOM-only and moved host string-name conversion to
the host boundary (`mdl/loader.rkt`, non-interning `mdl-find-atom`). Every
primitive #121 names is covered by `tests/binding_atom_string_test.rkt` and
the native evidence in [I199](I199-STRING-ATOM.md) (80 cases).

## Remaining scope tested here: APPLY and REST views

Pinned Confusion (`.cache/build/confusion_patched/mdli`, SHA-256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789`; mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`, checkout clean), run twice from a
disposable copy of `mdlzork_771212/patched_confusion` under `$TMPDIR` with the
unchanged `scripts/mdl_probe.py` (the same 3-line `GAME` wrapper as I199). The
copy's file hashes were identical before and after. The two runs' `cases`
arrays are equal. Probe exit 1 is expected (cases that raise errors).

Cases: [`i121-apply-string-cases.json`](i121-apply-string-cases.json);
reference: [`i121-apply-string-reference.json`](i121-apply-string-reference.json).

| Case | Confusion | This runtime (main `5b27177`) |
|---|---|---|
| `<APPLY "F" 1>` (F defined) | `*ERROR* NON-APPLICABLE-TYPE "F"` | error `NON-APPLICABLE-TYPE` |
| `<APPLY "+" 1 2>` | `*ERROR* NON-APPLICABLE-TYPE "+"` | error `NON-APPLICABLE-TYPE` |
| `<"F" 1>` (a STRING FORM head) | `*ERROR* NON-APPLICABLE-TYPE "F"` | error `NON-APPLICABLE-TYPE` |
| `<APPLY ,F 1>` (control) | `2` | `2` |
| `<APPLY ,+ 1 2>` (control) | `3` | `3` |
| `<SETG <REST "XFOO" 1> 3>` | `Type Mismatch, 1st arg to SETG must be atom`; `,FOO` still 7 | `mdl-setg: expected an MDL ATOM`; `,FOO` still 7 |
| `<GVAL <REST "XFOO" 1>>` | `*ERROR* FIRST-ARG-WRONG-TYPE` | `mdl-gval: expected an MDL ATOM` |

Error text and mechanism differ (the existing error-reporting difference,
ADR-0064 class B); the accepted and rejected cases agree.

**Before #202.** The same MDL-level cases run against `6a9f0fe` (the commit
before #202, a temporary detached worktree, removed afterwards) give the
same rejections: APPLY of a STRING was already NON-APPLICABLE-TYPE at the MDL
level, and REST views were already rejected by SETG and GVAL. The "APPLY with
a string" of #121 was the host-level `mdl-apply`, which accepted a Racket
string name; #202 removed that (host callers now pass ATOMs or go through
`mdl-session-call`, which resolves names without interning). The new checks
in `tests/binding_atom_string_test.rkt` ("#121") therefore guard behaviour
that is correct before and after; they are not a red-to-green fix.

## Disposition

Fully superseded by #199/#202. #121 is closed with this record. Not in either
issue's scope: BOUND?, GBOUND?, UNASSIGN (no implementation here; UNASSIGN is
absent in both runtimes).
