#ifndef RPG_CALL_RUNTIME_H
#define RPG_CALL_RUNTIME_H

// Program calls (EXTPGM and CALL), resolved when the program runs, as on
// IBM i. A called program is a shared library -- NAME.so, NAME.dylib or
// NAME.dll (or with a lib prefix) -- exporting a C function named after
// the program that takes one pointer per parameter:
//
//     int NAME(void* parm1, void* parm2, ...);
//
// Each parameter is passed by reference in IBM i's own format, not as
// this compiler's C++ objects, so a called program need not be RPG: a C
// function or a GnuCOBOL module of that shape works, and can call RPG.
//     CHAR(n)          n bytes, blank padded           (COBOL PIC X(n))
//     VARCHAR(n)       2-byte length, then n bytes
//     INT/UNS          native binary integer            (COBOL COMP-5)
//     PACKED(p:s)      p/2+1 bytes packed decimal       (COBOL COMP-3)
//     ZONED(p:s)       p digits; a negative value has its sign in the
//                      last digit, as GnuCOBOL writes it (COBOL DISPLAY)
//     FLOAT            native float or double
//     IND              '1' or '0'
//     DATE/TIME/TIMESTAMP   their *ISO character form
//     data structure   its bytes, as the data structure is a character
//                      value (see rpg_img_* in rpg_runtime.h)
// The function returns 0, or a negative value when the program ended in
// error; the caller then gets status 202, or 231 for -2, which an rpgc
// program returns when it ended with a halt indicator on. A program that
// can't be found is status 211.
//
// The library is looked for in the calling program's own directory, then
// in each directory on PATH, then wherever the system loader looks
// (LD_LIBRARY_PATH, DYLD_LIBRARY_PATH, ...). It is loaded once, on the
// first call.

#ifdef _WIN32
#  ifndef WIN32_LEAN_AND_MEAN
#    define WIN32_LEAN_AND_MEAN
#  endif
#  ifndef NOUSER
#    define NOUSER
#  endif
#  ifndef NOGDI
#    define NOGDI
#  endif
#  include <windows.h>
// Field names a program may use freely; see rpg_sql_runtime.h.
#  undef IN
#  undef OUT
#  undef OPTIONAL
#  undef DELETE
#  undef CONST
#  undef ERROR
#  define RPG_PROGRAM_EXPORT extern "C" __declspec(dllexport)
#else
#  include <dlfcn.h>
#  include <unistd.h>
#  ifdef __APPLE__
#    include <mach-o/dyld.h>
#  endif
#  define RPG_PROGRAM_EXPORT extern "C" __attribute__((visibility("default")))
#endif
#include "rpg_runtime.h"
#include <climits>
#include <cstdint>
#include <cstring>
#include <map>
#include <string>
#include <utility>
#include <vector>

// --- Parameters in IBM i's formats -------------------------------------

inline std::string rpg_abi_char(const std::string& v, int len) { return rpg_img_char(v, len); }

inline std::string rpg_abi_varchar(const std::string& v, int len) {
    size_t n = std::min(v.size(), static_cast<size_t>(len < 0 ? 0 : len));
    uint16_t n16 = static_cast<uint16_t>(n);
    std::string s(2, '\0');
    std::memcpy(&s[0], &n16, 2);
    s += v.substr(0, n);
    s.resize(static_cast<size_t>(len) + 2, ' ');
    return s;
}

inline std::string rpg_abi_zoned(double v, int digits, int dec) {
    std::string d = rpg_num_digits(v, digits, dec);
    if (v < 0 && !d.empty()) d.back() = static_cast<char>(0x70 | (d.back() - '0'));
    return d;
}

inline std::string rpg_abi_packed(double v, int digits, int dec) {
    std::string s = rpg_img_packed(v, digits, dec);
    // COBOL's COMP-3 writes C for positive, which IBM also accepts.
    if (!s.empty() && v >= 0) s.back() = static_cast<char>((s.back() & 0xF0) | 0x0C);
    return s;
}

inline std::string rpg_abi_int(long long v, int bytes) {
    std::string s(static_cast<size_t>(bytes), '\0');
    switch (bytes) {
        case 1: { int8_t  x = static_cast<int8_t>(v);  std::memcpy(&s[0], &x, 1); break; }
        case 2: { int16_t x = static_cast<int16_t>(v); std::memcpy(&s[0], &x, 2); break; }
        case 4: { int32_t x = static_cast<int32_t>(v); std::memcpy(&s[0], &x, 4); break; }
        default: { int64_t x = static_cast<int64_t>(v); s.resize(8); std::memcpy(&s[0], &x, 8); }
    }
    return s;
}

