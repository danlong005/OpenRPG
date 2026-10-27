%{
#include <climits>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <string>
#include "ast.h"
#include "keyword_list.h"
#include "parser.h"
#include "free_bridge.h"
#include "cond_expr.h"

// One statement per line: IBM i rejects anything but a comment after a
// statement's semicolon on the same line (RNF5508), in **FREE source as in
// free-form lines of fixed-format source. g_semi_line is the line of the
// last semicolon; every token is checked against it before its rule runs.
// Text the fixed-format transpiler generates is exempt: it is not the
// user's layout.
int g_semi_line = -1;
static void check_one_statement_per_line() {
    extern int yylineno;
    extern char* yytext;
    if (g_semi_line != yylineno || g_allow_fixed_only_stmts) return;
    char c = yytext[0];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') return;
    if (c == '/' && (yytext[1] == '/' || yytext[1] == '*')) return;
    g_semi_line = -1;
    report_semantic_error(yylineno, "Only one statement is allowed on a line: nothing but a "
        "comment may follow the semicolon ending a statement (IBM: RNF5508)");
}
// Text inside a block comment is not checked: it is all comment.
#define YY_USER_ACTION if (YY_START != BLOCKCMT) check_one_statement_per_line();
static int block_comment_line = 0;

static char* process_rpg_string(const char* text) {
    size_t len = strlen(text);
    char* result = (char*)malloc(len);
    size_t j = 0;
    for (size_t i = 1; i < len - 1; i++) {
        if (text[i] == '\'' && i + 1 < len - 1 && text[i+1] == '\'') {
            result[j++] = '\'';
            i++;
        } else {
            result[j++] = text[i];
        }
    }
    result[j] = '\0';
    return result;
}

// Convert X'hex...' or x'hex...' literal to a byte string.
static char* process_hex_string(const char* text) {
    // text is like X'0A0D' — skip leading X/' and trailing '
    const char* p = text + 2; // skip X'
    size_t hex_len = strlen(p);
    if (hex_len > 0 && p[hex_len - 1] == '\'') hex_len--;
    size_t bytes = hex_len / 2;
    char* result = (char*)malloc(bytes + 1);
    for (size_t i = 0; i < bytes; i++) {
        unsigned int val = 0;
        char hi = p[i * 2], lo = p[i * 2 + 1];
        if (hi >= '0' && hi <= '9') val = (hi - '0') << 4;
        else val = (toupper((unsigned char)hi) - 'A' + 10) << 4;
        if (lo >= '0' && lo <= '9') val |= (lo - '0');
        else val |= (toupper((unsigned char)lo) - 'A' + 10);
        result[i] = (char)val;
    }
    result[bytes] = '\0';
    // A NUL byte would end the C string here, and everything from it on
    // was lost (X'C100' became 'A'). Pass such a literal as its hex digits
    // behind a marker instead; rpg_decode_lexed_string (ast.h) restores it.
    if (strlen(result) != bytes) {
        free(result);
        std::string enc = std::string(rpg::RPG_HEX_NUL_MARKER) + std::string(p, bytes * 2);
        return strdup(enc.c_str());
    }
    return result;
}

static char* strdup_upper(const char* text) {
    char* result = strdup(text);
    for (char* p = result; *p; p++) {
        *p = toupper((unsigned char)*p);
    }
    return result;
}

// A copied member is read as fixed-format unless its own first line is
// **FREE, whatever the including source is (as on IBM i). In a fixed-format
// member, code sits in positions 8-80: position 7 holds only a directive's
// '/' or a comment's '*', and 1-6 nothing. A member that is neither **FREE
// nor laid out that way is misread by IBM i, which reports its lines as out
// of sequence (RNF0257); this compiler reads it as free-form, so it says so
// instead. Reported once per member, at the /COPY line.
static void check_copy_member_format(const char* filename, int copy_line) {
    FILE* f = fopen(filename, "r");
    if (!f) return;
    char buf[1024];
    int n = 0;
    bool first = true;
    while (fgets(buf, sizeof buf, f)) {
        n++;
        std::string l(buf);
        while (!l.empty() && (l.back() == '\n' || l.back() == '\r')) l.pop_back();
        size_t i = l.find_first_not_of(" \t");
        if (i == std::string::npos) continue;
        if (first) {
            first = false;
            std::string u = l.substr(i, 6);
            for (auto& c : u) c = (char)toupper((unsigned char)c);
            if (i == 0 && u == "**FREE") break;
        }
        if (i < 6 || (i == 6 && l[i] != '/' && l[i] != '*')) {
            report_semantic_error(copy_line, std::string("/COPY ") + filename + ": the member "
                "has no **FREE on its first line, so it is fixed-format, and its line " +
                std::to_string(n) + " starts before position 8. Add **FREE as its first line, "
                "or keep its code in positions 8-80 (IBM: RNF0257)");
            break;
        }
    }
    fclose(f);
}

// Buffer stack for /COPY and /INCLUDE
#define MAX_INCLUDE_DEPTH 10
static YY_BUFFER_STATE include_stack[MAX_INCLUDE_DEPTH];
static int include_stack_ptr = 0;

// An interpolated string, f'I have {n} apples' (an OpenRPG extension), is
// rewritten as the concatenation it stands for, ('I have ' + %CHAR((n)) +
// ' apples'), and that text is read in its place -- pushed like a /COPY
// member, so the parser sees ordinary tokens. text is the literal between
// its quotes, with '' still doubled. {{ and }} are a brace.
static std::string desugar_fstring(const std::string& text, int line) {
    std::vector<std::string> parts;
    std::string lit;
    auto flush = [&]() {
        if (lit.empty()) return;
        parts.push_back("'" + lit + "'");   // its quotes are still doubled
        lit.clear();
    };
    for (size_t i = 0; i < text.size(); i++) {
        char c = text[i];
        if (c == '{' && i + 1 < text.size() && text[i + 1] == '{') { lit += '{'; i++; continue; }
        if (c == '}' && i + 1 < text.size() && text[i + 1] == '}') { lit += '}'; i++; continue; }
        if (c == '}') {
            report_semantic_error(line, "A } in an interpolated string closes no {; write }} for a brace");
            continue;
        }
        if (c != '{') { lit += c; continue; }
        // The expression runs to the matching }, skipping any string in it
        // (written with doubled quotes, as inside any literal).
        size_t j = i + 1;
        bool inStr = false;
        while (j < text.size() && (inStr || text[j] != '}')) {
            if (text[j] == '\'' && j + 1 < text.size() && text[j + 1] == '\'') { inStr = !inStr; j += 2; continue; }
            j++;
        }
        if (j >= text.size()) {
            report_semantic_error(line, "A { in an interpolated string has no } to close it; write {{ for a brace");
            break;
        }
        std::string expr = text.substr(i + 1, j - i - 1);
        // Inside the literal a quote is doubled; in the expression it is one.
        std::string e;
        for (size_t k = 0; k < expr.size(); k++) {
            e += expr[k];
            if (expr[k] == '\'' && k + 1 < expr.size() && expr[k + 1] == '\'') k++;
        }
        i = j;
        if (e.find_first_not_of(" \t\r\n") == std::string::npos) {
            report_semantic_error(line, "An interpolated string has an empty {}");
            continue;
        }
        flush();
        parts.push_back("%CHAR((" + e + "))");
    }
    flush();
    if (parts.empty()) return "''";
    std::string r = "(";
    for (size_t k = 0; k < parts.size(); k++) r += (k ? " + " : "") + parts[k];
    return r + ")";
}

// Conditional compilation
#include <set>
// *OPENRPG is predefined, as IBM's compiler predefines *ILERPG, so one source
// can hold lines only rpgc should see (/IF DEFINED(*OPENRPG)). A /DEFINE name
// can't start with '*', so user code can't collide with it.
static std::set<std::string> cond_defines = {"*OPENRPG"};
#define MAX_COND_DEPTH 20
static bool cond_active[MAX_COND_DEPTH]; // is this level active?
static bool cond_done[MAX_COND_DEPTH];   // has any branch been taken?
static int cond_depth = 0;

static bool cond_is_active() {
    // Active if ALL levels in the stack are active
    for (int i = 1; i <= cond_depth; i++) {
        if (!cond_active[i]) return false;
    }
    return true;
}

static std::string cond_extract_symbol(const char* text) {
    // Extract symbol from "DEFINED(SYMBOL)" pattern
    const char* p = text;
    while (*p && *p != '(') p++;
    if (*p == '(') p++;
    std::string sym;
    while (*p && *p != ')' && *p != ' ' && *p != '\t') {
        sym += toupper(*p);
        p++;
    }
    return sym;
}

static std::string cond_toupper(const std::string& s) {
    std::string r = s;
    for (auto& c : r) c = toupper(c);
    return r;
}

// SQL text buffer for EXEC SQL
static std::string sql_buffer;

// CTL-OPT keyword extraction helpers
char ctlopt_main_proc[256] = {0};
char ctlopt_datfmt[64] = {0};
char ctlopt_timfmt[64] = {0};
bool ctlopt_nomain = false;
bool ctlopt_debug_dump = false;
bool ctlopt_nolenchk = false;

// Thin wrapper over the generic rpg::parseKeywordList() (keyword_list.h)
// — shared with H-spec's fixed-format keyword-list content, which is the
// same "KEYWORD(value)..." vocabulary without CTL-OPT's own wrapper. Only
// 4 keys are semantically meaningful here (see TODO.md's "CTL-OPT
// Keywords (all accepted/ignored)" list for the rest); values are stored
// uppercased, matching this function's pre-existing behavior.
static void parse_ctlopt(const char* text) {
    ctlopt_nomain = false;
    ctlopt_main_proc[0] = '\0';
    ctlopt_datfmt[0] = '\0';
    ctlopt_timfmt[0] = '\0';

    ctlopt_debug_dump = false;
    ctlopt_nolenchk = false;
    auto kw = rpg::parseKeywordList(text);
    // OPTION(*NOLENCHK), an OpenRPG extension: a %SUBST length that runs
    // past the end of the data gives the rest of it, not status 100.
    auto opt = kw.find("OPTION");
    if (opt != kw.end()) {
        std::string v = opt->second;
        for (auto& c : v) c = (char)toupper((unsigned char)c);
        ctlopt_nolenchk = v.find("*NOLENCHK") != std::string::npos;
    }
    if (kw.count("NOMAIN")) ctlopt_nomain = true;
    // DEBUG, DEBUG(*YES) or DEBUG(*DUMP ...): DUMP operations write a dump.
    auto dbg = kw.find("DEBUG");
    if (dbg != kw.end()) {
        std::string v = dbg->second;
        for (auto& c : v) c = (char)toupper((unsigned char)c);
        ctlopt_debug_dump = v.empty() || v.find("*YES") != std::string::npos ||
                            v.find("*DUMP") != std::string::npos;
    }

    auto setUpper = [](char* dst, size_t dstSize, const std::string& val) {
        std::string upper = val;
        for (auto& c : upper) c = (char)toupper((unsigned char)c);
        strncpy(dst, upper.c_str(), dstSize - 1);
    };
    auto it = kw.find("MAIN");
    if (it != kw.end()) setUpper(ctlopt_main_proc, sizeof(ctlopt_main_proc), it->second);
    it = kw.find("DATFMT");
    if (it != kw.end()) setUpper(ctlopt_datfmt, sizeof(ctlopt_datfmt), it->second);
    it = kw.find("TIMFMT");
    if (it != kw.end()) setUpper(ctlopt_timfmt, sizeof(ctlopt_timfmt), it->second);
}
%}

