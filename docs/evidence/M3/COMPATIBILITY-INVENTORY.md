# M3 source compatibility inventory

This is a diagnostic inventory, not a claim that every lexical occurrence
is exercised by the unchanged loader or game. The executable loader is
the authority for the next implementation dependency.

Updated 2026-11-23 for the branch stack ending at PR #141
(`feat/m3-interactive-io`, `45c387f`). `main` (`fdf48e4`) still stops at
`77rooms.mud:101`, so every row from that line onward (including the
unmarked ones, which landed on the umbrella `feat/m3-logical-gc`) and every
row marked "Branch" is not on `main`. Scoped gate results are in
[STATUS](../../STATUS.md).

| Source location | Context | Expected MDL behavior | Current support / dependency |
|---|---|---|---|
| `77act1.mud:78`, `LEAF-PILE` `#DECL ((PV) <VECTOR [3 ANY]> ...)` | Definition metadata, validated while the file loads | A VECTOR declaration with exactly three ANY slots | Implemented and tested in earlier M3 slice |
| `81tell-repl.mud:46`, `READST` | Function body, not called during source loading or on the tested path | `READSTRING` reads input with a newline terminator built by `%<STRING <ASCII 10>>` | Read-time substitution supported. Branch: READSTRING implemented for the RDCOM/YES-NO form (explicit channel, STRING stop; ADR-0050); READST's own call is not exercised |
| `77act1.mud:492`, nested call in action code | Runtime action path, not exercised by source loading | `RANDOM` and indexing feed an exit decision | Random/event issue #71; seed and call order require reference probes |
| `77np.mud:131`, `SP` function body | Parser runtime | `LEX` tokenizes original input | Branch: original `LEX` runs via RDCOM for the six house-boot commands (scoped INTERACTIVE PASS, `make test-m3-interactive`); other inputs unverified |
| `77rooms.mud:101`, `77rooms.mud:804` | Source load | GC event and BLOCK lookup list | Implemented and tested; logical GC accounting is bounded to tracked LIST/VECTOR/UVECTOR allocations |
| `77rooms.mud:1249`, `77dung.mud:213` | Source load | IUVECTOR, CHUTYPE and empty UTYPE LOSE | Implemented and tested; REST views share a UTYPE header, as confirmed by pinned Confusion |
| `77dung.mud:148`, `77dung.mud:2463` | Source load | `#NEXIT` STRING literal and SPNAME | Implemented and tested; SPNAME may copy to enforce immutability |
| `81tell-repl.mud:57`, `77rooms.mud:286` | START path | GETTIMEDATE and PRINTSTRING with terminal CHANNEL | Implemented and tested for the source-reached subset; clock is host time |
| `77rooms.mud:286` | START path | CRLF newline and T return | Implemented and focused test passing |
| `77rooms.mud:291` | START path | 36-bit session-owned RANDOM with deterministic seeding | Implemented on issue #108 follow-up branch; native negative-seed range deviation documented |
| `77rooms.mud:297` | CONTIN path | BACK on terminal CHANNEL's backing storage | Implemented on issue #110 follow-up branch with manual and native probes |
| `77rooms.mud:298`, `77patch.mud:38` | CONTIN and original startup prelude | TENEX? is set via GETSYS before START | Branch: the faithful `<FLOAD "77loadall.mud">` + `<SAVE-IT>` path runs GETSYS and passes 298; only a direct START call (test-m3-start-back XFAIL) still stops here |
| `77rooms.mud:598-616` (RDCOM), `81tell-repl.mud:46` | Interactive path | READSTRING plus original LEX/parser | Branch: scoped INITIALIZED/INTERACTIVE PASS for the six house-boot commands via the host loop (S7); `!` in input, default channel, FIX stop and EOF routine are strict errors; SMOKE_PARITY NOT RUN (needs the fixed clock, #135) |
| `77rooms.mud:16-26` (SAVE-IT) | Startup | ON "IPC", SAVE, INT-LEVEL | Branch: ON registers IPC without a source (ADR-0047); SAVE is an in-session record returning `"SAVED"` (ADR-0048); RESTORE strict |
| `77rooms.mud:301-303` (CONTIN) | Startup | GVAL REP, RESET of INCHAN | Branch: inert default REP SUBR (ADR-0049); RESET implemented (ADR-0050) |
| `77rooms.mud:598-616`, `675-680` | Game loop | PRINC/PRIN1 of STRING, CHARACTER, FIX, `,NULL` | Branch: implemented without line breaking (ADR-0050) |
| `77rooms.mud:521-525` | Room description | `<PROB 80>` via RANDOM seeded from DSKDATE | Branch: works; text varies with the host clock until a session-owned fixed clock exists (#135) |
| `77rooms.mud:220` (HANDLE), `33-50`, `279`, `316-353` (QUIT/FINISH/RECORD paths) | ERROR handler, game end | MEMBER, QUIT, OPEN/CLOSE | Branch: MEMBER (#145), QUIT as a session outcome and OPEN under the no-file policy (#147) implemented; the quit path FINISH → RECORD → QUIT runs byte-identical to native. CLOSE unsupported (not reached). HANDLE stops at unsupported PRINT (`77rooms.mud:251`) before QUIT |

Locked source revision: mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
