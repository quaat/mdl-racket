# M3 NTH declaration repetition — issue #96

**Scoped slice: PASS on `feat/m3-nth-declaration`; formal M3 gate:
INCOMPLETE.** Base main commit `b95852efc3967acabee0f97b2ce04f56d27300b3`.
Locked source commits: MIT Zork
`d94501340842e006791fce0757dc0043b8ec8916`, mdlzork/Confusion
`bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`.

The [MDL manual §14.1](https://mdl-language.readthedocs.io/en/latest/14-data-type-declarations/)
defines `[n Pattern ...]` as a positive-count repeated Pattern sequence.
The runtime now normalizes that count without expanding it, consumes one
required element at a time, and preserves ordinary suffix and trailing REST
behavior. Zero/negative counts and an empty Pattern sequence raise errors.
Attached FUNCTION declarations, explicit `DECL?`, GDECL matching, and
NEWTYPE's stored Pattern use the same matcher. A 34,359,738,367-count test
against an empty VECTOR returns FALSE promptly without large allocation.

The [13 clean native cases](nth-decl-reference.json) confirm counts,
multi-Pattern order, prefix/suffix, REST, mismatches, short values and extra
undeclared elements. The probe command
`.venv/bin/python -m scripts.mdl_probe --cases docs/evidence/M3/nth-decl-cases.json --output docs/evidence/M3/nth-decl-reference.json`
exited **0**. The corresponding command with
`nth-decl-errors-cases.json` and `nth-decl-errors-reference.json` exited
**1 as expected** because each of four cases enters the native error level:
non-positive count `BAD-TYPE-SPECIFICATION4`, empty sequence
`VECTOR-LESS-THAN-2-ELEMENTS`, and explicit `DECL?` with `ANY`
`BAD-TYPE-SPECIFICATION1`. Each case used one local Confusion process,
expression plus `<QUIT>`, no game input or RNG. Rebuilt native binary SHA256:
`bd70657059954cbb706fe93e8aceb14c64a58f51f227cfa4e69841d7df9ef340`.
Confusion accepts a two-element vector in an attached `[3 ANY]` declaration;
the manual and this runtime require three. This is an explicit deviation.

`TMPDIR=/tmp raco test tests/nth_decl_test.rkt` exited **1 before the
implementation** with `unsupported declaration pattern NTH`. After the
initial matcher change it passed, while two old D3 assertions still expected
NTH to fail; those assertions were updated. A NEWTYPE NTH regression then
failed **1** on shape validation and passed after enabling the same syntax
there. Focused `TMPDIR=/tmp raco test tests/nth_decl_test.rkt
tests/newtype_decl_test.rkt tests/declaration_pattern_test.rkt` exited **0**
with 117 checks. `TMPDIR=/tmp make test` exited **0** with **1,219 Racket
checks and 23 Python tests**. `TMPDIR=/tmp make m2-check` exited **0**:
historical G3 58 assertions, native primitive probe 12 expressions, and
five-turn reference capture. `make m3-source-progress` exited **0 as a
partial-progress measurement** after verifying locked source commits and 36
parsed historical text files. Its underlying loader exited **1** after
**233 completed original forms, zero skipped**, up 45 from 188. The first
failure is `77act1.mud` expression 55, line 740, unknown declaration type
`PRSOBJ`; see [source summary](source-progress-nth-decl.json) and
[raw report](source-load-nth-decl.json). The source report records SHA256 of
each encountered file, including `77act1.mud`
`fd1bde71f7d356ccd28c3fd73236e1d0ec2cb6a001d4be816a3d2011aecd0ee8`.

Supported: NTH in LIST/VECTOR/UVECTOR/TUPLE structured Patterns and
NEWTYPE's nested PRIMTYPE form. Unsupported: OPT, arbitrary READ table
changes, and later source constructs. No source under `.cache/upstream/`,
GPLv3 reference code, public license, or network service changed. The
local interpreter remains incomplete, with no exposed production REPL.
Full source load, initialization, interactive input, smoke parity and
gameplay are unverified. Next: [issue #98](https://github.com/quaat/mdl-racket/issues/98)
must investigate the undeclared `PRSOBJ` atom against the manual and native
reference before modifying declaration behavior.

Reproduce after `make reference-build`:

```bash
TMPDIR=/tmp raco test tests/nth_decl_test.rkt tests/newtype_decl_test.rkt tests/declaration_pattern_test.rkt
TMPDIR=/tmp make test
TMPDIR=/tmp make m2-check
make m3-source-progress
git diff --check
```
