# M4 S10 (issue #171) help / info: handoff (WIP, 2026-11-24)

> **Superseded (2026-11-25):** the work was resumed and completed; see
> [S10-HELP-INFO.md](S10-HELP-INFO.md). This file is kept as the record of the
> interruption only.

Branch `feat/m4-help-info-allowlist` (from main `6b826d5`), worktree
`.claude/worktrees/m4-helpinfo`. Work stopped early on the coordinator's
request (usage limit). Gate state: **NOT RUN**. No runtime code changed yet.

## Done

- Native probes (pinned Confusion, disposable game copies under `$TMPDIR`):
  - `scripts/probe_file_read_reference.py` → `docs/evidence/M4/file-read-probe.json`
    (53 cases: OPEN "READ" forms, FILE-LENGTH, file READSTRING by count / stop
    STRING / to EOF / after EOF, `!` and CR LF in files, PRINTSTRING with a
    count, CLOSE value and double CLOSE, FILE-TO-TTY, `help`/`info`/`?` in game).
  - `scripts/probe_help_info_scenario_reference.py` + `tests/scenarios/help-info.json`
    → `docs/evidence/M4/help-info-reference.json` (T1, T1b, X1, P00–P07,
    D00–D07; commands `north help east info "open window" ? west score`).
  - `docs/evidence/M4/HELP-INFO-REFERENCE.md`: all findings written up.
- Key native findings: FILE-LENGTH is in characters (= bytes: 4274, 1527);
  READSTRING FIX arg = exact count; stop STRING consumed, not stored; the EOF
  read returns the partial count and sets CHANNEL element 11 to 1; any read
  after EOF is a host error `Unexpected EOF`; `!` is an escape in file input
  too; CLOSE returns the CHANNEL, double CLOSE returns it again; CHANNEL slots
  recorded (element 10 is the absolute host directory natively); no case
  folding; device ignored in the file spec; the help text has two mid-line
  `>`, so the runner needs a line-initial prompt split for this scenario.

## Verified (commands actually run)

| Command | Exit |
|---|---|
| `python3 -I scripts/probe_file_read_reference.py docs/evidence/M4/file-read-probe.json` | 0 |
| `python3 -I scripts/probe_help_info_scenario_reference.py docs/evidence/M4/help-info-reference.json` | 0 |
| same to `$TMPDIR/help-info-reference-2.json` (second capture; transcripts, stdout hashes, checkpoints identical) | 0 |
| `sha256sum .cache/build/confusion_patched/mdli` before/after | `6df359f6…b789` unchanged |

`make test`, the `make test-m4-*` targets and `make m3-check` were **not run**
on this branch.

## Not yet done (from the brief)

1. ADR-0055 amendment (quote the decision) and SEMANTICS section (OPEN "READ"
   allowlist, FILE-LENGTH, file READSTRING incl. FIX count and EOF, CLOSE,
   PRINTSTRING count; deviations: host path not exposed in element 10, count
   > buffer / negative count strict, FILE-LENGTH on a non-file strict, CLOSE
   of a terminal channel strict).
2. Failing tests first, then implementation. Planned design:
   - core.rkt: grant struct `mdl-read-only-file` (name1 name2 device directory
     sha256 size), atom-space fields for grants + host reader; OPEN "READ"
     matches all four names exactly (string=?), else the existing strict error
     (message keeps the `mode "READ" is not supported` prefix; no file access
     before the match); sha256 + size check at open (strict on mismatch);
     whole content in memory, channel served from an immutable byte string;
     host-channel gains a `file` record (port, closed?) — file READSTRING never
     flushes and never calls the ADR-0061 observer; after-EOF read and
     closed-channel read are plain strict errors (NOT
     `exn:fail:mdl-input-exhausted`); FILE-LENGTH, CLOSE as probed; RESET on a
     file channel strict; storage added to `channel-storages` (TOP refused).
   - loader.rkt: `make-mdl-session #:read-only-files` (default '()); reader
     resolves `root/directory/name1.name2`, rejects links (dir and file),
     checks size before reading, compares `port-file-identity` with the
     path's own (as-link) identity; `mdl-session-file-channels` introspection.
   - zork/game-files.rkt: the two pinned grants; pass them from zork/main.rkt,
     replay profile (new field `read-only-files`; update
     tests/replay_checkpoint_test.rkt), zork/persistence.rkt, the runner.
   - runner: `#:prompt-split 'line-initial` option; guard: no file channel
     left open.
3. Tests: tests/file_read_test.rkt (fixture dir + pinned files, security
   guard, observer not called for file reads), replay record/restore across
   `help`, tests/historical_help_info_test.rkt + Makefile `test-m4-help-info`
   + CI step after strange-passage; update F3 in
   tests/historical_m4_frontier_test.rkt and tests/quit_open_test.rkt
   expectations; GAMEPLAY-FAILURE-INVENTORY (INV-05 fixed); operator-head
   sweep and test_sweep_operator_heads.py (CLOSE, FILE-LENGTH); function-type
   probe re-record for new builtins.
4. Mutation table, S10-HELP-INFO.md, STATUS row, full verification.

## Known problems / open questions

- Native CLOSE of a closed channel succeeds; mirroring it is planned (no
  decision needed). Native crashes (FILE-LENGTH of a STRING, negative count)
  become strict errors (recorded deviation).
- Natively an absent allowlisted file gives `File not found.`; planned: strict
  error (missing pinned file = host setup problem), consistent with "no
  FALSE-returning denial".

## Next step

Write the ADR-0055 amendment and SEMANTICS section, then tests/file_read_test.rkt
(failing), then the core/loader implementation above.
