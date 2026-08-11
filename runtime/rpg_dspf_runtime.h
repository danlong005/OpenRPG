#pragma once
//
// rpg_dspf_runtime.h — OpenDSPF display file runtime (ncurses)
//
// Renders RPG display file record formats in the terminal using ncurses.
// Works over SSH and locally; each process owns its own terminal session.
// No daemon, no network, no browser required.
//
// Link with -lncurses (Linux/macOS) or -lpdcurses (Windows/PDCurses).
//
// API (generated code requires no changes):
//   dspf_init(path)           load descriptor, initialise ncurses
//   dspf_set_indicators(p,n)  pass current indicator array before each I/O op
//   dspf_exfmt(rec, buf)      render screen, collect input, return indicator
//   dspf_write(rec, buf)      write record (SFL: append row; SFLCTL: clear SFL; else render)
//   dspf_read (rec, buf)      same as exfmt
//   dspf_close()              restore terminal
//

#ifdef _WIN32
#  include <curses.h>   // PDCurses drop-in
#else
#  include <ncurses.h>
#endif

#include <algorithm>
#include <cassert>
#include <cctype>
#include <climits>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

// =============================================================================
// Minimal JSON parser (reads the .dspfd descriptor)
// =============================================================================

struct DspfJVal {
    enum Kind { Null, Bool, Int, Str, Arr, Obj } kind = Null;
    bool b = false; int i = 0;
    std::string s;
    std::vector<DspfJVal> arr;
    std::map<std::string, DspfJVal> obj;

    const DspfJVal& operator[](const std::string& k) const {
        static DspfJVal nul;
        auto it = obj.find(k); return it == obj.end() ? nul : it->second;
    }
    const DspfJVal& operator[](size_t idx) const {
        static DspfJVal nul; return idx < arr.size() ? arr[idx] : nul;
    }
    bool        has(const std::string& k) const { return obj.count(k) > 0; }
    std::string str()  const { return s; }
    int         num()  const { return i; }
    size_t      size() const { return arr.size(); }
};

static void dspf__skipWS(const char*& p) {
    while (*p && isspace((unsigned char)*p)) p++;
}

static std::string dspf__parseStr(const char*& p) {
    assert(*p == '"'); p++;
    std::string r;
    while (*p && *p != '"') {
        if (*p == '\\') { p++;
            switch (*p) {
                case '"':  r += '"';  break; case '\\': r += '\\'; break;
                case 'n':  r += '\n'; break; case 'r':  r += '\r'; break;
                case 't':  r += '\t'; break; default:   r += *p;   break;
            }
        } else { r += *p; }
        p++;
    }
    if (*p == '"') p++;
    return r;
}

static DspfJVal dspf__parseVal(const char*& p);

static DspfJVal dspf__parseObj(const char*& p) {
    assert(*p == '{'); p++;
    DspfJVal v; v.kind = DspfJVal::Obj;
    dspf__skipWS(p);
    while (*p && *p != '}') {
        dspf__skipWS(p);
        if (*p != '"') { p++; continue; }
        std::string key = dspf__parseStr(p);
        dspf__skipWS(p); if (*p == ':') p++;
        dspf__skipWS(p);
        v.obj[key] = dspf__parseVal(p);
        dspf__skipWS(p); if (*p == ',') p++;
        dspf__skipWS(p);
    }
    if (*p == '}') p++;
    return v;
}

static DspfJVal dspf__parseArr(const char*& p) {
    assert(*p == '['); p++;
    DspfJVal v; v.kind = DspfJVal::Arr;
    dspf__skipWS(p);
    while (*p && *p != ']') {
        v.arr.push_back(dspf__parseVal(p));
        dspf__skipWS(p); if (*p == ',') p++;
        dspf__skipWS(p);
    }
    if (*p == ']') p++;
    return v;
}

static DspfJVal dspf__parseVal(const char*& p) {
    dspf__skipWS(p);
    if (*p == '{') return dspf__parseObj(p);
    if (*p == '[') return dspf__parseArr(p);
    if (*p == '"') { DspfJVal v; v.kind=DspfJVal::Str; v.s=dspf__parseStr(p); return v; }
    if (strncmp(p,"true", 4)==0){p+=4;DspfJVal v;v.kind=DspfJVal::Bool;v.b=true; return v;}
    if (strncmp(p,"false",5)==0){p+=5;DspfJVal v;v.kind=DspfJVal::Bool;v.b=false;return v;}
    if (strncmp(p,"null", 4)==0){p+=4;return DspfJVal{};}
    DspfJVal v; v.kind=DspfJVal::Int;
    bool neg=(*p=='-'); if(neg) p++;
    while (*p&&isdigit((unsigned char)*p)){v.i=v.i*10+(*p-'0');p++;}
    if(neg) v.i=-v.i;
    return v;
}

static DspfJVal dspf__parseJSON(const std::string& src) {
    const char* p = src.c_str(); return dspf__parseVal(p);
}

// =============================================================================
// Buffer helpers — walk buffer using descriptor to extract / apply field values
// =============================================================================

// Field types stored as char[len+1] in the generated _buf struct (codegen's
// cppFieldType default case) rather than long/double — "A" plus the
// date/time/timestamp types, which have no numeric representation.
static bool dspf__isCharType(const std::string& type) {
    return type == "A" || type == "L" || type == "T" || type == "Z";
}

static std::map<std::string,std::string>
dspf__extractFields(const DspfJVal& rec, const void* buf) {
    std::map<std::string,std::string> m;
    std::map<std::string,bool> seen; // tracks fields already mapped to a buffer slot
    const char* p = (const char*)buf;
    const DspfJVal& fields = rec["fields"];
    for (size_t i = 0; i < fields.size(); i++) {
        std::string name = fields[i]["name"].str();
        std::string type = fields[i]["type"].str();
        int len  = fields[i]["len"].num();
        int dec  = fields[i]["dec"].num();
        std::string io = fields[i]["io"].str();
        if (io == "H") { // advance pointer but skip value
            if (dspf__isCharType(type)) p += (len + 1);
            else if (type == "B") p += sizeof(long);
            else p += sizeof(double);
            continue;
        }
        // Duplicate display entries (same field, different conditioning/attributes)
        // share one buffer slot — only the first occurrence advances the pointer.
        if (seen.count(name)) continue;
        seen[name] = true;
        if (dspf__isCharType(type)) {
            std::string val(p, strnlen(p, (size_t)len));
            while (!val.empty() && val.back() == ' ') val.pop_back();
            m[name] = val;
            p += (len + 1);
        } else if (type == "B") {
            m[name] = std::to_string(*(const long*)p);
            p += sizeof(long);
        } else {
            char tmp[64];
            snprintf(tmp, sizeof(tmp), "%.*f", dec, *(const double*)p);
            m[name] = tmp;
            p += sizeof(double);
        }
    }
    return m;
}