%option noyywrap
%option case-insensitive
%option yylineno

%x SKIPPING
%x SQL
%x PI_NAME
%x BLOCKCMT

%%

^"**CTDATA".*       {
    /* Compile-time data starts here and runs to the end of the source. It
       is not RPG: main.cpp reads it from the source text (see ctdata in
       main.cpp), so the scanner stops. */
    yyterminate();
}
"**FREE"            {
    /* **FREE is a FILE-level format declaration, not a statement. A /COPY
       member is its own source file and declares its own format, exactly as
       on IBM i -- a copy member included into a **FREE source is still read
       as fixed-format unless it says **FREE itself. So consume the directive
       inside an include rather than handing the grammar a token it only
       accepts at the very start of the program. */
    if (include_stack_ptr > 0) { /* consumed */ }
    else return KW_FREE;
}

 /* EXEC SQL: switch to SQL mode and capture text until semicolon. The
    statement often starts on the next line, so a line break may follow
    EXEC SQL as blanks do -- but EXEC and SQL themselves share a line, as
    IBM i requires (EXEC alone on a line is RNF7030 there). */
[Ee][Xx][Ee][Cc][ \t]+[Ss][Qq][Ll][ \t\r\n]+ {
    sql_buffer.clear();
    BEGIN(SQL);
}

