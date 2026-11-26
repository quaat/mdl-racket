# M4 R5 maintainer record — DRAFT (not an acceptance)

This is a draft for the maintainer to complete, prepared under the ADR-0063
amendment (2026-11-26). It is **not** cited by
`tests/scenarios/m4-manifest.json` and does not satisfy R5. Only the
maintainer may turn it into the accepted record: copy it to its final path,
fill every field from a reviewed commit, change the acceptance line to
`ACCEPTED`, and set `maintainer_record` in the manifest in the same commit.
`scripts/m4_check.py` checks only the form of that record, never its truth.

Maintainer acceptance: PENDING
Accepted by: (maintainer)
Date: (YYYY-MM-DD)
Reviewed commit: (40-hex SHA of the reviewed main commit)
Source pins: (mit_zork and mdlzork SHAs from sources.lock.json; mdli SHA-256)

## Accepted semantic deviations

One entry per deviation from historical MDL or from the pinned reference
that M4 relies on, each with its ADR and evidence link. To be compiled from
DECISIONS.md and SEMANTICS.md at the reviewed commit (for example: ADR-0048
SAVE record; ADR-0055 OPEN policy; the attached-declaration amendment (#196);
ADR-0059 MAX; ADR-0061 replay persistence; MANIFEST enforcement; the error
reporting difference).

## Evidence

The `make m4-accept` report for the reviewed commit, its CI run, and the
evidence records each deviation cites.

## Scope and consequences

What each deviation changes for the game and for general MDL programs.

## Remaining limitations

Known gaps that remain after M4 (for example full MDL SAVE/RESTORE
continuation semantics, general error compatibility, the L0–L5 conformance
backlog).
