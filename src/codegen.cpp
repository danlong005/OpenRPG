#include "codegen.h"
#include <iomanip>
#include <algorithm>

namespace rpg {

// Returns true if the expression is a string literal containing "CSV" (case-insensitive).
// Used at codegen time to select the CSV code path for DATA-INTO / DATA-GEN.
static bool isCsvParser(Expression* p) {
    if (!p) return false;
    auto* sl = dynamic_cast<StringLiteral*>(p);
    if (!sl) return false;
    std::string v = sl->value;
    std::transform(v.begin(), v.end(), v.begin(), [](unsigned char c){ return std::toupper(c); });
    return v.find("CSV") != std::string::npos;
}

std::string CodeGen::generate(Program& program) {
    out_.str("");
    indent_ = 1;
    in_procedure_ = false;
    program.accept(*this);
    return out_.str();
}

void CodeGen::emitIndent() {
    for (int i = 0; i < indent_; i++) out_ << "    ";
}

std::string CodeGen::emitExpr(Expression& expr) {
    expr_.str("");
    expr.accept(*this);
    return expr_.str();
}

static std::string stripOuterParens(const std::string& s) {
    if (s.size() >= 2 && s.front() == '(' && s.back() == ')') {
        int depth = 0;
        for (size_t i = 0; i < s.size(); i++) {
            if (s[i] == '(') depth++;
            else if (s[i] == ')') depth--;
            if (depth == 0 && i < s.size() - 1) return s;
        }
        return s.substr(1, s.size() - 2);
    }
    return s;
}

// Escapes a raw string for embedding as a C++ string literal — same
// escaping StringLiteral's own codegen uses, factored out here so
// DFTVAL('text') can produce an identical literal for a flat variable's
// initializer.
static std::string cppEscape(const std::string& s) {
    std::ostringstream o;
    for (unsigned char c : s) {
        if (c == '"')       o << "\\\"";
        else if (c == '\\') o << "\\\\";
        else if (c == '\n') o << "\\n";
        else if (c == '\r') o << "\\r";
        else if (c == '\t') o << "\\t";
        else if (c < 0x20 || c == 0x7f)
            o << "\\x" << std::hex << std::setw(2) << std::setfill('0')
              << static_cast<int>(c) << std::dec;
        else                o << static_cast<char>(c);
    }
    return o.str();
}

void CodeGen::emitLineDirective(int line) {
    if (debug_mode_ && line > 0 && !source_file_.empty()) {
        out_ << "#line " << line << " \"" << source_file_ << "\"\n";
    }
}

void CodeGen::emitStatements(std::vector<std::unique_ptr<Statement>>& stmts) {
    for (auto& s : stmts) {
        emitLineDirective(s->line);
        s->accept(*this);
    }
}

std::string CodeGen::typeToString(RPGType type, int /*length*/) {
    switch (type) {
        case RPGType::CHAR: return "std::string";
        case RPGType::VARCHAR: return "std::string";
        case RPGType::INT10: return "int";
        case RPGType::PACKED:
        case RPGType::ZONED: return "double";
        case RPGType::IND: return "bool";
        case RPGType::DATE: return "RpgDate";
        case RPGType::TIME: return "RpgTime";
        case RPGType::TIMESTAMP: return "RpgTimestamp";
        case RPGType::POINTER: return "void*";
        case RPGType::UNS: return "unsigned int";
        case RPGType::FLOAT4: return "float";
        case RPGType::FLOAT8: return "double";
        case RPGType::BINDEC: return "int";
        case RPGType::UCS2: return "std::string";
        case RPGType::OBJECT: return "void*";
    }
    return "int";
}

std::string CodeGen::paramTypeToString(const ParamDecl& p) {
    std::string base;
    if (!p.likeds.empty()) {
        base = p.likeds + "_t";
    } else {
        base = typeToString(p.type, p.length);
    }
    if (p.omit) {
        return base + "*";  // *OMIT params use pointers (nullptr = omitted)
    } else if (p.by_value) {
        return base;
    } else {
        return base + "&";
    }
}

std::string CodeGen::escapeSqlForCpp(const std::string& sql) {
    std::string result;
    for (char c : sql) {
        switch (c) {
            case '\n': result += " "; break;
            case '\r': break;
            case '\t': result += " "; break;
            case '"':  result += "\\\""; break;
            case '\\': result += "\\\\"; break;
            default:   result += c; break;
        }
    }
    return result;
}

std::string CodeGen::sqlCommentText(const std::string& sql) {
    // Replace newlines with spaces for single-line comment
    std::string result;
    for (char c : sql) {
        if (c == '\n' || c == '\r') result += ' ';
        else result += c;
    }
    return result;
}

void CodeGen::emitSqlBindParam(const std::string& var, int index, const std::string& handle) {
    emitIndent();
    out_ << "__sql_env.bindParam(" << handle << ", " << index << ", " << var << ");\n";
}

void CodeGen::emitSqlBindParamWithInd(const std::string& var, const std::string& ind_var, int index, const std::string& handle) {
    emitIndent();
    out_ << "__sql_env.bindParamWithInd(" << handle << ", " << index << ", " << var << ", (int)" << ind_var << ");\n";
}

void CodeGen::emitSqlBindCol(const std::string& var, int index, const std::string& handle) {
    emitIndent();
    out_ << "SQLLEN __sql_ind_" << index << " = 0;\n";
    emitIndent();
    out_ << "__sql_env.bindCol(" << handle << ", " << index << ", " << var
         << ", __sql_strbuf_" << index << ", sizeof(__sql_strbuf_" << index
         << "), __sql_ind_" << index << ");\n";
}

std::vector<std::string> CodeGen::expandSqlIntoVars(const std::vector<std::string>& vars) {
    std::vector<std::string> expanded;
    for (auto& v : vars) {
        auto dit = ds_defs_.find(v);
        if (dit != ds_defs_.end()) {
            // It's a DS — expand into qualified field references
            for (auto& f : dit->second->fields) {
                expanded.push_back(v + "." + f.name);
            }
        } else {
            expanded.push_back(v);
        }
    }
    return expanded;
}

std::vector<HostVarWithInd> CodeGen::expandSqlIntoVarsWithInd(const std::vector<HostVarWithInd>& vars) {
    std::vector<HostVarWithInd> expanded;
    for (auto& hvwi : vars) {
        auto dit = ds_defs_.find(hvwi.var);
        if (dit != ds_defs_.end() && hvwi.ind_var.empty()) {
            for (auto& f : dit->second->fields) {
                expanded.push_back({hvwi.var + "." + f.name, ""});
            }
        } else {
            expanded.push_back(hvwi);
        }
    }
    return expanded;
}

void CodeGen::visit(ExecSqlStmt& node) {
    uses_sql_ = true;
    emitIndent();
    out_ << "// EXEC SQL " << sqlCommentText(node.sql_text) << "\n";

    switch (node.kind) {
        case SqlStmtKind::COMMIT:
            emitIndent();
            out_ << "__sql_env.commit();\n";
            break;
        case SqlStmtKind::ROLLBACK:
            emitIndent();
            out_ << "__sql_env.rollback();\n";
            break;
        case SqlStmtKind::CONNECT: {
            auto info = parseConnect(node.sql_text);
            if (info.is_reset) {
                emitIndent();
                out_ << "__sql_env.disconnect();\n";
            } else if (info.user == "__CONNSTR__") {
                // Connection string mode: CONNECT USING :connStr
                emitIndent();
                out_ << "__sql_env.connectStr(" << info.server << ");\n";
            } else if (!info.user.empty()) {
                emitIndent();
                out_ << "__sql_env.connect(" << info.server
                     << ", " << info.user << ", " << info.password << ");\n";
            } else {
                emitIndent();
                out_ << "__sql_env.connect(" << info.server << ");\n";
            }
            break;
        }
        case SqlStmtKind::DISCONNECT:
            emitIndent();
            out_ << "__sql_env.disconnect();\n";
            break;
        case SqlStmtKind::DECLARE_CURSOR: {
            std::string cursor_name = extractCursorName(node.sql_text);
            std::string query = extractCursorQuery(node.sql_text);
            std::string parameterized = replaceHostVarsWithMarkers(query);
            std::vector<std::string> host_vars = extractHostVariables(query);
            emitIndent();
            out_ << "__sql_env.declareCursor(\"" << cursor_name
                 << "\", \"" << escapeSqlForCpp(parameterized) << "\");\n";
            // Store host vars for binding at OPEN time
            if (!host_vars.empty()) {
                cursor_host_vars_[cursor_name] = host_vars;
            }
            break;
        }
        case SqlStmtKind::OPEN_CURSOR: {
            std::string cursor_name = extractCursorName(node.sql_text);
            auto it = cursor_host_vars_.find(cursor_name);
            if (it != cursor_host_vars_.end() && !it->second.empty()) {
                // Bind host variables before opening
                emitIndent();
                out_ << "{\n";
                indent_++;
                emitIndent();
                out_ << "SQLHSTMT __cstmt = __sql_env.getCursorStmt(\"" << cursor_name << "\");\n";
                emitIndent();
                out_ << "__sql_env.clearParamBufs();\n";
                for (size_t i = 0; i < it->second.size(); i++) {
                    emitSqlBindParam(it->second[i], static_cast<int>(i + 1), "__cstmt");
                }
                indent_--;
                emitIndent();
                out_ << "}\n";
            }
            emitIndent();
            out_ << "__sql_env.openCursor(\"" << cursor_name << "\");\n";
            break;
        }
        case SqlStmtKind::CLOSE_CURSOR: {
            std::string cursor_name = extractCursorName(node.sql_text);
            emitIndent();
            out_ << "__sql_env.closeCursor(\"" << cursor_name << "\");\n";
            break;
        }
        case SqlStmtKind::FETCH: {
            std::string cursor_name = extractCursorName(node.sql_text);
            std::vector<HostVarWithInd> into_hvwi = expandSqlIntoVarsWithInd(extractFetchIntoWithInd(node.sql_text));
            // For multi-row FETCH, fall back to plain var names (indicators not supported with FOR :n ROWS)
            std::vector<std::string> into_vars;
            for (auto& h : into_hvwi) into_vars.push_back(h.var);
            std::string rows_var;
            bool multi_row = parseFetchForRows(node.sql_text, rows_var);

            emitIndent();
            out_ << "{\n";
            indent_++;
            emitIndent();
            out_ << "SQLHSTMT __cstmt = __sql_env.getCursorStmt(\"" << cursor_name << "\");\n";

            if (multi_row) {
                // Multi-row FETCH: loop N times into array elements
                emitIndent();
                out_ << "for (int __ri = 0; __ri < " << rows_var << "; __ri++) {\n";
                indent_++;

                for (size_t i = 0; i < into_vars.size(); i++) {
                    emitIndent();
                    out_ << "char __sql_strbuf_" << (i+1) << "[4096] = {};\n";
                }
                for (size_t i = 0; i < into_vars.size(); i++) {
                    // Bind to array element: VAR[__ri]
                    emitIndent();
                    out_ << "SQLLEN __sql_ind_" << (i+1) << " = 0;\n";
                    emitIndent();
                    out_ << "__sql_env.bindCol(__cstmt, " << (i+1) << ", "
                         << into_vars[i] << "[__ri], __sql_strbuf_" << (i+1)
                         << ", sizeof(__sql_strbuf_" << (i+1) << "), __sql_ind_" << (i+1) << ");\n";
                }
                emitIndent();
                out_ << "SQLRETURN __frc = SQLFetch(__cstmt);\n";
                emitIndent();
                out_ << "__sql_env.updateStmtDiag(__cstmt, __frc);\n";
                emitIndent();
                out_ << "if (__frc != SQL_SUCCESS && __frc != SQL_SUCCESS_WITH_INFO) break;\n";
                for (size_t i = 0; i < into_vars.size(); i++) {
                    emitIndent();
                    out_ << "RpgSqlEnv::copyStrBuf(" << into_vars[i]
                         << "[__ri], __sql_strbuf_" << (i+1) << ", __frc);\n";
                }

                indent_--;
                emitIndent();
                out_ << "}\n";
            } else {
                // Single-row FETCH
                for (size_t i = 0; i < into_vars.size(); i++) {
                    emitIndent();
                    out_ << "char __sql_strbuf_" << (i+1) << "[4096] = {};\n";
                }
                for (size_t i = 0; i < into_vars.size(); i++) {
                    emitSqlBindCol(into_vars[i], static_cast<int>(i + 1), "__cstmt");
                }
                emitIndent();
                out_ << "SQLRETURN __frc = SQLFetch(__cstmt);\n";
                emitIndent();
                out_ << "__sql_env.updateStmtDiag(__cstmt, __frc);\n";
                for (size_t i = 0; i < into_vars.size(); i++) {
                    emitIndent();
                    out_ << "RpgSqlEnv::copyStrBuf(" << into_vars[i]
                         << ", __sql_strbuf_" << (i+1) << ", __frc);\n";
                    if (!into_hvwi[i].ind_var.empty()) {
                        emitIndent();
                        out_ << into_hvwi[i].ind_var << " = (__sql_ind_" << (i+1) << " < 0) ? -1 : 0;\n";
                    }
                }
            }

            indent_--;
            emitIndent();
            out_ << "}\n";
            break;
        }
        case SqlStmtKind::SELECT_INTO: {
            // Strip INTO clause and bind result columns
            std::string stripped;
            std::vector<HostVarWithInd> raw_into_hvwi = extractSelectIntoWithInd(node.sql_text, stripped);
            std::vector<HostVarWithInd> into_hvwi = expandSqlIntoVarsWithInd(raw_into_hvwi);
            std::string parameterized = replaceHostVarsWithMarkers(stripped);
            std::vector<HostVarWithInd> host_hvwi = extractHostVarsWithInd(stripped);

            emitIndent();
            out_ << "{\n";
            indent_++;
            emitIndent();
            out_ << "SQLHSTMT __hstmt = __sql_env.allocStmt();\n";
            emitIndent();
            out_ << "__sql_env.clearParamBufs();\n";
            emitIndent();
            out_ << "SQLPrepare(__hstmt, (SQLCHAR*)\"" << escapeSqlForCpp(parameterized) << "\", SQL_NTS);\n";

            // Bind input parameters
            for (size_t i = 0; i < host_hvwi.size(); i++) {
                if (host_hvwi[i].ind_var.empty()) {
                    emitSqlBindParam(host_hvwi[i].var, static_cast<int>(i + 1));
                } else {
                    emitSqlBindParamWithInd(host_hvwi[i].var, host_hvwi[i].ind_var, static_cast<int>(i + 1));
                }
            }

            // Declare string buffers for output columns (needed since bind happens before fetch)
            for (size_t i = 0; i < into_hvwi.size(); i++) {
                emitIndent();
                out_ << "char __sql_strbuf_" << (i+1) << "[4096] = {};\n";
            }

            // Bind output columns
            for (size_t i = 0; i < into_hvwi.size(); i++) {
                emitSqlBindCol(into_hvwi[i].var, static_cast<int>(i + 1));
            }

            // Execute and fetch
            emitIndent();
            out_ << "SQLExecute(__hstmt);\n";
            emitIndent();
            out_ << "SQLRETURN __frc = SQLFetch(__hstmt);\n";
            emitIndent();
            out_ << "__sql_env.updateStmtDiag(__hstmt, __frc);\n";

            // Copy string buffers back to string variables after fetch; assign indicator vars
            for (size_t i = 0; i < into_hvwi.size(); i++) {
                emitIndent();
                out_ << "RpgSqlEnv::copyStrBuf(" << into_hvwi[i].var
                     << ", __sql_strbuf_" << (i+1) << ", __frc);\n";
                if (!into_hvwi[i].ind_var.empty()) {
                    emitIndent();
                    out_ << into_hvwi[i].ind_var << " = (__sql_ind_" << (i+1) << " < 0) ? -1 : 0;\n";
                }
            }

            emitIndent();
            out_ << "SQLFreeHandle(SQL_HANDLE_STMT, __hstmt);\n";
            indent_--;
            emitIndent();
            out_ << "}\n";
            break;
        }
        case SqlStmtKind::PREPARE: {
            std::string stmt_name, from_var;
            parsePrepare(node.sql_text, stmt_name, from_var);
            emitIndent();
            out_ << "__sql_env.prepareStmt(\"" << stmt_name << "\", " << from_var << ");\n";
            break;
        }
        case SqlStmtKind::EXECUTE: {
            std::string stmt_name;
            std::vector<std::string> using_vars;
            parseExecute(node.sql_text, stmt_name, using_vars);
            if (!using_vars.empty()) {
                emitIndent();
                out_ << "{\n";
                indent_++;
                emitIndent();
                out_ << "SQLHSTMT __pstmt = __sql_env.getPreparedStmt(\"" << stmt_name << "\");\n";
                emitIndent();
                out_ << "__sql_env.clearParamBufs();\n";
                for (size_t i = 0; i < using_vars.size(); i++) {
                    emitSqlBindParam(using_vars[i], static_cast<int>(i + 1), "__pstmt");
                }
                indent_--;
                emitIndent();
                out_ << "}\n";
            }
            emitIndent();
            out_ << "__sql_env.executeStmt(\"" << stmt_name << "\");\n";
            break;
        }
        case SqlStmtKind::EXECUTE_IMMEDIATE: {
            std::string host_var = parseExecuteImmediate(node.sql_text);
            if (!host_var.empty()) {
                emitIndent();
                out_ << "__sql_env.execDirect(" << host_var << ");\n";
            } else {
                // Literal SQL after EXECUTE IMMEDIATE (no host var)
                std::string upper = node.sql_text;
                for (auto& c : upper) c = toupper(static_cast<unsigned char>(c));
                size_t pos = upper.find("IMMEDIATE");
                if (pos != std::string::npos) {
                    pos += 9;
                    while (pos < node.sql_text.size() && std::isspace(static_cast<unsigned char>(node.sql_text[pos]))) pos++;
                    std::string literal_sql = node.sql_text.substr(pos);
                    emitIndent();
                    out_ << "__sql_env.execDirect(\"" << escapeSqlForCpp(literal_sql) << "\");\n";
                }
            }
            break;
        }
        case SqlStmtKind::GET_DIAGNOSTICS: {
            auto items = parseGetDiagnostics(node.sql_text);
            for (auto& item : items) {
                emitIndent();
                if (item.item == "ROW_COUNT") {
                    out_ << item.var << " = static_cast<int>(__sql_env.row_count);\n";
                } else if (item.item == "DB2_RETURN_STATUS" || item.item == "RETURN_STATUS") {
                    out_ << item.var << " = __sql_env.sqlcode;\n";
                } else {
                    out_ << item.var << " = __sql_env.sqlcode; // GET DIAGNOSTICS " << item.item << "\n";
                }
            }
            break;
        }
        case SqlStmtKind::CALL: {
            std::string proc_name;
            std::vector<std::string> params;
            parseCall(node.sql_text, proc_name, params);
            std::string call_sql = "{CALL " + proc_name + "(";
            for (size_t i = 0; i < params.size(); i++) {
                if (i > 0) call_sql += ", ";
                call_sql += "?";
            }
            call_sql += ")}";
            if (params.empty()) {
                emitIndent();
                out_ << "__sql_env.execDirect(\"" << escapeSqlForCpp(call_sql) << "\");\n";
            } else {
                emitIndent();
                out_ << "{\n";
                indent_++;
                emitIndent();
                out_ << "SQLHSTMT __hstmt = __sql_env.allocStmt();\n";
                emitIndent();
                out_ << "__sql_env.clearParamBufs();\n";
                emitIndent();
                out_ << "SQLPrepare(__hstmt, (SQLCHAR*)\"" << escapeSqlForCpp(call_sql) << "\", SQL_NTS);\n";
                for (size_t i = 0; i < params.size(); i++) {
                    emitSqlBindParam(params[i], static_cast<int>(i + 1));
                }
                emitIndent();
                out_ << "SQLRETURN __erc = SQLExecute(__hstmt);\n";
                emitIndent();
                out_ << "__sql_env.updateStmtDiag(__hstmt, __erc);\n";
                emitIndent();
                out_ << "SQLFreeHandle(SQL_HANDLE_STMT, __hstmt);\n";
                indent_--;
                emitIndent();
                out_ << "}\n";
            }
            break;
        }
        default: {
            // Check for multi-row INSERT (FOR :n ROWS)
            std::string rows_var, stripped_sql;
            bool multi_row = parseInsertForRows(node.sql_text, rows_var, stripped_sql);
            std::string sql_text = multi_row ? stripped_sql : node.sql_text;

            // General case: prepare + bind params + execute (INSERT/UPDATE/DELETE/other)
            std::vector<HostVarWithInd> host_hvwi = extractHostVarsWithInd(sql_text);
            std::string parameterized = replaceHostVarsWithMarkers(sql_text);

            if (host_hvwi.empty() && !multi_row) {
                // Simple execution, no host variables
                emitIndent();
                out_ << "__sql_env.execDirect(\"" << escapeSqlForCpp(parameterized) << "\");\n";
            } else if (multi_row && !host_hvwi.empty()) {
                // Multi-row INSERT: loop N times with array element bindings (indicators not supported)
                emitIndent();
                out_ << "{\n";
                indent_++;
                emitIndent();
                out_ << "SQLHSTMT __hstmt = __sql_env.allocStmt();\n";
                emitIndent();
                out_ << "SQLPrepare(__hstmt, (SQLCHAR*)\"" << escapeSqlForCpp(parameterized) << "\", SQL_NTS);\n";
                emitIndent();
                out_ << "for (int __ri = 0; __ri < " << rows_var << "; __ri++) {\n";
                indent_++;
                emitIndent();
                out_ << "__sql_env.clearParamBufs();\n";
                for (size_t i = 0; i < host_hvwi.size(); i++) {
                    emitIndent();
                    out_ << "__sql_env.bindParam(__hstmt, " << (i+1) << ", "
                         << host_hvwi[i].var << "[__ri]);\n";
                }
                emitIndent();
                out_ << "SQLRETURN __erc = SQLExecute(__hstmt);\n";
                emitIndent();
                out_ << "__sql_env.updateStmtDiag(__hstmt, __erc);\n";
                emitIndent();
                out_ << "if (__erc != SQL_SUCCESS && __erc != SQL_SUCCESS_WITH_INFO) break;\n";
                indent_--;
                emitIndent();
                out_ << "}\n";
                emitIndent();
                out_ << "SQLFreeHandle(SQL_HANDLE_STMT, __hstmt);\n";
                indent_--;
                emitIndent();
                out_ << "}\n";
            } else {
                emitIndent();
                out_ << "{\n";
                indent_++;
                emitIndent();
                out_ << "SQLHSTMT __hstmt = __sql_env.allocStmt();\n";
                emitIndent();
                out_ << "__sql_env.clearParamBufs();\n";
                emitIndent();
                out_ << "SQLPrepare(__hstmt, (SQLCHAR*)\"" << escapeSqlForCpp(parameterized) << "\", SQL_NTS);\n";

                for (size_t i = 0; i < host_hvwi.size(); i++) {
                    if (host_hvwi[i].ind_var.empty()) {
                        emitSqlBindParam(host_hvwi[i].var, static_cast<int>(i + 1));
                    } else {
                        emitSqlBindParamWithInd(host_hvwi[i].var, host_hvwi[i].ind_var, static_cast<int>(i + 1));
                    }
                }

                emitIndent();
                out_ << "SQLRETURN __erc = SQLExecute(__hstmt);\n";
                emitIndent();
                out_ << "__sql_env.updateStmtDiag(__hstmt, __erc);\n";
                emitIndent();
                out_ << "SQLFreeHandle(SQL_HANDLE_STMT, __hstmt);\n";
                indent_--;
                emitIndent();
                out_ << "}\n";
            }
            break;
        }
    }
}

void CodeGen::visit(Program& node) {
    // Store date/time format settings
    datfmt_ = node.datfmt;
    timfmt_ = node.timfmt;

    // *USER constant requires PSDS initialization
    if (node.uses_user_const) uses_psds_ = true;

    // Scan for EXEC SQL / XML-INTO / PSDS / RLA usage to set feature flags
    for (auto& stmt : node.statements) {
        if (dynamic_cast<ExecSqlStmt*>(stmt.get())) uses_sql_ = true;
        if (dynamic_cast<XmlIntoStmt*>(stmt.get())) uses_xml_ = true;
        if (auto* di = dynamic_cast<DataIntoStmt*>(stmt.get())) {
            if (isCsvParser(di->parser.get())) uses_csv_ = true; else uses_json_ = true;
        }
        if (auto* dg = dynamic_cast<DataGenStmt*>(stmt.get())) {
            if (isCsvParser(dg->parser.get())) uses_csv_ = true; else uses_json_ = true;
        }
        auto* ds = dynamic_cast<DclDS*>(stmt.get());
        if (ds && ds->is_psds) uses_psds_ = true;
        auto* dclf = dynamic_cast<DclF*>(stmt.get());
        if (dclf && dclf->usage == "DISK") uses_rla_ = true;
        if (dclf && dclf->usage == "WORKSTN") uses_dspf_ = true;
        if (auto* irf = dynamic_cast<IRecordFormat*>(stmt.get())) {
            flat_input_formats_[irf->fileName].push_back(irf);
            uses_flatfile_ = true;
        }
        if (auto* orf = dynamic_cast<ORecordFormat*>(stmt.get())) {
            flat_output_formats_[orf->fileName] = orf;
            uses_flatfile_ = true;
        }
        // Also check inside procedures
        auto* proc = dynamic_cast<DclProc*>(stmt.get());
        if (proc) {
            for (auto& s : proc->body) {
                if (dynamic_cast<ExecSqlStmt*>(s.get())) uses_sql_ = true;
                if (dynamic_cast<XmlIntoStmt*>(s.get())) uses_xml_ = true;
                if (auto* di = dynamic_cast<DataIntoStmt*>(s.get())) {
                    if (isCsvParser(di->parser.get())) uses_csv_ = true; else uses_json_ = true;
                }
                if (auto* dg = dynamic_cast<DataGenStmt*>(s.get())) {
                    if (isCsvParser(dg->parser.get())) uses_csv_ = true; else uses_json_ = true;
                }
            }
        }
    }
    if (uses_rla_) {
        // Only activate RLA if at least one file has a schema in ext_file_descs_
        bool has_schema = false;
        for (auto& stmt : node.statements) {
            auto* dclf = dynamic_cast<DclF*>(stmt.get());
            if (dclf && dclf->usage == "DISK" && ext_file_descs_.count(dclf->name)) {
                has_schema = true;
                break;
            }
        }
        uses_rla_ = has_schema;
    }
    if (uses_rla_) uses_sql_ = true; // RLA piggybacks on SQL runtime

    out_ << "#include \"rpg_runtime.h\"\n";
    if (uses_dspf_) {
        out_ << "#include \"rpg_dspf_runtime.h\"\n";
    }
    if (uses_sql_) {
        out_ << "#include \"rpg_sql_runtime.h\"\n";
    }
    if (uses_xml_) {
        out_ << "#include \"rpg_xml_runtime.h\"\n";
    }
    if (uses_json_) {
        out_ << "#include \"rpg_json_runtime.h\"\n";
    }
    if (uses_csv_) {
        out_ << "#include \"rpg_csv_runtime.h\"\n";
    }
    if (uses_flatfile_) {
        out_ << "#include \"rpg_flatfile_runtime.h\"\n";
    }
    out_ << "#include <algorithm>\n";
    out_ << "#include <array>\n";
    out_ << "#include <cmath>\n";
    out_ << "#include <iostream>\n";
    out_ << "#include <string>\n";
    out_ << "#include <vector>\n";

    // Emit date/time format configuration if non-default
    if (!datfmt_.empty()) {
        out_ << "static const std::string RPG_DATFMT = \"" << datfmt_ << "\";\n";
    }
    if (!timfmt_.empty()) {
        out_ << "static const std::string RPG_TIMFMT = \"" << timfmt_ << "\";\n";
    }

    // Categorize statements into DS definitions, procs/prototypes, and main body
    std::vector<Statement*> ds_stmts;
    std::vector<Statement*> main_stmts;
    std::vector<Statement*> proc_stmts;
    std::vector<Statement*> export_decls; // EXPORT/IMPORT vars go at file scope

    for (auto& stmt : node.statements) {
        if (dynamic_cast<DclProc*>(stmt.get()) || dynamic_cast<DclPR*>(stmt.get())) {
            proc_stmts.push_back(stmt.get());
        } else if (dynamic_cast<DclDS*>(stmt.get())) {
            ds_stmts.push_back(stmt.get());
        } else {
            // Check if this is an EXPORT or IMPORT DclS — goes at file scope
            auto* dcls = dynamic_cast<DclS*>(stmt.get());
            if (dcls && (dcls->is_export || dcls->is_import)) {
                export_decls.push_back(stmt.get());
            } else {
                main_stmts.push_back(stmt.get());
            }
        }
    }

    // Emit DS struct definitions at file scope (needed for procedure params)
    indent_ = 0;
    for (auto* s : ds_stmts) {
        s->accept(*this);
    }

    // Emit EXPORT/IMPORT declarations at file scope
    for (auto* s : export_decls) {
        s->accept(*this);
    }

    // Emit global SQL env if needed
    if (uses_sql_) {
        out_ << "static RpgSqlEnv __sql_env;\n\n";
    }

    // Pre-collect all procedure/prototype signatures (needed for OVERLOAD wrapper generation)
    for (auto* s : proc_stmts) {
        if (auto* pr = dynamic_cast<DclPR*>(s)) {
            if (pr->overload_impls.empty()) proc_sigs_[pr->name] = pr->interface;
        } else if (auto* proc = dynamic_cast<DclProc*>(s)) {
            proc_sigs_[proc->name] = proc->interface;
        }
    }

    // Emit prototypes and procedures
    for (auto* s : proc_stmts) {
        s->accept(*this);
    }

    // NOMAIN: no main() function
    if (node.nomain) {
        return;
    }

    // MAIN(procname): emit a main() that calls the named procedure
    if (!node.main_proc.empty()) {
        out_ << "int main() {\n";
        out_ << "    " << node.main_proc << "();\n";
        out_ << "    return 0;\n";
        out_ << "}\n";
        return;
    }

    // Emit main (use argc/argv when PSDS is declared)
    if (uses_psds_) {
        out_ << "int main(int argc, char* argv[]) {\n";
        out_ << "    (void)argc;\n";
        out_ << "    rpg_psds_init(argv[0]);\n";
    } else {
        out_ << "int main() {\n";
    }
    out_ << "    bool rpg_indicators[100] = {};\n";
    indent_ = 1;

    // Emit DS instance declarations in main
    for (auto* s : ds_stmts) {
        auto* ds = dynamic_cast<DclDS*>(s);
        std::string type_name = ds->like_ds.empty() ? ds->name + "_t" : ds->like_ds + "_t";
        emitIndent();
        if (ds->dim > 0 && (ds->dim_type == 1 || ds->dim_type == 2)) {
            // DIM(*VAR:max) or DIM(*AUTO:max) — use std::vector
            out_ << "std::vector<" << type_name << "> " << ds->name << ";\n";
            emitIndent();
            out_ << ds->name << ".reserve(" << ds->dim << ");\n";
        } else if (ds->dim > 0) {
            out_ << "std::array<" << type_name << ", " << ds->dim << "> " << ds->name << ";\n";
        } else {
            out_ << type_name << " " << ds->name << ";\n";
        }
        // If this is a PSDS, initialize POS-mapped subfields from runtime
        if (ds->is_psds && ds->dim == 0) {
            for (auto& f : ds->fields) {
                if (f.pos <= 0) continue;
                emitIndent();
                bool is_numeric = (f.type == RPGType::INT10 || f.type == RPGType::PACKED ||
                                   f.type == RPGType::ZONED || f.type == RPGType::FLOAT8 ||
                                   f.type == RPGType::UNS);
                if (is_numeric) {
                    out_ << ds->name << "." << f.name << " = rpg_psds_field_int(" << f.pos << ");\n";
                } else {
                    out_ << ds->name << "." << f.name << " = rpg_psds_field_str(" << f.pos << ");\n";
                }
            }
        }
    }

    // Separate declarations, subroutines, and executable statements
    std::vector<Statement*> decl_stmts;
    std::vector<Statement*> sr_stmts;   // subroutines (lambdas, emit before use)
    std::vector<Statement*> exec_stmts;
    Statement* inzsr_stmt = nullptr;
    Statement* pssr_stmt = nullptr;
    for (auto* s : main_stmts) {
        auto* bsr = dynamic_cast<BegSR*>(s);
        if (bsr && bsr->name == "*INZSR") {
            inzsr_stmt = s;
        } else if (bsr && bsr->name == "*PSSR") {
            pssr_stmt = s;
        } else if (bsr) {
            sr_stmts.push_back(s);
        } else if (dynamic_cast<DclS*>(s) || dynamic_cast<DclC*>(s) || dynamic_cast<DclF*>(s)) {
            decl_stmts.push_back(s);
        } else {
            exec_stmts.push_back(s);
        }
    }

    // 1. Emit declarations (includes DCL-F which registers file structs)
    for (auto* s : decl_stmts) {
        emitLineDirective(s->line);
        s->accept(*this);
    }

    // 1.5 Auto-connect from rpgc.conf (if DSN provided and program uses SQL or RLA)
    if (!conf_dsn_.empty() && uses_sql_) {
        emitIndent();
        out_ << "__sql_env.connectStr(\"" << conf_dsn_ << "\");\n";
    }

    // Emit RAII auto-disconnect guard (fires before any return, including *INLR = *ON)
    if (uses_sql_) {
        emitIndent();
        out_ << "struct __SqlGuard { ~__SqlGuard() { __sql_env.disconnect(); } } __sql_guard;\n";
    }

    // dspf_init: open display file descriptor(s) for each WORKSTN file
    if (uses_dspf_) {
        for (auto& [fname, df] : file_defs_) {
            if (df->usage != "WORKSTN") continue;
            if (!dspf_descs_.count(fname)) continue;
            emitIndent();
            out_ << "dspf_init(\"" << fname << ".dspfd\");\n";
        }
        emitIndent();
        out_ << "struct __DspfGuard { ~__DspfGuard() { dspf_close(); } } __dspf_guard;\n";
    }

    // 2. Emit subroutine lambdas (so they can be called later)
    for (auto* s : sr_stmts) {
        emitLineDirective(s->line);
        s->accept(*this);
    }

    // 2.5 Emit *PSSR lambda
    if (pssr_stmt) {
        emitLineDirective(pssr_stmt->line);
        pssr_stmt->accept(*this);
    }

    // 3. Emit *INZSR and auto-call it
    if (inzsr_stmt) {
        emitLineDirective(inzsr_stmt->line);
        inzsr_stmt->accept(*this);
        emitIndent();
        out_ << "sr__INZSR();\n";
    }

    // 4. Emit remaining executable statements — wrap in try/catch if *PSSR exists
    if (pssr_stmt) {
        emitIndent(); out_ << "try {\n"; indent_++;
    }
    for (auto* s : exec_stmts) {
        emitLineDirective(s->line);
        s->accept(*this);
    }
    if (pssr_stmt) {
        indent_--; emitIndent(); out_ << "} catch (...) {\n";
        indent_++;
        if (uses_psds_) { emitIndent(); out_ << "rpg_psds_sync();\n"; }
        emitIndent(); out_ << "sr__PSSR();\n";
        indent_--; emitIndent(); out_ << "}\n";
    }
    out_ << "}\n";
}

void CodeGen::visit(DclPR& node) {
    // OVERLOAD: emit inline C++ wrapper functions, one per implementation
    if (!node.overload_impls.empty()) {
        for (auto& impl : node.overload_impls) {
            auto it = proc_sigs_.find(impl);
            if (it == proc_sigs_.end()) continue;
            const ProcInterface& sig = it->second;
            std::string ret = sig.has_return ? typeToString(sig.return_type) : "void";
            out_ << "inline " << ret << " " << node.name << "(";
            for (size_t i = 0; i < sig.params.size(); i++) {
                if (i > 0) out_ << ", ";
                out_ << paramTypeToString(sig.params[i]) << " __p" << i;
            }
            out_ << ") { ";
            if (sig.has_return) out_ << "return ";
            out_ << impl << "(";
            for (size_t i = 0; i < sig.params.size(); i++) {
                if (i > 0) out_ << ", ";
                out_ << "__p" << i;
            }
            out_ << "); }\n";
        }
        return;
    }

    bool has_nopass = std::any_of(node.interface.params.begin(), node.interface.params.end(),
                                  [](const ParamDecl& p) { return p.nopass; });
    bool has_omit = std::any_of(node.interface.params.begin(), node.interface.params.end(),
                                 [](const ParamDecl& p) { return p.omit; });
    if (has_nopass) {
        nopass_procs_.insert(node.name);
    }
    if (has_nopass || has_omit) {
        nopass_proc_params_[node.name] = node.interface.params;
    }

    // Determine the C++ function name
    std::string cppName = node.name;
    if (!node.extproc.empty()) {
        cppName = node.extproc;
        // Track the mapping: RPG name → C++ name
        extproc_map_[node.name] = node.extproc;
    } else if (!node.extpgm.empty()) {
        cppName = node.extpgm;
        extproc_map_[node.name] = node.extpgm;
    }

    // Emit C++ forward declaration
    std::string ret = node.interface.has_return
        ? typeToString(node.interface.return_type) : "void";
    out_ << ret << " " << cppName << "(";
    for (size_t i = 0; i < node.interface.params.size(); i++) {
        if (i > 0) out_ << ", ";
        out_ << paramTypeToString(node.interface.params[i])
             << " " << node.interface.params[i].name;
        if (node.interface.params[i].nopass) {
            out_ << " = " << paramTypeDefault(node.interface.params[i]);
        }
    }
    if (has_nopass) {
        out_ << ", int _rpg_parms = " << countRequiredParams(node.interface.params);
    }
    out_ << ");\n";
    if (!node.extpgm.empty()) {
        out_ << "// EXTPGM: " << node.name << " → " << node.extpgm << "\n";
    }
}

void CodeGen::visit(DclProc& node) {
    bool has_nopass = std::any_of(node.interface.params.begin(), node.interface.params.end(),
                                  [](const ParamDecl& p) { return p.nopass; });

    std::string ret = node.interface.has_return
        ? typeToString(node.interface.return_type) : "void";
    out_ << ret << " " << node.name << "(";
    for (size_t i = 0; i < node.interface.params.size(); i++) {
        if (i > 0) out_ << ", ";
        out_ << paramTypeToString(node.interface.params[i])
             << " " << node.interface.params[i].name;
        // Don't emit default values here - they go in the prototype (DclPR)
    }
    if (has_nopass) {
        out_ << ", int _rpg_parms";
    }
    out_ << ") {\n";
    indent_ = 1;
    in_procedure_ = true;
    current_proc_parm_count_ = static_cast<int>(node.interface.params.size());
    has_nopass_params_ = has_nopass;
    current_proc_name_ = node.name;
    if (has_nopass) {
        nopass_procs_.insert(node.name);
    }

    // Detect *PSSR in procedure body
    Statement* proc_pssr_stmt = nullptr;
    for (auto& s : node.body) {
        auto* bsr = dynamic_cast<BegSR*>(s.get());
        if (bsr && bsr->name == "*PSSR") {
            proc_pssr_stmt = s.get();
            break;
        }
    }

    if (!node.on_exit_body.empty()) {
        // Emit declarations first, then scope guard, then executable statements
        for (auto& s : node.body) {
            if (dynamic_cast<DclS*>(s.get()) || dynamic_cast<DclC*>(s.get()) || dynamic_cast<DclDS*>(s.get())) {
                s->accept(*this);
            }
        }
        // Emit *PSSR lambda before scope guard
        if (proc_pssr_stmt) {
            proc_pssr_stmt->accept(*this);
        }
        emitIndent();
        out_ << "auto _on_exit_fn = rpg_make_scope_guard([&]() {\n";
        indent_++;
        emitStatements(node.on_exit_body);
        indent_--;
        emitIndent();
        out_ << "});\n";
        if (proc_pssr_stmt) {
            emitIndent(); out_ << "try {\n"; indent_++;
        }
        for (auto& s : node.body) {
            if (!dynamic_cast<DclS*>(s.get()) && !dynamic_cast<DclC*>(s.get()) && !dynamic_cast<DclDS*>(s.get()) && s.get() != proc_pssr_stmt) {
                s->accept(*this);
            }
        }
        if (proc_pssr_stmt) {
            indent_--; emitIndent(); out_ << "} catch (...) {\n";
            indent_++; emitIndent(); out_ << "sr__PSSR();\n";
            indent_--; emitIndent(); out_ << "}\n";
        }
    } else {
        // Separate declarations, *PSSR, subroutines, and executable statements
        if (proc_pssr_stmt) {
            // Need to emit declarations first, then *PSSR lambda, then try/catch around the rest
            for (auto& s : node.body) {
                if (dynamic_cast<DclS*>(s.get()) || dynamic_cast<DclC*>(s.get()) || dynamic_cast<DclDS*>(s.get())) {
                    s->accept(*this);
                }
            }
            // Emit subroutines (non-*PSSR)
            for (auto& s : node.body) {
                auto* bsr = dynamic_cast<BegSR*>(s.get());
                if (bsr && s.get() != proc_pssr_stmt) {
                    s->accept(*this);
                }
            }
            proc_pssr_stmt->accept(*this);
            emitIndent(); out_ << "try {\n"; indent_++;
            for (auto& s : node.body) {
                if (!dynamic_cast<DclS*>(s.get()) && !dynamic_cast<DclC*>(s.get()) && !dynamic_cast<DclDS*>(s.get()) && !dynamic_cast<BegSR*>(s.get())) {
                    s->accept(*this);
                }
            }
            indent_--; emitIndent(); out_ << "} catch (...) {\n";
            indent_++; emitIndent(); out_ << "sr__PSSR();\n";
            indent_--; emitIndent(); out_ << "}\n";
        } else {
            emitStatements(node.body);
        }
    }
    in_procedure_ = false;
    current_proc_parm_count_ = 0;
    has_nopass_params_ = false;
    current_proc_name_.clear();
    out_ << "}\n";
}

void CodeGen::visit(ExprStmt& node) {
    emitIndent();
    out_ << emitExpr(*node.expr) << ";\n";
}

void CodeGen::visit(DclF& node) {
    if (node.usage == "WORKSTN") {
        file_defs_[node.name] = &node;
        emitIndent();
        out_ << "// --- WORKSTN file: " << node.name << " ---\n";

        auto dit = dspf_descs_.find(node.name);
        if (dit == dspf_descs_.end()) {
            emitIndent();
            out_ << "// No .dspfd descriptor found for " << node.name
                 << " — run: dspfc " << node.name << ".dspf\n";
            return;
        }
        const DspfFileInfo& dfi = dit->second;

        // Include the generated header (struct types for each record format)
        out_ << "#include \"" << node.name << "_dspf.h\"\n";

        // Emit struct instances and flat RPG field variables
        for (const DspfRecInfo& rec : dfi.records) {
            emitIndent();
            out_ << rec.name << "_buf " << rec.name << "_buf_ = {}; "
                 << "// record format buffer\n";
            emitIndent();
            out_ << "bool " << rec.name << "_eof = false; "
                 << "// %EOF(" << rec.name << ") — meaningful after READC\n";
            for (const DspfFldInfo& f : rec.fields) {
                // HIDDEN fields still get a flat variable — "hidden" only
                // means not rendered, not "no data" (e.g. SFLRCDNBR HIDDEN
                // needs to be readable after EXFMT to know which row was
                // selected).
                emitIndent();
                // DFTVAL('text') seeds the field's initial value — its
                // displayed content before the program ever sets it, on
                // both a normal record and (since a subfile row's stored
                // fields come from whatever the flat var held at WRITE
                // time) a subfile row too.
                if ((f.dtype == 'A' || f.dtype == 'L' || f.dtype == 'T' || f.dtype == 'Z')) {
                    out_ << "std::string " << f.rpgName() << " = \"" << cppEscape(f.dftval)
                         << "\"; // " << rec.name << "." << f.name << "\n";
                } else if (f.dtype == 'B') {
                    long dv = 0;
                    if (!f.dftval.empty()) { try { dv = std::stol(f.dftval); } catch (...) {} }
                    out_ << "long " << f.rpgName() << " = " << dv << ";\n";
                } else {
                    double dv = 0.0;
                    if (!f.dftval.empty()) { try { dv = std::stod(f.dftval); } catch (...) {} }
                    out_ << "double " << f.rpgName() << " = " << dv << ";\n";
                }
            }
        }
        return;
    }
    if (node.usage != "DISK") {
        emitIndent();
        out_ << "// DCL-F " << node.name << " " << node.usage << "\n";
        return;
    }

    // Register for opcode lookup
    file_defs_[node.name] = &node;

    // Program-described (I-spec/O-spec) file — mutually exclusive with the
    // externally-described/RLA path below (see TODO.md item #4).
    auto finIt = flat_input_formats_.find(node.name);
    auto foutIt = flat_output_formats_.find(node.name);
    if (finIt != flat_input_formats_.end() || foutIt != flat_output_formats_.end()) {
        emitIndent();
        out_ << "// --- File " << node.name << " (program-described) ---\n";

        // Union of fields across every I-spec record format for this
        // file, first-declared-wins on name collisions across formats.
        std::vector<std::string> fieldOrder;
        std::map<std::string, RPGType> fieldTypes;
        std::map<std::string, int> fieldDecimals;
        std::map<std::string, int> fieldLengths;
        int recLen = node.recordLen;
        if (finIt != flat_input_formats_.end()) {
            for (auto* rf : finIt->second) {
                for (auto& f : rf->fields) {
                    if (!fieldTypes.count(f.name)) {
                        fieldTypes[f.name] = f.type;
                        fieldDecimals[f.name] = f.decimals;
                        fieldLengths[f.name] = f.toPos - f.fromPos + 1;
                        fieldOrder.push_back(f.name);
                    }
                    if (f.toPos > recLen) recLen = f.toPos;
                }
            }
        }
        if (recLen < 1) recLen = 1;
        flat_record_len_[node.name] = recLen;

        for (auto& fname : fieldOrder) {
            RPGType t = fieldTypes[fname];
            var_types_[fname] = t;
            var_decimals_[fname] = fieldDecimals[fname];
            var_lengths_[fname] = fieldLengths[fname];
            std::string cpptype = typeToString(t);
            emitIndent();
            if (cpptype == "std::string") {
                out_ << cpptype << " " << fname << ";\n";
            } else if (cpptype == "bool") {
                out_ << cpptype << " " << fname << " = false;\n";
            } else if (cpptype == "void*") {
                out_ << cpptype << " " << fname << " = nullptr;\n";
            } else {
                out_ << cpptype << " " << fname << " = 0;\n";
            }
        }

        std::string lowerName = node.name;
        for (auto& c : lowerName) c = (char)tolower((unsigned char)c);

        emitIndent(); out_ << "RpgFlatFile " << node.name << "_ff;\n";
        emitIndent(); out_ << "bool " << node.name << "_eof   = false;\n";
        emitIndent(); out_ << "bool " << node.name << "_found = false;\n";
        emitIndent();
        out_ << "bool " << node.name << "_open = " << node.name << "_ff.open(\""
             << lowerName << ".txt\", " << recLen << ");\n";
        return;
    }

    auto it = ext_file_descs_.find(node.name);
    if (it == ext_file_descs_.end()) {
        emitIndent();
        out_ << "// DCL-F " << node.name << " DISK — no schema found (add " << node.name << ".extdesc)\n";
        return;
    }
    const ExternalFileDesc& desc = it->second;

    // Emit per-file state variables
    emitIndent();
    out_ << "// --- File " << node.name << " (table: " << desc.tableName << ") ---\n";

    // Per-field variables (act as the "record buffer")
    for (auto& f : desc.fields) {
        emitIndent();
        std::string fvar = node.prefix.empty() ? f.name : node.prefix + f.name;
        if (f.cppType == "std::string") {
            out_ << "std::string " << fvar << ";\n";
        } else if (f.cppType == "long") {
            out_ << "long " << fvar << " = 0;\n";
        } else {
            out_ << "double " << fvar << " = 0.0;\n";
        }
    }

    // Per-file flags and handles
    emitIndent(); out_ << "bool " << node.name << "_eof   = false;\n";
    emitIndent(); out_ << "bool " << node.name << "_found = false;\n";
    emitIndent(); out_ << "SQLHSTMT " << node.name << "_scroll = SQL_NULL_HSTMT;\n";
    emitIndent(); out_ << "SQLHSTMT " << node.name << "_chain  = SQL_NULL_HSTMT;\n";
    emitIndent(); out_ << "SQLHSTMT " << node.name << "_ins    = SQL_NULL_HSTMT;\n";
    emitIndent(); out_ << "SQLHSTMT " << node.name << "_upd    = SQL_NULL_HSTMT;\n";
    emitIndent(); out_ << "SQLHSTMT " << node.name << "_del    = SQL_NULL_HSTMT;\n";
    emitIndent(); out_ << "bool " << node.name << "_open  = false;\n";
}

// IRecordFormat/ORecordFormat are purely declarative (like DclDS) — their
// data is consumed via flat_input_formats_/flat_output_formats_ (built in
// the visit(Program&) pre-pass) by visit(DclF&) and the ReadStmt/WriteStmt/
// UpdateStmt program-described branches, not emitted at their own position
// in the statement stream.
void CodeGen::visit(IRecordFormat&) {}
void CodeGen::visit(ORecordFormat&) {}

void CodeGen::visit(DclC& node) {
    emitIndent();
    // Determine type from value expression
    if (dynamic_cast<StringLiteral*>(node.value.get())) {
        out_ << "const std::string " << node.name << " = " << emitExpr(*node.value) << ";\n";
    } else if (dynamic_cast<FloatLiteral*>(node.value.get())) {
        out_ << "constexpr double " << node.name << " = " << emitExpr(*node.value) << ";\n";
    } else {
        out_ << "constexpr int " << node.name << " = " << emitExpr(*node.value) << ";\n";
    }
}

void CodeGen::visit(DclS& node) {
    // Track variable info for RESET/CLEAR
    var_types_[node.name] = node.type;
    var_lengths_[node.name] = node.length;
    var_digits_[node.name] = node.digits;
    var_decimals_[node.name] = node.decimals;
    if (node.inz_value) has_inz_.insert(node.name);
    if (node.dim > 0) array_vars_.insert(node.name);
    if (!node.dtaara_name.empty()) dtaara_vars_[node.name] = node.dtaara_name;

    // TEMPLATE: skip emission (type definition only, no variable)
    if (node.is_template) return;

    // IMPORT: emit as extern declaration
    if (node.is_import) {
        emitIndent();
        out_ << "extern " << typeToString(node.type, node.length) << " " << node.name << ";\n";
        return;
    }

    // Handle LIKE - resolve type from referenced variable
    if (!node.like_var.empty()) {
        auto it = var_types_.find(node.like_var);
        if (it != var_types_.end()) {
            var_types_[node.name] = it->second;
            var_lengths_[node.name] = var_lengths_[node.like_var];
            emitIndent();
            std::string cppType = typeToString(it->second, var_lengths_[node.like_var]);
            if (node.is_static) out_ << "static ";
            out_ << cppType << " " << node.name;
            switch (it->second) {
                case RPGType::INT10: out_ << " = 0"; break;
                case RPGType::PACKED: case RPGType::ZONED: out_ << " = 0.0"; break;
                default: break;
            }
            out_ << ";\n";
            return;
        }
    }

    // Handle BASED(pointer) — reference via pointer
    if (!node.based_ptr.empty()) {
        emitIndent();
        out_ << typeToString(node.type, node.length) << "& " << node.name
             << " = *reinterpret_cast<" << typeToString(node.type, node.length)
             << "*>(" << node.based_ptr << ");\n";
        return;
    }

    emitIndent();
    // Emit static keyword if needed
    if (node.is_static) out_ << "static ";
    // Handle DIM arrays
    if (node.dim > 0) {
        if (node.dim_type == 1 || node.dim_type == 2) {
            // DIM(*VAR:max) or DIM(*AUTO:max) — use std::vector
            out_ << "std::vector<" << typeToString(node.type, node.length) << "> " << node.name << ";\n";
            // Reserve capacity for max elements
            emitIndent();
            out_ << node.name << ".reserve(" << node.dim << ");\n";
        } else {
            out_ << "std::array<" << typeToString(node.type, node.length) << ", " << node.dim << "> " << node.name << ";\n";
        }
        return;
    }
    switch (node.type) {
        case RPGType::CHAR:
            if (node.is_const) {
                out_ << "const std::string " << node.name << " = " << emitExpr(*node.inz_value) << ";\n";
            } else if (node.inz_value) {
                out_ << "std::string " << node.name << " = " << emitExpr(*node.inz_value) << ";\n";
            } else {
                out_ << "std::string " << node.name << "(" << node.length << ", ' ');\n";
            }
            break;
        case RPGType::VARCHAR:
            if (node.inz_value) {
                out_ << "std::string " << node.name << " = " << emitExpr(*node.inz_value) << ";\n";
            } else {
                out_ << "std::string " << node.name << ";\n";
            }
            break;
        case RPGType::INT10:
            if (node.is_const) {
                out_ << "const int " << node.name << " = " << emitExpr(*node.inz_value) << ";\n";
            } else if (node.inz_value) {
                out_ << "int " << node.name << " = " << emitExpr(*node.inz_value) << ";\n";
            } else {
                out_ << "int " << node.name << " = 0;\n";
            }
            break;
        case RPGType::PACKED:
        case RPGType::ZONED:
            if (node.is_const) {
                out_ << "const double " << node.name << " = " << emitExpr(*node.inz_value) << ";\n";
            } else if (node.inz_value) {
                out_ << "double " << node.name << " = " << emitExpr(*node.inz_value) << ";\n";
            } else {
                out_ << "double " << node.name << " = 0.0;\n";
            }
            break;
        case RPGType::IND:
            out_ << "bool " << node.name << " = false;\n";
            break;
        case RPGType::DATE:
            out_ << "RpgDate " << node.name << ";\n";
            break;
        case RPGType::TIME:
            out_ << "RpgTime " << node.name << ";\n";
            break;
        case RPGType::TIMESTAMP:
            out_ << "RpgTimestamp " << node.name << ";\n";
            break;
        case RPGType::POINTER:
            out_ << "void* " << node.name << " = nullptr;\n";
            break;
        case RPGType::UNS:
            if (node.inz_value) {
                out_ << "unsigned int " << node.name << " = " << emitExpr(*node.inz_value) << ";\n";
            } else {
                out_ << "unsigned int " << node.name << " = 0;\n";
            }
            break;
        case RPGType::FLOAT4:
            if (node.inz_value) {
                out_ << "float " << node.name << " = " << emitExpr(*node.inz_value) << ";\n";
            } else {
                out_ << "float " << node.name << " = 0.0f;\n";
            }
            break;
        case RPGType::FLOAT8:
            if (node.inz_value) {
                out_ << "double " << node.name << " = " << emitExpr(*node.inz_value) << ";\n";
            } else {
                out_ << "double " << node.name << " = 0.0;\n";
            }
            break;
        case RPGType::BINDEC:
            if (node.inz_value) {
                out_ << "int " << node.name << " = " << emitExpr(*node.inz_value) << ";\n";
            } else {
                out_ << "int " << node.name << " = 0;\n";
            }
            break;
        case RPGType::UCS2:
            if (node.inz_value) {
                out_ << "std::string " << node.name << " = " << emitExpr(*node.inz_value) << ";\n";
            } else {
                out_ << "std::string " << node.name << ";\n";
            }
            break;
        case RPGType::OBJECT:
            out_ << "void* " << node.name << " = nullptr; // OBJECT(*JAVA:'" << node.java_class << "')\n";
            break;
    }
    // Emit shadow variable for RESET support if INZ was specified
    if (node.inz_value) {
        emitIndent();
        out_ << "const auto _init_" << node.name << " = " << node.name << ";\n";
    }
}

std::string CodeGen::figConstValue(const std::string& name, RPGType type, const std::string& var_name) {
    if (name == "RPG_BLANKS") {
        if (type == RPGType::CHAR) {
            auto it = var_lengths_.find(var_name);
            if (it != var_lengths_.end() && it->second > 0)
                return "std::string(" + std::to_string(it->second) + ", ' ')";
            return "\"\"";
        }
        if (type == RPGType::VARCHAR) return "\"\"";
        return "0";
    } else if (name == "RPG_ZEROS") {
        if (type == RPGType::CHAR || type == RPGType::VARCHAR) return "\"\"";
        if (type == RPGType::PACKED || type == RPGType::ZONED) return "0.0";
        return "0";
    } else if (name == "RPG_USER") {
        uses_psds_ = true;
        return "rpg_psds_field_str(91)";
    } else if (name == "RPG_HIVAL") {
        if (type == RPGType::INT10) return "INT_MAX";
        if (type == RPGType::PACKED || type == RPGType::ZONED) return "DBL_MAX";
        return "std::string(9999, '\\xFF')";
    } else if (name == "RPG_LOVAL") {
        if (type == RPGType::INT10) return "INT_MIN";
        if (type == RPGType::PACKED || type == RPGType::ZONED) return "-DBL_MAX";
        return "\"\"";
    }
    return "";
}

void CodeGen::visit(EvalStmt& node) {
    // Check for %ELEM(array) = n (resize varying array)
    auto* lhs_bif = dynamic_cast<BIFCall*>(node.target.get());
    if (lhs_bif && lhs_bif->name == "ELEM" && !lhs_bif->args.empty()) {
        emitIndent();
        std::string arr = emitExpr(*lhs_bif->args[0]);
        std::string val = emitExpr(*node.value);
        // Check second arg: *ALLOC → reserve, *KEEP → resize (keep capacity), default → resize
        bool is_alloc = false;
        if (lhs_bif->args.size() >= 2) {
            auto* second = dynamic_cast<rpg::Identifier*>(lhs_bif->args[1].get());
            is_alloc = second && second->name == "__ALLOC";
            // *KEEP: resize without shrink — C++ .resize() already preserves capacity, same as default
        }
        if (is_alloc)
            out_ << arr << ".reserve(" << val << ");";
        else
            out_ << arr << ".resize(" << val << ");";
        if (node.line > 0) out_ << " // line " << node.line;
        out_ << "\n";
        return;
    }

    emitIndent();
    std::string target_str = emitExpr(*node.target);

    // Check for *ALL'x' on RHS
    auto* rhs_bif = dynamic_cast<BIFCall*>(node.value.get());
    if (rhs_bif && rhs_bif->name == "ALL" && !rhs_bif->args.empty()) {
        auto* tgt_id = dynamic_cast<Identifier*>(node.target.get());
        int len = 50; // default
        if (tgt_id && var_lengths_.count(tgt_id->name)) {
            len = var_lengths_[tgt_id->name];
        }
        auto* sl = dynamic_cast<StringLiteral*>(rhs_bif->args[0].get());
        if (sl) {
            out_ << target_str << " = rpg_all(\"" << sl->value << "\", " << len << ");";
        } else {
            out_ << target_str << " = rpg_all(" << emitExpr(*rhs_bif->args[0]) << ", " << len << ");";
        }
        if (node.line > 0) out_ << " // line " << node.line;
        out_ << "\n";
        return;
    }

    // Check for figurative constant on RHS
    auto* rhs_id = dynamic_cast<Identifier*>(node.value.get());
    if (rhs_id) {
        std::string var_name;
        RPGType ttype = RPGType::INT10;
        auto* tgt_id = dynamic_cast<Identifier*>(node.target.get());
        if (tgt_id && var_types_.count(tgt_id->name)) {
            ttype = var_types_[tgt_id->name];
            var_name = tgt_id->name;
        }
        std::string fc = figConstValue(rhs_id->name, ttype, var_name);
        if (!fc.empty()) {
            out_ << target_str << " = " << fc << ";";
            if (node.line > 0) out_ << " // line " << node.line;
            out_ << "\n";
            return;
        }
    }

    bool half_adj = node.extenders.find('H') != std::string::npos
                 || node.extenders.find('R') != std::string::npos;
    bool error_ext = node.extenders.find('E') != std::string::npos;

    std::string rhs = emitExpr(*node.value);
    if (half_adj) {
        // Check if target is a numeric type so we apply rounding
        auto* tgt_id = dynamic_cast<rpg::Identifier*>(node.target.get());
        bool is_numeric = false;
        if (tgt_id && var_types_.count(tgt_id->name)) {
            auto t = var_types_[tgt_id->name];
            is_numeric = (t == RPGType::INT10 || t == RPGType::PACKED ||
                          t == RPGType::ZONED  || t == RPGType::FLOAT4 ||
                          t == RPGType::FLOAT8 || t == RPGType::UNS    ||
                          t == RPGType::BINDEC);
        }
        if (is_numeric) {
            rhs = "static_cast<decltype(" + target_str + ")>(std::round(static_cast<double>(" + rhs + ")))";
        }
    }

    if (error_ext) {
        out_ << "rpg_error_flag() = false; rpg_status_code() = 0;\n";
        emitIndent();
        out_ << "try { " << target_str << " = " << rhs << "; }";
        out_ << " catch (...) { rpg_error_flag() = true; rpg_status_code() = 202; }";
    } else {
        out_ << target_str << " = " << rhs << ";";
    }
    if (node.line > 0) out_ << " // line " << node.line;
    out_ << "\n";
}

void CodeGen::visit(DsplyStmt& node) {
    emitIndent();
    out_ << "std::cout << " << emitExpr(*node.expr) << " << std::endl;\n";
}

void CodeGen::visit(ReturnStmt& node) {
    emitIndent();
    if (node.has_expr) {
        out_ << "return " << emitExpr(*node.expr) << ";\n";
    } else {
        out_ << "return " << node.code << ";\n";
    }
}

void CodeGen::visit(IfStmt& node) {
    emitIndent();
    out_ << "if (" << stripOuterParens(emitExpr(*node.condition)) << ") {\n";
    indent_++;
    emitStatements(node.then_body);
    indent_--;
    for (auto& branch : node.elseif_branches) {
        emitIndent();
        out_ << "} else if (" << stripOuterParens(emitExpr(*branch.condition)) << ") {\n";
        indent_++;
        emitStatements(branch.body);
        indent_--;
    }
    if (!node.else_body.empty()) {
        emitIndent();
        out_ << "} else {\n";
        indent_++;
        emitStatements(node.else_body);
        indent_--;
    }
    emitIndent();
    out_ << "}\n";
}

void CodeGen::visit(DowStmt& node) {
    emitIndent();
    out_ << "while (" << stripOuterParens(emitExpr(*node.condition)) << ") {\n";
    indent_++;
    emitStatements(node.body);
    indent_--;
    emitIndent();
    out_ << "}\n";
}

void CodeGen::visit(DouStmt& node) {
    emitIndent();
    out_ << "do {\n";
    indent_++;
    emitStatements(node.body);
    indent_--;
    emitIndent();
    out_ << "} while (!(" << stripOuterParens(emitExpr(*node.condition)) << "));\n";
}

void CodeGen::visit(ForStmt& node) {
    emitIndent();
    std::string var = node.var;
    std::string start_val = emitExpr(*node.start);
    std::string end_val = emitExpr(*node.end);
    std::string by_val = node.by ? emitExpr(*node.by) : "1";

    if (node.downto) {
        out_ << "for (" << var << " = " << start_val << "; "
             << var << " >= " << end_val << "; "
             << var << " -= " << by_val << ") {\n";
    } else {
        out_ << "for (" << var << " = " << start_val << "; "
             << var << " <= " << end_val << "; "
             << var << " += " << by_val << ") {\n";
    }
    indent_++;
    emitStatements(node.body);
    indent_--;
    emitIndent();
    out_ << "}\n";
}

void CodeGen::visit(SelectStmt& node) {
    for (size_t i = 0; i < node.when_branches.size(); i++) {
        emitIndent();
        if (i == 0) {
            out_ << "if (" << stripOuterParens(emitExpr(*node.when_branches[i].condition)) << ") {\n";
        } else {
            out_ << "} else if (" << stripOuterParens(emitExpr(*node.when_branches[i].condition)) << ") {\n";
        }
        indent_++;
        emitStatements(node.when_branches[i].body);
        indent_--;
    }
    if (!node.other_body.empty()) {
        emitIndent();
        out_ << "} else {\n";
        indent_++;
        emitStatements(node.other_body);
        indent_--;
    }
    emitIndent();
    out_ << "}\n";
}

void CodeGen::visit(IterStmt&) {
    emitIndent();
    out_ << "continue;\n";
}

void CodeGen::visit(LeaveStmt&) {
    emitIndent();
    out_ << "break;\n";
}

std::string CodeGen::fieldTypeDefault(RPGType type, int length) {
    switch (type) {
        case RPGType::INT10: return "0";
        case RPGType::CHAR: return "std::string(" + std::to_string(length) + ", ' ')";
        case RPGType::VARCHAR: return "\"\"";
        case RPGType::PACKED:
        case RPGType::ZONED: return "0.0";
        case RPGType::IND: return "false";
        case RPGType::DATE: return "RpgDate{}";
        case RPGType::TIME: return "RpgTime{}";
        case RPGType::TIMESTAMP: return "RpgTimestamp{}";
        case RPGType::POINTER: return "nullptr";
        case RPGType::UNS: return "0u";
        case RPGType::FLOAT4: return "0.0f";
        case RPGType::FLOAT8: return "0.0";
        case RPGType::BINDEC: return "0";
        case RPGType::UCS2: return "\"\"";
        case RPGType::OBJECT: return "nullptr";
    }
    return "0";
}

void CodeGen::visit(DclDS& node) {
    // Store for LIKEDS lookup
    ds_defs_[node.name] = &node;
    if (node.dim > 0) array_vars_.insert(node.name);

    if (!node.like_ds.empty()) {
        // LIKEDS: no struct to emit, just store reference
        return;
    }

    if (!node.extname.empty()) {
        // EXTNAME: externally described DS (stub)
        out_ << "struct " << node.name << "_t { /* EXTNAME(" << node.extname << ") - fields from file */ };\n";
        return;
    }

    // Apply PREFIX to field names
    if (!node.prefix.empty()) {
        for (auto& f : node.fields) {
            if (node.prefix_nbr > 0 && static_cast<int>(f.name.size()) > node.prefix_nbr) {
                f.name = node.prefix + f.name.substr(node.prefix_nbr);
            } else {
                f.name = node.prefix + f.name;
            }
        }
    }

    // Collect overlay fields (fields that overlay other fields)
    std::set<std::string> overlay_fields;
    for (auto& f : node.fields) {
        if (!f.overlay_field.empty()) {
            overlay_fields.insert(f.name);
        }
    }

    // Emit struct definition at file scope
    out_ << "struct " << node.name << "_t {\n";
    // Per-subfield LIKE(other) resolves against fields already declared
    // earlier in this same DS — the reliable, tested case. The var_types_/
    // var_lengths_ fallback (an outer standalone field) only helps when
    // that field's own DclS has already been visited by this point; at
    // top/main-line scope it usually hasn't, since visit(Program) emits
    // *every* DS struct definition before *any* standalone field (DS
    // structs are needed for procedure params — see visit(Program)'s
    // ds_stmts pass), regardless of the two statements' textual order.
    // Inside a DCL-PROC body, where declarations emit in textual order,
    // the fallback does apply. Unresolved LIKE falls back to the field's
    // own placeholder type, same as top-level DclS's LIKE handling above.
    std::map<std::string, std::pair<RPGType, int>> ds_local_types;
    for (auto& f : node.fields) {
        if (!f.overlay_field.empty()) {
            out_ << "    " << typeToString(f.type, f.length) << " " << f.name;
            if (f.type == RPGType::INT10) out_ << " = 0";
            else if (f.type == RPGType::PACKED || f.type == RPGType::ZONED) out_ << " = 0.0";
            out_ << "; // OVERLAY(" << f.overlay_field;
            if (f.overlay_pos > 0) out_ << ":" << f.overlay_pos;
            out_ << ")\n";
            ds_local_types[f.name] = {f.type, f.length};
        } else if (!f.likeds.empty()) {
            // LIKEDS subfield: emit nested struct type
            out_ << "    " << f.likeds << "_t " << f.name << ";\n";
        } else if (!f.like_var.empty()) {
            // Per-subfield LIKE(other): resolve type/length from an earlier
            // subfield in this DS, else an outer standalone field.
            RPGType rtype = f.type;
            int rlen = f.length;
            auto lit = ds_local_types.find(f.like_var);
            if (lit != ds_local_types.end()) {
                rtype = lit->second.first;
                rlen = lit->second.second;
            } else {
                auto git = var_types_.find(f.like_var);
                if (git != var_types_.end()) {
                    rtype = git->second;
                    rlen = var_lengths_[f.like_var];
                }
            }
            out_ << "    " << typeToString(rtype, rlen) << " " << f.name;
            if (rtype == RPGType::INT10) out_ << " = 0";
            else if (rtype == RPGType::PACKED || rtype == RPGType::ZONED) out_ << " = 0.0";
            out_ << "; // LIKE(" << f.like_var << ")\n";
            ds_local_types[f.name] = {rtype, rlen};
        } else if (f.dim > 0) {
            // Per-subfield DIM(n): the subfield itself is an array within the DS.
            out_ << "    std::array<" << typeToString(f.type, f.length) << ", " << f.dim
                 << "> " << f.name << "; // DIM(" << f.dim << ")\n";
            ds_local_types[f.name] = {f.type, f.length};
        } else if (f.pos > 0) {
            // POS field: emit with comment showing position
            out_ << "    " << typeToString(f.type, f.length) << " " << f.name;
            if (f.type == RPGType::INT10) out_ << " = 0";
            else if (f.type == RPGType::PACKED || f.type == RPGType::ZONED) out_ << " = 0.0";
            out_ << "; // POS(" << f.pos << ")\n";
            ds_local_types[f.name] = {f.type, f.length};
        } else {
            out_ << "    " << typeToString(f.type, f.length) << " " << f.name;
            if (f.type == RPGType::INT10) out_ << " = 0";
            else if (f.type == RPGType::PACKED || f.type == RPGType::ZONED) out_ << " = 0.0";
            out_ << ";\n";
            ds_local_types[f.name] = {f.type, f.length};
        }
    }
    out_ << "};\n";
}

void CodeGen::visit(DclEnum& node) {
    // For QUALIFIED enums, we need RPG's dot-access (COLORS.RED) to work.
    // C++ enum class uses ::, so we register as a "DS-like" to make DotExpr
    // emit the right field access. We use a simple struct with non-static members
    // and create an instance.
    if (node.qualified) {
        // Emit a local struct + instance to support dot-qualified access
        emitIndent();
        out_ << "struct " << node.name << "_t {\n";
        indent_++;
        int auto_val = 0;
        for (size_t i = 0; i < node.constants.size(); i++) {
            emitIndent();
            out_ << "const int " << node.constants[i].name << " = ";
            if (node.constants[i].value) {
                out_ << emitExpr(*node.constants[i].value);
            } else {
                out_ << auto_val;
            }
            out_ << ";\n";
            auto_val++;
        }
        indent_--;
        emitIndent();
        out_ << "};\n";
        emitIndent();
        out_ << node.name << "_t " << node.name << ";\n";
    } else {
        // Non-qualified: emit as plain constants
        int auto_val = 0;
        for (size_t i = 0; i < node.constants.size(); i++) {
            emitIndent();
            out_ << "const int " << node.constants[i].name << " = ";
            if (node.constants[i].value) {
                out_ << emitExpr(*node.constants[i].value);
            } else {
                out_ << auto_val;
            }
            out_ << ";\n";
            auto_val++;
        }
    }
}

void CodeGen::visit(DotExpr& node) {
    // Check if object is a FuncCall — treat as array(idx).field
    auto* fc = dynamic_cast<FuncCall*>(node.object.get());
    if (fc && fc->args.size() == 1) {
        expr_ << fc->name << "[";
        fc->args[0]->accept(*this);
        expr_ << " - 1]." << node.field;
    } else {
        node.object->accept(*this);
        expr_ << "." << node.field;
    }
}

void CodeGen::visit(ArrayAccess& node) {
    expr_ << node.name << "[";
    node.index->accept(*this);
    expr_ << " - 1]";  // RPG arrays are 1-based
}

void CodeGen::visit(MonitorStmt& node) {
    emitIndent();
    out_ << "try {\n";
    indent_++;
    emitStatements(node.try_body);
    indent_--;
    emitIndent();
    out_ << "} catch (...) {\n";
    indent_++;
    if (uses_psds_) { emitIndent(); out_ << "rpg_psds_sync();\n"; }
    emitStatements(node.on_error_body);
    indent_--;
    emitIndent();
    out_ << "}\n";
}

static std::string sanitizeSRName(const std::string& name) {
    std::string result;
    for (char c : name) {
        result += (c == '*') ? '_' : c;
    }
    return result;
}

void CodeGen::visit(BegSR& node) {
    // Emit as a lambda that can be called by EXSR
    emitIndent();
    out_ << "auto sr_" << sanitizeSRName(node.name) << " = [&]() {\n";
    indent_++;
    emitStatements(node.body);
    indent_--;
    emitIndent();
    out_ << "};\n";
}

void CodeGen::visit(ExSR& node) {
    emitIndent();
    out_ << "sr_" << sanitizeSRName(node.name) << "();\n";
}

void CodeGen::visit(GotoStmt& node) {
    emitIndent();
    out_ << "goto rpg_label_" << node.label << ";\n";
}

void CodeGen::visit(TagStmt& node) {
    emitIndent();
    out_ << "rpg_label_" << node.label << ":;\n";
}

void CodeGen::visit(ResetStmt& node) {
    emitIndent();
    if (has_inz_.count(node.var_name)) {
        out_ << node.var_name << " = _init_" << node.var_name << ";\n";
    } else {
        // No INZ — reset to type default
        auto it = var_types_.find(node.var_name);
        if (it != var_types_.end()) {
            out_ << node.var_name << " = " << fieldTypeDefault(it->second, var_lengths_[node.var_name]) << ";\n";
        }
    }
}

void CodeGen::visit(ClearStmt& node) {
    emitIndent();
    auto it = var_types_.find(node.var_name);
    if (it != var_types_.end()) {
        switch (it->second) {
            case RPGType::INT10: out_ << node.var_name << " = 0;\n"; break;
            case RPGType::PACKED:
            case RPGType::ZONED: out_ << node.var_name << " = 0.0;\n"; break;
            case RPGType::CHAR:
            case RPGType::VARCHAR: out_ << node.var_name << " = \"\";\n"; break;
            case RPGType::IND: out_ << node.var_name << " = false;\n"; break;
            case RPGType::DATE: out_ << node.var_name << " = RpgDate{};\n"; break;
            case RPGType::TIME: out_ << node.var_name << " = RpgTime{};\n"; break;
            case RPGType::TIMESTAMP: out_ << node.var_name << " = RpgTimestamp{};\n"; break;
            case RPGType::POINTER: out_ << node.var_name << " = nullptr;\n"; break;
        }
    }
}

void CodeGen::visit(DumpStmt& node) {
    (void)node;
    emitIndent();
    out_ << "{\n";
    indent_++;
    emitIndent();
    out_ << "std::cout << \"** DUMP **\\n\";\n";
    for (auto& [vname, vtype] : var_types_) {
        if (array_vars_.count(vname)) continue;
        emitIndent();
        switch (vtype) {
            case RPGType::CHAR:
            case RPGType::VARCHAR:
            case RPGType::UCS2:
                out_ << "std::cout << \"   " << vname << " = '\" << " << vname << " << \"'\\n\";\n";
                break;
            case RPGType::DATE:
                out_ << "std::cout << \"   " << vname << " = '\" << " << vname << ".value << \"'\\n\";\n";
                break;
            case RPGType::TIME:
                out_ << "std::cout << \"   " << vname << " = '\" << " << vname << ".value << \"'\\n\";\n";
                break;
            case RPGType::TIMESTAMP:
                out_ << "std::cout << \"   " << vname << " = '\" << " << vname << ".value << \"'\\n\";\n";
                break;
            case RPGType::IND:
                out_ << "std::cout << \"   " << vname << " = '\" << (" << vname << " ? '1' : '0') << \"'\\n\";\n";
                break;
            case RPGType::PACKED:
            case RPGType::ZONED: {
                int dec = var_decimals_.count(vname) ? var_decimals_.at(vname) : 0;
                out_ << "{ auto __df = std::cout.flags(); auto __dp = std::cout.precision();\n";
                emitIndent();
                out_ << "  std::cout << \"   " << vname << " = \" << std::fixed << std::setprecision(" << dec << ") << " << vname << " << \"\\n\";\n";
                emitIndent();
                out_ << "  std::cout.flags(__df); std::cout.precision(__dp); }\n";
                break;
            }
            case RPGType::POINTER:
            case RPGType::OBJECT:
                out_ << "std::cout << \"   " << vname << " = \" << static_cast<void*>(" << vname << ") << \"\\n\";\n";
                break;
            default:
                out_ << "std::cout << \"   " << vname << " = \" << " << vname << " << \"\\n\";\n";
                break;
        }
    }
    indent_--;
    emitIndent();
    out_ << "}\n";
}

void CodeGen::visit(IndicatorExpr& node) {
    uses_indicators_ = true;
    expr_ << "rpg_indicators[" << node.number << "]";
}

void CodeGen::visit(Identifier& node) {
    // *USER figurative constant
    if (node.name == "RPG_USER") {
        uses_psds_ = true;
        expr_ << "rpg_psds_field_str(91)";
        return;
    }

    // Map SQL diagnostic variables
    if (uses_sql_) {
        if (node.name == "SQLCOD" || node.name == "SQLCODE") {
            expr_ << "__sql_env.sqlcode";
            return;
        }
        if (node.name == "SQLSTT" || node.name == "SQLSTATE") {
            expr_ << "__sql_env.sqlstate";
            return;
        }
    }

    // Check if this identifier is an *OMIT parameter (pointer type) — dereference it
    if (!current_proc_name_.empty()) {
        auto pit = nopass_proc_params_.find(current_proc_name_);
        if (pit != nopass_proc_params_.end()) {
            for (auto& p : pit->second) {
                if (p.name == node.name && p.omit) {
                    expr_ << "(*" << node.name << ")";
                    return;
                }
            }
        }
    }
    expr_ << node.name;
}

void CodeGen::visit(IntLiteral& node) {
    expr_ << node.value;
}

void CodeGen::visit(FloatLiteral& node) {
    // Use enough precision to preserve the literal value
    std::ostringstream tmp;
    tmp << std::fixed << std::setprecision(10) << node.value;
    std::string s = tmp.str();
    // Trim trailing zeros but keep at least one decimal
    auto dot = s.find('.');
    if (dot != std::string::npos) {
        auto last = s.find_last_not_of('0');
        if (last == dot) last++; // keep at least one digit after dot
        s = s.substr(0, last + 1);
    }
    expr_ << s;
}

void CodeGen::visit(StringLiteral& node) {
    expr_ << "std::string(\"";
    for (unsigned char c : node.value) {
        if (c == '"')       expr_ << "\\\"";
        else if (c == '\\') expr_ << "\\\\";
        else if (c == '\n') expr_ << "\\n";
        else if (c == '\r') expr_ << "\\r";
        else if (c == '\t') expr_ << "\\t";
        else if (c < 0x20 || c == 0x7f)
            expr_ << "\\x" << std::hex << std::setw(2) << std::setfill('0')
                  << static_cast<int>(c) << std::dec;
        else                expr_ << static_cast<char>(c);
    }
    expr_ << "\")";
}

void CodeGen::visit(BinaryExpr& node) {
    if (node.op == BinOp::POWER) {
        expr_ << "std::pow(";
        node.left->accept(*this);
        expr_ << ", ";
        node.right->accept(*this);
        expr_ << ")";
        return;
    }
    expr_ << "(";
    node.left->accept(*this);
    switch (node.op) {
        case BinOp::ADD: expr_ << " + "; break;
        case BinOp::SUB: expr_ << " - "; break;
        case BinOp::MUL: expr_ << " * "; break;
        case BinOp::DIV: expr_ << " / "; break;
        case BinOp::EQ:  expr_ << " == "; break;
        case BinOp::NE:  expr_ << " != "; break;
        case BinOp::LT:  expr_ << " < "; break;
        case BinOp::GT:  expr_ << " > "; break;
        case BinOp::LE:  expr_ << " <= "; break;
        case BinOp::GE:  expr_ << " >= "; break;
        case BinOp::AND: expr_ << " && "; break;
        case BinOp::OR:  expr_ << " || "; break;
        case BinOp::POWER: break; // handled above
    }
    node.right->accept(*this);
    expr_ << ")";
}

void CodeGen::visit(NotExpr& node) {
    expr_ << "!(";
    node.operand->accept(*this);
    expr_ << ")";
}

void CodeGen::visit(FuncCall& node) {
    // Check if this is actually an array access
    if (array_vars_.count(node.name) && node.args.size() == 1) {
        expr_ << node.name << "[";
        node.args[0]->accept(*this);
        expr_ << " - 1]";
        return;
    }
    // Resolve EXTPROC/EXTPGM name mapping
    std::string callName = node.name;
    auto eit = extproc_map_.find(node.name);
    if (eit != extproc_map_.end()) callName = eit->second;
    expr_ << callName << "(";
    for (size_t i = 0; i < node.args.size(); i++) {
        if (i > 0) expr_ << ", ";
        node.args[i]->accept(*this);
    }
    // If this function has NOPASS params, fill defaults for skipped params and append parm count
    if (nopass_procs_.count(node.name)) {
        auto it = nopass_proc_params_.find(node.name);
        if (it != nopass_proc_params_.end()) {
            for (size_t i = node.args.size(); i < it->second.size(); i++) {
                expr_ << ", " << paramTypeDefault(it->second[i]);
            }
        }
        expr_ << ", " << node.args.size();
    }
    expr_ << ")";
}

void CodeGen::visit(BIFCall& node) {
    if (node.name == "CHAR") {
        // Check if arg is a date/time variable and DATFMT/TIMFMT is set
        auto* arg_id = dynamic_cast<Identifier*>(node.args[0].get());
        bool is_date_var = false, is_time_var = false;
        if (arg_id) {
            auto vit = var_types_.find(arg_id->name);
            if (vit != var_types_.end()) {
                if (vit->second == RPGType::DATE) is_date_var = true;
                if (vit->second == RPGType::TIME) is_time_var = true;
            }
        }
        if (is_date_var && !datfmt_.empty()) {
            expr_ << "rpg_to_char(";
            node.args[0]->accept(*this);
            expr_ << ", RPG_DATFMT)";
        } else if (is_time_var && !timfmt_.empty()) {
            expr_ << "rpg_to_char(";
            node.args[0]->accept(*this);
            expr_ << ", RPG_TIMFMT)";
        } else {
            // For PACKED/ZONED variables, emit the scale so formatting matches
            // the RPG declaration (e.g. PACKED(9:2) → "91000.00", not "91000.000000")
            bool is_packed = false;
            int dec_places = 0;
            if (arg_id) {
                auto vit = var_types_.find(arg_id->name);
                auto dit = var_decimals_.find(arg_id->name);
                if (vit != var_types_.end() && dit != var_decimals_.end() &&
                    (vit->second == RPGType::PACKED || vit->second == RPGType::ZONED)) {
                    is_packed = true;
                    dec_places = dit->second;
                }
            }
            if (is_packed) {
                expr_ << "rpg_to_char_packed(";
                node.args[0]->accept(*this);
                expr_ << ", " << dec_places << ")";
            } else {
                expr_ << "rpg_to_char(";
                node.args[0]->accept(*this);
                expr_ << ")";
            }
        }
    } else if (node.name == "TRIM") {
        expr_ << "rpg_trim(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "TRIML") {
        expr_ << "rpg_triml(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "TRIMR") {
        expr_ << "rpg_trimr(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "LEN") {
        expr_ << "static_cast<int>(";
        node.args[0]->accept(*this);
        expr_ << ".size())";
    } else if (node.name == "SUBST") {
        node.args[0]->accept(*this);
        expr_ << ".substr(";
        node.args[1]->accept(*this);
        expr_ << " - 1";
        if (node.args.size() > 2) {
            expr_ << ", ";
            node.args[2]->accept(*this);
        }
        expr_ << ")";
    } else if (node.name == "SCAN") {
        // %SCAN(needle : haystack) → returns 1-based position
        expr_ << "rpg_scan(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        if (node.args.size() > 2) {
            expr_ << ", ";
            node.args[2]->accept(*this);
        }
        expr_ << ")";
    } else if (node.name == "SCANRPL") {
        // %SCANRPL(find : replace : string)
        expr_ << "rpg_scanrpl(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        expr_ << ", ";
        node.args[2]->accept(*this);
        expr_ << ")";
    } else if (node.name == "XLATE") {
        // %XLATE(from : to : string)
        expr_ << "rpg_xlate(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        expr_ << ", ";
        node.args[2]->accept(*this);
        expr_ << ")";
    } else if (node.name == "DEC") {
        // %DEC(expr) → convert to double
        expr_ << "static_cast<double>(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "INT") {
        // %INT(expr) → convert to int
        expr_ << "static_cast<int>(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "ELEM") {
        // %ELEM(array) → size; %ELEM(array:*ALLOC) → capacity
        bool is_alloc = node.args.size() >= 2 &&
            [&]{ auto* id = dynamic_cast<rpg::Identifier*>(node.args[1].get());
                 return id && id->name == "__ALLOC"; }();
        expr_ << "static_cast<int>(";
        node.args[0]->accept(*this);
        expr_ << (is_alloc ? ".capacity())" : ".size())");
    } else if (node.name == "MAX") {
        if (node.args.size() == 2) {
            expr_ << "std::max(";
            node.args[0]->accept(*this);
            expr_ << ", ";
            node.args[1]->accept(*this);
            expr_ << ")";
        } else {
            expr_ << "std::max({";
            for (size_t i = 0; i < node.args.size(); i++) {
                if (i > 0) expr_ << ", ";
                node.args[i]->accept(*this);
            }
            expr_ << "})";
        }
    } else if (node.name == "MIN") {
        if (node.args.size() == 2) {
            expr_ << "std::min(";
            node.args[0]->accept(*this);
            expr_ << ", ";
            node.args[1]->accept(*this);
            expr_ << ")";
        } else {
            expr_ << "std::min({";
            for (size_t i = 0; i < node.args.size(); i++) {
                if (i > 0) expr_ << ", ";
                node.args[i]->accept(*this);
            }
            expr_ << "})";
        }
    } else if (node.name == "STATUS") {
        expr_ << "rpg_status()";
    } else if (node.name == "ERROR") {
        expr_ << "rpg_error()";
    } else if (node.name == "PARMS") {
        if (has_nopass_params_) {
            expr_ << "_rpg_parms";
        } else {
            expr_ << current_proc_parm_count_;
        }
    } else if (node.name == "SIZE") {
        // Return RPG-declared size, not C++ sizeof (which varies by platform/stdlib).
        // CHAR(N)/VARCHAR(N) → N bytes; PACKED(N:D) → ceil((N+1)/2); others → sizeof.
        auto* id = dynamic_cast<Identifier*>(node.args[0].get());
        bool emitted = false;
        if (id) {
            auto tit = var_types_.find(id->name);
            auto lit = var_lengths_.find(id->name);
            if (tit != var_types_.end() && lit != var_lengths_.end()) {
                if (tit->second == RPGType::CHAR || tit->second == RPGType::VARCHAR ||
                    tit->second == RPGType::UCS2) {
                    expr_ << lit->second;
                    emitted = true;
                } else if (tit->second == RPGType::PACKED || tit->second == RPGType::ZONED) {
                    auto dit = var_digits_.find(id->name);
                    int digits = (dit != var_digits_.end()) ? dit->second : lit->second;
                    expr_ << ((digits + 1) / 2);
                    emitted = true;
                }
            }
        }
        if (!emitted) {
            expr_ << "static_cast<int>(sizeof(";
            node.args[0]->accept(*this);
            expr_ << "))";
        }
    } else if (node.name == "ADDR") {
        expr_ << "static_cast<void*>(&";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "ABS") {
        expr_ << "std::abs(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "DIV") {
        expr_ << "(";
        node.args[0]->accept(*this);
        expr_ << " / ";
        node.args[1]->accept(*this);
        expr_ << ")";
    } else if (node.name == "REM") {
        expr_ << "(";
        node.args[0]->accept(*this);
        expr_ << " % ";
        node.args[1]->accept(*this);
        expr_ << ")";
    } else if (node.name == "DATE") {
        if (node.args.empty()) {
            expr_ << "rpg_current_date()";
        } else {
            expr_ << "rpg_make_date(";
            node.args[0]->accept(*this);
            expr_ << ")";
        }
    } else if (node.name == "TIME") {
        if (node.args.empty()) {
            expr_ << "rpg_current_time()";
        } else {
            expr_ << "rpg_make_time(";
            node.args[0]->accept(*this);
            expr_ << ")";
        }
    } else if (node.name == "TIMESTAMP") {
        if (node.args.empty()) {
            expr_ << "rpg_current_timestamp()";
        } else {
            expr_ << "rpg_make_timestamp(";
            node.args[0]->accept(*this);
            expr_ << ")";
        }
    } else if (node.name == "DIFF") {
        // args: date1, date2, unit_string
        auto unit = dynamic_cast<StringLiteral*>(node.args[2].get());
        std::string func = "rpg_diff_days";
        if (unit && unit->value == "MONTHS") func = "rpg_diff_months";
        else if (unit && unit->value == "YEARS") func = "rpg_diff_years";
        else if (unit && unit->value == "HOURS") func = "rpg_diff_hours";
        else if (unit && unit->value == "MINUTES") func = "rpg_diff_minutes";
        else if (unit && unit->value == "SECONDS") func = "rpg_diff_seconds";
        expr_ << func << "(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        expr_ << ")";
    } else if (node.name == "DAYS") {
        expr_ << "RpgDuration{";
        node.args[0]->accept(*this);
        expr_ << ", 'D'}";
    } else if (node.name == "MONTHS") {
        expr_ << "RpgDuration{";
        node.args[0]->accept(*this);
        expr_ << ", 'M'}";
    } else if (node.name == "YEARS") {
        expr_ << "RpgDuration{";
        node.args[0]->accept(*this);
        expr_ << ", 'Y'}";
    } else if (node.name == "LOWER") {
        expr_ << "rpg_lower(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "UPPER") {
        expr_ << "rpg_upper(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "SUBDT") {
        // %SUBDT(date : unit) — extract part
        auto unit = dynamic_cast<StringLiteral*>(node.args[1].get());
        std::string func = "rpg_subdt_days";
        if (unit && unit->value == "YEARS") func = "rpg_subdt_years";
        else if (unit && unit->value == "MONTHS") func = "rpg_subdt_months";
        else if (unit && unit->value == "HOURS") func = "rpg_subdt_hours";
        else if (unit && unit->value == "MINUTES") func = "rpg_subdt_minutes";
        else if (unit && unit->value == "SECONDS") func = "rpg_subdt_seconds";
        expr_ << func << "(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "FLOAT") {
        expr_ << "static_cast<double>(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "SQRT") {
        expr_ << "std::sqrt(static_cast<double>(";
        node.args[0]->accept(*this);
        expr_ << "))";
    } else if (node.name == "CHECK") {
        // %CHECK(comparator : base {: start})
        expr_ << "rpg_check(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        if (node.args.size() > 2) {
            expr_ << ", ";
            node.args[2]->accept(*this);
        }
        expr_ << ")";
    } else if (node.name == "CHECKR") {
        // %CHECKR(comparator : base {: start})
        expr_ << "rpg_checkr(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        if (node.args.size() > 2) {
            expr_ << ", ";
            node.args[2]->accept(*this);
        }
        expr_ << ")";
    } else if (node.name == "REPLACE") {
        // %REPLACE(new : source : start {: length})
        expr_ << "rpg_replace(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        expr_ << ", ";
        node.args[2]->accept(*this);
        if (node.args.size() > 3) {
            expr_ << ", ";
            node.args[3]->accept(*this);
        }
        expr_ << ")";
    } else if (node.name == "EDITC") {
        // %EDITC(number : editcode)
        expr_ << "rpg_editc(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        expr_ << ")";
    } else if (node.name == "EDITW") {
        // %EDITW(number : editword)
        expr_ << "rpg_editw(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        expr_ << ")";
    } else if (node.name == "LOOKUP") {
        // %LOOKUP(arg : array) → 1-based index, 0 if not found
        expr_ << "rpg_lookup(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        expr_ << ")";
    } else if (node.name == "ALLOC") {
        expr_ << "std::malloc(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "REALLOC") {
        expr_ << "std::realloc(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        expr_ << ")";
    } else if (node.name == "XFOOT") {
        expr_ << "rpg_xfoot(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "UNS") {
        expr_ << "static_cast<unsigned int>(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "INTH") {
        expr_ << "static_cast<int>(std::round(static_cast<double>(";
        node.args[0]->accept(*this);
        expr_ << ")))";
    } else if (node.name == "DECH") {
        // %DECH(expr:digits:decimals) — round to decimals then cast
        expr_ << "rpg_dech(";
        node.args[0]->accept(*this);
        if (node.args.size() > 2) {
            expr_ << ", ";
            node.args[2]->accept(*this);
        } else {
            expr_ << ", 0";
        }
        expr_ << ")";
    } else if (node.name == "DECPOS") {
        expr_ << "rpg_decpos(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "SPLIT") {
        expr_ << "rpg_split(";
        node.args[0]->accept(*this);
        if (node.args.size() > 1) {
            expr_ << ", ";
            node.args[1]->accept(*this);
        }
        expr_ << ")";
    } else if (node.name == "CONCAT") {
        // %CONCAT(separator : str1 : str2 : ...)
        // First arg is separator, rest are strings to join
        expr_ << "rpg_concat(";
        node.args[0]->accept(*this);
        for (size_t i = 1; i < node.args.size(); i++) {
            expr_ << ", ";
            node.args[i]->accept(*this);
        }
        expr_ << ")";
    } else if (node.name == "CONCATARR") {
        expr_ << "rpg_concatarr(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        expr_ << ")";
    } else if (node.name == "LEFT") {
        node.args[0]->accept(*this);
        expr_ << ".substr(0, ";
        node.args[1]->accept(*this);
        expr_ << ")";
    } else if (node.name == "RIGHT") {
        expr_ << "rpg_right(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        expr_ << ")";
    } else if (node.name == "STR") {
        expr_ << "rpg_str(";
        node.args[0]->accept(*this);
        if (node.args.size() > 1) {
            expr_ << ", ";
            node.args[1]->accept(*this);
        }
        expr_ << ")";
    } else if (node.name == "SUBARR") {
        expr_ << "rpg_subarr(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        if (node.args.size() > 2) {
            expr_ << ", ";
            node.args[2]->accept(*this);
        }
        expr_ << ")";
    } else if (node.name == "MAXARR") {
        expr_ << "rpg_maxarr(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "MINARR") {
        expr_ << "rpg_minarr(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "LIST") {
        // %LIST(v1:v2:...) → initializer list — emits as rpg_list(...)
        expr_ << "rpg_list(";
        for (size_t i = 0; i < node.args.size(); i++) {
            if (i > 0) expr_ << ", ";
            node.args[i]->accept(*this);
        }
        expr_ << ")";
    } else if (node.name == "RANGE") {
        expr_ << "rpg_range(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        expr_ << ")";
    } else if (node.name == "LOOKUPLT") {
        expr_ << "rpg_lookup_lt(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        expr_ << ")";
    } else if (node.name == "LOOKUPGE") {
        expr_ << "rpg_lookup_ge(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        expr_ << ")";
    } else if (node.name == "LOOKUPLE") {
        expr_ << "rpg_lookup_le(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        expr_ << ")";
    } else if (node.name == "LOOKUPGT") {
        expr_ << "rpg_lookup_gt(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        expr_ << ")";
    } else if (node.name == "TLOOKUP") {
        expr_ << "rpg_tlookup(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        if (node.args.size() > 2) {
            expr_ << ", ";
            node.args[2]->accept(*this);
        }
        expr_ << ")";
    } else if (node.name == "TLOOKUPLT") {
        expr_ << "rpg_tlookup_lt(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        if (node.args.size() > 2) {
            expr_ << ", ";
            node.args[2]->accept(*this);
        }
        expr_ << ")";
    } else if (node.name == "TLOOKUPGT") {
        expr_ << "rpg_tlookup_gt(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        if (node.args.size() > 2) {
            expr_ << ", ";
            node.args[2]->accept(*this);
        }
        expr_ << ")";
    } else if (node.name == "TLOOKUPLE") {
        expr_ << "rpg_tlookup_le(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        if (node.args.size() > 2) {
            expr_ << ", ";
            node.args[2]->accept(*this);
        }
        expr_ << ")";
    } else if (node.name == "TLOOKUPGE") {
        expr_ << "rpg_tlookup_ge(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        if (node.args.size() > 2) {
            expr_ << ", ";
            node.args[2]->accept(*this);
        }
        expr_ << ")";
    } else if (node.name == "HOURS") {
        expr_ << "RpgDuration{";
        node.args[0]->accept(*this);
        expr_ << ", 'H'}";
    } else if (node.name == "MINUTES") {
        expr_ << "RpgDuration{";
        node.args[0]->accept(*this);
        expr_ << ", 'I'}";
    } else if (node.name == "SECONDS") {
        expr_ << "RpgDuration{";
        node.args[0]->accept(*this);
        expr_ << ", 'S'}";
    } else if (node.name == "MSECONDS") {
        expr_ << "RpgDuration{";
        node.args[0]->accept(*this);
        expr_ << ", 'U'}";
    } else if (node.name == "PADDR") {
        auto* sl = dynamic_cast<StringLiteral*>(node.args[0].get());
        if (sl) {
            expr_ << "reinterpret_cast<void*>(&" << sl->value << ")";
        } else {
            expr_ << "reinterpret_cast<void*>(&";
            node.args[0]->accept(*this);
            expr_ << ")";
        }
    } else if (node.name == "PROC") {
        if (!current_proc_name_.empty()) {
            expr_ << "std::string(\"" << current_proc_name_ << "\")";
        } else {
            expr_ << "std::string(\"main\")";
        }
    } else if (node.name == "ALL") {
        // Will be resolved in EvalStmt context; for now emit rpg_all helper
        auto* sl = dynamic_cast<StringLiteral*>(node.args[0].get());
        if (sl) {
            expr_ << "rpg_all(\"" << sl->value << "\")";
        } else {
            expr_ << "rpg_all(";
            node.args[0]->accept(*this);
            expr_ << ")";
        }
    } else if (node.name == "PASSED") {
        // %PASSED(parmname) — check if optional param was passed
        auto* arg_id = dynamic_cast<Identifier*>(node.args[0].get());
        if (arg_id && !current_proc_name_.empty()) {
            auto pit = nopass_proc_params_.find(current_proc_name_);
            if (pit != nopass_proc_params_.end()) {
                // Check if param has *OMIT — use nullptr check
                for (size_t i = 0; i < pit->second.size(); i++) {
                    if (pit->second[i].name == arg_id->name) {
                        if (pit->second[i].omit) {
                            expr_ << "(" << arg_id->name << " != nullptr)";
                        } else {
                            expr_ << "(_rpg_parms >= " << (i + 1) << ")";
                        }
                        break;
                    }
                }
            } else {
                expr_ << "true";
            }
        } else {
            expr_ << "true";
        }
    } else if (node.name == "OMITTED") {
        // %OMITTED(parmname) — check if param was omitted
        auto* arg_id = dynamic_cast<Identifier*>(node.args[0].get());
        if (arg_id && !current_proc_name_.empty()) {
            auto pit = nopass_proc_params_.find(current_proc_name_);
            if (pit != nopass_proc_params_.end()) {
                for (size_t i = 0; i < pit->second.size(); i++) {
                    if (pit->second[i].name == arg_id->name) {
                        if (pit->second[i].omit) {
                            expr_ << "(" << arg_id->name << " == nullptr)";
                        } else {
                            expr_ << "(_rpg_parms < " << (i + 1) << ")";
                        }
                        break;
                    }
                }
            } else {
                expr_ << "false";
            }
        } else {
            expr_ << "false";
        }
    } else if (node.name == "FOUND") {
        if (!node.args.empty()) {
            auto* id = dynamic_cast<Identifier*>(node.args[0].get());
            if (id) expr_ << id->name << "_found";
            else expr_ << "rpg_found()";
        } else {
            expr_ << "rpg_found()";
        }
    } else if (node.name == "EOF") {
        if (!node.args.empty()) {
            auto* id = dynamic_cast<Identifier*>(node.args[0].get());
            if (id) expr_ << id->name << "_eof";
            else expr_ << "rpg_eof()";
        } else {
            expr_ << "rpg_eof()";
        }
    } else if (node.name == "BITAND") {
        expr_ << "(static_cast<unsigned int>(";
        node.args[0]->accept(*this);
        expr_ << ") & static_cast<unsigned int>(";
        node.args[1]->accept(*this);
        expr_ << "))";
    } else if (node.name == "BITNOT") {
        expr_ << "(~static_cast<unsigned int>(";
        node.args[0]->accept(*this);
        expr_ << "))";
    } else if (node.name == "BITOR") {
        expr_ << "(static_cast<unsigned int>(";
        node.args[0]->accept(*this);
        expr_ << ") | static_cast<unsigned int>(";
        node.args[1]->accept(*this);
        expr_ << "))";
    } else if (node.name == "BITXOR") {
        expr_ << "(static_cast<unsigned int>(";
        node.args[0]->accept(*this);
        expr_ << ") ^ static_cast<unsigned int>(";
        node.args[1]->accept(*this);
        expr_ << "))";
    } else if (node.name == "SCANR") {
        expr_ << "rpg_scanr(";
        node.args[0]->accept(*this);
        expr_ << ", ";
        node.args[1]->accept(*this);
        if (node.args.size() > 2) {
            expr_ << ", ";
            node.args[2]->accept(*this);
        }
        expr_ << ")";
    } else if (node.name == "EDITFLT") {
        expr_ << "rpg_editflt(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "UNSH") {
        expr_ << "rpg_unsh(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else if (node.name == "PARMNUM") {
        // %PARMNUM returns the ordinal position of a parameter (compile-time)
        auto* id = dynamic_cast<Identifier*>(node.args[0].get());
        if (id && !current_proc_name_.empty()) {
            auto pit = nopass_proc_params_.find(current_proc_name_);
            if (pit != nopass_proc_params_.end()) {
                for (size_t i = 0; i < pit->second.size(); i++) {
                    if (pit->second[i].name == id->name) {
                        expr_ << (i + 1);
                        break;
                    }
                }
            } else {
                expr_ << "0 /* %PARMNUM: param not found */";
            }
        } else {
            expr_ << "0 /* %PARMNUM: not in procedure */";
        }
    } else if (node.name == "GETENV") {
        expr_ << "rpg_getenv(";
        node.args[0]->accept(*this);
        expr_ << ")";
    } else {
        expr_ << "/* unknown BIF: %" << node.name << " */";
    }
}

