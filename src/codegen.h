#ifndef CODEGEN_H
#define CODEGEN_H

#include "ast.h"
#include "extdesc.h"
#include "sql_utils.h"
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

namespace rpg {

// DSPF field descriptor (loaded from .dspfd at compile time)
struct DspfFldInfo {
    std::string name;
    std::string alias; // ALIAS(name) keyword — RPG-visible variable name,
                        // if different from the DDS field name itself
    std::string dftval; // DFTVAL('text') keyword — the flat RPG variable's
                         // initial value (quotes already stripped)
    char  dtype = 'A'; // A=char, S=zoned, P=packed, B=binary, F=float
    int   len   = 1;
    int   dec   = 0;
    char  io    = 'O'; // I=input, O=output, B=both, H=hidden
    // RPG-visible variable name: the alias if the field has one, else its
    // own DDS name. The generated _buf struct member is always the DDS
    // name, regardless — only how RPG source refers to the field changes.
    const std::string& rpgName() const { return alias.empty() ? name : alias; }
};

struct DspfRecInfo {
    std::string name;
    std::vector<DspfFldInfo> fields;
};

struct DspfFileInfo {
    std::string filename;
    std::vector<DspfRecInfo> records;
    // record name → index for fast lookup
    std::map<std::string, size_t> recIdx;
};

class CodeGen : public ASTVisitor {
public:
    std::string generate(Program& program);
    void setDebugMode(bool on, const std::string& src_file) {
        debug_mode_ = on;
        source_file_ = src_file;
    }
    void setExtFileDescs(std::map<std::string, ExternalFileDesc> descs) {
        ext_file_descs_ = std::move(descs);
    }
    void setDspfDescs(std::map<std::string, DspfFileInfo> descs) {
        dspf_descs_ = std::move(descs);
    }
    void setConfDsn(std::string dsn) { conf_dsn_ = std::move(dsn); }

    void visit(Identifier& node) override;
    void visit(IntLiteral& node) override;
    void visit(FloatLiteral& node) override;
    void visit(StringLiteral& node) override;
    void visit(BinaryExpr& node) override;
    void visit(NotExpr& node) override;
    void visit(BIFCall& node) override;
    void visit(FuncCall& node) override;
    void visit(DclF& node) override;
    void visit(IRecordFormat& node) override;
    void visit(ORecordFormat& node) override;
    void visit(DclC& node) override;
    void visit(DclS& node) override;
    void visit(EvalStmt& node) override;
    void visit(DsplyStmt& node) override;
    void visit(ReturnStmt& node) override;
    void visit(IfStmt& node) override;
    void visit(DowStmt& node) override;
    void visit(DouStmt& node) override;
    void visit(ForStmt& node) override;
    void visit(SelectStmt& node) override;
    void visit(IterStmt& node) override;
    void visit(LeaveStmt& node) override;
    void visit(DclPR& node) override;
    void visit(DclProc& node) override;
    void visit(ExprStmt& node) override;
    void visit(DclDS& node) override;
    void visit(DotExpr& node) override;
    void visit(ArrayAccess& node) override;
    void visit(MonitorStmt& node) override;
    void visit(BegSR& node) override;
    void visit(ExSR& node) override;
    void visit(GotoStmt& node) override;
    void visit(TagStmt& node) override;
    void visit(MoveStmt& node) override;
    void visit(CallStmt& node) override;
    void visit(SortAStmt& node) override;
    void visit(ResetStmt& node) override;
    void visit(ClearStmt& node) override;
    void visit(DumpStmt& node) override;
    void visit(IndicatorExpr& node) override;
    void visit(EvalCorrStmt& node) override;
    void visit(EvalRStmt& node) override;
    void visit(LeaveSRStmt& node) override;
    void visit(DeallocStmt& node) override;
    void visit(TestStmt& node) override;
    void visit(ForEachStmt& node) override;
    void visit(InExpr& node) override;
    void visit(DclEnum& node) override;
    void visit(ExecSqlStmt& node) override;
    void visit(SndMsgStmt& node) override;
    void visit(XmlIntoStmt& node) override;
    void visit(DataIntoStmt& node) override;
    void visit(DataGenStmt& node) override;
    void visit(DataInStmt& node) override;
    void visit(DataOutStmt& node) override;
    void visit(DataUnlockStmt& node) override;
    void visit(CallpStmt& node) override;
    void visit(ChainStmt& node) override;
    void visit(ReadStmt& node) override;
    void visit(ReadcStmt& node) override;
    void visit(ReadeStmt& node) override;
    void visit(ReadpStmt& node) override;
    void visit(ReadpeStmt& node) override;
    void visit(WriteStmt& node) override;
    void visit(UpdateStmt& node) override;
    void visit(DeleteStmt& node) override;
    void visit(SetllStmt& node) override;
    void visit(SetgtStmt& node) override;
    void visit(ExfmtStmt& node) override;
    void visit(Program& node) override;

private:
    std::ostringstream out_;
    std::ostringstream expr_;
    int indent_ = 1;
    bool in_procedure_ = false;
    bool uses_indicators_ = false;
    int current_proc_parm_count_ = 0;
    bool has_nopass_params_ = false;
    std::string current_proc_name_;
    // True while emitting a function with no return value, so a bare RPG
    // RETURN emits `return;` rather than `return 0;` (which does not
    // compile in a void function). Set for a DCL-PROC with no return type
    // and for the *ENTRY PLIST entry point.
    bool void_return_ = false;
    // *ENTRY PLIST parameter names. These are declared by ordinary D-specs
    // *and* are the entry function's C++ parameters, so their local
    // declarations are suppressed — the parameter is the one storage
    // location the caller's address refers to.
    std::set<std::string> entry_params_;
    std::string datfmt_; // default date format (e.g., "*ISO", "*USA", "*MDY")
    std::string timfmt_; // default time format
    bool debug_mode_ = false; // emit #line directives for source-level debugging
    std::string source_file_; // absolute path to the .rpgle source file

