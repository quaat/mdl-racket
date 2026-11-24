# M4 S9 reference: the IMAGE, SLEEP and TIME SUBRs

Date: 2026-11-24. Read-only reference investigation for issues #168, #169
and #170. Pinned mdli sha256
`6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` before and
after (not rebuilt); upstream mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`;
fixed clock 250776000, TZ=UTC (shim `scripts/reference/fixed_time.c`, sha256
`d1fa8652…b925`; the shim fixes the wall clock only: sleeping and CPU time run
normally).

Command: `python3 -I scripts/probe_p0prims_reference.py docs/evidence/M4/p0prims-probe.json`
→ exit 0, 48 cases (one bare mdli process each, pipe mode, each in a fresh
empty `$TMPDIR/p0prims-probes` directory; no game load). Record:
`p0prims-probe.json` (sha256 `60860ea3…05be`), raw stdout/stderr per case
(latin-1, so IMAGE's bytes appear as `\u0007` etc.; `stdout_hex_tail` repeats
the last 64 bytes in hex), wall time per case (`elapsed_seconds`). Script
sha256 `8caa5777…0b65`.

Manual: *The MDL Programming Language* §11.4.2.3 (IMAGE: "always outputs the
real thing: that ASCII character whose ASCII 7-bit code is *fix* … *channel*
is optional, `.OUTCHAN` by default … `IMAGE` returns *fix*"), §21.10.2
(SLEEP: "suspends execution, interruptibly, without consuming any CPU time,
for *time* seconds, where *time* is non-negative, and then returns `T`.
*pred* is the same as for `HANG`"), §23.1 (TIME: "takes any number of
arguments, which are evaluated but ignored, and returns a `FLOAT` giving the
number of seconds of CPU time the MDL process has used so far"), Appendix 2
(`IMAGE (CODE "OPTIONAL" (CHANNEL .OUTCHAN))`; `SLEEP (<OR FIX FLOAT>
"OPTIONAL" (UNHANG <>))`; `TIME ("TUPLE" IGNORED)`, VALUE FLOAT).

## Findings

Printed results follow `LISTENING-AT-LEVEL 1 PROCESS 1`; IMAGE's byte comes
right before the printed return value.

| Case | Observation |
|---|---|
| baseline | `<+ 1 1>` 2; 0.01 s |
| image-65 | byte `A`, then `65`; `<TYPE <IMAGE 66>>` byte `B`, `FIX` |
| image-7 | byte 0x07, `7`; TYPE FIX |
| image-controls | codes 0, 1, 10, 13, 27, 127: each written as that one raw byte (0x00 0x01 0x0A 0x0D 0x1B 0x7F), never `^X`; returns the code |
| image-128 / -200 / -255 | one byte 0x80 / 0xC8 / 0xFF; returns the code |
| image-256 / -321 / -negative | byte 0x00 / `A` (0x41) / 0xFF: **the code modulo 256**; returns 256 / 321 / -1 |
| image-outchan-lval / -gval | `<IMAGE 66 .OUTCHAN>` `B` 66; `<IMAGE 67 ,OUTCHAN>` `C` 67 |
| err-image-inchan | `<IMAGE 65 .INCHAN>`: **no byte, returns 65**, no error |
| err-image-chan-fix | `<IMAGE 65 1>`: stderr `Error: Attempt to write to non-channel`, back at LISTEN level 1 |
| err-image-no-args / -three-args | `*ERROR*` TOO-FEW- / TOO-MANY-ARGUMENTS-SUPPLIED |
| err-image-string, -character, -float, -false, -atom | `*ERROR*` FIRST-ARG-WRONG-TYPE each (a CHARACTER is refused too) |
| image-applicable | `<TYPE ,IMAGE>` SUBR; `<APPLY ,IMAGE 68>` `D` 68 |
| image-fweep-no-sleep | FWEEP (77act2.mud:53) `<FWEEP 7>`: six 0x07 bytes, value T, 0.01 s |
| sleep-0 | `<SLEEP 0>` T; `<TYPE <SLEEP 0>>` ATOM |
| sleep-1 | T; **1.01 s** |
| sleep-3x1 | T T T; **3.01 s** |
| sleep-float, sleep-float-1.5, sleep-negative-float | `<SLEEP 0.5>`, `<SLEEP 1.5>`, `<SLEEP -0.5>`: `*ERROR*` FIRST-ARG-WRONG-TYPE, **no wait** (0.0 s) |
| sleep-negative | `<SLEEP -1>`: `*ERROR*` ARGUMENT-OUT-OF-RANGE "SLEEP time negative" |
| sleep-pred-true / -false | `<SLEEP 0 T>` T; `<SLEEP 1 <>>` T after 1.0 s (UNHANG accepted, not consulted) |
| sleep-gettimedate | `<GETTIMEDATE>` `![0 0 12 12 12 1977 0!]` before and after `<SLEEP 1>` (1.01 s): the shim's fixed wall clock does not move |
| err-sleep-no-args / -three-args | TOO-FEW- / TOO-MANY-ARGUMENTS-SUPPLIED |
| err-sleep-string, -atom, -false, -character, -list | FIRST-ARG-WRONG-TYPE each |
| sleep-applicable | `<TYPE ,SLEEP>` SUBR; `<APPLY ,SLEEP 0>` T |
| sleep-fweep | `<FWEEP 4 1>` (FLY-ME, 77act2.mud:43): three 0x07 bytes, T, **3.01 s** |
| time-type | `<TYPE <TIME>>` FLOAT; `<G? <TIME> 0.0>` T; `<TIME>` 0.0054770 (CPU seconds; differs per run) |
| time-args | `<TYPE <TIME 1>>` FLOAT; `<TYPE <TIME 1 "a" FOO <>>>` FLOAT; `<TIME <SETG X 5>>` then `,X` 5 (arguments evaluated, ignored) |
| time-monotonic | two successive values 0.0038540, 0.0038730: `<G=? .B .A>` T, `<==? .A .B>` FALSE |
| time-truthy | `<COND (<TIME> "true") …>` and `<COND (<APPLY <GVAL TIME>> "true") …>` "true" |
| time-applicable | `<TYPE ,TIME>` SUBR; `<TYPE <APPLY ,TIME>>` FLOAT |
| time-sleep | TIME before and after `<SLEEP 1>` differ by 0.00015 (`<L? <- .B .A> 0.5>` T): SLEEP uses no CPU time |

Every case exit 0; the error cases' stderr is the usual `Atom REP has neither
LVAL nor GVAL` of the second LISTEN level.

## Manual vs reference, and this runtime

1. **IMAGE codes.** The manual specifies a 7-bit ASCII code; the reference
   writes any FIX modulo 256. This runtime accepts 0–127 and writes exactly
   that byte (maintainer decision #168: the exact byte); other codes are a
   strict error (ADR-0050/0057 terminal range). The game uses 7 only.
2. **IMAGE channels.** The reference silently writes nothing to an input
   channel and prints a host error for a non-CHANNEL; this runtime refuses
   both strictly (the PRINC channel check). The game uses the default
   channel only.
3. **SLEEP FLOAT.** The manual and Appendix 2 accept a FLOAT time; the
   reference refuses every FLOAT. This runtime follows the reference.
4. **SLEEP waiting.** Natively SLEEP always waits (also under the
   fixed-clock shim). This runtime waits only on a live session clock
   (maintainer decision #169); under the fixed and replaying clocks used by
   tests and restore it returns T at once. Same value and errors in every mode.
5. **TIME value.** Natively CPU seconds, non-deterministic. This runtime
   returns the session's TIME-call count as a FLOAT (maintainer decision
   #170; SEMANTICS "M4: IMAGE, SLEEP, TIME"), keeping TYPE FLOAT, positive,
   true, non-decreasing, successive calls not `==?`.
6. **Errors.** The reference raises MDL ERRORs; this runtime fails strictly
   (host errors) whose messages carry the same ERROR names, as for ABS/MAX.
