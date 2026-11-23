# Clock → DSKDATE → RANDOM seed chain: pinned Confusion reference (Probe E)

This is a read-only reference investigation, 2026-11-23.

- **Data:** [`clock-seed-probe.json`](clock-seed-probe.json)
- **Driver:** [`scripts/probe_session_reference.py`](../../../scripts/probe_session_reference.py) `seed`
- **Provenance:** as in [SESSION-QUIT-REFERENCE.md](SESSION-QUIT-REFERENCE.md)
  - mdli sha256 `6df359f6…b789`, the same before and after
  - mdlzork `bdcd4a67`
  - shim `fixed_time.c` sha256 `d1fa8652…ab925`, which freezes `gettimeofday`, `time` and
    `CLOCK_REALTIME*` with `tv_usec`/`tv_nsec` = 0

**Command** (sandboxed; exit 0; every mdli exit 0):

```
python3 -I scripts/probe_session_reference.py seed docs/evidence/M3/clock-seed-probe.json \
  --shim-src <boot-ref worktree>/scripts/reference/fixed_time.c
```

**Diagnostic runs vs transcript runs.** Cases marked diagnostic `SETG` RANDOM, GETTIMEDATE and
READSTRING to logging FUNCTIONs **before** the FLOAD, and DSKDATE (a game FUNCTION) after the
FLOAD and before `<SAVE-IT>`. They log to `DIAG.LOG` outside the game copy.

- Each wrapper applies the original to the same arguments and returns its value unchanged.
- Their game stdout equals the transcript runs: E1 vs E7, and E4 vs E4b.
- The transcript runs (E4b, E7, E7b) use no wrapper.

## Source chain (file:line, all in `mdlzork_771212/patched_confusion`)

1. **`GETTIMEDATE`** is a Confusion SUBR (behaviour only). It returns the 7-element FIX
   UVECTOR `[sec min hour mday month year usec]` from `gettimeofday` and `localtime_r`, so it
   depends on **TZ**.
2. **`DSKDATE`** is defined in `81tell-repl.mud:57-61`, not as a Confusion builtin:
   ```
   <DEFINE DSKDATE ("AUX" (DVEC <GETTIMEDATE>) (W #WORD 0) TM)
     <SET W <PUTBITS .W <BITS 18 0> <+ </ <7 .DVEC> 500000> <* <1 .DVEC> 2> <* <2 .DVEC> 120> <* <3 .DVEC> 7200>>>>
     <SET W <PUTBITS .W <BITS 7 27> <MOD <6 .DVEC> 100>>>  ;"Year"
     <SET W <PUTBITS .W <BITS 4 23> <5 .DVEC>>>  ;"Month"
     <SET W <PUTBITS .W <BITS 5 18> <4 .DVEC>>>  ;"Day of Month"
   >
   ```
   The formula is:

   **seed = (year mod 100)·2²⁷ + month·2²³ + mday·2¹⁸ + (⌊usec/500000⌋ + 2·sec + 120·min + 7200·hour)**

   The low 18 bits count half-seconds of the local day.
3. DSKDATE is called three times before play, and every result is identical under the fixed clock:
   - SAVE-IT → `REMARKABLY-DISGUSTING-CODE` (`77rooms.mud:10`, defined at 158). This produces
     `This version created December 12.`
   - START: `<SETG INTIME <DSKDATE>>` (`77rooms.mud:277`).
   - START: **`<RANDOM <CHTYPE <DSKDATE> FIX>>`** (`77rooms.mud:291`). This is the only seeding
     call. Its return value is discarded, and it is followed by `<INT-LEVEL 0>` and `<CONTIN>`.

   Later readers of DSKDATE are not seed inputs: `GET-TIME` (174) and `PDSKDATE` (833, from
   RECORD 761), plus the save/restore paths (390, 417).
4. **`PROB`** (`77rooms.mud:446`) is `<L=? <MOD <RANDOM> 100> .NUM>`.
5. **ROOM-INFO**, `77rooms.mud:521-525`, prints the brief text `RDESC2` when the room was seen
   (`RSEEN?`) **and** `<OR ,BRIEF!-FLAG <PROB 80>>` holds and the call is not FULL. Otherwise
   it prints the full `RDESC1`.

**RANDOM state.** This is observed behaviour: the formula reproduces every value below.
- RANDOM keeps two 36-bit words.
- A one-argument call sets the first word to the seed and **keeps the second word**, then
  advances once and returns.
- The second word holds its interpreter-start value, `0155256071112`, because **no RANDOM
  call happens before START's seed call**. RANDOM was wrapped before FLOAD, and the first
  logged RANDOM is the seed call (E1, E4).

This matches the runtime's existing one-seed rule ([RANDOM-START.md](RANDOM-START.md)).

## Observations

