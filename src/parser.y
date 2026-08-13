%code requires {
#include <memory>
#include <vector>
#include <string>
#include "ast.h"

struct StmtList {
    std::vector<rpg::Statement*> stmts;
};

struct ElseIfData {
    rpg::Expression* cond;
    std::vector<rpg::Statement*> body;
};

struct WhenData {
    rpg::Expression* cond;
    std::vector<rpg::Statement*> body;
};

struct ParamList {
    std::vector<rpg::ParamDecl> params;
};

struct DSFieldList {
    std::vector<rpg::DSField> fields;
};
}

%{
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <vector>
#include <string>
#include "ast.h"
#include "free_bridge.h"
#include "sql_utils.h"

extern int yylex();
extern int yylineno;
extern char* yytext;
void yyerror(const char* s);

// Flex's in-memory scan-buffer API — not declared by any generated
// header (this Makefile invokes flex without --header-file), so these
// match flex's actual default (non-%option c++) signatures by hand.
// Used by parse_free_block() below to re-invoke this same lexer/parser
// on an in-memory string instead of a file, for the fixed-format /free
// bridge (see TODO.md's "Fixed-Format Source Support" entry).
// No extern "C" here — flex's generated lexer.cpp is compiled as C++
// (this Makefile has no %option c++, but clang++ still compiles the
// .cpp output with normal C++ linkage/mangling), matching how yylex()/
// yylineno above are declared as plain extern, not extern "C".
typedef struct yy_buffer_state* YY_BUFFER_STATE;
extern YY_BUFFER_STATE yy_scan_string(const char* yy_str);
extern void yy_switch_to_buffer(YY_BUFFER_STATE new_buffer);
extern void yy_delete_buffer(YY_BUFFER_STATE b);

static rpg::Program* g_program = nullptr;
static int g_error_count = 0;

rpg::Program* get_parsed_program();
int get_parse_error_count();

// CTL-OPT values extracted by lexer
extern char ctlopt_main_proc[256];
extern char ctlopt_datfmt[64];
extern char ctlopt_timfmt[64];
extern bool ctlopt_nomain;

// Set line number on AST node
#define SET_LINE(node) do { if (node) (node)->line = yylineno; } while(0)

// DCL-F option globals (reset at start of each dclf_opts parse)
static bool g_dclf_keyed = false;
static bool g_dclf_usropn = false;
static char* g_dclf_extdesc = nullptr;
static char* g_dclf_usages = nullptr;
static char* g_dclf_prefix = nullptr;

static rpg::BIFCall* make_bif(const char* name, std::vector<rpg::Expression*>* raw_args) {
    std::vector<std::unique_ptr<rpg::Expression>> args;
    for (auto* e : *raw_args) {
        args.emplace_back(e);
    }
    delete raw_args;
    return new rpg::BIFCall(name, std::move(args));
}

static rpg::FuncCall* make_func(const char* name, std::vector<rpg::Expression*>* raw_args) {
    std::vector<std::unique_ptr<rpg::Expression>> args;
    if (raw_args) {
        for (auto* e : *raw_args) {
            args.emplace_back(e);
        }
        delete raw_args;
    }
    return new rpg::FuncCall(name, std::move(args));
}
%}

%union {
    int ival;
    double fval;
    char* sval;
    rpg::Expression* expr;
    rpg::Statement* stmt;
    rpg::Program* program;
    std::vector<rpg::Expression*>* expr_list;
    StmtList* stmt_list;
    std::vector<ElseIfData*>* elseif_list;
    ElseIfData* elseif_data;
    std::vector<WhenData*>* when_list;
    WhenData* when_data;
    ParamList* param_list;
    rpg::ParamDecl* param_decl;
    DSFieldList* ds_field_list;
    rpg::DSField* ds_field;
    std::vector<rpg::EnumConstant>* enum_const_list;
    std::vector<std::string>* str_list;
}

%token KW_FREE
%token KW_DCL_F KW_DCL_S KW_DCL_C
%token KW_DISK KW_PRINTER KW_WORKSTN KW_USAGE KW_KEYED KW_EXTDESC KW_USROPN
%token KW_CHAR KW_VARCHAR KW_INT KW_PACKED KW_ZONED
%token KW_DATE KW_TIME KW_TIMESTAMP KW_IND KW_POINTER KW_NULL
%token KW_DAYS KW_MONTHS KW_YEARS KW_HOURS KW_MINUTES KW_SECONDS KW_MSECONDS
%token KW_CONST KW_INZ
%token KW_DSPLY
%token KW_EVAL KW_EVAL_CORR KW_EVALR KW_CALLP KW_LEAVESR KW_ON_EXIT KW_DEALLOC KW_TEST
%token <sval> KW_EVAL_EXT KW_EVALR_EXT KW_CALLP_EXT
%token KW_STATIC KW_TEMPLATE KW_BASED KW_OPTIONS KW_NOPASS KW_OMIT
%token KW_EXPORT KW_IMPORT KW_EXTPGM KW_EXTPROC KW_CTLOPT KW_OVERLOAD
%token KW_RETURN
%token KW_INLR KW_ON
%token KW_BLANKS KW_ZEROS KW_HIVAL KW_LOVAL KW_USER
%token KW_IF KW_ELSEIF KW_ELSE KW_ENDIF
%token KW_DOW KW_DOU KW_ENDDO
%token KW_FOR KW_ENDFOR KW_TO KW_DOWNTO KW_BY
%token KW_SELECT KW_WHEN KW_OTHER KW_ENDSL
%token KW_ITER KW_LEAVE
%token KW_MONITOR KW_ON_ERROR KW_ENDMON
%token KW_BEGSR KW_ENDSR KW_EXSR
%token KW_OFF KW_RESET KW_CLEAR KW_SORTA KW_DUMP KW_DUMP_A
%token <ival> INDICATOR
%token KW_AND KW_OR KW_NOT
%token KW_DCL_PROC KW_END_PROC
%token KW_DCL_PI KW_END_PI
%token KW_DCL_PR KW_END_PR
%token KW_VALUE
%token KW_DCL_DS KW_END_DS KW_QUALIFIED KW_DIM KW_LIKEDS KW_LIKE KW_DCL_SUBF KW_DCL_PARM
%token DOT
%token BIF_CHAR BIF_TRIM BIF_TRIML BIF_TRIMR BIF_LEN BIF_SUBST
%token BIF_SCAN BIF_SCANRPL BIF_XLATE BIF_DEC BIF_INT BIF_ELEM BIF_FOUND BIF_EOF
%token BIF_ABS BIF_DIV BIF_REM BIF_SIZE BIF_ADDR BIF_PARMS BIF_STATUS BIF_ERROR BIF_MAX BIF_MIN BIF_LOOKUP
%token BIF_DATE BIF_TIME BIF_TIMESTAMP BIF_DIFF BIF_DAYS BIF_MONTHS BIF_YEARS
%token BIF_EDITC BIF_EDITW BIF_REPLACE BIF_CHECK BIF_CHECKR
%token BIF_LOWER BIF_UPPER BIF_SUBDT BIF_FLOAT BIF_SQRT
%token BIF_ALLOC BIF_REALLOC BIF_XFOOT BIF_SUBARR BIF_SPLIT
%token BIF_UNS BIF_INTH BIF_DECH BIF_DECPOS
%token BIF_CONCAT BIF_CONCATARR BIF_LEFT BIF_RIGHT BIF_STR
%token BIF_MAXARR BIF_MINARR BIF_LIST BIF_RANGE
%token BIF_LOOKUPLT BIF_LOOKUPGE BIF_LOOKUPLE BIF_LOOKUPGT
%token BIF_TLOOKUP BIF_TLOOKUPLT BIF_TLOOKUPGT BIF_TLOOKUPLE BIF_TLOOKUPGE
%token BIF_HOURS BIF_MINUTES BIF_SECONDS BIF_MSECONDS
%token BIF_PADDR BIF_PROC
%token BIF_PASSED BIF_OMITTED
%token BIF_BITAND BIF_BITNOT BIF_BITOR BIF_BITXOR
%token BIF_SCANR BIF_EDITFLT BIF_UNSH BIF_PARMNUM BIF_GETENV BIF_XML
%token BIF_DATA BIF_PARSER
%token KW_ALL
%token KW_UNS KW_FLOAT_TYPE KW_BINDEC KW_UCS2 KW_GRAPH KW_OBJECT KW_JAVA
%token KW_OVERLAY KW_POS KW_PREFIX KW_DATFMT KW_TIMFMT KW_EXTNAME KW_PSDS KW_SDS
%token KW_DTAARA KW_OUT KW_UNLOCK
%token KW_RTNPARM KW_OPDESC KW_ASCEND KW_DESCEND KW_NULLIND
%token KW_VARSIZE KW_STRING_OPT KW_TRIM_OPT
%token KW_DCL_ENUM KW_END_ENUM KW_BOOLEAN
%token <sval> EXEC_SQL_TEXT
%token POWER
%token KW_DIM_VAR KW_DIM_AUTO
%token KW_FOR_EACH KW_IN KW_XML_INTO KW_DATA_INTO KW_DATA_GEN KW_SND_MSG
%token KW_STAR_INFO KW_STAR_DIAG KW_STAR_ESCAPE KW_TYPE
%token KW_STAR_ALLOC KW_STAR_KEEP
%token KW_READ KW_READC KW_READE KW_READP KW_READPE KW_CHAIN KW_WRITE KW_UPDATE KW_DELETE KW_SETLL KW_SETGT KW_EXFMT
%token <sval> KW_READ_EXT KW_READE_EXT KW_READP_EXT KW_READPE_EXT KW_CHAIN_EXT
%token <sval> KW_WRITE_EXT KW_UPDATE_EXT KW_DELETE_EXT
%token <sval> IDENTIFIER
%token <ival> INTEGER_LITERAL
%token <fval> FLOAT_LITERAL
%token <sval> STRING_LITERAL

%token SEMICOLON EQUALS LPAREN RPAREN COLON
%token PLUS MINUS STAR SLASH
%token NE LE GE LT GT

%type <program> program
%type <stmt> statement dcl_f_stmt dcl_s_stmt dcl_c_stmt eval_stmt eval_corr_stmt evalr_stmt dsply_stmt inlr_stmt return_stmt expr_stmt reset_stmt clear_stmt sorta_stmt dump_stmt callp_stmt leavesr_stmt dealloc_stmt test_stmt
%type <stmt> if_stmt dow_stmt dou_stmt for_stmt for_each_stmt select_stmt iter_stmt leave_stmt
%type <stmt> dcl_proc_stmt dcl_pr_stmt dcl_ds_stmt dcl_enum_stmt
%type <stmt> monitor_stmt begsr_stmt exsr_stmt exec_sql_stmt xml_into_stmt
%type <stmt> in_da_stmt out_da_stmt unlock_da_stmt data_into_stmt data_gen_stmt snd_msg_stmt
%type <stmt> chain_stmt read_stmt readc_stmt reade_stmt readp_stmt readpe_stmt
%type <stmt> write_stmt update_stmt delete_stmt setll_stmt setgt_stmt exfmt_stmt
%type <expr> expression or_expr and_expr not_expr comparison_expr additive_expr multiplicative_expr power_expr unary_expr postfix_expr primary_expr eval_target
%type <expr_list> arg_list call_arg_list call_args_opt rla_keys rla_key_list
%type <stmt_list> statement_list
%type <elseif_list> elseif_clauses
%type <elseif_data> elseif_clause
%type <stmt_list> else_clause
%type <when_list> when_clauses
%type <when_data> when_clause
%type <stmt_list> other_clause
%type <ds_field_list> ds_fields
%type <ds_field> ds_field
%type <param_list> pi_params pr_params
%type <param_decl> pi_param pr_param
%type <ival> pi_return_type dcl_s_keywords proc_export
%type <sval> ident
%type <enum_const_list> enum_constants enum_constant
%type <str_list> overload_list

%start program

%%

program:
    KW_FREE statements_opt {
        $$ = g_program;
    }
    | statements_opt {
        $$ = g_program;
    }
    ;

statements_opt:
    /* empty */
    | statements_opt statement {
        if ($2) {
            g_program->statements.emplace_back($2);
        }
    }
    | statements_opt KW_CTLOPT {
        if (ctlopt_nomain) g_program->nomain = true;
        if (ctlopt_main_proc[0]) g_program->main_proc = ctlopt_main_proc;
        if (ctlopt_datfmt[0]) g_program->datfmt = ctlopt_datfmt;
        if (ctlopt_timfmt[0]) g_program->timfmt = ctlopt_timfmt;
    }
    ;

statement_list:
    /* empty */ {
        $$ = new StmtList();
    }
    | statement_list statement {
        $$ = $1;
        if ($2) {
            $$->stmts.push_back($2);
        }
    }
    ;

