#ifndef AST_H
#define AST_H

#include <memory>
#include <string>
#include <vector>

namespace rpg {

class ASTVisitor;

class ASTNode {
public:
    int line = 0; // source line number
    virtual ~ASTNode() = default;
    virtual void accept(ASTVisitor& visitor) = 0;
};

class Expression : public ASTNode {
public:
    virtual ~Expression() = default;
};

class Statement : public ASTNode {
public:
    virtual ~Statement() = default;
};

// --- Expressions ---

class Identifier : public Expression {
public:
    std::string name;
    explicit Identifier(std::string name);
    void accept(ASTVisitor& visitor) override;
};

class IntLiteral : public Expression {
public:
    int value;
    explicit IntLiteral(int value);
    void accept(ASTVisitor& visitor) override;
};

class FloatLiteral : public Expression {
public:
    double value;
    explicit FloatLiteral(double value);
    void accept(ASTVisitor& visitor) override;
};

class StringLiteral : public Expression {
public:
    std::string value;
    explicit StringLiteral(std::string value);
    void accept(ASTVisitor& visitor) override;
};

enum class BinOp {
    ADD, SUB, MUL, DIV, POWER,
    EQ, NE, LT, GT, LE, GE,
    AND, OR
};

class BinaryExpr : public Expression {
public:
    BinOp op;
    std::unique_ptr<Expression> left;
    std::unique_ptr<Expression> right;
    BinaryExpr(BinOp op, std::unique_ptr<Expression> left, std::unique_ptr<Expression> right);
    void accept(ASTVisitor& visitor) override;
};

class NotExpr : public Expression {
public:
    std::unique_ptr<Expression> operand;
    explicit NotExpr(std::unique_ptr<Expression> operand);
    void accept(ASTVisitor& visitor) override;
};

class BIFCall : public Expression {
public:
    std::string name;
    std::vector<std::unique_ptr<Expression>> args;
    BIFCall(std::string name, std::vector<std::unique_ptr<Expression>> args);
    void accept(ASTVisitor& visitor) override;
};

// Function call expression (user-defined procedures)
class FuncCall : public Expression {
public:
    std::string name;
    std::vector<std::unique_ptr<Expression>> args;
    FuncCall(std::string name, std::vector<std::unique_ptr<Expression>> args);
    void accept(ASTVisitor& visitor) override;
};

// --- Statements ---

enum class RPGType {
    CHAR,
    VARCHAR,
    INT10,
    PACKED,
    ZONED,
    IND,       // indicator type (boolean)
    DATE,      // date type
    TIME,      // time type
    TIMESTAMP, // timestamp type
    POINTER,   // pointer type
    UNS,       // unsigned integer
    FLOAT4,    // IEEE float (4 bytes)
    FLOAT8,    // IEEE double (8 bytes)
    BINDEC,    // binary decimal (legacy)
    UCS2,      // Unicode UCS-2
    OBJECT     // Java object reference (stub)
};

// File declaration (DCL-F)
class DclF : public Statement {
public:
    std::string name;
    std::string usage;    // DISK, PRINTER, WORKSTN
    bool keyed = false;
    std::string extdesc;  // EXTDESC('tablename') override
    std::string usages;   // *INPUT, *OUTPUT, *UPDATE, etc.
    bool usropn = false;
    std::string prefix;   // PREFIX(pfx) — prepended to field variable names
    DclF(std::string name, std::string usage);
    void accept(ASTVisitor& visitor) override;
};

// --- File I/O opcodes ---

class ChainStmt : public Statement {
public:
    std::vector<std::unique_ptr<Expression>> keys;
    std::string filename;
    std::string extender;
    ChainStmt(std::vector<std::unique_ptr<Expression>> keys,
              std::string filename, std::string extender);
    void accept(ASTVisitor& visitor) override;
};

class ReadStmt : public Statement {
public:
    std::string filename;
    std::string extender;
    ReadStmt(std::string filename, std::string extender);
    void accept(ASTVisitor& visitor) override;
};

// READC recordname; — subfile-only: pops the next operator-modified
// subfile row (ascending relative record number) into recordname's own
// buffer. %EOF(recordname) reports when there are none left.
class ReadcStmt : public Statement {
public:
    std::string recordname;
    explicit ReadcStmt(std::string recordname);
    void accept(ASTVisitor& visitor) override;
};

class ReadeStmt : public Statement {
public:
    std::vector<std::unique_ptr<Expression>> keys;
    std::string filename;
    std::string extender;
    ReadeStmt(std::vector<std::unique_ptr<Expression>> keys,
              std::string filename, std::string extender);
    void accept(ASTVisitor& visitor) override;
};

class ReadpStmt : public Statement {
public:
    std::string filename;
    std::string extender;
    ReadpStmt(std::string filename, std::string extender);
    void accept(ASTVisitor& visitor) override;
};

class ReadpeStmt : public Statement {
public:
    std::vector<std::unique_ptr<Expression>> keys;
    std::string filename;
    std::string extender;
    ReadpeStmt(std::vector<std::unique_ptr<Expression>> keys,
               std::string filename, std::string extender);
    void accept(ASTVisitor& visitor) override;
};

class WriteStmt : public Statement {
public:
    std::string filename;
    std::string extender;
    WriteStmt(std::string filename, std::string extender);
    void accept(ASTVisitor& visitor) override;
};

class UpdateStmt : public Statement {
public:
    std::string filename;
    std::string extender;
    UpdateStmt(std::string filename, std::string extender);
    void accept(ASTVisitor& visitor) override;
};

class DeleteStmt : public Statement {
public:
    std::string filename;
    std::string extender;
    DeleteStmt(std::string filename, std::string extender);
    void accept(ASTVisitor& visitor) override;
};

class SetllStmt : public Statement {
public:
    std::vector<std::unique_ptr<Expression>> keys;
    std::string filename;
    SetllStmt(std::vector<std::unique_ptr<Expression>> keys, std::string filename);
    void accept(ASTVisitor& visitor) override;
};

class SetgtStmt : public Statement {
public:
    std::vector<std::unique_ptr<Expression>> keys;
    std::string filename;
    SetgtStmt(std::vector<std::unique_ptr<Expression>> keys, std::string filename);
    void accept(ASTVisitor& visitor) override;
};

// EXFMT — write record format to display file then wait for user input
class ExfmtStmt : public Statement {
public:
    std::string filename;  // DCL-F file name
    std::string format;    // record format name
    std::string extender;  // E = error handling
    ExfmtStmt(std::string filename, std::string format, std::string extender = "");
    void accept(ASTVisitor& visitor) override;
};

// Named constant (DCL-C)
class DclC : public Statement {
public:
    std::string name;
    std::unique_ptr<Expression> value;
    DclC(std::string name, std::unique_ptr<Expression> value);
    void accept(ASTVisitor& visitor) override;
};

class DclS : public Statement {
public:
    std::string name;
    RPGType type;
    int length;
    int digits;
    int decimals;
    bool is_const;
    bool is_static = false;   // STATIC keyword
    bool is_template = false; // TEMPLATE keyword
    bool is_export = false;   // EXPORT keyword
    bool is_import = false;   // IMPORT keyword
    std::string based_ptr;    // BASED(ptrname)
    int dim;  // DIM(n), 0 = not an array
    int dim_type = 0;  // 0=fixed, 1=*VAR, 2=*AUTO
    std::string like_var; // LIKE(varname)
    int sort_order = 0;  // 0=none, 1=ASCEND, -1=DESCEND
    std::string datfmt;  // per-field DATFMT
    std::string timfmt;  // per-field TIMFMT
    std::string nullind; // NULLIND(field)
    std::string java_class; // OBJECT(*JAVA:'class')
    std::string dtaara_name; // DTAARA(*LDA), DTAARA(MYDA), etc.
    std::unique_ptr<Expression> inz_value;
    DclS(std::string name, RPGType type, int length, int digits = 0, int decimals = 0,
         bool is_const = false, std::unique_ptr<Expression> inz_value = nullptr, int dim = 0);
    void accept(ASTVisitor& visitor) override;
};

class EvalStmt : public Statement {
public:
    std::unique_ptr<Expression> target;
    std::unique_ptr<Expression> value;
    std::string extenders; // e.g. "H", "MR", "E"
    EvalStmt(std::unique_ptr<Expression> target, std::unique_ptr<Expression> value);
    void accept(ASTVisitor& visitor) override;
};

class DsplyStmt : public Statement {
public:
    std::unique_ptr<Expression> expr;
    explicit DsplyStmt(std::unique_ptr<Expression> expr);
    void accept(ASTVisitor& visitor) override;
};

class ReturnStmt : public Statement {
public:
    int code;                              // used for *INLR = *ON (code=0)
    std::unique_ptr<Expression> expr;      // used for RETURN expr;
    bool has_expr;
    explicit ReturnStmt(int code);
    explicit ReturnStmt(std::unique_ptr<Expression> expr);
    void accept(ASTVisitor& visitor) override;
};

// --- Control Flow ---

struct ElseIfBranch {
    std::unique_ptr<Expression> condition;
    std::vector<std::unique_ptr<Statement>> body;
};

class IfStmt : public Statement {
public:
    std::unique_ptr<Expression> condition;
    std::vector<std::unique_ptr<Statement>> then_body;
    std::vector<ElseIfBranch> elseif_branches;
    std::vector<std::unique_ptr<Statement>> else_body;
    IfStmt(std::unique_ptr<Expression> condition);
    void accept(ASTVisitor& visitor) override;
};

class DowStmt : public Statement {
public:
    std::unique_ptr<Expression> condition;
    std::vector<std::unique_ptr<Statement>> body;
    DowStmt(std::unique_ptr<Expression> condition);
    void accept(ASTVisitor& visitor) override;
};

class DouStmt : public Statement {
public:
    std::unique_ptr<Expression> condition;
    std::vector<std::unique_ptr<Statement>> body;
    DouStmt(std::unique_ptr<Expression> condition);
    void accept(ASTVisitor& visitor) override;
};

class ForStmt : public Statement {
public:
    std::string var;
    std::unique_ptr<Expression> start;
    std::unique_ptr<Expression> end;
    std::unique_ptr<Expression> by;
    bool downto;
    std::vector<std::unique_ptr<Statement>> body;
    ForStmt(std::string var, std::unique_ptr<Expression> start,
            std::unique_ptr<Expression> end, std::unique_ptr<Expression> by, bool downto);
    void accept(ASTVisitor& visitor) override;
};

struct WhenBranch {
    std::unique_ptr<Expression> condition;
    std::vector<std::unique_ptr<Statement>> body;
};

class SelectStmt : public Statement {
public:
    std::vector<WhenBranch> when_branches;
    std::vector<std::unique_ptr<Statement>> other_body;
    SelectStmt();
    void accept(ASTVisitor& visitor) override;
};

class IterStmt : public Statement {
public:
    void accept(ASTVisitor& visitor) override;
};

class LeaveStmt : public Statement {
public:
    void accept(ASTVisitor& visitor) override;
};

// --- Procedures ---

struct ParamDecl {
    std::string name;
    RPGType type;
    int length;
    int digits;
    int decimals;
    bool by_value;  // VALUE keyword
    std::string likeds; // LIKEDS(dsname)
    bool nopass = false;  // OPTIONS(*NOPASS)
    bool omit = false;    // OPTIONS(*OMIT)
    bool varsize = false; // OPTIONS(*VARSIZE)
    bool string_opt = false; // OPTIONS(*STRING)
    bool trim_opt = false;   // OPTIONS(*TRIM)
};

// Procedure interface (DCL-PI)
struct ProcInterface {
    RPGType return_type;
    int return_length;
    int return_digits;
    int return_decimals;
    bool has_return;
    std::vector<ParamDecl> params;
};

// Prototype (DCL-PR) - forward declaration
class DclPR : public Statement {
public:
    std::string name;
    ProcInterface interface;
    std::string extpgm;   // EXTPGM('name') — external program
    std::string extproc;  // EXTPROC('name') — external procedure
    bool rtnparm = false; // RTNPARM keyword
    bool opdesc = false;  // OPDESC keyword
    std::vector<std::string> overload_impls; // OVERLOAD(impl1 : impl2 : ...)
    DclPR(std::string name, ProcInterface iface);
    void accept(ASTVisitor& visitor) override;
};

// Procedure (DCL-PROC / END-PROC)
class DclProc : public Statement {
public:
    std::string name;
    ProcInterface interface;
    bool is_export = false; // EXPORT keyword
    std::vector<std::unique_ptr<Statement>> body;
    std::vector<std::unique_ptr<Statement>> on_exit_body;
    DclProc(std::string name, ProcInterface iface);
    void accept(ASTVisitor& visitor) override;
};

// Expression statement (function call as statement)
class ExprStmt : public Statement {
public:
    std::unique_ptr<Expression> expr;
    explicit ExprStmt(std::unique_ptr<Expression> expr);
    void accept(ASTVisitor& visitor) override;
};

// --- Phase 8: Monitor, Subroutines, Indicators ---

class MonitorStmt : public Statement {
public:
    std::vector<std::unique_ptr<Statement>> try_body;
    std::vector<std::unique_ptr<Statement>> on_error_body;
    MonitorStmt();
    void accept(ASTVisitor& visitor) override;
};

class BegSR : public Statement {
public:
    std::string name;
    std::vector<std::unique_ptr<Statement>> body;
    BegSR(std::string name);
    void accept(ASTVisitor& visitor) override;
};

class ExSR : public Statement {
public:
    std::string name;
    explicit ExSR(std::string name);
    void accept(ASTVisitor& visitor) override;
};

// Indicator access (*INxx)
class IndicatorExpr : public Expression {
public:
    int number; // 1-99
    explicit IndicatorExpr(int number);
    void accept(ASTVisitor& visitor) override;
};

// SORTA statement
class SortAStmt : public Statement {
public:
    std::string array_name;
    explicit SortAStmt(std::string name);
    void accept(ASTVisitor& visitor) override;
};

// RESET and CLEAR statements
class ResetStmt : public Statement {
public:
    std::string var_name;
    explicit ResetStmt(std::string name);
    void accept(ASTVisitor& visitor) override;
};

class ClearStmt : public Statement {
public:
    std::string var_name;
    explicit ClearStmt(std::string name);
    void accept(ASTVisitor& visitor) override;
};

// DUMP statement
class DumpStmt : public Statement {
public:
    bool always_; // true if (A) extender — dump regardless of DEBUG setting
    explicit DumpStmt(bool always_a = false);
    void accept(ASTVisitor& visitor) override;
};

// DEALLOC statement
class DeallocStmt : public Statement {
public:
    std::string var_name;
    explicit DeallocStmt(std::string name);
    void accept(ASTVisitor& visitor) override;
};

// TEST statement (validate date/time)
class TestStmt : public Statement {
public:
    char type; // 'D', 'T', 'Z' for date, time, timestamp
    std::string var_name;
    TestStmt(char type, std::string name);
    void accept(ASTVisitor& visitor) override;
};

// EVALR statement (right-adjust)
class EvalRStmt : public Statement {
public:
    std::unique_ptr<Expression> target;
    std::unique_ptr<Expression> value;
    std::string extenders; // e.g. "H", "E"
    EvalRStmt(std::unique_ptr<Expression> target, std::unique_ptr<Expression> value);
    void accept(ASTVisitor& visitor) override;
};

// LEAVESR statement
class LeaveSRStmt : public Statement {
public:
    void accept(ASTVisitor& visitor) override;
};

// EVAL-CORR statement
class EvalCorrStmt : public Statement {
public:
    std::string target;
    std::string source;
    EvalCorrStmt(std::string target, std::string source);
    void accept(ASTVisitor& visitor) override;
};

// XML-INTO statement
class XmlIntoStmt : public Statement {
public:
    std::string target;                          // target DS variable
    std::unique_ptr<Expression> xml_source;      // XML string expression
    std::unique_ptr<Expression> options;          // options string (e.g., 'case=any')
    XmlIntoStmt(std::string target, std::unique_ptr<Expression> xml_source,
                std::unique_ptr<Expression> options);
    void accept(ASTVisitor& visitor) override;
};

// SND-MSG statement
class SndMsgStmt : public Statement {
public:
    std::string msg_type;                   // "INFO", "DIAG", or "ESCAPE"
    std::unique_ptr<Expression> message;
    SndMsgStmt(std::string msg_type, std::unique_ptr<Expression> message);
    void accept(ASTVisitor& visitor) override;
};

// DATA-INTO statement — parse data (JSON etc.) into a DS
class DataIntoStmt : public Statement {
public:
    std::string target;                          // target DS variable
    std::unique_ptr<Expression> data_source;     // source expression (%DATA first arg)
    std::unique_ptr<Expression> options;         // options string (%DATA second arg, optional)
    std::unique_ptr<Expression> parser;          // %PARSER arg (optional, stubbed)
    DataIntoStmt(std::string target, std::unique_ptr<Expression> data_source,
                 std::unique_ptr<Expression> options, std::unique_ptr<Expression> parser);
    void accept(ASTVisitor& visitor) override;
};

// DATA-GEN statement — generate data (JSON etc.) from a DS into a string variable
class DataGenStmt : public Statement {
public:
    std::string source_ds;                       // source DS variable
    std::unique_ptr<Expression> output_var;      // output variable expression (%DATA first arg)
    std::unique_ptr<Expression> options;         // options string (%DATA second arg, optional)
    std::unique_ptr<Expression> parser;          // %PARSER arg (optional, stubbed)
    DataGenStmt(std::string source_ds, std::unique_ptr<Expression> output_var,
                std::unique_ptr<Expression> options, std::unique_ptr<Expression> parser);
    void accept(ASTVisitor& visitor) override;
};

// --- Data Area Statements ---

class DataInStmt : public Statement {
public:
    std::string var_name;
    explicit DataInStmt(std::string v);
    void accept(ASTVisitor& visitor) override;
};

class DataOutStmt : public Statement {
public:
    std::string var_name;
    explicit DataOutStmt(std::string v);
    void accept(ASTVisitor& visitor) override;
};

class DataUnlockStmt : public Statement {
public:
    std::string var_name;
    explicit DataUnlockStmt(std::string v);
    void accept(ASTVisitor& visitor) override;
};

class CallpStmt : public Statement {
public:
    std::unique_ptr<Expression> expr;
    std::string extenders; // e.g. "E"
    CallpStmt(std::unique_ptr<Expression> expr, std::string extenders);
    void accept(ASTVisitor& visitor) override;
};

// --- Data Structures ---

struct DSField {
    std::string name;
    RPGType type;
    int length;
    int digits;
    int decimals;
    std::string overlay_field;
    int overlay_pos = 0;
    int pos = 0;
    std::string likeds;  // LIKEDS subfield — nested DS type name
};

class DclDS : public Statement {
public:
    std::string name;
    bool qualified;
    int dim;  // DIM(n), 0 = not an array
    int dim_type = 0;  // 0=fixed, 1=*VAR, 2=*AUTO
    std::string like_ds; // LIKEDS(name)
    std::string extname; // EXTNAME(filename)
    std::string prefix;  // PREFIX(pfx)
    int prefix_nbr = 0;
    int occurs = 0;      // OCCURS(n), 0 = not multi-occurrence
    bool is_psds = false; // PSDS or SDS keyword
    std::vector<DSField> fields;
    DclDS(std::string name);
    void accept(ASTVisitor& visitor) override;
};

// Dot-qualified access: ds.field
class DotExpr : public Expression {
public:
    std::unique_ptr<Expression> object;
    std::string field;
    DotExpr(std::unique_ptr<Expression> object, std::string field);
    void accept(ASTVisitor& visitor) override;
};

// Array index access: arr(i)
class ArrayAccess : public Expression {
public:
    std::string name;
    std::unique_ptr<Expression> index;
    ArrayAccess(std::string name, std::unique_ptr<Expression> index);
    void accept(ASTVisitor& visitor) override;
};

// FOR-EACH statement
class ForEachStmt : public Statement {
public:
    std::string var;
    std::unique_ptr<Expression> collection;
    std::vector<std::unique_ptr<Statement>> body;
    ForEachStmt(std::string var, std::unique_ptr<Expression> collection);
    void accept(ASTVisitor& visitor) override;
};

// IN operator expression (x IN %LIST(...) or x IN %RANGE(...))
class InExpr : public Expression {
public:
    std::unique_ptr<Expression> value;
    std::unique_ptr<Expression> collection;
    InExpr(std::unique_ptr<Expression> value, std::unique_ptr<Expression> collection);
    void accept(ASTVisitor& visitor) override;
};

// --- Embedded SQL ---

enum class SqlStmtKind {
    SELECT_INTO,
    INSERT,
    UPDATE,
    DELETE_SQL,
    COMMIT,
    ROLLBACK,
    DECLARE_CURSOR,
    OPEN_CURSOR,
    FETCH,
    CLOSE_CURSOR,
    CONNECT,
    DISCONNECT,
    SET_CONNECTION,
    PREPARE,
    EXECUTE,
    EXECUTE_IMMEDIATE,
    GET_DIAGNOSTICS,
    CALL,
    SET,
    OTHER
};

class ExecSqlStmt : public Statement {
public:
    std::string sql_text;      // raw SQL text (after "EXEC SQL")
    SqlStmtKind kind;
    ExecSqlStmt(std::string sql_text, SqlStmtKind kind);
    void accept(ASTVisitor& visitor) override;
};

// --- Program ---

class Program : public ASTNode {
public:
    bool nomain = false;
    bool uses_user_const = false; // program references *USER
    std::string main_proc;
    std::string datfmt;
    std::string timfmt;
    std::vector<std::unique_ptr<Statement>> statements;
    void accept(ASTVisitor& visitor) override;
};

// DCL-ENUM / END-ENUM
struct EnumConstant {
    std::string name;
    std::unique_ptr<Expression> value; // optional explicit value
};

class DclEnum : public Statement {
public:
    std::string name;
    bool qualified = false;
    std::vector<EnumConstant> constants;
    DclEnum(std::string name) : name(std::move(name)) {}
    void accept(ASTVisitor& visitor) override;
};

// --- Visitor ---

class ASTVisitor {
public:
    virtual ~ASTVisitor() = default;
    virtual void visit(Identifier& node) = 0;
    virtual void visit(IntLiteral& node) = 0;
    virtual void visit(FloatLiteral& node) = 0;
    virtual void visit(StringLiteral& node) = 0;
    virtual void visit(BinaryExpr& node) = 0;
    virtual void visit(NotExpr& node) = 0;
    virtual void visit(BIFCall& node) = 0;
    virtual void visit(FuncCall& node) = 0;
    virtual void visit(DclF& node) = 0;
    virtual void visit(DclC& node) = 0;
    virtual void visit(DclS& node) = 0;
    virtual void visit(EvalStmt& node) = 0;
    virtual void visit(DsplyStmt& node) = 0;
    virtual void visit(ReturnStmt& node) = 0;
    virtual void visit(IfStmt& node) = 0;
    virtual void visit(DowStmt& node) = 0;
    virtual void visit(DouStmt& node) = 0;
    virtual void visit(ForStmt& node) = 0;
    virtual void visit(SelectStmt& node) = 0;
    virtual void visit(IterStmt& node) = 0;
    virtual void visit(LeaveStmt& node) = 0;
    virtual void visit(DclPR& node) = 0;
    virtual void visit(DclProc& node) = 0;
    virtual void visit(ExprStmt& node) = 0;
    virtual void visit(DclDS& node) = 0;
    virtual void visit(DotExpr& node) = 0;
    virtual void visit(ArrayAccess& node) = 0;
    virtual void visit(MonitorStmt& node) = 0;
    virtual void visit(BegSR& node) = 0;
    virtual void visit(ExSR& node) = 0;
    virtual void visit(SortAStmt& node) = 0;
    virtual void visit(ResetStmt& node) = 0;
    virtual void visit(ClearStmt& node) = 0;
    virtual void visit(DumpStmt& node) = 0;
    virtual void visit(IndicatorExpr& node) = 0;
    virtual void visit(EvalCorrStmt& node) = 0;
    virtual void visit(EvalRStmt& node) = 0;
    virtual void visit(LeaveSRStmt& node) = 0;
    virtual void visit(DeallocStmt& node) = 0;
    virtual void visit(TestStmt& node) = 0;
    virtual void visit(ForEachStmt& node) = 0;
    virtual void visit(InExpr& node) = 0;
    virtual void visit(DclEnum& node) = 0;
    virtual void visit(ExecSqlStmt& node) = 0;
    virtual void visit(SndMsgStmt& node) = 0;
    virtual void visit(XmlIntoStmt& node) = 0;
    virtual void visit(DataIntoStmt& node) = 0;
    virtual void visit(DataGenStmt& node) = 0;
    virtual void visit(DataInStmt& node) = 0;
    virtual void visit(DataOutStmt& node) = 0;
    virtual void visit(DataUnlockStmt& node) = 0;
    virtual void visit(CallpStmt& node) = 0;
    virtual void visit(ChainStmt& node) = 0;
    virtual void visit(ReadStmt& node) = 0;
    virtual void visit(ReadcStmt& node) = 0;
    virtual void visit(ReadeStmt& node) = 0;
    virtual void visit(ReadpStmt& node) = 0;
    virtual void visit(ReadpeStmt& node) = 0;
    virtual void visit(WriteStmt& node) = 0;
    virtual void visit(UpdateStmt& node) = 0;
    virtual void visit(DeleteStmt& node) = 0;
    virtual void visit(SetllStmt& node) = 0;
    virtual void visit(SetgtStmt& node) = 0;
    virtual void visit(ExfmtStmt& node) = 0;
    virtual void visit(Program& node) = 0;
};

} // namespace rpg

#endif // AST_H