[Ee][Xx][Ee][Cc][ \t]*\r?\n[ \t\r\n]*[Ss][Qq][Ll][ \t\r\n]+ {
    int exec_line = yylineno;
    for (const char* c = yytext; *c; c++) if (*c == '\n') exec_line--;
    report_semantic_error(exec_line, "EXEC and SQL must be on the same line: EXEC alone "
        "is read as a name, which is not defined (IBM: RNF7030)");
    sql_buffer.clear();
    BEGIN(SQL);
}

<SQL>[^;]+ {
    sql_buffer.append(yytext);
}

<SQL>";" {
    BEGIN(INITIAL);
    /* Trim leading/trailing whitespace from captured SQL */
    size_t start = sql_buffer.find_first_not_of(" \t\r\n");
    size_t end = sql_buffer.find_last_not_of(" \t\r\n");
    if (start != std::string::npos) {
        yylval.sval = strdup(sql_buffer.substr(start, end - start + 1).c_str());
    } else {
        yylval.sval = strdup("");
    }
    return EXEC_SQL_TEXT;
}

"CTL-OPT"[^;]*";"  { parse_ctlopt(yytext); return KW_CTLOPT; }
"DCL-F"             { return KW_DCL_F; }
"DCL-S"             { return KW_DCL_S; }
"DCL-C"             { return KW_DCL_C; }
"DCL-ENUM"          { return KW_DCL_ENUM; }
"END-ENUM"          { return KW_END_ENUM; }
"CHAR"              { return KW_CHAR; }
"VARCHAR"           { return KW_VARCHAR; }
"INT"               { return KW_INT; }
"PACKED"            { return KW_PACKED; }
"ZONED"             { return KW_ZONED; }
"CONST"             { return KW_CONST; }
"DATE"              { return KW_DATE; }
"TIME"              { return KW_TIME; }
"TIMESTAMP"         { return KW_TIMESTAMP; }
"IND"               { return KW_IND; }
"POINTER"           { return KW_POINTER; }
"DISK"              { return KW_DISK; }
"PRINTER"           { return KW_PRINTER; }
"WORKSTN"           { return KW_WORKSTN; }
"USAGE"             { return KW_USAGE; }
"KEYED"             { return KW_KEYED; }
"EXTDESC"           { return KW_EXTDESC; }
"USROPN"            { return KW_USROPN; }
"EXTFILE"           { return KW_EXTFILE; }
"READE("[EHMNRP]+")" {
    char *p = strchr(yytext, '(') + 1;
    char ext[16] = {0}; int i = 0;
    while (*p && *p != ')') ext[i++] = (char)toupper((unsigned char)*p++);
    yylval.sval = strdup(ext);
    return KW_READE_EXT;
}
"READE"             { return KW_READE; }
"READPE("[EHMNRP]+")" {
    char *p = strchr(yytext, '(') + 1;
    char ext[16] = {0}; int i = 0;
    while (*p && *p != ')') ext[i++] = (char)toupper((unsigned char)*p++);
    yylval.sval = strdup(ext);
    return KW_READPE_EXT;
}
"READPE"            { return KW_READPE; }
"READP("[EHMNRP]+")" {
    char *p = strchr(yytext, '(') + 1;
    char ext[16] = {0}; int i = 0;
    while (*p && *p != ')') ext[i++] = (char)toupper((unsigned char)*p++);
    yylval.sval = strdup(ext);
    return KW_READP_EXT;
}
"READP"             { return KW_READP; }
"READ("[EHMNRP]+")" {
    char *p = strchr(yytext, '(') + 1;
    char ext[16] = {0}; int i = 0;
    while (*p && *p != ')') ext[i++] = (char)toupper((unsigned char)*p++);
    yylval.sval = strdup(ext);
    return KW_READ_EXT;
}
"EXFMT"             { return KW_EXFMT; }
"READC"             { return KW_READC; }
"READ"              { return KW_READ; }
"CHAIN("[EHMNRP]+")" {
    char *p = strchr(yytext, '(') + 1;
    char ext[16] = {0}; int i = 0;
    while (*p && *p != ')') ext[i++] = (char)toupper((unsigned char)*p++);
    yylval.sval = strdup(ext);
    return KW_CHAIN_EXT;
}
"CHAIN"             { return KW_CHAIN; }
"WRITE("[EHMNRP]+")" {
    char *p = strchr(yytext, '(') + 1;
    char ext[16] = {0}; int i = 0;
    while (*p && *p != ')') ext[i++] = (char)toupper((unsigned char)*p++);
    yylval.sval = strdup(ext);
    return KW_WRITE_EXT;
}
"WRITE"             { return KW_WRITE; }
"EXCEPT"            { return KW_EXCEPT; }
"UPDATE("[EHMNRP]+")" {
    char *p = strchr(yytext, '(') + 1;
    char ext[16] = {0}; int i = 0;
    while (*p && *p != ')') ext[i++] = (char)toupper((unsigned char)*p++);
    yylval.sval = strdup(ext);
    return KW_UPDATE_EXT;
}
"UPDATE"            { return KW_UPDATE; }
"DELETE("[EHMNRP]+")" {
    char *p = strchr(yytext, '(') + 1;
    char ext[16] = {0}; int i = 0;
    while (*p && *p != ')') ext[i++] = (char)toupper((unsigned char)*p++);
    yylval.sval = strdup(ext);
    return KW_DELETE_EXT;
}
"DELETE"            { return KW_DELETE; }
"SETLL"             { return KW_SETLL; }
"SETGT"             { return KW_SETGT; }
"TYPE"              { return KW_TYPE; }
"INZ"               { return KW_INZ; }
"DSPLY"             { return KW_DSPLY; }
"EVAL-CORR"         { return KW_EVAL_CORR; }
"XML-INTO"          { return KW_XML_INTO; }
"DATA-INTO"         { return KW_DATA_INTO; }
"DATA-GEN"          { return KW_DATA_GEN; }
"SND-MSG"           { return KW_SND_MSG; }
"EVALR("[EHMNRP]+")" {
    char *p = strchr(yytext, '(') + 1;
    char ext[16] = {0}; int i = 0;
    while (*p && *p != ')') ext[i++] = (char)toupper((unsigned char)*p++);
    yylval.sval = strdup(ext);
    return KW_EVALR_EXT;
}
"EVALR"             { return KW_EVALR; }
"EVAL("[EHMNRPT]+")" {
    char *p = strchr(yytext, '(') + 1;
    char ext[16] = {0}; int i = 0;
    while (*p && *p != ')') ext[i++] = (char)toupper((unsigned char)*p++);
    yylval.sval = strdup(ext);
    return KW_EVAL_EXT;
}
"EVAL"              { return KW_EVAL; }
"IN(E)"             { yylval.sval = strdup("E"); return KW_IN_EXT; }
"OUT(E)"            { yylval.sval = strdup("E"); return KW_OUT_EXT; }
"UNLOCK(E)"         { yylval.sval = strdup("E"); return KW_UNLOCK_EXT; }
"OPEN(E)"           { yylval.sval = strdup("E"); return KW_OPEN_EXT; }
"CLOSE(E)"          { yylval.sval = strdup("E"); return KW_CLOSE_EXT; }
"CALLP("[EHMNRP]+")" {
    char *p = strchr(yytext, '(') + 1;
    char ext[16] = {0}; int i = 0;
    while (*p && *p != ')') ext[i++] = (char)toupper((unsigned char)*p++);
    yylval.sval = strdup(ext);
    return KW_CALLP_EXT;
}
"CALLP"             { return KW_CALLP; }
"CALL"              { return KW_CALL; }
"LEAVESR"           { return KW_LEAVESR; }
"ON-EXIT"           { return KW_ON_EXIT; }
"STATIC"            { return KW_STATIC; }
"TEMPLATE"          { return KW_TEMPLATE; }
"BASED"             { return KW_BASED; }
"EXPORT"            { return KW_EXPORT; }
"IMPORT"            { return KW_IMPORT; }
"EXTPGM"            { return KW_EXTPGM; }
"EXTPROC"           { return KW_EXTPROC; }
"OVERLOAD"          { return KW_OVERLOAD; }
"DEALLOC"           { return KW_DEALLOC; }
"OPTIONS"           { return KW_OPTIONS; }
"*NOPASS"           { return KW_NOPASS; }
"*OMIT"             { return KW_OMIT; }
"TEST"              { return KW_TEST; }
"RETURN"            { return KW_RETURN; }
"DCL-PROC"          { return KW_DCL_PROC; }
"END-PROC"          { return KW_END_PROC; }
"DCL-PI"            { BEGIN(PI_NAME); return KW_DCL_PI; }
 /* *N — "no name" — is the standard way to write a procedure interface's
    name, and IBM's recommended one. It is a name only in this position:
    elsewhere "*N" is multiplication by N (total*N), so it is recognized
    only as the first token after DCL-PI (or DCL-DS), and anything else there is
    handed back to be scanned normally. */
