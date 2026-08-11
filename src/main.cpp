#include <climits>
#include <cstdio>
#include <cstring>
#include <cctype>
#include <fstream>
#include <iostream>
#include <regex>
#include <sstream>
#include <string>
#include <sys/stat.h>
#include <cstdlib>
#include "ast.h"
#include "codegen.h"
#include "conf.h"
#include "extdesc.h"

// ---------------------------------------------------------------------------
// Minimal .dspfd JSON loader for the WORKSTN pre-pass
// ---------------------------------------------------------------------------
static std::string dspfd_str(const std::string& src, const std::string& key) {
    // Find "key": "value" in the (pretty-printed) JSON
    std::string pat = "\"" + key + "\": \"";
    auto pos = src.find(pat);
    if (pos == std::string::npos) return "";
    pos += pat.size();
    auto end = src.find('"', pos);
    if (end == std::string::npos) return "";
    return src.substr(pos, end - pos);
}

static int dspfd_int(const std::string& src, const std::string& key, size_t fromPos = 0) {
    std::string pat = "\"" + key + "\": ";
    auto pos = src.find(pat, fromPos);
    if (pos == std::string::npos) return 0;
    pos += pat.size();
    bool neg = (pos < src.size() && src[pos] == '-');
    if (neg) pos++;
    int v = 0;
    while (pos < src.size() && isdigit((unsigned char)src[pos])) v = v * 10 + (src[pos++] - '0');
    return neg ? -v : v;
}

static rpg::DspfFileInfo loadDspfDesc(const std::string& path, const std::string& filename) {
    rpg::DspfFileInfo info;
    info.filename = filename;

    std::ifstream f(path);
    if (!f.is_open()) return info;
    std::ostringstream ss;
    ss << f.rdbuf();
    std::string src = ss.str();

    // Find each record block by scanning for "name": "RECNAME" patterns at record level
    // Simple approach: find all occurrences of \"name\" within records[] array
    size_t recsPos = src.find("\"records\":");
    if (recsPos == std::string::npos) return info;

    // Iterate over record objects between the outer "[" and "]"
    size_t arrOpen = src.find('[', recsPos);
    if (arrOpen == std::string::npos) return info;

    size_t pos = arrOpen + 1;
    while (pos < src.size()) {
        // Find next record object "{"
        size_t recOpen = src.find('{', pos);
        if (recOpen == std::string::npos) break;

        // Find matching "}"  — skip nested braces
        int depth = 0;
        size_t recClose = recOpen;
        for (size_t i = recOpen; i < src.size(); i++) {
            if (src[i] == '{') depth++;
            else if (src[i] == '}') { if (--depth == 0) { recClose = i; break; } }
        }
        if (recClose == recOpen) break;

        std::string recSrc = src.substr(recOpen, recClose - recOpen + 1);
        rpg::DspfRecInfo rec;
        rec.name = dspfd_str(recSrc, "name");
        if (rec.name.empty()) { pos = recClose + 1; continue; }

        // Find fields array within this record
        size_t fieldsPos = recSrc.find("\"fields\":");
        if (fieldsPos != std::string::npos) {
            size_t fArrOpen = recSrc.find('[', fieldsPos);
            size_t fPos = fArrOpen + 1;
            while (fPos < recSrc.size()) {
                size_t fOpen = recSrc.find('{', fPos);
                if (fOpen == std::string::npos) break;
                int fd = 0; size_t fClose = fOpen;
                for (size_t i = fOpen; i < recSrc.size(); i++) {
                    if (recSrc[i] == '{') fd++;
                    else if (recSrc[i] == '}') { if (--fd == 0) { fClose = i; break; } }
                }
                if (fClose == fOpen) break;
                std::string fSrc = recSrc.substr(fOpen, fClose - fOpen + 1);
                rpg::DspfFldInfo fld;
                fld.name  = dspfd_str(fSrc, "name");
                std::string type = dspfd_str(fSrc, "type");
                fld.dtype = type.empty() ? 'A' : (char)toupper((unsigned char)type[0]);
                fld.len   = dspfd_int(fSrc, "len");
                fld.dec   = dspfd_int(fSrc, "dec");
                std::string io = dspfd_str(fSrc, "io");
                fld.io    = io.empty() ? 'O' : (char)toupper((unsigned char)io[0]);
                if (fld.len == 0) fld.len = 1;
                if (!fld.name.empty()) rec.fields.push_back(fld);
                fPos = fClose + 1;
            }
        }

        info.recIdx[rec.name] = info.records.size();
        info.records.push_back(std::move(rec));
        pos = recClose + 1;
    }
    return info;
}