statement:
    dcl_f_stmt    { $$ = $1; SET_LINE($$); }
    | dcl_s_stmt  { $$ = $1; SET_LINE($$); }
    | dcl_c_stmt  { $$ = $1; SET_LINE($$); }
    | eval_stmt   { $$ = $1; SET_LINE($$); }
    | eval_corr_stmt { $$ = $1; SET_LINE($$); }
    | dsply_stmt  { $$ = $1; SET_LINE($$); }
    | inlr_stmt   { $$ = $1; SET_LINE($$); }
    | return_stmt { $$ = $1; SET_LINE($$); }
    | if_stmt     { $$ = $1; SET_LINE($$); }
    | dow_stmt    { $$ = $1; SET_LINE($$); }
    | dou_stmt    { $$ = $1; SET_LINE($$); }
    | for_stmt    { $$ = $1; SET_LINE($$); }
    | for_each_stmt { $$ = $1; SET_LINE($$); }
    | select_stmt { $$ = $1; SET_LINE($$); }
    | iter_stmt   { $$ = $1; SET_LINE($$); }
    | leave_stmt  { $$ = $1; SET_LINE($$); }
    | dcl_proc_stmt { $$ = $1; SET_LINE($$); }
    | dcl_pr_stmt   { $$ = $1; SET_LINE($$); }
    | dcl_ds_stmt   { $$ = $1; SET_LINE($$); }
    | dcl_enum_stmt { $$ = $1; SET_LINE($$); }
    | monitor_stmt  { $$ = $1; SET_LINE($$); }
    | begsr_stmt    { $$ = $1; SET_LINE($$); }
    | exsr_stmt     { $$ = $1; SET_LINE($$); }
    | reset_stmt    { $$ = $1; SET_LINE($$); }
    | clear_stmt    { $$ = $1; SET_LINE($$); }
    | sorta_stmt    { $$ = $1; SET_LINE($$); }
    | dump_stmt     { $$ = $1; SET_LINE($$); }
    | evalr_stmt    { $$ = $1; SET_LINE($$); }
    | callp_stmt    { $$ = $1; SET_LINE($$); }
    | leavesr_stmt  { $$ = $1; SET_LINE($$); }
    | dealloc_stmt  { $$ = $1; SET_LINE($$); }
    | test_stmt     { $$ = $1; SET_LINE($$); }
    | exec_sql_stmt { $$ = $1; SET_LINE($$); }
    | xml_into_stmt  { $$ = $1; SET_LINE($$); }
    | data_into_stmt { $$ = $1; SET_LINE($$); }
    | data_gen_stmt  { $$ = $1; SET_LINE($$); }
    | snd_msg_stmt   { $$ = $1; SET_LINE($$); }
    | in_da_stmt    { $$ = $1; SET_LINE($$); }
    | out_da_stmt   { $$ = $1; SET_LINE($$); }
    | unlock_da_stmt { $$ = $1; SET_LINE($$); }
    | chain_stmt   { $$ = $1; SET_LINE($$); }
    | read_stmt    { $$ = $1; SET_LINE($$); }
    | readc_stmt   { $$ = $1; SET_LINE($$); }
    | reade_stmt   { $$ = $1; SET_LINE($$); }
    | readp_stmt   { $$ = $1; SET_LINE($$); }
    | readpe_stmt  { $$ = $1; SET_LINE($$); }
    | write_stmt   { $$ = $1; SET_LINE($$); }
    | update_stmt  { $$ = $1; SET_LINE($$); }
    | delete_stmt  { $$ = $1; SET_LINE($$); }
    | setll_stmt   { $$ = $1; SET_LINE($$); }
    | setgt_stmt   { $$ = $1; SET_LINE($$); }
    | exfmt_stmt   { $$ = $1; SET_LINE($$); }
    | expr_stmt   { $$ = $1; SET_LINE($$); }
    | error SEMICOLON { $$ = nullptr; yyerrok; }
    ;

/* DCL-F: file declaration */
dcl_f_stmt:
    KW_DCL_F IDENTIFIER KW_DISK dclf_opts SEMICOLON {
        auto* n = new rpg::DclF($2, "DISK");
        free($2);
        // opts encoded in g_dclf_* globals set by dclf_opts
        n->keyed   = g_dclf_keyed;
        n->extdesc = g_dclf_extdesc ? g_dclf_extdesc : "";
        if (g_dclf_extdesc) { free(g_dclf_extdesc); g_dclf_extdesc = nullptr; }
        n->usages  = g_dclf_usages ? g_dclf_usages : "";
        if (g_dclf_usages) { free(g_dclf_usages); g_dclf_usages = nullptr; }
        n->usropn  = g_dclf_usropn;
        n->prefix  = g_dclf_prefix ? g_dclf_prefix : "";
        if (g_dclf_prefix) { free(g_dclf_prefix); g_dclf_prefix = nullptr; }
        g_dclf_keyed = false; g_dclf_usropn = false;
        $$ = n;
    }
    | KW_DCL_F IDENTIFIER KW_PRINTER SEMICOLON {
        $$ = new rpg::DclF($2, "PRINTER");
        free($2);
    }
    | KW_DCL_F IDENTIFIER KW_WORKSTN dclf_opts SEMICOLON {
        auto* n = new rpg::DclF($2, "WORKSTN");
        free($2);
        n->prefix  = g_dclf_prefix ? g_dclf_prefix : "";
        if (g_dclf_prefix) { free(g_dclf_prefix); g_dclf_prefix = nullptr; }
        g_dclf_keyed = false; g_dclf_usropn = false;
        $$ = n;
    }
    ;

/* DCL-F option keywords (zero or more before the semicolon) */
dclf_opts:
    /* empty */ {
        g_dclf_keyed = false; g_dclf_usropn = false;
        if (g_dclf_extdesc) { free(g_dclf_extdesc); g_dclf_extdesc = nullptr; }
        if (g_dclf_usages)  { free(g_dclf_usages);  g_dclf_usages  = nullptr; }
        if (g_dclf_prefix)  { free(g_dclf_prefix);  g_dclf_prefix  = nullptr; }
    }
    | dclf_opts KW_KEYED       { g_dclf_keyed = true; }
    | dclf_opts KW_USROPN      { g_dclf_usropn = true; }
    | dclf_opts KW_EXTDESC LPAREN STRING_LITERAL RPAREN {
        if (g_dclf_extdesc) free(g_dclf_extdesc);
        g_dclf_extdesc = $4;
    }
    | dclf_opts KW_PREFIX LPAREN IDENTIFIER RPAREN {
        if (g_dclf_prefix) free(g_dclf_prefix);
        g_dclf_prefix = $4;
    }
    | dclf_opts KW_USAGE LPAREN IDENTIFIER RPAREN {
        if (g_dclf_usages) free(g_dclf_usages);
        g_dclf_usages = $4;
    }
    | dclf_opts KW_USAGE LPAREN IDENTIFIER COLON IDENTIFIER RPAREN {
        char buf[128];
        snprintf(buf, sizeof(buf), "%s:%s", $4, $6);
        if (g_dclf_usages) free(g_dclf_usages);
        g_dclf_usages = strdup(buf);
        free($4); free($6);
    }
    ;

/* ---------- File I/O opcodes ---------- */

/* Key list: single expr or (expr:expr:...) */
rla_keys:
    expression {
        $$ = new std::vector<rpg::Expression*>();
        $$->push_back($1);
    }
    | LPAREN rla_key_list RPAREN { $$ = $2; }
    ;

rla_key_list:
    expression {
        $$ = new std::vector<rpg::Expression*>();
        $$->push_back($1);
    }
    | rla_key_list COLON expression {
        $$ = $1;
        $$->push_back($3);
    }
    ;

chain_stmt:
    KW_CHAIN rla_keys IDENTIFIER SEMICOLON {
        std::vector<std::unique_ptr<rpg::Expression>> keys;
        for (auto* e : *$2) keys.emplace_back(e);
        delete $2;
        $$ = new rpg::ChainStmt(std::move(keys), $3, "");
        free($3);
    }
    | KW_CHAIN_EXT rla_keys IDENTIFIER SEMICOLON {
        std::vector<std::unique_ptr<rpg::Expression>> keys;
        for (auto* e : *$2) keys.emplace_back(e);
        delete $2;
        $$ = new rpg::ChainStmt(std::move(keys), $3, $1);
        free($1); free($3);
    }
    ;

read_stmt:
    KW_READ IDENTIFIER SEMICOLON {
        $$ = new rpg::ReadStmt($2, "");
        free($2);
    }
    | KW_READ_EXT IDENTIFIER SEMICOLON {
        $$ = new rpg::ReadStmt($2, $1);
        free($1); free($2);
    }
    ;

readc_stmt:
    KW_READC IDENTIFIER SEMICOLON {
        $$ = new rpg::ReadcStmt($2);
        free($2);
    }
    ;

reade_stmt:
    KW_READE rla_keys IDENTIFIER SEMICOLON {
        std::vector<std::unique_ptr<rpg::Expression>> keys;
        for (auto* e : *$2) keys.emplace_back(e);
        delete $2;
        $$ = new rpg::ReadeStmt(std::move(keys), $3, "");
        free($3);
    }
    | KW_READE_EXT rla_keys IDENTIFIER SEMICOLON {
        std::vector<std::unique_ptr<rpg::Expression>> keys;
        for (auto* e : *$2) keys.emplace_back(e);
        delete $2;
        $$ = new rpg::ReadeStmt(std::move(keys), $3, $1);
        free($1); free($3);
    }
    ;

readp_stmt:
    KW_READP IDENTIFIER SEMICOLON {
        $$ = new rpg::ReadpStmt($2, "");
        free($2);
    }
    | KW_READP_EXT IDENTIFIER SEMICOLON {
        $$ = new rpg::ReadpStmt($2, $1);
        free($1); free($2);
    }
    ;

readpe_stmt:
    KW_READPE rla_keys IDENTIFIER SEMICOLON {
        std::vector<std::unique_ptr<rpg::Expression>> keys;
        for (auto* e : *$2) keys.emplace_back(e);
        delete $2;
        $$ = new rpg::ReadpeStmt(std::move(keys), $3, "");
        free($3);
    }
    | KW_READPE_EXT rla_keys IDENTIFIER SEMICOLON {
        std::vector<std::unique_ptr<rpg::Expression>> keys;
        for (auto* e : *$2) keys.emplace_back(e);
        delete $2;
        $$ = new rpg::ReadpeStmt(std::move(keys), $3, $1);
        free($1); free($3);
    }
    ;

write_stmt:
    KW_WRITE IDENTIFIER SEMICOLON {
        $$ = new rpg::WriteStmt($2, "");
        free($2);
    }
    | KW_WRITE_EXT IDENTIFIER SEMICOLON {
        $$ = new rpg::WriteStmt($2, $1);
        free($1); free($2);
    }
    ;

update_stmt:
    KW_UPDATE IDENTIFIER SEMICOLON {
        $$ = new rpg::UpdateStmt($2, "");
        free($2);
    }
    | KW_UPDATE_EXT IDENTIFIER SEMICOLON {
        $$ = new rpg::UpdateStmt($2, $1);
        free($1); free($2);
    }
    ;

delete_stmt:
    KW_DELETE IDENTIFIER SEMICOLON {
        $$ = new rpg::DeleteStmt($2, "");
        free($2);
    }
    | KW_DELETE_EXT IDENTIFIER SEMICOLON {
        $$ = new rpg::DeleteStmt($2, $1);
        free($1); free($2);
    }
    ;

setll_stmt:
    KW_SETLL rla_keys IDENTIFIER SEMICOLON {
        std::vector<std::unique_ptr<rpg::Expression>> keys;
        for (auto* e : *$2) keys.emplace_back(e);
        delete $2;
        $$ = new rpg::SetllStmt(std::move(keys), $3);
        free($3);
    }
    ;

setgt_stmt:
    KW_SETGT rla_keys IDENTIFIER SEMICOLON {
        std::vector<std::unique_ptr<rpg::Expression>> keys;
        for (auto* e : *$2) keys.emplace_back(e);
        delete $2;
        $$ = new rpg::SetgtStmt(std::move(keys), $3);
        free($3);
    }
    ;

exfmt_stmt:
    KW_EXFMT IDENTIFIER SEMICOLON {
        // EXFMT RECFMT; — format name and file name are the same (single-record file)
        $$ = new rpg::ExfmtStmt($2, $2);
        free($2);
    }
    | KW_EXFMT IDENTIFIER COLON IDENTIFIER SEMICOLON {
        // EXFMT FILE:RECFMT; — explicit file:format
        $$ = new rpg::ExfmtStmt($2, $4);
        free($2); free($4);
    }
    ;