<PI_NAME>[ \t\r\n]+    { /* whitespace between DCL-PI and its name */ }
<PI_NAME>"*N"/[^A-Za-z0-9_] { BEGIN(INITIAL); yylval.sval = strdup("*N"); return IDENTIFIER; }
<PI_NAME>.            { yyless(0); BEGIN(INITIAL); }
"END-PI"            { return KW_END_PI; }
"DCL-PR"            { return KW_DCL_PR; }
"END-PR"            { return KW_END_PR; }
"VALUE"             { return KW_VALUE; }
"DCL-DS"            { BEGIN(PI_NAME); return KW_DCL_DS; }   /* *N: an unnamed DS */
"DCL-SUBF"          { return KW_DCL_SUBF; }
"DCL-PARM"          { return KW_DCL_PARM; }
"END-DS"            { return KW_END_DS; }
"QUALIFIED"         { return KW_QUALIFIED; }
"DIM"               { return KW_DIM; }
"LIKEDS"            { return KW_LIKEDS; }
"LIKE"              { return KW_LIKE; }
"UNS"               { return KW_UNS; }
"FLOAT"             { return KW_FLOAT_TYPE; }
"BINDEC"            { return KW_BINDEC; }
"UCS2"              { return KW_UCS2; }
"GRAPH"             { return KW_GRAPH; }
"OBJECT"            { return KW_OBJECT; }
"*JAVA"             { return KW_JAVA; }
"DATFMT"            { return KW_DATFMT; }
"TIMFMT"            { return KW_TIMFMT; }
"OVERLAY"           { return KW_OVERLAY; }
"POS"               { return KW_POS; }
"PREFIX"            { return KW_PREFIX; }
"EXTNAME"           { return KW_EXTNAME; }
"PSDS"              { return KW_PSDS; }
"SDS"               { return KW_SDS; }
"DTAARA"            { return KW_DTAARA; }
"OUT"               { return KW_OUT; }
"UNLOCK"            { return KW_UNLOCK; }
"OPEN"              { return KW_OPEN; }
"CLOSE"             { return KW_CLOSE; }
"RTNPARM"           { return KW_RTNPARM; }
"OPDESC"            { return KW_OPDESC; }
"ASCEND"            { return KW_ASCEND; }
"CTDATA"            { return KW_CTDATA; }
"PERRCD"            { return KW_PERRCD; }
"DESCEND"           { return KW_DESCEND; }
"NULLIND"           { return KW_NULLIND; }
"*EXTDFT"           { return KW_STAR_EXTDFT; }
"*LIKEDS"           { return KW_STAR_LIKEDS; }
"*VAR"              { return KW_DIM_VAR; }
"*AUTO"             { return KW_DIM_AUTO; }
"*VARSIZE"          { return KW_VARSIZE; }
"*STRING"           { return KW_STRING_OPT; }
"*TRIM"             { return KW_TRIM_OPT; }
"*UPPER"            { return KW_UPPER_OPT; }
"*LOWER"            { return KW_LOWER_OPT; }
"FOR-EACH"          { return KW_FOR_EACH; }
"IN"                { return KW_IN; }

