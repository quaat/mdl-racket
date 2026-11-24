# M4 S8 reference: the ABS SUBR

Date: 2026-11-24. Read-only reference investigation for issue #167. Pinned
mdli sha256 `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789`
before and after (not rebuilt); upstream mdlzork
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`; fixed clock 250776000, TZ=UTC
(shim `scripts/reference/fixed_time.c`, sha256 `d1fa8652…b925`).

Command: `python3 -I scripts/probe_abs_reference.py docs/evidence/M4/abs-probe.json`
→ exit 0, 21 cases (one bare mdli process each, pipe mode, each in a fresh
empty `$TMPDIR/abs-probes` directory; no game load). Record: `abs-probe.json`
(sha256 `ccee33fc…3302`), raw stdout/stderr per case (latin-1; local paths
sanitized to `$TMPDIR` / `<repo>`). Script sha256 `1275c11a…b458`.

Manual: *The MDL Programming Language* §3.4 (ABS among the arithmetic SUBRs,
indifferent to FIX/FLOAT), §3.5 (overflow is an error), Appendix 2
(`ABS (NUMBER)`, `#DECL ((VALUE) <OR FIX FLOAT> (NUMBER) <OR FIX FLOAT>)`,
"returns absolute value of a number").

## The game's ABS calls (grep of the pinned `.mud` files)

| Site | Form | Argument |
|---|---|---|
| `77act1.mud:949` CYCLOPS, waking | `<PUT .RM ,RVARS <ABS <RVARS .RM>>>` | FIX (the cyclops anger counter) |
| `77act1.mud:951` CYCLOPS | `<G? <ABS .COUNT> 5>` | FIX (COUNT DECLed FIX at `:940`) |
| `77act1.mud:1031` CYCLOPS-ROOM | `<NTH ,CYCLOMAD <ABS .VARS>>` | FIX (VARS DECLed FIX) |
| `77act1.mud:1050` AOS-SOS | `<NTH ,CYCLOMAD <ABS .FOO>>` | FIX (FOO DECLed FIX) |

No FLOAT argument and nothing near ±2^35 occurs (the counter stays in −6..6).

## Findings

| Case | Observation |
|---|---|
| fix | `<ABS 5>` 5, `<ABS -5>` 5, `<ABS 0>` 0, TYPE FIX each; `<ABS -1>` 1, `<ABS 1>` 1 |
| float | `<ABS 2.5>` 2.5000000, `<ABS -2.5>` 2.5000000, `<ABS 0.0>` 0.0000000, TYPE FLOAT each; `<ABS -0.5>` 0.5000000; `<==? <ABS -2.5> 2.5>` T |
| float-large | `<ABS -1.0E20>` 100000000000000000000.0000000, `==?` 1.0E20 T, TYPE FLOAT; `<==? <ABS <- <MIN>>> <MIN>>` T, `<==? <ABS <MIN>> <MIN>>` T, TYPE FLOAT; `<==? <ABS <MAX>> <MAX>>` T and `<G? <ABS <MAX>> 0>` T (the reference `<MAX>` is the positive DBL_MIN, R6/ADR-0059); `<ABS <* -100000000000.0 1000000000.0>>` 100000000000000000000.0000000 and `==?` the positive product T |
| fix-36bit-boundaries | `<ABS 34359738367>` 34359738367, `<ABS -34359738367>` 34359738367 FIX |
| fix-most-negative | **`<ABS -34359738368>` 34359738368, TYPE FIX**; `<G? <ABS -34359738368> 34359738367>` T (64-bit host FIX, no overflow) |
| fix-most-negative-computed | `<ABS <- 0 34359738368>>` 34359738368; `<TYPE <- 0 34359738368>>` FIX |
| fix-beyond-36bit | `<ABS -34359738369>` 34359738369 FIX |
| err-no-args | `*ERROR* "TOO-FEW-ARGUMENTS-SUPPLIED"`, LISTENING-AT-LEVEL 2 |
| err-two-args, err-two-args-negative | `*ERROR* "TOO-MANY-ARGUMENTS-SUPPLIED"` |
| err-string, err-atom, err-quoted-atom, err-list, err-false, err-character, err-vector | `*ERROR* "FIRST-ARG-WRONG-TYPE"` each |
| applicable | `<TYPE ,ABS>` SUBR; `<APPLY ,ABS -7>` 7; `<MAPF ,LIST ,ABS '(-1 2 -3)>` (1 2 3) |
| game-cyclops-count | `<G? <ABS .COUNT> 5>`: COUNT 0 FALSE, −6 T, 6 T, −5 FALSE |
| game-cyclomad-index | `<NTH v <ABS -1>>` "a", `<ABS 2>` "b", `<ABS -6>` "f"; FOO −2 → −3 → "c" |
| game-rvars-put | `<PUT ,V 1 <ABS <1 ,V>>>` on `[-3]` gives `[3]`, element FIX |

Every case exit 0; the error cases' stderr is the usual
`Atom REP has neither LVAL nor GVAL` of the second LISTEN level.

## Manual vs reference

They agree for every value the game can produce (FIX in the 36-bit range,
TYPE preserved, one argument). Differences, none on the game path:

1. **−2^35.** The manual's 36-bit machine cannot represent +2^35, and §3.5
   makes overflow an error. Confusion FIX is a 64-bit host integer and
   returns FIX 34359738368. This runtime follows the 36-bit model: strict
   `mdl-abs: FIX overflow` (as `<- 0 -34359738368>` already is). Recorded
   deviation (docs/SEMANTICS.md "M4: ABS (#167)").
2. **Beyond the 36-bit range** (`-34359738369`): our reader makes the literal
   a FLOAT (M1 issue #8), so ABS gives FLOAT 34359738369.0 here, FIX there.
3. **`<ABS <MAX>>`**: follows the ADR-0059 `<MAX>` difference (DBL_MIN there,
   the least PDP-10 FLOAT here, whose ABS is `<MIN>`).
4. **Exponent FLOAT literals** (`1.0E20`) are a strict reader failure here
   (reader scope, not ABS); the test forms the same value by multiplication.
5. **Errors**: the reference raises MDL ERRORs (FIRST-ARG-WRONG-TYPE,
   TOO-FEW/TOO-MANY-ARGUMENTS-SUPPLIED); this runtime fails strictly with
   messages carrying the same arity names, as MAX does.

No adjudication is needed: the game uses ABS only on small FIX counters.