void CodeGen::visit(EvalRStmt& node) {
    // Right-adjust: pad left with spaces
    emitIndent();
    std::string target = emitExpr(*node.target);
    std::string value = emitExpr(*node.value);
    bool half_adj = node.extenders.find('H') != std::string::npos;
    if (half_adj) {
        // EVALR(H): round numeric value, convert to string, right-adjust
        out_ << target << " = rpg_evalr(" << target << ", std::to_string((long long)std::round(static_cast<double>(" << value << "))));\n";
    } else {
        out_ << target << " = rpg_evalr(" << target << ", " << value << ");\n";
    }
}

void CodeGen::visit(LeaveSRStmt& node) {
    (void)node;
    emitIndent();
    out_ << "return;\n";
}

void CodeGen::visit(EvalCorrStmt& node) {
    // Find both DS definitions and emit assignments for matching field names
    auto tit = ds_defs_.find(node.target);
    auto sit = ds_defs_.find(node.source);
    if (tit != ds_defs_.end() && sit != ds_defs_.end()) {
        DclDS* tds = tit->second;
        DclDS* sds = sit->second;
        for (auto& tf : tds->fields) {
            for (auto& sf : sds->fields) {
                if (tf.name == sf.name) {
                    emitIndent();
                    out_ << node.target << "." << tf.name << " = "
                         << node.source << "." << sf.name << ";\n";
                    break;
                }
            }
        }
    }
}