"IF"                { return KW_IF; }
"ELSEIF"            { return KW_ELSEIF; }
"ELSE"              { return KW_ELSE; }
"ENDIF"             { return KW_ENDIF; }
"DOU"               { return KW_DOU; }
"DOW"               { return KW_DOW; }
"ENDDO"             { return KW_ENDDO; }
"FOR"               { return KW_FOR; }
"ENDFOR"            { return KW_ENDFOR; }
"TO"                { return KW_TO; }
"DOWNTO"            { return KW_DOWNTO; }
"BY"                { return KW_BY; }
"SELECT"            { return KW_SELECT; }
"WHEN-IS-NOT"       { return KW_WHEN_IS_NOT; }
"WHEN-NOT-IN"       { return KW_WHEN_NOT_IN; }
"WHEN-IS"           { return KW_WHEN_IS; }
"WHEN-IN"           { return KW_WHEN_IN; }
"WHEN"              { return KW_WHEN; }
"OTHER"             { return KW_OTHER; }
"ENDSL"             { return KW_ENDSL; }
"ITER"              { return KW_ITER; }
"LEAVE"             { return KW_LEAVE; }
"MONITOR"           { return KW_MONITOR; }
"ON-ERROR"          { return KW_ON_ERROR; }
"ENDMON"            { return KW_ENDMON; }
"BEGSR"             { return KW_BEGSR; }
"ENDSR"             { return KW_ENDSR; }
"EXSR"              { return KW_EXSR; }
"GOTO"              { return KW_GOTO; }
"MOVEL(P)"          { return KW_MOVEL_PAD; }
"MOVEL"             { return KW_MOVEL; }
"MOVE(P)"           { return KW_MOVE_PAD; }
"MOVE"              { return KW_MOVE; }
"TAG"               { return KW_TAG; }
"RESET"             { return KW_RESET; }
"SORTA"             { return KW_SORTA; }
"CLEAR"             { return KW_CLEAR; }
"DUMP("[Aa]")"      { return KW_DUMP_A; }
"DUMP"              { return KW_DUMP; }
"AND"               { return KW_AND; }
"OR"                { return KW_OR; }
"NOT"               { return KW_NOT; }

"%CHAR"             { return BIF_CHAR; }
"%TRIM"             { return BIF_TRIM; }
"%TRIML"            { return BIF_TRIML; }
"%TRIMR"            { return BIF_TRIMR; }
"%LEN"              { return BIF_LEN; }
"%SUBST"            { return BIF_SUBST; }
"%SCAN"             { return BIF_SCAN; }
"%SCANRPL"          { return BIF_SCANRPL; }
"%XLATE"            { return BIF_XLATE; }
"%DEC"              { return BIF_DEC; }
"%INT"              { return BIF_INT; }
"%ELEM"             { return BIF_ELEM; }
"%PARMS"            { return BIF_PARMS; }
"%STATUS"           { return BIF_STATUS; }
"%ERROR"            { return BIF_ERROR; }
"%LOOKUP"           { return BIF_LOOKUP; }
"%MAX"              { return BIF_MAX; }
"%MIN"              { return BIF_MIN; }
"%SIZE"             { return BIF_SIZE; }
"%ADDR"             { return BIF_ADDR; }
"%ABS"              { return BIF_ABS; }
"%DIV"              { return BIF_DIV; }
"%REM"              { return BIF_REM; }
"%FOUND"            { return BIF_FOUND; }
"%EDITC"            { return BIF_EDITC; }
"%EDITW"            { return BIF_EDITW; }
"%REPLACE"          { return BIF_REPLACE; }
"%CHECK"            { return BIF_CHECK; }
"%CHECKR"           { return BIF_CHECKR; }
"%LOWER"            { return BIF_LOWER; }
"%UPPER"            { return BIF_UPPER; }
"%SUBDT"            { return BIF_SUBDT; }
"%FLOAT"            { return BIF_FLOAT; }
"%SQRT"             { return BIF_SQRT; }
"%ALLOC"            { return BIF_ALLOC; }
"%REALLOC"          { return BIF_REALLOC; }
"%XFOOT"            { return BIF_XFOOT; }
"%SUBARR"           { return BIF_SUBARR; }
"%SPLIT"            { return BIF_SPLIT; }
"%UNS"              { return BIF_UNS; }
"%INTH"             { return BIF_INTH; }
"%DECH"             { return BIF_DECH; }
"%DECPOS"           { return BIF_DECPOS; }
"%CONCAT"           { return BIF_CONCAT; }
"%CONCATARR"        { return BIF_CONCATARR; }
"%LEFT"             { return BIF_LEFT; }
"%RIGHT"            { return BIF_RIGHT; }
"%STR"              { return BIF_STR; }
"%MAXARR"           { return BIF_MAXARR; }
"%MINARR"           { return BIF_MINARR; }
"%LIST"             { return BIF_LIST; }
"%RANGE"            { return BIF_RANGE; }
"%LOOKUPLT"         { return BIF_LOOKUPLT; }
"%LOOKUPGE"         { return BIF_LOOKUPGE; }
"%LOOKUPLE"         { return BIF_LOOKUPLE; }
"%LOOKUPGT"         { return BIF_LOOKUPGT; }
"%TLOOKUP"          { return BIF_TLOOKUP; }
"%TLOOKUPLT"        { return BIF_TLOOKUPLT; }
"%TLOOKUPGT"        { return BIF_TLOOKUPGT; }
"%TLOOKUPLE"        { return BIF_TLOOKUPLE; }
"%TLOOKUPGE"        { return BIF_TLOOKUPGE; }
"%HOURS"            { return BIF_HOURS; }
"%MINUTES"          { return BIF_MINUTES; }
"%SECONDS"          { return BIF_SECONDS; }
"%MSECONDS"         { return BIF_MSECONDS; }
"%PADDR"            { return BIF_PADDR; }
"%PROC"             { return BIF_PROC; }
"%PASSED"           { return BIF_PASSED; }
"%OMITTED"          { return BIF_OMITTED; }
"%BITAND"           { return BIF_BITAND; }
"%BITNOT"           { return BIF_BITNOT; }
"%BITOR"            { return BIF_BITOR; }
"%BITXOR"           { return BIF_BITXOR; }
"%SCANR"            { return BIF_SCANR; }
"%EDITFLT"          { return BIF_EDITFLT; }
"%UNSH"             { return BIF_UNSH; }
"%PARMNUM"          { return BIF_PARMNUM; }
"%EOF"              { return BIF_EOF; }
"%OPEN"             { return BIF_OPEN; }
"%DATE"             { return BIF_DATE; }
"%TIME"             { return BIF_TIME; }
"%TIMESTAMP"        { return BIF_TIMESTAMP; }
"%DIFF"             { return BIF_DIFF; }
"%DAYS"             { return BIF_DAYS; }
"%MONTHS"           { return BIF_MONTHS; }
"%YEARS"            { return BIF_YEARS; }
"%GETENV"           { return BIF_GETENV; }
"%FKEY"             { return BIF_FKEY; }
"DEPRECATED"        { return KW_DEPRECATED; }
"DEFAULT"           { return KW_DEFAULT; }
"%IF"               { return BIF_IF; }
"%COMPCORR"         { return BIF_COMPCORR; }
"%KDS"              { return BIF_KDS; }
"%REPEAT"           { return BIF_REPEAT; }
"%PROGNAME"         { return BIF_PROGNAME; }
"%TOHEX"            { return BIF_TOHEX; }
"%HEX"              { return BIF_TOHEX; }
"%FROMHEX"          { return BIF_FROMHEX; }
"%MATCHES"          { return BIF_MATCHES; }
"%FIND"             { return BIF_FIND; }
"%COUNTMATCHES"     { return BIF_COUNTMATCHES; }
"%XML"              { return BIF_XML; }
"%DATA"             { return BIF_DATA; }
"%PARSER"           { return BIF_PARSER; }
"%GEN"              { return BIF_GEN; }
 /* Date and time formats, with an optional separator suffix (*MDY/, *ISO0),
    as the operand of %DATE, %TIME, %TIMESTAMP, %CHAR, TEST and DATFMT. */
