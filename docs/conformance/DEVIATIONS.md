# Manual and reference differences

The accepted contracts are maintained in [SEMANTICS](../SEMANTICS.md) and
[DECISIONS](../DECISIONS.md). This ledger records the distinctions
encountered while building the L0 corpus.

| Scope | Manual | Observation and treatment |
| --- | --- | --- |
| DECL? structured mismatch, §14.7.4 | Empty FALSE in the example | Pinned Confusion and Racket carry the offending element and type pattern in the FALSE payload. The fixture retains the printed manual result and asserts the accepted diagnostic payload under ADR-0023 and M2 D3. |
| Confusion floats and WORD printing, §§2.4, 18.3 | The transcripts use fewer digits | Native output records the exact formatting. The Racket suite asserts typed values and explicit program output. |
| GC, §22.5 | Returns a FIX count of words reclaimed | Racket implements a logical storage count. The pinned Confusion probe gives TYPE ATOM; the corpus asserts the documented return type without requiring a historical reclamation count. |
| TIME, §23.1 | Returns CPU time in seconds | Racket returns a session-owned FLOAT call count per #170. The corpus asserts eager evaluation and result type. |
| SQRT, §3.4 | The 3–4–5 example returns FLOAT 5.0 | Pinned Confusion does not bind SQRT. Racket's specific missing-operator diagnostics are tracked. A later implementation needs math evidence beyond this interpreter. |
| SETLOC, §12.3.2 | Writes to a locative | Pinned Confusion does not bind SETLOC. Racket's strict missing-operator diagnostics are tracked. |
| %% reader macro, §17.1.1 | Evaluates during READ and discards its result | Confusion explicitly rejects it. Racket currently rejects it through the loader reader and the module compiler, with separate expectations. |
| PUT deletion, §13.1.3 | Return the prior associated value or FALSE | ADR-0023 retains Confusion's observed item return for existing PUT. Explicit PUTPROP behavior is a pending decision in #179. |
| OPEN and SAVE, §§11.2.1, 11.6.1 | Historical channels/files and saved images | Existing virtual file policy and in-session save record remain the accepted project contracts under ADR-0055 and ADR-0048. |

Source for native observations and exact program inputs is the
[L0 probe record](../evidence/L0/native-examples.json).
