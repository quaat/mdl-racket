# M4 WP4: host persistence by deterministic replay (proof of concept)

Result: **PASS (branch evidence, proof of concept, scenario-scoped)** on
`feat/m4-replay-persistence` (base `main` = `b74588d`). Epic #163 WP4.1–WP4.5
and the WP4.6 regressions that apply before player-facing saves. ADR-0061;
semantics in SEMANTICS "M4 WP4: session clock modes and deterministic replay
checkpoints". This is not a player-facing SAVE/LOAD, not a PLAYABLE claim
and not an M4-gate claim. `run-zork` and MDL code gained no file access;
ADR-0048 (SAVE) and ADR-0055 (OPEN) are unchanged.

Upstream (`sources.lock.json`): mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`,
MIT zork `d94501340842e006791fce0757dc0043b8ec8916`. Oracle: pinned Confusion
mdli `6df359f6…` captures in `troll-combat-reference.json` (S6). Local
toolchain: Racket v7.9 [bc]. Clock: fixed source 250776000, zone UTC (the
native capture's clock), recorded through the recording clock.

## Design

| Part | Where | What |
|---|---|---|
| Clock modes | `mdl/runtime/clock.rkt` | `make-recording-mdl-clock`, `make-replaying-mdl-clock`, `make-resumed-mdl-clock`, `mdl-clock-finish-replay!`, `mdl-clock-observations`; real and fixed unchanged; ADR-0052 interface unchanged |
| Input observer | `mdl/runtime/core.rkt` (READSTRING), `mdl/loader.rkt` (`#:input-observer`) | host-only procedure told at each READSTRING entry and, at return, the raw characters consumed and why the call ended (`stop`/`full`/`eof`) |
| Draw count | `mdl/runtime/random36.rkt` | host-only count of generator steps; never changes a RANDOM result |
| Engine | `mdl/replay.rkt` | canonical JSON + strict parser, checkpoint build/validate, `replay-record`, `replay-restore` |
| Zork profile | `zork/persistence.rkt` | RDCOM save boundary, selected state, seed provenance; `zork-record`, `zork-restore` |