"*"(ISO|USA|EUR|JIS|MDY|DMY|YMD|JUL|LONGJUL|CYMD|CMDY|CDMY|HMS)[-/.,&0]?/[^A-Za-z0-9_#$@] {
    std::string v = yytext;
    for (auto& c : v) c = (char)toupper((unsigned char)c);
    yylval.sval = strdup(v.c_str());
    return IDENTIFIER;
}
"*NOZEROSUPPRESS"   { yylval.sval = strdup("*NOZEROSUPPRESS"); return IDENTIFIER; }
"*FIRST"            { yylval.sval = strdup("*FIRST"); return IDENTIFIER; }
"*NEXT"             { yylval.sval = strdup("*NEXT"); return IDENTIFIER; }
 /* *EMPTY, an OpenRPG extension: the empty string, exactly as ''. */
"*EMPTY"            { yylval.sval = strdup(""); return STRING_LITERAL; }
"*LAST"             { yylval.sval = strdup("*LAST"); return IDENTIFIER; }
"*ZEROSUPPRESS"     { yylval.sval = strdup("*ZEROSUPPRESS"); return IDENTIFIER; }
"*INZSR"            { yylval.sval = strdup("*INZSR"); return IDENTIFIER; }
"*PSSR"             { yylval.sval = strdup("*PSSR"); return IDENTIFIER; }
"*LDA"              { yylval.sval = strdup("*LDA"); return IDENTIFIER; }
"*GDA"              { yylval.sval = strdup("*GDA"); return IDENTIFIER; }
"*PDA"              { yylval.sval = strdup("*PDA"); return IDENTIFIER; }
"*INFO"             { return KW_STAR_INFO; }
"*DIAG"             { return KW_STAR_DIAG; }
"*ESCAPE"           { return KW_STAR_ESCAPE; }
"*COMP"             { return KW_STAR_COMP; }
"*LOCK"             { return KW_STAR_LOCK; }
"*SYS"              { return KW_STAR_SYS; }
"*DTAARA"           { return KW_STAR_DTAARA; }
"*STATUS"           { return KW_STAR_STATUS; }
"*NOTIFY"           { return KW_STAR_NOTIFY; }
"*CALLER"           { return KW_STAR_CALLER; }
"*SELF"             { return KW_STAR_SELF; }
"*EXT"              { return KW_STAR_EXT; }
"%TARGET"           { return BIF_TARGET; }
"*INLR"             { yylval.ival = 0; return INDICATOR; }  /* LR: slot 0, see IndicatorExpr::LR */
"*ON"               { return KW_ON; }
"*OFF"              { return KW_OFF; }
 /* *TRUE and *FALSE, an OpenRPG extension: other names for *ON and *OFF. */
"*TRUE"             { return KW_ON; }
"*FALSE"            { return KW_OFF; }
"*NULL"             { return KW_NULL; }
"*USER"             { return KW_USER; }
"*BLANKS"           { return KW_BLANKS; }
"*BLANK"            { return KW_BLANKS; }
"*ZEROS"            { return KW_ZEROS; }
"*ZERO"             { return KW_ZEROS; }
"*HIVAL"            { return KW_HIVAL; }
"*LOVAL"            { return KW_LOVAL; }
"*ALL"              { return KW_ALL; }
"*FILE"             { return KW_STAR_FILE; }
"*PROGRAM"          { return KW_STAR_PROGRAM; }
"*DAYS"             { return KW_DAYS; }
"*MONTHS"           { return KW_MONTHS; }
"*YEARS"            { return KW_YEARS; }
"*HOURS"            { return KW_HOURS; }
"*MINUTES"          { return KW_MINUTES; }
"*SECONDS"          { return KW_SECONDS; }
"*MSECONDS"         { return KW_MSECONDS; }
"*IN"[0-9][0-9]     { yylval.ival = atoi(yytext + 3); return INDICATOR; }
 /* *IN, the array of the 99 numbered indicators: *IN(i) or *IN itself. */