/* DCL-S */
dcl_s_stmt:
    KW_DCL_S ident KW_CHAR LPAREN INTEGER_LITERAL RPAREN dcl_s_keywords SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::CHAR, $5);
        n->is_static = ($7 & 1); n->is_template = ($7 & 2); n->is_export = ($7 & 4); n->is_import = ($7 & 8);
        $$ = n; free($2);
    }
    | KW_DCL_S ident KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN dcl_s_keywords SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::VARCHAR, $5);
        n->is_static = ($7 & 1); n->is_template = ($7 & 2); n->is_export = ($7 & 4); n->is_import = ($7 & 8);
        $$ = n; free($2);
    }
    | KW_DCL_S ident KW_INT LPAREN INTEGER_LITERAL RPAREN dcl_s_keywords SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::INT10, 0);
        n->is_static = ($7 & 1); n->is_template = ($7 & 2); n->is_export = ($7 & 4); n->is_import = ($7 & 8);
        $$ = n; free($2);
    }
    | KW_DCL_S ident KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN dcl_s_keywords SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::PACKED, 0, $5, $7);
        n->is_static = ($9 & 1); n->is_template = ($9 & 2); n->is_export = ($9 & 4); n->is_import = ($9 & 8);
        $$ = n; free($2);
    }
    | KW_DCL_S ident KW_ZONED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN dcl_s_keywords SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::ZONED, 0, $5, $7);
        n->is_static = ($9 & 1); n->is_template = ($9 & 2); n->is_export = ($9 & 4); n->is_import = ($9 & 8);
        $$ = n; free($2);
    }
    | KW_DCL_S ident KW_INT LPAREN INTEGER_LITERAL RPAREN KW_CONST KW_INZ LPAREN expression RPAREN SEMICOLON {
        $$ = new rpg::DclS($2, rpg::RPGType::INT10, 0, 0, 0, true,
                           std::unique_ptr<rpg::Expression>($10));
        free($2);
    }
    | KW_DCL_S ident KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_CONST KW_INZ LPAREN expression RPAREN SEMICOLON {
        $$ = new rpg::DclS($2, rpg::RPGType::CHAR, $5, 0, 0, true,
                           std::unique_ptr<rpg::Expression>($10));
        free($2);
    }
    | KW_DCL_S ident KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN KW_CONST KW_INZ LPAREN expression RPAREN SEMICOLON {
        $$ = new rpg::DclS($2, rpg::RPGType::PACKED, 0, $5, $7, true,
                           std::unique_ptr<rpg::Expression>($<expr>12));
        free($2);
    }
    | KW_DCL_S ident KW_INT LPAREN INTEGER_LITERAL RPAREN KW_INZ LPAREN expression RPAREN SEMICOLON {
        $$ = new rpg::DclS($2, rpg::RPGType::INT10, 0, 0, 0, false,
                           std::unique_ptr<rpg::Expression>($9));
        free($2);
    }
    | KW_DCL_S ident KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_INZ LPAREN expression RPAREN SEMICOLON {
        $$ = new rpg::DclS($2, rpg::RPGType::CHAR, $5, 0, 0, false,
                           std::unique_ptr<rpg::Expression>($9));
        free($2);
    }
    | KW_DCL_S ident KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN KW_INZ LPAREN expression RPAREN SEMICOLON {
        $$ = new rpg::DclS($2, rpg::RPGType::PACKED, 0, $5, $7, false,
                           std::unique_ptr<rpg::Expression>($<expr>11));
        free($2);
    }
    | KW_DCL_S ident KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN KW_INZ LPAREN expression RPAREN SEMICOLON {
        $$ = new rpg::DclS($2, rpg::RPGType::VARCHAR, $5, 0, 0, false,
                           std::unique_ptr<rpg::Expression>($9));
        free($2);
    }
    /* EXPORT INZ variants */
    | KW_DCL_S ident KW_INT LPAREN INTEGER_LITERAL RPAREN KW_EXPORT KW_INZ LPAREN expression RPAREN SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::INT10, 0, 0, 0, false,
                           std::unique_ptr<rpg::Expression>($10));
        n->is_export = true;
        $$ = n; free($2);
    }
    | KW_DCL_S ident KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_EXPORT KW_INZ LPAREN expression RPAREN SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::CHAR, $5, 0, 0, false,
                           std::unique_ptr<rpg::Expression>($10));
        n->is_export = true;
        $$ = n; free($2);
    }
    | KW_DCL_S ident KW_IND SEMICOLON {
        $$ = new rpg::DclS($2, rpg::RPGType::IND, 0);
        free($2);
    }
    | KW_DCL_S ident KW_BOOLEAN SEMICOLON {
        $$ = new rpg::DclS($2, rpg::RPGType::IND, 0);
        free($2);
    }
    | KW_DCL_S ident KW_DATE SEMICOLON {
        $$ = new rpg::DclS($2, rpg::RPGType::DATE, 0);
        free($2);
    }
    | KW_DCL_S ident KW_TIME SEMICOLON {
        $$ = new rpg::DclS($2, rpg::RPGType::TIME, 0);
        free($2);
    }
    | KW_DCL_S ident KW_TIMESTAMP SEMICOLON {
        $$ = new rpg::DclS($2, rpg::RPGType::TIMESTAMP, 0);
        free($2);
    }
    | KW_DCL_S ident KW_POINTER SEMICOLON {
        $$ = new rpg::DclS($2, rpg::RPGType::POINTER, 0);
        free($2);
    }
    | KW_DCL_S ident KW_INT LPAREN INTEGER_LITERAL RPAREN KW_DIM LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::DclS($2, rpg::RPGType::INT10, 0, 0, 0, false, nullptr, $9);
        free($2);
    }
    | KW_DCL_S ident KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_DIM LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::DclS($2, rpg::RPGType::CHAR, $5, 0, 0, false, nullptr, $9);
        free($2);
    }
    | KW_DCL_S ident KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN KW_DIM LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::DclS($2, rpg::RPGType::VARCHAR, $5, 0, 0, false, nullptr, $9);
        free($2);
    }
    | KW_DCL_S ident KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN KW_DIM LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::DclS($2, rpg::RPGType::PACKED, 0, $5, $7, false, nullptr, $<ival>11);
        free($2);
    }
    | KW_DCL_S ident KW_INT LPAREN INTEGER_LITERAL RPAREN KW_DIM LPAREN KW_DIM_VAR COLON INTEGER_LITERAL RPAREN SEMICOLON {
        auto* node = new rpg::DclS($2, rpg::RPGType::INT10, 0, 0, 0, false, nullptr, $11);
        node->dim_type = 1;
        free($2);
        $$ = node;
    }
    | KW_DCL_S ident KW_INT LPAREN INTEGER_LITERAL RPAREN KW_DIM LPAREN KW_DIM_AUTO COLON INTEGER_LITERAL RPAREN SEMICOLON {
        auto* node = new rpg::DclS($2, rpg::RPGType::INT10, 0, 0, 0, false, nullptr, $11);
        node->dim_type = 2;
        free($2);
        $$ = node;
    }
    | KW_DCL_S ident KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN KW_DIM LPAREN KW_DIM_VAR COLON INTEGER_LITERAL RPAREN SEMICOLON {
        auto* node = new rpg::DclS($2, rpg::RPGType::VARCHAR, $5, 0, 0, false, nullptr, $11);
        node->dim_type = 1;
        free($2);
        $$ = node;
    }
    | KW_DCL_S ident KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN KW_DIM LPAREN KW_DIM_AUTO COLON INTEGER_LITERAL RPAREN SEMICOLON {
        auto* node = new rpg::DclS($2, rpg::RPGType::VARCHAR, $5, 0, 0, false, nullptr, $11);
        node->dim_type = 2;
        free($2);
        $$ = node;
    }
    | KW_DCL_S ident KW_LIKE LPAREN IDENTIFIER RPAREN SEMICOLON {
        auto* node = new rpg::DclS($2, rpg::RPGType::INT10, 0);
        node->like_var = $5;
        free($2);
        free($5);
        $$ = node;
    }
    | KW_DCL_S ident KW_UNS LPAREN INTEGER_LITERAL RPAREN dcl_s_keywords SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::UNS, $5);
        n->is_static = ($7 & 1); n->is_template = ($7 & 2); n->is_export = ($7 & 4); n->is_import = ($7 & 8);
        $$ = n; free($2);
    }
    | KW_DCL_S ident KW_FLOAT_TYPE LPAREN INTEGER_LITERAL RPAREN dcl_s_keywords SEMICOLON {
        auto type = ($5 <= 4) ? rpg::RPGType::FLOAT4 : rpg::RPGType::FLOAT8;
        auto* n = new rpg::DclS($2, type, $5);
        n->is_static = ($7 & 1); n->is_template = ($7 & 2); n->is_export = ($7 & 4); n->is_import = ($7 & 8);
        $$ = n; free($2);
    }
    | KW_DCL_S ident KW_BINDEC LPAREN INTEGER_LITERAL RPAREN dcl_s_keywords SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::BINDEC, $5);
        n->is_static = ($7 & 1); n->is_template = ($7 & 2); n->is_export = ($7 & 4); n->is_import = ($7 & 8);
        $$ = n; free($2);
    }
    | KW_DCL_S ident KW_UCS2 LPAREN INTEGER_LITERAL RPAREN dcl_s_keywords SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::UCS2, $5);
        n->is_static = ($7 & 1); n->is_template = ($7 & 2); n->is_export = ($7 & 4); n->is_import = ($7 & 8);
        $$ = n; free($2);
    }
    | KW_DCL_S ident KW_GRAPH LPAREN INTEGER_LITERAL RPAREN dcl_s_keywords SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::UCS2, $5);
        n->is_static = ($7 & 1); n->is_template = ($7 & 2); n->is_export = ($7 & 4); n->is_import = ($7 & 8);
        $$ = n; free($2);
    }
    | KW_DCL_S ident KW_OBJECT LPAREN KW_JAVA COLON STRING_LITERAL RPAREN SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::OBJECT, 0);
        n->java_class = $7;
        $$ = n; free($2); free($7);
    }
    | KW_DCL_S ident KW_INT LPAREN INTEGER_LITERAL RPAREN KW_BASED LPAREN IDENTIFIER RPAREN SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::INT10, 0);
        n->based_ptr = $9;
        $$ = n; free($2); free($9);
    }
    | KW_DCL_S ident KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_BASED LPAREN IDENTIFIER RPAREN SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::CHAR, $5);
        n->based_ptr = $9;
        $$ = n; free($2); free($9);
    }
    | KW_DCL_S ident KW_INT LPAREN INTEGER_LITERAL RPAREN KW_DIM LPAREN INTEGER_LITERAL RPAREN KW_ASCEND SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::INT10, 0, 0, 0, false, nullptr, $9);
        n->sort_order = 1;
        $$ = n; free($2);
    }
    | KW_DCL_S ident KW_INT LPAREN INTEGER_LITERAL RPAREN KW_DIM LPAREN INTEGER_LITERAL RPAREN KW_DESCEND SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::INT10, 0, 0, 0, false, nullptr, $9);
        n->sort_order = -1;
        $$ = n; free($2);
    }
    | KW_DCL_S ident KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_DIM LPAREN INTEGER_LITERAL RPAREN KW_ASCEND SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::CHAR, $5, 0, 0, false, nullptr, $9);
        n->sort_order = 1;
        $$ = n; free($2);
    }
    | KW_DCL_S ident KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_DIM LPAREN INTEGER_LITERAL RPAREN KW_DESCEND SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::CHAR, $5, 0, 0, false, nullptr, $9);
        n->sort_order = -1;
        $$ = n; free($2);
    }
    | KW_DCL_S ident KW_DATE KW_DATFMT LPAREN IDENTIFIER RPAREN SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::DATE, 0);
        n->datfmt = $6;
        $$ = n; free($2); free($6);
    }
    | KW_DCL_S ident KW_TIME KW_TIMFMT LPAREN IDENTIFIER RPAREN SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::TIME, 0);
        n->timfmt = $6;
        $$ = n; free($2); free($6);
    }
    | KW_DCL_S ident KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_DTAARA LPAREN IDENTIFIER RPAREN SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::CHAR, $5);
        n->dtaara_name = $9;
        $$ = n; free($2); free($9);
    }
    | KW_DCL_S ident KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN KW_DTAARA LPAREN IDENTIFIER RPAREN SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::VARCHAR, $5);
        n->dtaara_name = $9;
        $$ = n; free($2); free($9);
    }
    | KW_DCL_S ident KW_INT LPAREN INTEGER_LITERAL RPAREN KW_DTAARA LPAREN IDENTIFIER RPAREN SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::INT10, 0);
        n->dtaara_name = $9;
        $$ = n; free($2); free($9);
    }
    | KW_DCL_S ident KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN KW_DTAARA LPAREN IDENTIFIER RPAREN SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::PACKED, 0, $5, $7);
        n->dtaara_name = $11;
        $$ = n; free($2); free($11);
    }
    ;

dcl_s_keywords:
    /* empty */   { $$ = 0; }
    | KW_STATIC   { $$ = 1; }
    | KW_TEMPLATE { $$ = 2; }
    | KW_EXPORT   { $$ = 4; }
    | KW_IMPORT   { $$ = 8; }
    ;

/* DCL-C: named constants */
dcl_c_stmt:
    KW_DCL_C IDENTIFIER expression SEMICOLON {
        $$ = new rpg::DclC($2, std::unique_ptr<rpg::Expression>($3));
        free($2);
    }
    ;

eval_target:
    IDENTIFIER {
        $$ = new rpg::Identifier($1);
        free($1);
    }
    | KW_POS { $$ = new rpg::Identifier("POS"); }
    | KW_OVERLAY { $$ = new rpg::Identifier("OVERLAY"); }
    | KW_PREFIX { $$ = new rpg::Identifier("PREFIX"); }
    | KW_UNS { $$ = new rpg::Identifier("UNS"); }
    | KW_FLOAT_TYPE { $$ = new rpg::Identifier("FLOAT"); }
    | KW_GRAPH { $$ = new rpg::Identifier("GRAPH"); }
    | KW_ASCEND { $$ = new rpg::Identifier("ASCEND"); }
    | KW_DESCEND { $$ = new rpg::Identifier("DESCEND"); }
    | KW_RTNPARM { $$ = new rpg::Identifier("RTNPARM"); }
    | KW_OPDESC { $$ = new rpg::Identifier("OPDESC"); }
    | KW_NULLIND { $$ = new rpg::Identifier("NULLIND"); }
    | KW_DATFMT { $$ = new rpg::Identifier("DATFMT"); }
    | KW_TIMFMT { $$ = new rpg::Identifier("TIMFMT"); }
    | KW_EXTNAME { $$ = new rpg::Identifier("EXTNAME"); }
    | INDICATOR {
        $$ = new rpg::IndicatorExpr($1);
    }
    | IDENTIFIER DOT IDENTIFIER {
        auto obj = std::unique_ptr<rpg::Expression>(new rpg::Identifier($1));
        $$ = new rpg::DotExpr(std::move(obj), $3);
        free($1);
        free($3);
    }
    | IDENTIFIER LPAREN expression RPAREN {
        $$ = new rpg::ArrayAccess($1, std::unique_ptr<rpg::Expression>($3));
        free($1);
    }
    | IDENTIFIER LPAREN expression RPAREN DOT IDENTIFIER {
        auto* arr = new rpg::ArrayAccess($1, std::unique_ptr<rpg::Expression>($3));
        $$ = new rpg::DotExpr(std::unique_ptr<rpg::Expression>(arr), $6);
        free($1);
        free($6);
    }
    | BIF_ELEM LPAREN arg_list RPAREN {
        $$ = make_bif("ELEM", $3);
    }
    ;

eval_stmt:
    eval_target EQUALS expression SEMICOLON {
        $$ = new rpg::EvalStmt(
            std::unique_ptr<rpg::Expression>($1),
            std::unique_ptr<rpg::Expression>($3)
        );
    }
    | KW_EVAL eval_target EQUALS expression SEMICOLON {
        $$ = new rpg::EvalStmt(
            std::unique_ptr<rpg::Expression>($2),
            std::unique_ptr<rpg::Expression>($4)
        );
    }
    | KW_EVAL_EXT eval_target EQUALS expression SEMICOLON {
        auto* s = new rpg::EvalStmt(
            std::unique_ptr<rpg::Expression>($2),
            std::unique_ptr<rpg::Expression>($4)
        );
        s->extenders = $1; free($1);
        $$ = s;
    }
    ;

eval_corr_stmt:
    KW_EVAL_CORR ident EQUALS ident SEMICOLON {
        $$ = new rpg::EvalCorrStmt(std::string($2), std::string($4));
        free($2);
        free($4);
    }
    ;

xml_into_stmt:
    KW_XML_INTO ident BIF_XML LPAREN expression COLON expression RPAREN SEMICOLON {
        $$ = new rpg::XmlIntoStmt(std::string($2),
            std::unique_ptr<rpg::Expression>($5),
            std::unique_ptr<rpg::Expression>($7));
        free($2);
    }
    | KW_XML_INTO ident BIF_XML LPAREN expression RPAREN SEMICOLON {
        $$ = new rpg::XmlIntoStmt(std::string($2),
            std::unique_ptr<rpg::Expression>($5),
            nullptr);
        free($2);
    }
    ;

