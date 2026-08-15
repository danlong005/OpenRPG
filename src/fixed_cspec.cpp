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

// Which fixed-column layout an opcode uses (SC09-2508 p.559 Table 125
// "Traditional Syntax" vs p.565 "Extended Factor 2 Syntax") and whether
// this compiler's free-format grammar accepts an (extender) suffix on it
// (only EVAL/EVALR/CALLP have a KW_*_EXT lexer rule — verified against
// src/lexer.l — every other V1 opcode must appear bare).
enum class CSpecShape { BARE, EXT_FACTOR2, TRADITIONAL };
struct OpcodeInfo {
    CSpecShape shape;
    bool allowsExtender = false;
};

// V1 opcode set (see TODO.md "Fixed-Format Source Support — Next Steps"
// item #1 and the implementation plan it came from). Every opcode here
// already has a working parser.y rule building the right AST node when
// fed the free-form text this file synthesizes — confirmed against
// parser.y before wiring each one in.
static const std::unordered_map<std::string, OpcodeInfo>& opcodeTable() {
    static const std::unordered_map<std::string, OpcodeInfo> table = {
        // Bare — no operands (parser.y: KW_X SEMICOLON with nothing between).
        {"ELSE",    {CSpecShape::BARE}},
        {"ENDDO",   {CSpecShape::BARE}},
        {"ENDFOR",  {CSpecShape::BARE}},
        {"ENDIF",   {CSpecShape::BARE}},
        {"ENDMON",  {CSpecShape::BARE}},
        {"ENDSL",   {CSpecShape::BARE}},
        {"ENDSR",   {CSpecShape::BARE}}, // begsr_stmt: KW_ENDSR SEMICOLON — no return-point/label support
        {"ITER",    {CSpecShape::BARE}},
        {"LEAVE",   {CSpecShape::BARE}},
        {"LEAVESR", {CSpecShape::BARE}},
        {"OTHER",   {CSpecShape::BARE}},
        {"SELECT",  {CSpecShape::BARE}},
        {"MONITOR", {CSpecShape::BARE}},

        // Extended factor 2 — Factor 1 blank, cols 36-80 = one free-form
        // expression (SC09-2508 p.565's own opcode list, intersected with
        // what this compiler's free-format grammar actually implements).
        {"IF",         {CSpecShape::EXT_FACTOR2}},
        {"ELSEIF",     {CSpecShape::EXT_FACTOR2}},
        {"DOW",        {CSpecShape::EXT_FACTOR2}},
        {"DOU",        {CSpecShape::EXT_FACTOR2}},
        {"WHEN",       {CSpecShape::EXT_FACTOR2}},
        {"EVAL",       {CSpecShape::EXT_FACTOR2, true}},
        {"EVALR",      {CSpecShape::EXT_FACTOR2, true}},
        {"EVAL-CORR",  {CSpecShape::EXT_FACTOR2}},
        {"RETURN",     {CSpecShape::EXT_FACTOR2}},
        {"CALLP",      {CSpecShape::EXT_FACTOR2, true}},
        {"FOR",        {CSpecShape::EXT_FACTOR2}},
        {"FOR-EACH",   {CSpecShape::EXT_FACTOR2}},
        {"ON-ERROR",   {CSpecShape::EXT_FACTOR2}},

        // Traditional Factor1/Factor2/Result — exact per-opcode field
        // usage verified against SC09-2508's dedicated opcode sections
        // and built by name in feedCSpecLine (a generic field-shape table
        // would be less readable than just naming each opcode).
        {"BEGSR", {CSpecShape::TRADITIONAL}},
        {"EXSR",  {CSpecShape::TRADITIONAL}},
        {"CLEAR", {CSpecShape::TRADITIONAL}},
        {"RESET", {CSpecShape::TRADITIONAL}},
        {"DSPLY", {CSpecShape::TRADITIONAL}},
        {"SORTA", {CSpecShape::TRADITIONAL}},

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
        // parser.y when g_allow_goto_tag is set — see free_bridge.h and
        // fixed_reader.cpp's flushCRun. No extender column for either
        // (unlike the arithmetic opcodes below).
        {"GOTO", {CSpecShape::TRADITIONAL}},
        {"TAG",  {CSpecShape::TRADITIONAL}},

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
    };
    return table;
}