static void dspf__applyFields(const DspfJVal& rec,
                               const std::map<std::string,std::string>& vals,
                               void* buf) {
    char* p = (char*)buf;
    std::map<std::string,bool> seen;
    const DspfJVal& fields = rec["fields"];
    for (size_t i = 0; i < fields.size(); i++) {
        std::string name = fields[i]["name"].str();
        std::string type = fields[i]["type"].str();
        int len = fields[i]["len"].num();
        std::string io = fields[i]["io"].str();
        if (io == "H") {
            if (dspf__isCharType(type)) p += (len + 1);
            else if (type == "B") p += sizeof(long);
            else p += sizeof(double);
            continue;
        }
        if (seen.count(name)) continue; // duplicate display entry — shares first slot
        seen[name] = true;
        if (dspf__isCharType(type)) {
            auto it = vals.find(name);
            if (it != vals.end()) {
                size_t clen = std::min((int)it->second.size(), len);
                memcpy(p, it->second.c_str(), clen);
                memset(p + clen, ' ', len - clen);
                p[len] = '\0';
            }
            p += (len + 1);
        } else if (type == "B") {
            auto it = vals.find(name);
            if (it != vals.end()) try { *(long*)p = std::stol(it->second); } catch (...) {}
            p += sizeof(long);
        } else {
            auto it = vals.find(name);
            if (it != vals.end()) try { *(double*)p = std::stod(it->second); } catch (...) {}
            p += sizeof(double);
        }
    }
}

// =============================================================================
// Indicator state — set by caller before each I/O operation
// =============================================================================

static bool g_dspf_indicators[100] = {};

inline void dspf_set_indicators(const bool* inds, int count) {
    int n = (count < 100) ? count : 100;
    for (int i = 0; i < n; i++) g_dspf_indicators[i] = inds[i];
}

// Returns true if the item's COND keywords are satisfied (or absent).
static bool dspf__condPass(const DspfJVal& item) {
    const DspfJVal& kw = item["keywords"];
    for (size_t i = 0; i < kw.size(); i++) {
        const std::string& k = kw[i].str();
        if (k.rfind("COND(", 0) != 0) continue;
        std::string inner = k.substr(5, k.size() > 6 ? k.size() - 6 : 0);
        bool neg = (!inner.empty() && (inner[0]=='N' || inner[0]=='n'));
        if (neg) inner = inner.substr(1);
        int ind = 0;
        if (inner.rfind("*IN", 0) == 0) {
            try { ind = std::stoi(inner.substr(3)); } catch (...) {}
        } else {
            try { ind = std::stoi(inner); } catch (...) {}
        }
        if (ind >= 0 && ind < 100) {
            bool on = g_dspf_indicators[ind];
            if (neg ? on : !on) return false;
        }
    }
    return true;
}

// Check if a record has any keyword whose text starts with `prefix`.
static bool dspf__hasRecKw(const DspfJVal& rec, const std::string& prefix) {
    const DspfJVal& kw = rec["keywords"];
    for (size_t i = 0; i < kw.size(); i++) {
        if (kw[i].str().rfind(prefix, 0) == 0) return true;
    }
    return false;
}

// CLRL(begline [endline]) — clear only that row range before writing,
// instead of the whole screen. endline omitted means "to the bottom".
static bool dspf__parseClrl(const DspfJVal& rec, int& startRow, int& endRow) {
    const DspfJVal& kw = rec["keywords"];
    for (size_t i = 0; i < kw.size(); i++) {
        const std::string& k = kw[i].str();
        if (k.rfind("CLRL(", 0) == 0) {
            std::istringstream iss(k.substr(5, k.size() > 6 ? k.size() - 6 : 0));
            int a = 0, b = 0;
            if (!(iss >> a) || a < 1) return false;
            startRow = a;
            endRow = (iss >> b) ? b : INT_MAX;
            return true;
        }
    }
    return false;
}

// Returns true when PROTECT is present and its indicator condition (if any) is met.
static bool dspf__isProtected(const DspfJVal& rec) {
    const DspfJVal& kw = rec["keywords"];
    for (size_t i = 0; i < kw.size(); i++) {
        const std::string& k = kw[i].str();
        if (k == "PROTECT") return true;
        if (k.rfind("PROTECT(", 0) == 0) {
            std::string inner = k.substr(8, k.size() > 9 ? k.size() - 9 : 0);
            bool neg = (!inner.empty() && (inner[0]=='N' || inner[0]=='n'));
            if (neg) inner = inner.substr(1);
            int ind = 0;
            if (inner.rfind("*IN", 0) == 0) {
                try { ind = std::stoi(inner.substr(3)); } catch (...) {}
            } else {
                try { ind = std::stoi(inner); } catch (...) {}
            }
            if (ind >= 0 && ind < 100) {
                bool on = g_dspf_indicators[ind];
                return neg ? !on : on;
            }
            return true;
        }
    }
    return false;
}

// =============================================================================
// ERRSFL — message subfile for validation errors
// =============================================================================
//
// Real DDS: SFLMSGRCD(nn) on a SFLCTL record reserves screen row nn onward
// to display the record's message subfile; ERRSFL enables routing that
// record's error indications there. On IBM i the message subfile is fed
// from the job's program message queue (SNDPGMMSG); OpenDSPF has no such
// queue, so this accumulates the validation-error text dspf__validateField
// already produces — same observable effect (a scrollable, growing list of
// error messages instead of only ever showing the single latest one) using
// what's actually available here. Global rather than per-record, matching
// a program message queue's own scope.

static std::vector<std::string> g_dspf_errsfl_messages;

// Row (1-based) SFLMSGRCD(nn) reserves for message display, or 0 if the
// record doesn't specify one.
static int dspf__sflMsgRcdRow(const DspfJVal& rec) {
    const DspfJVal& kw = rec["keywords"];
    for (size_t i = 0; i < kw.size(); i++) {
        const std::string& k = kw[i].str();
        if (k.rfind("SFLMSGRCD(", 0) == 0) {
            try { return std::stoi(k.substr(10)); } catch (...) {}
        }
    }
    return 0;
}

