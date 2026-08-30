#include "fixed_reader.h"
#include "fixed_columns.h"
#include "fixed_cspec.h"
#include "free_bridge.h"
#include "keyword_list.h"
#include <cctype>
#include <cstdlib>
#include <fstream>
#include <set>
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
    // KEYED is a FREE-FORM DCL-F keyword. In a fixed-format F-spec, keyed
    // access is the Record-Address-Type entry in position 34 ('K'), and IBM
    // rejects the keyword outright with RNF2367 ("The keyword is valid only
    // for a free-form File declaration") at severity 20. This reader used to
    // accept it in the keyword tail as an extension, which left five tests
    // uncompilable on a real system for a reason nothing local reported.
    if (kw.count("KEYED")) {
        report_fixed_format_error(pending.line,
            "F-spec: KEYED is a free-form DCL-F keyword; in fixed format put 'K' in "
            "position 34 (Record-Address-Type) instead (IBM: RNF2367)");
    }
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

// IBM requires numeric entries right-adjusted within their column range and
// reports RNF0263 ("Entry not right-adjusted") at severity 20 -- the program is
// not created. extractCol() trims both ends, so this compiler could not see the
// difference at all until extractColRaw() existed; source that trips this would
// not compile on a real IBM i either, so it is rejected here too. Only all-digit
// entries are checked: alphanumeric fields (names, keywords) are left-adjusted
// by rule, and a blank field carries no adjustment at all.
static void warnIfNotRightAdjusted(const std::string& line, const ColSpec& spec,
                                   int lineNo, const char* what) {
    std::string raw = extractColRaw(line, spec);
    std::string val = trim(raw);
    if (val.empty()) return;
    if (val.find_first_not_of("0123456789") != std::string::npos) return;
    int width = spec.endCol - spec.startCol + 1;
    std::string want = std::string(width - (int)val.size(), ' ') + val;
    if (raw == want) return;
    report_fixed_format_error(lineNo,
        std::string(what) + ": entry '" + val + "' must be right-adjusted in positions " +
        std::to_string(spec.startCol) + "-" + std::to_string(spec.endCol) +
        " (IBM: RNF0263)");
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

    // Entries IBM requires that this reader has never looked at. A
    // program-described file needs a File-Type (position 17) and a
    // File-Format (position 22); omitting them is RNF2003/RNF2006 at
    // severity 20, and the record length must be right-adjusted (RNF0263).
    warnIfNotRightAdjusted(line, FSpec::RecordLen,   lineNo, "F-spec Record-Length");
    warnIfNotRightAdjusted(line, FSpec::KeyFieldLen, lineNo, "F-spec Key-Field-Length");

    std::string fileType = upper(extractCol(line, FSpec::FileType));
    if (fileType.empty() || fileType.find_first_not_of("IOUC") != std::string::npos) {
        report_fixed_format_error(lineNo,
            "F-spec: File-Type in position 17 is '" + (fileType.empty() ? std::string("blank") : fileType) +
            "'; must be I, O, U or C (IBM: RNF2003)");
    }
    std::string fileFormat = upper(extractCol(line, FSpec::FileFormat));
    if (fileFormat.empty() || fileFormat.find_first_not_of("FE") != std::string::npos) {
        report_fixed_format_error(lineNo,
            "F-spec: File-Format in position 22 is '" + (fileFormat.empty() ? std::string("blank") : fileFormat) +
            "'; must be F (program-described) or E (externally described) (IBM: RNF2006)");
    }

    pending.dclf = new DclF(upper(name), usage);
    // Record-Address-Type (position 34): 'K' means the file is accessed by key.
    // This is the fixed-format spelling of what free-form DCL-F calls KEYED.
    std::string rat = upper(extractCol(line, FSpec::RecAddrType));
    if (rat == "K") {
        pending.dclf->keyed = true;
    } else if (!rat.empty()) {
        report_fixed_format_error(lineNo,
            "F-spec: Record-Address-Type '" + rat + "' in position 34 is not supported; "
            "only 'K' (keyed) or blank");
    }
    pending.tailText = extractCol(line, FSpec::KeywordTail);
    pending.line = lineNo;
    std::string recLenStr = extractCol(line, FSpec::RecordLen);
    if (!recLenStr.empty()) pending.dclf->recordLen = atoi(recLenStr.c_str());
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

    warnIfNotRightAdjusted(line, DSpec::FromPos,  lineNo, "D-spec From-Position");
    warnIfNotRightAdjusted(line, DSpec::ToLen,   lineNo, "D-spec To/Length");
    warnIfNotRightAdjusted(line, DSpec::Decimals, lineNo, "D-spec Decimal-Positions");

    std::string defType = upper(extractCol(line, DSpec::DefType));
    std::string dataTypeStr = extractCol(line, DSpec::DataType);
    char dataTypeChar = dataTypeStr.empty() ? '\0' : dataTypeStr[0];
    std::string decStr = extractCol(line, DSpec::Decimals);
    std::string toLenStr = extractCol(line, DSpec::ToLen);
    int decimals = decStr.empty() ? 0 : atoi(decStr.c_str());
    int toLen = toLenStr.empty() ? 0 : atoi(toLenStr.c_str());
    std::string keywordTail = extractCol(line, DSpec::KeywordTail);
    auto kw = rpg::parseKeywordList(keywordTail);

    // Any non-blank definition type ends an open group: DS/PR/PI open a new
    // one, S/C are standalone. Only a blank type continues the current group
    // as a subfield. Without this, an 'S' field following a DS was absorbed
    // into it, which is not what IBM does.
    if (!defType.empty()) state.currentDS = nullptr;

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
        it = kw.find("LIKE");
        if (it != kw.end()) f.like_var = upper(it->second);
        it = kw.find("DIM");
        if (it != kw.end() && !it->second.empty()) f.dim = atoi(it->second.c_str());
        state.currentDS->fields.push_back(f);
    } else {
        // Reaching here with a blank definition type means a subfield-shaped
        // line with no group open. IBM reads blank positions 24-25 as "subfield
        // of the enclosing data structure" and rejects it with RNF3703 at
        // severity 20; this compiler infers "standalone" instead. 94 such
        // declarations were sitting in the test corpus unnoticed.
        if (defType.empty()) {
            report_fixed_format_error(lineNo,
                "D-spec: field '" + upper(name) + "' has a blank Definition-Type in "
                "positions 24-25 and no open DS/PR/PI group; IBM reads this as a "
                "subfield (IBM: RNF3703). Specify 'S' in positions 24-25 for a standalone field");
        }
        auto* n = new DclS(upper(name), type, length, digits, decimals);
        n->line = lineNo;
        auto it = kw.find("LIKE");
        if (it != kw.end()) n->like_var = upper(it->second);
        it = kw.find("DIM");
        if (it != kw.end() && !it->second.empty()) n->dim = atoi(it->second.c_str());
        // Per-field DATFMT/TIMFMT. The H-spec forms already set the
        // program-wide default; these are the per-field overrides the
        // free-format DCL-S has always had (ast.h's DclS::datfmt), and
        // MOVE/MOVEL needs them: with factor 1 blank, "the format of the
        // Date, Time, or Timestamp field is used" (SC09-2508 p.405).
        it = kw.find("DATFMT");
        if (it != kw.end()) n->datfmt = upper(it->second);
        it = kw.find("TIMFMT");
        if (it != kw.end()) n->timfmt = upper(it->second);
        program->statements.emplace_back(n);
    }
}

