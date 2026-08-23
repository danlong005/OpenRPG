#ifndef RPG_RUNTIME_H
#define RPG_RUNTIME_H

#include <string>
#include <array>
#include <vector>
#include <algorithm>
#include <cmath>
#include <climits>
#include <cfloat>
#include <cstdlib>
#include <ctime>
#include <cstring>
#include <sstream>
#include <iomanip>
#include <cctype>

// %GETENV - read environment variable (returns empty string if not set)
inline std::string rpg_getenv(const std::string& name) {
    const char* val = std::getenv(name.c_str());
    return val ? std::string(val) : std::string();
}

// %TRIM - trim both sides
inline std::string rpg_trim(const std::string& s) {
    auto start = s.find_first_not_of(' ');
    if (start == std::string::npos) return "";
    auto end = s.find_last_not_of(' ');
    return s.substr(start, end - start + 1);
}

// %TRIML - trim left
inline std::string rpg_triml(const std::string& s) {
    auto start = s.find_first_not_of(' ');
    if (start == std::string::npos) return "";
    return s.substr(start);
}

// %TRIMR - trim right
inline std::string rpg_trimr(const std::string& s) {
    auto end = s.find_last_not_of(' ');
    if (end == std::string::npos) return "";
    return s.substr(0, end + 1);
}

// %SCAN - find needle in haystack, returns 1-based position (0 if not found)
inline int rpg_scan(const std::string& needle, const std::string& haystack, int start = 1) {
    auto pos = haystack.find(needle, start - 1);
    return (pos == std::string::npos) ? 0 : static_cast<int>(pos) + 1;
}

// %SCANRPL - scan and replace all occurrences
inline std::string rpg_scanrpl(const std::string& find, const std::string& replace,
                                const std::string& source) {
    std::string result = source;
    size_t pos = 0;
    while ((pos = result.find(find, pos)) != std::string::npos) {
        result.replace(pos, find.length(), replace);
        pos += replace.length();
    }
    return result;
}

// %XLATE - translate characters
inline std::string rpg_xlate(const std::string& from, const std::string& to,
                              const std::string& source) {
    std::string result = source;
    for (auto& ch : result) {
        auto pos = from.find(ch);
        if (pos != std::string::npos && pos < to.size()) {
            ch = to[pos];
        }
    }
    return result;
}

// %FOUND / %EOF stubs - will be connected to file I/O later
inline bool rpg_found() { return false; }
inline bool rpg_eof() { return false; }

// %LOOKUP - find element in array, returns 1-based index (0 if not found)
template<typename T, std::size_t N>
inline int rpg_lookup(const T& val, const std::array<T, N>& arr) {
    for (std::size_t i = 0; i < N; i++) {
        if (arr[i] == val) return static_cast<int>(i + 1);
    }
    return 0;
}

// %CHECK - find first char in base NOT in comparator (1-based, 0 if all found)
inline int rpg_check(const std::string& comp, const std::string& base, int start = 1) {
    for (int i = start - 1; i < static_cast<int>(base.size()); i++) {
        if (comp.find(base[i]) == std::string::npos) return i + 1;
    }
    return 0;
}

// %CHECKR - same as %CHECK but from right
inline int rpg_checkr(const std::string& comp, const std::string& base, int start = 0) {
    int end = (start > 0) ? start - 1 : static_cast<int>(base.size()) - 1;
    for (int i = end; i >= 0; i--) {
        if (comp.find(base[i]) == std::string::npos) return i + 1;
    }
    return 0;
}

// %REPLACE(new : source : start {: length})
inline std::string rpg_replace(const std::string& newstr, const std::string& source, int start, int length = -1) {
    std::string result = source;
    int pos = start - 1; // 1-based to 0-based
    if (length < 0) {
        // Insert mode: insert at position without removing
        result.insert(pos, newstr);
    } else {
        result.replace(pos, length, newstr);
    }
    return result;
}

// %EDITC - format number with edit code
inline std::string rpg_editc(double val, const std::string& code) {
    bool negative = val < 0;
    double absval = negative ? -val : val;

    // Split into integer and decimal parts
    long long intpart = static_cast<long long>(absval * 100 + 0.5);
    long long cents = intpart % 100;
    long long dollars = intpart / 100;

    std::string digits = std::to_string(dollars);
    char editcode = code.empty() ? '1' : code[0];

    bool use_commas = (editcode == '1' || editcode == '3');
    bool show_sign = (editcode == '3' || editcode == '4');
    bool show_all_zeros = (editcode == 'X' || editcode == 'x');

    std::string result;
    if (show_all_zeros) {
        // Edit code X: show all digits with leading zeros
        char buf[32];
        snprintf(buf, sizeof(buf), "%07.2f", absval);
        return std::string(buf);
    }

    // Insert commas
    if (use_commas && digits.size() > 3) {
        std::string with_commas;
        int count = 0;
        for (int i = static_cast<int>(digits.size()) - 1; i >= 0; i--) {
            if (count > 0 && count % 3 == 0) with_commas = "," + with_commas;
            with_commas = digits[i] + with_commas;
            count++;
        }
        digits = with_commas;
    }

    char buf[8];
    snprintf(buf, sizeof(buf), ".%02lld", cents);
    result = digits + buf;

    if (show_sign && negative) {
        result += "CR";
    }

    return result;
}

inline std::string rpg_editc(int val, const std::string& code) {
    return rpg_editc(static_cast<double>(val), code);
}