void CodeGen::visit(SndMsgStmt& node) {
    std::string msg_expr = emitExpr(*node.message);
    if (node.msg_type == "ESCAPE") {
        emitIndent();
        out_ << "std::cerr << \"ESCAPE: \" << " << msg_expr << " << std::endl;\n";
        emitIndent();
        out_ << "throw std::runtime_error(" << msg_expr << ");\n";
    } else {
        emitIndent();
        out_ << "std::cerr << \"" << node.msg_type << ": \" << " << msg_expr << " << std::endl;\n";
    }
}

void CodeGen::visit(XmlIntoStmt& node) {
    // Look up target DS definition
    auto it = ds_defs_.find(node.target);
    if (it == ds_defs_.end()) {
        emitIndent();
        out_ << "// XML-INTO: unknown target DS '" << node.target << "'\n";
        return;
    }
    DclDS* ds = it->second;

    // Determine options string
    std::string opts_expr;
    if (node.options) {
        opts_expr = emitExpr(*node.options);
    } else {
        opts_expr = "\"\"";
    }

    std::string xml_expr = emitExpr(*node.xml_source);

    // Parse the XML into a document
    emitIndent();
    out_ << "{\n";
    indent_++;
    emitIndent();
    out_ << "RpgXmlDoc __xml_doc = rpg_xml_parse(" << xml_expr << ");\n";
    emitIndent();
    out_ << "std::string __xml_opts = " << opts_expr << ";\n";
    emitIndent();
    out_ << "bool __xml_case_any = (__xml_opts.find(\"case=any\") != std::string::npos || "
         << "__xml_opts.find(\"case=upper\") != std::string::npos);\n";

    // Parse path= option if present
    emitIndent();
    out_ << "const RpgXmlNode* __xml_root = &__xml_doc.root;\n";
    emitIndent();
    out_ << "{\n";
    indent_++;
    emitIndent();
    out_ << "auto __path_pos = __xml_opts.find(\"path=\");\n";
    emitIndent();
    out_ << "if (__path_pos != std::string::npos) {\n";
    indent_++;
    emitIndent();
    out_ << "auto __path_start = __path_pos + 5;\n";
    emitIndent();
    out_ << "auto __path_end = __xml_opts.find(' ', __path_start);\n";
    emitIndent();
    out_ << "std::string __path = (__path_end == std::string::npos) ? "
         << "__xml_opts.substr(__path_start) : __xml_opts.substr(__path_start, __path_end - __path_start);\n";
    emitIndent();
    out_ << "auto* __nav = rpg_xml_navigate(*__xml_root, __path, __xml_case_any);\n";
    emitIndent();
    out_ << "if (__nav) __xml_root = __nav;\n";
    indent_--;
    emitIndent();
    out_ << "}\n";
    indent_--;
    emitIndent();
    out_ << "}\n";

    // Check if target is an array DS — if so, iterate XML children
    bool is_array = (ds->dim > 0 || ds->dim_type != 0);
    if (is_array) {
        bool is_vector = (ds->dim_type == 1 || ds->dim_type == 2);
        emitIndent();
        out_ << "auto& __xml_children = __xml_root->children;\n";
        if (is_vector) {
            // DIM(*VAR) / DIM(*AUTO) — push_back into vector
            emitIndent();
            out_ << "for (size_t __xml_i = 0; __xml_i < __xml_children.size() && static_cast<int>(__xml_i) < "
                 << ds->dim << "; __xml_i++) {\n";
            indent_++;
            emitIndent();
            out_ << "auto& __xml_src = __xml_children[__xml_i];\n";
            emitIndent();
            out_ << node.target << ".push_back({});\n";
            emitIndent();
            out_ << "auto& __xml_tgt = " << node.target << ".back();\n";
        } else {
            // Fixed DIM — index into std::array
            emitIndent();
            out_ << "for (size_t __xml_i = 0; __xml_i < __xml_children.size() && __xml_i < "
                 << node.target << ".size(); __xml_i++) {\n";
            indent_++;
            emitIndent();
            out_ << "auto& __xml_src = __xml_children[__xml_i];\n";
            emitIndent();
            out_ << "auto& __xml_tgt = " << node.target << "[__xml_i];\n";
        }
        // Emit field assignments for array element
        emitXmlFieldAssignments(ds, "__xml_tgt", "__xml_src");
        indent_--;
        emitIndent();
        out_ << "}\n";
    } else {
        emitIndent();
        out_ << "auto& __xml_src = *__xml_root;\n";
        // Emit field assignments for scalar
        emitXmlFieldAssignments(ds, node.target, "__xml_src");
    }

    indent_--;
    emitIndent();
    out_ << "}\n";
}