// --- I-spec (program-described files only) -------------------------------
// I-spec's data-format letter (position 36) is a distinct table from
// D-spec's position-40 letters (SC09-2508 p.550-551) — L/R (zoned with
// leading/trailing sign) and N (character in "indicator format") have no
// D-spec counterpart, so this is deliberately not shared with mapDataType().
// L/R both map to plain ZONED (the leading-vs-trailing sign distinction
// isn't modeled, matching how this compiler doesn't track sign position
// elsewhere either). G (graphic) and N (indicator-format character) are
// rejected as unsupported, same spirit as D-spec's own G rejection. D/T/Z
// (date/time/timestamp) are also rejected here — codegen extracts I-spec
// fields as plain substrings, and those three are C++ struct types
// (RpgDate/RpgTime/RpgTimestamp), not std::string, so they'd need real
// date/time parsing this pass doesn't build; a program-described file
// with a date field can still read it as plain CHAR text.
static bool mapISpecDataFormat(char c, int lenForFloat, RPGType& outType) {
    switch ((char)toupper((unsigned char)c)) {
        case 'A': outType = RPGType::CHAR;      return true;
        case 'B': outType = RPGType::BINDEC;    return true;
        case 'C': outType = RPGType::UCS2;      return true;
        case 'F': outType = (lenForFloat == 4) ? RPGType::FLOAT4 : RPGType::FLOAT8; return true;
        case 'I': outType = RPGType::INT10;     return true;
        case 'L': outType = RPGType::ZONED;     return true; // leading sign, not modeled
        case 'P': outType = RPGType::PACKED;    return true;
        case 'R': outType = RPGType::ZONED;     return true; // trailing sign, not modeled
        case 'S': outType = RPGType::ZONED;     return true;
        case 'U': outType = RPGType::UNS;       return true;
        default: return false; // includes D, T, Z, G, N — unsupported
    }
}

