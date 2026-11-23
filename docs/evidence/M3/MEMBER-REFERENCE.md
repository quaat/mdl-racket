# MEMBER: pinned Confusion reference observations

Read-only reference investigation, 2026-11-23. Nothing here is runtime code. No
implementation, test, or upstream file was changed.

| Item | Value |
| --- | --- |
| Repository commit probed from | `45c387f` (branch `evidence/m3-session-probes`) |
| Interpreter | `.cache/build/confusion_patched/mdli`, sha256 `6df359f676862b3468790fcd91448ccd66aa4e124bf9301bf221dd216a28b789` (checked by the script before the run and again before every case) |
| Upstream | mdlzork `bdcd4a671b4707f7acad5a2e3aa3cc9f51bf19b3`, mit_zork `d94501340842e006791fce0757dc0043b8ec8916` (`sources.lock.json`) |
| Script | `docs/evidence/M3/member-bang-probe.py` (suite `member`) |
| Raw evidence | `docs/evidence/M3/member-probe.json` (58 cases, every exit status 0) |
| RNG / clock | not relevant; no fixed clock used for this suite |

## Method

```
python3 -I docs/evidence/M3/member-bang-probe.py member docs/evidence/M3/member-probe.json
```

Exit status 0. The run was repeated twice with identical results. Each case runs
one `mdli` process with no arguments. The cwd is a fresh empty directory under
`$TMPDIR/mb-probe-work/`. The case's forms go on a stdin pipe, followed by
`<QUIT>`. Nothing runs in `.cache/upstream`, and no case created or changed a
file. The JSON stores, for each case, the exact input (and hex), the raw
stdout and stderr, the exit status, the checked SHA, and the output after the
`LISTENING-AT-LEVEL 1 PROCESS 1` banner. Every error case is a separate
process, so a `LISTENING-AT-LEVEL 2` cannot hide a later result.

Confusion's C++ source (`.cache/build/confusion_patched/macros.cpp`,
`mdl_builtin_eval_member` and `mdl_memmem`) was read to choose the probes. It was
not copied. Every claim below rests on an observed output.

## Manual

