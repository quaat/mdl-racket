# M2 reference investigation — the `MUDDLE` global, the `77defs.mud` chain head, `USE`, `RAPPLIC`, and `MEMQ` (issue #51, D4)

Read-only reference probe against the pinned patched Confusion build. No
implementation, test, script, Makefile, or `.cache/upstream/` file was
touched; only the five files listed at the end were created. Interpreter:
`.cache/build/confusion_patched/mdli`, SHA-256
`a29c756df5c973e462a6ad2b318e28ec265934e89e72d825bc7672387317e629`
(unchanged from the segment-slice evidence note).

## Expected semantics (from the task and the MDL manual's stated rules)

`MUDDLE` is an interpreter-supplied global reporting the MUDDLE/MDL
version as a FIX; the December-1977 Zork sources switch on it
(`77defs.mud:1` `<AND <L? ,MUDDLE 100> <USE "LSRTNS">>` guards a
MUDDLE-10-only library load; `77patch.mud:38` and `77rooms.mud` branch on
`<G? ,MUDDLE 100>`). `<L? A B>` returns T if A < B, otherwise `#FALSE ()`.
`AND` evaluates left to right, stops at and returns the first FALSE value,
so a false first test must leave the remaining expressions unevaluated.
`<USE "LIBRARY">` is the MUDDLE-10-era library-load operator; a
non-MUDDLE-10 interpreter may simply not bind the atom `USE`, and because
the 1977 guards are numeric comparisons the Zork sources never need it on
MUDDLE 100+. `RAPPLIC` is a plain atom used in `77defs.mud` as a TYPE-name
slot spec (`NEWSTRUC` slots `RACTION`, `CXACTION`, `VFCN`, `AACTION`,
`OACTION`, `HACTION` all typed `RAPPLIC`); `<PUT RAPPLIC DECL '...>`
(77defs expression 3, line 5) attaches the type declaration to the atom
without ever assigning it, `<GASSIGNED? RAPPLIC>` is the safe predicate,
and a bare `,RAPPLIC` read must raise `UNBOUND-VARIABLE` until something
assigns it. `MEMQ` searches the top-level elements of a LIST for the first
element matching the item (`==?`-class identity comparison) and, per the
historical manual, returns the sublist beginning with that element (a
LIST, also usable as a truth value), `#FALSE ()` on miss. Note: the manual
page itself was not fetched in this session (fetch not permitted); rules
above are the ones the task supplied plus `docs/SEMANTICS.md` M1 #3
(`AND`), and every claim below is anchored to recorded output.

## Commands and exit codes

All from the repository root:

```
PYTHONPATH="$PWD/.sandbox-pydeps/lib" /usr/bin/python3 -m scripts.mdl_probe \
  --cases docs/evidence/M2/muddle-cases.json \
  --output docs/evidence/M2/muddle-reference.json --timeout 300
# exit 0 — "Probed 12 expressions; review: docs/evidence/M2/muddle-reference.json"
PYTHONPATH="$PWD/.sandbox-pydeps/lib" /usr/bin/python3 -m scripts.mdl_probe \
  --cases docs/evidence/M2/muddle-error-cases.json \
  --output docs/evidence/M2/muddle-error-reference.json --timeout 300
# exit 1 — EXPECTED BY DESIGN (deliberately failing observations recorded)
```

Each case runs in a fresh Confusion process (stdin expression + `<QUIT>`,
cwd `.cache/upstream/mdlzork/mdlzork_771212/patched_confusion`). All
outputs below are quoted from the recorded JSON files.

## Success cases (12/12 clean exits) — `muddle-cases.json`, `muddle-reference.json`