// Scan RPG source for DCL-F X WORKSTN and load their .dspfd descriptors
static std::map<std::string, rpg::DspfFileInfo>
queryDspfDescs(const std::string& src_text, const std::string& src_dir) {
    std::map<std::string, rpg::DspfFileInfo> result;
    // Case-insensitive scan for DCL-F <name> WORKSTN
    static const std::regex re(R"(DCL-F\s+([A-Za-z_][A-Za-z0-9_]*)\s+WORKSTN)",
                                std::regex_constants::icase);
    auto begin = std::sregex_iterator(src_text.begin(), src_text.end(), re);
    auto end   = std::sregex_iterator();
    for (auto it = begin; it != end; ++it) {
        std::string fname = (*it)[1].str();
        // Uppercase
        for (auto& c : fname) c = (char)toupper((unsigned char)c);
        if (result.count(fname)) continue;
        // Look for FNAME.dspfd in source directory
        std::string dspfdPath = src_dir + "/" + fname + ".dspfd";
        struct stat st;
        if (stat(dspfdPath.c_str(), &st) != 0) {
            // Also try lowercase
            std::string lower = fname;
            for (auto& c : lower) c = (char)tolower((unsigned char)c);
            dspfdPath = src_dir + "/" + lower + ".dspfd";
            if (stat(dspfdPath.c_str(), &st) != 0) continue;
        }
        result[fname] = loadDspfDesc(dspfdPath, fname);
    }
    return result;
}

#ifdef _WIN32
#  include <direct.h>
#  define rpgc_realpath(p,b) _fullpath(b, p, PATH_MAX)
#  define rpgc_mkdir(p)      _mkdir(p)
#else
#  define rpgc_realpath(p,b) realpath(p, b)
#  define rpgc_mkdir(p)      mkdir(p, 0755)
#endif

#ifndef RPGC_RUNTIME_DIR
#define RPGC_RUNTIME_DIR "/usr/local/share/rpgc/runtime"
#endif

#ifndef RPGC_VERSION
#define RPGC_VERSION "dev"
#endif

#ifdef _WIN32
   // MSYS2's CLANGARM64 toolchain (used to build rpgc.exe for Windows ARM64)
   // has no g++ at all — invoke whichever compiler actually built this
   // binary so the generated C++ is compiled with a toolchain that exists.
#  if defined(__clang__)
#    define RPGC_CXX     "clang++"
#  else
#    define RPGC_CXX     "g++"
#  endif
#  define RPGC_ODBC_FLAGS " -lodbc32"
#  define RPGC_DSPF_FLAGS " -lpdcurses"
#elif defined(__APPLE__)
#  define RPGC_CXX       "clang++"
#  define RPGC_ODBC_FLAGS " -I/opt/homebrew/include -L/opt/homebrew/lib -lodbc"
#  define RPGC_DSPF_FLAGS " -lncurses"
#else
#  define RPGC_CXX       "g++"
#  define RPGC_ODBC_FLAGS " -lodbc"
#  define RPGC_DSPF_FLAGS " -lncurses"
#endif

