#ifndef RPG_SQL_RUNTIME_H
#define RPG_SQL_RUNTIME_H

// ODBC SQL runtime support for RPG-generated C++ programs
// Only included when the RPG source contains EXEC SQL statements

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#endif
#include <sql.h>
#include <sqlext.h>
#include <cstring>
#include <iostream>
#include <map>
#include <stdexcept>
#include <deque>
#include <string>
#include <vector>

class RpgSqlEnv {
public:
    SQLHENV henv = SQL_NULL_HENV;
    SQLHDBC hdbc = SQL_NULL_HDBC;
    int sqlcode = 0;
    std::string sqlstate = "00000";
    SQLLEN row_count = 0; // last statement's row count (for GET DIAGNOSTICS)
    bool isConnected_ = false;

    // Named cursors: cursor name → statement handle
    std::map<std::string, SQLHSTMT> cursors;

    // Named prepared statements: stmt name → statement handle
    std::map<std::string, SQLHSTMT> prepared;

    RpgSqlEnv() {
        SQLAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE, &henv);
        SQLSetEnvAttr(henv, SQL_ATTR_ODBC_VERSION, (void*)SQL_OV_ODBC3, 0);
        SQLAllocHandle(SQL_HANDLE_DBC, henv, &hdbc);
    }

    ~RpgSqlEnv() {
        for (auto& [name, hstmt] : cursors) {
            SQLFreeHandle(SQL_HANDLE_STMT, hstmt);
        }
        for (auto& [name, hstmt] : prepared) {
            if (cursors.find(name) == cursors.end()) {
                SQLFreeHandle(SQL_HANDLE_STMT, hstmt);
            }
        }
        if (hdbc != SQL_NULL_HDBC) {
            SQLDisconnect(hdbc);
            SQLFreeHandle(SQL_HANDLE_DBC, hdbc);
        }
        if (henv != SQL_NULL_HENV) {
            SQLFreeHandle(SQL_HANDLE_ENV, henv);
        }
    }

    // Connect using DSN
    void connect(const std::string& dsn,
                 const std::string& user = "",
                 const std::string& password = "") {
        if (isConnected_) { SQLDisconnect(hdbc); isConnected_ = false; }
        SQLRETURN rc = SQLConnect(hdbc,
            (SQLCHAR*)dsn.c_str(), SQL_NTS,
            user.empty() ? nullptr : (SQLCHAR*)user.c_str(), SQL_NTS,
            password.empty() ? nullptr : (SQLCHAR*)password.c_str(), SQL_NTS);
        updateDiag(SQL_HANDLE_DBC, hdbc, rc);
        if (rc == SQL_SUCCESS || rc == SQL_SUCCESS_WITH_INFO) isConnected_ = true;
    }

    // Connect using connection string
    void connectStr(const std::string& connStr) {
        if (isConnected_) {
            SQLDisconnect(hdbc);
            isConnected_ = false;
        }
        SQLCHAR outConn[1024];
        SQLSMALLINT outLen;
        SQLRETURN rc = SQLDriverConnect(hdbc, nullptr,
            (SQLCHAR*)connStr.c_str(), SQL_NTS,
            outConn, sizeof(outConn), &outLen,
            SQL_DRIVER_NOPROMPT);
        updateDiag(SQL_HANDLE_DBC, hdbc, rc);
        if (rc == SQL_SUCCESS || rc == SQL_SUCCESS_WITH_INFO) isConnected_ = true;
    }

    void disconnect() {
        if (!isConnected_) return;
        SQLRETURN rc = SQLDisconnect(hdbc);
        updateDiag(SQL_HANDLE_DBC, hdbc, rc);
        isConnected_ = false;
    }

    // Allocate a new statement handle
    SQLHSTMT allocStmt() {
        SQLHSTMT hstmt = SQL_NULL_HSTMT;
        SQLAllocHandle(SQL_HANDLE_STMT, hdbc, &hstmt);
        return hstmt;
    }

    // Execute SQL directly (no parameters)
    void execDirect(const std::string& sql) {
        SQLHSTMT hstmt = allocStmt();
        SQLRETURN rc = SQLExecDirect(hstmt, (SQLCHAR*)sql.c_str(), SQL_NTS);
        updateDiag(SQL_HANDLE_STMT, hstmt, rc);
        if (rc == SQL_SUCCESS || rc == SQL_SUCCESS_WITH_INFO) {
            SQLRowCount(hstmt, &row_count);
        }
        SQLFreeHandle(SQL_HANDLE_STMT, hstmt);
    }

    // Commit / Rollback
    void commit() {
        SQLRETURN rc = SQLEndTran(SQL_HANDLE_DBC, hdbc, SQL_COMMIT);
        updateDiag(SQL_HANDLE_DBC, hdbc, rc);
    }

    void rollback() {
        SQLRETURN rc = SQLEndTran(SQL_HANDLE_DBC, hdbc, SQL_ROLLBACK);
        updateDiag(SQL_HANDLE_DBC, hdbc, rc);
    }

    // Declare a cursor (allocate stmt handle, prepare SQL)
    void declareCursor(const std::string& name, const std::string& sql) {
        SQLHSTMT hstmt = allocStmt();
        SQLRETURN rc = SQLPrepare(hstmt, (SQLCHAR*)sql.c_str(), SQL_NTS);
        updateDiag(SQL_HANDLE_STMT, hstmt, rc);
        cursors[name] = hstmt;
    }

    // Open a cursor (execute the prepared statement)
    void openCursor(const std::string& name) {
        auto it = cursors.find(name);
        if (it == cursors.end()) {
            sqlcode = -1;
            sqlstate = "24000";
            return;
        }
        SQLRETURN rc = SQLExecute(it->second);
        updateDiag(SQL_HANDLE_STMT, it->second, rc);
    }

    // Fetch from a cursor
    bool fetchCursor(const std::string& name) {
        auto it = cursors.find(name);
        if (it == cursors.end()) {
            sqlcode = -1;
            sqlstate = "24000";
            return false;
        }
        SQLRETURN rc = SQLFetch(it->second);
        updateDiag(SQL_HANDLE_STMT, it->second, rc);
        return (rc == SQL_SUCCESS || rc == SQL_SUCCESS_WITH_INFO);
    }

    // Close a cursor
    void closeCursor(const std::string& name) {
        auto it = cursors.find(name);
        if (it == cursors.end()) {
            sqlcode = -1;
            sqlstate = "24000";
            return;
        }
        SQLRETURN rc = SQLFreeStmt(it->second, SQL_CLOSE);
        updateDiag(SQL_HANDLE_STMT, it->second, rc);
    }

    // Get cursor statement handle (for binding columns)
    SQLHSTMT getCursorStmt(const std::string& name) {
        auto it = cursors.find(name);
        return (it != cursors.end()) ? it->second : SQL_NULL_HSTMT;
    }

    // Prepare a named statement
    void prepareStmt(const std::string& name, const std::string& sql) {
        SQLHSTMT hstmt = allocStmt();
        SQLRETURN rc = SQLPrepare(hstmt, (SQLCHAR*)sql.c_str(), SQL_NTS);
        updateDiag(SQL_HANDLE_STMT, hstmt, rc);
        prepared[name] = hstmt;
    }

    // Execute a named prepared statement
    void executeStmt(const std::string& name) {
        auto it = prepared.find(name);
        if (it == prepared.end()) {
            sqlcode = -1;
            sqlstate = "07003";
            return;
        }
        SQLRETURN rc = SQLExecute(it->second);
        updateDiag(SQL_HANDLE_STMT, it->second, rc);
    }

    // Get prepared statement handle (for binding parameters)
    SQLHSTMT getPreparedStmt(const std::string& name) {
        auto it = prepared.find(name);
        return (it != prepared.end()) ? it->second : SQL_NULL_HSTMT;
    }

    // Get row count from last statement
    SQLLEN getRowCount(SQLHSTMT hstmt) {
        SQLLEN count = 0;
        SQLRowCount(hstmt, &count);
        return count;
    }

    // Update diagnostics from a statement handle after execute/fetch
    void updateStmtDiag(SQLHSTMT hstmt, SQLRETURN rc) {
        updateDiag(SQL_HANDLE_STMT, hstmt, rc);
        if (rc == SQL_SUCCESS || rc == SQL_SUCCESS_WITH_INFO) {
            SQLRowCount(hstmt, &row_count);
        }
    }

    // Type-dispatched parameter binding (template enables if constexpr)
    template<typename T>
    void bindParam(SQLHSTMT hstmt, int idx, T& val) {
        if constexpr (std::is_same_v<std::decay_t<T>, std::string>) {
            // Bound without trailing blanks. A CHAR(n) field always holds n
            // bytes, so a key of 'C002' arrives as 'C002      '. DB2 on
            // IBM i compares character values blank-padded, so that still
            // matches a stored 'C002'; SQLite and most ODBC targets compare
            // exactly, and it would not. Trimming gives DB2's result on a
            // database that doesn't pad. The cost: a VARCHAR host variable
            // that deliberately ends in blanks loses them.
            param_bufs_.push_back(val);
            auto& buf = param_bufs_.back();
            while (!buf.empty() && buf.back() == ' ') buf.pop_back();
            SQLBindParameter(hstmt, idx, SQL_PARAM_INPUT, SQL_C_CHAR, SQL_VARCHAR,
                             buf.size(), 0, (SQLCHAR*)buf.c_str(), buf.size() + 1, nullptr);
        } else if constexpr (std::is_integral_v<std::decay_t<T>>) {
            param_int_bufs_.push_back(static_cast<SQLINTEGER>(val));
            SQLBindParameter(hstmt, idx, SQL_PARAM_INPUT, SQL_C_SLONG, SQL_INTEGER,
                             0, 0, &param_int_bufs_.back(), 0, nullptr);
        } else {
            param_dbl_bufs_.push_back(static_cast<SQLDOUBLE>(val));
            SQLBindParameter(hstmt, idx, SQL_PARAM_INPUT, SQL_C_DOUBLE, SQL_DOUBLE,
                             0, 0, &param_dbl_bufs_.back(), 0, nullptr);
        }
    }

    // Type-dispatched column binding for SELECT INTO
    // strbuf must be a char array that outlives the fetch call
    template<typename T>
    void bindCol(SQLHSTMT hstmt, int idx, T& val, char* strbuf, SQLLEN strbufSize, SQLLEN& ind) {
        if constexpr (std::is_same_v<std::decay_t<T>, std::string>) {
            SQLBindCol(hstmt, idx, SQL_C_CHAR, strbuf, strbufSize, &ind);
        } else if constexpr (std::is_integral_v<std::decay_t<T>>) {
            SQLBindCol(hstmt, idx, SQL_C_SLONG, &val, 0, &ind);
        } else {
            SQLBindCol(hstmt, idx, SQL_C_DOUBLE, &val, 0, &ind);
        }
    }

    // Copy string buffer back to variable after fetch (no-op for non-string types)
    template<typename T>
    static void copyStrBuf(T& val, const char* strbuf, SQLRETURN frc) {
        if constexpr (std::is_same_v<std::decay_t<T>, std::string>) {
            if (frc == SQL_SUCCESS || frc == SQL_SUCCESS_WITH_INFO)
                val = std::string(strbuf);
        }
    }

    // Bind a parameter with an SQL indicator variable (ind < 0 → SQL NULL)
    template<typename T>
    void bindParamWithInd(SQLHSTMT hstmt, int idx, T& val, int ind_val) {
        if (ind_val < 0) {
            null_ind_bufs_.push_back(SQL_NULL_DATA);
            SQLBindParameter(hstmt, idx, SQL_PARAM_INPUT, SQL_C_CHAR, SQL_VARCHAR,
                             0, 0, nullptr, 0, &null_ind_bufs_.back());
        } else {
            bindParam(hstmt, idx, val);
        }
    }

    // Clear parameter buffers (call before binding a new statement)
    void clearParamBufs() {
        param_bufs_.clear();
        param_int_bufs_.clear();
        param_dbl_bufs_.clear();
        null_ind_bufs_.clear();
    }

    // Parameter buffers (persist until next statement execution)
    // Using deque to avoid pointer invalidation on push_back (vector reallocates)
    std::deque<std::string> param_bufs_;
    std::deque<SQLINTEGER> param_int_bufs_;
    std::deque<SQLDOUBLE> param_dbl_bufs_;
    std::deque<SQLLEN> null_ind_bufs_;

private:
    void updateDiag(SQLSMALLINT handleType, SQLHANDLE handle, SQLRETURN rc) {
        if (rc == SQL_SUCCESS) {
            sqlcode = 0;
            sqlstate = "00000";
            return;
        }
        if (rc == SQL_NO_DATA) {
            sqlcode = 100;
            sqlstate = "02000";
            return;
        }
        SQLCHAR state[6] = {};
        SQLINTEGER nativeError = 0;
        SQLCHAR msg[512] = {};
        SQLSMALLINT msgLen = 0;
        if (SQLGetDiagRec(handleType, handle, 1, state, &nativeError,
                          msg, sizeof(msg), &msgLen) == SQL_SUCCESS) {
            sqlstate = std::string((char*)state, 5);
            sqlcode = (rc == SQL_SUCCESS_WITH_INFO) ? 0 : -static_cast<int>(nativeError);
            if (sqlcode == 0 && rc != SQL_SUCCESS && rc != SQL_SUCCESS_WITH_INFO) {
                sqlcode = -1;
            }
        } else {
            sqlcode = (rc == SQL_SUCCESS_WITH_INFO) ? 0 : -1;
            sqlstate = "HY000";
        }
    }
};

#endif // RPG_SQL_RUNTIME_H
