%{
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <string>
#include "ast.h"
#include "keyword_list.h"
#include "parser.h"

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
    return result;
}

static char* strdup_upper(const char* text) {
    char* result = strdup(text);
    for (char* p = result; *p; p++) {
        *p = toupper((unsigned char)*p);
    }
    return result;
}

// Buffer stack for /COPY and /INCLUDE
#define MAX_INCLUDE_DEPTH 10
static YY_BUFFER_STATE include_stack[MAX_INCLUDE_DEPTH];
static int include_stack_ptr = 0;

// Conditional compilation
#include <set>
static std::set<std::string> cond_defines;
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

    auto kw = rpg::parseKeywordList(text);
    if (kw.count("NOMAIN")) ctlopt_nomain = true;

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

%%

"**FREE"            { return KW_FREE; }

 /* EXEC SQL: switch to SQL mode and capture text until semicolon */
[Ee][Xx][Ee][Cc][ \t]+[Ss][Qq][Ll][ \t]+ {
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
"BOOLEAN"           { return KW_BOOLEAN; }
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
"EVAL("[EHMNRP]+")" {
    char *p = strchr(yytext, '(') + 1;
    char ext[16] = {0}; int i = 0;
    while (*p && *p != ')') ext[i++] = (char)toupper((unsigned char)*p++);
    yylval.sval = strdup(ext);
    return KW_EVAL_EXT;
}
"EVAL"              { return KW_EVAL; }
"CALLP("[EHMNRP]+")" {
    char *p = strchr(yytext, '(') + 1;
    char ext[16] = {0}; int i = 0;
    while (*p && *p != ')') ext[i++] = (char)toupper((unsigned char)*p++);
    yylval.sval = strdup(ext);
    return KW_CALLP_EXT;
}
"CALLP"             { return KW_CALLP; }
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
"DCL-PI"            { return KW_DCL_PI; }
"END-PI"            { return KW_END_PI; }
"DCL-PR"            { return KW_DCL_PR; }
"END-PR"            { return KW_END_PR; }
"VALUE"             { return KW_VALUE; }
"DCL-DS"            { return KW_DCL_DS; }
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
"RTNPARM"           { return KW_RTNPARM; }
"OPDESC"            { return KW_OPDESC; }
"ASCEND"            { return KW_ASCEND; }
"DESCEND"           { return KW_DESCEND; }
"NULLIND"           { return KW_NULLIND; }
"*VAR"              { return KW_DIM_VAR; }
"*AUTO"             { return KW_DIM_AUTO; }
"*VARSIZE"          { return KW_VARSIZE; }
"*STRING"           { return KW_STRING_OPT; }
"*TRIM"             { return KW_TRIM_OPT; }
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
"%DATE"             { return BIF_DATE; }
"%TIME"             { return BIF_TIME; }
"%TIMESTAMP"        { return BIF_TIMESTAMP; }
"%DIFF"             { return BIF_DIFF; }
"%DAYS"             { return BIF_DAYS; }
"%MONTHS"           { return BIF_MONTHS; }
"%YEARS"            { return BIF_YEARS; }
"%GETENV"           { return BIF_GETENV; }
"%XML"              { return BIF_XML; }
"%DATA"             { return BIF_DATA; }
"%PARSER"           { return BIF_PARSER; }
"*INZSR"            { yylval.sval = strdup("*INZSR"); return IDENTIFIER; }
"*PSSR"             { yylval.sval = strdup("*PSSR"); return IDENTIFIER; }
"*LDA"              { yylval.sval = strdup("*LDA"); return IDENTIFIER; }
"*GDA"              { yylval.sval = strdup("*GDA"); return IDENTIFIER; }
"*PDA"              { yylval.sval = strdup("*PDA"); return IDENTIFIER; }
"*INFO"             { return KW_STAR_INFO; }
"*DIAG"             { return KW_STAR_DIAG; }
"*ESCAPE"           { return KW_STAR_ESCAPE; }
"*INLR"             { return KW_INLR; }
"*ON"               { return KW_ON; }
"*OFF"              { return KW_OFF; }
"*NULL"             { return KW_NULL; }
"*USER"             { return KW_USER; }
"*BLANKS"           { return KW_BLANKS; }
"*BLANK"            { return KW_BLANKS; }
"*ZEROS"            { return KW_ZEROS; }
"*ZERO"             { return KW_ZEROS; }
"*HIVAL"            { return KW_HIVAL; }
"*LOVAL"            { return KW_LOVAL; }
"*ALL"              { return KW_ALL; }
"*DAYS"             { return KW_DAYS; }
"*MONTHS"           { return KW_MONTHS; }
"*YEARS"            { return KW_YEARS; }
"*HOURS"            { return KW_HOURS; }
"*MINUTES"          { return KW_MINUTES; }
"*SECONDS"          { return KW_SECONDS; }
"*MSECONDS"         { return KW_MSECONDS; }
"*IN"[0-9][0-9]     { yylval.ival = atoi(yytext + 3); return INDICATOR; }
"*ALLOC"            { return KW_STAR_ALLOC; }
"*KEEP"             { return KW_STAR_KEEP; }

";"                 { return SEMICOLON; }
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

<INITIAL,SKIPPING>^[ \t]*"/"[Ii][Ff][ \t]+[Dd][Ee][Ff][Ii][Nn][Ee][Dd][ \t]*"("[^)]*")" {
    cond_depth++;
    std::string sym = cond_extract_symbol(yytext);
    bool defined = cond_defines.count(sym) > 0;
    cond_active[cond_depth] = defined;
    cond_done[cond_depth] = defined;
    if (!cond_is_active()) BEGIN(SKIPPING);
    else BEGIN(INITIAL);
}

