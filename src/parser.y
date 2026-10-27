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

// DCL-S keywords, collected by dcl_kws (see dcl_s_stmt).
struct DclSKws {
    int flags = 0;          // 1 STATIC, 2 TEMPLATE, 4 EXPORT, 8 IMPORT
    bool is_const = false;
    rpg::Expression* inz = nullptr;
    int dim = 0;
    int dim_type = 0;       // 0 fixed, 1 *VAR, 2 *AUTO
    int sort = 0;           // 1 ASCEND, -1 DESCEND
    bool ctdata = false;    // CTDATA
    int perrcd = 1;         // PERRCD(n)
    std::string based, dtaara, datfmt, timfmt;
    std::string dtaara_var; // DTAARA(var)
    bool dtaara_self = false; // bare DTAARA
};
}

%{
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <strings.h>
#include <memory>
#include <vector>
#include <string>
#include "ast.h"
#include "free_bridge.h"
#include "sql_utils.h"

extern int yylex();
extern int yylineno;
extern char* yytext;
extern int g_semi_line;   // lexer.l: line of the last semicolon
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

// Declared extern in free_bridge.h — see that header for why GOTO/TAG need
// this gate (no free-form syntax exists for either per SC09-2508).
bool g_allow_fixed_only_stmts = false;

rpg::Program* get_parsed_program();
int get_parse_error_count();

// CTL-OPT values extracted by lexer
extern char ctlopt_main_proc[256];
extern char ctlopt_datfmt[64];
extern char ctlopt_timfmt[64];
extern bool ctlopt_nomain;
extern bool ctlopt_debug_dump;
extern bool ctlopt_nolenchk;

// Set line number on AST node
#define SET_LINE(node) do { if (node) (node)->line = yylineno; } while(0)

// Each indicator's first reference as a value, and whether anything sets
// it, across every parse of the source (the fixed-format reader parses its
// calculations a block at a time). IBM i rejects a program that refers to
// an indicator nothing sets: RNF7030, "The name or indicator *IN55 is not
// defined". check_indicators_defined (main.cpp, once the whole source is
// parsed) reports them. Indexed by IndicatorExpr number: LR 0, 01-99,
// H1-H9 101-109.
int g_ind_tested_line[110];
bool g_ind_set[110];

// The *IN array used as such -- *IN(i), or *IN itself -- which on IBM i
// leaves 01-99 unchecked, since any of them may be set through it.
bool g_ind_array_used;

void reset_indicator_uses() {
    for (int i = 0; i < 110; i++) { g_ind_tested_line[i] = 0; g_ind_set[i] = false; }
    g_ind_array_used = false;
}

// *IN(index), or *IN itself when index is null. Reading *IN whole (in
// %LOOKUP, say) does not count as using it to set indicators.
static rpg::Expression* make_ind_array(rpg::Expression* index, bool sets = true) {
    if (sets) g_ind_array_used = true;
    auto* ind = new rpg::IndicatorExpr(rpg::IndicatorExpr::ARRAY);
    ind->index.reset(index);
    return ind;
}

// The value of target op= value: target op (value), with the target copied,
// since it is also the assignment's left-hand side.
static rpg::Expression* compound_value(rpg::Expression* target, int op, rpg::Expression* value) {
    static const rpg::BinOp ops[] = {rpg::BinOp::ADD, rpg::BinOp::SUB, rpg::BinOp::MUL,
                                     rpg::BinOp::DIV, rpg::BinOp::POWER};
    auto* e = new rpg::BinaryExpr(ops[op], rpg::cloneExpr(*target),
                                  std::unique_ptr<rpg::Expression>(value));
    e->line = value->line;
    return e;
}

// DCL-F option globals (reset at start of each dclf_opts parse)
static bool g_dclf_keyed = false;
static bool g_dclf_usropn = false;
static char* g_dclf_extdesc = nullptr;
static char* g_dclf_usages = nullptr;
static char* g_dclf_prefix = nullptr;
static char* g_dclf_extfile = nullptr;
static bool g_dclf_extfile_var = false;

// DCL-F name DISK{(n)} options: the declaration, from the g_dclf_* options.
// A record length makes the file program-described.
static rpg::DclF* make_disk_file(char* name, int recordLen) {
    auto* n = new rpg::DclF(name, "DISK");
    free(name);
    n->recordLen = recordLen;
    n->keyed   = g_dclf_keyed;
    n->extdesc = g_dclf_extdesc ? g_dclf_extdesc : "";
    if (g_dclf_extdesc) { free(g_dclf_extdesc); g_dclf_extdesc = nullptr; }
    n->usages  = g_dclf_usages ? g_dclf_usages : "";
    if (g_dclf_usages) { free(g_dclf_usages); g_dclf_usages = nullptr; }
    n->usropn  = g_dclf_usropn;
    n->prefix  = g_dclf_prefix ? g_dclf_prefix : "";
    if (g_dclf_prefix) { free(g_dclf_prefix); g_dclf_prefix = nullptr; }
    n->extfile = g_dclf_extfile ? g_dclf_extfile : "";
    n->extfile_var = g_dclf_extfile_var;
    if (g_dclf_extfile) { free(g_dclf_extfile); g_dclf_extfile = nullptr; }
    g_dclf_keyed = false; g_dclf_usropn = false; g_dclf_extfile_var = false;
    return n;
}

// Builds a subfield from its name, its type (a param_type result, or null
// for LIKEDS/LIKE, whose type comes from elsewhere) and its keywords.
static rpg::DSField* make_ds_field(const char* name, rpg::ParamDecl* type, rpg::DSField* kws) {
    auto* f = kws;
    f->name = name;
    f->line = yylineno;
    if (type) {
        f->type = type->type;
        f->length = type->length;
        f->digits = type->digits;
        f->decimals = type->decimals;
        delete type;
    } else {
        f->type = rpg::RPGType::CHAR;
    }
    return f;
}

// The subfield keywords written before LIKEDS or LIKE and those after it,
// as one set: the later ones are folded into the earlier.
static rpg::DSField* merge_ds_kws(rpg::DSField* before, rpg::DSField* after) {
    if (after->pos) before->pos = after->pos;
    if (after->dim) before->dim = after->dim;
    if (after->inz_default) before->inz_default = true;
    if (after->inz_value) before->inz_value = after->inz_value;
    if (!after->overlay_field.empty()) {
        before->overlay_field = after->overlay_field;
        before->overlay_pos = after->overlay_pos;
    }
    delete after;
    return before;
}

// Parameter keyword bits collected by param_kws (see param_decl).
enum { PK_VALUE = 1, PK_CONST = 2, PK_NOPASS = 4, PK_OMIT = 8,
       PK_VARSIZE = 16, PK_STRING = 32, PK_TRIM = 64, PK_UPPER = 128, PK_LOWER = 256 };
// DEFAULT(value) among a parameter's keywords: kept here by param_kw and
// taken by apply_param_kws, which runs as that parameter's rule ends.
static rpg::Expression* g_param_default = nullptr;
static void apply_param_kws(rpg::ParamDecl* p, int kws) {
    if (g_param_default) {
        p->dflt.reset(g_param_default);
        g_param_default = nullptr;
    }
    p->by_value   = (kws & PK_VALUE) != 0;
    p->is_const   = (kws & PK_CONST) != 0;
    p->nopass     = (kws & PK_NOPASS) != 0;
    p->omit       = (kws & PK_OMIT) != 0;
    p->varsize    = (kws & PK_VARSIZE) != 0;
    p->string_opt = (kws & PK_STRING) != 0;
    p->trim_opt   = (kws & PK_TRIM) != 0;
    p->upper_opt  = (kws & PK_UPPER) != 0;
    p->lower_opt  = (kws & PK_LOWER) != 0;
}

static rpg::Statement* make_move(rpg::Expression* src, char* dst, bool left, bool pad,
                                 char* fmt = nullptr) {
    if (!g_allow_fixed_only_stmts) {
        yyerror(left ? "MOVEL is not valid in free-format RPG (fixed-format C-spec only)"
                     : "MOVE is not valid in free-format RPG (fixed-format C-spec only)");
    }
    auto* s = new rpg::MoveStmt(std::unique_ptr<rpg::Expression>(src), dst, left, pad,
                                fmt ? std::string(fmt) : std::string());
    free(dst);
    if (fmt) free(fmt);
    return s;
}

// DEPRECATED {('message')} on a DCL-PR, after its return type: kept here
// by deprecated_opt and taken by the prototype's rule (apply_deprecated).
// On a DCL-PROC it is part of proc_export's value instead, an index into
// g_dep_msgs, since procedures nest and a side channel would cross them.
static bool g_dep_pending = false;
static std::string g_dep_msg;
static std::vector<std::string> g_dep_msgs;
static void apply_deprecated(rpg::ProcInterface& iface) {
    if (!g_dep_pending) return;
    iface.deprecated = true;
    iface.deprecated_msg = g_dep_msg;
    g_dep_pending = false;
}
static void apply_proc_deprecated(rpg::ProcInterface& iface, int proc_export) {
    // DEPRECATED on a DCL-PI belongs on its DCL-PROC.
    if (g_dep_pending) {
        yyerror("DEPRECATED goes on the DCL-PROC or the DCL-PR, not the DCL-PI");
        g_dep_pending = false;
    }
    int idx = proc_export >> 1;
    if (idx > 0) {
        iface.deprecated = true;
        iface.deprecated_msg = g_dep_msgs[idx - 1];
    }
}

// name => value in an argument list. Only make_func takes one: it records
// the name on the call and keeps the value, so no later stage sees this.
struct NamedArgExpr : rpg::Expression {
    std::string name;
    rpg::Expression* value;
    NamedArgExpr(std::string n, rpg::Expression* v) : name(std::move(n)), value(v) {}
    void accept(rpg::ASTVisitor&) override {}
};

static rpg::BIFCall* make_bif(const char* name, std::vector<rpg::Expression*>* raw_args) {
    std::vector<std::unique_ptr<rpg::Expression>> args;
    for (auto* e : *raw_args) {
        if (auto* na = dynamic_cast<NamedArgExpr*>(e)) {
            yyerror("A built-in function takes its operands by position, not name => value");
            e = na->value;
            na->value = nullptr;
            delete na;
        }
        args.emplace_back(e);
    }
    delete raw_args;
    return new rpg::BIFCall(name, std::move(args));
}

static rpg::FuncCall* make_func(const char* name, std::vector<rpg::Expression*>* raw_args) {
    std::vector<std::unique_ptr<rpg::Expression>> args;
    std::vector<std::string> names;
    bool named = false;
    if (raw_args) {
        for (auto* e : *raw_args) {
            if (auto* na = dynamic_cast<NamedArgExpr*>(e)) {
                named = true;
                names.push_back(na->name);
                args.emplace_back(na->value);
                na->value = nullptr;
                delete na;
            } else {
                if (named) yyerror("An argument given by position cannot follow one given by name (name => value)");
                names.push_back("");
                args.emplace_back(e);
            }
        }
        delete raw_args;
    }
    auto* f = new rpg::FuncCall(name, std::move(args));
    if (named) f->arg_names = std::move(names);
    return f;
}
// DATA-INTO / DATA-GEN from their %DATA(source [: options]) and
// %PARSER / %GEN(name [: options]) argument lists. The handler's own options
// are accepted and not used: the built-in handlers take theirs from %DATA.
static rpg::Expression* take_arg(std::vector<rpg::Expression*>* v, size_t i) {
    if (!v || i >= v->size()) return nullptr;
    rpg::Expression* e = (*v)[i];
    (*v)[i] = nullptr;
    return e;
}
static void drop_args(std::vector<rpg::Expression*>* v) {
    if (!v) return;
    for (auto* e : *v) delete e;
    delete v;
}
// The option names %DATA takes, which IBM i checks at compile time when the
// options are a literal (RNF0236). They differ by statement. Options for the
// parser or generator itself (the CSV handler's header, delimiter) go in the
// second operand of %PARSER or %GEN, which is passed through unchecked.
static const char* const DATA_INTO_OPTIONS[] = {
    "doc", "case", "trim", "allowmissing", "allowextra", "path", "ccsid", "countprefix", nullptr};
static const char* const DATA_GEN_OPTIONS[] = {
    "doc", "countprefix", "renameprefix", "output", "name", nullptr};
static void check_data_options(rpg::Expression* opts, const char* op, const char* const* valid) {
    auto* lit = dynamic_cast<rpg::StringLiteral*>(opts);
    if (!lit) return;
    std::string text = lit->value;
    size_t i = 0;
    while (i < text.size()) {
        while (i < text.size() && isspace((unsigned char)text[i])) i++;
        size_t start = i;
        while (i < text.size() && !isspace((unsigned char)text[i])) i++;
        if (start == i) break;
        std::string opt = text.substr(start, i - start);
        std::string name = opt.substr(0, opt.find('='));
        for (auto& c : name) c = tolower((unsigned char)c);
        bool ok = false;
        for (const char* const* v = valid; *v; v++) if (name == *v) ok = true;
        if (!ok) {
            std::string msg = std::string(op) + ": \"" + opt + "\" is not a %DATA option; "
                "options for the parser or generator go in its own second operand, "
                "e.g. %" + (std::string(op) == "DATA-GEN" ? "GEN" : "PARSER") +
                "('CSV' : '" + opt + "') (IBM: RNF0236)";
            yyerror(msg.c_str());
        }
    }
}
static rpg::Statement* makeDataInto(char* target, std::vector<rpg::Expression*>* data,
                                    std::vector<rpg::Expression*>* handler) {
    auto* s = new rpg::DataIntoStmt(target,
        std::unique_ptr<rpg::Expression>(take_arg(data, 0)),
        std::unique_ptr<rpg::Expression>(take_arg(data, 1)),
        std::unique_ptr<rpg::Expression>(take_arg(handler, 0)));
    s->handler_options.reset(take_arg(handler, 1));
    check_data_options(s->options.get(), "DATA-INTO", DATA_INTO_OPTIONS);
    drop_args(data); drop_args(handler); free(target);
    return s;
}
static rpg::Statement* makeDataGen(char* source, std::vector<rpg::Expression*>* data,
                                   std::vector<rpg::Expression*>* handler) {
    auto* s = new rpg::DataGenStmt(source,
        std::unique_ptr<rpg::Expression>(take_arg(data, 0)),
        std::unique_ptr<rpg::Expression>(take_arg(data, 1)),
        std::unique_ptr<rpg::Expression>(take_arg(handler, 0)));
    s->handler_options.reset(take_arg(handler, 1));
    check_data_options(s->options.get(), "DATA-GEN", DATA_GEN_OPTIONS);
    drop_args(data); drop_args(handler); free(source);
    return s;
}

// The operation extenders IBM i allows on each free-form opcode: EVAL takes
// H, M and R, EVALR M and R, and CALLP E, M and R. Anything else is RNF5049.
// (T) is internal to EVAL -- see eval_stmt -- and allowed only there, from
// the fixed-format transpiler.
static void check_extenders(const char* op, const char* ext, const char* allowed) {
    for (const char* c = ext; *c; c++) {
        if (*c == 'T' && strcmp(op, "EVAL") == 0 && g_allow_fixed_only_stmts) continue;
        if (!strchr(allowed, *c)) {
            std::string msg = std::string(op) + "(" + ext + "): the operation extender " + *c +
                " is not valid for " + op + ", which takes ";
            std::string list;
            for (const char* a = allowed; *a; a++) {
                if (!list.empty()) list += a[1] ? ", " : " and ";
                list += *a;
            }
            msg += list + " (IBM: RNF5049)";
            yyerror(msg.c_str());
            return;
        }
    }
}

// D'...', T'...' and Z'...' are %DATE / %TIME / %TIMESTAMP of the text in
// *ISO format, so an impossible value is caught the same way.
static rpg::Expression* typed_literal(const char* bif, char* text, const char* fmt) {
    auto* args = new std::vector<rpg::Expression*>();
    args->push_back(new rpg::StringLiteral(text));
    args->push_back(new rpg::Identifier(fmt));
    free(text);
    return make_bif(bif, args);
}

static std::string qualified_name(rpg::Expression* e);
static rpg::Statement* make_test(char* ext, char* fmt, rpg::Expression* field) {
    std::string e = ext;
    for (auto& c : e) c = toupper((unsigned char)c);
    if (e.find('E') == std::string::npos)
        yyerror("TEST: in free form the E extender is required, e.g. TEST(DE); check %ERROR "
                "afterwards (IBM: RNF5056)");
    char type = 0;
    for (char c : e) {
        if (c == 'D' || c == 'T' || c == 'Z') type = c;
        else if (c != 'E') yyerror(("TEST(" + e + "): the extenders are E and one of D, T "
                                    "or Z (IBM: RNF5049)").c_str());
    }
    std::string name = qualified_name(field);
    if (name.empty()) name = "the field";
    auto* t = new rpg::TestStmt(type, std::unique_ptr<rpg::Expression>(field), name);
    if (fmt) {
        if (!type) yyerror("TEST: a format operand needs the D, T or Z extender");
        t->format = fmt;
        free(fmt);
    }
    free(ext);
    return t;
}

// Length/digits/scale of the most recent pi_return_type (see that rule).
static int g_ret_len = 0, g_ret_digits = 0, g_ret_dec = 0;

// DCL-PR name [type] OVERLOAD(a : b ...);  ret is pi_return_type's value.
// Line of the OVERLOAD keyword's list. The statement is only reduced after
// the parser has read the next token (to see whether END-PR follows), by
// which point yylineno has moved on.
static int g_overload_line = 0;
static rpg::DclPR* make_overload_pr(char* name, int ret, std::vector<std::string>* impls) {
    rpg::ProcInterface iface{};
    iface.has_return = ret >= 0;
    if (iface.has_return) {
        iface.return_type = static_cast<rpg::RPGType>(ret);
        iface.return_length = g_ret_len;
        iface.return_digits = g_ret_digits;
        iface.return_decimals = g_ret_dec;
    }
    auto* pr = new rpg::DclPR(name, std::move(iface));
    pr->overload_impls = std::move(*impls);
    pr->line = g_overload_line;
    delete impls;
    free(name);
    return pr;
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
    DclSKws* dcl_kws;
    rpg::DclDS* ds_hdr;
    rpg::MonitorStmt* monitor;
    rpg::OnErrorClause* on_error;
}

%code {
// SELECT operand: the variable holding each open SELECT's operand.
static std::vector<std::string> g_select_vars;
static int g_select_count = 0;
static WhenData* make_is_clause(rpg::BinOp op, rpg::Expression* value, StmtList* body) {
    auto* w = new WhenData();
    w->cond = new rpg::BinaryExpr(op, std::make_unique<rpg::Identifier>(g_select_vars.back()),
                                  std::unique_ptr<rpg::Expression>(value));
    w->body = std::move(body->stmts);
    delete body;
    return w;
}
static WhenData* make_in_clause(bool negate, rpg::Expression* coll, StmtList* body) {
    auto* w = new WhenData();
    rpg::Expression* in = new rpg::InExpr(std::make_unique<rpg::Identifier>(g_select_vars.back()),
                                          std::unique_ptr<rpg::Expression>(coll));
    w->cond = negate ? new rpg::NotExpr(std::unique_ptr<rpg::Expression>(in)) : in;
    w->body = std::move(body->stmts);
    delete body;
    return w;
}

// "A" or "A.B.C" for a target that is a plain chain of names, else "".
static std::string qualified_name(rpg::Expression* e) {
    if (auto* id = dynamic_cast<rpg::Identifier*>(e)) return id->name;
    if (auto* dot = dynamic_cast<rpg::DotExpr*>(e)) {
        std::string base = qualified_name(dot->object.get());
        return base.empty() ? "" : base + "." + dot->field;
    }
    return "";
}

// An ON-ERROR code: *FILE, *PROGRAM and *ALL are kept by name, anything
// else (a status number or a named constant) as an expression.
static void add_on_error_code(rpg::OnErrorClause* c, rpg::Expression* e) {
    auto* id = dynamic_cast<rpg::Identifier*>(e);
    if (id && !id->name.empty() && id->name[0] == '*') {
        c->special.push_back(id->name);
        delete e;
        return;
    }
    c->codes.emplace_back(e);
}

// Combines the header keywords written before and after LIKEDS or PSDS.
static rpg::DclDS* merge_ds_hdr(rpg::DclDS* a, rpg::DclDS* b) {
    a->qualified   = a->qualified || b->qualified;
    a->is_template = a->is_template || b->is_template;
    if (b->dim) { a->dim = b->dim; a->dim_type = b->dim_type; }
    if (!b->prefix.empty()) { a->prefix = b->prefix; a->prefix_nbr = b->prefix_nbr; }
    if (!b->inz.empty()) a->inz = b->inz;
    delete b;
    return a;
}

// Builds a DCL-S from its type (a dcl_type result) and its keywords.
static rpg::DclS* make_dcl_s(const char* name, rpg::ParamDecl* t, DclSKws* k) {
    auto* n = new rpg::DclS(name, t->type, t->length, t->digits, t->decimals, k->is_const,
                            std::unique_ptr<rpg::Expression>(k->inz), k->dim);
    n->dim_type    = k->dim_type;
    n->sort_order  = k->sort;
    n->ctdata      = k->ctdata;
    n->perrcd      = k->perrcd;
    n->is_static   = (k->flags & 1) != 0;
    n->is_template = (k->flags & 2) != 0;
    n->is_export   = (k->flags & 4) != 0;
    n->is_import   = (k->flags & 8) != 0;
    n->based_ptr   = k->based;
    n->dtaara_name = k->dtaara_self ? std::string(name) : k->dtaara;
    n->dtaara_var  = k->dtaara_var;
    n->datfmt      = k->datfmt;
    n->timfmt      = k->timfmt;
    delete t;
    delete k;
    return n;
}

// DCL-S a b c INT(10): every name after the first is declared the same way,
// an OpenRPG extension. The first is the statement; the others wait here
// until statement_list takes them, right after it, so each is an ordinary
// DCL-S of its own.
static std::vector<rpg::Statement*> g_more_dcl_s;
static rpg::DclS* make_dcl_s_list(const char* first, std::vector<std::string>* more,
                                  rpg::ParamDecl* t, DclSKws* k) {
    for (const auto& name : *more) {
        auto* kc = new DclSKws(*k);
        if (k->inz) kc->inz = rpg::cloneExpr(*k->inz).release();
        g_more_dcl_s.push_back(make_dcl_s(name.c_str(), new rpg::ParamDecl(*t), kc));
    }
    delete more;
    return make_dcl_s(first, t, k);
}
}

%token KW_FREE
%token KW_DCL_F KW_DCL_S KW_DCL_C
%token KW_DISK KW_PRINTER KW_WORKSTN KW_USAGE KW_KEYED KW_EXTDESC KW_USROPN KW_EXTFILE
%token KW_CHAR KW_VARCHAR KW_INT KW_PACKED KW_ZONED
%token KW_DATE KW_TIME KW_TIMESTAMP KW_IND KW_POINTER KW_NULL
%token KW_DAYS KW_MONTHS KW_YEARS KW_HOURS KW_MINUTES KW_SECONDS KW_MSECONDS
%token KW_CONST KW_INZ
%token KW_STAR_EXTDFT KW_STAR_LIKEDS
%token KW_DSPLY
%token KW_EVAL KW_EVAL_CORR KW_EVALR KW_CALLP KW_LEAVESR KW_ON_EXIT KW_DEALLOC KW_TEST
%token <sval> KW_EVAL_EXT KW_EVALR_EXT KW_CALLP_EXT KW_IN_EXT KW_OUT_EXT KW_UNLOCK_EXT
%token <sval> KW_OPEN_EXT KW_CLOSE_EXT
%token KW_OPEN KW_CLOSE BIF_OPEN
%token KW_STATIC KW_TEMPLATE KW_BASED KW_OPTIONS KW_NOPASS KW_OMIT
%token KW_EXPORT KW_IMPORT KW_EXTPGM KW_EXTPROC KW_CTLOPT KW_OVERLOAD KW_DEPRECATED KW_DEFAULT
%token KW_RETURN
%token KW_ON
%token KW_BLANKS KW_ZEROS KW_HIVAL KW_LOVAL KW_USER
%token KW_IF KW_ELSEIF KW_ELSE KW_ENDIF
%token KW_DOW KW_DOU KW_ENDDO
%token KW_FOR KW_ENDFOR KW_TO KW_DOWNTO KW_BY
%token KW_SELECT KW_WHEN KW_OTHER KW_ENDSL KW_WHEN_IS KW_WHEN_IN KW_WHEN_IS_NOT KW_WHEN_NOT_IN
%token KW_ITER KW_LEAVE
%token KW_MONITOR KW_ON_ERROR KW_ENDMON KW_STAR_FILE KW_STAR_PROGRAM
%token KW_BEGSR KW_ENDSR KW_EXSR
%token KW_GOTO KW_TAG KW_MOVE KW_MOVEL KW_MOVE_PAD KW_MOVEL_PAD KW_CALL
%token KW_OFF KW_RESET KW_CLEAR KW_SORTA KW_DUMP KW_DUMP_A
%token <ival> INDICATOR
%token KW_AND KW_OR KW_NOT ARROW
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
%token BIF_SCANR BIF_EDITFLT BIF_UNSH BIF_PARMNUM BIF_GETENV BIF_FKEY BIF_IF BIF_COMPCORR BIF_KDS BIF_REPEAT BIF_PROGNAME BIF_TOHEX BIF_FROMHEX BIF_MATCHES BIF_FIND BIF_COUNTMATCHES BIF_XML
%token BIF_DATA BIF_PARSER BIF_GEN
%token KW_ALL
%token KW_UNS KW_FLOAT_TYPE KW_BINDEC KW_UCS2 KW_GRAPH KW_OBJECT KW_JAVA
%token KW_OVERLAY KW_POS KW_PREFIX KW_DATFMT KW_TIMFMT KW_EXTNAME KW_PSDS KW_SDS
%token KW_DTAARA KW_OUT KW_UNLOCK
%token KW_RTNPARM KW_OPDESC KW_ASCEND KW_DESCEND KW_NULLIND KW_CTDATA KW_PERRCD
%token KW_VARSIZE KW_STRING_OPT KW_TRIM_OPT KW_UPPER_OPT KW_LOWER_OPT
%token KW_DCL_ENUM KW_END_ENUM
%token <sval> EXEC_SQL_TEXT
%token POWER
%token KW_DIM_VAR KW_DIM_AUTO
%token KW_FOR_EACH KW_IN KW_XML_INTO KW_DATA_INTO KW_DATA_GEN KW_SND_MSG
%token KW_STAR_INFO KW_STAR_DIAG KW_STAR_ESCAPE KW_TYPE
%token KW_STAR_LOCK KW_STAR_DTAARA KW_STAR_SYS KW_EXCEPT
%token KW_STAR_IN
%token KW_STAR_COMP KW_STAR_STATUS KW_STAR_NOTIFY KW_STAR_CALLER KW_STAR_SELF KW_STAR_EXT BIF_TARGET
%token KW_STAR_ALLOC KW_STAR_KEEP
%token KW_READ KW_READC KW_READE KW_READP KW_READPE KW_CHAIN KW_WRITE KW_UPDATE KW_DELETE KW_SETLL KW_SETGT KW_EXFMT
%token <sval> KW_READ_EXT KW_READE_EXT KW_READP_EXT KW_READPE_EXT KW_CHAIN_EXT
%token <sval> KW_WRITE_EXT KW_UPDATE_EXT KW_DELETE_EXT
%token <sval> IDENTIFIER
%token <ival> INTEGER_LITERAL
%token <sval> FLOAT_LITERAL
%token <sval> STRING_LITERAL DATE_LITERAL TIME_LITERAL TIMESTAMP_LITERAL

%token SEMICOLON EQUALS LPAREN RPAREN COLON
%token <ival> COMPOUND_ASSIGN   /* += -= *= /= **= : 0..4 */
%token PLUS MINUS STAR SLASH
%token NE LE GE LT GT

%type <program> program
%type <stmt> statement dcl_f_stmt dcl_s_stmt dcl_c_stmt eval_stmt eval_corr_stmt evalr_stmt dsply_stmt return_stmt expr_stmt reset_stmt clear_stmt sorta_stmt dump_stmt callp_stmt leavesr_stmt dealloc_stmt test_stmt
%type <stmt> if_stmt dow_stmt dou_stmt for_stmt for_each_stmt select_stmt iter_stmt leave_stmt
%type <stmt> dcl_proc_stmt dcl_pr_stmt dcl_ds_stmt dcl_enum_stmt
%type <str_list> call_parm_list
%type <monitor> on_error_clauses
%type <on_error> on_error_clause on_error_codes on_error_code_list
%type <expr> on_error_code
%type <stmt> monitor_stmt begsr_stmt exsr_stmt goto_stmt tag_stmt move_stmt call_stmt exec_sql_stmt xml_into_stmt
%type <stmt> open_close_stmt
%type <stmt> in_da_stmt out_da_stmt unlock_da_stmt data_into_stmt data_gen_stmt snd_msg_stmt except_stmt
%type <sval> snd_msg_type da_name like_name
%type <stmt> chain_stmt read_stmt readc_stmt reade_stmt readp_stmt readpe_stmt
%type <stmt> write_stmt update_stmt delete_stmt setll_stmt setgt_stmt exfmt_stmt
%type <expr> expression or_expr and_expr not_expr comparison_expr additive_expr multiplicative_expr power_expr unary_expr postfix_expr primary_expr eval_target
%type <expr_list> arg_list call_arg_list call_args_opt rla_keys rla_key_list
%type <stmt_list> statement_list
%type <elseif_list> elseif_clauses
%type <elseif_data> elseif_clause
%type <stmt_list> else_clause
%type <when_list> when_clauses is_clauses
%type <when_data> when_clause is_clause
%type <stmt_list> other_clause
%type <ds_field_list> ds_fields
%type <ds_field> ds_field
%type <param_list> pi_params pr_params
%type <param_decl> pi_param pr_param param_decl param_type
%type <ds_field> ds_kws
%type <ival> param_kws param_kw param_opts param_opt
%type <ival> pi_return_type pi_ret_type proc_export proc_kw
%type <sval> pi_name
%type <param_decl> dcl_type
%type <dcl_kws> dcl_kws
%type <str_list> dcl_s_more_names
%type <ds_hdr> ds_hdr_kws
%type <expr> eval_any_target
%type <ival> da_lock_opt
%type <sval> snd_msg_target snd_target_entry
%type <sval> ident plain_name kw_name op_name call_kw_name usage_list
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
        for (auto* d : g_more_dcl_s) {
            if ($2) d->line = $2->line;
            g_program->statements.emplace_back(d);
        }
        g_more_dcl_s.clear();
    }
    /* DCL-PI *N among the main source statements: the program's own
       parameters. A program returns no value. */
    | statements_opt KW_DCL_PI IDENTIFIER SEMICOLON pi_params KW_END_PI SEMICOLON {
        if (g_program->has_main_pi)
            yyerror("The main procedure has only one DCL-PI (IBM: RNF3768)");
        g_program->has_main_pi = true;
        for (auto& p : $5->params) {
            rpg::Statement* d;
            if (!p.likeds.empty()) {
                auto* ds = new rpg::DclDS(p.name);
                ds->like_ds = p.likeds;
                d = ds;
            } else {
                d = new rpg::DclS(p.name, p.type, p.length, p.digits, p.decimals);
            }
            d->line = yylineno;
            g_program->statements.emplace_back(d);
            g_program->main_pi.push_back(p);
        }
        delete $5;
        free($3);
    }
    | statements_opt KW_CTLOPT {
        if (ctlopt_nomain) g_program->nomain = true;
        if (ctlopt_debug_dump) g_program->debug_dump = true;
        if (ctlopt_nolenchk) g_program->nolenchk = true;
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
        for (auto* d : g_more_dcl_s) {
            if ($2) d->line = $2->line;
            $$->stmts.push_back(d);
        }
        g_more_dcl_s.clear();
    }
    ;