void CodeGen::emitXmlFieldAssignments(DclDS* ds, const std::string& target, const std::string& xml_src) {
    for (auto& f : ds->fields) {
        if (!f.likeds.empty()) {
            // Nested DS — find child node and extract recursively
            auto nested_it = ds_defs_.find(f.likeds);
            if (nested_it != ds_defs_.end()) {
                emitIndent();
                out_ << "{\n";
                indent_++;
                emitIndent();
                out_ << "const RpgXmlNode* __nested_" << f.name << " = rpg_xml_find("
                     << xml_src << ", \"" << f.name << "\", __xml_case_any);\n";
                emitIndent();
                out_ << "if (__nested_" << f.name << ") {\n";
                indent_++;
                std::string nested_target = target + "." + f.name;
                std::string nested_src = "*__nested_" + f.name;
                emitXmlFieldAssignments(nested_it->second, nested_target, nested_src);
                indent_--;
                emitIndent();
                out_ << "}\n";
                indent_--;
                emitIndent();
                out_ << "}\n";
            }
            continue;
        }
        emitIndent();
        switch (f.type) {
            case RPGType::INT10:
            case RPGType::UNS:
                out_ << target << "." << f.name << " = rpg_xml_get_int("
                     << xml_src << ", \"" << f.name << "\", __xml_case_any);\n";
                break;
            case RPGType::PACKED:
            case RPGType::ZONED:
            case RPGType::FLOAT4:
            case RPGType::FLOAT8:
                out_ << target << "." << f.name << " = rpg_xml_get_double("
                     << xml_src << ", \"" << f.name << "\", __xml_case_any);\n";
                break;
            default:
                out_ << target << "." << f.name << " = rpg_xml_get_str("
                     << xml_src << ", \"" << f.name << "\", __xml_case_any);\n";
                break;
        }
    }
}