data_into_stmt:
    KW_DATA_INTO ident BIF_DATA LPAREN expression COLON expression RPAREN BIF_PARSER LPAREN expression RPAREN SEMICOLON {
        $$ = new rpg::DataIntoStmt(std::string($2),
            std::unique_ptr<rpg::Expression>($5),
            std::unique_ptr<rpg::Expression>($7),
            std::unique_ptr<rpg::Expression>($11));
        free($2);
    }
    | KW_DATA_INTO ident BIF_DATA LPAREN expression COLON expression RPAREN SEMICOLON {
        $$ = new rpg::DataIntoStmt(std::string($2),
            std::unique_ptr<rpg::Expression>($5),
            std::unique_ptr<rpg::Expression>($7),
            nullptr);
        free($2);
    }
    | KW_DATA_INTO ident BIF_DATA LPAREN expression RPAREN BIF_PARSER LPAREN expression RPAREN SEMICOLON {
        $$ = new rpg::DataIntoStmt(std::string($2),
            std::unique_ptr<rpg::Expression>($5),
            nullptr,
            std::unique_ptr<rpg::Expression>($9));
        free($2);
    }
    | KW_DATA_INTO ident BIF_DATA LPAREN expression RPAREN SEMICOLON {
        $$ = new rpg::DataIntoStmt(std::string($2),
            std::unique_ptr<rpg::Expression>($5),
            nullptr, nullptr);
        free($2);
    }
    ;

data_gen_stmt:
    KW_DATA_GEN ident BIF_DATA LPAREN expression COLON expression RPAREN BIF_PARSER LPAREN expression RPAREN SEMICOLON {
        $$ = new rpg::DataGenStmt(std::string($2),
            std::unique_ptr<rpg::Expression>($5),
            std::unique_ptr<rpg::Expression>($7),
            std::unique_ptr<rpg::Expression>($11));
        free($2);
    }
    | KW_DATA_GEN ident BIF_DATA LPAREN expression COLON expression RPAREN SEMICOLON {
        $$ = new rpg::DataGenStmt(std::string($2),
            std::unique_ptr<rpg::Expression>($5),
            std::unique_ptr<rpg::Expression>($7),
            nullptr);
        free($2);
    }
    | KW_DATA_GEN ident BIF_DATA LPAREN expression RPAREN BIF_PARSER LPAREN expression RPAREN SEMICOLON {
        $$ = new rpg::DataGenStmt(std::string($2),
            std::unique_ptr<rpg::Expression>($5),
            nullptr,
            std::unique_ptr<rpg::Expression>($9));
        free($2);
    }
    | KW_DATA_GEN ident BIF_DATA LPAREN expression RPAREN SEMICOLON {
        $$ = new rpg::DataGenStmt(std::string($2),
            std::unique_ptr<rpg::Expression>($5),
            nullptr, nullptr);
        free($2);
    }
    ;

snd_msg_stmt:
    KW_SND_MSG KW_STAR_ESCAPE expression SEMICOLON {
        $$ = new rpg::SndMsgStmt("ESCAPE", std::unique_ptr<rpg::Expression>($3));
    }
    | KW_SND_MSG KW_STAR_INFO expression SEMICOLON {
        $$ = new rpg::SndMsgStmt("INFO", std::unique_ptr<rpg::Expression>($3));
    }
    | KW_SND_MSG KW_STAR_DIAG expression SEMICOLON {
        $$ = new rpg::SndMsgStmt("DIAG", std::unique_ptr<rpg::Expression>($3));
    }
    | KW_SND_MSG KW_TYPE LPAREN KW_STAR_ESCAPE RPAREN expression SEMICOLON {
        $$ = new rpg::SndMsgStmt("ESCAPE", std::unique_ptr<rpg::Expression>($6));
    }
    | KW_SND_MSG KW_TYPE LPAREN KW_STAR_INFO RPAREN expression SEMICOLON {
        $$ = new rpg::SndMsgStmt("INFO", std::unique_ptr<rpg::Expression>($6));
    }
    | KW_SND_MSG KW_TYPE LPAREN KW_STAR_DIAG RPAREN expression SEMICOLON {
        $$ = new rpg::SndMsgStmt("DIAG", std::unique_ptr<rpg::Expression>($6));
    }
    | KW_SND_MSG expression SEMICOLON {
        $$ = new rpg::SndMsgStmt("INFO", std::unique_ptr<rpg::Expression>($2));
    }
    ;

in_da_stmt:
    KW_IN IDENTIFIER SEMICOLON {
        $$ = new rpg::DataInStmt($2);
        free($2);
    }
    ;

out_da_stmt:
    KW_OUT IDENTIFIER SEMICOLON {
        $$ = new rpg::DataOutStmt($2);
        free($2);
    }
    ;

unlock_da_stmt:
    KW_UNLOCK IDENTIFIER SEMICOLON {
        $$ = new rpg::DataUnlockStmt($2);
        free($2);
    }
    ;

evalr_stmt:
    KW_EVALR eval_target EQUALS expression SEMICOLON {
        $$ = new rpg::EvalRStmt(
            std::unique_ptr<rpg::Expression>($2),
            std::unique_ptr<rpg::Expression>($4)
        );
    }
    | KW_EVALR_EXT eval_target EQUALS expression SEMICOLON {
        auto* s = new rpg::EvalRStmt(
            std::unique_ptr<rpg::Expression>($2),
            std::unique_ptr<rpg::Expression>($4)
        );
        s->extenders = $1; free($1);
        $$ = s;
    }
    ;

callp_stmt:
    KW_CALLP expression SEMICOLON {
        $$ = new rpg::CallpStmt(std::unique_ptr<rpg::Expression>($2), "");
    }
    | KW_CALLP_EXT expression SEMICOLON {
        $$ = new rpg::CallpStmt(std::unique_ptr<rpg::Expression>($2), $1);
        free($1);
    }
    ;

leavesr_stmt:
    KW_LEAVESR SEMICOLON {
        $$ = new rpg::LeaveSRStmt();
    }
    ;

dsply_stmt:
    KW_DSPLY expression SEMICOLON {
        $$ = new rpg::DsplyStmt(std::unique_ptr<rpg::Expression>($2));
    }
    ;

inlr_stmt:
    KW_INLR EQUALS KW_ON SEMICOLON {
        $$ = new rpg::ReturnStmt(0);
    }
    ;

return_stmt:
    KW_RETURN expression SEMICOLON {
        $$ = new rpg::ReturnStmt(std::unique_ptr<rpg::Expression>($2));
    }
    | KW_RETURN SEMICOLON {
        $$ = new rpg::ReturnStmt(0);
    }
    ;

/* Expression as statement (for procedure calls) */
expr_stmt:
    IDENTIFIER LPAREN call_args_opt RPAREN SEMICOLON {
        auto* fc = make_func($1, $3);
        free($1);
        $$ = new rpg::ExprStmt(std::unique_ptr<rpg::Expression>(fc));
    }
    ;

/* --- Procedures --- */

/* DCL-PR: prototype/forward declaration */
dcl_pr_stmt:
    KW_DCL_PR IDENTIFIER pi_return_type SEMICOLON pr_params KW_END_PR SEMICOLON {
        rpg::ProcInterface iface;
        if ($3 >= 0) {
            iface.has_return = true;
            iface.return_type = static_cast<rpg::RPGType>($3);
            iface.return_length = 0;
            iface.return_digits = 0;
            iface.return_decimals = 0;
        } else {
            iface.has_return = false;
        }
        iface.params = std::move($5->params);
        delete $5;
        $$ = new rpg::DclPR($2, std::move(iface));
        free($2);
    }
    /* EXTPROC variant */
    | KW_DCL_PR IDENTIFIER pi_return_type KW_EXTPROC LPAREN STRING_LITERAL RPAREN SEMICOLON pr_params KW_END_PR SEMICOLON {
        rpg::ProcInterface iface;
        if ($3 >= 0) {
            iface.has_return = true;
            iface.return_type = static_cast<rpg::RPGType>($3);
            iface.return_length = 0;
            iface.return_digits = 0;
            iface.return_decimals = 0;
        } else {
            iface.has_return = false;
        }
        iface.params = std::move($9->params);
        delete $9;
        auto* pr = new rpg::DclPR($2, std::move(iface));
        pr->extproc = $6;
        free($2);
        free($6);
        $$ = pr;
    }
    /* EXTPGM variant */
    | KW_DCL_PR IDENTIFIER KW_EXTPGM LPAREN STRING_LITERAL RPAREN SEMICOLON pr_params KW_END_PR SEMICOLON {
        rpg::ProcInterface iface;
        iface.has_return = false;
        iface.params = std::move($8->params);
        delete $8;
        auto* pr = new rpg::DclPR($2, std::move(iface));
        pr->extpgm = $5;
        free($2);
        free($5);
        $$ = pr;
    }
    /* OVERLOAD variant */
    | KW_DCL_PR IDENTIFIER KW_OVERLOAD LPAREN overload_list RPAREN SEMICOLON KW_END_PR SEMICOLON {
        auto* pr = new rpg::DclPR($2, rpg::ProcInterface{});
        pr->overload_impls = std::move(*$5);
        delete $5;
        free($2);
        $$ = pr;
    }
    ;

overload_list:
    IDENTIFIER {
        $$ = new std::vector<std::string>();
        $$->push_back($1);
        free($1);
    }
    | overload_list COLON IDENTIFIER {
        $1->push_back($3);
        free($3);
        $$ = $1;
    }
    ;

/* DCL-PROC with embedded DCL-PI */
dcl_proc_stmt:
    KW_DCL_PROC IDENTIFIER proc_export SEMICOLON
    KW_DCL_PI pi_return_type SEMICOLON pi_params KW_END_PI SEMICOLON
    statement_list
    KW_END_PROC SEMICOLON {
        rpg::ProcInterface iface;
        if ($6 >= 0) {
            iface.has_return = true;
            iface.return_type = static_cast<rpg::RPGType>($6);
            iface.return_length = 0;
            iface.return_digits = 0;
            iface.return_decimals = 0;
        } else {
            iface.has_return = false;
        }
        iface.params = std::move($8->params);
        delete $8;
        auto* proc = new rpg::DclProc($2, std::move(iface));
        proc->is_export = ($3 != 0);
        for (auto* s : $<stmt_list>11->stmts) proc->body.emplace_back(s);
        delete $<stmt_list>11;
        free($2);
        $$ = proc;
    }
    /* DCL-PI with explicit name instead of *N */
    | KW_DCL_PROC IDENTIFIER proc_export SEMICOLON
      KW_DCL_PI IDENTIFIER pi_return_type SEMICOLON pi_params KW_END_PI SEMICOLON
      statement_list
      KW_END_PROC SEMICOLON {
        rpg::ProcInterface iface;
        if ($7 >= 0) {
            iface.has_return = true;
            iface.return_type = static_cast<rpg::RPGType>($7);
            iface.return_length = 0;
            iface.return_digits = 0;
            iface.return_decimals = 0;
        } else {
            iface.has_return = false;
        }
        iface.params = std::move($9->params);
        delete $9;
        auto* proc = new rpg::DclProc($2, std::move(iface));
        proc->is_export = ($3 != 0);
        for (auto* s : $<stmt_list>12->stmts) proc->body.emplace_back(s);
        delete $<stmt_list>12;
        free($2);
        free($6);
        $$ = proc;
    }
    /* With ON-EXIT (anonymous PI) */
    | KW_DCL_PROC IDENTIFIER proc_export SEMICOLON
      KW_DCL_PI pi_return_type SEMICOLON pi_params KW_END_PI SEMICOLON
      statement_list
      KW_ON_EXIT SEMICOLON statement_list
      KW_END_PROC SEMICOLON {
        rpg::ProcInterface iface;
        if ($6 >= 0) {
            iface.has_return = true;
            iface.return_type = static_cast<rpg::RPGType>($6);
            iface.return_length = 0;
            iface.return_digits = 0;
            iface.return_decimals = 0;
        } else {
            iface.has_return = false;
        }
        iface.params = std::move($8->params);
        delete $8;
        auto* proc = new rpg::DclProc($2, std::move(iface));
        proc->is_export = ($3 != 0);
        for (auto* s : $<stmt_list>11->stmts) proc->body.emplace_back(s);
        delete $<stmt_list>11;
        for (auto* s : $14->stmts) proc->on_exit_body.emplace_back(s);
        delete $14;
        free($2);
        $$ = proc;
    }
    /* With ON-EXIT (named PI) */
    | KW_DCL_PROC IDENTIFIER proc_export SEMICOLON
      KW_DCL_PI IDENTIFIER pi_return_type SEMICOLON pi_params KW_END_PI SEMICOLON
      statement_list
      KW_ON_EXIT SEMICOLON statement_list
      KW_END_PROC SEMICOLON {
        rpg::ProcInterface iface;
        if ($7 >= 0) {
            iface.has_return = true;
            iface.return_type = static_cast<rpg::RPGType>($7);
            iface.return_length = 0;
            iface.return_digits = 0;
            iface.return_decimals = 0;
        } else {
            iface.has_return = false;
        }
        iface.params = std::move($9->params);
        delete $9;
        auto* proc = new rpg::DclProc($2, std::move(iface));
        proc->is_export = ($3 != 0);
        for (auto* s : $<stmt_list>12->stmts) proc->body.emplace_back(s);
        delete $<stmt_list>12;
        for (auto* s : $15->stmts) proc->on_exit_body.emplace_back(s);
        delete $15;
        free($2);
        free($6);
        $$ = proc;
    }
    ;

proc_export:
    /* empty */ { $$ = 0; }
    | KW_EXPORT { $$ = 1; }
    ;

/* Return type for PI/PR: returns -1 if void, or RPGType enum value */
pi_return_type:
    /* void */ { $$ = -1; }
    | KW_INT LPAREN INTEGER_LITERAL RPAREN { $$ = (int)rpg::RPGType::INT10; }
    | KW_CHAR LPAREN INTEGER_LITERAL RPAREN { $$ = (int)rpg::RPGType::CHAR; }
    | KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN { $$ = (int)rpg::RPGType::VARCHAR; }
    | KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN { $$ = (int)rpg::RPGType::PACKED; }
    | KW_FLOAT_TYPE LPAREN INTEGER_LITERAL RPAREN {
        $$ = ($3 <= 4) ? (int)rpg::RPGType::FLOAT4 : (int)rpg::RPGType::FLOAT8;
    }
    ;