| Case | Clock | GETTIMEDATE (all 3 calls) | DSKDATE as FIX (all 3) | Seed arg to RANDOM | Seed call returns | 2nd RANDOM (`west`'s PROB 80) → MOD 100 | `west` text |
|---|---|---|---|---|---|---|---|
| E1 / E1b (repeat) | 250776000, UTC | `![0 0 12 12 12 1977 0!]` | **10438660480** (octal 115614250600) | 10438660480 | 16566282405 | −21802663835 → **65** (≤ 80) | brief: `West of House\nThere is a small mailbox here.\n` |
| E2 | 251036100 (1977-12-15 12:15:00), UTC | `![0 15 12 15 12 1977 0!]` | 10439448712 | 10439448712 | 16565494189 | −21802005015 → **85** (> 80) | **full**: `You are in an open field west of a big white house, with a boarded\nfront door.\nThere is a small mailbox here.\n`. The banner reads `December 15.` |
| E3 | 250776000, `TZ=America/New_York` | `![0 0 7 12 12 1977 0!]` | 10438624480 | 10438624480 | 16566255045 | −21802737739 → 61 | brief |

- E1 and E1b side logs are identical. The E7 and E7b transcripts are byte-identical (same stdout sha256).
- The E1/E7 `west` text equals the approved `house-boot-candidate.json` (BOOT-REF `e616ac0`).
- **Only two RANDOM calls** happen in the whole six-command scenario: the seed call and
  `west`'s PROB. `north` enters an unseen room, so it calls no PROB, and the other commands
  call none.

**The first 13 values after seeding** (E5 plain LISTEN after FLOAD: `<RANDOM seed>`, then 12 × `<RANDOM>`):

- **Epoch A** (seed 10438660480): 16566282405, −21802663835, 12914488375, −6577089531,
  34210328094, 3437552668, 13814526739, −20114144995, 11990399124, 31711279130,
  25894896720, 24534915165, −5538612619
- **Epoch B** (seed 10439448712, E5b): 16565494189, −21802005015, 12915277119, −6577677365,
  34210260308, 3438241969, −20545471973, 14245121603, −5190372530, −2648140689, 125308360,
  33125320703, −1244643045

**In-game confirmation (E4).** E4 is 12 alternating `north`/`west` moves. The 1st `north`
enters an unseen room, so it calls no PROB. Each of the other 11 moves enters a seen room and
calls PROB 80.
- The side log holds 12 RANDOM results: the seed call's return plus the 11 PROB draws.
  They equal values 1-12 of the epoch-A list exactly.
- The PROB draws MOD 100 are 65, 75, 69, **94**, 68, 39, 5, 24, 30, 20, 65.
- The transcript (E4b, no wrappers) shows the full text for the 1st command (unseen room) and
  for the 5th (`north`, draw 94 > 80). Every other response is brief.

An independent model of the recurrence also reproduces the seeds, the values above, E2, E3
and E4 exactly. The model was an evidence aid in `$TMPDIR`, not committed and not runtime code.

**Subsecond time (E8, diagnostic).** GETTIMEDATE's element 7 was forced under the fixed clock:

| usec | DSKDATE |
|---|---|
| 0 or 499999 | 10438660480 |
| 500000 or 999999 | **10438660481** |

- The only subsecond input to the seed is that half-second bit.
- With the shim, `tv_usec` is always 0.
- Without the shim (E6), element 7 is live (`387293`, `387347`), so an unfixed clock varies
  the seed through the half-second bit as well.

## Answers

- **Seed formula:** `seed = CHTYPE(DSKDATE, FIX)`, the bit packing above, from local time.
  Its inputs are the year mod 100, month, day of month, hour, minute, second and the
  half-second bit (usec ≥ 500000). Nothing else from the clock reaches it: no weekday,
  no year above two digits, no sub-half-second resolution.
- **TZ reaches the seed** through `localtime_r` (E3). The fixed setting is `TZ=UTC`.
- **Interpreter state.** The sequence also depends on RANDOM's second state word, which is
  the interpreter's initial value only because nothing calls RANDOM earlier in the session.
  A RANDOM call added before START would shift every later value.
- **Under epoch 250776000, TZ=UTC:** seed 10438660480, and the `west` text is deterministic
  (brief `West of House`). A different epoch can flip it: epoch B gives the full text.

## Limitations

- **No real subsecond probe.** The subsecond case (E8) forces GETTIMEDATE's result through a
  wrapper. It is not a real `tv_usec`, because the shim has no microsecond control.
- **Confusion's RANDOM is cited, not reproduced.** Its starting value and recurrence are
  cited from observed outputs and the independent model. No Confusion source was copied.
- **Extreme seeds not probed.** RANDOM's negative/overflow behaviour is outside this probe;
  see RANDOM-START.md for the known `<RANDOM -1 -2>` deviation.