void CodeGen::visit(DataIntoStmt& node) {
    auto it = ds_defs_.find(node.target);
    if (it == ds_defs_.end()) {
        emitIndent();
        out_ << "// DATA-INTO: unknown target DS '" << node.target << "'\n";
        return;
    }
    DclDS* ds = it->second;

    std::string opts_expr = node.options ? emitExpr(*node.options) : "\"\"";
    std::string data_expr = emitExpr(*node.data_source);
    bool is_array = (ds->dim > 0 || ds->dim_type != 0);

    if (isCsvParser(node.parser.get())) {
        // --- CSV path ---
        emitIndent(); out_ << "{\n"; indent_++;
        emitIndent(); out_ << "std::string __csv_opts = " << opts_expr << ";\n";
        emitIndent(); out_ << "bool __csv_case_any = (__csv_opts.find(\"case=any\") != std::string::npos || "
                           << "__csv_opts.find(\"case=upper\") != std::string::npos);\n";
        emitIndent(); out_ << "bool __csv_has_header = (__csv_opts.find(\"header=no\") == std::string::npos);\n";
        emitIndent(); out_ << "char __csv_delim = ',';\n";
        emitIndent(); out_ << "{ auto __dp = __csv_opts.find(\"delimiter=\");\n";
        emitIndent(); out_ << "  if (__dp != std::string::npos && __dp + 10 < __csv_opts.size())\n";
        emitIndent(); out_ << "      __csv_delim = __csv_opts[__dp + 10]; }\n";
        emitIndent(); out_ << "RpgCsvDoc __csv_doc = rpg_csv_parse(" << data_expr
                           << ", __csv_delim, __csv_has_header);\n";

        if (is_array) {
            bool is_vector = (ds->dim_type == 1 || ds->dim_type == 2);
            if (is_vector) {
                emitIndent();
                out_ << "for (size_t __ci = 0; __ci < __csv_doc.rows.size() && static_cast<int>(__ci) < "
                     << ds->dim << "; __ci++) {\n";
                indent_++;
                emitIndent(); out_ << node.target << ".push_back({});\n";
                emitCsvFieldAssignments(ds, node.target + ".back()", "__csv_doc", "__ci");
            } else {
                emitIndent();
                out_ << "for (size_t __ci = 0; __ci < __csv_doc.rows.size() && __ci < "
                     << node.target << ".size(); __ci++) {\n";
                indent_++;
                emitCsvFieldAssignments(ds, node.target + "[__ci]", "__csv_doc", "__ci");
            }
            indent_--;
            emitIndent(); out_ << "}\n";
        } else {
            emitCsvFieldAssignments(ds, node.target, "__csv_doc", "0");
        }

        indent_--;
        emitIndent(); out_ << "}\n";
    } else {
        // --- JSON path (default) ---
        emitIndent();
        out_ << "{\n";
        indent_++;
        emitIndent();
        out_ << "RpgJsonNode __json_doc = rpg_json_parse(" << data_expr << ");\n";
        emitIndent();
        out_ << "std::string __json_opts = " << opts_expr << ";\n";
        emitIndent();
        out_ << "bool __json_case_any = (__json_opts.find(\"case=any\") != std::string::npos || "
             << "__json_opts.find(\"case=upper\") != std::string::npos);\n";

        if (is_array) {
            bool is_vector = (ds->dim_type == 1 || ds->dim_type == 2);
            emitIndent();
            out_ << "auto& __json_items = __json_doc.items;\n";
            if (is_vector) {
                emitIndent();
                out_ << "for (size_t __ji = 0; __ji < __json_items.size() && static_cast<int>(__ji) < "
                     << ds->dim << "; __ji++) {\n";
                indent_++;
                emitIndent();
                out_ << "auto& __json_src = __json_items[__ji];\n";
                emitIndent();
                out_ << node.target << ".push_back({});\n";
                emitIndent();
                out_ << "auto& __json_tgt = " << node.target << ".back();\n";
            } else {
                emitIndent();
                out_ << "for (size_t __ji = 0; __ji < __json_items.size() && __ji < "
                     << node.target << ".size(); __ji++) {\n";
                indent_++;
                emitIndent();
                out_ << "auto& __json_src = __json_items[__ji];\n";
                emitIndent();
                out_ << "auto& __json_tgt = " << node.target << "[__ji];\n";
            }
            emitJsonFieldAssignments(ds, "__json_tgt", "__json_src");
            indent_--;
            emitIndent();
            out_ << "}\n";
        } else {
            emitIndent();
            out_ << "auto& __json_src = __json_doc;\n";
            emitJsonFieldAssignments(ds, node.target, "__json_src");
        }

        indent_--;
        emitIndent();
        out_ << "}\n";
    }
}

