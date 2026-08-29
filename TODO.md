# RPG IV Free-Format Feature Tracker

---

## ✅ Implemented Features

### Core Language
- **FREE, DCL-S (CHAR, VARCHAR, INT, PACKED, ZONED, IND, DATE, TIME, TIMESTAMP, POINTER, UNS, FLOAT, BINDEC)
- DCL-S keywords: DIM, DIM(*VAR:max), DIM(*AUTO:max), LIKE, INZ, CONST, STATIC, TEMPLATE, BASED, ASCEND, DESCEND
- DCL-C, DCL-F (stub), DCL-DS/END-DS (QUALIFIED, DIM, DIM(*VAR), LIKEDS, OVERLAY, POS, PREFIX, EXTNAME stub)
- DCL-SUBF, DCL-PARM
- DCL-PR/END-PR, DCL-PROC/END-PROC, DCL-PI/END-PI (VALUE, return types, LIKEDS params)
- DCL-ENUM/END-ENUM (QUALIFIED), BOOLEAN data type (Test 71)
- EXPORT, IMPORT, EXTPGM, EXTPROC, NOMAIN (Tests 48/49)
- OPTIONS(*NOPASS) (Test 46), OPTIONS(*OMIT) (Test 64)

### Statements & Control Flow
- EVAL, EVAL-CORR, EVALR, DSPLY, RETURN, CALLP, LEAVESR
- IF/ELSEIF/ELSE/ENDIF, DOW/ENDDO, DOU/ENDDO
- FOR/ENDFOR (TO, DOWNTO, BY), FOR-EACH (Test 58)
- SELECT/WHEN/OTHER/ENDSL, ITER, LEAVE
- MONITOR/ON-ERROR/ENDMON, BEGSR/ENDSR/EXSR
- RESET, CLEAR, SORTA, DEALLOC
- ON-EXIT (Test 42), TEST(D/T/Z) (Test 47)
- XML-INTO (direct mode, %XML with case options) (Test 87)
- XML-INTO Phase 2: array DS, PATH option, nested DS/LIKEDS subfields (Tests 88-89)
- *INZSR (Test 37), *PSSR (Test 66/67)

### Expressions & Operators
- Arithmetic: +, -, *, /, ** (exponentiation, Test 68)
- Comparison: =, <>, <, >, <=, >=
- Logical: AND, OR, NOT
- IN operator (Test 58)

### Built-In Functions
- **String:** %CHAR, %TRIM, %TRIML, %TRIMR, %LEN, %SUBST, %SCAN, %SCANR (Test 69), %SCANRPL, %XLATE, %REPLACE, %CHECK, %CHECKR, %LOWER, %UPPER, %SPLIT, %CONCATARR, %CONCAT (Test 74), %LEFT, %RIGHT, %STR, %EDITC, %EDITW
- **Numeric:** %DEC, %INT, %FLOAT, %UNS, %INTH, %DECH, %DECPOS, %SQRT, %ABS, %DIV, %REM, %EDITFLT (Test 70), %UNSH (Test 70), %PARMNUM (Test 71)
- **Array:** %ELEM, %ELEM(arr)=n (Test 72), %LOOKUP, %LOOKUPLT/GE/LE/GT (Test 52), %TLOOKUP/LT/GT/LE/GE (Test 75), %XFOOT, %SUBARR, %MAXARR, %MINARR, %LIST, %RANGE, %SIZE
- **Bitwise:** %BITAND, %BITNOT, %BITOR, %BITXOR (Test 68)
- **Date/Time:** %DATE, %TIME, %TIMESTAMP, %DIFF, %DAYS, %MONTHS, %YEARS, %HOURS, %MINUTES, %SECONDS, %MSECONDS, %SUBDT
- **Memory/Pointer:** %ALLOC, %REALLOC, %ADDR, %PADDR, %PROC, %STR
- **Other:** %PARMS, %STATUS, %ERROR, %FOUND, %EOF, %PASSED, %OMITTED, %MAX, %MIN, %GETENV (Test 85)

### %STATUS Code Values
| Code | Description | Applicable |
|------|-------------|------------|
| 0 | No error | ✅ |
| 100 | Value out of range for string operation | ✅ |
| 101 | Negative square root | ✅ |
| 102 | Divide by zero | ✅ |
| 103 | Intermediate result overflow | ✅ |
| 104 | Float underflow | ✅ |
| 112 | Invalid date/time/timestamp value | ✅ |
| 113 | Date overflow/underflow | ✅ |
| 114 | Date mapping errors | ✅ |
| 115 | Variable-length field has invalid length | ✅ |
| 120 | Table/array out of sequence | N/A (legacy) |
| 121 | Array index not valid | ✅ |
| 122 | OCCUR value not valid | N/A (legacy) |
| 202 | Called program failed | ✅ |
| 211 | Error calling program | ✅ |
| 221 | Called program not found | ✅ |
| 222 | Pointer/parameter error | ✅ |
| 231 | Called program halted | ✅ |
| 232 | Halt indicator on in called program | ✅ |
| 233 | Halt indicator on when RETURN | ✅ |
| 299 | RPG IV runtime error | ✅ |
| 301-399 | File I/O errors | N/A (using SQL) |
| 401 | Data area not found | ✅ |
| 402 | Data area type/length mismatch | N/A (file-based, no schema) |
| 411 | Data area not locked | N/A (locking is a no-op) |
| 412 | Data area lock error | N/A (locking is a no-op) |
| 413 | Error updating data area | ✅ |
| 414 | User not authorized to data area | N/A (IBM i user profiles) |
| 415 | Error accessing data area | ✅ |
| 421 | Error calling DSPLY | ✅ |
| 431 | Error calling SND-MSG | N/A (IBM i) |
| 450 | Character conversion error | ✅ |
| 500 | Failure to allocate storage | ✅ |
| 802 | Failure in sort | ✅ |
| 803 | Error during dump | N/A (IBM i) |
| 804 | Error in *PSSR | ✅ |
| 907 | Decimal data error | ✅ |
| 1021-1026 | XML parser errors | N/A (IBM i) |
| 1211-1299 | XML-SAX/XML-INTO errors | N/A (IBM i) |
| 9001 | Program exception | ✅ |
| 9999 | General ILE RPG error | ✅ |

### Date/Time Formats (Test 73)
- Date: *ISO, *USA, *EUR, *JIS, *MDY, *DMY, *YMD, *JUL, *CYMD, *CMDY, *CDMY, *LONGJUL
- Time: *HMS, *ISO, *USA, *EUR, *JIS
- Timestamp: *ISO, *ISO0
- On `MOVE`/`MOVEL` a format may also carry its separator (`*MDY/`,
  `*MDY-`, `*MDY.`, `*MDY,`, `*MDY&`) or a trailing `0` for none at all
  (`*MDY0`, `*ISO0`) — Tests 208-211. `*JOBRUN` is refused (Test 213).

### Figurative Constants
- *BLANKS, *ZEROS, *HIVAL, *LOVAL, *ON, *OFF, *NULL, *INLR, *ALL'x', *OMIT
- *USER — Current user profile (Test 101)

### String Literals
- Quoted strings: `'text'` with `''` escape for embedded apostrophe
- Hex literals: `X'0A0D'` — converted to byte string at compile time (Test 112)

### Indicators
- *IN01-*IN99 — Fully functional
- *INLR — Compatibility only (accepted/ignored; no RPG cycle to end)

### Compiler Directives
- /COPY, /INCLUDE, /DEFINE, /UNDEFINE, /IF DEFINED, /IF NOT DEFINED, /ELSE, /ELSEIF, /ENDIF
- /EOF, /EJECT, /SPACE, /SET, /RESTORE, /TITLE (compatibility)

### CTL-OPT (Control Options)
- NOMAIN (Test 48), MAIN(procname) (Test 56)
- DATFMT(fmt), TIMFMT(fmt) (Test 57)
- DFTACTGRP, ACTGRP, OPTION, DEBUG, DECEDIT, CCSID, TEXT, THREAD, COPYRIGHT — accepted/ignored

---

## 🔲 Remaining Work

### Still TODO