// Appends a message to the message subfile and redraws the reserved area,
// scrolled to show as many of the most recent messages as fit.
static void dspf__errsflShow(const DspfJVal& rec, const std::string& msg) {
    g_dspf_errsfl_messages.push_back(msg);
    int row = dspf__sflMsgRcdRow(rec);
    if (row <= 0) row = (LINES > 24) ? 24 : LINES;
    int maxLines = LINES - row + 1;
    if (maxLines < 1) maxLines = 1;
    int start = (int)g_dspf_errsfl_messages.size() - maxLines;
    if (start < 0) start = 0;
    attron(A_REVERSE);
    for (int i = start; i < (int)g_dspf_errsfl_messages.size(); i++) {
        mvprintw(row - 1 + (i - start), 0, "%-*s", COLS, g_dspf_errsfl_messages[i].c_str());
    }
    attroff(A_REVERSE);
    refresh();
}

// =============================================================================
// Field validation — VALUES / RANGE / COMP keywords
// =============================================================================

static std::string dspf__trimSpaces(const std::string& s) {
    size_t a = s.find_first_not_of(' ');
    if (a == std::string::npos) return "";
    size_t b = s.find_last_not_of(' ');
    return s.substr(a, b - a + 1);
}

// Splits a keyword's parenthesized content into whitespace-separated tokens,
// honoring single-quoted strings (with '' escaping) as one token each —
// e.g. "'A' 'B' 'C'" -> {"A","B","C"}, "1 100" -> {"1","100"}.
static std::vector<std::string> dspf__splitValueList(const std::string& inner) {
    std::vector<std::string> out;
    size_t i = 0;
    while (i < inner.size()) {
        while (i < inner.size() && inner[i] == ' ') i++;
        if (i >= inner.size()) break;
        if (inner[i] == '\'') {
            std::string tok;
            size_t j = i + 1;
            while (j < inner.size()) {
                if (inner[j] == '\'' && j + 1 < inner.size() && inner[j+1] == '\'') { tok += '\''; j += 2; }
                else if (inner[j] == '\'') { j++; break; }
                else { tok += inner[j]; j++; }
            }
            out.push_back(tok);
            i = j;
        } else {
            size_t j = i;
            while (j < inner.size() && inner[j] != ' ') j++;
            out.push_back(inner.substr(i, j - i));
            i = j;
        }
    }
    return out;
}

// Numeric comparison when both sides parse fully as numbers; falls back to
// lexicographic string comparison otherwise (character fields, VALUES lists
// of non-numeric codes, etc).
static int dspf__compareValues(const std::string& a, const std::string& b) {
    char* enda = nullptr; char* endb = nullptr;
    double da = strtod(a.c_str(), &enda);
    double db = strtod(b.c_str(), &endb);
    bool numA = enda != a.c_str() && *enda == '\0' && !a.empty();
    bool numB = endb != b.c_str() && *endb == '\0' && !b.empty();
    if (numA && numB) return (da < db) ? -1 : (da > db) ? 1 : 0;
    int c = a.compare(b);
    return (c < 0) ? -1 : (c > 0) ? 1 : 0;
}

// Validates a submitted field value against its VALUES/RANGE/COMP keywords
// (IBM i DDS field validation, enforced here since dspfc has no access to
// the caller's runtime once the buffer is returned). Returns an empty
// string if valid, or a user-facing error message if not.
static std::string dspf__validateField(const DspfJVal& field, const std::string& rawVal) {
    std::string val = dspf__trimSpaces(rawVal);
    const std::string& name = field["name"].str();
    const DspfJVal& kw = field["keywords"];

    for (size_t i = 0; i < kw.size(); i++) {
        const std::string& k = kw[i].str();

        if (k.rfind("VALUES(", 0) == 0) {
            std::string inner = k.substr(7, k.size() > 8 ? k.size() - 8 : 0);
            std::vector<std::string> allowed = dspf__splitValueList(inner);
            bool ok = false;
            for (auto& a : allowed) {
                if (dspf__compareValues(val, a) == 0) { ok = true; break; }
            }
            if (!ok) return name + ": value not valid";
        } else if (k.rfind("RANGE(", 0) == 0) {
            std::string inner = k.substr(6, k.size() > 7 ? k.size() - 7 : 0);
            std::vector<std::string> bounds = dspf__splitValueList(inner);
            if (bounds.size() == 2 &&
                (dspf__compareValues(val, bounds[0]) < 0 ||
                 dspf__compareValues(val, bounds[1]) > 0)) {
                return name + ": value not in range";
            }
        } else if (k.rfind("COMP(", 0) == 0) {
            std::string inner = k.substr(5, k.size() > 6 ? k.size() - 6 : 0);
            std::vector<std::string> parts = dspf__splitValueList(inner);
            if (parts.size() == 2) {
                std::string op = parts[0];
                for (auto& c : op) c = (char)toupper((unsigned char)c);
                int cmp = dspf__compareValues(val, parts[1]);
                bool ok = true;
                if      (op == "EQ") ok = (cmp == 0);
                else if (op == "NE") ok = (cmp != 0);
                else if (op == "LT") ok = (cmp <  0);
                else if (op == "NL") ok = (cmp >= 0);
                else if (op == "LE") ok = (cmp <= 0);
                else if (op == "GT") ok = (cmp >  0);
                else if (op == "NG") ok = (cmp <= 0);
                else if (op == "GE") ok = (cmp >= 0);
                if (!ok) return name + ": value fails comparison";
            }
        }
    }
    return "";
}

// Extract WINDOW parameters from a record. Returns true if the record is a window record.
static bool dspf__isWindow(const DspfJVal& rec, int& winRow, int& winCol, int& winH, int& winW) {
    if (!rec.has("window")) return false;
    winRow = rec["window"]["row"].num();
    winCol = rec["window"]["col"].num();
    winH   = rec["window"]["height"].num();
    winW   = rec["window"]["width"].num();
    return winRow > 0 && winH > 0 && winW > 0;
}

// =============================================================================
// Edit code / edit word formatting
// =============================================================================