/* Parameters for DCL-PI */
pi_params:
    /* empty */ {
        $$ = new ParamList();
    }
    | pi_params pi_param {
        $$ = $1;
        $$->params.push_back(*$2);
        delete $2;
    }
    ;

pi_param:
    IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::INT10, 0, 0, 0, false};
        free($1);
    }
    | IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::INT10, 0, 0, 0, true};
        free($1);
    }
    | IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::CHAR, $4, 0, 0, false};
        free($1);
    }
    | IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::CHAR, $4, 0, 0, true};
        free($1);
    }
    | IDENTIFIER KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::VARCHAR, $4, 0, 0, false};
        free($1);
    }
    | IDENTIFIER KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::VARCHAR, $4, 0, 0, true};
        free($1);
    }
    | IDENTIFIER KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::PACKED, 0, $4, $6, false};
        free($1);
    }
    | IDENTIFIER KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::PACKED, 0, $4, $6, true};
        free($1);
    }
    | IDENTIFIER KW_FLOAT_TYPE LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        auto type = ($4 <= 4) ? rpg::RPGType::FLOAT4 : rpg::RPGType::FLOAT8;
        $$ = new rpg::ParamDecl{$1, type, 0, 0, 0, false};
        free($1);
    }
    | IDENTIFIER KW_FLOAT_TYPE LPAREN INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        auto type = ($4 <= 4) ? rpg::RPGType::FLOAT4 : rpg::RPGType::FLOAT8;
        $$ = new rpg::ParamDecl{$1, type, 0, 0, 0, true};
        free($1);
    }
    /* DCL-PARM alternatives */
    | KW_DCL_PARM IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$2, rpg::RPGType::INT10, 0, 0, 0, false};
        free($2);
    }
    | KW_DCL_PARM IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        $$ = new rpg::ParamDecl{$2, rpg::RPGType::INT10, 0, 0, 0, true};
        free($2);
    }
    | KW_DCL_PARM IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$2, rpg::RPGType::CHAR, $5, 0, 0, false};
        free($2);
    }
    | KW_DCL_PARM IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        $$ = new rpg::ParamDecl{$2, rpg::RPGType::CHAR, $5, 0, 0, true};
        free($2);
    }
    | KW_DCL_PARM IDENTIFIER KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$2, rpg::RPGType::VARCHAR, $5, 0, 0, false};
        free($2);
    }
    | KW_DCL_PARM IDENTIFIER KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        $$ = new rpg::ParamDecl{$2, rpg::RPGType::VARCHAR, $5, 0, 0, true};
        free($2);
    }
    | KW_DCL_PARM IDENTIFIER KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$2, rpg::RPGType::PACKED, 0, $5, $7, false};
        free($2);
    }
    | KW_DCL_PARM IDENTIFIER KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        $$ = new rpg::ParamDecl{$2, rpg::RPGType::PACKED, 0, $5, $7, true};
        free($2);
    }
    | IDENTIFIER KW_LIKEDS LPAREN IDENTIFIER RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::CHAR, 0, 0, 0, false, std::string($4)};
        free($1);
        free($4);
    }
    /* OPTIONS(*NOPASS) variants */
    | IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN KW_VALUE KW_OPTIONS LPAREN KW_NOPASS RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::INT10, 0, 0, 0, true};
        p->nopass = true;
        $$ = p; free($1);
    }
    | IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_VALUE KW_OPTIONS LPAREN KW_NOPASS RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::CHAR, $4, 0, 0, true};
        p->nopass = true;
        $$ = p; free($1);
    }
    | IDENTIFIER KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN KW_VALUE KW_OPTIONS LPAREN KW_NOPASS RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::VARCHAR, $4, 0, 0, true};
        p->nopass = true;
        $$ = p; free($1);
    }
    | IDENTIFIER KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN KW_VALUE KW_OPTIONS LPAREN KW_NOPASS RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::PACKED, 0, $4, $6, true};
        p->nopass = true;
        $$ = p; free($1);
    }
    /* OPTIONS(*OMIT) variants */
    | IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN KW_OPTIONS LPAREN KW_OMIT RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::INT10, 0, 0, 0, false};
        p->omit = true;
        $$ = p; free($1);
    }
    | IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_OPTIONS LPAREN KW_OMIT RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::CHAR, $4, 0, 0, false};
        p->omit = true;
        $$ = p; free($1);
    }
    | IDENTIFIER KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN KW_OPTIONS LPAREN KW_OMIT RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::VARCHAR, $4, 0, 0, false};
        p->omit = true;
        $$ = p; free($1);
    }
    | IDENTIFIER KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN KW_OPTIONS LPAREN KW_OMIT RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::PACKED, 0, $4, $6, false};
        p->omit = true;
        $$ = p; free($1);
    }
    /* OPTIONS(*NOPASS:*OMIT) combined */
    | IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN KW_OPTIONS LPAREN KW_NOPASS COLON KW_OMIT RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::INT10, 0, 0, 0, false};
        p->nopass = true; p->omit = true;
        $$ = p; free($1);
    }
    | IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_OPTIONS LPAREN KW_NOPASS COLON KW_OMIT RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::CHAR, $4, 0, 0, false};
        p->nopass = true; p->omit = true;
        $$ = p; free($1);
    }
    | IDENTIFIER KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN KW_OPTIONS LPAREN KW_NOPASS COLON KW_OMIT RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::VARCHAR, $4, 0, 0, false};
        p->nopass = true; p->omit = true;
        $$ = p; free($1);
    }
    ;

/* Parameters for DCL-PR (same structure) */
pr_params:
    /* empty */ {
        $$ = new ParamList();
    }
    | pr_params pr_param {
        $$ = $1;
        $$->params.push_back(*$2);
        delete $2;
    }
    ;

pr_param:
    IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::INT10, 0, 0, 0, false};
        free($1);
    }
    | IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::INT10, 0, 0, 0, true};
        free($1);
    }
    | IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::CHAR, $4, 0, 0, false};
        free($1);
    }
    | IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::CHAR, $4, 0, 0, true};
        free($1);
    }
    | IDENTIFIER KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::VARCHAR, $4, 0, 0, false};
        free($1);
    }
    | IDENTIFIER KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::VARCHAR, $4, 0, 0, true};
        free($1);
    }
    | IDENTIFIER KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::PACKED, 0, $4, $6, false};
        free($1);
    }
    | IDENTIFIER KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::PACKED, 0, $4, $6, true};
        free($1);
    }
    /* DCL-PARM alternatives */
    | IDENTIFIER KW_FLOAT_TYPE LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        auto type = ($4 <= 4) ? rpg::RPGType::FLOAT4 : rpg::RPGType::FLOAT8;
        $$ = new rpg::ParamDecl{$1, type, 0, 0, 0, false};
        free($1);
    }
    | IDENTIFIER KW_FLOAT_TYPE LPAREN INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        auto type = ($4 <= 4) ? rpg::RPGType::FLOAT4 : rpg::RPGType::FLOAT8;
        $$ = new rpg::ParamDecl{$1, type, 0, 0, 0, true};
        free($1);
    }
    | KW_DCL_PARM IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$2, rpg::RPGType::INT10, 0, 0, 0, false};
        free($2);
    }
    | KW_DCL_PARM IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        $$ = new rpg::ParamDecl{$2, rpg::RPGType::INT10, 0, 0, 0, true};
        free($2);
    }
    | KW_DCL_PARM IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$2, rpg::RPGType::CHAR, $5, 0, 0, false};
        free($2);
    }
    | KW_DCL_PARM IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        $$ = new rpg::ParamDecl{$2, rpg::RPGType::CHAR, $5, 0, 0, true};
        free($2);
    }
    | KW_DCL_PARM IDENTIFIER KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$2, rpg::RPGType::VARCHAR, $5, 0, 0, false};
        free($2);
    }
    | KW_DCL_PARM IDENTIFIER KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        $$ = new rpg::ParamDecl{$2, rpg::RPGType::VARCHAR, $5, 0, 0, true};
        free($2);
    }
    | KW_DCL_PARM IDENTIFIER KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$2, rpg::RPGType::PACKED, 0, $5, $7, false};
        free($2);
    }
    | KW_DCL_PARM IDENTIFIER KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN KW_VALUE SEMICOLON {
        $$ = new rpg::ParamDecl{$2, rpg::RPGType::PACKED, 0, $5, $7, true};
        free($2);
    }
    | IDENTIFIER KW_LIKEDS LPAREN IDENTIFIER RPAREN SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::CHAR, 0, 0, 0, false, std::string($4)};
        free($1);
        free($4);
    }
    /* OPTIONS(*NOPASS) variants */
    | IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN KW_VALUE KW_OPTIONS LPAREN KW_NOPASS RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::INT10, 0, 0, 0, true};
        p->nopass = true;
        $$ = p; free($1);
    }
    | IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_VALUE KW_OPTIONS LPAREN KW_NOPASS RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::CHAR, $4, 0, 0, true};
        p->nopass = true;
        $$ = p; free($1);
    }
    | IDENTIFIER KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN KW_VALUE KW_OPTIONS LPAREN KW_NOPASS RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::VARCHAR, $4, 0, 0, true};
        p->nopass = true;
        $$ = p; free($1);
    }
    | IDENTIFIER KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN KW_VALUE KW_OPTIONS LPAREN KW_NOPASS RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::PACKED, 0, $4, $6, true};
        p->nopass = true;
        $$ = p; free($1);
    }
    /* OPTIONS(*OMIT) variants */
    | IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN KW_OPTIONS LPAREN KW_OMIT RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::INT10, 0, 0, 0, false};
        p->omit = true;
        $$ = p; free($1);
    }
    | IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_OPTIONS LPAREN KW_OMIT RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::CHAR, $4, 0, 0, false};
        p->omit = true;
        $$ = p; free($1);
    }
    | IDENTIFIER KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN KW_OPTIONS LPAREN KW_OMIT RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::VARCHAR, $4, 0, 0, false};
        p->omit = true;
        $$ = p; free($1);
    }
    | IDENTIFIER KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN KW_OPTIONS LPAREN KW_OMIT RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::PACKED, 0, $4, $6, false};
        p->omit = true;
        $$ = p; free($1);
    }
    /* OPTIONS(*NOPASS:*OMIT) combined */
    | IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN KW_OPTIONS LPAREN KW_NOPASS COLON KW_OMIT RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::INT10, 0, 0, 0, false};
        p->nopass = true; p->omit = true;
        $$ = p; free($1);
    }
    | IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_OPTIONS LPAREN KW_NOPASS COLON KW_OMIT RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::CHAR, $4, 0, 0, false};
        p->nopass = true; p->omit = true;
        $$ = p; free($1);
    }
    | IDENTIFIER KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN KW_OPTIONS LPAREN KW_NOPASS COLON KW_OMIT RPAREN SEMICOLON {
        auto* p = new rpg::ParamDecl{$1, rpg::RPGType::VARCHAR, $4, 0, 0, false};
        p->nopass = true; p->omit = true;
        $$ = p; free($1);
    }
    ;

/* --- Monitor / Subroutines --- */

monitor_stmt:
    KW_MONITOR SEMICOLON statement_list KW_ON_ERROR SEMICOLON statement_list KW_ENDMON SEMICOLON {
        auto* node = new rpg::MonitorStmt();
        for (auto* s : $3->stmts) node->try_body.emplace_back(s);
        delete $3;
        for (auto* s : $6->stmts) node->on_error_body.emplace_back(s);
        delete $6;
        $$ = node;
    }
    ;

begsr_stmt:
    KW_BEGSR IDENTIFIER SEMICOLON statement_list KW_ENDSR SEMICOLON {
        auto* node = new rpg::BegSR($2);
        for (auto* s : $4->stmts) node->body.emplace_back(s);
        delete $4;
        free($2);
        $$ = node;
    }
    ;

exsr_stmt:
    KW_EXSR ident SEMICOLON {
        $$ = new rpg::ExSR($2);
        free($2);
    }
    ;

/* SORTA */
sorta_stmt:
    KW_SORTA ident SEMICOLON {
        $$ = new rpg::SortAStmt($2);
        free($2);
    }
    ;

/* RESET and CLEAR */
reset_stmt:
    KW_RESET ident SEMICOLON {
        $$ = new rpg::ResetStmt($2);
        free($2);
    }
    ;

clear_stmt:
    KW_CLEAR ident SEMICOLON {
        $$ = new rpg::ClearStmt($2);
        free($2);
    }
    ;

/* DUMP */
dump_stmt:
    KW_DUMP SEMICOLON {
        $$ = new rpg::DumpStmt(false);
    }
  | KW_DUMP_A SEMICOLON {
        $$ = new rpg::DumpStmt(true);
    }
  ;

/* DEALLOC */
dealloc_stmt:
    KW_DEALLOC ident SEMICOLON {
        $$ = new rpg::DeallocStmt($2);
        free($2);
    }
    ;

/* TEST */
test_stmt:
    KW_TEST LPAREN ident RPAREN ident SEMICOLON {
        char type = toupper($3[0]);
        $$ = new rpg::TestStmt(type, std::string($5));
        free($3);
        free($5);
    }
    ;

/* --- Embedded SQL --- */

exec_sql_stmt:
    EXEC_SQL_TEXT {
        rpg::SqlStmtKind kind = rpg::classifySqlStmt($1);
        $$ = new rpg::ExecSqlStmt(std::string($1), kind);
        free($1);
    }
    ;

/* --- Enumerations --- */

dcl_enum_stmt:
    KW_DCL_ENUM IDENTIFIER KW_QUALIFIED SEMICOLON enum_constants KW_END_ENUM SEMICOLON {
        auto* e = new rpg::DclEnum($2);
        e->qualified = true;
        e->constants = std::move(*$5);
        delete $5;
        free($2);
        $$ = e;
    }
    | KW_DCL_ENUM IDENTIFIER SEMICOLON enum_constants KW_END_ENUM SEMICOLON {
        auto* e = new rpg::DclEnum($2);
        e->qualified = false;
        e->constants = std::move(*$4);
        delete $4;
        free($2);
        $$ = e;
    }
    ;

enum_constants:
    enum_constant {
        $$ = $1;
    }
    | enum_constants enum_constant {
        $1->insert($1->end(), std::make_move_iterator($2->begin()), std::make_move_iterator($2->end()));
        delete $2;
        $$ = $1;
    }
    ;