// Opcodes that are real RPG IV opcodes with a well-defined traditional
// field mapping but aren't wired up yet — a distinct, encouraging error
// from "not planned" legacy opcodes. See TODO.md's fast-follow list.
static const std::unordered_set<std::string>& deferredOpcodes() {
    static const std::unordered_set<std::string> s = {
        "ON-EXIT", "ON-EXCP", "XML-INTO", "XML-SAX", "DATA-INTO",
        "DATA-GEN", "SND-MSG",
        // Item #3 fast-follow, deliberately not V1 — see TODO.md for why
        // each one specifically (MOVE/MOVEL: real fixed-length right/left
        // -adjust and date-format-conversion semantics, no clean EVAL
        // mapping; CALL/PARM/PLIST: needs cross-line PLIST state, CALLP
        // already covers modern program calls).
        "MOVE", "MOVEL", "CALL", "PARM", "PLIST",
    };
    return s;
}

void feedCSpecLine(CSpecRunState& state, const std::string& line, int lineNo) {
    int idx = (int)state.bufLines.size();
    state.bufLines.push_back("");

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
        state.bufLines[state.pendingLineIdx] += ";";
        state.pendingExt = false;
        state.pendingLineIdx = -1;
    }

    std::string controlLevel = upper(extractCol(line, CSpec::ControlLevel));
    if (!controlLevel.empty() && controlLevel != "SR") {
        report_fixed_format_error(lineNo, "C-spec: control level '" + controlLevel +
            "' is not supported (RPG-cycle semantics are not implemented) — "
            "leave positions 7-8 blank, or 'SR'");
        return;
    }
    if (!extractCol(line, CSpec::Indicators).empty()) {
        report_fixed_format_error(lineNo,
            "C-spec: conditioning indicators (positions 9-11) are not yet "
            "supported in fixed-format C-spec — see TODO.md");
        return;
    }

    std::string opcodeRaw = extractCol(line, CSpec::Opcode);
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

    const auto& table = opcodeTable();
    auto it = table.find(opcodeName);
    if (it == table.end()) {
        if (deferredOpcodes().count(opcodeName)) {
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
        state.bufLines[idx] = opcodeName + ";";
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
        state.bufLines[idx] = expr.empty() ? header : (header + " " + expr);
        state.pendingExt = true;
        state.pendingLineIdx = idx;
        return; // closed by the next non-continuation feedCSpecLine call, or flush
    }
    case CSpecShape::TRADITIONAL: {
        std::string factor2 = extractCol(line, CSpec::Factor2);
        std::string result = extractCol(line, CSpec::Result);
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
        } else if (opcodeName == "GOTO" || opcodeName == "TAG") {
            if (factor2.empty() || !factor1.empty()) {
                report_fixed_format_error(lineNo,
                    "C-spec: " + opcodeName + " requires a label in Factor 2 only");
                return;
            }
            built = opcodeName + " " + factor2;
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
        state.bufLines[idx] = built + ";";
        return;
    }
    }
}

std::string flushCSpecRun(CSpecRunState& state, int& outStartLine) {
    if (state.pendingExt && state.pendingLineIdx >= 0) {
        state.bufLines[state.pendingLineIdx] += ";";
    }
    std::string buf;
    for (auto& l : state.bufLines) {
        buf += l;
        buf += "\n";
    }
    outStartLine = state.startLine;
    state = CSpecRunState();
    return buf;
}

} // namespace fixed
} // namespace rpg
