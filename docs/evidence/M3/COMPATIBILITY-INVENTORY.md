# M3 source compatibility inventory

This is a diagnostic inventory, not a claim that every lexical occurrence
is exercised by the unchanged loader or game. The executable loader is
the authority for the next implementation dependency.

| Source location | Context | Expected MDL behavior | Current support / dependency |
|---|---|---|---|
| `77act1.mud:78`, `LEAF-PILE` `#DECL ((PV) <VECTOR [3 ANY]> ...)` | Definition metadata, validated while the file loads | A VECTOR declaration with exactly three ANY slots | Implemented and tested in earlier M3 slice |
| `81tell-repl.mud:46`, `READST` | Function body, not called during source loading | `READSTRING` reads input with a newline terminator built by `%<STRING <ASCII 10>>` | Read-time substitution supported; default CHANNEL metadata implemented; `READSTRING` remains unsupported |
| `77act1.mud:492`, nested call in action code | Runtime action path, not exercised by source loading | `RANDOM` and indexing feed an exit decision | Random/event issue #71; seed and call order require reference probes |
| `77np.mud:131`, `SP` function body | Parser runtime, source definition loaded but not called | `LEX` tokenizes original input | Original `LEX` definition loaded; interactive invocation unverified |
| `77rooms.mud:101`, `77rooms.mud:804` | Source load | GC event and BLOCK lookup list | Implemented and tested; logical GC accounting is bounded to tracked LIST/VECTOR/UVECTOR allocations |
| `77rooms.mud:1249`, `77dung.mud:213` | Source load | IUVECTOR, CHUTYPE and empty UTYPE LOSE | Implemented and tested; REST views share a UTYPE header, as confirmed by pinned Confusion |
| `77dung.mud:148`, `77dung.mud:2463` | Source load | `#NEXIT` STRING literal and SPNAME | Implemented and tested; SPNAME may copy to enforce immutability |
| `81tell-repl.mud:57`, `77rooms.mud:286` | START path | GETTIMEDATE and PRINTSTRING with terminal CHANNEL | Implemented and tested for the source-reached subset; clock is host time |
| `77rooms.mud:286` | START path | CRLF newline and T return | Implemented and focused test passing |
| `77rooms.mud:291` | START path | 36-bit session-owned RANDOM with deterministic seeding | Implemented on issue #108 follow-up branch; native negative-seed range deviation documented |
| `77rooms.mud:297` | CONTIN path | BACK on terminal CHANNEL's backing storage | First actual failure after RANDOM; source-backed semantics and reference probes required |
| `81tell-repl.mud:46` | Interactive path | READSTRING plus original LEX/parser | Not implemented or verified; source definition loaded only |

Locked source revision: mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
