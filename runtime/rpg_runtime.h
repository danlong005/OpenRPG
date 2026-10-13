#ifndef RPG_RUNTIME_H
#define RPG_RUNTIME_H

#include <string>
#include <iostream>
#include <cstdio>
#include <exception>
#include <stdexcept>
#include <string_view>
#include <functional>
#include <type_traits>
#include <array>
#include <vector>
#include <set>
#include <algorithm>
#include <cmath>
#include <climits>
#include <cfloat>
#include <cstdint>
#include <limits>
#include <cstdlib>
#include <ctime>
#include <cstring>
#include <sstream>
#include <ostream>
#include <iomanip>
#include <cctype>
#include <cstdarg>

// printf-style formatting into a string sized to fit. A fixed char buffer
// can cut the text short -- %.*f of a wide decimal field runs past 64
// characters -- and GCC warns about every such snprintf where a width or
// precision is a variable (-Wformat-truncation, on by default on Ubuntu;
// issue #19). The format attribute keeps the arguments type-checked.
#if defined(__GNUC__) || defined(__clang__)
__attribute__((format(printf, 1, 2)))
#endif
inline std::string rpg_sprintf(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    va_list ap2;
    va_copy(ap2, ap);
    int n = std::vsnprintf(nullptr, 0, fmt, ap);
    va_end(ap);
    std::string s;
    if (n > 0) {
        s.resize(static_cast<size_t>(n) + 1);
        std::vsnprintf(&s[0], s.size(), fmt, ap2);
        s.resize(static_cast<size_t>(n));
    }
    va_end(ap2);
    return s;
}

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
// %SCAN and %SCANR search a portion of the source: from `start` for
// `length` characters, or to the end without one. A match must lie wholly
// inside it; the result is numbered from the start of the whole source.
// The start must lie within the source and the portion must not run past
// its end -- otherwise status 100. All verified on PUB400 (test69).
constexpr long long RPG_SCAN_TO_END = LLONG_MIN;
constexpr long long RPG_SCAN_FROM_START = LLONG_MIN;  // no start given: 1
// Defined with RpgError below; declared here for the helpers that raise.
[[noreturn]] inline void rpg_raise(int status, const std::string& msg);
// Returns one past the portion's end, and sets `start` to its first
// position; `none` when there is nothing to search (no start given and an
// empty source -- not an error).
inline size_t rpg_scan_portion(const std::string& source, long long& start, long long length,
                               bool& none) {
    long long n = static_cast<long long>(source.size());
    none = false;
    if (start == RPG_SCAN_FROM_START) {
        start = 1;
        if (n == 0 && length == RPG_SCAN_TO_END) { none = true; return 0; }
    }
    if (length == RPG_SCAN_TO_END) length = n - start + 1;
    if (start < 1 || start > n || length < 0 || start - 1 + length > n)
        rpg_raise(100, "RNX0100: Value out of range for string operation.");
    return static_cast<size_t>(start - 1 + length);  // one past the portion's end
}

inline int rpg_scan(const std::string& search, const std::string& source,
                    long long start = RPG_SCAN_FROM_START, long long length = RPG_SCAN_TO_END) {
    bool none;
    size_t end = rpg_scan_portion(source, start, length, none);
    if (none) return 0;
    auto pos = source.find(search, static_cast<size_t>(start - 1));
    return (pos == std::string::npos || pos + search.size() > end) ? 0 : static_cast<int>(pos) + 1;
}

// %SCANRPL - scan and replace all occurrences
// %SCANRPL(scan : replacement : source {: start {: length}} {: *FIRST |
// *LAST}): every occurrence of scan in the portion of source from start, of
// length characters, replaced -- the rest of source is kept as it is. A
// portion outside the source, or an empty scan string, is status 100. *FIRST or *LAST, an OpenRPG
// extension, replaces only the first or the last occurrence in the portion.
constexpr long long RPG_SCANRPL_TO_END = LLONG_MIN;
inline std::string rpg_scanrpl(const std::string& find, const std::string& replace,
                               const std::string& source, long long start = 1,
                               long long length = RPG_SCANRPL_TO_END, int which = 0) {
    long long n = static_cast<long long>(source.size());
    if (length == RPG_SCANRPL_TO_END) length = n - start + 1;
    if (start < 1 || start > n + 1 || length < 0 || start - 1 + length > n)
        rpg_raise(100, "RNX0100: Length or start position is out of range for the string operation.");
    // An empty scan string is status 100 on IBM i (test398).
    if (find.empty())
        rpg_raise(100, "RNX0100: Length or start position is out of range for the string operation.");
    size_t from = static_cast<size_t>(start - 1), end = from + static_cast<size_t>(length);
    std::string portion = source.substr(from, end - from);
    if (which == 2) {
        size_t pos = portion.rfind(find);
        if (pos != std::string::npos) portion.replace(pos, find.size(), replace);
    } else {
        size_t pos = 0;
        while ((pos = portion.find(find, pos)) != std::string::npos) {
            portion.replace(pos, find.size(), replace);
            pos += replace.size();
            if (which == 1) break;
        }
    }
    return source.substr(0, from) + portion + source.substr(end);
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

// --- Comparison -------------------------------------------------------------
// RPG compares two character values of unequal length as if the shorter
// were padded on the right with blanks, so a CHAR(5) holding five blanks
// equals ' ', and CHAR(3) 'AB ' equals 'AB'. A plain std::string == is
// false for both. Every relational operator in generated code goes through
// rpg_eq ... rpg_ge below, which apply that rule when both operands are
// character and are the ordinary C++ operator otherwise.
//
// "Character" is std::string or std::string_view only, never anything
// merely convertible to one: a const char* or nullptr also converts to
// std::string_view, and a pointer compared against *NULL must stay a
// pointer comparison.
template<typename T>
constexpr bool rpg_is_char_v =
    std::is_same_v<std::decay_t<T>, std::string> ||
    std::is_same_v<std::decay_t<T>, std::string_view>;

inline int rpg_cmp_char(std::string_view a, std::string_view b) {
    std::size_t n = std::min(a.size(), b.size());
    int c = a.substr(0, n).compare(b.substr(0, n));
    if (c != 0) return c < 0 ? -1 : 1;
    // Equal up to the shorter length: the longer one's tail is compared
    // against the blanks the shorter one is padded with.
    bool aLonger = a.size() > n;
    std::string_view tail = aLonger ? a.substr(n) : b.substr(n);
    for (unsigned char ch : tail) {
        if (ch == ' ') continue;
        bool tailHigher = ch > static_cast<unsigned char>(' ');
        return (tailHigher == aLonger) ? 1 : -1;
    }
    return 0;
}

// *BLANKS, *ZEROS, *HIVAL and *LOVAL used as an operand. A figurative
// constant has no length of its own; it takes the length of whatever it is
// compared with, so it is expanded against the other operand at the point
// of comparison: *BLANKS beside a CHAR(5) is five blanks, beside a number
// is zero. (Assignment of one is handled in codegen, which knows the
// target's declared type — see CodeGen::figConstValue.)
struct RpgFigConst {
    char   fill;  // character value, repeated to the other operand's length
    double num;   // numeric value
};
inline const RpgFigConst RPG_BLANKS{' ', 0.0};
inline const RpgFigConst RPG_ZEROS{'0', 0.0};
inline const RpgFigConst RPG_HIVAL{'\xFF', DBL_MAX};
inline const RpgFigConst RPG_LOVAL{'\x00', -DBL_MAX};

template<typename T>
constexpr bool rpg_is_fig_v = std::is_same_v<std::decay_t<T>, RpgFigConst>;

template<typename Other>
inline auto rpg_fig_like(const RpgFigConst& f, const Other& other) {
    if constexpr (rpg_is_char_v<Other>)
        return std::string(std::string_view(other).size(), f.fill);
    else
        return f.num;
}

// An indicator is character data on IBM i, '1' or '0': 'flag=' + flag is
// flag=1, and flag = '1' compares characters. Here it is a bool, so it goes
// through these wherever it meets a character value. A character value
// assigned to an indicator turns it on when it is '1'.
inline std::string rpg_ind_chars(bool b) { return b ? "1" : "0"; }
inline bool rpg_chars_ind(std::string_view s) { return !s.empty() && s[0] == '1'; }

template<typename A, typename B, typename Op>
inline bool rpg_compare(const A& a, const B& b, Op op) {
    if constexpr (std::is_same_v<A, bool> && rpg_is_char_v<B>)
        return rpg_compare(rpg_ind_chars(a), b, op);
    else if constexpr (rpg_is_char_v<A> && std::is_same_v<B, bool>)
        return rpg_compare(a, rpg_ind_chars(b), op);
    else if constexpr (rpg_is_fig_v<A>)
        return rpg_compare(rpg_fig_like(a, b), b, op);
    else if constexpr (rpg_is_fig_v<B>)
        return rpg_compare(a, rpg_fig_like(b, a), op);
    else if constexpr (rpg_is_char_v<A> && rpg_is_char_v<B>)
        return op(rpg_cmp_char(a, b), 0);
    else
        return op(a, b);
}

template<typename A, typename B> inline bool rpg_eq(const A& a, const B& b) { return rpg_compare(a, b, std::equal_to<>()); }
template<typename A, typename B> inline bool rpg_ne(const A& a, const B& b) { return rpg_compare(a, b, std::not_equal_to<>()); }
template<typename A, typename B> inline bool rpg_lt(const A& a, const B& b) { return rpg_compare(a, b, std::less<>()); }
template<typename A, typename B> inline bool rpg_gt(const A& a, const B& b) { return rpg_compare(a, b, std::greater<>()); }
template<typename A, typename B> inline bool rpg_le(const A& a, const B& b) { return rpg_compare(a, b, std::less_equal<>()); }
template<typename A, typename B> inline bool rpg_ge(const A& a, const B& b) { return rpg_compare(a, b, std::greater_equal<>()); }

// A std::array with every element set to `v` — how a DIM'd CHAR(n)
// subfield starts out as n blanks per element rather than empty strings.
template<typename T, std::size_t N>
inline std::array<T, N> rpg_filled_array(const T& v) {
    std::array<T, N> a;
    a.fill(v);
    return a;
}

// %BITAND, %BITOR, %BITXOR and %BITNOT of character operands, byte by byte.
// The result is as long as the longest operand; a shorter one is padded
// with the byte that changes nothing: X'FF' for AND, X'00' for OR and XOR.
inline std::string rpg_bits_chars(char op, std::initializer_list<std::string> args) {
    std::size_t n = 0;
    for (const auto& a : args) n = std::max(n, a.size());
    unsigned char pad = op == '&' ? 0xFF : 0x00;
    std::string r;
    bool first = true;
    for (const auto& a : args) {
        std::string b = a;
        b.resize(n, static_cast<char>(pad));
        if (first) { r = b; first = false; continue; }
        for (std::size_t i = 0; i < n; i++) {
            unsigned char x = static_cast<unsigned char>(r[i]), y = static_cast<unsigned char>(b[i]);
            r[i] = static_cast<char>(op == '&' ? (x & y) : op == '|' ? (x | y) : (x ^ y));
        }
    }
    if (op == '~')
        for (auto& c : r) c = static_cast<char>(~static_cast<unsigned char>(c));
    return r;
}

// %TOHEX(value): each byte as two upper-case hex digits. %FROMHEX(digits):
// each two hex digits as a byte; an odd number of digits, or a character
// that is not one, is status 100.
inline std::string rpg_tohex(const std::string& s) {
    static const char* d = "0123456789ABCDEF";
    std::string r;
    r.reserve(s.size() * 2);
    for (unsigned char c : s) { r += d[c >> 4]; r += d[c & 15]; }
    return r;
}
inline std::string rpg_fromhex(const std::string& h) {
    auto val = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        return -1;
    };
    if (h.size() % 2 != 0)
        rpg_raise(100, "RNX0100: %FROMHEX needs an even number of hex digits.");
    std::string r;
    for (std::size_t i = 0; i < h.size(); i += 2) {
        int a = val(h[i]), b = val(h[i + 1]);
        if (a < 0 || b < 0)
            rpg_raise(100, "RNX0100: %FROMHEX found a character that is not a hex digit.");
        r += static_cast<char>(a * 16 + b);
    }
    return r;
}

// %REPEAT(string : count): the string count times over. A negative count
// is status 100, as a bad length is elsewhere.
inline std::string rpg_repeat(const std::string& s, long long count) {
    if (count < 0)
        rpg_raise(100, "RNX0100: Length or start position is out of range for the string operation.");
    std::string r;
    r.reserve(s.size() * static_cast<size_t>(count));
    for (long long i = 0; i < count; i++) r += s;
    return r;
}

// %COMPCORR's test of one pair of subfields: as RPG compares them, and an
// array subfield element by element.
template<typename A, typename B>
inline bool rpg_compcorr_eq(const A& a, const B& b) { return rpg_eq(a, b); }
template<typename T, typename U, std::size_t N, std::size_t M>
inline bool rpg_compcorr_eq(const std::array<T, N>& a, const std::array<U, M>& b) {
    if (N != M) return false;
    for (std::size_t i = 0; i < N; i++) if (!rpg_eq(a[i], b[i])) return false;
    return true;
}

// INZ(%LIST(...)) on an array: the list's values first, then the default.
template<typename T, std::size_t N>
inline std::array<T, N> rpg_list_array(const T& dflt, std::initializer_list<T> vals) {
    std::array<T, N> a;
    a.fill(dflt);
    std::size_t i = 0;
    for (const auto& v : vals) { if (i == N) break; a[i++] = v; }
    return a;
}

// %LOOKUP - find element in array, returns 1-based index (0 if not found)
// --- %LOOKUPxx: 1-based index of the element found, 0 if none ---
// mode 'E' finds an equal element. The others find the element nearest the
// search value, as IBM i does: 'L' the greatest element below it (LT), 'G'
// the least element above it (GT), and 'l' / 'g' an equal element if there
// is one, else as 'L' / 'G' (LE, GE). On an array in ASCEND or DESCEND order,
// which IBM requires for those four, that is the element next to where the
// value would sort. Ties go to the lowest index. start and count limit the
// search to count elements from start; count < 0 means to the end.
template<typename V, typename T>
inline int rpg_lookup_in(const V& val, const T* arr, std::size_t n, char mode,
                         int start, int count) {
    std::size_t lo = start > 1 ? static_cast<std::size_t>(start - 1) : 0;
    std::size_t hi = n;
    if (count >= 0 && lo + static_cast<std::size_t>(count) < hi) hi = lo + count;
    int best = 0;
    for (std::size_t i = lo; i < hi; i++) {
        if (mode != 'L' && mode != 'G' && rpg_eq(arr[i], val)) return static_cast<int>(i + 1);
    }
    if (mode == 'E') return 0;
    bool below = (mode == 'L' || mode == 'l');
    for (std::size_t i = lo; i < hi; i++) {
        bool side = below ? rpg_lt(arr[i], val) : rpg_gt(arr[i], val);
        if (!side) continue;
        if (best == 0) { best = static_cast<int>(i + 1); continue; }
        const T& b = arr[best - 1];
        if (below ? rpg_gt(arr[i], b) : rpg_lt(arr[i], b)) best = static_cast<int>(i + 1);
    }
    return best;
}