**Module placement.** The generic machinery is a host module beside the
session loader (`mdl/replay.rkt`) because it depends only on the session
API, works for any MDL program (the fast suite uses a 25-line program) and
must stay outside the MDL language: no MDL primitive reaches it. The Zork
rules depend on the 1977 source (RDCOM's frame, ORPHANS, object names), so
they live with the launcher under `zork/`. Neither writes a file; a
checkpoint is a detached byte string (tests store it under `$TMPDIR`).

**RNG contract `rng/v1`.** Algorithm `mdl-random36/v1` (the existing
generator; no second RNG); both unsigned 36-bit words; `draws` (counted in
the generator state host-side; an explicit reseed counts as one call;
invisible to MDL; decided in because it costs nothing and catches a
diverging draw path); seed provenance (START's `<RANDOM <CHTYPE <DSKDATE>
FIX>>`, observation index 2, DSKDATE computed host-side = 10438660480 under
the fixed clock, equal to the native first RANDOM argument). Restore never
writes the words into a session and never reseeds from the wall clock.

**Clock modes.** Recording logs `(seconds, micros, turn)` per read, turn =
completed READSTRING calls. Replaying serves the log; strict
`exn:fail:mdl-clock-replay` on an extra read, a turn mismatch (order
divergence) and, at `mdl-clock-finish-replay!`, unread observations.
Finishing switches the same clock to resumed: `base (last observation) +
max(0, wall − wall_at_resume)`, wall injected. All logging modes keep
logging, so a restored game can be saved again (tested).

**Input log.** One `(raw, reason)` per completed READSTRING, captured inside
READSTRING, so it is exactly what MDL consumed (READSTRING never peeks;
READCHR is not implemented and its game uses are commented out). The
restore input port serves exactly those characters; a read past them is a
strict replay error and never reads the live port (tested: the live input
is untouched).

**Save boundary and how it is detected.** At a READSTRING entry the
observer receives the dynamic local frames, the activation kinds, the
buffer, the channel and the stop set. A checkpoint is refused
(`exn:fail:replay-save-refused`) unless: the session is live and no MDL
ERROR was signalled; no end of input was consumed; the previous READSTRING
ended at its stop character (not a full buffer); and (Zork profile) the
frames are exactly RDCOM's REPEAT frame `{CV VVAL}`, RDCOM's frame (its 11
locals) with `IVEC` FALSE, and the top-level frame, with activation kinds
`(prog)`; the buffer is `,INBUF`, the channel `,INCHAN`, the stops
READER-STRING (ESC CR LF); `,REP` is `,RDCOM`; and `<1 ,ORPHANS>` is FALSE.
YES/NO's READSTRING has YES/NO's and FINISH's frames on top; the echo
room's and `COMMAND`'s readers are not RDCOM's top-level call. Prompt
objects are valid only during the host's callback. A save request is
synchronous with the prompt (the host's callback at the READSTRING entry);
no arbitrary continuation is captured.

**Format `mdl-zork-replay/v1`.** Canonical JSON (ASCII, sorted keys, no
whitespace, integers only, canonical escapes), parsed only by the strict
parser in `mdl/replay.rkt` (no `read`, `eval`, `fasl`, `racket/serialize`);
the bytes must equal the canonical re-encoding. Limits: 4 MiB, 100 000
input units, 400 000 observations, 64 KiB strings, depth 8, 19-digit
integers, 256 state entries. Fields: `format`, `profile`
(`zork-1977-run.mud/v1`), `rng` {`version`, `algorithm`, `state`, `draws`,
`seed`}, `source` {`upstream`, `entry_file`, `entry_function`, `files`
[[path, sha256]…] (the 13 files the load actually read), `manifest_sha256`},
`runtime` {`commit`, `racket`} (diagnostic only), `clock` {`time_zone`,
`boot_clock`}, `observations` [[s, µs, turn]…], `input` [[raw, reason]…],
`verification` {`input_units`, `observations`, `moves`, `state` (34 fields:
the S6 troll checkpoint fields plus clock events, lamp, deaths, INTIME,
PLAYED-TIME, PARSE-WON, ORPHANS OFLAG, DIVERT-CNT/AMT, logical ledger used
and capacity), `state_sha256`, `transcript_bytes`, `transcript_sha256`},
`checksum` (SHA-256 of the canonical encoding without `checksum`). Rejected
before any session: oversize, non-canonical, format/RNG version or
algorithm, checksum, schema, profile, upstream SHAs or manifest hash
recomputed from the files on disk. Reading the verification state is
checked not to perturb the session (RNG and storage ledger unchanged).

**Restore.** Fresh session; replaying clock; output captured only; every
replayed unit compared with its log entry; at the READSTRING entry after the
last unit: input fully consumed, save boundary holds, RNG words, draws,
MOVES, state (differing fields named), transcript length and digest, clock
log fully consumed. Any failure raises `exn:fail:replay-restore` (stage
`format`/`checksum`/`schema`/`profile`/`provenance`/`boot`/`replay`/
`verification`); the fresh session is dropped. Then resumed clock, live
output, live input, in the same call.

## Results (`make test-m4-replay-persistence`, exit 0, 2 min 06 s)

| | Regression | Result |
|---|---|---|
| 1 | recorded uninterrupted run (22 commands, checkpoints at turns 0/13/16/22) | output = native T1 byte for byte (D1 only); end state = native end checkpoint 22; all 23 RDCOM prompts saveable |
| a | save before the first `kill troll with sword` (turn 13), session ended | checkpoint of the ended 13-command session = the uninterrupted run's turn-13 checkpoint, byte for byte (3 269 bytes); in-process restore from the file verified in 5.5 s; state (34 fields) and RNG words (46916812901, 16566282405; draws 2) equal; pre-save output + post-restore output = native T1; end state = native and = the uninterrupted run's full state |
| a | fresh process (`racket tests/persistence_restore_child.rkt`) | RNG words, draws, state at restore, continuation text, result kind and end state equal the in-process restore |
| b | save after combat (turn 16) | ownership `(LAMP SWORD)`, troll gone (`#FALSE ()`, TROLL-FLAG T, not fighting), axe in the troll, RAW-SCORE/ASCORE 35, glow 0, MOVES 16, = native checkpoint 16; continuation = native |
| c | lamp countdown pending (LNTIN on since `turn on lamp`) | `LNTIN 347 T` at save and after a restore with the wall clock ~30 years later; then it advances per turn exactly as uninterrupted (end states equal) |
| d | RNG continuity | next 12 values from detached snapshots after restore = uninterrupted run |
| e | explicit RANDOM reseed (`tests/replay_checkpoint_test.rkt`; the game never reseeds after START) | a program reseeding with `<RANDOM 12345 67890>` before and after the save point: continuation output, RNG words and draws equal the uninterrupted run |
| f | different wall clocks | restores under wall clocks starting at 1e9 and 2e9 s (both +1 s per read) give identical continuations; `time` reports 1 s then 2 s (play since the save point only) |
| g | tampering | before any session (session counter unchanged): one changed byte → checksum; changed checksum → checksum; truncated → format; format v2, rng/v2, other algorithm → format; manifest hash, upstream SHA, a listed file hash, a changed game file on disk (copy with 77dung.mud edited) → provenance. After replay: first or second RNG word changed → verification ("RANDOM state words"); missing / extra / turn-moved observation → replay ("extra clock read" / "missing clock read" / "order diverged"); fast suite also: reordered values, draws, MOVES, transcript length, an input unit, an input overrun. Different runtime commit and Racket version → accepted, identical continuation |
| h | side effects | post-restore live output is only the post-save text (concatenations above); no file write or delete in any run (guard), temporary cwd empty, game directory manifest unchanged |
| i | independence | a restored game waiting at its prompt on a pipe, then a failed restore (verification) and a second restore of the same checkpoint run to completion; the waiting game then continues = native, end state = uninterrupted; second restore output identical |
| — | save boundary in the game | refused after `Kill what?` (orphan pending), at `quit`'s YES/NO, after a 101-character line (pending input); allowed at the other prompts; a save after the YES/NO round trip (RESET of INCHAN) restores and continues exactly |
| j | replay cost | boot to the first prompt 6.0 s; 100 commands 6.9 s; **0.84–0.87 s per 100 commands** (three runs); checkpoint of 100 commands 5 418 bytes |

Nothing failed to reproduce. The GC interrupt question is only partly
answered: no logical collection or DIVERT-AGC occurred in these scenarios
(DIVERT-CNT 0, ledger below capacity), so reproduction across an explicit
`<GC>` (whose reclaimed count depends on host weak-box liveness) is not
demonstrated; the ledger and DIVERT counters are in the verification state,
so a divergence would fail a restore rather than pass silently.

## Commands (local, sequential; exit status)

| Command | Exit | Notes |
|---|---|---|
| `make test` (sandbox) | 2 | 3/4507 failures: the known sandbox `/tmp` failures (loader_test, declaration_test, percent_read_test: `make-directory /tmp/…: Read-only file system`) |
| `make test` (outside the sandbox) | racket 0 (4659 tests passed); python step needs `PYTHONPATH` | `/usr/bin/python3: No module named pytest` without it |
| `PYTHONPATH=.sandbox-pydeps/lib make test-python` | 0 | 68 passed, 1 deselected |
| `make test-historical` (outside the sandbox; inside: `/tmp` read-only) | 0 | |
| `make test-m3-session` | 0 | 85 tests |
| `make test-m3-launcher` | 0 | 57 tests |
| `make test-m4-troll-combat` | 0 | 23 prefixes |
| `make test-m4-replay-persistence` | 0 | output above |
| `racket tests/replay_clock_test.rkt`, `racket tests/replay_checkpoint_test.rkt` | 0 | also inside `make test` |

Mutation checks: making the verifier skip the RNG word comparison makes the
fast suite fail (`modified RNG words` → `accepted`, expected `verification`)
and the PoC fail (`modified first RNG word` → `accepted`); disabling the
replaying clock's turn check makes `replay_clock_test` and the
`moved to another turn` case fail. Both mutations reverted (no diff).

After the independent review (finding L1) three more verifier mutants were
checked against `tests/replay_checkpoint_test.rkt`, each reverted after:
dropping the `state_sha256` comparison → the `state_sha256`-only tamper is
`accepted` (test fails); dropping the `state` map comparison → the
`state`-only tamper is `accepted` (fails); dropping the transcript digest
comparison → the reordered-observation case is `accepted` (fails first; the
explicit reseed at turn 3 equalises the RNG words, so only the transcript
digest catches it), and the `transcript_sha256`-only tamper would fail too.

## Review fixes (independent review of `26a88ed`)

| Finding | Fix | Test (failing before, passing after) |
|---|---|---|
| M1 quadratic schema check, O(n²) replay lookup | input and observation counts computed once; replay compares units through a vector | validating a crafted 3.6 MB checkpoint (100 000 input units, 300 000 observations): timed out at 30 s before, 1.7 s after (whole fast suite 5 s) |
| M2 unbounded, duplicated `source.files` | at most 64 entries, no duplicate paths (schema); the listed names must equal the profile's game files before any file is read (provenance) | duplicate entry and 40 000 copies: `accepted` before (40 000 copies hashed in 3.0 s), `schema` after (1.8 s, all parsing, nothing hashed); 65 entries → `schema`; an unexpected `missing.mud` → `provenance` "not the profile's game files", no file read |
| M3 wrong-typed fields escaped as contract errors | the schema check and the whole validation convert any other failure into `exn:fail:replay-restore` | `input_units: "x"` raised `exn:fail:contract` (`=`) before; 20 wrong-typed fields → `schema` after, no session created |
| L1 surviving verifier mutants | tamper tests for `transcript_sha256`, `state`, `state_sha256` alone | mutants above |
| L2 host callback raising into the game | `on-prompt`/`on-restored` failures are caught at the callback boundary and returned as `replay-result-host-errors`; `replay-prompt-try-checkpoint` returns the refusal instead of raising | a refused `replay-prompt-checkpoint` in `on-prompt` no longer ends the game: it runs to its own QUIT with all 7 inputs read, one host error reported |
| L3 resumed clock could go backwards | monotonic: never below the last value served | a wall clock 100→105→103→90→104→110 gives 1005, 1005, 1005, 1005, 1010 (failed before at 103) |
| L3/L4/L5 wording | verification order (clock log last), integrity-only checksum, "selected verification state" in ADR-0061 and SEMANTICS | — |

## Security and licensing

No MDL primitive, game source, game global or upstream file changed. No new
file write path: the engine runs every session under a no-write/no-network
guard; tests write checkpoints under `$TMPDIR` themselves. Checkpoints are
untrusted input: size-bounded before parsing, parsed by a strict canonical
parser, schema-checked, checksummed, provenance-checked; listed game paths
must stay inside the source root. No GPL code copied.

## Trust model

The checksum is integrity only, not authentication. A player can edit and
reseal the input or clock log, including the clock observations that choose
START's RANDOM seed (so a seed can be chosen). Verification guarantees only
that the restored state is what the real game produces from the recorded
inputs. The verification state is a selected state (34 fields); object
positions beyond those fields, room flags and most globals are covered only
by the transcript digest and by the reconstruction itself.

## Limitations

- After a restore nothing is printed: the save point's `>` prompt belongs
  to the replayed (discarded) transcript, so a player-facing host must show
  its own notice or re-show the prompt (review L7).
- Saves are taken synchronously in the host's prompt callback; an
  asynchronous "save now" request from another thread is not offered yet.
- The transcript is kept in memory to digest it (linear in play length).
- Restore cost is boot (6 s) + 0.85 s per 100 commands, linear in history.
- `time_zone` `local` depends on the host zone: a restore on a host in
  another zone changes DSKDATE and fails verification (never silently).
- The OFLAG rule is conservative (OFLAG stays set after an unanswerable
  orphan reply until a later successful parse).
- Checkpoints after a consumed end of input or a host break are refused.
- The GC reproduction caveat above; the GC interrupt's elapsed-time
  argument (ADR-0052 note) is unaffected and unused by the game.

## Recommendation for the player-facing SAVE/LOAD slice (WP4.7)

1. Keep MDL's SAVE/RESTORE strict; add host commands in the launcher (for
   example a `--save-dir` plus meta-input such as `#save NAME` read by the
   host before RDCOM sees the line, honoured only at a saveable prompt).
2. Named slots only (`[a-z0-9-]{1,32}`), stored in one host-chosen directory;
   no player-controlled paths; files written atomically (temp file in the
   same directory, fsync, rename) and checksummed (the format already is).
3. This needs an accepted amendment of ADR-0055's no-file policy for the
   launcher only (MDL code keeps no file access), and the launcher notice
   must change accordingly.
4. The checksum does not authenticate: a slot file can be edited and
   resealed (inputs, clock observations and therefore the RANDOM seed
   included). If save tampering matters, add host-side authentication
   (for example an HMAC with a host-held key) as its own decision.
5. Acceptance scenarios: save/quit/load in a fresh process continuing a
   native transcript (as here); corrupted, truncated, foreign-version and
   foreign-source slots rejected with a message and no state change; slot
   overwrite is atomic under a crash; saving at a refused prompt explains
   why; restore time measured for long games (if too slow: verified
   intermediate snapshots, ADR-0061 Option A).
6. Native SAVE/RESTORE compatibility (DO-SAVE/DO-RESTORE, the 20-minute
   rule, continuation semantics) stays a separate decision.
