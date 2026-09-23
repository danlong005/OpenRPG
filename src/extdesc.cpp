#include "extdesc.h"
#include <algorithm>
#include <cctype>
#include <cstring>
#include <fstream>
#include <iostream>
#include <sstream>

// ODBC headers — only included when building extdesc
#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#endif
#include <sql.h>
#include <sqlext.h>

static std::string toUpper(std::string s) {
    for (auto& c : s) c = static_cast<char>(toupper(static_cast<unsigned char>(c)));
    return s;
}

static std::string toLower(std::string s) {
    for (auto& c : s) c = static_cast<char>(tolower(static_cast<unsigned char>(c)));
    return s;
}

static std::string trim(const std::string& s) {
    size_t a = s.find_first_not_of(" \t\r\n");
    size_t b = s.find_last_not_of(" \t\r\n");
    return (a == std::string::npos) ? "" : s.substr(a, b - a + 1);
}

// Map ODBC SQL type → ExtField cppType / bindKind
static void mapSqlType(SQLSMALLINT sqlType, SQLULEN colSize, SQLSMALLINT decDigits,
                        ExtField& f) {
    switch (sqlType) {
        case SQL_CHAR:
        case SQL_WCHAR:
            f.cppType  = "std::string";
            f.bindKind = "str";
            f.kind     = "char";
            f.length   = static_cast<int>(colSize);
            break;
        case SQL_VARCHAR:
        case SQL_LONGVARCHAR:
        case SQL_WVARCHAR:
            f.cppType  = "std::string";
            f.bindKind = "str";
            f.kind     = "varchar";
            f.length   = static_cast<int>(colSize);
            break;
        case SQL_SMALLINT:
        case SQL_INTEGER:
        case SQL_TINYINT:
        case SQL_BIGINT:
            f.cppType  = "long";
            f.bindKind = "int";
            f.kind     = "int";
            f.length   = static_cast<int>(colSize);
            break;
        case SQL_NUMERIC:
        case SQL_DECIMAL:
            f.cppType  = "double";
            f.bindKind = "dbl";
            f.kind     = "decimal";
            f.length   = static_cast<int>(colSize);
            f.decimals = static_cast<int>(decDigits);
            break;
        case SQL_FLOAT:
        case SQL_REAL:
        case SQL_DOUBLE:
            // Binary floating point has no scale to truncate to; whatever
            // DECIMAL_DIGITS the driver reports for it is not one.
            f.cppType  = "double";
            f.bindKind = "dbl";
            f.kind     = "float";
            f.length   = static_cast<int>(colSize);
            f.decimals = static_cast<int>(decDigits);
            break;
        case SQL_TYPE_DATE:
        case SQL_TYPE_TIME:
        case SQL_TYPE_TIMESTAMP:
            f.cppType  = "std::string";
            f.bindKind = "str";
            f.kind     = "datetime";
            f.length   = 26;
            break;
        default:
            f.cppType  = "std::string";
            f.bindKind = "str";
            f.length   = static_cast<int>(colSize ? colSize : 256);
            break;
    }
}

