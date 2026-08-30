#include "fixed_cspec.h"
#include "fixed_columns.h"
#include "free_bridge.h"
#include <cctype>
#include <unordered_map>
#include <unordered_set>

namespace rpg {
namespace fixed {

using rpg::fixed::extractCol;

static std::string upper(std::string s) {
    for (auto& c : s) c = (char)toupper((unsigned char)c);
    return s;
}

static std::string trim(const std::string& s) {
    size_t a = s.find_first_not_of(" \t");
    if (a == std::string::npos) return "";
    size_t b = s.find_last_not_of(" \t");
    return s.substr(a, b - a + 1);
}

// Raw (untrimmed, blank-padded to the full range) column slice. Unlike
// extractCol it preserves each character's position within the range,
// which the conditioning-indicator field needs: position 9 is the "not"
// flag and positions 10-11 the indicator itself, so a trimmed "N10" and a
// trimmed (misaligned) "N10" starting a column early would otherwise be
// indistinguishable.
static std::string rawCols(const std::string& line, const ColSpec& spec) {
    std::string out;
    for (int c = spec.startCol; c <= spec.endCol; c++)
        out += (c <= (int)line.size()) ? line[c - 1] : ' ';
    return out;
}

// The RPG IV indicators that are real conditioning indicators but that
// this compiler has no representation for — everything outside *IN01-*IN99
// (see TODO.md "Indicator Types (beyond *IN01-*IN99, *INLR)" under Not
// Planned). Recognized only so they get a "not supported here" diagnostic
// instead of being reported as a typo.
static bool isUnsupportedIndicatorName(const std::string& s) {
    if (s.size() != 2) return false;
    char a = s[0], b = s[1];
    if (s == "LR" || s == "MR" || s == "RT" || s == "OV" || s == "1P") return true;
    if ((a == 'L' || a == 'H') && b >= '1' && b <= '9') return true; // L1-L9, H1-H9
    if (a == 'U' && b >= '1' && b <= '8') return true;               // U1-U8
    if (a == 'K' && b >= 'A' && b <= 'Y' && b != 'O') return true;   // KA-KN, KP-KY
    if (a == 'O' && b >= 'A' && b <= 'G') return true;               // OA-OG
    return false;
}

// Parses the conditioning-indicator field (SC09-2508 p.561: position 9 is
// an optional 'N' meaning "not", positions 10-11 the indicator). On
// success `cond` is either left empty (field blank — statement runs
// unconditionally) or set to the free-form boolean expression the
// statement must be wrapped in. Returns false after reporting an error.
static bool parseCondIndicator(const std::string& line, int lineNo, std::string& cond) {
    std::string raw = rawCols(line, CSpec::Indicators);
    if (trim(raw).empty()) return true;

    char notFlag = (char)toupper((unsigned char)raw[0]);
    std::string name = upper(raw.substr(1, 2));
    if (notFlag != ' ' && notFlag != 'N') {
        report_fixed_format_error(lineNo, std::string("C-spec: malformed conditioning indicator '") +
            trim(raw) + "' — position 9 must be blank or 'N', with the indicator itself in "
            "positions 10-11");
        return false;
    }
    if (name.size() == 2 && isdigit((unsigned char)name[0]) && isdigit((unsigned char)name[1])) {
        if (name == "00") {
            report_fixed_format_error(lineNo,
                "C-spec: conditioning indicator '00' is not valid — indicators are 01-99");
            return false;
        }
        cond = (notFlag == 'N') ? ("NOT *IN" + name) : ("*IN" + name);
        return true;
    }
    if (isUnsupportedIndicatorName(name)) {
        report_fixed_format_error(lineNo, "C-spec: conditioning indicator '" + name +
            "' is not supported — this compiler implements only the numbered indicators "
            "*IN01-*IN99 (see TODO.md \"Indicator Types\")");
        return false;
    }
    report_fixed_format_error(lineNo, std::string("C-spec: malformed conditioning indicator '") +
        trim(raw) + "' — expected an optional 'N' in position 9 and a two-digit indicator "
        "(01-99) in positions 10-11");
    return false;
}

// Collapses an accumulated AND/OR conditioning group into one free-form
// boolean expression. RPG relates the lines of such a group as an OR of
// AND-groups — each `OR` line starts a fresh AND-group — rather than
// left-to-right, so every multi-term AND-group is parenthesized before the
// groups are ORed together, and the whole thing is parenthesized again so
// it composes safely wherever it is dropped in.
static std::string joinCondGroups(const std::vector<std::vector<std::string>>& groups) {
    std::string out;
    for (const auto& group : groups) {
        std::string andExpr;
        for (const auto& term : group) {
            if (!andExpr.empty()) andExpr += " AND ";
            andExpr += term;
        }
        if (group.size() > 1) andExpr = "(" + andExpr + ")";
        if (!out.empty()) out += " OR ";
        out += andExpr;
    }
    if (groups.size() > 1) out = "(" + out + ")";
    return out;
}

// Maps a CASxx/CABxx comparison mnemonic (SC09-2508: EQ/NE/LT/LE/GT/GE,
// or none at all for the unconditional CAS/CAB form) onto the free-form
// operator it transpiles to. Returns false if the suffix is not one.
static bool casCabOperator(const std::string& mn, std::string& op) {
    if (mn.empty()) { op.clear(); return true; }
    if (mn == "EQ") { op = "=";  return true; }
    if (mn == "NE") { op = "<>"; return true; }
    if (mn == "LT") { op = "<";  return true; }
    if (mn == "LE") { op = "<="; return true; }
    if (mn == "GT") { op = ">";  return true; }
    if (mn == "GE") { op = ">="; return true; }
    return false;
}

// Validates one of COMP's resulting-indicator slots and turns it into the
// indicator's free-form name. Empty slot -> empty name (that comparison
// simply is not recorded). Same supported set as conditioning indicators:
// only the numbered *IN01-*IN99 exist in this compiler.
static bool parseResultIndicator(const std::string& raw, int lineNo,
                                 const char* which, std::string& name) {
    std::string t = trim(raw);
    if (t.empty()) { name.clear(); return true; }
    std::string up = upper(t);
    if (up.size() == 2 && isdigit((unsigned char)up[0]) && isdigit((unsigned char)up[1])) {
        if (up == "00") {
            report_fixed_format_error(lineNo, std::string("C-spec: COMP ") + which +
                " resulting indicator '00' is not valid — indicators are 01-99");
            return false;
        }
        name = "*IN" + up;
        return true;
    }
    if (isUnsupportedIndicatorName(up)) {
        report_fixed_format_error(lineNo, std::string("C-spec: COMP ") + which +
            " resulting indicator '" + up + "' is not supported — this compiler implements "
            "only the numbered indicators *IN01-*IN99 (see TODO.md \"Indicator Types\")");
        return false;
    }
    report_fixed_format_error(lineNo, std::string("C-spec: COMP ") + which +
        " resulting indicator '" + t + "' is malformed — expected a two-digit indicator (01-99)");
    return false;
}

// Wraps one already-complete transpiled statement (its ';' included) in
// the IF/ENDIF a conditioning indicator asks for. Deliberately stays on
// the single buffer line this physical source line owns, so
// parse_free_block's line numbers keep matching the original source.
// A built-in function reference: '%' followed by a letter, outside any
// character literal (so '100% done' is not mistaken for one).
//
// SC09-2508: traditional-syntax Factor 1 and Factor 2 hold a field name, a
// literal, a named or figurative constant, or a special word -- never an
// expression. A built-in function IS an expression, so IBM rejects it in
// either factor with RNF0372 ("Built-in function not allowed"), at severity
// 20. Confirmed empirically on IBM i 7.5: %CHAR(n) in Factor 1 of DSPLY,
// %LEN(s) in Factor 1 of IFGT, and %TRIM(s) in traditional Factor 2 of MOVE
// are all rejected, while the same built-in in EXTENDED Factor 2 (EVAL)
// compiles cleanly -- which is why this check lives only in the TRADITIONAL
// branch below.
static bool containsBuiltIn(const std::string& s) {
    bool inLiteral = false;
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '\'') { inLiteral = !inLiteral; continue; }
        if (inLiteral) continue;
        if (s[i] == '%' && i + 1 < s.size() && isalpha((unsigned char)s[i + 1])) return true;
    }
    return false;
}

