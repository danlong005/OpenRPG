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

// Extracts the (trimmed) substring for `spec` from `line`, converting the
// 1-based inclusive column range to a 0-based std::string::substr call
// and clamping to the line's actual length (a physical source line is
// often shorter than 80 columns — trailing blanks are typically not
// stored). Returns "" if the range starts past the end of the line.
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