// Resolve which C++ compiler to invoke for the generated code. Prefer the
// one this rpgc binary was built with (RPGC_CXX) since it's guaranteed to
// exist in that build's own toolchain, but fall back to the other major
// compiler if that's what's actually on the user's PATH instead — e.g. on
// Windows, where MinGW GCC and LLVM/Clang are installed independently of
// whichever one happened to build rpgc.exe itself. RPGC_CXX_OVERRIDE (or
// the conventional CXX) lets the user force a specific compiler/path.
static std::string rpgc_resolve_cxx() {
    if (const char* env = std::getenv("RPGC_CXX_OVERRIDE")) return env;
    if (const char* env = std::getenv("CXX")) return env;

    auto on_path = [](const std::string& cxx) {
#ifdef _WIN32
        std::string cmd = "where " + cxx + " >nul 2>nul";
#else
        std::string cmd = "command -v " + cxx + " >/dev/null 2>&1";
#endif
        return system(cmd.c_str()) == 0;
    };

#if defined(__clang__)
    const char* other = "g++";
#else
    const char* other = "clang++";
#endif

    if (on_path(RPGC_CXX)) return RPGC_CXX;
    if (on_path(other))    return other;
    return RPGC_CXX; // neither found; let the real compile invocation surface the error
}

// Directory for scratch .cpp files generated during compilation.
// /tmp doesn't exist on Windows, so honor the platform's own temp-dir
// convention instead of assuming a Unix layout.
static std::string rpgc_temp_dir() {
#ifdef _WIN32
    const char* t = std::getenv("TEMP");
    if (!t) t = std::getenv("TMP");
    return t ? std::string(t) : std::string(".");
#else
    const char* t = std::getenv("TMPDIR");
    return t ? std::string(t) : std::string("/tmp");
#endif
}

extern FILE* yyin;
extern rpg::Program* get_parsed_program();
extern int get_parse_error_count();

