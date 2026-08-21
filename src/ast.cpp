#include "ast.h"

namespace rpg {

Identifier::Identifier(std::string name) : name(std::move(name)) {}
void Identifier::accept(ASTVisitor& visitor) { visitor.visit(*this); }

IntLiteral::IntLiteral(int value) : value(value) {}
void IntLiteral::accept(ASTVisitor& visitor) { visitor.visit(*this); }

FloatLiteral::FloatLiteral(double value) : value(value) {}
void FloatLiteral::accept(ASTVisitor& visitor) { visitor.visit(*this); }

StringLiteral::StringLiteral(std::string value) : value(std::move(value)) {}
void StringLiteral::accept(ASTVisitor& visitor) { visitor.visit(*this); }

BinaryExpr::BinaryExpr(BinOp op, std::unique_ptr<Expression> left, std::unique_ptr<Expression> right)
    : op(op), left(std::move(left)), right(std::move(right)) {}
void BinaryExpr::accept(ASTVisitor& visitor) { visitor.visit(*this); }

NotExpr::NotExpr(std::unique_ptr<Expression> operand) : operand(std::move(operand)) {}
void NotExpr::accept(ASTVisitor& visitor) { visitor.visit(*this); }

BIFCall::BIFCall(std::string name, std::vector<std::unique_ptr<Expression>> args)
    : name(std::move(name)), args(std::move(args)) {}
void BIFCall::accept(ASTVisitor& visitor) { visitor.visit(*this); }

FuncCall::FuncCall(std::string name, std::vector<std::unique_ptr<Expression>> args)
    : name(std::move(name)), args(std::move(args)) {}
void FuncCall::accept(ASTVisitor& visitor) { visitor.visit(*this); }

DclF::DclF(std::string name, std::string usage)
    : name(std::move(name)), usage(std::move(usage)) {}
void DclF::accept(ASTVisitor& visitor) { visitor.visit(*this); }

IRecordFormat::IRecordFormat(std::string fileName) : fileName(std::move(fileName)) {}
void IRecordFormat::accept(ASTVisitor& visitor) { visitor.visit(*this); }

ORecordFormat::ORecordFormat(std::string fileName) : fileName(std::move(fileName)) {}
void ORecordFormat::accept(ASTVisitor& visitor) { visitor.visit(*this); }

DclC::DclC(std::string name, std::unique_ptr<Expression> value)
    : name(std::move(name)), value(std::move(value)) {}
void DclC::accept(ASTVisitor& visitor) { visitor.visit(*this); }

DclS::DclS(std::string name, RPGType type, int length, int digits, int decimals,
           bool is_const, std::unique_ptr<Expression> inz_value, int dim)
    : name(std::move(name)), type(type), length(length), digits(digits), decimals(decimals),
      is_const(is_const), dim(dim), inz_value(std::move(inz_value)) {}
void DclS::accept(ASTVisitor& visitor) { visitor.visit(*this); }

EvalStmt::EvalStmt(std::unique_ptr<Expression> target, std::unique_ptr<Expression> value)
    : target(std::move(target)), value(std::move(value)) {}
void EvalStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

DsplyStmt::DsplyStmt(std::unique_ptr<Expression> expr) : expr(std::move(expr)) {}
void DsplyStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

ReturnStmt::ReturnStmt(int code) : code(code), has_expr(false) {}
ReturnStmt::ReturnStmt(std::unique_ptr<Expression> expr)
    : code(0), expr(std::move(expr)), has_expr(true) {}
void ReturnStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

IfStmt::IfStmt(std::unique_ptr<Expression> condition)
    : condition(std::move(condition)) {}
void IfStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

DowStmt::DowStmt(std::unique_ptr<Expression> condition)
    : condition(std::move(condition)) {}
void DowStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

DouStmt::DouStmt(std::unique_ptr<Expression> condition)
    : condition(std::move(condition)) {}
void DouStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

ForStmt::ForStmt(std::string var, std::unique_ptr<Expression> start,
                 std::unique_ptr<Expression> end, std::unique_ptr<Expression> by, bool downto)
    : var(std::move(var)), start(std::move(start)), end(std::move(end)),
      by(std::move(by)), downto(downto) {}
void ForStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

SelectStmt::SelectStmt() {}
void SelectStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

void IterStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }
void LeaveStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