// Rejects a built-in in any traditional-syntax operand. Returns true when it
// reported, so callers can bail out.
//
// Traditional Factor 1, Factor 2 and the Result field take a field name, a
// literal, or a named/figurative constant. A built-in is an expression and is
// only legal in EXTENDED Factor 2. IBM reports RNF0372 at severity 20 for the
// factors; a built-in in the Result field is rejected too, since the result
// operand must be assignable.
//
// Every traditional path routes through here rather than checking inline: the
// CAS/CAB group reads its own operands and returns before the shape switch, so
// an inline check in one place left `C %LEN(s) CABGT n TAG1` accepted.
static bool rejectBuiltInOperands(const std::string& opcodeName, int lineNo,
                                  const std::string& factor1,
                                  const std::string& factor2,
                                  const std::string& result) {
    struct { const char* what; const std::string& text; } ops[] = {
        {"Factor 1", factor1}, {"Factor 2", factor2}, {"the Result field", result}
    };
    for (const auto& o : ops) {
        if (!containsBuiltIn(o.text)) continue;
        report_fixed_format_error(lineNo,
            std::string("C-spec: built-in function in ") + o.what + " of '" + opcodeName +
            "' — traditional-syntax operands take a field, literal or constant, not an "
            "expression. Assign the built-in to a field with EVAL first (IBM: RNF0372)");
        return true;
    }
    return false;
}

static std::string wrapCond(const std::string& cond, const std::string& stmt) {
    if (cond.empty()) return stmt;
    return "IF " + cond + "; " + stmt + " ENDIF;";
}

// Which fixed-column layout an opcode uses (SC09-2508 p.559 Table 125
// "Traditional Syntax" vs p.565 "Extended Factor 2 Syntax") and whether
// this compiler's free-format grammar accepts an (extender) suffix on it
// (only EVAL/EVALR/CALLP have a KW_*_EXT lexer rule — verified against
// src/lexer.l — every other V1 opcode must appear bare).
enum class CSpecShape { BARE, EXT_FACTOR2, TRADITIONAL };
struct OpcodeInfo {
    CSpecShape shape;
    bool allowsExtender = false;
    // Whether a conditioning indicator (positions 9-11) may condition this
    // opcode. False for every block-structure opcode — openers (IF/DOW/
    // SELECT/BEGSR/...), middles (ELSE/WHEN/ON-ERROR), closers (ENDIF/
    // ENDDO/ENDSR/...) — and for TAG. This transpiler expresses a
    // conditioning indicator as an `IF cond; <stmt>; ENDIF;` wrapper
    // around the one statement the indicator conditions, which only works
    // when that statement is self-contained: wrapping half of a block
    // would leave the block unbalanced, and wrapping a TAG would bury the
    // label inside a nested scope its GOTOs cannot legally jump into.
    // Rejected with a distinct error rather than transpiled approximately.
    bool allowsCond = true;
};