MDL manual §8.2.2 "Equality and Membership"
(<https://mdl-language.readthedocs.io/en/latest/08-truth/>):
- `<MEMBER object:any structured>` "runs down *structured* from first to last
  element, comparing each element of *structured* with *object*. If it finds an
  element of *structured* which is `=?` to *object*, it returns
  `<REST structured i>` (which is of `TYPE` `<PRIMTYPE structured>`) …
  If no element of *structured* is `=?` to *object*, `MEMBER` returns
  `#FALSE ()`."
- "If *object* and *structured* are of `PRIMTYPE` `STRING` [or `BYTES`],
  `MEMBER` does a substring search." Example: `<MEMBER "PART" "SUM OF PARTS">`
  gives `"PARTS"`.
- `MEMQ` "is exactly the same as `MEMBER`, except that the comparison test is
  `==?`."

## Call-site inventory (December 1977 sources, `patched_confusion/`)

There are 20 `MEMBER` calls in total. Other `.mud` files have none.

| Site | Enclosing DEFINE | Form | Shape |
| --- | --- | --- | --- |
| 77act1.mud:16 | ILO | `<MEMBER "<FLUSH-ME>" .BODY>` | STRING in STRING (substring) |
| 77act1.mud:17 | ILO | `<MEMBER ,XUNM ,WINNERS>` | STRING in VECTOR of STRING (`=?` element) |
| 77act1.mud:18 | ILO | `<MEMBER .NM1 ,WINNERS>` | STRING in VECTOR of STRING |
| 77act1.mud:19 | ILO | `<MEMBER ,FF .BODY>` | STRING in STRING (FF is a STRING, GDECL 77act1.mud:12) |
| 77act1.mud:1096 | ECHO-ROOM | `<==? <MEMBER "ECHO" <UPPERCASE .B>> .B>` | substring; result identity tested against the haystack (offset 0) |
| 77act2.mud:269 | RBOAT-FUNCTION | `<MEMBER "RIVR" <SPNAME <RID .HERE>>>` | substring in an ATOM PNAME |
| 77act2.mud:497, 550, 757 | BALLOON, PUT-BALLOON, VOLGNOME | `<MEMBER "LEDG" <SPNAME <RID ,HERE>>>` | substring |
| 77act2.mud:511, 562 | RISE-AND-SHINE, DECLINE-AND-FALL | `<SET M <MEMBER "VAIR" <SPNAME <RID .BL>>>>` | substring; the result is kept |
| 77act2.mud:532 | RISE-AND-SHINE | `<SET M <MEMBER "LEDG" <SPNAME <RID .BL>>>>` | substring; the result is kept |
| 77act3.mud:112, 131 | CAKE-FUNCTION | `<MEMBER "ALI" <SPNAME <RID .HERE>>>` | substring |
| 77rooms.mud:33 | SAVE-IT | `<MEMBER <SETG XUNM <XUNAME>> ,WINNERS>` | STRING in VECTOR (only when `<STARTER>` is a FIX > 3; not reached at boot, S5-SAVE-FRONTIER) |
| 77rooms.mud:220 | HANDLE | `<MEMBER ,XUNM ,WINNERS>` | STRING in VECTOR; this is the live ERROR path (S7 INTERACTIVE-FRONTIER D6) |
| 77rooms.mud:349, 380 | DO-SCRIPT, DO-SAVE | `<NOT <MEMBER "GUEST" .UNM>>` | STRING in STRING |
| 77rooms.mud:414 | DO-RESTORE | `<MEMBER ,XUNM ,WINNERS>` | STRING in VECTOR |
| 77rooms.mud:1745 | COMMAND | `<REST <MEMBER "" ,LEXV>>` | empty STRING in VECTOR of STRING views (`=?` element search, **not** substring) |

Data shapes: `WINNERS` is `'["BKD" "TAA" "MARC" "PDL" "MDL"]` with GDECL
`<VECTOR [REST STRING]>` (77rooms.mud:254-256). `LEXV` is
`<IVECTOR 10 '<REST <ISTRING 5> 5>>` (77rooms.mud:1555), a VECTOR of empty
STRING views. The game has no LIST or UVECTOR haystack, no non-STRING needle,
and no empty needle in a STRING haystack.

## Observations (exact output after the banner; `|` separates top-level results)

### Structural search (`=?`)

| Case | Input | Output |
| --- | --- | --- |
| list-hit | `<MEMBER 2 '(1 2 3)>` | `(2 3)` |
| list-miss | `<MEMBER 4 '(1 2 3)>` | `#FALSE ()` |
| list-first-of-duplicates | `<MEMBER 2 '(1 2 3 2 5)>`, `<LENGTH …>` | `(2 3 2 5)` \| `4` |
| list-empty | `<MEMBER 1 ()>` | `#FALSE ()` |
| list-nested-equal | `<MEMBER '(1 2) '(0 (1 2) 3)>` | `((1 2) 3)` |
| list-nested-kind-differs | `<MEMBER '[1 2] '(0 (1 2) 3)>` | `#FALSE ()` |
| list-deep-nested | `<MEMBER '(1 [2 "x"]) '(0 (1 [2 "x"]) 3)>` | `((1 [2 "x"]) 3)` |
| fix-vs-float | `<MEMBER 2 '(1 2.0 3)>`, `<MEMBER 2.0 '(1 2 2.0)>`, `<MEMBER 2.0 '(1 2.0)>` | `#FALSE ()` \| `(2.0000000)` \| `(2.0000000)` |
| atom-element | `<MEMBER FOO '(BAR FOO BAZ)>`, `<MEMBER FOO '(BAR BAZ)>` | `(FOO BAZ)` \| `#FALSE ()` |
| character-element | `<MEMBER !\b '(!\a !\b)>`, `<MEMBER !\B '(!\a !\b)>` | `(!\b)` \| `#FALSE ()` |
| false-element | `<MEMBER <> '(1 #FALSE () 2)>`, `<MEMBER #FALSE (1) '(#FALSE () #FALSE (1) 2)>` | `(#FALSE () 2)` \| `(#FALSE (1) 2)` |
| string-element-list | `<MEMBER "abc" '("x" "abc" "y")>` | `("abc" "y")` |
| string-element-distinct-object | `<MEMBER <STRING "ab" "c"> '("x" "abc")>` | `("abc")` |
| memq-contrast-distinct-string | `<MEMQ <STRING "ab" "c"> '("x" "abc")>` | `#FALSE ()` |
| string-needle-vector-no-substring | `<MEMBER "a" ["abc" "xa"]>`, `<MEMBER "abc" ["xabcx" "abc"]>` | `#FALSE ()` \| `["abc"]` |
| string-needle-char-list | `<MEMBER "a" '(!\a)>` | `#FALSE ()` |
| vector-hit | `<MEMBER "B" ["A" "B" "C"]>`, `<TYPE …>` | `["B" "C"]` \| `VECTOR` |
| uvector-hit | `<MEMBER 2 ![1 2 3!]>`, `<TYPE …>`, `<MEMBER 4 ![1 2 3!]>` | `![2 3!]` \| `UVECTOR` \| `#FALSE ()` |
| winners-vector | WINNERS as in 77rooms.mud:254; `"MARC"`, `"MTRZORK"`, `"MAR"`, `"marc"`, `<STRING "MD" "L">` | `["MARC" "PDL" "MDL"]` \| `#FALSE ()` \| `#FALSE ()` \| `#FALSE ()` \| `["MDL"]` |
| lexv-empty-string-search | LEXV as in 77rooms.mud:1555; `<MEMBER "" ,LEXV>`; `<==? <MEMBER "" ,LEXV> ,LEXV>`; PUT `"ROBOT"`, `"GO"` into 1, 2; `<MEMBER "" ,LEXV>`; `<LENGTH …>`; `<REST <MEMBER "" ,LEXV>>`; `<MEMBER "" ["A" "B"]>` | `["" "" "" ""]` \| `T` \| … \| `["" ""]` \| `2` \| `[""]` \| `#FALSE ()` |
| list-alias | `<SET L (1 2 3)>`, `<PUT <MEMBER 2 .L> 1 99>`, `.L`, `<==? <MEMBER 99 .L> <REST .L 1>>`, `<==? <MEMBER 1 .L> .L>` | … `(99 3)` \| `(1 99 3)` \| `T` \| `T` |
| vector-alias | same with `[1 2 3]` | … `[99 3]` \| `[1 99 3]` \| `T` \| `T` |
| uvector-alias | same with `![1 2 3!]` | … `![99 3!]` \| `![1 99 3!]` \| `T` |
| rest-view-haystack | `<MEMBER 1 <REST '(1 2 1 3) 1>>`, `<MEMBER 1 <REST [1 2 1 3] 1>>`, `<MEMBER 1 <REST [1 2 3] 1>>` | `(1 3)` \| `[1 3]` \| `#FALSE ()` |
| typed-structure | `<MEMBER 2 <CHTYPE (1 2 3) FORM>>`, `<TYPE …>`; `<NEWTYPE MYV VECTOR>`, `<MEMBER 2 <CHTYPE [1 2 3] MYV>>`, `<TYPE …>` | `(2 3)` \| `LIST` \| `MYV` \| `[2 3]` \| `VECTOR` |
| false-haystack | `<MEMBER 1 <>>`, `<MEMBER 1 #FALSE (1 2)>` | `#FALSE ()` \| `(1 2)` (a FALSE is PRIMTYPE LIST; the result has TYPE LIST) |

### STRING needle in a STRING haystack (substring)

| Case | Input | Output |
| --- | --- | --- |
| str-manual-example | `<MEMBER "PART" "SUM OF PARTS">` | `"PARTS"` |
| str-miss | `<MEMBER "XYZ" "SUM OF PARTS">` | `#FALSE ()` |
| str-match-at-start | `"SUM"`, `"S"` in `"SUM OF PARTS"` | `"SUM OF PARTS"` \| `"SUM OF PARTS"` |
| str-match-at-end | `"TS"`, `"PARTS"` | `"TS"` \| `"PARTS"` |
| str-equal | `<MEMBER "abc" "abc">` | `"abc"` |
| str-needle-longer | `<MEMBER "abcd" "abc">`, `<MEMBER "xabc" "abc">` | `#FALSE ()` \| `#FALSE ()` |
| str-case-sensitive | `<MEMBER "part" "SUM OF PARTS">` | `#FALSE ()` |
| str-first-of-multiple | `<MEMBER "AB" "xABAB">`, `<LENGTH …>` | `"ABAB"` \| `4` |
| str-backtrack | `<MEMBER "aab" "aaab">` | `"aab"` |
| str-rest-haystack | `<MEMBER "b" <REST "abcb" 2>>`, `<MEMBER "ab" <REST "abab" 1>>`, `<MEMBER "a" <REST "abc" 1>>` | `"b"` \| `"ab"` \| `#FALSE ()` |
| str-rest-needle | `<MEMBER <REST "xLEDG" 1> "CLEDG">` | `"LEDG"` |
| str-result-type | `<TYPE <MEMBER "b" "abc">>` | `STRING` |
| str-alias | `<SET S <STRING "RIVR3">>`, `<SET M <MEMBER "VR" .S>>`, `<LENGTH .M>`, `<PUT .M 1 !\Z>`, `.S`, `<==? .M <REST .S 2>>`, `<=? .M <REST .S 2>>` | … `"VR3"` \| `3` \| `"ZR3"` \| `"RIZR3"` \| `T` \| `T` |
| str-identity-offset0 | `B="ECHO"`: `<==? <MEMBER "ECHO" .B> .B>`, `<==? <MEMBER "CHO" .B> .B>`; `B2="XECHO"`: `<==? <MEMBER "ECHO" .B2> .B2>`; `B3=<ISTRING 10 !\x>` with `ECHO` PUT into 1-4: `<==? <MEMBER "ECHO" .B3> .B3>` | `T` \| `#FALSE ()` \| `#FALSE ()` \| `T` |
| str-spname-haystack | `"RIVR"` in `<SPNAME RIVR4>`, `"LEDG"`/LEDG2, `"VAIR"`/VAIR1, `"ALI"`/ALICE, `"ALI"`/ALITR, `"RIVR"`/RAVINE, `<TYPE <SPNAME FOO>>` | `"RIVR4"` \| `"LEDG2"` \| `"VAIR1"` \| `"ALICE"` \| `"ALITR"` \| `#FALSE ()` \| `STRING` |
| str-typed | `<NEWTYPE MYS STRING>`; `<MEMBER "b" <CHTYPE "abc" MYS>>`, `<TYPE …>`, `<MEMBER <CHTYPE "b" MYS> "abc">`, `<MEMBER <CHTYPE "b" MYS> <CHTYPE "abc" MYS>>`, `<MEMBER <CHTYPE "b" MYS> '("b")>` | `"bc"` \| `STRING` \| `"bc"` \| `"bc"` \| `#FALSE ()` |
| str-empty-haystack | `<MEMBER "a" "">`, `<MEMBER "a" <REST "abc" 3>>` | `#FALSE ()` \| `#FALSE ()` |

### Non-STRING needle in a STRING haystack (element search)

| Case | Input | Output |
| --- | --- | --- |
| str-character-needle | `<MEMBER !\b "abc">`, `<MEMBER !\z "abc">`, `<MEMBER !\B "abc">`, `<MEMQ !\b "abc">` | `"bc"` \| `#FALSE ()` \| `#FALSE ()` \| `"bc"` |
| str-fix-needle | `<MEMBER 98 "abc">` | `#FALSE ()` |
| str-atom-needle | `<MEMBER abc "abc">` | `#FALSE ()` |
| str-list-needle | `<MEMBER '(1) "abc">` | `#FALSE ()` |

### Empty needle: an implementation artifact (surprise)

| Case | Input | Output |
| --- | --- | --- |
| str-empty-needle | `<MEMBER "" "abc">`, `<LENGTH …>` | `""` \| `0` |
| str-empty-needle-variants | `<MEMBER <REST "xyz" 3> "abc">`, `<MEMBER <ISTRING 0> "abc">`, `<MEMBER "" <REST "abc" 3>>`, `<MEMBER "" "">`, `<MEMBER "" <ISTRING 3>>`, `<LENGTH …>` | `""` \| `""` \| `""` \| `""` \| `"^@^@^@"` \| `3` |
| str-empty-needle-storage | `<MEMBER "" <STRING "ab" "c">>`, `<MEMBER "" <ISTRING 3 !\a>>`, `<MEMBER "" <SUBSTRUC "abcdef" 0 3>>`, `<MEMBER <REST <STRING "x" "y"> 2> "abc">`, `<MEMBER "" <STRING "ab" <ASCII 0> "cd">>` | `""` \| `""` \| `""` \| `""` \| `"^@cd"` |
| str-nul-needle | `<MEMBER <STRING <ASCII 0>> "abc">`, `<MEMBER <STRING <ASCII 0>> <STRING "ab" <ASCII 0>>>` | `#FALSE ()` \| `"^@"` |

An empty needle does **not** give the whole haystack, which is what the
manual's substring definition implies (the empty string occurs at position 0).
It matches at the first NUL character in the haystack. If the haystack has no
NUL, it matches one position past the end and returns an empty tail. The
source shows why: the scan compares the needle's first byte before it checks
the length, so it reads beyond both strings. This is undefined behaviour in
the reference, not MDL semantics. A one-character NUL needle cannot match past
the end (`#FALSE ()` for `"abc"`).

### Errors (one process each; exit status 0 because of `<QUIT>`)

| Case | Input | stdout after banner | stderr |
| --- | --- | --- | --- |
| err-arity-0 | `<MEMBER>` | `*ERROR*` `"TOO-FEW-ARGUMENTS-SUPPLIED"` → `LISTENING-AT-LEVEL 2` | `Atom REP has neither LVAL nor GVAL` |
| err-arity-1 | `<MEMBER 1>` | same `TOO-FEW-ARGUMENTS-SUPPLIED` | same |
| err-arity-3 | `<MEMBER 1 '(1) 2>` | `"TOO-MANY-ARGUMENTS-SUPPLIED"` → level 2 | same |
| err-nonstructured-fix | `<MEMBER 1 2>` | `LISTENING-AT-LEVEL 1` (no MDL ERROR frame) | `Second arg to MEMBER must be structured` |
| err-nonstructured-atom | `<MEMBER 1 FOO>` | same | same |
| err-string-needle-fix-haystack | `<MEMBER "a" 5>` | same | same |
| err-character-haystack | `<MEMBER "a" !\a>` | same | same |

The arity errors are MDL ERRORs. The non-structured haystack is a
Confusion-internal error that returns to level 1 without an ERROR frame.

## Findings

1. Element search uses `=?`. It scans left to right, and the first match wins.
   It returns the shared `REST` view: a PUT through the result is visible in
   the original. The result is `==?` to `<REST s i>`, and at offset 0 it is
   `==?` to the haystack itself. This holds for LIST, VECTOR, UVECTOR, and
   STRING. A miss returns `#FALSE ()`.
2. `=?` details: FIX 2 is not FLOAT 2.0, a LIST is not a VECTOR, STRINGs
   compare by content (a distinct object matches, where MEMQ misses),
   comparison is case-sensitive, a typed value is not equal to its PRIMTYPE
   twin (`MYS "b"` vs `"b"` misses), FALSE values compare by contents, and
   nested structures compare deeply.
3. Substring search happens only when **both** arguments are PRIMTYPE STRING,
   typed STRINGs included. A STRING needle against a VECTOR or LIST does a
   `=?` element search (`<MEMBER "a" ["abc"]>` misses). Any other needle
   against a STRING does an element search (a CHARACTER finds its position; a
   FIX, ATOM, or LIST misses).
4. Substring results: the first occurrence, case-sensitive, with correct
   backtracking. Offsets are relative to a REST'd haystack, and the result
   shares storage with the haystack (`PUT` mutates the original; `==?` to
   `<REST .S 2>` is `T`). A needle longer than the haystack, or an empty
   haystack, gives `#FALSE ()`.
5. Result TYPE is the haystack's PRIMTYPE type, as the manual says: FORM gives
   LIST, the NEWTYPE MYV gives VECTOR, the NEWTYPE MYS gives STRING, and
   FALSE gives LIST.
6. ECHO-ROOM's `<==? <MEMBER "ECHO" X> X>` is `T` exactly when the match is
   at offset 0, including when the 100-character buffer has trailing stale
   characters (B3 case).

## Recommended supported subset (for the implementing slice)

Support:
- `<MEMBER needle haystack>` with exactly 2 arguments, where the haystack is a
  LIST, VECTOR, or UVECTOR (native or REST view, including CHTYPE'd/NEWTYPE'd
  values of those PRIMTYPEs). Search with the runtime's `=?`. Return the
  `mdl-rest` view at the first match so aliasing and `==?` are preserved,
  typed with the PRIMTYPE type. Return `#FALSE ()` on a miss.
- STRING haystack (native, REST view, or PRIMTYPE STRING) with a
  **non-empty** STRING needle (PRIMTYPE STRING): a case-sensitive substring
  search that returns the shared tail view of TYPE STRING, or `#FALSE ()`.
- STRING haystack with a non-STRING needle: an element search with `=?`. This
  is the same rule as MEMQ on STRING; for a CHARACTER it gives the same result.

Strict failures (never a silent FALSE or no-op):
- Arity other than 2. Confusion raises MDL ERROR `TOO-FEW-ARGUMENTS-SUPPLIED`
  or `TOO-MANY-ARGUMENTS-SUPPLIED`.
- A non-structured haystack (FIX, ATOM, CHARACTER, …). Confusion:
  `Second arg to MEMBER must be structured`.
- An **empty STRING needle with a STRING haystack**. Confusion's result is
  undefined behaviour (above) and differs from the manual. The game never
  does this. Raise a strict unsupported error that cites this file; do not
  return the haystack and do not return `""`.
  (`<MEMBER "" ,LEXV>` is a VECTOR haystack and **must** work: it is an
  element search.)
- Other structured PRIMTYPEs not yet represented in the runtime (BYTES,
  TUPLE, TEMPLATE, …): strict unsupported, unless they are already modelled.

Tests the implementer should mirror: every row above except the empty-needle
undefined-behaviour rows, which become strict-error tests.

## Limitations

- BYTES (the manual's other substring case) was not probed; the game has no
  BYTES.
- TUPLE, TEMPLATE, and ASOC haystacks were not probed.
- The out-of-bounds empty-needle behaviour depends on memory contents. It was
  stable across the two runs here, but it is not a contract.
- Security and licensing: probes ran locally on isolated copies. No GPLv3
  code was copied, and only observed outputs are recorded.
