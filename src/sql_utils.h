#ifndef SQL_UTILS_H
#define SQL_UTILS_H

#include <string>
#include <vector>
#include "ast.h"

namespace rpg {

// Host variable paired with its optional indicator variable
struct HostVarWithInd {
    std::string var;     // host variable name (uppercase, no colon)
    std::string ind_var; // indicator variable name (empty if none)
};

// Extract host variable names from SQL text (e.g., ":varName" → "VARNAME")
// Indicator variables (:var :ind syntax) are skipped — only value vars are returned.
std::vector<std::string> extractHostVariables(const std::string& sql);

// Replace :varName references with ? parameter markers
std::string replaceHostVarsWithMarkers(const std::string& sql);

// Strip the INTO :v1, :v2 clause from a SELECT statement
// Returns the SQL without the INTO clause and populates into_vars
std::string stripSelectInto(const std::string& sql, std::vector<std::string>& into_vars);

// Classify the SQL statement kind based on leading keyword
SqlStmtKind classifySqlStmt(const std::string& sql);

// Db2 for i requires "SAVEPOINT name [UNIQUE] ON ROLLBACK RETAIN CURSORS
// [ON ROLLBACK RETAIN LOCKS]"; SQLite and PostgreSQL accept only
// "SAVEPOINT name". Returns the portable form, or sql unchanged when it
// is not a SAVEPOINT statement.
std::string portableSavepoint(const std::string& sql);

// Extract cursor name from DECLARE/OPEN/FETCH/CLOSE statements
// e.g. "DECLARE C1 CURSOR FOR SELECT ..." → "C1"
std::string extractCursorName(const std::string& sql);

// Extract the SELECT query from a DECLARE CURSOR statement
// e.g. "DECLARE C1 CURSOR FOR SELECT * FROM tbl" → "SELECT * FROM tbl"
std::string extractCursorQuery(const std::string& sql);

// Extract INTO variables from a FETCH statement
// e.g. "FETCH C1 INTO :name, :age" → {"NAME", "AGE"}
std::vector<std::string> extractFetchIntoVars(const std::string& sql);

// Extract statement name and FROM host variable from PREPARE
// e.g. "PREPARE S1 FROM :sqlStr" → name="S1", from_var="SQLSTR"
void parsePrepare(const std::string& sql, std::string& name, std::string& from_var);

// Extract statement name and USING variables from EXECUTE
// e.g. "EXECUTE S1 USING :v1, :v2" → name="S1", using_vars={"V1","V2"}
void parseExecute(const std::string& sql, std::string& name, std::vector<std::string>& using_vars);

// Extract host variable from EXECUTE IMMEDIATE
// e.g. "EXECUTE IMMEDIATE :sqlStr" → "SQLSTR"
std::string parseExecuteImmediate(const std::string& sql);

// Parse GET DIAGNOSTICS assignments
// e.g. "GET DIAGNOSTICS :rc = ROW_COUNT" → {{"RC", "ROW_COUNT"}}
struct DiagItem { std::string var; std::string item; };
std::vector<DiagItem> parseGetDiagnostics(const std::string& sql);

// Extract procedure name and parameters from CALL
// e.g. "CALL myproc(:p1, :p2)" → name="myproc", params={"P1","P2"}
void parseCall(const std::string& sql, std::string& proc_name, std::vector<std::string>& params);

// Parse CONNECT statement
// Variants: "CONNECT TO :dsn USER :u USING :p", "CONNECT TO :dsn", "CONNECT RESET"
struct ConnectInfo {
    std::string server;   // host var or literal
    std::string user;     // host var (empty if not specified)
    std::string password; // host var (empty if not specified)
    bool is_reset = false;
};
ConnectInfo parseConnect(const std::string& sql);

// Parse SET CONNECTION statement
// e.g. "SET CONNECTION :name" or "SET CONNECTION name"
std::string parseSetConnection(const std::string& sql);

// Check if a FETCH has "FOR :n ROWS" clause and extract the row count variable
// e.g. "FETCH C1 FOR :nRows ROWS INTO :a, :b" → rows_var="NROWS", returns true
bool parseFetchForRows(const std::string& sql, std::string& rows_var);

// Check if an INSERT has "FOR :n ROWS" clause and extract the row count variable
// e.g. "INSERT INTO tbl VALUES(:a, :b) FOR :nRows ROWS" → rows_var="NROWS", returns true
// Also strips the "FOR :n ROWS" from the SQL
bool parseInsertForRows(const std::string& sql, std::string& rows_var, std::string& stripped_sql);

// Extract host variables with optional indicator variables from general SQL
// (for INSERT/UPDATE/DELETE parameter binding)
std::vector<HostVarWithInd> extractHostVarsWithInd(const std::string& sql);

// Extract SELECT INTO variables with optional indicators; also strips the INTO clause
std::vector<HostVarWithInd> extractSelectIntoWithInd(const std::string& sql, std::string& stripped);

// Extract FETCH INTO variables with optional indicators
std::vector<HostVarWithInd> extractFetchIntoWithInd(const std::string& sql);

} // namespace rpg

#endif // SQL_UTILS_H