// Correct the mapping from the column's declared type name where the
// driver's DATA_TYPE is less specific than the column. SQLite's ODBC driver
// is the case in point: SQLite has no fixed-length character type, so it
// reports CHAR(6) as SQL_VARCHAR, and it reports DECIMAL(7,2) as a 2-byte
// string. TYPE_NAME still carries the declaration ("CHAR(6)",
// "DECIMAL(7,2)"), and on a driver that reports types exactly (DB2 on IBM
// i) this agrees with DATA_TYPE and changes nothing.
static void refineFromTypeName(const std::string& typeName, ExtField& f) {
    std::string t = toUpper(trim(typeName));
    auto args = [&](int& a, int& b) {
        a = b = -1;
        size_t lp = t.find('('), rp = t.find(')');
        if (lp == std::string::npos || rp == std::string::npos || rp < lp) return;
        std::string in = t.substr(lp + 1, rp - lp - 1);
        size_t comma = in.find(',');
        try {
            a = std::stoi(in.substr(0, comma));
            if (comma != std::string::npos) b = std::stoi(in.substr(comma + 1));
        } catch (...) { a = b = -1; }
    };
    auto startsWord = [&](const char* w) {
        size_t n = strlen(w);
        return t.compare(0, n, w) == 0 && (t.size() == n || t[n] == '(' || t[n] == ' ');
    };
    int a, b;
    if (startsWord("CHAR") || startsWord("CHARACTER") || startsWord("NCHAR")) {
        f.cppType = "std::string"; f.bindKind = "str"; f.kind = "char";
        args(a, b); if (a > 0) f.length = a;
    } else if (startsWord("VARCHAR") || startsWord("NVARCHAR") || startsWord("CHARACTER VARYING")) {
        f.cppType = "std::string"; f.bindKind = "str"; f.kind = "varchar";
        args(a, b); if (a > 0) f.length = a;
    } else if (startsWord("DECIMAL") || startsWord("NUMERIC") || startsWord("DEC")) {
        f.cppType = "double"; f.bindKind = "dbl"; f.kind = "decimal";
        args(a, b);
        if (a > 0) f.length = a;
        f.decimals = (b >= 0) ? b : (a > 0 ? 0 : f.decimals);
    }
}

// Write .extdesc cache file
static void writeCache(const std::string& path, const ExternalFileDesc& desc) {
    std::ofstream f(path);
    if (!f.is_open()) return;
    f << "# auto-generated by rpgc — safe to commit\n";
    f << "table=" << desc.tableName << "\n";
    for (auto& fld : desc.fields) {
        f << fld.name << " " << fld.cppType;
        if (fld.length > 0) f << "(" << fld.length;
        if (fld.decimals > 0) f << ":" << fld.decimals;
        if (fld.length > 0) f << ")";
        f << " " << fld.bindKind;
        if (!fld.kind.empty()) f << " " << fld.kind;
        f << "\n";
    }
}

// Read .extdesc cache file
static bool readCache(const std::string& path, ExternalFileDesc& desc) {
    std::ifstream f(path);
    if (!f.is_open()) return false;
    std::string line;
    while (std::getline(f, line)) {
        if (line.empty() || line[0] == '#') continue;
        if (line.substr(0, 6) == "table=") {
            desc.tableName = trim(line.substr(6));
            continue;
        }
        // field line: NAME cpptype(len:dec) bindkind
        std::istringstream ss(line);
        ExtField ef;
        std::string typestr, bindkind;
        ss >> ef.name >> typestr >> bindkind >> ef.kind;
        if (ef.name.empty() || typestr.empty()) continue;
        // parse cpptype and optional (len:dec)
        auto paren = typestr.find('(');
        if (paren != std::string::npos) {
            std::string inner = typestr.substr(paren + 1);
            if (!inner.empty() && inner.back() == ')') inner.pop_back();
            typestr = typestr.substr(0, paren);
            auto colon = inner.find(':');
            if (colon != std::string::npos) {
                ef.length   = std::stoi(inner.substr(0, colon));
                ef.decimals = std::stoi(inner.substr(colon + 1));
            } else {
                ef.length = std::stoi(inner);
            }
        }
        ef.cppType  = typestr;
        ef.bindKind = bindkind.empty() ? "str" : bindkind;
        desc.fields.push_back(ef);
    }
    return !desc.fields.empty() || !desc.tableName.empty();
}