"*IN"/[^A-Za-z0-9_#$@]       { return KW_STAR_IN; }
 /* Halt indicators *H1-*H9 (also *INH1-*INH9): IndicatorExpr::H1 + n - 1 */
"*H"[1-9]/[^A-Za-z0-9_#$@]   { yylval.ival = 100 + (yytext[2] - '0'); return INDICATOR; }
"*INH"[1-9]/[^A-Za-z0-9_#$@] { yylval.ival = 100 + (yytext[4] - '0'); return INDICATOR; }
"*ALLOC"            { return KW_STAR_ALLOC; }
"*KEEP"             { return KW_STAR_KEEP; }

";"                 { g_semi_line = yylineno; return SEMICOLON; }
 /* Compound assignment: x += y is x = x + (y). No expression can contain
    one of these pairs, so they are safe to take as single tokens. */
"+="                { yylval.ival = 0; return COMPOUND_ASSIGN; }
"-="                { yylval.ival = 1; return COMPOUND_ASSIGN; }
"*="                { yylval.ival = 2; return COMPOUND_ASSIGN; }
"/="                { yylval.ival = 3; return COMPOUND_ASSIGN; }
"**="               { yylval.ival = 4; return COMPOUND_ASSIGN; }
"="                 { return EQUALS; }
"("                 { return LPAREN; }
")"                 { return RPAREN; }
":"                 { return COLON; }
"+"                 { return PLUS; }
"-"                 { return MINUS; }
"**"                { return POWER; }
"*"                 { return STAR; }
"/"                 { return SLASH; }
"<>"                { return NE; }
"<="                { return LE; }
">="                { return GE; }
"=>"                { return ARROW; }
"<"                 { return LT; }
">"                 { return GT; }
"."                 { return DOT; }

 /* Conditional compilation directives - processed in both INITIAL and SKIPPING states */
<INITIAL,SKIPPING>^[ \t]*"/"[Dd][Ee][Ff][Ii][Nn][Ee][ \t]+[a-zA-Z_][a-zA-Z0-9_]* {
    if (cond_is_active()) {
        const char* p = yytext;
        while (*p == ' ' || *p == '\t') p++;
        p++;
        while (*p && *p != ' ' && *p != '\t') p++;
        while (*p == ' ' || *p == '\t') p++;
        std::string sym;
        while (*p && *p != ' ' && *p != '\t' && *p != '\n') {
            sym += toupper(*p); p++;
        }
        cond_defines.insert(sym);
    }
}

<INITIAL,SKIPPING>^[ \t]*"/"[Uu][Nn][Dd][Ee][Ff][Ii][Nn][Ee][ \t]+[a-zA-Z_][a-zA-Z0-9_]* {
    if (cond_is_active()) {
        const char* p = yytext;
        while (*p == ' ' || *p == '\t') p++;
        p++;
        while (*p && *p != ' ' && *p != '\t') p++;
        while (*p == ' ' || *p == '\t') p++;
        std::string sym;
        while (*p && *p != ' ' && *p != '\t' && *p != '\n') {
            sym += toupper(*p); p++;
        }
        cond_defines.erase(sym);
    }
}

<INITIAL,SKIPPING>^[ \t]*"/"[Ii][Ff][ \t]+[^\n]*$ {
    /* /IF condition: DEFINED(name), NOT, AND, OR and parentheses
       (cond_expr.h). Evaluated in a skipped branch too, to track nesting. */
    cond_depth++;
    bool v = false;
    std::string err;
    const char* c = yytext;
    while (*c == ' ' || *c == '\t') c++;
    if (!rpgc_cond::evaluate(std::string(c + 3), cond_defines, v, err))
        report_semantic_error(yylineno, "/IF: " + err);
    cond_active[cond_depth] = v;
    cond_done[cond_depth] = v;
    if (!cond_is_active()) BEGIN(SKIPPING);
    else BEGIN(INITIAL);
}

<INITIAL,SKIPPING>^[ \t]*"/"[Ee][Ll][Ss][Ee][Ii][Ff][ \t]+[^\n]*$ {
    if (cond_depth > 0) {
        bool v = false;
        std::string err;
        const char* c = yytext;
        while (*c == ' ' || *c == '\t') c++;
        if (!rpgc_cond::evaluate(std::string(c + 7), cond_defines, v, err))
            report_semantic_error(yylineno, "/ELSEIF: " + err);
        if (cond_done[cond_depth]) {
            cond_active[cond_depth] = false;
        } else {
            cond_active[cond_depth] = v;
            cond_done[cond_depth] = v;
        }
    }
    if (!cond_is_active()) BEGIN(SKIPPING);
    else BEGIN(INITIAL);
}

 /* /MESSAGE {*WARNING | *ERROR} 'text': a warning, or an error that fails
    the compile -- only where code is being compiled (cond_expr.h). */
^[ \t]*"/"[Mm][Ee][Ss][Ss][Aa][Gg][Ee]([ \t][^\n]*)?$ {
    const char* c = yytext;
    while (*c == ' ' || *c == '\t') c++;
    bool err = false;
    std::string text;
    rpgc_cond::message(std::string(c + 8), err, text);
    if (err) report_semantic_error(yylineno, "/MESSAGE: " + text);
    else report_semantic_warning(yylineno, "/MESSAGE: " + text);
}

<INITIAL,SKIPPING>^[ \t]*"/"[Ee][Ll][Ss][Ee][ \t]*$ {
    if (cond_depth > 0) {
        cond_active[cond_depth] = !cond_done[cond_depth];
        cond_done[cond_depth] = true;
    }
    if (!cond_is_active()) BEGIN(SKIPPING);
    else BEGIN(INITIAL);
}

<INITIAL,SKIPPING>^[ \t]*"/"[Ee][Nn][Dd][Ii][Ff][ \t]*$ {
    if (cond_depth > 0) {
        cond_depth--;
    }
    if (!cond_is_active()) BEGIN(SKIPPING);
    else BEGIN(INITIAL);
}

<SKIPPING>[^\n]*\n   { /* skip lines in inactive conditional blocks */ }
<SKIPPING>[^\n]*     { /* skip last line without newline */ }

 /* /EOF ends the current source member only. Inside a /COPY member that
    means returning to the including member, exactly as reaching the member's
    real end does (<<EOF>> below) — yyterminate() there ended the whole
    compile, silently discarding every line of the includer after the
    /COPY, with exit status 0. */
^[ \t]*"/"[Ee][Oo][Ff][ \t]*    {
    if (include_stack_ptr > 0) {
        yy_delete_buffer(YY_CURRENT_BUFFER);
        yy_switch_to_buffer(include_stack[--include_stack_ptr]);
    } else {
        yyterminate();
    }
}

 /* Listing directives - ignored */
^[ \t]*"/"[Ee][Jj][Ee][Cc][Tt][ \t]*     { /* /EJECT: listing, ignore */ }
^[ \t]*"/"[Ss][Pp][Aa][Cc][Ee][ \t]+[^\n]* { /* /SPACE: listing, ignore */ }
^[ \t]*"/"[Tt][Ii][Tt][Ll][Ee][ \t]+[^\n]* { /* /TITLE: listing title, ignore */ }
^[ \t]*"/"[Ss][Ee][Tt][ \t]+[^\n]*       { /* /SET: stub, ignore */ }
^[ \t]*"/"[Rr][Ee][Ss][Tt][Oo][Rr][Ee][ \t]* { /* /RESTORE: stub, ignore */ }

 /* /COPY and /INCLUDE directives */
^[ \t]*"/"[Cc][Oo][Pp][Yy][ \t]+[^\n]+ {
    /* Extract filename from /COPY directive */
    const char* p = yytext;
    while (*p == ' ' || *p == '\t') p++;
    p++; /* skip '/' */
    while (*p && *p != ' ' && *p != '\t') p++; /* skip COPY */
    while (*p == ' ' || *p == '\t') p++;
    /* p now points to filename; trim trailing whitespace */
    char filename[256];
    int k = 0;
    while (*p && *p != '\n' && *p != '\r' && k < 255) {
        filename[k++] = *p++;
    }
    filename[k] = '\0';
    /* Trim trailing whitespace */
    while (k > 0 && (filename[k-1] == ' ' || filename[k-1] == '\t')) {
        filename[--k] = '\0';
    }

    if (include_stack_ptr >= MAX_INCLUDE_DEPTH) {
        fprintf(stderr, "Error: /COPY nesting too deep\n");
    } else {
        FILE* f = fopen(filename, "r");
        if (!f) {
            fprintf(stderr, "Error: cannot open /COPY file '%s'\n", filename);
        } else {
            check_copy_member_format(filename, yylineno);
            include_stack[include_stack_ptr++] = YY_CURRENT_BUFFER;
            yy_switch_to_buffer(yy_create_buffer(f, YY_BUF_SIZE));
        }
    }
}

^[ \t]*"/"[Ii][Nn][Cc][Ll][Uu][Dd][Ee][ \t]+[^\n]+ {
    /* Same as /COPY */
    const char* p = yytext;
    while (*p == ' ' || *p == '\t') p++;
    p++;
    while (*p && *p != ' ' && *p != '\t') p++;
    while (*p == ' ' || *p == '\t') p++;
    char filename[256];
    int k = 0;
    while (*p && *p != '\n' && *p != '\r' && k < 255) {
        filename[k++] = *p++;
    }
    filename[k] = '\0';
    while (k > 0 && (filename[k-1] == ' ' || filename[k-1] == '\t')) {
        filename[--k] = '\0';
    }

    if (include_stack_ptr >= MAX_INCLUDE_DEPTH) {
        fprintf(stderr, "Error: /INCLUDE nesting too deep\n");
    } else {
        FILE* f = fopen(filename, "r");
        if (!f) {
            fprintf(stderr, "Error: cannot open /INCLUDE file '%s'\n", filename);
        } else {
            check_copy_member_format(filename, yylineno);
            include_stack[include_stack_ptr++] = YY_CURRENT_BUFFER;
            yy_switch_to_buffer(yy_create_buffer(f, YY_BUF_SIZE));
        }
    }
}

 /* An unclosed block comment. Before the <<EOF>> rule below, which would
    otherwise apply to this start condition too. */
<BLOCKCMT><<EOF>>   {
    report_semantic_error(block_comment_line, "The comment begun here with /* has no */ to end it");
    BEGIN(INITIAL);
    if (include_stack_ptr > 0) {
        yy_delete_buffer(YY_CURRENT_BUFFER);
        yy_switch_to_buffer(include_stack[--include_stack_ptr]);
    } else {
        yyterminate();
    }
}

<<EOF>> {
    if (include_stack_ptr > 0) {
        yy_delete_buffer(YY_CURRENT_BUFFER);
        yy_switch_to_buffer(include_stack[--include_stack_ptr]);
    } else {
        yyterminate();
    }
}

    /* A decimal literal keeps its text: its scale is the digits written
       after the point, so 1.50 has two decimal positions where 1.5 has one. */
[0-9]+\.[0-9]+      { yylval.sval = strdup(yytext); return FLOAT_LITERAL; }
[0-9]+              {
    /* A literal beyond int's range was atoi'd into it and silently wrapped
       (3000000000 became -1294967296). Such a literal is a numeric value,
       not a size or an index, so it is returned as a decimal literal,
       which a double holds exactly up to 2**53. */
    long long v = strtoll(yytext, nullptr, 10);
    if (v > INT_MAX) { yylval.sval = strdup(yytext); return FLOAT_LITERAL; }
    yylval.ival = static_cast<int>(v);
    return INTEGER_LITERAL;
}

[Ff]'([^']|'')*'    {
    std::string text = desugar_fstring(std::string(yytext + 2, yyleng - 3), yylineno);
    if (include_stack_ptr >= MAX_INCLUDE_DEPTH) {
        report_semantic_error(yylineno, "Interpolated strings nest too deeply");
    } else {
        include_stack[include_stack_ptr++] = YY_CURRENT_BUFFER;
        yy_scan_string(text.c_str());
    }
}
[Bb]'[^'\n]*'       {
    /* A binary literal, an OpenRPG extension: B'10100001' is X'A1' -- each
       eight binary digits one byte, the first the most significant. */
    std::string bits(yytext + 2, yyleng - 3);
    std::string hex = "X'";
    if (bits.size() % 8 != 0 || bits.find_first_not_of("01") != std::string::npos) {
        report_semantic_error(yylineno, "A binary literal holds only the digits 0 and 1, eight to "
            "each byte: B'" + bits + "' has " + std::to_string(bits.size()) + " characters");
    } else {
        // As the hex literal it equals, so a zero byte is kept as one is there.
        static const char* digits = "0123456789ABCDEF";
        for (size_t i = 0; i < bits.size(); i += 8) {
            unsigned v = 0;
            for (size_t k = 0; k < 8; k++) v = v * 2 + (unsigned)(bits[i + k] - '0');
            hex += digits[v >> 4];
            hex += digits[v & 15];
        }
    }
    hex += "'";
    yylval.sval = process_hex_string(hex.c_str());
    return STRING_LITERAL;
}
[Xx]'[0-9A-Fa-f]*'  { yylval.sval = process_hex_string(yytext); return STRING_LITERAL; }
 /* Typed literals: D'2024-01-15', T'10.30.00', Z'2024-01-15-10.30.00.000000' */
 /* (std::string rather than strndup, which Windows' C library lacks) */