enum_constant:
    IDENTIFIER SEMICOLON {
        auto* v = new std::vector<rpg::EnumConstant>();
        rpg::EnumConstant ec;
        ec.name = $1;
        free($1);
        v->push_back(std::move(ec));
        $$ = v;
    }
    | IDENTIFIER EQUALS expression SEMICOLON {
        auto* v = new std::vector<rpg::EnumConstant>();
        rpg::EnumConstant ec;
        ec.name = $1;
        ec.value.reset($3);
        free($1);
        v->push_back(std::move(ec));
        $$ = v;
    }
    ;

/* --- Data Structures --- */

dcl_ds_stmt:
    /* DCL-DS name QUALIFIED; fields END-DS; */
    KW_DCL_DS IDENTIFIER KW_QUALIFIED SEMICOLON ds_fields KW_END_DS SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->qualified = true;
        ds->fields = std::move($5->fields);
        delete $5;
        free($2);
        $$ = ds;
    }
    /* DCL-DS name; fields END-DS; (not qualified) */
    | KW_DCL_DS IDENTIFIER SEMICOLON ds_fields KW_END_DS SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->qualified = false;
        ds->fields = std::move($4->fields);
        delete $4;
        free($2);
        $$ = ds;
    }
    /* DCL-DS name DIM(n) QUALIFIED; fields END-DS; */
    | KW_DCL_DS IDENTIFIER KW_DIM LPAREN INTEGER_LITERAL RPAREN KW_QUALIFIED SEMICOLON ds_fields KW_END_DS SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->dim = $5;
        ds->qualified = true;
        ds->fields = std::move($9->fields);
        delete $9;
        free($2);
        $$ = ds;
    }
    /* DCL-DS name QUALIFIED DIM(n); fields END-DS; */
    | KW_DCL_DS IDENTIFIER KW_QUALIFIED KW_DIM LPAREN INTEGER_LITERAL RPAREN SEMICOLON ds_fields KW_END_DS SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->dim = $6;
        ds->qualified = true;
        ds->fields = std::move($9->fields);
        delete $9;
        free($2);
        $$ = ds;
    }
    /* DCL-DS name DIM(*VAR:n) QUALIFIED; fields END-DS; */
    | KW_DCL_DS IDENTIFIER KW_DIM LPAREN KW_DIM_VAR COLON INTEGER_LITERAL RPAREN KW_QUALIFIED SEMICOLON ds_fields KW_END_DS SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->dim = $7;
        ds->dim_type = 1;
        ds->qualified = true;
        ds->fields = std::move($11->fields);
        delete $11;
        free($2);
        $$ = ds;
    }
    /* DCL-DS name QUALIFIED DIM(*VAR:n); fields END-DS; */
    | KW_DCL_DS IDENTIFIER KW_QUALIFIED KW_DIM LPAREN KW_DIM_VAR COLON INTEGER_LITERAL RPAREN SEMICOLON ds_fields KW_END_DS SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->dim = $8;
        ds->dim_type = 1;
        ds->qualified = true;
        ds->fields = std::move($11->fields);
        delete $11;
        free($2);
        $$ = ds;
    }
    /* DCL-DS name DIM(*AUTO:n) QUALIFIED; fields END-DS; */
    | KW_DCL_DS IDENTIFIER KW_DIM LPAREN KW_DIM_AUTO COLON INTEGER_LITERAL RPAREN KW_QUALIFIED SEMICOLON ds_fields KW_END_DS SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->dim = $7;
        ds->dim_type = 2;
        ds->qualified = true;
        ds->fields = std::move($11->fields);
        delete $11;
        free($2);
        $$ = ds;
    }
    /* DCL-DS name QUALIFIED DIM(*AUTO:n); fields END-DS; */
    | KW_DCL_DS IDENTIFIER KW_QUALIFIED KW_DIM LPAREN KW_DIM_AUTO COLON INTEGER_LITERAL RPAREN SEMICOLON ds_fields KW_END_DS SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->dim = $8;
        ds->dim_type = 2;
        ds->qualified = true;
        ds->fields = std::move($11->fields);
        delete $11;
        free($2);
        $$ = ds;
    }
    /* DCL-DS name LIKEDS(other); */
    | KW_DCL_DS IDENTIFIER KW_LIKEDS LPAREN IDENTIFIER RPAREN SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->like_ds = $5;
        free($2);
        free($5);
        $$ = ds;
    }
    /* DCL-DS name LIKEDS(other) DIM(n); */
    | KW_DCL_DS IDENTIFIER KW_LIKEDS LPAREN IDENTIFIER RPAREN KW_DIM LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->like_ds = $5;
        ds->dim = $9;
        free($2);
        free($5);
        $$ = ds;
    }
    /* DCL-DS name QUALIFIED PREFIX(pfx); fields END-DS; */
    | KW_DCL_DS IDENTIFIER KW_QUALIFIED KW_PREFIX LPAREN IDENTIFIER RPAREN SEMICOLON ds_fields KW_END_DS SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->qualified = true;
        ds->prefix = $6;
        ds->fields = std::move($9->fields);
        delete $9;
        free($2); free($6);
        $$ = ds;
    }
    /* DCL-DS name PREFIX(pfx:n) QUALIFIED; fields END-DS; */
    | KW_DCL_DS IDENTIFIER KW_PREFIX LPAREN IDENTIFIER COLON INTEGER_LITERAL RPAREN KW_QUALIFIED SEMICOLON ds_fields KW_END_DS SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->qualified = true;
        ds->prefix = $5;
        ds->prefix_nbr = $7;
        ds->fields = std::move($11->fields);
        delete $11;
        free($2); free($5);
        $$ = ds;
    }
    /* DCL-DS name QUALIFIED PREFIX(pfx:n); fields END-DS; */
    | KW_DCL_DS IDENTIFIER KW_QUALIFIED KW_PREFIX LPAREN IDENTIFIER COLON INTEGER_LITERAL RPAREN SEMICOLON ds_fields KW_END_DS SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->qualified = true;
        ds->prefix = $6;
        ds->prefix_nbr = $8;
        ds->fields = std::move($11->fields);
        delete $11;
        free($2); free($6);
        $$ = ds;
    }
    /* DCL-DS name PREFIX(pfx); fields END-DS; (not qualified) */
    | KW_DCL_DS IDENTIFIER KW_PREFIX LPAREN IDENTIFIER RPAREN SEMICOLON ds_fields KW_END_DS SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->qualified = false;
        ds->prefix = $5;
        ds->fields = std::move($8->fields);
        delete $8;
        free($2); free($5);
        $$ = ds;
    }
    /* DCL-DS name PSDS QUALIFIED; fields END-DS; */
    | KW_DCL_DS IDENTIFIER psds_kw KW_QUALIFIED SEMICOLON ds_fields KW_END_DS SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->is_psds = true;
        ds->qualified = true;
        ds->fields = std::move($6->fields);
        delete $6;
        free($2);
        $$ = ds;
    }
    /* DCL-DS name QUALIFIED PSDS; fields END-DS; */
    | KW_DCL_DS IDENTIFIER KW_QUALIFIED psds_kw SEMICOLON ds_fields KW_END_DS SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->is_psds = true;
        ds->qualified = true;
        ds->fields = std::move($6->fields);
        delete $6;
        free($2);
        $$ = ds;
    }
    /* DCL-DS name PSDS; fields END-DS; (not qualified) */
    | KW_DCL_DS IDENTIFIER psds_kw SEMICOLON ds_fields KW_END_DS SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->is_psds = true;
        ds->qualified = false;
        ds->fields = std::move($5->fields);
        delete $5;
        free($2);
        $$ = ds;
    }
    /* DCL-DS name PSDS; (empty — no subfields declared) */
    | KW_DCL_DS IDENTIFIER psds_kw SEMICOLON {
        auto* ds = new rpg::DclDS($2);
        ds->is_psds = true;
        ds->qualified = false;
        free($2);
        $$ = ds;
    }
    ;

ds_fields:
    /* empty */ {
        $$ = new DSFieldList();
    }
    | ds_fields ds_field {
        $$ = $1;
        $$->fields.push_back(*$2);
        delete $2;
    }
    ;

psds_kw:
    KW_PSDS {}
    | KW_SDS {}
    ;

ds_field:
    IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::DSField{$1, rpg::RPGType::INT10, 0, 0, 0};
        free($1);
    }
    | IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::DSField{$1, rpg::RPGType::CHAR, $4, 0, 0};
        free($1);
    }
    | IDENTIFIER KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::DSField{$1, rpg::RPGType::VARCHAR, $4, 0, 0};
        free($1);
    }
    | IDENTIFIER KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::DSField{$1, rpg::RPGType::PACKED, 0, $4, $6};
        free($1);
    }
    /* DCL-SUBF alternatives */
    | KW_DCL_SUBF IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::DSField{$2, rpg::RPGType::INT10, 0, 0, 0};
        free($2);
    }
    | KW_DCL_SUBF IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::DSField{$2, rpg::RPGType::CHAR, $5, 0, 0};
        free($2);
    }
    | KW_DCL_SUBF IDENTIFIER KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::DSField{$2, rpg::RPGType::VARCHAR, $5, 0, 0};
        free($2);
    }
    | KW_DCL_SUBF IDENTIFIER KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN SEMICOLON {
        $$ = new rpg::DSField{$2, rpg::RPGType::PACKED, 0, $5, $7};
        free($2);
    }
    /* Fields with POS(n) */
    | IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_POS LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        auto* f = new rpg::DSField{$1, rpg::RPGType::CHAR, $4, 0, 0};
        f->pos = $8;
        free($1);
        $$ = f;
    }
    | IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN KW_POS LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        auto* f = new rpg::DSField{$1, rpg::RPGType::INT10, 0, 0, 0};
        f->pos = $8;
        free($1);
        $$ = f;
    }
    | IDENTIFIER KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN KW_POS LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        auto* f = new rpg::DSField{$1, rpg::RPGType::PACKED, 0, $4, $6};
        f->pos = $10;
        free($1);
        $$ = f;
    }
    /* Fields with OVERLAY(field) */
    | IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_OVERLAY LPAREN IDENTIFIER RPAREN SEMICOLON {
        auto* f = new rpg::DSField{$1, rpg::RPGType::CHAR, $4, 0, 0};
        f->overlay_field = $8;
        free($1); free($8);
        $$ = f;
    }
    /* Fields with OVERLAY(field:pos) */
    | IDENTIFIER KW_CHAR LPAREN INTEGER_LITERAL RPAREN KW_OVERLAY LPAREN IDENTIFIER COLON INTEGER_LITERAL RPAREN SEMICOLON {
        auto* f = new rpg::DSField{$1, rpg::RPGType::CHAR, $4, 0, 0};
        f->overlay_field = $8;
        f->overlay_pos = $10;
        free($1); free($8);
        $$ = f;
    }
    | IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN KW_OVERLAY LPAREN IDENTIFIER RPAREN SEMICOLON {
        auto* f = new rpg::DSField{$1, rpg::RPGType::INT10, 0, 0, 0};
        f->overlay_field = $8;
        free($1); free($8);
        $$ = f;
    }
    | IDENTIFIER KW_INT LPAREN INTEGER_LITERAL RPAREN KW_OVERLAY LPAREN IDENTIFIER COLON INTEGER_LITERAL RPAREN SEMICOLON {
        auto* f = new rpg::DSField{$1, rpg::RPGType::INT10, 0, 0, 0};
        f->overlay_field = $8;
        f->overlay_pos = $10;
        free($1); free($8);
        $$ = f;
    }
    /* LIKEDS subfield: field LIKEDS(dsname); */
    | IDENTIFIER KW_LIKEDS LPAREN IDENTIFIER RPAREN SEMICOLON {
        auto* f = new rpg::DSField{$1, rpg::RPGType::CHAR, 0, 0, 0};
        f->likeds = $4;
        free($1); free($4);
        $$ = f;
    }
    | KW_DCL_SUBF IDENTIFIER KW_LIKEDS LPAREN IDENTIFIER RPAREN SEMICOLON {
        auto* f = new rpg::DSField{$2, rpg::RPGType::CHAR, 0, 0, 0};
        f->likeds = $5;
        free($2); free($5);
        $$ = f;
    }
    ;

/* --- Control Flow --- */

if_stmt:
    KW_IF expression SEMICOLON statement_list elseif_clauses else_clause KW_ENDIF SEMICOLON {
        auto* node = new rpg::IfStmt(std::unique_ptr<rpg::Expression>($2));
        for (auto* s : $4->stmts) node->then_body.emplace_back(s);
        delete $4;
        if ($5) {
            for (auto* eif : *$5) {
                rpg::ElseIfBranch branch;
                branch.condition.reset(eif->cond);
                for (auto* s : eif->body) branch.body.emplace_back(s);
                node->elseif_branches.push_back(std::move(branch));
                delete eif;
            }
            delete $5;
        }
        if ($6) {
            for (auto* s : $6->stmts) node->else_body.emplace_back(s);
            delete $6;
        }
        $$ = node;
    }
    ;

elseif_clauses:
    /* empty */ { $$ = nullptr; }
    | elseif_clauses elseif_clause {
        if (!$1) $1 = new std::vector<ElseIfData*>();
        $$ = $1;
        $$->push_back($2);
    }
    ;

elseif_clause:
    KW_ELSEIF expression SEMICOLON statement_list {
        $$ = new ElseIfData();
        $$->cond = $2;
        $$->body = std::move($4->stmts);
        delete $4;
    }
    ;

else_clause:
    /* empty */ { $$ = nullptr; }
    | KW_ELSE SEMICOLON statement_list {
        $$ = $3;
    }
    ;

dow_stmt:
    KW_DOW expression SEMICOLON statement_list KW_ENDDO SEMICOLON {
        auto* node = new rpg::DowStmt(std::unique_ptr<rpg::Expression>($2));
        for (auto* s : $4->stmts) node->body.emplace_back(s);
        delete $4;
        $$ = node;
    }
    ;

dou_stmt:
    KW_DOU expression SEMICOLON statement_list KW_ENDDO SEMICOLON {
        auto* node = new rpg::DouStmt(std::unique_ptr<rpg::Expression>($2));
        for (auto* s : $4->stmts) node->body.emplace_back(s);
        delete $4;
        $$ = node;
    }
    ;