DclPR::DclPR(std::string name, ProcInterface iface)
    : name(std::move(name)), interface(std::move(iface)) {}
void DclPR::accept(ASTVisitor& visitor) { visitor.visit(*this); }

DclProc::DclProc(std::string name, ProcInterface iface)
    : name(std::move(name)), interface(std::move(iface)) {}
void DclProc::accept(ASTVisitor& visitor) { visitor.visit(*this); }

ExprStmt::ExprStmt(std::unique_ptr<Expression> expr) : expr(std::move(expr)) {}
void ExprStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

MonitorStmt::MonitorStmt() {}
void MonitorStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

BegSR::BegSR(std::string name) : name(std::move(name)) {}
void BegSR::accept(ASTVisitor& visitor) { visitor.visit(*this); }

ExSR::ExSR(std::string name) : name(std::move(name)) {}
void ExSR::accept(ASTVisitor& visitor) { visitor.visit(*this); }

GotoStmt::GotoStmt(std::string label) : label(std::move(label)) {}
void GotoStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

TagStmt::TagStmt(std::string label) : label(std::move(label)) {}
void TagStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

SortAStmt::SortAStmt(std::string name) : array_name(std::move(name)) {}
void SortAStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

ResetStmt::ResetStmt(std::string name) : var_name(std::move(name)) {}
void ResetStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

ClearStmt::ClearStmt(std::string name) : var_name(std::move(name)) {}
void ClearStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

DumpStmt::DumpStmt(bool always_a) : always_(always_a) {}
void DumpStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

IndicatorExpr::IndicatorExpr(int number) : number(number) {}
void IndicatorExpr::accept(ASTVisitor& visitor) { visitor.visit(*this); }

DclDS::DclDS(std::string name)
    : name(std::move(name)), qualified(false), dim(0) {}
void DclDS::accept(ASTVisitor& visitor) { visitor.visit(*this); }

DotExpr::DotExpr(std::unique_ptr<Expression> object, std::string field)
    : object(std::move(object)), field(std::move(field)) {}
void DotExpr::accept(ASTVisitor& visitor) { visitor.visit(*this); }

ArrayAccess::ArrayAccess(std::string name, std::unique_ptr<Expression> index)
    : name(std::move(name)), index(std::move(index)) {}
void ArrayAccess::accept(ASTVisitor& visitor) { visitor.visit(*this); }

DeallocStmt::DeallocStmt(std::string name) : var_name(std::move(name)) {}
void DeallocStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

TestStmt::TestStmt(char type, std::string name) : type(type), var_name(std::move(name)) {}
void TestStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

EvalRStmt::EvalRStmt(std::unique_ptr<Expression> target, std::unique_ptr<Expression> value)
    : target(std::move(target)), value(std::move(value)) {}
void EvalRStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

void LeaveSRStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

EvalCorrStmt::EvalCorrStmt(std::string target, std::string source)
    : target(std::move(target)), source(std::move(source)) {}
void EvalCorrStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

ForEachStmt::ForEachStmt(std::string var, std::unique_ptr<Expression> collection)
    : var(std::move(var)), collection(std::move(collection)) {}
void ForEachStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

InExpr::InExpr(std::unique_ptr<Expression> value, std::unique_ptr<Expression> collection)
    : value(std::move(value)), collection(std::move(collection)) {}
void InExpr::accept(ASTVisitor& visitor) { visitor.visit(*this); }

void DclEnum::accept(ASTVisitor& visitor) { visitor.visit(*this); }

ExecSqlStmt::ExecSqlStmt(std::string sql_text, SqlStmtKind kind)
    : sql_text(std::move(sql_text)), kind(kind) {}
void ExecSqlStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

XmlIntoStmt::XmlIntoStmt(std::string target, std::unique_ptr<Expression> xml_source,
                         std::unique_ptr<Expression> options)
    : target(std::move(target)), xml_source(std::move(xml_source)),
      options(std::move(options)) {}
void XmlIntoStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

SndMsgStmt::SndMsgStmt(std::string msg_type, std::unique_ptr<Expression> message)
    : msg_type(std::move(msg_type)), message(std::move(message)) {}
void SndMsgStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