    bool uses_sql_ = false;   // program contains EXEC SQL statements
    bool uses_xml_ = false;   // program contains XML-INTO statements
    bool uses_json_ = false;  // program contains DATA-INTO / DATA-GEN statements (JSON)
    bool uses_csv_ = false;   // program contains DATA-INTO / DATA-GEN with %PARSER('CSV')
    bool uses_psds_ = false;  // program declares a PSDS
    bool uses_rla_  = false;   // program uses file I/O opcodes or DCL-F DISK
    bool uses_dspf_ = false;   // program uses DCL-F WORKSTN
    bool uses_flatfile_ = false; // program uses a program-described (I-spec/O-spec) file

    std::map<std::string, ExternalFileDesc> ext_file_descs_; // from pre-pass
    std::map<std::string, DspfFileInfo>     dspf_descs_;      // from .dspfd pre-pass
    std::map<std::string, DclF*> file_defs_;  // DCL-F nodes by name
    // Program-described I-spec/O-spec layouts, collected in a first pass
    // over Program::statements (fixed_reader.cpp constructs these AST
    // nodes directly — no free-form equivalent exists to bridge through).
    std::map<std::string, std::vector<IRecordFormat*>> flat_input_formats_;
    std::map<std::string, ORecordFormat*> flat_output_formats_;
    std::map<std::string, int> flat_record_len_; // resolved record length, keyed by file name
    std::string conf_dsn_;    // from rpgc.conf, for auto-connect

    void emitIndent();
    void emitLineDirective(int line);
    void emitStatements(std::vector<std::unique_ptr<Statement>>& stmts);
    std::string emitExpr(Expression& expr);
    std::string typeToString(RPGType type, int length = 0);
    int declaredDigits(const std::string& name) const;
    std::string declaredDtFormat(const std::string& name, RPGType type) const;
    std::string paramTypeToString(const ParamDecl& p);
    std::string paramTypeDefault(const ParamDecl& p);
    int countRequiredParams(const std::vector<ParamDecl>& params);
    std::string fieldTypeDefault(RPGType type, int length);
    std::string figConstValue(const std::string& name, RPGType type, const std::string& var_name);

    // XML-INTO codegen helpers
    void emitXmlFieldAssignments(DclDS* ds, const std::string& target, const std::string& xml_src);