static std::string dspf__applyEditCode(double val, int /*len*/, int dec, char code) {
    char u = (char)toupper((unsigned char)code);
    bool negative = (val < 0.0);
    double absval = std::fabs(val);

    // Raw formatted number
    char buf[64];
    snprintf(buf, sizeof(buf), "%.*f", dec, absval);
    std::string raw(buf);

    // Split integer / decimal
    std::string intPart, decPart;
    auto dot = raw.find('.');
    if (dot == std::string::npos) { intPart = raw; }
    else { intPart = raw.substr(0, dot); decPart = raw.substr(dot + 1); }

    // Code Z: strip all formatting, remove leading zeros
    if (u == 'Z') {
        std::string z;
        bool lead = true;
        for (char c : intPart) {
            if (c == '0' && lead) continue;
            lead = false; z += c;
        }
        if (!decPart.empty()) { z += '.'; z += decPart; }
        return z.empty() ? "0" : z;
    }

    // Code Y: date edit — nnnnnnn → nn/nn/nn (strips leading zero from first pair)
    if (u == 'Y') {
        std::string digits;
        for (char c : intPart) if (isdigit((unsigned char)c)) digits += c;
        while (digits.size() < 6) digits = "0" + digits;
        // mm/dd/yy from rightmost 6 digits
        std::string d = digits.size() >= 6 ? digits.substr(digits.size() - 6) : digits;
        std::string mm = d.substr(0, 2); if (mm[0]=='0') mm = mm.substr(1);
        return mm + "/" + d.substr(2, 2) + "/" + d.substr(4, 2);
    }

    // Zero-suppress: replace leading zeros with spaces
    {
        bool leading = true;
        for (char& c : intPart) {
            if (leading && c == '0') c = ' ';
            else leading = false;
        }
    }

    // Asterisk fill (codes A-D): replace leading spaces with '*'
    bool asterisk = (u=='A'||u=='B'||u=='C'||u=='D');
    if (asterisk) {
        for (char& c : intPart) if (c == ' ') c = '*';
    }

    // Comma separator (codes 1,2,A,B,J,K,N,O)
    bool useComma = (u=='1'||u=='2'||u=='A'||u=='B'||u=='J'||u=='K'||u=='N'||u=='O');
    if (useComma) {
        std::string result;
        int digitCount = 0;
        for (int i = (int)intPart.size() - 1; i >= 0; i--) {
            char c = intPart[i];
            if (c != ' ' && c != '*') {
                if (digitCount > 0 && digitCount % 3 == 0) result = "," + result;
                digitCount++;
            }
            result = c + result;
        }
        intPart = result;
    }

    std::string out = intPart;
    if (!decPart.empty()) out += "." + decPart;

    // Sign handling
    bool useCR    = (u=='2'||u=='4'||u=='B'||u=='D'||u=='K'||u=='M'||u=='O'||u=='Q');
    bool useMinus = (u=='J'||u=='L'||u=='N'||u=='P'||u=='3'||u=='4'||u=='C'||u=='D');
    if (negative) {
        if (useCR)    out += "CR";
        else if (useMinus) out = "-" + out;
    }

    return out;
}

static std::string dspf__applyEditWord(double val, int /*len*/, int dec,
                                        const std::string& mask) {
    bool negative = (val < 0.0);
    double absval = std::fabs(val);

    // Separate body from status (after single quote in mask)
    std::string body = mask;
    std::string status;
    auto sq = mask.find('\'');
    if (sq != std::string::npos) {
        body   = mask.substr(0, sq);
        status = mask.substr(sq + 1);
    }

    // Count digit slots (spaces) in body
    int slots = 0;
    for (char c : body) if (c == ' ') slots++;

    // Build digit string with appropriate decimal places
    char buf[64];
    snprintf(buf, sizeof(buf), "%0*.*f", slots, dec, absval);
    std::string digits;
    for (char c : std::string(buf)) if (isdigit((unsigned char)c)) digits += c;
    while ((int)digits.size() < slots) digits = "0" + digits;
    if ((int)digits.size() > slots) digits = digits.substr(digits.size() - slots);

    // Fill body slots with digits left-to-right
    std::string result = body;
    int di = 0;
    for (char& c : result) if (c == ' ' && di < (int)digits.size()) c = digits[di++];

    // Zero-suppress: blank leading zeros and adjacent literal chars
    bool suppress = true;
    for (size_t i = 0; i < result.size(); i++) {
        char c = result[i];
        if (suppress) {
            if (c == '0') { result[i] = ' '; }
            else if (!isdigit((unsigned char)c)) { result[i] = ' '; } // leading literal
            else { suppress = false; }
        }
    }

    // Append status section if negative
    if (negative && !status.empty()) result += status;

    return result;
}

// =============================================================================
// ncurses colour / attribute helpers
// =============================================================================

enum {
    DSPF_PAIR_NORMAL  = 1,
    DSPF_PAIR_RED     = 2,
    DSPF_PAIR_BLUE    = 3,
    DSPF_PAIR_GREEN   = 4,
    DSPF_PAIR_YELLOW  = 5,
    DSPF_PAIR_MAGENTA = 6,
    DSPF_PAIR_CYAN    = 7,
    // Background pairs — used for window borders
    DSPF_PAIR_BG_RED     = 8,
    DSPF_PAIR_BG_BLUE    = 9,
    DSPF_PAIR_BG_GREEN   = 10,
    DSPF_PAIR_BG_YELLOW  = 11,
    DSPF_PAIR_BG_MAGENTA = 12,
    DSPF_PAIR_BG_CYAN    = 13,
    DSPF_PAIR_BG_WHITE   = 14,
};

static int dspf__colorPair(const DspfJVal& field) {
    const DspfJVal& kw = field["keywords"];
    for (size_t i = 0; i < kw.size(); i++) {
        const std::string& k = kw[i].str();
        if (k == "COLOR(RED)")    return DSPF_PAIR_RED;
        if (k == "COLOR(BLUE)")   return DSPF_PAIR_BLUE;
        if (k == "COLOR(GREEN)")  return DSPF_PAIR_GREEN;
        if (k == "COLOR(YELLOW)") return DSPF_PAIR_YELLOW;
        if (k == "COLOR(PINK)")   return DSPF_PAIR_MAGENTA;
        if (k == "COLOR(TURQ)")   return DSPF_PAIR_CYAN;
    }
    return DSPF_PAIR_NORMAL;
}

static attr_t dspf__fieldAttrs(const DspfJVal& field) {
    attr_t a = A_NORMAL;
    const DspfJVal& kw = field["keywords"];
    for (size_t i = 0; i < kw.size(); i++) {
        const std::string& k = kw[i].str();
        if (k == "DSPATR(HI)") a |= A_BOLD;
        if (k == "DSPATR(BL)") a |= A_BLINK;
        if (k == "DSPATR(RI)") a |= A_REVERSE;
        if (k == "DSPATR(UL)") a |= A_UNDERLINE;
    }
    return a;
}