DataIntoStmt::DataIntoStmt(std::string target, std::unique_ptr<Expression> data_source,
                           std::unique_ptr<Expression> options, std::unique_ptr<Expression> parser)
    : target(std::move(target)), data_source(std::move(data_source)),
      options(std::move(options)), parser(std::move(parser)) {}
void DataIntoStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

DataGenStmt::DataGenStmt(std::string source_ds, std::unique_ptr<Expression> output_var,
                         std::unique_ptr<Expression> options, std::unique_ptr<Expression> parser)
    : source_ds(std::move(source_ds)), output_var(std::move(output_var)),
      options(std::move(options)), parser(std::move(parser)) {}
void DataGenStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

DataInStmt::DataInStmt(std::string v) : var_name(std::move(v)) {}
void DataInStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

DataOutStmt::DataOutStmt(std::string v) : var_name(std::move(v)) {}
void DataOutStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

DataUnlockStmt::DataUnlockStmt(std::string v) : var_name(std::move(v)) {}
void DataUnlockStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

CallpStmt::CallpStmt(std::unique_ptr<Expression> e, std::string ext)
    : expr(std::move(e)), extenders(std::move(ext)) {}
void CallpStmt::accept(ASTVisitor& visitor) { visitor.visit(*this); }

void Program::accept(ASTVisitor& visitor) { visitor.visit(*this); }

// --- File I/O opcode constructors ---

ChainStmt::ChainStmt(std::vector<std::unique_ptr<Expression>> k, std::string f, std::string e)
    : keys(std::move(k)), filename(std::move(f)), extender(std::move(e)) {}
void ChainStmt::accept(ASTVisitor& v) { v.visit(*this); }

ReadStmt::ReadStmt(std::string f, std::string e)
    : filename(std::move(f)), extender(std::move(e)) {}
void ReadStmt::accept(ASTVisitor& v) { v.visit(*this); }

ReadcStmt::ReadcStmt(std::string r) : recordname(std::move(r)) {}
void ReadcStmt::accept(ASTVisitor& v) { v.visit(*this); }

ReadeStmt::ReadeStmt(std::vector<std::unique_ptr<Expression>> k, std::string f, std::string e)
    : keys(std::move(k)), filename(std::move(f)), extender(std::move(e)) {}
void ReadeStmt::accept(ASTVisitor& v) { v.visit(*this); }

ReadpStmt::ReadpStmt(std::string f, std::string e)
    : filename(std::move(f)), extender(std::move(e)) {}
void ReadpStmt::accept(ASTVisitor& v) { v.visit(*this); }

ReadpeStmt::ReadpeStmt(std::vector<std::unique_ptr<Expression>> k, std::string f, std::string e)
    : keys(std::move(k)), filename(std::move(f)), extender(std::move(e)) {}
void ReadpeStmt::accept(ASTVisitor& v) { v.visit(*this); }

WriteStmt::WriteStmt(std::string f, std::string e)
    : filename(std::move(f)), extender(std::move(e)) {}
void WriteStmt::accept(ASTVisitor& v) { v.visit(*this); }

UpdateStmt::UpdateStmt(std::string f, std::string e)
    : filename(std::move(f)), extender(std::move(e)) {}
void UpdateStmt::accept(ASTVisitor& v) { v.visit(*this); }

DeleteStmt::DeleteStmt(std::string f, std::string e)
    : filename(std::move(f)), extender(std::move(e)) {}
void DeleteStmt::accept(ASTVisitor& v) { v.visit(*this); }

ExfmtStmt::ExfmtStmt(std::string fname, std::string fmt, std::string ext)
    : filename(std::move(fname)), format(std::move(fmt)), extender(std::move(ext)) {}
void ExfmtStmt::accept(ASTVisitor& v) { v.visit(*this); }

SetllStmt::SetllStmt(std::vector<std::unique_ptr<Expression>> k, std::string f)
    : keys(std::move(k)), filename(std::move(f)) {}
void SetllStmt::accept(ASTVisitor& v) { v.visit(*this); }

SetgtStmt::SetgtStmt(std::vector<std::unique_ptr<Expression>> k, std::string f)
    : keys(std::move(k)), filename(std::move(f)) {}
void SetgtStmt::accept(ASTVisitor& v) { v.visit(*this); }

} // namespace rpg