<INITIAL,SKIPPING>^[ \t]*"/"[Ii][Ff][ \t]+[Nn][Oo][Tt][ \t]+[Dd][Ee][Ff][Ii][Nn][Ee][Dd][ \t]*"("[^)]*")" {
    cond_depth++;
    std::string sym = cond_extract_symbol(yytext);
    bool defined = cond_defines.count(sym) > 0;
    cond_active[cond_depth] = !defined;
    cond_done[cond_depth] = !defined;
    if (!cond_is_active()) BEGIN(SKIPPING);
    else BEGIN(INITIAL);
}

<INITIAL,SKIPPING>^[ \t]*"/"[Ee][Ll][Ss][Ee][Ii][Ff][ \t]+[Dd][Ee][Ff][Ii][Nn][Ee][Dd][ \t]*"("[^)]*")" {
    if (cond_depth > 0) {
        if (cond_done[cond_depth]) {
            cond_active[cond_depth] = false;
        } else {
            std::string sym = cond_extract_symbol(yytext);
            bool defined = cond_defines.count(sym) > 0;
            cond_active[cond_depth] = defined;
            cond_done[cond_depth] = defined;
        }
    }
    if (!cond_is_active()) BEGIN(SKIPPING);
    else BEGIN(INITIAL);
}

<INITIAL,SKIPPING>^[ \t]*"/"[Ee][Ll][Ss][Ee][Ii][Ff][ \t]+[Nn][Oo][Tt][ \t]+[Dd][Ee][Ff][Ii][Nn][Ee][Dd][ \t]*"("[^)]*")" {
    if (cond_depth > 0) {
        if (cond_done[cond_depth]) {
            cond_active[cond_depth] = false;
        } else {
            std::string sym = cond_extract_symbol(yytext);
            bool defined = cond_defines.count(sym) > 0;
            cond_active[cond_depth] = !defined;
            cond_done[cond_depth] = !defined;
        }
    }
    if (!cond_is_active()) BEGIN(SKIPPING);
    else BEGIN(INITIAL);
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

 /* /EOF - force end of source */
^[ \t]*"/"[Ee][Oo][Ff][ \t]*    { yyterminate(); }

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
            include_stack[include_stack_ptr++] = YY_CURRENT_BUFFER;
            yy_switch_to_buffer(yy_create_buffer(f, YY_BUF_SIZE));
        }
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

[0-9]+\.[0-9]+      { yylval.fval = atof(yytext); return FLOAT_LITERAL; }
[0-9]+              { yylval.ival = atoi(yytext); return INTEGER_LITERAL; }

[Xx]'[0-9A-Fa-f]*'  { yylval.sval = process_hex_string(yytext); return STRING_LITERAL; }
'([^']|'')*'        { yylval.sval = process_rpg_string(yytext); return STRING_LITERAL; }

[a-zA-Z_][a-zA-Z0-9_]* {
    yylval.sval = strdup_upper(yytext);
    return IDENTIFIER;
}

"//".*              { /* single-line comment, ignore */ }
[ \t\r\n]+          { /* whitespace, ignore */ }

.                   { fprintf(stderr, "Unexpected character: '%c' at line %d\n", *yytext, yylineno); }

%%