// V1 opcode set (see TODO.md "Fixed-Format Source Support — Next Steps"
// item #1 and the implementation plan it came from). Every opcode here
// already has a working parser.y rule building the right AST node when
// fed the free-form text this file synthesizes — confirmed against
// parser.y before wiring each one in.
static const std::unordered_map<std::string, OpcodeInfo>& opcodeTable() {
    static const std::unordered_map<std::string, OpcodeInfo> table = {
        // Bare — no operands (parser.y: KW_X SEMICOLON with nothing between).
        {"ELSE",    {CSpecShape::BARE, false, false}},
        {"ENDDO",   {CSpecShape::BARE, false, false}},
        {"ENDFOR",  {CSpecShape::BARE, false, false}},
        {"ENDIF",   {CSpecShape::BARE, false, false}},
        {"ENDMON",  {CSpecShape::BARE, false, false}},
        {"ENDSL",   {CSpecShape::BARE, false, false}},
        {"ENDSR",   {CSpecShape::BARE, false, false}}, // begsr_stmt: KW_ENDSR SEMICOLON — no return-point/label support
        {"ITER",    {CSpecShape::BARE}},
        {"LEAVE",   {CSpecShape::BARE}},
        {"LEAVESR", {CSpecShape::BARE}},
        {"OTHER",   {CSpecShape::BARE, false, false}},
        {"SELECT",  {CSpecShape::BARE, false, false}},
        {"MONITOR", {CSpecShape::BARE, false, false}},

        // Extended factor 2 — Factor 1 blank, cols 36-80 = one free-form
        // expression (SC09-2508 p.565's own opcode list, intersected with
        // what this compiler's free-format grammar actually implements).
        {"IF",         {CSpecShape::EXT_FACTOR2, false, false}},
        {"ELSEIF",     {CSpecShape::EXT_FACTOR2, false, false}},
        {"DOW",        {CSpecShape::EXT_FACTOR2, false, false}},
        {"DOU",        {CSpecShape::EXT_FACTOR2, false, false}},
        {"WHEN",       {CSpecShape::EXT_FACTOR2, false, false}},
        {"EVAL",       {CSpecShape::EXT_FACTOR2, true}},
        {"EVALR",      {CSpecShape::EXT_FACTOR2, true}},
        {"EVAL-CORR",  {CSpecShape::EXT_FACTOR2}},
        {"RETURN",     {CSpecShape::EXT_FACTOR2}},
        {"CALLP",      {CSpecShape::EXT_FACTOR2, true}},
        {"FOR",        {CSpecShape::EXT_FACTOR2, false, false}},
        {"FOR-EACH",   {CSpecShape::EXT_FACTOR2, false, false}},
        {"ON-ERROR",   {CSpecShape::EXT_FACTOR2, false, false}},

        // Modern opcodes whose operand syntax is free-form by nature
        // (%XML/%DATA/%PARSER expressions, SND-MSG's message-type
        // operand). Extended factor 2 is the right shape for exactly that
        // reason: columns 36-80 plus continuation carry the expression
        // through to the free-format parser untouched, where these
        // opcodes were already fully implemented. Nothing else was
        // needed — no new grammar, no new AST, no codegen change.
        {"XML-INTO",   {CSpecShape::EXT_FACTOR2}},
        {"DATA-INTO",  {CSpecShape::EXT_FACTOR2}},
        {"DATA-GEN",   {CSpecShape::EXT_FACTOR2}},
        {"SND-MSG",    {CSpecShape::EXT_FACTOR2}},

        // Traditional Factor1/Factor2/Result — exact per-opcode field
        // usage verified against SC09-2508's dedicated opcode sections
        // and built by name in feedCSpecLine (a generic field-shape table
        // would be less readable than just naming each opcode).
        {"BEGSR", {CSpecShape::TRADITIONAL, false, false}},
        {"EXSR",  {CSpecShape::TRADITIONAL}},
        {"CLEAR", {CSpecShape::TRADITIONAL}},
        {"RESET", {CSpecShape::TRADITIONAL}},
        {"DSPLY", {CSpecShape::TRADITIONAL}},
        {"SORTA", {CSpecShape::TRADITIONAL}},
        // COMP — the sole opcode allowed to fill the resulting-indicator
        // columns (71-76); see the COMP branch in feedCSpecLine.
        {"COMP",  {CSpecShape::TRADITIONAL}},

        // RLA opcodes (item 1b, fast-follow to V1) — this compiler's own
        // free-format grammar (parser.y) is a simplified subset of the
        // full IBM traditional syntax: no data-structure Result operand
        // on any of these (verified — every *_stmt rule below ends at
        // IDENTIFIER SEMICOLON, nothing after the file name), and DELETE
        // takes no key at all (deletes the last-fetched record, per
        // tests/test105's own usage). SETLL/SETGT have no KW_*_EXT lexer
        // rule (src/lexer.l) — no extender support, unlike the rest.
        {"CHAIN",  {CSpecShape::TRADITIONAL, true}},
        {"READ",   {CSpecShape::TRADITIONAL, true}},
        {"READP",  {CSpecShape::TRADITIONAL, true}},
        {"READE",  {CSpecShape::TRADITIONAL, true}},
        {"READPE", {CSpecShape::TRADITIONAL, true}},
        {"WRITE",  {CSpecShape::TRADITIONAL, true}},
        {"UPDATE", {CSpecShape::TRADITIONAL, true}},
        {"DELETE", {CSpecShape::TRADITIONAL, true}},
        {"SETLL",  {CSpecShape::TRADITIONAL}},
        {"SETGT",  {CSpecShape::TRADITIONAL}},

        // Item #3 V1 — traditional legacy opcodes. GOTO/TAG have NO
        // free-form syntax at all (SC09-2508: "not allowed"), so the
        // GotoStmt/TagStmt text these transpile to is only accepted by
        // parser.y when g_allow_fixed_only_stmts is set — see free_bridge.h and
        // fixed_reader.cpp's flushCRun. No extender column for either
        // (unlike the arithmetic opcodes below).
        {"GOTO", {CSpecShape::TRADITIONAL}},
        {"TAG",  {CSpecShape::TRADITIONAL, false, false}},

        // ADD/SUB/MULT/DIV/Z-ADD/Z-SUB also have no free-form *keyword*
        // ("not allowed — use the +/-/*// operator", "use the EVAL
        // operation code") but the manual explicitly prescribes the
        // EVAL/expression equivalent, so these transpile to synthesized
        // EVAL text rather than needing any new grammar. (H) half-adjust
        // etc. passes straight through onto the synthesized EVAL, which
        // already supports it.
        {"ADD",   {CSpecShape::TRADITIONAL, true}},
        {"SUB",   {CSpecShape::TRADITIONAL, true}},
        {"MULT",  {CSpecShape::TRADITIONAL, true}},
        {"DIV",   {CSpecShape::TRADITIONAL, true}},
        {"Z-ADD", {CSpecShape::TRADITIONAL, true}},
        {"Z-SUB", {CSpecShape::TRADITIONAL, true}},

        // MOVE/MOVEL — like GOTO/TAG, no free-form syntax exists, so the
        // MoveStmt text these build is only accepted by parser.y when
        // g_allow_fixed_only_stmts is set. Character, numeric and
        // date/time operands are all supported; which combinations are
        // legal is decided in codegen, the first place with a symbol
        // table. (P) is the one extender. Factor 1, when present, is the
        // date/time format of the character or numeric operand.
        {"MOVE",  {CSpecShape::TRADITIONAL, true}},
        {"MOVEL", {CSpecShape::TRADITIONAL, true}},

        // CALL/PLIST/PARM — traditional program call. CALL has no free-form
        // syntax (CALLP replaced it), so like GOTO/TAG/MOVE its bridge
        // text is gated on g_allow_fixed_only_stmts. PLIST and PARM are
        // declarative and contribute no statement of their own — they feed
        // the CALL that uses them, which is why neither can carry a
        // conditioning indicator (SC09-2508 p.928/930 forbid one outright).
        {"CALL",  {CSpecShape::TRADITIONAL, false, true}},
        {"PLIST", {CSpecShape::TRADITIONAL, false, false}},
        {"PARM",  {CSpecShape::TRADITIONAL, false, false}},
    };
    return table;
}

// Opcodes that are real RPG IV opcodes with a well-defined traditional
// field mapping but aren't wired up yet — a distinct, encouraging error
// from "not planned" legacy opcodes. See TODO.md's fast-follow list.
static const std::unordered_set<std::string>& deferredOpcodes() {
    static const std::unordered_set<std::string> s = {
        // Not implemented anywhere in this compiler — free-format has no
        // grammar for either, so there is nothing to reach from fixed
        // columns yet. Listed here only so they earn the "planned"
        // message rather than the never-planned one.
        "ON-EXCP", "XML-SAX",
    };
    return s;
}

// Opcodes that exist and work, but only somewhere fixed-format source
// cannot reach. ON-EXIT is valid solely inside a DCL-PROC (parser.y has
// no standalone rule for it — it appears only in the DCL-PROC
// productions), and fixed-format source cannot declare a procedure at
// all, since this reader has no P-spec support. So it is not a fast-
// follow port: it needs a /free block either way.
static const std::unordered_set<std::string>& procOnlyOpcodes() {
    static const std::unordered_set<std::string> s = { "ON-EXIT" };
    return s;
}

// The whole statement text for a call plus its parameter list. SC09-2508
// p.929 numbers the moves a CALL performs around each PARM: on the call,
// "the contents of the factor 2 field of a PARM operation are copied into
// the result field"; on return, "the contents of the result field ... are
// copied into the factor 1 field". Both operands are optional, and the
// data "is moved in the same way as data is moved using the EVAL
// operation code" — so each becomes one ordinary assignment bracketing
// the CALL, and a PARM with neither operand contributes nothing but the
// argument itself.
//
// All of it lands on the CALL's single buffer line: the PARM lines sit
// *after* the CALL in the source, so their own buffer entries could never
// hold statements that must run *before* it.
static std::string buildCallText(const std::string& program,
                                 const std::vector<CSpecParm>& parms) {
    std::string pre, args, post;
    for (size_t i = 0; i < parms.size(); i++) {
        if (i) args += " : ";
        args += parms[i].name;
        if (!parms[i].source.empty())
            pre += parms[i].name + " = " + parms[i].source + "; ";
        if (!parms[i].target.empty())
            post += " " + parms[i].target + " = " + parms[i].name + ";";
    }
    std::string text = pre + "CALL " + program;
    if (!parms.empty()) text += " (" + args + ")";
    return text + ";" + post;
}