// %EDITW - format number with edit word
inline std::string rpg_editw(double val, const std::string& editword) {
    bool negative = val < 0;
    double absval = negative ? -val : val;

    // Convert to string of digits (including decimals)
    long long scaled = static_cast<long long>(absval * 100 + 0.5);
    std::string digits = std::to_string(scaled);

    // Count blanks in edit word (positions for digits)
    int blank_count = 0;
    for (char c : editword) {
        if (c == ' ') blank_count++;
    }

    // Pad digits to match blank count
    while (static_cast<int>(digits.size()) < blank_count) {
        digits = "0" + digits;
    }

    // Fill in the edit word
    std::string result;
    int dpos = 0;
    bool significant = false;
    for (char c : editword) {
        if (c == ' ') {
            char d = digits[dpos++];
            if (d != '0') significant = true;
            result += significant ? d : ' ';
        } else {
            // Commas, periods, etc. - show only if significant digit has appeared
            if (significant || c == '.' || c == '0') {
                result += c;
            } else {
                result += ' ';
            }
        }
    }
    return result;
}

inline std::string rpg_editw(int val, const std::string& editword) {
    return rpg_editw(static_cast<double>(val), editword);
}

// %STATUS / %ERROR - program status tracking
inline int& rpg_status_code() { static int s = 0; return s; }
inline bool& rpg_error_flag() { static bool e = false; return e; }
inline int rpg_status() { return rpg_status_code(); }
inline int rpg_error() { return rpg_error_flag() ? 1 : 0; }

// --- PSDS — Program Status Data Structure ---
// Cross-platform PID
#ifdef _WIN32
#include <process.h>
inline int rpg_get_pid() { return _getpid(); }
#else
#include <unistd.h>
inline int rpg_get_pid() { return (int)getpid(); }
#endif

struct RpgPsds {
    std::string proc_name;        // pos 1-10:   procedure/program name
    int         status_code = 0;  // pos 11-15:  last status code
    int         prev_status = 0;  // pos 16-20:  previous status code
    std::string routine_name;     // pos 21-28:  routine name
    int         parm_count = 0;   // pos 37-39:  parameter count
    std::string program_name;     // pos 81-90:  program name
    std::string user_profile;     // pos 91-100: user profile
    std::string job_number;       // pos 101-108: job number (PID)
    std::string run_date;         // pos 109-118: run date YYYYMMDD
    std::string run_time;         // pos 119-124: run time HHMMSS
};

inline RpgPsds& rpg_psds() { static RpgPsds p; return p; }

inline std::string rpg_basename_prog(const char* path) {
    std::string s = path ? path : "PROGRAM";
    size_t p = s.find_last_of("/\\");
    if (p != std::string::npos) s = s.substr(p + 1);
    size_t dot = s.rfind('.');
    if (dot != std::string::npos) s = s.substr(0, dot);
    for (auto& c : s) c = (char)toupper((unsigned char)c);
    if (s.size() > 10) s = s.substr(0, 10);
    return s;
}

inline void rpg_psds_init(const char* argv0) {
    auto& p = rpg_psds();
    p.proc_name = rpg_basename_prog(argv0);
    p.program_name = p.proc_name;
    p.routine_name = p.proc_name;
    const char* u = std::getenv("USER");
    if (!u) u = std::getenv("USERNAME");
    if (u) {
        p.user_profile = std::string(u);
        if (p.user_profile.size() > 10) p.user_profile.resize(10);
    } else {
        p.user_profile = "UNKNOWN   ";
    }
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%08d", rpg_get_pid());
    p.job_number = buf;
    std::time_t now = std::time(nullptr);
    std::tm* t = std::localtime(&now);
    std::snprintf(buf, sizeof(buf), "%04d%02d%02d",
        t->tm_year + 1900, t->tm_mon + 1, t->tm_mday);
    p.run_date = buf;
    std::snprintf(buf, sizeof(buf), "%02d%02d%02d",
        t->tm_hour, t->tm_min, t->tm_sec);
    p.run_time = buf;
}

inline void rpg_psds_sync() {
    rpg_psds().status_code = rpg_status_code();
    rpg_psds().prev_status = rpg_status_code();
}

inline std::string rpg_psds_field_str(int pos) {
    auto& p = rpg_psds();
    if (pos >= 1   && pos <= 10)  return p.proc_name;
    if (pos >= 21  && pos <= 28)  return p.routine_name;
    if (pos >= 81  && pos <= 90)  return p.program_name;
    if (pos >= 91  && pos <= 100) return p.user_profile;
    if (pos >= 101 && pos <= 108) return p.job_number;
    if (pos >= 109 && pos <= 118) return p.run_date;
    if (pos >= 119 && pos <= 124) return p.run_time;
    return "";
}
inline int rpg_psds_field_int(int pos) {
    if (pos >= 11 && pos <= 15) return rpg_status_code();
    if (pos >= 16 && pos <= 20) return rpg_psds().prev_status;
    if (pos >= 37 && pos <= 39) return rpg_psds().parm_count;
    return 0;
}

// --- Data Areas ---
#include <filesystem>
#include <fstream>

inline std::filesystem::path rpg_da_dir() {
    const char* env = std::getenv("RPGC_DA_DIR");
    if (env && env[0]) {
        std::filesystem::path p(env);
        std::filesystem::create_directories(p);
        return p;
    }
    const char* home = std::getenv("HOME");
    if (!home) home = std::getenv("USERPROFILE");
    std::filesystem::path p = home ? std::filesystem::path(home) / ".rpgc" / "da"
                                   : std::filesystem::path(".rpgc") / "da";
    std::filesystem::create_directories(p);
    return p;
}