// One record-identification line's worth of state; field-description
// lines that follow (blank FileName) attach to it, same shape as D-spec's
// "currentDS" tracking.
struct ISpecState {
    IRecordFormat* currentFormat = nullptr;
};

// Parses one record-identification-code set (position/not/codepart/char)
// and, if a position is given, appends the test to `tests`. Returns false
// (after reporting an error) if the code-part is Z or D — unsupported.
static bool parseIdTestSet(const std::string& line, int lineNo,
                            const ColSpec& posSpec, const ColSpec& notSpec,
                            const ColSpec& partSpec, const ColSpec& charSpec,
                            std::vector<IRecordIdTest>& tests) {
    std::string posStr = extractCol(line, posSpec);
    if (posStr.empty()) return true; // this set isn't used on this line
    std::string partStr = upper(extractCol(line, partSpec));
    if (!partStr.empty() && partStr != "C") {
        report_fixed_format_error(lineNo,
            "I-spec: record-identification code part '" + partStr +
            "' is not supported (only 'C' — entire character — is; see TODO.md)");
        return false;
    }
    IRecordIdTest test;
    test.position = atoi(posStr.c_str());
    test.negate = upper(extractCol(line, notSpec)) == "N";
    test.character = extractCol(line, charSpec);
    tests.push_back(test);
    return true;
}