// Writes a CALL and the PARM lines gathered after it into the CALL's own
// buffer line, and clears the pending state. Called when the run of PARM
// lines ends: any other opcode, or the end of the C-spec run.
static void finishCall(CSpecRunState& state) {
    if (!state.pendingCall) return;
    state.bufLines[state.callLineIdx] =
        wrapCond(state.callCond, buildCallText(state.callProgram, state.callParms));
    state.pendingCall = false;
    state.callLineIdx = -1;
    state.callProgram.clear();
    state.callCond.clear();
    state.callParms.clear();
}

// Closes a named PLIST once its run of PARM lines ends. "The PLIST
// operation must be immediately followed by at least one PARM"
// (SC09-2508 p.930), so an empty one is an error rather than an empty
// argument list — it is far more likely a typo'd or misplaced PARM.
static void finishPlist(CSpecRunState& state) {
    state.plistSuppress = false;
    if (!state.inPlist) return;
    if (!state.plistSawParm) {
        report_fixed_format_error(state.plistLine, "C-spec: PLIST '" + state.plistName +
            "' is not followed by any PARM line — a parameter list must declare at least "
            "one parameter");
    }
    state.inPlist = false;
    state.plistName.clear();
    state.plistLine = 0;
    state.plistSawParm = false;
}