inline std::string rpg_da_path(const std::string& name) {
    std::string upper = name;
    for (auto& c : upper) c = (char)toupper((unsigned char)c);
    if (!upper.empty() && upper[0] == '*') upper = upper.substr(1);
    return (rpg_da_dir() / upper).string();
}

inline std::string rpg_da_read(const std::string& name, int max_len) {
    std::string path = rpg_da_path(name);
    if (!std::filesystem::exists(path)) {
        rpg_status_code() = 401; // data area not found
        rpg_error_flag() = true;
        return std::string(max_len, ' ');
    }
    std::ifstream f(path, std::ios::binary);
    if (!f) {
        rpg_status_code() = 415; // error accessing data area
        rpg_error_flag() = true;
        return std::string(max_len, ' ');
    }
    rpg_status_code() = 0;
    rpg_error_flag() = false;
    std::string content((std::istreambuf_iterator<char>(f)),
                         std::istreambuf_iterator<char>());
    content.resize(max_len, ' ');
    return content;
}

inline void rpg_da_write(const std::string& name, const std::string& value) {
    std::ofstream f(rpg_da_path(name), std::ios::binary | std::ios::trunc);
    if (!f) {
        rpg_status_code() = 413; // error updating data area
        rpg_error_flag() = true;
        return;
    }
    f << value;
    if (!f) {
        rpg_status_code() = 413;
        rpg_error_flag() = true;
        return;
    }
    rpg_status_code() = 0;
    rpg_error_flag() = false;
}

inline void rpg_da_unlock(const std::string& /*name*/) {}

// --- %CHAR: generic to-string conversion ---
inline std::string rpg_to_char(int v) { return std::to_string(v); }
inline std::string rpg_to_char(unsigned int v) { return std::to_string(v); }
inline std::string rpg_to_char(double v) { return std::to_string(v); }
inline std::string rpg_to_char(const std::string& v) { return v; }
inline std::string rpg_to_char(bool v) { return v ? "1" : "0"; }
// PACKED/ZONED: format with exactly the declared number of decimal places
inline std::string rpg_to_char_packed(double v, int dec) {
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%.*f", dec, v);
    return buf;
}

// --- Date/Time/Timestamp types ---

// Helper: parse ISO date "YYYY-MM-DD" into struct tm
inline std::tm rpg_parse_date_tm(const std::string& s) {
    std::tm t = {};
    // Parse YYYY-MM-DD
    t.tm_year = std::stoi(s.substr(0, 4)) - 1900;
    t.tm_mon = std::stoi(s.substr(5, 2)) - 1;
    t.tm_mday = std::stoi(s.substr(8, 2));
    return t;
}

inline std::string rpg_format_date_tm(const std::tm& t) {
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%04d-%02d-%02d",
                  t.tm_year + 1900, t.tm_mon + 1, t.tm_mday);
    return buf;
}

struct RpgDate {
    std::string value; // ISO format: YYYY-MM-DD
    RpgDate() : value("0001-01-01") {}
    RpgDate(const std::string& v) : value(v) {}
};

struct RpgTime {
    std::string value; // HH:MM:SS
    RpgTime() : value("00:00:00") {}
    RpgTime(const std::string& v) : value(v) {}
};

struct RpgTimestamp {
    std::string value; // YYYY-MM-DD-HH.MM.SS.MMMMMM
    RpgTimestamp() : value("0001-01-01-00.00.00.000000") {}
    RpgTimestamp(const std::string& v) : value(v) {}
};

struct RpgDuration {
    int amount;
    char unit; // 'D'=days, 'M'=months, 'Y'=years
};

// rpg_to_char overloads for date/time types
inline std::string rpg_to_char(const RpgDate& d) { return d.value; }
inline std::string rpg_to_char(const RpgTime& t) { return t.value; }
inline std::string rpg_to_char(const RpgTimestamp& ts) { return ts.value; }