// Apply EDTCDE/EDTWRD formatting to a numeric field value string.
static std::string dspf__formatField(const DspfJVal& field, const std::string& raw) {
    std::string type = field["type"].str();
    if (dspf__isCharType(type)) return raw; // not numeric
    int len = field["len"].num();
    int dec = field["dec"].num();
    double numVal = 0.0;
    try { numVal = std::stod(raw); } catch (...) {}
    const DspfJVal& kw = field["keywords"];
    for (size_t i = 0; i < kw.size(); i++) {
        const std::string& k = kw[i].str();
        if (k.rfind("EDTCDE(", 0) == 0 && k.size() > 8) {
            return dspf__applyEditCode(numVal, len, dec, k[7]);
        }
        if (k.rfind("EDTWRD(", 0) == 0 && k.size() > 8) {
            std::string mask = k.substr(7, k.size() - 8);
            if (mask.size() >= 2 && mask.front() == '\'') mask = mask.substr(1);
            if (!mask.empty() && mask.back() == '\'') mask.pop_back();
            return dspf__applyEditWord(numVal, len, dec, mask);
        }
    }
    // No edit code: format with zero-fill, decimal point at correct position.
    // A ZONED/PACKED len=9 dec=2 field occupies 10 display chars (9 digits + '.').
    char buf[64];
    if (dec > 0) {
        snprintf(buf, sizeof(buf), "%0*.*f", len + 1, dec, numVal);
    } else {
        snprintf(buf, sizeof(buf), "%0*.*f", len, 0, numVal);
    }
    return std::string(buf);
}

// =============================================================================
// Window border rendering (WDWBORDER keyword)
// =============================================================================

static void dspf__drawWindowBorder(WINDOW* win, const DspfJVal& rec) {
    if (!rec.has("wdwborder")) {
        box(win, 0, 0);
        return;
    }

    const DspfJVal& wb  = rec["wdwborder"];
    std::string chars   = wb["chars"].str();
    std::string color   = wb["color"].str();
    std::string dspatr  = wb["dspatr"].str();

    // Map color name to background color pair
    int pair = 0;
    if      (color == "RED")    pair = DSPF_PAIR_BG_RED;
    else if (color == "BLUE")   pair = DSPF_PAIR_BG_BLUE;
    else if (color == "GREEN")  pair = DSPF_PAIR_BG_GREEN;
    else if (color == "YELLOW") pair = DSPF_PAIR_BG_YELLOW;
    else if (color == "PINK")   pair = DSPF_PAIR_BG_MAGENTA;
    else if (color == "TURQ")   pair = DSPF_PAIR_BG_CYAN;
    else if (color == "WHITE")  pair = DSPF_PAIR_BG_WHITE;

    // Map display attribute
    attr_t attrs = A_NORMAL;
    if      (dspatr == "HI") attrs = A_BOLD;
    else if (dspatr == "BL") attrs = A_BLINK;
    else if (dspatr == "RI") attrs = A_REVERSE;
    else if (dspatr == "UL") attrs = A_UNDERLINE;

    attr_t on = (pair ? COLOR_PAIR(pair) : 0) | attrs;
    if (on) wattron(win, on);

    if (chars.size() >= 8) {
        // IBM i char order: tl, top, tr, left, right, bl, bottom, br
        // ncurses wborder:  ls,  rs,  ts,   bs,   tl,  tr,     bl,     br
        wborder(win,
            (chtype)(unsigned char)chars[3], (chtype)(unsigned char)chars[4],
            (chtype)(unsigned char)chars[1], (chtype)(unsigned char)chars[6],
            (chtype)(unsigned char)chars[0], (chtype)(unsigned char)chars[2],
            (chtype)(unsigned char)chars[5], (chtype)(unsigned char)chars[7]);
    } else {
        box(win, 0, 0);
    }

    if (on) wattroff(win, on);
}

// =============================================================================
// Screen rendering
// =============================================================================

static void dspf__renderScreen(const DspfJVal& rec,
                                const std::map<std::string,std::string>& vals,
                                WINDOW* win, int rowOff, int colOff) {
    int clrStart, clrEnd;
    if (!dspf__hasRecKw(rec, "OVERLAY") && !dspf__hasRecKw(rec, "NOCLEAR")) {
        if (dspf__parseClrl(rec, clrStart, clrEnd)) {
            // Partial clear: only the declared row range, not the whole screen.
            int maxRows = (win == stdscr) ? LINES : getmaxy(win);
            int from = std::max(0, clrStart - 1 - rowOff);
            int to   = std::min(maxRows - 1, clrEnd - 1 - rowOff);
            for (int r = from; r <= to; r++) {
                wmove(win, r, 0);
                wclrtoeol(win);
            }
        } else if (win == stdscr) clear();
        else werase(win);
    }
    if (win != stdscr) dspf__drawWindowBorder(win, rec);

    // Literals
    const DspfJVal& lits = rec["literals"];
    for (size_t i = 0; i < lits.size(); i++) {
        if (!dspf__condPass(lits[i])) continue;
        int row = lits[i]["row"].num() - 1 - rowOff;
        int col = lits[i]["col"].num() - 1 - colOff;
        mvwprintw(win, row, col, "%s", lits[i]["text"].str().c_str());
    }

    // COLHDG('text'): implicit field label directly above the field, one
    // row up at the same column — the common case (a subfile column
    // heading) — but only when the record doesn't already have an explicit
    // LITERAL at that exact position; an author who placed one there
    // clearly wants their own text, not this fallback.
    const DspfJVal& fieldsForHdg = rec["fields"];
    for (size_t i = 0; i < fieldsForHdg.size(); i++) {
        if (fieldsForHdg[i]["io"].str() == "H") continue;
        if (!dspf__condPass(fieldsForHdg[i])) continue;
        std::string hdg;
        const DspfJVal& kw = fieldsForHdg[i]["keywords"];
        for (size_t k = 0; k < kw.size(); k++) {
            const std::string& s = kw[k].str();
            if (s.rfind("COLHDG(", 0) != 0) continue;
            size_t q1 = s.find('\'');
            size_t q2 = (q1 == std::string::npos) ? std::string::npos : s.find('\'', q1 + 1);
            if (q1 != std::string::npos && q2 != std::string::npos) hdg = s.substr(q1 + 1, q2 - q1 - 1);
            break;
        }
        if (hdg.empty()) continue;
        int fRow = fieldsForHdg[i]["row"].num();
        int fCol = fieldsForHdg[i]["col"].num();
        int hdgRow = fRow - 1;
        if (hdgRow < 1) continue; // no room above row 1
        bool occupied = false;
        for (size_t li = 0; li < lits.size(); li++) {
            if (lits[li]["row"].num() == hdgRow && lits[li]["col"].num() == fCol) { occupied = true; break; }
        }
        if (occupied) continue;
        mvwprintw(win, hdgRow - 1 - rowOff, fCol - 1 - colOff, "%s", hdg.c_str());
    }

    // Fields
    const DspfJVal& fields = rec["fields"];
    for (size_t i = 0; i < fields.size(); i++) {
        std::string io = fields[i]["io"].str();
        if (io == "H") continue;
        if (!dspf__condPass(fields[i])) continue;

        int row = fields[i]["row"].num() - 1 - rowOff;
        int col = fields[i]["col"].num() - 1 - colOff;
        int len = fields[i]["len"].num(); if (len == 0) len = 1;

        std::string name = fields[i]["name"].str();
        std::string val;
        auto it = vals.find(name);
        if (it != vals.end()) val = it->second;
        val = dspf__formatField(fields[i], val);
        if ((int)val.size() > len) val.resize(len);

        int pair   = dspf__colorPair(fields[i]);
        attr_t ext = dspf__fieldAttrs(fields[i]);

        if (io == "O") {
            std::string ftype = fields[i]["type"].str();
            wattron(win, COLOR_PAIR(pair) | ext);
            if (ftype != "A") {
                mvwprintw(win, row, col, "%*s", len, val.c_str());   // right-align numeric
            } else {
                mvwprintw(win, row, col, "%-*s", len, val.c_str());  // left-align char
            }
            wattroff(win, COLOR_PAIR(pair) | ext);
        } else {
            wattron(win, COLOR_PAIR(pair) | ext | A_REVERSE);
            mvwprintw(win, row, col, "%-*s", len, val.c_str());
            wattroff(win, COLOR_PAIR(pair) | ext | A_REVERSE);
        }
    }

    // F-key legend on line 25 (0-indexed 24) — only on stdscr
    if (win == stdscr && LINES > 24) {
        const DspfJVal& keys = rec["keys"];
        std::string legend = " Enter=Submit";
        for (size_t i = 0; i < keys.size(); i++) {
            const std::string& k = keys[i]["key"].str();
            legend += "  " + k;
            static const std::map<std::string,std::string> desc = {
                {"F3","=Exit"},{"F4","=Prompt"},{"F5","=Refresh"},{"F6","=Add"},
                {"F7","=Prev"},{"F8","=Next"},{"F12","=Cancel"},
            };
            auto it = desc.find(k);
            if (it != desc.end()) legend += it->second;
        }
        attron(A_REVERSE);
        mvprintw(24, 0, "%-*s", COLS, legend.c_str());
        attroff(A_REVERSE);
    }

    wrefresh(win);
}