    // DATA-INTO / DATA-GEN codegen helpers (JSON)
    void emitJsonFieldAssignments(DclDS* ds, const std::string& target, const std::string& json_src);
    void emitJsonFieldGeneration(DclDS* ds, const std::string& source, const std::string& out_var, bool first);

    // DATA-INTO / DATA-GEN codegen helpers (CSV)
    void emitCsvFieldAssignments(DclDS* ds, const std::string& target,
                                  const std::string& csv_doc, const std::string& row_idx);
    void emitCsvFieldGeneration(DclDS* ds, const std::string& source, const std::string& out_var);

    // SQL codegen helpers
    void emitSqlBindParam(const std::string& var, int index, const std::string& handle = "__hstmt");
    void emitSqlBindParamWithInd(const std::string& var, const std::string& ind_var, int index, const std::string& handle = "__hstmt");
    void emitSqlBindCol(const std::string& var, int index, const std::string& handle = "__hstmt");
    // Expand DS host variables into qualified field names (e.g., :row → ROW.ID, ROW.NAME, ...)
    std::vector<std::string> expandSqlIntoVars(const std::vector<std::string>& vars);
    std::vector<HostVarWithInd> expandSqlIntoVarsWithInd(const std::vector<HostVarWithInd>& vars);
    static std::string escapeSqlForCpp(const std::string& sql);
    static std::string sqlCommentText(const std::string& sql);

    // RLA codegen helpers
    void emitRlaFileOpen(const std::string& fname, const ExternalFileDesc& desc, bool keyed);
    std::string rlaFieldVar(const std::string& fname, const std::string& fieldName) const;
    std::string rlaKeyColName(const std::string& fname) const;
    std::string rlaColumnList(const ExternalFileDesc& desc) const;
    std::string rlaParamList(const ExternalFileDesc& desc, size_t count) const;
    void emitRlaFetchBind(const std::string& fname, const ExternalFileDesc& desc,
                          const std::string& stmtVar);
    void emitRlaCopyBack(const std::string& fname, const ExternalFileDesc& desc,
                         const std::string& stmtVar, const std::string& rcVar);

    // Track DS definitions for LIKEDS resolution
    std::map<std::string, DclDS*> ds_defs_;

    // Track variable types and whether they have INZ for RESET/CLEAR
    std::map<std::string, RPGType> var_types_;
    std::map<std::string, int> var_lengths_; // for CHAR length
    std::map<std::string, int> var_digits_;   // for PACKED/ZONED digit count
    std::map<std::string, int> var_decimals_; // for PACKED/ZONED decimal places (scale)

    // Decimal positions declared for whatever `expr` names, or -1 when the
    // expression is not a plain reference to a declared field (an arbitrary
    // arithmetic expression has no declaration to consult).
    int operandDecimals(const rpg::Expression* expr) const;

    // DS name -> the subfields of it that are OVERLAY views rather than
    // storage. A view is reached through a member function, so `ds.field`
    // has to be emitted as `ds.field()`; this is what tells DotExpr which
    // ones those are.
    std::map<std::string, std::set<std::string>> overlay_subfields_;
    std::map<std::string, std::string> var_datfmt_; // per-field DATFMT (DATE fields)
    std::map<std::string, std::string> var_timfmt_; // per-field TIMFMT (TIME fields)
    std::set<std::string> has_inz_; // variables with INZ values
    std::set<std::string> array_vars_; // DIM array variables
    std::set<std::string> nopass_procs_; // procs with *NOPASS params
    std::map<std::string, std::vector<ParamDecl>> nopass_proc_params_; // full param info
    std::map<std::string, std::string> extproc_map_; // RPG name → C++ name (EXTPROC/EXTPGM)
    std::map<std::string, ProcInterface> proc_sigs_; // all proc/prototype signatures (for OVERLOAD)
    std::map<std::string, std::string> dtaara_vars_; // varname → data area name
    std::map<std::string, std::vector<std::string>> cursor_host_vars_; // cursor name → host vars for binding at OPEN
};

} // namespace rpg

#endif // CODEGEN_H