static void handleISpecLine(Program* program, ISpecState& state,
                             const std::string& line, int lineNo) {
    std::string fileName = extractCol(line, ISpec::FileName);
    if (!fileName.empty()) {
        // New record-identification line.
        // Positions 17-18 (SC09-2508 p.546): an ALPHABETIC entry means "no
        // sequence checking", which is exactly this compiler's behaviour, so
        // accept it. A NUMERIC entry requests real sequence checking within
        // the file, which is not implemented. IBM in turn *requires* a value
        // here and reports RNF4008 when it is blank, so rejecting every
        // non-blank entry made it impossible to write source both compilers
        // accept.
        std::string seq = extractCol(line, ISpec::Sequence);
        if (!seq.empty() && seq.find_first_of("0123456789") != std::string::npos) {
            report_fixed_format_error(lineNo,
                "I-spec: numeric sequence entry '" + seq + "' (positions 17-18) requests "
                "sequence checking, which is not supported; use an alphabetic entry such "
                "as 'AA' for no sequence checking");
            return;
        }
        if (!extractCol(line, ISpec::Number).empty() || !extractCol(line, ISpec::Option).empty()) {
            report_fixed_format_error(lineNo, "I-spec: sequence number/option (positions 19-20) is not supported");
            return;
        }
        auto* rf = new IRecordFormat(upper(fileName));
        rf->line = lineNo;
        rf->recordIdIndicator = upper(extractCol(line, ISpec::RecordIdInd));
        bool ok = true;
        warnIfNotRightAdjusted(line, ISpec::Set1Position, lineNo, "I-spec record-ID Position (set 1)");
        warnIfNotRightAdjusted(line, ISpec::Set2Position, lineNo, "I-spec record-ID Position (set 2)");
        warnIfNotRightAdjusted(line, ISpec::Set3Position, lineNo, "I-spec record-ID Position (set 3)");
        ok &= parseIdTestSet(line, lineNo, ISpec::Set1Position, ISpec::Set1Not, ISpec::Set1CodePart, ISpec::Set1Character, rf->idTests);
        ok &= parseIdTestSet(line, lineNo, ISpec::Set2Position, ISpec::Set2Not, ISpec::Set2CodePart, ISpec::Set2Character, rf->idTests);
        ok &= parseIdTestSet(line, lineNo, ISpec::Set3Position, ISpec::Set3Not, ISpec::Set3CodePart, ISpec::Set3Character, rf->idTests);
        if (!ok) { delete rf; return; }
        program->statements.emplace_back(rf);
        state.currentFormat = rf;
        return;
    }

    if (upper(extractCol(line, ISpec::LogicalRel)) == "AND" ||
        upper(extractCol(line, ISpec::LogicalRel)) == "OR") {
        report_fixed_format_error(lineNo,
            "I-spec: AND/OR record-identification continuation lines are not supported — see TODO.md");
        return;
    }

    // Field-description line.
    if (!state.currentFormat) {
        report_fixed_format_error(lineNo, "I-spec: field description with no preceding record-identification line");
        return;
    }
    if (!extractCol(line, ISpec::DataAttributes).empty() || !extractCol(line, ISpec::DateTimeSep).empty()) {
        report_fixed_format_error(lineNo,
            "I-spec: date/time external format and *VAR (positions 31-35) are not supported");
        return;
    }
    std::string fmtStr = extractCol(line, ISpec::DataFormat);
    char fmtChar = fmtStr.empty() ? '\0' : fmtStr[0];
    warnIfNotRightAdjusted(line, ISpec::FromPos,  lineNo, "I-spec From-Position");
    warnIfNotRightAdjusted(line, ISpec::ToPos,    lineNo, "I-spec To-Position");
    warnIfNotRightAdjusted(line, ISpec::Decimals, lineNo, "I-spec Decimal-Positions");

    std::string fromStr = extractCol(line, ISpec::FromPos);
    std::string toStr = extractCol(line, ISpec::ToPos);
    std::string decStr = extractCol(line, ISpec::Decimals);
    std::string fname = extractCol(line, ISpec::FieldName);
    if (fromStr.empty() || toStr.empty() || fname.empty()) {
        report_fixed_format_error(lineNo, "I-spec: field description requires From/To position and a field name");
        return;
    }
    if (!extractCol(line, ISpec::MatchingFields).empty()) {
        report_fixed_format_error(lineNo, "I-spec: matching fields (positions 65-66) are not supported — see TODO.md");
        return;
    }
    if (!extractCol(line, ISpec::FieldRecordRel).empty()) {
        report_fixed_format_error(lineNo, "I-spec: field record relation (positions 67-68) is not supported — see TODO.md");
        return;
    }

    RPGType type;
    if (fmtChar == '\0') {
        type = decStr.empty() ? RPGType::CHAR : RPGType::ZONED;
    } else if (!mapISpecDataFormat(fmtChar, 0, type)) {
        report_fixed_format_error(lineNo, std::string("I-spec: unsupported data format '") +
                                   fmtChar + "' for field " + fname);
        return;
    }

    IFieldDesc f;
    f.name = upper(fname);
    f.type = type;
    f.fromPos = atoi(fromStr.c_str());
    f.toPos = atoi(toStr.c_str());
    f.decimals = decStr.empty() ? 0 : atoi(decStr.c_str());
    f.controlLevel = upper(extractCol(line, ISpec::ControlLevel));
    f.indPlus = extractCol(line, ISpec::FieldIndPlus);
    f.indMinus = extractCol(line, ISpec::FieldIndMinus);
    f.indZeroBlank = extractCol(line, ISpec::FieldIndZeroBlank);
    state.currentFormat->fields.push_back(f);
}

// --- O-spec (program-described DISK files only) --------------------------
struct OSpecState {
    ORecordFormat* currentFormat = nullptr;
    // Only one O-spec record format per file is supported — codegen keeps
    // a single ORecordFormat* per file name (real DDS disambiguates
    // multiple O-spec formats for one file via record-type/EXCEPT names,
    // both deferred; see TODO.md). Tracks every file name a record line
    // has already been seen for, across the whole O-spec, so a second one
    // is rejected loudly instead of silently overwriting the first.
    std::set<std::string> seenFiles;
};

// True if all three conditioning-indicator slots on this line are blank.
static bool oCondBlank(const std::string& line, const ColSpec& c1, const ColSpec& c2, const ColSpec& c3) {
    return extractCol(line, c1).empty() && extractCol(line, c2).empty() && extractCol(line, c3).empty();
}