| Case | Expression | Recorded `result_output` |
|---|---|---|
| `muddle-gval` | `,MUDDLE` | `101` |
| `muddle-type` | `<TYPE ,MUDDLE>` | `FIX` |
| `muddle-ltest` | `<L? ,MUDDLE 100>` | `#FALSE ()` |
| `defs-line1-and-short-circuits` | `<AND <L? ,MUDDLE 100> <USE "LSRTNS">>` | `#FALSE ()`, empty stderr |
| `rapplic-gassigned-false-fresh` | `<GASSIGNED? RAPPLIC>` | `#FALSE ()` |
| `defs-line3-put-decl-unassigned-atom` | `<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>` | `RAPPLIC` (the atom echoed as the PUT's result), empty stderr |
| `memq-first-hit` | `<MEMQ 'A '(A B)>` | `(A B)` |
| `memq-second-hit` | `<MEMQ 'B '(A B)>` | `(B)` |
| `memq-miss` | `<MEMQ 1 '(A B)>` | `#FALSE ()` |
| `memq-result-type` | `<TYPE <MEMQ 'A '(A B)>>` | `LIST` |
| `fload-chain-completion` | `<FLOAD "77loadall.mud">` | see below |
| `fload-chain-rapplic-gassigned-after` | `<FLOAD "77loadall.mud"> <GASSIGNED? RAPPLIC>` | chain output, then `"DONE"`, then `#FALSE ()` |

What each shows:

- **The `MUDDLE` global is FIX 101 in a fresh process.** `,MUDDLE` → `101`
  and `<TYPE ,MUDDLE>` → `FIX`. Nothing in the loaded sources sets it — a
  grep of all `.mud` files shows only *uses* (`77defs.mud:1`,
  `77patch.mud:38`, `77rooms.mud:6` GDECL and branches from line 8 on) — so
  the value comes from the interpreter itself.
- **`<L? ,MUDDLE 100>` is `#FALSE ()`**, so the first conjunct of
  `77defs.mud:1` is false on the pinned reference.
- **The exact `77defs.mud:1` expression short-circuits.**
  `<AND <L? ,MUDDLE 100> <USE "LSRTNS">>` in a fresh process returned
  `#FALSE ()` with empty stderr and clean exit — `USE` was never evaluated
  (compare the error case below, where the same `USE` call alone breaks).
- **`PUT ... DECL` does not need an assignment.** 77defs expression 3,
  `<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>`, succeeds on the
  never-SETG'd atom in a fresh process and echoes `RAPPLIC` as its result;
  empty stderr.
- **The whole `77loadall.mud` chain loads to completion.** The recorded
  `result_output` of `fload-chain-completion` is exactly:
  `81prim.mud loaded`, `77defs.mud loaded`, `77makstr.mud loaded`,
  `81tell-repl.mud loaded`, `77act1.mud loaded`, `77act2.mud loaded`,
  `77act3.mud loaded`, `77rooms.mud loaded`, `77patch.mud loaded`,
  `77np.mud loaded`, `78melee.mud loaded`, `77dung.mud loaded`, then
  `"DONE"` — no error, clean exit, empty stderr. The reference therefore
  loads the full 12-file chain head-to-head with zero failures and returns
  the STRING `"DONE"` (FLOAD's return value;
  `macros.cpp:7278` in the pinned build returns `mdl_new_string(4, "DONE")`
  at the end of `mdl_builtin_eval_fload`). No game loop starts during load
  — the `<QUIT>` after the FLOAD terminates the session normally.
- **`RAPPLIC` is never assigned, even after the full chain.** After
  `<FLOAD "77loadall.mud">` in the same process, `<GASSIGNED? RAPPLIC>` is
  still `#FALSE ()` (see the error file for the matching `,RAPPLIC`
  read breaking UNBOUND after the chain). Nothing in the 12 files SETGs
  RAPPLIC; every source use is as a type spec or a `#DECL` type
  (`77rooms.mud:1255`). Its "value" in the reference is nothing: the atom
  carries only its DECL association.
- **MEMQ returns a tail sublist, not the element and not T.**
  `<MEMQ 'A '(A B)>` → `(A B)`; `<MEMQ 'B '(A B)>` → `(B)`;
  `<MEMQ 1 '(A B)>` → `#FALSE ()` (FIX 1 does not match atoms A, B, so
  the comparison is identity-typed); `<TYPE <MEMQ 'A '(A B)>>` → `LIST`.
  The installed original call shape `<MEMQ .FOO .PL>` therefore yields the
  portion of the list beginning at the first matching element, which every
  Zork site treats as a truth value (e.g. `77defs.mud` COND-OPEN, KILL-OBJ,
  ARMED?).

## Deliberate-error cases — `muddle-error-cases.json`, `muddle-error-reference.json` (probe exit 1, expected)

All cases exit code 0 at process level but break into MDL error levels or
write diagnostics to stderr, so the probe flags them not-ok and exits 1 —
that is the deliberate-error design. As recorded in SEGMENTS.md, every
break-level case also writes the pre-existing handler artifact
`Atom REP has neither LVAL nor GVAL` to stderr, which is not part of the
diagnostic.

| Case | Expression | Recorded diagnostic |
|---|---|---|
| `use-unbound` | `<USE "LSRTNS">` | `*ERROR* "UNBOUND-VARIABLE" "In apply of form" USE`, break `LISTENING-AT-LEVEL 2` |
| `rapplic-gval-unbound-fresh` | `,RAPPLIC` | `*ERROR* "UNBOUND-VARIABLE" "GVAL" RAPPLIC`, break `LISTENING-AT-LEVEL 2` |
| `rapplic-type-of-unbound-gval` | `<TYPE ,RAPPLIC>` | same `UNBOUND-VARIABLE` `"GVAL"` diagnostic, offender `RAPPLIC` |
| `rapplic-gval-after-full-chain` | `<FLOAD "77loadall.mud"> ,RAPPLIC` | full chain loads (`"DONE"` quoted in `result_output` after the 12 `... loaded` lines), then `*ERROR* "UNBOUND-VARIABLE" "GVAL" RAPPLIC` at break level 2 |
| `memq-nonlist-second-arg` | `<MEMQ 'A 5>` | stderr `Second arg to MEMQ must be structured` with no `*ERROR*` break; `result_output` is just a fresh `LISTENING-AT-LEVEL 1 PROCESS 1` prompt |

- **`USE` is not bound in the pinned reference.** Evaluated outside the
  short-circuit, `<USE "LSRTNS">` breaks with
  `*ERROR* "UNBOUND-VARIABLE" "In apply of form" USE` — the atom `USE` is
  unbound and the error is raised in the apply-path diagnostic form, not
  the `GVAL` read form used for `,RAPPLIC`.
- **`RAPPLIC` reads break UNBOUND in a fresh process and after the full
  chain.** Both `,RAPPLIC` and `<TYPE ,RAPPLIC>` give
  `*ERROR* "UNBOUND-VARIABLE" "GVAL" RAPPLIC`; loading the whole
  `77loadall.mud` chain first changes nothing — the chain output in that
  case shows all 12 files loaded and `"DONE"` before the break. The
  reference is fully consistent with the sources: RAPPLIC is used only as
  a declared type name and is never assigned a value.
- **MEMQ rejects a non-LIST second argument with a direct diagnostic,**
  `Second arg to MEMQ must be structured`, on stderr, without an `*ERROR*`
  marker — the process returns to a fresh `LISTENING-AT-LEVEL 1` prompt
  rather than a nested break level (distinct from the UNBOUND-VARIABLE
  break pattern above).

## Findings (issue #51 D4 load blocker parity facts)

1. **`MUDDLE` = FIX 101, TYPE FIX, interpreter-supplied** (quoted `101`
   / `FIX`); no `.mud` file assigns it. The `77defs.mud:1` guard
   `<L? ,MUDDLE 100>` is `#FALSE ()`, so `<AND <L? ,MUDDLE 100> <USE "LSRTNS">>`
   returns `#FALSE ()` without touching `USE` (clean exit, empty stderr).
2. **`USE` is NOT implemented in the pinned reference** — it is an unbound
   atom; a direct call breaks `UNBOUND-VARIABLE` `"In apply of form"`.
   Any implementation that reaches `<USE ...>` will need this error path
   or the guard must short-circuit first, exactly as the reference's AND
   does.
3. **`RAPPLIC` is unassigned in a fresh process and stays unassigned after
   the entire chain loads** (fresh `<GASSIGNED? RAPPLIC>` → `#FALSE ()`;
   post-chain `<GASSIGNED? RAPPLIC>` → `#FALSE ()`; reads break
   `UNBOUND-VARIABLE` `"GVAL"` both times). It originates nowhere — the
   chain defines its DECL association only, via 77defs expression 3,
   `<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>`, which succeeds on the
   unassigned atom and echoes `RAPPLIC`.
4. **The pinned reference loads the whole `77loadall.mud` chain to
   completion with zero errors** — first failure: none. Twelve
   `... loaded` lines plus FLOAD's return `"DONE"`. Parity for the
   implementation's chain loader is defined by this full-completion
   transcript, not the current three-expression barrier recorded in
   SEGMENTS.md.
5. **MEMQ** returns the sublist beginning at the first element matching
   the item (`(A B)` / `(B)`, TYPE `LIST`), `#FALSE ()` on miss, and
   rejects a non-LIST second argument with stderr
   `Second arg to MEMQ must be structured` (no `*ERROR*` break).

## Files created

- `docs/evidence/M2/muddle-cases.json` (12 clean-exit cases)
- `docs/evidence/M2/muddle-reference.json` (generated by the probe tool,
  `complete: true`)
- `docs/evidence/M2/muddle-error-cases.json` (5 deliberate-error cases)
- `docs/evidence/M2/muddle-error-reference.json` (generated by the probe
  tool, `complete: false` — by design)
- `docs/evidence/M2/MUDDLE.md` (this note)

## Implementation record (D4, main-session implemented and verified)

Implemented on branch `feat/m2-muddle` (main-agent change: the slice is a
single seeded global; the following atom-property PUT slice will be
delegated), tracked by
[issue #51](https://github.com/quaat/mdl-racket/issues/51).

- **Red:** the pinned `77loadall.mud` chain stopped at ten completed
  expressions with `unassigned MDL global MUDDLE` at `77defs.mud`
  expression 1; `tests/muddle_test.rkt` (new) failed at its first
  session-global assertion.
- **Change:** `mdl-interpreter-version` (101, exported) and in-session
  seeding — `make-mdl-session` interns `MUDDLE` into its globals hash
  inside `call-in-session`, so the atom belongs to that session's atom
  space (an earlier-interned atom would have a different identity than
  later GVAL lookups, the atom-identity lesson recorded in D1's tests).
- **Green (fresh, main session):** `tests/muddle_test.rkt` 9 checks
  (value, TYPE, GASSIGNED?, the false guard, the short-circuited AND, and
  `USE` remaining an explicit failure); full suite 802 Racket checks;
  loader 57; historical VFLOAD 23; historical DECL 20 (its chain
  assertion now pins twelve completed expressions and the new blocker);
  `git diff --check` clean.
- **Load progression:** the chain completes **twelve** expressions —
  past `77defs.mud:1` (guard false, `USE` never evaluated) and expression
  2 — and stops at `77defs.mud` expression 3:
  `<PUT RAPPLIC DECL '<OR ATOM FALSE NOFFSET>>` fails with
  `mdl-put: index out of range` (execute stage, 5:1): atom-property
  `PUT` is the next source dependency, exactly as predicted in the D4
  reference note (RAPPLIC stays unassigned; the historical mechanism is
  the DECL *property* on the atom).
- **Reference parity note:** the pinned reference loads the entire chain
  to `DONE`; the gap from twelve completed expressions to that target
  is now bounded by atom-property PUT and the constructs behind it.