void CodeGen::emitJsonFieldAssignments(DclDS* ds, const std::string& target, const std::string& json_src) {
    for (auto& f : ds->fields) {
        if (!f.likeds.empty()) {
            auto nested_it = ds_defs_.find(f.likeds);
            if (nested_it != ds_defs_.end()) {
                emitIndent();
                out_ << "{\n";
                indent_++;
                emitIndent();
                out_ << "const RpgJsonNode* __nested_" << f.name << " = rpg_json_find("
                     << json_src << ", \"" << f.name << "\", __json_case_any);\n";
                emitIndent();
                out_ << "if (__nested_" << f.name << ") {\n";
                indent_++;
                std::string nested_target = target + "." + f.name;
                std::string nested_src = "*__nested_" + f.name;
                emitJsonFieldAssignments(nested_it->second, nested_target, nested_src);
                indent_--;
                emitIndent();
                out_ << "}\n";
                indent_--;
                emitIndent();
                out_ << "}\n";
            }
            continue;
        }
        emitIndent();
        switch (f.type) {
            case RPGType::INT10:
            case RPGType::UNS:
                out_ << target << "." << f.name << " = rpg_json_get_int("
                     << json_src << ", \"" << f.name << "\", __json_case_any);\n";
                break;
            case RPGType::PACKED:
            case RPGType::ZONED:
            case RPGType::FLOAT4:
            case RPGType::FLOAT8:
                out_ << target << "." << f.name << " = rpg_json_get_double("
                     << json_src << ", \"" << f.name << "\", __json_case_any);\n";
                break;
            default:
                out_ << target << "." << f.name << " = rpg_json_get_str("
                     << json_src << ", \"" << f.name << "\", __json_case_any);\n";
                break;
        }
    }
}

void CodeGen::visit(DataGenStmt& node) {
    auto it = ds_defs_.find(node.source_ds);
    if (it == ds_defs_.end()) {
        emitIndent();
        out_ << "// DATA-GEN: unknown source DS '" << node.source_ds << "'\n";
        return;
    }
    DclDS* ds = it->second;

    std::string opts_expr = node.options ? emitExpr(*node.options) : "\"\"";
    std::string output_expr = emitExpr(*node.output_var);
    bool is_array = (ds->dim > 0 || ds->dim_type != 0);

    if (isCsvParser(node.parser.get())) {
        // --- CSV path ---
        emitIndent(); out_ << "{\n"; indent_++;
        emitIndent(); out_ << "std::string __csv_opts = " << opts_expr << ";\n";
        emitIndent(); out_ << "bool __csv_has_header = (__csv_opts.find(\"header=no\") == std::string::npos);\n";
        emitIndent(); out_ << "char __csv_delim = ',';\n";
        emitIndent(); out_ << "{ auto __dp = __csv_opts.find(\"delimiter=\");\n";
        emitIndent(); out_ << "  if (__dp != std::string::npos && __dp + 10 < __csv_opts.size())\n";
        emitIndent(); out_ << "      __csv_delim = __csv_opts[__dp + 10]; }\n";
        emitIndent(); out_ << "std::string __csv_out;\n";

        // Header row (compile-time field names, emitted as a runtime conditional)
        emitIndent(); out_ << "if (__csv_has_header) {\n"; indent_++;
        bool hdr_first = true;
        for (auto& f : ds->fields) {
            emitIndent();
            if (!hdr_first) out_ << "__csv_out += std::string(1, __csv_delim);\n";
            hdr_first = false;
            emitIndent();
            // Field names are always uppercase in RPG; quote them for safety
            out_ << "__csv_out += rpg_csv_escape(\"" << f.name << "\", __csv_delim);\n";
        }
        emitIndent(); out_ << "__csv_out += \"\\n\";\n";
        indent_--; emitIndent(); out_ << "}\n";

        // Data row(s): rows separated by \n, no trailing \n.
        // The header row (if any) already ends with \n, so only add \n before rows
        // after the first, or always for rows after the first in an array.
        if (is_array) {
            emitIndent();
            out_ << "for (size_t __gi = 0; __gi < " << node.source_ds << ".size(); __gi++) {\n";
            indent_++;
            emitIndent(); out_ << "if (__gi > 0) __csv_out += \"\\n\";\n";
            emitCsvFieldGeneration(ds, node.source_ds + "[__gi]", "__csv_out");
            indent_--;
            emitIndent(); out_ << "}\n";
        } else {
            emitCsvFieldGeneration(ds, node.source_ds, "__csv_out");
        }

        emitIndent(); out_ << output_expr << " = __csv_out;\n";
        indent_--;
        emitIndent(); out_ << "}\n";
    } else {
        // --- JSON path (default) ---
        emitIndent();
        out_ << "{\n";
        indent_++;
        emitIndent();
        out_ << "std::string __json_out;\n";

        if (is_array) {
            emitIndent();
            out_ << "__json_out = \"[\";\n";
            emitIndent();
            out_ << "for (size_t __gi = 0; __gi < " << node.source_ds << ".size(); __gi++) {\n";
            indent_++;
            emitIndent();
            out_ << "if (__gi > 0) __json_out += \",\";\n";
            emitIndent();
            out_ << "__json_out += \"{\";\n";
            emitJsonFieldGeneration(ds, node.source_ds + "[__gi]", "__json_out", true);
            emitIndent();
            out_ << "__json_out += \"}\";\n";
            indent_--;
            emitIndent();
            out_ << "}\n";
            emitIndent();
            out_ << "__json_out += \"]\";\n";
        } else {
            emitIndent();
            out_ << "__json_out = \"{\";\n";
            emitJsonFieldGeneration(ds, node.source_ds, "__json_out", true);
            emitIndent();
            out_ << "__json_out += \"}\";\n";
        }

        emitIndent();
        out_ << output_expr << " = __json_out;\n";
        indent_--;
        emitIndent();
        out_ << "}\n";
    }
}

void CodeGen::emitJsonFieldGeneration(DclDS* ds, const std::string& source,
                                      const std::string& out_var, bool first) {
    bool f_first = first;
    for (auto& f : ds->fields) {
        std::string sep = f_first ? "" : ",";
        f_first = false;
        std::string field_ref = source + "." + f.name;
        emitIndent();
        out_ << out_var << " += \"" << sep << "\\\"" << f.name << "\\\":\";\n";
        emitIndent();
        switch (f.type) {
            case RPGType::INT10:
            case RPGType::UNS:
                out_ << out_var << " += std::to_string(" << field_ref << ");\n";
                break;
            case RPGType::PACKED:
            case RPGType::ZONED:
            case RPGType::FLOAT4:
            case RPGType::FLOAT8:
                out_ << out_var << " += std::to_string(" << field_ref << ");\n";
                break;
            default:
                out_ << out_var << " += \"\\\"\" + rpg_json_escape(" << field_ref << ") + \"\\\"\";\n";
                break;
        }
    }
}

void CodeGen::emitCsvFieldAssignments(DclDS* ds, const std::string& target,
                                       const std::string& csv_doc, const std::string& row_idx) {
    for (auto& f : ds->fields) {
        emitIndent();
        switch (f.type) {
            case RPGType::INT10:
            case RPGType::UNS:
                out_ << target << "." << f.name << " = rpg_csv_get_int("
                     << csv_doc << ", " << row_idx << ", \"" << f.name << "\", __csv_case_any);\n";
                break;
            case RPGType::PACKED:
            case RPGType::ZONED:
            case RPGType::FLOAT4:
            case RPGType::FLOAT8:
                out_ << target << "." << f.name << " = rpg_csv_get_double("
                     << csv_doc << ", " << row_idx << ", \"" << f.name << "\", __csv_case_any);\n";
                break;
            default:
                out_ << target << "." << f.name << " = rpg_csv_get_str("
                     << csv_doc << ", " << row_idx << ", \"" << f.name << "\", __csv_case_any);\n";
                break;
        }
    }
}

void CodeGen::emitCsvFieldGeneration(DclDS* ds, const std::string& source,
                                      const std::string& out_var) {
    bool first = true;
    for (auto& f : ds->fields) {
        std::string field_ref = source + "." + f.name;
        if (!first) {
            emitIndent();
            out_ << out_var << " += std::string(1, __csv_delim);\n";
        }
        first = false;
        emitIndent();
        switch (f.type) {
            case RPGType::INT10:
            case RPGType::UNS:
                out_ << out_var << " += std::to_string(" << field_ref << ");\n";
                break;
            case RPGType::PACKED:
            case RPGType::ZONED:
            case RPGType::FLOAT4:
            case RPGType::FLOAT8:
                out_ << out_var << " += std::to_string(" << field_ref << ");\n";
                break;
            default:
                out_ << out_var << " += rpg_csv_escape(" << field_ref << ", __csv_delim);\n";
                break;
        }
    }
}

void CodeGen::visit(DataInStmt& node) {
    auto it = dtaara_vars_.find(node.var_name);
    if (it != dtaara_vars_.end()) {
        int len = 0;
        auto lit = var_lengths_.find(node.var_name);
        if (lit != var_lengths_.end()) len = lit->second;
        emitIndent();
        out_ << node.var_name << " = rpg_da_read(\"" << it->second << "\", " << len << ");\n";
    }
}

void CodeGen::visit(DataOutStmt& node) {
    auto it = dtaara_vars_.find(node.var_name);
    if (it != dtaara_vars_.end()) {
        emitIndent();
        out_ << "rpg_da_write(\"" << it->second << "\", " << node.var_name << ");\n";
    }
}

void CodeGen::visit(DataUnlockStmt& node) {
    auto it = dtaara_vars_.find(node.var_name);
    if (it != dtaara_vars_.end()) {
        emitIndent();
        out_ << "rpg_da_unlock(\"" << it->second << "\");\n";
    }
}

void CodeGen::visit(CallpStmt& node) {
    bool error_ext = node.extenders.find('E') != std::string::npos;
    emitIndent();
    if (error_ext) {
        out_ << "rpg_error_flag() = false; rpg_status_code() = 0;\n";
        emitIndent();
        out_ << "try {\n";
        indent_++;
        emitIndent();
        out_ << emitExpr(*node.expr) << ";\n";
        indent_--;
        emitIndent();
        out_ << "} catch (...) { rpg_error_flag() = true; rpg_status_code() = 202; }\n";
    } else {
        out_ << emitExpr(*node.expr) << ";\n";
    }
}

void CodeGen::visit(SortAStmt& node) {
    emitIndent();
    out_ << "std::sort(" << node.array_name << ".begin(), " << node.array_name << ".end());\n";
}

void CodeGen::visit(DeallocStmt& node) {
    emitIndent();
    out_ << "std::free(" << node.var_name << ");\n";
    emitIndent();
    out_ << node.var_name << " = nullptr;\n";
}

void CodeGen::visit(TestStmt& node) {
    emitIndent();
    out_ << "rpg_error_flag() = !rpg_test_";
    switch (node.type) {
        case 'D': out_ << "date"; break;
        case 'T': out_ << "time"; break;
        case 'Z': out_ << "timestamp"; break;
    }
    out_ << "(" << node.var_name << ");\n";
}

std::string CodeGen::paramTypeDefault(const ParamDecl& p) {
    if (p.omit) return "nullptr";  // *OMIT defaults to omitted
    if (!p.likeds.empty()) return p.likeds + "_t{}";
    switch (p.type) {
        case RPGType::CHAR:
        case RPGType::VARCHAR: return "std::string()";
        case RPGType::INT10: return "0";
        case RPGType::PACKED:
        case RPGType::ZONED: return "0.0";
        case RPGType::IND: return "false";
        default: return "{}";
    }
}

int CodeGen::countRequiredParams(const std::vector<ParamDecl>& params) {
    int count = 0;
    for (auto& p : params) {
        if (!p.nopass) count++;
    }
    return count;
}

void CodeGen::visit(ForEachStmt& node) {
    emitIndent();
    std::string coll = emitExpr(*node.collection);
    out_ << "for (auto& " << node.var << " : " << coll << ") {\n";
    indent_++;
    emitStatements(node.body);
    indent_--;
    emitIndent();
    out_ << "}\n";
}

void CodeGen::visit(InExpr& node) {
    auto* bif = dynamic_cast<BIFCall*>(node.collection.get());
    if (bif && bif->name == "LIST") {
        expr_ << "rpg_in_list(";
        node.value->accept(*this);
        expr_ << ", rpg_list(";
        for (size_t i = 0; i < bif->args.size(); i++) {
            if (i > 0) expr_ << ", ";
            bif->args[i]->accept(*this);
        }
        expr_ << "))";
    } else if (bif && bif->name == "RANGE") {
        expr_ << "rpg_in_range(";
        node.value->accept(*this);
        expr_ << ", rpg_range(";
        bif->args[0]->accept(*this);
        expr_ << ", ";
        bif->args[1]->accept(*this);
        expr_ << "))";
    } else {
        // Generic: assume collection is iterable
        expr_ << "rpg_in_list(";
        node.value->accept(*this);
        expr_ << ", ";
        node.collection->accept(*this);
        expr_ << ")";
    }
}

// ============================================================
// RLA helper methods
// ============================================================

std::string CodeGen::rlaColumnList(const ExternalFileDesc& desc) const {
    std::string s;
    for (size_t i = 0; i < desc.fields.size(); i++) {
        if (i > 0) s += ",";
        s += desc.fields[i].name;
    }
    return s;
}

std::string CodeGen::rlaParamList(const ExternalFileDesc& /*desc*/, size_t count) const {
    std::string s;
    for (size_t i = 0; i < count; i++) {
        if (i > 0) s += ",";
        s += "?";
    }
    return s;
}

std::string CodeGen::rlaFieldVar(const std::string& fname, const std::string& fieldName) const {
    auto it = file_defs_.find(fname);
    if (it != file_defs_.end() && !it->second->prefix.empty())
        return it->second->prefix + fieldName;
    return fieldName;
}