static void handleOSpecLine(Program* program, OSpecState& state,
                             const std::string& line, int lineNo) {
    std::string fileName = extractCol(line, OSpec::FileName);
    if (!fileName.empty()) {
        // Position 17 (SC09-2508 p.572): D (detail) is the ordinary record type
        // and matches what this compiler emits, so accept it. H (heading),
        // T (total) and E (exception) need RPG-cycle timing that is not
        // implemented. IBM *requires* a value here (RNF6005 when blank), so
        // rejecting every non-blank entry left no mutually acceptable form.
        std::string recType = upper(extractCol(line, OSpec::RecType));
        if (!recType.empty() && recType != "D") {
            report_fixed_format_error(lineNo,
                "O-spec: record type '" + recType + "' (position 17) needs RPG-cycle timing "
                "this compiler doesn't implement; only 'D' (detail) is supported. See TODO.md");
            return;
        }
        if (!extractCol(line, OSpec::AddDel).empty()) {
            report_fixed_format_error(lineNo, "O-spec: record addition/deletion (positions 18-20) is not supported");
            return;
        }
        if (!oCondBlank(line, OSpec::Cond1, OSpec::Cond2, OSpec::Cond3)) {
            report_fixed_format_error(lineNo,
                "O-spec: conditioning indicators (positions 21-29) are not yet supported — see TODO.md");
            return;
        }
        if (!extractCol(line, OSpec::ExceptName).empty()) {
            report_fixed_format_error(lineNo, "O-spec: EXCEPT name (positions 30-39) is not supported — see TODO.md");
            return;
        }
        if (!extractCol(line, OSpec::SpaceSkip).empty()) {
            report_fixed_format_error(lineNo,
                "O-spec: printer spacing/skip (positions 40-51) is not supported — this compiler "
                "has no PRINTER-file runtime; see TODO.md");
            return;
        }
        std::string upperFileName = upper(fileName);
        if (!state.seenFiles.insert(upperFileName).second) {
            report_fixed_format_error(lineNo,
                "O-spec: only one record format per file is supported (real DDS disambiguates "
                "multiple O-spec formats for one file via record-type/EXCEPT names, both "
                "deferred — see TODO.md)");
            return;
        }
        auto* orf = new ORecordFormat(upperFileName);
        orf->line = lineNo;
        program->statements.emplace_back(orf);
        state.currentFormat = orf;
        return;
    }

    if (upper(extractCol(line, OSpec::LogicalRel)) == "AND" ||
        upper(extractCol(line, OSpec::LogicalRel)) == "OR") {
        report_fixed_format_error(lineNo,
            "O-spec: AND/OR conditioning continuation lines are not supported — see TODO.md");
        return;
    }

    // Field/constant description line.
    if (!state.currentFormat) {
        report_fixed_format_error(lineNo, "O-spec: field description with no preceding record line");
        return;
    }
    if (!oCondBlank(line, OSpec::FCond1, OSpec::FCond2, OSpec::FCond3)) {
        report_fixed_format_error(lineNo,
            "O-spec: output conditioning indicators (positions 21-29) are not yet supported — see TODO.md");
        return;
    }
    std::string fname = extractCol(line, OSpec::FieldName);
    std::string constantRaw = trim(extractCol(line, OSpec::Constant));
    warnIfNotRightAdjusted(line, OSpec::EndPos, lineNo, "O-spec End-Position");

    std::string endStr = extractCol(line, OSpec::EndPos);
    if (endStr.empty() || (endStr[0] == '+' || endStr[0] == '-')) {
        report_fixed_format_error(lineNo,
            "O-spec: end position (positions 47-51) is required and must be an absolute position "
            "(relative +n/-n positions are not supported)");
        return;
    }
    if (fname.empty() && constantRaw.empty()) {
        report_fixed_format_error(lineNo, "O-spec: field description requires a field name or a constant");
        return;
    }

    OFieldDesc f;
    f.endPos = atoi(endStr.c_str());
    if (!fname.empty()) {
        f.fieldName = upper(fname);
    } else {
        // Constant: a quoted literal ('text'). Anything else at 53-80
        // (edit words, DATE/TIME/SYSNAME/etc.) isn't supported yet.
        if (constantRaw.size() >= 2 && constantRaw.front() == '\'' && constantRaw.back() == '\'') {
            f.constant = constantRaw.substr(1, constantRaw.size() - 2);
        } else {
            report_fixed_format_error(lineNo,
                "O-spec: only a quoted 'constant' is supported at positions 53-80 (no edit words/reserved words yet)");
            return;
        }
    }
    std::string editCodeStr = extractCol(line, OSpec::EditCode);
    if (!editCodeStr.empty()) f.editCode = editCodeStr[0];
    f.blankAfter = upper(extractCol(line, OSpec::BlankAfter)) == "B";
    state.currentFormat->fields.push_back(f);
}