void feedCSpecLine(CSpecRunState& state, const std::string& line, int lineNo) {
    int idx = (int)state.bufLines.size();
    state.bufLines.push_back("");

    // Fixed-column embedded SQL: C/EXEC SQL, C+ continuation lines,
    // C/END-EXEC. Checked before the ordinary column layout because
    // column 7 here carries a directive ('/') or continuation ('+')
    // marker, which the control-level field would otherwise reject.
    // Everything gathered is emitted as one free-form `EXEC SQL ...;`,
    // which the lexer's own <SQL> start condition then captures exactly
    // as it does for free-format source — so this needs no SQL parsing
    // of its own, and the transpile-and-bridge model still holds.
    {
        char marker = line.size() >= 7 ? line[6] : ' ';
        std::string rest = line.size() > 7 ? trim(line.substr(7)) : "";
        std::string restUp = upper(rest);
        if (state.inSqlCapture) {
            if (marker == '/' && restUp == "END-EXEC") {
                state.bufLines[state.sqlLineIdx] = "EXEC SQL " + trim(state.sqlText) + ";";
                state.inSqlCapture = false;
                state.sqlLineIdx = -1;
                state.sqlText.clear();
                return;
            }
            if (marker == '+') {
                if (!state.sqlText.empty()) state.sqlText += " ";
                state.sqlText += rest;
                return;
            }
            report_fixed_format_error(state.sqlLine, "C-spec: embedded SQL statement is not "
                "terminated by a C/END-EXEC line — continuation lines must carry '+' in "
                "position 7");
            state.inSqlCapture = false;
            state.sqlLineIdx = -1;
            state.sqlText.clear();
            return;
        }
        if (marker == '/' && restUp.compare(0, 8, "EXEC SQL") == 0) {
            finishCall(state);
            finishPlist(state);
            state.inSqlCapture = true;
            state.sqlLineIdx = idx;
            state.sqlLine = lineNo;
            state.sqlText = trim(rest.substr(8)); // text may start on this line
            return;
        }
        if (marker == '/' && restUp == "END-EXEC") {
            report_fixed_format_error(lineNo,
                "C-spec: C/END-EXEC with no preceding C/EXEC SQL");
            return;
        }
    }

    bool contShaped = extractCol(line, CSpec::ControlLevel).empty() &&
                       extractCol(line, CSpec::Indicators).empty() &&
                       extractCol(line, CSpec::Factor1).empty() &&
                       extractCol(line, CSpec::Opcode).empty();

    if (contShaped) {
        if (!state.pendingExt) {
            report_fixed_format_error(lineNo,
                "C-spec: continuation line (positions 7-35 blank) with no "
                "preceding extended-factor-2 statement to continue");
            return;
        }
        state.bufLines[state.pendingLineIdx] += " " + extractCol(line, CSpec::ExtFactor2);
        return; // this physical line contributes no new buffer line of its own
    }

    // A non-continuation line closes any statement still open from before.
    if (state.pendingExt) {
        state.bufLines[state.pendingLineIdx] += ";" + state.pendingSuffix;
        state.pendingSuffix.clear();
        state.pendingExt = false;
        state.pendingLineIdx = -1;
    }

    std::string controlLevel = upper(extractCol(line, CSpec::ControlLevel));
    bool isAnOr = (controlLevel == "AN" || controlLevel == "OR");
    if (!controlLevel.empty() && !isAnOr && controlLevel != "SR") {
        report_fixed_format_error(lineNo, "C-spec: control level '" + controlLevel +
            "' is not supported (RPG-cycle semantics are not implemented) — "
            "leave positions 7-8 blank, or 'SR'/'AN'/'OR'");
        return;
    }
    // Conditioning indicator (positions 9-11) — transpiled into an
    // IF/ENDIF wrapper around this one statement once the opcode is known
    // to be conditionable (OpcodeInfo::allowsCond). `cond` holds just this
    // line's own term until any AND/OR group below folds the rest in.
    std::string cond;
    if (!parseCondIndicator(line, lineNo, cond)) return;

    std::string opcodeRaw = extractCol(line, CSpec::Opcode);

    // AND/OR conditioning group (positions 7-8). Unlike the control-level
    // entries above, `AN`/`OR` have nothing to do with the RPG cycle: they
    // exist only to combine positions-9-11 indicators across physical
    // lines, which is the sole way to write a multi-indicator condition in
    // RPG IV (its C-spec has room for exactly one indicator per line). The
    // group's operation code sits on its last line.
    if (!isAnOr && !state.condGroups.empty()) {
        report_fixed_format_error(state.condLine,
            "C-spec: conditioning-indicator line (no operation code) is not continued by "
            "an 'AN'/'OR' line — an AND/OR conditioning group must end with the line "
            "carrying the operation");
        state.condGroups.clear();
    }
    if (isAnOr) {
        if (state.condGroups.empty()) {
            report_fixed_format_error(lineNo, "C-spec: '" + controlLevel +
                "' in positions 7-8 has no preceding conditioning-indicator line to "
                "combine with");
            return;
        }
        if (cond.empty()) {
            report_fixed_format_error(lineNo, "C-spec: an '" + controlLevel +
                "' line must carry a conditioning indicator in positions 9-11");
            state.condGroups.clear(); // group is broken; don't also report it dangling
            return;
        }
        if (controlLevel == "AN") state.condGroups.back().push_back(cond);
        else                      state.condGroups.push_back({cond});
        if (opcodeRaw.empty()) return; // group continues on a later line
        cond = joinCondGroups(state.condGroups);
        state.condGroups.clear();
    } else if (!cond.empty() && opcodeRaw.empty()) {
        // First line of a group: an indicator with the operation still to
        // come on a following AN/OR line.
        state.condGroups.push_back({cond});
        state.condLine = lineNo;
        return;
    }

    if (opcodeRaw.empty()) {
        report_fixed_format_error(lineNo, "C-spec: missing operation code");
        return;
    }
    std::string opcodeName = opcodeRaw;
    std::string extender;
    size_t paren = opcodeRaw.find('(');
    if (paren != std::string::npos) {
        size_t closeParen = opcodeRaw.find(')', paren);
        if (closeParen == std::string::npos) {
            report_fixed_format_error(lineNo,
                "C-spec: unterminated operation extender in '" + opcodeRaw + "'");
            return;
        }
        opcodeName = opcodeRaw.substr(0, paren);
        extender = opcodeRaw.substr(paren, closeParen - paren + 1); // includes ( )
    }
    opcodeName = upper(trim(opcodeName));

    // A PARM run belongs to whichever of the two opened it; anything
    // else ends it. "A parameter list is ended when an operation other
    // than PARM is encountered" (SC09-2508 p.930).
    if (opcodeName != "PARM") { finishCall(state); finishPlist(state); }

    // CASxx / CABxx / ENDCS. Handled ahead of the opcode table because the
    // comparison mnemonic is glued onto the opcode itself (`CASGT`), so
    // there is no fixed name to look up.
    bool isCas = opcodeName.compare(0, 3, "CAS") == 0 &&
                 (opcodeName.size() == 3 || opcodeName.size() == 5);
    bool isCab = opcodeName.compare(0, 3, "CAB") == 0 &&
                 (opcodeName.size() == 3 || opcodeName.size() == 5);
    if (isCas || isCab || opcodeName == "ENDCS") {
        if (!extractCol(line, CSpec::ResultInd).empty() ||
            !extractCol(line, CSpec::Length).empty() ||
            !extractCol(line, CSpec::Decimals).empty()) {
            report_fixed_format_error(lineNo, "C-spec: '" + opcodeName +
                "' — resulting indicators and inline field length/decimals are not supported");
            return;
        }
        if (!extender.empty()) {
            report_fixed_format_error(lineNo, "C-spec: operation extender '" + extender +
                "' is not supported on '" + opcodeName + "' in this compiler");
            return;
        }
        std::string factor1 = extractCol(line, CSpec::Factor1);
        std::string factor2 = extractCol(line, CSpec::Factor2);
        std::string result  = extractCol(line, CSpec::Result);
        if (rejectBuiltInOperands(opcodeName, lineNo, factor1, factor2, result)) return;

        if (opcodeName == "ENDCS") {
            if (!state.inCasGroup) {
                report_fixed_format_error(lineNo,
                    "C-spec: ENDCS with no CASxx group to close");
                return;
            }
            if (!cond.empty()) {
                report_fixed_format_error(lineNo, "C-spec: a conditioning indicator cannot be "
                    "applied to 'ENDCS' — it closes the CASxx group, so conditioning it would "
                    "leave the group unbalanced");
                return;
            }
            state.bufLines[idx] = state.casOpened ? "ENDIF;" : "";
            state.inCasGroup = false;
            state.casOpened = false;
            state.casElse = false;
            return;
        }

        std::string mnemonic = opcodeName.substr(3);
        std::string cmp;
        if (!casCabOperator(mnemonic, cmp)) {
            report_fixed_format_error(lineNo, "C-spec: '" + opcodeName + "' — '" + mnemonic +
                "' is not a comparison mnemonic (expected EQ, NE, LT, LE, GT or GE, or none "
                "at all for the unconditional form)");
            return;
        }
        if (result.empty()) {
            report_fixed_format_error(lineNo, "C-spec: " + opcodeName + " requires a " +
                std::string(isCas ? "subroutine name" : "label") + " in the Result field");
            return;
        }
        if (cmp.empty()) {
            if (!factor1.empty() || !factor2.empty()) {
                report_fixed_format_error(lineNo, "C-spec: " + opcodeName +
                    " has no comparison mnemonic, so Factor 1 and Factor 2 must be blank");
                return;
            }
        } else if (factor1.empty() || factor2.empty()) {
            report_fixed_format_error(lineNo, "C-spec: " + opcodeName +
                " requires Factor 1 and Factor 2 to compare");
            return;
        }
        std::string test = cmp.empty() ? "" : (factor1 + " " + cmp + " " + factor2);

        if (isCab) {
            // Self-contained: a comparison guarding a branch, or a bare
            // unconditional branch. GOTO is accepted here because the whole
            // run parses with g_allow_fixed_only_stmts set.
            std::string built = cmp.empty()
                ? ("GOTO " + result + ";")
                : ("IF " + test + "; GOTO " + result + "; ENDIF;");
            state.bufLines[idx] = wrapCond(cond, built);
            return;
        }

        // CASxx: a chain, so a conditioning indicator on one arm would
        // break the IF/ELSEIF structure the group transpiles to.
        if (!cond.empty()) {
            report_fixed_format_error(lineNo, "C-spec: a conditioning indicator cannot be "
                "applied to '" + opcodeName + "' — CASxx lines chain into one IF/ELSEIF "
                "group, which conditioning a single arm would leave unbalanced");
            return;
        }
        if (!state.inCasGroup) {
            state.inCasGroup = true;
            state.casLine = lineNo;
            state.casOpened = !cmp.empty();
            state.casElse = false;
            state.bufLines[idx] = cmp.empty()
                ? ("EXSR " + result + ";")
                : ("IF " + test + "; EXSR " + result + ";");
        } else if (!state.casOpened || state.casElse) {
            report_fixed_format_error(lineNo, "C-spec: " + opcodeName + " follows an "
                "unconditional CAS, which already runs on every pass — the rest of the group "
                "is unreachable");
            return;
        } else {
            state.bufLines[idx] = cmp.empty()
                ? ("ELSE; EXSR " + result + ";")
                : ("ELSEIF " + test + "; EXSR " + result + ";");
            if (cmp.empty()) state.casElse = true; // ELSE arm taken; no further arms
        }
        return;
    }
    if (state.inCasGroup) {
        report_fixed_format_error(state.casLine, "C-spec: CASxx group is not closed by an "
            "ENDCS — every CASxx line up to the ENDCS must be part of the same group");
        state.inCasGroup = false;
        state.casOpened = false;
        state.casElse = false;
    }

    const auto& table = opcodeTable();
    auto it = table.find(opcodeName);
    if (it == table.end()) {
        if (procOnlyOpcodes().count(opcodeName)) {
            report_fixed_format_error(lineNo, "C-spec: opcode '" + opcodeName +
                "' is valid only inside a DCL-PROC, which fixed-format source cannot declare "
                "(no P-spec support) — write the procedure in a /free block, where '" +
                opcodeName + "' already works");
        } else if (deferredOpcodes().count(opcodeName)) {
            report_fixed_format_error(lineNo, "C-spec: opcode '" + opcodeName +
                "' is not yet supported in fixed-format C-spec (planned fast-follow — see TODO.md)");
        } else {
            report_fixed_format_error(lineNo, "C-spec: opcode '" + opcodeName +
                "' is not supported (traditional/legacy opcode — see TODO.md)");
        }
        return;
    }
    const OpcodeInfo& info = it->second;

    if (!extender.empty() && !info.allowsExtender) {
        report_fixed_format_error(lineNo, "C-spec: operation extender '" + extender +
            "' is not supported on '" + opcodeName + "' in this compiler");
        return;
    }

    if (!cond.empty() && !info.allowsCond) {
        if (opcodeName == "PARM" || opcodeName == "PLIST") {
            // SC09-2508 p.928/930 forbid these outright ("Conditioning
            // indicator entries (positions 9 through 11) are not
            // allowed"), and the reason carries over here: both are
            // declarative, so there is no statement to wrap in an IF.
            report_fixed_format_error(lineNo,
                "C-spec: a conditioning indicator cannot be applied to '" + opcodeName +
                "' — it declares part of a parameter list rather than being a statement of "
                "its own; condition the CALL instead");
        } else if (opcodeName == "TAG") {
            report_fixed_format_error(lineNo,
                "C-spec: a conditioning indicator cannot be applied to 'TAG' — a label is a "
                "jump target, not an executable operation, and the IF/ENDIF this compiler "
                "conditions with would put it inside a block its own GOTOs cannot jump into; "
                "condition the GOTO instead");
        } else {
            report_fixed_format_error(lineNo, "C-spec: a conditioning indicator cannot be "
                "applied to the block-structure opcode '" + opcodeName + "' — conditioning is "
                "transpiled to an IF/ENDIF around the conditioned statement, which would leave "
                "the block unbalanced; fold the indicator into the block's own condition "
                "instead (e.g. 'IF *INnn AND ...')");
        }
        return;
    }

    std::string factor1 = extractCol(line, CSpec::Factor1);

    switch (info.shape) {
    case CSpecShape::BARE: {
        if (!factor1.empty()) {
            report_fixed_format_error(lineNo,
                "C-spec: '" + opcodeName + "' does not take a Factor 1 entry");
            return;
        }
        if (!extractCol(line, CSpec::ExtFactor2).empty()) {
            report_fixed_format_error(lineNo,
                "C-spec: '" + opcodeName + "' does not take operands");
            return;
        }
        state.bufLines[idx] = wrapCond(cond, opcodeName + ";");
        return;
    }
    case CSpecShape::EXT_FACTOR2: {
        if (!factor1.empty()) {
            report_fixed_format_error(lineNo, "C-spec: '" + opcodeName +
                "' uses extended factor 2 — Factor 1 (positions 12-25) must be blank");
            return;
        }
        std::string expr = extractCol(line, CSpec::ExtFactor2);
        std::string header = opcodeName + extender;
        std::string stmt = expr.empty() ? header : (header + " " + expr);
        // The statement stays open across any continuation lines, so its
        // ENDIF has to wait for whoever appends the terminating ';'.
        if (!cond.empty()) {
            stmt = "IF " + cond + "; " + stmt;
            state.pendingSuffix = " ENDIF;";
        }
        state.bufLines[idx] = stmt;
        state.pendingExt = true;
        state.pendingLineIdx = idx;
        return; // closed by the next non-continuation feedCSpecLine call, or flush
    }
    case CSpecShape::TRADITIONAL: {
        std::string factor2 = extractCol(line, CSpec::Factor2);
        std::string result = extractCol(line, CSpec::Result);
        if (rejectBuiltInOperands(opcodeName, lineNo, factor1, factor2, result)) return;
        if (opcodeName == "COMP") {
            // The one opcode whose resulting indicators are its entire
            // effect — and, unlike the resulting indicators free-form
            // drops everywhere else, one this compiler CAN express, since
            // *INnn is an assignable target. Each non-blank slot becomes
            // one indicator assignment.
            if (factor1.empty() || factor2.empty()) {
                report_fixed_format_error(lineNo,
                    "C-spec: COMP requires Factor 1 and Factor 2 to compare");
                return;
            }
            if (!result.empty()) {
                report_fixed_format_error(lineNo,
                    "C-spec: COMP does not take a Result field — its result is the "
                    "resulting indicators in positions 71-76");
                return;
            }
            if (!extractCol(line, CSpec::Length).empty() ||
                !extractCol(line, CSpec::Decimals).empty()) {
                report_fixed_format_error(lineNo,
                    "C-spec: COMP — inline field length/decimals are not supported");
                return;
            }
            std::string hi, lo, eq;
            if (!parseResultIndicator(extractCol(line, CSpec::ResultIndHi), lineNo, "high", hi) ||
                !parseResultIndicator(extractCol(line, CSpec::ResultIndLo), lineNo, "low",  lo) ||
                !parseResultIndicator(extractCol(line, CSpec::ResultIndEq), lineNo, "equal", eq))
                return;
            if (hi.empty() && lo.empty() && eq.empty()) {
                report_fixed_format_error(lineNo, "C-spec: COMP with no resulting indicators "
                    "in positions 71-76 has no effect — give at least one");
                return;
            }
            std::string text;
            if (!hi.empty()) text += hi + " = (" + factor1 + " > "  + factor2 + "); ";
            if (!lo.empty()) text += lo + " = (" + factor1 + " < "  + factor2 + "); ";
            if (!eq.empty()) text += eq + " = (" + factor1 + " = "  + factor2 + "); ";
            while (!text.empty() && text.back() == ' ') text.pop_back();
            state.bufLines[idx] = wrapCond(cond, text);
            return;
        }
        if (!extractCol(line, CSpec::ResultInd).empty() ||
            !extractCol(line, CSpec::Length).empty() ||
            !extractCol(line, CSpec::Decimals).empty()) {
            report_fixed_format_error(lineNo, "C-spec: '" + opcodeName +
                "' — resulting indicators and inline field length/decimals are not supported");
            return;
        }
        std::string built;
        if (opcodeName == "BEGSR") {
            if (factor1.empty() || !factor2.empty() || !result.empty()) {
                report_fixed_format_error(lineNo,
                    "C-spec: BEGSR requires a subroutine name in Factor 1 only");
                return;
            }
            built = "BEGSR " + factor1;
        } else if (opcodeName == "EXSR") {
            if (factor2.empty() || !factor1.empty() || !result.empty()) {
                report_fixed_format_error(lineNo,
                    "C-spec: EXSR requires a subroutine name in Factor 2 only");
                return;
            }
            built = "EXSR " + factor2;
        } else if (opcodeName == "CLEAR" || opcodeName == "RESET") {
            if (result.empty() || !factor1.empty() || !factor2.empty()) {
                report_fixed_format_error(lineNo, "C-spec: " + opcodeName +
                    " requires a name in the Result field only (*NOKEY/*ALL are not supported by this compiler)");
                return;
            }
            built = opcodeName + " " + result;
        } else if (opcodeName == "DSPLY") {
            if (factor1.empty() || !factor2.empty() || !result.empty()) {
                report_fixed_format_error(lineNo, "C-spec: DSPLY requires the message in Factor 1 only "
                    "(message-queue/response are not supported by this compiler)");
                return;
            }
            built = "DSPLY " + factor1;
        } else if (opcodeName == "SORTA") {
            if (factor2.empty() || !factor1.empty() || !result.empty()) {
                report_fixed_format_error(lineNo,
                    "C-spec: SORTA requires the array name in Factor 2 only");
                return;
            }
            built = "SORTA " + factor2;
        } else if (opcodeName == "CHAIN" || opcodeName == "READE" || opcodeName == "READPE" ||
                   opcodeName == "SETLL" || opcodeName == "SETGT") {
            if (factor1.empty() || factor2.empty() || !result.empty()) {
                report_fixed_format_error(lineNo, "C-spec: " + opcodeName +
                    " requires a key in Factor 1 and a file name in Factor 2 "
                    "(a data-structure result operand is not supported by this compiler)");
                return;
            }
            built = opcodeName + extender + " " + factor1 + " " + factor2;
        } else if (opcodeName == "READ" || opcodeName == "READP" ||
                   opcodeName == "WRITE" || opcodeName == "UPDATE") {
            if (factor2.empty() || !factor1.empty() || !result.empty()) {
                report_fixed_format_error(lineNo, "C-spec: " + opcodeName +
                    " requires a file name in Factor 2 only "
                    "(a data-structure result operand is not supported by this compiler)");
                return;
            }
            built = opcodeName + extender + " " + factor2;
        } else if (opcodeName == "DELETE") {
            if (factor2.empty() || !factor1.empty() || !result.empty()) {
                report_fixed_format_error(lineNo,
                    "C-spec: DELETE requires a file name in Factor 2 only — this "
                    "compiler deletes the last-fetched record, it does not take a "
                    "delete-by-key Factor 1 (matches the free-format grammar)");
                return;
            }
            built = opcodeName + extender + " " + factor2;
        } else if (opcodeName == "GOTO") {
            // GOTO names its target in Factor 2 (SC09-2508 p.562).
            if (factor2.empty() || !factor1.empty()) {
                report_fixed_format_error(lineNo,
                    "C-spec: GOTO requires a label in Factor 2 only");
                return;
            }
            built = opcodeName + " " + factor2;
        } else if (opcodeName == "TAG") {
            // TAG is the mirror image of GOTO: the label it DECLARES goes in
            // Factor 1, and Factor 2 must be blank. This reader previously
            // treated the two identically and wanted the label in Factor 2 for
            // both, which IBM rejects with RNF5009 ("Factor 1 operand is
            // required") plus RNF5025 ("Factor 2 entry is not blank").
            // Verified on IBM i 7.5: `C  LOOPTOP  TAG` compiles,
            // `C  TAG  LOOPTOP` does not.
            if (factor1.empty() || !factor2.empty()) {
                report_fixed_format_error(lineNo,
                    "C-spec: TAG declares its label in Factor 1 (positions 12-25) and "
                    "Factor 2 must be blank — the reverse of GOTO, which names its "
                    "target in Factor 2 (IBM: RNF5009/RNF5025)");
                return;
            }
            built = opcodeName + " " + factor1;
        } else if (opcodeName == "ADD" || opcodeName == "SUB" ||
                   opcodeName == "MULT" || opcodeName == "DIV") {
            if (factor2.empty() || result.empty()) {
                report_fixed_format_error(lineNo, "C-spec: " + opcodeName +
                    " requires Factor 2 and a Result field");
                return;
            }
            // SC09-2508: "If factor 1 is specified, ... adds it to factor 2
            // and places the sum in the result field. If factor 1 is not
            // specified, the contents of factor 2 are added to the result
            // field" — same accumulate-into-result pattern for SUB/MULT/DIV.
            char op = opcodeName == "ADD" ? '+' :
                      opcodeName == "SUB" ? '-' :
                      opcodeName == "MULT" ? '*' : '/';
            std::string lhs = factor1.empty() ? result : factor1;
            built = "EVAL" + extender + " " + result + " = " + lhs + " " + op + " " + factor2;
        } else if (opcodeName == "CALL") {
            if (!factor1.empty()) {
                report_fixed_format_error(lineNo,
                    "C-spec: CALL does not take a Factor 1 entry");
                return;
            }
            if (factor2.size() < 3 || factor2.front() != '\'' || factor2.back() != '\'') {
                report_fixed_format_error(lineNo, "C-spec: CALL requires a quoted program name "
                    "in Factor 2 — a program name held in a variable is a dynamic call, which "
                    "has no equivalent here (this compiler links a called program statically, "
                    "the same way DCL-PR ... EXTPGM does); see TODO.md");
                return;
            }
            if (upper(result) == "*ENTRY") {
                report_fixed_format_error(lineNo, "C-spec: CALL cannot name the *ENTRY "
                    "parameter list — *ENTRY declares this program's own incoming "
                    "parameters, not a list to pass to another program");
                return;
            }
            if (!result.empty()) {
                // A named PLIST, which may be defined *later* in the
                // source than the CALL that uses it — so this call cannot
                // be assembled now the way an inline PARM run can. Record
                // the site; flushCSpecRun substitutes the parameter list
                // once every PLIST has been seen.
                state.plistCalls.push_back({idx, lineNo, factor2, upper(result), cond});
                return;
            }
            // Assembled once the PARM lines that follow have been read.
            state.pendingCall = true;
            state.callLineIdx = idx;
            state.callLine = lineNo;
            state.callProgram = factor2;
            state.callCond = cond;
            state.callParms.clear();
            return;
        } else if (opcodeName == "PLIST") {
            if (factor1.empty() || !factor2.empty() || !result.empty()) {
                report_fixed_format_error(lineNo,
                    "C-spec: PLIST requires the parameter-list name in Factor 1 only");
                state.plistSuppress = true;
                return;
            }
            std::string name = upper(factor1);
            // *ENTRY is the program's own incoming parameter list, not a
            // list some CALL in this member uses. It is collected the same
            // way (so the PARM path is shared) but read back out by
            // parseFixedFormat, which turns the mainline into a callable
            // function instead of an int main().
            if (state.plists.count(name)) {
                report_fixed_format_error(lineNo, name == "*ENTRY"
                    ? std::string("C-spec: only one *ENTRY parameter list can be specified "
                                  "in a program")
                    : ("C-spec: PLIST '" + name +
                       "' is already defined — a parameter-list name must be unique"));
                state.plistSuppress = true;
                return;
            }
            state.plists[name]; // registered now, so a forward CALL resolves
            state.inPlist = true;
            state.plistName = name;
            state.plistLine = lineNo;
            return; // declarative — contributes no statement
        } else if (opcodeName == "PARM") {
            if (state.plistSuppress) return; // its PLIST line already errored
            state.plistSawParm = true;
            if (!state.pendingCall && !state.inPlist) {
                report_fixed_format_error(lineNo, "C-spec: PARM with no preceding CALL or "
                    "PLIST — a PARM line must immediately follow the CALL or PLIST whose "
                    "parameter list it belongs to");
                return;
            }
            if (result.empty()) {
                report_fixed_format_error(lineNo,
                    "C-spec: PARM requires the parameter name in the Result field");
                return;
            }
            // p.929: the Result field is the field whose address is
            // passed, so it cannot be anything without one. Indicators are
            // called out by name there; a literal has no storage to pass
            // and no name to declare. (A named constant is equally
            // forbidden but is not distinguishable here — it reaches
            // codegen, which has the symbol table, as an ordinary name.)
            if (upper(result).compare(0, 3, "*IN") == 0) {
                report_fixed_format_error(lineNo, "C-spec: PARM cannot pass an indicator ('" +
                    result + "') as the parameter — use a declared field, and move the "
                    "indicator into it around the CALL");
                return;
            }
            if (result.front() == '\'' || isdigit((unsigned char)result.front())) {
                report_fixed_format_error(lineNo, "C-spec: PARM cannot pass the literal " +
                    result + " as the parameter — RPG passes parameters by address, so the "
                    "Result field must be a declared field");
                return;
            }
            // p.929: "A literal or named constant cannot be specified in
            // factor 1" — factor 1 is written to on return, so it needs
            // storage just as the result field does. Factor 2 is only read
            // and may be a literal.
            if (!factor1.empty() &&
                (factor1.front() == '\'' || isdigit((unsigned char)factor1.front()))) {
                report_fixed_format_error(lineNo, "C-spec: PARM Factor 1 cannot be the literal "
                    + factor1 + " — it receives the parameter's value when the call returns, "
                    "so it must be a field");
                return;
            }
            // p.929 step 4: in the CALLED program, factor 2 is copied into
            // the result field when control returns to the caller. That is
            // a copy at *every* exit point — each RETURN plus falling off
            // the end — which this line-by-line transpiler cannot place.
            // Factor 1 on an *ENTRY PARM is the entry-time copy (step 3)
            // and is supported, since it happens once, at the top.
            if (state.inPlist && state.plistName == "*ENTRY" && !factor2.empty()) {
                report_fixed_format_error(lineNo, "C-spec: Factor 2 on an *ENTRY PLIST PARM "
                    "is not supported — it copies the parameter back when the program "
                    "returns, which would have to happen at every exit point; assign to '" +
                    result + "' directly instead. Factor 1 (the entry-time copy) does work.");
                return;
            }
            CSpecParm parm{factor1, factor2, result, lineNo};
            if (state.inPlist) state.plists[state.plistName].push_back(parm);
            else               state.callParms.push_back(parm);
            return; // feeds the CALL or PLIST, not a statement of its own
        } else if (opcodeName == "MOVE" || opcodeName == "MOVEL") {
            // Factor 1 on MOVE/MOVEL is a date/time format naming the shape
            // of whichever operand is the character or numeric one, with an
            // optional separator or a trailing 0 for "no separators". It is
            // passed through verbatim: whether it is a format this compiler
            // knows, and whether it is even allowed here (the manual
            // requires factor 1 blank when both operands are date/time
            // types), both need the declared operand types, so codegen
            // makes those calls. Only the leading * is checkable here.
            if (!factor1.empty() && factor1.front() != '*') {
                report_fixed_format_error(lineNo, "C-spec: " + opcodeName + " Factor 1 '" +
                    factor1 + "' is not a date/time format — Factor 1 on " + opcodeName +
                    " is either blank or a format such as *ISO, *MDY/ or *MDY0");
                return;
            }
            if (factor2.empty() || result.empty()) {
                report_fixed_format_error(lineNo, "C-spec: " + opcodeName +
                    " requires Factor 2 and a Result field");
                return;
            }
            if (!extender.empty() && upper(extender) != "(P)") {
                report_fixed_format_error(lineNo, "C-spec: " + opcodeName + " supports only the "
                    "(P) extender in this compiler, not '" + extender + "'");
                return;
            }
            // The bridge text carries factor 1 as a quoted string right
            // after the opcode (see parser.y's move_stmt); a format is
            // letters, digits and a separator, so it can never need
            // escaping inside those quotes.
            std::string f1 = upper(factor1);
            built = opcodeName + upper(extender) +
                    (f1.empty() ? "" : (":'" + f1 + "'")) +
                    " " + factor2 + " " + result;
        } else if (opcodeName == "Z-ADD" || opcodeName == "Z-SUB") {
            if (factor2.empty() || result.empty() || !factor1.empty()) {
                report_fixed_format_error(lineNo, "C-spec: " + opcodeName +
                    " requires Factor 2 and a Result field (Factor 1 is not used)");
                return;
            }
            built = (opcodeName == "Z-ADD")
                ? ("EVAL" + extender + " " + result + " = " + factor2)
                : ("EVAL" + extender + " " + result + " = -(" + factor2 + ")");
        }
        state.bufLines[idx] = wrapCond(cond, built + ";");
        return;
    }
    }
}