std::string CodeGen::rlaKeyColName(const std::string& fname) const {
    auto it = ext_file_descs_.find(fname);
    if (it == ext_file_descs_.end() || it->second.fields.empty()) return "";
    return it->second.fields[0].name; // first field is the key
}

// Emit the lazy-open block for a file (prepares all ODBC statements on first use)
void CodeGen::emitRlaFileOpen(const std::string& fname, const ExternalFileDesc& desc, bool keyed) {
    std::string cols = rlaColumnList(desc);
    std::string tbl  = desc.tableName;
    std::string keyCol = desc.fields.empty() ? "1" : desc.fields[0].name;

    emitIndent(); out_ << "if (!" << fname << "_open) {\n";
    indent_++;
    emitIndent(); out_ << fname << "_open = true;\n";

    // Scroll cursor: SELECT cols FROM tbl ORDER BY keycol (static, scrollable)
    std::string scrollSql = "SELECT " + cols + " FROM " + tbl + " ORDER BY " + keyCol;
    emitIndent(); out_ << fname << "_scroll = __sql_env.allocStmt();\n";
    emitIndent(); out_ << "SQLSetStmtAttr(" << fname << "_scroll, SQL_ATTR_CURSOR_TYPE, "
                       << "(SQLPOINTER)SQL_CURSOR_STATIC, 0);\n";
    emitIndent(); out_ << "SQLPrepare(" << fname << "_scroll, (SQLCHAR*)\"" << scrollSql << "\", SQL_NTS);\n";
    emitIndent(); out_ << "SQLExecute(" << fname << "_scroll);\n";

    if (keyed && !desc.fields.empty()) {
        // CHAIN: SELECT by key
        std::string chainSql = "SELECT " + cols + " FROM " + tbl + " WHERE " + keyCol + "=?";
        emitIndent(); out_ << fname << "_chain = __sql_env.allocStmt();\n";
        emitIndent(); out_ << "SQLPrepare(" << fname << "_chain, (SQLCHAR*)\"" << chainSql << "\", SQL_NTS);\n";
    }

    // INSERT
    std::string insSql = "INSERT INTO " + tbl + "(" + cols + ") VALUES(" + rlaParamList(desc, desc.fields.size()) + ")";
    emitIndent(); out_ << fname << "_ins = __sql_env.allocStmt();\n";
    emitIndent(); out_ << "SQLPrepare(" << fname << "_ins, (SQLCHAR*)\"" << insSql << "\", SQL_NTS);\n";

    if (!desc.fields.empty()) {
        // UPDATE: SET all non-key fields WHERE key=?
        std::string updSet;
        for (size_t i = 1; i < desc.fields.size(); i++) {
            if (i > 1) updSet += ",";
            updSet += desc.fields[i].name + "=?";
        }
        if (!updSet.empty()) {
            std::string updSql = "UPDATE " + tbl + " SET " + updSet + " WHERE " + keyCol + "=?";
            emitIndent(); out_ << fname << "_upd = __sql_env.allocStmt();\n";
            emitIndent(); out_ << "SQLPrepare(" << fname << "_upd, (SQLCHAR*)\"" << updSql << "\", SQL_NTS);\n";
        }

        // DELETE: WHERE key=?
        std::string delSql = "DELETE FROM " + tbl + " WHERE " + keyCol + "=?";
        emitIndent(); out_ << fname << "_del = __sql_env.allocStmt();\n";
        emitIndent(); out_ << "SQLPrepare(" << fname << "_del, (SQLCHAR*)\"" << delSql << "\", SQL_NTS);\n";
    }

    indent_--;
    emitIndent(); out_ << "}\n";
}

// Emit SQLBindCol calls + string buffers for all fields of a file
void CodeGen::emitRlaFetchBind(const std::string& fname, const ExternalFileDesc& desc,
                                const std::string& stmtVar) {
    for (size_t i = 0; i < desc.fields.size(); i++) {
        auto& f = desc.fields[i];
        int col = static_cast<int>(i) + 1;
        std::string fvar = rlaFieldVar(fname, f.name);
        if (f.bindKind == "str") {
            emitIndent(); out_ << "char __rla_buf_" << i << "[4096] = {};\n";
            emitIndent(); out_ << "SQLLEN __rla_ind_" << i << " = 0;\n";
            emitIndent(); out_ << "SQLBindCol(" << stmtVar << ", " << col
                               << ", SQL_C_CHAR, __rla_buf_" << i
                               << ", sizeof(__rla_buf_" << i << "), &__rla_ind_" << i << ");\n";
        } else if (f.bindKind == "int") {
            emitIndent(); out_ << "SQLLEN __rla_ind_" << i << " = 0;\n";
            emitIndent(); out_ << "SQLINTEGER __rla_int_" << i << " = 0;\n";
            emitIndent(); out_ << "SQLBindCol(" << stmtVar << ", " << col
                               << ", SQL_C_SLONG, &__rla_int_" << i
                               << ", 0, &__rla_ind_" << i << ");\n";
        } else {
            emitIndent(); out_ << "SQLLEN __rla_ind_" << i << " = 0;\n";
            emitIndent(); out_ << "SQLDOUBLE __rla_dbl_" << i << " = 0;\n";
            emitIndent(); out_ << "SQLBindCol(" << stmtVar << ", " << col
                               << ", SQL_C_DOUBLE, &__rla_dbl_" << i
                               << ", 0, &__rla_ind_" << i << ");\n";
        }
    }
}

// Emit copy-back from temp vars to per-file field variables
void CodeGen::emitRlaCopyBack(const std::string& fname, const ExternalFileDesc& desc,
                               const std::string& /*stmtVar*/, const std::string& rcVar) {
    for (size_t i = 0; i < desc.fields.size(); i++) {
        auto& f = desc.fields[i];
        std::string fvar = rlaFieldVar(fname, f.name);
        emitIndent();
        if (f.bindKind == "str") {
            out_ << "if (" << rcVar << " == SQL_SUCCESS || " << rcVar
                 << " == SQL_SUCCESS_WITH_INFO) " << fvar << " = std::string(__rla_buf_" << i << ");\n";
        } else if (f.bindKind == "int") {
            out_ << "if (" << rcVar << " == SQL_SUCCESS || " << rcVar
                 << " == SQL_SUCCESS_WITH_INFO) " << fvar << " = (long)__rla_int_" << i << ";\n";
        } else {
            out_ << "if (" << rcVar << " == SQL_SUCCESS || " << rcVar
                 << " == SQL_SUCCESS_WITH_INFO) " << fvar << " = (double)__rla_dbl_" << i << ";\n";
        }
    }
}

// ============================================================
// RLA opcode visitors
// ============================================================

void CodeGen::visit(ReadStmt& node) {
    // Check if this is a READ from a WORKSTN (display file) record format
    {
        DclF* dclf = nullptr;
        std::string fname;
        if (file_defs_.count(node.filename) && file_defs_[node.filename]->usage == "WORKSTN") {
            dclf = file_defs_[node.filename]; fname = node.filename;
        } else {
            for (auto& [fn, df] : file_defs_) {
                if (df->usage != "WORKSTN") continue;
                auto dit = dspf_descs_.find(fn);
                if (dit == dspf_descs_.end()) continue;
                if (dit->second.recIdx.count(node.filename)) { dclf = df; fname = fn; break; }
            }
        }
        if (dclf) {
            const DspfFileInfo* dfi = dspf_descs_.count(fname) ? &dspf_descs_[fname] : nullptr;
            const DspfRecInfo*  rci = nullptr;
            if (dfi) {
                auto rit = dfi->recIdx.find(node.filename);
                if (rit != dfi->recIdx.end()) rci = &dfi->records[rit->second];
            }
            std::string bufName = node.filename + "_buf_";
            emitIndent(); out_ << "{\n"; indent_++;
            if (rci) {
                for (const DspfFldInfo& f : rci->fields) {
                    emitIndent();
                    if ((f.dtype == 'A' || f.dtype == 'L' || f.dtype == 'T' || f.dtype == 'Z')) {
                        out_ << "strncpy(" << bufName << "." << f.name << ", "
                             << f.rpgName() << ".c_str(), " << f.len << "); "
                             << bufName << "." << f.name << "[" << f.len << "] = '\\0';\n";
                    } else {
                        out_ << bufName << "." << f.name << " = " << f.rpgName() << ";\n";
                    }
                }
            }
            emitIndent(); out_ << "dspf_set_indicators(rpg_indicators, 100);\n";
            emitIndent(); out_ << "int __dspf_key = dspf_read(\""
                               << node.filename << "\", &" << bufName << ");\n";
            if (rci) {
                for (const DspfFldInfo& f : rci->fields) {
                    if (f.io == 'O') continue; // only copy back input/both/hidden
                    emitIndent();
                    if ((f.dtype == 'A' || f.dtype == 'L' || f.dtype == 'T' || f.dtype == 'Z')) {
                        out_ << f.rpgName() << " = std::string(" << bufName << "." << f.name
                             << ", strnlen(" << bufName << "." << f.name << ", " << f.len << "));\n";
                    } else {
                        out_ << f.rpgName() << " = " << bufName << "." << f.name << ";\n";
                    }
                }
            }
            emitIndent(); out_ << "for (int __i = 1; __i <= 24; ++__i) rpg_indicators[__i] = false;\n";
            emitIndent(); out_ << "if (__dspf_key >= 1 && __dspf_key <= 99) rpg_indicators[__dspf_key] = true;\n";
            uses_indicators_ = true;
            indent_--; emitIndent(); out_ << "}\n";
            return;
        }
    }

    // Program-described (I-spec) READ
    {
        auto fin = flat_input_formats_.find(node.filename);
        if (fin != flat_input_formats_.end()) {
            emitIndent(); out_ << "{\n"; indent_++;
            emitIndent(); out_ << "std::string __rec;\n";
            emitIndent(); out_ << "bool __ok = " << node.filename << "_ff.readNext(__rec);\n";
            emitIndent(); out_ << node.filename << "_eof = !__ok;\n";
            emitIndent(); out_ << node.filename << "_found = __ok;\n";
            emitIndent(); out_ << "if (__ok) {\n"; indent_++;
            // Reset every record-identifying indicator this file's
            // formats use before dispatch, so a later read of a
            // different record type doesn't leave an earlier read's
            // indicator stuck on (this compiler has no RPG cycle to do
            // that reset for us).
            for (auto* rf : fin->second) {
                if (!rf->recordIdIndicator.empty()) {
                    emitIndent(); out_ << "rpg_indicators[" << atoi(rf->recordIdIndicator.c_str())
                                       << "] = false;\n";
                }
            }
            for (auto* rf : fin->second) {
                std::string cond;
                if (rf->idTests.empty()) {
                    cond = "true";
                } else {
                    for (size_t i = 0; i < rf->idTests.size(); i++) {
                        auto& t = rf->idTests[i];
                        if (i) cond += " && ";
                        cond += "__rec.substr(" + std::to_string(t.position - 1) + ", 1) " +
                                (t.negate ? "!= \"" : "== \"") + cppEscape(t.character) + "\"";
                    }
                }
                emitIndent(); out_ << "if (" << cond << ") {\n"; indent_++;
                if (!rf->recordIdIndicator.empty()) {
                    emitIndent(); out_ << "rpg_indicators[" << atoi(rf->recordIdIndicator.c_str())
                                       << "] = true;\n";
                }
                for (auto& f : rf->fields) {
                    int width = f.toPos - f.fromPos + 1;
                    std::string raw = "__rec.substr(" + std::to_string(f.fromPos - 1) +
                                       ", " + std::to_string(width) + ")";
                    std::string cpptype = typeToString(f.type);
                    emitIndent();
                    if (cpptype == "std::string") {
                        out_ << f.name << " = " << raw << ";\n";
                    } else {
                        out_ << f.name << " = static_cast<" << cpptype
                             << ">(rpg_flatfile_parse_numeric(" << raw << ", " << f.decimals << "));\n";
                    }
                    if (!f.indPlus.empty()) {
                        emitIndent(); out_ << "rpg_indicators[" << atoi(f.indPlus.c_str())
                                           << "] = (" << f.name << " > 0);\n";
                    }
                    if (!f.indMinus.empty()) {
                        emitIndent(); out_ << "rpg_indicators[" << atoi(f.indMinus.c_str())
                                           << "] = (" << f.name << " < 0);\n";
                    }
                    if (!f.indZeroBlank.empty()) {
                        emitIndent();
                        if (cpptype == "std::string") {
                            out_ << "rpg_indicators[" << atoi(f.indZeroBlank.c_str())
                                 << "] = rpg_trim(" << f.name << ").empty();\n";
                        } else {
                            out_ << "rpg_indicators[" << atoi(f.indZeroBlank.c_str())
                                 << "] = (" << f.name << " == 0);\n";
                        }
                    }
                }
                indent_--; emitIndent(); out_ << "}\n";
            }
            indent_--; emitIndent(); out_ << "}\n";
            indent_--; emitIndent(); out_ << "}\n";
            uses_indicators_ = true;
            return;
        }
    }

    // Disk / RLA READ
    auto it = ext_file_descs_.find(node.filename);
    if (it == ext_file_descs_.end()) {
        emitIndent(); out_ << "// READ " << node.filename << " — no schema\n"; return;
    }
    auto* dclf = file_defs_.count(node.filename) ? file_defs_[node.filename] : nullptr;
    const ExternalFileDesc& desc = it->second;
    emitIndent(); out_ << "{\n"; indent_++;
    emitRlaFileOpen(node.filename, desc, dclf && dclf->keyed);
    emitRlaFetchBind(node.filename, desc, node.filename + "_scroll");
    emitIndent(); out_ << "SQLRETURN __rla_rc = SQLFetchScroll(" << node.filename
                       << "_scroll, SQL_FETCH_NEXT, 0);\n";
    emitIndent(); out_ << node.filename << "_eof   = (__rla_rc == SQL_NO_DATA);\n";
    emitIndent(); out_ << node.filename << "_found = (__rla_rc == SQL_SUCCESS || __rla_rc == SQL_SUCCESS_WITH_INFO);\n";
    emitRlaCopyBack(node.filename, desc, node.filename + "_scroll", "__rla_rc");
    indent_--; emitIndent(); out_ << "}\n";
}

void CodeGen::visit(ReadcStmt& node) {
    // READC only makes sense against a WORKSTN subfile record format —
    // find it the same way the WORKSTN branch of READ does.
    DclF* dclf = nullptr;
    std::string fname;
    for (auto& [fn, df] : file_defs_) {
        if (df->usage != "WORKSTN") continue;
        auto dit = dspf_descs_.find(fn);
        if (dit == dspf_descs_.end()) continue;
        if (dit->second.recIdx.count(node.recordname)) { dclf = df; fname = fn; break; }
    }
    if (!dclf) {
        emitIndent(); out_ << "// READC " << node.recordname << " — no WORKSTN record format found\n";
        return;
    }

    const DspfFileInfo* dfi = dspf_descs_.count(fname) ? &dspf_descs_[fname] : nullptr;
    const DspfRecInfo*  rci = nullptr;
    if (dfi) {
        auto rit = dfi->recIdx.find(node.recordname);
        if (rit != dfi->recIdx.end()) rci = &dfi->records[rit->second];
    }
    std::string bufName = node.recordname + "_buf_";
    emitIndent(); out_ << "{\n"; indent_++;
    emitIndent(); out_ << "int __dspf_rrn = dspf_readc(\"" << node.recordname
                       << "\", &" << bufName << ");\n";
    emitIndent(); out_ << node.recordname << "_eof = (__dspf_rrn == 0);\n";
    // Unlike a normal EXFMT/READ copy-back (input/both/hidden fields only —
    // the program already knows what it output), READC copies every
    // field, including OUTPUT: the row's OUTPUT fields (e.g. a key like
    // CUSTNO) are how the program identifies *which* row's OPTION was
    // touched.
    if (rci) {
        emitIndent(); out_ << "if (__dspf_rrn != 0) {\n"; indent_++;
        for (const DspfFldInfo& f : rci->fields) {
            emitIndent();
            if ((f.dtype == 'A' || f.dtype == 'L' || f.dtype == 'T' || f.dtype == 'Z')) {
                out_ << f.rpgName() << " = std::string(" << bufName << "." << f.name
                     << ", strnlen(" << bufName << "." << f.name << ", " << f.len << "));\n";
            } else {
                out_ << f.rpgName() << " = " << bufName << "." << f.name << ";\n";
            }
        }
        indent_--; emitIndent(); out_ << "}\n";
    }
    indent_--; emitIndent(); out_ << "}\n";
}

void CodeGen::visit(ReadpStmt& node) {
    auto it = ext_file_descs_.find(node.filename);
    if (it == ext_file_descs_.end()) {
        emitIndent(); out_ << "// READP " << node.filename << " — no schema\n"; return;
    }
    auto* dclf = file_defs_.count(node.filename) ? file_defs_[node.filename] : nullptr;
    const ExternalFileDesc& desc = it->second;
    emitIndent(); out_ << "{\n"; indent_++;
    emitRlaFileOpen(node.filename, desc, dclf && dclf->keyed);
    emitRlaFetchBind(node.filename, desc, node.filename + "_scroll");
    emitIndent(); out_ << "SQLRETURN __rla_rc = SQLFetchScroll(" << node.filename
                       << "_scroll, SQL_FETCH_PRIOR, 0);\n";
    emitIndent(); out_ << node.filename << "_eof   = (__rla_rc == SQL_NO_DATA);\n";
    emitIndent(); out_ << node.filename << "_found = (__rla_rc == SQL_SUCCESS || __rla_rc == SQL_SUCCESS_WITH_INFO);\n";
    emitRlaCopyBack(node.filename, desc, node.filename + "_scroll", "__rla_rc");
    indent_--; emitIndent(); out_ << "}\n";
}

void CodeGen::visit(ReadeStmt& node) {
    auto it = ext_file_descs_.find(node.filename);
    if (it == ext_file_descs_.end()) {
        emitIndent(); out_ << "// READE " << node.filename << " — no schema\n"; return;
    }
    auto* dclf = file_defs_.count(node.filename) ? file_defs_[node.filename] : nullptr;
    const ExternalFileDesc& desc = it->second;
    std::string keyVar = node.keys.empty() ? "" : emitExpr(*node.keys[0]);
    std::string keyCol = rlaKeyColName(node.filename);
    emitIndent(); out_ << "{\n"; indent_++;
    emitRlaFileOpen(node.filename, desc, dclf && dclf->keyed);
    emitRlaFetchBind(node.filename, desc, node.filename + "_scroll");
    emitIndent(); out_ << "SQLRETURN __rla_rc = SQLFetchScroll(" << node.filename
                       << "_scroll, SQL_FETCH_NEXT, 0);\n";
    // Post-check key equality
    if (!keyVar.empty() && !keyCol.empty()) {
        std::string fvar = rlaFieldVar(node.filename, keyCol);
        emitIndent(); out_ << "if (__rla_rc == SQL_SUCCESS || __rla_rc == SQL_SUCCESS_WITH_INFO) {\n";
        indent_++;
        emitRlaCopyBack(node.filename, desc, node.filename + "_scroll", "__rla_rc");
        emitIndent(); out_ << "if (!(" << fvar << " == " << keyVar << ")) __rla_rc = SQL_NO_DATA;\n";
        indent_--;
        emitIndent(); out_ << "}\n";
    } else {
        emitRlaCopyBack(node.filename, desc, node.filename + "_scroll", "__rla_rc");
    }
    emitIndent(); out_ << node.filename << "_eof   = (__rla_rc == SQL_NO_DATA);\n";
    emitIndent(); out_ << node.filename << "_found = (__rla_rc == SQL_SUCCESS || __rla_rc == SQL_SUCCESS_WITH_INFO);\n";
    indent_--; emitIndent(); out_ << "}\n";
}

void CodeGen::visit(ReadpeStmt& node) {
    auto it = ext_file_descs_.find(node.filename);
    if (it == ext_file_descs_.end()) {
        emitIndent(); out_ << "// READPE " << node.filename << " — no schema\n"; return;
    }
    auto* dclf = file_defs_.count(node.filename) ? file_defs_[node.filename] : nullptr;
    const ExternalFileDesc& desc = it->second;
    std::string keyVar = node.keys.empty() ? "" : emitExpr(*node.keys[0]);
    std::string keyCol = rlaKeyColName(node.filename);
    emitIndent(); out_ << "{\n"; indent_++;
    emitRlaFileOpen(node.filename, desc, dclf && dclf->keyed);
    emitRlaFetchBind(node.filename, desc, node.filename + "_scroll");
    emitIndent(); out_ << "SQLRETURN __rla_rc = SQLFetchScroll(" << node.filename
                       << "_scroll, SQL_FETCH_PRIOR, 0);\n";
    if (!keyVar.empty() && !keyCol.empty()) {
        std::string fvar = rlaFieldVar(node.filename, keyCol);
        emitIndent(); out_ << "if (__rla_rc == SQL_SUCCESS || __rla_rc == SQL_SUCCESS_WITH_INFO) {\n";
        indent_++;
        emitRlaCopyBack(node.filename, desc, node.filename + "_scroll", "__rla_rc");
        emitIndent(); out_ << "if (!(" << fvar << " == " << keyVar << ")) __rla_rc = SQL_NO_DATA;\n";
        indent_--;
        emitIndent(); out_ << "}\n";
    } else {
        emitRlaCopyBack(node.filename, desc, node.filename + "_scroll", "__rla_rc");
    }
    emitIndent(); out_ << node.filename << "_eof   = (__rla_rc == SQL_NO_DATA);\n";
    emitIndent(); out_ << node.filename << "_found = (__rla_rc == SQL_SUCCESS || __rla_rc == SQL_SUCCESS_WITH_INFO);\n";
    indent_--; emitIndent(); out_ << "}\n";
}