int main(int argc, char* argv[]) {
    if (argc == 2 && (strcmp(argv[1], "-v") == 0 || strcmp(argv[1], "--version") == 0)) {
        std::cout << "rpgc " << RPGC_VERSION << "\n";
        return 0;
    }

    if (argc < 2) {
        std::cerr << "Usage: rpgc <input.rpgle> [-c] [-g] [-o output] [file.o ...]\n";
        std::cerr << "  -c           Compile to object file, do not link\n";
        std::cerr << "  -g           Compile with debug info (for GDB/LLDB/VS Code)\n";
        std::cerr << "  -o file      Output file\n";
        std::cerr << "  -v, --version  Print version and exit\n";
        return 1;
    }

    const char* input_file = nullptr;
    const char* output_file = nullptr;
    bool emit_only = false;
    bool keep_cpp = false;
    bool debug_mode = false;
    bool compile_only = false;
    std::vector<std::string> extra_objs;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-S") == 0) {
            emit_only = true;
        } else if (strcmp(argv[i], "-c") == 0) {
            compile_only = true;
        } else if (strcmp(argv[i], "-g") == 0) {
            debug_mode = true;
        } else if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
            output_file = argv[++i];
        } else if (strcmp(argv[i], "--keep-cpp") == 0) {
            keep_cpp = true;
        } else if (!input_file) {
            input_file = argv[i];
        } else {
            // Extra arguments after the source file: collect .o files for linking
            extra_objs.push_back(argv[i]);
        }
    }

    if (!input_file) {
        std::cerr << "Error: no input file specified.\n";
        return 1;
    }

    // Determine base name from input
    std::string base(input_file);
    auto dot = base.rfind('.');
    if (dot != std::string::npos) base = base.substr(0, dot);
    auto slash = base.rfind('/');
    if (slash != std::string::npos) base = base.substr(slash + 1);

    // Load rpgc.conf
    RpgConf conf = RpgConf::load();

    // Read source for pre-pass (extdesc query)
    std::string src_text;
    {
        std::ifstream src_f(input_file);
        if (!src_f) {
            std::cerr << "Error: cannot open " << input_file << "\n";
            return 1;
        }
        std::ostringstream ss;
        ss << src_f.rdbuf();
        src_text = ss.str();
    }

    // Determine source directory for .extdesc cache lookup
    std::string src_dir;
    {
        std::string inp(input_file);
        auto sl = inp.rfind('/');
        src_dir = (sl != std::string::npos) ? inp.substr(0, sl) : ".";
    }

    // Preemptive EXTDESC pass: query DB schema (or read cache)
    auto ext_descs = queryExternalDescs(src_text, src_dir, conf);

    // Preemptive DSPF pass: load .dspfd descriptor for each DCL-F WORKSTN file
    auto dspf_descs = queryDspfDescs(src_text, src_dir);

    yyin = fopen(input_file, "r");
    if (!yyin) {
        std::cerr << "Error: cannot open " << input_file << "\n";
        return 1;
    }

    rpg::Program* program = get_parsed_program();
    fclose(yyin);

    int errors = get_parse_error_count();
    if (errors > 0) {
        std::cerr << errors << " error(s) found. Compilation failed.\n";
        delete program;
        return 1;
    }

    // Resolve absolute path to source file for #line directives
    std::string abs_source;
    {
        char buf[PATH_MAX];
        if (rpgc_realpath(input_file, buf)) abs_source = buf;
        else abs_source = input_file;
    }

    bool has_rla = !ext_descs.empty();

    bool is_dspf = !dspf_descs.empty();

    rpg::CodeGen codegen;
    if (debug_mode) codegen.setDebugMode(true, abs_source);
    codegen.setExtFileDescs(std::move(ext_descs));
    codegen.setDspfDescs(std::move(dspf_descs));
    if (!conf.db_dsn.empty()) codegen.setConfDsn(conf.db_dsn);
    std::string cpp_code = codegen.generate(*program);

    if (emit_only) {
        // -S: emit C++ only
        std::string cpp_path = output_file ? output_file : base + ".cpp";
        std::ofstream out(cpp_path);
        if (!out) {
            std::cerr << "Error: cannot write to " << cpp_path << "\n";
            delete program;
            return 1;
        }
        out << cpp_code;
        delete program;
        return 0;
    }

    // Detect SQL/RLA source: .sqlrpgle extension or source contains DCL-F DISK
    std::string input_str(input_file);
    bool is_sql = false;
    if (input_str.size() >= 9) {
        std::string ext = input_str.substr(input_str.size() - 9);
        for (auto& c : ext) c = tolower(static_cast<unsigned char>(c));
        if (ext == ".sqlrpgle") is_sql = true;
    }
    // Also flag as SQL if any DCL-F DISK file was found (needs ODBC link)
    if (has_rla) is_sql = true;

    // Find runtime headers: check relative to binary, cwd, then install prefix
    auto dir_exists = [](const std::string& path) {
        struct stat st;
        return stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
    };

    std::string runtime_dir;
    // 1) Relative to the rpgc binary (e.g. ./runtime when run from source tree)
    std::string self(argv[0]);
    size_t last_slash = self.find_last_of("/\\");
    if (last_slash != std::string::npos) {
        std::string bin_dir = self.substr(0, last_slash);
        if (dir_exists(bin_dir + "/runtime"))
            runtime_dir = bin_dir + "/runtime";
    }
    // 2) Current working directory
    if (runtime_dir.empty() && dir_exists("runtime"))
        runtime_dir = "runtime";
    // 3) Installed location (compile-time default)
    if (runtime_dir.empty() && dir_exists(RPGC_RUNTIME_DIR))
        runtime_dir = RPGC_RUNTIME_DIR;

    if (runtime_dir.empty()) {
        std::cerr << "Error: cannot find rpgc runtime headers.\n"
                  << "Looked in: ./runtime, " << RPGC_RUNTIME_DIR << "\n";
        delete program;
        return 1;
    }

    if (compile_only) {
        // -c: transpile then compile to object file, do not link
        std::string obj_path = output_file ? output_file : base + ".o";
        std::string cpp_path = rpgc_temp_dir() + "/" + base + ".cpp";
        {
            std::ofstream out(cpp_path);
            if (!out) {
                std::cerr << "Error: cannot write to " << cpp_path << "\n";
                delete program;
                return 1;
            }
            out << cpp_code;
        }
        std::string cmd = rpgc_resolve_cxx() + " -std=c++17 -I" + runtime_dir + " -I" + src_dir +
                          " -c -o " + obj_path + " " + cpp_path;
        int rc = system(cmd.c_str());
        std::remove(cpp_path.c_str());
        delete program;
        return rc == 0 ? 0 : 1;
    }

    // Default: compile to executable
    std::string exe_path = output_file ? output_file : base;

    // Write C++ to temp file (or kept file)
    std::string cpp_path;
    if (keep_cpp) {
        cpp_path = base + ".cpp";
    } else {
        cpp_path = rpgc_temp_dir() + "/" + base + ".cpp";
    }

    {
        std::ofstream out(cpp_path);
        if (!out) {
            std::cerr << "Error: cannot write to " << cpp_path << "\n";
            delete program;
            return 1;
        }
        out << cpp_code;
    }

    std::string cmd = rpgc_resolve_cxx() + " -std=c++17 -I" + runtime_dir + " -I" + src_dir;
    if (debug_mode) {
        cmd += " -g -O0";
    }
    if (is_sql) {
        cmd += RPGC_ODBC_FLAGS;
    }
    if (is_dspf) {
        cmd += RPGC_DSPF_FLAGS;
    }
    cmd += " -o " + exe_path + " " + cpp_path;
    for (const auto& obj : extra_objs) cmd += " " + obj;
    int rc = system(cmd.c_str());

    if (!keep_cpp) {
        std::remove(cpp_path.c_str());
    }

    if (rc != 0) {
        std::cerr << "C++ compilation failed.\n";
        delete program;
        return 1;
    }

    // Generate .vscode/launch.json for VS Code debugging
    if (debug_mode) {
        // Resolve absolute path to the output binary
        std::string abs_exe;
        {
            char buf[PATH_MAX];
            if (rpgc_realpath(exe_path.c_str(), buf)) abs_exe = buf;
            else abs_exe = exe_path;
        }

        // Create .vscode directory if needed
        struct stat st;
        if (stat(".vscode", &st) != 0) {
            rpgc_mkdir(".vscode");
        }

        // Choose debugger type based on platform
#if defined(_WIN32)
        std::string dbg_type = "cppvsdbg";
        std::string dbg_ext  = "ms-vscode.cpptools";
        std::string dbg_ext_name = "C/C++ (ms-vscode.cpptools)";
#else
        std::string dbg_type = "lldb";
        std::string dbg_ext  = "vadimcn.vscode-lldb";
        std::string dbg_ext_name = "CodeLLDB (vadimcn.vscode-lldb)";
#endif

        std::ofstream launch(".vscode/launch.json");
        if (launch) {
            launch << "{\n";
            launch << "    \"version\": \"0.2.0\",\n";
            launch << "    \"configurations\": [\n";
            launch << "        {\n";
            launch << "            \"type\": \"" << dbg_type << "\",\n";
            launch << "            \"request\": \"launch\",\n";
            launch << "            \"name\": \"Debug " << base << "\",\n";
            launch << "            \"program\": \"" << abs_exe << "\",\n";
            launch << "            \"args\": [],\n";
            launch << "            \"cwd\": \"${workspaceFolder}\"\n";
            launch << "        }\n";
            launch << "    ]\n";
            launch << "}\n";
            std::cerr << "Debug info written to .vscode/launch.json\n";
            std::cerr << "Install the " << dbg_ext_name << " extension in VS Code, then press F5 to debug.\n";
        }
    }

    delete program;
    return 0;
}
