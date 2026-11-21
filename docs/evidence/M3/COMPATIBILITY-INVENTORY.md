# M3 source compatibility inventory

This is a diagnostic inventory, not a claim that every lexical occurrence
is exercised by the unchanged loader or game. The executable loader is
the authority for the next implementation dependency.

| Source location | Context | Expected MDL behavior | Current support / dependency |
|---|---|---|---|
| `77act1.mud:78`, `LEAF-PILE` `#DECL ((PV) <VECTOR [3 ANY]> ...)` | Definition metadata, validated while the file loads | A VECTOR declaration with exactly three ANY slots | First actual failure after issue #94: NTH repetition Pattern unsupported; probe before implementation |
| `81tell-repl.mud:46`, `READST` | Function body, not called during source loading | `READSTRING` reads input with a newline terminator built by `%<STRING <ASCII 10>>` | Read-time substitution supported in issue #94; `READSTRING` execution and channel model still unsupported |
| `77act1.mud:492`, nested call in action code | Runtime action path, not exercised by source loading | `RANDOM` and indexing feed an exit decision | Random/event issue #71; seed and call order require reference probes |
| `77np.mud:131`, `SP` function body | Parser runtime, not yet loaded in the current prefix | `LEX` tokenizes original input | `LEX` unsupported; original parser integration required before gameplay |

Locked source revision: mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.