for_stmt:
    KW_FOR ident EQUALS expression KW_TO expression SEMICOLON statement_list KW_ENDFOR SEMICOLON {
        auto* node = new rpg::ForStmt($2,
            std::unique_ptr<rpg::Expression>($4),
            std::unique_ptr<rpg::Expression>($6),
            nullptr, false);
        for (auto* s : $8->stmts) node->body.emplace_back(s);
        delete $8;
        free($2);
        $$ = node;
    }
    | KW_FOR ident EQUALS expression KW_TO expression KW_BY expression SEMICOLON statement_list KW_ENDFOR SEMICOLON {
        auto* node = new rpg::ForStmt($2,
            std::unique_ptr<rpg::Expression>($4),
            std::unique_ptr<rpg::Expression>($6),
            std::unique_ptr<rpg::Expression>($8), false);
        for (auto* s : $10->stmts) node->body.emplace_back(s);
        delete $10;
        free($2);
        $$ = node;
    }
    | KW_FOR ident EQUALS expression KW_DOWNTO expression SEMICOLON statement_list KW_ENDFOR SEMICOLON {
        auto* node = new rpg::ForStmt($2,
            std::unique_ptr<rpg::Expression>($4),
            std::unique_ptr<rpg::Expression>($6),
            nullptr, true);
        for (auto* s : $8->stmts) node->body.emplace_back(s);
        delete $8;
        free($2);
        $$ = node;
    }
    | KW_FOR ident EQUALS expression KW_DOWNTO expression KW_BY expression SEMICOLON statement_list KW_ENDFOR SEMICOLON {
        auto* node = new rpg::ForStmt($2,
            std::unique_ptr<rpg::Expression>($4),
            std::unique_ptr<rpg::Expression>($6),
            std::unique_ptr<rpg::Expression>($8), true);
        for (auto* s : $10->stmts) node->body.emplace_back(s);
        delete $10;
        free($2);
        $$ = node;
    }
    ;

for_each_stmt:
    KW_FOR_EACH ident KW_IN expression SEMICOLON statement_list KW_ENDFOR SEMICOLON {
        auto* node = new rpg::ForEachStmt($2, std::unique_ptr<rpg::Expression>($4));
        for (auto* s : $6->stmts) node->body.emplace_back(s);
        delete $6;
        free($2);
        $$ = node;
    }
    ;

select_stmt:
    KW_SELECT SEMICOLON when_clauses other_clause KW_ENDSL SEMICOLON {
        auto* node = new rpg::SelectStmt();
        for (auto* w : *$3) {
            rpg::WhenBranch branch;
            branch.condition.reset(w->cond);
            for (auto* s : w->body) branch.body.emplace_back(s);
            node->when_branches.push_back(std::move(branch));
            delete w;
        }
        delete $3;
        if ($4) {
            for (auto* s : $4->stmts) node->other_body.emplace_back(s);
            delete $4;
        }
        $$ = node;
    }
    ;

when_clauses:
    when_clause {
        $$ = new std::vector<WhenData*>();
        $$->push_back($1);
    }
    | when_clauses when_clause {
        $$ = $1;
        $$->push_back($2);
    }
    ;

when_clause:
    KW_WHEN expression SEMICOLON statement_list {
        $$ = new WhenData();
        $$->cond = $2;
        $$->body = std::move($4->stmts);
        delete $4;
    }
    ;

other_clause:
    /* empty */ { $$ = nullptr; }
    | KW_OTHER SEMICOLON statement_list {
        $$ = $3;
    }
    ;

iter_stmt:
    KW_ITER SEMICOLON { $$ = new rpg::IterStmt(); }
    ;

leave_stmt:
    KW_LEAVE SEMICOLON { $$ = new rpg::LeaveStmt(); }
    ;

/* --- Expressions --- */

expression:
    or_expr { $$ = $1; }
    ;

or_expr:
    and_expr { $$ = $1; }
    | or_expr KW_OR and_expr {
        $$ = new rpg::BinaryExpr(rpg::BinOp::OR,
            std::unique_ptr<rpg::Expression>($1),
            std::unique_ptr<rpg::Expression>($3));
    }
    ;

and_expr:
    not_expr { $$ = $1; }
    | and_expr KW_AND not_expr {
        $$ = new rpg::BinaryExpr(rpg::BinOp::AND,
            std::unique_ptr<rpg::Expression>($1),
            std::unique_ptr<rpg::Expression>($3));
    }
    ;

not_expr:
    comparison_expr { $$ = $1; }
    | KW_NOT comparison_expr {
        $$ = new rpg::NotExpr(std::unique_ptr<rpg::Expression>($2));
    }
    ;

comparison_expr:
    additive_expr { $$ = $1; }
    | comparison_expr EQUALS additive_expr {
        $$ = new rpg::BinaryExpr(rpg::BinOp::EQ,
            std::unique_ptr<rpg::Expression>($1),
            std::unique_ptr<rpg::Expression>($3));
    }
    | comparison_expr NE additive_expr {
        $$ = new rpg::BinaryExpr(rpg::BinOp::NE,
            std::unique_ptr<rpg::Expression>($1),
            std::unique_ptr<rpg::Expression>($3));
    }
    | comparison_expr LT additive_expr {
        $$ = new rpg::BinaryExpr(rpg::BinOp::LT,
            std::unique_ptr<rpg::Expression>($1),
            std::unique_ptr<rpg::Expression>($3));
    }
    | comparison_expr GT additive_expr {
        $$ = new rpg::BinaryExpr(rpg::BinOp::GT,
            std::unique_ptr<rpg::Expression>($1),
            std::unique_ptr<rpg::Expression>($3));
    }
    | comparison_expr LE additive_expr {
        $$ = new rpg::BinaryExpr(rpg::BinOp::LE,
            std::unique_ptr<rpg::Expression>($1),
            std::unique_ptr<rpg::Expression>($3));
    }
    | comparison_expr GE additive_expr {
        $$ = new rpg::BinaryExpr(rpg::BinOp::GE,
            std::unique_ptr<rpg::Expression>($1),
            std::unique_ptr<rpg::Expression>($3));
    }
    | additive_expr KW_IN additive_expr {
        $$ = new rpg::InExpr(
            std::unique_ptr<rpg::Expression>($1),
            std::unique_ptr<rpg::Expression>($3));
    }
    ;

additive_expr:
    multiplicative_expr { $$ = $1; }
    | additive_expr PLUS multiplicative_expr {
        $$ = new rpg::BinaryExpr(rpg::BinOp::ADD,
            std::unique_ptr<rpg::Expression>($1),
            std::unique_ptr<rpg::Expression>($3));
    }
    | additive_expr MINUS multiplicative_expr {
        $$ = new rpg::BinaryExpr(rpg::BinOp::SUB,
            std::unique_ptr<rpg::Expression>($1),
            std::unique_ptr<rpg::Expression>($3));
    }
    ;

multiplicative_expr:
    power_expr { $$ = $1; }
    | multiplicative_expr STAR power_expr {
        $$ = new rpg::BinaryExpr(rpg::BinOp::MUL,
            std::unique_ptr<rpg::Expression>($1),
            std::unique_ptr<rpg::Expression>($3));
    }
    | multiplicative_expr SLASH power_expr {
        $$ = new rpg::BinaryExpr(rpg::BinOp::DIV,
            std::unique_ptr<rpg::Expression>($1),
            std::unique_ptr<rpg::Expression>($3));
    }
    ;

power_expr:
    unary_expr { $$ = $1; }
    | unary_expr POWER power_expr {
        $$ = new rpg::BinaryExpr(rpg::BinOp::POWER,
            std::unique_ptr<rpg::Expression>($1),
            std::unique_ptr<rpg::Expression>($3));
    }
    ;

unary_expr:
    postfix_expr { $$ = $1; }
    | MINUS postfix_expr {
        $$ = new rpg::BinaryExpr(rpg::BinOp::SUB,
            std::unique_ptr<rpg::Expression>(new rpg::IntLiteral(0)),
            std::unique_ptr<rpg::Expression>($2));
    }
    ;

postfix_expr:
    primary_expr { $$ = $1; }
    | postfix_expr DOT IDENTIFIER {
        $$ = new rpg::DotExpr(std::unique_ptr<rpg::Expression>($1), $3);
        free($3);
    }
    ;

ident:
    IDENTIFIER { $$ = $1; }
    | KW_UNS { $$ = strdup("UNS"); }
    | KW_FLOAT_TYPE { $$ = strdup("FLOAT"); }
    | KW_GRAPH { $$ = strdup("GRAPH"); }
    | KW_ASCEND { $$ = strdup("ASCEND"); }
    | KW_DESCEND { $$ = strdup("DESCEND"); }
    | KW_IN { $$ = strdup("IN"); }
    | KW_RTNPARM { $$ = strdup("RTNPARM"); }
    | KW_OPDESC { $$ = strdup("OPDESC"); }
    | KW_NULLIND { $$ = strdup("NULLIND"); }
    | KW_DATFMT { $$ = strdup("DATFMT"); }
    | KW_TIMFMT { $$ = strdup("TIMFMT"); }
    | KW_EXTNAME { $$ = strdup("EXTNAME"); }
    | KW_OVERLAY { $$ = strdup("OVERLAY"); }
    | KW_POS { $$ = strdup("POS"); }
    | KW_PREFIX { $$ = strdup("PREFIX"); }
    ;