statement:
    dcl_f_stmt    { $$ = $1; SET_LINE($$); }
    | dcl_s_stmt  { $$ = $1; SET_LINE($$); }
    | dcl_c_stmt  { $$ = $1; SET_LINE($$); }
    | eval_stmt   { $$ = $1; SET_LINE($$); }
    | eval_corr_stmt { $$ = $1; SET_LINE($$); }
    | dsply_stmt  { $$ = $1; SET_LINE($$); }
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
    | dcl_pr_stmt   { $$ = $1; if (!$$->line) SET_LINE($$); }
    | dcl_ds_stmt   { $$ = $1; SET_LINE($$); }
    | dcl_enum_stmt { $$ = $1; SET_LINE($$); }
    | monitor_stmt  { $$ = $1; SET_LINE($$); }
    | begsr_stmt    { $$ = $1; SET_LINE($$); }
    | exsr_stmt     { $$ = $1; SET_LINE($$); }
    | goto_stmt     { $$ = $1; SET_LINE($$); }
    | tag_stmt      { $$ = $1; SET_LINE($$); }
    | move_stmt     { $$ = $1; SET_LINE($$); }
    | call_stmt     { $$ = $1; SET_LINE($$); }
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
    | except_stmt    { $$ = $1; SET_LINE($$); }
    | in_da_stmt    { $$ = $1; SET_LINE($$); }
    | out_da_stmt   { $$ = $1; SET_LINE($$); }
    | unlock_da_stmt { $$ = $1; SET_LINE($$); }
    | open_close_stmt { $$ = $1; SET_LINE($$); }
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
        $$ = make_disk_file($2, 0);
    }
    /* DISK(*EXT) is externally described, the default; DISK(n) is a
       program-described file of n-byte records, whose layout the I- and
       O-specs give. */
    | KW_DCL_F IDENTIFIER KW_DISK LPAREN KW_STAR_EXT RPAREN dclf_opts SEMICOLON {
        $$ = make_disk_file($2, 0);
    }
    | KW_DCL_F IDENTIFIER KW_DISK LPAREN INTEGER_LITERAL RPAREN dclf_opts SEMICOLON {
        $$ = make_disk_file($2, $5);
    }
    | KW_DCL_F IDENTIFIER KW_PRINTER SEMICOLON {
        $$ = new rpg::DclF($2, "PRINTER");
        free($2);
    }
    /* PRINTER(n): a program-described printer file with n-byte records, the
       usual form for a printer file with no DDS of its own. Without the
       length, the file is externally described, and a printer file created
       without DDS has a record format of its own name, which RPG rejects
       (IBM: RNF2121). */
    | KW_DCL_F IDENTIFIER KW_PRINTER LPAREN INTEGER_LITERAL RPAREN SEMICOLON {
        auto* n = new rpg::DclF($2, "PRINTER");
        n->recordLen = $5;
        free($2);
        $$ = n;
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
        if (g_dclf_extfile) { free(g_dclf_extfile); g_dclf_extfile = nullptr; }
        g_dclf_extfile_var = false;
    }
    | dclf_opts KW_KEYED       { g_dclf_keyed = true; }
    /* EXTFILE('path') opens that file; EXTFILE(var) the path var holds
       when the file is opened; EXTFILE(*EXTDESC) the one EXTDESC names. */
    | dclf_opts KW_EXTFILE LPAREN STRING_LITERAL RPAREN {
        if (g_dclf_extfile) free(g_dclf_extfile);
        g_dclf_extfile = $4; g_dclf_extfile_var = false;
    }
    | dclf_opts KW_EXTFILE LPAREN IDENTIFIER RPAREN {
        if (g_dclf_extfile) free(g_dclf_extfile);
        if (strcasecmp($4, "*EXTDESC") == 0) { g_dclf_extfile = nullptr; free($4); }
        else { g_dclf_extfile = $4; g_dclf_extfile_var = true; }
    }
    | dclf_opts KW_USROPN      { g_dclf_usropn = true; }
    | dclf_opts KW_EXTDESC LPAREN STRING_LITERAL RPAREN {
        if (g_dclf_extdesc) free(g_dclf_extdesc);
        g_dclf_extdesc = $4;
    }
    | dclf_opts KW_PREFIX LPAREN IDENTIFIER RPAREN {
        if (g_dclf_prefix) free(g_dclf_prefix);
        g_dclf_prefix = $4;
    }
    | dclf_opts KW_USAGE LPAREN usage_list RPAREN {
        if (g_dclf_usages) free(g_dclf_usages);
        g_dclf_usages = $4;
    }
    ;