void CodeGen::visit(ChainStmt& node) {
    auto it = ext_file_descs_.find(node.filename);
    if (it == ext_file_descs_.end()) {
        emitIndent(); out_ << "// CHAIN " << node.filename << " — no schema\n"; return;
    }
    auto* dclf = file_defs_.count(node.filename) ? file_defs_[node.filename] : nullptr;
    const ExternalFileDesc& desc = it->second;
    std::string keyExpr = node.keys.empty() ? "" : emitExpr(*node.keys[0]);
    emitIndent(); out_ << "{\n"; indent_++;
    emitRlaFileOpen(node.filename, desc, dclf && dclf->keyed);
    emitIndent(); out_ << "__sql_env.clearParamBufs();\n";
    if (!keyExpr.empty()) {
        emitIndent(); out_ << "__sql_env.bindParam(" << node.filename << "_chain, 1, " << keyExpr << ");\n";
    }
    emitIndent(); out_ << "SQLFreeStmt(" << node.filename << "_chain, SQL_CLOSE);\n";
    emitIndent(); out_ << "SQLExecute(" << node.filename << "_chain);\n";
    emitRlaFetchBind(node.filename, desc, node.filename + "_chain");
    emitIndent(); out_ << "SQLRETURN __rla_rc = SQLFetch(" << node.filename << "_chain);\n";
    emitIndent(); out_ << node.filename << "_found = (__rla_rc == SQL_SUCCESS || __rla_rc == SQL_SUCCESS_WITH_INFO);\n";
    emitIndent(); out_ << node.filename << "_eof   = false;\n";
    emitRlaCopyBack(node.filename, desc, node.filename + "_chain", "__rla_rc");
    indent_--; emitIndent(); out_ << "}\n";
}

void CodeGen::visit(WriteStmt& node) {
    // Check if this is a WRITE to a WORKSTN (display file) record format
    {
        DclF* dclf = nullptr;
        std::string fname;
        if (file_defs_.count(node.filename) && file_defs_[node.filename]->usage == "WORKSTN") {
            dclf = file_defs_[node.filename]; fname = node.filename;
        } else {
            for (auto& [fn, df] : file_defs_) {
                if (df->usage != "WORKSTN") continue;
                auto dit = dspf_descs_.find(fn);
                if (dit == dspf_descs_.end()) continue;
                if (dit->second.recIdx.count(node.filename)) { dclf = df; fname = fn; break; }
            }
        }
        if (dclf) {
            const DspfFileInfo* dfi = dspf_descs_.count(fname) ? &dspf_descs_[fname] : nullptr;
            const DspfRecInfo*  rci = nullptr;
            if (dfi) {
                auto rit = dfi->recIdx.find(node.filename);
                if (rit != dfi->recIdx.end()) rci = &dfi->records[rit->second];
            }
            std::string bufName = node.filename + "_buf_";
            emitIndent(); out_ << "{\n"; indent_++;
            if (rci) {
                for (const DspfFldInfo& f : rci->fields) {
                    emitIndent();
                    if ((f.dtype == 'A' || f.dtype == 'L' || f.dtype == 'T' || f.dtype == 'Z')) {
                        out_ << "strncpy(" << bufName << "." << f.name << ", "
                             << f.rpgName() << ".c_str(), " << f.len << "); "
                             << bufName << "." << f.name << "[" << f.len << "] = '\\0';\n";
                    } else {
                        out_ << bufName << "." << f.name << " = " << f.rpgName() << ";\n";
                    }
                }
            }
            emitIndent(); out_ << "dspf_set_indicators(rpg_indicators, 100);\n";
            emitIndent(); out_ << "dspf_write(\"" << node.filename << "\", &" << bufName << ");\n";
            uses_indicators_ = true;
            indent_--; emitIndent(); out_ << "}\n";
            return;
        }
    }

    // Program-described (O-spec) WRITE. Each field/constant's start
    // position is inferred as (previous field's end position + 1) on the
    // same record — i.e. O-spec fields must be listed in increasing,
    // contiguous end-position order (a documented simplification: real
    // DDS infers width from the field's own prior declared length, which
    // would need cross-referencing D-spec/I-spec declarations at O-spec
    // parse time; this compiler infers it from the gap between
    // successive end positions instead).
    {
        auto fout = flat_output_formats_.find(node.filename);
        if (fout != flat_output_formats_.end()) {
            int recLen = flat_record_len_.count(node.filename) ? flat_record_len_[node.filename] : 1;
            emitIndent(); out_ << "{\n"; indent_++;
            emitIndent(); out_ << "std::string __rec(" << recLen << ", ' ');\n";
            int prevEnd = 0;
            for (auto& f : fout->second->fields) {
                int width = f.endPos - prevEnd;
                if (width < 1) width = 1;
                std::string valueExpr;
                if (!f.fieldName.empty()) {
                    if (f.editCode != '\0') {
                        valueExpr = "rpg_editc(" + f.fieldName + ", \"" + std::string(1, f.editCode) + "\")";
                    } else if (var_types_.count(f.fieldName) && typeToString(var_types_[f.fieldName]) == "std::string") {
                        valueExpr = f.fieldName;
                    } else {
                        valueExpr = "rpg_flatfile_format_numeric(static_cast<double>(" + f.fieldName +
                                     "), " + std::to_string(width) + ", 0)";
                    }
                } else {
                    valueExpr = "std::string(\"" + cppEscape(f.constant) + "\")";
                }
                emitIndent();
                out_ << "{ std::string __v = " << valueExpr << "; "
                     << "if ((int)__v.size() > " << width << ") __v.resize(" << width << "); "
                     << "else if ((int)__v.size() < " << width << ") __v.resize(" << width << ", ' '); "
                     << "__rec.replace(" << prevEnd << ", " << width << ", __v); }\n";
                prevEnd = f.endPos;
            }
            emitIndent(); out_ << node.filename << "_ff.writeRecord(__rec);\n";
            for (auto& f : fout->second->fields) {
                if (f.blankAfter && !f.fieldName.empty()) {
                    emitIndent();
                    if (var_types_.count(f.fieldName) && typeToString(var_types_[f.fieldName]) == "std::string") {
                        out_ << f.fieldName << ".assign(" << f.fieldName << ".size(), ' ');\n";
                    } else {
                        out_ << f.fieldName << " = 0;\n";
                    }
                }
            }
            indent_--; emitIndent(); out_ << "}\n";
            return;
        }
    }

    // Disk / RLA WRITE
    auto it = ext_file_descs_.find(node.filename);
    if (it == ext_file_descs_.end()) {
        emitIndent(); out_ << "// WRITE " << node.filename << " — no schema\n"; return;
    }
    auto* dclf = file_defs_.count(node.filename) ? file_defs_[node.filename] : nullptr;
    const ExternalFileDesc& desc = it->second;
    emitIndent(); out_ << "{\n"; indent_++;
    emitRlaFileOpen(node.filename, desc, dclf && dclf->keyed);
    emitIndent(); out_ << "__sql_env.clearParamBufs();\n";
    for (size_t i = 0; i < desc.fields.size(); i++) {
        std::string fvar = rlaFieldVar(node.filename, desc.fields[i].name);
        emitIndent(); out_ << "__sql_env.bindParam(" << node.filename << "_ins, "
                           << (i+1) << ", " << fvar << ");\n";
    }
    emitIndent(); out_ << "SQLExecute(" << node.filename << "_ins);\n";
    indent_--; emitIndent(); out_ << "}\n";
}

void CodeGen::visit(UpdateStmt& node) {
    // Check if this is an UPDATE to a WORKSTN (display file) subfile
    // record format. Unlike DISK/RLA UPDATE (which needs a key), this
    // targets whatever row READC most recently returned — dspf_update()
    // tracks that implicitly, matching real DDS's "current record"
    // semantics. No indicator/key handling needed: UPDATE is silent.
    {
        DclF* dclf = nullptr;
        std::string fname;
        for (auto& [fn, df] : file_defs_) {
            if (df->usage != "WORKSTN") continue;
            auto dit = dspf_descs_.find(fn);
            if (dit == dspf_descs_.end()) continue;
            if (dit->second.recIdx.count(node.filename)) { dclf = df; fname = fn; break; }
        }
        if (dclf) {
            const DspfFileInfo* dfi = dspf_descs_.count(fname) ? &dspf_descs_[fname] : nullptr;
            const DspfRecInfo*  rci = nullptr;
            if (dfi) {
                auto rit = dfi->recIdx.find(node.filename);
                if (rit != dfi->recIdx.end()) rci = &dfi->records[rit->second];
            }
            std::string bufName = node.filename + "_buf_";
            emitIndent(); out_ << "{\n"; indent_++;
            if (rci) {
                for (const DspfFldInfo& f : rci->fields) {
                    emitIndent();
                    if ((f.dtype == 'A' || f.dtype == 'L' || f.dtype == 'T' || f.dtype == 'Z')) {
                        out_ << "strncpy(" << bufName << "." << f.name << ", "
                             << f.rpgName() << ".c_str(), " << f.len << "); "
                             << bufName << "." << f.name << "[" << f.len << "] = '\\0';\n";
                    } else {
                        out_ << bufName << "." << f.name << " = " << f.rpgName() << ";\n";
                    }
                }
            }
            emitIndent(); out_ << "dspf_set_indicators(rpg_indicators, 100);\n";
            emitIndent(); out_ << "dspf_update(\"" << node.filename << "\", &" << bufName << ");\n";
            indent_--; emitIndent(); out_ << "}\n";
            return;
        }
    }

    // Program-described (I-spec) UPDATE — rewrites the last-read record
    // with the current flat-field values, using the union of all record
    // formats' field layouts (a single-record-type file, the common
    // case, is handled exactly; a multi-record-type file assumes fields
    // from every format can coexist in one rewritten buffer).
    {
        auto fin = flat_input_formats_.find(node.filename);
        if (fin != flat_input_formats_.end()) {
            int recLen = flat_record_len_.count(node.filename) ? flat_record_len_[node.filename] : 1;
            emitIndent(); out_ << "{\n"; indent_++;
            emitIndent(); out_ << "std::string __rec(" << recLen << ", ' ');\n";
            for (auto* rf : fin->second) {
                for (auto& f : rf->fields) {
                    int width = f.toPos - f.fromPos + 1;
                    std::string cpptype = typeToString(f.type);
                    std::string valueExpr = (cpptype == "std::string") ? f.name
                        : ("rpg_flatfile_format_numeric(static_cast<double>(" + f.name + "), " +
                           std::to_string(width) + ", " + std::to_string(f.decimals) + ")");
                    emitIndent();
                    out_ << "{ std::string __v = " << valueExpr << "; "
                         << "if ((int)__v.size() > " << width << ") __v.resize(" << width << "); "
                         << "else if ((int)__v.size() < " << width << ") __v.resize(" << width << ", ' '); "
                         << "__rec.replace(" << (f.fromPos - 1) << ", " << width << ", __v); }\n";
                }
            }
            emitIndent(); out_ << node.filename << "_ff.updateLast(__rec);\n";
            indent_--; emitIndent(); out_ << "}\n";
            return;
        }
    }

    // Disk / RLA UPDATE
    auto it = ext_file_descs_.find(node.filename);
    if (it == ext_file_descs_.end()) {
        emitIndent(); out_ << "// UPDATE " << node.filename << " — no schema\n"; return;
    }
    auto* dclf = file_defs_.count(node.filename) ? file_defs_[node.filename] : nullptr;
    const ExternalFileDesc& desc = it->second;
    emitIndent(); out_ << "{\n"; indent_++;
    emitRlaFileOpen(node.filename, desc, dclf && dclf->keyed);
    if (desc.fields.size() < 2) {
        emitIndent(); out_ << "// UPDATE: need at least 2 fields (key + data)\n";
        indent_--; emitIndent(); out_ << "}\n"; return;
    }
    emitIndent(); out_ << "__sql_env.clearParamBufs();\n";
    // Bind non-key fields first, then key last
    for (size_t i = 1; i < desc.fields.size(); i++) {
        std::string fvar = rlaFieldVar(node.filename, desc.fields[i].name);
        emitIndent(); out_ << "__sql_env.bindParam(" << node.filename << "_upd, "
                           << i << ", " << fvar << ");\n";
    }
    // Key field last
    std::string keyFvar = rlaFieldVar(node.filename, desc.fields[0].name);
    emitIndent(); out_ << "__sql_env.bindParam(" << node.filename << "_upd, "
                       << desc.fields.size() << ", " << keyFvar << ");\n";
    emitIndent(); out_ << "SQLExecute(" << node.filename << "_upd);\n";
    indent_--; emitIndent(); out_ << "}\n";
    (void)dclf;
}

void CodeGen::visit(DeleteStmt& node) {
    auto it = ext_file_descs_.find(node.filename);
    if (it == ext_file_descs_.end()) {
        emitIndent(); out_ << "// DELETE " << node.filename << " — no schema\n"; return;
    }
    auto* dclf = file_defs_.count(node.filename) ? file_defs_[node.filename] : nullptr;
    const ExternalFileDesc& desc = it->second;
    emitIndent(); out_ << "{\n"; indent_++;
    emitRlaFileOpen(node.filename, desc, dclf && dclf->keyed);
    emitIndent(); out_ << "__sql_env.clearParamBufs();\n";
    if (!desc.fields.empty()) {
        std::string keyFvar = rlaFieldVar(node.filename, desc.fields[0].name);
        emitIndent(); out_ << "__sql_env.bindParam(" << node.filename << "_del, 1, "
                           << keyFvar << ");\n";
    }
    emitIndent(); out_ << "SQLExecute(" << node.filename << "_del);\n";
    indent_--; emitIndent(); out_ << "}\n";
    (void)dclf;
}

void CodeGen::visit(SetllStmt& node) {
    auto it = ext_file_descs_.find(node.filename);
    if (it == ext_file_descs_.end()) {
        emitIndent(); out_ << "// SETLL " << node.filename << " — no schema\n"; return;
    }
    auto* dclf = file_defs_.count(node.filename) ? file_defs_[node.filename] : nullptr;
    const ExternalFileDesc& desc = it->second;
    std::string keyExpr = node.keys.empty() ? "" : emitExpr(*node.keys[0]);
    std::string keyCol = desc.fields.empty() ? "1" : desc.fields[0].name;
    std::string cols = rlaColumnList(desc);
    std::string tbl  = desc.tableName;
    emitIndent(); out_ << "{\n"; indent_++;
    emitRlaFileOpen(node.filename, desc, dclf && dclf->keyed);
    // Close + re-prepare scroll cursor with WHERE key >= ?
    emitIndent(); out_ << "SQLFreeStmt(" << node.filename << "_scroll, SQL_CLOSE);\n";
    std::string sql = "SELECT " + cols + " FROM " + tbl + " WHERE " + keyCol + ">=? ORDER BY " + keyCol;
    emitIndent(); out_ << "SQLPrepare(" << node.filename << "_scroll, (SQLCHAR*)\"" << sql << "\", SQL_NTS);\n";
    if (!keyExpr.empty()) {
        emitIndent(); out_ << "__sql_env.clearParamBufs();\n";
        emitIndent(); out_ << "__sql_env.bindParam(" << node.filename << "_scroll, 1, " << keyExpr << ");\n";
    }
    emitIndent(); out_ << "SQLExecute(" << node.filename << "_scroll);\n";
    emitIndent(); out_ << node.filename << "_eof   = false;\n";
    emitIndent(); out_ << node.filename << "_found = false;\n";
    indent_--; emitIndent(); out_ << "}\n";
    (void)dclf;
}

void CodeGen::visit(SetgtStmt& node) {
    auto it = ext_file_descs_.find(node.filename);
    if (it == ext_file_descs_.end()) {
        emitIndent(); out_ << "// SETGT " << node.filename << " — no schema\n"; return;
    }
    auto* dclf = file_defs_.count(node.filename) ? file_defs_[node.filename] : nullptr;
    const ExternalFileDesc& desc = it->second;
    std::string keyExpr = node.keys.empty() ? "" : emitExpr(*node.keys[0]);
    std::string keyCol = desc.fields.empty() ? "1" : desc.fields[0].name;
    std::string cols = rlaColumnList(desc);
    std::string tbl  = desc.tableName;
    emitIndent(); out_ << "{\n"; indent_++;
    emitRlaFileOpen(node.filename, desc, dclf && dclf->keyed);
    // Close + re-prepare scroll cursor with WHERE key > ?
    emitIndent(); out_ << "SQLFreeStmt(" << node.filename << "_scroll, SQL_CLOSE);\n";
    std::string sql = "SELECT " + cols + " FROM " + tbl + " WHERE " + keyCol + ">? ORDER BY " + keyCol;
    emitIndent(); out_ << "SQLPrepare(" << node.filename << "_scroll, (SQLCHAR*)\"" << sql << "\", SQL_NTS);\n";
    if (!keyExpr.empty()) {
        emitIndent(); out_ << "__sql_env.clearParamBufs();\n";
        emitIndent(); out_ << "__sql_env.bindParam(" << node.filename << "_scroll, 1, " << keyExpr << ");\n";
    }
    emitIndent(); out_ << "SQLExecute(" << node.filename << "_scroll);\n";
    emitIndent(); out_ << node.filename << "_eof   = false;\n";
    emitIndent(); out_ << node.filename << "_found = false;\n";
    indent_--; emitIndent(); out_ << "}\n";
    (void)dclf;
}

// ---------------------------------------------------------------------------
// EXFMT — display file write+read
// ---------------------------------------------------------------------------
void CodeGen::visit(ExfmtStmt& node) {
    // Resolve which DCL-F this EXFMT belongs to.
    // The format name may equal the file name (single-record files) or differ.
    DclF* dclf = nullptr;
    std::string fname;
    if (file_defs_.count(node.filename) && file_defs_[node.filename]->usage == "WORKSTN") {
        dclf = file_defs_[node.filename]; fname = node.filename;
    } else if (file_defs_.count(node.format) && file_defs_[node.format]->usage == "WORKSTN") {
        dclf = file_defs_[node.format]; fname = node.format;
    } else {
        // Search: find a WORKSTN file that has this record format
        for (auto& [fn, df] : file_defs_) {
            if (df->usage != "WORKSTN") continue;
            auto dit = dspf_descs_.find(fn);
            if (dit == dspf_descs_.end()) continue;
            if (dit->second.recIdx.count(node.format)) { dclf = df; fname = fn; break; }
        }
    }
    if (!dclf) {
        emitIndent();
        out_ << "// EXFMT " << node.format << " — WORKSTN file not declared\n";
        return;
    }

    // Get descriptor for the specific record format
    const DspfFileInfo* dfi = dspf_descs_.count(fname) ? &dspf_descs_[fname] : nullptr;
    const DspfRecInfo*  rci = nullptr;
    if (dfi) {
        auto rit = dfi->recIdx.find(node.format);
        if (rit != dfi->recIdx.end()) rci = &dfi->records[rit->second];
    }

    std::string bufName = node.format + "_buf_";
    std::string recBuf  = node.format + "_buf";

    emitIndent(); out_ << "{\n"; indent_++;

    // Copy flat RPG variables → buffer struct (output, both, and hidden
    // fields — hidden still carries a real value, just isn't rendered)
    if (rci) {
        for (const DspfFldInfo& f : rci->fields) {
            emitIndent();
            if ((f.dtype == 'A' || f.dtype == 'L' || f.dtype == 'T' || f.dtype == 'Z')) {
                // string → char buf
                out_ << "strncpy(" << bufName << "." << f.name << ", "
                     << f.rpgName() << ".c_str(), " << f.len << "); "
                     << bufName << "." << f.name << "[" << f.len << "] = '\\0';\n";
            } else if (f.dtype == 'B') {
                out_ << bufName << "." << f.name << " = " << f.rpgName() << ";\n";
            } else {
                out_ << bufName << "." << f.name << " = " << f.rpgName() << ";\n";
            }
        }
    }

    // Pass current indicators then call dspf_exfmt
    emitIndent(); out_ << "dspf_set_indicators(rpg_indicators, 100);\n";
    emitIndent(); out_ << "int __dspf_key = dspf_exfmt(\""
                       << node.format << "\", &" << bufName << ");\n";

    // Copy buffer struct → flat RPG variables (input, both, and hidden
    // fields — e.g. SFLRCDNBR HIDDEN needs to be readable after EXFMT)
    if (rci) {
        for (const DspfFldInfo& f : rci->fields) {
            if (f.io == 'O') continue; // only copy back input/both/hidden
            emitIndent();
            if ((f.dtype == 'A' || f.dtype == 'L' || f.dtype == 'T' || f.dtype == 'Z')) {
                out_ << f.rpgName() << " = std::string(" << bufName << "." << f.name
                     << ", strnlen(" << bufName << "." << f.name << ", " << f.len << "));\n";
            } else if (f.dtype == 'B') {
                out_ << f.rpgName() << " = " << bufName << "." << f.name << ";\n";
            } else {
                out_ << f.rpgName() << " = " << bufName << "." << f.name << ";\n";
            }
        }
    }

    // Clear F-key indicators 01-24, then set the returned one
    emitIndent(); out_ << "for (int __i = 1; __i <= 24; ++__i) rpg_indicators[__i] = false;\n";
    emitIndent(); out_ << "if (__dspf_key >= 1 && __dspf_key <= 99) "
                       << "rpg_indicators[__dspf_key] = true;\n";
    // CHANGE/BLANKS response indicators — can land anywhere in 1-99, so
    // applied after the block above rather than folded into it.
    emitIndent(); out_ << "dspf_apply_out_indicators(rpg_indicators, 100);\n";
    uses_indicators_ = true;

    indent_--; emitIndent(); out_ << "}\n";
}

} // namespace rpg