template<typename V, typename T, std::size_t N>
inline int rpg_lookup(const V& val, const std::array<T, N>& arr, int start = 1, int count = -1) {
    return rpg_lookup_in(val, arr.data(), N, 'E', start, count);
}

// %LOOKUPxx(arg : array : start : count : %PADDR(proc)), an OpenRPG
// extension: as rpg_lookup_in, with the order the procedure gives --
// cmp(a, b) below 0 when a comes before b, 0 when they are equal, above 0
// when a comes after -- in place of RPG's own comparison.
template<typename V, typename C, typename Cmp>
inline int rpg_lookup_cmp(const V& val, const C& c, char mode, int start, int count, Cmp cmp) {
    std::size_t n = c.size();
    std::size_t lo = start > 1 ? static_cast<std::size_t>(start - 1) : 0;
    std::size_t hi = n;
    if (count >= 0 && lo + static_cast<std::size_t>(count) < hi) hi = lo + count;
    for (std::size_t i = lo; i < hi; i++)
        if (mode != 'L' && mode != 'G' && cmp(c[i], val) == 0) return static_cast<int>(i + 1);
    if (mode == 'E') return 0;
    bool below = (mode == 'L' || mode == 'l');
    int best = 0;
    for (std::size_t i = lo; i < hi; i++) {
        int r = cmp(c[i], val);
        if (below ? r >= 0 : r <= 0) continue;
        if (best == 0) { best = static_cast<int>(i + 1); continue; }
        int rb = cmp(c[i], c[best - 1]);
        if (below ? rb > 0 : rb < 0) best = static_cast<int>(i + 1);
    }
    return best;
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
// %SUBST(string : start {: length}): `length` characters from `start`, or
// the rest of the string without one. A start outside the string, a
// negative length, or one that runs past the end is status 100, as on IBM
// i -- not a C++ exception, and not a quietly shorter result.
constexpr long long RPG_SUBST_TO_END = LLONG_MIN;
inline std::string rpg_subst(const std::string& s, long long start, long long length = RPG_SUBST_TO_END) {
    long long n = static_cast<long long>(s.size());
    if (length == RPG_SUBST_TO_END) length = n - start + 1;
    if (start < 1 || start > n || length < 0 || start - 1 + length > n)
        rpg_raise(100, "RNX0100: Length or start position is out of range for the string operation.");
    return s.substr(static_cast<size_t>(start - 1), static_cast<size_t>(length));
}

// %SUBST(field : start {: length}) = value: that part of the field takes
// the value, padded with blanks or cut to the length -- the rest of the
// field is left as it was. A start or length outside the field is status
// 100, as for %SUBST in an expression; with OPTION(*NOLENCHK) a length past
// the end stops at it.
inline void rpg_subst_set(std::string& field, long long start, long long length,
                          const std::string& value, bool nolenchk) {
    long long n = static_cast<long long>(field.size());
    if (length == RPG_SUBST_TO_END) length = n - start + 1;
    if (nolenchk && start >= 1 && start <= n && length >= 0 && start - 1 + length > n)
        length = n - start + 1;
    if (start < 1 || start > n || length < 0 || start - 1 + length > n)
        rpg_raise(100, "RNX0100: Length or start position is out of range for the string operation.");
    std::string piece = value.substr(0, static_cast<size_t>(length));
    piece.resize(static_cast<size_t>(length), ' ');
    field.replace(static_cast<size_t>(start - 1), static_cast<size_t>(length), piece);
}

// %SUBST under CTL-OPT OPTION(*NOLENCHK), an OpenRPG extension: a length
// that runs past the end of the data gives what there is, from the start
// to the end, and a length of 0 gives nothing. A start just past the end
// gives nothing too, so %SUBST(s : 1 : 3) of an empty s is ''. A start
// further out, or a negative length, is still status 100.
inline std::string rpg_subst_nolenchk(const std::string& s, long long start,
                                      long long length = RPG_SUBST_TO_END) {
    long long n = static_cast<long long>(s.size());
    if (start == n + 1 && length != RPG_SUBST_TO_END && length >= 0) return "";
    if (length != RPG_SUBST_TO_END && length >= 0 && start >= 1 && start <= n &&
        start - 1 + length > n)
        length = n - start + 1;
    return rpg_subst(s, start, length);
}

// %REPLACE(replacement : source {: start {: length}}), as IBM i does it:
// `length` characters of the source, from `start`, give way to the
// replacement. The start defaults to 1, and the length to the
// replacement's own length, cut off at the end of the source -- so
// 'Beautiful ' over 'Hello World' at 7 is 'Hello Beautiful ', not an
// insertion. A length of 0 inserts. A start outside 1 .. length + 1 of the
// source, or a length given explicitly that runs past its end, is status
// 100. All verified on PUB400 (test33).
constexpr long long RPG_REPLACE_DEFAULT = LLONG_MIN;
inline std::string rpg_replace(const std::string& repl, const std::string& source,
                               long long start = 1, long long length = RPG_REPLACE_DEFAULT) {
    long long n = static_cast<long long>(source.size());
    bool given = length != RPG_REPLACE_DEFAULT;
    if (!given) length = static_cast<long long>(repl.size());
    if (start < 1 || start > n + 1 || length < 0 || (given && start - 1 + length > n))
        rpg_raise(100, "RNX0100: Value out of range for string operation.");
    std::string result = source;
    result.replace(static_cast<size_t>(start - 1),
                   static_cast<size_t>(std::min(length, n - (start - 1))), repl);
    return result;
}

// ---------------------------------------------------------------------
// OVERLAY subfield views.
//
// A subfield declared with OVERLAY is not storage of its own: it is a
// window onto bytes belonging to the field it overlays, so writing either
// one is visible through the other. These views hold their reference only
// for the duration of one access -- a data structure exposes them through
// member functions that build a view on the spot -- so the structure
// itself stays a plain copyable aggregate.
//
// The overlaid field is character data. A numeric subfield laid over it
// reads and writes plain ASCII digits with an implied decimal point, the
// same convention this runtime's program-described flat files use, since
// a numeric field here has no byte-level representation of its own.
// ---------------------------------------------------------------------
// A numeric overlay deliberately does NOT inherit the character view's
// std::string conversion: a class offering conversions to both double and
// std::string makes every runtime helper overloaded on the two ambiguous.
class RpgOverlayBase {
public:
    RpgOverlayBase(std::string& base, int pos, int len)
        : base_(base), pos_(static_cast<size_t>(pos - 1)),
          len_(static_cast<size_t>(len)) {}

protected:
    // The overlaid field is padded, never truncated: a short assignment to
    // the base leaves the trailing window readable as blanks rather than
    // making the slice fall off the end.
    void reserveBase() {
        if (base_.size() < pos_ + len_) base_.resize(pos_ + len_, ' ');
    }
    std::string read() const {
        if (base_.size() >= pos_ + len_) return base_.substr(pos_, len_);
        std::string padded = base_;
        padded.resize(pos_ + len_, ' ');
        return padded.substr(pos_, len_);
    }
    void writeRaw(const std::string& value) {
        reserveBase();
        std::string v = value;
        if (v.size() < len_) v.resize(len_, ' ');
        else if (v.size() > len_) v.resize(len_);
        base_.replace(pos_, len_, v);
    }
    std::string& base_;
    size_t pos_;
    size_t len_;
};

class RpgCharOverlay : public RpgOverlayBase {
public:
    RpgCharOverlay(std::string& base, int pos, int len)
        : RpgOverlayBase(base, pos, len) {}

    operator std::string() const { return read(); }
    std::string str() const { return read(); }

    RpgCharOverlay& operator=(const std::string& value) { writeRaw(value); return *this; }
    RpgCharOverlay& operator=(const char* value) { writeRaw(std::string(value)); return *this; }
    RpgCharOverlay& operator=(const RpgCharOverlay& other) { writeRaw(other.read()); return *this; }
};

class RpgNumOverlay : public RpgOverlayBase {
public:
    RpgNumOverlay(std::string& base, int pos, int len, int decimals)
        : RpgOverlayBase(base, pos, len), decimals_(decimals < 0 ? 0 : decimals) {}

    operator double() const {
        std::string raw = read();
        double v = 0.0;
        try { v = std::stod(raw); } catch (...) { return 0.0; }
        for (int i = 0; i < decimals_; i++) v /= 10.0;
        return v;
    }
    double val() const { return static_cast<double>(*this); }

    RpgNumOverlay& operator=(double value) {
        bool neg = value < 0;
        double scaled = neg ? -value : value;
        for (int i = 0; i < decimals_; i++) scaled *= 10.0;
        long long digits = static_cast<long long>(scaled + 0.5);
        std::string text = std::to_string(digits);
        size_t room = neg ? (len_ > 0 ? len_ - 1 : 0) : len_;
        if (text.size() < room) text = std::string(room - text.size(), '0') + text;
        else if (text.size() > room) text = text.substr(text.size() - room);
        if (neg) text = "-" + text;
        writeRaw(text);
        return *this;
    }
    RpgNumOverlay& operator=(const RpgNumOverlay& other) { return *this = other.val(); }

private:
    int decimals_;
};

// The standard library's operator+, comparisons and operator<< for
// std::string are function templates, and template argument deduction
// never considers a user-defined conversion -- so `operator std::string()`
// above is invisible to `"x" + ds.FLD()`. These non-template overloads give
// an overlay view the ordinary string behaviour codegen assumes it has.
inline std::string operator+(const RpgCharOverlay& a, const std::string& b) { return a.str() + b; }
inline std::string operator+(const std::string& a, const RpgCharOverlay& b) { return a + b.str(); }
inline std::string operator+(const RpgCharOverlay& a, const char* b) { return a.str() + b; }
inline std::string operator+(const char* a, const RpgCharOverlay& b) { return a + b.str(); }
inline std::string operator+(const RpgCharOverlay& a, const RpgCharOverlay& b) { return a.str() + b.str(); }

inline bool operator==(const RpgCharOverlay& a, const std::string& b) { return a.str() == b; }
inline bool operator==(const std::string& a, const RpgCharOverlay& b) { return a == b.str(); }
inline bool operator==(const RpgCharOverlay& a, const char* b) { return a.str() == b; }
inline bool operator==(const char* a, const RpgCharOverlay& b) { return a == b.str(); }
inline bool operator==(const RpgCharOverlay& a, const RpgCharOverlay& b) { return a.str() == b.str(); }

inline bool operator!=(const RpgCharOverlay& a, const std::string& b) { return !(a == b); }
inline bool operator!=(const std::string& a, const RpgCharOverlay& b) { return !(a == b); }
inline bool operator!=(const RpgCharOverlay& a, const char* b) { return !(a == b); }
inline bool operator!=(const char* a, const RpgCharOverlay& b) { return !(a == b); }
inline bool operator!=(const RpgCharOverlay& a, const RpgCharOverlay& b) { return !(a == b); }

inline bool operator<(const RpgCharOverlay& a, const std::string& b) { return a.str() < b; }
inline bool operator<(const std::string& a, const RpgCharOverlay& b) { return a < b.str(); }
inline bool operator<(const RpgCharOverlay& a, const RpgCharOverlay& b) { return a.str() < b.str(); }
inline bool operator>(const RpgCharOverlay& a, const std::string& b) { return b < a.str(); }
inline bool operator>(const std::string& a, const RpgCharOverlay& b) { return b.str() < a; }
inline bool operator>(const RpgCharOverlay& a, const RpgCharOverlay& b) { return b.str() < a.str(); }
inline bool operator<=(const RpgCharOverlay& a, const std::string& b) { return !(a > b); }
inline bool operator<=(const std::string& a, const RpgCharOverlay& b) { return !(a > b); }
inline bool operator>=(const RpgCharOverlay& a, const std::string& b) { return !(a < b); }
inline bool operator>=(const std::string& a, const RpgCharOverlay& b) { return !(a < b); }

inline std::ostream& operator<<(std::ostream& os, const RpgCharOverlay& v) { return os << v.str(); }

// Half-adjust (the (H) operation extender): round at the result field's
// own decimal position, not at the units position. RPG defines it as
// adding 5 one position to the right of the last retained digit, which is
// round-half-away-from-zero at `decimals` places -- so a PACKED(11:2)
// result keeps its cents instead of losing them to a whole-number round.
inline double rpg_half_adjust(double val, int decimals) {
    if (decimals < 0) decimals = 0;
    double scale = 1.0;
    for (int i = 0; i < decimals; i++) scale *= 10.0;
    return std::round(val * scale) / scale;
}

// --- Assignment to a declared field ------------------------------------------
// RPG holds every field to its declaration on assignment; C++ does not.
// EVAL into a CHAR(n) left-adjusts the value and pads it with blanks or
// truncates it on the right to exactly n; into a VARCHAR(n) it truncates
// past n; into a PACKED/ZONED it drops decimals beyond the field's scale
// (truncating, not rounding — (H) is how a program asks for rounding).
// Codegen wraps the assigned value in these whenever it knows the
// target's declaration.
inline std::string rpg_fit_char(const std::string& v, int len) {
    if (len <= 0) return v;
    if (static_cast<int>(v.size()) >= len) return v.substr(0, static_cast<size_t>(len));
    return v + std::string(static_cast<size_t>(len) - v.size(), ' ');
}

inline std::string rpg_fit_varchar(const std::string& v, int maxLen) {
    if (maxLen <= 0 || static_cast<int>(v.size()) <= maxLen) return v;
    return v.substr(0, static_cast<size_t>(maxLen));
}

// --- Blank storage -----------------------------------------------------------
// On IBM i a data structure without INZ starts as blanks (x'40' bytes). What
// each subfield then reads as is what those bytes decode to: an INT(10) is
// 1077952576 (x'40404040'), a FLOAT(8) 32.50196..., and a PACKED or ZONED
// subfield holds no valid decimal data at all -- using it is a decimal data
// error (MCH1202, status 907). Here that blank decimal state is a NaN, and
// every place that consumes a decimal value checks for it.
inline double rpg_blank_dec() { return std::numeric_limits<double>::quiet_NaN(); }
inline float rpg_blank_float4() {
    uint32_t b = 0x40404040u; float f; std::memcpy(&f, &b, sizeof f); return f;
}
inline double rpg_blank_float8() {
    uint64_t b = 0x4040404040404040ull; double d; std::memcpy(&d, &b, sizeof d); return d;
}
inline void rpg_chk_dec(double v) {
    if (std::isnan(v)) rpg_raise(907, "RNX0907: Decimal data error: a numeric field holds blanks, not decimal data.");
}

inline double rpg_trunc_dec(double v, int decimals) {
    rpg_chk_dec(v);
    if (decimals < 0) decimals = 0;
    double scale = 1.0;
    for (int i = 0; i < decimals; i++) scale *= 10.0;
    double scaled = v * scale;
    // A decimal value is rarely exact in binary: 0.29 is stored as
    // 0.28999999999999998, and truncating that at two places would give
    // 0.28. Nudge toward the next unit first, by a few steps of the
    // value's own binary precision (never less than 1e-7 of a unit), so
    // representation error is absorbed but a digit genuinely there is not.
    // The nudge must stay far below one unit at every magnitude: one
    // scaled with the value itself turned 99999999.99 into 100000000.xx.
    double mag = std::fabs(scaled);
    double ulp = std::nextafter(mag, HUGE_VAL) - mag;
    double eps = std::max(1e-7, 4.0 * ulp);
    return std::trunc(scaled + std::copysign(eps, scaled)) / scale;
}

// %EDITC, as IBM i edits. Verified against PUB400 output, 2026-09-26.
//
// The result is always the operand's full edited width: `digits` digit
// positions (the declared length), a decimal point when `decimals` > 0,
// commas when the code has them, and the code's sign positions. Leading
// zeros of the integer part become blanks, and so does a comma with no
// significant digit to its left, so a PACKED(7:2) edits as "  1,250.75"
// and zero as "       .00". When `digits` is not known (0) the value's own
// digits are used, with no padding.
//
//   code  commas  zero shown  sign
//   1 2   yes     1 only      none
//   3 4   no      3 only      none
//   A B   yes     A only      CR
//   C D   no      C only      CR
//   J K   yes     J only      trailing -
//   L M   no      L only      trailing -
//   N O   yes     N only      floating leading -
//   P Q   no      P only      floating leading -
//   X     digits with leading zeros, no decimal point
//   Y     date: nn/nn/nn or nn/nn/nnnn, first leading zero blanked
//   Z     zero suppression only: no commas, point or sign
inline std::string rpg_editc(double val, const std::string& code, int digits, int decimals) {
    rpg_chk_dec(val);
    bool negative = val < 0;
    if (decimals < 0) decimals = 0;
    double scale = 1.0;
    for (int i = 0; i < decimals; i++) scale *= 10.0;
    long long scaled = std::llround(std::fabs(val) * scale);
    std::string s = std::to_string(scaled);
    int width = digits > 0 ? digits : std::max<int>(static_cast<int>(s.size()), decimals);
    if (static_cast<int>(s.size()) > width) s = s.substr(s.size() - width);  // high-order digits lost
    s = std::string(width - s.size(), '0') + s;
    char c = code.empty() ? '1' : static_cast<char>(std::toupper(static_cast<unsigned char>(code[0])));

    if (c == 'X') return s;
    if (c == 'Y') {
        std::string r;
        if (width == 6) r = s.substr(0, 2) + "/" + s.substr(2, 2) + "/" + s.substr(4, 2);
        else if (width == 8) r = s.substr(0, 2) + "/" + s.substr(2, 2) + "/" + s.substr(4, 4);
        else r = s;
        if (!r.empty() && r[0] == '0') r[0] = ' ';
        return r;
    }
    if (c == 'Z') {
        size_t nz = s.find_first_not_of('0');
        return nz == std::string::npos ? std::string(width, ' ') : std::string(nz, ' ') + s.substr(nz);
    }

    bool commas = std::strchr("12ABJKNO", c) != nullptr;
    bool zero_shown = std::strchr("13ACJLNP", c) != nullptr;
    int sign_len = std::strchr("ABCD", c) ? 2 : std::strchr("JKLM", c) ? 1 : 0;
    bool floating_minus = std::strchr("NOPQ", c) != nullptr;

    std::string ip = s.substr(0, width - decimals), fp = s.substr(width - decimals);
    std::string intpart;
    bool significant = false;
    for (size_t i = 0; i < ip.size(); i++) {
        int left = static_cast<int>(ip.size() - i);   // digits from here to the point
        if (ip[i] != '0') significant = true;
        // With no decimals, a zero value still shows its units digit.
        bool units = (left == 1 && decimals == 0);
        intpart += (significant || units) ? ip[i] : ' ';
        if (commas && left > 1 && (left - 1) % 3 == 0)
            intpart += significant ? ',' : ' ';
    }
    std::string r = intpart + (decimals > 0 ? "." + fp : "");
    if (floating_minus) {
        size_t first = r.find_first_not_of(' ');
        if (first == std::string::npos) first = r.size();
        r = " " + r;
        if (negative) r[first] = '-';
    }
    if (sign_len == 2) r += negative ? "CR" : "  ";
    if (sign_len == 1) r += negative ? "-" : " ";
    if (scaled == 0 && !zero_shown) return std::string(r.size(), ' ');
    return r;
}

// DSPLY of a numeric field, as IBM i shows it (verified on PUB400): the
// field's digits right-adjusted in its declared width, leading zeros
// blank, NO decimal point, and a trailing minus when negative.
// PACKED(7:2) -12.5 shows "   1250-", INT(10) -7 "         7-".
inline std::string rpg_dsply_numeric(double val, int digits, int decimals) {
    std::string r = rpg_editc(val, "Z", digits, decimals);
    if (r.find_first_not_of(' ') == std::string::npos && !r.empty()) r.back() = '0';
    if (val < 0) r += "-";
    return r;
}

// Right-adjusts `s` in a slot `width` wide; a longer value keeps its
// rightmost characters.
inline std::string rpg_right_adjust(const std::string& s, int width) {
    if (static_cast<int>(s.size()) >= width) return s.substr(s.size() - width);
    return std::string(width - s.size(), ' ') + s;
}

inline std::string rpg_editc(double val, const std::string& code, int decimals) {
    return rpg_editc(val, code, 0, decimals);
}

// %EDITW - format number with edit word. `decimals` is the operand's
// declared scale: the edit word's digit positions take the value's digits
// at that scale.
inline std::string rpg_editw(double val, const std::string& editword, int decimals = 2) {
    bool negative = val < 0;
    double absval = negative ? -val : val;
    double scale = 1.0;
    for (int i = 0; i < decimals; i++) scale *= 10.0;
    long long scaled = std::llround(absval * scale);
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

// %STATUS / %ERROR - program status tracking
inline int& rpg_status_code() { static int s = 0; return s; }
inline bool& rpg_error_flag() { static bool e = false; return e; }
inline int rpg_status() { return rpg_status_code(); }
inline int rpg_error() { return rpg_error_flag() ? 1 : 0; }

// --- Raising an RPG runtime error ---------------------------------------------
// An error RPG itself detects (a numeric target too small for its result,
// division by zero) sets %STATUS and ends the operation. MONITOR/ON-ERROR
// and *PSSR are C++ catch(...) blocks, so throwing is how control reaches
// them. Unmonitored, the error ends the program with its message, as it
// does in a batch job on IBM i, rather than as a bare C++ abort.
struct RpgError : std::runtime_error {
    int status;
    RpgError(int st, const std::string& msg) : std::runtime_error(msg), status(st) {}
};

[[noreturn]] inline void rpg_raise(int status, const std::string& msg) {
    rpg_status_code() = status;
    rpg_error_flag() = true;
    throw RpgError(status, msg);
}

// An array element as RPG indexes it: from 1, and an index outside the
// array is status 121 (RNX0121), not a read or write past its end.
template <class A, class I>
inline auto& rpg_elem(A& a, I index) {
    long long i = static_cast<long long>(index);
    if (i < 1 || i > static_cast<long long>(a.size()))
        rpg_raise(121, "RNX0121: Array index not valid.");
    return a[static_cast<size_t>(i - 1)];
}
// DIM(*AUTO:max): an index past the current end extends the array, up to
// its maximum; new elements take the array's initial value.
template <class V, class I, class T>
inline auto& rpg_elem_auto(V& v, I index, long long max, const T& fill) {
    long long i = static_cast<long long>(index);
    if (i < 1) rpg_raise(121, "RNX0121: Array index not valid.");
    // Growing past the DIM(*AUTO : max) maximum is status 124 (PUB400, test426).
    if (i > max) rpg_raise(124, "RNX0124: The index is greater than the maximum allowed for the array.");
    if (i > static_cast<long long>(v.size())) v.resize(static_cast<size_t>(i), fill);
    return v[static_cast<size_t>(i - 1)];
}
template <class V, class I>
inline auto& rpg_elem_auto(V& v, I index, long long max) {
    return rpg_elem_auto(v, index, max, typename V::value_type{});
}

// SND-MSG *ESCAPE, as IBM i sends it (verified on PUB400, test312). By
// default it goes to the procedure's caller: the sending procedure ends,
// and none of its own handlers (MONITOR, *PSSR) sees the message -- so it
// is its own type, which they pass on. At the procedure's boundary it
// becomes an error in the caller, status 202, message CPF9898; from the
// main procedure it ends the program. %TARGET(*SELF) sends it to the
// procedure itself instead: an ordinary error there, status 9999.
struct RpgCallerEscape : RpgError { using RpgError::RpgError; };
[[noreturn]] inline void rpg_escape_to_caller(const std::string& text) {
    throw RpgCallerEscape(202, "CPF9898: " + text);
}
[[noreturn]] inline void rpg_escape_to_self(const std::string& text) {
    rpg_raise(9999, "CPF9898: " + text);
}
[[noreturn]] inline void rpg_escape_arrives(const RpgCallerEscape& e) {
    rpg_raise(202, e.what());
}

// Set when a RETURN runs inside one of the program's subroutines: the
// program returns too, once the subroutine does.
inline bool rpg_sr_returned = false;

// A *PSSR run because of an error that reaches its ENDSR, with no RETURN,
// ends the program in error (IBM i: RNX9001).
[[noreturn]] inline void rpg_pssr_ended() {
    rpg_raise(9001, "RNX9001: The *PSSR ended without a RETURN; the program ends in error.");
}

// An error that leaves a procedure reaches its caller as status 202,
// "called program or procedure failed" (IBM i), whatever it was inside.
[[noreturn]] inline void rpg_procedure_failed(const RpgError& e) {
    if (e.status == 202) throw e;
    rpg_raise(202, "RNX0202: The call to a procedure ended in error: " + std::string(e.what()));
}

// The status of the error being handled, inside a catch: the RpgError's
// own, else the last status the runtime set.
inline int rpg_caught_status() {
    try { throw; }
    catch (const RpgError& e) { return e.status; }
    catch (...) { return rpg_status_code(); }
}

// --- The program's exit status ---
// A program that ends normally exits with status 0, unless one of the
// halt indicators *H1-*H9 is on: then it ends in error, as on IBM i, with
// status n for *Hn (the lowest one on), and its pending database changes
// are rolled back, not committed. An unhandled error ends it with status
// 1. rpg_set_exit_status is an OpenRPG extension, for a batch script that
// needs a particular status:
//     DCL-PR SetExitStatus EXTPROC('rpg_set_exit_status');
//       status INT(10) VALUE;
//     END-PR;
// It takes effect when the program ends normally, after the usual
// cleanup.
inline bool* rpg_halt_indicators() { static bool h[10] = {}; return h; }
inline int& rpg_exit_status_ref() { static int s = 0; return s; }
inline void rpg_set_exit_status(int status) { rpg_exit_status_ref() = status; }
inline int rpg_main_end() {
    for (int i = 1; i <= 9; i++) {
        if (rpg_halt_indicators()[i]) {
            std::cout.flush();
            std::fprintf(stderr, "The program ended with halt indicator H%d on.\n", i);
            std::_Exit(i);
        }
    }
    return rpg_exit_status_ref();
}

[[noreturn]] inline void rpg__unhandled_error() {
    if (std::exception_ptr ep = std::current_exception()) {
        try { std::rethrow_exception(ep); }
        catch (const RpgError& e) {
            std::cout.flush();
            std::fprintf(stderr, "%s\n", e.what());
            std::_Exit(1);
        }
        catch (...) {}
    }
    std::abort();
}
inline const bool rpg__unhandled_error_installed =
    (std::set_terminate(rpg__unhandled_error), true);

// Status 103 — EVAL (and a RETURN or VALUE parameter, which assign the same
// way) into a PACKED/ZONED field whose integer digits cannot hold the
// value. `digits` 0 means the declaration isn't known; only the scale is
// applied then.
inline double rpg_fit_dec(double v, int digits, int decimals) {
    double t = rpg_trunc_dec(v, decimals);
    if (digits > 0) {
        double limit = 1.0;
        for (int i = 0; i < digits - (decimals > 0 ? decimals : 0); i++) limit *= 10.0;
        if (!std::isfinite(v) || std::fabs(t) >= limit)
            rpg_raise(103, "RNX0103: The target for a numeric operation is too small to hold the result.");
    }
    return t;
}

// The fixed-format arithmetic operations (ADD, SUB, MULT, DIV, Z-ADD,
// Z-SUB) do not raise 103: SC09-2508 has them drop the result's excess
// high-order digits. Codegen marks those assignments with the internal
// (T) extender (see fixed_cspec.cpp).
inline double rpg_fit_dec_hi(double v, int digits, int decimals) {
    double t = rpg_trunc_dec(v, decimals);
    if (digits > 0 && std::isfinite(t)) {
        double limit = 1.0;
        for (int i = 0; i < digits - (decimals > 0 ? decimals : 0); i++) limit *= 10.0;
        if (std::fabs(t) >= limit) t = rpg_trunc_dec(std::fmod(t, limit), decimals);
    }
    return t;
}

// INT and UNS are 4-byte here whatever width was declared, so this checks
// that range. The fractional part is dropped, as C++ conversion also does.
inline int rpg_fit_int(double v) {
    rpg_chk_dec(v);
    double t = std::trunc(v);
    if (!std::isfinite(v) || t < static_cast<double>(INT_MIN) || t > static_cast<double>(INT_MAX))
        rpg_raise(103, "RNX0103: The target for a numeric operation is too small to hold the result.");
    return static_cast<int>(t);
}
// An integer field holds what its size does: INT(3) one byte, -128 to 127;
// INT(5) two; INT(10) four; INT(20) eight bytes. A value outside that is
// status 103, as on IBM i. Integer values are checked exactly, without
// passing through a double, which can't hold every 64-bit value.
inline void rpg__int_range(int digits, long long& lo, long long& hi) {
    if (digits > 0 && digits <= 3)       { lo = -128;      hi = 127; }
    else if (digits > 0 && digits <= 5)  { lo = -32768;    hi = 32767; }
    else if (digits == 0 || digits <= 10) { lo = INT_MIN;  hi = INT_MAX; }
    else                                 { lo = LLONG_MIN; hi = LLONG_MAX; }
}
[[noreturn]] inline void rpg__int_overflow() {
    rpg_raise(103, "RNX0103: The target for a numeric operation is too small to hold the result.");
}
template <class T>
inline long long rpg_fit_intn(T v, int digits) {
    long long lo, hi;
    rpg__int_range(digits, lo, hi);
    if constexpr (std::is_integral_v<T>) {
        if constexpr (std::is_unsigned_v<T>) {
            if (static_cast<unsigned long long>(v) > static_cast<unsigned long long>(hi)) rpg__int_overflow();
            return static_cast<long long>(v);
        } else {
            long long x = static_cast<long long>(v);
            if (x < lo || x > hi) rpg__int_overflow();
            return x;
        }
    } else {
        double d = static_cast<double>(v);
        rpg_chk_dec(d);
        double t = std::trunc(d);
        // 2^63 is the first double past LLONG_MAX
        if (!std::isfinite(d) || t < static_cast<double>(lo) || t >= 9223372036854775808.0 ||
            t > static_cast<double>(hi))
            rpg__int_overflow();
        return static_cast<long long>(t);
    }
}
template <class T>
inline unsigned long long rpg_fit_unsn(T v, int digits) {
    unsigned long long hi = digits > 0 && digits <= 3 ? 255ULL : digits > 0 && digits <= 5 ? 65535ULL
                          : digits == 0 || digits <= 10 ? 4294967295ULL : ULLONG_MAX;
    if constexpr (std::is_integral_v<T>) {
        if constexpr (std::is_signed_v<T>) { if (v < 0) rpg__int_overflow(); }
        if (static_cast<unsigned long long>(v) > hi) rpg__int_overflow();
        return static_cast<unsigned long long>(v);
    } else {
        double d = static_cast<double>(v);
        rpg_chk_dec(d);
        double t = std::trunc(d);
        if (!std::isfinite(d) || t < 0.0 || t >= 18446744073709551616.0 ||
            t > static_cast<double>(hi))
            rpg__int_overflow();
        return static_cast<unsigned long long>(t);
    }
}

inline unsigned int rpg_fit_uns(double v) {
    rpg_chk_dec(v);
    double t = std::trunc(v);
    if (!std::isfinite(v) || t < 0.0 || t > static_cast<double>(UINT_MAX))
        rpg_raise(103, "RNX0103: The target for a numeric operation is too small to hold the result.");
    return static_cast<unsigned int>(t);
}

// Status 102 — division by zero. A double quotient by zero used to come
// out as inf and carry on.
template <typename A, typename B>
inline double rpg_div(const A& a, const B& b) {
    if (static_cast<double>(b) == 0.0)
        rpg_raise(102, "RNX0102: Attempt to divide by zero.");
    return static_cast<double>(a) / static_cast<double>(b);
}
template <typename A, typename B>
inline long long rpg_int_div(const A& a, const B& b) {
    if (static_cast<double>(b) == 0.0)
        rpg_raise(102, "RNX0102: Attempt to divide by zero.");
    return static_cast<long long>(static_cast<double>(a) / static_cast<double>(b));
}
template <typename A, typename B>
inline long long rpg_int_rem(const A& a, const B& b) {
    if (static_cast<double>(b) == 0.0)
        rpg_raise(102, "RNX0102: Attempt to divide by zero.");
    return static_cast<long long>(a) % static_cast<long long>(b);
}

// --- PSDS — Program Status Data Structure ---
// Cross-platform PID
#ifdef _WIN32
#include <process.h>
inline int rpg_get_pid() { return _getpid(); }
#else
#include <unistd.h>
inline int rpg_get_pid() { return (int)getpid(); }
#endif

// The Program Status Data Structure, laid out as IBM i lays it out (ILE RPG
// Reference, "Program Status Data Structure"). A PSDS subfield names its
// field by starting position; rpg_psds_field_str/int below answer for each
// position IBM i defines that this runtime can supply.
struct RpgPsds {
    std::string proc_name;        // 1-10    procedure name
    int         status_code = 0;  // 11-15   status code (zoned 5,0)
    int         prev_status = 0;  // 16-20   previous status code
    std::string stmt_number;      // 21-28   statement number of the error
    std::string routine_name;     // 29-36   routine the error occurred in
    int         parm_count = 0;   // 37-39   number of parameters (zoned 3,0)
    std::string exc_type;         // 40-42   exception type: MCH, CPF, RNX, ...
    std::string exc_number;       // 43-46   exception number
    std::string exc_data;         // 91-170  exception data (message text)
    std::string job_name;         // 244-253 job name
    std::string user_profile;     // 254-263 user name; 358-367 current user
    int         job_number = 0;   // 264-269 job number (zoned 6,0)
    int         run_date = 0;     // 276-281 date the program ran, MMDDYY
    int         run_time = 0;     // 282-287 time the program ran, HHMMSS
    std::string program_name;     // 334-343 program; 344-353 module
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

// The current user profile, as *USER and PSDS positions 91-100 give it: the
// login name, upper-cased as IBM i profile names are, at most 10 characters.
// Read directly rather than from the PSDS, because INZ(*USER) on a global
// field is evaluated before main() fills the PSDS in.
inline std::string rpg_user_profile() {
    const char* u = std::getenv("USER");
    if (!u) u = std::getenv("USERNAME");
    std::string s = u ? u : "UNKNOWN";
    for (auto& c : s) c = (char)toupper((unsigned char)c);
    if (s.size() > 10) s.resize(10);
    return s;
}

inline void rpg_psds_init(const char* argv0) {
    auto& p = rpg_psds();
    p.proc_name = rpg_basename_prog(argv0);
    p.program_name = p.proc_name;
    p.job_name = p.proc_name;
    p.user_profile = rpg_user_profile();
    p.job_number = rpg_get_pid() % 1000000;
    std::time_t now = std::time(nullptr);
    std::tm* t = std::localtime(&now);
    p.run_date = (t->tm_mon + 1) * 10000 + t->tm_mday * 100 + t->tm_year % 100;
    p.run_time = t->tm_hour * 10000 + t->tm_min * 100 + t->tm_sec;
}

// Called where an error is handled (ON-ERROR, *PSSR): the status moves to
// the previous-status field, and the error's status, message ID and text
// are recorded. An RpgError's message starts with its ID ("RNX0100: ...").
inline void rpg_psds_sync() {
    auto& p = rpg_psds();
    p.prev_status = p.status_code;
    p.status_code = rpg_status_code();
    std::string msg;
    if (std::exception_ptr ep = std::current_exception()) {
        try { std::rethrow_exception(ep); }
        catch (const std::exception& e) { msg = e.what(); }
        catch (...) {}
    }
    if (msg.size() >= 7 && std::isalpha((unsigned char)msg[0]) &&
        std::isdigit((unsigned char)msg[3]) && std::isdigit((unsigned char)msg[6])) {
        p.exc_type = msg.substr(0, 3);
        p.exc_number = msg.substr(3, 4);
        size_t colon = msg.find(':');
        p.exc_data = colon == std::string::npos ? msg : msg.substr(colon + 1);
        size_t first = p.exc_data.find_first_not_of(' ');
        p.exc_data = first == std::string::npos ? "" : p.exc_data.substr(first);
    } else {
        p.exc_type.clear();
        p.exc_number.clear();
        p.exc_data = msg;
    }
}

// A PSDS subfield's value, by the position it starts at. Positions IBM i
// defines that this runtime cannot supply (the program's library, the
// statement number, file information, ...) read as blanks or zero.
inline std::string rpg_psds_field_str(int pos) {
    auto& p = rpg_psds();
    switch (pos) {
        case 1:   return p.proc_name;
        case 21:  return p.stmt_number;
        case 29:  return p.routine_name;
        case 40:  return p.exc_type;
        case 43:  return p.exc_number;
        case 91:  return p.exc_data;
        case 244: return p.job_name;
        case 254: return p.user_profile;
        case 334: return p.program_name;
        case 344: return p.program_name;
        case 358: return p.user_profile;
        default:  return "";
    }
}
inline long long rpg_psds_field_int(int pos) {
    auto& p = rpg_psds();
    switch (pos) {
        case 11:  return p.status_code;
        case 16:  return p.prev_status;
        case 37:  return p.parm_count;
        case 264: return p.job_number;
        case 276: return p.run_date;
        case 282: return p.run_time;
        default:  return 0;
    }
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
    // A name held in a variable may be qualified, LIB/NAME, and padded with
    // blanks; data areas here live in one directory, so only NAME matters.
    auto slash = upper.rfind('/');
    if (slash != std::string::npos) upper = upper.substr(slash + 1);
    while (!upper.empty() && upper.back() == ' ') upper.pop_back();
    if (!upper.empty() && upper[0] == '*') upper = upper.substr(1);
    return (rpg_da_dir() / upper).string();
}

// IN, OUT and UNLOCK, as IBM i does them (verified on PUB400, test93,
// test96). IN *LOCK takes the data area's lock; OUT needs it (status 412
// without), and releases it unless it is OUT *LOCK; UNLOCK releases it, and
// unlocking one not locked is not an error. The local, group and
// program-initialization data areas (*LDA, *GDA, *PDA) need no lock. An
// error -- 401 not found, 412 not locked, 413/415 cannot write/read -- ends
// the program unless (E) is coded or a MONITOR handles it.
inline std::set<std::string>& rpg_da_locks() { static std::set<std::string> s; return s; }
inline std::string rpg_da_key(const std::string& name) {
    std::string k = rpg_da_path(name);
    return k;
}
inline bool rpg_da_special(const std::string& name) {
    size_t i = name.find_first_not_of(' ');
    return i != std::string::npos && name[i] == '*';
}
inline bool rpg_da_fail(int status, const std::string& msg, bool errext) {
    if (!errext) rpg_raise(status, msg);
    rpg_status_code() = status;
    rpg_error_flag() = true;
    return false;
}
inline void rpg_da_ok() {
    rpg_status_code() = 0;
    rpg_error_flag() = false;
}

// Reads the data area into `out`; false (and `out` untouched) on an error.
inline bool rpg_da_in(const std::string& name, int max_len, bool lock, bool errext, std::string& out) {
    std::string path = rpg_da_path(name);
    if (!std::filesystem::exists(path))
        return rpg_da_fail(401, "RNX0401: Data area " + name + " was not found.", errext);
    std::ifstream f(path, std::ios::binary);
    if (!f)
        return rpg_da_fail(415, "RNX0415: Data area " + name + " could not be read.", errext);
    std::string content((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    content.resize(max_len, ' ');
    out = content;
    if (lock && !rpg_da_special(name)) rpg_da_locks().insert(rpg_da_key(name));
    rpg_da_ok();
    return true;
}

inline bool rpg_da_out(const std::string& name, const std::string& value, bool lock, bool errext) {
    bool special = rpg_da_special(name);
    std::string key = rpg_da_key(name);
    if (!special && !rpg_da_locks().count(key))
        return rpg_da_fail(412, "RNX0412: Data area " + name + " is not locked; OUT needs IN *LOCK first.",
                           errext);
    std::ofstream f(rpg_da_path(name), std::ios::binary | std::ios::trunc);
    if (f) f << value;
    if (!f)
        return rpg_da_fail(413, "RNX0413: Data area " + name + " could not be written.", errext);
    if (!lock) rpg_da_locks().erase(key);
    rpg_da_ok();
    return true;
}

inline void rpg_da_unlock(const std::string& name) {
    rpg_da_locks().erase(rpg_da_key(name));
    rpg_da_ok();
}

// Reads a data area outright -- the program's initial read of a DTAARA
// field declared with *AUTO, and similar: not found is blanks.
inline std::string rpg_da_read(const std::string& name, int max_len) {
    std::string v(max_len, ' ');
    rpg_da_in(name, max_len, false, true, v);
    return v;
}

// --- %CHAR: generic to-string conversion ---
inline std::string rpg_to_char(int v) { return std::to_string(v); }
inline std::string rpg_to_char(unsigned int v) { return std::to_string(v); }
inline std::string rpg_to_char(long long v) { return std::to_string(v); }
inline std::string rpg_to_char(unsigned long long v) { return std::to_string(v); }
inline std::string rpg_to_char(double v) { return std::to_string(v); }
inline std::string rpg_to_char(const std::string& v) { return v; }
inline std::string rpg_to_char(bool v) { return v ? "1" : "0"; }
// PACKED/ZONED: format with exactly the declared number of decimal places.
// IBM i writes no zero before the decimal point: %CHAR of 0.50 is ".50",
// of -0.5 "-.50", of zero at two decimals ".00" (verified on PUB400).
// %CHAR(number : *NOZEROSUPPRESS), an OpenRPG extension: every digit the
// field is declared with, leading zeros kept -- PACKED(7:2) 123.4 is
// "00123.40", and -5 "-00005.00" -- with a decimal point and a leading
// minus sign as %CHAR has them.
inline std::string rpg_char_nozero(long double v, int digits, int dec) {
    bool neg = v < 0;
    long double scaled = (neg ? -v : v);
    for (int i = 0; i < dec; i++) scaled *= 10;
    unsigned long long n = static_cast<unsigned long long>(std::llround(scaled));
    std::string d = std::to_string(n);
    if (static_cast<int>(d.size()) < digits) d.insert(0, digits - d.size(), '0');
    if (dec > 0) d.insert(d.size() - dec, ".");
    return (neg && n != 0 ? "-" : "") + d;
}

inline std::string rpg_to_char_packed(double v, int dec) {
    rpg_chk_dec(v);
    std::string buf;
    buf = rpg_sprintf("%.*f", dec, v);
    std::string s = buf;
    if (dec > 0) {
        if (s.compare(0, 2, "0.") == 0) s.erase(0, 1);
        else if (s.compare(0, 3, "-0.") == 0) s.erase(1, 1);
    }
    if (s.find_first_not_of("-0.") == std::string::npos && s[0] == '-') s.erase(0, 1);
    return s;
}

// FLOAT as IBM i writes it in %CHAR, %EDITFLT and DSPLY: an explicit sign,
// one digit, the fraction and a signed exponent. An 8-byte float shows 16
// significant digits and a three-digit exponent, "+1.500000000000000E+000";
// a 4-byte one 8 and two, "+1.5000000E+00". Both verified on PUB400.
inline std::string rpg_float_text(double v, bool four_byte) {
    std::string buf;
    buf = rpg_sprintf("%+.*E", four_byte ? 7 : 15, v);
    std::string s = buf;
    size_t e = s.find('E');
    if (e == std::string::npos) return s;   // inf / nan
    int exp = std::atoi(s.c_str() + e + 1);
    std::string tail;
    tail = rpg_sprintf(four_byte ? "E%c%02d" : "E%c%03d",
                  exp < 0 ? '-' : '+', exp < 0 ? -exp : exp);
    return s.substr(0, e) + tail;
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
    std::string buf;
    buf = rpg_sprintf("%04d-%02d-%02d",
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

// Dates, times and timestamps compare in time order. Their internal values
// are fixed-width ISO text, which sorts the same way.
#define RPG_DT_COMPARE(T) \
    inline bool operator==(const T& a, const T& b) { return a.value == b.value; } \
    inline bool operator!=(const T& a, const T& b) { return a.value != b.value; } \
    inline bool operator<(const T& a, const T& b)  { return a.value <  b.value; } \
    inline bool operator<=(const T& a, const T& b) { return a.value <= b.value; } \
    inline bool operator>(const T& a, const T& b)  { return a.value >  b.value; } \
    inline bool operator>=(const T& a, const T& b) { return a.value >= b.value; }
RPG_DT_COMPARE(RpgDate)
RPG_DT_COMPARE(RpgTime)
RPG_DT_COMPARE(RpgTimestamp)
#undef RPG_DT_COMPARE

struct RpgDuration {
    int amount;
    char unit; // 'D'=days, 'M'=months, 'Y'=years
};

// rpg_to_char overloads for date/time types
inline std::string rpg_to_char(const RpgDate& d) { return d.value; }
// A time is held as hh:mm:ss; its default character form is *ISO, hh.mm.ss.
inline std::string rpg_to_char(const RpgTime& t) {
    std::string v = t.value;
    for (auto& c : v) if (c == ':') c = '.';
    return v;
}
inline std::string rpg_to_char(const RpgTimestamp& ts) { return ts.value; }

// --- A data structure as a character value ---
// A data structure is also a character field of its whole length: DSPLY ds,
// 'x' + ds, ds = other. Its subfields are separate members here, so each
// generated struct's rpg_chars() lays out their bytes, each at its own
// position, with these. Character and zoned bytes are their characters (a
// negative zoned value written as a numeric OVERLAY does, with a leading
// '-'); binary and packed ones are big-endian, as on IBM i.
inline std::string rpg_num_digits(double v, int digits, int dec);
inline std::string rpg_img_char(const std::string& v, int len) {
    std::string s = v;
    s.resize(static_cast<size_t>(len < 0 ? 0 : len), ' ');
    return s;
}
inline std::string rpg_img_varchar(const std::string& v, int len) {
    size_t n = std::min(v.size(), static_cast<size_t>(len < 0 ? 0 : len));
    std::string s;
    s += static_cast<char>((n >> 8) & 0xFF);
    s += static_cast<char>(n & 0xFF);
    s += v.substr(0, n);
    s.resize(static_cast<size_t>(len) + 2, ' ');
    return s;
}
inline std::string rpg_img_zoned(double v, int digits, int dec) {
    bool neg = v < 0;
    std::string d = rpg_num_digits(v, neg && digits > 0 ? digits - 1 : digits, dec);
    return neg ? "-" + d : d;
}
inline std::string rpg_img_packed(double v, int digits, int dec) {
    int bytes = digits / 2 + 1;
    std::string d = rpg_num_digits(v, bytes * 2 - 1, dec);
    d += v < 0 ? 'D' : 'F';
    std::string s;
    for (int i = 0; i < bytes; i++) {
        auto nib = [](char c) { return c >= '0' && c <= '9' ? c - '0' : c == 'D' ? 0xD : 0xF; };
        s += static_cast<char>((nib(d[2 * i]) << 4) | nib(d[2 * i + 1]));
    }
    return s;
}
inline std::string rpg_img_int(long long v, int bytes) {
    std::string s(static_cast<size_t>(bytes), '\0');
    unsigned long long u = static_cast<unsigned long long>(v);
    for (int i = bytes - 1; i >= 0; i--) { s[static_cast<size_t>(i)] = static_cast<char>(u & 0xFF); u >>= 8; }
    return s;
}
inline std::string rpg_img_float(double v, int bytes) {
    std::string s(static_cast<size_t>(bytes), '\0');
    unsigned char b[8];
    if (bytes == 4) { float f = static_cast<float>(v); std::memcpy(b, &f, 4); }
    else std::memcpy(b, &v, 8);
    for (int i = 0; i < bytes; i++) s[static_cast<size_t>(i)] = static_cast<char>(b[bytes - 1 - i]);
    return s;
}
// Place one subfield's bytes at `from` (1-based), or after the previous
// subfield when its position isn't known until run time (from 0).
inline void rpg_img_put(std::string& s, size_t& next, int from, const std::string& img) {
    size_t at = from > 0 ? static_cast<size_t>(from - 1) : next;
    if (s.size() < at + img.size()) s.resize(at + img.size(), ' ');
    s.replace(at, img.size(), img);
    next = at + img.size();
}

// The other way: a data structure's subfields from its bytes (rpg_set_chars,
// when one is passed to a program, which may change it). rpg_img_take
// takes a subfield's `len` bytes from where rpg_img_put put them.
inline std::string rpg_img_take(const std::string& s, size_t& next, int from, size_t len) {
    size_t at = from > 0 ? static_cast<size_t>(from - 1) : next;
    next = at + len;
    std::string b = at < s.size() ? s.substr(at, len) : std::string();
    b.resize(len, ' ');
    return b;
}
inline std::string rpg_unimg_varchar(const std::string& b, int len) {
    size_t n = b.size() >= 2 ? (static_cast<unsigned char>(b[0]) << 8 | static_cast<unsigned char>(b[1])) : 0;
    n = std::min(n, static_cast<size_t>(len < 0 ? 0 : len));
    return b.size() >= 2 + n ? b.substr(2, n) : std::string();
}
inline double rpg_digits_num(const std::string& d, int dec, bool neg);
inline double rpg_unimg_zoned(const std::string& b, int dec) {
    bool neg = !b.empty() && b[0] == '-';
    std::string d;
    for (char c : b) d += (c >= '0' && c <= '9') ? c : '0';
    return rpg_digits_num(d, dec, neg);
}
inline double rpg_unimg_packed(const std::string& b, int dec) {
    std::string d;
    for (size_t i = 0; i < b.size(); i++) {
        unsigned char c = static_cast<unsigned char>(b[i]);
        d += static_cast<char>('0' + ((c >> 4) % 10));
        if (i + 1 < b.size()) d += static_cast<char>('0' + ((c & 0x0F) % 10));
    }
    unsigned char sign = b.empty() ? 0x0F : static_cast<unsigned char>(b.back()) & 0x0F;
    return rpg_digits_num(d, dec, sign == 0x0D || sign == 0x0B);
}
inline long long rpg_unimg_int(const std::string& b) {
    unsigned long long u = 0;
    for (char c : b) u = (u << 8) | static_cast<unsigned char>(c);
    if (!b.empty() && b.size() < 8 && (static_cast<unsigned char>(b[0]) & 0x80))
        u |= ~0ULL << (8 * b.size());   // sign-extend
    return static_cast<long long>(u);
}
inline unsigned long long rpg_unimg_uns(const std::string& b) {
    unsigned long long u = 0;
    for (char c : b) u = (u << 8) | static_cast<unsigned char>(c);
    return u;
}
inline double rpg_unimg_float(const std::string& b) {
    unsigned char r[8] = {};
    for (size_t i = 0; i < b.size() && i < 8; i++) r[i] = static_cast<unsigned char>(b[b.size() - 1 - i]);
    if (b.size() == 4) { float f; std::memcpy(&f, r, 4); return f; }
    double d; std::memcpy(&d, r, 8); return d;
}


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
    } else if (fmt == "*CYMD" || fmt == "*CMDY" || fmt == "*CDMY") {
        // cyy/mm/dd, cmm/dd/yy, cdd/mm/yy — SC09-2508 Table 15: the
        // century digit is joined to the group that follows it, not
        // separated from it, so these are 9 characters, not 10. Note 2
        // there gives c its full range: c=0 is 1900-1999, c=1 2000-2099,
        // up to c=9 for 2800-2899 — not a 19xx/20xx flag.
        int a, b, e;
        sscanf(s.c_str(), "%3d%*c%2d%*c%2d", &a, &b, &e);
        int century = 1900 + (a / 100) * 100;
        if (fmt == "*CYMD")      { y = century + (a % 100); m = b; d = e; }
        else if (fmt == "*CMDY") { m = a % 100; d = b; y = century + e; }
        else                     { d = a % 100; m = b; y = century + e; }
    } else {
        return s; // unknown format, pass through
    }
    std::string buf;
    buf = rpg_sprintf("%04d-%02d-%02d", y, m, d);
    return buf;
}

// Format ISO date to specified RPG format
inline std::string rpg_format_date_fmt(const std::string& iso, const std::string& fmt) {
    if (fmt == "*ISO" || fmt == "*ISO0" || fmt.empty()) return iso;
    int y = std::stoi(iso.substr(0, 4));
    int m = std::stoi(iso.substr(5, 2));
    int d = std::stoi(iso.substr(8, 2));
    std::string buf;
    if (fmt == "*USA") {
        buf = rpg_sprintf("%02d/%02d/%04d", m, d, y);
    } else if (fmt == "*EUR") {
        buf = rpg_sprintf("%02d.%02d.%04d", d, m, y);
    } else if (fmt == "*JIS") {
        return iso;
    } else if (fmt == "*MDY") {
        buf = rpg_sprintf("%02d/%02d/%02d", m, d, y % 100);
    } else if (fmt == "*DMY") {
        buf = rpg_sprintf("%02d/%02d/%02d", d, m, y % 100);
    } else if (fmt == "*YMD") {
        buf = rpg_sprintf("%02d/%02d/%02d", y % 100, m, d);
    } else if (fmt == "*JUL") {
        int doy = rpg_day_of_year(y, m, d);
        buf = rpg_sprintf("%02d/%03d", y % 100, doy);
    } else if (fmt == "*LONGJUL") {
        int doy = rpg_day_of_year(y, m, d);
        buf = rpg_sprintf("%04d/%03d", y, doy);
    } else if (fmt == "*CYMD") {
        buf = rpg_sprintf("%d%02d/%02d/%02d", (y - 1900) / 100, y % 100, m, d);
    } else if (fmt == "*CMDY") {
        buf = rpg_sprintf("%d%02d/%02d/%02d", (y - 1900) / 100, m, d, y % 100);
    } else if (fmt == "*CDMY") {
        buf = rpg_sprintf("%d%02d/%02d/%02d", (y - 1900) / 100, d, m, y % 100);
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
    std::string buf;
    buf = rpg_sprintf("%02d:%02d:%02d", h, m, sec);
    return buf;
}

// Format ISO time to RPG format
inline std::string rpg_format_time_fmt(const std::string& iso, const std::string& fmt) {
    if (fmt == "*ISO" || fmt == "*ISO0" || fmt.empty()) return iso;
    int h = std::stoi(iso.substr(0, 2));
    int m = std::stoi(iso.substr(3, 2));
    int s = std::stoi(iso.substr(6, 2));
    std::string buf;
    if (fmt == "*USA") {
        const char* ampm = (h >= 12) ? "PM" : "AM";
        int h12 = h % 12;
        if (h12 == 0) h12 = 12;
        buf = rpg_sprintf("%02d:%02d %s", h12, m, ampm);
    } else if (fmt == "*HMS") {
        buf = rpg_sprintf("%02d:%02d:%02d", h, m, s);
    } else if (fmt == "*EUR") {
        buf = rpg_sprintf("%02d.%02d.%02d", h, m, s);
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
    std::string buf;
    buf = rpg_sprintf("%02d:%02d:%02d", t->tm_hour, t->tm_min, t->tm_sec);
    return RpgTime(buf);
}

// %TIMESTAMP
inline RpgTimestamp rpg_make_timestamp(const std::string& s) { return RpgTimestamp(s); }
inline RpgTimestamp rpg_current_timestamp() {
    time_t now = time(nullptr);
    std::tm* t = localtime(&now);
    std::string buf;
    buf = rpg_sprintf("%04d-%02d-%02d-%02d.%02d.%02d.000000",
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


// --- %DECH: round to specified decimal places ---
// A character operand of %DEC, %DECH, %INT, %INTH, %UNS, %UNSH or %FLOAT
// (V5R3): an optional sign, '+' or '-', before or after the digits; an
// optional decimal point, a period or a comma; blanks anywhere. Only
// %FLOAT takes an exponent ('1.2E6'). Anything else is status 105.
inline double rpg_char_num(const std::string& s, bool is_float = false) {
    std::string t;
    bool neg = false, sign = false, digits = false, point = false, after = false;
    bool exp = false, exp_digits = false;
    for (char c : s) {
        if (c == ' ') continue;
        if (exp) {
            if ((c == '+' || c == '-') && !exp_digits && t.back() == 'E') t += c;
            else if (c >= '0' && c <= '9') { t += c; exp_digits = true; }
            else goto bad;
            continue;
        }
        if (c >= '0' && c <= '9') {
            if (after) goto bad;
            t += c; digits = true;
        } else if (c == '.' || c == ',') {
            if (point || after) goto bad;
            t += '.'; point = true;
        } else if (c == '+' || c == '-') {
            if (sign) goto bad;
            sign = true; neg = c == '-';
            if (digits || point) after = true;     // a trailing sign
        } else if ((c == 'E' || c == 'e') && is_float && digits && !after) {
            t += 'E'; exp = true;
        } else {
            goto bad;
        }
    }
    if (!digits || (exp && !exp_digits)) goto bad;
    {
        double v = std::strtod(t.c_str(), nullptr);
        return neg ? -v : v;
    }
bad:
    rpg_raise(105, "RNX0105: A character representation of a numeric value is in error ('" +
              s + "')");
}

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

// %LOOKUP(%KDS(key) : ds(*) {: start {: count}}): the 1-based index of the
// first element, of those searched, that the predicate holds for, or 0.
template<typename C, typename P>
inline int rpg_lookup_if(const C& c, P pred, int start = 1, int count = -1) {
    int n = static_cast<int>(c.size());
    if (start < 1 || start > n + 1)
        rpg_raise(121, "RNX0121: Array index not valid.");
    int end = count < 0 ? n : std::min(n, start - 1 + count);
    for (int i = start - 1; i < end; i++)
        if (pred(c[i])) return i + 1;
    return 0;
}

// ds(*).subfield: that subfield of each element of a data structure array.
template<typename C, typename F>
inline auto rpg_ds_column(const C& c, F f) {
    std::vector<std::decay_t<decltype(f(*c.begin()))>> v;
    v.reserve(c.size());
    for (const auto& e : c) v.push_back(f(e));
    return v;
}

// The array BIFs over a std::vector too: a varying array, or ds(*).subfield.
template<typename T>
inline T rpg_xfoot(const std::vector<T>& arr) {
    T sum = T{};
    for (const auto& v : arr) sum += v;
    return sum;
}
template<typename T>
inline int rpg_maxarr(const std::vector<T>& arr) {
    if (arr.empty()) return 0;
    return static_cast<int>(std::distance(arr.begin(), std::max_element(arr.begin(), arr.end()))) + 1;
}
template<typename T>
inline int rpg_minarr(const std::vector<T>& arr) {
    if (arr.empty()) return 0;
    return static_cast<int>(std::distance(arr.begin(), std::min_element(arr.begin(), arr.end()))) + 1;
}
template<typename V, typename T>
inline int rpg_lookup(const V& val, const std::vector<T>& arr, int start = 1, int count = -1) {
    return rpg_lookup_in(val, arr.data(), arr.size(), 'E', start, count);
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

// --- %LOOKUPLT/LE/GT/GE: see rpg_lookup_in ---
template<typename V, typename T, std::size_t N>
inline int rpg_lookup_lt(const V& val, const std::array<T, N>& arr, int start = 1, int count = -1) {
    return rpg_lookup_in(val, arr.data(), N, 'L', start, count);
}

template<typename V, typename T, std::size_t N>
inline int rpg_lookup_le(const V& val, const std::array<T, N>& arr, int start = 1, int count = -1) {
    return rpg_lookup_in(val, arr.data(), N, 'l', start, count);
}

template<typename V, typename T, std::size_t N>
inline int rpg_lookup_gt(const V& val, const std::array<T, N>& arr, int start = 1, int count = -1) {
    return rpg_lookup_in(val, arr.data(), N, 'G', start, count);
}

template<typename V, typename T, std::size_t N>
inline int rpg_lookup_ge(const V& val, const std::array<T, N>& arr, int start = 1, int count = -1) {
    return rpg_lookup_in(val, arr.data(), N, 'g', start, count);
}

// --- %TLOOKUP: table lookup (returns bool, optionally sets alt table element) ---
template<typename V, typename T, std::size_t N>
inline bool rpg_tlookup(const V& val, const std::array<T, N>& table) {
    for (std::size_t i = 0; i < N; i++) {
        if (rpg_eq(table[i], val)) return true;
    }
    return false;
}

template<typename V, typename T, std::size_t N, typename U, std::size_t M>
inline bool rpg_tlookup(const V& val, const std::array<T, N>& table, std::array<U, M>& alt) {
    for (std::size_t i = 0; i < N && i < M; i++) {
        if (rpg_eq(table[i], val)) return true;
    }
    return false;
}

template<typename V, typename T>
inline bool rpg_tlookup(const V& val, const std::vector<T>& table) {
    for (std::size_t i = 0; i < table.size(); i++) {
        if (rpg_eq(table[i], val)) return true;
    }
    return false;
}

template<typename V, typename T, std::size_t N>
inline bool rpg_tlookup_lt(const V& val, const std::array<T, N>& table) {
    for (std::size_t i = 0; i < N; i++) {
        if (rpg_lt(table[i], val)) return true;
    }
    return false;
}

template<typename V, typename T, std::size_t N>
inline bool rpg_tlookup_gt(const V& val, const std::array<T, N>& table) {
    for (std::size_t i = 0; i < N; i++) {
        if (rpg_gt(table[i], val)) return true;
    }
    return false;
}

template<typename V, typename T, std::size_t N>
inline bool rpg_tlookup_le(const V& val, const std::array<T, N>& table) {
    for (std::size_t i = 0; i < N; i++) {
        if (rpg_le(table[i], val)) return true;
    }
    return false;
}

template<typename V, typename T, std::size_t N>
inline bool rpg_tlookup_ge(const V& val, const std::array<T, N>& table) {
    for (std::size_t i = 0; i < N; i++) {
        if (rpg_ge(table[i], val)) return true;
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
    total_secs = (total_secs % 86400 + 86400) % 86400;
    std::string buf;
    buf = rpg_sprintf("%02d:%02d:%02d", total_secs / 3600, (total_secs % 3600) / 60, total_secs % 60);
    return RpgTime(buf);
}

// Timestamp + duration. Years and months move the month and keep the day,
// cut back to the last day of a shorter month (Jan 31 + 1 month is Feb 28 or
// 29), as on IBM i. Days through microseconds are exact: the timestamp is
// counted in microseconds from a fixed day, so no time zone or daylight
// saving change can shift it, as mktime could.
inline long long rpg_civil_to_days(long long y, int m, int d) {
    y -= m <= 2;
    long long era = (y >= 0 ? y : y - 399) / 400;
    long long yoe = y - era * 400;
    long long doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    long long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe;
}
inline void rpg_days_to_civil(long long z, long long& y, int& m, int& d) {
    long long era = (z >= 0 ? z : z - 146096) / 146097;
    long long doe = z - era * 146097;
    long long yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    long long doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    long long mp = (5 * doy + 2) / 153;
    d = static_cast<int>(doy - (153 * mp + 2) / 5 + 1);
    m = static_cast<int>(mp < 10 ? mp + 3 : mp - 9);
    y = yoe + era * 400 + (m <= 2);
}
inline RpgTimestamp operator+(const RpgTimestamp& ts, const RpgDuration& dur) {
    const std::string& v = ts.value;
    long long y = std::stoll(v.substr(0, 4));
    int mo = std::stoi(v.substr(5, 2));
    int d = std::stoi(v.substr(8, 2));
    long long us = std::stoll(v.substr(11, 2)) * 3600000000LL +
                   std::stoll(v.substr(14, 2)) * 60000000LL +
                   std::stoll(v.substr(17, 2)) * 1000000LL +
                   (v.size() > 20 ? std::stoll(v.substr(20)) : 0);
    long long n = dur.amount;
    if (dur.unit == 'Y' || dur.unit == 'M') {
        long long months = y * 12 + (mo - 1) + (dur.unit == 'Y' ? n * 12 : n);
        y = (months >= 0 ? months : months - 11) / 12;
        mo = static_cast<int>(months - y * 12) + 1;
        static const int mdays[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
        bool leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
        int last = mo == 2 && leap ? 29 : mdays[mo - 1];
        if (d > last) d = last;
    } else {
        const long long day_us = 86400000000LL;
        switch (dur.unit) {
            case 'D': us += n * day_us; break;
            case 'H': us += n * 3600000000LL; break;
            case 'I': us += n * 60000000LL; break;
            case 'S': us += n * 1000000LL; break;
            case 'U': us += n; break;
        }
        long long days = rpg_civil_to_days(y, mo, d) + (us >= 0 ? us / day_us : (us - day_us + 1) / day_us);
        us -= (us >= 0 ? us / day_us : (us - day_us + 1) / day_us) * day_us;
        rpg_days_to_civil(days, y, mo, d);
    }
    return RpgTimestamp(rpg_sprintf("%04lld-%02d-%02d-%02lld.%02lld.%02lld.%06lld",
                                    y, mo, d, us / 3600000000LL, us / 60000000LL % 60,
                                    us / 1000000LL % 60, us % 1000000LL));
}

// Date + duration: the date part of a timestamp moved the same way, so
// Jan 31 + 1 month is the last day of February here too, not March 2 or 3
// as normalizing with mktime made it.
inline RpgDate operator+(const RpgDate& d, const RpgDuration& dur) {
    RpgTimestamp ts = RpgTimestamp(d.value + "-00.00.00.000000") + dur;
    return RpgDate(ts.value.substr(0, 10));
}

// Subtracting a duration adds its negative.
inline RpgDate operator-(const RpgDate& d, const RpgDuration& dur) {
    return d + RpgDuration{-dur.amount, dur.unit};
}
inline RpgTime operator-(const RpgTime& t, const RpgDuration& dur) {
    return t + RpgDuration{-dur.amount, dur.unit};
}
inline RpgTimestamp operator-(const RpgTimestamp& ts, const RpgDuration& dur) {
    return ts + RpgDuration{-dur.amount, dur.unit};
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

// --- MOVE/MOVEL with a numeric operand ---
// SC09-2508 "Move Operations" p.633 plus the MOVE (p.884) and MOVEL
// (p.905) entries. The governing rule is that these are *digit* moves,
// not value assignments: "If move operations are specified between
// numeric fields, the decimal positions specified for the factor 2 field
// are ignored. For example, if 1.00 is moved into a three-position
// numeric field with one decimal position, the result is 10.0."
//
// So a numeric operand is first reduced to the fixed-width digit string
// its DECLARED digit count and decimal places give it (codegen passes
// both, since a double carries neither), the move then runs positionally
// on that string exactly as the character move does, and the result
// string is finally reinterpreted through the RESULT field's own decimal
// places. Nothing here looks at either operand's decimal point.

// Exactly `digits` characters: the absolute value scaled by 10^dec, zero
// padded on the left, keeping the rightmost digits if it overflows (which
// is the value a field of that declared size could actually hold).
inline std::string rpg_num_digits(double v, int digits, int dec) {
    if (digits <= 0) return std::string();
    double scaled = std::fabs(v);
    for (int i = 0; i < dec; i++) scaled *= 10.0;
    // llround, not a truncating cast: the scaling above is binary floating
    // point, so an exact decimal like 1.00 can arrive as 99.999999 and a
    // cast would yield "099" — the manual's own worked example, wrong.
    long long n = std::llround(scaled);
    std::string s = std::to_string(n);
    if (static_cast<int>(s.size()) < digits)
        s = std::string(static_cast<size_t>(digits) - s.size(), '0') + s;
    else if (static_cast<int>(s.size()) > digits)
        s = s.substr(s.size() - static_cast<size_t>(digits));
    return s;
}

inline double rpg_digits_num(const std::string& d, int dec, bool neg) {
    double v = 0.0;
    for (char c : d) v = v * 10.0 + static_cast<double>(c - '0');
    for (int i = 0; i < dec; i++) v /= 10.0;
    return neg ? -v : v;
}

// A factor 2 reduced to (digit string, sign) in one evaluation — so a
// factor 2 that is a call or a computed expression is not evaluated twice
// to get its digits and then its sign.
struct RpgDigits {
    std::string digits;
    bool neg;
};

template <typename T>
inline RpgDigits rpg_digits_of(T v, int digits, int dec) {
    double d = static_cast<double>(v);
    return RpgDigits{rpg_num_digits(d, digits, dec), d < 0};
}

// The CCSID 37 (EBCDIC, US) code of each byte, read as Latin-1. MOVE
// between characters and numbers works on EBCDIC zones and digit portions,
// so a character's meaning there is its EBCDIC code's, not its ASCII one.
inline unsigned char rpg_ebcdic37(unsigned char c) {
    static const unsigned char t[256] = {
    0x00, 0x01, 0x02, 0x03, 0x37, 0x2D, 0x2E, 0x2F, 0x16, 0x05, 0x25, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
    0x10, 0x11, 0x12, 0x13, 0x3C, 0x3D, 0x32, 0x26, 0x18, 0x19, 0x3F, 0x27, 0x1C, 0x1D, 0x1E, 0x1F,
    0x40, 0x5A, 0x7F, 0x7B, 0x5B, 0x6C, 0x50, 0x7D, 0x4D, 0x5D, 0x5C, 0x4E, 0x6B, 0x60, 0x4B, 0x61,
    0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0x7A, 0x5E, 0x4C, 0x7E, 0x6E, 0x6F,
    0x7C, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6,
    0xD7, 0xD8, 0xD9, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xBA, 0xE0, 0xBB, 0xB0, 0x6D,
    0x79, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96,
    0x97, 0x98, 0x99, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xC0, 0x4F, 0xD0, 0xA1, 0x07,
    0x20, 0x21, 0x22, 0x23, 0x24, 0x15, 0x06, 0x17, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x09, 0x0A, 0x1B,
    0x30, 0x31, 0x1A, 0x33, 0x34, 0x35, 0x36, 0x08, 0x38, 0x39, 0x3A, 0x3B, 0x04, 0x14, 0x3E, 0xFF,
    0x41, 0xAA, 0x4A, 0xB1, 0x9F, 0xB2, 0x6A, 0xB5, 0xBD, 0xB4, 0x9A, 0x8A, 0x5F, 0xCA, 0xAF, 0xBC,
    0x90, 0x8F, 0xEA, 0xFA, 0xBE, 0xA0, 0xB6, 0xB3, 0x9D, 0xDA, 0x9B, 0x8B, 0xB7, 0xB8, 0xB9, 0xAB,
    0x64, 0x65, 0x62, 0x66, 0x63, 0x67, 0x9E, 0x68, 0x74, 0x71, 0x72, 0x73, 0x78, 0x75, 0x76, 0x77,
    0xAC, 0x69, 0xED, 0xEE, 0xEB, 0xEF, 0xEC, 0xBF, 0x80, 0xFD, 0xFE, 0xFB, 0xFC, 0xAD, 0xAE, 0x59,
    0x44, 0x45, 0x42, 0x46, 0x43, 0x47, 0x9C, 0x48, 0x54, 0x51, 0x52, 0x53, 0x58, 0x55, 0x56, 0x57,
    0x8C, 0x49, 0xCD, 0xCE, 0xCB, 0xCF, 0xCC, 0xE1, 0x70, 0xDD, 0xDE, 0xDB, 0xDC, 0x8D, 0x8E, 0xDF
    };
    return t[c];
}

// Character factor 2 into a numeric result: "the digit portion of each
// character is converted to its corresponding numeric character and then
// moved to the result field. Blanks are transferred as zeros." The digit
// portion is the low half of the character's EBCDIC code, so 'A' (x'C1')
// moves as 1 and 'J' (x'D1') as 1 too, with no data error (PUB400,
// test196). The result is negative when "the zone from the rightmost
// position of factor 2 is a hexadecimal D", which is 'J'-'R' and '}'.
// A digit portion above 9 (x'4A'-x'4F', among others) is no digit at all;
// that stays a data exception (status 907).
inline RpgDigits rpg_digits_of_char(const std::string& s) {
    std::string out;
    out.reserve(s.size());
    unsigned char zone = 0xF;
    for (char c : s) {
        unsigned char e = rpg_ebcdic37(static_cast<unsigned char>(c));
        unsigned char d = e & 0x0F;
        if (d > 9) {
            rpg_status_code() = 907; // decimal data error
            rpg_error_flag() = true;
            return RpgDigits{std::string(s.size(), '0'), false};
        }
        out += static_cast<char>('0' + d);
        zone = static_cast<unsigned char>(e >> 4);
    }
    return RpgDigits{out, !s.empty() && zone == 0xD};
}

// Numeric factor 2 into a character result: the digits, with the sign in
// the zone of the rightmost one, as IBM i stores a zoned number. A
// negative value's last digit takes the D zone, which reads as '}' for 0
// and 'J'-'R' for 1-9 (-12345 moves as "1234N"; PUB400, test193).
inline std::string rpg_digits_text(const RpgDigits& d) {
    std::string out = d.digits;
    if (d.neg && !out.empty()) out.back() = "}JKLMNOPQR"[out.back() - '0'];
    return out;
}

template <typename T>
inline void rpg_move_num_fixed(T& dst, int dstDigits, int dstDec,
                               const RpgDigits& src, bool pad, bool left) {
    if (dstDigits <= 0) return;
    double cur_val = static_cast<double>(dst);
    std::string cur = rpg_num_digits(cur_val, dstDigits, dstDec);
    bool neg = cur_val < 0;
    int slen = static_cast<int>(src.digits.size());
    int n = slen > dstDigits ? dstDigits : slen;
    if (left) {
        // MOVEL: excess RIGHTMOST digits of factor 2 are not moved; excess
        // rightmost digits of the result are unchanged unless padded.
        for (int i = 0; i < n; i++)
            cur[static_cast<size_t>(i)] = src.digits[static_cast<size_t>(i)];
        if (pad) for (int i = n; i < dstDigits; i++) cur[static_cast<size_t>(i)] = '0';
        // "the sign (+ or -) of the result field is retained except when
        // factor 2 is as long as or longer than the result field. In this
        // case, the sign of factor 2 is used as the sign of the result."
        if (slen >= dstDigits) neg = src.neg;
    } else {
        // MOVE: excess LEFTMOST digits of factor 2 are not moved; excess
        // leftmost digits of the result are unchanged unless padded.
        for (int i = 0; i < n; i++)
            cur[static_cast<size_t>(dstDigits - n + i)] =
                src.digits[static_cast<size_t>(slen - n + i)];
        if (pad) for (int i = 0; i < dstDigits - n; i++) cur[static_cast<size_t>(i)] = '0';
        // MOVE always moves factor 2's rightmost position, which is where
        // the sign lives, so factor 2's sign always becomes the result's.
        neg = src.neg;
    }
    dst = static_cast<T>(rpg_digits_num(cur, dstDec, neg));
}

template <typename T>
inline void rpg_move_num(T& dst, int dstDigits, int dstDec,
                         const RpgDigits& src, bool pad) {
    rpg_move_num_fixed(dst, dstDigits, dstDec, src, pad, false);
}

template <typename T>
inline void rpg_movel_num(T& dst, int dstDigits, int dstDec,
                          const RpgDigits& src, bool pad) {
    rpg_move_num_fixed(dst, dstDigits, dstDec, src, pad, true);
}
// --- MOVE/MOVEL with a date, time or timestamp operand ---
// SC09-2508 "Moving Date-Time Data" p.405, plus MOVE (p.629) and MOVEL
// (p.650). The manual allows exactly thirteen operand combinations:
// Date/Time/Timestamp to their own type, Date and Time to Timestamp,
// Timestamp to Date and to Time, each of the three to character or
// numeric, and character or numeric to each of the three.
//
// Factor 1 "must be blank if both the source and the target of the move
// are Date, Time or Timestamp fields. If factor 1 is blank, the format of
// the Date, Time, or Timestamp field is used." Otherwise it names the
// format of whichever operand is the character or numeric one. Codegen
// resolves that to (format name, separator) and passes both in; a
// separator of '\0' is the manual's trailing zero (*MDY0), meaning the
// character operand carries no separators at all. Numeric operands never
// carry separators ("If the result field is numeric, separator characters
// will be removed, prior to the operation"), so codegen passes '\0'.
//
// The move itself is still the same positional move the character and
// numeric forms already do: the conversion produces a fixed-width text
// exactly as wide as the format defines, and rpg_move_fixed /
// rpg_move_num_fixed then place it in the result. That is what makes
// "if character or numeric data is longer than required, only the
// leftmost data (rightmost for the MOVE operation) is used" fall out
// rather than needing its own rule.

// Every RPG date and time format is a run of fixed-width digit groups
// joined by a single separator character, so one digit-layout description
// covers all of them. The two exceptions are handled on their own below:
// time *USA (a 12-hour clock with an AM/PM suffix, not a separator) and
// the timestamp (six separators that are not all the same character).
inline int rpg_dt_digit_width(int kind, const std::string& f) {
    if (kind == 2) return 20;                       // timestamp: yyyymmddhhmmss+6
    if (kind == 1) return 6;                        // time: hhmmss
    if (f == "*JUL") return 5;                      // yyddd
    if (f == "*CYMD" || f == "*CMDY" || f == "*CDMY") return 7;   // cyymmdd
    if (f == "*LONGJUL") return 7;                  // yyyyddd
    if (f == "*ISO" || f == "*JIS" || f == "*USA" || f == "*EUR") return 8;
    return 6;                                       // *MDY, *DMY, *YMD
}

// Offsets into the digit string at which this format's separators fall,
// and the character each one uses when it is not the caller's separator
// (only the timestamp needs per-position characters).
inline int rpg_dt_sep_positions(int kind, const std::string& f, int* pos,
                                const char** perPos) {
    *perPos = nullptr;
    if (kind == 2) {                                // yyyy-mm-dd-hh.mm.ss.mmmmmm
        pos[0] = 4; pos[1] = 6; pos[2] = 8; pos[3] = 10; pos[4] = 12; pos[5] = 14;
        *perPos = "---...";
        return 6;
    }
    if (kind == 1) { pos[0] = 2; pos[1] = 4; return 2; }
    if (f == "*JUL")     { pos[0] = 2; return 1; }
    if (f == "*LONGJUL") { pos[0] = 4; return 1; }
    if (f == "*CYMD" || f == "*CMDY" || f == "*CDMY") { pos[0] = 3; pos[1] = 5; return 2; }
    if (f == "*ISO" || f == "*JIS") { pos[0] = 4; pos[1] = 6; return 2; }
    pos[0] = 2; pos[1] = 4; return 2;               // *MDY/*DMY/*YMD/*USA/*EUR
}

// The default separator (Table 13/15/16's "Format (Default Separator)").
inline char rpg_dt_default_sep(int kind, const std::string& f) {
    if (kind == 2) return '-';                      // per-position, see above
    if (kind == 1) return (f == "*ISO" || f == "*EUR") ? '.' : ':';
    if (f == "*ISO" || f == "*JIS") return '-';
    if (f == "*EUR") return '.';
    return '/';
}

// Full width of the rendered text: digits plus separators, unless the
// caller asked for none. Time *USA is "hh:mm AM", eight characters, and
// has no separator-free form.
inline int rpg_dt_width(int kind, const std::string& f, char sep) {
    if (kind == 1 && f == "*USA") return 8;
    int pos[6];
    const char* perPos;
    int nsep = rpg_dt_sep_positions(kind, f, pos, &perPos);
    return rpg_dt_digit_width(kind, f) + (sep ? nsep : 0);
}

// Days-in-month check, so an impossible date is a status 112 rather than
// a silently normalized one.
inline bool rpg_dt_valid_ymd(int y, int m, int d) {
    if (y < 1 || y > 9999 || m < 1 || m > 12 || d < 1) return false;
    static const int dim[] = {31,28,31,30,31,30,31,31,30,31,30,31};
    int mx = dim[m - 1];
    if (m == 2 && ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)) mx = 29;
    return d <= mx;
}

inline int rpg_dt_num(const std::string& s, int off, int len) {
    int v = 0;
    for (int i = 0; i < len; i++) {
        char c = s[static_cast<size_t>(off + i)];
        if (c < '0' || c > '9') return -1;
        v = v * 10 + (c - '0');
    }
    return v;
}

inline std::string rpg_dt_pad(int v, int w) {
    std::string s = std::to_string(v);
    if (static_cast<int>(s.size()) < w) s = std::string(static_cast<size_t>(w) - s.size(), '0') + s;
    return s.substr(s.size() - static_cast<size_t>(w));
}

// A date's year range is decided by how many year digits its format has
// (SC09-2508 p.193): 2 digits reach 1940-2039, 3 (the century digit plus
// two) reach 1900-2899, 4 reach the whole range. A date outside the
// target format's range is the manual's error 114, not a wrapped year.
inline int rpg_date_year_digits(const std::string& f) {
    if (f == "*MDY" || f == "*DMY" || f == "*YMD" || f == "*JUL") return 2;
    if (f == "*CYMD" || f == "*CMDY" || f == "*CDMY") return 3;
    return 4;
}

inline bool rpg_date_fits(const std::string& iso, const std::string& f) {
    if (iso.size() < 4) return false;
    int y = rpg_dt_num(iso, 0, 4);
    switch (rpg_date_year_digits(f)) {
        case 2:  return y >= 1940 && y <= 2039;
        case 3:  return y >= 1900 && y <= 2899;
        default: return y >= 1 && y <= 9999;
    }
}

// ISO internal value -> this format's digit string. Returns "" (and sets
// status 114) when the value cannot be represented in the format.
inline std::string rpg_dt_digits(const std::string& iso, int kind, const std::string& f) {
    if (kind == 2) {   // yyyy-mm-dd-hh.mm.ss.mmmmmm -> 20 digits
        std::string d;
        for (char c : iso) if (c >= '0' && c <= '9') d += c;
        d.resize(20, '0');
        return d;
    }
    if (kind == 1) {   // hh:mm:ss -> hhmmss
        std::string d;
        for (char c : iso) if (c >= '0' && c <= '9') d += c;
        d.resize(6, '0');
        return d;
    }
    if (!rpg_date_fits(iso, f)) {
        rpg_status_code() = 114;   // date mapping error
        rpg_error_flag() = true;
        return std::string();
    }
    int y = rpg_dt_num(iso, 0, 4), m = rpg_dt_num(iso, 5, 2), d = rpg_dt_num(iso, 8, 2);
    std::string yy = rpg_dt_pad(y % 100, 2);
    std::string c  = rpg_dt_pad((y - 1900) / 100, 1);
    std::string mm = rpg_dt_pad(m, 2), dd = rpg_dt_pad(d, 2);
    if (f == "*MDY") return mm + dd + yy;
    if (f == "*DMY") return dd + mm + yy;
    if (f == "*YMD") return yy + mm + dd;
    if (f == "*JUL") return yy + rpg_dt_pad(rpg_day_of_year(y, m, d), 3);
    if (f == "*USA") return mm + dd + rpg_dt_pad(y, 4);
    if (f == "*EUR") return dd + mm + rpg_dt_pad(y, 4);
    if (f == "*CYMD") return c + yy + mm + dd;
    if (f == "*CMDY") return c + mm + dd + yy;
    if (f == "*CDMY") return c + dd + mm + yy;
    if (f == "*LONGJUL") return rpg_dt_pad(y, 4) + rpg_dt_pad(rpg_day_of_year(y, m, d), 3);
    return rpg_dt_pad(y, 4) + mm + dd;   // *ISO, *JIS
}

// This format's digit string -> ISO internal value. Returns "" (and sets
// status 112) when the digits are not a valid date or time.
inline std::string rpg_dt_from_digits(const std::string& g, int kind, const std::string& f) {
    for (char c : g) if (c < '0' || c > '9') { rpg_status_code() = 112; rpg_error_flag() = true; return std::string(); }
    std::string buf;
    if (kind == 2) {
        int y = rpg_dt_num(g,0,4), mo = rpg_dt_num(g,4,2), d = rpg_dt_num(g,6,2);
        int h = rpg_dt_num(g,8,2), mi = rpg_dt_num(g,10,2), s = rpg_dt_num(g,12,2);
        if (!rpg_dt_valid_ymd(y, mo, d) || h > 24 || mi > 59 || s > 59 ||
            (h == 24 && (mi != 0 || s != 0))) {
            rpg_status_code() = 112; rpg_error_flag() = true; return std::string();
        }
        buf = rpg_sprintf("%04d-%02d-%02d-%02d.%02d.%02d.%s",
                 y, mo, d, h, mi, s, g.substr(14, 6).c_str());
        return buf;
    }
    if (kind == 1) {
        int h = rpg_dt_num(g,0,2), mi = rpg_dt_num(g,2,2), s = rpg_dt_num(g,4,2);
        // 24.00.00 is midnight at the end of the day; any later 24.xx.xx
        // is not a time
        if (h > 24 || mi > 59 || s > 59 || (h == 24 && (mi != 0 || s != 0))) {
            rpg_status_code() = 112; rpg_error_flag() = true; return std::string();
        }
        buf = rpg_sprintf("%02d:%02d:%02d", h, mi, s);
        return buf;
    }
    int y = 0, m = 0, d = 0, doy = 0;
    // A 2-digit year reaches 1940-2039; a century digit c reaches
    // 1900+c*100 .. 1999+c*100 (SC09-2508 Table 15 note 2).
    if (f == "*MDY")       { m = rpg_dt_num(g,0,2); d = rpg_dt_num(g,2,2); y = rpg_dt_num(g,4,2); y += (y < 40) ? 2000 : 1900; }
    else if (f == "*DMY")  { d = rpg_dt_num(g,0,2); m = rpg_dt_num(g,2,2); y = rpg_dt_num(g,4,2); y += (y < 40) ? 2000 : 1900; }
    else if (f == "*YMD")  { y = rpg_dt_num(g,0,2); m = rpg_dt_num(g,2,2); d = rpg_dt_num(g,4,2); y += (y < 40) ? 2000 : 1900; }
    else if (f == "*JUL")  { y = rpg_dt_num(g,0,2); doy = rpg_dt_num(g,2,3); y += (y < 40) ? 2000 : 1900; }
    else if (f == "*USA")  { m = rpg_dt_num(g,0,2); d = rpg_dt_num(g,2,2); y = rpg_dt_num(g,4,4); }
    else if (f == "*EUR")  { d = rpg_dt_num(g,0,2); m = rpg_dt_num(g,2,2); y = rpg_dt_num(g,4,4); }
    else if (f == "*CYMD") { y = 1900 + rpg_dt_num(g,0,1) * 100 + rpg_dt_num(g,1,2); m = rpg_dt_num(g,3,2); d = rpg_dt_num(g,5,2); }
    else if (f == "*CMDY") { y = 1900 + rpg_dt_num(g,0,1) * 100; m = rpg_dt_num(g,1,2); d = rpg_dt_num(g,3,2); y += rpg_dt_num(g,5,2); }
    else if (f == "*CDMY") { y = 1900 + rpg_dt_num(g,0,1) * 100; d = rpg_dt_num(g,1,2); m = rpg_dt_num(g,3,2); y += rpg_dt_num(g,5,2); }
    else if (f == "*LONGJUL") { y = rpg_dt_num(g,0,4); doy = rpg_dt_num(g,4,3); }
    else                   { y = rpg_dt_num(g,0,4); m = rpg_dt_num(g,4,2); d = rpg_dt_num(g,6,2); }
    if (doy > 0) {
        bool leap = (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
        if (doy > (leap ? 366 : 365)) { rpg_status_code() = 112; rpg_error_flag() = true; return std::string(); }
        rpg_from_day_of_year(y, doy, m, d);
    }
    if (!rpg_dt_valid_ymd(y, m, d)) {
        rpg_status_code() = 112; rpg_error_flag() = true; return std::string();
    }
    buf = rpg_sprintf("%04d-%02d-%02d", y, m, d);
    return buf;
}

// Rendered text for a date/time/timestamp, exactly rpg_dt_width wide.
inline std::string rpg_dt_text(const std::string& iso, int kind,
                               const std::string& f, char sep) {
    if (kind == 1 && f == "*USA") {
        int h = rpg_dt_num(iso, 0, 2), mi = rpg_dt_num(iso, 3, 2);
        const char* ap = (h >= 12) ? "PM" : "AM";
        int h12 = h % 12; if (h12 == 0) h12 = 12;
        std::string buf;
        buf = rpg_sprintf("%02d%c%02d %s", h12, sep ? sep : ':', mi, ap);
        return buf;
    }
    std::string g = rpg_dt_digits(iso, kind, f);
    if (g.empty()) return g;
    if (!sep) return g;
    int pos[6];
    const char* perPos;
    int nsep = rpg_dt_sep_positions(kind, f, pos, &perPos);
    std::string out;
    int prev = 0;
    for (int i = 0; i < nsep; i++) {
        out += g.substr(static_cast<size_t>(prev), static_cast<size_t>(pos[i] - prev));
        out += perPos ? perPos[i] : sep;
        prev = pos[i];
    }
    out += g.substr(static_cast<size_t>(prev));
    return out;
}

// The inverse: text of exactly rpg_dt_width characters back to the ISO
// internal value. Separator characters are checked to be where the format
// puts them ("separator characters must be valid for the specified
// format"), so a mis-shaped field is a status 112 rather than digits read
// out of position.
inline std::string rpg_dt_parse(const std::string& t, int kind,
                                const std::string& f, char sep) {
    if (kind == 1 && f == "*USA") {
        int h = rpg_dt_num(t, 0, 2), mi = rpg_dt_num(t, 3, 2);
        if (h < 0 || mi < 0 || h > 12 || mi > 59) { rpg_status_code() = 112; rpg_error_flag() = true; return std::string(); }
        char ap = t.size() > 6 ? static_cast<char>(toupper((unsigned char)t[6])) : 'A';
        if (ap == 'P' && h != 12) h += 12;
        if (ap == 'A' && h == 12) h = 0;
        std::string buf;
        buf = rpg_sprintf("%02d:%02d:00", h, mi);
        return buf;
    }
    std::string g;
    if (!sep) {
        g = t;
    } else {
        int pos[6];
        const char* perPos;
        int nsep = rpg_dt_sep_positions(kind, f, pos, &perPos);
        int prev = 0, take = 0;
        for (int i = 0; i < nsep; i++) {
            int n = pos[i] - prev;
            g += t.substr(static_cast<size_t>(take), static_cast<size_t>(n));
            take += n;
            char want = perPos ? perPos[i] : sep;
            if (static_cast<size_t>(take) >= t.size() || t[static_cast<size_t>(take)] != want) {
                rpg_status_code() = 112; rpg_error_flag() = true; return std::string();
            }
            take++;
            prev = pos[i];
        }
        g += t.substr(static_cast<size_t>(take));
    }
    return rpg_dt_from_digits(g, kind, f);
}

// --- %DATE / %TIME / %TIMESTAMP with a format, and TEST(D/T/Z) ---
// A format may carry its separator as a suffix: *MDY/ or *MDY-, and a
// trailing 0 (*MDY0, *ISO0) for none. Without one, the format's default.
inline void rpg_dt_split_fmt(int kind, const std::string& spec, std::string& f, char& sep) {
    f = spec;
    for (auto& c : f) c = (char)toupper((unsigned char)c);
    if (f.empty()) f = "*ISO";
    char last = f.back();
    bool known = false;
    for (const char* n : {"*ISO", "*USA", "*EUR", "*JIS", "*MDY", "*DMY", "*YMD", "*JUL",
                          "*LONGJUL", "*CYMD", "*CMDY", "*CDMY", "*HMS"})
        if (f == n) known = true;
    if (!known && std::string("/-.,&0:").find(last) != std::string::npos) {
        f.pop_back();
        sep = last == '0' ? '\0' : last;
        return;
    }
    sep = rpg_dt_default_sep(kind, f);
}

// Character text in format spec -> the internal value, or "" (status 112)
// when it is not a valid date, time or timestamp in that format. Trailing
// blanks are ignored; otherwise the text must be exactly the format's width.
inline std::string rpg_dt_text_value(const std::string& text, int kind, const std::string& spec) {
    std::string f; char sep;
    rpg_dt_split_fmt(kind, spec, f, sep);
    std::string t = text;
    while (!t.empty() && t.back() == ' ') t.pop_back();
    if (kind == 2 && sep == '-') sep = '-';          // timestamp: per-position separators
    if (static_cast<int>(t.size()) != rpg_dt_width(kind, f, sep)) {
        rpg_status_code() = 112; rpg_error_flag() = true; return std::string();
    }
    return rpg_dt_parse(t, kind, f, sep);
}

// A number in format spec -> the internal value. Numbers carry no
// separators: 20240115 in *ISO, 11524 (011524) in *MDY.
inline std::string rpg_dt_number_value(long long v, int kind, const std::string& spec) {
    std::string f; char sep;
    rpg_dt_split_fmt(kind, spec, f, sep);
    if (v < 0) { rpg_status_code() = 112; rpg_error_flag() = true; return std::string(); }
    std::string g = std::to_string(v);
    int w = rpg_dt_digit_width(kind, f);
    if (static_cast<int>(g.size()) > w) { rpg_status_code() = 112; rpg_error_flag() = true; return std::string(); }
    g = std::string(static_cast<size_t>(w) - g.size(), '0') + g;
    return rpg_dt_from_digits(g, kind, f);
}

inline std::string rpg_dt_value(const std::string& text, int kind, const std::string& spec) {
    return rpg_dt_text_value(text, kind, spec);
}
inline std::string rpg_dt_value(const char* text, int kind, const std::string& spec) {
    return rpg_dt_text_value(text, kind, spec);
}
template <typename N, typename = std::enable_if_t<std::is_arithmetic_v<N>>>
inline std::string rpg_dt_value(N v, int kind, const std::string& spec) {
    return rpg_dt_number_value(static_cast<long long>(v), kind, spec);
}

// %DATE(value : format) and friends: an invalid value is status 112.
template <typename V>
inline RpgDate rpg_make_date(const V& v, const std::string& spec) {
    std::string iso = rpg_dt_value(v, 0, spec);
    if (iso.empty()) rpg_raise(112, "Date, time or timestamp value is not valid");
    return RpgDate(iso);
}
template <typename V>
inline RpgTime rpg_make_time(const V& v, const std::string& spec) {
    std::string iso = rpg_dt_value(v, 1, spec);
    if (iso.empty()) rpg_raise(112, "Date, time or timestamp value is not valid");
    return RpgTime(iso);
}
template <typename V>
inline RpgTimestamp rpg_make_timestamp(const V& v, const std::string& spec) {
    std::string iso = rpg_dt_value(v, 2, spec);
    if (iso.empty()) rpg_raise(112, "Date, time or timestamp value is not valid");
    return RpgTimestamp(iso);
}
// The date or time part of a timestamp
inline RpgDate rpg_make_date(const RpgTimestamp& z) { return RpgDate(z.value.substr(0, 10)); }
inline RpgDate rpg_make_date(const RpgDate& d) { return d; }
inline RpgTime rpg_make_time(const RpgTimestamp& z) {
    std::string t = z.value.substr(11, 8);
    for (auto& c : t) if (c == '.') c = ':';
    return RpgTime(t);
}
inline RpgTime rpg_make_time(const RpgTime& t) { return t; }

// TEST(E) on a time or timestamp field: whether its value is valid.
inline bool rpg_test_time(const RpgTime& t) {
    std::string g;
    for (char c : t.value) if (c >= '0' && c <= '9') g += c;
    return g.size() == 6 && !rpg_dt_from_digits(g, 1, "*ISO").empty();
}
inline bool rpg_test_timestamp(const RpgTimestamp& z) {
    std::string g;
    for (char c : z.value) if (c >= '0' && c <= '9') g += c;
    return g.size() == 20 && !rpg_dt_from_digits(g, 2, "*ISO").empty();
}

// TEST(D/T/Z) {format} field: whether a character or numeric field holds a
// valid date, time or timestamp in that format.
template <typename V>
inline bool rpg_test_value(const V& v, int kind, const std::string& spec) {
    return !rpg_dt_value(v, kind, spec).empty();
}

// --- The moves themselves ---
// Kind and internal value are read off the operand's own type, so the
// combination table is enforced by which overloads exist plus codegen's
// own check (which is what produces the diagnostic).
inline int rpg_dt_kind(const RpgDate&)      { return 0; }
inline int rpg_dt_kind(const RpgTime&)      { return 1; }
inline int rpg_dt_kind(const RpgTimestamp&) { return 2; }

// Date/Time/Timestamp -> character. The conversion yields exactly the
// format's width; the positional character move then places it.
template <typename D>
inline void rpg_move_dt_char(std::string& dst, int dstLen, const D& src,
                             const std::string& f, char sep, bool pad, bool left) {
    std::string t = rpg_dt_text(src.value, rpg_dt_kind(src), f, sep);
    if (t.empty()) return;                  // conversion failed; result unchanged
    rpg_move_fixed(dst, t, dstLen, pad, left);
}

// Date/Time/Timestamp -> numeric. Same conversion with separators removed
// ("If the result field is numeric, separator characters will be removed,
// prior to the operation"), then the positional digit move.
template <typename T, typename D>
inline void rpg_move_dt_num(T& dst, int dstDigits, int dstDec, const D& src,
                            const std::string& f, bool pad, bool left) {
    std::string t = rpg_dt_text(src.value, rpg_dt_kind(src), f, '\0');
    if (t.empty()) return;
    rpg_move_num_fixed(dst, dstDigits, dstDec, RpgDigits{t, false}, pad, left);
}

// A MOVE that cannot produce a valid date, time or timestamp is an error
// that ends the program unless MONITOR handles it (MOVE has no (E), and
// this compiler does not take the error indicator in positions 73-74).
// The result field is left unchanged. PUB400, test208 and test212.
[[noreturn]] inline void rpg_move_dt_invalid() {
    rpg_raise(112, "RNX0112: The date, time or timestamp value is not valid.");
}
[[noreturn]] inline void rpg_move_dt_range() {
    rpg_raise(114, "RNX0114: The date is outside the range of the result field's date format.");
}

// Character or numeric -> Date/Time/Timestamp. `text` is the operand at
// its declared width (a character field padded to its declared length, a
// numeric one reduced to its declared digits). Only as much of it as the
// format needs is used, taken from the left for MOVEL and from the right
// for MOVE. `dstFmt` is the RESULT field's own declared format: the
// internal value is always ISO here, but a 2- or 3-digit-year result
// format still cannot represent every date.
template <typename D>
inline void rpg_move_text_dt(D& dst, const std::string& text,
                             const std::string& f, char sep, bool left,
                             const std::string& dstFmt) {
    int kind = rpg_dt_kind(dst);
    int need = rpg_dt_width(kind, f, sep);
    int have = static_cast<int>(text.size());
    if (have < need) rpg_move_dt_invalid();  // not a valid representation
    std::string piece = left ? text.substr(0, static_cast<size_t>(need))
                             : text.substr(static_cast<size_t>(have - need));
    std::string iso = rpg_dt_parse(piece, kind, f, sep);
    if (iso.empty()) rpg_move_dt_invalid();
    if (kind == 0 && !rpg_date_fits(iso, dstFmt)) rpg_move_dt_range();
    dst.value = iso;
}

// Date/Time/Timestamp -> Date/Time/Timestamp: factor 1 must be blank, and
// the internal representation is format-independent here, so the seven
// allowed pairings are copies or field extractions rather than
// conversions. `dstFmt` still gates a date result, since its declared
// format is what decides whether the value is representable at all
// (Figure 287 moves *HIVAL into a *YMD date and gets error 114).
inline void rpg_move_dt(RpgDate& dst, const RpgDate& src, const std::string& dstFmt) {
    if (!rpg_date_fits(src.value, dstFmt)) rpg_move_dt_range();
    dst.value = src.value;
}
inline void rpg_move_dt(RpgDate& dst, const RpgTimestamp& src, const std::string& dstFmt) {
    std::string iso = src.value.substr(0, 10);
    if (!rpg_date_fits(iso, dstFmt)) rpg_move_dt_range();
    dst.value = iso;
}
inline void rpg_move_dt(RpgTime& dst, const RpgTime& src) { dst.value = src.value; }
inline void rpg_move_dt(RpgTime& dst, const RpgTimestamp& src) {
    dst.value = src.value.substr(11, 2) + ":" + src.value.substr(14, 2) + ":" + src.value.substr(17, 2);
}
inline void rpg_move_dt(RpgTimestamp& dst, const RpgTimestamp& src) { dst.value = src.value; }
// "When moving from a Date to a Timestamp field, the time and microsecond
// portion of the timestamp are unaffected."
inline void rpg_move_dt(RpgTimestamp& dst, const RpgDate& src) {
    dst.value = src.value + dst.value.substr(10);
}
// "When moving from a Time to a Timestamp field, the microseconds part of
// the timestamp is set to 000000. The date portion remains unaffected."
inline void rpg_move_dt(RpgTimestamp& dst, const RpgTime& src) {
    dst.value = dst.value.substr(0, 11) + src.value.substr(0, 2) + "." +
                src.value.substr(3, 2) + "." + src.value.substr(6, 2) + ".000000";
}

inline std::string rpg_all(const std::string& pattern, int len = 50) {
    if (pattern.empty()) return std::string(static_cast<size_t>(len > 0 ? len : 0), ' ');
    std::string result;
    while (static_cast<int>(result.size()) < len) {
        result += pattern;
    }
    return result.substr(0, len);
}

#include <vector>

// A literal or calculation passed for a CONST or VALUE parameter with
// OPTIONS(*OMIT), which the procedure receives as a pointer: the address of
// a temporary of the parameter's type, which lasts until the call returns.
template<typename T>
inline T* rpg_omit_tmp(T&& v) { return &v; }

// --- IN operator helpers ---
// x IN %LIST(...), an enum's constants, or an array: any collection, so an
// array (a std::array, or a varying one) works as the list does.
template<typename T, typename C>
inline bool rpg_in_list(const T& val, const C& list) {
    for (const auto& item : list) {
        if (rpg_eq(val, item)) return true;
    }
    return false;
}

template<typename T>
inline bool rpg_in_range(const T& val, const RpgRange<T>& range) {
    return rpg_ge(val, range.low) && rpg_le(val, range.high);
}

// %SCANR: the last match in the portion (see rpg_scan).
inline int rpg_scanr(const std::string& search, const std::string& source,
                     long long start = RPG_SCAN_FROM_START, long long length = RPG_SCAN_TO_END) {
    bool none;
    size_t end = rpg_scan_portion(source, start, length, none);
    if (none) return 0;
    if (search.size() > end - static_cast<size_t>(start - 1)) return 0;
    auto pos = source.rfind(search, end - search.size());
    return (pos == std::string::npos || pos < static_cast<size_t>(start - 1)) ? 0
                                                                           : static_cast<int>(pos) + 1;
}

// %EDITFLT — external float representation
inline std::string rpg_editflt(double val, bool four_byte = false) {
    return rpg_float_text(val, four_byte);
}

// %UNSH — unsigned integer with half-adjust (rounding)
inline unsigned int rpg_unsh(double val) {
    return static_cast<unsigned int>(std::round(val));
}

#endif // RPG_RUNTIME_H