std::string flushCSpecRun(CSpecRunState& state, int& outStartLine) {
    finishCall(state);
    finishPlist(state);
    // Named-PLIST call sites, resolved only now that every PLIST in the
    // run has been seen — a PLIST is allowed to be defined after the CALL
    // that names it, so this is the earliest point the parameter list is
    // knowable. An unresolved name is reported against the CALL's own line.
    for (const auto& pc : state.plistCalls) {
        auto it = state.plists.find(pc.plist);
        if (it == state.plists.end()) {
            report_fixed_format_error(pc.line, "C-spec: CALL names the parameter list '" +
                pc.plist + "', which no PLIST line defines");
            continue;
        }
        state.bufLines[pc.bufIdx] = wrapCond(pc.cond, buildCallText(pc.program, it->second));
    }
    if (state.inCasGroup) {
        report_fixed_format_error(state.casLine,
            "C-spec: CASxx group is not closed by an ENDCS");
    }
    if (state.inSqlCapture) {
        report_fixed_format_error(state.sqlLine,
            "C-spec: embedded SQL statement is not terminated by a C/END-EXEC line");
    }
    if (!state.condGroups.empty()) {
        report_fixed_format_error(state.condLine,
            "C-spec: conditioning-indicator line (no operation code) is not continued by "
            "an 'AN'/'OR' line — an AND/OR conditioning group must end with the line "
            "carrying the operation");
    }
    if (state.pendingExt && state.pendingLineIdx >= 0) {
        state.bufLines[state.pendingLineIdx] += ";" + state.pendingSuffix;
    }
    std::string buf;
    for (auto& l : state.bufLines) {
        buf += l;
        buf += "\n";
    }
    outStartLine = state.startLine;
    // PLIST declarations are program-wide, not run-wide: an interleaved
    // spec type (an O-spec, a /free block) splits the calculations into
    // several runs, and a PLIST defined in one of them is still in scope
    // for the rest. Everything else here is genuinely per-run and resets.
    auto plists = std::move(state.plists);
    state = CSpecRunState();
    state.plists = std::move(plists);
    return buf;
}

} // namespace fixed
} // namespace rpg
