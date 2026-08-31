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
#include <set>
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
        // Duplicate display entries (same field, different conditioning/attributes)
        // share one buffer slot — only the first occurrence advances the pointer.
        // HIDDEN ("H") fields carry a real value through the buffer just like any
        // other usage — "hidden" only means not rendered (see dspf__renderScreen),
        // not "no data transfer"; the classic SFLRCDNBR HIDDEN pattern depends on
        // its value actually reaching the buffer.
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
        // HIDDEN ("H") fields carry a real value through the buffer just like any
        // other usage — see the matching note in dspf__extractFields above.
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

// Is a record-level keyword present and, if it carries an indicator
// condition, currently in effect?
//
// Bare `NAME` means always. `NAME(*INnn)` / `NAME(Nnn)` means only while that
// indicator is on (or off, with the N). Real DDS conditions a record-level
// keyword from the option-indicator columns (positions 8-16) rather than a
// parameter; dds_reader folds that condition into the keyword's own text so
// both source formats arrive here in one shape.
//
// The name must match exactly or be followed by '(' — SFLDSP is a prefix of
// SFLDSPCTL, and a plain prefix test would report one as the other.
// Is the keyword present at all, regardless of any condition on it? Uses the
// same exact-name-or-'(' rule as dspf__recKwActive; dspf__hasRecKw is a plain
// prefix test and would report SFLDSPCTL as SFLDSP.
static bool dspf__hasRecKwExact(const DspfJVal& rec, const std::string& name) {
    const DspfJVal& kw = rec["keywords"];
    for (size_t i = 0; i < kw.size(); i++) {
        const std::string& k = kw[i].str();
        if (k == name) return true;
        if (k.size() > name.size() &&
            k.compare(0, name.size(), name) == 0 && k[name.size()] == '(') return true;
    }
    return false;
}

static bool dspf__recKwActive(const DspfJVal& rec, const std::string& name) {
    const DspfJVal& kw = rec["keywords"];
    for (size_t i = 0; i < kw.size(); i++) {
        const std::string& k = kw[i].str();
        if (k == name) return true;
        if (k.size() <= name.size() + 1) continue;
        if (k.compare(0, name.size(), name) != 0 || k[name.size()] != '(') continue;

        std::string inner = k.substr(name.size() + 1,
                                     k.size() - name.size() - 2);
        bool neg = (!inner.empty() && (inner[0] == 'N' || inner[0] == 'n'));
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
        return true;   // unparseable condition: treat as unconditional
    }
    return false;
}

// Subfile display control: SFLDSP, SFLDSPCTL, SFLCLR.
//
// On IBM i these are required — a subfile is not displayed unless SFLDSP is
// in effect, and the control record's WRITE clears the subfile only when
// SFLCLR is. This compiler shipped for a long time doing all three
// unconditionally, and display files written against it say none of them.
//
// So presence decides which rule applies: declare the keyword and it is
// honoured exactly, including its indicator condition; omit it and the old
// unconditional behaviour stands. That keeps existing display files working
// while letting real DDS — where these are always conditioned, and where
// writing the control record without SFLCLR must NOT wipe the subfile —
// behave the way its author meant.
static bool dspf__sflCtlFlag(const DspfJVal& rec, const std::string& name) {
    return !dspf__hasRecKwExact(rec, name) || dspf__recKwActive(rec, name);
}

// PROTECT (record-level): write-protect every input-capable field.
static bool dspf__isProtected(const DspfJVal& rec) {
    return dspf__recKwActive(rec, "PROTECT");
}