/* USAGE(*INPUT : *OUTPUT : *UPDATE : *DELETE), as "*INPUT:*OUTPUT". The
   values lex as '*' and a name (UPDATE and DELETE as operation codes). */
usage_list:
    STAR ident {
        std::string v = std::string("*") + $2;
        for (auto& c : v) c = toupper((unsigned char)c);
        free($2);
        $$ = strdup(v.c_str());
    }
    | usage_list COLON STAR ident {
        std::string v = std::string($1) + ":*" + $4;
        for (auto& c : v) c = toupper((unsigned char)c);
        free($1); free($4);
        $$ = strdup(v.c_str());
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

/* EXCEPT {name}: write the exception output records (O-spec type E). */
except_stmt:
    KW_EXCEPT SEMICOLON { $$ = new rpg::ExceptStmt(""); }
    | KW_EXCEPT IDENTIFIER SEMICOLON {
        $$ = new rpg::ExceptStmt($2);
        free($2);
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
/* A standalone field: a type, then any of its keywords in any order.
   This replaced 48 alternatives, each pairing one type with a hand-picked
   subset of INZ, CONST, DIM, ASCEND/DESCEND, BASED, DTAARA, EXPORT and
   STATIC, so INZ on a ZONED or on an array, a CHAR DIM(*VAR), or any
   combination not spelled out was a syntax error. */
dcl_s_stmt:
    KW_DCL_S ident dcl_type dcl_kws SEMICOLON {
        $$ = make_dcl_s($2, $3, $4); free($2);
    }
    | KW_DCL_S ident dcl_s_more_names dcl_type dcl_kws SEMICOLON {
        $$ = make_dcl_s_list($2, $3, $4, $5); free($2);
    }
    | KW_DCL_S ident KW_LIKE LPAREN like_name RPAREN dcl_kws SEMICOLON {
        auto* t = new rpg::ParamDecl{"", rpg::RPGType::INT10, 0, 0, 0, false};
        auto* n = make_dcl_s($2, t, $7);
        n->like_var = $5;
        $$ = n; free($2); free($5);
    }
    | KW_DCL_S ident dcl_s_more_names KW_LIKE LPAREN like_name RPAREN dcl_kws SEMICOLON {
        for (const auto& name : *$3) {
            auto* kc = new DclSKws(*$8);
            if ($8->inz) kc->inz = rpg::cloneExpr(*$8->inz).release();
            auto* m = make_dcl_s(name.c_str(),
                new rpg::ParamDecl{"", rpg::RPGType::INT10, 0, 0, 0, false}, kc);
            m->like_var = $6;
            g_more_dcl_s.push_back(m);
        }
        delete $3;
        auto* t = new rpg::ParamDecl{"", rpg::RPGType::INT10, 0, 0, 0, false};
        auto* n = make_dcl_s($2, t, $8);
        n->like_var = $6;
        $$ = n; free($2); free($6);
    }
    | KW_DCL_S ident KW_OBJECT LPAREN KW_JAVA COLON STRING_LITERAL RPAREN SEMICOLON {
        auto* n = new rpg::DclS($2, rpg::RPGType::OBJECT, 0);
        n->java_class = $7;
        $$ = n; free($2); free($7);
    }
    ;

/* The further names of DCL-S a b c INT(10). Plain names only: a name that
   is also a type keyword (DATE, IND, ...) would be read as the type. */
dcl_s_more_names:
    IDENTIFIER { $$ = new std::vector<std::string>{$1}; free($1); }
    | dcl_s_more_names IDENTIFIER { $$ = $1; $$->push_back($2); free($2); }
    ;

/* A DCL-S type, with the length conventions DclS has always used: INT
   carries no length; UNS, FLOAT, BINDEC and UCS2 carry theirs; PACKED and
   ZONED carry digits and scale. INT and UNS also carry their digits (3, 5,
   10 or 20), which decide their edited width and their size in bytes. */
dcl_type:
    KW_CHAR LPAREN INTEGER_LITERAL RPAREN     { $$ = new rpg::ParamDecl{"", rpg::RPGType::CHAR, $3, 0, 0, false}; }
    /* CHAR with no length, an OpenRPG extension: a string of any length,
       held as a VARCHAR whose length 0 means no maximum. */
    | KW_CHAR                                 { $$ = new rpg::ParamDecl{"", rpg::RPGType::VARCHAR, 0, 0, 0, false}; }
    | KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN { $$ = new rpg::ParamDecl{"", rpg::RPGType::VARCHAR, $3, 0, 0, false}; }
    | KW_INT LPAREN INTEGER_LITERAL RPAREN    { $$ = new rpg::ParamDecl{"", rpg::RPGType::INT10, 0, $3, 0, false}; }
    | KW_UNS LPAREN INTEGER_LITERAL RPAREN    { $$ = new rpg::ParamDecl{"", rpg::RPGType::UNS, $3, $3, 0, false}; }
    | KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN {
        $$ = new rpg::ParamDecl{"", rpg::RPGType::PACKED, 0, $3, $5, false};
    }
    | KW_ZONED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN {
        $$ = new rpg::ParamDecl{"", rpg::RPGType::ZONED, 0, $3, $5, false};
    }
    | KW_FLOAT_TYPE LPAREN INTEGER_LITERAL RPAREN {
        $$ = new rpg::ParamDecl{"", ($3 <= 4) ? rpg::RPGType::FLOAT4 : rpg::RPGType::FLOAT8, $3, 0, 0, false};
    }
    | KW_BINDEC LPAREN INTEGER_LITERAL RPAREN { $$ = new rpg::ParamDecl{"", rpg::RPGType::BINDEC, $3, 0, 0, false}; }
    | KW_UCS2 LPAREN INTEGER_LITERAL RPAREN   { $$ = new rpg::ParamDecl{"", rpg::RPGType::UCS2, $3, 0, 0, false}; }
    | KW_GRAPH LPAREN INTEGER_LITERAL RPAREN  { $$ = new rpg::ParamDecl{"", rpg::RPGType::UCS2, $3, 0, 0, false}; }
    | KW_IND        { $$ = new rpg::ParamDecl{"", rpg::RPGType::IND, 0, 0, 0, false}; }
    | KW_DATE       { $$ = new rpg::ParamDecl{"", rpg::RPGType::DATE, 0, 0, 0, false}; }
    | KW_TIME       { $$ = new rpg::ParamDecl{"", rpg::RPGType::TIME, 0, 0, 0, false}; }
    | KW_TIMESTAMP  { $$ = new rpg::ParamDecl{"", rpg::RPGType::TIMESTAMP, 0, 0, 0, false}; }
    | KW_POINTER    { $$ = new rpg::ParamDecl{"", rpg::RPGType::POINTER, 0, 0, 0, false}; }
    ;

dcl_kws:
    /* empty */ { $$ = new DclSKws(); }
    | dcl_kws KW_STATIC   { $$ = $1; $$->flags |= 1; }
    | dcl_kws KW_TEMPLATE { $$ = $1; $$->flags |= 2; }
    | dcl_kws KW_EXPORT   { $$ = $1; $$->flags |= 4; }
    | dcl_kws KW_IMPORT   { $$ = $1; $$->flags |= 8; }
    | dcl_kws KW_CONST    { $$ = $1; $$->is_const = true; }
    | dcl_kws KW_INZ LPAREN expression RPAREN { $$ = $1; $$->inz = $4; }
    | dcl_kws KW_DIM LPAREN INTEGER_LITERAL RPAREN { $$ = $1; $$->dim = $4; }
    | dcl_kws KW_DIM LPAREN KW_DIM_VAR COLON INTEGER_LITERAL RPAREN {
        $$ = $1; $$->dim = $6; $$->dim_type = 1;
    }
    | dcl_kws KW_DIM LPAREN KW_DIM_AUTO COLON INTEGER_LITERAL RPAREN {
        $$ = $1; $$->dim = $6; $$->dim_type = 2;
    }
    | dcl_kws KW_ASCEND   { $$ = $1; $$->sort = 1; }
    | dcl_kws KW_DESCEND  { $$ = $1; $$->sort = -1; }
    | dcl_kws KW_CTDATA   { $$ = $1; $$->ctdata = true; }
    | dcl_kws KW_PERRCD LPAREN INTEGER_LITERAL RPAREN { $$ = $1; $$->perrcd = $4; }
    | dcl_kws KW_BASED LPAREN IDENTIFIER RPAREN  { $$ = $1; $$->based = $4; free($4); }
    /* DTAARA('NAME') names the data area; DTAARA(*LDA) and friends are the
       special ones; DTAARA(var), unquoted, names a variable holding the name,
       as on IBM i; bare DTAARA uses the field's own name. */
    | dcl_kws KW_DTAARA LPAREN IDENTIFIER RPAREN {
        $$ = $1;
        if ($4[0] == '*') $$->dtaara = $4; else $$->dtaara_var = $4;
        free($4);
    }
    | dcl_kws KW_DTAARA LPAREN STRING_LITERAL RPAREN {
        $$ = $1;
        std::string n = $4;
        for (auto& c : n) c = toupper((unsigned char)c);
        size_t slash = n.find('/');
        std::string obj = slash == std::string::npos ? n : n.substr(slash + 1);
        std::string lib = slash == std::string::npos ? "" : n.substr(0, slash);
        if (obj.size() > 10 || lib.size() > 10)
            yyerror(("DTAARA('" + n + "'): an IBM i object or library name is at most 10 "
                     "characters (IBM: RNF0653)").c_str());
        $$->dtaara = n;
        free($4);
    }
    | dcl_kws KW_DTAARA { $$ = $1; $$->dtaara_self = true; }
    | dcl_kws KW_DATFMT LPAREN IDENTIFIER RPAREN { $$ = $1; $$->datfmt = $4; free($4); }
    | dcl_kws KW_TIMFMT LPAREN IDENTIFIER RPAREN { $$ = $1; $$->timfmt = $4; free($4); }
    ;

/* DCL-C: named constants */
dcl_c_stmt:
    KW_DCL_C ident expression SEMICOLON {
        $$ = new rpg::DclC($2, std::unique_ptr<rpg::Expression>($3));
        free($2);
    }
    ;

eval_target:
    IDENTIFIER {
        $$ = new rpg::Identifier($1);
        free($1);
    }
    | kw_name {
        $$ = new rpg::Identifier($1);
        free($1);
    }
    | INDICATOR {
        g_ind_set[$1] = true;
        $$ = new rpg::IndicatorExpr($1);
    }
    | KW_STAR_IN LPAREN expression RPAREN { $$ = make_ind_array($3); }
    | KW_STAR_IN { $$ = make_ind_array(nullptr); }
    /* Qualified targets chain to any depth: ds.f, ds.sub.f, ds(i).sub.f.
       Only one level used to be accepted, so assigning to a subfield of a
       LIKEDS subfield — readable as an expression — was a syntax error. */
    | eval_target DOT ident {
        $$ = new rpg::DotExpr(std::unique_ptr<rpg::Expression>($1), $3);
        free($3);
    }
    | IDENTIFIER LPAREN expression RPAREN {
        $$ = new rpg::ArrayAccess($1, std::unique_ptr<rpg::Expression>($3));
        free($1);
    }
    | call_kw_name LPAREN expression RPAREN {
        $$ = new rpg::ArrayAccess($1, std::unique_ptr<rpg::Expression>($3));
        free($1);
    }

    /* Per-subfield array element: ds.field(idx), ds.sub.field(idx) — the
       field itself is DIM(n). Part of the same chain as the rule above;
       as a separate IDENTIFIER DOT ... rule it made the parser commit
       before it could see whether a `(` followed. */
    | eval_target DOT ident LPAREN expression RPAREN {
        std::string base = qualified_name($1);
        if (base.empty()) yyerror("an element of a DIM subfield of an array element is not supported as an assignment target");
        $$ = new rpg::ArrayAccess(base + "." + $3, std::unique_ptr<rpg::Expression>($5));
        delete $1;
        free($3);
    }
    | BIF_ELEM LPAREN arg_list RPAREN {
        $$ = make_bif("ELEM", $3);
    }
    /* %SUBST(field : start {: length}) = value: part of the field. */
    | BIF_SUBST LPAREN arg_list RPAREN {
        $$ = make_bif("SUBST", $3);
        $$->line = yylineno;
    }
    ;

/* After EVAL, a target may be named like an operation code: EVAL out = 1.
   Without EVAL, IBM reads the statement as that operation. */
eval_any_target:
    eval_target { $$ = $1; }
    | op_name { $$ = new rpg::Identifier($1); free($1); }
    | op_name LPAREN expression RPAREN {
        $$ = new rpg::ArrayAccess($1, std::unique_ptr<rpg::Expression>($3));
        free($1);
    }
    ;

eval_stmt:
    /* Compound assignment: target op= value is target = target op (value).
       The value is one operand, whatever its own operators: x *= a + b
       multiplies by (a + b). */
    eval_target COMPOUND_ASSIGN expression SEMICOLON {
        $$ = new rpg::EvalStmt(std::unique_ptr<rpg::Expression>($1),
                               std::unique_ptr<rpg::Expression>(compound_value($1, $2, $3)));
    }
    | KW_EVAL eval_any_target COMPOUND_ASSIGN expression SEMICOLON {
        $$ = new rpg::EvalStmt(std::unique_ptr<rpg::Expression>($2),
                               std::unique_ptr<rpg::Expression>(compound_value($2, $3, $4)));
    }
    | KW_EVAL_EXT eval_any_target COMPOUND_ASSIGN expression SEMICOLON {
        check_extenders("EVAL", $1, "HMR");
        auto* s = new rpg::EvalStmt(std::unique_ptr<rpg::Expression>($2),
                                    std::unique_ptr<rpg::Expression>(compound_value($2, $3, $4)));
        s->extenders = $1; free($1);
        $$ = s;
    }
    | eval_target EQUALS expression SEMICOLON {
        $$ = new rpg::EvalStmt(
            std::unique_ptr<rpg::Expression>($1),
            std::unique_ptr<rpg::Expression>($3)
        );
    }
    | KW_EVAL eval_any_target EQUALS expression SEMICOLON {
        $$ = new rpg::EvalStmt(
            std::unique_ptr<rpg::Expression>($2),
            std::unique_ptr<rpg::Expression>($4)
        );
    }
    | KW_EVAL_EXT eval_any_target EQUALS expression SEMICOLON {
        /* (T) is internal: the fixed-format transpiler marks the EVAL an
           ADD/SUB/MULT/DIV/Z-ADD/Z-SUB becomes with it, so the result
           drops excess high-order digits as those opcodes do instead of
           raising status 103 as EVAL does. It is not an RPG extender. */
        check_extenders("EVAL", $1, "HMR");
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

/* DATA-INTO and DATA-GEN name their parser or generator, as IBM i requires:
   DATA-INTO needs %PARSER as its third operand (RNF5449), DATA-GEN needs %GEN
   (RNF5454). Each takes a name and optional options, %PARSER('JSON' : 'x').
   The built-in JSON and CSV handlers stand in for the named program: a name
   containing CSV selects CSV, any other selects JSON. */
data_into_stmt:
    KW_DATA_INTO ident BIF_DATA LPAREN arg_list RPAREN BIF_PARSER LPAREN arg_list RPAREN SEMICOLON {
        $$ = makeDataInto($2, $5, $9);
    }
    | KW_DATA_INTO ident BIF_DATA LPAREN arg_list RPAREN SEMICOLON {
        yyerror("DATA-INTO: the third operand must be %PARSER, e.g. %PARSER('JSON') (IBM: RNF5449)");
        $$ = makeDataInto($2, $5, nullptr);
    }
    | KW_DATA_INTO ident BIF_DATA LPAREN arg_list RPAREN BIF_GEN LPAREN arg_list RPAREN SEMICOLON {
        yyerror("DATA-INTO: the third operand must be %PARSER, not %GEN (IBM: RNF5449)");
        $$ = makeDataInto($2, $5, $9);
    }
    ;

data_gen_stmt:
    KW_DATA_GEN ident BIF_DATA LPAREN arg_list RPAREN BIF_GEN LPAREN arg_list RPAREN SEMICOLON {
        $$ = makeDataGen($2, $5, $9);
    }
    | KW_DATA_GEN ident BIF_DATA LPAREN arg_list RPAREN SEMICOLON {
        yyerror("DATA-GEN: the third operand must be %GEN, e.g. %GEN('JSON') (IBM: RNF5454)");
        $$ = makeDataGen($2, $5, nullptr);
    }
    | KW_DATA_GEN ident BIF_DATA LPAREN arg_list RPAREN BIF_PARSER LPAREN arg_list RPAREN SEMICOLON {
        yyerror("DATA-GEN: the third operand must be %GEN, not %PARSER (IBM: RNF5454)");
        $$ = makeDataGen($2, $5, $9);
    }
    ;

/* SND-MSG {type} message {%TARGET(target {: offset})}. The type is one of
   IBM's six; with none, *INFO. TYPE(*INFO) is not IBM's syntax: IBM reads
   TYPE as a variable name (RNF0203/RNF7030). */
snd_msg_stmt:
    KW_SND_MSG snd_msg_type expression snd_msg_target SEMICOLON {
        auto* s = new rpg::SndMsgStmt($2, std::unique_ptr<rpg::Expression>($3));
        s->target = $4; $$ = s;
        free($2); free($4);
    }
    | KW_SND_MSG expression snd_msg_target SEMICOLON {
        auto* s = new rpg::SndMsgStmt("INFO", std::unique_ptr<rpg::Expression>($2));
        s->target = $3; $$ = s;
        free($3);
    }
    | KW_SND_MSG KW_TYPE LPAREN snd_msg_type RPAREN expression SEMICOLON {
        yyerror("SND-MSG: write the message type directly, e.g. SND-MSG *INFO 'text'; "
                "TYPE(...) is not SND-MSG syntax (IBM: RNF0203)");
        $$ = new rpg::SndMsgStmt($4, std::unique_ptr<rpg::Expression>($6));
        free($4);
    }
    ;

snd_msg_type:
    KW_STAR_INFO     { $$ = strdup("INFO"); }
    | KW_STAR_DIAG   { $$ = strdup("DIAG"); }
    | KW_STAR_ESCAPE { $$ = strdup("ESCAPE"); }
    | KW_STAR_COMP   { $$ = strdup("COMP"); }
    | KW_STAR_STATUS { $$ = strdup("STATUS"); }
    | KW_STAR_NOTIFY { $$ = strdup("NOTIFY"); }
    ;

/* %TARGET names a call-stack entry or the external message queue. It
   decides where an *ESCAPE message goes (SndMsgStmt::target); other messages
   go to stderr here, whatever the target. */
snd_msg_target:
    %empty { $$ = strdup(""); }
    | BIF_TARGET LPAREN snd_target_entry RPAREN { $$ = $3; }
    | BIF_TARGET LPAREN snd_target_entry COLON expression RPAREN { $$ = $3; delete $5; }
    ;

snd_target_entry:
    KW_STAR_CALLER { $$ = strdup("*CALLER"); }
    | KW_STAR_SELF { $$ = strdup("*SELF"); }
    | KW_STAR_EXT  { $$ = strdup("*EXT"); }
    | expression   { $$ = strdup(""); delete $1; }
    ;

/* IN{(E)} {*LOCK} name, OUT{(E)} {*LOCK} name, UNLOCK{(E)} name. The name may
   be *DTAARA, every data area the program defines. *LOCK on IN takes the
   data area's lock, which OUT needs; OUT *LOCK keeps it, OUT and UNLOCK
   release it (runtime: rpg_da_in/out/unlock). */
in_da_stmt:
    KW_IN da_lock_opt da_name SEMICOLON {
        auto* s = new rpg::DataInStmt($3); s->lock = $2; $$ = s;
        free($3);
    }
    | KW_IN_EXT da_lock_opt da_name SEMICOLON {
        auto* s = new rpg::DataInStmt($3); s->lock = $2; s->extenders = $1; $$ = s;
        free($1); free($3);
    }
    ;

out_da_stmt:
    KW_OUT da_lock_opt da_name SEMICOLON {
        auto* s = new rpg::DataOutStmt($3); s->lock = $2; $$ = s;
        free($3);
    }
    | KW_OUT_EXT da_lock_opt da_name SEMICOLON {
        auto* s = new rpg::DataOutStmt($3); s->lock = $2; s->extenders = $1; $$ = s;
        free($1); free($3);
    }
    ;

/* OPEN file and CLOSE file, CLOSE *ALL: a USROPN file is opened and
   closed by the program. */
open_close_stmt:
    KW_OPEN IDENTIFIER SEMICOLON { $$ = new rpg::OpenCloseStmt($2, false); free($2); }
    | KW_OPEN_EXT IDENTIFIER SEMICOLON {
        auto* s = new rpg::OpenCloseStmt($2, false); s->extenders = $1; $$ = s;
        free($1); free($2);
    }
    | KW_CLOSE IDENTIFIER SEMICOLON { $$ = new rpg::OpenCloseStmt($2, true); free($2); }
    | KW_CLOSE_EXT IDENTIFIER SEMICOLON {
        auto* s = new rpg::OpenCloseStmt($2, true); s->extenders = $1; $$ = s;
        free($1); free($2);
    }
    | KW_CLOSE KW_ALL SEMICOLON { $$ = new rpg::OpenCloseStmt("*ALL", true); }
    | KW_CLOSE_EXT KW_ALL SEMICOLON {
        auto* s = new rpg::OpenCloseStmt("*ALL", true); s->extenders = $1; $$ = s; free($1);
    }
    ;

unlock_da_stmt:
    KW_UNLOCK da_name SEMICOLON {
        $$ = new rpg::DataUnlockStmt($2);
        free($2);
    }
    | KW_UNLOCK_EXT da_name SEMICOLON {
        auto* s = new rpg::DataUnlockStmt($2); s->extenders = $1; $$ = s;
        free($1); free($2);
    }
    ;

da_lock_opt:
    %empty { $$ = 0; }
    | KW_STAR_LOCK { $$ = 1; }
    ;

da_name:
    IDENTIFIER { $$ = $1; }
    | KW_STAR_DTAARA { $$ = strdup("*DTAARA"); }
    ;

evalr_stmt:
    KW_EVALR eval_any_target EQUALS expression SEMICOLON {
        $$ = new rpg::EvalRStmt(
            std::unique_ptr<rpg::Expression>($2),
            std::unique_ptr<rpg::Expression>($4)
        );
    }
    | KW_EVALR_EXT eval_any_target EQUALS expression SEMICOLON {
        check_extenders("EVALR", $1, "MR");
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
        check_extenders("CALLP", $1, "EMR");
        $$ = new rpg::CallpStmt(std::unique_ptr<rpg::Expression>($2), $1);
        free($1);
    }
    ;

leavesr_stmt:
    KW_LEAVESR SEMICOLON {
        $$ = new rpg::LeaveSRStmt();
    }
    ;

/* DSPLY's operands are separated by blanks (message, message queue,
   response), so on IBM i a message that is an expression must be in
   parentheses: `DSPLY 'Total: ' + x;` is RNF0637, `DSPLY ('Total: ' + x);`
   is fine. A single field, literal or built-in needs none. */
dsply_stmt:
    KW_DSPLY expression SEMICOLON {
        rpg::Expression* e = $2;
        bool compound = dynamic_cast<rpg::BinaryExpr*>(e) || dynamic_cast<rpg::NotExpr*>(e) ||
                        dynamic_cast<rpg::InExpr*>(e);
        if (compound && !e->parenthesized) {
            yyerror("DSPLY: an expression must be in parentheses, e.g. DSPLY ('Total: ' + x) (IBM: RNF0637)");
        }
        $$ = new rpg::DsplyStmt(std::unique_ptr<rpg::Expression>(e));
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
    /* A one-argument call, proc(x);, reads exactly like the start of an
       array-element assignment, arr(x) = ...; — and the parser, seeing
       `name ( expression` followed by `)`, shifts toward the assignment
       (eval_target) reading, then failed on the `;`. Spelling the call out
       here puts both readings in the same state after the `)`, where the
       next token decides: `;` is a call, `=` an assignment. Calls with no
       argument or several already parsed; CALLP was the workaround. */
    | IDENTIFIER LPAREN expression RPAREN SEMICOLON {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back($3);
        auto* fc = make_func($1, args);
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
            iface.return_length = g_ret_len;
            iface.return_digits = g_ret_digits;
            iface.return_decimals = g_ret_dec;
        } else {
            iface.has_return = false;
        }
        iface.params = std::move($5->params);
        delete $5;
        apply_deprecated(iface);
        $$ = new rpg::DclPR($2, std::move(iface));
        free($2);
    }
    /* EXTPROC variant */
    | KW_DCL_PR IDENTIFIER pi_return_type KW_EXTPROC LPAREN STRING_LITERAL RPAREN SEMICOLON pr_params KW_END_PR SEMICOLON {
        rpg::ProcInterface iface;
        if ($3 >= 0) {
            iface.has_return = true;
            iface.return_type = static_cast<rpg::RPGType>($3);
            iface.return_length = g_ret_len;
            iface.return_digits = g_ret_digits;
            iface.return_decimals = g_ret_dec;
        } else {
            iface.has_return = false;
        }
        iface.params = std::move($9->params);
        delete $9;
        apply_deprecated(iface);
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
        apply_deprecated(iface);
        auto* pr = new rpg::DclPR($2, std::move(iface));
        pr->extpgm = $5;
        free($2);
        free($5);
        $$ = pr;
    }
    /* EXTPGM(var): the program named by a variable when it is called */
    | KW_DCL_PR IDENTIFIER KW_EXTPGM LPAREN IDENTIFIER RPAREN SEMICOLON pr_params KW_END_PR SEMICOLON {
        rpg::ProcInterface iface;
        iface.has_return = false;
        iface.params = std::move($8->params);
        delete $8;
        apply_deprecated(iface);
        auto* pr = new rpg::DclPR($2, std::move(iface));
        pr->extpgm = $5;
        pr->extpgm_var = true;
        free($2);
        free($5);
        $$ = pr;
    }
    /* EXTPGM alone: the program has the prototype's name */
    | KW_DCL_PR IDENTIFIER KW_EXTPGM SEMICOLON pr_params KW_END_PR SEMICOLON {
        rpg::ProcInterface iface;
        iface.has_return = false;
        iface.params = std::move($5->params);
        delete $5;
        apply_deprecated(iface);
        auto* pr = new rpg::DclPR($2, std::move(iface));
        pr->extpgm = $2;
        free($2);
        $$ = pr;
    }
    /* OVERLOAD: one statement, as on IBM i — an overloaded prototype has no
       parameters, so no END-PR (RNF3551 with one). Its return type is the
       one every candidate must have (checked in codegen, RNF3244). */
    | KW_DCL_PR IDENTIFIER pi_return_type KW_OVERLOAD LPAREN overload_list RPAREN SEMICOLON {
        $$ = make_overload_pr($2, $3, $6);
    }
    | KW_DCL_PR IDENTIFIER pi_return_type KW_OVERLOAD LPAREN overload_list RPAREN SEMICOLON
      KW_END_PR SEMICOLON {
        yyerror("END-PR is not expected: an OVERLOAD prototype has no parameters, so it is "
                "a single statement, e.g. DCL-PR fmt VARCHAR(30) OVERLOAD(a : b); (IBM: RNF3551)");
        $$ = make_overload_pr($2, $3, $6);
    }
    ;

overload_list:
    IDENTIFIER {
        g_overload_line = yylineno;   /* the OVERLOAD statement's own line */
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

/* A procedure interface's name: the procedure's own name, or *N. IBM
   requires one; with none, it reads the return type (INT(10)) as the name.
   Checked here, as soon as DCL-PI is read, so the error carries the DCL-PI's
   line. $<sval>-3 is the procedure name: every use follows
   `DCL-PROC name proc_export ; DCL-PI`. */
pi_name:
    IDENTIFIER {
        const char* proc = $<sval>-3;
        if (strcmp($1, "*N") != 0 && strcasecmp($1, proc) != 0) {
            yyerror((std::string("DCL-PI name ") + $1 + " must be the procedure's name, " +
                     proc + ", or *N (IBM: RNF3767)").c_str());
        }
        $$ = $1;
    }
    | %empty {
        yyerror((std::string("DCL-PI needs a name: the procedure's name, ") + $<sval>-3 +
                 ", or *N (IBM: RNF3767)").c_str());
        $$ = strdup("*N");
    }
    ;

/* DCL-PROC with embedded DCL-PI */
dcl_proc_stmt:
    KW_DCL_PROC IDENTIFIER proc_export SEMICOLON
      KW_DCL_PI pi_name pi_return_type SEMICOLON pi_params KW_END_PI SEMICOLON
      statement_list
      KW_END_PROC SEMICOLON {
        rpg::ProcInterface iface;
        if ($7 >= 0) {
            iface.has_return = true;
            iface.return_type = static_cast<rpg::RPGType>($7);
            iface.return_length = g_ret_len;
            iface.return_digits = g_ret_digits;
            iface.return_decimals = g_ret_dec;
        } else {
            iface.has_return = false;
        }
        iface.params = std::move($9->params);
        delete $9;
        apply_proc_deprecated(iface, $3);
        auto* proc = new rpg::DclProc($2, std::move(iface));
        proc->is_export = ($3 & 1) != 0;
        for (auto* s : $<stmt_list>12->stmts) proc->body.emplace_back(s);
        delete $<stmt_list>12;
        free($2);
        free($6);
        $$ = proc;
    }
    /* With ON-EXIT */
    | KW_DCL_PROC IDENTIFIER proc_export SEMICOLON
      KW_DCL_PI pi_name pi_return_type SEMICOLON pi_params KW_END_PI SEMICOLON
      statement_list
      KW_ON_EXIT SEMICOLON statement_list
      KW_END_PROC SEMICOLON {
        rpg::ProcInterface iface;
        if ($7 >= 0) {
            iface.has_return = true;
            iface.return_type = static_cast<rpg::RPGType>($7);
            iface.return_length = g_ret_len;
            iface.return_digits = g_ret_digits;
            iface.return_decimals = g_ret_dec;
        } else {
            iface.has_return = false;
        }
        iface.params = std::move($9->params);
        delete $9;
        apply_proc_deprecated(iface, $3);
        auto* proc = new rpg::DclProc($2, std::move(iface));
        proc->is_export = ($3 & 1) != 0;
        for (auto* s : $<stmt_list>12->stmts) proc->body.emplace_back(s);
        delete $<stmt_list>12;
        for (auto* s : $15->stmts) proc->on_exit_body.emplace_back(s);
        delete $15;
        free($2);
        free($6);
        $$ = proc;
    }
    /* No DCL-PI at all. IBM lets a procedure with no parameters and no
       return value omit its interface; it was a syntax error here. The
       statement list cannot begin with DCL-PI, so the next token after
       `DCL-PROC name;` decides which form this is. */
    | KW_DCL_PROC IDENTIFIER proc_export SEMICOLON
      statement_list
      KW_END_PROC SEMICOLON {
        rpg::ProcInterface iface;
        iface.has_return = false;
        apply_proc_deprecated(iface, $3);
        auto* proc = new rpg::DclProc($2, std::move(iface));
        proc->is_export = ($3 & 1) != 0;
        for (auto* s : $<stmt_list>5->stmts) proc->body.emplace_back(s);
        delete $<stmt_list>5;
        free($2);
        $$ = proc;
    }
    | KW_DCL_PROC IDENTIFIER proc_export SEMICOLON
      statement_list
      KW_ON_EXIT SEMICOLON statement_list
      KW_END_PROC SEMICOLON {
        rpg::ProcInterface iface;
        iface.has_return = false;
        apply_proc_deprecated(iface, $3);
        auto* proc = new rpg::DclProc($2, std::move(iface));
        proc->is_export = ($3 & 1) != 0;
        for (auto* s : $<stmt_list>5->stmts) proc->body.emplace_back(s);
        delete $<stmt_list>5;
        for (auto* s : $8->stmts) proc->on_exit_body.emplace_back(s);
        delete $8;
        free($2);
        $$ = proc;
    }
    ;

/* A DCL-PROC's keywords: EXPORT (bit 0) and DEPRECATED, whose message
   is g_dep_msgs[(value >> 1) - 1]. */
proc_export:
    /* empty */ { $$ = 0; }
    | proc_export proc_kw { $$ = ($1 & 1) | $2; }
    ;

proc_kw:
    KW_EXPORT { $$ = 1; }
    | KW_DEPRECATED {
        g_dep_msgs.push_back("");
        $$ = static_cast<int>(g_dep_msgs.size()) << 1;
    }
    | KW_DEPRECATED LPAREN STRING_LITERAL RPAREN {
        g_dep_msgs.push_back(rpg::rpg_decode_lexed_string($3));
        free($3);
        $$ = static_cast<int>(g_dep_msgs.size()) << 1;
    }
    ;

/* Return type for PI/PR: returns -1 if void, or RPGType enum value */
/* The value is the return type's code; its length, digits and scale are
   left in g_ret_* for the enclosing DCL-PR/DCL-PI action to copy, since
   they used to be discarded here and every interface came out with a
   length and scale of 0. Nothing between this reduction and that action
   parses another return type, so the side channel cannot be clobbered. */
pi_return_type:
    pi_ret_type deprecated_opt { $$ = $1; }
    ;

deprecated_opt:
    /* empty */ { }
    | KW_DEPRECATED { g_dep_pending = true; g_dep_msg.clear(); }
    | KW_DEPRECATED LPAREN STRING_LITERAL RPAREN {
        g_dep_pending = true;
        g_dep_msg = rpg::rpg_decode_lexed_string($3);
        free($3);
    }
    ;

pi_ret_type:
    /* void */ { $$ = -1; g_ret_len = g_ret_digits = g_ret_dec = 0; }
    | KW_INT LPAREN INTEGER_LITERAL RPAREN { $$ = (int)rpg::RPGType::INT10; g_ret_len = 0; g_ret_digits = $3; g_ret_dec = 0; }
    | KW_CHAR LPAREN INTEGER_LITERAL RPAREN { $$ = (int)rpg::RPGType::CHAR; g_ret_len = $3; g_ret_digits = g_ret_dec = 0; }
    | KW_CHAR { $$ = (int)rpg::RPGType::VARCHAR; g_ret_len = g_ret_digits = g_ret_dec = 0; }
    | KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN { $$ = (int)rpg::RPGType::VARCHAR; g_ret_len = $3; g_ret_digits = g_ret_dec = 0; }
    | KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN { $$ = (int)rpg::RPGType::PACKED; g_ret_len = 0; g_ret_digits = $3; g_ret_dec = $5; }
    | KW_FLOAT_TYPE LPAREN INTEGER_LITERAL RPAREN {
        $$ = ($3 <= 4) ? (int)rpg::RPGType::FLOAT4 : (int)rpg::RPGType::FLOAT8;
        g_ret_len = g_ret_digits = g_ret_dec = 0;
    }
    | KW_IND { $$ = (int)rpg::RPGType::IND; g_ret_len = g_ret_digits = g_ret_dec = 0; }
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
    param_decl { $$ = $1; }
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
    param_decl { $$ = $1; }
    ;

/* One procedure parameter, in DCL-PI and DCL-PR alike: a name (optionally
   introduced by DCL-PARM), a type or LIKEDS, then any of VALUE, CONST and
   OPTIONS(...) in any order. This replaced 30 hand-enumerated
   alternatives per rule — one per type x keyword combination — which is
   why CONST, or OPTIONS(*NOPASS) on a by-reference parameter, or a ZONED
   or DATE parameter, was a syntax error: no alternative spelled it. */
param_decl:
    IDENTIFIER param_type param_kws SEMICOLON {
        $$ = $2; $$->name = $1; apply_param_kws($$, $3); free($1);
    }
    | KW_DCL_PARM ident param_type param_kws SEMICOLON {
        $$ = $3; $$->name = $2; apply_param_kws($$, $4); free($2);
    }
    | IDENTIFIER KW_LIKEDS LPAREN IDENTIFIER RPAREN param_kws SEMICOLON {
        $$ = new rpg::ParamDecl{$1, rpg::RPGType::CHAR, 0, 0, 0, false, std::string($4)};
        apply_param_kws($$, $6); free($1); free($4);
    }
    | KW_DCL_PARM ident KW_LIKEDS LPAREN IDENTIFIER RPAREN param_kws SEMICOLON {
        $$ = new rpg::ParamDecl{$2, rpg::RPGType::CHAR, 0, 0, 0, false, std::string($5)};
        apply_param_kws($$, $7); free($2); free($5);
    }
    ;

param_type:
    KW_INT LPAREN INTEGER_LITERAL RPAREN      { $$ = new rpg::ParamDecl{"", rpg::RPGType::INT10, 0, $3, 0, false}; }
    | KW_UNS LPAREN INTEGER_LITERAL RPAREN    { $$ = new rpg::ParamDecl{"", rpg::RPGType::UNS, 0, $3, 0, false}; }
    | KW_CHAR LPAREN INTEGER_LITERAL RPAREN   { $$ = new rpg::ParamDecl{"", rpg::RPGType::CHAR, $3, 0, 0, false}; }
    | KW_CHAR                                 { $$ = new rpg::ParamDecl{"", rpg::RPGType::VARCHAR, 0, 0, 0, false}; }
    | KW_VARCHAR LPAREN INTEGER_LITERAL RPAREN { $$ = new rpg::ParamDecl{"", rpg::RPGType::VARCHAR, $3, 0, 0, false}; }
    | KW_PACKED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN {
        $$ = new rpg::ParamDecl{"", rpg::RPGType::PACKED, 0, $3, $5, false};
    }
    | KW_ZONED LPAREN INTEGER_LITERAL COLON INTEGER_LITERAL RPAREN {
        $$ = new rpg::ParamDecl{"", rpg::RPGType::ZONED, 0, $3, $5, false};
    }
    | KW_FLOAT_TYPE LPAREN INTEGER_LITERAL RPAREN {
        $$ = new rpg::ParamDecl{"", ($3 <= 4) ? rpg::RPGType::FLOAT4 : rpg::RPGType::FLOAT8, 0, 0, 0, false};
    }
    | KW_IND        { $$ = new rpg::ParamDecl{"", rpg::RPGType::IND, 0, 0, 0, false}; }
    | KW_DATE       { $$ = new rpg::ParamDecl{"", rpg::RPGType::DATE, 0, 0, 0, false}; }
    | KW_TIME       { $$ = new rpg::ParamDecl{"", rpg::RPGType::TIME, 0, 0, 0, false}; }
    | KW_TIMESTAMP  { $$ = new rpg::ParamDecl{"", rpg::RPGType::TIMESTAMP, 0, 0, 0, false}; }
    | KW_POINTER    { $$ = new rpg::ParamDecl{"", rpg::RPGType::POINTER, 0, 0, 0, false}; }
    ;

/* Parameter keywords as a bit set: see apply_param_kws. */
param_kws:
    /* empty */          { $$ = 0; }
    | param_kws param_kw { $$ = $1 | $2; }
    ;

param_kw:
    KW_VALUE                               { $$ = PK_VALUE; }
    | KW_CONST                             { $$ = PK_CONST; }
    | KW_OPTIONS LPAREN param_opts RPAREN  { $$ = $3; }
    | KW_DEFAULT LPAREN expression RPAREN  {
        delete g_param_default;
        g_param_default = $3;
        $$ = 0;
    }
    ;

param_opts:
    param_opt                    { $$ = $1; }
    | param_opts COLON param_opt { $$ = $1 | $3; }
    ;

param_opt:
    KW_NOPASS       { $$ = PK_NOPASS; }
    | KW_OMIT       { $$ = PK_OMIT; }
    | KW_VARSIZE    { $$ = PK_VARSIZE; }
    | KW_STRING_OPT { $$ = PK_STRING; }
    | KW_TRIM_OPT   { $$ = PK_TRIM; }
    | KW_UPPER_OPT  { $$ = PK_UPPER; }
    | KW_LOWER_OPT  { $$ = PK_LOWER; }
    ;

/* --- Monitor / Subroutines --- */

/* MONITOR ... ON-ERROR {codes}; ... {ON-ERROR ...} ENDMON. Each clause
   lists status codes, named constants, *FILE, *PROGRAM or *ALL, separated
   by colons; none at all means *ALL. The clauses are collected onto the
   MonitorStmt as they are parsed. */
monitor_stmt:
    KW_MONITOR SEMICOLON statement_list on_error_clauses KW_ENDMON SEMICOLON {
        auto* node = $4;
        for (auto* s : $3->stmts) node->try_body.emplace_back(s);
        delete $3;
        $$ = node;
    }
    ;

on_error_clauses:
    on_error_clause { $$ = new rpg::MonitorStmt(); $$->clauses.push_back(std::move(*$1)); delete $1; }
    | on_error_clauses on_error_clause { $$ = $1; $$->clauses.push_back(std::move(*$2)); delete $2; }
    ;

on_error_clause:
    KW_ON_ERROR on_error_codes SEMICOLON statement_list {
        $$ = $2;
        for (auto* s : $4->stmts) $$->body.emplace_back(s);
        delete $4;
    }
    ;

on_error_codes:
    /* empty */ { $$ = new rpg::OnErrorClause(); }
    | on_error_code_list { $$ = $1; }
    ;

on_error_code_list:
    on_error_code { $$ = new rpg::OnErrorClause(); add_on_error_code($$, $1); }
    | on_error_code_list COLON on_error_code { $$ = $1; add_on_error_code($$, $3); }
    ;

on_error_code:
    INTEGER_LITERAL   { $$ = new rpg::IntLiteral($1); }
    | IDENTIFIER      { $$ = new rpg::Identifier($1); free($1); }
    | KW_STAR_FILE    { $$ = new rpg::Identifier("*FILE"); }
    | KW_STAR_PROGRAM { $$ = new rpg::Identifier("*PROGRAM"); }
    | KW_ALL          { $$ = new rpg::Identifier("*ALL"); }
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

/* GOTO/TAG have no free-form syntax at all (SC09-2508: "not allowed — use
   other operation codes"). g_allow_fixed_only_stmts (free_bridge.h) is only set
   true around the fixed-format reader's own native-C-spec parse_free_block()
   call, so this only accepts them when the text being parsed was
   synthesized by that transpiler — genuine free-form text (**FREE
   top-level, or an explicit /free block even inside a fixed-format file)
   always parses with the flag false and gets a clear rejection here. */
goto_stmt:
    KW_GOTO ident SEMICOLON {
        if (!g_allow_fixed_only_stmts) {
            yyerror("GOTO is not valid in free-format RPG (fixed-format C-spec only)");
        }
        $$ = new rpg::GotoStmt($2);
        free($2);
    }
    ;

tag_stmt:
    KW_TAG ident SEMICOLON {
        if (!g_allow_fixed_only_stmts) {
            yyerror("TAG is not valid in free-format RPG (fixed-format C-spec only)");
        }
        $$ = new rpg::TagStmt($2);
        free($2);
    }
    ;

/* MOVE/MOVEL — like GOTO/TAG, no free-form syntax exists; the fixed-format
   C-spec transpiler is the only thing that emits this text. Factor 2 is a
   general expression, the Result field a plain name (this compiler's MOVE
   is character-to-character; codegen enforces that once it can see the
   declared types). */
/* CALL — traditional program call. Like GOTO/TAG/MOVE, no free-form
   syntax exists (free-form uses CALLP with a prototype), so only the
   fixed-format C-spec transpiler emits this text; it collects the
   following PARM lines and hands the whole call over at once. The program
   name is a literal by construction — the transpiler refuses a variable
   one, since there is no dynamic program dispatch to compile it to. */
call_stmt:
    KW_CALL STRING_LITERAL SEMICOLON {
        if (!g_allow_fixed_only_stmts) {
            yyerror("CALL is not valid in free-format RPG (fixed-format C-spec only; use CALLP)");
        }
        $$ = new rpg::CallStmt($2, {});
        free($2);
    }
    | KW_CALL STRING_LITERAL LPAREN call_parm_list RPAREN SEMICOLON {
        if (!g_allow_fixed_only_stmts) {
            yyerror("CALL is not valid in free-format RPG (fixed-format C-spec only; use CALLP)");
        }
        $$ = new rpg::CallStmt($2, *$4);
        free($2); delete $4;
    }
    /* The program named by a variable, when the CALL runs */
    | KW_CALL IDENTIFIER SEMICOLON {
        if (!g_allow_fixed_only_stmts) {
            yyerror("CALL is not valid in free-format RPG (fixed-format C-spec only; use CALLP)");
        }
        auto* c = new rpg::CallStmt($2, {}); c->program_is_var = true; $$ = c;
        free($2);
    }
    | KW_CALL IDENTIFIER LPAREN call_parm_list RPAREN SEMICOLON {
        if (!g_allow_fixed_only_stmts) {
            yyerror("CALL is not valid in free-format RPG (fixed-format C-spec only; use CALLP)");
        }
        auto* c = new rpg::CallStmt($2, *$4); c->program_is_var = true; $$ = c;
        free($2); delete $4;
    }
    ;

call_parm_list:
    IDENTIFIER {
        $$ = new std::vector<std::string>();
        $$->push_back($1);
        free($1);
    }
    | call_parm_list COLON IDENTIFIER {
        $$ = $1;
        $$->push_back($3);
        free($3);
    }
    ;

move_stmt:
    KW_MOVE expression IDENTIFIER SEMICOLON      { $$ = make_move($2, $3, false, false); }
    | KW_MOVE_PAD expression IDENTIFIER SEMICOLON  { $$ = make_move($2, $3, false, true); }
    | KW_MOVEL expression IDENTIFIER SEMICOLON     { $$ = make_move($2, $3, true, false); }
    | KW_MOVEL_PAD expression IDENTIFIER SEMICOLON { $$ = make_move($2, $3, true, true); }
    /* Factor 1 (a date/time format) rides in a quoted string right after
       the opcode, keeping the C-spec's own operand order. It cannot simply
       precede factor 2 unquoted: a format like *MDY/ is not one token, and
       an unquoted leading literal would collide with a character factor 2
       (MOVE '02/01/53' D) one token before an LALR(1) parser can tell them
       apart. The COLON marker resolves that on the token right after the
       opcode. */
    | KW_MOVE COLON STRING_LITERAL expression IDENTIFIER SEMICOLON      { $$ = make_move($4, $5, false, false, $3); }
    | KW_MOVE_PAD COLON STRING_LITERAL expression IDENTIFIER SEMICOLON  { $$ = make_move($4, $5, false, true, $3); }
    | KW_MOVEL COLON STRING_LITERAL expression IDENTIFIER SEMICOLON     { $$ = make_move($4, $5, true, false, $3); }
    | KW_MOVEL_PAD COLON STRING_LITERAL expression IDENTIFIER SEMICOLON { $$ = make_move($4, $5, true, true, $3); }
    ;

/* SORTA */
sorta_stmt:
    KW_SORTA ident SEMICOLON {
        $$ = new rpg::SortAStmt($2);
        free($2);
    }
    /* SORTA array %PADDR(proc): ordered by a comparison procedure, an
       OpenRPG extension. */
    | KW_SORTA ident BIF_PADDR LPAREN expression RPAREN SEMICOLON {
        auto* st = new rpg::SortAStmt($2);
        if (auto* sl = dynamic_cast<rpg::StringLiteral*>($5)) st->cmp_proc = sl->value;
        else if (auto* id = dynamic_cast<rpg::Identifier*>($5)) st->cmp_proc = id->name;
        else yyerror("SORTA array %PADDR(proc): name the comparison procedure");
        for (auto& ch : st->cmp_proc) ch = (char)toupper((unsigned char)ch);
        delete $5;
        free($2);
        $$ = st;
    }
    /* SORTA ds(*).subfield: a data structure array's elements, ordered by
       that subfield. */
    | KW_SORTA IDENTIFIER LPAREN STAR RPAREN DOT ident SEMICOLON {
        auto* st = new rpg::SortAStmt($2);
        st->key_field = $7;
        $$ = st;
        free($2); free($7);
    }
    ;

/* RESET and CLEAR */
reset_stmt:
    KW_RESET ident SEMICOLON {
        $$ = new rpg::ResetStmt($2);
        free($2);
    }
    ;

/* CLEAR takes a name, or a subfield or array element: ds.sub, arr(i),
   ds.sub(i).field. A plain name keeps the name-only form codegen has
   always had; anything else carries the expression. */
clear_stmt:
    KW_CLEAR postfix_expr SEMICOLON {
        if (auto* id = dynamic_cast<rpg::Identifier*>($2)) {
            $$ = new rpg::ClearStmt(id->name);
            delete $2;
        } else {
            if (auto* ind = dynamic_cast<rpg::IndicatorExpr*>($2); ind && ind->number == rpg::IndicatorExpr::ARRAY)
                g_ind_array_used = true;   // CLEAR *IN sets them all
            auto* c = new rpg::ClearStmt("");
            c->target.reset($2);
            $$ = c;
        }
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
/* TEST{(E {D|T|Z})} {format} field. In free form the error extender E is
   required (RNF5056). D, T or Z tests a character or numeric field as a
   date, time or timestamp in the format given, or the default; without one,
   the field is itself a date, time or timestamp and its value is tested. */
test_stmt:
    KW_TEST LPAREN ident RPAREN eval_target SEMICOLON {
        $$ = make_test($3, nullptr, $5);
    }
    | KW_TEST LPAREN ident RPAREN IDENTIFIER eval_target SEMICOLON {
        $$ = make_test($3, $5, $6);
    }
    | KW_TEST eval_target SEMICOLON {
        $$ = make_test(strdup(""), nullptr, $2);
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

/* IBM's form: a name and its value, written like DCL-C — `RED 1;` or
   `RED CONST(1);`. The value is required (RNF3905 without one). */
enum_constant:
    ident expression SEMICOLON {
        auto* v = new std::vector<rpg::EnumConstant>();
        rpg::EnumConstant ec;
        ec.name = $1;
        ec.value.reset($2);
        free($1);
        v->push_back(std::move(ec));
        $$ = v;
    }
    | ident KW_CONST LPAREN expression RPAREN SEMICOLON {
        auto* v = new std::vector<rpg::EnumConstant>();
        rpg::EnumConstant ec;
        ec.name = $1;
        ec.value.reset($4);
        free($1);
        v->push_back(std::move(ec));
        $$ = v;
    }
    | ident SEMICOLON {
        yyerror((std::string("DCL-ENUM constant ") + $1 + " needs a value, e.g. " + $1 +
                 " 1; (IBM: RNF3905)").c_str());
        free($1);
        $$ = new std::vector<rpg::EnumConstant>();
    }
    | ident EQUALS expression SEMICOLON {
        yyerror((std::string("DCL-ENUM constant ") + $1 + ": write the value without '=', e.g. " +
                 $1 + " 1;").c_str());
        delete $3;
        free($1);
        $$ = new std::vector<rpg::EnumConstant>();
    }
    ;

/* --- Data Structures --- */

/* A data structure: header keywords in any order, then its subfields and
   END-DS — or, for LIKEDS, no subfields of its own. This replaced 18
   alternatives, each a fixed subset of QUALIFIED, DIM, LIKEDS, PREFIX and
   PSDS in a fixed order, so TEMPLATE, or QUALIFIED after DIM with PREFIX,
   or any order nobody had spelled out, was a syntax error. PSDS/SDS have
   a slot of their own. A DS that isn't LIKEDS ends with END-DS, as IBM
   requires: the old grammar also took `DCL-DS x PSDS;` with nothing after
   it, which is not valid RPG and made a PSDS's first subfield ambiguous
   with a statement once the header keywords were generalized. */
dcl_ds_stmt:
    KW_DCL_DS ident ds_hdr_kws SEMICOLON ds_fields KW_END_DS SEMICOLON {
        auto* ds = $3; ds->name = strcmp($2, "*N") ? $2 : rpg::unnamedDsName(); free($2);
        ds->fields = std::move($5->fields); delete $5;
        $$ = ds;
    }
    | KW_DCL_DS ident ds_hdr_kws KW_LIKEDS LPAREN IDENTIFIER RPAREN ds_hdr_kws SEMICOLON {
        auto* ds = merge_ds_hdr($3, $8); ds->name = strcmp($2, "*N") ? $2 : rpg::unnamedDsName(); ds->like_ds = $6;
        free($2); free($6);
        $$ = ds;
    }
    | KW_DCL_DS ident ds_hdr_kws psds_kw ds_hdr_kws SEMICOLON ds_fields KW_END_DS SEMICOLON {
        auto* ds = merge_ds_hdr($3, $5); ds->name = strcmp($2, "*N") ? $2 : rpg::unnamedDsName(); ds->is_psds = true; free($2);
        ds->fields = std::move($7->fields); delete $7;
        $$ = ds;
    }
    ;

ds_hdr_kws:
    /* empty */ { $$ = new rpg::DclDS(""); }
    | ds_hdr_kws KW_QUALIFIED { $$ = $1; $$->qualified = true; }
    | ds_hdr_kws KW_TEMPLATE  { $$ = $1; $$->is_template = true; }
    | ds_hdr_kws KW_DIM LPAREN INTEGER_LITERAL RPAREN { $$ = $1; $$->dim = $4; }
    | ds_hdr_kws KW_DIM LPAREN KW_DIM_VAR COLON INTEGER_LITERAL RPAREN {
        $$ = $1; $$->dim = $6; $$->dim_type = 1;
    }
    | ds_hdr_kws KW_DIM LPAREN KW_DIM_AUTO COLON INTEGER_LITERAL RPAREN {
        $$ = $1; $$->dim = $6; $$->dim_type = 2;
    }
    | ds_hdr_kws KW_INZ { $$ = $1; $$->inz = "*DFT"; }
    | ds_hdr_kws KW_INZ LPAREN KW_STAR_EXTDFT RPAREN { $$ = $1; $$->inz = "*EXTDFT"; }
    | ds_hdr_kws KW_INZ LPAREN KW_STAR_LIKEDS RPAREN { $$ = $1; $$->inz = "*LIKEDS"; }
    | ds_hdr_kws KW_PREFIX LPAREN IDENTIFIER RPAREN { $$ = $1; $$->prefix = $4; free($4); }
    | ds_hdr_kws KW_PREFIX LPAREN IDENTIFIER COLON INTEGER_LITERAL RPAREN {
        $$ = $1; $$->prefix = $4; $$->prefix_nbr = $6; free($4);
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

/* One data-structure subfield: a name (optionally DCL-SUBF), a type from
   param_type — shared with procedure parameters — or LIKEDS/LIKE, then any
   of POS, OVERLAY and DIM. LIKEDS and LIKE are keywords like the others,
   so as on IBM i the rest may also come before them: sub DIM(3) LIKEDS(t). This replaced 26 hand-enumerated alternatives
   that covered only INT, CHAR, VARCHAR and PACKED, each with its own
   fixed set of keywords, so a ZONED, IND, DATE, UNS or FLOAT subfield was
   a syntax error, as was any keyword combination not spelled out. */
ds_field:
    plain_name param_type ds_kws SEMICOLON {
        $$ = make_ds_field($1, $2, $3); free($1);
    }
    | KW_DCL_SUBF ident param_type ds_kws SEMICOLON {
        $$ = make_ds_field($2, $3, $4); free($2);
    }
    | plain_name ds_kws KW_LIKEDS LPAREN IDENTIFIER RPAREN ds_kws SEMICOLON {
        $$ = make_ds_field($1, nullptr, merge_ds_kws($2, $7)); $$->likeds = $5; free($1); free($5);
    }
    | KW_DCL_SUBF ident ds_kws KW_LIKEDS LPAREN IDENTIFIER RPAREN ds_kws SEMICOLON {
        $$ = make_ds_field($2, nullptr, merge_ds_kws($3, $8)); $$->likeds = $6; free($2); free($6);
    }
    | plain_name ds_kws KW_LIKE LPAREN like_name RPAREN ds_kws SEMICOLON {
        $$ = make_ds_field($1, nullptr, merge_ds_kws($2, $7)); $$->like_var = $5; free($1); free($5);
    }
    | KW_DCL_SUBF ident ds_kws KW_LIKE LPAREN like_name RPAREN ds_kws SEMICOLON {
        $$ = make_ds_field($2, nullptr, merge_ds_kws($3, $8)); $$->like_var = $6; free($2); free($6);
    }
    ;

/* Subfield keywords, accumulated onto a scratch DSField (see make_ds_field). */
ds_kws:
    /* empty */ { $$ = new rpg::DSField{}; }
    | ds_kws KW_POS LPAREN INTEGER_LITERAL RPAREN { $$ = $1; $$->pos = $4; }
    | ds_kws KW_DIM LPAREN INTEGER_LITERAL RPAREN { $$ = $1; $$->dim = $4; }
    | ds_kws KW_INZ { $$ = $1; $$->inz_default = true; }
    | ds_kws KW_INZ LPAREN expression RPAREN { $$ = $1; $$->inz_value.reset($4); }
    | ds_kws KW_OVERLAY LPAREN IDENTIFIER RPAREN {
        $$ = $1; $$->overlay_field = $4; free($4);
    }
    | ds_kws KW_OVERLAY LPAREN IDENTIFIER COLON INTEGER_LITERAL RPAREN {
        $$ = $1; $$->overlay_field = $4; $$->overlay_pos = $6; free($4);
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
    /* FOR-EACH item IN arr INDEX(i): i is the current element's position,
       from 1 -- an OpenRPG extension. */
    | KW_FOR_EACH ident KW_IN expression IDENTIFIER LPAREN ident RPAREN SEMICOLON statement_list KW_ENDFOR SEMICOLON {
        if (strcasecmp($5, "INDEX") != 0)
            yyerror("FOR-EACH ... IN array may be followed only by INDEX(name)");
        auto* node = new rpg::ForEachStmt($2, std::unique_ptr<rpg::Expression>($4));
        node->index_var = $7;
        for (auto* s : $10->stmts) node->body.emplace_back(s);
        delete $10;
        free($2); free($5); free($7);
        $$ = node;
    }
    ;

select_stmt:
    /* SELECT operand; WHEN-IS value; WHEN-IN %LIST(...) | %RANGE(...);
       (IBM i 7.4/7.5) -- and WHEN-IS-NOT and WHEN-NOT-IN, OpenRPG
       extensions. The operand is evaluated once, into a variable each
       condition compares (g_select_var, set as the operand is reduced). */
    KW_SELECT expression SEMICOLON { g_select_vars.push_back("__SEL" + std::to_string(++g_select_count)); }
      is_clauses other_clause KW_ENDSL SEMICOLON {
        auto* node = new rpg::SelectStmt();
        node->subject.reset($2);
        node->subject_var = g_select_vars.back();
        g_select_vars.pop_back();
        for (auto* w : *$5) {
            rpg::WhenBranch branch;
            branch.condition.reset(w->cond);
            for (auto* s : w->body) branch.body.emplace_back(s);
            node->when_branches.push_back(std::move(branch));
            delete w;
        }
        delete $5;
        if ($6) {
            for (auto* s : $6->stmts) node->other_body.emplace_back(s);
            delete $6;
        }
        $$ = node;
    }
    | KW_SELECT SEMICOLON when_clauses other_clause KW_ENDSL SEMICOLON {
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

is_clauses:
    /* none */ { $$ = new std::vector<WhenData*>(); }
    | is_clauses is_clause { $$ = $1; $$->push_back($2); }
    ;

is_clause:
    KW_WHEN_IS expression SEMICOLON statement_list {
        $$ = make_is_clause(rpg::BinOp::EQ, $2, $4);
    }
    | KW_WHEN_IS_NOT expression SEMICOLON statement_list {
        $$ = make_is_clause(rpg::BinOp::NE, $2, $4);
    }
    | KW_WHEN_IN expression SEMICOLON statement_list {
        $$ = make_in_clause(false, $2, $4);
    }
    | KW_WHEN_NOT_IN expression SEMICOLON statement_list {
        $$ = make_in_clause(true, $2, $4);
    }
    | KW_WHEN expression SEMICOLON statement_list {
        yyerror("A SELECT with an operand is followed by WHEN-IS, WHEN-IN, OTHER or ENDSL, not WHEN (IBM: RNF0203)");
        $$ = make_is_clause(rpg::BinOp::EQ, $2, $4);
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

/* NOT is not here: it is a unary operator (see unary_expr), not a
   comparison-level one. */
not_expr:
    comparison_expr { $$ = $1; }
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
    /* x NOT IN list, an OpenRPG extension: NOT (x IN list). */
    | additive_expr KW_NOT KW_IN additive_expr {
        $$ = new rpg::NotExpr(std::unique_ptr<rpg::Expression>(new rpg::InExpr(
            std::unique_ptr<rpg::Expression>($1),
            std::unique_ptr<rpg::Expression>($4))));
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

/* NOT binds as tightly as unary minus, above ** and every binary operator
   — IBM's precedence order. It used to sit below the comparisons, so
   `NOT x = 0` meant NOT (x = 0) here, while IBM reads (NOT x) = 0 and
   rejects NOT on a number (RNF7421). Write NOT (x = 0) for the other. */
unary_expr:
    postfix_expr { $$ = $1; }
    | KW_NOT unary_expr {
        $$ = new rpg::NotExpr(std::unique_ptr<rpg::Expression>($2));
        $$->line = yylineno;   /* its own line, for RNF7421 */
    }
    | MINUS postfix_expr {
        $$ = new rpg::BinaryExpr(rpg::BinOp::SUB,
            std::unique_ptr<rpg::Expression>(new rpg::IntLiteral(0)),
            std::unique_ptr<rpg::Expression>($2));
    }
    ;

postfix_expr:
    primary_expr { $$ = $1; }
    | postfix_expr DOT ident {
        // ds(*).subfield: that subfield of every element (__DSCOL).
        if (auto* all = dynamic_cast<rpg::BIFCall*>($1); all && all->name == "__DSALL") {
            auto* args = new std::vector<rpg::Expression*>();
            args->push_back(all->args[0].release());
            args->push_back(new rpg::StringLiteral($3));
            int line = all->line;
            delete all;
            $$ = make_bif("__DSCOL", args);
            $$->line = line;
        } else {
            $$ = new rpg::DotExpr(std::unique_ptr<rpg::Expression>($1), $3);
        }
        free($3);
    }
    /* Per-subfield array element (read): ds.field(idx), ds.sub.field(idx) —
       the field itself is DIM(n). The base may be any chain of names; an
       indexed base (items(1).field(idx)) still isn't supported. */
    | postfix_expr DOT ident LPAREN expression RPAREN {
        std::string baseName = qualified_name($1);
        if (baseName.empty()) {
            yyerror("an element of a DIM subfield of an array element (items(1).field(idx)) is not supported");
            YYERROR;
        }
        std::string qualified = baseName + "." + $3;
        delete $1;
        $$ = new rpg::ArrayAccess(qualified, std::unique_ptr<rpg::Expression>($5));
        free($3);
    }
    ;

/* The field LIKE names: a plain name, or a subfield of a qualified data
   structure, LIKE(ds.field), through any depth of nested data structures,
   LIKE(ds.inner.field). */
like_name:
    IDENTIFIER { $$ = $1; }
    | like_name DOT IDENTIFIER {
        std::string n = std::string($1) + "." + $3;
        free($1); free($3);
        $$ = strdup(n.c_str());
    }
    ;

/* Names. IBM i reserves almost no words: a field may be named CHAR, TYPE,
   VALUE, IND or TAG (verified on PUB400, 2026-09-26; only NOT is refused).
   A name that is a free-form operation code (op_name) is the one exception
   at the start of a statement, which IBM reads as that operation -- there
   the assignment needs EVAL -- and as a subfield or parameter, which then
   needs DCL-SUBF or DCL-PARM. kw_name and op_name are generated from the
   lexer's keywords. */
ident:
    IDENTIFIER { $$ = $1; }
    | kw_name { $$ = $1; }
    | op_name { $$ = $1; }
    ;

plain_name:
    IDENTIFIER { $$ = $1; }
    | kw_name { $$ = $1; }
    ;

kw_name:
      KW_CHAR { $$ = strdup("CHAR"); }
    | KW_VARCHAR { $$ = strdup("VARCHAR"); }
    | KW_INT { $$ = strdup("INT"); }
    | KW_PACKED { $$ = strdup("PACKED"); }
    | KW_ZONED { $$ = strdup("ZONED"); }
    | KW_CONST { $$ = strdup("CONST"); }
    | KW_DATE { $$ = strdup("DATE"); }
    | KW_TIME { $$ = strdup("TIME"); }
    | KW_TIMESTAMP { $$ = strdup("TIMESTAMP"); }
    | KW_IND { $$ = strdup("IND"); }
    | KW_POINTER { $$ = strdup("POINTER"); }
    | KW_DISK { $$ = strdup("DISK"); }
    | KW_PRINTER { $$ = strdup("PRINTER"); }
    | KW_WORKSTN { $$ = strdup("WORKSTN"); }
    | KW_DEPRECATED { $$ = strdup("DEPRECATED"); }
    | KW_DEFAULT { $$ = strdup("DEFAULT"); }
    | KW_USAGE { $$ = strdup("USAGE"); }
    | KW_KEYED { $$ = strdup("KEYED"); }
    | KW_EXTDESC { $$ = strdup("EXTDESC"); }
    | KW_USROPN { $$ = strdup("USROPN"); }
    | KW_EXTFILE { $$ = strdup("EXTFILE"); }
    | KW_TYPE { $$ = strdup("TYPE"); }
    | KW_INZ { $$ = strdup("INZ"); }
    | KW_STATIC { $$ = strdup("STATIC"); }
    | KW_TEMPLATE { $$ = strdup("TEMPLATE"); }
    | KW_BASED { $$ = strdup("BASED"); }
    | KW_EXPORT { $$ = strdup("EXPORT"); }
    | KW_IMPORT { $$ = strdup("IMPORT"); }
    | KW_EXTPGM { $$ = strdup("EXTPGM"); }
    | KW_EXTPROC { $$ = strdup("EXTPROC"); }
    | KW_OVERLOAD { $$ = strdup("OVERLOAD"); }
    | KW_OPTIONS { $$ = strdup("OPTIONS"); }
    | KW_VALUE { $$ = strdup("VALUE"); }
    | KW_QUALIFIED { $$ = strdup("QUALIFIED"); }
    | KW_DIM { $$ = strdup("DIM"); }
    | KW_LIKEDS { $$ = strdup("LIKEDS"); }
    | KW_LIKE { $$ = strdup("LIKE"); }
    | KW_UNS { $$ = strdup("UNS"); }
    | KW_FLOAT_TYPE { $$ = strdup("FLOAT"); }
    | KW_BINDEC { $$ = strdup("BINDEC"); }
    | KW_UCS2 { $$ = strdup("UCS2"); }
    | KW_GRAPH { $$ = strdup("GRAPH"); }
    | KW_OBJECT { $$ = strdup("OBJECT"); }
    | KW_DATFMT { $$ = strdup("DATFMT"); }
    | KW_TIMFMT { $$ = strdup("TIMFMT"); }
    | KW_OVERLAY { $$ = strdup("OVERLAY"); }
    | KW_POS { $$ = strdup("POS"); }
    | KW_PREFIX { $$ = strdup("PREFIX"); }
    | KW_EXTNAME { $$ = strdup("EXTNAME"); }
    | KW_PSDS { $$ = strdup("PSDS"); }
    | KW_SDS { $$ = strdup("SDS"); }
    | KW_DTAARA { $$ = strdup("DTAARA"); }
    | KW_RTNPARM { $$ = strdup("RTNPARM"); }
    | KW_OPDESC { $$ = strdup("OPDESC"); }
    | KW_ASCEND { $$ = strdup("ASCEND"); }
    | KW_CTDATA { $$ = strdup("CTDATA"); }
    | KW_PERRCD { $$ = strdup("PERRCD"); }
    | KW_DESCEND { $$ = strdup("DESCEND"); }
    | KW_NULLIND { $$ = strdup("NULLIND"); }
    | KW_TO { $$ = strdup("TO"); }
    | KW_DOWNTO { $$ = strdup("DOWNTO"); }
    | KW_BY { $$ = strdup("BY"); }
    | KW_TAG { $$ = strdup("TAG"); }
    ;

/* kw_name, less TYPE and CONST: a name written with ( after it. TYPE(
   and CONST( are keywords there (SND-MSG TYPE(...), an enum CONST(...)). */
call_kw_name:
      KW_CHAR { $$ = strdup("CHAR"); }
    | KW_VARCHAR { $$ = strdup("VARCHAR"); }
    | KW_INT { $$ = strdup("INT"); }
    | KW_PACKED { $$ = strdup("PACKED"); }
    | KW_ZONED { $$ = strdup("ZONED"); }
    | KW_DATE { $$ = strdup("DATE"); }
    | KW_TIME { $$ = strdup("TIME"); }
    | KW_TIMESTAMP { $$ = strdup("TIMESTAMP"); }
    | KW_IND { $$ = strdup("IND"); }
    | KW_POINTER { $$ = strdup("POINTER"); }
    | KW_DISK { $$ = strdup("DISK"); }
    | KW_PRINTER { $$ = strdup("PRINTER"); }
    | KW_WORKSTN { $$ = strdup("WORKSTN"); }
    | KW_USAGE { $$ = strdup("USAGE"); }
    | KW_KEYED { $$ = strdup("KEYED"); }
    | KW_EXTDESC { $$ = strdup("EXTDESC"); }
    | KW_USROPN { $$ = strdup("USROPN"); }
    | KW_EXTFILE { $$ = strdup("EXTFILE"); }
    | KW_INZ { $$ = strdup("INZ"); }
    | KW_STATIC { $$ = strdup("STATIC"); }
    | KW_TEMPLATE { $$ = strdup("TEMPLATE"); }
    | KW_BASED { $$ = strdup("BASED"); }
    | KW_EXPORT { $$ = strdup("EXPORT"); }
    | KW_IMPORT { $$ = strdup("IMPORT"); }
    | KW_EXTPGM { $$ = strdup("EXTPGM"); }
    | KW_EXTPROC { $$ = strdup("EXTPROC"); }
    | KW_OVERLOAD { $$ = strdup("OVERLOAD"); }
    | KW_OPTIONS { $$ = strdup("OPTIONS"); }
    | KW_VALUE { $$ = strdup("VALUE"); }
    | KW_QUALIFIED { $$ = strdup("QUALIFIED"); }
    | KW_DIM { $$ = strdup("DIM"); }
    | KW_LIKEDS { $$ = strdup("LIKEDS"); }
    | KW_LIKE { $$ = strdup("LIKE"); }
    | KW_UNS { $$ = strdup("UNS"); }
    | KW_FLOAT_TYPE { $$ = strdup("FLOAT"); }
    | KW_BINDEC { $$ = strdup("BINDEC"); }
    | KW_UCS2 { $$ = strdup("UCS2"); }
    | KW_GRAPH { $$ = strdup("GRAPH"); }
    | KW_OBJECT { $$ = strdup("OBJECT"); }
    | KW_DATFMT { $$ = strdup("DATFMT"); }
    | KW_TIMFMT { $$ = strdup("TIMFMT"); }
    | KW_OVERLAY { $$ = strdup("OVERLAY"); }
    | KW_POS { $$ = strdup("POS"); }
    | KW_PREFIX { $$ = strdup("PREFIX"); }
    | KW_EXTNAME { $$ = strdup("EXTNAME"); }
    | KW_PSDS { $$ = strdup("PSDS"); }
    | KW_SDS { $$ = strdup("SDS"); }
    | KW_DTAARA { $$ = strdup("DTAARA"); }
    | KW_RTNPARM { $$ = strdup("RTNPARM"); }
    | KW_OPDESC { $$ = strdup("OPDESC"); }
    | KW_ASCEND { $$ = strdup("ASCEND"); }
    | KW_CTDATA { $$ = strdup("CTDATA"); }
    | KW_PERRCD { $$ = strdup("PERRCD"); }
    | KW_DESCEND { $$ = strdup("DESCEND"); }
    | KW_NULLIND { $$ = strdup("NULLIND"); }
    | KW_TO { $$ = strdup("TO"); }
    | KW_DOWNTO { $$ = strdup("DOWNTO"); }
    | KW_BY { $$ = strdup("BY"); }
    | KW_TAG { $$ = strdup("TAG"); }
    ;

op_name:
      KW_READE { $$ = strdup("READE"); }
    | KW_READPE { $$ = strdup("READPE"); }
    | KW_READP { $$ = strdup("READP"); }
    | KW_EXFMT { $$ = strdup("EXFMT"); }
    | KW_READC { $$ = strdup("READC"); }
    | KW_READ { $$ = strdup("READ"); }
    | KW_CHAIN { $$ = strdup("CHAIN"); }
    | KW_WRITE { $$ = strdup("WRITE"); }
    | KW_EXCEPT { $$ = strdup("EXCEPT"); }
    | KW_UPDATE { $$ = strdup("UPDATE"); }
    | KW_DELETE { $$ = strdup("DELETE"); }
    | KW_SETLL { $$ = strdup("SETLL"); }
    | KW_SETGT { $$ = strdup("SETGT"); }
    | KW_DSPLY { $$ = strdup("DSPLY"); }
    | KW_EVALR { $$ = strdup("EVALR"); }
    | KW_EVAL { $$ = strdup("EVAL"); }
    | KW_CALLP { $$ = strdup("CALLP"); }
    | KW_CALL { $$ = strdup("CALL"); }
    | KW_LEAVESR { $$ = strdup("LEAVESR"); }
    | KW_DEALLOC { $$ = strdup("DEALLOC"); }
    | KW_TEST { $$ = strdup("TEST"); }
    | KW_RETURN { $$ = strdup("RETURN"); }
    | KW_OUT { $$ = strdup("OUT"); }
    | KW_UNLOCK { $$ = strdup("UNLOCK"); }
    | KW_OPEN { $$ = strdup("OPEN"); }
    | KW_CLOSE { $$ = strdup("CLOSE"); }
    | KW_IN { $$ = strdup("IN"); }
    | KW_IF { $$ = strdup("IF"); }
    | KW_ELSEIF { $$ = strdup("ELSEIF"); }
    | KW_ELSE { $$ = strdup("ELSE"); }
    | KW_ENDIF { $$ = strdup("ENDIF"); }
    | KW_DOU { $$ = strdup("DOU"); }
    | KW_DOW { $$ = strdup("DOW"); }
    | KW_ENDDO { $$ = strdup("ENDDO"); }
    | KW_FOR { $$ = strdup("FOR"); }
    | KW_ENDFOR { $$ = strdup("ENDFOR"); }
    | KW_SELECT { $$ = strdup("SELECT"); }
    | KW_WHEN { $$ = strdup("WHEN"); }
    | KW_OTHER { $$ = strdup("OTHER"); }
    | KW_ENDSL { $$ = strdup("ENDSL"); }
    | KW_ITER { $$ = strdup("ITER"); }
    | KW_LEAVE { $$ = strdup("LEAVE"); }
    | KW_MONITOR { $$ = strdup("MONITOR"); }
    | KW_ENDMON { $$ = strdup("ENDMON"); }
    | KW_BEGSR { $$ = strdup("BEGSR"); }
    | KW_ENDSR { $$ = strdup("ENDSR"); }
    | KW_EXSR { $$ = strdup("EXSR"); }
    | KW_GOTO { $$ = strdup("GOTO"); }
    | KW_MOVEL { $$ = strdup("MOVEL"); }
    | KW_MOVE { $$ = strdup("MOVE"); }
    | KW_RESET { $$ = strdup("RESET"); }
    | KW_SORTA { $$ = strdup("SORTA"); }
    | KW_CLEAR { $$ = strdup("CLEAR"); }
    | KW_DUMP { $$ = strdup("DUMP"); }
    ;

primary_expr:
    ident {
        $$ = new rpg::Identifier($1);
        free($1);
    }
    | INTEGER_LITERAL {
        $$ = new rpg::IntLiteral($1);
    }
    | FLOAT_LITERAL {
        auto* lit = new rpg::FloatLiteral(atof($1));
        const char* pt = strchr($1, '.');
        lit->scale = pt ? static_cast<int>(strlen(pt + 1)) : 0;
        $$ = lit;
        free($1);
    }
    | STRING_LITERAL {
        $$ = new rpg::StringLiteral(rpg::rpg_decode_lexed_string($1));
        free($1);
    }
    | IDENTIFIER LPAREN call_args_opt RPAREN {
        $$ = make_func($1, $3);
        free($1);
    }
    /* ds(*): every element of a data structure array, for
       %LOOKUP(%KDS(key) : ds(*)). Followed by .subfield (postfix_expr) it
       is that subfield of every element, as an array -- for SORTA's
       sibling forms, %LOOKUP, %XFOOT, %MAXARR, %MINARR and IN. */
    | IDENTIFIER LPAREN STAR RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back(new rpg::Identifier($1));
        $$ = make_bif("__DSALL", args);
        $$->line = yylineno;
        free($1);
    }

    | call_kw_name LPAREN call_args_opt RPAREN {
        $$ = make_func($1, $3);
        free($1);
    }
    | op_name LPAREN call_args_opt RPAREN {
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
    /* A built-in with no arguments may drop its parentheses, as on IBM i:
       IF %ERROR; n = %STATUS; IF %FOUND; */
    | BIF_STATUS { $$ = make_bif("STATUS", new std::vector<rpg::Expression*>()); }
    | BIF_DATE      { $$ = make_bif("DATE",      new std::vector<rpg::Expression*>()); }
    | BIF_TIME      { $$ = make_bif("TIME",      new std::vector<rpg::Expression*>()); }
    | BIF_TIMESTAMP { $$ = make_bif("TIMESTAMP", new std::vector<rpg::Expression*>()); }
    | BIF_ERROR  { $$ = make_bif("ERROR",  new std::vector<rpg::Expression*>()); }
    | BIF_FOUND  { $$ = make_bif("FOUND",  new std::vector<rpg::Expression*>()); }
    | BIF_EOF    { $$ = make_bif("EOF",    new std::vector<rpg::Expression*>()); }
    | BIF_PARMS  { $$ = make_bif("PARMS",  new std::vector<rpg::Expression*>()); }
    | BIF_FKEY   { $$ = make_bif("FKEY",   new std::vector<rpg::Expression*>()); }
    | BIF_FKEY LPAREN RPAREN { $$ = make_bif("FKEY", new std::vector<rpg::Expression*>()); }
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
    | BIF_OPEN LPAREN IDENTIFIER RPAREN {
        auto* args = new std::vector<rpg::Expression*>();
        args->push_back(new rpg::Identifier($3));
        free($3);
        $$ = make_bif("OPEN", args);
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
        args->push_back(new rpg::StringLiteral(rpg::rpg_decode_lexed_string($2)));
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
    | BIF_IF LPAREN arg_list RPAREN { $$ = make_bif("IF", $3); $$->line = yylineno; }
    | BIF_COMPCORR LPAREN arg_list RPAREN { $$ = make_bif("COMPCORR", $3); $$->line = yylineno; }
    | BIF_KDS LPAREN arg_list RPAREN { $$ = make_bif("KDS", $3); $$->line = yylineno; }
    | BIF_REPEAT LPAREN arg_list RPAREN { $$ = make_bif("REPEAT", $3); $$->line = yylineno; }
    | BIF_TOHEX LPAREN arg_list RPAREN { $$ = make_bif("TOHEX", $3); $$->line = yylineno; }
    | BIF_FROMHEX LPAREN arg_list RPAREN { $$ = make_bif("FROMHEX", $3); $$->line = yylineno; }
    /* %PROGNAME, with or without (): the running program's name. */
    | BIF_PROGNAME {
        if (g_program) g_program->uses_progname = true;
        $$ = make_bif("PROGNAME", new std::vector<rpg::Expression*>());
    }
    | BIF_PROGNAME LPAREN RPAREN {
        if (g_program) g_program->uses_progname = true;
        $$ = make_bif("PROGNAME", new std::vector<rpg::Expression*>());
    }
    | BIF_MATCHES LPAREN arg_list RPAREN { $$ = make_bif("MATCHES", $3); $$->line = yylineno; }
    | BIF_FIND LPAREN arg_list RPAREN { $$ = make_bif("FIND", $3); $$->line = yylineno; }
    | BIF_COUNTMATCHES LPAREN arg_list RPAREN { $$ = make_bif("COUNTMATCHES", $3); $$->line = yylineno; }
    | INDICATOR {
        if (!g_ind_tested_line[$1]) g_ind_tested_line[$1] = yylineno;
        $$ = new rpg::IndicatorExpr($1);
    }
    | KW_STAR_IN LPAREN expression RPAREN { $$ = make_ind_array($3); }
    | KW_STAR_IN { $$ = make_ind_array(nullptr, false); }
    | KW_ON {
        auto* v = new rpg::IntLiteral(1);  // *ON → true
        v->indicator = true;
        $$ = v;
    }
    | KW_OFF {
        auto* v = new rpg::IntLiteral(0);  // *OFF → false
        v->indicator = true;
        $$ = v;
    }
    | KW_NULL {
        $$ = new rpg::Identifier("nullptr");
    }
    | KW_OMIT {
        $$ = new rpg::Identifier("nullptr");
    }
    /* A typed literal is its BIF with the literal's format: *ISO */
    | DATE_LITERAL      { $$ = typed_literal("DATE", $1, "*ISO"); }
    | TIME_LITERAL      { $$ = typed_literal("TIME", $1, "*ISO"); }
    | TIMESTAMP_LITERAL { $$ = typed_literal("TIMESTAMP", $1, "*ISO"); }
    | KW_USER {
        $$ = new rpg::Identifier("RPG_USER");
        if (g_program) g_program->uses_user_const = true;
    }
    | KW_BLANKS {
        $$ = new rpg::Identifier("RPG_BLANKS");
    }
    | KW_STAR_SYS {
        $$ = new rpg::Identifier("RPG_SYS");   // INZ(*SYS): the current date/time
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
        $$->parenthesized = true;
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
    /* name => value: an argument for the parameter of that name, an
       OpenRPG extension (make_func). */
    | IDENTIFIER ARROW expression {
        $$ = new std::vector<rpg::Expression*>();
        $$->push_back(new NamedArgExpr($1, $3));
        free($1);
    }
    | call_arg_list COLON IDENTIFIER ARROW expression {
        $$ = $1;
        $$->push_back(new NamedArgExpr($3, $5));
        free($3);
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
    reset_indicator_uses();
    yyparse();
    return g_program;
}

// RNF7030 for every indicator the program refers to and nothing sets.
// Besides an assignment (which a fixed-format resulting indicator also
// becomes), an I-spec's record identifying and field indicators set theirs,
// and a display file sets 01-99 from its own DDS, which this source does
// not show, so a program with a WORKSTN file is not checked for those.
// U1-U8 and 1P are always defined on IBM i; rpgc has neither.
void check_indicators_defined(rpg::Program* program) {
    bool set[110];
    for (int i = 0; i < 110; i++) set[i] = g_ind_set[i];
    bool workstn = false;
    auto mark = [&](const std::string& ind) {
        if (ind.size() == 2 && isdigit((unsigned char)ind[0]) && isdigit((unsigned char)ind[1]))
            set[atoi(ind.c_str())] = true;
    };
    for (auto& st : program->statements) {
        if (auto* f = dynamic_cast<rpg::DclF*>(st.get()); f && f->usage == "WORKSTN") workstn = true;
        if (auto* r = dynamic_cast<rpg::IRecordFormat*>(st.get())) {
            mark(r->recordIdIndicator);
            for (auto& fd : r->fields) { mark(fd.indPlus); mark(fd.indMinus); mark(fd.indZeroBlank); }
        }
    }
    for (int i = 0; i < 110; i++) {
        if (!g_ind_tested_line[i] || set[i]) continue;
        if (i >= 1 && i <= 99 && (workstn || g_ind_array_used)) continue;
        char name[8];
        if (i == rpg::IndicatorExpr::LR) snprintf(name, sizeof name, "LR");
        else if (i >= rpg::IndicatorExpr::H1) snprintf(name, sizeof name, "H%d", i - 100);
        else snprintf(name, sizeof name, "%02d", i);
        report_semantic_error(g_ind_tested_line[i], std::string("The name or indicator *IN") + name +
            " is not defined: the program refers to it but never sets it (IBM: RNF7030)");
    }
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
    g_semi_line = -1;
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


void report_semantic_error(int line, const std::string& msg) {
    report_fixed_format_error(line, msg);
}

void report_semantic_warning(int line, const std::string& msg) {
    fprintf(stderr, "Warning at line %d: %s\n", line, msg.c_str());
}