inline std::string rpg_abi_float(double v, int bytes) {
    std::string s(static_cast<size_t>(bytes == 4 ? 4 : 8), '\0');
    if (bytes == 4) { float f = static_cast<float>(v); std::memcpy(&s[0], &f, 4); }
    else std::memcpy(&s[0], &v, 8);
    return s;
}

inline std::string rpg_abi_ind(bool v) { return std::string(1, v ? '1' : '0'); }

inline std::string rpg_abi_ptr(void* p) {
    std::string s(sizeof(void*), '\0');
    std::memcpy(&s[0], &p, sizeof(void*));
    return s;
}

inline std::string rpg_abi_get_char(const char* p, int len) {
    return std::string(p, static_cast<size_t>(len < 0 ? 0 : len));
}

inline std::string rpg_abi_get_varchar(const char* p, int len) {
    uint16_t n = 0;
    std::memcpy(&n, p, 2);
    if (n > len) n = static_cast<uint16_t>(len);
    return std::string(p + 2, n);
}

// The sign can be in the last digit (0x70-0x79, or '}' and 'J'-'R') or a
// leading '-'. A blank counts as 0.
inline double rpg_abi_get_zoned(const char* p, int digits, int dec) {
    std::string d;
    bool neg = false;
    for (int i = 0; i < digits; i++) {
        unsigned char c = static_cast<unsigned char>(p[i]);
        if (c == '-' && i == 0) { neg = true; d += '0'; continue; }
        if (i == digits - 1) {
            if (c >= 0x70 && c <= 0x79) { neg = true; c = static_cast<unsigned char>('0' + (c & 0x0F)); }
            else if (c == '}') { neg = true; c = '0'; }
            else if (c >= 'J' && c <= 'R') { neg = true; c = static_cast<unsigned char>('1' + (c - 'J')); }
            else if (c == '{') c = '0';
            else if (c >= 'A' && c <= 'I') c = static_cast<unsigned char>('1' + (c - 'A'));
        }
        d += (c >= '0' && c <= '9') ? static_cast<char>(c) : '0';
    }
    return rpg_digits_num(d, dec, neg);
}

inline double rpg_abi_get_packed(const char* p, int digits, int dec) {
    int bytes = digits / 2 + 1;
    std::string d;
    for (int i = 0; i < bytes; i++) {
        unsigned char b = static_cast<unsigned char>(p[i]);
        d += static_cast<char>('0' + ((b >> 4) % 10));
        if (i < bytes - 1) d += static_cast<char>('0' + ((b & 0x0F) % 10));
    }
    unsigned char sign = static_cast<unsigned char>(p[bytes - 1]) & 0x0F;
    return rpg_digits_num(d, dec, sign == 0x0D || sign == 0x0B);
}

inline long long rpg_abi_get_int(const char* p, int bytes) {
    switch (bytes) {
        case 1: { int8_t  x; std::memcpy(&x, p, 1); return x; }
        case 2: { int16_t x; std::memcpy(&x, p, 2); return x; }
        case 4: { int32_t x; std::memcpy(&x, p, 4); return x; }
        default: { int64_t x; std::memcpy(&x, p, 8); return x; }
    }
}

inline unsigned long long rpg_abi_get_uns(const char* p, int bytes) {
    switch (bytes) {
        case 1: { uint8_t  x; std::memcpy(&x, p, 1); return x; }
        case 2: { uint16_t x; std::memcpy(&x, p, 2); return x; }
        case 4: { uint32_t x; std::memcpy(&x, p, 4); return x; }
        default: { uint64_t x; std::memcpy(&x, p, 8); return x; }
    }
}

inline double rpg_abi_get_float(const char* p, int bytes) {
    if (bytes == 4) { float f; std::memcpy(&f, p, 4); return f; }
    double d; std::memcpy(&d, p, 8); return d;
}

inline bool rpg_abi_get_ind(const char* p) { return p[0] == '1'; }

inline void* rpg_abi_get_ptr(const char* p) {
    void* v; std::memcpy(&v, p, sizeof(void*)); return v;
}

// Writes a parameter's new value back through the caller's pointer.
inline void rpg_abi_put(void* p, const std::string& bytes) {
    if (p) std::memcpy(p, bytes.data(), bytes.size());
}

// --- Finding and calling a program ---------------------------------------

inline std::string rpg__exe_dir() {
    std::string path;
#ifdef _WIN32
    char buf[MAX_PATH];
    DWORD n = GetModuleFileNameA(nullptr, buf, MAX_PATH);
    if (n > 0 && n < MAX_PATH) path.assign(buf, n);
#elif defined(__APPLE__)
    char buf[PATH_MAX];
    uint32_t size = sizeof(buf);
    if (_NSGetExecutablePath(buf, &size) == 0) path = buf;
#else
    char buf[PATH_MAX];
    ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
    if (n > 0) path.assign(buf, static_cast<size_t>(n));
#endif
    size_t slash = path.find_last_of("/\\");
    return slash == std::string::npos ? std::string() : path.substr(0, slash);
}