// =============================================================================
// Input loop — tab between fields, F-keys and Enter exit
// =============================================================================

struct DspfEditField {
    int  recIdx;
    int  row, col, len;
    std::string name;
    std::string val;
};

static int dspf__inputLoop(const DspfJVal& rec,
                            std::map<std::string,std::string>& vals,
                            WINDOW* win, int rowOff, int colOff) {
    bool noinput = dspf__hasRecKw(rec, "NOINPUT") || dspf__isProtected(rec);

    std::vector<DspfEditField> ef;
    if (!noinput) {
        std::map<std::string,bool> efSeen;
        const DspfJVal& fields = rec["fields"];
        for (size_t i = 0; i < fields.size(); i++) {
            std::string io = fields[i]["io"].str();
            if (io != "I" && io != "B") continue;
            if (!dspf__condPass(fields[i])) continue;
            std::string fname = fields[i]["name"].str();
            if (efSeen.count(fname)) continue;
            efSeen[fname] = true;
            DspfEditField f;
            f.recIdx = (int)i;
            f.row    = fields[i]["row"].num() - 1 - rowOff;
            f.col    = fields[i]["col"].num() - 1 - colOff;
            f.len    = fields[i]["len"].num(); if (f.len == 0) f.len = 1;
            f.name   = fname;
            auto it  = vals.find(f.name);
            f.val    = (it != vals.end()) ? it->second : "";
            if ((int)f.val.size() > f.len) f.val.resize(f.len);
            ef.push_back(f);
        }
    }

    const DspfJVal& fields = rec["fields"];
    int cur = 0;

    while (true) {
        if (!ef.empty()) {
            int cx = ef[cur].col + (int)ef[cur].val.size();
            if (cx >= ef[cur].col + ef[cur].len) cx = ef[cur].col + ef[cur].len - 1;
            wmove(win, ef[cur].row, cx);
            wrefresh(win);
        }

        int ch = wgetch(win);

        if (ch >= KEY_F(1) && ch <= KEY_F(24)) {
            int fnum = ch - KEY_F(0);
            std::string key = "F" + std::to_string(fnum);
            for (auto& f : ef) vals[f.name] = f.val;
            const DspfJVal& keys = rec["keys"];
            for (size_t i = 0; i < keys.size(); i++) {
                if (keys[i]["key"].str() == key)
                    return keys[i]["indicator"].num();
            }
            return fnum;
        }

        // PAGEUP/PAGEDOWN as exit keys on a plain (non-subfile) record — the
        // subfile control-record loop already uses these same ncurses codes
        // for scrolling (dspf__sflExfmt); here there's nothing to scroll, so
        // they only do anything if the record actually declares
        // KEY PAGEUP/PAGEDOWN INDICATOR(nn) (DDS ROLLDOWN/ROLLUP respectively
        // in fixed-format). Otherwise a no-op, unlike unmapped F-keys.
        if (ch == KEY_PPAGE || ch == KEY_NPAGE) {
            std::string key = (ch == KEY_PPAGE) ? "PAGEUP" : "PAGEDOWN";
            const DspfJVal& keys = rec["keys"];
            for (size_t i = 0; i < keys.size(); i++) {
                if (keys[i]["key"].str() == key) {
                    for (auto& f : ef) vals[f.name] = f.val;
                    return keys[i]["indicator"].num();
                }
            }
            continue;
        }

        if (ch == '\n' || ch == '\r' || ch == KEY_ENTER) {
            int badIdx = -1;
            std::string errMsg;
            for (size_t i = 0; i < ef.size(); i++) {
                std::string msg = dspf__validateField(fields[ef[i].recIdx], ef[i].val);
                if (!msg.empty()) { badIdx = (int)i; errMsg = msg; break; }
            }
            if (badIdx >= 0) {
                beep();
                if (dspf__hasRecKw(rec, "ERRSFL")) {
                    dspf__errsflShow(rec, errMsg);
                } else if (LINES > 24) {
                    attron(A_REVERSE);
                    mvprintw(24, 0, "%-*s", COLS, errMsg.c_str());
                    attroff(A_REVERSE);
                    refresh();
                }
                cur = badIdx;
                continue;
            }
            for (auto& f : ef) vals[f.name] = f.val;
            return 0;
        }

        if (ef.empty()) continue;

        DspfEditField& f = ef[cur];

        if (ch == '\t' || ch == KEY_DOWN) {
            cur = (cur + 1) % (int)ef.size(); continue;
        }
        if (ch == KEY_BTAB || ch == KEY_UP) {
            cur = (cur - 1 + (int)ef.size()) % (int)ef.size(); continue;
        }
        if (ch == KEY_HOME) { cur = 0; continue; }
        if (ch == KEY_END)  { cur = (int)ef.size() - 1; continue; }

        if (ch == KEY_BACKSPACE || ch == 127 || ch == 8) {
            if (!f.val.empty()) {
                f.val.pop_back();
                int pair = dspf__colorPair(fields[f.recIdx]);
                attr_t ext = dspf__fieldAttrs(fields[f.recIdx]);
                wattron(win, COLOR_PAIR(pair) | ext | A_REVERSE);
                mvwprintw(win, f.row, f.col, "%-*s", f.len, f.val.c_str());
                wattroff(win, COLOR_PAIR(pair) | ext | A_REVERSE);
            }
            continue;
        }

        if (isprint(ch) && (int)f.val.size() < f.len) {
            f.val += (char)ch;
            int pair = dspf__colorPair(fields[f.recIdx]);
            attr_t ext = dspf__fieldAttrs(fields[f.recIdx]);
            wattron(win, COLOR_PAIR(pair) | ext | A_REVERSE);
            mvwprintw(win, f.row, f.col, "%-*s", f.len, f.val.c_str());
            wattroff(win, COLOR_PAIR(pair) | ext | A_REVERSE);
            if ((int)f.val.size() >= f.len && dspf__hasRecKw(fields[f.recIdx], "AUTO")) {
                cur = (cur + 1) % (int)ef.size();
                wrefresh(win);
            }
        }
    }
}