primary_expr:
    IDENTIFIER {
        $$ = new rpg::Identifier($1);
        free($1);
    }
    | KW_UNS { $$ = new rpg::Identifier("UNS"); }
    | KW_FLOAT_TYPE { $$ = new rpg::Identifier("FLOAT"); }
    | KW_GRAPH { $$ = new rpg::Identifier("GRAPH"); }
    | KW_ASCEND { $$ = new rpg::Identifier("ASCEND"); }
    | KW_DESCEND { $$ = new rpg::Identifier("DESCEND"); }
    | KW_RTNPARM { $$ = new rpg::Identifier("RTNPARM"); }
    | KW_OPDESC { $$ = new rpg::Identifier("OPDESC"); }
    | KW_NULLIND { $$ = new rpg::Identifier("NULLIND"); }
    | KW_DATFMT { $$ = new rpg::Identifier("DATFMT"); }
    | KW_OVERLAY { $$ = new rpg::Identifier("OVERLAY"); }
    | KW_POS { $$ = new rpg::Identifier("POS"); }
    | KW_PREFIX { $$ = new rpg::Identifier("PREFIX"); }
    | KW_TIMFMT { $$ = new rpg::Identifier("TIMFMT"); }
    | KW_EXTNAME { $$ = new rpg::Identifier("EXTNAME"); }
    | INTEGER_LITERAL {
        $$ = new rpg::IntLiteral($1);
    }
    | FLOAT_LITERAL {
        $$ = new rpg::FloatLiteral($1);
    }
    | STRING_LITERAL {
        $$ = new rpg::StringLiteral($1);
        free($1);
    }
    | IDENTIFIER LPAREN call_args_opt RPAREN {
        $$ = make_func($1, $3);
        free($1);
    }
    | BIF_CHAR LPAREN arg_list RPAREN {
        $$ = make_bif("CHAR", $3);
    }
    | BIF_TRIM LPAREN arg_list RPAREN {
        $$ = make_bif("TRIM", $3);
    }
    | BIF_TRIML LPAREN arg_list RPAREN {
        $$ = make_bif("TRIML", $3);
    }
    | BIF_TRIMR LPAREN arg_list RPAREN {
        $$ = make_bif("TRIMR", $3);
    }
    | BIF_LEN LPAREN arg_list RPAREN {
        $$ = make_bif("LEN", $3);
    }
    | BIF_SUBST LPAREN arg_list RPAREN {
        $$ = make_bif("SUBST", $3);
    }
    | BIF_SCAN LPAREN arg_list RPAREN {
        $$ = make_bif("SCAN", $3);
    }
    | BIF_SCANRPL LPAREN arg_list RPAREN {
        $$ = make_bif("SCANRPL", $3);
    }
    | BIF_XLATE LPAREN arg_list RPAREN {
        $$ = make_bif("XLATE", $3);
    }
    | BIF_DEC LPAREN arg_list RPAREN {
        $$ = make_bif("DEC", $3);
    }
    | BIF_INT LPAREN arg_list RPAREN {
        $$ = make_bif("INT", $3);
    }
    | BIF_ELEM LPAREN arg_list RPAREN {
        $$ = make_bif("ELEM", $3);
    }
    | BIF_PARMS LPAREN RPAREN {
        auto* empty = new std::vector<rpg::Expression*>();
        $$ = make_bif("PARMS", empty);
    }
    | BIF_LOOKUP LPAREN arg_list RPAREN {
        $$ = make_bif("LOOKUP", $3);
    }
    | BIF_EDITC LPAREN arg_list RPAREN {
        $$ = make_bif("EDITC", $3);
    }
    | BIF_EDITW LPAREN arg_list RPAREN {
        $$ = make_bif("EDITW", $3);
    }
    | BIF_REPLACE LPAREN arg_list RPAREN {
        $$ = make_bif("REPLACE", $3);
    }
    | BIF_CHECK LPAREN arg_list RPAREN {
        $$ = make_bif("CHECK", $3);
    }
    | BIF_CHECKR LPAREN arg_list RPAREN {
        $$ = make_bif("CHECKR", $3);
    }
    | BIF_LOWER LPAREN arg_list RPAREN {
        $$ = make_bif("LOWER", $3);
    }
    | BIF_UPPER LPAREN arg_list RPAREN {
        $$ = make_bif("UPPER", $3);
    }
    | BIF_SUBDT LPAREN expression COLON KW_YEARS RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        args->push_back(new rpg::StringLiteral("YEARS"));
        $$ = make_bif("SUBDT", args);
    }
    | BIF_SUBDT LPAREN expression COLON KW_MONTHS RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        args->push_back(new rpg::StringLiteral("MONTHS"));
        $$ = make_bif("SUBDT", args);
    }
    | BIF_SUBDT LPAREN expression COLON KW_DAYS RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        args->push_back(new rpg::StringLiteral("DAYS"));
        $$ = make_bif("SUBDT", args);
    }
    | BIF_SUBDT LPAREN expression COLON KW_HOURS RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        args->push_back(new rpg::StringLiteral("HOURS"));
        $$ = make_bif("SUBDT", args);
    }
    | BIF_SUBDT LPAREN expression COLON KW_MINUTES RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        args->push_back(new rpg::StringLiteral("MINUTES"));
        $$ = make_bif("SUBDT", args);
    }
    | BIF_SUBDT LPAREN expression COLON KW_SECONDS RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        args->push_back(new rpg::StringLiteral("SECONDS"));
        $$ = make_bif("SUBDT", args);
    }
    | BIF_FLOAT LPAREN arg_list RPAREN {
        $$ = make_bif("FLOAT", $3);
    }
    | BIF_SQRT LPAREN arg_list RPAREN {
        $$ = make_bif("SQRT", $3);
    }
    | BIF_MAX LPAREN arg_list RPAREN {
        $$ = make_bif("MAX", $3);
    }
    | BIF_MIN LPAREN arg_list RPAREN {
        $$ = make_bif("MIN", $3);
    }
    | BIF_STATUS LPAREN RPAREN {
        auto* empty = new std::vector<rpg::Expression*>();
        $$ = make_bif("STATUS", empty);
    }
    | BIF_ERROR LPAREN RPAREN {
        auto* empty = new std::vector<rpg::Expression*>();
        $$ = make_bif("ERROR", empty);
    }
    | BIF_SIZE LPAREN arg_list RPAREN {
        $$ = make_bif("SIZE", $3);
    }
    | BIF_ADDR LPAREN arg_list RPAREN {
        $$ = make_bif("ADDR", $3);
    }
    | BIF_ABS LPAREN arg_list RPAREN {
        $$ = make_bif("ABS", $3);
    }
    | BIF_DIV LPAREN arg_list RPAREN {
        $$ = make_bif("DIV", $3);
    }
    | BIF_REM LPAREN arg_list RPAREN {
        $$ = make_bif("REM", $3);
    }
    | BIF_DATE LPAREN arg_list RPAREN {
        $$ = make_bif("DATE", $3);
    }
    | BIF_DATE LPAREN RPAREN {
        auto* empty = new std::vector<rpg::Expression*>();
        $$ = make_bif("DATE", empty);
    }
    | BIF_TIME LPAREN arg_list RPAREN {
        $$ = make_bif("TIME", $3);
    }
    | BIF_TIME LPAREN RPAREN {
        auto* empty = new std::vector<rpg::Expression*>();
        $$ = make_bif("TIME", empty);
    }
    | BIF_TIMESTAMP LPAREN arg_list RPAREN {
        $$ = make_bif("TIMESTAMP", $3);
    }
    | BIF_TIMESTAMP LPAREN RPAREN {
        auto* empty = new std::vector<rpg::Expression*>();
        $$ = make_bif("TIMESTAMP", empty);
    }
    | BIF_DIFF LPAREN expression COLON expression COLON KW_DAYS RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        args->push_back($5);
        args->push_back(new rpg::StringLiteral("DAYS"));
        $$ = make_bif("DIFF", args);
    }
    | BIF_DIFF LPAREN expression COLON expression COLON KW_MONTHS RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        args->push_back($5);
        args->push_back(new rpg::StringLiteral("MONTHS"));
        $$ = make_bif("DIFF", args);
    }
    | BIF_DIFF LPAREN expression COLON expression COLON KW_YEARS RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        args->push_back($5);
        args->push_back(new rpg::StringLiteral("YEARS"));
        $$ = make_bif("DIFF", args);
    }
    | BIF_DAYS LPAREN expression RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        $$ = make_bif("DAYS", args);
    }
    | BIF_MONTHS LPAREN expression RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        $$ = make_bif("MONTHS", args);
    }
    | BIF_YEARS LPAREN expression RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        $$ = make_bif("YEARS", args);
    }
    | BIF_FOUND LPAREN RPAREN {
        auto* empty = new std::vector<rpg::Expression*>();
        $$ = make_bif("FOUND", empty);
    }
    | BIF_FOUND LPAREN IDENTIFIER RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back(new rpg::Identifier($3));
        free($3);
        $$ = make_bif("FOUND", args);
    }
    | BIF_EOF LPAREN RPAREN {
        auto* empty = new std::vector<rpg::Expression*>();
        $$ = make_bif("EOF", empty);
    }
    | BIF_EOF LPAREN IDENTIFIER RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back(new rpg::Identifier($3));
        free($3);
        $$ = make_bif("EOF", args);
    }
    | BIF_ALLOC LPAREN arg_list RPAREN {
        $$ = make_bif("ALLOC", $3);
    }
    | BIF_REALLOC LPAREN arg_list RPAREN {
        $$ = make_bif("REALLOC", $3);
    }
    | BIF_XFOOT LPAREN arg_list RPAREN {
        $$ = make_bif("XFOOT", $3);
    }
    | BIF_UNS LPAREN arg_list RPAREN {
        $$ = make_bif("UNS", $3);
    }
    | BIF_INTH LPAREN arg_list RPAREN {
        $$ = make_bif("INTH", $3);
    }
    | BIF_DECH LPAREN arg_list RPAREN {
        $$ = make_bif("DECH", $3);
    }
    | BIF_DECPOS LPAREN arg_list RPAREN {
        $$ = make_bif("DECPOS", $3);
    }
    | BIF_SPLIT LPAREN arg_list RPAREN {
        $$ = make_bif("SPLIT", $3);
    }
    | BIF_CONCAT LPAREN arg_list RPAREN {
        $$ = make_bif("CONCAT", $3);
    }
    | BIF_CONCATARR LPAREN arg_list RPAREN {
        $$ = make_bif("CONCATARR", $3);
    }
    | BIF_LEFT LPAREN arg_list RPAREN {
        $$ = make_bif("LEFT", $3);
    }
    | BIF_RIGHT LPAREN arg_list RPAREN {
        $$ = make_bif("RIGHT", $3);
    }
    | BIF_STR LPAREN arg_list RPAREN {
        $$ = make_bif("STR", $3);
    }
    | BIF_SUBARR LPAREN arg_list RPAREN {
        $$ = make_bif("SUBARR", $3);
    }
    | BIF_MAXARR LPAREN arg_list RPAREN {
        $$ = make_bif("MAXARR", $3);
    }
    | BIF_MINARR LPAREN arg_list RPAREN {
        $$ = make_bif("MINARR", $3);
    }
    | BIF_LIST LPAREN arg_list RPAREN {
        $$ = make_bif("LIST", $3);
    }
    | BIF_RANGE LPAREN arg_list RPAREN {
        $$ = make_bif("RANGE", $3);
    }
    | BIF_LOOKUPLT LPAREN arg_list RPAREN {
        $$ = make_bif("LOOKUPLT", $3);
    }
    | BIF_LOOKUPGE LPAREN arg_list RPAREN {
        $$ = make_bif("LOOKUPGE", $3);
    }
    | BIF_LOOKUPLE LPAREN arg_list RPAREN {
        $$ = make_bif("LOOKUPLE", $3);
    }
    | BIF_LOOKUPGT LPAREN arg_list RPAREN {
        $$ = make_bif("LOOKUPGT", $3);
    }
    | BIF_TLOOKUP LPAREN arg_list RPAREN {
        $$ = make_bif("TLOOKUP", $3);
    }
    | BIF_TLOOKUPLT LPAREN arg_list RPAREN {
        $$ = make_bif("TLOOKUPLT", $3);
    }
    | BIF_TLOOKUPGT LPAREN arg_list RPAREN {
        $$ = make_bif("TLOOKUPGT", $3);
    }
    | BIF_TLOOKUPLE LPAREN arg_list RPAREN {
        $$ = make_bif("TLOOKUPLE", $3);
    }
    | BIF_TLOOKUPGE LPAREN arg_list RPAREN {
        $$ = make_bif("TLOOKUPGE", $3);
    }
    | BIF_HOURS LPAREN expression RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        $$ = make_bif("HOURS", args);
    }
    | BIF_MINUTES LPAREN expression RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        $$ = make_bif("MINUTES", args);
    }
    | BIF_SECONDS LPAREN expression RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        $$ = make_bif("SECONDS", args);
    }
    | BIF_MSECONDS LPAREN expression RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        $$ = make_bif("MSECONDS", args);
    }
    | BIF_PADDR LPAREN IDENTIFIER RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back(new rpg::StringLiteral($3));
        free($3);
        $$ = make_bif("PADDR", args);
    }
    | BIF_PROC LPAREN RPAREN {
        auto* empty = new std::vector<rpg::Expression*>();
        $$ = make_bif("PROC", empty);
    }
    | BIF_PROC {
        auto* empty = new std::vector<rpg::Expression*>();
        $$ = make_bif("PROC", empty);
    }
    | BIF_DIFF LPAREN expression COLON expression COLON KW_HOURS RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        args->push_back($5);
        args->push_back(new rpg::StringLiteral("HOURS"));
        $$ = make_bif("DIFF", args);
    }
    | BIF_DIFF LPAREN expression COLON expression COLON KW_MINUTES RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        args->push_back($5);
        args->push_back(new rpg::StringLiteral("MINUTES"));
        $$ = make_bif("DIFF", args);
    }
    | BIF_DIFF LPAREN expression COLON expression COLON KW_SECONDS RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        args->push_back($5);
        args->push_back(new rpg::StringLiteral("SECONDS"));
        $$ = make_bif("DIFF", args);
    }
    | KW_ALL STRING_LITERAL {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back(new rpg::StringLiteral($2));
        free($2);
        $$ = make_bif("ALL", args);
    }
    | BIF_PASSED LPAREN ident RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back(new rpg::Identifier($3));
        free($3);
        $$ = make_bif("PASSED", args);
    }
    | BIF_OMITTED LPAREN ident RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back(new rpg::Identifier($3));
        free($3);
        $$ = make_bif("OMITTED", args);
    }
    | BIF_BITAND LPAREN arg_list RPAREN {
        $$ = make_bif("BITAND", $3);
    }
    | BIF_BITNOT LPAREN arg_list RPAREN {
        $$ = make_bif("BITNOT", $3);
    }
    | BIF_BITOR LPAREN arg_list RPAREN {
        $$ = make_bif("BITOR", $3);
    }
    | BIF_BITXOR LPAREN arg_list RPAREN {
        $$ = make_bif("BITXOR", $3);
    }
    | BIF_SCANR LPAREN arg_list RPAREN {
        $$ = make_bif("SCANR", $3);
    }
    | BIF_EDITFLT LPAREN arg_list RPAREN {
        $$ = make_bif("EDITFLT", $3);
    }
    | BIF_UNSH LPAREN arg_list RPAREN {
        $$ = make_bif("UNSH", $3);
    }
    | BIF_PARMNUM LPAREN ident RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back(new rpg::Identifier($3));
        free($3);
        $$ = make_bif("PARMNUM", args);
    }
    | BIF_GETENV LPAREN arg_list RPAREN {
        $$ = make_bif("GETENV", $3);
    }
    | INDICATOR {
        $$ = new rpg::IndicatorExpr($1);
    }
    | KW_ON {
        $$ = new rpg::IntLiteral(1);  // *ON → true
    }
    | KW_OFF {
        $$ = new rpg::IntLiteral(0);  // *OFF → false
    }
    | KW_NULL {
        $$ = new rpg::Identifier("nullptr");
    }
    | KW_OMIT {
        $$ = new rpg::Identifier("nullptr");
    }
    | KW_USER {
        $$ = new rpg::Identifier("RPG_USER");
        if (g_program) g_program->uses_user_const = true;
    }
    | KW_BLANKS {
        $$ = new rpg::Identifier("RPG_BLANKS");
    }
    | KW_ZEROS {
        $$ = new rpg::Identifier("RPG_ZEROS");
    }
    | KW_HIVAL {
        $$ = new rpg::Identifier("RPG_HIVAL");
    }
    | KW_LOVAL {
        $$ = new rpg::Identifier("RPG_LOVAL");
    }
    | KW_STAR_ALLOC {
        $$ = new rpg::Identifier("__ALLOC");
    }
    | KW_STAR_KEEP {
        $$ = new rpg::Identifier("__KEEP");
    }
    | LPAREN expression RPAREN {
        $$ = $2;
    }
    ;

/* Function call arguments use comma separator */
call_args_opt:
    /* empty */ { $$ = nullptr; }
    | call_arg_list { $$ = $1; }
    ;

call_arg_list:
    expression {
        $$ = new std::vector<rpg::Expression*>();
        $$->push_back($1);
    }
    | call_arg_list COLON expression {
        $$ = $1;
        $$->push_back($3);
    }
    ;

/* BIF arguments use colon separator */
arg_list:
    expression {
        $$ = new std::vector<rpg::Expression*>();
        $$->push_back($1);
    }
    | arg_list COLON expression {
        $$ = $1;
        $$->push_back($3);
    }
    ;

%%

void yyerror(const char* s) {
    g_error_count++;
    const char* token = yytext;
    if (token == NULL || token[0] == '\0') {
        fprintf(stderr, "Error at line %d: %s (unexpected end of file)\n", yylineno, s);
    } else {
        fprintf(stderr, "Error at line %d: %s (near '%s')\n", yylineno, s, token);
    }
}

rpg::Program* get_parsed_program() {
    g_program = new rpg::Program();
    g_error_count = 0;
    yyparse();
    return g_program;
}

int get_parse_error_count() {
    return g_error_count;
}

std::vector<std::unique_ptr<rpg::Statement>>
parse_free_block(const std::string& text, int start_line) {
    // Save every piece of global lexer/parser state this touches, so
    // control returns to whatever the caller (the fixed-format reader,
    // via main.cpp) was doing with none of it disturbed.
    rpg::Program* saved_program = g_program;
    int saved_lineno = yylineno;

    g_program = new rpg::Program();
    yylineno = start_line;
    YY_BUFFER_STATE buf = yy_scan_string(text.c_str());
    yy_switch_to_buffer(buf);
    // Deliberately NOT resetting g_error_count here (unlike
    // get_parsed_program()) — a syntax error inside a /free block is a
    // real error in the overall compilation unit and must add to the
    // same count main.cpp already gates on, not reset/hide it.
    yyparse();
    yy_delete_buffer(buf);

    std::vector<std::unique_ptr<rpg::Statement>> stmts = std::move(g_program->statements);
    delete g_program;

    g_program = saved_program;
    yylineno = saved_lineno;
    return stmts;
}

void report_fixed_format_error(int line, const std::string& msg) {
    g_error_count++;
    fprintf(stderr, "Error at line %d: %s\n", line, msg.c_str());
}