// Query ODBC for one table's columns
static bool queryODBC(SQLHDBC hdbc, const std::string& tableName, ExternalFileDesc& desc) {
    SQLHSTMT hstmt = SQL_NULL_HSTMT;
    if (SQLAllocHandle(SQL_HANDLE_STMT, hdbc, &hstmt) != SQL_SUCCESS) return false;

    // SQLColumns: catalog=NULL, schema=NULL, table=tableName, column=NULL
    SQLRETURN rc = SQLColumns(hstmt,
        nullptr, 0,
        nullptr, 0,
        (SQLCHAR*)tableName.c_str(), SQL_NTS,
        nullptr, 0);

    if (rc != SQL_SUCCESS && rc != SQL_SUCCESS_WITH_INFO) {
        SQLFreeHandle(SQL_HANDLE_STMT, hstmt);
        return false;
    }

    // Bind result columns we care about: col 4 = COLUMN_NAME, 5 = DATA_TYPE,
    // 6 = TYPE_NAME, 7 = COLUMN_SIZE, 9 = DECIMAL_DIGITS
    char colName[256] = {};
    SQLSMALLINT dataType = 0;
    SQLULEN colSize = 0;
    SQLSMALLINT decDigits = 0;
    SQLLEN indName = 0, indType = 0, indSize = 0, indDec = 0;

    char typeName[128] = {};
    SQLLEN indTypeName = 0;
    SQLBindCol(hstmt, 4, SQL_C_CHAR,   colName,   sizeof(colName), &indName);
    SQLBindCol(hstmt, 6, SQL_C_CHAR,   typeName,  sizeof(typeName), &indTypeName);
    SQLBindCol(hstmt, 5, SQL_C_SSHORT, &dataType, 0,               &indType);
    SQLBindCol(hstmt, 7, SQL_C_ULONG,  &colSize,  0,               &indSize);
    SQLBindCol(hstmt, 9, SQL_C_SSHORT, &decDigits,0,               &indDec);

    bool found = false;
    while ((rc = SQLFetch(hstmt)) == SQL_SUCCESS || rc == SQL_SUCCESS_WITH_INFO) {
        ExtField ef;
        ef.name = toUpper(std::string(colName, (indName > 0) ? (size_t)indName : strlen(colName)));
        mapSqlType(dataType, colSize, decDigits, ef);
        if (indTypeName > 0) refineFromTypeName(typeName, ef);
        desc.fields.push_back(ef);
        found = true;
    }

    SQLFreeHandle(SQL_HANDLE_STMT, hstmt);
    return found;
}

std::map<std::string, ExternalFileDesc>
queryExternalDescs(const std::vector<std::pair<std::string, std::string>>& diskFiles,
                   const std::string& src_dir,
                   const RpgConf& conf) {
    std::map<std::string, ExternalFileDesc> result;

    auto& files = diskFiles;
    if (files.empty()) return result;

    // Try to establish ODBC connection if conf has DSN
    SQLHENV henv = SQL_NULL_HENV;
    SQLHDBC hdbc = SQL_NULL_HDBC;
    bool connected = false;

    if (!conf.db_dsn.empty()) {
        SQLAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE, &henv);
        SQLSetEnvAttr(henv, SQL_ATTR_ODBC_VERSION, (void*)SQL_OV_ODBC3, 0);
        SQLAllocHandle(SQL_HANDLE_DBC, henv, &hdbc);
        SQLCHAR outConn[1024] = {};
        SQLSMALLINT outLen = 0;
        SQLRETURN rc = SQLDriverConnect(hdbc, nullptr,
            (SQLCHAR*)conf.db_dsn.c_str(), SQL_NTS,
            outConn, sizeof(outConn), &outLen,
            SQL_DRIVER_NOPROMPT);
        connected = (rc == SQL_SUCCESS || rc == SQL_SUCCESS_WITH_INFO);
    }

    std::string prefix = src_dir.empty() ? "" : src_dir + "/";

    for (auto& [rpgName, override_table] : files) {
        ExternalFileDesc desc;
        std::string tableName = override_table.empty() ? toLower(rpgName) : override_table;
        desc.tableName = tableName;

        std::string cachePath = prefix + rpgName + ".extdesc";

        if (connected) {
            // Try live query first
            if (queryODBC(hdbc, tableName, desc) && !desc.fields.empty()) {
                writeCache(cachePath, desc);
                result[rpgName] = desc;
                continue;
            }
        }

        // Fall back to cache
        ExternalFileDesc cached;
        if (readCache(cachePath, cached) && !cached.fields.empty()) {
            if (cached.tableName.empty()) cached.tableName = tableName;
            result[rpgName] = cached;
        } else if (!desc.fields.empty()) {
            result[rpgName] = desc;
        }
        // If neither DB nor cache has it, leave it out — codegen will emit a comment
    }

    if (connected) {
        SQLDisconnect(hdbc);
        SQLFreeHandle(SQL_HANDLE_DBC, hdbc);
        SQLFreeHandle(SQL_HANDLE_ENV, henv);
    }

    return result;
}
