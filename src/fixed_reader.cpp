#include "fixed_reader.h"
#include "fixed_columns.h"
#include "fixed_cspec.h"
#include "free_bridge.h"
#include "keyword_list.h"
#include <cctype>
#include <cstdlib>
#include <fstream>
#include <sstream>

namespace rpg {
namespace fixed {

using rpg::fixed::extractCol;

// Splits src_text into physical lines (no terminators), preserving a
// trailing blank line if the file ends without one so 1-based line
// numbers below line up with the original source exactly.
static std::vector<std::string> splitLines(const std::string& src_text) {
    std::vector<std::string> lines;
    std::string cur;
    for (char c : src_text) {
        if (c == '\n') {
            if (!cur.empty() && cur.back() == '\r') cur.pop_back();
            lines.push_back(cur);
            cur.clear();
        } else {
            cur += c;
        }
    }
    if (!cur.empty()) lines.push_back(cur);
    return lines;
}

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

// Matches the free-format lexer's own /COPY and /INCLUDE nesting limit
// (src/lexer.l's MAX_INCLUDE_DEPTH) — kept as the same constant for
// consistency, not because either number is load-bearing.
static const int MAX_COPY_DEPTH = 10;

static bool readFileLines(const std::string& path, std::vector<std::string>& outLines) {
    std::ifstream f(path);
    if (!f) return false;
    std::ostringstream ss;
    ss << f.rdbuf();
    outLines = splitLines(ss.str());
    return true;
}

// Expands /COPY and /INCLUDE directive lines by splicing the target
// file's own lines in place, recursively — matching the free-format
// lexer's own /COPY/INCLUDE convention exactly (src/lexer.l): the text
// after the directive keyword is a literal filename, opened via fopen()
// relative to the process's current working directory (no library/member
// catalog, no search path). Lines inside an explicit /FREE...·/END-FREE
// region are left untouched: parse_free_block() re-invokes the real
// free-format lexer on that text, which already has its own working
// /COPY/INCLUDE mechanism — expanding here too would double-process it.
//
// Line numbers after an expansion point are relative to this flattened
// line stream, not the original file — the same "best effort, not exact"
// precision the free-format lexer already has today (yylineno isn't
// saved/restored across its own buffer switch either), not a new
// regression introduced here.
//
// `depth` guards against runaway/self-referential copies (matches
// MAX_COPY_DEPTH above); `ok` is set false (not thrown) on any error so
// the rest of the file can still be scanned for further diagnostics,
// matching this reader's error-recovery style elsewhere.
static std::vector<std::string> expandCopyDirectives(const std::vector<std::string>& lines, int depth, bool& ok) {
    std::vector<std::string> out;
    bool inFree = false;
    for (size_t i = 0; i < lines.size(); i++) {
        const std::string& line = lines[i];
        std::string trimmed = trim(line);
        std::string upperTrimmed = upper(trimmed);

        if (inFree) {
            out.push_back(line);
            if (upperTrimmed == "/END-FREE") inFree = false;
            continue;
        }
        if (upperTrimmed == "/FREE") {
            inFree = true;
            out.push_back(line);
            continue;
        }

        bool isCopy = upperTrimmed.rfind("/COPY", 0) == 0 &&
            (upperTrimmed.size() == 5 || upperTrimmed[5] == ' ' || upperTrimmed[5] == '\t');
        bool isInclude = !isCopy && upperTrimmed.rfind("/INCLUDE", 0) == 0 &&
            (upperTrimmed.size() == 8 || upperTrimmed[8] == ' ' || upperTrimmed[8] == '\t');
        if (!isCopy && !isInclude) {
            out.push_back(line);
            continue;
        }

        const char* directiveName = isCopy ? "/COPY" : "/INCLUDE";
        size_t kwLen = isCopy ? 5 : 8;
        std::string filename = trim(trimmed.substr(kwLen));
        if (filename.empty()) {
            report_fixed_format_error((int)i + 1, std::string(directiveName) + ": missing filename");
            ok = false;
            continue;
        }
        if (depth >= MAX_COPY_DEPTH) {
            report_fixed_format_error((int)i + 1, std::string(directiveName) + " nesting too deep");
            ok = false;
            continue;
        }
        std::vector<std::string> copied;
        if (!readFileLines(filename, copied)) {
            report_fixed_format_error((int)i + 1,
                std::string("cannot open ") + directiveName + " file '" + filename + "'");
            ok = false;
            continue;
        }
        auto expanded = expandCopyDirectives(copied, depth + 1, ok);
        for (auto& l : expanded) out.push_back(std::move(l));
    }
    return out;
}

// D-spec position 40 (Internal Data Type) — verified against IBM's ILE
// RPG Language Reference SC09-2508, ch.15 "Position 40 (Internal Data
// Type)" table. 'G' (Graphic) has no RPGType home in this compiler and
// is deliberately unsupported (reported as an error at the call site);
// blank is handled separately by the caller per the manual's own rule
// (character if no decimals, else packed/zoned).
static bool mapDataType(char c, int lenForFloat, RPGType& outType) {
    switch ((char)toupper((unsigned char)c)) {
        case 'A': outType = RPGType::CHAR;      return true;
        case 'B': outType = RPGType::BINDEC;    return true;
        case 'C': outType = RPGType::UCS2;      return true;
        case 'D': outType = RPGType::DATE;      return true;
        case 'F': outType = (lenForFloat == 4) ? RPGType::FLOAT4 : RPGType::FLOAT8; return true;
        case 'I': outType = RPGType::INT10;     return true;
        case 'N': outType = RPGType::IND;       return true;
        case 'O': outType = RPGType::OBJECT;    return true;
        case 'P': outType = RPGType::PACKED;    return true;
        case 'S': outType = RPGType::ZONED;     return true;
        case 'T': outType = RPGType::TIME;      return true;
        case 'U': outType = RPGType::UNS;       return true;
        case 'Z': outType = RPGType::TIMESTAMP; return true;
        case '*': outType = RPGType::POINTER;   return true;
        default: return false;
    }
}

static bool isNumericType(RPGType t) {
    switch (t) {
        case RPGType::PACKED: case RPGType::ZONED: case RPGType::BINDEC:
        case RPGType::INT10:  case RPGType::UNS:    case RPGType::FLOAT4:
        case RPGType::FLOAT8:
            return true;
        default:
            return false;
    }
}

// --- H-spec -----------------------------------------------------------
// Accumulated across every H-line in the file (real H-spec is
// conventionally one contiguous block, but nothing stops it being
// revisited) and applied once, at the end of parseFixedFormat — same
// timing as when KW_CTLOPT fires in the free-format grammar (parser.y's
// statements_opt rule), just triggered here instead of by a token.
static void applyHSpecKeywords(Program* program, const std::string& tailText) {
    auto kw = rpg::parseKeywordList(tailText);
    if (kw.count("NOMAIN")) program->nomain = true;
    auto it = kw.find("MAIN");
    if (it != kw.end()) program->main_proc = upper(it->second);
    it = kw.find("DATFMT");
    if (it != kw.end()) program->datfmt = upper(it->second);
    it = kw.find("TIMFMT");
    if (it != kw.end()) program->timfmt = upper(it->second);
}

// --- F-spec -------------------------------------------------------------
// One in-progress DclF plus its accumulated keyword-tail text (continued
// across lines with FileName blank), finalized when the next
// non-continuation line — of any spec type — appears, or at EOF.
struct PendingFSpec {
    DclF* dclf = nullptr;
    std::string tailText;
    int line = 0;
};

static void finalizeFSpec(Program* program, PendingFSpec& pending) {
    if (!pending.dclf) return;
    auto kw = rpg::parseKeywordList(pending.tailText);
    // Mirrors dclf_opts in parser.y — same keyword vocabulary, since
    // this compiler's own DCL-F extensions (EXTDESC/PREFIX/KEYED/USROPN)
    // aren't real legacy F-spec keywords, but are this compiler's
    // pragmatic equivalent for externally-described files, matching how
    // free-format DCL-F already spells them.
    if (kw.count("KEYED")) pending.dclf->keyed = true;
    if (kw.count("USROPN")) pending.dclf->usropn = true;
    auto it = kw.find("EXTDESC");
    if (it != kw.end()) pending.dclf->extdesc = it->second;
    it = kw.find("PREFIX");
    if (it != kw.end()) pending.dclf->prefix = upper(it->second);

    pending.dclf->line = pending.line;
    program->statements.emplace_back(pending.dclf);
    pending.dclf = nullptr;
    pending.tailText.clear();
}

static void handleFSpecLine(Program* program, PendingFSpec& pending,
                             const std::string& line, int lineNo) {
    std::string name = extractCol(line, FSpec::FileName);
    if (name.empty()) {
        // Continuation of the previous F-line's keyword tail.
        if (pending.dclf) pending.tailText += " " + extractCol(line, FSpec::KeywordTail);
        return;
    }
    // A new named F-line — finalize whatever was pending first.
    finalizeFSpec(program, pending);

    std::string device = upper(extractCol(line, FSpec::Device));
    std::string usage;
    if (device == "DISK") usage = "DISK";
    else if (device == "PRINTER") usage = "PRINTER";
    else if (device == "WORKSTN") usage = "WORKSTN";
    else {
        report_fixed_format_error(lineNo, "F-spec: unsupported or missing device '" + device +
                                   "' for file " + name + " (Phase 1 supports DISK/PRINTER/WORKSTN)");
        return;
    }

    pending.dclf = new DclF(upper(name), usage);
    pending.tailText = extractCol(line, FSpec::KeywordTail);
    pending.line = lineNo;
}

// --- D-spec ---------------------------------------------------------------
// Name continuation (trailing "...") needs one line of carry-over state;
// "current DS" tracks which DclDS subsequent blank-name subfield lines
// belong to, cleared whenever a new standalone field or new DS starts.
struct DSpecState {
    std::string pendingName; // accumulated across "..."-continued name lines
    DclDS* currentDS = nullptr;
};

static void handleDSpecLine(Program* program, DSpecState& state,
                             const std::string& line, int lineNo) {
    std::string rawName = extractCol(line, DSpec::Name);
    std::string name = state.pendingName + rawName;
    if (!name.empty() && name.size() >= 3 && name.substr(name.size() - 3) == "...") {
        state.pendingName = name.substr(0, name.size() - 3);
        return; // wait for the rest of the name on the next line
    }
    state.pendingName.clear();

    std::string defType = upper(extractCol(line, DSpec::DefType));
    std::string dataTypeStr = extractCol(line, DSpec::DataType);
    char dataTypeChar = dataTypeStr.empty() ? '\0' : dataTypeStr[0];
    std::string decStr = extractCol(line, DSpec::Decimals);
    std::string toLenStr = extractCol(line, DSpec::ToLen);
    int decimals = decStr.empty() ? 0 : atoi(decStr.c_str());
    int toLen = toLenStr.empty() ? 0 : atoi(toLenStr.c_str());
    std::string keywordTail = extractCol(line, DSpec::KeywordTail);
    auto kw = rpg::parseKeywordList(keywordTail);

    if (defType == "DS") {
        auto* ds = new DclDS(upper(name));
        ds->line = lineNo;
        if (kw.count("QUALIFIED")) ds->qualified = true;
        auto it = kw.find("LIKEDS");
        if (it != kw.end()) ds->like_ds = upper(it->second);
        it = kw.find("EXTNAME");
        if (it != kw.end()) ds->extname = it->second;
        it = kw.find("DIM");
        if (it != kw.end() && !it->second.empty()) ds->dim = atoi(it->second.c_str());
        program->statements.emplace_back(ds);
        state.currentDS = ds;
        return;
    }

    if (defType == "PR" || defType == "PI" || defType == "C") {
        // Prototypes/procedure interfaces/named constants: real, but
        // deliberately out of Phase 1's "basic standalone fields + DS/
        // subfields" scope (see TODO.md). Fail loudly rather than
        // silently drop the line.
        report_fixed_format_error(lineNo, "D-spec: definition type '" + defType +
                                   "' not supported in fixed-format Phase 1 (name " + name + ")");
        return;
    }

    if (name.empty()) {
        // Blank name + blank def-type + still inside a DS => a subfield
        // continuation line. With no current DS, or with a real name
        // required elsewhere, this is just an unrecognized/keyword-only
        // line — ignore rather than error, matching how blank D-spec
        // lines with only keywords (e.g. continuing a long keyword
        // list) are valid but carry no new field.
        return;
    }

    // Resolve the data type per the manual's blank-column rule: blank
    // dataType + blank decimals => character; blank dataType + decimals
    // present => packed (standalone) or zoned (subfield).
    RPGType type;
    if (dataTypeChar == '\0') {
        if (decStr.empty()) {
            type = RPGType::CHAR;
        } else {
            type = state.currentDS ? RPGType::ZONED : RPGType::PACKED;
        }
    } else if (!mapDataType(dataTypeChar, toLen, type)) {
        report_fixed_format_error(lineNo, std::string("D-spec: unsupported internal data type '") +
                                   dataTypeChar + "' for field " + name);
        return;
    }

    // VARYING{(2|4)} (SC09-2508 ch.15 "VARYING{(2|4)}"): a keyword-tail-only
    // keyword ("not used in a free-form definition" — free-format spells
    // this via the VARCHAR(n) type keyword instead) that flips an otherwise
    // fixed-length character field to variable-length. Applies uniformly to
    // standalone fields and DS subfields — same rule either way, per the
    // manual. The optional (2|4) length-prefix-size parameter isn't modeled
    // here, matching free-format VARCHAR(n)'s own lack of that distinction.
    if (type == RPGType::CHAR && kw.count("VARYING")) type = RPGType::VARCHAR;

    int length  = isNumericType(type) ? 0 : toLen;
    int digits  = isNumericType(type) ? toLen : 0;

    if (state.currentDS) {
        DSField f;
        f.name = upper(name);
        f.type = type;
        f.length = length;
        f.digits = digits;
        f.decimals = decimals;
        auto it = kw.find("OVERLAY");
        if (it != kw.end() && !it->second.empty()) {
            std::string val = it->second;
            size_t colon = val.find(':');
            if (colon == std::string::npos) {
                f.overlay_field = upper(val);
            } else {
                f.overlay_field = upper(trim(val.substr(0, colon)));
                std::string posStr = trim(val.substr(colon + 1));
                if (!posStr.empty()) f.overlay_pos = atoi(posStr.c_str());
            }
        }
        it = kw.find("POS");
        if (it != kw.end() && !it->second.empty()) f.pos = atoi(it->second.c_str());
        it = kw.find("LIKEDS");
        if (it != kw.end()) f.likeds = upper(it->second);
        state.currentDS->fields.push_back(f);
    } else {
        auto* n = new DclS(upper(name), type, length, digits, decimals);
        n->line = lineNo;
        auto it = kw.find("LIKE");
        if (it != kw.end()) n->like_var = upper(it->second);
        it = kw.find("DIM");
        if (it != kw.end() && !it->second.empty()) n->dim = atoi(it->second.c_str());
        program->statements.emplace_back(n);
    }
}

// --- Main driver ------------------------------------------------------

Program* parseFixedFormat(const std::string& src_text, const std::string& /*filename*/) {
    auto* program = new Program();
    std::vector<std::string> lines = splitLines(src_text);
    bool copyOk = true;
    lines = expandCopyDirectives(lines, 0, copyOk);

    std::string hSpecTail;
    PendingFSpec pendingF;
    DSpecState dState;

    bool inFreeBlock = false;
    std::string freeBlockText;
    int freeBlockStartLine = 0;

    // Native (column-based) C-spec: a contiguous run of 'C' lines is
    // transpiled line-by-line into free-form-equivalent text (see
    // fixed_cspec.h/.cpp), then flushed through the *same*
    // parse_free_block() bridge /free blocks already use, exactly once
    // per run. bufLines keeps one entry per physical line consumed
    // (including blank/comment lines, pushed directly below) so error
    // line numbers inside the run stay aligned with the real source.
    CSpecRunState cState;
    bool inCSpecRun = false;
    auto flushCRun = [&]() {
        int startLine = 0;
        std::string buf = flushCSpecRun(cState, startLine);
        auto stmts = parse_free_block(buf, startLine);
        for (auto& s : stmts) program->statements.push_back(std::move(s));
        inCSpecRun = false;
    };

    for (size_t idx = 0; idx < lines.size(); idx++) {
        int lineNo = (int)idx + 1;
        const std::string& line = lines[idx];

        if (inFreeBlock) {
            std::string trimmed = trim(line);
            if (upper(trimmed) == "/END-FREE") {
                auto stmts = parse_free_block(freeBlockText, freeBlockStartLine);
                for (auto& s : stmts) program->statements.push_back(std::move(s));
                inFreeBlock = false;
                freeBlockText.clear();
            } else {
                freeBlockText += line + "\n";
            }
            continue;
        }

        std::string trimmed = trim(line);
        if (upper(trimmed) == "/FREE") {
            if (inCSpecRun) flushCRun();
            inFreeBlock = true;
            freeBlockStartLine = lineNo + 1;
            continue;
        }

        if (line.empty()) {
            if (inCSpecRun) cState.bufLines.push_back("");
            continue;
        }
        std::string specType = upper(extractCol(line, SpecType));
        std::string commentFlag = extractCol(line, CommentFlag);
        if (commentFlag == "*") { // whole-line comment
            if (inCSpecRun) cState.bufLines.push_back("");
            continue;
        }
        if (specType.empty()) { // blank/short line, nothing to dispatch
            if (inCSpecRun) cState.bufLines.push_back("");
            continue;
        }

        // A new spec-type line always closes out any pending F-spec
        // continuation (F-spec keyword-tail continuation lines have
        // spec type 'F' themselves but a blank FileName, handled inside
        // handleFSpecLine — so reaching here with a *different* spec
        // type, or a fresh named F-line, both need the old one finalized
        // first).
        if (specType != "F" && pendingF.dclf) finalizeFSpec(program, pendingF);
        if (specType != "D" && !dState.pendingName.empty()) {
            report_fixed_format_error(lineNo, "D-spec: name continuation ('...') never completed");
            dState.pendingName.clear();
        }
        if (specType != "D") dState.currentDS = nullptr;
        if (specType != "C" && inCSpecRun) flushCRun();

        if (specType == "H") {
            hSpecTail += " " + extractCol(line, HSpec::KeywordTail);
        } else if (specType == "F") {
            handleFSpecLine(program, pendingF, line, lineNo);
        } else if (specType == "D") {
            handleDSpecLine(program, dState, line, lineNo);
        } else if (specType == "C") {
            if (!inCSpecRun) { inCSpecRun = true; cState.startLine = lineNo; }
            feedCSpecLine(cState, line, lineNo);
        } else if (specType == "I" || specType == "O") {
            report_fixed_format_error(lineNo,
                std::string("Fixed-format Phase 1 does not support ") + specType +
                "-specs (record I/O) — see TODO.md");
        } else {
            report_fixed_format_error(lineNo, "Unrecognized spec type '" + specType + "'");
        }
    }

    if (inFreeBlock) {
        report_fixed_format_error(freeBlockStartLine, "/FREE block never closed with /END-FREE");
    }
    if (inCSpecRun) flushCRun();
    finalizeFSpec(program, pendingF);
    if (!dState.pendingName.empty()) {
        report_fixed_format_error((int)lines.size(), "D-spec: name continuation ('...') never completed");
    }
    applyHSpecKeywords(program, hSpecTail);

    return program;
}

} // namespace fixed
} // namespace rpg
