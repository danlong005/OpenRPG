#ifndef RPG_FIXED_COLUMNS_H
#define RPG_FIXED_COLUMNS_H

#include <string>

namespace rpg {
namespace fixed {

// Column layouts for classic fixed-format (column-based) RPG source —
// H/F/D specs only (Phase 1 scope; see TODO.md's "Fixed-Format Source
// Support" entry). Every range below is verified against IBM's ILE RPG
// Language Reference, form SC09-2508 ("Positions N-M" subsections of
// chapters 13 (Control), 14 (File Description), and 15 (Definition)) —
// not guessed. If a column number here ever needs correcting, re-check
// against that manual, not against inference from example source.
//
// All ranges are 1-based and inclusive, matching how the manual itself
// numbers columns.
struct ColSpec {
    const char* fieldName;
    int startCol;   // 1-based, inclusive
    int endCol;     // 1-based, inclusive
    const char* manualRef;
};

// Common to every spec type.
inline constexpr ColSpec SeqNumber   {"SeqNumber",    1,   5, "SC09-2508: positions 1-5, sequence number/comment"};
inline constexpr ColSpec SpecType    {"SpecType",     6,   6, "SC09-2508: position 6, spec type (H/F/D/I/C/O/P)"};
inline constexpr ColSpec CommentFlag {"CommentFlag",  7,   7, "SC09-2508: position 7, '*' = whole line is a comment"};

namespace HSpec {
    // H-spec (Control): position 6 dispatch only — positions 7-80 are a
    // free keyword-list, not further column-positional data. See
    // parseKeywordList() (keyword_list.h) for how the tail is scanned.
    inline constexpr ColSpec KeywordTail {"KeywordTail", 7, 80, "SC09-2508 ch.13: Control spec, positions 7-80"};
}

namespace FSpec {
    // F-spec (File Description).
    inline constexpr ColSpec FileName    {"FileName",    7,  16, "SC09-2508 ch.14: positions 7-16"};
    inline constexpr ColSpec FileType    {"FileType",    17, 17, "SC09-2508 ch.14: position 17 (I/O/U/C)"};
    inline constexpr ColSpec FileDesig   {"FileDesig",   18, 18, "SC09-2508 ch.14: position 18 (blank/P/S/R/T/F)"};
    inline constexpr ColSpec EofFlag     {"EofFlag",     19, 19, "SC09-2508 ch.14: position 19 (E)"};
    inline constexpr ColSpec AddFlag     {"AddFlag",     20, 20, "SC09-2508 ch.14: position 20 (A)"};
    inline constexpr ColSpec Sequence    {"Sequence",    21, 21, "SC09-2508 ch.14: position 21 (A/D)"};
    inline constexpr ColSpec FileFormat  {"FileFormat",  22, 22, "SC09-2508 ch.14: position 22 (E/F)"};
    inline constexpr ColSpec RecordLen   {"RecordLen",   23, 27, "SC09-2508 ch.14: positions 23-27"};
    inline constexpr ColSpec ProcessMode {"ProcessMode", 28, 28, "SC09-2508 ch.14: position 28"};
    inline constexpr ColSpec KeyFieldLen {"KeyFieldLen", 29, 33, "SC09-2508 ch.14: positions 29-33"};
    inline constexpr ColSpec RecAddrType {"RecAddrType", 34, 34, "SC09-2508 ch.14: position 34"};
    inline constexpr ColSpec FileOrg     {"FileOrg",     35, 35, "SC09-2508 ch.14: position 35 (I=indexed, etc.)"};
    inline constexpr ColSpec Device      {"Device",      36, 42, "SC09-2508 ch.14: positions 36-42 (DISK/PRINTER/WORKSTN/SPECIAL/SEQ)"};
    // Position 43 is reserved/must be blank — no ColSpec needed.
    inline constexpr ColSpec KeywordTail {"KeywordTail", 44, 80, "SC09-2508 ch.14: positions 44-80, continuable"};
}

namespace DSpec {
    // D-spec (Definition).
    inline constexpr ColSpec Name        {"Name",        7,  21, "SC09-2508 ch.15: positions 7-21, continuable via trailing '...'"};
    inline constexpr ColSpec ExtDescFlag {"ExtDescFlag", 22, 22, "SC09-2508 ch.15: position 22 (E or blank)"};
    inline constexpr ColSpec DsType      {"DsType",      23, 23, "SC09-2508 ch.15: position 23 (blank/S/U)"};
    inline constexpr ColSpec DefType     {"DefType",     24, 25, "SC09-2508 ch.15: positions 24-25 (blank/C/DS/PR/PI/S)"};
    inline constexpr ColSpec FromPos     {"FromPos",     26, 32, "SC09-2508 ch.15: positions 26-32"};
    inline constexpr ColSpec ToLen       {"ToLen",       33, 39, "SC09-2508 ch.15: positions 33-39 (to-position or length)"};
    inline constexpr ColSpec DataType    {"DataType",    40, 40, "SC09-2508 ch.15: position 40"};
    inline constexpr ColSpec Decimals    {"Decimals",    41, 42, "SC09-2508 ch.15: positions 41-42"};
    // Position 43 is reserved/must be blank — no ColSpec needed.
    inline constexpr ColSpec KeywordTail {"KeywordTail", 44, 80, "SC09-2508 ch.15: positions 44-80, continuable"};
}

namespace CSpec {
    // C-spec (Calculation) — traditional and extended-factor-2 layouts share
    // the same column positions (SC09-2508 "Calculation Specifications",
    // p.559 Table 125 "Operation Codes in Traditional Syntax" and p.565
    // "Extended Factor 2 Syntax"); which fields apply depends on the opcode.
    inline constexpr ColSpec ControlLevel {"ControlLevel", 7,   8, "SC09-2508 p.560: positions 7-8 (blank, SR, or AN/OR here; L0/L1-L9/LR are RPG-cycle-only, rejected. AN/OR are not cycle-related at all — they combine the positions-9-11 conditioning indicators of consecutive lines, the only way to write a multi-indicator condition)"};
    inline constexpr ColSpec Indicators   {"Indicators",   9,  11, "SC09-2508 p.561: positions 9-11, conditioning indicator"};
    inline constexpr ColSpec Factor1      {"Factor1",      12, 25, "SC09-2508 p.562: positions 12-25 (blank for extended-factor-2 opcodes)"};
    inline constexpr ColSpec Opcode       {"Opcode",       26, 35, "SC09-2508 p.562: positions 26-35, operation code + (extender)"};
    inline constexpr ColSpec Factor2      {"Factor2",      36, 49, "SC09-2508 p.563: positions 36-49 (traditional-syntax opcodes only)"};
    inline constexpr ColSpec Result       {"Result",       50, 63, "SC09-2508 p.563: positions 50-63 (traditional-syntax opcodes only)"};
    inline constexpr ColSpec Length       {"Length",       64, 68, "SC09-2508 p.563: positions 64-68 (must be blank — inline field definition not supported)"};
    inline constexpr ColSpec Decimals     {"Decimals",     69, 70, "SC09-2508 p.564: positions 69-70 (must be blank — inline field definition not supported)"};
    inline constexpr ColSpec ResultInd    {"ResultInd",    71, 76, "SC09-2508 p.564: positions 71-76 (must be blank for every opcode but COMP — free-form drops resulting indicators; COMP is the exception, since its whole effect IS the three indicators and indicator assignment is expressible)"};
    // COMP's three resulting-indicator slots (SC09-2508 p.564): high
    // (factor 1 > factor 2), low (factor 1 < factor 2), equal.
    inline constexpr ColSpec ResultIndHi  {"ResultIndHi",  71, 72, "SC09-2508 p.564: positions 71-72, high (factor 1 > factor 2)"};
    inline constexpr ColSpec ResultIndLo  {"ResultIndLo",  73, 74, "SC09-2508 p.564: positions 73-74, low (factor 1 < factor 2)"};
    inline constexpr ColSpec ResultIndEq  {"ResultIndEq",  75, 76, "SC09-2508 p.564: positions 75-76, equal"};
    inline constexpr ColSpec ExtFactor2   {"ExtFactor2",   36, 80, "SC09-2508 p.565: positions 36-80, one free-form expression (extended-factor-2 opcodes only); continuation lines resume here with 7-35 blank"};
}

namespace ISpec {
    // I-spec (Input), program-described files only — SC09-2508
    // "Input Specifications" > "Program Described Files" (p.545-555).
    // Record identification entries (one line per record type):
    inline constexpr ColSpec FileName        {"FileName",        7,  16, "SC09-2508 p.545: positions 7-16"};
    inline constexpr ColSpec LogicalRel      {"LogicalRel",      16, 18, "SC09-2508 p.546: positions 16-18, AND/OR continuation (must be blank — not supported)"};
    inline constexpr ColSpec Sequence        {"Sequence",        17, 18, "SC09-2508 p.546: positions 17-18 (must be blank — sequence checking not supported)"};
    inline constexpr ColSpec Number          {"Number",          19, 19, "SC09-2508 p.547: position 19 (must be blank)"};
    inline constexpr ColSpec Option          {"Option",          20, 20, "SC09-2508 p.547: position 20 (must be blank)"};
    inline constexpr ColSpec RecordIdInd     {"RecordIdInd",     21, 22, "SC09-2508 p.547: positions 21-22, record identifying indicator"};
    // Three record-identification-code sets (position/not/codepart/character),
    // p.548 Table: "23-30", "31-38", "39-46". Only code-part 'C' (character)
    // is supported — Z (zone) and D (digit) are rejected as unsupported.
    inline constexpr ColSpec Set1Position    {"Set1Position",    23, 27, "SC09-2508 p.548: positions 23-27"};
    inline constexpr ColSpec Set1Not         {"Set1Not",         28, 28, "SC09-2508 p.548: position 28"};
    inline constexpr ColSpec Set1CodePart    {"Set1CodePart",    29, 29, "SC09-2508 p.548: position 29 (C/Z/D — only C supported)"};
    inline constexpr ColSpec Set1Character   {"Set1Character",   30, 30, "SC09-2508 p.548: position 30"};
    inline constexpr ColSpec Set2Position    {"Set2Position",    31, 35, "SC09-2508 p.548: positions 31-35"};
    inline constexpr ColSpec Set2Not         {"Set2Not",         36, 36, "SC09-2508 p.548: position 36"};
    inline constexpr ColSpec Set2CodePart    {"Set2CodePart",    37, 37, "SC09-2508 p.548: position 37 (C/Z/D — only C supported)"};
    inline constexpr ColSpec Set2Character   {"Set2Character",   38, 38, "SC09-2508 p.548: position 38"};
    inline constexpr ColSpec Set3Position    {"Set3Position",    39, 43, "SC09-2508 p.548: positions 39-43"};
    inline constexpr ColSpec Set3Not         {"Set3Not",         44, 44, "SC09-2508 p.548: position 44"};
    inline constexpr ColSpec Set3CodePart    {"Set3CodePart",    45, 45, "SC09-2508 p.548: position 45 (C/Z/D — only C supported)"};
    inline constexpr ColSpec Set3Character   {"Set3Character",   46, 46, "SC09-2508 p.548: position 46"};
    // Field description entries (one line per field, following a record-ID line):
    inline constexpr ColSpec DataAttributes  {"DataAttributes",  31, 34, "SC09-2508 p.550: positions 31-34 (must be blank — date/time external format and *VAR not supported)"};
    inline constexpr ColSpec DateTimeSep     {"DateTimeSep",     35, 35, "SC09-2508 p.550: position 35 (must be blank)"};
    inline constexpr ColSpec DataFormat      {"DataFormat",      36, 36, "SC09-2508 p.550: position 36"};
    inline constexpr ColSpec FromPos         {"FromPos",         37, 41, "SC09-2508 p.551: positions 37-41"};
    inline constexpr ColSpec ToPos           {"ToPos",           42, 46, "SC09-2508 p.551: positions 42-46"};
    inline constexpr ColSpec Decimals        {"Decimals",        47, 48, "SC09-2508 p.552: positions 47-48"};
    inline constexpr ColSpec FieldName       {"FieldName",       49, 62, "SC09-2508 p.552: positions 49-62"};
    inline constexpr ColSpec ControlLevel    {"ControlLevel",    63, 64, "SC09-2508 p.553: positions 63-64 (L1-L9)"};
    inline constexpr ColSpec MatchingFields  {"MatchingFields",  65, 66, "SC09-2508 p.553: positions 65-66 (must be blank — multi-file matching not supported)"};
    inline constexpr ColSpec FieldRecordRel  {"FieldRecordRel",  67, 68, "SC09-2508 p.554: positions 67-68 (must be blank — OR-relationship field sharing not supported)"};
    inline constexpr ColSpec FieldIndPlus    {"FieldIndPlus",    69, 70, "SC09-2508 p.555: positions 69-70"};
    inline constexpr ColSpec FieldIndMinus   {"FieldIndMinus",   71, 72, "SC09-2508 p.555: positions 71-72"};
    inline constexpr ColSpec FieldIndZeroBlank {"FieldIndZeroBlank", 73, 74, "SC09-2508 p.555: positions 73-74"};
}

namespace OSpec {
    // O-spec (Output), program-described DISK files only — SC09-2508
    // "Output Specifications" > "Program Described Files" (p.569-580).
    // Record identification and control entries (one line per record type):
    inline constexpr ColSpec FileName    {"FileName",    7,  16, "SC09-2508 p.570: positions 7-16"};
    inline constexpr ColSpec LogicalRel  {"LogicalRel",  16, 18, "SC09-2508 p.572: positions 16-18, AND/OR continuation (must be blank — not supported)"};
    inline constexpr ColSpec RecType     {"RecType",     17, 17, "SC09-2508 p.572: position 17 (must be blank — H/T/E cycle/exception record types not supported)"};
    inline constexpr ColSpec AddDel      {"AddDel",      18, 20, "SC09-2508 p.572-573: positions 18-20 (must be blank — ADD/DEL/release not supported)"};
    // Three conditioning-indicator slots (N-flag + 2-digit indicator each):
    inline constexpr ColSpec Cond1       {"Cond1",       21, 23, "SC09-2508 p.573: positions 21-23"};
    inline constexpr ColSpec Cond2       {"Cond2",       24, 26, "SC09-2508 p.573: positions 24-26"};
    inline constexpr ColSpec Cond3       {"Cond3",       27, 29, "SC09-2508 p.573: positions 27-29"};
    inline constexpr ColSpec ExceptName  {"ExceptName",  30, 39, "SC09-2508 p.573: positions 30-39 (must be blank — EXCEPT mechanism not supported)"};
    inline constexpr ColSpec SpaceSkip   {"SpaceSkip",   40, 51, "SC09-2508 p.574: positions 40-51 (must be blank — printer spacing/skip not supported, no printer runtime exists)"};
    // Field description and control entries (one line per field/constant):
    inline constexpr ColSpec FCond1      {"FCond1",      21, 23, "SC09-2508 p.575: positions 21-23"};
    inline constexpr ColSpec FCond2      {"FCond2",      24, 26, "SC09-2508 p.575: positions 24-26"};
    inline constexpr ColSpec FCond3      {"FCond3",      27, 29, "SC09-2508 p.575: positions 27-29"};
    inline constexpr ColSpec FieldName   {"FieldName",   30, 43, "SC09-2508 p.575: positions 30-43 (blank if a constant is given at 53-80 instead)"};
    inline constexpr ColSpec EditCode    {"EditCode",    44, 44, "SC09-2508 p.576: position 44"};
    inline constexpr ColSpec BlankAfter  {"BlankAfter",  45, 45, "SC09-2508 p.577: position 45 (B)"};
    inline constexpr ColSpec EndPos      {"EndPos",      47, 51, "SC09-2508 p.577: positions 47-51"};
    inline constexpr ColSpec Constant    {"Constant",    53, 80, "SC09-2508 p.578: positions 53-80, constant/edit word"};
}

// Extracts the (trimmed) substring for `spec` from `line`, converting the
// 1-based inclusive column range to a 0-based std::string::substr call
// and clamping to the line's actual length (a physical source line is
// often shorter than 80 columns — trailing blanks are typically not
// stored). Returns "" if the range starts past the end of the line.
// Like extractCol but WITHOUT trimming, so a caller can tell " 0" from "0 ".
// IBM requires numeric entries right-adjusted within their field and reports
// RNF0263 at severity 20 when they are not; extractCol's trim makes the two
// forms indistinguishable, which is why 89 malformed D-specs accumulated in
// the test corpus unnoticed. Short lines are padded, since a right-adjusted
// entry can legitimately end past the physical end of the line.
inline std::string extractColRaw(const std::string& line, const ColSpec& spec) {
    std::string padded = line;
    if ((int)padded.size() < spec.endCol) padded.resize(spec.endCol, ' ');
    return padded.substr(spec.startCol - 1, spec.endCol - spec.startCol + 1);
}

inline std::string extractCol(const std::string& line, const ColSpec& spec) {
    int start0 = spec.startCol - 1;
    if (start0 >= static_cast<int>(line.size()) || start0 < 0) return "";
    int end0 = spec.endCol; // exclusive, since endCol is inclusive 1-based
    if (end0 > static_cast<int>(line.size())) end0 = static_cast<int>(line.size());
    if (end0 <= start0) return "";
    std::string raw = line.substr(start0, end0 - start0);
    size_t a = raw.find_first_not_of(' ');
    if (a == std::string::npos) return "";
    size_t b = raw.find_last_not_of(' ');
    return raw.substr(a, b - a + 1);
}

} // namespace fixed
} // namespace rpg

#endif // RPG_FIXED_COLUMNS_H