inline void* rpg__open_library(const std::string& path) {
#ifdef _WIN32
    return reinterpret_cast<void*>(LoadLibraryA(path.c_str()));
#else
    return dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
#endif
}

inline void* rpg__find_symbol(void* lib, const std::string& name) {
#ifdef _WIN32
    return reinterpret_cast<void*>(GetProcAddress(reinterpret_cast<HMODULE>(lib), name.c_str()));
#else
    return dlsym(lib, name.c_str());
#endif
}

// The program's entry point, loaded on its first call and kept.
inline void* rpg_find_program(const std::string& name) {
    static std::map<std::string, void*> loaded;
    std::string key = rpg_trim(name);
    for (auto& c : key) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    auto it = loaded.find(key);
    if (it != loaded.end()) return it->second;

    std::string lower = key;
    for (auto& c : lower) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
#ifdef _WIN32
    const char* ext = ".dll";
    const char sep = ';';
#elif defined(__APPLE__)
    const char* ext = ".dylib";
    const char sep = ':';
#else
    const char* ext = ".so";
    const char sep = ':';
#endif
    std::vector<std::string> files;
    for (const std::string& n : {key, lower}) {
        files.push_back(n + ext);
        files.push_back("lib" + n + ext);
    }
    std::vector<std::string> dirs;
    std::string self = rpg__exe_dir();
    if (!self.empty()) dirs.push_back(self);
    if (const char* path = std::getenv("PATH")) {
        std::string p = path;
        size_t start = 0;
        while (start <= p.size()) {
            size_t end = p.find(sep, start);
            if (end == std::string::npos) end = p.size();
            if (end > start) dirs.push_back(p.substr(start, end - start));
            start = end + 1;
        }
    }
    dirs.push_back("");   // the system loader's own search
    for (const auto& dir : dirs) {
        for (const auto& file : files) {
            std::string path = dir.empty() ? file : dir + "/" + file;
            void* lib = rpg__open_library(path);
            if (!lib) continue;
            for (const std::string& sym : {key, lower, rpg_trim(name)}) {
                if (void* fn = rpg__find_symbol(lib, sym)) {
                    loaded[key] = fn;
                    return fn;
                }
            }
        }
    }
    rpg_raise(211, "RNX0211: Program " + key + " was not found: no " + key + ext +
              " exporting " + key + " in the program's directory, on PATH or on the "
              "library path.");
}

template <size_t... I>
inline int rpg__invoke(void* fn, void** a, std::index_sequence<I...>) {
    using Fn = int (*)(decltype((void)I, static_cast<void*>(nullptr))...);
    Fn f;
    std::memcpy(&f, &fn, sizeof f);
    return f(a[I]...);
}

template <size_t N = 0>
inline int rpg__invoke_n(size_t n, void* fn, void** a) {
    if (n == N) return rpg__invoke(fn, a, std::make_index_sequence<N>{});
    if constexpr (N < 64) return rpg__invoke_n<N + 1>(n, fn, a);
    else rpg_raise(202, "RNX0202: A program call passes at most 64 parameters here.");
}

// Calls the program with one buffer per parameter, each in its raw
// format; the program may change them in place.
inline void rpg_call_program(const std::string& name, std::vector<std::string>& parms) {
    void* fn = rpg_find_program(name);
    std::vector<void*> ptrs;
    for (auto& p : parms) ptrs.push_back(p.empty() ? nullptr : static_cast<void*>(&p[0]));
    std::cout.flush();
    int rc = rpg__invoke_n(ptrs.size(), fn, ptrs.data());
    if (rc < 0) {
        std::string key = rpg_trim(name);
        for (auto& c : key) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        if (rc == -2)
            rpg_raise(231, "RNX0231: The called program " + key + " returned with a halt indicator on.");
        rpg_raise(202, "RNX0202: The call to program " + key + " ended in error.");
    }
}

// A called program built by rpgc: whether it ended with a halt indicator
// on, which its caller sees as status 231. The indicators are reset for
// the next call.
inline bool rpg_called_program_failed() {
    bool failed = false;
    for (int i = 1; i <= 9; i++) {
        if (rpg_halt_indicators()[i]) failed = true;
        rpg_halt_indicators()[i] = false;
    }
    return failed;
}

#endif // RPG_CALL_RUNTIME_H