// =============================================================================
// Global descriptor (forward-declared here; defined in Public API section)
// =============================================================================

static DspfJVal g_dspfDescriptor;
static bool     g_dspfActive = false;

// =============================================================================
// Subfile store
// =============================================================================

struct DspfSflRow { std::map<std::string,std::string> fields; };
static std::map<std::string, std::vector<DspfSflRow>> g_dspf_subfiles;
static std::map<std::string, int> g_dspf_sfl_cursor; // sflctl name → 1-based RRN
static std::map<std::string, int> g_dspf_sfl_page;   // sflctl name → 0-based page offset

// =============================================================================
// Subfile EXFMT — render scrollable table and handle navigation
// =============================================================================

static int dspf__sflExfmt(const char* ctlName, const DspfJVal& ctl, void* ctlBuf) {
    std::string sflName = ctl["sfl"].str();
    int sflpag = ctl["sflpag"].num(); if (sflpag <= 0) sflpag = 10;

    // Locate the SFL record definition in the global descriptor
    const DspfJVal* sflRec = nullptr;
    {
        const DspfJVal& allRecs = g_dspfDescriptor["records"];
        for (size_t i = 0; i < allRecs.size(); i++) {
#ifdef _WIN32
            if (_stricmp(allRecs[i]["name"].str().c_str(), sflName.c_str()) == 0) {
#else
            if (strcasecmp(allRecs[i]["name"].str().c_str(), sflName.c_str()) == 0) {
#endif
                sflRec = &allRecs[i]; break;
            }
        }
    }

    auto& rows    = g_dspf_subfiles[sflName];
    int   numRows = (int)rows.size();

    std::string ctlKey(ctlName);
    int& pageOff = g_dspf_sfl_page[ctlKey];
    int& cursor  = g_dspf_sfl_cursor[ctlKey];
    if (cursor < 1) cursor = 1;
    if (numRows > 0 && cursor > numRows) cursor = numRows;

    // Keep cursor on screen
    if (cursor - 1 < pageOff)            pageOff = cursor - 1;
    if (cursor - 1 >= pageOff + sflpag)  pageOff = cursor - sflpag;
    if (pageOff < 0) pageOff = 0;

    // Find base row of SFL fields (0-indexed screen row for first data row)
    int sflBaseRow = 5;
    if (sflRec) {
        const DspfJVal& sf = (*sflRec)["fields"];
        int minR = INT_MAX;
        for (size_t i = 0; i < sf.size(); i++) {
            int r = sf[i]["row"].num();
            if (r > 0 && r < minR) minR = r;
        }
        if (minR < INT_MAX) sflBaseRow = minR - 1;
    }

    auto ctlVals = dspf__extractFields(ctl, ctlBuf);

    // Render everything (control record + subfile rows)
    auto render = [&]() {
        dspf__renderScreen(ctl, ctlVals, stdscr, 0, 0);

        if (!sflRec) { refresh(); return; }
        const DspfJVal& sf = (*sflRec)["fields"];
        int endPage = std::min(numRows, pageOff + sflpag);

        for (int i = pageOff; i < endPage; i++) {
            int screenRow = sflBaseRow + (i - pageOff);
            bool isCursor = (i == cursor - 1);

            for (size_t fi = 0; fi < sf.size(); fi++) {
                if (sf[fi]["io"].str() == "H") continue;
                int col = sf[fi]["col"].num() - 1;
                int len = sf[fi]["len"].num(); if (len == 0) len = 1;
                std::string fname = sf[fi]["name"].str();

                std::string val;
                auto it = rows[i].fields.find(fname);
                if (it != rows[i].fields.end()) val = it->second;
                val = dspf__formatField(sf[fi], val);
                if ((int)val.size() > len) val.resize(len);

                int pair   = dspf__colorPair(sf[fi]);
                attr_t ext = dspf__fieldAttrs(sf[fi]);

                if (isCursor) {
                    attron(COLOR_PAIR(pair) | ext | A_REVERSE);
                    mvprintw(screenRow, col, "%-*s", len, val.c_str());
                    attroff(COLOR_PAIR(pair) | ext | A_REVERSE);
                } else {
                    attron(COLOR_PAIR(pair) | ext);
                    mvprintw(screenRow, col, "%-*s", len, val.c_str());
                    attroff(COLOR_PAIR(pair) | ext);
                }
            }
        }
        refresh();
    };

    render();

    while (true) {
        // Position cursor at start of current row
        if (numRows > 0 && sflRec) {
            const DspfJVal& sf = (*sflRec)["fields"];
            if (sf.size() > 0) {
                int screenRow = sflBaseRow + (cursor - 1 - pageOff);
                move(screenRow, sf[0]["col"].num() - 1);
            }
        }
        refresh();

        int ch = getch();

        if (ch >= KEY_F(1) && ch <= KEY_F(24)) {
            int fnum = ch - KEY_F(0);
            std::string key = "F" + std::to_string(fnum);
            ctlVals["SFLRCDNBR"] = std::to_string(cursor);
            dspf__applyFields(ctl, ctlVals, ctlBuf);
            const DspfJVal& keys = ctl["keys"];
            for (size_t i = 0; i < keys.size(); i++) {
                if (keys[i]["key"].str() == key) return keys[i]["indicator"].num();
            }
            return fnum;
        }

        if (ch == '\n' || ch == '\r' || ch == KEY_ENTER) {
            ctlVals["SFLRCDNBR"] = std::to_string(cursor);
            dspf__applyFields(ctl, ctlVals, ctlBuf);
            return 0;
        }

        if (numRows == 0) continue;

        if (ch == KEY_UP) {
            if (cursor > 1) {
                cursor--;
                if (cursor - 1 < pageOff) pageOff = std::max(0, pageOff - 1);
                render();
            }
        } else if (ch == KEY_DOWN) {
            if (cursor < numRows) {
                cursor++;
                if (cursor - 1 >= pageOff + sflpag) pageOff++;
                render();
            }
        } else if (ch == KEY_PPAGE) {
            pageOff = std::max(0, pageOff - sflpag);
            cursor  = pageOff + 1;
            render();
        } else if (ch == KEY_NPAGE) {
            if (pageOff + sflpag < numRows) {
                pageOff += sflpag;
                cursor   = pageOff + 1;
                render();
            }
        }
    }
}

// =============================================================================
// Record lookup
// =============================================================================

static const DspfJVal* dspf__findRec(const char* recname) {
    const DspfJVal& recs = g_dspfDescriptor["records"];
    for (size_t i = 0; i < recs.size(); i++) {
        std::string n = recs[i]["name"].str();
#ifdef _WIN32
        if (_stricmp(n.c_str(), recname) == 0) return &recs[i];
#else
        if (strcasecmp(n.c_str(), recname) == 0) return &recs[i];
#endif
    }
    return nullptr;
}

// =============================================================================
// Public API
// =============================================================================

inline void dspf_init(const char* descriptor_path) {
    FILE* f = fopen(descriptor_path, "rb");
    if (!f) {
        fprintf(stderr, "dspf_init: cannot open %s\n", descriptor_path);
        exit(1);
    }
    fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
    std::string json(sz, '\0');
    fread(&json[0], 1, sz, f); fclose(f);
    g_dspfDescriptor = dspf__parseJSON(json);

    initscr();
    cbreak();
    noecho();
    keypad(stdscr, TRUE);
    if (has_colors()) {
        start_color();
        use_default_colors();
        init_pair(DSPF_PAIR_NORMAL,  COLOR_GREEN,   -1);
        init_pair(DSPF_PAIR_RED,     COLOR_RED,     -1);
        init_pair(DSPF_PAIR_BLUE,    COLOR_BLUE,    -1);
        init_pair(DSPF_PAIR_GREEN,   COLOR_GREEN,   -1);
        init_pair(DSPF_PAIR_YELLOW,  COLOR_YELLOW,  -1);
        init_pair(DSPF_PAIR_MAGENTA, COLOR_MAGENTA, -1);
        init_pair(DSPF_PAIR_CYAN,    COLOR_CYAN,    -1);
        init_pair(DSPF_PAIR_BG_RED,     COLOR_BLACK, COLOR_RED);
        init_pair(DSPF_PAIR_BG_BLUE,    COLOR_WHITE, COLOR_BLUE);
        init_pair(DSPF_PAIR_BG_GREEN,   COLOR_BLACK, COLOR_GREEN);
        init_pair(DSPF_PAIR_BG_YELLOW,  COLOR_BLACK, COLOR_YELLOW);
        init_pair(DSPF_PAIR_BG_MAGENTA, COLOR_BLACK, COLOR_MAGENTA);
        init_pair(DSPF_PAIR_BG_CYAN,    COLOR_BLACK, COLOR_CYAN);
        init_pair(DSPF_PAIR_BG_WHITE,   COLOR_BLACK, COLOR_WHITE);
    }
    g_dspfActive = true;
}

inline int dspf_exfmt(const char* recname, void* recbuf) {
    const DspfJVal* rec = dspf__findRec(recname);
    if (!rec) return 0;
    if (dspf__hasRecKw(*rec, "ALARM")) beep();
    std::string recType = (*rec)["type"].str();
    if (recType == "sflctl") return dspf__sflExfmt(recname, *rec, recbuf);

    int winRow = 0, winCol = 0, winH = 0, winW = 0;
    bool isWin = dspf__isWindow(*rec, winRow, winCol, winH, winW);
    WINDOW* win  = stdscr;
    int rowOff = 0, colOff = 0;
    if (isWin) {
        win = newwin(winH, winW, winRow - 1, winCol - 1);
        keypad(win, TRUE);
        rowOff = winRow - 1;
        colOff = winCol - 1;
    }

    auto vals = dspf__extractFields(*rec, recbuf);
    dspf__renderScreen(*rec, vals, win, rowOff, colOff);
    int indicator = dspf__inputLoop(*rec, vals, win, rowOff, colOff);
    dspf__applyFields(*rec, vals, recbuf);

    if (isWin) {
        delwin(win);
        touchwin(stdscr);
        refresh();
    }

    return indicator;
}

inline void dspf_write(const char* recname, const void* recbuf) {
    const DspfJVal* rec = dspf__findRec(recname);
    if (!rec) return;
    std::string recType = (*rec)["type"].str();

    if (recType == "sfl") {
        // Append a row to the subfile store
        auto vals = dspf__extractFields(*rec, recbuf);
        g_dspf_subfiles[recname].push_back({vals});
        return;
    }

    if (recType == "sflctl") {
        // Writing to the control record clears the associated subfile
        std::string sflName = (*rec)["sfl"].str();
        g_dspf_subfiles[sflName].clear();
        std::string ctlKey(recname);
        g_dspf_sfl_cursor[ctlKey] = 1;
        g_dspf_sfl_page[ctlKey]   = 0;
        return;
    }

    // Normal record: render immediately (no input wait)
    auto vals = dspf__extractFields(*rec, recbuf);
    dspf__renderScreen(*rec, vals, stdscr, 0, 0);
}

inline int dspf_read(const char* recname, void* recbuf) {
    return dspf_exfmt(recname, recbuf);
}

inline void dspf_close() {
    if (g_dspfActive) {
        endwin();
        g_dspfActive = false;
    }
}