[Dd]'[^'\n]*'       { yylval.sval = strdup(std::string(yytext + 2, yyleng - 3).c_str()); return DATE_LITERAL; }
[Tt]'[^'\n]*'       { yylval.sval = strdup(std::string(yytext + 2, yyleng - 3).c_str()); return TIME_LITERAL; }
[Zz]'[^'\n]*'       { yylval.sval = strdup(std::string(yytext + 2, yyleng - 3).c_str()); return TIMESTAMP_LITERAL; }
'([^']|'')*'        { yylval.sval = process_rpg_string(yytext); return STRING_LITERAL; }

[a-zA-Z_][a-zA-Z0-9_]* {
    yylval.sval = strdup_upper(yytext);
    return IDENTIFIER;
}

"//".*              { /* single-line comment, ignore */ }

 /* A block comment, an OpenRPG extension (IBM i has only //): from a
    slash-star to the next star-slash, on one line or across several,
    as in C. They do not nest. */
"/*"                { block_comment_line = yylineno; BEGIN(BLOCKCMT); }
<BLOCKCMT>"*/"      { BEGIN(INITIAL); }
<BLOCKCMT>[^*\n]+   { }
<BLOCKCMT>"*"       { }
<BLOCKCMT>\n        { }
[ \t\r\n]+          { /* whitespace, ignore */ }

.                   { fprintf(stderr, "Unexpected character: '%c' at line %d\n", *yytext, yylineno); }

%%