// The C++ symbol a member with an *ENTRY PLIST compiles to. A traditional
// CALL resolves a program name to a same-named function (see codegen's
// CallStmt), and fixed-format source has no P-spec to name a procedure
// with, so the member's own file name is what the caller must be able to
// spell: `CALL 'ORD100'` links to ORD100.rpgle's entry point. Directory
// and extension are stripped and the name upper-cased, matching how RPG
// program names are written.
static std::string entryNameFromFile(const std::string& path) {
    size_t slash = path.find_last_of("/\\");
    std::string base = (slash == std::string::npos) ? path : path.substr(slash + 1);
    size_t dot = base.find_last_of('.');
    if (dot != std::string::npos && dot > 0) base = base.substr(0, dot);
    return upper(base);
}

// --- Main driver ------------------------------------------------------

Program* parseFixedFormat(const std::string& src_text, const std::string& filename) {
    auto* program = new Program();
    std::vector<std::string> lines = splitLines(src_text);
    bool copyOk = true;
    lines = expandCopyDirectives(lines, 0, copyOk);

    std::string hSpecTail;
    PendingFSpec pendingF;
    DSpecState dState;
    ISpecState iState;
    OSpecState oState;

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
        // Only this call site's text is transpiler-synthesized (never
        // user-typed), so only here is GOTO/TAG allowed — see
        // g_allow_fixed_only_stmts's doc comment in free_bridge.h.
        g_allow_fixed_only_stmts = true;
        auto stmts = parse_free_block(buf, startLine);
        g_allow_fixed_only_stmts = false;
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
                // Inside a fixed-format source, positions 1-5 are the
                // sequence-number area and 6-7 are the form type and comment
                // flag; free-format code lives in positions 8-80 (SC09-2508
                // "Free-Form Statements"). Code starting earlier is read by
                // IBM as a malformed specification -- "  NAME = 'x';" puts NAM
                // in the sequence area and E in the form-type column, giving
                // RNF0257 at severity 30. This compiler used to accept a
                // /free body at any column, which hid the problem in 24 files.
                if (!trimmed.empty() && !trimmed.empty()) {
                    size_t indent = line.find_first_not_of(" \t");
                    if (indent != std::string::npos && indent < 7) {
                        report_fixed_format_error(lineNo,
                            "/FREE block: code starts in position " + std::to_string(indent + 1) +
                            "; free-form statements must begin at position 8 or later "
                            "(positions 1-7 are the sequence area, form type and comment flag) "
                            "(IBM: RNF0257)");
                    }
                }
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
        if (specType != "I") iState.currentFormat = nullptr;
        if (specType != "O") oState.currentFormat = nullptr;

        if (specType == "H") {
            hSpecTail += " " + extractCol(line, HSpec::KeywordTail);
        } else if (specType == "F") {
            handleFSpecLine(program, pendingF, line, lineNo);
        } else if (specType == "D") {
            handleDSpecLine(program, dState, line, lineNo);
        } else if (specType == "C") {
            if (!inCSpecRun) { inCSpecRun = true; cState.startLine = lineNo; }
            feedCSpecLine(cState, line, lineNo);
        } else if (specType == "I") {
            handleISpecLine(program, iState, line, lineNo);
        } else if (specType == "O") {
            handleOSpecLine(program, oState, line, lineNo);
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

    // *ENTRY PLIST — collected by the C-spec transpiler alongside the named
    // PLISTs (cState.plists survives each flush), and read back here
    // because it changes what the whole member compiles to rather than
    // what any one statement does.
    auto entry = cState.plists.find("*ENTRY");
    if (entry != cState.plists.end() && !entry->second.empty()) {
        if (program->nomain) {
            // NOMAIN discards the mainline, which is precisely what an
            // *ENTRY PLIST turns into a callable function — so the two
            // together would silently compile to nothing at all.
            report_fixed_format_error(1, "*ENTRY PLIST cannot be combined with NOMAIN — "
                "*ENTRY already makes this member a callable function rather than a "
                "standalone program, and NOMAIN would discard its calculations");
        }
        std::string name = entryNameFromFile(filename);
        bool ok = !name.empty() && (isalpha((unsigned char)name[0]) || name[0] == '_');
        for (char ch : name)
            if (!isalnum((unsigned char)ch) && ch != '_') ok = false;
        if (!ok) {
            report_fixed_format_error(1, "*ENTRY PLIST: this member compiles to a function "
                "named after its own file, which a caller spells in CALL — but '" + name +
                "' is not usable as a program name (letters, digits and underscores only). "
                "Rename the source file.");
        } else {
            program->entry_name = name;
            for (const auto& p : entry->second)
                program->entry_params.push_back(EntryParam{p.name, p.target, p.line});
        }
    }

    return program;
}

} // namespace fixed
} // namespace rpg