// --- Date/Time format helpers ---
// Day of year (1-366) from month/day
inline int rpg_day_of_year(int y, int m, int d) {
    static const int days_before[] = {0,31,59,90,120,151,181,212,243,273,304,334};
    int doy = days_before[m - 1] + d;
    bool leap = (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
    if (leap && m > 2) doy++;
    return doy;
}

// Convert day-of-year back to month/day
inline void rpg_from_day_of_year(int y, int doy, int& m, int& d) {
    bool leap = (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
    static const int days_in_month[] = {31,28,31,30,31,30,31,31,30,31,30,31};
    m = 1;
    for (int i = 0; i < 12; i++) {
        int dim = days_in_month[i];
        if (i == 1 && leap) dim++;
        if (doy <= dim) { d = doy; return; }
        doy -= dim;
        m++;
    }
    d = doy;
}

// --- Date/Time format parsing ---
// Parse date from various RPG formats into ISO
inline std::string rpg_parse_date_fmt(const std::string& s, const std::string& fmt) {
    if (fmt == "*ISO" || fmt == "*ISO0" || fmt.empty()) return s; // already ISO
    int y, m, d;
    if (fmt == "*USA") {
        // MM/DD/YYYY
        sscanf(s.c_str(), "%d/%d/%d", &m, &d, &y);
    } else if (fmt == "*EUR") {
        // DD.MM.YYYY
        sscanf(s.c_str(), "%d.%d.%d", &d, &m, &y);
    } else if (fmt == "*JIS") {
        // YYYY-MM-DD (same as ISO)
        return s;
    } else if (fmt == "*MDY") {
        // MM/DD/YY
        sscanf(s.c_str(), "%d/%d/%d", &m, &d, &y);
        y += (y < 40) ? 2000 : 1900;
    } else if (fmt == "*DMY") {
        // DD/MM/YY
        sscanf(s.c_str(), "%d/%d/%d", &d, &m, &y);
        y += (y < 40) ? 2000 : 1900;
    } else if (fmt == "*YMD") {
        // YY/MM/DD
        sscanf(s.c_str(), "%d/%d/%d", &y, &m, &d);
        y += (y < 40) ? 2000 : 1900;
    } else if (fmt == "*JUL") {
        // YY/DDD
        int doy;
        sscanf(s.c_str(), "%d/%d", &y, &doy);
        y += (y < 40) ? 2000 : 1900;
        rpg_from_day_of_year(y, doy, m, d);
    } else if (fmt == "*LONGJUL") {
        // YYYY/DDD
        int doy;
        sscanf(s.c_str(), "%d/%d", &y, &doy);
        rpg_from_day_of_year(y, doy, m, d);
    } else if (fmt == "*CYMD") {
        // C/YY/MM/DD  (C: 0=19xx, 1=20xx)
        int c;
        sscanf(s.c_str(), "%d/%d/%d/%d", &c, &y, &m, &d);
        y += (c == 0) ? 1900 : 2000;
    } else if (fmt == "*CMDY") {
        // C/MM/DD/YY
        int c;
        sscanf(s.c_str(), "%d/%d/%d/%d", &c, &m, &d, &y);
        y += (c == 0) ? 1900 : 2000;
    } else if (fmt == "*CDMY") {
        // C/DD/MM/YY
        int c;
        sscanf(s.c_str(), "%d/%d/%d/%d", &c, &d, &m, &y);
        y += (c == 0) ? 1900 : 2000;
    } else {
        return s; // unknown format, pass through
    }
    char buf[32];
    snprintf(buf, sizeof(buf), "%04d-%02d-%02d", y, m, d);
    return buf;
}

// Format ISO date to specified RPG format
inline std::string rpg_format_date_fmt(const std::string& iso, const std::string& fmt) {
    if (fmt == "*ISO" || fmt == "*ISO0" || fmt.empty()) return iso;
    int y = std::stoi(iso.substr(0, 4));
    int m = std::stoi(iso.substr(5, 2));
    int d = std::stoi(iso.substr(8, 2));
    char buf[32];
    if (fmt == "*USA") {
        snprintf(buf, sizeof(buf), "%02d/%02d/%04d", m, d, y);
    } else if (fmt == "*EUR") {
        snprintf(buf, sizeof(buf), "%02d.%02d.%04d", d, m, y);
    } else if (fmt == "*JIS") {
        return iso;
    } else if (fmt == "*MDY") {
        snprintf(buf, sizeof(buf), "%02d/%02d/%02d", m, d, y % 100);
    } else if (fmt == "*DMY") {
        snprintf(buf, sizeof(buf), "%02d/%02d/%02d", d, m, y % 100);
    } else if (fmt == "*YMD") {
        snprintf(buf, sizeof(buf), "%02d/%02d/%02d", y % 100, m, d);
    } else if (fmt == "*JUL") {
        int doy = rpg_day_of_year(y, m, d);
        snprintf(buf, sizeof(buf), "%02d/%03d", y % 100, doy);
    } else if (fmt == "*LONGJUL") {
        int doy = rpg_day_of_year(y, m, d);
        snprintf(buf, sizeof(buf), "%04d/%03d", y, doy);
    } else if (fmt == "*CYMD") {
        int c = (y >= 2000) ? 1 : 0;
        snprintf(buf, sizeof(buf), "%d/%02d/%02d/%02d", c, y % 100, m, d);
    } else if (fmt == "*CMDY") {
        int c = (y >= 2000) ? 1 : 0;
        snprintf(buf, sizeof(buf), "%d/%02d/%02d/%02d", c, m, d, y % 100);
    } else if (fmt == "*CDMY") {
        int c = (y >= 2000) ? 1 : 0;
        snprintf(buf, sizeof(buf), "%d/%02d/%02d/%02d", c, d, m, y % 100);
    } else {
        return iso;
    }
    return buf;
}

// Parse time from RPG format to ISO HH:MM:SS
inline std::string rpg_parse_time_fmt(const std::string& s, const std::string& fmt) {
    if (fmt == "*ISO" || fmt == "*ISO0" || fmt.empty()) return s;
    int h, m, sec;
    if (fmt == "*USA") {
        // HH:MM AM/PM
        char ampm[4] = {};
        sscanf(s.c_str(), "%d:%d %2s", &h, &m, ampm);
        sec = 0;
        if ((ampm[0] == 'P' || ampm[0] == 'p') && h != 12) h += 12;
        if ((ampm[0] == 'A' || ampm[0] == 'a') && h == 12) h = 0;
    } else if (fmt == "*HMS") {
        sscanf(s.c_str(), "%d:%d:%d", &h, &m, &sec);
    } else {
        return s;
    }
    char buf[16];
    snprintf(buf, sizeof(buf), "%02d:%02d:%02d", h, m, sec);
    return buf;
}

// Format ISO time to RPG format
inline std::string rpg_format_time_fmt(const std::string& iso, const std::string& fmt) {
    if (fmt == "*ISO" || fmt == "*ISO0" || fmt.empty()) return iso;
    int h = std::stoi(iso.substr(0, 2));
    int m = std::stoi(iso.substr(3, 2));
    int s = std::stoi(iso.substr(6, 2));
    char buf[32];
    if (fmt == "*USA") {
        const char* ampm = (h >= 12) ? "PM" : "AM";
        int h12 = h % 12;
        if (h12 == 0) h12 = 12;
        snprintf(buf, sizeof(buf), "%02d:%02d %s", h12, m, ampm);
    } else if (fmt == "*HMS") {
        snprintf(buf, sizeof(buf), "%02d:%02d:%02d", h, m, s);
    } else if (fmt == "*EUR") {
        snprintf(buf, sizeof(buf), "%02d.%02d.%02d", h, m, s);
    } else {
        return iso;
    }
    return buf;
}

// Format-aware rpg_to_char overloads
inline std::string rpg_to_char(const RpgDate& d, const std::string& fmt) {
    return rpg_format_date_fmt(d.value, fmt);
}
inline std::string rpg_to_char(const RpgTime& t, const std::string& fmt) {
    return rpg_format_time_fmt(t.value, fmt);
}

// %DATE with format
inline RpgDate rpg_make_date(const std::string& s, const std::string& fmt) {
    return RpgDate(rpg_parse_date_fmt(s, fmt));
}

// %DATE
inline RpgDate rpg_make_date(const std::string& s) { return RpgDate(s); }
inline RpgDate rpg_current_date() {
    time_t now = time(nullptr);
    std::tm* t = localtime(&now);
    return RpgDate(rpg_format_date_tm(*t));
}

// %TIME
inline RpgTime rpg_make_time(const std::string& s) { return RpgTime(s); }
inline RpgTime rpg_current_time() {
    time_t now = time(nullptr);
    std::tm* t = localtime(&now);
    char buf[16];
    std::snprintf(buf, sizeof(buf), "%02d:%02d:%02d", t->tm_hour, t->tm_min, t->tm_sec);
    return RpgTime(buf);
}

// %TIMESTAMP
inline RpgTimestamp rpg_make_timestamp(const std::string& s) { return RpgTimestamp(s); }
inline RpgTimestamp rpg_current_timestamp() {
    time_t now = time(nullptr);
    std::tm* t = localtime(&now);
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%04d-%02d-%02d-%02d.%02d.%02d.000000",
                  t->tm_year + 1900, t->tm_mon + 1, t->tm_mday,
                  t->tm_hour, t->tm_min, t->tm_sec);
    return RpgTimestamp(buf);
}

// %DIFF - date difference
inline int rpg_diff_days(const RpgDate& d1, const RpgDate& d2) {
    std::tm t1 = rpg_parse_date_tm(d1.value);
    std::tm t2 = rpg_parse_date_tm(d2.value);
    time_t time1 = mktime(&t1);
    time_t time2 = mktime(&t2);
    return static_cast<int>(difftime(time1, time2) / 86400);
}

inline int rpg_diff_months(const RpgDate& d1, const RpgDate& d2) {
    std::tm t1 = rpg_parse_date_tm(d1.value);
    std::tm t2 = rpg_parse_date_tm(d2.value);
    return (t1.tm_year - t2.tm_year) * 12 + (t1.tm_mon - t2.tm_mon);
}

inline int rpg_diff_years(const RpgDate& d1, const RpgDate& d2) {
    std::tm t1 = rpg_parse_date_tm(d1.value);
    std::tm t2 = rpg_parse_date_tm(d2.value);
    return t1.tm_year - t2.tm_year;
}

// Date + duration arithmetic
inline RpgDate operator+(const RpgDate& d, const RpgDuration& dur) {
    std::tm t = rpg_parse_date_tm(d.value);
    switch (dur.unit) {
        case 'D': t.tm_mday += dur.amount; break;
        case 'M': t.tm_mon += dur.amount; break;
        case 'Y': t.tm_year += dur.amount; break;
    }
    mktime(&t); // normalize
    return RpgDate(rpg_format_date_tm(t));
}

// --- Figurative constants ---
// Resolved at codegen time based on target type; these are fallback defaults
inline const std::string RPG_BLANKS_STR = "";
inline const std::string RPG_ZEROS_STR = "";
constexpr int RPG_HIVAL_INT = INT_MAX;
constexpr int RPG_LOVAL_INT = INT_MIN;
constexpr double RPG_HIVAL_DBL = DBL_MAX;
constexpr double RPG_LOVAL_DBL = -DBL_MAX;

// --- EVALR: right-adjust ---
inline std::string rpg_evalr(const std::string& target, const std::string& value) {
    size_t len = target.size();
    if (value.size() >= len) return value.substr(value.size() - len, len);
    return std::string(len - value.size(), ' ') + value;
}

// --- %LOWER / %UPPER ---
inline std::string rpg_lower(const std::string& s) {
    std::string r = s;
    for (auto& c : r) c = std::tolower(static_cast<unsigned char>(c));
    return r;
}

inline std::string rpg_upper(const std::string& s) {
    std::string r = s;
    for (auto& c : r) c = std::toupper(static_cast<unsigned char>(c));
    return r;
}

// --- %SUBDT: extract date/time part ---
inline int rpg_subdt_years(const RpgDate& d) {
    struct tm t = rpg_parse_date_tm(d.value);
    return t.tm_year + 1900;
}
inline int rpg_subdt_months(const RpgDate& d) {
    struct tm t = rpg_parse_date_tm(d.value);
    return t.tm_mon + 1;
}
inline int rpg_subdt_days(const RpgDate& d) {
    struct tm t = rpg_parse_date_tm(d.value);
    return t.tm_mday;
}

// --- Scope guard for ON-EXIT ---
template<typename F>
struct rpg_scope_guard {
    F fn;
    bool active;
    rpg_scope_guard(F f) : fn(std::move(f)), active(true) {}
    ~rpg_scope_guard() { if (active) fn(); }
    rpg_scope_guard(const rpg_scope_guard&) = delete;
    rpg_scope_guard& operator=(const rpg_scope_guard&) = delete;
};
template<typename F>
rpg_scope_guard<F> rpg_make_scope_guard(F f) { return rpg_scope_guard<F>(std::move(f)); }

// --- %XFOOT: sum all elements of an array ---
template<typename T, std::size_t N>
inline T rpg_xfoot(const std::array<T, N>& arr) {
    T sum = T{};
    for (std::size_t i = 0; i < N; i++) sum += arr[i];
    return sum;
}

// --- TEST opcodes: validate date/time ---
inline bool rpg_test_date(const RpgDate& d) {
    try {
        std::tm t = rpg_parse_date_tm(d.value);
        return t.tm_year >= 0 && t.tm_mon >= 0 && t.tm_mon < 12 && t.tm_mday >= 1 && t.tm_mday <= 31;
    } catch (...) {
        return false;
    }
}

inline bool rpg_test_time(const RpgTime&) {
    return true; // simplified
}

inline bool rpg_test_timestamp(const RpgTimestamp&) {
    return true; // simplified
}

// --- %DECH: round to specified decimal places ---
inline double rpg_dech(double val, int decimals) {
    double factor = std::pow(10.0, decimals);
    return std::round(val * factor) / factor;
}

// --- %DECPOS: number of decimal positions ---
inline int rpg_decpos(double val) {
    std::string s = std::to_string(val);
    auto dot = s.find('.');
    if (dot == std::string::npos) return 0;
    // Trim trailing zeros
    auto last = s.find_last_not_of('0');
    if (last <= dot) return 0;
    return static_cast<int>(last - dot);
}
inline int rpg_decpos(int) { return 0; }

// --- %SPLIT: split string into vector ---
inline std::vector<std::string> rpg_split(const std::string& s, const std::string& sep = " ") {
    std::vector<std::string> result;
    size_t start = 0;
    while (start < s.size()) {
        auto pos = s.find(sep, start);
        if (pos == std::string::npos) {
            std::string tok = rpg_trim(s.substr(start));
            if (!tok.empty()) result.push_back(tok);
            break;
        }
        std::string tok = rpg_trim(s.substr(start, pos - start));
        if (!tok.empty()) result.push_back(tok);
        start = pos + sep.size();
    }
    return result;
}

// --- %CONCAT: concatenate strings with separator ---
inline std::string rpg_concat(const std::string& sep) {
    (void)sep;
    return "";
}

template<typename... Args>
inline std::string rpg_concat(const std::string& sep, const std::string& first, const Args&... rest) {
    if constexpr (sizeof...(rest) == 0) {
        return first;
    } else {
        return first + sep + rpg_concat(sep, rest...);
    }
}

// --- %CONCATARR: join array elements with separator ---
template<typename T, std::size_t N>
inline std::string rpg_concatarr(const std::array<T, N>& arr, const std::string& sep) {
    std::string result;
    for (std::size_t i = 0; i < N; i++) {
        if (i > 0) result += sep;
        result += rpg_to_char(arr[i]);
    }
    return result;
}

inline std::string rpg_concatarr(const std::vector<std::string>& arr, const std::string& sep) {
    std::string result;
    for (std::size_t i = 0; i < arr.size(); i++) {
        if (i > 0) result += sep;
        result += arr[i];
    }
    return result;
}

// --- %RIGHT: right substring ---
inline std::string rpg_right(const std::string& s, int len) {
    if (len >= static_cast<int>(s.size())) return s;
    return s.substr(s.size() - len);
}

// --- %STR: null-terminated string from pointer ---
inline std::string rpg_str(void* ptr, int len = -1) {
    if (!ptr) return "";
    if (len >= 0) return std::string(static_cast<char*>(ptr), len);
    return std::string(static_cast<char*>(ptr));
}

// --- %SUBARR: sub-array ---
template<typename T, std::size_t N>
inline std::vector<T> rpg_subarr(const std::array<T, N>& arr, int start, int count = -1) {
    int s = start - 1; // 1-based to 0-based
    int c = (count < 0) ? static_cast<int>(N) - s : count;
    return std::vector<T>(arr.begin() + s, arr.begin() + s + c);
}

// --- %MAXARR / %MINARR: index of max/min element (1-based) ---
template<typename T, std::size_t N>
inline int rpg_maxarr(const std::array<T, N>& arr) {
    auto it = std::max_element(arr.begin(), arr.end());
    return static_cast<int>(std::distance(arr.begin(), it)) + 1;
}

template<typename T, std::size_t N>
inline int rpg_minarr(const std::array<T, N>& arr) {
    auto it = std::min_element(arr.begin(), arr.end());
    return static_cast<int>(std::distance(arr.begin(), it)) + 1;
}

// --- %LIST: create a temporary vector ---
template<typename T, typename... Args>
inline std::vector<T> rpg_list(T first, Args... rest) {
    return std::vector<T>{first, static_cast<T>(rest)...};
}

// --- %RANGE: create a pair for range checking ---
template<typename T>
struct RpgRange {
    T low, high;
};

template<typename T>
inline RpgRange<T> rpg_range(T low, T high) {
    return RpgRange<T>{low, high};
}

// --- %LOOKUPxx: array search variants (1-based, 0 if not found) ---
template<typename T, std::size_t N>
inline int rpg_lookup_lt(const T& val, const std::array<T, N>& arr) {
    for (std::size_t i = 0; i < N; i++) {
        if (arr[i] < val) return static_cast<int>(i + 1);
    }
    return 0;
}

template<typename T, std::size_t N>
inline int rpg_lookup_gt(const T& val, const std::array<T, N>& arr) {
    for (std::size_t i = 0; i < N; i++) {
        if (arr[i] > val) return static_cast<int>(i + 1);
    }
    return 0;
}

template<typename T, std::size_t N>
inline int rpg_lookup_le(const T& val, const std::array<T, N>& arr) {
    for (std::size_t i = 0; i < N; i++) {
        if (arr[i] <= val) return static_cast<int>(i + 1);
    }
    return 0;
}

template<typename T, std::size_t N>
inline int rpg_lookup_ge(const T& val, const std::array<T, N>& arr) {
    for (std::size_t i = 0; i < N; i++) {
        if (arr[i] >= val) return static_cast<int>(i + 1);
    }
    return 0;
}

// --- %TLOOKUP: table lookup (returns bool, optionally sets alt table element) ---
template<typename V, typename T, std::size_t N>
inline bool rpg_tlookup(const V& val, const std::array<T, N>& table) {
    for (std::size_t i = 0; i < N; i++) {
        if (table[i] == val) return true;
    }
    return false;
}

template<typename V, typename T, std::size_t N, typename U, std::size_t M>
inline bool rpg_tlookup(const V& val, const std::array<T, N>& table, std::array<U, M>& alt) {
    for (std::size_t i = 0; i < N && i < M; i++) {
        if (table[i] == val) return true;
    }
    return false;
}

template<typename V, typename T>
inline bool rpg_tlookup(const V& val, const std::vector<T>& table) {
    for (std::size_t i = 0; i < table.size(); i++) {
        if (table[i] == val) return true;
    }
    return false;
}

template<typename V, typename T, std::size_t N>
inline bool rpg_tlookup_lt(const V& val, const std::array<T, N>& table) {
    for (std::size_t i = 0; i < N; i++) {
        if (table[i] < val) return true;
    }
    return false;
}

template<typename V, typename T, std::size_t N>
inline bool rpg_tlookup_gt(const V& val, const std::array<T, N>& table) {
    for (std::size_t i = 0; i < N; i++) {
        if (table[i] > val) return true;
    }
    return false;
}

template<typename V, typename T, std::size_t N>
inline bool rpg_tlookup_le(const V& val, const std::array<T, N>& table) {
    for (std::size_t i = 0; i < N; i++) {
        if (table[i] <= val) return true;
    }
    return false;
}

template<typename V, typename T, std::size_t N>
inline bool rpg_tlookup_ge(const V& val, const std::array<T, N>& table) {
    for (std::size_t i = 0; i < N; i++) {
        if (table[i] >= val) return true;
    }
    return false;
}

// --- %HOURS/%MINUTES/%SECONDS/%MSECONDS duration + time arithmetic ---
inline RpgTime operator+(const RpgTime& t, const RpgDuration& dur) {
    int h = std::stoi(t.value.substr(0, 2));
    int m = std::stoi(t.value.substr(3, 2));
    int s = std::stoi(t.value.substr(6, 2));
    int total_secs = h * 3600 + m * 60 + s;
    switch (dur.unit) {
        case 'H': total_secs += dur.amount * 3600; break;
        case 'I': total_secs += dur.amount * 60; break;
        case 'S': total_secs += dur.amount; break;
    }
    if (total_secs < 0) total_secs += 86400;
    total_secs %= 86400;
    char buf[16];
    std::snprintf(buf, sizeof(buf), "%02d:%02d:%02d", total_secs / 3600, (total_secs % 3600) / 60, total_secs % 60);
    return RpgTime(buf);
}

inline RpgTimestamp operator+(const RpgTimestamp& ts, const RpgDuration& dur) {
    // Simplified: delegate date part to RpgDate arithmetic
    return RpgTimestamp(ts.value); // stub for complex timestamp math
}

// %DIFF for time types
inline int rpg_diff_hours(const RpgTime& t1, const RpgTime& t2) {
    int h1 = std::stoi(t1.value.substr(0, 2));
    int h2 = std::stoi(t2.value.substr(0, 2));
    int m1 = std::stoi(t1.value.substr(3, 2));
    int m2 = std::stoi(t2.value.substr(3, 2));
    int s1 = std::stoi(t1.value.substr(6, 2));
    int s2 = std::stoi(t2.value.substr(6, 2));
    int total1 = h1 * 3600 + m1 * 60 + s1;
    int total2 = h2 * 3600 + m2 * 60 + s2;
    return (total1 - total2) / 3600;
}

inline int rpg_diff_minutes(const RpgTime& t1, const RpgTime& t2) {
    int h1 = std::stoi(t1.value.substr(0, 2));
    int h2 = std::stoi(t2.value.substr(0, 2));
    int m1 = std::stoi(t1.value.substr(3, 2));
    int m2 = std::stoi(t2.value.substr(3, 2));
    int s1 = std::stoi(t1.value.substr(6, 2));
    int s2 = std::stoi(t2.value.substr(6, 2));
    int total1 = h1 * 3600 + m1 * 60 + s1;
    int total2 = h2 * 3600 + m2 * 60 + s2;
    return (total1 - total2) / 60;
}

inline int rpg_diff_seconds(const RpgTime& t1, const RpgTime& t2) {
    int h1 = std::stoi(t1.value.substr(0, 2));
    int h2 = std::stoi(t2.value.substr(0, 2));
    int m1 = std::stoi(t1.value.substr(3, 2));
    int m2 = std::stoi(t2.value.substr(3, 2));
    int s1 = std::stoi(t1.value.substr(6, 2));
    int s2 = std::stoi(t2.value.substr(6, 2));
    int total1 = h1 * 3600 + m1 * 60 + s1;
    int total2 = h2 * 3600 + m2 * 60 + s2;
    return total1 - total2;
}

// --- %SUBDT for time ---
inline int rpg_subdt_hours(const RpgTime& t) {
    return std::stoi(t.value.substr(0, 2));
}
inline int rpg_subdt_minutes(const RpgTime& t) {
    return std::stoi(t.value.substr(3, 2));
}
inline int rpg_subdt_seconds(const RpgTime& t) {
    return std::stoi(t.value.substr(6, 2));
}

// --- %PADDR: procedure address (identity, returns void*) ---
// Handled at codegen as reinterpret_cast<void*>(&procname)

// --- %PROC: current procedure name (set by codegen context) ---
// The codegen emits a literal string, but we provide a fallback
inline std::string rpg_proc_name() { return "main"; }

// --- *ALL'x': fill with repeated characters ---
// A fixed-length character field's full declared-length value. Codegen
// wraps a CHAR factor 2 in this so MOVE/MOVEL align against the length the
// field was DECLARED with, not the possibly-shorter string a plain
// assignment happened to leave in it — real RPG draws no such distinction,
// a fixed-length field is always exactly its declared length.
inline std::string rpg_fixed_len(const std::string& s, int n) {
    std::string out = s;
    out.resize(static_cast<size_t>(n), ' ');
    return out;
}

// MOVE/MOVEL — fixed-length character move (SC09-2508). `dstLen` is the
// result field's DECLARED length, passed in by codegen: RPG fixed-length
// character fields are always exactly that long, but this compiler's
// generated std::string can be shorter after a plain assignment, so the
// destination is normalized to its declared length first.
//
// The move copies at most dstLen characters and leaves the rest of the
// destination UNCHANGED — that remainder is the whole reason MOVE is not
// plain assignment. `pad` is the (P) extender: blank the remainder instead
// of leaving it. MOVE aligns right (truncating Factor 2 on the LEFT when
// it is too long); MOVEL aligns left (truncating on the RIGHT).
inline void rpg_move_fixed(std::string& dst, const std::string& src,
                           int dstLen, bool pad, bool left) {
    if (dstLen <= 0) return;
    dst.resize(static_cast<size_t>(dstLen), ' ');
    int n = static_cast<int>(src.size());
    if (n > dstLen) n = dstLen;
    if (left) {
        for (int i = 0; i < n; i++) dst[static_cast<size_t>(i)] = src[static_cast<size_t>(i)];
        if (pad) for (int i = n; i < dstLen; i++) dst[static_cast<size_t>(i)] = ' ';
    } else {
        int srcStart = static_cast<int>(src.size()) - n;
        for (int i = 0; i < n; i++)
            dst[static_cast<size_t>(dstLen - n + i)] = src[static_cast<size_t>(srcStart + i)];
        if (pad) for (int i = 0; i < dstLen - n; i++) dst[static_cast<size_t>(i)] = ' ';
    }
}

inline void rpg_move(std::string& dst, const std::string& src, int dstLen, bool pad) {
    rpg_move_fixed(dst, src, dstLen, pad, false);
}

inline void rpg_movel(std::string& dst, const std::string& src, int dstLen, bool pad) {
    rpg_move_fixed(dst, src, dstLen, pad, true);
}

inline std::string rpg_all(const std::string& pattern, int len = 50) {
    std::string result;
    while (static_cast<int>(result.size()) < len) {
        result += pattern;
    }
    return result.substr(0, len);
}

#include <vector>

// --- IN operator helpers ---
template<typename T, typename... Args>
inline bool rpg_in_list(const T& val, const std::vector<T>& list) {
    for (const auto& item : list) {
        if (val == item) return true;
    }
    return false;
}

template<typename T>
inline bool rpg_in_range(const T& val, const RpgRange<T>& range) {
    return val >= range.low && val <= range.high;
}

// %SCANR — reverse scan (search right to left)
inline int rpg_scanr(const std::string& search, const std::string& source) {
    auto pos = source.rfind(search);
    return (pos == std::string::npos) ? 0 : static_cast<int>(pos) + 1;
}

inline int rpg_scanr(const std::string& search, const std::string& source, int start) {
    if (start < 1 || start > static_cast<int>(source.size())) return 0;
    auto pos = source.rfind(search, static_cast<size_t>(start) - 1);
    return (pos == std::string::npos) ? 0 : static_cast<int>(pos) + 1;
}

// %EDITFLT — external float representation
inline std::string rpg_editflt(double val) {
    std::ostringstream oss;
    oss << std::scientific << std::uppercase << val;
    return oss.str();
}

// %UNSH — unsigned integer with half-adjust (rounding)
inline unsigned int rpg_unsh(double val) {
    return static_cast<unsigned int>(std::round(val));
}

#endif // RPG_RUNTIME_H