// SFLNXTCHG (record-level, on the SFL record): in effect for *this* UPDATE
// call — the real-world case is a program turning its indicator on right
// before an UPDATE that should force-remark a row as changed.
static bool dspf__sflNxtChgActive(const DspfJVal& rec) {
    return dspf__recKwActive(rec, "SFLNXTCHG");
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
                // Trim the allowed-list token too, not just `val` — otherwise
                // an explicit VALUES('...' ' ') blank-allowed token (a
                // single quoted space, meaning "leaving this field blank is
                // OK") can never match, since a genuinely blank/untouched
                // submission always trims down to "" while the token stays
                // literally " ".
                if (dspf__compareValues(val, dspf__trimSpaces(a)) == 0) { ok = true; break; }
            }
            if (!ok) return name + ": value not valid";
        } else if (k.rfind("RANGE(", 0) == 0) {
            std::string inner = k.substr(6, k.size() > 7 ? k.size() - 7 : 0);
            std::vector<std::string> bounds = dspf__splitValueList(inner);
            if (bounds.size() == 2 &&
                (dspf__compareValues(val, dspf__trimSpaces(bounds[0])) < 0 ||
                 dspf__compareValues(val, dspf__trimSpaces(bounds[1])) > 0)) {
                return name + ": value not in range";
            }
        } else if (k.rfind("COMP(", 0) == 0) {
            std::string inner = k.substr(5, k.size() > 6 ? k.size() - 6 : 0);
            std::vector<std::string> parts = dspf__splitValueList(inner);
            if (parts.size() == 2) {
                std::string op = parts[0];
                for (auto& c : op) c = (char)toupper((unsigned char)c);
                int cmp = dspf__compareValues(val, dspf__trimSpaces(parts[1]));
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

    // Literals — dspf__colorPair/dspf__fieldAttrs just read a "keywords"
    // array, so they work on a literal's JSON shape as-is; COLOR(...)/
    // DSPATR(...) already parsed onto literals identically to fields
    // (LITERAL reuses the same generic keyword grammar as FIELD), they
    // just were never applied here.
    const DspfJVal& lits = rec["literals"];
    for (size_t i = 0; i < lits.size(); i++) {
        if (!dspf__condPass(lits[i])) continue;
        int row = lits[i]["row"].num() - 1 - rowOff;
        int col = lits[i]["col"].num() - 1 - colOff;
        int pair   = dspf__colorPair(lits[i]);
        attr_t ext = dspf__fieldAttrs(lits[i]);
        wattron(win, COLOR_PAIR(pair) | ext);
        mvwprintw(win, row, col, "%s", lits[i]["text"].str().c_str());
        wattroff(win, COLOR_PAIR(pair) | ext);
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
    bool touched = false; // operator keyed into this field (MDT-like — see CHANGE)
};

// Extracts the response-indicator number from a keyword's stored text, e.g.
// "CHANGE(*IN67 'FLDX was changed')" or "BLANKS(67)" -> 67. Returns -1 if
// `kw` isn't this keyword or has no parseable indicator.
static int dspf__parseIndFromKw(const std::string& kw, const std::string& prefix) {
    if (kw.rfind(prefix, 0) != 0) return -1;
    std::string inner = kw.substr(prefix.size());
    if (inner.rfind("*IN", 0) == 0) inner = inner.substr(3);
    try { return std::stoi(inner); } catch (...) { return -1; }
}

// CHANGE(ind ['text']) / BLANKS(ind ['text']) response indicators, computed
// once input is committed (Enter, F-key, or PAGEUP/PAGEDOWN) — never on a
// failed-validation retry, matching real MDT semantics where these persist
// across redisplays until the record actually passes back to the program.
// Applied into the caller's indicator array via dspf_apply_out_indicators().
static std::vector<int> g_dspf_out_set_indicators;
static std::vector<int> g_dspf_out_clear_indicators;

static void dspf__computeChangeBlanks(const DspfJVal& rec, const std::vector<DspfEditField>& ef) {
    g_dspf_out_set_indicators.clear();
    g_dspf_out_clear_indicators.clear();

    bool anyTouched = false;
    for (const auto& f : ef) if (f.touched) anyTouched = true;

    // Record-level CHANGE: any input-capable field in the record was keyed
    // into. Explicitly cleared when not, since MDT resets on every fresh
    // screen paint (this runtime always redraws fresh — no PUTRETAIN) —
    // otherwise a prior pass's "on" would wrongly stick around.
    const DspfJVal& recKw = rec["keywords"];
    for (size_t i = 0; i < recKw.size(); i++) {
        int ind = dspf__parseIndFromKw(recKw[i].str(), "CHANGE(");
        if (ind < 0) continue;
        if (anyTouched) g_dspf_out_set_indicators.push_back(ind);
        else g_dspf_out_clear_indicators.push_back(ind);
    }

    const DspfJVal& fields = rec["fields"];
    for (const auto& f : ef) {
        const DspfJVal& kw = fields[f.recIdx]["keywords"];
        for (size_t k = 0; k < kw.size(); k++) {
            const std::string& s = kw[k].str();
            int changeInd = dspf__parseIndFromKw(s, "CHANGE(");
            if (changeInd >= 0) {
                if (f.touched) g_dspf_out_set_indicators.push_back(changeInd);
                else g_dspf_out_clear_indicators.push_back(changeInd);
                continue;
            }
            int blanksInd = dspf__parseIndFromKw(s, "BLANKS(");
            if (blanksInd >= 0) {
                // "Blank" = nothing keyed, or only spaces — mirrors real
                // hardware's all-blank/all-null display test.
                bool isBlank = f.val.find_first_not_of(' ') == std::string::npos;
                if (isBlank) g_dspf_out_set_indicators.push_back(blanksInd);
                else g_dspf_out_clear_indicators.push_back(blanksInd);
            }
        }
    }
}

// Overlays the indicators computed by dspf__computeChangeBlanks onto the
// caller's indicator array — called once per EXFMT, right after the
// existing single-exit-indicator handling so CHANGE/BLANKS indicators
// (which can land anywhere in 1-99) aren't wiped out by it.
inline void dspf_apply_out_indicators(bool* inds, int count) {
    int n = (count < 100) ? count : 100;
    for (int ind : g_dspf_out_set_indicators)   if (ind >= 0 && ind < n) inds[ind] = true;
    for (int ind : g_dspf_out_clear_indicators) if (ind >= 0 && ind < n) inds[ind] = false;
}

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
            dspf__computeChangeBlanks(rec, ef);
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
                    dspf__computeChangeBlanks(rec, ef);
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
            dspf__computeChangeBlanks(rec, ef);
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
                f.touched = true;
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
            f.touched = true;
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

// Rows the operator typed into during a subfile pass — keyed by SFL record
// name, values are 1-based RRNs. Drained by READC in ascending order,
// matching real IBM i's "read changed records in relative-record-number
// order" behavior. Not cleared between EXFMT passes: if a program doesn't
// drain it via READC before the next EXFMT, entries just accumulate rather
// than silently vanish (this runtime has no MDT-reset-on-rewrite model).
static std::map<std::string, std::set<int>> g_dspf_sfl_changed;

// The RRN most recently returned by dspf_readc() for a given SFL record —
// mirrors real DDS's implicit "current record" pointer, which UPDATE
// targets without taking an RRN parameter itself.
static std::map<std::string, int> g_dspf_sfl_current_rrn;

// Rows UPDATE+SFLNXTCHG force-marked as changed, staged separately from
// g_dspf_sfl_changed — real DDS makes such a row visible to READC only
// starting the *next* redisplay, not immediately within the same READC
// loop that called UPDATE (that loop is what's processing the record
// SFLNXTCHG just remarked; folding it straight back into the queue it's
// currently draining would spin forever). Merged into g_dspf_sfl_changed
// at the top of the next dspf__sflExfmt call.
static std::map<std::string, std::set<int>> g_dspf_sfl_pending_nxtchg;

// A single editable cell within a SFLCTL screen — either one of the
// control record's own input-capable fields (rowIdx == -1) or one
// input-capable field within a currently-visible subfile row. Unified so
// Tab/typing/validation can walk one combined list instead of juggling
// two separate ones.
struct DspfSflEditField {
    int rowIdx;      // -1 = control-record field; else 0-based row in g_dspf_subfiles
    int fieldRecIdx; // index into ctl["fields"] (rowIdx==-1) or sflRec["fields"]
    int screenRow, col, len;
    std::string name;
    std::string val;
    bool touched = false;
};

// =============================================================================
// Subfile EXFMT — render scrollable table and handle navigation
// =============================================================================

static int dspf__sflExfmt(const char* ctlName, const DspfJVal& ctl, void* ctlBuf) {
    std::string sflName = ctl["sfl"].str();
    int sflpag = ctl["sflpag"].num(); if (sflpag <= 0) sflpag = 10;

    // Rows UPDATE+SFLNXTCHG staged since the last redisplay become visible
    // to READC starting now — this is that boundary.
    {
        auto& pending = g_dspf_sfl_pending_nxtchg[sflName];
        for (int rrn : pending) g_dspf_sfl_changed[sflName].insert(rrn);
        pending.clear();
    }

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
        if (dspf__sflCtlFlag(ctl, "SFLDSPCTL")) {
            dspf__renderScreen(ctl, ctlVals, stdscr, 0, 0);
        } else if (!dspf__hasRecKw(ctl, "OVERLAY") && !dspf__hasRecKw(ctl, "NOCLEAR")) {
            clear();
        }

        if (!sflRec || !dspf__sflCtlFlag(ctl, "SFLDSP")) { refresh(); return; }
        const DspfJVal& sf = (*sflRec)["fields"];
        int endPage = std::min(numRows, pageOff + sflpag);

        // SFLEND: mark whether more rows exist below the page. IBM's parameter
        // choices are a display style (*MORE gives More.../Bottom, *PLUS a '+',
        // *SCRBAR a scroll bar); this renders the *MORE wording for all of
        // them, since there is no scroll bar to draw here.
        if (dspf__hasRecKwExact(ctl, "SFLEND") && dspf__recKwActive(ctl, "SFLEND")) {
            mvprintw(sflBaseRow + std::min(sflpag, endPage - pageOff),
                     sf.size() ? sf[0]["col"].num() - 1 : 0,
                     "%s", endPage < numRows ? "More..." : "Bottom");
        }

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

    // ── Editable fields: the control record's own input-capable fields,
    // plus (appended after) each currently-visible row's input-capable
    // fields — e.g. a per-row OPTION column, the classic "type 1/2/4 next
    // to a row" subfile pattern. Every subfile row shares the same field
    // template, so either every row has the same editable fields or none
    // do; there's no per-row variation to worry about.
    std::vector<DspfSflEditField> combined;
    {
        const DspfJVal& cf = ctl["fields"];
        std::map<std::string,bool> seen;
        for (size_t i = 0; i < cf.size(); i++) {
            std::string io = cf[i]["io"].str();
            if (io != "I" && io != "B") continue;
            if (!dspf__condPass(cf[i])) continue;
            std::string fname = cf[i]["name"].str();
            if (seen.count(fname)) continue;
            seen[fname] = true;
            DspfSflEditField e;
            e.rowIdx = -1;
            e.fieldRecIdx = (int)i;
            e.screenRow = cf[i]["row"].num() - 1;
            e.col = cf[i]["col"].num() - 1;
            e.len = cf[i]["len"].num(); if (e.len == 0) e.len = 1;
            e.name = fname;
            auto it = ctlVals.find(e.name);
            e.val = (it != ctlVals.end()) ? it->second : "";
            if ((int)e.val.size() > e.len) e.val.resize(e.len);
            combined.push_back(e);
        }
    }
    int ctlCount = (int)combined.size();

    auto fieldDefFor = [&](const DspfSflEditField& e) -> const DspfJVal& {
        return (e.rowIdx == -1) ? ctl["fields"][e.fieldRecIdx] : (*sflRec)["fields"][e.fieldRecIdx];
    };

    // Writes every combined entry's current (possibly in-progress) value
    // back to its real store — ctlVals for control fields, the row's own
    // map for row fields — and queues touched rows for READC. Called
    // before scrolling away from the current page (so in-progress typing
    // isn't lost) and before returning to the caller.
    auto commitCombined = [&]() {
        for (auto& e : combined) {
            if (e.rowIdx == -1) {
                ctlVals[e.name] = e.val;
            } else {
                rows[e.rowIdx].fields[e.name] = e.val;
                if (e.touched) g_dspf_sfl_changed[sflName].insert(e.rowIdx + 1);
            }
        }
    };

    // Rebuilds just the row-field portion of `combined` for whatever page
    // is now visible, reloading each field's value from its row's store
    // (so a prior commitCombined()'s writes round-trip back in).
    auto rebuildRowPortion = [&]() {
        combined.resize(ctlCount);
        if (!sflRec || numRows == 0) return;
        const DspfJVal& sf = (*sflRec)["fields"];
        int endPage = std::min(numRows, pageOff + sflpag);
        for (int i = pageOff; i < endPage; i++) {
            int screenRow = sflBaseRow + (i - pageOff);
            for (size_t fi = 0; fi < sf.size(); fi++) {
                std::string io = sf[fi]["io"].str();
                if (io != "I" && io != "B") continue;
                if (!dspf__condPass(sf[fi])) continue;
                DspfSflEditField e;
                e.rowIdx = i;
                e.fieldRecIdx = (int)fi;
                e.screenRow = screenRow;
                e.col = sf[fi]["col"].num() - 1;
                e.len = sf[fi]["len"].num(); if (e.len == 0) e.len = 1;
                e.name = sf[fi]["name"].str();
                auto it = rows[i].fields.find(e.name);
                e.val = (it != rows[i].fields.end()) ? it->second : "";
                if ((int)e.val.size() > e.len) e.val.resize(e.len);
                combined.push_back(e);
            }
        }
    };
    rebuildRowPortion();

    int cur = 0;

    // Relocates `cur` to the given (0-based) row's first editable field,
    // if the row has one — since every row shares the same field
    // template, this either finds one on every call or none ever.
    auto focusRow = [&](int rowIdx0based) {
        for (int i = ctlCount; i < (int)combined.size(); i++) {
            if (combined[i].rowIdx == rowIdx0based) { cur = i; return; }
        }
        if (cur >= (int)combined.size()) cur = combined.empty() ? 0 : (int)combined.size() - 1;
    };
    focusRow(cursor - 1);

    auto redrawFocused = [&]() {
        if (combined.empty()) return;
        const DspfSflEditField& e = combined[cur];
        const DspfJVal& fdef = fieldDefFor(e);
        int pair = dspf__colorPair(fdef);
        attr_t ext = dspf__fieldAttrs(fdef);
        attron(COLOR_PAIR(pair) | ext | A_REVERSE);
        mvprintw(e.screenRow, e.col, "%-*s", e.len, e.val.c_str());
        attroff(COLOR_PAIR(pair) | ext | A_REVERSE);
    };

    while (true) {
        if (!combined.empty()) {
            const DspfSflEditField& e = combined[cur];
            int cx = e.col + (int)e.val.size();
            if (cx >= e.col + e.len) cx = e.col + e.len - 1;
            move(e.screenRow, cx);
        } else if (numRows > 0 && sflRec) {
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
            commitCombined();
            ctlVals["SFLRCDNBR"] = std::to_string(cursor);
            dspf__applyFields(ctl, ctlVals, ctlBuf);
            const DspfJVal& keys = ctl["keys"];
            for (size_t i = 0; i < keys.size(); i++) {
                if (keys[i]["key"].str() == key) return keys[i]["indicator"].num();
            }
            return fnum;
        }

        if (ch == '\n' || ch == '\r' || ch == KEY_ENTER) {
            int badIdx = -1;
            std::string errMsg;
            for (size_t i = 0; i < combined.size(); i++) {
                std::string msg = dspf__validateField(fieldDefFor(combined[i]), combined[i].val);
                if (!msg.empty()) { badIdx = (int)i; errMsg = msg; break; }
            }
            if (badIdx >= 0) {
                beep();
                if (dspf__hasRecKw(ctl, "ERRSFL")) {
                    dspf__errsflShow(ctl, errMsg);
                } else if (LINES > 24) {
                    attron(A_REVERSE);
                    mvprintw(24, 0, "%-*s", COLS, errMsg.c_str());
                    attroff(A_REVERSE);
                    refresh();
                }
                cur = badIdx;
                if (combined[cur].rowIdx != -1) { cursor = combined[cur].rowIdx + 1; render(); }
                continue;
            }
            commitCombined();
            ctlVals["SFLRCDNBR"] = std::to_string(cursor);
            dspf__applyFields(ctl, ctlVals, ctlBuf);
            return 0;
        }

        if (ch == '\t') {
            if (!combined.empty()) {
                cur = (cur + 1) % (int)combined.size();
                if (combined[cur].rowIdx != -1 && combined[cur].rowIdx != cursor - 1) {
                    cursor = combined[cur].rowIdx + 1;
                    render();
                }
            }
            continue;
        }
        if (ch == KEY_BTAB) {
            if (!combined.empty()) {
                cur = (cur - 1 + (int)combined.size()) % (int)combined.size();
                if (combined[cur].rowIdx != -1 && combined[cur].rowIdx != cursor - 1) {
                    cursor = combined[cur].rowIdx + 1;
                    render();
                }
            }
            continue;
        }
        if (ch == KEY_HOME) { if (!combined.empty()) cur = 0; continue; }
        if (ch == KEY_END)  { if (!combined.empty()) cur = (int)combined.size() - 1; continue; }

        if (!combined.empty()) {
            DspfSflEditField& e = combined[cur];
            if (ch == KEY_BACKSPACE || ch == 127 || ch == 8) {
                if (!e.val.empty()) { e.val.pop_back(); e.touched = true; redrawFocused(); }
                continue;
            }
            if (isprint(ch) && (int)e.val.size() < e.len) {
                e.val += (char)ch; e.touched = true; redrawFocused();
                continue;
            }
        }

        if (numRows == 0) continue;

        if (ch == KEY_UP) {
            if (cursor > 1) {
                cursor--;
                bool pageChanged = false;
                if (cursor - 1 < pageOff) { pageOff = std::max(0, pageOff - 1); pageChanged = true; }
                if (pageChanged) { commitCombined(); rebuildRowPortion(); }
                focusRow(cursor - 1);
                render();
            }
        } else if (ch == KEY_DOWN) {
            if (cursor < numRows) {
                cursor++;
                bool pageChanged = false;
                if (cursor - 1 >= pageOff + sflpag) { pageOff++; pageChanged = true; }
                if (pageChanged) { commitCombined(); rebuildRowPortion(); }
                focusRow(cursor - 1);
                render();
            }
        } else if (ch == KEY_PPAGE) {
            pageOff = std::max(0, pageOff - sflpag);
            cursor  = pageOff + 1;
            commitCombined(); rebuildRowPortion(); focusRow(cursor - 1);
            render();
        } else if (ch == KEY_NPAGE) {
            if (pageOff + sflpag < numRows) {
                pageOff += sflpag;
                cursor   = pageOff + 1;
                commitCombined(); rebuildRowPortion(); focusRow(cursor - 1);
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
        // Writing the control record clears the subfile only when SFLCLR is in
        // effect. A program that writes the control record to display it —
        // with SFLCLR's indicator off — must keep its rows, which is the
        // normal load-then-display idiom and used to wipe them here.
        if (dspf__sflCtlFlag(*rec, "SFLCLR")) {
            std::string sflName = (*rec)["sfl"].str();
            g_dspf_subfiles[sflName].clear();
            std::string ctlKey(recname);
            g_dspf_sfl_cursor[ctlKey] = 1;
            g_dspf_sfl_page[ctlKey]   = 0;
        }
        return;
    }

    // Normal record: render immediately (no input wait)
    auto vals = dspf__extractFields(*rec, recbuf);
    dspf__renderScreen(*rec, vals, stdscr, 0, 0);
}

inline int dspf_read(const char* recname, void* recbuf) {
    return dspf_exfmt(recname, recbuf);
}

// READC (Read Changed): pops the next touched subfile row (ascending RRN)
// into the SFL record's own buffer — mirrors real IBM i's "process rows
// the operator typed into" loop. Returns the 1-based RRN read, or 0 when
// there are none left (the caller sets its own <recname>_eof from that).
// Unlike a normal EXFMT read-back (which only copies input/both fields —
// the program already knows what it output), this copies every non-hidden
// field: the row's OUTPUT fields (e.g. a key like CUSTNO) are how the
// program identifies *which* row's OPTION was touched.
inline int dspf_readc(const char* recname, void* recbuf) {
    const DspfJVal* rec = dspf__findRec(recname);
    if (!rec) return 0;
    auto& changed = g_dspf_sfl_changed[recname];
    if (changed.empty()) return 0;
    int rrn = *changed.begin();
    changed.erase(changed.begin());
    auto& rows = g_dspf_subfiles[recname];
    if (rrn < 1 || rrn > (int)rows.size()) return 0;
    dspf__applyFields(*rec, rows[rrn - 1].fields, recbuf);
    g_dspf_sfl_current_rrn[recname] = rrn; // UPDATE's implicit target
    return rrn;
}

// UPDATE recordname — rewrites the subfile row most recently returned by
// READC for this record with the program's current buffer values. If
// SFLNXTCHG is in effect for this call (bare, or its conditioning
// indicator is on), the row is force-remarked as changed even though the
// operator didn't touch it, so the next READC pass (after the subfile is
// redisplayed) returns it again — the real-world "reject a program-
// detected error and make the operator look at it again" loop.
inline void dspf_update(const char* recname, const void* recbuf) {
    const DspfJVal* rec = dspf__findRec(recname);
    if (!rec) return;
    auto rit = g_dspf_sfl_current_rrn.find(recname);
    if (rit == g_dspf_sfl_current_rrn.end()) return; // nothing READC'd yet
    int rrn = rit->second;
    auto& rows = g_dspf_subfiles[recname];
    if (rrn < 1 || rrn > (int)rows.size()) return;
    rows[rrn - 1].fields = dspf__extractFields(*rec, recbuf);
    if (dspf__sflNxtChgActive(*rec)) g_dspf_sfl_pending_nxtchg[recname].insert(rrn);
}

inline void dspf_close() {
    if (g_dspfActive) {
        endwin();
        g_dspfActive = false;
    }
}
