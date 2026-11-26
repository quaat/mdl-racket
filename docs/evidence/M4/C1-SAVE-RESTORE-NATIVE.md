# C1 (#172): native evidence for the game's `save` / `restore`

Date 2026-11-26. This is a read-only reference investigation of the pinned
Confusion interpreter. No implementation, test, script or Makefile was edited.
Nothing under `.cache/` was written, and `make reference-build` was not run.
The probe questions come from the C1 contract draft (§5.3, P1-P10). Probe P11
(restore after death and resurrection) was not run.

## Provenance

| Item | Value |
|---|---|
| Interpreter | `.cache/build/confusion_patched/mdli` (read from the main checkout's `.cache`; the worktree has none) |
| mdli sha256 before / after | `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` / same |
| Upstream mdlzork HEAD | `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3` (read from `.git/HEAD`) |
| Upstream tree hash before / after | `829dec20b2aea0a48048e4971a5f887ec5322599c80b547366b04e315fef3b29` (369 files) / same. Method: sha256 over the sorted lines `relpath NUL sha256 LF` for every regular file under `.cache/upstream/mdlzork`, `.git` included |
| Clock shim | `scripts/reference/fixed_time.c` (sha256 `d1fa8652…ab925`), compiled once per capture and loaded with LD_PRELOAD. Each process sets its own `MDL_FIXED_EPOCH` and `TZ=UTC`; microseconds are 0 |
| Default epoch | 250776000 (1977-12-12 12:00:00 UTC). START seed 10438660480 |
| Other epochs | E+3725 = 250779725; E+86400 = 250862400; 23:59:00 = 250819140; next-day 00:01:00 = 250819260 |
| Recorded at | 2026-11-26T21:42:57Z |

## Files

| File | Content |
|---|---|
| `c1-save-restore-cases.json` | Inputs: 31 cases, with the processes of each case, their commands, epochs, setup and host operations |
| `c1-save-restore-reference.json` | Every capture. For each process: stdin, raw stdout (latin-1, not canonicalised), stderr, exit status, clock, the files it changed, and the `SAVEFILE/ZORK.SAVE` size and sha256 after it ran. Also the determinism checks, the diagnostic-twin check, the interpreter and upstream hashes, and the diagnostic forms |
| `c1_save_restore_probe.py` | The driver. It reuses the protocol of `scripts/probe_failure_inventory_reference.py` and `probe_session_reference.py`, adding sequential processes and an epoch per process. It is evidence only and is not wired into any target |

## Protocol

- **Disposable copies.** Each repetition of a case gets one fresh copy of
  `mdlzork_771212/patched_confusion` under `$TMPDIR/c1-save-restore/`.
  - The case's processes run one after another in that same copy, so process
    B sees the files A left.
  - Only one mdli process ran at any time.
  - The shipped `SAVEFILE/ZORK.SAVE` is deleted from the copy, except in P6a.
- **Input.** Pipe mode: all of stdin is written at once, followed by EOF.
  - Game entry: `<FLOAD "77loadall.mud">`, then `<SAVE-IT>`.
  - P1 uses no entry ("bare" MDL).
- **Repetitions.** Every case was run twice. Every case that boots the game
  also has a **diagnostic twin**, also run twice.
  - The twin types forms at LISTEN after FLOAD and before SAVE-IT. They wrap
    `READSTRING` and `RANDOM`. At each READSTRING entry the wrapper prints
    a state row `{{CP …}}` to stdout. It also prints each `{{IN "line"}}`
    read and each draw `{{R args=>value}}`.
  - The state row fields are MOVES, `RID ,HERE`, LIT?, RAW-SCORE, ASTRENGTH,
    DEATHS, the CTICK/CFLAG of LNTIN and CURIN, the troll's OCAPAC and
    FIGHTBIT, OLIGHT? of the lamp, BRIEF/SUPER-BRIEF, AVEHICLE, INTIME as
    FIX, PLAYED-TIME, PARSE-WON, and `TYPE <2 ,PRSVEC>`.
  - The wrappers apply the original SUBR and return its value unchanged.
  - **Check:** for all 29 game cases and every process, the twin's game
    output with the `{{…}}` markers removed is byte-identical to the
    transcript run's output. So the wrappers did not change what the game
    prints.
  - CP rows appear at *every* READSTRING, including the "patch you?"
    question after a death (P3c).

## Commands and exit codes

```
sha256sum .cache/build/confusion_patched/mdli                 # 6df359f6…b789, exit 0
python3 -I docs/evidence/M4/c1_save_restore_probe.py \
    docs/evidence/M4/c1-save-restore-cases.json \
    docs/evidence/M4/c1-save-restore-reference.json \
    --cache <main checkout>/.cache --shim-src scripts/reference/fixed_time.c
                                                               # exit 0
sha256sum .cache/build/confusion_patched/mdli                 # unchanged, exit 0
```

- **Processes.** 168 mdli processes ran, and every one exited with status 0.
  - Confusion exits 0 even on EOF.
  - Every game run ends with `Error: Unexpected EOF` on stderr, because
    stdin is exhausted at the next READSTRING.
- **Exploration.** An exploratory sweep found the inputs for P3b and P3c: 0
  to 6 `diagnose` turns before `save`, run in scratch only. It is not part
  of the reference file.

## Determinism

- **Transcripts.** For each process, stdout was **byte-identical** between
  repetition 1 and 2 in all 31 cases. This holds for both the transcript and
  the diagnostic variants. Exit statuses were also identical.
- **stderr.** Identical everywhere except process B of P6c and P6d (the
  truncated images). There the image-reader message names a different number
  each time, for example `Unable to fixup assoc table 21` / `18` / `15` /
  `17`.
- **Save images.** The bytes are **not reproducible**: the same input gives a
  different sha256, and often a different size.
  - P8 A: 874,953 bytes vs 874,947 bytes.
  - P1 `R.SAVE`: 12,921 bytes in both repetitions, with different sha256s.
  - The transcripts that read these images back were still identical.

## Per-probe results

Every quoted excerpt is from `stdout_raw` of the transcript run, repetition 1
(CR bytes are omitted here). "CP" rows are from the diagnostic twin. A CP row
printed after `IN "x"` is the state at the next READSTRING, i.e. after command
x and its demons.

| Probe | Question | Native answer | Evidence (excerpt) |
|---|---|---|---|
| P1 cross-process | Is RANDOM state part of the image? | **No.** The heap comes back but RNG does not. B continues its own sequence after RESTORE. | A after `<SAVE "R.SAVE">`: `-34359694148 -17179805972 -34359697230`. B: `,MARK` → `42` (A's value; B had set 7), then `-17179869184 -34359738368 -8589934592`. These equal C-control's draws 3-5 (`-34359738368 -34359738368 -17179869184 -34359738368 -8589934592`). LISTEN printed nothing for the RESTORE line, then went on reading stdin |
| P1 same process | Does RESTORE rewind RANDOM? | **No.** | After save: `-34359694148 -17179805972 -34359697230`. After restore: `-8589878332 -25769768035 21474895487` |
| P1g | Game combat after a restore in a new process: whose RNG? | **The restoring process's.** The same image gives different fights depending on B's epoch and B's draws before the restore. | One A image (route to the Troll Room, `save`). B restore-first (epoch E): `Your sword pinks the troll on the wrist…` and `It's curtains for the troll…`. B after 3 looks: `The force of your blow knocks the troll back, stunned.`, and the player is killed on the `score` turn. B at E+86400: `A furious exchange, and the troll is knocked out!`, then on the 3rd kill `I can't see a troll here.` In-process: `Clang! Crash! The troll parries.` RNG log of B restore-first: B's own stream from its START seed (`=>-21802663835` at ROOM-INFO, then `12914488375 …`) |
| P2 | Lamp tick and MOVES across save→restore | Restored MOVES **includes the save turn**. The save turn's clock tick is **absent**. | CP after `turn on lamp`: `MOVES=7 LN=349`. After `save`: `MOVES=8 LN=348`. After `restore`: `MOVES=8 LN=349`. After `look`: `MOVES=9 LN=348`. Then `Your score would be 10 [total of 500 points], in 10 moves.` |
| P3 | Is the save turn's villain blow undone? | **Yes.** All demon effects of the save turn are absent after restore: wound, CURIN, death. | P3b, save turn: `Saving.` `The flat of the troll's axe skins across your forearm.` CP after save: `ASTR=-1 CU=29 CUF=T LN=342 MOVES=18`. After restore: `ASTR=0 CU=0 CUF=#FALSE () LN=343 MOVES=18`. `diagnose` → `You are in perfect health.` P3c, the save turn kills the player: CP shows `DEATHS=1 HERE=FORE1`. After restore: `HERE=MTROL DEATHS=0 MOVES=19`, and `diagnose` → `You have a light wound, which will be cured after 29 moves.` In P3 itself the save-turn blow missed (`The troll's axe barely misses your ear.`), so health shows no difference there |
| P4 | Text after a successful restore | Always `Restored.` + LF, then the output of ROOM-INFO T (full description), then `>`. In every observed case this is identical to an immediate `look`. ROOM-INFO T draws RANDOM once in a seen, lit room when BRIEF is off (SUPERBRIEF included), and not in a dark room or with BRIEF on. | Dark cellar: `Restored.\nIt is pitch black.  You are likely to be eaten by a grue.` (no draw). BRIEF: the full West of House text (no draw). SUPERBRIEF: the full text, one draw `=>-21802663835`. Boat at the dock: dam-base text + `You are in the magic boat.\nThe magic boat contains:\n A tan label\nA sharp stick, … is here. [in the room]`. On the river: `You are on the River Frigid in the vicinity of the Dam. …` + boat lines |
| P5 | Clock after restore | GET-TIME uses the **saving session's INTIME**, so downtime counts. PLAYED-TIME stays 0. The restoring session's own INTIME and MOVES are discarded. Its play before the restore takes no time under the fixed clock, so its duration is not tested here. | A at E `save`; B at E+3725 `restore` `time` → `You have been playing DUNGEON for 1 hour, 2 minutes, and 5 seconds.` CP INTIME goes from `10438667930` (B) to `10438660480` (A). Controls: B without restore → `0 seconds`; A `save` `time` → `0 seconds`. Across midnight (23:59:00 → 00:01:00): `2 minutes, and 0 seconds`, and B's banner says `December 13.` After 3 looks in B: still `1 hour, 2 minutes, and 5 seconds`, and score `in 3 moves` (the image's MOVES 1, plus `time` and `score`) |
| P6a | The shipped `ZORK.SAVE` (873,599 bytes) | **Loads.** It is a game at North of House with MOVES=2. | `Restored.\nYou are facing the north side of a white house.` Then `in 4 moves`, `You are empty handed.`, `You have been playing DUNGEON for 20 hours, 39 minutes, and 12 seconds.` Diagnostic twin: no CP rows after `restore`, i.e. the image's GVALs replaced the session's wrappers |
| P6b | No `SAVEFILE/` directory | `Saving.` is still printed and no file is created. `restore` prints `Restored.` with no room text, the turn counts, and play goes on (the F4 path) | `>Saving.\n>Restored.\n>\nYour score would be 0 … in 3 moves.` stderr is only `Error: Unexpected EOF` |
| P6c-e | Truncated image: 1000 bytes, half its size, 0 bytes | Same as F4: `Restored.`, then play goes on in the current state and the turn counts. stderr carries a reader message | `>Restored.\n>\nYour score would be 0 … in 2 moves.` stderr: `Unable to fixup assoc table N`, `Unable to read object type N` / `Failed to fixup object N (type 0)`, `Unable to read built_in table -1` |
| P7 | `save` `n` `restore` in one process | Rolls back to the save point | `Restored.\nYou are in an open field west of a big white house…` Then `in 3 moves` and `You are empty handed.` CP after restore: `MOVES=1 HERE=WHOUS` |
| P8 | `restore` as the first command after a process that saved | Loads A's state: MOVES from the image, room text of the image | `>Restored.\nYou are facing the north side of a white house.` → `in 3 moves`. CP after restore: `MOVES=2 HERE=NHOUS`. B changed only `MDL/MADADV.SAVE` |
| P9 | `save` typed at an orphan prompt | `save` is parsed as the SAVE verb. The orphan is cleared by that parse, with or without a restore | P9a: `>at what?\n>Saving.\n>Restored.\n…` then `mailbox` → `What should I do with the mailbox?` P9c (no restore): the same `What should I do with the mailbox?` P9b: `Kill what?` → `Saving.` CP: `PRSO=OBJECT PW=#FALSE ()` after `throw leaflet`, then `PRSO=FALSE PW=VERB` after `save` |
| P10 | Restore twice; does restore change the image? | Both restores return to the same point. **The image is never modified by RESTORE.** | P10a and P10b: two `Restored.` + West of House, CP `MOVES=1` after each restore, then `in 3 moves`. P10b image sha256 after A = after B (`bd9ff24e9b70…`). None of the 48 game processes that restored without saving changed `SAVEFILE/ZORK.SAVE`; each changed only `MDL/MADADV.SAVE`, which SAVE-IT writes |

### Observations common to all probes

- No restore ever printed a second `Saving.`. The SAVE call is never
  resumed, consistent with F5 and `S5-SAVE-FRONTIER.md`.
- The game's text for a failed restore (P6b-e) is the same as when no image
  exists (F4).
- Pre-restore output in the restoring process stays on stdout. For example,
  B's 3 `look` replies in P1g and P5c come before `Restored.`

## Deviations between Confusion and the manual

These are already noted in `S5-SAVE-FRONTIER.md` and the C1 draft; this run
confirms them:

- **Execution state.** Manual §11.6.2 says RESTORE makes SAVE return
  `"RESTORED"` and resumes the saved execution state. Natively, the saved
  turn's continuation (`Saving.`, the room action, the demons) never runs
  (P2, P3b, P3c).
- **RNG.** The manual says SAVE stores "the entire state". Confusion does not
  store RANDOM state (P1, P1g).

## What this means for replay equivalence (facts only)

1. **The restored state is the heap at the SAVE call inside the save turn.**
   MOVES includes the save turn. None of that turn's demon effects are
   present: lamp tick, wound and CURIN, death. A state taken at the next
   prompt after `save` differs from it in LN, ASTRENGTH, CURIN, DEATHS and
   HERE (P2, P3b, P3c).
2. **The text after a successful restore is fixed:** `Restored.` + LF, then
   ROOM-INFO T, then `>`.
   - ROOM-INFO T makes 0 or 1 RANDOM draws, depending on lighting, RSEEN and
     BRIEF (P4).
   - It may describe a vehicle and its contents, with `[in the room]`
     suffixes.
3. **The RNG after restore comes from the restoring process,** with its own
   START seed and its own earlier draws.
   - The same image gave four different troll fights in four restoring
     contexts (P1g).
   - So native post-restore random text is reproducible only when the
     restoring process's seed (its epoch) and its draws before the restore
     are also fixed.
4. **The clock counts downtime.** After restore, INTIME is the saving
   session's and PLAYED-TIME stays 0, so `time` reports the wall-clock time
   since the saving session's START (P5).
5. **A failed restore leaves the current session running.** This covers a
   missing directory, a missing file, an empty file and a truncated file. The
   session prints `Restored.`, counts the turn and runs its demons. The only
   other signal is a stderr line, whose text can vary between runs (P6b-e,
   F4).
6. **The shipped `SAVEFILE/ZORK.SAVE` restores under the pinned Confusion**
   (North of House, MOVES 2). This matters for any probe that does not
   delete it (P6a).
7. **Image files are not byte-reproducible; transcripts are.**
   - Native evidence for save/restore can only be compared by transcript and
     game state, not by image hash.
   - A restore does not change the image, and one image can be restored
     repeatedly (P10).
8. **`save` at an orphan prompt is an ordinary SAVE command.** It clears the
   orphan before the image is written (P9).