| # | Feature | Section |
|---|---------|---------|
| 1 | ✅ Operation extenders (E), (H), (N), (M), (R), (P) | Opcodes |
| 2 | ✅ DUMP opcode (debug) | Opcodes |
| 3 | ~~COMMIT / ROLBK~~ — Moved to Embedded SQL Phase 2 | Opcodes |
| 4 | ✅ IN / OUT — Data area operations | Opcodes |
| 5 | ✅ *USER — Current user profile figurative constant | Constants |
| 6 | ✅ PSDS — Program Status Data Structure | DS Keywords |
| 7 | ✅ %ELEM(*ALLOC) / %ELEM(*KEEP) — Varying array control | BIFs |
| 8 | ✅ SND-MSG — Message operations (7.5+) | Modern |
| 9 | ✅ DATA-INTO / DATA-GEN (%DATA) | Modern |
| 10 | ✅ OVERLOAD — Overloaded procedures (7.4+) | Modern |
| 11 | ✅ Data area operations (IN/OUT/UNLOCK, DTAARA, *LDA/*GDA/*PDA) | Data Areas |
| 12 | ✅ SQL indicator variables (`:var :ind`) | Embedded SQL |
| 13 | ✅ RPG status codes (full %STATUS value set) | Error Handling |

### Record Level Access (via ODBC) ✅
DCL-F, CHAIN, READ, WRITE, UPDATE, DELETE, SETLL, SETGT, READE — implemented via ODBC (Tests 103-108)

### Fixed-Format Source Support — Phase 1 ✅
A second, column-based frontend alongside free-format — real legacy RPG is
often still fixed-format H/F/D/C specs, sometimes with C-spec logic already
modernized into `/free`...`/end-free` blocks while H/F/D stay fixed-format
(a common incremental-modernization pattern). The AST and codegen are
already format-agnostic, so this is purely a new *parsing* frontend — every
existing language feature becomes reachable from fixed-format source once
it builds the same AST nodes, no codegen changes needed. Source format is
content-sniffed (columns 1-6 of the first substantive line), not extension-
gated — `**FREE` was never a hard mode switch here either.
- H-spec (control options — MAIN/NOMAIN/DATFMT/TIMFMT, same as CTL-OPT)
- F-spec (externally-described DISK/WORKSTN files; keyword-tail continuation)
- D-spec (standalone fields; basic non-OCCURS DS/subfields; name continuation via trailing `...`)
- C-spec via `/free`...`/end-free` only — the block body is parsed by the
  *existing* free-format lexer/parser unchanged (re-invoked via flex's
  `yy_scan_string`), not a new C-spec grammar
- Implemented via a hand-written column-slicer (`src/fixed_columns.h`,
  `src/fixed_reader.cpp`), not a new flex/bison grammar (Tests 116-119)
- **Deliberately excluded from Phase 1** (see "Legacy / Fixed-Format"
  below for what's rejected outright vs. deferred): traditional fixed-
  column C-spec, extended-factor-2 C-spec, I-specs, O-specs — all real
  engineering, deferred rather than rejected; revisit as a later phase
  if there's demand

### Fixed-Format Source Support — Phase 2 (D-spec depth) ✅
Closes D-spec gaps left basic in Phase 1 — all pure fixed-format *parsing*
gaps (same thesis as Phase 1: the AST/codegen already supported every one
of these via the free-format grammar, so `fixed_reader.cpp` is the only
file this phase touches). Motivated by a concrete pain point Phase 1 hit in
its own testing: test118's DISK `CHAIN` needed an integer key instead of
the natural `VARCHAR` key, since fixed-format D-spec had no way to declare
one.
- `VARYING{(2|4)}` keyword-tail keyword → `RPGType::VARCHAR` (standalone
  fields and DS subfields) — verified against SC09-2508's `VARYING{(2|4)}`
  entry: keyword-tail only, "not used in a free-form definition" (that's
  what `VARCHAR(n)` is for), applies uniformly regardless of standalone-
  vs-subfield context. Test122 rebuilds Phase 1's test118 DISK `CHAIN`
  milestone with a real `VARCHAR` key, closing that gap.
- `DIM(n)` on a `DclDS` itself (array of DS elements, e.g. `items(1).qty`)
- Per-subfield `OVERLAY(field)`, `OVERLAY(field:pos)`, `POS(n)`, `LIKEDS(name)`
- **Found but out of scope**: per-subfield `LIKE(...)` and per-subfield
  `DIM(...)` (an array *within* one subfield) have no grammar support in
  free-format either, and `DSField` has no fields to hold them — extending
  these would mean growing the free-format language surface itself, not
  just this frontend. Deferred as a follow-on, not silently dropped.
- Tests 120-124. Note: DS-subfield `CHAR` vs `VARCHAR` currently has no
  differentiated codegen behavior in this compiler (true for free-format
  DS subfields too — confirmed by code search, not a fixed-format-specific
  gap) — test121 is a round-trip check, not a type-distinction check like
  test120's standalone-field version.

### Fixed-Format Source Support — Next Steps (ranked by real-world necessity)
Goal shifted from "cover the common cases" (Phases 1-2) to **accepting most
real fixed-format RPG IV source**, not just H/F/D specs paired with already-
modernized `/free` C-spec logic. Ranked by how much real legacy source each
item unblocks, most-needed first:

**1. Traditional / extended-factor-2 fixed-column C-spec ✅ (V1).**
Implemented via a **transpile-and-bridge** design, not a new grammar:
`src/fixed_cspec.h/.cpp` transpiles each native C-spec line (Factor1/
Opcode/Factor2/Result, or Extended Factor 2's whole-expression style) into
its exact free-form-equivalent text, buffers a contiguous run of them
exactly like an implicit `/free` block, and flushes through the *same*
`parse_free_block()` bridge Phase 1 already built for explicit
`/free`...`/end-free` — zero new AST nodes, zero new bison grammar, no
hand-rolled expression parser. Verified against SC09-2508 (p.559-567:
Traditional Syntax, Extended Factor 2 Syntax, continuation rules) —
citations live in `fixed_columns.h`'s `CSpec` namespace.
- **V1 opcode set** (Tests 125-134): bare — `ELSE`/`ENDDO`/`ENDFOR`/
  `ENDIF`/`ENDMON`/`ENDSL`/`ENDSR`/`ITER`/`LEAVE`/`LEAVESR`/`OTHER`/
  `SELECT`/`MONITOR`; extended-factor-2 — `IF`/`ELSEIF`/`DOW`/`DOU`/
  `WHEN`/`EVAL`/`EVALR`/`EVAL-CORR`/`RETURN`/`CALLP`/`FOR`/`FOR-EACH`/
  `ON-ERROR`; traditional Factor1/Factor2/Result — `BEGSR`/`EXSR`/
  `CLEAR`/`RESET`/`DSPLY`/`SORTA`. Extended-Factor-2 continuation across
  physical lines works (Test 133); native C-spec freely mixes with
  explicit `/free` blocks in the same file (Test 134).
- **Rejected, not silently dropped** (clear, distinct compile errors —
  Tests 135-138): non-blank control level (RPG-cycle-only, `L0`/`L1-L9`/
  `LR`; `AN`/`OR` were rejected here too but have since shipped with item
  #6 — they are conditioning syntax, not cycle syntax), non-blank
  conditioning indicators (positions 9-11 —
  since shipped, see item #6), resulting indicators/inline field
  length (free-form drops these too, so this isn't a new gap), any opcode
  outside the V1 set — with a distinct message for known-but-deferred
  opcodes (e.g. `SND-MSG`) vs. never-planned legacy ones (e.g. `ADD`).
- **Deferred fast-follow**: `ON-EXIT`/`ON-EXCP`; `XML-INTO`/`XML-SAX`/
  `DATA-INTO`/`DATA-GEN`/`SND-MSG`; conditioning indicators (positions
  9-11 — since shipped as item #6, exactly as sketched here: the
  transpiled statement wrapped in `IF {N}*INnn; ... ENDIF;`); `EXEC SQL`
  in fixed columns
  (architecturally distinct — the SQL capture is a dedicated lexer
  `<SQL>` start-condition, not a column-mapped opcode, so it doesn't fit
  this transpile model cleanly). Traditional *legacy* opcodes (`ADD`/
  `SUB`/`MOVE`/`GOTO`/etc.) remain item #3 below, untouched by this pass.

**1b. RLA opcodes in native C-spec ✅.** `CHAIN`, `READ`, `READP`,
`READE`, `READPE`, `WRITE`, `UPDATE`, `DELETE`, `SETLL`, `SETGT` — the
same `TRADITIONAL`-shape mechanism item #1 already built, just more
opcode-table entries in `src/fixed_cspec.cpp`; no new architecture.
Verified against this compiler's own `parser.y` grammar rather than the
full IBM manual, since the free-format RLA grammar here is already a
simplified subset: **no data-structure Result operand on any of these**
(every `*_stmt` rule ends at `IDENTIFIER SEMICOLON`, nothing after the
file name), and **`DELETE` takes no key at all** — it deletes the
last-fetched record, matching `tests/test105`'s own usage, not a
delete-by-key Factor 1. `SETLL`/`SETGT` have no `KW_*_EXT` lexer rule, so
(unlike the other eight) they don't accept an operation extender. Direct
fixed-format analogues of Tests 103-106: Tests 144-147.

**2. `/COPY`/`/INCLUDE` outside `/free` blocks ✅.** Implemented as a
recursive, depth-limited line-splicing preprocessing pass
(`expandCopyDirectives()` in `src/fixed_reader.cpp`) that runs once,
before spec-type dispatch begins — so a copied D-spec, F-spec, H-spec, or
native C-spec line is indistinguishable from one that was physically
present in the outer file. Matches the free-format lexer's own
`/COPY`/`/INCLUDE` convention exactly (`src/lexer.l`): the text after the
directive keyword is a literal filename, opened relative to the process's
current working directory — no library/member catalog, no search path.
Nesting is capped at the same depth (10) as the free-format lexer's own
`MAX_INCLUDE_DEPTH`, for consistency rather than because either number is
load-bearing. Lines between an explicit `/FREE`...`/END-FREE` pair are
deliberately left untouched by this pass — `parse_free_block()`
re-invokes the real free-format lexer on that text, which already has its
own working `/COPY`/`/INCLUDE` handling, so expanding here too would
double-process it (Test 142 proves the two paths coexist correctly). Line
numbers after an expansion point are relative to the flattened line
stream, not the original file — the same "best effort, not exact"
precision the free-format lexer already has today (`yylineno` isn't
saved/restored across its own buffer switch either), not a new
regression. Tests 139-143.

**3. Traditional legacy opcodes ✅ (V1): `GOTO`/`TAG`, `ADD`/`SUB`/`MULT`/
`DIV`/`Z-ADD`/`Z-SUB`.** For genuinely old, pre-modern-opcode fixed-format
source — distinct from #1, which targets shops already writing modern
opcodes in column form; this targets shops that never left `MOVE`/`ADD`/
`GOTO`-style code. The one part of this whole "Fixed-Format Source
Support" effort that couldn't just reuse the transpile-and-bridge trick
as-is, since `GOTO`/`TAG` have **no free-form syntax at all** (SC09-2508
says so outright for both: "not allowed — use other operation codes, such
as `LEAVE`, `LEAVESR`, `ITER`, and `RETURN`").
- **`GOTO`/`TAG`**: real new `GotoStmt`/`TagStmt` AST nodes + `parser.y`
  grammar (`src/ast.h`, `src/codegen.cpp` → `goto`/label in the generated
  C++ directly), gated by `g_allow_goto_tag` (`src/free_bridge.h`) so
  they're only accepted when the text being parsed was synthesized by the
  fixed-format C-spec transpiler (`fixed_reader.cpp`'s `flushCRun`) —
  genuine free-form text, `**FREE` top-level or an explicit `/free` block
  even inside an otherwise fixed-format file, still correctly rejects
  them (Test 152), matching the manual exactly rather than silently
  extending free-form beyond the documented spec. Subroutines (`BEGSR`/
  `ENDSR`) codegen as C++ lambdas, which happens to enforce real RPG's own
  `GOTO` scoping rule (can't cross a subroutine boundary) for free, with
  no extra validation needed — a `TAG`/`GOTO` crossing that boundary
  anyway just surfaces as a real (if less-polished) C++ compile error,
  not silently wrong behavior. No "undefined/duplicate label" validation
  either — C++'s own compiler already rejects that when it compiles the
  generated code.
- **`ADD`/`SUB`/`MULT`/`DIV`/`Z-ADD`/`Z-SUB`**: no free-form *keyword*
  either ("not allowed — use the `+`/`+=` operator", etc.) but the manual
  itself prescribes the `EVAL`/expression equivalent, so these transpile
  straight to synthesized `EVAL` text — zero new grammar, same mechanism
  as items #1/1b. Verified blank-Factor-1 semantics against SC09-2508:
  Factor 1 present → `Result = Factor1 op Factor2`; Factor 1 blank →
  `Result = Result op Factor2` (accumulate into the result field) for
  `ADD`/`SUB`/`MULT`/`DIV`; `Z-ADD`/`Z-SUB` never use Factor 1 at all
  (`Result = Factor2` / `Result = -Factor2`). Extenders (e.g. `(H)`
  half-adjust) pass straight through onto the synthesized `EVAL`, which
  already supports them.
- **Deferred, not V1** (documented, not silently dropped): `MOVE`/`MOVEL`
  — real semantic risk, not just unwired plumbing: traditional fixed-
  length right/left-adjusted move with truncation/padding, plus date/
  time-format conversion via `D()`/`T()`/`Z()` Factor-2 suffixes, none of
  which map onto this compiler's plain-assignment `EVAL` — shipping an
  approximate version risks silently-wrong output for edge cases rather
  than a clear compile error, which this project avoids. `COMP` — its
  only real effect (setting `HI`/`LO`/`EQ` resulting indicators) has no
  free-form target at all, since free-form drops resulting indicators
  entirely (an existing limitation, not new). `CASxx`/`CABxx` —
  conditional branch-to-tag/subroutine; meaningfully more parsing work for
  the `xx` comparison-mnemonic suffix, and with `GOTO`/`TAG`/`IF` all now
  available, the same logic is expressible as `IF cond; GOTO label;
  ENDIF;`. `CALL`/`PARM`/`PLIST` — old-style program calls, a genuinely
  different mechanism from `CALLP` needing cross-line state to build a
  `PLIST`'s parameter list across multiple physical `PARM` lines (similar
  complexity to F-spec continuation); `CALLP` already covers modern
  program calls. `DO` — the manual's own guidance is "not allowed — use
  the `FOR` operation code," already fully supported. Does not revive the
  RPG cycle itself (detail/total calc, LR-driven implicit read loop) —
  that stays rejected regardless of any of this item's future scope.

**4. I-specs / O-specs (program-described file I/O) ✅.** Unlike items
1/1b/2/3, this couldn't reuse existing infrastructure — every existing
file opcode (RLA — `CHAIN`/`READ`/`WRITE`/etc.) is 100% SQL/ODBC against a
database table, but program-described I-specs/O-specs describe **flat
files with byte-position field layout**, so this needed a genuinely new
raw fixed-length-record file I/O runtime
(`runtime/rpg_flatfile_runtime.h`) built from scratch. Real IBM i
program-described files have no in-file delimiters (pure fixed-width
bytes on a record-oriented file system); since there's no equivalent on
macOS/Linux/Windows, records are newline-delimited fixed-width text
instead — an OpenRPG-specific portable convention, not literal IBM i
on-disk semantics, documented as such in the runtime header. `READ`/
`WRITE`/`UPDATE` reuse the *same* `ReadStmt`/`WriteStmt`/`UpdateStmt` AST
nodes RLA already uses (a program just writes `READ MYFILE;` regardless
of which kind of file `MYFILE` is) — `visit()` for each gained a new
branch checked before the existing RLA/"no schema" fallback, mirroring
the pattern the WORKSTN branch already used in the same methods.
- **In scope**: record identification via character-part (`C`) tests only
  (position/not/character — no zone/digit tests), field description
  (from/to byte position, data type, decimals, field name, field
  indicators for plus/minus/zero-or-blank), sequential `READ` with
  multi-record-type dispatch, `UPDATE` (rewrite the last-read record in
  place). **One O-spec record format per file** (field/constant placement
  by end-position — width inferred from the gap to the previous field's
  end position, not by cross-referencing the field's own declared length;
  edit codes reuse the existing `rpg_editc()` used by `%EDITC`), `WRITE`.
- **Deferred, documented not dropped** (found or reconfirmed during
  implementation, beyond the two flagged when this item was scoped):
  zone/digit (`Z`/`D`) record-identification tests (SC09-2508 p.548-549,
  obscure EBCDIC-era byte testing); matching fields / multi-file record
  merging (RPG-cycle-adjacent, permanently rejected elsewhere);
  `CHAIN`/`SETLL`/`SETGT`/`DELETE` on program-described files (real keyed
  access needs F-spec key-field columns not modeled for program-described
  files); O-spec spacing/skip and printer paging (this compiler has zero
  PRINTER-output runtime at all, for *any* file type — a separate,
  standalone feature, not something O-specs are specifically blocked on);
  **control-level (`L1`-`L9`) indicator-on-value-change** — parses and is
  accepted, but doesn't yet set anything at codegen time: wiring it in
  turned out to need real extensions to this compiler's indicator system
  (general indicators are a flat `bool[100]` array with no L1-L9 concept
  at all, and *INL1-style expression syntax doesn't exist), a
  meaningfully bigger, separate task once actually reached; **multiple
  O-spec record formats per file** — real DDS disambiguates via
  record-type/EXCEPT names, both already deferred above, so a file needs
  exactly one O-spec format (a second one is rejected with a clear error,
  not silently overwritten — found via this session's own test155);
  **date/time/timestamp (`D`/`T`/`Z`) and graphic/indicator-format
  (`G`/`N`) I-spec data formats** — rejected at parse time (`CHAR` text
  still works fine for a date field if you don't need real date parsing);
  **O-spec relative end positions** (`+n`/`-n`) — only absolute end
  positions are supported; **sequence checking** (I-spec positions
  17-20) — not implemented, must be blank.
- Tests 154-160.

**5. Per-subfield `LIKE(...)`/`DIM(...)` ✅.** Found during Phase 2: neither
existed at the subfield level in free-format either, so — unlike items
#1-#4, which were pure fixed-format *parsing* gaps — this needed real
`ds_field` grammar productions in `parser.y` (`DSField` gained `like_var`/
`dim` members) before `fixed_reader.cpp` had anything to populate.
- **DIM(n)**: the subfield becomes an array *within* the DS
  (`std::array<T,n>`), distinct from DIM on the DS itself (an array of DS
  elements, Phase 2). Accessed via new `ds.field(idx)` grammar — added at
  the `postfix_expr`/`eval_target` level, not as a flat `IDENTIFIER DOT
  IDENTIFIER LPAREN...` production, since the latter would shift/reduce-
  conflict with plain `ds.field` (no index) in `primary_expr`'s existing
  `IDENTIFIER` reduction; going through the already-reduced `postfix_expr`
  nonterminal first sidesteps that (verified no new conflicts vs. this
  grammar's existing 2 shift/reduce + 1 reduce/reduce baseline).
- **LIKE(other)**: resolves against a field already declared **earlier in
  the same DS** — the reliable, tested case (Test 163's `price
  LIKE(unitPrice)` inside the same DS). Referencing an *outer standalone*
  field also has fallback code (mirroring top-level `DCL-S ... LIKE`), but
  doesn't fire reliably at main/top-line scope: `visit(Program)` emits
  every DS struct definition before any standalone field's own DclS
  (DS structs are needed for procedure params), regardless of the two
  declarations' textual order — found the hard way via Test 162's first
  version, which referenced an outer field and silently got the fallback
  placeholder type. Works fine inside a `DCL-PROC` body, where
  declarations emit in textual order.
- **Deferred, not V1**: combining `LIKE` and `DIM` on the same subfield
  (e.g. `qty LIKE(other) DIM(5)`); `DIM(*VAR:n)`/`DIM(*AUTO:n)` on a
  subfield (fixed-size only, matching the DS-level DIM(n) case this
  mirrors, not the *VAR/*AUTO forms DCL-S standalone fields support).
- Tests 161-162 (fixed-format D-spec — declaration only, since
  `fixed_reader.cpp` builds `DSField` directly rather than through the
  bison grammar); Test 163 (free-format — the one that actually exercises
  the new `ds_field` productions, since 161/162's fixed-format source
  never touches `parser.y` on the declaration side, only via the `/free`
  block's access expressions).

**6. Conditioning indicators (positions 9-11) ✅.** The highest-value
entry on the deferred fast-follow list below when it was written — common
in real legacy source and, unlike the RPG cycle's control-level field
(positions 7-8), completely independent of cycle semantics. Same
transpile-and-bridge design as item #1: position 9 (blank or `N`) and
positions 10-11 (the indicator) become an `IF {NOT }*INnn; <stmt> ENDIF;`
wrapper emitted onto the *same* buffer line the physical source line
already owns, so `parse_free_block`'s line numbers stay aligned exactly as
before. No new AST nodes, no grammar change — `*IN01`-`*IN99` were already
ordinary expressions (`IndicatorExpr`, parser.y).
- **Conditionable only where the wrapper is exactly equivalent** — that
  is, self-contained statements: `EVAL`/`EVALR`/`EVAL-CORR`/`RETURN`/
  `CALLP`; `ITER`/`LEAVE`/`LEAVESR`; every traditional-shape opcode
  (`EXSR`/`CLEAR`/`RESET`/`DSPLY`/`SORTA`, the RLA set, `GOTO`, and the
  `ADD`/`SUB`/`MULT`/`DIV`/`Z-ADD`/`Z-SUB` arithmetic set).
- **Rejected on block-structure opcodes** (`IF`/`ELSEIF`/`ELSE`/`ENDIF`,
  `DOW`/`DOU`/`ENDDO`, `FOR`/`FOR-EACH`/`ENDFOR`, `SELECT`/`WHEN`/
  `OTHER`/`ENDSL`, `MONITOR`/`ON-ERROR`/`ENDMON`, `BEGSR`/`ENDSR`) — an
  `IF`/`ENDIF` wrapper around one half of a block leaves the block
  unbalanced, so there is no honest transpilation; a distinct compile
  error says so and suggests folding the test into the block's own
  condition (Test 165). `TAG` is rejected for a related but different
  reason: wrapping a label would bury it inside a nested scope its own
  `GOTO`s cannot legally jump into.
- **Rejected on indicators this compiler has no representation for** —
  `LR`, `MR`, `RT`, `OV`, `1P`, `L1-L9`, `H1-H9`, `U1-U8`, `KA-KY`,
  `OA-OG` — recognized by name specifically so they get a "not supported
  here" diagnostic pointing at "Indicator Types" under Not Planned,
  rather than being reported as a typo (Test 166). `00` and any
  column-misaligned entry get their own messages (Test 136, repurposed
  from its previous "conditioning indicators rejected outright" role to
  the misalignment case its source actually exercises).
- **`AN`/`OR` multi-indicator groups (positions 7-8)** — RPG IV's C-spec
  has room for exactly one indicator per line, so `AN`/`OR` on a following
  line is the *only* way to write a multi-indicator condition; the group's
  operation code sits on its last line. Terms accumulate in
  `CSpecRunState::condGroups` (outer = AND-groups, ORed together) and
  collapse into one expression when that operation line arrives. RPG
  relates them as an **OR of AND-groups**, not left-to-right, so each
  multi-term AND-group is parenthesized — Test 167 pins this with a
  `(10 AND 30) OR 20` case that only passes under the correct grouping.
  Note this corrects a wrong claim in the old `fixed_columns.h`
  `ControlLevel` doc string, which lumped `AN`/`OR` in with `L0`/`L1-L9`/
  `LR` as "RPG-cycle-only" — they have nothing to do with the cycle, and
  that mischaracterization is likely why they were rejected alongside it.
  A group whose last line never arrives, an `AN`/`OR` with nothing before
  it, and an `AN`/`OR` line missing its indicator each get their own error
  (Tests 168-169).
- **Extended-factor-2 continuation** needed the one piece of new state:
  the wrapper's `ENDIF` can't be emitted until whoever appends the
  statement's terminating `;` runs, which for a continued statement is
  several physical lines later — hence `CSpecRunState::pendingSuffix`.
- **Still not conditionable from fixed columns**: the O-spec's own
  conditioning indicators (positions 21-29) remain rejected in
  `fixed_reader.cpp` — a separate mechanism belonging to item #4, not to
  this one.
- Tests 164 (positive: both polarities, all three opcode shapes,
  conditioned `GOTO`, conditioned `LEAVE`/`ITER` inside `DOW` loops, and
  a conditioned statement continued across a physical line), 167 (`AN`/
  `OR` groups), 165-166 and 168-169 (rejections).

**7. `MOVE`/`MOVEL` — character moves ✅.** Deferred out of item #3 for
semantic risk rather than missing plumbing, so this ships the part that
can be made exact and refuses the rest outright.
- **What makes it not plain assignment**: `MOVE` aligns factor 2 against
  the RIGHT end of the result, `MOVEL` against the LEFT, and the part of
  the result the move does not reach is left **unchanged** (the `(P)`
  extender blanks it instead). An over-long factor 2 truncates on the side
  away from the alignment. That needs the result's *declared* length, so
  unlike every other opcode here this could not be a pure text transpile.
- **Where the type check lives**: `fixed_cspec.cpp` has no symbol table,
  so codegen — the first stage that can see declared types — is what
  refuses a non-character operand. That needed a diagnostic channel after
  parsing: `report_semantic_error` (free_bridge.h) reuses
  `report_fixed_format_error`'s stderr channel and error counter, and
  `main.cpp` now re-checks the count once codegen returns.
- **Character-to-character only** *(superseded by item #13, which added
  the numeric forms)*. Numeric, date/time and varying-length results were
  rejected here, as was a numeric or date/time factor 2, and so is the
  date/time-conversion form that puts a format in Factor 1 — that one is
  caught in the transpiler, since it needs no type info (Test 172).
  Digit-alignment and format-conversion semantics had no representation
  in this compiler at the time, and approximating them is exactly the
  silently-wrong-output risk this item was deferred over. Date/time
  results and the Factor-1 form are still refused.
- **New `MoveStmt` AST node** plus a `move_stmt` rule gated the way
  `GOTO`/`TAG` already were — `MOVE`/`MOVEL` likewise have no free-form
  syntax at all (Test 173). The gate flag was renamed `g_allow_goto_tag`
  → `g_allow_fixed_only_stmts` now that it guards four opcodes, not two.
- **Cost of making them keywords**: `MOVE`/`MOVEL` are now lexer keywords,
  so free-format source can no longer use either as a *variable* name
  (`DCL-S move CHAR(10)` is a syntax error today, where it parsed before).
  Same tradeoff `GOTO`/`TAG` already carry, and both are reserved opcode
  names in RPG, so real source is unlikely to hit it — noted rather than
  discovered later.
- **Fixed a latent gap this exposed**: a CHAR field's generated
  `std::string` is *not* kept at its declared length (a plain `EVAL`
  assigns a shorter string), but real RPG fixed-length fields always are,
  and `MOVE` alignment depends on it. Codegen now wraps a CHAR factor 2
  in `rpg_fixed_len(...)`, and the runtime normalizes the result field
  before moving, so `MOVEL` of a `CHAR(5)` holding `'AB'` correctly moves
  five characters, not two. Only `MOVE`/`MOVEL` are corrected here — the
  broader "CHAR is not padding-faithful" behavior is untouched elsewhere.
- Test 170 covers both directions, both truncation sides, `(P)` on each,
  and a literal factor 2 (which keeps its own length rather than being
  padded to a declared one). Test 153 was repurposed from `MOVE` to
  `CALL`, still deferred, so deferred-opcode rejection stays covered.

**8. `CALL`/`PARM` — traditional program calls ✅.** Old-style program
calls, pervasive in pre-ILE source and the kind of thing that fails a
whole member. V1 supports a `CALL` with its `PARM` lines inline
immediately after it; named `PLIST`s were deferred here and shipped in
item #14 below.
- **How a prototype-less call gets a signature**: `CALLP` works because
  `DCL-PR ... EXTPGM` declared the parameter types; a traditional `CALL`
  has no prototype at all. Codegen synthesizes the callee's signature
  from the `PARM` operands' own declared types — every parameter a `T&`,
  since RPG passes by reference, which is exactly what a non-`VALUE`
  `DCL-PI` parameter generates in the called member. The declaration is
  emitted at **block scope** (legal C++, external linkage), so no
  hoisting pass or output-stream refactor was needed.
- **Mismatches fail at link time, not silently**: if caller and callee
  disagree on types, the two C++ mangled names differ and the link fails.
  An ugly error, but an honest one — and the same failure mode `EXTPGM`
  already has.
- **The program name must be a literal.** A name held in a variable is a
  genuinely dynamic dispatch on IBM i; this compiler links programs
  statically as C++ functions, so there is nothing to compile it to. The
  transpiler refuses it (Test 177) rather than guessing.
- **Cross-line state**: `CSpecRunState` gains a pending-`CALL` block. The
  assembled statement is written back into the `CALL`'s *own* buffer line
  once the `PARM` run ends (any other opcode, or the end of the C-spec
  run), keeping the one-buffer-line-per-physical-line invariant that
  `parse_free_block`'s line numbers depend on. Blank and comment lines
  between `CALL` and its `PARM`s are fine — they never reach
  `feedCSpecLine`. A conditioning indicator on the `CALL` wraps the whole
  thing; one on a `PARM` is refused, since a `PARM` line is part of the
  call's parameter list rather than a statement of its own — SC09-2508
  p.928 forbids one there outright, which item #14 later confirmed.
- **New `CallStmt` AST node**, gated on `g_allow_fixed_only_stmts` like
  `GOTO`/`TAG`/`MOVE` — free-form has `CALLP` instead (Test 179). As with
  `MOVE`, this makes `CALL` a lexer keyword, so free-format source can no
  longer use it as a variable name; `CALLP` is unaffected (flex takes the
  longest match).
- Tests 174 (the NOMAIN callee module it links against, same pattern as
  tests 48/49) and 175 (call, by-reference mutation of both an `INT` and
  a `CHAR` parameter, plus a conditioned `CALL` in both polarities);
  176-179 (rejections).

**9. Modern opcodes in native C-spec ✅.** `XML-INTO`, `DATA-INTO`,
`DATA-GEN` and `SND-MSG` are now reachable from fixed columns. This turned
out to be four table entries and nothing else — the item's framing was
more pessimistic than the work.
- **Extended factor 2 is the right shape**, and that is the whole trick.
  Their operands are free-form expressions by nature (`%XML(doc:opts)`,
  `%DATA(...) %PARSER(...)`, `SND-MSG`'s message-type operand), which is
  exactly what columns 36-80 plus continuation lines carry through to the
  free-format parser untouched. Factor 2's traditional 14-column width
  could never have held a realistic one — reading them as extended factor
  2 sidesteps that entirely. No new grammar, AST node, or codegen change.
- **`ON-EXIT` was mis-filed on this list** and is not a port at all.
  `parser.y` has no standalone rule for it — it appears only inside the
  `DCL-PROC` productions — and fixed-format source cannot declare a
  procedure, since this reader has no P-spec support. It therefore needs
  a `/free` block either way, and now says so in its own error (Test 181)
  instead of promising a fast-follow that would not help.
- **`XML-SAX` and `ON-EXCP` were also mis-filed**: they are not
  implemented anywhere in this compiler (no lexer token, no parser rule),
  so there was never anything to reach from fixed columns. They stay in
  `deferredOpcodes` purely to earn the friendlier "planned" message, and
  `XML-SAX`'s real home is Modern/Stretch item 46.
- Test 180 (`DATA-INTO` with its expression continued across a physical
  line, plus `SND-MSG`); all four opcodes share the one code path with no
  per-opcode logic. Test 137 was repurposed from `SND-MSG` to `XML-SAX`,
  which is still deferred, so the deferred-opcode message stays covered.

**10. `CASxx` / `CABxx` ✅.** Both are comparison-mnemonic opcodes, so
neither can be an opcode-table entry — the mnemonic is glued onto the
opcode itself (`CASGT`), and they are matched by prefix ahead of the table
lookup. `EQ`/`NE`/`LT`/`LE`/`GT`/`GE` map to `=`/`<>`/`<`/`<=`/`>`/`>=`,
and the bare `CAS`/`CAB` forms are the unconditional ones.
- **`CABxx` is self-contained**: a comparison guarding a branch, so it
  transpiles to `IF f1 <op> f2; GOTO label; ENDIF;` — or a plain
  `GOTO label;` for bare `CAB`. It can carry a conditioning indicator.
- **`CASxx` is a group**, and that is the real work here: the lines chain
  like `SELECT`/`WHEN` (the first true comparison runs its subroutine,
  the rest are skipped), so a group transpiles to one `IF`/`ELSEIF`/`ELSE`
  chain that `ENDCS` closes with `ENDIF`. State lives in `CSpecRunState`
  alongside the `AN`/`OR` and pending-`CALL` accumulators. A conditioning
  indicator on a single arm is refused — it would leave the chain
  unbalanced, the same reasoning as the block-structure opcodes.
- **Degenerate groups are caught, not miscompiled**: a group led by an
  unconditional `CAS` needs no `IF` and so gets no `ENDIF`; arms after an
  unconditional one are unreachable and rejected; an orphan `ENDCS`
  (Test 183), a group left unclosed at the end of the run (Test 184), and
  an unrecognized mnemonic (Test 185) each get their own message.
- Test 182 runs the same group four times, hitting each arm including the
  `ELSE`, then exercises both `CABxx` forms.

**11. `COMP` ✅ — and the reason it was deferred turned out to be wrong.**
The old entry said `COMP`'s only effect, setting the `HI`/`LO`/`EQ`
resulting indicators, "has no free-form target at all". That is true of
resulting indicators as a *column feature* — free-form drops them — but
not of `COMP`, because `*INnn` is an assignable target in this compiler.
Each non-blank slot simply becomes one indicator assignment:
`*IN10 = (a > b); *IN20 = (a < b); *IN30 = (a = b);`. Exact, not
approximate.
- `COMP` is therefore the **one** opcode allowed to fill positions 71-76;
  every other opcode still rejects them. The three slots got their own
  `ColSpec`s (71-72 high, 73-74 low, 75-76 equal) and reuse the
  conditioning indicators' validation, so `*INLR` and friends are refused
  the same way there as anywhere else.
- A `COMP` with all three slots blank does nothing at all and is rejected
  rather than silently emitted (Test 187).
- Test 186 reads the results back through *conditioning* indicators,
  exercising both halves of the indicator support against each other.

**12. `EXEC SQL` in fixed columns ✅.** `C/EXEC SQL` … `C+` … `C/END-EXEC`.
The old entry called this "architecturally distinct — the SQL capture is a
dedicated lexer `<SQL>` start-condition, not a column-mapped opcode, so it
doesn't fit the transpile-and-bridge model". The start-condition part is
right; the conclusion was not. Gathering the `C+` lines and emitting one
free-form `EXEC SQL …;` hands the text to that very start condition, which
captures it exactly as it does in free-format source — so the bridge model
fits perfectly and **no SQL parsing was added at all**.
- Handled ahead of the ordinary column layout, since position 7 carries
  the `/` or `+` marker that the control-level field would otherwise
  reject. The gathered statement is written into the `C/EXEC SQL` line's
  own buffer entry, keeping the one-line-per-physical-line invariant.
- An orphan `C/END-EXEC` (Test 189) and a block never terminated
  (Test 190, plus the same check at run flush) each get their own error.
- Test 188 goes end to end against SQLite: connect, create, two inserts,
  a `SELECT … INTO` host variable, and a `COUNT(*)`, with the `CREATE
  TABLE` continued across two `C+` lines.

**13. `MOVE`/`MOVEL` — numeric operands ✅.** The rest of item #7, and the
one the deferred list called the most commonly hit in real legacy source.
The reason it was deferred — "digit-alignment semantics have no
representation in this compiler" — turned out to be a *runtime* gap, not a
semantic one: the semantics are exact and citable, they just needed a
digit string to act on.
- **The rule that decides everything**: SC09-2508 p.633, "if move
  operations are specified between numeric fields, the decimal positions
  specified for the factor 2 field are ignored. For example, if 1.00 is
  moved into a three-position numeric field with one decimal position,
  the result is 10.0." So a numeric `MOVE` is not an assignment and not a
  scaling conversion — it is the *same positional move* the character
  form already does, run over the field's digits instead of its
  characters. Neither operand's decimal point participates. Test 191
  opens with that exact example.
- **Reducing a numeric to digits is the whole implementation.** A
  `PACKED`/`ZONED` field is a C++ `double` here, which carries neither a
  digit count nor a decimal place, so codegen passes both declared
  numbers in (`var_digits_`/`var_decimals_`, with the same
  `var_lengths_` fallback `%SIZE` already uses) and
  `rpg_num_digits(v, digits, dec)` builds the fixed-width digit string.
  The move then runs positionally on that string exactly as
  `rpg_move_fixed` does on characters, and the result is read back
  through the *result* field's decimal places. Same three cases as the
  character form (factor 2 longer / shorter / equal), same `(P)`
  behaviour except that the pad character is `'0'` for a numeric result
  and stays blank for a character one.
- **`llround`, not a cast**, when scaling by 10^dec — binary floating
  point lands an exact `1.00` at `99.999999`, and a truncating cast would
  turn the manual's own worked example into `099`. Found by running it.
- **The sign rules are asymmetric and are implemented as written**, not
  approximated: `MOVE` always moves factor 2's rightmost position, which
  is where the sign lives, so factor 2's sign always wins. `MOVEL`
  (p.905) "retains the sign of the result field except when factor 2 is
  as long as or longer than the result field", so a shorter factor 2
  leaves the result negative if it already was. Test 191 pins all four
  combinations.
- **Character→numeric is always positive, and that is the manual's rule
  rather than a guess.** It asks for a minus sign only when "the zone
  from the rightmost position of factor 2 is a hexadecimal D", and
  otherwise a positive one. That zone is EBCDIC; this compiler stores
  ASCII, where no digit (zone `0x3`) or blank (`0x2`) is ever a D — so
  the rule *evaluates* to positive here, every time. No overpunch
  decoding is invented, consistent with how the I-spec reader already
  refuses `Z`/`D` record-identification code parts. "Blanks are
  transferred as zeros" is implemented literally, so a `CHAR(5)` holding
  `'123'` moves the digits `12300` (Test 192).
- **A character that is not a digit or blank is a data exception**
  (`%STATUS` 907), matching "if the digit portions are not valid digits,
  a data exception error occurs" — the moved digits become zeros and the
  program can test for it (Test 196), rather than the compiler
  reinterpreting the byte.
- **Numeric→character drops the sign, and this is the one deviation.**
  Real IBM i folds it into the EBCDIC zone of the result's rightmost
  character; in ASCII that byte is a printable character with no zone to
  spare, so writing one would corrupt the character rather than carry a
  sign. Digits move, sign does not (Test 193). Flagged here rather than
  buried because it is the only place this item is not exact.
- **Still refused, each with its own message**: float operands (the
  manual disallows them outright — Test 194), date/time results and
  factor 2s, and a *decimal* literal as factor 2 (Test 195) — it reaches
  codegen as a `double` having lost the trailing zeros that decide its
  digit count, and `'1.00'` and `'1.0'` move differently. An *integer*
  literal is accepted, since the digits written are the digits it has.

**14. Named `PLIST` and `PARM` factor 1/2 ✅.** The two thirds of the
deferred `PLIST` entry that did not need any new signature machinery.
- **A named `PLIST` forces a collect-then-substitute pass**, and that is
  the whole reason it was deferred: "a parameter list is ended when an
  operation other than PARM is encountered" (SC09-2508 p.930), but
  nothing requires the `PLIST` to appear *before* the `CALL` that names
  it — real source routinely groups every `PLIST` at the bottom. A
  linear transpiler cannot resolve that in line order, so a `CALL` with a
  name in its Result field now records its buffer index and is filled in
  by `flushCSpecRun`, once every `PLIST` in the run has been seen. Test
  197 puts the definition after all five calls that use it, which is the
  case that fails without the pass.
- **`plists` is the one piece of `CSpecRunState` that survives a flush.**
  A `PLIST` is a program-wide declaration, but a C-spec *run* ends at any
  interleaved spec type, so a run boundary between the definition and a
  later use would otherwise lose it. The reverse order — a `CALL` in an
  earlier run than its `PLIST` — is still refused, since the substitution
  happens at that earlier run's flush; it gets a real diagnostic naming
  the list (Test 200), never a silently argument-less call.
- **`PARM` factor 1/2 turned out to be two plain assignments.** The
  deferral said the direction semantics were unverified, and p.929
  settles them: on the call "the contents of the factor 2 field ... are
  copied into the result field", and on return "the contents of the
  result field ... are copied into the factor 1 field" — each "in the
  same way as data is moved using the EVAL operation code". So factor 2
  is a seed-in and factor 1 a harvest-out, and `buildCallText` brackets
  the `CALL` with one assignment apiece. Both land on the `CALL`'s own
  buffer line, because the `PARM` lines sit *after* it in the source and
  their own entries could never hold statements that must run *before*
  it. Test 198 runs all three shapes (both operands, factor 2 only,
  factor 1 only).
- **Result-field restrictions are enforced, not assumed.** p.929 bars
  `*IN`/`*INxx`, literals, named constants and table names from a `PARM`
  Result field, and bars a literal from factor 1 (which is written to on
  return). Indicators and literals are refused by name (Test 202); a
  named constant is indistinguishable from an ordinary name at this stage
  and reaches codegen, which has the symbol table.
- **One diagnostic per mistake.** A rejected `PLIST` line sets
  `plistSuppress`, so its orphaned `PARM` lines stay quiet instead of
  each reporting itself — without it, `*ENTRY PLIST` reported two errors
  for one cause. Duplicate names (Test 201) and an empty `PLIST` (Test
  176, repurposed from the old "named PLISTs are rejected" test) each get
  their own message.
- **`*ENTRY PLIST` shipped separately** as item #15 — it turned out to be
  a different problem entirely, and needed a design decision rather than
  more transpiler work.

**15. `*ENTRY PLIST` ✅.** The last of the deferred `PLIST` entry, and the
one that was mis-scoped: the old note said it "needs the main-program
signature machinery", but **there is no such machinery**. `DCL-PI` appears
only inside `DCL-PROC` in `parser.y`, and a compiled program is an
`int main()` taking no arguments — free-format has no way to give the main
program parameters either. So this was never a port; it was a decision
about what a *program with parameters* compiles to at all.
- **A member with an `*ENTRY PLIST` compiles to a callable function, not
  a `main()`.** `void <NAME>(T1&, T2&, ...)`, holding the mainline, with
  every parameter a reference because RPG passes by address — which is
  exactly the signature a caller's traditional `CALL` already synthesizes
  from its own `PARM` operands (item #8), so the two link with no new
  machinery on the calling side. The alternative, filling parameters from
  `argv`, was rejected: a process cannot write back to its caller, so the
  *output* half of `*ENTRY` semantics would be silently lost, and output
  parameters are the common case in real entry lists.
- **The name comes from the source file**, upper-cased with directory and
  extension stripped: `ORD100.rpgle` is reachable as `CALL 'ORD100'`.
  Fixed-format source has no P-spec to name a procedure with, so the file
  name is the only thing both sides can agree on. A file name that is not
  a usable symbol is refused with an explicit "rename the source file"
  message rather than emitting an uncompilable one. This is why the test
  callee is `tests/ADDTWO.rpgle` and not a `testNNN` name.
- **The parameters are declared twice and stored once.** They are ordinary
  D-spec fields *and* the function's C++ parameters, so codegen registers
  their types as usual but suppresses the local declaration
  (`entry_params_`) — leaving the caller's storage as the single location
  the body reads and writes, which is what p.929's "each parameter field
  has only one storage location" requires.
- **Factor 1 works; factor 2 is refused.** p.929 step 3 puts the
  result→factor 1 copy "after it receives control and after any normal
  program initialization", so it is emitted once, after `*INZSR`, before
  the first executable statement. Step 4's factor 2→result copy happens
  *on return* — at every exit point, each `RETURN` plus falling off the
  end — which this line-by-line transpiler cannot place, so it is
  rejected with a message saying to assign to the parameter directly
  (Test 205).
- **`NOMAIN` with `*ENTRY` is an error** (Test 199, repurposed): `NOMAIN`
  discards the mainline, which is the very thing `*ENTRY` turns into the
  function, so together they compiled to an empty file.
- **Fixed a pre-existing bug this exposed**: a bare `RETURN` emitted
  `return 0;` regardless of the enclosing function's return type, so it
  did not compile inside *any* `void` function — a `DCL-PROC` with no
  return type already had this, `*ENTRY` just made it unavoidable (a
  fixed-format mainline almost always ends in `C RETURN`). Codegen now
  tracks `void_return_` and emits a bare `return;`.
- Tests 203 (the `ADDTWO` callee) and 204, which calls it twice — once
  with inline `PARM`s and once through a named `PLIST` defined after the
  call — so items #14 and #15 meet end to end. 205-207 are the
  rejections.

**16. `MOVE`/`MOVEL` date/time conversion ✅.** The last of the deferred
fast-follow list, and what items #7 and #13 both left out: a date, time or
timestamp on either side of the move, plus the Factor-1 format form
(`C  *MDY  MOVE  chr  datefld`) that #7 rejected outright.
- **It turned out not to be a different kind of move at all.** The reason
  this was deferred — "genuine format conversions rather than positional
  moves" — held only for the *conversion*. SC09-2508 p.406 settles the
  rest: "If character or numeric data is longer than required, only the
  leftmost data (rightmost for the MOVE operation) is used." That is the
  same left/right positional rule #7 and #13 already implement. So the
  conversion produces a text exactly as wide as the format defines, and
  `rpg_move_fixed`/`rpg_move_num_fixed` then place it unchanged — one
  new step in front of machinery that already existed, not a second
  move implementation. Test 211 pins both directions of that.
- **Thirteen combinations, and the manual lists them by name** (p.405):
  each of Date/Time/Timestamp to its own type, Date and Time *to* a
  timestamp, Timestamp *to* a date and to a time, each of the three to
  character or numeric, and character or numeric to each of the three.
  Date-to-Time and Time-to-Date are absent, and are refused with a
  message pointing at the timestamp, which is the only thing that
  carries both (Test 171, repurposed from #7's date rejection).
- **Factor 1 is the format of the character or numeric operand, never of
  the date field.** "Factor 1 must be blank if both the source and the
  target of the move are Date, Time or Timestamp fields. If factor 1 is
  blank, the format of the Date, Time, or Timestamp field is used." Both
  halves are implemented: a factor 1 with two date/time operands is an
  error (as is a factor 1 with neither — Test 172, likewise repurposed),
  and a blank one falls back to the field's own DATFMT/TIMFMT, then the
  H-spec's, then `*ISO`.
- **A format carries its own separator.** `*MDY/` names one explicitly,
  `*MDY0` says the character field has none at all, and a bare `*MDY`
  takes the format's default. Codegen validates the separator against
  the set the format allows (Tables 13, 15 and 16) — and needs no
  separate default-separator table, since the default is the first entry
  in each of those sets. Numeric operands never carry separators, per
  "If the result field is numeric, separator characters will be removed."
- **The year-range rules are enforced, not just documented.** A 2-digit
  year format reaches 1940-2039 and a 3-digit one 1900-2899 (p.193), and
  a value outside the *result* field's range is error 114 with the result
  left unchanged — which is what Figure 287's own `*HIVAL` move produces.
  This is checked even on a plain date-to-date move, where the internal
  value is format-independent here, so that example reproduces exactly.
- **Fixed a pre-existing bug this uncovered**: `*CYMD`/`*CMDY`/`*CDMY`
  were being rendered and parsed as `c/yy/mm/dd` — ten characters with
  the century digit separated — where Table 15 gives `cyy/mm/dd`, nine,
  with the century digit joined to the year. The century digit was also
  treated as a 19xx/20xx flag rather than its documented `1900 + c*100`
  range. Both were wrong in `%CHAR(date:*CYMD)` and `%DATE(str:*CYMD)`
  too, so the fix is in the shared legacy helpers, not just the new path.
- **Fixed-format D-specs now read per-field `DATFMT`/`TIMFMT`.** Only the
  H-spec forms were parsed before; the free-format `DCL-S` has always
  had the per-field keywords, and a blank factor 1 needs them.
- **Still refused, each with its own message**: `*JOBRUN` (Test 213),
  which takes its format and separator from runtime job attributes this
  compiler has no equivalent of; time format `*USA` against a numeric
  field, which the manual disallows outright and whose AM/PM suffix is
  not a digit anyway (Test 214); and a varying-length result, which was
  already out of scope for the character form.
- **`(P)` on a date/time *result* is accepted and does nothing** — there
  is no remainder to blank in a date field. It still pads a character
  result the conversion did not fill (Figure 289's `*ISO0` timestamp).
- Tests 208-210 reproduce Figures 287, 288 and 289 value for value, so
  the manual is the oracle rather than this compiler's own output. 211 is
  the alignment/truncation pinning above, 212 the runtime failures
  (status 112, result unchanged), 213-214 the rejections.

### Fixed C-spec — Deferred Fast-Follow ✅ (cleared)
Items explicitly deferred (not silently dropped) out of items #1 and #3
above when each shipped — kept here as their own trackable list instead of
staying buried in a completed item's writeup. Both entries are now closed.

1. ~~**`MOVE`/`MOVEL` date/time conversion.**~~ — done: item #16 above.
2. ~~**Named `PLIST`, `*ENTRY PLIST`, and `PARM` factor 1/2.**~~ — done:
   items #14 and #15 above. The one piece deliberately left behind is
   **factor 2 on an `*ENTRY` PARM**, the return-time copy back to the
   caller: it has to happen at every exit point, which a line-by-line
   transpiler cannot place, and it is refused rather than approximated
   (Test 205). Doing it properly means a control-flow pass over the
   mainline — a single exit rewrite, or a scope guard — which is a
   bigger change than this entry ever covered. This is the only thing
   still outstanding from either entry.

### ~~Fixed-Format File I/O~~ — Not Planned
~~Native record format / INFSR / legacy PLIST-based file I/O~~ — item #4
above *does* now implement program-described (byte-position) record I/O
for fixed-format source; what stays not-planned here is INFSR (file
exception/error subroutines) and legacy `PLIST`-based parameter-list file
operations, neither of which item #4 touches.

### Embedded SQL (via ODBC)

#### Phase 1 — Foundation ✅
| # | Feature | Details |
|---|---------|---------|
| 18 | ✅ EXEC SQL parsing | Lexer `<SQL>` start condition, captures raw SQL until `;` as `EXEC_SQL_TEXT` token |
| 19 | ✅ Host variables | Extract `:varName` references, replace with `?` parameter markers |
| 20 | ✅ ExecSqlStmt AST node | Single node with `SqlStmtKind` enum (avoids 15+ separate node classes) |
| 21 | ✅ SQL utility functions | `src/sql_utils.h/.cpp` — `extractHostVariables()`, `replaceHostVarsWithMarkers()`, `classifySqlStmt()` |
| 22 | ✅ ODBC runtime wrapper | `runtime/rpg_sql_runtime.h` — `RpgSqlEnv` class (connection, cursor, prepared stmt management) |

#### Phase 2 — Core SQL Statements ✅
| # | Feature | RPG Syntax | ODBC Mapping |
|---|---------|-----------|-------------|
| 23 | ✅ SELECT INTO | `EXEC SQL SELECT col INTO :var FROM tbl WHERE ...;` | `SQLPrepare` + `SQLBindCol` + `SQLExecute` + `SQLFetch` |
| 24 | ✅ INSERT | `EXEC SQL INSERT INTO tbl VALUES(:v1, :v2);` | `SQLPrepare` + `SQLBindParameter` + `SQLExecute` |
| 25 | ✅ UPDATE | `EXEC SQL UPDATE tbl SET col = :v WHERE ...;` | Same as INSERT |
| 26 | ✅ DELETE | `EXEC SQL DELETE FROM tbl WHERE ...;` | Same as INSERT |
| 27 | ✅ COMMIT | `EXEC SQL COMMIT;` | `SQLEndTran(SQL_COMMIT)` |
| 28 | ✅ ROLLBACK | `EXEC SQL ROLLBACK;` | `SQLEndTran(SQL_ROLLBACK)` |
| 29 | ✅ SQLCODE / SQLSTATE | `SQLCOD` / `SQLSTT` variables | `SQLGetDiagRec` → `__sql_env.sqlcode` / `.sqlstate` |

#### Phase 3 — Cursor Operations ✅
| # | Feature | RPG Syntax | ODBC Mapping |
|---|---------|-----------|-------------|
| 30 | ✅ DECLARE CURSOR | `EXEC SQL DECLARE C1 CURSOR FOR SELECT ...;` | `SQLPrepare` (store handle in cursor map) |
| 31 | ✅ OPEN | `EXEC SQL OPEN C1;` | `SQLExecute` on cursor's stmt handle |
| 32 | ✅ FETCH | `EXEC SQL FETCH C1 INTO :v1, :v2;` | `SQLBindCol` + `SQLFetch` |
| 33 | ✅ CLOSE | `EXEC SQL CLOSE C1;` | `SQLFreeStmt(SQL_CLOSE)` |

#### Phase 4 — Connection Management ✅
| # | Feature | RPG Syntax | ODBC Mapping |
|---|---------|-----------|-------------|
| 34 | ✅ CONNECT | `EXEC SQL CONNECT TO :dsn USER :u USING :p;` | `SQLConnect` |
| 34a | ✅ CONNECT (conn string) | `EXEC SQL CONNECT USING :connStr;` | `SQLDriverConnect` |
| 34b | ✅ CONNECT RESET | `EXEC SQL CONNECT RESET;` | `SQLDisconnect` |
| 35 | ✅ DISCONNECT | `EXEC SQL DISCONNECT;` | `SQLDisconnect` |
| 36 | — SET CONNECTION | Not supported (single connection per program) | — |

#### Phase 5 — Dynamic SQL ✅
| # | Feature | RPG Syntax | ODBC Mapping |
|---|---------|-----------|-------------|
| 37 | ✅ PREPARE | `EXEC SQL PREPARE S1 FROM :sqlStr;` | `SQLPrepare` (store handle) |
| 38 | ✅ EXECUTE | `EXEC SQL EXECUTE S1 USING :v1, :v2;` | `SQLBindParameter` + `SQLExecute` |
| 39 | ✅ EXECUTE IMMEDIATE | `EXEC SQL EXECUTE IMMEDIATE :sqlStr;` | `SQLExecDirect` |

#### Phase 6 — Advanced Features ✅
| # | Feature | RPG Syntax | ODBC Mapping |
|---|---------|-----------|-------------|
| 40 | ✅ Indicator variables | `:var :ind` | `SQLLEN` indicator in bind calls |
| 41 | ✅ GET DIAGNOSTICS | `EXEC SQL GET DIAGNOSTICS :rc = ROW_COUNT;` | `SQLGetDiagRec` / `SQLGetDiagField` |
| 42 | ✅ CALL procedures | `EXEC SQL CALL proc(:p1, :p2);` | `SQLPrepare("{CALL proc(?,?)}")` + bind |
| 43 | ✅ SAVEPOINT | `EXEC SQL SAVEPOINT sp1;` | SQL passthrough (driver-dependent) |
| 44 | ✅ Multiple-row FETCH | `FETCH ... FOR :n ROWS` | Loop with `SQLFetch` into array elements |
| 45 | ✅ Multiple-row INSERT | `INSERT ... FOR :n ROWS` | Loop with `SQLExecute` per array element |

#### Architecture Notes
- **Lexer**: `EXEC SQL` triggers exclusive start condition `<SQL>`, captures until `;`
- **Parser**: Single `exec_sql_stmt` rule; classification via utility function (not a full SQL parser)
- **AST**: Single `ExecSqlStmt` node with `SqlStmtKind` enum
- **Runtime**: Separate `rpg_sql_runtime.h` (programs without SQL don't need ODBC)
- **Linking**: `-lodbc` added only when SQL is used (codegen sets `uses_sql_` flag)
- **SELECT INTO**: `INTO :var1, :var2` clause stripped from SQL sent to ODBC (uses `SQLBindCol` instead)

### Modern/Stretch

| # | Feature |
|---|---------|
| 46 | XML-SAX (%HANDLER) |
| 47 | Remaining CTL-OPT keywords (USRPRF, VALIDATE) |

---

## 🗳 Community-Requested Features (IBM Ideas Portal)

**Source:** <https://ibm-power-systems.ideas.ibm.com/ideas/?category=7078724330326335155>
Append `&sort=popular&page=N` to walk the list vote-ranked, highest first
(~290 ideas over 29 pages as of the last pull).

**Last pulled: 2026-08-29** — vote-sorted walk down to a 20-vote floor
(~60 of ~290 ideas reviewed).

Why this list exists: the portal is a free, continuously-updated, vote-ranked
backlog of what real RPG shops actually want from the language. IBM marks many
of the *highest*-voted entries "Not under consideration" — usually because of
ILE/IBM i compatibility constraints this compiler doesn't carry. Those are the
**highest**-value entries here, not the lowest: they're things RPG developers
demonstrably want and will never get from IBM.

### Maintenance rule (followed by the monthly automated re-pull)

1. Walk `…&sort=popular&page=N` from N=1 upward, one page at a time, collecting
   each idea's title, vote count and IBM status. Stop once vote counts drop
   below **20** (~6 pages, ~60 ideas). If page 1 comes back *not* vote-ordered,
   the sort parameter has broken — say so, and walk unsorted pages 1–10 instead.
2. Diff against **this whole file**, not just this section. Skip anything
   already covered under Implemented Features, Remaining Work, or Not Planned,
   or already listed in a tier below. Vote counts drift — refresh them in place
   rather than adding duplicate rows.
3. For genuinely new ideas, judge fit by **reading the actual code**
   (`src/lexer.l`, `src/parser.y`, `src/codegen.cpp`, `runtime/`, `OpenDSPF/`)
   before estimating effort — don't guess. Keep each row's note concrete and
   specific to this codebase; effort notes here are first-read judgments against
   the code, not designs.
4. Sort into the tiers below. **Tier 1 (IBM declined it, and it's cheap here) is
   the highest-value tier, not the lowest** — those are things RPG shops
   demonstrably want and will never get from IBM, because IBM carries ILE/IBM i
   compatibility constraints this compiler doesn't.
5. Update the **Last pulled** date in this section's header.
6. If nothing changed, don't open a PR — just report that. Otherwise commit to a
   branch `ideas-pull-YYYY-MM` and open a PR against `main` titled
   `TODO: IBM Ideas portal pull YYYY-MM`, whose body lists what was added, which
   vote counts moved, and anything deliberately skipped and why. **`TODO.md`
   only — the re-pull never changes code.**

### Tier 1 — IBM declined it, and it's cheap here

The differentiators. Every row is "Not under consideration" at IBM.

| Votes | Idea | Why it's cheap here |
|-------|------|---------------------|
| **93** | RPG block comments (`/* … */`) | Highest-voted RPG idea in the whole portal. One flex rule in `lexer.l` (alongside the existing `"//".*`). Caveat: fixed-format needs separate handling in `fixed_reader.cpp`, where `*` in column 7 is already the comment marker. |
| **90** | DSPF/PRTF definitions from an open format (XML/JSON) | OpenDSPF *already* compiles DDS → a JSON descriptor. Accepting that JSON as `dspfc` **input** is mostly plumbing — shipping the exact thing IBM declined. |
| 40 | `%FKEY` built-in function | `rpg_dspf_runtime.h` already decodes `KEY_F(1)`–`KEY_F(24)` into a function-key number; this is a BIF over state already tracked. |
| 39 | Multiple definitions in one `DCL-S` | Grammar-only change. |
| 37 | String interpolation | Lexer change + desugar to concatenation in codegen. No runtime work. |
| 30 | Procedure inside a procedure | Subroutines already codegen as C++ lambdas — the mechanism exists. |
| 30 | A `NOT IN` operator | `IN` already ships (Test 58). |
| 28 | Regular-expression BIFs | `std::regex` — the compiler already uses it (`sql_utils.cpp`); generated code would too. |
| 27 | Relax the `%SUBST` "length exceeds data" error | Diagnostic policy, not new machinery. |
| 25 | `%CHAR` with `%EDITC` formatting | Both BIFs already ship; this merges them. |
| 15 | Multiple conditions in one `/IF` directive | Directive handling already lives in the lexer. |
| 13 | `*TRUE` / `*FALSE` figurative constants | `BOOLEAN` already ships (Test 71). |

### Tier 2 — "Future consideration" at IBM, small-to-medium here

| Votes | Idea | Note |
|-------|------|------|
| **93** | Conditional (ternary) operator `?:` in EVAL | Ties for #1 overall. C++ has it natively, so codegen is a passthrough; grammar is the work. |
| 49 | Keyword parameters in prototyped calls | |
| 49 | `%SCANRPL` limited to `*FIRST` / `*LAST` occurrence | `SCANRPL` already in `codegen.cpp`. |
| 48 | `OPTION(*UPPER)` / `OPTION(*LOWER)` on parameters | |
| 44 | Dynamic strings (declare CHAR without a length) | `CHAR` is already a `std::string`. |
| 41 | Initialize arrays with `%LIST` | `%LIST` already ships. |
| 39 | `%XFOOT` over subfields of a DS array | |
| 38 | BIF for comparing data structures | |
| 35 | `DEPRECATED` keyword on procedures | Just a compiler warning. |
| 34 | `%LOOKUP` searching more than one subfield | |
| 29 | `%REPEAT` BIF | |
| 28 | Default values for `*NOPASS` / `*OMIT` parameters | |
| 27 | `%PROGNAME` BIF | |
| 26 | Binary literals, like the hex form | Hex literals already ship (Test 112). |
| 22 | Named index of the current `FOR-EACH` iteration | |
| 22 | Comparison procedure for `SORTA` / `%LOOKUPxx` | |
| 22 | `WHEN-IS-NOT` on the newer `SELECT` | Needs `SELECT`/`WHEN-IS` first. |
| 18 | `%SCANRPL` first/last (duplicate filing of the 49-vote entry) | |
| 16 | `*EMPTY` figurative constant | |
| 14 | `%HEX` / `%TOHEX` / `%FROMHEX` | |
| 12 | `/MESSAGE` compiler directive | |

### Larger, but worth their vote count

| Votes | Idea | Note |
|-------|------|------|
| 86 | Restrict global-variable use in subprocedures | A `DCL-PROC` keyword plus a codegen-time scope check — the `report_semantic_error` channel built for `MOVE` is the right home. |
| 45 | `FOR-EACH` over record-level access | RLA over ODBC already ships (Tests 103–108); this is a real but tractable iterator. |
| 38 / 33 | Consistent null handling / full NULL support | Partly touched by SQL indicator variables; genuinely deep otherwise. |

### Already satisfied here (confirm + document, no work)

| Votes | Idea | Status in this compiler |
|-------|------|-------------------------|
| 60 | Make `%DEC()` 2nd & 3rd parms optional | Already true — `%DEC` codegen is `static_cast<double>(…)` and ignores digits/decimals entirely. |
| 30 | Expand the 16,773,104-byte limit within data structures | No such limit exists here. |
| 26 | Raise maximum variable length to 4GB | No such limit exists here — strings are `std::string`. |

### Reviewed and not planned

Cross-check against **❌ Not Planned** below before re-adding any of these.

| Votes | Idea | Why not |
|-------|------|---------|
| 76 | Rename "ILE/RPG" to "RPG for i" | Not a compiler feature. |
| 38 / 1 | Native CLOB/BLOB in RPG | Already declined under *Embedded SQL — Not Planned* (LOB support varies wildly by ODBC driver). |
| 36 | Control joblog writes with `ON-ERROR` | IBM i runtime. |
| 36 | Mixed-case DB2 column names in DS | IBM i catalog behavior. |
| 34 | `EXTNAME`/`LIKEREC(*NULL)` SQL indicator subfields | `LIKEREC`/`EXTNAME` options are already Not Planned. |
| 27 | `*NODEBUGSQL` control option | IBM i compilation directive. |
| 24 | Exclude hidden fields from externally-described DS | IBM i catalog behavior. |
| 23 | `DECFLOAT` data type | Needs a real decimal library — large, standalone. |
| 20 | Better UTF-8 (CCSID 1208) support | `CCSID` is already Not Planned; real work, deep. |
| 16 | Prohibit changing a program's activation group | Activation groups are parsed for compatibility only. |

---

## ❌ Not Planned

These features are IBM i-specific, legacy, or otherwise not applicable:

### Embedded SQL — Not Planned
- SQLTYPE (CLOB, BLOB, XML) — LOB support varies wildly by ODBC driver
- SQLDA (Descriptor Area) — Complex, rarely used, requires dynamic memory allocation
- WHENEVER — Legacy error handling; programs should check SQLCODE directly
- SET OPTION — IBM i compilation directive, no C++ equivalent
- DESCRIBE — Requires SQLDA support
- DBCLOB — Double-byte, IBM i specific
- XML variants (XML_BLOB, XML_CLOB) — IBM i specific

### IBM i-Specific
- %GRAPH, %UCS2, %SHTDN — IBM i encoding/shutdown
- CCSID — Character set conversion IDs
- FROMFILE/TOFILE — Compile-time array file keywords
- SERIALIZE — Serialized procedure access (job locking)
- ACTGRP semantics — Activation group (parsed for compatibility)
- INFDS — File Information Data Structure
- LIKEREC, LIKEFILE, EXTNAME options (*ALL/*INPUT/*OUTPUT/*KEY)
- ALIGN — Subfield alignment (C++ handles natively)
- LEN(n) — Explicit DS length
- NULLIND — Null indicator association
- OPDESC — Operational descriptors
- RTNPARM, NOOPT — Procedure/variable keywords
- %OPEN, %KDS, %FIELDS, %EQUAL, %NULLIND — File/Record BIFs
- BNDDIR — Binding directory
- STGMDL, ALLOC(*TERASPACE) — Storage model
- Open Access / Handler programs
- *ENTRY — Entry point parameter list
- %THIS — Java object reference

### CTL-OPT Keywords (all accepted/ignored, no implementation)
- ALWNULL, ALTSEQ, AUT, CHARCOUNT, COPYNEST, CURSYM, DATEDIT, DECPREC
- DFTNAME, ENBPFRCOL, EXPROPTS, EXTBININT, FIXNBR, FLTDIV, FORMSALIGN
- GENLVL, INDENT, INTPREC, LANGID, OPTIMIZE, OPENOPT, PRFDTA, REQPREXP
- SRTSEQ, TGTCCSID, TGTRLS, TRUNCNBR

### Declaration Keywords
- OPTIONS(*VARSIZE/*STRING/*TRIM/*RIGHTADJ/*CONVERT/*EXACT)
- VARYING, CCSID(n), DTAARA, PERRCD, EXTFMT

### Legacy / Fixed-Format
- RPG cycle processing (detail calc, total calc, LR indicator) — rejected
  outright, independent of any fixed-format C-spec work below
- CTDATA, ALT(array), OCCURS/%OCCUR
- Traditional/extended-factor-2 fixed-column C-spec (modern opcodes in
  column form) and truly legacy opcodes (ADD, SUB, MULT, DIV, MOVE, COMP,
  GOTO, TAG, CALL, PARM, PLIST, etc.) are **no longer rejected outright** —
  see "Fixed-Format Source Support — Next Steps" above, ranked #1 and #3
  respectively, now that the goal is accepting most real fixed-format
  source rather than just the common cases
- I-specs, O-specs (fixed-format record I/O) — deferred, not rejected
  outright; see "Fixed-Format Source Support" above (ranked #4). Real
  shops overwhelmingly use externally-described files, so this covers
  little missed value for a lot of engineering (two full column layouts
  each, program- vs. externally-described, with cross-line state)

Note: `/FREE`...`/END-FREE` itself is *not* rejected — see "Fixed-Format
Source Support" above. What's rejected here is reviving the RPG cycle and
legacy fixed-column opcode semantics, not the ability for a fixed-format
member's C-spec to host modern free-format statements.

### Indicator Types (beyond *IN01-*IN99, *INLR)
- *INKx, *INHx, *INOx, *INLx, *INUx, *INRT, *INMR, *IN array

---

## Test Index

| Test | Description |
|------|-------------|
| 01 | Hello World |
| 02 | Arithmetic |
| 03 | Types |
| 04 | BIFs |
| 05 | IF |
| 06 | Loops |
| 07 | Select |
| 08 | Procedures |
| 09 | Data Structures |
| 10 | Expanded BIFs |
| 11 | Error Reporting |
| 12 | Monitor |
| 13 | Subroutines |
| 14 | Indicators |
| 15 | DOU Loop |
| 16 | /COPY Include |
| 17 | Named Constants |
| 18 | Date/Time |
| 19 | Math BIFs |
| 20 | Memory BIFs |
| 21 | %PARMS |
| 22 | %STATUS/%ERROR |
| 23 | RESET/CLEAR |
| 24 | %MAX/%MIN |
| 25 | DCL-F |
| 26 | Pointers |
| 27 | Arrays |
| 28 | Conditional Compilation |
| 29 | DCL-SUBF/DCL-PARM |
| 30 | LIKE |
| 31 | LOOKUP and SORTA |
| 32 | EDITC/EDITW |
| 33 | REPLACE |
| 34 | CHECK/CHECKR |
| 35 | EVAL-CORR |
| 36 | DS Params |
| 37 | *INZSR |
| 38 | CTL-OPT |
| 39 | Figurative Constants |
| 40 | EVALR/LEAVESR |
| 41 | String/Math BIFs |
| 42 | ON-EXIT |
| 43 | STATIC |
| 44 | ALLOC/DEALLOC |
| 45 | Array BIFs |
| 46 | OPTIONS(*NOPASS) |
| 47 | TEST Opcode |
| 48 | NOMAIN Module |
| 49 | EXTPROC/IMPORT |
| 50 | Numeric BIFs |
| 51 | String BIFs |
| 52 | Array BIFs |
| 53 | Date/Time BIFs |
| 54 | Memory/Pointer BIFs |
| 55 | Figurative Constants |
| 56 | MAIN(procname) |
| 57 | DATFMT/TIMFMT |
| 58 | FOR-EACH and IN |
| 59 | %PASSED/%OMITTED |
| 60 | Data Types |
| 61 | No **FREE |
| 62 | OVERLAY/POS |
| 63 | PREFIX |
| 64 | OPTIONS(*OMIT) |
| 65 | DFTACTGRP/ACTGRP |
| 66 | *PSSR |
| 67 | *PSSR Error |
| 68 | Bitwise & Power |
| 69 | %SCANR |
| 70 | %EDITFLT & %UNSH |
| 71 | Enum & Boolean |
| 72 | DIM(*VAR) |
| 73 | Date Formats |
| 74 | %CONCAT |
| 75 | %TLOOKUP & %ELEM |
| 76 | DS DIM(*VAR) |
| 77 | Embedded SQL |
| 78 | SQL in Procedures |
| 79 | SQL Core Statements |
| 80 | SQL Cursors |
| 81 | Dynamic SQL |
| 82 | SQL Advanced |
| 83 | SQL Multi-row |
| 84 | SQL Connect |
| 85 | %GETENV |
| 86 | SQL End-to-End (DS FETCH, cursors) |
| 87 | XML-INTO (direct mode, %XML, case options) |
| 88 | XML-INTO array DS (fixed DIM, DIM(*VAR), path option) |
| 89 | XML-INTO path option + nested DS (LIKEDS subfields) |
| 90 | PSDS Basic |
| 91 | PSDS + MONITOR |
| 92 | Data Area *LDA round-trip |
| 93 | Data Area named |
| 94 | Extender (H) Half-Adjust |
| 95 | Extender (E) Error |
| 96 | DA Status 401 (not found) |
| 97 | DA Status 415 (cannot read) |
| 98 | DA Status 413 (cannot write) |
| 99 | DATA-INTO JSON parsing |
| 100 | DATA-GEN JSON generation |
| 101 | *USER figurative constant |
| 102 | SND-MSG |
| 103 | RLA CHAIN / %FOUND |
| 104 | RLA READ sequential |
| 105 | RLA WRITE/UPDATE/DELETE |
| 106 | RLA SETLL/READE |
| 107 | SQL via rpgc.conf (no CONNECT) |
| 108 | RLA via rpgc.conf (no CONNECT) |
| 109 | SQL indicator variables |
| 110 | OVERLOAD procedures |
| 111 | %ELEM(*ALLOC)/%ELEM(*KEEP) |
| 112 | DATA-INTO CSV parsing (%PARSER('CSV')) |
| 113 | DATA-GEN CSV generation (%PARSER('CSV')) |
| 114 | DATA-INTO/GEN explicit %PARSER('JSON') |
| 115 | DUMP opcode |
| 116 | Fixed-format: H+D specs only |
| 117 | Fixed-format: H+D+C(/free) hello world |
| 118 | Fixed-format: H+F+D+C DISK CHAIN, full Phase 1 milestone |
| 119 | Fixed-format: syntax error inside /free |
| 120 | Fixed-format: VARCHAR standalone field (VARYING) |
| 121 | Fixed-format: VARCHAR DS subfield (VARYING) |
| 122 | Fixed-format: DISK CHAIN with a VARCHAR key |
| 123 | Fixed-format: DIM(n) array of DS |
| 124 | Fixed-format: subfield OVERLAY/POS |
| 125 | Fixed C-spec: IF/ELSEIF/ELSE/ENDIF |
| 126 | Fixed C-spec: DOW/DOU/ENDDO |
| 127 | Fixed C-spec: FOR/ENDFOR (TO/DOWNTO/BY) |
| 128 | Fixed C-spec: SELECT/WHEN/OTHER/ENDSL |
| 129 | Fixed C-spec: BEGSR/EXSR/ENDSR |
| 130 | Fixed C-spec: EVAL/EVALR/CALLP/RETURN/LEAVE/ITER |
| 131 | Fixed C-spec: CLEAR/RESET/DSPLY/SORTA |
| 132 | Fixed C-spec: MONITOR/ON-ERROR/ENDMON |
| 133 | Fixed C-spec: Extended-Factor-2 continuation across lines |
| 134 | Fixed C-spec: mixed with an explicit /free block |
| 135 | Fixed C-spec: reject non-blank control level |
| 136 | Fixed C-spec: reject misaligned cond indicator |
| 137 | Fixed C-spec: reject deferred opcode (CHAIN) with distinct message |
| 138 | Fixed C-spec: reject legacy opcode (ADD) |
| 139 | Fixed-format /COPY: D-spec copybook |
| 140 | Fixed-format /INCLUDE: C-spec copybook mid-run |
| 141 | Fixed-format /COPY: nested copybooks |
| 142 | Fixed-format /COPY inside an explicit /free block |
| 143 | Fixed-format /COPY: missing file rejected |
| 144 | Fixed C-spec: CHAIN by key, %FOUND |
| 145 | Fixed C-spec: READ sequential, %EOF |
| 146 | Fixed C-spec: WRITE/UPDATE/DELETE |
| 147 | Fixed C-spec: SETLL/READE |
| 148 | Fixed C-spec: GOTO/TAG backward loop + forward skip |
| 149 | Fixed C-spec: GOTO/TAG inside BEGSR |
| 150 | Fixed C-spec: ADD/SUB/MULT/DIV (both Factor 1 forms) |
| 151 | Fixed C-spec: Z-ADD/Z-SUB |
| 152 | Fixed C-spec: reject GOTO inside explicit /free block |
| 153 | Fixed C-spec: reject deferred legacy opcode (CALL) |
| 154 | Fixed I-spec: single record type, sequential READ |
| 155 | Fixed I-spec: multi record type dispatch |
| 156 | Fixed I-spec: field indicators (plus/minus/zero) |
| 157 | Fixed I-spec: UPDATE rewrites record in place |
| 158 | Fixed O-spec: field placement + edit code |
| 159 | Fixed I-spec: reject zone record-ID test |
| 160 | Fixed I-spec: reject matching fields (M1) |
| 161 | Fixed D-spec: per-subfield DIM(n) |
| 162 | Fixed D-spec: per-subfield LIKE(field) |
| 163 | Free-format: per-subfield LIKE/DIM declaration + access |
| 164 | Fixed C-spec: conditioning indicators |
| 165 | Fixed C-spec: reject cond ind on block opcode |
| 166 | Fixed C-spec: reject unsupported cond indicator |
| 167 | Fixed C-spec: AN/OR indicator groups |
| 168 | Fixed C-spec: reject orphan AN line |
| 169 | Fixed C-spec: reject dangling cond ind line |
| 170 | Fixed C-spec: MOVE/MOVEL character move |
| 171 | Fixed C-spec: reject MOVE date to time |
| 172 | Fixed C-spec: reject MOVE format, no date operand |
| 173 | Free-format: reject MOVE (fixed-format only) |
| 174 | CALL callee module (NOMAIN) |
| 175 | Fixed C-spec: CALL/PARM program call |
| 176 | Fixed C-spec: reject PLIST with no PARM |
| 177 | Fixed C-spec: reject dynamic CALL name |
| 178 | Fixed C-spec: reject PARM without CALL |
| 179 | Free-format: reject CALL (fixed-format only) |
| 180 | Fixed C-spec: DATA-INTO / SND-MSG |
| 181 | Fixed C-spec: reject ON-EXIT (proc-only) |
| 182 | Fixed C-spec: CASxx chain + CABxx branch |
| 183 | Fixed C-spec: reject orphan ENDCS |
| 184 | Fixed C-spec: reject unclosed CASxx group |
| 185 | Fixed C-spec: reject bad CASxx mnemonic |
| 186 | Fixed C-spec: COMP resulting indicators |
| 187 | Fixed C-spec: reject COMP with no indicators |
| 188 | Fixed C-spec: embedded SQL (C/EXEC SQL) |
| 189 | Fixed C-spec: reject orphan C/END-EXEC |
| 190 | Fixed C-spec: reject unterminated EXEC SQL |
| 191 | Fixed C-spec: MOVE numeric to numeric |
| 192 | Fixed C-spec: MOVE character to numeric |
| 193 | Fixed C-spec: MOVE numeric to character |
| 194 | Fixed C-spec: reject MOVE on float field |
| 195 | Fixed C-spec: reject MOVE decimal literal |
| 196 | Fixed C-spec: MOVE invalid digit -> 907 |
| 197 | Fixed C-spec: named PLIST |
| 198 | Fixed C-spec: PARM factor 1/factor 2 |
| 199 | Fixed C-spec: reject *ENTRY with NOMAIN |
| 200 | Fixed C-spec: reject undefined PLIST name |
| 201 | Fixed C-spec: reject duplicate PLIST name |
| 202 | Fixed C-spec: reject literal PARM result |
| 203 | *ENTRY callee module (ADDTWO) |
| 204 | Fixed C-spec: *ENTRY PLIST call |
| 205 | Fixed C-spec: reject *ENTRY PARM factor 2 |
| 206 | Fixed C-spec: reject undeclared *ENTRY parm |
| 207 | Fixed C-spec: reject CALL naming *ENTRY |
| 208 | Fixed C-spec: MOVE date conversions (Figure 287) |
| 209 | Fixed C-spec: MOVE date/time without separators (Figure 288) |
| 210 | Fixed C-spec: MOVE timestamp (Figure 289) |
| 211 | Fixed C-spec: MOVE date alignment/truncation |
| 212 | Fixed C-spec: MOVE invalid date -> 112 |
| 213 | Fixed C-spec: reject MOVE *JOBRUN |
| 214 | Fixed C-spec: reject MOVE time *USA to numeric |
